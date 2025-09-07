--[[ vim config just for this file

set makeprg=./build_and_run.sh
nnoremap <cr> :make<cr>

--]]

import "CoreLibs/graphics"
import "CoreLibs/object"
import "CoreLibs/sprites"

-- TODO
-- * tryMove(x, y): check for collisions along each axis (x, y) individually.
--   for all bodies returned, recursively call tryMove on them, with the current
--   distance subtracted. once all tryMove calls have returned, call
--   self:moveWithCollisions(x, y).
-- * use delta time instead of fixed framerate
-- * make blocks stack
-- * make the block move left and right
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

print(gfx.getImageDrawMode())
print(gfx.kDrawModeCopy)
gfx.setImageDrawMode(gfx.kDrawModeCopy)

class("Fork").extends(gfx.sprite)

function Fork:init(x, y, w, h)
  Fork.super.init(self)
  self:moveTo(x, y)
  self:setSize(w, h)
  self:setCollideRect(0, 0, w, h)
end

function Fork:draw(x, y, w, h)
  gfx.fillRect(x, y, w, h)
end

--local forkImage = gfx.image.new("images/fork")
--assert(forkImage)
local fork = Fork(100, 100, 30, 5)
--fork:setImage(forkImage)
fork:add()

class("StaticBody").extends(gfx.sprite)

function StaticBody:init(x, y, w, h)
  StaticBody.super.init(self)
  self:setSize(w, h)
  self:moveTo(x, y)
  self:setCollideRect(0, 0, w, h)
end

function StaticBody:draw(x, y, w, h)
  gfx.fillRect(x, y, w, h)
end

local ground = StaticBody(50, 50, 60, 40)
ground:add()


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
  fork:moveWithCollisions(fork.x, fork.y + dy)

  -- handle player x-axis movement
  if playdate.buttonIsPressed(playdate.kButtonRight) then
    dx = 2
  end
  if playdate.buttonIsPressed(playdate.kButtonLeft) then
    dx = -2
  end
  fork:moveWithCollisions(fork.x + dx, fork.y)

  -- draw
  --gfx.clear()
  gfx.sprite.update()
end

init()
