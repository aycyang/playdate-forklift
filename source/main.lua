import "CoreLibs/graphics"

function init()
  forklift = newForklift(300, 200)
  ground = newGround(200)
  packages = {}
  table.insert(packages, newPackage(120, 100))
  table.insert(packages, newPackage(250, 100))
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
  local forkRect = playdate.geometry.rect.new(0, 0, forkLength, forkWidth)
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
  function obj:getForkRect()
    forkRect.x = self.x - widthBase/2 - forkWidth - forkGap - forkLength
    forkRect.y = self.y - self.forkHeight
    return forkRect
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

function newGround(y, h)
  local obj = playdate.geometry.rect.new(
     0,
     y,
     playdate.display.getWidth(),
     h or playdate.display.getHeight())
  return obj
end

-- (x, y) refers to the bottom center of the package
function newPackage(x, y, w, h)
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
  function obj:getRect()
    return playdate.geometry.rect.new(
      self.x - self.w/2,
      self.y - self.h,
      self.w,
      self.h)
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
  -- gravity and try update position
  for i = 1, #packages do
    packages[i]:update(deltaTime)
  end
  -- collision: push object out
  -- packages with ground
  for i = 1, #packages do
    if ground:intersects(packages[i]:getRect()) then
      packages[i].vy = 0
      packages[i].y = ground.y
    end
  end
  local fork = forklift:getForkRect()
  for i = 1, #packages do
    if fork:intersects(packages[i]:getRect()) then
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
  playdate.graphics.drawRect(ground)
  forklift:draw(playdate.graphics)
  for i = 1, #packages do
    packages[i]:draw(playdate.graphics)
  end
end

init()
