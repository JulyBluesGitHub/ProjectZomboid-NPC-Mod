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
        getWorkshopID = function(self) return "3738362476" end,
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
