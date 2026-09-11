script_name("LSPD Impound Panel")
script_author("d4x")
script_version("0.1 BETA")

require "lib.moonloader"
local imgui = require "imgui"
local ffi = require "ffi"
local vkeys = require "vkeys"

local sampapi = require "SA-MP API"

local window = imgui.ImBool(false)
local searchBuf = imgui.ImBuffer("", 64)
local levelBuf = imgui.ImBuffer("", 16)
local vehicleType = imgui.ImInt(1)

local VEHICLES = {
    "Motorcycle",
    "Car",
    "Commercial Vehicle",
    "Sport Vehicle"
}

local function readSearchBuffer()
    local ok, value = pcall(function()
        return searchBuf.v
    end)

    if ok and value ~= nil then
        return tostring(value)
    end

    local ok2, value2 = pcall(function()
        return ffi.string(searchBuf)
    end)

    if ok2 and value2 ~= nil then
        return tostring(value2)
    end

    return ""
end

local function normalizeName(s)
    s = tostring(s or "")
    s = s:gsub("[%z\1-\31\127]", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s:lower()
end

local function validPlayerName(name)
    name = tostring(name or "")
    if #name < 3 or #name > 24 then return false end
    return name:match("^[A-Za-z0-9_]+$") ~= nil
end

local function readPlayerName(p)
    if p == nil then return "" end

    local ok, name = pcall(function()
        return ffi.string(p.strPlayerName)
    end)
    if ok and validPlayerName(name) then
        return name
    end

    local ok2, result = pcall(function()
        local b = ffi.cast("uint8_t*", p)
        local len = tonumber(ffi.cast("uint32_t*", b + 0x28)[0]) or 0
        if len < 3 or len > 24 then return "" end

        if len <= 15 then
            local inlineName = ffi.string(ffi.cast("char*", b + 0x18), len)
            if validPlayerName(inlineName) then return inlineName end
        end

        local ptr = tonumber(ffi.cast("uintptr_t*", b + 0x18)[0]) or 0
        if ptr < 0x10000 or ptr > 0x7FFFFFFF then return "" end
        local longName = ffi.string(ffi.cast("char*", ptr), len)
        if validPlayerName(longName) then return longName end
        return ""
    end)

    if ok2 then return result end
    return ""
end

local function getPlayerInfoById(id)
    if not sampapi.GetIsAvailable() then return nil end

    local result = nil
    pcall(function()
        local samp = sampapi.Get()
        local pool = samp.pBase.pPools.pPlayer
        if pool == nil then return end
        local rp = pool.pRemotePlayer[id]
        if rp == nil or tonumber(rp.iIsNPC) ~= 0 then return end

        local level = tonumber(rp.iScore) or 0
        result = {
            id = id,
            name = readPlayerName(rp),
            level = level
        }
    end)

    return result
end

local function getPlayersByName(query)
    local results = {}
    if not sampapi.GetIsAvailable() then return results end

    pcall(function()
        local samp = sampapi.Get()
        local pool = samp.pBase.pPools.pPlayer
        if pool == nil then return end

        local maxId = tonumber(pool.ulMaxPlayerID) or 1003
        if maxId > 1003 then maxId = 1003 end

        for id = 0, maxId do
            local rp = pool.pRemotePlayer[id]
            if rp ~= nil and tonumber(rp.iIsNPC) == 0 then
                local level = tonumber(rp.iScore) or 0
                local name = readPlayerName(rp)

                if level > 0 and name ~= "" then
                    local normalized = normalizeName(name)
                    if normalized:find(query, 1, true) then
                        results[#results + 1] = {
                            id = id,
                            name = name,
                            level = level
                        }
                    end
                end
            end
        end
    end)

    table.sort(results, function(a, b)
        return normalizeName(a.name) < normalizeName(b.name)
    end)

    return results
end

local function getPlayerInfoByQuery(query)
    if query == "" then return nil, {} end

    if query:match("^%d+$") then
        local id = tonumber(query)
        if id == nil or id < 0 or id > 1003 then
            return nil, {}
        end

        local player = getPlayerInfoById(id)
        if player ~= nil then
            return player, {player}
        end

        return nil, {}
    end

    local matches = getPlayersByName(query)
    if #matches == 1 then
        return matches[1], matches
    end

    for _, player in ipairs(matches) do
        if normalizeName(player.name) == query then
            return player, matches
        end
    end

    return nil, matches
end

local FINES = {
    {325,650,975,1300,1625,1950,2275,2600,2925,3250,3575,3900,4225,4550,4875,5200,5525,5850,6175,6500},
    {650,1300,1950,2600,3250,3900,4550,5200,5850,6500,7150,7800,8450,9100,9750,10400,11050,11700,12350,13000},
    {488,975,1463,1950,2438,2925,3413,3900,4388,4875,5363,5850,6338,6825,7313,7800,8288,8775,9263,9750},
    {813,1625,2438,3250,4063,4875,5688,6500,7313,8125,8938,9750,10563,11375,12188,13000,13813,14625,15438,16250}
}

local function getFine(level, typeIndex)
    level = tonumber(level) or 0
    if level < 1 then return nil end
    if level > 100 then level = 100 end
    local bracket = math.ceil(level / 5)
    return FINES[typeIndex][bracket]
end

local function money(n)
    local s = tostring(n)
    while true do
        local ns, count = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        s = ns
        if count == 0 then break end
    end
    return "$" .. s
end

function main()
    while true do
        wait(0)

        if isKeyDown(vkeys.VK_F5) and isKeyJustPressed(vkeys.VK_F5) then
            window.v = not window.v
        end

        imgui.Process = window.v
    end
end

function imgui.OnDrawFrame()
    imgui.Process = window.v
    if not window.v then return end

    imgui.SetNextWindowSize(imgui.ImVec2(560, 360), imgui.Cond.FirstUseEver)

    if imgui.Begin("LSPD Impound Panel", window) then
        imgui.Text("Vehicle Type")

        local vehicleCombo = imgui.ImInt(vehicleType.v - 1)
        if imgui.Combo("##vehicle_type", vehicleCombo, VEHICLES, #VEHICLES) then
            vehicleType.v = vehicleCombo.v + 1
        end

        imgui.Separator()
        imgui.Text("Player")
        imgui.InputText("##player_search", searchBuf)

        imgui.Text("Level")
        imgui.InputText("##player_level", levelBuf)

        local queryText = normalizeName(readSearchBuffer())
        local levelText = normalizeName(levelBuf.v or "")
        local manualLevel = nil
        local manualLevelInvalid = false

        if levelText ~= "" then
            if levelText:match("^%d+$") then
                manualLevel = tonumber(levelText)
                if manualLevel < 1 then
                    manualLevelInvalid = true
                elseif manualLevel > 100 then
                    manualLevel = 100
                end
            else
                manualLevelInvalid = true
            end
        end

        local selectedPlayer, matches = getPlayerInfoByQuery(queryText)
        local playerLevel = nil
        local invalidReason = nil

        if manualLevelInvalid then
            invalidReason = "Invalid level"
        elseif manualLevel ~= nil then
            playerLevel = manualLevel
        elseif queryText ~= "" then
            if queryText:match("^%d+$") then
                local id = tonumber(queryText)
                local rawPlayer = getPlayerInfoById(id)

                if rawPlayer == nil then
                    invalidReason = "Player not found"
                elseif rawPlayer.level <= 0 then
                    invalidReason = "Invalid player: level 0"
                else
                    playerLevel = rawPlayer.level
                    selectedPlayer = rawPlayer
                end
            elseif selectedPlayer ~= nil then
                if selectedPlayer.level <= 0 then
                    invalidReason = "Invalid player: level 0"
                else
                    playerLevel = selectedPlayer.level
                end
            elseif #matches > 1 then
                invalidReason = "Multiple players found"
            else
                invalidReason = "Player not found"
            end
        end

        if selectedPlayer ~= nil then
            local displayLevel = manualLevel ~= nil and manualLevel or selectedPlayer.level
            imgui.Text(string.format(
                "%s [ID %d | Level %d]",
                selectedPlayer.name,
                selectedPlayer.id,
                displayLevel
            ))
        elseif queryText ~= "" and #matches > 1 then
            imgui.Text(string.format("%d players found", #matches))
        end

        if invalidReason ~= nil then
            imgui.Text(invalidReason)
        elseif playerLevel ~= nil then
            local fine = getFine(playerLevel, vehicleType.v)
            if fine ~= nil then
                imgui.Separator()
                imgui.Text(string.format(
                    "Vehicle: %s | Fine: %s",
                    VEHICLES[vehicleType.v],
                    money(fine)
                ))
            end
        end

        imgui.End()
    end
end
