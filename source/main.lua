import "CoreLibs/graphics"

function init()
  forklift = newForklift(300, 200)
  fork = newAABB(0, 0, 0, 0)
  ground = makeGround(200)
  packages = {}
  table.insert(packages, makePackage(120, 100))
  table.insert(packages, makePackage(250, 100))
end

function newForklift(x, y)
  local widthBase <const> = 50
  local widthCockpit <const> = 30
  local heightBase <const> = 20
  local heightCockpit <const> = 50
  local forkWidth <const> = 2
  local forkMaxHeight <const> = 120
  local forkLength <const> = 30
  local forkGap <const> = 1
  local obj = {
    x = x,
    y = y,
    forkHeight = 20,
  }
  function obj:raiseFork(crankChange)
    self.forkHeight = clamp(self.forkHeight + crankChange, 0, 120)
  end
  function obj:move(dx)
    self.x += dx
  end
  function obj:getForkAABB()
    return newAABB(
      self.x - widthBase/2 - forkWidth - forkGap - forkLength,
      self.y - self.forkHeight,
      forkLength,
      forkWidth)
  end
  function obj:draw(gfx)
    gfx.fillRect(self.x - widthBase/2, self.y - heightBase, widthBase, heightBase)
    gfx.drawRect(self.x - widthCockpit/2, self.y - heightCockpit, widthCockpit, heightCockpit)
    gfx.fillRect(self.x - widthBase/2 - forkWidth - forkGap, self.y - forkMaxHeight, forkWidth, forkMaxHeight)
    -- fork
    gfx.fillRect(self.x - widthBase/2 - forkWidth - forkGap - forkLength, self.y - self.forkHeight, forkLength, forkWidth)
  end
  function obj:update(dt)
  end
  return obj
end

function newAABB(x, y, w, h)
  return {
    x = x,
    y = y,
    w = w,
    h = h,
  }
end

function makeGround(y, h)
  local obj = {
    x = 0,
    y = y,
    w = playdate.display.getWidth(),
    h = h or playdate.display.getHeight(),
  }
  function obj:draw(gfx)
    gfx.drawRect(self.x, self.y, self.w, self.h)
  end
  return obj
end

function collide(a, b)
  return not (a.x + a.w < b.x or b.x + b.w < a.x or a.y + a.h < b.y or b.y + b.h < a.y)
end

-- (x, y) refers to the bottom center of the package
function makePackage(x, y, w, h)
  local obj = {
    x = x,
    y = y,
    vx = 0,
    vy = 0,
    w = w or 40,
    h = h or 40,
  }
  function obj:draw(gfx)
    gfx.fillRect(self.x - self.w/2, self.y - self.h, self.w, self.h)
  end
  function obj:update(dt)
    self.vy += 1
    self.y += self.vy
  end
  function obj:getAABB()
    return {
      x = self.x - self.w/2,
      y = self.y - self.h,
      w = self.w,
      h = self.h,
    }
  end
  return obj
end


function clamp(n, lower, upper)
  return math.min(math.max(n, lower), upper)
end

-- (x, y) refers to the bottom center of the forklift
function drawForklift(gfx, x, y, h)
end

function playdate.update()
  -- handle input
  local change, _ = playdate.getCrankChange()
  forklift:raiseFork(change)

  if playdate.buttonIsPressed( playdate.kButtonRight ) then
    forklift:move(2)
  end
  if playdate.buttonIsPressed( playdate.kButtonLeft ) then
    forklift:move(-2)
  end

  -- update
  local deltaTime = playdate.getElapsedTime()
  playdate.resetElapsedTime()
  -- update forklift fork collider
  fork = forklift:getForkAABB()
  -- gravity and try update position
  for i = 1, #packages do
    packages[i]:update(deltaTime)
  end
  -- collision: push object out
  -- packages with ground
  for i = 1, #packages do
    if collide(packages[i]:getAABB(), ground) then
      packages[i].vy = 0
      packages[i].y = ground.y
    end
  end
  for i = 1, #packages do
    if collide(packages[i]:getAABB(), fork) then
      packages[i].vy = 0
      packages[i].y = fork.y
    end
  end
  -- packages with packages
  for i = 1, #packages do
    for j = 1, #packages do
      if i == j then goto continue end
      -- TODO
      ::continue::
    end
  end

  -- draw
  playdate.graphics.clear()
  ground:draw(playdate.graphics)
  forklift:draw(playdate.graphics)
  for i = 1, #packages do
    packages[i]:draw(playdate.graphics)
  end
end

init()
