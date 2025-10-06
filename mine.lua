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

-- === Utility ===

local function saveState()
    local file = fs.open(STATE_FILE, "w")
    file.write(textutils.serialize({pos = pos, dir = dir}))
    file.close()
end

local function loadState()
    if fs.exists(STATE_FILE) then
        local file = fs.open(STATE_FILE, "r")
        local data = textutils.unserialize(file.readAll())
        file.close()
        pos = data.pos
        dir = data.dir
        return true
    end
    return false
end

local function promptDimensions()
    term.clear()
    term.setCursorPos(1, 1)
    print("=== New Excavation Setup ===")
    write("Width  (X): ") WIDTH = tonumber(read())
    write("Height (Y): ") HEIGHT = tonumber(read())
    write("Depth  (Z): ") DEPTH = tonumber(read())

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
    saveState()
end

local function forward()
    checkFuel()
    while not turtle.forward() do
        turtle.dig()
        sleep(0.5)
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
        sleep(0.5)
    end
    pos.y = pos.y + 1
    saveState()
end

local function down()
    checkFuel()
    while not turtle.down() do
        turtle.digDown()
        sleep(0.5)
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

local function unloadInventory()
    print("Inventory full. Unloading...")

    local savedPos = {x = pos.x, y = pos.y, z = pos.z}
    local savedDir = dir

    -- Go home
    while pos.y > 0 do down() end
    while dir ~= 2 do turnRight() end
    while pos.z > 0 do forward() end
    while dir ~= 3 do turnRight() end
    while pos.x > 0 do forward() end
    while dir ~= 2 do turnRight() end

    -- Drop items except coal (keep 64)
    local coalKept = 0
    for i = 1, 16 do
        turtle.select(i)
        local item = turtle.getItemDetail()
        if item then
            if item.name == "minecraft:coal" then
                if coalKept + item.count <= 64 then
                    coalKept = coalKept + item.count
                else
                    local dropCount = (coalKept + item.count) - 64
                    turtle.drop(dropCount)
                    coalKept = 64
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

-- === Ore Mining on Perimeter ===

local function isOre(name)
    return name and string.find(name, "ore")
end

local function mineAdjacentOres()
    local directions = {
        {cond = pos.x == 0, turn = function() while dir ~= 3 do turnRight() end end},
        {cond = pos.x == WIDTH - 1, turn = function() while dir ~= 1 do turnRight() end end},
        {cond = pos.z == 0, turn = function() while dir ~= 2 do turnRight() end end},
        {cond = pos.z == DEPTH - 1, turn = function() while dir ~= 0 do turnRight() end end}
    }

    for _, side in ipairs(directions) do
        if side.cond then
            local originalDir = dir
            side.turn()
            local success, data = turtle.inspect()
            if success and isOre(data.name) then
                turtle.dig()
                forward()
                mineAdjacentOres()
                turnLeft() turnLeft()
                forward()
                while dir ~= originalDir do turnRight() end
                saveState()
            else
                while dir ~= originalDir do turnRight() end
            end
        end
    end
end

-- === Excavation Logic ===

local function excavate()
    for h = HEIGHT - 1, 0, -1 do
        for d = 0, DEPTH - 1 do
            local rowDir = (d % 2 == 0) and 1 or -1
            local startX = (rowDir == 1) and 0 or WIDTH - 1
            local endX = (rowDir == 1) and WIDTH - 1 or 0
            local step = rowDir

            for x = startX, endX, step do
                -- Move to X
                if pos.x ~= x then
                    if pos.x < x then
                        while dir ~= 1 do turnRight() end
                    else
                        while dir ~= 3 do turnRight() end
                    end
                    while pos.x ~= x do forward() end
                end

                -- Move to Z
                if pos.z ~= d then
                    if pos.z < d then
                        while dir ~= 0 do turnRight() end
                    else
                        while dir ~= 2 do turnRight() end
                    end
                    while pos.z ~= d do forward() end
                end

                -- Move to Y (DOWN instead of UP)
                while pos.y < h do up() end
                while pos.y > h do down() end

                -- Dig down and check perimeter
                turtle.digDown()
                blocksDug = blocksDug + 1
                updateProgressBar()
                mineAdjacentOres()

                if isInventoryFull() then
                    unloadInventory()
                end

                saveState()
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
        blocksDug = (pos.y * WIDTH * DEPTH) + (pos.z * WIDTH) + pos.x
        updateProgressBar()
    else
        fs.delete(STATE_FILE)
        fs.delete(CONFIG_FILE)
        promptDimensions()
        pos = {x = 0, y = 0, z = 0}
        dir = 0
        totalBlocks = WIDTH * HEIGHT * DEPTH
        blocksDug = 0
        saveState()
        updateProgressBar()
    end
else
    promptDimensions()
    pos = {x = 0, y = 0, z = 0}
    dir = 0
    totalBlocks = WIDTH * HEIGHT * DEPTH
    blocksDug = 0
    saveState()
    updateProgressBar()
end

sleep(1)
excavate()
