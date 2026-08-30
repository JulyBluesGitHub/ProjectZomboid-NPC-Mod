NPCDepth = NPCDepth or {}

local Runtime = {
    installed = false
}
NPCDepth.Runtime = Runtime

function Runtime.OnGameStart()
    NPCDepth.CompatibilityProbe.Start("game-start")
    if NPCDepth.CompatibilityProbe.ConsumeFinalReportFlag() then
        NPCDepth.Debug.PrintCompatibilityReport()
    end
end

function Runtime.OnTick()
    NPCDepth.CompatibilityProbe.Tick()
    if NPCDepth.CompatibilityProbe.ConsumeFinalReportFlag() then
        NPCDepth.Debug.PrintCompatibilityReport()
    end
end

function Runtime.Install()
    if Runtime.installed then
        return
    end
    Runtime.installed = true
    Events.OnGameStart.Add(Runtime.OnGameStart)
    Events.OnTick.Add(Runtime.OnTick)
end

function NPCDepth.GetCompatibilityReport()
    return NPCDepth.CompatibilityProbe.GetReport()
end

function NPCDepth.PrintCompatibilityReport()
    return NPCDepth.Debug.PrintCompatibilityReport()
end

function NPCDepth.GetCompanionSnapshots()
    return NPCDepth.CompatibilityProbe.GetCompanionSnapshots()
end

function NPCDepth.ReprobeCompatibility(reason)
    NPCDepth.CompatibilityProbe.Start(reason or "manual-debug-request")
    if NPCDepth.CompatibilityProbe.ConsumeFinalReportFlag() then
        NPCDepth.Debug.PrintCompatibilityReport()
    end
    return NPCDepth.CompatibilityProbe.GetReport()
end

