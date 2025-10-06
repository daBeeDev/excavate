-- === Mining Turtle Excavator (Final Fixed & Improved) ===

-- File paths
local STATE_FILE = "resume.dat"
local CONFIG_FILE = "config.dat"

-- Default dimensions
local WIDTH, HEIGHT, DEPTH = 5, 3, 10

-- Position state
local pos = {x = 0, y = 0, z = 0}
local dir = 0 -- 0=+Z, 1=+X, 2=-Z, 3=-X

-- Progress tracking
local totalBlocks = 0
local blocksDug = 0

-- Torch placement tracking
local blocksSinceTorch = 0
local TORCH_INTERVAL = 10

-- === Utility ===

local function saveState()
    local file = fs.open(STATE_FILE, "w")
    file.write(textutils.serialize({
        pos = pos,
        dir = dir,
        blocksDug = blocksDug,
        blocksSinceTorch = blocksSinceTorch
    }))
    file.close()
end

local function loadState()
    if fs.exists(STATE_FILE) then
        local file = fs.open(STATE_FILE, "r")
        local data = textutils.unserialize(file.readAll())
        file.close()
        pos = data.pos
        dir = data.dir
        blocksDug = data.blocksDug or 0
        blocksSinceTorch = data.blocksSinceTorch or 0
        return true
    end
    return false
end

local function promptDimensions()
    term.clear()
    term.setCursorPos(1, 1)
    print("=== New Excavation Setup ===")

    write("Width  (X): ")
    WIDTH = tonumber(read())

    write("Depth  (Z): ")
    DEPTH = tonumber(read())

    write("Height (Downward, Y): ")
    HEIGHT = tonumber(read())

    local config = {width = WIDTH, height = HEIGHT, depth = DEPTH}
    local file = fs.open(CONFIG_FILE, "w")
    file.write(textutils.serialize(config))
    file.close()
end

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then
        promptDimensions()
        return
    end
    local file = fs.open(CONFIG_FILE, "r")
    local data = textutils.unserialize(file.readAll())
    file.close()
    WIDTH = data.width
    HEIGHT = data.height
    DEPTH = data.depth
end

local function updateProgressBar()
    local barLength = 20
    local percent = math.floor((blocksDug / totalBlocks) * 100)
    local filled = math.floor((percent / 100) * barLength)
    term.setCursorPos(1, 5)
    term.write("Progress: [")
    term.write(string.rep("#", filled))
    term.write(string.rep("-", barLength - filled))
    term.write("] " .. percent .. "%")
end

local function checkFuel()
    if turtle.getFuelLevel() == "unlimited" then return end
    if turtle.getFuelLevel() < 50 then
        for i = 1, 16 do
            turtle.select(i)
            if turtle.refuel(1) then
                break
            end
        end
    end
end

-- === Movement ===

local function turnRight()
    turtle.turnRight()
    dir = (dir + 1) % 4
    saveState()
end

local function turnLeft()
    turtle.turnLeft()
    dir = (dir - 1) % 4
    if dir < 0 then dir = 3 end
    saveState()
end

local function forward()
    checkFuel()
    while not turtle.forward() do
        turtle.dig()
        sleep(0.3)
    end
    if dir == 0 then pos.z = pos.z + 1
    elseif dir == 1 then pos.x = pos.x + 1
    elseif dir == 2 then pos.z = pos.z - 1
    elseif dir == 3 then pos.x = pos.x - 1 end
    saveState()
end

local function up()
    checkFuel()
    while not turtle.up() do
        turtle.digUp()
        sleep(0.3)
    end
    pos.y = pos.y + 1
    saveState()
end

local function down()
    checkFuel()
    while not turtle.down() do
        turtle.digDown()
        sleep(0.3)
    end
    pos.y = pos.y - 1
    saveState()
end

-- === Inventory & Unload ===

local function isInventoryFull()
    for i = 1, 16 do
        if turtle.getItemCount(i) == 0 then return false end
    end
    return true
end

local function findItem(name)
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and item.name == name then
            return i
        end
    end
    return nil
end

local function placeLadderBelowChest()
    local slot = findItem("minecraft:ladder")
    if not slot then return end
    turtle.select(slot)
    turtle.down()
    turtle.placeUp()
    turtle.up()
    turtle.select(1)
end

