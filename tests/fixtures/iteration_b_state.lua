-- Iteration B / V01-005 fixtures: schema v1 construction and validation,
-- migration refusal semantics, and Global ModData sentinels.

local State = NPCDepth.State
local Migrations = NPCDepth.Migrations
local Store = NPCDepth.GlobalStore

local function hasError(errors, needle)
    for index = 1, #errors do
        if string.find(errors[index], needle, 1, true) ~= nil then
            return true
        end
    end
    return false
end

local function newSocialRecord()
    return {
        relationships = {
            affection = 3,
            fear = 0,
            resentment = 1,
            respect = 8,
            trust = 12
        },
        incidentsById = {
            ["npcdepth.core.incident.maya_shallow_cut"] = {
                status = "resolved",
                choiceId = "save_for_serious_wound",
                resolvedAtWorldHours = 126.0
            }
        },
        memoriesById = {
            ["npcdepth.core.memory.maya_shallow_cut"] = {
                outcome = "approved_triage",
                createdAtWorldHours = 126.0,
                recallCount = 0
            }
        },
        knownTopics = {}
    }
end

-- Builds a populated, valid v1 state plus the ids it minted.
local function newPopulatedState()
    local state = State.NewState()
    local subjectId = State.MintId(state, "subject", "survivor")
    local npcId = State.MintId(state, "npc", "cameron")

    state.subjectsById[subjectId] = {
        status = "active",
        createdAtWorldHours = 120.0,
        upstreamBinding = nil
    }
    state.npcsById[npcId] = {
        status = "alive",
        profileId = "npcdepth.core.profile.maya",
        createdAtWorldHours = 120.0,
        socialBySubjectId = {
            [subjectId] = newSocialRecord()
        }
    }
    state.bindings.npcByFrameworkKey["2c9c8ae2-a825-4b3f-bf49-56141b310592"] = npcId
    state.bindings.subjectByFrameworkKey["survivor-alpha"] = subjectId
    state.activeSubjectId = subjectId
    return state, subjectId, npcId
end

-- === Schema v1 construction and validation =================================

