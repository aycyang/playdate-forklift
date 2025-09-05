import "CoreLibs/graphics"

function init()
  forkliftHeight = 20
  forkliftX = 100
  forkliftY = 200
end

init()

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
  local change, _ = playdate.getCrankChange()
  forkliftHeight = clamp(forkliftHeight + change, 0, 120)

  if playdate.buttonIsPressed( playdate.kButtonRight ) then
    forkliftX += 2
  end
  if playdate.buttonIsPressed( playdate.kButtonLeft ) then
    forkliftX -= 2
  end

  playdate.graphics.clear()
  drawForklift(playdate.graphics, forkliftX, forkliftY, forkliftHeight)
end
