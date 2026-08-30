NPCDepth = NPCDepth or {}

local Probe = {}
NPCDepth.CompatibilityProbe = Probe

local state = nil

local function newCapabilities()
    local result = {}
    local names = NPCDepth.Config.capabilityNames
    for index = 1, #names do
        result[names[index]] = "unverified"
    end
    return result
end

local function newState(reason)
    return {
        phase = "idle",
        result = "not_started",
        safeMode = true,
        startReason = reason or "unspecified",
        tickCount = 0,
        attempts = 0,
        final = false,
        printedFinal = false,
        lastObservation = nil,
        companionSnapshots = {},
        capabilities = newCapabilities(),
        diagnostics = {},
        diagnosticKeys = {},
        circuits = {}
    }
end

local function addDiagnostic(code, severity, message)
    local key = tostring(code) .. ":" .. tostring(message)
    if state.diagnosticKeys[key] then
        return
    end

    state.diagnosticKeys[key] = true
    table.insert(state.diagnostics, {
        code = code,
        severity = severity,
        message = message
    })
end

local function finalize(result)
    state.phase = "complete"
    state.result = result
    state.safeMode = true
    state.final = true
end

local function validateCompanionSnapshots(value)
    if type(value) ~= "table" then
        return false
    end
    for index = 1, #value do
        local snapshot = value[index]
        if type(snapshot) ~= "table"
            or type(snapshot.frameworkKey) ~= "string"
            or snapshot.frameworkKey == ""
            or type(snapshot.displayName) ~= "string"
            or type(snapshot.assignment) ~= "string" then
            return false
        end
    end
    return true
end