local fresh = State.NewState()
local ok, errors = State.Validate(fresh)
assert(ok == true)
assert(#errors == 0)
assert(fresh.schemaVersion == NPCDepth.Config.schemaVersion)
assert(fresh.revision == 0)
assert(fresh.metadata.idCounter == 0)

-- Ids are minted from a counter, are namespaced, and can never be read as a
-- number by a coercing ModData bridge.
local npcId = State.MintId(fresh, "npc", "npc-a")
assert(npcId == "npcd:npc:1-npc-a")
assert(State.IsNamespacedId(npcId, "npc") == true)
assert(State.IsNamespacedId(npcId, "subject") == false)
assert(State.IsCoercionSafeKey(npcId) == true)

local subjectId = State.MintId(fresh, "subject", "survivor one!")
assert(subjectId == "npcd:subject:2-survivorone")
assert(fresh.metadata.idCounter == 2)

local unknownId, unknownReason = State.MintId(fresh, "not-a-kind", "x")
assert(unknownId == nil)
assert(unknownReason == "unknown_id_kind")

assert(State.IsCoercionSafeKey("12345") == false)
assert(State.IsCoercionSafeKey("") == false)

local populated, populatedSubjectId, populatedNpcId = newPopulatedState()
ok, errors = State.Validate(populated)
assert(ok == true, errors[1])
assert(State.GetNpc(populated, populatedNpcId) ~= nil)
assert(State.GetSubject(populated, populatedSubjectId) ~= nil)
assert(State.GetSocial(populated, populatedNpcId, populatedSubjectId) ~= nil)
assert(State.FindNpcIdByFrameworkKey(populated, "2c9c8ae2-a825-4b3f-bf49-56141b310592") == populatedNpcId)
assert(State.FindSubjectIdByFrameworkKey(populated, "survivor-alpha") == populatedSubjectId)
assert(State.FindNpcIdByFrameworkKey(populated, "no-such-key") == nil)

assert(State.BumpRevision(populated) == 1)
assert(populated.revision == 1)

-- Relationship bounds, axes, and integer-ness.
local outOfBounds = newPopulatedState()
outOfBounds.npcsById[populatedNpcId].socialBySubjectId[populatedSubjectId].relationships.trust = 101
ok, errors = State.Validate(outOfBounds)
assert(ok == false)
assert(hasError(errors, "must be within 0..100"))

local unknownAxis = newPopulatedState()
unknownAxis.npcsById[populatedNpcId].socialBySubjectId[populatedSubjectId].relationships.loyalty = 5
ok, errors = State.Validate(unknownAxis)
assert(ok == false)
assert(hasError(errors, "is not a known relationship axis"))

local fractional = newPopulatedState()
fractional.npcsById[populatedNpcId].socialBySubjectId[populatedSubjectId].relationships.respect = 8.5
ok, errors = State.Validate(fractional)
assert(ok == false)
assert(hasError(errors, "must be an integer"))

-- A numeric-looking framework key is rejected before it can be silently
-- coerced by ModData.
local numericKey = newPopulatedState()
numericKey.bindings.npcByFrameworkKey["12345"] = populatedNpcId
ok, errors = State.Validate(numericKey)
assert(ok == false)
assert(hasError(errors, "must not be numeric-looking"))

local danglingBinding = newPopulatedState()
danglingBinding.bindings.npcByFrameworkKey["ghost-key"] = "npcd:npc:999-missing"
ok, errors = State.Validate(danglingBinding)
assert(ok == false)
assert(hasError(errors, "points at an id that does not exist"))

local danglingSocial = newPopulatedState()
danglingSocial.npcsById[populatedNpcId].socialBySubjectId["npcd:subject:999-missing"] = newSocialRecord()
ok, errors = State.Validate(danglingSocial)
assert(ok == false)
assert(hasError(errors, "references a subject that does not exist"))

-- Ids are never recycled once tombstoned.
local recycled = newPopulatedState()
recycled.tombstonesById[populatedNpcId] = { status = "dead" }
ok, errors = State.Validate(recycled)
assert(ok == false)
assert(hasError(errors, "was recycled by a live record"))

local badActive = newPopulatedState()
badActive.activeSubjectId = "npcd:subject:999-missing"
ok, errors = State.Validate(badActive)
assert(ok == false)
assert(hasError(errors, "references a subject that does not exist"))

local badStatus = newPopulatedState()
badStatus.npcsById[populatedNpcId].status = "undead"
ok, errors = State.Validate(badStatus)
assert(ok == false)
assert(hasError(errors, "status is not a recognized status"))

-- Two subjects keep independent social records for the same NPC.
local twoSubjects, subjectA, npcForBoth = newPopulatedState()
local subjectB = State.MintId(twoSubjects, "subject", "successor")
twoSubjects.subjectsById[subjectB] = { status = "active", createdAtWorldHours = 300.0 }
local recordB = newSocialRecord()
recordB.relationships.trust = 44
twoSubjects.npcsById[npcForBoth].socialBySubjectId[subjectB] = recordB
ok, errors = State.Validate(twoSubjects)
assert(ok == true)
assert(State.GetSocial(twoSubjects, npcForBoth, subjectA).relationships.trust == 12)
assert(State.GetSocial(twoSubjects, npcForBoth, subjectB).relationships.trust == 44)

-- DeepCopy is independent of its source.
local copy = State.DeepCopy(populated)
copy.npcsById[populatedNpcId].socialBySubjectId[populatedSubjectId].relationships.trust = 99
assert(populated.npcsById[populatedNpcId].socialBySubjectId[populatedSubjectId].relationships.trust == 12)

-- === Migration and load refusal ============================================

local status, loaded, reason = Migrations.Load(nil)
assert(status == "created")
assert(reason == "empty_store")
assert(loaded.schemaVersion == NPCDepth.Config.schemaVersion)

status, loaded, reason = Migrations.Load({})
assert(status == "created")

local current = newPopulatedState()
status, loaded, reason = Migrations.Load(current)
assert(status == "loaded")
assert(reason == "current_schema")
assert(loaded == current)

-- An unknown future schema refuses to load and is left byte-for-byte alone.
local future = { schemaVersion = 99, mysteryField = "keep me" }
status, loaded, reason = Migrations.Load(future)
assert(status == "refused")
assert(reason == "future_schema")
assert(loaded == nil)
assert(future.mysteryField == "keep me")
assert(future.schemaVersion == 99)
assert(State.Count(future) == 2)

local invalid = newPopulatedState()
invalid.revision = -1
status, loaded, reason = Migrations.Load(invalid)
assert(status == "refused")
assert(reason == "invalid_state")
assert(loaded == nil)

status, loaded, reason = Migrations.Load({ schemaVersion = 0 })
assert(status == "refused")
assert(reason == "no_migration_path")

status, loaded, reason = Migrations.Load({ notAVersion = true })
assert(status == "refused")
assert(reason == "missing_schema_version")

-- A migration builds a separate replacement and leaves the original intact.
Migrations.steps[0] = function(old)
    local built = State.NewState()
    built.metadata.idCounter = 7
    return built
end
local legacy = { schemaVersion = 0, marker = "original" }
status, loaded, reason = Migrations.Load(legacy)
assert(status == "migrated")
assert(loaded.metadata.idCounter == 7)
assert(loaded.schemaVersion == NPCDepth.Config.schemaVersion)
assert(legacy.marker == "original")
assert(legacy.schemaVersion == 0)

Migrations.steps[0] = function(old)
    return { schemaVersion = 0 }
end
status, loaded, reason = Migrations.Load({ schemaVersion = 0 })
assert(status == "refused")
assert(reason == "migration_did_not_advance")

Migrations.steps[0] = function(old)
    error("fixture migration failure")
end
status, loaded, reason = Migrations.Load({ schemaVersion = 0 })
assert(status == "refused")
assert(reason == "migration_failed")
Migrations.steps[0] = nil

-- === Global ModData sentinels ==============================================

-- Simulates a ModData bridge that coerces numeric-looking string keys, which is
-- exactly the Build 42 behaviour the plan refused to assume.
local function coerceKeys(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] ~= nil then
        return seen[value]
    end
    local out = {}
    seen[value] = out
    for key, item in pairs(value) do
        local newKey = key
        if type(key) == "string" and tonumber(key) ~= nil then
            newKey = tonumber(key)
        end
        out[newKey] = coerceKeys(item, seen)
    end
    return out
end

-- Every read goes through the transform so nothing can pass by holding on to
-- the same table reference.
local function newFakeModData(transform)
    local disk = {}
    local api = {}
    api.getOrCreate = function(key)
        local current = disk[key]
        if current == nil then
            current = {}
            disk[key] = current
            return current
        end
        disk[key] = transform(current)
        return disk[key]
    end
    return api, disk
end

-- ModData missing entirely.
ModData = nil
Store.BeginSession()
local unavailable = Store.Bind("fixture-no-moddata")
assert(unavailable.status == "unavailable")
assert(unavailable.persistence == false)
assert(Store.IsPersistenceEnabled() == false)
assert(Store.GetState() == nil)
assert(Store.GetStateSnapshot() == nil)

-- A faithful store: round-trip verifies, cross-session is pending until a
-- second session reads back what the first one wrote.
local faithfulApi, faithfulDisk = newFakeModData(function(value)
    return State.DeepCopy(value)
end)
ModData = faithfulApi

Store.BeginSession()
local first = Store.Bind("fixture-session-one")
assert(first.status == "bound")
assert(first.persistence == true)
assert(first.sentinel.roundTrip == "verified")
assert(first.sentinel.crossSession == "pending_reload")
assert(first.sentinel.writeCount == 1)
assert(#first.sentinel.failures == 0)
assert(first.stateStatus == "created")
assert(first.schemaVersion == NPCDepth.Config.schemaVersion)
assert(first.revision == 0)
assert(Store.IsPersistenceEnabled() == true)

-- The envelope really was written into the ModData table, not into a local.
assert(faithfulDisk["NPCDepth"] ~= nil)
assert(faithfulDisk["NPCDepth"].schemaVersion == NPCDepth.Config.schemaVersion)
assert(faithfulDisk["NPCDepth"].metadata.idCounter == 0)
assert(faithfulDisk["NPCDepth_Sentinel"].payload ~= nil)

-- A rebind inside the same session does not claim cross-session evidence.
local rebind = Store.Bind("fixture-rebind")
assert(rebind.sentinel.crossSession == "not_evaluated")
assert(rebind.sentinel.roundTrip == "verified")

-- Second session over the same disk: the payload came back from storage.
Store.BeginSession()
local second = Store.Bind("fixture-session-two")
assert(second.status == "bound")
assert(second.sentinel.crossSession == "verified")
assert(second.sentinel.roundTrip == "verified")
assert(second.sentinel.writeCount == 3)
assert(second.stateStatus == "loaded")
assert(second.stateReason == "current_schema")
assert(second.persistence == true)

-- Snapshots are copies; mutating one cannot corrupt persisted state.
local snapshot = Store.GetStateSnapshot()
assert(snapshot ~= nil)
snapshot.revision = 4242
assert(Store.GetStateSnapshot().revision == 0)

-- A coercing store fails the sentinel, so durable writes stay disabled even
-- though the envelope still binds and reports.
local coercingApi = newFakeModData(coerceKeys)
ModData = coercingApi

Store.BeginSession()
local degraded = Store.Bind("fixture-coercing-store")
assert(degraded.status == "degraded")
assert(degraded.persistence == false)
assert(degraded.sentinel.roundTrip == "failed")
assert(#degraded.sentinel.failures > 0)
assert(hasError(degraded.sentinel.failures, "numeric-looking key was coerced to number"))
assert(degraded.stateStatus == "created")
assert(Store.IsPersistenceEnabled() == false)

-- A store holding a future schema refuses without touching what is there.
local futureApi, futureDisk = newFakeModData(function(value)
    return State.DeepCopy(value)
end)
ModData = futureApi
futureDisk["NPCDepth"] = { schemaVersion = 99, mysteryField = "keep me" }

Store.BeginSession()
local refused = Store.Bind("fixture-future-schema")
assert(refused.status == "refused")
assert(refused.stateStatus == "refused")
assert(refused.stateReason == "future_schema")
assert(refused.persistence == false)
assert(Store.GetState() == nil)
assert(futureDisk["NPCDepth"].mysteryField == "keep me")
assert(futureDisk["NPCDepth"].schemaVersion == 99)

-- Report rendering must survive every status, including the unbound case.
local storeLines = NPCDepth.Debug.BuildStoreLines(refused)
assert(#storeLines >= 4)
assert(#NPCDepth.Debug.BuildStoreLines(nil) == 1)

-- Runtime exposes the debug seams the console needs.
assert(type(NPCDepth.GetStoreReport) == "function")
assert(type(NPCDepth.GetStateSnapshot) == "function")
assert(type(NPCDepth.RebindStore) == "function")
assert(type(NPCDepth.PrintStoreReport) == "function")

ModData = nil
