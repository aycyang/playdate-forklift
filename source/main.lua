--[[ vim config just for this file

set makeprg=./build_and_run.sh
nnoremap <cr> :make<cr>

--]]

import "CoreLibs/graphics"
import "CoreLibs/object"
import "CoreLibs/sprites"

-- TODO
-- * gravity
-- * static friction
-- * use delta time instead of fixed framerate
-- * turn the forklift

-- ### Collision system rules:
-- * a static body cannot move
-- * a kinematic body moves via external control
-- * a dynamic body can be subjected to forces such as gravity
-- * a dynamic body can be pushed by another dynamic body or a kinematic body
-- * no body may intersect any other body
--
-- * the ground is a static body
-- * the player (the fork of the forklift) is a kinematic body
-- * packages are dynamic bodies (affected by gravity)
--
-- ### Collision system internals:
-- * when a kinematic body is going to collide with a dynamic body, it queries
--   the dynamic body to move first, before attempting to move itself. this may
--   be a recursive query.

local gfx <const> = playdate.graphics

local TAGS <const> = {
  static = 1,
  dynamic = 2,
}

function warnIfNot(cond, msg)
  if not cond then
    error("warning: " .. msg)
  end
end

function sign(n)
  if n < 0 then
    return -1
  elseif n > 0 then
    return 1
  else
    return n
  end
end

function playdate.graphics.sprite:distX(other)
  local aHalfWidth <const> = self.width / 2
  local aLower <const> = self.x - aHalfWidth
  local aUpper <const> = self.x + aHalfWidth
  local bHalfWidth <const> = other.width / 2
  local bLower <const> = other.x - bHalfWidth
  local bUpper <const> = other.x + bHalfWidth
  local result <const> = math.max(aLower - bUpper, bLower - aUpper)
  return result
end

function playdate.graphics.sprite:distY(other)
  local aHalfHeight <const> = self.height / 2
  local aLower <const> = self.y - aHalfHeight
  local aUpper <const> = self.y + aHalfHeight
  local bHalfHeight <const> = other.height / 2
  local bLower <const> = other.y - bHalfHeight
  local bUpper <const> = other.y + bHalfHeight
  local result <const> = math.max(aLower - bUpper, bLower - aUpper)
  return result
end

class("Body").extends(gfx.sprite)

function Body:init(x, y, w, h, tag)
  Body.super.init(self)
  -- Set the collision response to "overlap" so that
  -- gfx.sprite:checkCollisions() returns more than one colliding sprite.
  --
  -- By default, the collisions response is "freeze", which means there can be
  -- at most one colliding sprite, so gfx.sprite:checkCollisions() only returns
  -- the first colliding sprite.
  --
  -- This project uses a custom collision algorithm in lieu of
  -- gfx.sprite:moveWithCollisions(). As such, even though the collision
  -- response is set to "overlap", a Body is not meant to overlap any other.
  --
  -- Source: https://devforum.play.date/t/checkcollisions-only-returns-a-single-collision-even-if-there-should-be-multiple/11505/2
  self.collisionResponse = gfx.sprite.kCollisionTypeOverlap
  self:moveTo(x, y)
  self:setSize(w, h)
  self:setCollideRect(0, 0, w, h)
  self:setTag(tag)
  self:add()
end

-- Without moving, return the maximum distance this body can travel along the
-- y-axis, up to goalY. Returns a value 0 through goalY.
function Body:checkMoveByY(goalY, recursionDepth)
  -- If this is a recursive call on a StaticBody, it should not move.
  if recursionDepth > 0 and self:getTag() == TAGS.static then return 0 end
  -- Recursively call checkMoveBy on any Body that is in the way.
  -- Adjust the return value accordingly.
  local _, _, collisions, numCollisions = self:checkCollisions(self.x, self.y + goalY)
  local minY = math.huge
  for i = 1, numCollisions do
    local other <const> = collisions[i].other
    local dist <const> = self:distY(other)
    warnIfNot(dist >= 0, "x distance was negative; maybe a body clipped inside another body?")
    local signedDist <const> = sign(goalY) * dist
    local truncY <const> = signedDist + other:checkMoveByY(goalY - signedDist, recursionDepth + 1)
    if math.abs(truncY) < math.abs(minY) then
      minY = truncY
    end
  end
  if minY < math.huge then
    return minY
  end
  return goalY
end

function Body:tryMoveByY(goalY, verbose, recursionDepth)
  recursionDepth = recursionDepth or 0
  -- Constrain movement based on how far subsequent bodies can be moved.
  local actualY = self:checkMoveByY(goalY, recursionDepth)
  local _, _, collisions, numCollisions = self:checkCollisions(self.x, self.y + actualY)
  for i = 1, numCollisions do
    local other <const> = collisions[i].other
    local dist <const> = self:distY(other)
    warnIfNot(dist >= 0, "x distance was negative; maybe a body clipped inside another body?")
    local signedDist <const> = sign(goalY) * dist
    other:tryMoveByY(actualY - signedDist, recursionDepth + 1)
  end
  if verbose and actualY ~= goalY then print("goalY="..goalY..", actualY="..actualY) end
  self:moveBy(0, actualY)