local function observeOnce()
    state.attempts = state.attempts + 1

    local ok, observation = pcall(NPCDepth.ProjectRemnantsAdapter.Observe)
    if not ok or type(observation) ~= "table" then
        addDiagnostic(
            "adapter_observation_failed",
            "error",
            "The read-only Project Remnants observation failed: " .. tostring(observation)
        )
        if state.attempts >= NPCDepth.Config.probeMaxAttempts then
            finalize("agent_not_ready")
        end
        return
    end

    state.lastObservation = observation

    if not observation.activatedMods.available then
        addDiagnostic(
            "activated_mods_unavailable",
            "error",
            observation.activatedMods.error or "The active mod list could not be read."
        )
        if state.attempts >= NPCDepth.Config.probeMaxAttempts then
            finalize("agent_not_ready")
        end
        return
    end

    if not observation.remnants.active then
        addDiagnostic(
            "remnants_absent",
            "info",
            "Project Remnants is not active; NPCDepth remains diagnostic-only."
        )
        finalize("remnants_absent")
        return
    end

    local globals = observation.frameworkGlobals.names
    if #globals > 0 then
        state.capabilities.frameworkGlobals = "verified"

        local profile = observation.profile or { status = "unknown" }
        if profile.status == "verified" and profile.id ~= nil then
            local readOk, snapshots, readError = Probe.CallCapability(
                "companionDiscovery",
                function()
                    return NPCDepth.ProjectRemnantsAdapter.ReadCompanionSnapshots(profile.id)
                end,
                validateCompanionSnapshots
            )

            if readOk then
                state.companionSnapshots = snapshots
                state.capabilities.companionDiscovery = "verified"
                state.capabilities.assignmentRead = "verified"
                if #snapshots == 0 then
                    addDiagnostic(
                        "verified_profile_empty_roster",
                        "info",
                        "The verified roster profile loaded; recruit a companion to complete the in-game selection gate."
                    )
                else
                    addDiagnostic(
                        "verified_profile_roster_read",
                        "info",
                        "The verified roster profile returned " .. tostring(#snapshots) .. " recruited companion snapshot(s)."
                    )
                end
                finalize("profile_verified")
                return
            end

            addDiagnostic(
                "verified_profile_read_failed",
                "error",
                "The verified roster profile could not read a valid companion snapshot: " .. tostring(readError)
            )
            if state.attempts >= NPCDepth.Config.probeMaxAttempts then
                finalize("profile_read_failed")
            end
            return
        end

        addDiagnostic(
            "unknown_remnants_profile",
            "warning",
            "Framework globals are visible, but no read-only adapter profile has been verified for this Remnants build."
        )
        finalize("unknown_profile")
        return
    end

    if observation.frameworkGlobals.error ~= nil then
        addDiagnostic(
            "framework_global_scan_failed",
            "error",
            observation.frameworkGlobals.error
        )
    end

    if state.attempts >= NPCDepth.Config.probeMaxAttempts then
        addDiagnostic(
            "agent_not_ready",
            "error",
            "Project Remnants is active, but no npcfw* globals appeared during the bounded readiness window."
        )
        finalize("agent_not_ready")
    end
end

function Probe.Start(reason)
    state = newState(reason or "game-start")
    state.phase = "probing"
    state.result = "probing"
    observeOnce()
end

function Probe.Tick()
    if state == nil or state.final then
        return
    end

    state.tickCount = state.tickCount + 1
    if state.tickCount < NPCDepth.Config.probeIntervalTicks then
        return
    end

    state.tickCount = 0
    observeOnce()
end

function Probe.CallCapability(name, operation, validator)
    if state == nil then
        state = newState("capability-call-before-start")
    end

    local circuit = state.circuits[name]
    if circuit == nil then
        circuit = {
            failures = 0,
            open = false,
            loggedOpen = false
        }
        state.circuits[name] = circuit
    end

    if circuit.open then
        return false, nil, "circuit_open"
    end

    local ok, value = pcall(operation)
    local valid = ok
    local validationError = nil

    if valid and validator ~= nil then
        local validatorOk, validatorResult = pcall(validator, value)
        valid = validatorOk and validatorResult == true
        if not validatorOk then
            validationError = tostring(validatorResult)
        elseif not valid then
            validationError = "return_shape_rejected"
        end
    end

    if valid then
        circuit.failures = 0
        return true, value, nil
    end

    circuit.failures = circuit.failures + 1
    local failure = validationError or tostring(value)

    if circuit.failures >= NPCDepth.Config.circuitFailureLimit then
        circuit.open = true
        if not circuit.loggedOpen then
            circuit.loggedOpen = true
            addDiagnostic(
                "capability_circuit_open",
                "error",
                tostring(name) .. " was disabled for this session after repeated failures."
            )
        end
    end

    return false, nil, failure
end

function Probe.GetReport()
    if state == nil then
        state = newState("report-before-start")
    end

    local observation = state.lastObservation or {}
    local remnants = observation.remnants or {}
    local manifest = remnants.manifest or {}
    local frameworkGlobals = observation.frameworkGlobals or { names = {} }
    local profile = observation.profile or { status = "unavailable" }

    return {
        npcDepthVersion = NPCDepth.Config.version,
        phase = state.phase,
        result = state.result,
        safeMode = state.safeMode,
        final = state.final,
        startReason = state.startReason,
        attempts = state.attempts,
        maxAttempts = NPCDepth.Config.probeMaxAttempts,
        gameBuild = observation.gameBuild or "unknown",
        remnants = {
            modId = remnants.modId or NPCDepth.Config.remnantsModId,
            workshopId = remnants.workshopId or NPCDepth.Config.remnantsWorkshopId,
            active = remnants.active == true,
            name = manifest.name,
            modVersion = manifest.modVersion,
            versionDir = manifest.versionDir,
            manifestFound = manifest.found == true
        },
        npcfwReady = #frameworkGlobals.names > 0,
        npcfwGlobals = frameworkGlobals.names,
        profileStatus = profile.status,
        profileId = profile.id,
        companionCount = #state.companionSnapshots,
        companions = Probe.GetCompanionSnapshots(),
        capabilities = state.capabilities,
        circuits = state.circuits,
        diagnostics = state.diagnostics
    }
end


function Probe.GetCompanionSnapshots()
    if state == nil then
        return {}
    end

    local copies = {}
    for index = 1, #state.companionSnapshots do
        local source = state.companionSnapshots[index]
        copies[index] = {
            frameworkKey = source.frameworkKey,
            displayName = source.displayName,
            assignment = source.assignment,
            isPartyMember = source.isPartyMember,
            isBaseResident = source.isBaseResident,
            isLive = source.isLive,
            safehouseJob = source.safehouseJob,
            safehouseJobLabel = source.safehouseJobLabel,
            currentSafehouseTask = source.currentSafehouseTask
        }
    end
    return copies
end

function Probe.ConsumeFinalReportFlag()
    if state == nil or not state.final or state.printedFinal then
        return false
    end
    state.printedFinal = true
    return true
end

