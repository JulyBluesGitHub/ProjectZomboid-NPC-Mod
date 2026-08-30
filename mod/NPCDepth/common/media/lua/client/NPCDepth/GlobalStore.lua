NPCDepth = NPCDepth or {}

-- Project Zomboid shell module. This is the ONLY module allowed to reference
-- ModData. It binds the validated envelope to the global store and proves, with
-- sentinels rather than assumption, that Build 42 ModData round-trips the key
-- and value shapes schema v1 depends on.
local Store = {}
NPCDepth.GlobalStore = Store

local state = nil
local report = nil
local sessionBindCount = 0

local function newReport(reason)
    return {
        reason = reason or "unspecified",
        status = "unavailable",
        sentinel = {
            roundTrip = "unknown",
            crossSession = "unknown",
            writeCount = 0,
            failures = {}
        },
        stateStatus = "unbound",
        stateReason = nil,
        schemaVersion = nil,
        revision = nil,
        persistence = false,
        errors = {}
    }
end

-- The sentinel deliberately includes every shape schema v1 relies on. A
-- numeric-looking string key is the one Build 42 behaviour the plan refused to
-- assume, so it is checked first and hardest.
local function buildSentinelPayload()
    return {
        marker = "npcdepth-sentinel",
        numericLookingKeys = { ["12345"] = "string-key" },
        namespacedKeys = { ["npcd:npc:sentinel"] = "namespaced-key" },
        booleanTrue = true,
        booleanFalse = false,
        integerValue = 42,
        negativeValue = -7,
        floatValue = 0.5,
        nested = { level2 = { level3 = "deep" } },
        denseArray = { "a", "b", "c" },
        emptyTable = {}
    }
end

local function verifySentinelPayload(payload, failures)
    if type(payload) ~= "table" then
        table.insert(failures, "payload is not a table")
        return false
    end

    if payload.marker ~= "npcdepth-sentinel" then
        table.insert(failures, "marker did not survive")
    end

    -- Key-type fidelity: a coerced key turns "12345" into 12345 and silently
    -- breaks every id map in the schema.
    if type(payload.numericLookingKeys) ~= "table" then
        table.insert(failures, "numericLookingKeys is not a table")
    else
        local found = false
        for key, value in pairs(payload.numericLookingKeys) do
            found = true
            if type(key) ~= "string" then
                table.insert(failures, "numeric-looking key was coerced to " .. type(key))
            elseif key ~= "12345" then
                table.insert(failures, "numeric-looking key changed to " .. tostring(key))
            end
            if value ~= "string-key" then
                table.insert(failures, "numeric-looking key lost its value")
            end
        end
        if not found then
            table.insert(failures, "numeric-looking key disappeared")
        end
    end

    if type(payload.namespacedKeys) ~= "table"
        or payload.namespacedKeys["npcd:npc:sentinel"] ~= "namespaced-key" then
        table.insert(failures, "namespaced key did not survive")
    end

    if payload.booleanTrue ~= true or payload.booleanFalse ~= false then
        table.insert(failures, "boolean values did not survive")
    end
    if payload.integerValue ~= 42 or payload.negativeValue ~= -7 then
        table.insert(failures, "integer values did not survive")
    end
    if payload.floatValue ~= 0.5 then
        table.insert(failures, "float value did not survive")
    end

    if type(payload.nested) ~= "table"
        or type(payload.nested.level2) ~= "table"
        or payload.nested.level2.level3 ~= "deep" then
        table.insert(failures, "nested tables did not survive")
    end

    if type(payload.denseArray) ~= "table"
        or #payload.denseArray ~= 3
        or payload.denseArray[1] ~= "a"
        or payload.denseArray[3] ~= "c" then
        table.insert(failures, "dense array did not survive")
    end

    if type(payload.emptyTable) ~= "table" then
        table.insert(failures, "empty table did not survive")
    end

    return #failures == 0
end

local function getOrCreate(key)
    local ok, value = pcall(function()
        return ModData.getOrCreate(key)
    end)
    if not ok or type(value) ~= "table" then
        return nil
    end
    return value
end

