NPCDepth = NPCDepth or {}

-- Pure domain module. It must not reference ModData, getPlayer, Events, npcfw*
-- globals, UI classes, os, io, math.random, or wall-clock time. Everything it
-- needs arrives as plain Lua tables so the same code runs under the fixture
-- runner and inside Project Zomboid.
local State = {}
NPCDepth.State = State

local SUBJECT_STATUSES = { active = true, inactive = true }
local NPC_STATUSES = { alive = true, dead = true }
local INCIDENT_STATUSES = { pending = true, resolved = true }

local function isTable(value)
    return type(value) == "table"
end

local function isNonEmptyString(value)
    return type(value) == "string" and value ~= ""
end

local function isInteger(value)
    return type(value) == "number" and value == math.floor(value)
end

local function isOptionalWorldHours(value)
    return value == nil or (type(value) == "number" and value >= 0)
end

-- Traversal that affects output must be explicitly sorted; pairs() order is not
-- stable and validation errors are compared in tests.
local function sortedKeys(map)
    local keys = {}
    for key in pairs(map) do
        table.insert(keys, key)
    end
    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)
    return keys
end
State.SortedKeys = sortedKeys

local function prefixFor(kind)
    local prefixes = NPCDepth.Config.idPrefixes
    if not isTable(prefixes) then
        return nil
    end
    return prefixes[kind]
end

function State.IsNamespacedId(value, kind)
    if not isNonEmptyString(value) then
        return false
    end
    local prefix = prefixFor(kind)
    if prefix == nil then
        return false
    end
    return string.sub(value, 1, string.len(prefix)) == prefix
end

-- Build 42 ModData is not trusted to preserve numeric-looking string keys, so
-- every persisted key must be impossible to read as a number.
function State.IsCoercionSafeKey(value)
    return isNonEmptyString(value) and tonumber(value) == nil
end

function State.NewState()
    return {
        schemaVersion = NPCDepth.Config.schemaVersion,
        revision = 0,
        activeSubjectId = nil,
        subjectsById = {},
        npcsById = {},
        bindings = {
            npcByFrameworkKey = {},
            subjectByFrameworkKey = {}
        },
        tombstonesById = {},
        quarantineById = {},
        metadata = {
            idCounter = 0
        }
    }
end

function State.DeepCopy(value, seen)
    if not isTable(value) then
        return value
    end
    seen = seen or {}
    if seen[value] ~= nil then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[key] = State.DeepCopy(item, seen)
    end
    return copy
end

function State.Count(map)
    if not isTable(map) then
        return 0
    end
    local count = 0
    for _ in pairs(map) do
        count = count + 1
    end
    return count
end

-- IDs are minted from a persisted counter rather than math.random so the same
-- inputs always produce the same ids under test.
function State.MintId(state, kind, discriminator)
    local prefix = prefixFor(kind)
    if prefix == nil then
        return nil, "unknown_id_kind"
    end
    if not isTable(state) or not isTable(state.metadata) then
        return nil, "invalid_state"
    end
    local counter = state.metadata.idCounter
    if not isInteger(counter) or counter < 0 then
        return nil, "invalid_id_counter"
    end
    counter = counter + 1
    state.metadata.idCounter = counter

    local suffix = "anon"
    if isNonEmptyString(discriminator) then
        local cleaned = string.gsub(discriminator, "[^%w%-]", "")
        if cleaned ~= "" then
            suffix = cleaned
        end
    end
    return prefix .. tostring(counter) .. "-" .. suffix
end

function State.BumpRevision(state)
    if not isTable(state) or not isInteger(state.revision) then
        return nil, "invalid_state"
    end
    state.revision = state.revision + 1
    return state.revision
end

function State.GetSubject(state, subjectId)
    if not isTable(state) or not isTable(state.subjectsById) then
        return nil
    end
    return state.subjectsById[subjectId]
end

function State.GetNpc(state, npcId)
    if not isTable(state) or not isTable(state.npcsById) then
        return nil
    end
    return state.npcsById[npcId]
end

function State.GetSocial(state, npcId, subjectId)
    local npc = State.GetNpc(state, npcId)
    if npc == nil or not isTable(npc.socialBySubjectId) then
        return nil
    end
    return npc.socialBySubjectId[subjectId]