local function unloadInventory()
    print("Inventory full. Returning to unload...")

    local savedPos = {x = pos.x, y = pos.y, z = pos.z}
    local savedDir = dir

    -- Return home (0,0,0)
    while pos.y > 0 do down() end
    while dir ~= 2 do turnRight() end
    while pos.z > 0 do forward() end
    while dir ~= 3 do turnRight() end
    while pos.x > 0 do forward() end
    while dir ~= 2 do turnRight() end

    -- Place ladder below chest
    placeLadderBelowChest()

    -- Drop all items except ladders, coal, torches (keep up to 64 each)
    local keep = {["minecraft:coal"] = 64, ["minecraft:ladder"] = 64, ["minecraft:torch"] = 64}
    local kept = {["minecraft:coal"] = 0, ["minecraft:ladder"] = 0, ["minecraft:torch"] = 0}

    for i = 1, 16 do
        turtle.select(i)
        local item = turtle.getItemDetail()
        if item then
            local name = item.name
            if keep[name] then
                local allowed = keep[name] - kept[name]
                if allowed > 0 then
                    if item.count > allowed then
                        turtle.drop(item.count - allowed)
                        kept[name] = kept[name] + allowed
                    else
                        kept[name] = kept[name] + item.count
                    end
                else
                    turtle.drop()
                end
            else
                turtle.drop()
            end
        end
    end
    turtle.select(1)

    -- Return to saved position
    while dir ~= 1 do turnRight() end
    while pos.x < savedPos.x do forward() end
    while dir ~= 0 do turnRight() end
    while pos.z < savedPos.z do forward() end
    while pos.y < savedPos.y do up() end
    while dir ~= savedDir do turnRight() end

    print("Resumed position.")
end

-- === Ore Detection ===

local function isOre(name)
    return name and (name:match("ore") or name:match("crystal") or name:match("gem"))
end

local function mineAdjacentOres()
    local directions = {
        function() turnLeft() end,
        function() turnRight() end,
        function() turnLeft(); turnLeft() end
    }
    for _, turn in ipairs(directions) do
        turn()
        local success, data = turtle.inspect()
        if success and isOre(data.name) then
            turtle.dig()
            forward()
            mineAdjacentOres()
            turnLeft(); turnLeft()
            forward()
            turnLeft(); turnLeft()
        end
    end
end

-- === Torch Placement ===

local function placeTorchOnWall()
    local slot = findItem("minecraft:torch")
    if not slot then return end
    turtle.select(slot)
    turnRight()
    turtle.place()
    turnLeft()
    turtle.select(1)
end

-- === Excavation Logic (with Resume Support) ===

local function excavate()
    local startLayer = math.floor(math.abs(pos.y))
    local startDepth = pos.z
    local startX = pos.x

    for h = startLayer, HEIGHT - 1 do
        while pos.y > -h do down() end
        while pos.y < -h do up() end

        local depthStart = (h == startLayer) and startDepth or 0
        for d = depthStart, DEPTH - 1 do
            local rowDir = (d % 2 == 0) and 1 or -1
            local rowStartX = (h == startLayer and d == startDepth) and startX or ((rowDir == 1) and 0 or WIDTH - 1)
            local endX = (rowDir == 1) and WIDTH - 1 or 0
            local step = rowDir

            for x = rowStartX, endX, step do
                turtle.digDown()
                blocksDug = blocksDug + 1
                blocksSinceTorch = blocksSinceTorch + 1
                updateProgressBar()
                mineAdjacentOres()

                if blocksSinceTorch >= TORCH_INTERVAL then
                    placeTorchOnWall()
                    blocksSinceTorch = 0
                end

                if isInventoryFull() then
                    unloadInventory()
                end

                saveState()

                if x ~= endX then forward() end
            end
        end
    end

    print("\nExcavation complete!")
    fs.delete(STATE_FILE)
end

-- === Main ===

term.clear()
term.setCursorPos(1,1)
print("=== Mining Turtle Excavator ===")

if fs.exists(STATE_FILE) then
    print("Previous session found.")
    write("Continue from saved position? (Y/N): ")
    local choice = read():lower()

    if choice == "y" then
        loadState()
        loadConfig()
        totalBlocks = WIDTH * HEIGHT * DEPTH
        updateProgressBar()
    else
        fs.delete(STATE_FILE)
        fs.delete(CONFIG_FILE)
        promptDimensions()
        pos = {x = 0, y = 0, z = 0}
        dir = 0
        totalBlocks = WIDTH * HEIGHT * DEPTH
        blocksDug = 0
        blocksSinceTorch = 0
        saveState()
        updateProgressBar()
    end
else
    promptDimensions()
    pos = {x = 0, y = 0, z = 0}
    dir = 0
    totalBlocks = WIDTH * HEIGHT * DEPTH
    blocksDug = 0
    blocksSinceTorch = 0
    saveState()
    updateProgressBar()
end

sleep(1)
excavate()
