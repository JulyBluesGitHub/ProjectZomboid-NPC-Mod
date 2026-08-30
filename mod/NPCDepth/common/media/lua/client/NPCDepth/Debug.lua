NPCDepth = NPCDepth or {}

local Debug = {}
NPCDepth.Debug = Debug

local function text(value)
    if value == nil then
        return "unknown"
    end
    return tostring(value)
end

local function join(values)
    if values == nil or #values == 0 then
        return "none"
    end
    return table.concat(values, ", ")
end

function Debug.BuildCompatibilityLines(report)
    local lines = {
        "NPCDepth " .. text(report.npcDepthVersion) .. " compatibility report",
        "result=" .. text(report.result)
            .. " phase=" .. text(report.phase)
            .. " safeMode=" .. text(report.safeMode),
        "attempts=" .. text(report.attempts) .. "/" .. text(report.maxAttempts),
        "gameBuild=" .. text(report.gameBuild),
        "remnants.active=" .. text(report.remnants.active)
            .. " modId=" .. text(report.remnants.modId)
            .. " version=" .. text(report.remnants.modVersion)
            .. " versionDir=" .. text(report.remnants.versionDir),
        "npcfwReady=" .. text(report.npcfwReady)
            .. " profileStatus=" .. text(report.profileStatus)
            .. " profileId=" .. text(report.profileId),
        "npcfwGlobals=" .. join(report.npcfwGlobals)
    }

    table.insert(lines, "companionCount=" .. text(report.companionCount))
    for index = 1, #(report.companions or {}) do
        local companion = report.companions[index]
        table.insert(
            lines,
            "companion." .. tostring(index)
                .. "=frameworkKey=" .. text(companion.frameworkKey)
                .. " displayName=" .. text(companion.displayName)
                .. " assignment=" .. text(companion.assignment)
                .. " party=" .. text(companion.isPartyMember)
                .. " baseResident=" .. text(companion.isBaseResident)
                .. " live=" .. text(companion.isLive)
        )
    end

    local capabilityNames = NPCDepth.Config.capabilityNames
    for index = 1, #capabilityNames do
        local name = capabilityNames[index]
        table.insert(lines, "capability." .. name .. "=" .. text(report.capabilities[name]))
    end

    for index = 1, #report.diagnostics do
        local diagnostic = report.diagnostics[index]
        table.insert(
            lines,
            "diagnostic." .. text(diagnostic.severity)
                .. "." .. text(diagnostic.code)
                .. "=" .. text(diagnostic.message)
        )
    end

    return lines
end

function Debug.PrintCompatibilityReport(report)
    local value = report or NPCDepth.CompatibilityProbe.GetReport()
    local lines = Debug.BuildCompatibilityLines(value)
    for index = 1, #lines do
        print("[NPCDepth] " .. lines[index])
    end
    return value
end