end

-- Without moving, return the maximum distance this body can travel along the
-- x-axis, up to goalX. Returns a value 0 through goalX.
function Body:checkMoveByX(goalX, recursionDepth)
  -- If this is a recursive call on a StaticBody, it should not move.
  if recursionDepth > 0 and self:getTag() == TAGS.static then return 0 end
  -- Recursively call checkMoveBy on any Body that is in the way.
  -- Adjust the return value accordingly.
  local _, _, collisions, numCollisions = self:checkCollisions(self.x + goalX, self.y)
  local minX = math.huge
  for i = 1, numCollisions do
    local other <const> = collisions[i].other
    local dist <const> = self:distX(other)
    warnIfNot(dist >= 0, "x distance was negative; maybe a body clipped inside another body?")
    local signedDist <const> = sign(goalX) * dist
    local truncX <const> = signedDist + other:checkMoveByX(goalX - signedDist, recursionDepth + 1)
    if math.abs(truncX) < math.abs(minX) then
      minX = truncX
    end
  end
  if minX ~= math.huge then
    return minX
  end
  return goalX
end

function Body:tryMoveByX(goalX, verbose, recursionDepth)
  recursionDepth = recursionDepth or 0
  -- Constrain movement based on how far subsequent bodies can be moved.
  local actualX = self:checkMoveByX(goalX, recursionDepth)
  local _, _, collisions, numCollisions = self:checkCollisions(self.x + actualX, self.y)
  for i = 1, numCollisions do
    local other <const> = collisions[i].other
    local dist <const> = self:distX(other)
    warnIfNot(dist >= 0, "x distance was negative; maybe a body clipped inside another body?")
    local signedDist <const> = sign(goalX) * dist
    other:tryMoveByX(actualX - signedDist, recursionDepth + 1)
  end
  if verbose and actualX ~= goalX then print("goalX="..goalX..", actualX="..actualX) end
  self:moveBy(actualX, 0)
end

class("StaticBody").extends(Body)

function StaticBody:init(x, y, w, h)
  StaticBody.super.init(self, x, y, w, h, TAGS.static)
end

function StaticBody:draw(x, y, w, h)
  gfx.fillRect(x, y, w, h)
end

class("DynamicBody").extends(Body)

function DynamicBody:init(x, y, w, h)
  DynamicBody.super.init(self, x, y, w, h, TAGS.dynamic)
end

function DynamicBody:draw(x, y, w, h)
  gfx.drawRect(x, y, w, h)
end

local fork = StaticBody(100, 100, 30, 20)
local ground = StaticBody(50, 50, 60, 40)
local bodyA = StaticBody(200, 80, 10, 40)
local bodyB = StaticBody(300, 120, 30, 70)
local bodyC = DynamicBody(280, 50, 50, 50)
local bodyC_copy1 = DynamicBody(320, 30, 20, 20)
local bodyC_copy2 = DynamicBody(330, 70, 20, 20)
local bodyC_copy3 = DynamicBody(350, 35, 20, 20)
local bodyC_copy4 = StaticBody(380, 35, 20, 20)
local bodyD = StaticBody(100, 150, 20, 50)
local bodyE = StaticBody(200, 140, 20, 10)
local bodyF = StaticBody(202, 155, 20, 10)
local bodyG = StaticBody(204, 170, 20, 10)
local bodyH = StaticBody(50, 150, 20, 10)
local bodyI = StaticBody(20, 140, 20, 20)
local bodyJ = DynamicBody(50, 135, 20, 10)
local bodyK = StaticBody(200, 40, 20, 20)
local bodyL = DynamicBody(160, 40, 20, 20)
local bodyM = DynamicBody(130, 40, 20, 20)
local bodyN = DynamicBody(100, 40, 20, 20)
local bodyO = DynamicBody(140, 80, 20, 20)
local bodyP = StaticBody(50, 110, 20, 20)
local bodyQ = DynamicBody(50, 85, 20, 20)
bodyI:tryMoveByX(20)

function init()
end

function playdate.update()
  local deltaTime = playdate.getElapsedTime()
  playdate.resetElapsedTime()

  local dx = 0
  local dy = 0

  -- handle player y-axis movement
  if playdate.isCrankDocked() then
    if playdate.buttonIsPressed(playdate.kButtonUp) then
      dy = -2
    end
    if playdate.buttonIsPressed(playdate.kButtonDown) then
      dy = 2
    end
  else
    local change, _ = playdate.getCrankChange()
    dy = -change
  end
  fork:tryMoveByY(dy)

  -- handle player x-axis movement
  if playdate.buttonIsPressed(playdate.kButtonRight) then
    dx = 2
  end
  if playdate.buttonIsPressed(playdate.kButtonLeft) then
    dx = -2
  end
  fork:tryMoveByX(dx)

  -- kinematic bodies
  bodyA:tryMoveByX(3)
  bodyD:tryMoveByX(7)
  bodyK:tryMoveByX(-2)
  bodyP:tryMoveByY(-2)

  -- draw
  --gfx.clear()
  gfx.sprite.update()
end

init()
