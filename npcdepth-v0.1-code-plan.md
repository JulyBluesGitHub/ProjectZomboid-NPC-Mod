# NPCDepth v0.1 — Code Plan

Status: code-planning baseline, 2026-08-29  
Target: private single-player prototype; not yet a Workshop release  
Upstream: Project Zomboid Build 42.20.x + one pinned Project Remnants release

## 1. Definition of done

Version `0.1.0-dev` proves one complete tracer bullet:

1. NPCDepth detects a compatible Project Remnants runtime without calling it during Lua file load.
2. The player uses a proximity **Talk** interaction on one recruited companion.
3. That companion is durably bound to an NPCDepth-owned ID and the authored Maya profile.
4. Maya presents one inventory-aware shallow-cut incident with three meaningful choices.
5. The selected outcome consumes a real item when required and changes state exactly once.
6. The same Maya recalls the outcome naturally during a later medical-supply assessment after at least six in-game hours.
7. Identity, relationship state, incident state, and memory survive save/quit/reload.
8. A tiny separate local test content mod registers one dummy rule through the experimental API without editing core.

The release gate is person-specific persistence. If durable identity cannot be proven, Tier-0 diagnostic dialogue may run in-session, but v0.1 is not complete.

## 2. Adopted decisions

These remain defaults unless the user changes them:

- Single-player only.
- Relationships are between an NPC and a durable **relationship subject**, initially the original survivor.
- A successor after player death receives a new subject ID; old records remain historical.
- NPCDepth mints its own IDs. Only exact persisted evidence may auto-resolve them.
- Manual pinning assigns Maya to an already resolved NPC; it does not replace durable identity.
- Descriptive fingerprints never auto-link records.
- A rebindable proximity Talk action is the primary interaction; Iteration A leaves it unassigned until vanilla and the pinned Remnants build have both been checked for collisions. World right-click is an experiment.
- Store trust, respect, affection, fear, and resentment. V0.1 only changes and summarizes trust, respect, and resentment.
- Loyalty/commitment is derived later and is not a stored or player-visible v0.1 statistic.
- No NPCFW mutator calls in v0.1. The only possible write on a Remnants character is NPCDepth's own ID in character ModData, and only after the persistence spike proves that safe.
- One namespaced Global ModData envelope is authoritative.
- All authored text uses localization keys from the beginning.
- No live LLM dialogue.

## 3. Repository and mod layout

The workspace is the source repository. Development installation copies the mod into the user's local Zomboid mods directory; it never edits the Workshop copy.

```text
NPCDepth/
  README.md
  docs/
    compatibility.md
    state-schema.md
  tools/
    Collect-RemnantsBaseline.ps1
    Install-DevMod.ps1
  mod/
    NPCDepth/
      common/
        media/lua/shared/
          NPCDepth_Init.lua
          NPCDepth/
            Config.lua
            State.lua
            Migrations.lua
            Identity.lua
            Relationships.lua
            Registry.lua
            DialogueResolver.lua
            Effects.lua
            API.lua
          NPCDepthContent/
            MayaProfile.lua
            MayaIncident.lua
        media/lua/client/
          NPCDepth_ClientInit.lua
          NPCDepth/
            GlobalStore.lua
            ProjectRemnantsAdapter.lua
            CompatibilityProbe.lua
            Runtime.lua
            Interaction.lua
            DialoguePanel.lua
            Debug.lua
      42/
        mod.info
  test-content-mod/
    NPCDepthTestContent/
      common/media/lua/shared/
        NPCDepthTestContent_Init.lua
      42/
        mod.info
  tests/
    unit/
    fixtures/
    support/
      FakeAdapter.lua
      TestRunner.lua
```

`NPCDepth_Init.lua` creates the one allowed global namespace, `NPCDepth`, and explicitly requires shared modules in a fixed order. `NPCDepth_ClientInit.lua` loads the Project Zomboid shell. No module performs game work merely because it was required.

The precise `mod.info` dependency and version fields must be confirmed against the pinned Build 42 and Remnants manifests during the baseline spike.

## 4. Layer boundaries

### 4.1 Pure domain layer

The shared domain modules accept and return plain Lua tables. They must not reference:

- `getPlayer()`
- `Events`
- `ModData`
- `IsoPlayer` or other Java objects
- `npcfw*`
- UI classes
- wall-clock, filesystem, network, `os`, or `io`

