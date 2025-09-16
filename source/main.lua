--[[ vim config just for this file

set makeprg=./build_and_run.sh
nnoremap <cr> :make<cr>

--]]

import "CoreLibs/graphics"
import "CoreLibs/object"
import "CoreLibs/sprites"

-- TODO
-- * conveyor belts
-- * spawn/despawn boxes
-- * label boxes
-- * create game flow
-- * draw the forklift
-- * turn the forklift
--
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

local GROUPS <const> = {
  player = 1,
  pallet = 2,
  package = 3,
  terrain = 4,
}

local GRAVITY <const> = 5
local PLAYER_SPEED_X <const> = 2
local PLAYER_SPEED_Y <const> = 2
local CRANK_SCALE <const> = 8

-- TODO all dimensions must be divisible by 2 right now. It's not clear to me
-- this is necessary, but it makes the distance calculations strictly integral,
-- which makes it easier to reason about the calculations.
local PLAYER_WIDTH <const> = 50
local PLAYER_HEIGHT <const> = 4

local SHELF_WIDTH <const> = 60
local SHELF_HEIGHT <const> = 8

local PKG_WIDTH <const> = 50
local PKG_HEIGHT <const> = 40
local PALLET_WIDTH <const> = 50
local PALLET_HEIGHT <const> = 12

local CONVEYOR_BELT_SEGMENT_WIDTH <const> = 6
local CONVEYOR_BELT_SEGMENT_HEIGHT <const> = 6

function copySetAndPut(t, e)
  local result = {}
  for k in pairs(t) do
    result[k] = true
  end
  result[e] = true
  return result
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
Body.nextId = 0

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
  self.attached = {}
  self.id = Body.nextId
  Body.nextId += 1
  self:add()
end

function Body:attach(other)
  self.attached[other] = true
  other.attached[self] = true
end

-- Without moving, return the maximum distance this body can travel along the
-- y-axis, up to goalY. Returns a value 0 through goalY.
function Body:checkMoveByY(goalY, recursionDepth, checked)
  checked = checked or {}
  -- If this is a recursive call on a StaticBody, it should not move.
  if recursionDepth > 0 and self:getTag() == TAGS.static then return 0 end
  -- Recursively call checkMoveBy on any Body that is in the way.
  -- Adjust the return value accordingly.
  local _, _, collisions, numCollisions = self:checkCollisions(self.x, self.y + goalY)
  local potentiallyConstrainingBodies = {}
  local minY = math.huge
  for i = 1, numCollisions do
    local other <const> = collisions[i].other
    if self.attached[other] then goto continue end
    local dist <const> = self:distY(other)
    assert(dist >= 0, "id="..self.id.."\tdistY="..dist)
    local signedDist <const> = sign(goalY) * dist
    local otherGoalDist <const> = goalY - signedDist
    local otherActualDist <const> = other:checkMoveByY(otherGoalDist, recursionDepth + 1, checked)
    local truncY <const> = signedDist + otherActualDist
    if otherGoalDist ~= otherActualDist then
      potentiallyConstrainingBodies[other] = truncY
    end
    if math.abs(truncY) < math.abs(minY) then
      minY = truncY
    end
    ::continue::
  end
  -- Check attached bodies.
  for other in pairs(self.attached) do
    if checked[other] then goto continue end
    local otherY <const> = other:checkMoveByY(goalY, 0, copySetAndPut(checked, self))
    if math.abs(otherY) < math.abs(minY) then
      minY = otherY
    end
    ::continue::
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

function Body:tryMoveByY(goalY, verbose, recursionDepth, checked)
  assert(math.type(goalY) == "integer")
  checked = checked or {}
  recursionDepth = recursionDepth or 0
  -- Constrain movement based on how far subsequent bodies can be moved.
  local actualY, constrainingBodies = self:checkMoveByY(goalY, recursionDepth, checked)
  for i = 1, #constrainingBodies do
    table.insert(constrainingBodies[i].carried, self)
  end
  local signY = sign(goalY)
  local _, _, collisions, numCollisions = self:checkCollisions(self.x, self.y + actualY)
  for i = 1, numCollisions do
    local other <const> = collisions[i].other
    if self.attached[other] then goto continue end
    local dist <const> = self:distY(other)
    assert(dist >= 0, "id="..self.id.."\tdistY="..dist)
    local signedDist <const> = signY * dist
    other:tryMoveByY(actualY - signedDist, verbose, recursionDepth + 1)
    ::continue::
  end
  if verbose and actualY ~= goalY then print("goalY="..goalY..", actualY="..actualY) end
  self:moveBy(0, actualY)
  -- Check attached bodies.
  for other in pairs(self.attached) do
    if checked[other] then goto continue end
    other:tryMoveByY(actualY, verbose, 0, copySetAndPut(checked, self))
    ::continue::
  end
  -- Weird exception for the sake of gamefeel: vertically stacked Bodies stick
  -- together when moving down, even if it's faster than gravity. If the
  -- carrying Body is moving up, propagation was already handled in the above
  -- recursive calls, so do nothing here.
  if actualY > 0 then
    for i = 1, #self.carried do
      self.carried[i]:tryMoveByY(actualY, verbose, 0)
    end
  end
  return actualY