end

local function lookupBinding(state, mapName, frameworkKey)
    if not isTable(state) or not isTable(state.bindings) then
        return nil
    end
    local map = state.bindings[mapName]
    if not isTable(map) or not isNonEmptyString(frameworkKey) then
        return nil
    end
    return map[frameworkKey]
end

function State.FindNpcIdByFrameworkKey(state, frameworkKey)
    return lookupBinding(state, "npcByFrameworkKey", frameworkKey)
end

function State.FindSubjectIdByFrameworkKey(state, frameworkKey)
    return lookupBinding(state, "subjectByFrameworkKey", frameworkKey)
end

local function validateRelationships(relationships, path, errors)
    if not isTable(relationships) then
        table.insert(errors, path .. " must be a table")
        return
    end
    local bounds = NPCDepth.Config.relationshipBounds
    local allowed = {}
    local axes = NPCDepth.Config.relationshipAxes
    for index = 1, #axes do
        allowed[axes[index]] = true
    end

    local keys = sortedKeys(relationships)
    for index = 1, #keys do
        local axis = keys[index]
        local value = relationships[axis]
        local axisPath = path .. "." .. tostring(axis)
        if allowed[axis] == nil then
            table.insert(errors, axisPath .. " is not a known relationship axis")
        elseif not isInteger(value) then
            table.insert(errors, axisPath .. " must be an integer")
        elseif value < bounds.min or value > bounds.max then
            table.insert(
                errors,
                axisPath .. " must be within " .. tostring(bounds.min) .. ".." .. tostring(bounds.max)
            )
        end
    end
end

local function validateSemanticMap(map, path, errors, statuses)
    if not isTable(map) then
        table.insert(errors, path .. " must be a table")
        return
    end
    local keys = sortedKeys(map)
    for index = 1, #keys do
        local key = keys[index]
        local entryPath = path .. "." .. tostring(key)
        if type(key) ~= "string" then
            table.insert(errors, entryPath .. " key must be a string")
        elseif not State.IsCoercionSafeKey(key) then
            table.insert(errors, entryPath .. " key must not be numeric-looking")
        end
        local entry = map[key]
        if not isTable(entry) then
            table.insert(errors, entryPath .. " must be a table")
        elseif statuses ~= nil and statuses[entry.status] == nil then
            table.insert(errors, entryPath .. ".status is not a recognized status")
        end
    end
end

local function validateSocial(social, path, errors, state)
    if not isTable(social) then
        table.insert(errors, path .. " must be a table")
        return
    end
    local subjectIds = sortedKeys(social)
    for index = 1, #subjectIds do
        local subjectId = subjectIds[index]
        local socialPath = path .. "." .. tostring(subjectId)
        if not State.IsNamespacedId(subjectId, "subject") then
            table.insert(errors, socialPath .. " key must use the subject id prefix")
        elseif State.GetSubject(state, subjectId) == nil then
            table.insert(errors, socialPath .. " references a subject that does not exist")
        end

        local record = social[subjectId]
        if not isTable(record) then
            table.insert(errors, socialPath .. " must be a table")
        else
            validateRelationships(record.relationships, socialPath .. ".relationships", errors)
            validateSemanticMap(record.incidentsById, socialPath .. ".incidentsById", errors, INCIDENT_STATUSES)
            validateSemanticMap(record.memoriesById, socialPath .. ".memoriesById", errors, nil)
            if not isTable(record.knownTopics) then
                table.insert(errors, socialPath .. ".knownTopics must be a table")
            end
        end
    end
end

local function validateIdMap(map, path, errors, kind, statuses, onEntry)
    if not isTable(map) then
        table.insert(errors, path .. " must be a table")
        return
    end
    local keys = sortedKeys(map)
    for index = 1, #keys do
        local id = keys[index]
        local entryPath = path .. "." .. tostring(id)
        if type(id) ~= "string" then
            table.insert(errors, entryPath .. " key must be a string")
        elseif not State.IsNamespacedId(id, kind) then
            table.insert(errors, entryPath .. " key must use the " .. kind .. " id prefix")
        elseif not State.IsCoercionSafeKey(id) then
            table.insert(errors, entryPath .. " key must not be numeric-looking")
        end

        local entry = map[id]
        if not isTable(entry) then
            table.insert(errors, entryPath .. " must be a table")
        else
            if statuses[entry.status] == nil then
                table.insert(errors, entryPath .. ".status is not a recognized status")
            end
            if not isOptionalWorldHours(entry.createdAtWorldHours) then
                table.insert(errors, entryPath .. ".createdAtWorldHours must be a non-negative number")
            end
            if onEntry ~= nil then
                onEntry(id, entry, entryPath)
            end
        end
    end
