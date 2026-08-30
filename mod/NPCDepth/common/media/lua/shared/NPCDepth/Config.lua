NPCDepth = NPCDepth or {}

NPCDepth.Config = NPCDepth.Config or {
    version = "0.1.0-dev",
    remnantsModId = "ProjectRemnants",
    remnantsWorkshopId = "3738362476",
    probeIntervalTicks = 60,
    probeMaxAttempts = 20,
    circuitFailureLimit = 3,
    schemaVersion = 1,
    modDataKey = "NPCDepth",
    sentinelModDataKey = "NPCDepth_Sentinel",
    idPrefixes = {
        subject = "npcd:subject:",
        npc = "npcd:npc:"
    },
    relationshipBounds = {
        min = 0,
        max = 100
    },
    relationshipAxes = {
        "affection",
        "fear",
        "resentment",
        "respect",
        "trust"
    },
    capabilityNames = {
        "frameworkGlobals",
        "companionDiscovery",
        "stableNpcKey",
        "originalSubject",
        "npcModDataTag",
        "needsRead",
        "professionRead",
        "assignmentRead"
    }
}

