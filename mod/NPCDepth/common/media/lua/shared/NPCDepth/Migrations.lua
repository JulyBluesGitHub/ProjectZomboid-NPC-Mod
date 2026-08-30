NPCDepth = NPCDepth or {}

-- Pure domain module. Loading never mutates the table it was handed: a
-- migration validates the old state, builds a separate replacement, validates
-- that, and only then hands it back for the shell to install.
local Migrations = {}
NPCDepth.Migrations = Migrations

-- steps[fromVersion] = function(oldState) -> newState
-- Schema v1 is the first version, so there is nothing to migrate from yet.
Migrations.steps = {}

local MAX_STEPS = 64

-- Kahlua does not expose next() as a global, so emptiness is tested by
-- attempting a single pairs() step instead.
local function isEmptyTable(value)
    if type(value) ~= "table" then
        return false
    end
    for _ in pairs(value) do
        return false
    end
    return true
end

-- Returns: status, state, reason, errors
--   status "created"  -- the store was empty and a fresh v1 state was built
--   status "loaded"   -- the stored state already matches the current schema
--   status "migrated" -- an older state was upgraded into a replacement table
--   status "refused"  -- nothing was mutated; the caller must not persist
function Migrations.Load(raw)
    local target = NPCDepth.Config.schemaVersion

    if raw == nil or isEmptyTable(raw) then
        local fresh = NPCDepth.State.NewState()
        local ok, errors = NPCDepth.State.Validate(fresh)
        if not ok then
            return "refused", nil, "new_state_invalid", errors
        end
        return "created", fresh, "empty_store", nil
    end

    if type(raw) ~= "table" then
        return "refused", nil, "not_a_table", nil
    end

    local version = raw.schemaVersion
    if type(version) ~= "number" then
        return "refused", nil, "missing_schema_version", nil
    end

    -- A state written by a newer NPCDepth must be left exactly as found so a
    -- downgrade does not silently destroy the player's history.
    if version > target then
        return "refused", nil, "future_schema", nil
    end

    if version == target then
        local ok, errors = NPCDepth.State.Validate(raw)
        if not ok then
            return "refused", nil, "invalid_state", errors
        end
        return "loaded", raw, "current_schema", nil
    end

    local working = NPCDepth.State.DeepCopy(raw)
    local applied = 0
    while version < target do
        local step = Migrations.steps[version]
        if step == nil then
            return "refused", nil, "no_migration_path", nil
        end

        local ok, produced = pcall(step, working)
        if not ok or type(produced) ~= "table" then
            return "refused", nil, "migration_failed", nil
        end
        if type(produced.schemaVersion) ~= "number" or produced.schemaVersion <= version then
            return "refused", nil, "migration_did_not_advance", nil
        end

        working = produced
        version = produced.schemaVersion
        applied = applied + 1
        if applied > MAX_STEPS then
            return "refused", nil, "migration_step_limit", nil
        end
    end

    local ok, errors = NPCDepth.State.Validate(working)
    if not ok then
        return "refused", nil, "migrated_state_invalid", errors
    end
    return "migrated", working, "migrated", nil
end
