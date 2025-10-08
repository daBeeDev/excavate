local t = turtle

-- Deny-list blocks
local denyBlocks = {
  ["minecraft:stone"]=true,
  ["minecraft:andesite"]=true,
  ["minecraft:diorite"]=true,
  ["minecraft:granite"]=true,
  ["minecraft:dirt"]=true,
  ["minecraft:gravel"]=true,
  ["minecraft:sand"]=true,
  ["minecraft:stone_brick"]=true
}

-- Starting position
local cx, cy, cz = 0, 0, 0
local dir = 0 -- 0=+X,1=+Z,2=-X,3=-Z

local visited = {}
local veinVisited = {}

local function posKey(x,y,z) return x..":"..y..":"..z end

-- Movement helpers
local function moveForward() if t.forward() then if dir==0 then cx=cx+1 elseif dir==1 then cz=cz+1 elseif dir==2 then cx=cx-1 elseif dir==3 then cz=cz-1 end return true end return false end
local function moveBack() t.turnLeft(); t.turnLeft(); moveForward(); t.turnLeft(); t.turnLeft() end
local function moveUp() if t.up() then cy=cy+1; return true end return false end
local function moveDown() if t.down() then cy=cy-1; return true end return false end
local function turnLeft() dir=(dir+3)%4; t.turnLeft() end
local function turnRight() dir=(dir+1)%4; t.turnRight() end

-- Inspect and dig
local function checkBlock(inspectFunc,digFunc)
  local ok,data = inspectFunc()
  if ok and not denyBlocks[data.name] then
    digFunc()
    return data.name
  end
  return nil
end

-- Vein mining
local function veinKey(x,y,z) return x..":"..y..":"..z end
local function mineVein(blockName)
  local key = veinKey(cx,cy,cz)
  if veinVisited[key] then return end
  veinVisited[key] = true

  local directions = {
    {move=moveForward, inspect=t.inspect, dig=t.dig},
    {move=moveUp, inspect=t.inspectUp, dig=t.digUp},
    {move=moveDown, inspect=t.inspectDown, dig=t.digDown},
    {move=function() turnLeft(); local moved=moveForward(); turnRight(); return moved end, inspect=t.inspect, dig=t.dig},
    {move=function() turnRight(); local moved=moveForward(); turnLeft(); return moved end, inspect=t.inspect, dig=t.dig}
  }

  for _,d in ipairs(directions) do
    local ok, data = d.inspect()
    if ok and data.name == blockName then
      d.dig()
      if d.move() then
        mineVein(blockName)
        if d.move==moveForward then moveBack()
        elseif d.move==moveUp then moveDown()
        elseif d.move==moveDown then moveUp()
        else turnLeft(); turnLeft(); moveForward(); turnLeft(); turnLeft() end
      end
    end
  end
end

-- BFS cave exploration
local function exploreBFS()
  local queue = {}
  table.insert(queue, {x=cx, y=cy, z=cz})

  while #queue > 0 do
    local current = table.remove(queue, 1)
    local key = posKey(current.x,current.y,current.z)
    if visited[key] then goto continue end
    visited[key] = true

    -- Move turtle to current position (assumes we backtrack as needed)
    -- For simplicity, assumes turtle is already at correct position

    -- Scan all adjacent blocks
    local adjacents = {
      {inspect=t.inspect, dig=t.dig, move=moveForward},
      {inspect=t.inspectUp, dig=t.digUp, move=moveUp},
      {inspect=t.inspectDown, dig=t.digDown, move=moveDown},
    }

    for _,adj in ipairs(adjacents) do
      local ok,data = adj.inspect()
      if ok and not denyBlocks[data.name] then
        adj.dig()
        mineVein(data.name)
        table.insert(queue, {x=cx, y=cy, z=cz})
      end
    end

    -- Scan sides
    for _,turn in ipairs({turnLeft, turnRight}) do
      turn()
      local ok,data = t.inspect()
      if ok and not denyBlocks[data.name] then
        t.dig()
        mineVein(data.name)
        table.insert(queue, {x=cx, y=cy, z=cz})
      end
      -- turn back to original direction
      if turn==turnLeft then turnRight() else turnLeft() end
    end

    ::continue::
  end
end

print("Starting BFS cave exploration...")
exploreBFS()
print("Finished exploration.")