local function runSentinel(result)
    local sentinel = result.sentinel
    local key = NPCDepth.Config.sentinelModDataKey

    local existing = getOrCreate(key)
    if existing == nil then
        sentinel.roundTrip = "failed"
        sentinel.crossSession = "failed"
        table.insert(sentinel.failures, "sentinel store could not be opened")
        return false
    end

    -- Only the first bind of a session can distinguish a payload that came back
    -- from disk from one this session just wrote.
    if sessionBindCount == 1 then
        if existing.payload == nil then
            sentinel.crossSession = "pending_reload"
        else
            local crossFailures = {}
            if verifySentinelPayload(existing.payload, crossFailures) then
                sentinel.crossSession = "verified"
            else
                sentinel.crossSession = "failed"
                for index = 1, #crossFailures do
                    table.insert(sentinel.failures, "cross-session: " .. crossFailures[index])
                end
            end
        end
    else
        sentinel.crossSession = "not_evaluated"
    end

    local previousWrites = existing.writeCount
    if type(previousWrites) ~= "number" then
        previousWrites = 0
    end

    existing.writeCount = previousWrites + 1
    existing.payload = buildSentinelPayload()

    -- Re-open the store so the value comes back through the ModData bridge
    -- rather than out of the table we still hold a reference to.
    local readBack = getOrCreate(key)
    if readBack == nil then
        sentinel.roundTrip = "failed"
        table.insert(sentinel.failures, "sentinel store could not be re-opened")
        return false
    end

    sentinel.writeCount = readBack.writeCount
    local roundTripFailures = {}
    if verifySentinelPayload(readBack.payload, roundTripFailures) then
        sentinel.roundTrip = "verified"
        return true
    end

    sentinel.roundTrip = "failed"
    for index = 1, #roundTripFailures do
        table.insert(sentinel.failures, "round-trip: " .. roundTripFailures[index])
    end
    return false
end

-- Replace the contents of the live ModData table in place. Reassigning a local
-- would not persist: the table handed back by getOrCreate is the one Project
-- Zomboid serializes.
local function adoptInto(target, source)
    local existingKeys = NPCDepth.State.SortedKeys(target)
    for index = 1, #existingKeys do
        target[existingKeys[index]] = nil
    end
    local sourceKeys = NPCDepth.State.SortedKeys(source)
    for index = 1, #sourceKeys do
        local key = sourceKeys[index]
        target[key] = source[key]
    end
    return target
end

function Store.BeginSession()
    state = nil
    report = nil
    sessionBindCount = 0
end

function Store.Bind(reason)
    local result = newReport(reason)
    sessionBindCount = sessionBindCount + 1

    if ModData == nil or type(ModData.getOrCreate) ~= "function" then
        result.status = "unavailable"
        table.insert(result.errors, "ModData is unavailable")
        state = nil
        report = result
        return result
    end

    local sentinelOk = runSentinel(result)

    local envelope = getOrCreate(NPCDepth.Config.modDataKey)
    if envelope == nil then
        result.status = "failed"
        result.stateStatus = "unbound"
        table.insert(result.errors, "state store could not be opened")
        state = nil
        report = result
        return result
    end

    local status, loaded, stateReason, errors = NPCDepth.Migrations.Load(envelope)
    result.stateStatus = status
    result.stateReason = stateReason
    if errors ~= nil then
        for index = 1, #errors do
            table.insert(result.errors, errors[index])
        end
    end

    if status == "refused" then
        result.status = "refused"
        result.persistence = false
        state = nil
        report = result
        return result
    end

    if status == "loaded" then
        state = envelope
    else
        state = adoptInto(envelope, loaded)
    end

    result.schemaVersion = state.schemaVersion
    result.revision = state.revision

    -- Durable writes stay disabled unless the store demonstrably preserves the
    -- shapes schema v1 needs.
    if sentinelOk then
        result.status = "bound"
        result.persistence = true
    else
        result.status = "degraded"
        result.persistence = false
    end

    report = result
    return result
end

function Store.GetReport()
    if report == nil then
        return nil
    end
    return NPCDepth.State.DeepCopy(report)
end

function Store.IsPersistenceEnabled()
    return report ~= nil and report.persistence == true
end

-- Live handle for future NPCDepth writes. Callers outside the shell should use
-- GetStateSnapshot so they cannot mutate persisted state by accident.
function Store.GetState()
    return state
end

function Store.GetStateSnapshot()
    if state == nil then
        return nil
    end
    return NPCDepth.State.DeepCopy(state)
end