end

-- Without moving, return the maximum distance this body can travel along the
-- x-axis, up to goalX. Returns a value 0 through goalX.
function Body:checkMoveByX(goalX, recursionDepth, checked)
  checked = checked or {}
  -- If this is a recursive call on a StaticBody, it should not move.
  if recursionDepth > 0 and self:getTag() == TAGS.static then return 0 end
  -- Recursively call checkMoveBy on any Body that is in the way.
  -- Adjust the return value accordingly.
  local _, _, collisions, numCollisions = self:checkCollisions(self.x + goalX, self.y)
  local minX = math.huge
  for i = 1, numCollisions do
    local other <const> = collisions[i].other
    if self.attached[other] then goto continue end
    local dist <const> = self:distX(other)
    assert(dist >= 0, "id="..self.id.."\tdistX="..dist)
    local signedDist <const> = sign(goalX) * dist
    local truncX <const> = signedDist + other:checkMoveByX(goalX - signedDist, recursionDepth + 1, checked)
    if math.abs(truncX) < math.abs(minX) then
      minX = truncX
    end
    ::continue::
  end
  -- Check attached bodies.
  for other in pairs(self.attached) do
    if checked[other] then goto continue end
    local otherX <const> = other:checkMoveByX(goalX, 0, copySetAndPut(checked, self))
    if math.abs(otherX) < math.abs(minX) then
      minX = otherX
    end
    ::continue::
  end
  if minX ~= math.huge then
    return minX
  end
  return goalX
end

function Body:tryMoveByX(goalX, verbose, recursionDepth, checked)
  assert(math.type(goalX) == "integer")
  checked = checked or {}
  recursionDepth = recursionDepth or 0
  -- Constrain movement based on how far subsequent bodies can be moved.
  local signX <const> = sign(goalX)
  local actualX = self:checkMoveByX(goalX, recursionDepth, checked)
  local _, _, collisions, numCollisions = self:checkCollisions(self.x + actualX, self.y)
  for i = 1, numCollisions do
    local other <const> = collisions[i].other
    if self.attached[other] then goto continue end
    local dist <const> = self:distX(other)
    assert(dist >= 0, "id="..self.id.."\tdistX="..dist)
    local signedDist <const> = signX * dist
    other:tryMoveByX(actualX - signedDist, verbose, recursionDepth + 1, checked)
    ::continue::
  end
  if verbose and actualX ~= goalX then print("goalX="..goalX..", actualX="..actualX) end
  self:moveBy(actualX, 0)
  -- Check attached bodies.
  for other in pairs(self.attached) do
    if checked[other] then goto continue end
    other:tryMoveByX(actualX, verbose, 0, copySetAndPut(checked, self))
    ::continue::
  end
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

function DynamicBody:init(x, y, w, h, label)
  DynamicBody.super.init(self, x, y, w, h, TAGS.dynamic)
  self.label = label
end

function DynamicBody:draw(x, y, w, h)
  gfx.drawRect(0, 0, self.width, self.height)
  if self.label then
    gfx.drawText(self.label, self.width / 2 - 4, self.height / 2 - 8)
  end
end

function spawnPackage(x, y, label)
  local package <const> = DynamicBody(x, y - PALLET_HEIGHT - PKG_HEIGHT/2, PKG_WIDTH, PKG_HEIGHT, label)
  local pallet <const> = DynamicBody(x, y - PALLET_HEIGHT/2, PALLET_WIDTH, PALLET_HEIGHT)
  package:attach(pallet)
  package:setGroups(GROUPS.package)
  package:setCollidesWithGroups({GROUPS.terrain, GROUPS.package, GROUPS.player, GROUPS.pallet})
  pallet:setGroups(GROUPS.pallet)
  pallet:setCollidesWithGroups({GROUPS.terrain, GROUPS.package})
  table.insert(dynBodies, package)
end

function spawnConveyorBeltSegment(x, y)
  local segment <const> = StaticBody(x, y, CONVEYOR_BELT_SEGMENT_WIDTH, CONVEYOR_BELT_SEGMENT_HEIGHT)
  segment:setGroups(GROUPS.terrain)
  segment:setCollidesWithGroups({GROUPS.package, GROUPS.pallet, GROUPS.player})
  return segment
end

