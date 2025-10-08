-- Turtle Cave Explorer with full vein mining and six-direction exploration

local t = turtle

-- Deny-list: blocks that should never be mined
local denyBlocks = {
  ["minecraft:stone"] = true,
  ["minecraft:andesite"] = true,
  ["minecraft:diorite"] = true,
  ["minecraft:granite"] = true,
  ["minecraft:dirt"] = true,
  ["minecraft:gravel"] = true,
  ["minecraft:sand"] = true,
  ["minecraft:stone_brick"] = true,
}

-- Position and direction tracking
local cx, cy, cz = 0, 0, 0
local dir = 0 -- 0=+X,1=+Z,2=-X,3=-Z
local visited = {}
local function posKey(x,y,z) return x..":"..y..":"..z end

-- Movement functions
local function moveForward() if t.forward() then if dir==0 then cx=cx+1 elseif dir==1 then cz=cz+1 elseif dir==2 then cx=cx-1 elseif dir==3 then cz=cz-1 end return true end return false end
local function moveBack() t.turnLeft(); t.turnLeft(); moveForward(); t.turnLeft(); t.turnLeft() end
local function moveUp() if t.up() then cy=cy+1; return true end return false end
local function moveDown() if t.down() then cy=cy-1; return true end return false end
local function turnLeft() dir=(dir+3)%4; t.turnLeft() end
local function turnRight() dir=(dir+1)%4; t.turnRight() end

-- Inspect and dig if allowed
local function checkBlock(inspectFunc,digFunc)
local ok,data=inspectFunc()
if ok and not denyBlocks[data.name] then digFunc(); return data.name end
return nil
end

-- Track visited blocks for vein mining
local veinVisited={}
local function veinKey(x,y,z) return x..":"..y..":"..z end

-- Recursive vein mining
local function mineVein(blockName)
local key=veinKey(cx,cy,cz)
if veinVisited[key] then return end
veinVisited[key]=true

local directions={
{move=moveForward,inspect=t.inspect,dig=t.dig},
{move=moveUp,inspect=t.inspectUp,dig=t.digUp},
{move=moveDown,inspect=t.inspectDown,dig=t.digDown},
{move=function() turnLeft(); local moved=moveForward(); turnRight(); return moved end, inspect=t.inspect,dig=t.dig},
{move=function() turnRight(); local moved=moveForward(); turnLeft(); return moved end, inspect=t.inspect,dig=t.dig}
}

for _,d in ipairs(directions) do
local ok,data=d.inspect()
if ok and data.name==blockName then
  d.dig()
  if d.move() then
    mineVein(blockName)
    -- backtrack
    if d.move==moveForward then moveBack()
    elseif d.move==moveUp then moveDown()
    elseif d.move==moveDown then moveUp()
    else -- left/right moves
      turnLeft(); turnLeft(); moveForward(); turnLeft(); turnLeft()
    end
  end
end
end
end

-- Scan all sides around current position for ores
local function scanAllSides()
local adjacents={
{inspect=t.inspect,dig=t.dig},
{inspect=t.inspectUp,dig=t.digUp},
{inspect=t.inspectDown,dig=t.digDown}
}
for _,adj in ipairs(adjacents) do
local ok,data=adj.inspect()
if ok and not denyBlocks[data.name] then
adj.dig()
mineVein(data.name)
end
end
-- check left and right sides
turnLeft()
local ok,data=t.inspect()
if ok and not denyBlocks[data.name] then t.dig(); mineVein(data.name) end
turnRight()
turnRight()
ok,data=t.inspect()
if ok and not denyBlocks[data.name] then t.dig(); mineVein(data.name) end
turnLeft()
end

-- Depth-first exploration in all six directions
local function explore()
local key=posKey(cx,cy,cz)
if visited[key] then return end
visited[key]=true

scanAllSides() -- continuously check for ores on all sides

local directions={
moveForward,
moveUp,
moveDown,
function() turnLeft(); local moved=moveForward(); turnRight(); return moved end,
function() turnRight(); local moved=moveForward(); turnLeft(); return moved end
}

for _,move in ipairs(directions) do
if move() then
  explore()
  -- backtrack
  if move==moveForward then moveBack()
  elseif move==moveUp then moveDown()
  elseif move==moveDown then moveUp()
  else -- left/right moves
    turnLeft(); turnLeft(); moveForward(); turnLeft(); turnLeft()
  end
end
end
end

print("Starting cave exploration with continuous ore scanning...")
explore()
print("Finished exploring.")