Responsibilities:

| Module | Responsibility |
|---|---|
| `Config.lua` | Schema version, ID prefixes, relationship bounds, experimental API version |
| `State.lua` | New-state construction, validation, lookup helpers, revisions |
| `Migrations.lua` | Sequential pure state migrations built into replacement tables |
| `Identity.lua` | Resolve exact bindings, detect conflicts, quarantine; no fingerprint matching |
| `Relationships.lua` | Validate/clamp axes and produce qualitative summaries for supported combinations |
| `Registry.lua` | Register and validate profiles, episodes, localization references, IDs, and collisions |
| `DialogueResolver.lua` | Evaluate whitelisted conditions deterministically and return an explanation trace |
| `Effects.lua` | Validate commands and apply bounded, semantic state effects exactly once |
| `API.lua` | Experimental `NPCDepth.API.v0` registration and read-only snapshot functions |

### 4.2 Project Zomboid shell

| Module | Responsibility |
|---|---|
| `GlobalStore.lua` | Bind the validated envelope to `ModData.getOrCreate("NPCDepth")` after the world is ready |
| `ProjectRemnantsAdapter.lua` | The only module allowed to reference live Remnants objects or `npcfw*` globals |
| `CompatibilityProbe.lua` | Readiness, capability, version/profile, and circuit-breaker diagnostics |
| `Runtime.lua` | Orchestrate subject, target, snapshot, identity, resolver, transaction, and UI flows |
| `Interaction.lua` | Proximity target selection and configurable Talk action; experimental target-picker hook |
| `DialoguePanel.lua` | Accessible qualitative UI; no raw relationship numbers |
| `Debug.lua` | Compatibility report, state inspection, resolver trace, fixture controls |

The runtime may hold an ephemeral live-character handle for the duration of an interaction. That handle never enters persistent state or the domain layer.

## 5. Persistent state contract

All IDs are non-numeric, namespaced strings such as:

- `npcd:subject:<generated-id>`
- `npcd:npc:<generated-id>`
- `npcdepth.core.profile.maya`
- `npcdepth.core.incident.maya_shallow_cut`

Namespacing is mandatory. Whether numeric-looking string keys are actually coerced by Build 42 ModData remains a Gate 1 test rather than an assumed fact.

```lua
{
    schemaVersion = 1,
    revision = 0,

    activeSubjectId = "npcd:subject:...",
    subjectsById = {
        ["npcd:subject:..."] = {
            status = "active",
            createdAtWorldHours = 120.0,
            upstreamBinding = nil
        }
    },

    npcsById = {
        ["npcd:npc:..."] = {
            status = "alive",
            profileId = "npcdepth.core.profile.maya",
            createdAtWorldHours = 120.0,
            socialBySubjectId = {
                ["npcd:subject:..."] = {
                    relationships = {
                        trust = 12,
                        respect = 8,
                        affection = 3,
                        fear = 0,
                        resentment = 1
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
                            lastRecalledAtWorldHours = nil,
                            recallCount = 0,
                            tags = { "medical", "scarcity", "judgment" }
                        }
                    },
                    knownTopics = {}
                }
            }
        }
    },

    bindings = {
        npcByFrameworkKey = {},
        subjectByFrameworkKey = {}
    },
    tombstonesById = {},
    quarantineById = {},
    metadata = {}
}
```

Rules:

- Relationship values are bounded integers from `0` to `100`.
- Live needs, position, assignment, pain, inventory, and profession are never persisted as authoritative NPCDepth facts.
- NPC death tombstones the ID; IDs are never recycled.
- Memories and incidents are keyed by semantic content IDs, not invocation UUIDs.
- A once-only incident record is its own idempotency guard. A second callback observes `status = "resolved"` and performs no world or state effect.
- Future repeatable event families store bounded occurrence counts and last-applied times rather than an append-only token ledger.
- Migrations validate the old state, build a separate new table, validate it, and only then replace the root.

## 6. Identity and relationship-subject resolution

### 6.1 NPC identity

`Identity.ResolveNpc(state, evidence)` accepts plain evidence:

```lua
{
    persistedNpcDepthId = nil,
    frameworkKey = "opaque-string-or-nil",
    diagnosticHints = {
        displayName = "...",
        profession = "...",
        callsign = "..."
    }
}
```