-- Starts at top left corner and travels clockwise.
function distanceAlongRectanglePerimeter(x, y, w, h, d)
  local xBase = x - w / 2
  local yBase = y - h / 2
  local dx = 0
  local dy = 0
  d = d % (2 * (w + h))
  if d < w + h then
    dx = math.min(w, d)
    dy = math.max(0, d - w)
  else
    xBase = x + w / 2
    yBase = y + h / 2
    d -= w + h
    dx = -math.min(w, d)
    dy = -math.max(0, d - w)
  end
  return xBase + dx, yBase + dy
end

class("ConveyorBelt").extends(baseObject)

function ConveyorBelt:init(x, y, w, h, numSegments)
  self.x = x
  self.y = y
  self.w = w
  self.h = h
  self.segments = {}
  local distBetweenSegments = math.floor(2 * (w + h) / numSegments)
  for i = 1, numSegments do
    local d = i * distBetweenSegments
    local px, py = distanceAlongRectanglePerimeter(x, y, w, h, d)
    self.segments[spawnConveyorBeltSegment(px, py)] = d
  end
end

function spawnShelf(x, y)
  local shelf = StaticBody(x, y, SHELF_WIDTH, SHELF_HEIGHT)
  shelf:setGroups(GROUPS.terrain)
end

function ConveyorBelt:update()
  for seg, d in pairs(self.segments) do
    self.segments[seg] = d + 1
  end
  for seg, d in pairs(self.segments) do
    local px, py = distanceAlongRectanglePerimeter(self.x, self.y, self.w, self.h, d)
    seg:tryMoveByX(math.floor(px - seg.x))
    seg:tryMoveByY(math.floor(py - seg.y))
  end
end

function init()
  -- This is a global variable that accumulates crank change and dispenses the
  -- integral portion when it is less than -1 or greater than 1.
  crankChangeAccumulator = 0

  ground = StaticBody(200, 240, playdate.display.getWidth(), 50)
  ground:setGroups(GROUPS.terrain)

  -- Shelves
  spawnShelf(SHELF_WIDTH / 2, 80)
  spawnShelf(SHELF_WIDTH / 2, 150)
  spawnShelf(playdate.display.getWidth() - SHELF_WIDTH / 2, 80)
  spawnShelf(playdate.display.getWidth() - SHELF_WIDTH / 2, 150)

  fork = StaticBody(200, 180, PLAYER_WIDTH, PLAYER_HEIGHT)
  fork:setGroups(GROUPS.player)
  fork:setCollidesWithGroups({GROUPS.terrain, GROUPS.package})

  dynBodies = {}
  spawnPackage(50, 210, "C")
  spawnPackage(50, 140, "B")
  spawnPackage(50, 70, "A")
  --spawnPackage(50, 40)
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
    crankChangeAccumulator -= change
    local scaledChange <const> = crankChangeAccumulator / CRANK_SCALE
    if scaledChange <= -1 then
      dy = math.ceil(scaledChange)
    end
    if scaledChange >= 1 then
      dy = math.floor(scaledChange)
    end
    crankChangeAccumulator -= dy * CRANK_SCALE
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
    local actualDistMoved = dynBodies[i]:tryMoveByY(GRAVITY)
    if actualDistMoved < GRAVITY then
      for other in pairs(dynBodies[i].attached) do
        other:tryMoveByY(GRAVITY - actualDistMoved)
      end
    end
  end

  -- Handle player x-axis movement.
  if playdate.buttonIsPressed(playdate.kButtonRight) then
    dx = PLAYER_SPEED_X
  end
  if playdate.buttonIsPressed(playdate.kButtonLeft) then
    dx = -PLAYER_SPEED_X
  end
  fork:tryMoveByX(dx)

  -- Check no sprites are overlapping.
  gfx.sprite.performOnAllSprites(function(sprite)
    assert(#sprite:overlappingSprites() == 0, "Sprite #"..sprite.id.." has overlapping sprites")
  end)

  -- draw
  gfx.sprite.update()
end

function playdate.debugDraw()
  --[[
  -- Denote constraints between bodies.
  gfx.sprite.performOnAllSprites(function(sprite)
    for other, _ in pairs(sprite.attached) do
      gfx.drawLine(sprite.x, sprite.y, other.x, other.y)
    end
  end)
  -- Label number of bodies carried by each body.
  gfx.sprite.performOnAllSprites(function(sprite)
    gfx.drawText(#sprite.carried, sprite.x + sprite.width / 2 + 2, sprite.y - sprite.height / 2 - 20)
  end)
  -- Label bodies with IDs.
  gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
  gfx.sprite.performOnAllSprites(function(sprite)
    gfx.drawText(sprite.id, sprite.x + sprite.width / 2 + 2, sprite.y - sprite.height / 2)
  end)
  --]]
end

init()