end

local function validateBindingMap(state, mapName, path, errors, targetName, kind)
    local map = state.bindings[mapName]
    if not isTable(map) then
        table.insert(errors, path .. " must be a table")
        return
    end
    local targets = state[targetName]
    local keys = sortedKeys(map)
    for index = 1, #keys do
        local frameworkKey = keys[index]
        local entryPath = path .. "." .. tostring(frameworkKey)
        if type(frameworkKey) ~= "string" then
            table.insert(errors, entryPath .. " key must be a string")
        elseif not State.IsCoercionSafeKey(frameworkKey) then
            table.insert(errors, entryPath .. " key must not be numeric-looking")
        end

        local targetId = map[frameworkKey]
        if not State.IsNamespacedId(targetId, kind) then
            table.insert(errors, entryPath .. " must point at a " .. kind .. " id")
        elseif not isTable(targets) or targets[targetId] == nil then
            table.insert(errors, entryPath .. " points at an id that does not exist")
        end
    end
end

function State.Validate(state)
    if not isTable(state) then
        return false, { "state must be a table" }
    end

    local errors = {}

    if state.schemaVersion ~= NPCDepth.Config.schemaVersion then
        table.insert(errors, "schemaVersion must be " .. tostring(NPCDepth.Config.schemaVersion))
    end
    if not isInteger(state.revision) or state.revision < 0 then
        table.insert(errors, "revision must be a non-negative integer")
    end

    validateIdMap(state.subjectsById, "subjectsById", errors, "subject", SUBJECT_STATUSES, nil)
    validateIdMap(state.npcsById, "npcsById", errors, "npc", NPC_STATUSES, function(_, npc, npcPath)
        if npc.profileId ~= nil and not isNonEmptyString(npc.profileId) then
            table.insert(errors, npcPath .. ".profileId must be a non-empty string when present")
        end
        validateSocial(npc.socialBySubjectId, npcPath .. ".socialBySubjectId", errors, state)
    end)

    if not isTable(state.bindings) then
        table.insert(errors, "bindings must be a table")
    else
        validateBindingMap(state, "npcByFrameworkKey", "bindings.npcByFrameworkKey", errors, "npcsById", "npc")
        validateBindingMap(state, "subjectByFrameworkKey", "bindings.subjectByFrameworkKey", errors, "subjectsById", "subject")
    end

    -- Tombstoned ids are burned permanently; a live record sharing a tombstoned
    -- id means an id was recycled.
    if not isTable(state.tombstonesById) then
        table.insert(errors, "tombstonesById must be a table")
    else
        local keys = sortedKeys(state.tombstonesById)
        for index = 1, #keys do
            local id = keys[index]
            local live = (isTable(state.npcsById) and state.npcsById[id] ~= nil)
                or (isTable(state.subjectsById) and state.subjectsById[id] ~= nil)
            if live then
                table.insert(errors, "tombstonesById." .. tostring(id) .. " was recycled by a live record")
            end
        end
    end

    if not isTable(state.quarantineById) then
        table.insert(errors, "quarantineById must be a table")
    end

    if state.activeSubjectId ~= nil then
        if not State.IsNamespacedId(state.activeSubjectId, "subject") then
            table.insert(errors, "activeSubjectId must use the subject id prefix")
        elseif State.GetSubject(state, state.activeSubjectId) == nil then
            table.insert(errors, "activeSubjectId references a subject that does not exist")
        end
    end

    if not isTable(state.metadata) then
        table.insert(errors, "metadata must be a table")
    elseif not isInteger(state.metadata.idCounter) or state.metadata.idCounter < 0 then
        table.insert(errors, "metadata.idCounter must be a non-negative integer")
    end

    return #errors == 0, errors
end
