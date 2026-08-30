NPCDepth = NPCDepth or {}

local Adapter = {}
NPCDepth.ProjectRemnantsAdapter = Adapter

local VERIFIED_ROSTER_PROFILE = {
    id = "project-remnants-42-roster-20260829",
    -- Recognition is by requiredGlobals only (API fingerprint). The Workshop ID
    -- is intentionally NOT used here: getWorkshopID() returns nil at runtime for
    -- this install, so a workshopId comparison would always reject the profile.
    requiredGlobals = {
        "npcfwGetAssignmentOf",
        "npcfwGetPlayerFactionMemberIds",
        "npcfwGetPlayerFactionRoster",
        "npcfwIsPlayerFactionMember"
    }
}

local MAX_ROSTER_ENTRIES = 256

local function safeValue(read)
    local ok, value = pcall(read)
    if not ok then
        return nil, tostring(value)
    end
    return value, nil
end

local function readGameBuild()
    if type(getGameVersion) == "function" then
        local value = safeValue(function()
            return getGameVersion()
        end)
        if value ~= nil then
            return tostring(value)
        end
    end

    if type(getCore) == "function" then
        local value = safeValue(function()
            return getCore():getVersionNumber()
        end)
        if value ~= nil then
            return tostring(value)
        end
    end

    return "unknown"
end

local function readActivatedMods()
    local result = {
        available = false,
        ids = {},
        error = nil
    }

    if type(getActivatedMods) ~= "function" then
        result.error = "getActivatedMods is unavailable"
        return result
    end

    local mods, readError = safeValue(function()
        return getActivatedMods()
    end)
    if mods == nil then
        result.error = readError or "getActivatedMods returned nil"
        return result
    end

    local count, countError = safeValue(function()
        return mods:size()
    end)
    if count == nil then
        result.error = countError or "activated mod list has no readable size"
        return result
    end

    result.available = true
    for index = 0, count - 1 do
        local modId, itemError = safeValue(function()
            return mods:get(index)
        end)
        if modId ~= nil then
            table.insert(result.ids, tostring(modId))
        elseif result.error == nil then
            result.error = itemError
        end
    end
    table.sort(result.ids)
    return result
end

local function contains(list, expected)
    for index = 1, #list do
        if list[index] == expected then
            return true
        end
    end
    return false
end

local function readModMetadata(modId)
    local result = {
        id = modId,
        found = false,
        name = nil,
        modVersion = nil,
        versionDir = nil,
        workshopId = nil,
        directory = nil,
        error = nil
    }

    if type(getModInfoByID) ~= "function" then
        result.error = "getModInfoByID is unavailable"
        return result
    end

    local modInfo, readError = safeValue(function()
        return getModInfoByID(modId)
    end)
    if modInfo == nil then
        result.error = readError or "manifest metadata was not found"
        return result
    end

    result.found = true

    local function readMethod(fieldName, method)
        local value, methodError = safeValue(method)
        if value ~= nil then
            result[fieldName] = tostring(value)
        elseif result.error == nil and methodError ~= nil then
            result.error = methodError
        end
    end

    readMethod("name", function() return modInfo:getName() end)
    readMethod("modVersion", function() return modInfo:getModVersion() end)
    readMethod("versionDir", function() return modInfo:getVersionDir() end)
    readMethod("workshopId", function() return modInfo:getWorkshopID() end)
    readMethod("directory", function() return modInfo:getDir() end)

    return result
end

local function listFrameworkGlobals()
    local result = {
        names = {},
        types = {},
        error = nil
    }

    local ok, scanError = pcall(function()
        for name, value in pairs(_G) do
            if type(name) == "string" and string.sub(name, 1, 5) == "npcfw" then
                table.insert(result.names, name)
                result.types[name] = type(value)
            end
        end
    end)

    if not ok then
        result.error = tostring(scanError)
    end
    table.sort(result.names)
    return result
end

