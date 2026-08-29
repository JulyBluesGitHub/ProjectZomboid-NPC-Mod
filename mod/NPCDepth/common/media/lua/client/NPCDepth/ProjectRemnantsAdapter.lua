NPCDepth = NPCDepth or {}

local Adapter = {}
NPCDepth.ProjectRemnantsAdapter = Adapter

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
        error = nil
    }

    local ok, scanError = pcall(function()
        for name, _ in pairs(_G) do
            if type(name) == "string" and string.sub(name, 1, 5) == "npcfw" then
                table.insert(result.names, name)
            end
        end
    end)

    if not ok then
        result.error = tostring(scanError)
    end
    table.sort(result.names)
    return result
end

function Adapter.Observe()
    local config = NPCDepth.Config
    local activatedMods = readActivatedMods()
    local modActive = activatedMods.available
        and contains(activatedMods.ids, config.remnantsModId)

    return {
        gameBuild = readGameBuild(),
        activatedMods = activatedMods,
        remnants = {
            modId = config.remnantsModId,
            workshopId = config.remnantsWorkshopId,
            active = modActive,
            manifest = readModMetadata(config.remnantsModId)
        },
        frameworkGlobals = listFrameworkGlobals()
    }
end

