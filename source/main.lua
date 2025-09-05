import "CoreLibs/graphics"

function init()
  forkliftHeight = 20
  forkliftX = 300
  forkliftY = 200
  packages = {}
  table.insert(packages, makePackage(120, 100))
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
  return obj
end


function clamp(n, lower, upper)
  return math.min(math.max(n, lower), upper)
end

-- (x, y) refers to the bottom center of the forklift
function drawForklift(gfx, x, y, h)
  local widthBase = 40
  local widthCockpit = 30
  local heightBase = 20
  local heightCockpit = 50
  local forkWidth = 2
  local forkMaxHeight = 120
  local forkLength = 30
  local forkGap = 1
  local forkHeight = h
  gfx.fillRect(x - widthBase/2, y - heightBase, widthBase, heightBase)
  gfx.drawRect(x - widthCockpit/2, y - heightCockpit, widthCockpit, heightCockpit)
  gfx.fillRect(x - widthBase/2 - forkWidth - forkGap, y - forkMaxHeight, forkWidth, forkMaxHeight)
  gfx.fillRect(x - widthBase/2 - forkWidth - forkGap - forkLength, y - forkHeight, forkLength, forkWidth)
end

function playdate.update()
  -- handle input
  local change, _ = playdate.getCrankChange()
  forkliftHeight = clamp(forkliftHeight + change, 0, 120)

  if playdate.buttonIsPressed( playdate.kButtonRight ) then
    forkliftX += 2
  end
  if playdate.buttonIsPressed( playdate.kButtonLeft ) then
    forkliftX -= 2
  end

  -- update
  local deltaTime = playdate.getElapsedTime()
  playdate.resetElapsedTime()
  for i = 1, #packages do
    packages[i]:update(deltaTime)
  end

  -- draw
  playdate.graphics.clear()
  drawForklift(playdate.graphics, forkliftX, forkliftY, forkliftHeight)
  for i = 1, #packages do
    packages[i]:draw(playdate.graphics)
  end
end

init()
