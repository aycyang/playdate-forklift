--[[ vim config just for this file

set makeprg=./build_and_run.sh
nnoremap <cr> :make<cr>

--]]

import "CoreLibs/graphics"
import "CoreLibs/object"
import "CoreLibs/sprites"

-- TODO
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

local GRAVITY <const> = 5
local PLAYER_SPEED_X <const> = 2
local PLAYER_SPEED_Y <const> = 2

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
  return math.tointeger(result)
end

function playdate.graphics.sprite:distY(other)
  local aHalfHeight <const> = self.height / 2
  local aLower <const> = self.y - aHalfHeight
  local aUpper <const> = self.y + aHalfHeight
  local bHalfHeight <const> = other.height / 2
  local bLower <const> = other.y - bHalfHeight
  local bUpper <const> = other.y + bHalfHeight
  local result <const> = math.max(aLower - bUpper, bLower - aUpper)
  return math.tointeger(result)
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
  self.carried = {}
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
  local potentiallyConstrainingBodies = {}
  local minY = math.huge
  for i = 1, numCollisions do
    local other <const> = collisions[i].other
    local dist <const> = self:distY(other)
    --warnIfNot(dist >= 0, "dist="..dist.."\ty distance was negative; maybe a body clipped inside another body?")
    local signedDist <const> = sign(goalY) * dist
    local otherGoalDist <const> = goalY - signedDist
    local otherActualDist <const> = other:checkMoveByY(otherGoalDist, recursionDepth + 1)
    local truncY <const> = signedDist + otherActualDist
    if otherGoalDist ~= otherActualDist then
      potentiallyConstrainingBodies[other] = truncY
    end
    if math.abs(truncY) < math.abs(minY) then
      minY = truncY
    end
  end
  if minY < math.huge then
    local constrainingBodies = {}
    for other, truncY in pairs(potentiallyConstrainingBodies) do
      if truncY == minY then
        table.insert(constrainingBodies, other)
      end
    end
    return minY, constrainingBodies
  end
  return goalY, {}
end

function Body:markCarriedY(deltaY)
  local _, _, collisions, numCollisions = self:checkCollisions(self.x, self.y + deltaY)
  for i = 1, numCollisions do
    table.insert(collisions[i].other.carried, self)
  end
end

function Body:tryMoveByY(goalY, verbose, recursionDepth)
  assert(math.type(goalY) == "integer")
  recursionDepth = recursionDepth or 0
  -- Constrain movement based on how far subsequent bodies can be moved.
  local actualY, constrainingBodies = self:checkMoveByY(goalY, recursionDepth)
  for i = 1, #constrainingBodies do
    table.insert(constrainingBodies[i].carried, self)
  end
  local signY = sign(goalY)
  local _, _, collisions, numCollisions = self:checkCollisions(self.x, self.y + actualY)
  for i = 1, numCollisions do
    local other <const> = collisions[i].other
    local dist <const> = self:distY(other)
    --warnIfNot(dist >= 0, "dist="..dist.."\ty distance was negative; maybe a body clipped inside another body?")
    local signedDist <const> = signY * dist
    other:tryMoveByY(actualY - signedDist, verbose, recursionDepth + 1)
  end
  if verbose and actualY ~= goalY then print("goalY="..goalY..", actualY="..actualY) end
  self:moveBy(0, actualY)
  -- Weird exception for the sake of gamefeel: vertically stacked Bodies stick
  -- together when moving down, even if it's faster than gravity. If the
  -- carrying Body is moving up, propagation was already handled in the above
  -- recursive calls, so do nothing here.
  if actualY > 0 then
    for i = 1, #self.carried do
      self.carried[i]:tryMoveByY(actualY, verbose, 0)
    end
  end
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
  assert(math.type(goalX) == "integer")
  recursionDepth = recursionDepth or 0
  -- Constrain movement based on how far subsequent bodies can be moved.
  local signX <const> = sign(goalX)
  local actualX = self:checkMoveByX(goalX, recursionDepth)
  local _, _, collisions, numCollisions = self:checkCollisions(self.x + actualX, self.y)
  for i = 1, numCollisions do
    local other <const> = collisions[i].other
    local dist <const> = self:distX(other)
    warnIfNot(dist >= 0, "x distance was negative; maybe a body clipped inside another body?")
    local signedDist <const> = signX * dist
    other:tryMoveByX(actualX - signedDist, verbose, recursionDepth + 1)
  end
  if verbose and actualX ~= goalX then print("goalX="..goalX..", actualX="..actualX) end
  self:moveBy(actualX, 0)
  -- Move carried Bodies as if by static friction.
  --
  -- To avoid double-moving carried Bodies, sort left-to-right if moving left,
  -- right-to-left if moving right, so the outermost Bodies move first.
  table.sort(self.carried, function(a, b)
    return signX * a.x > signX * b.x
  end)
  for i = 1, #self.carried do
    self.carried[i]:tryMoveByX(actualX, verbose, 0)
  end