local function recognizeProfile(remnants, frameworkGlobals)
    local result = {
        status = "unknown",
        id = nil,
        missingGlobals = {}
    }

    if not remnants.active or #frameworkGlobals.names == 0 then
        result.status = "unavailable"
        return result
    end

    -- Recognize by npcfw* API fingerprint only. Do NOT gate on workshopId; the
    -- runtime metadata (getWorkshopID) is nil for this install and would reject
    -- an otherwise-verified profile.

    for index = 1, #VERIFIED_ROSTER_PROFILE.requiredGlobals do
        local name = VERIFIED_ROSTER_PROFILE.requiredGlobals[index]
        if frameworkGlobals.types[name] ~= "function" then
            table.insert(result.missingGlobals, name)
        end
    end

    if #result.missingGlobals == 0 then
        result.status = "verified"
        result.id = VERIFIED_ROSTER_PROFILE.id
    end

    return result
end

local function readRowField(row, fieldName)
    local value, readError = safeValue(function()
        return row[fieldName]
    end)
    if readError ~= nil then
        error("Could not read roster field " .. tostring(fieldName) .. ": " .. readError)
    end
    return value
end

local function copyRosterRow(row, index)
    if row == nil then
        return nil
    end

    local npcId = readRowField(row, "npcId")
    if npcId == nil or tostring(npcId) == "" then
        error("Roster entry " .. tostring(index) .. " has no npcId")
    end

    local displayName = readRowField(row, "displayName")
    local assignment = readRowField(row, "assignment")
    local safehouseJob = readRowField(row, "safehouseJob")
    local safehouseJobLabel = readRowField(row, "safehouseJobLabel")
    local currentSafehouseTask = readRowField(row, "currentSafehouseTask")

    return {
        frameworkKey = tostring(npcId),
        displayName = tostring(displayName or "NPC"),
        assignment = tostring(assignment or "WORLD"),
        isPartyMember = readRowField(row, "isPartyMember") == true,
        isBaseResident = readRowField(row, "isBaseResident") == true,
        isLive = readRowField(row, "isLive") == true,
        safehouseJob = tostring(safehouseJob or "NONE"),
        safehouseJobLabel = tostring(safehouseJobLabel or safehouseJob or "NONE"),
        currentSafehouseTask = tostring(currentSafehouseTask or "IDLE")
    }
end

function Adapter.ReadCompanionSnapshots(profileId)
    if profileId ~= VERIFIED_ROSTER_PROFILE.id then
        error("Unsupported Project Remnants profile: " .. tostring(profileId))
    end

    local readRoster = _G["npcfwGetPlayerFactionRoster"]
    if type(readRoster) ~= "function" then
        error("npcfwGetPlayerFactionRoster is unavailable")
    end

    local roster, rosterError = safeValue(function()
        return readRoster()
    end)
    if rosterError ~= nil then
        error("Player-faction roster read failed: " .. rosterError)
    end
    if roster == nil then
        error("Player-faction roster returned nil")
    end

    local snapshots = {}
    for index = 1, MAX_ROSTER_ENTRIES do
        local row, rowError = safeValue(function()
            return roster[index]
        end)
        if rowError ~= nil then
            error("Could not read roster entry " .. tostring(index) .. ": " .. rowError)
        end
        if row == nil then
            table.sort(snapshots, function(left, right)
                return left.frameworkKey < right.frameworkKey
            end)
            return snapshots
        end
        table.insert(snapshots, copyRosterRow(row, index))
    end

    error("Player-faction roster exceeded the safety limit of " .. tostring(MAX_ROSTER_ENTRIES))
end

function Adapter.Observe()
    local config = NPCDepth.Config
    local activatedMods = readActivatedMods()
    local modActive = activatedMods.available
        and contains(activatedMods.ids, config.remnantsModId)

    local remnants = {
        modId = config.remnantsModId,
        workshopId = config.remnantsWorkshopId,
        active = modActive,
        manifest = readModMetadata(config.remnantsModId)
    }
    local frameworkGlobals = listFrameworkGlobals()

    return {
        gameBuild = readGameBuild(),
        activatedMods = activatedMods,
        remnants = remnants,
        frameworkGlobals = frameworkGlobals,
        profile = recognizeProfile(remnants, frameworkGlobals)
    }
end

