local activeModIds = {}
local gameStartHandler = nil
local tickHandler = nil

Events = {
    OnGameStart = {
        Add = function(handler)
            gameStartHandler = handler
        end
    },
    OnTick = {
        Add = function(handler)
            tickHandler = handler
        end
    }
}

getActivatedMods = function()
    return {
        size = function(self)
            return #activeModIds
        end,
        get = function(self, index)
            return activeModIds[index + 1]
        end
    }
end

getModInfoByID = function(modId)
    if modId ~= "ProjectRemnants" or #activeModIds == 0 then
        return nil
    end
    return {
        getName = function(self) return "Project Remnants Fixture" end,
        getModVersion = function(self) return "fixture-version" end,
        getVersionDir = function(self) return "42" end,
        getWorkshopID = function(self) return nil end,
        getDir = function(self) return "fixture" end
    }
end

getGameVersion = function()
    return "42.20.4-fixture"
end

NPCDepth.Runtime.Install()
assert(gameStartHandler ~= nil)
assert(tickHandler ~= nil)
gameStartHandler()
local absent = NPCDepth.CompatibilityProbe.GetReport()
assert(absent.final == true)
assert(absent.result == "remnants_absent")
assert(absent.safeMode == true)
assert(absent.gameBuild == "42.20.4-fixture")
assert(absent.remnants.active == false)

activeModIds = { "ProjectRemnants" }
NPCDepth.CompatibilityProbe.Start("fixture-agent-timeout")
for index = 1, NPCDepth.Config.probeIntervalTicks * NPCDepth.Config.probeMaxAttempts do
    NPCDepth.CompatibilityProbe.Tick()
end
local timeout = NPCDepth.CompatibilityProbe.GetReport()
assert(timeout.final == true)
assert(timeout.result == "agent_not_ready")
assert(timeout.attempts == NPCDepth.Config.probeMaxAttempts)
assert(timeout.remnants.active == true)
assert(timeout.npcfwReady == false)

npcfwFixtureSentinel = function()
    return true
end
NPCDepth.CompatibilityProbe.Start("fixture-unknown-profile")
local unknown = NPCDepth.CompatibilityProbe.GetReport()
assert(unknown.final == true)
assert(unknown.result == "unknown_profile")
assert(unknown.npcfwReady == true)
assert(unknown.capabilities.frameworkGlobals == "verified")
assert(unknown.remnants.modVersion == "fixture-version")

local rosterCalls = 0
npcfwGetAssignmentOf = function(npc)
    return "ACTIVE_PARTY"
end
npcfwGetPlayerFactionMemberIds = function()
    return { "npc-b", "npc-a" }
end
npcfwIsPlayerFactionMember = function(npc)
    return true
end
npcfwGetPlayerFactionRoster = function()
    rosterCalls = rosterCalls + 1
    return {
        {
            npcId = "npc-b",
            displayName = "Blake",
            assignment = "BASE_RESIDENT",
            isPartyMember = false,
            isBaseResident = true,
            isLive = true,
            safehouseJob = "GUARD",
            safehouseJobLabel = "Guard",
            currentSafehouseTask = "PATROL"
        },
        {
            npcId = "npc-a",
            displayName = "Alex",
            assignment = "ACTIVE_PARTY",
            isPartyMember = true,
            isBaseResident = false,
            isLive = true
        }
    }
end

NPCDepth.CompatibilityProbe.Start("fixture-verified-profile")
local verified = NPCDepth.CompatibilityProbe.GetReport()
assert(verified.final == true)
assert(verified.result == "profile_verified")
assert(verified.safeMode == true)
assert(verified.profileStatus == "verified")
assert(verified.profileId == "project-remnants-42-roster-20260829")
assert(verified.capabilities.frameworkGlobals == "verified")
assert(verified.capabilities.companionDiscovery == "verified")
assert(verified.capabilities.assignmentRead == "verified")
assert(verified.capabilities.stableNpcKey == "unverified")
assert(verified.companionCount == 2)
assert(verified.companions[1].frameworkKey == "npc-a")
assert(verified.companions[1].displayName == "Alex")
assert(verified.companions[1].isPartyMember == true)
assert(verified.companions[2].frameworkKey == "npc-b")
assert(verified.companions[2].isBaseResident == true)
assert(rosterCalls == 1)

local snapshots = NPCDepth.GetCompanionSnapshots()
assert(#snapshots == 2)
snapshots[1].displayName = "mutated fixture copy"
assert(NPCDepth.GetCompanionSnapshots()[1].displayName == "Alex")

local calls = 0
for index = 1, NPCDepth.Config.circuitFailureLimit do
    local ok = NPCDepth.CompatibilityProbe.CallCapability(
        "fixtureCapability",
        function()
            calls = calls + 1
            error("fixture failure")
        end
    )
    assert(ok == false)
end

local ok, value, failure = NPCDepth.CompatibilityProbe.CallCapability(
    "fixtureCapability",
    function()
        calls = calls + 1
        return "should not run"
    end
)
assert(ok == false)
assert(value == nil)
assert(failure == "circuit_open")
assert(calls == NPCDepth.Config.circuitFailureLimit)

local lines = NPCDepth.Debug.BuildCompatibilityLines(NPCDepth.CompatibilityProbe.GetReport())
assert(#lines > #NPCDepth.Config.capabilityNames)