Resolution order:

1. Exact persisted NPCDepth ID, cross-checked against state.
2. Exact framework key binding.
3. Otherwise `unresolved`.
4. Conflicting exact evidence returns `quarantined`.

Diagnostic hints may rank records in a manual relink screen, but never bind automatically. Manual relinking requires explicit confirmation and an audit entry; it does not merge histories.

Assigning Maya is a separate operation: after a durable NPC is resolved, a developer/UI action binds the Maya profile to that NPCDepth ID. Manual profile assignment is not identity evidence.

### 6.2 Relationship subject

The subject is the survivor Maya remembers, not necessarily the live object returned by `getPlayer()` during possession.

The adapter attempts to identify the original survivor through a proven Remnants capability. NPCDepth then binds that exact upstream evidence to a minted subject ID. Domain state always uses the subject ID.

If the original survivor dies and play continues as another character, v0.1 creates a new subject ID. The prior subject and social history remain readable but inactive.

If no durable subject can be resolved, persistent relationship effects are disabled alongside persistent NPC identity.

## 7. Adapter and compatibility contracts

### 7.1 Adapter surface

Proposed surface; exact implementation waits for Gate 0 evidence:

```lua
Adapter.ProbeCapabilities()              -- report
Adapter.IsReady()                        -- boolean, reason
Adapter.FindNearbyEligibleCompanions()   -- ephemeral handles
Adapter.IsEligibleCompanion(handle)      -- boolean, reason
Adapter.GetFrameworkNpcKey(handle)       -- string|nil, reason
Adapter.GetOriginalSubjectEvidence()     -- plain evidence|nil, reason
Adapter.ReadNpcDepthId(handle)            -- string|nil, reason
Adapter.WriteNpcDepthId(handle, id)       -- success, reason; optional capability
Adapter.ReadSnapshot(handle)              -- plain snapshot|nil, reason
Adapter.IsSameLiveTarget(handle)           -- boolean
```

`ReadSnapshot` returns only proven fields:

```lua
{
    frameworkKey = "...",
    displayName = "Maya Torres",
    recruited = true,
    alive = true,
    profession = "nurse",
    needs = {},
    assignment = nil,
    worldAgeHours = 126.0
}
```

The runtime augments this with player inventory facts such as:

```lua
inventoryTags = {
    sterileDressing = 1
}
```

For the installed Build 42 baseline, `sterileDressing` contains `Base.AlcoholBandage` (Bandage, Sterilized) and `Base.AlcoholRippedSheets` (Rag, Sterilized). Ordinary `Base.Bandage`, `Base.RippedSheets`, dirty dressings, and packed bundles do not count. Gate 0 re-verifies these IDs against the pinned target build. Content rules depend on the semantic inventory tag, not localized English names.

### 7.2 Capability report

```lua
{
    gameBuild = "observed",
    remnantsVersion = "observed-or-unknown",
    npcfwReady = true,
    profileStatus = "known" or "unknown",
    capabilities = {
        companionDiscovery = "verified",
        stableNpcKey = "verified",
        originalSubject = "unverified",
        npcModDataTag = "unverified",
        needsRead = "missing",
        professionRead = "verified",
        assignmentRead = "missing"
    },
    diagnostics = {}
}
```

Every adapter operation is wrapped with `pcall`, return-shape validation, and a per-capability failure counter. Repeated failures open that capability's circuit breaker for the current session and log one actionable error.

No write capability is probed by mutating gameplay at startup.

### 7.3 Lifecycle

1. Lua files load and register functions; no `npcfw*` calls occur.
2. After game start, `CompatibilityProbe` begins a bounded readiness check.
3. On success, the report is cached for the session.
4. The runtime re-probes when an actual control/subject change is detected through a supported hook or a low-frequency throttled check. It does not assume `OnCreatePlayer` fires for possession.
5. Unknown or malformed upstream behavior fails closed for persistent writes.

The author-contact request runs in parallel with Gate 0. A reply is not required for the diagnostic spike to pass, but publication should not claim a supported integration without coordination.

## 8. Declarative content contracts

### 8.1 Profile

