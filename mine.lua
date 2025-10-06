-- === Mining Turtle Excavator (Layered + Resume Fixed) ===

local STATE_FILE = "resume.dat"
local CONFIG_FILE = "config.dat"

local WIDTH, HEIGHT, DEPTH = 5, 3, 10
local pos = {x = 0, y = 0, z = 0}
local dir = 0 -- 0=+Z, 1=+X, 2=-Z, 3=-X
local totalBlocks, blocksDug, blocksSinceTorch = 0, 0, 0
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
    if not fs.exists(STATE_FILE) then return false end
    local file = fs.open(STATE_FILE, "r")
    local data = textutils.unserialize(file.readAll())
    file.close()
    pos = data.pos or pos
    dir = data.dir or 0
    blocksDug = data.blocksDug or 0
    blocksSinceTorch = data.blocksSinceTorch or 0
    return true
end

local function promptDimensions()
    term.clear()
    term.setCursorPos(1, 1)
    print("=== New Excavation Setup ===")
    write("Width  (X): ") WIDTH = tonumber(read())
    write("Depth  (Z): ") DEPTH = tonumber(read())
    write("Height (Downward, Y): ") HEIGHT = tonumber(read())
    local file = fs.open(CONFIG_FILE, "w")
    file.write(textutils.serialize({width = WIDTH, height = HEIGHT, depth = DEPTH}))
    file.close()
end

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then promptDimensions() return end
    local file = fs.open(CONFIG_FILE, "r")
    local data = textutils.unserialize(file.readAll())
    file.close()
    WIDTH, HEIGHT, DEPTH = data.width, data.height, data.depth
end

local function updateProgressBar()
    local percent = math.floor((blocksDug / totalBlocks) * 100)
    local filled = math.floor(percent / 5)
    term.setCursorPos(1, 5)
    term.write(("Progress: [%s%s] %d%%"):format(string.rep("#", filled), string.rep("-", 20 - filled), percent))
end

local function checkFuel()
    if turtle.getFuelLevel() == "unlimited" then return end
    if turtle.getFuelLevel() < 50 then
        for i = 1, 16 do
            turtle.select(i)
            if turtle.refuel(1) then break end
        end
    end
end

-- === Movement ===
local function turnRight() turtle.turnRight() dir = (dir + 1) % 4 saveState() end
local function turnLeft()  turtle.turnLeft()  dir = (dir - 1) % 4 if dir < 0 then dir = 3 end saveState() end

local function forward()
    checkFuel()
    while not turtle.forward() do turtle.dig() sleep(0.2) end
    if dir == 0 then pos.z = pos.z + 1
    elseif dir == 1 then pos.x = pos.x + 1
    elseif dir == 2 then pos.z = pos.z - 1
    elseif dir == 3 then pos.x = pos.x - 1 end
    saveState()
end

local function down()
    checkFuel()
    while not turtle.down() do turtle.digDown() sleep(0.2) end
    pos.y = pos.y - 1
    saveState()
end

-- === Inventory ===
local function isInventoryFull()
    for i = 1, 16 do if turtle.getItemCount(i) == 0 then return false end end
    return true
end

local function findItem(name)
    for i = 1, 16 do
        local item = turtle.getItemDetail(i)
        if item and item.name == name then return i end
    end
    return nil
end

local function placeLadderBelowChest()
    local slot = findItem("minecraft:ladder")
    if not slot then return end
    turtle.select(slot)
    if turtle.detectDown() then turtle.digDown() end
    turtle.placeDown()
    turtle.select(1)
end

local function unloadInventory()
    print("Returning to chest to unload...")
    local savedPos = {x = pos.x, y = pos.y, z = pos.z}
    local savedDir = dir

    -- Return to 0,0,0
    while pos.y > 0 do down() end
    while dir ~= 2 do turnRight() end
    while pos.z > 0 do forward() end
    while dir ~= 3 do turnRight() end
    while pos.x > 0 do forward() end
    while dir ~= 2 do turnRight() end

    placeLadderBelowChest()

    local keep = {["minecraft:coal"] = 64, ["minecraft:ladder"] = 64, ["minecraft:torch"] = 64}
    local kept = {["minecraft:coal"] = 0, ["minecraft:ladder"] = 0, ["minecraft:torch"] = 0}
    for i = 1, 16 do
        turtle.select(i)
        local item = turtle.getItemDetail()
        if item then
            local name = item.name
            if keep[name] then
                local allowed = keep[name] - kept[name]
                if allowed < item.count then turtle.drop(item.count - allowed) end
                kept[name] = math.min(keep[name], kept[name] + item.count)
            else
                turtle.drop()
            end
        end
    end

    -- Return to saved position
    while dir ~= 1 do turnRight() end
    while pos.x < savedPos.x do forward() end
    while dir ~= 0 do turnRight() end
    while pos.z < savedPos.z do forward() end
    while pos.y < savedPos.y do turtle.up() pos.y = pos.y + 1 saveState() end
    while dir ~= savedDir do turnRight() end
    print("Resumed position.")
end

-- === Torch Placement ===
local function placeTorchOnWall()
    local slot = findItem("minecraft:torch")
    if not slot then return end
    turtle.select(slot)
    turnRight()
    if not turtle.detect() then turtle.place() end
    turnLeft()
    turtle.select(1)
end

-- === Excavation ===
local function excavate()
    local startLayer = math.floor(math.abs(pos.y))
    for layer = startLayer, HEIGHT - 1 do
        print("Mining layer " .. (layer + 1) .. "/" .. HEIGHT)

        for d = 0, DEPTH - 1 do
            local rowDir = (d % 2 == 0) and 1 or -1
            local startX = (rowDir == 1) and 0 or WIDTH - 1
            local endX = (rowDir == 1) and WIDTH - 1 or 0
            local step = rowDir

            for x = startX, endX, step do
                turtle.digDown()
                blocksDug = blocksDug + 1
                blocksSinceTorch = blocksSinceTorch + 1
                updateProgressBar()

                if blocksSinceTorch >= TORCH_INTERVAL then
                    placeTorchOnWall()
                    blocksSinceTorch = 0
                end

                if isInventoryFull() then unloadInventory() end
                saveState()
                if x ~= endX then forward() end
            end

            -- Move to next row (Z)
            if d ~= DEPTH - 1 then
                if rowDir == 1 then turnRight(); forward(); turnRight()
                else turnLeft(); forward(); turnLeft() end
            end
        end

        -- Finished layer, move down
        if layer ~= HEIGHT - 1 then
            print("Descending to next layer...")
            turnRight(); turnRight()
            for z = 1, DEPTH - 1 do forward() end
            turnRight(); turnRight()
            down()
        end
    end

    print("\nExcavation complete!")
    fs.delete(STATE_FILE)
end

-- === Main ===
term.clear()
term.setCursorPos(1, 1)
print("=== Mining Turtle Excavator ===")

if fs.exists(STATE_FILE) then
    print("Previous session found.")
    write("Continue from saved position? (Y/N): ")
    if read():lower() == "y" then
        loadState()
        loadConfig()
    else
        fs.delete(STATE_FILE)
        promptDimensions()
    end
else
    promptDimensions()
end

loadConfig()
totalBlocks = WIDTH * HEIGHT * DEPTH
updateProgressBar()
sleep(1)
excavate()