end

class("StaticBody").extends(Body)

function StaticBody:init(x, y, w, h)
  StaticBody.super.init(self, x, y, w, h, TAGS.static)
end

function StaticBody:draw(x, y, w, h)
  gfx.fillRect(0, 0, self.width, self.height)
end

class("DynamicBody").extends(Body)

function DynamicBody:init(x, y, w, h)
  DynamicBody.super.init(self, x, y, w, h, TAGS.dynamic)
end

function DynamicBody:draw(x, y, w, h)
  gfx.drawRect(0, 0, self.width, self.height)
end

local fork = StaticBody(100, 180, 50, 20)
local ground = StaticBody(200, 240, playdate.display.getWidth(), 50)
local bodyA = StaticBody(200, 120, 50, 50)
local bodyA = StaticBody(200, 120, 50, 50)
local dynBodies = {
  DynamicBody(100, 100, 40, 40),
  DynamicBody(80, 50, 20, 30),
  DynamicBody(120, 50, 20, 40),
}

function init()
  -- This is a global variable that accumulates crank change and dispenses the
  -- integral portion when it is less than -1 or greater than 1.
  crankChangeAccumulator = 0
end

function playdate.update()
  local deltaTime = playdate.getElapsedTime()
  playdate.resetElapsedTime()

  local dx = 0
  local dy = 0

  -- Handle player y-axis movement.
  if playdate.isCrankDocked() then
    if playdate.buttonIsPressed(playdate.kButtonUp) then
      dy = -PLAYER_SPEED_Y
    end
    if playdate.buttonIsPressed(playdate.kButtonDown) then
      dy = PLAYER_SPEED_Y
    end
  else
    local change, _ = playdate.getCrankChange()
    crankChangeAccumulator += change
    if crankChangeAccumulator <= -1 then
      dy = math.ceil(crankChangeAccumulator)
    end
    if crankChangeAccumulator >= 1 then
      dy = math.floor(crankChangeAccumulator)
    end
    crankChangeAccumulator -= dy
  end
  fork:tryMoveByY(dy)

  -- `carried` is updated by gravity update below.
  -- Reset carried for all sprites, otherwise `carried` grows unbounded.
  gfx.sprite.performOnAllSprites(function(sprite)
    sprite.carried = {}
  end)

  -- Handle dynamic body gravity.
  -- This updates each Body's `carried` attribute, so it must happen before
  -- x-axis movement for static friction to work.
  for i = 1, #dynBodies do
    dynBodies[i]:tryMoveByY(GRAVITY)
  end

  -- Handle player x-axis movement.
  if playdate.buttonIsPressed(playdate.kButtonRight) then
    dx = PLAYER_SPEED_X
  end
  if playdate.buttonIsPressed(playdate.kButtonLeft) then
    dx = -PLAYER_SPEED_X
  end
  fork:tryMoveByX(dx)

  -- draw
  gfx.sprite.update()
end

init()