```lua
NPCDepth.API.v0.RegisterProfile({
    id = "npcdepth.core.profile.maya",
    displayNameKey = "IGUI_NPCDepth_Maya_Name",
    backgroundKey = "IGUI_NPCDepth_Maya_Background",
    specializationTags = { "medical_assessment" },
    values = { "care", "triage", "resource_discipline" },
    sensitivities = {
        scarcityJudgment = 1.0,
        contempt = 1.0
    }
})
```

### 8.2 Episode

```lua
NPCDepth.API.v0.RegisterEpisode({
    id = "npcdepth.core.incident.maya_shallow_cut",
    profileId = "npcdepth.core.profile.maya",
    trigger = "talk",
    priority = 100,
    conditions = {
        all = {
            { op = "incidentStatus", value = "unstarted" },
            { op = "inventoryTagAtLeast", tag = "sterileDressing", value = 1 }
        }
    },
    choices = {
        -- localized labels, requirements, world effects, and state effects
    },
    fallbackId = "npcdepth.core.dialogue.maya_neutral"
})
```

Initial whitelisted condition operators:

- `all`, `any`, `not`
- `capabilityAvailable`
- `incidentStatus`
- `inventoryTagAtLeast`, `inventoryTagAtMost`
- `relationshipAtLeast`, `relationshipAtMost`
- `memoryExists`
- `elapsedWorldHoursAtLeast`

No arbitrary Lua predicates are accepted in external content.

### 8.3 Maya inventory-aware variants

The high-stakes wording is eligible only when `sterileDressing == 1`:

- **Give her the last sterile dressing:** trust `+4`, respect `-1`.
- **Save it for a serious wound:** respect `+3`.
- **You're not worth wasting supplies on:** trust `-4`, resentment `+6`.

If the player has more than one qualifying dressing, a lower-stakes variant says **Give her a sterile dressing** and does not claim scarcity or apply the respect penalty. With none, the item choice is disabled and the dialogue acknowledges the shortage.

Affection and fear remain in the schema but have no v0.1 producers and do not appear in the v0.1 qualitative summary.

### 8.4 Contextual recall

The delayed recall is part of a later medical-supply assessment rather than a direct “remember?” exchange. Conditions include:

- shallow-cut incident resolved
- at least six world hours elapsed
- relevant memory exists
- recall cooldown satisfied

The assessment contains branch-specific incidental detail—for example, Maya may refer to preserving sterile dressings for serious injuries because the player previously chose triage. This is both a player-facing memory signal and a deterministic resolver test.

Estimated content budget: 35–50 localized strings, including interaction labels, incident variants, responses, contextual recalls, fallbacks, relationship summaries, and diagnostic/accessibility text.

## 9. Choice transaction and idempotency

Content selection and effect execution are separate.

```text
resolve dialogue
    -> player selects choice
    -> build semantic command
    -> revalidate target, incident, requirements, and inventory
    -> execute whitelisted world effect
    -> commit pure state effects
    -> show response
```

For the bandage choice:

1. Confirm the incident is still unresolved.
2. Confirm the same live target remains eligible.
3. Confirm the player still owns one qualifying item.
4. Remove exactly one item through a normal Project Zomboid inventory operation.
5. Apply the semantic incident outcome, relationship deltas, and memory in one protected synchronous state commit.
6. If state commit fails, attempt to refund the item, keep the incident unresolved, trip the effect circuit breaker, and show a non-destructive error.

Applying the callback twice is safe because the second call finds the semantic incident already resolved. Opening the UI, selecting a disabled choice, cancelling a timed action, or recalling the memory never changes relationship state.

No item is written into Remnants-owned NPC inventory during v0.1; the dressing is treated as used on the shallow cut.

## 10. Interaction and UI

### Player interaction

- A configurable proximity Talk binding finds eligible recruited companions within a small tested range. Iteration A leaves the default unassigned: the installed Build 42.20.4 `keyBinding.lua` assigns numeric key `37` (LWJGL `K`) to **Display FPS**. Gate 0 inventories the pinned Remnants build before selecting a non-conflicting default.
- Zero candidates: show no dialogue action.
- One candidate: open that NPC's panel.
- Multiple candidates: display a small radial/list; never guess based only on distance.
- World right-click/target picking remains an experimental compatibility test.
- Party-panel integration waits for a supported Remnants hook.

The development hotkey may force incident state, advance test time, or inspect a selected NPC, but it does not count as proof of the player interaction.

### Dialogue panel

- Name and revealed background
- Observable, evidence-backed state only
- Qualitative relationship summary
- One recent impression when appropriate
- Localized choices with visible item requirements
- Scrollable response/transcript

Requirements:

- Keyboard/controller focus
- No timed choices
- Scalable text and wrapping
- At least 30% text expansion without clipping
- No meaning conveyed only by color
- Raw scores and resolver traces restricted to debug mode

## 11. Test strategy

### 11.1 Pure domain tests

- New v1 state validates.
- Unknown future schema refuses to load without mutation.
- Migration builds a replacement and preserves the original on failure.
- Relationship deltas clamp to documented bounds.
- Different subject IDs maintain independent social records for the same NPC.
- Exact persisted ID and exact framework binding resolve correctly.
- Conflicting exact evidence quarantines.
- Names/professions/appearance never auto-resolve identity.
- Duplicate profile/episode IDs fail with actionable diagnostics.
- Missing localization and invalid condition/effect operators fail registration.
- Identical snapshots always choose the same rule and explanation trace.
- Candidate traversal and tie-breaking are explicitly sorted.
- Inventory count `1`, `>1`, and `0` select truthful Maya variants.
- Applying a choice twice consumes/applies once.
- Recall produces no second relationship delta.
- Semantic incident/memory maps remain bounded.

### 11.2 Lua compatibility policy

The installed game JAR confirms a Kahlua-derived runtime. The domain core targets the Project Zomboid-compatible subset deliberately.

Initial static checks should flag:

- `os` and `io`
- reliance on `#table` for sparse tables
- output-affecting unsorted `pairs()` traversal
- global `math.random()` or wall-clock time
- direct Project Zomboid globals inside pure modules

Static checks do not prove compatibility. Gate 2 also runs fixtures inside Project Zomboid through the debug harness.

### 11.3 In-game lifecycle matrix

- Fresh save
- Normal save/quit/reload
- Cell unload/reload
- Possess Maya and return control
- Dismiss/re-recruit
- NPC death/corpse
- Original-survivor death/failover
- NPCDepth disable/re-enable
- Remnants disabled
- Remnants Lua present but Java agent missing/not ready
- Unknown Remnants compatibility profile
- Quit without saving correctly rolls back

Every case checks identity, subject binding, sentinel persistence, compatibility diagnostics, and absence of silent cross-links.

### 11.4 Slice acceptance

- Only one durably resolved, recruited Maya exposes the incident.
- Item-dependent choices reflect the actual item count.
- Exactly one item and one semantic outcome are recorded.
- Cancelled/stale actions change nothing.
- Save/reload restores the same Maya, subject, axes, incident, and memory.
- Contextual assessment recalls the correct outcome after six hours.
- Thirty repeated Talk interactions create no extra delta.
- Missing optional capabilities fall back rather than crash.
- Debug trace explains every selected and rejected rule.
- Pseudo-localized and keyboard-only UI remains usable.

## 12. Implementation sequence

### Iteration A — Baseline and diagnostic probe

1. Create repository/mod skeleton and local install tool.
2. Obtain one Project Remnants build and record exact manifests/file hashes outside gameplay code.
3. Inventory current `npcfw*` definitions/call sites and ModData behavior.
4. Implement load-safe readiness/capability reporting with circuit breakers.
5. Prove one recruited companion can be selected in-session.

Exit: Tier-0 compatibility report and session interaction work without persistent writes.

### Iteration B — Durable identity and subject

1. Implement schema v1, validation, revision, and Global ModData binding.
2. Implement NPC and relationship-subject IDs.
3. Run sentinel and full lifecycle matrix.
4. Implement conflict quarantine and debug-only manual relink.
5. Bind one resolved NPC to Maya without altering Remnants-owned identity.

Exit: the same NPC and original-survivor subject resolve after reload with zero fingerprint auto-links.

### Iteration C — Pure domain/content seam

1. Implement registry, relationships, resolver, effects, and explanation traces test-first.
2. Add Lua-subset checks and in-game fixture runner.
3. Register Maya profile and incident through `API.v0`.
4. Implement semantic incident/memory idempotency.

Exit: pure and in-game fixtures pass deterministically.

### Iteration D — Transactional Maya slice

1. Implement proximity interaction and dialogue panel.
2. Verify the `Base.AlcoholBandage` and `Base.AlcoholRippedSheets` mapping against the pinned target build.
3. Implement three inventory-aware choice variants and safe item consumption.
4. Implement relationship summary and contextual later assessment.
5. Pass save/reload, repeat-interaction, accessibility, and failure tests.

Exit: the v0.1 player loop is complete on a disposable save.

### Iteration E — Extensibility proof

1. Register one dummy external profile/dialogue from `test-content-mod`.
2. Test dependency absence, load order, duplicate IDs, and compatibility failure.
3. Freeze only the proven `NPCDepth.API.v0` surface for the private prototype.

Exit: no second production content is hard-coded into core.

## 13. First implementation tickets

1. **V01-001 — Development skeleton and safe local installer**
2. **V01-002 — Remnants baseline collector and compatibility report format**
3. **V01-003 — Load-safe Project Remnants readiness/capability probe**
4. **V01-004 — Proximity companion discovery spike**
5. **V01-005 — Schema v1, validation, and Global ModData sentinels**
6. **V01-006 — NPC and relationship-subject identity lifecycle matrix**
7. **V01-007 — Pure registry/resolver/effects test harness**
8. **V01-008 — Maya profile and shallow-cut content definitions**
9. **V01-009 — Transactional choice action and semantic idempotency**
10. **V01-010 — Dialogue panel, qualitative summaries, and contextual recall**
11. **V01-011 — Save/reload and compatibility failure QA pass**
12. **V01-012 — External test content mod and API seam proof**

Tickets should be implemented in order through V01-006. After identity evidence exists, V01-007 through V01-012 may be refined based on the actual adapter surface.

## 14. Resolved defaults and later checkpoints

No user decision blocks Iteration A. The five earlier questions are resolved as follows:

1. **Relationship ownership:** relationships belong to the original survivor's durable subject ID. If play continues after that survivor dies, the successor receives a new subject ID; prior records remain historical.
2. **Talk binding:** leave the Iteration A action unassigned, then choose a rebindable default after the pinned Remnants build is installed. Local Build 42.20.4 already binds numeric key `37` (LWJGL `K`) to **Display FPS**, so `K` is rejected.
3. **Manual relinking:** developer/debug-only in v0.1. It is too easy for a player-facing recovery tool to transfer one person's memories to another NPC. Reconsider only after real identity failures are observed.
4. **Sterile dressing tag:** include `Base.AlcoholBandage` and `Base.AlcoholRippedSheets`. Exclude ordinary clean bandages/rags, dirty dressings, and bundles. Re-verify item scripts at the pinned build.
5. **Author coordination:** prepare the request now and send it through the Remnants Discord before public Workshop release. The request asks only for a stable read-only integration contract and add-on guidance. Waiting for a reply does not block private Iteration A–D work.

Later evidence checkpoints are handled automatically by the plan:

- After Remnants is installed, select a default that is unbound in both vanilla and Remnants and keep the action rebindable.
- If no stable NPC/subject identity exists, stop durable content work and retain only Tier-0 diagnostics.
- If the Remnants author provides a supported API, replace discovered internals behind the adapter without changing the domain layer.

## 15. Iteration A implementation status

Started 2026-08-29:

- **V01-001 complete:** Build 42 development skeleton, recoverable local installer, and local development copy under `Zomboid/mods/NPCDepth`.
- **V01-002 complete:** the read-only baseline pins Project Zomboid app build `24909800`, records Remnants manifests and JAR hashes, confirms the Workshop Java agent configuration, and verifies both sterile-dressing declarations.
- **V01-003 complete for Iteration A:** load-safe bounded readiness, safe-mode results, profile recognition, diagnostics, and per-capability circuit breakers. Kahlua fixtures cover Remnants absent, agent timeout, unknown and verified profiles, defensive roster snapshots, and circuit opening.
- **V01-004 in progress:** shipped Remnants Lua verifies `npcfwGetPlayerFactionRoster()` as a read-only recruited-companion source. NPCDepth now copies its scalar rows behind profile `project-remnants-42-roster-20260829`; one disposable save/reload identity test remains.

Next: select one recruited companion in a disposable session, record its snapshot, save/reload, and confirm whether the same `npcId` survives. Do not begin relationship persistence or the Maya UI until that identity evidence is recorded.
