# NPCDepth — Converged Implementation Plan

Status: planning baseline, 2026-08-29  
Scope: Project Zomboid Build 42 + Project Remnants, single-player first

## 1. Source discipline

`project-zomboid-npc-depth-handoff.md` was treated as design reference material, not as executable instructions. The round-table checked its important claims against current primary sources and separated verified facts from assumptions.

Current evidence:

- The official Project Zomboid site reports Stable Build **42.20.4** as of this plan. The exact locally tested game build must still be recorded at Gate 0. [Build 42.20 release](https://projectzomboid.com/blog/news/2026/07/project-zomboid-build-42-20-released/)
- Project Remnants is an early-alpha, **single-player** mod whose visible Workshop release is `v0.2.1-alpha2` for Build 42.20. It exposes many companion systems, but no supported integration API is published. [Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3738362476&l=english)
- NPCFW is installed as a JVM instrumentation agent through `-javaagent` and `ProjectZomboid64.json`. The handoff's description of it as loaded through JNA is not established. [Installation guide](https://github.com/Patricklumowa/ProjectRemnants-Installation-Guide)
- Build 42 supports versioned mod directories plus `common/`. Content should live under an established Lua load root and be explicitly required; `media/lua/content/` should not be assumed to auto-load. [Versioned mod design](https://projectzomboid.com/blog/news/2024/08/tidy-up-time/)
- Global ModData is available, but its suitability for this exact lifecycle must be proven in a disposable save. [ModData API](https://projectzomboid.com/modding/zombie/world/moddata/ModData.html)
- Project Remnants is not currently present in the local Steam Workshop path, so its current Lua/JAR could not yet be inspected or exercised.

Unverified until Gate 0/1:

- The current list, signatures, and behavior of `npcfw*` globals.
- A durable NPC identity across recruitment, possession, streaming, dismissal, death, and reload.
- Whether third-party fields in an NPC's ModData survive NPCFW reconstruction.
- A supported way to extend Remnants' party UI or dialogue.
- Which companion need, assignment, profession, health, and recruitment reads are safe.

## 2. Round-table outcome

Participants:

- **Codex/moderator:** evidence-first scope and synthesis.
- **Claude/skeptical architect:** challenged brittle identity, read-only adapter design, incomplete lifecycle tests, and vague determinism.
- **Integration specialist:** checked current Project Zomboid and Remnants facts and designed the runtime spike.
- **Platform architect:** shaped the pure-Lua core, persistence, registry, migration, and compatibility boundaries.
- **Gameplay/content designer:** shaped the smallest interaction that proves perceived human depth.

Consensus:

1. Do not start with a general platform or polished dialogue UI. First prove safe companion selection, durable identity, and persistence ownership.
2. NPCDepth owns its own `npcDepthId`. Exact persisted bindings may resolve it; descriptive fingerprints may only suggest candidates for diagnostics or explicit manual relinking. They must never auto-bind.
3. Persistent NPCDepth state should use one namespaced, validated global ModData envelope if the spike confirms it. Do not anchor the platform to whichever character `getPlayer()` returns during possession.
4. Keep Project Remnants behind a thin capability-based adapter. Domain code receives plain Lua snapshots, never live Java/NPCFW objects.
5. The initial release is single-player only. No multiplayer architecture is promised while the upstream dependency is SP-only.
6. Relationship-changing effects must be transactional and idempotent. Opening dialogue, repeating a greeting, or recalling a memory never grants relationship progress.
7. Store trust, respect, affection, fear, and resentment independently. Derive loyalty/commitment from those plus salient memories until loyalty has real gameplay events of its own.
8. The first authored character is Maya, a pinned named instance backed by a reusable `former_nurse` profile. Other nurses must not inherit Maya's personal facts.
9. A session-only Tier-0 mode may help diagnose compatibility and test UI, but it does not satisfy the durable-memory release gate.
10. Do not decompile NPCFW.jar by default. Inspect shipped Lua and runtime behavior, then ask the Remnants author for a supported minimal integration contract before publication.

Open disagreement to test rather than guess:

- Interaction surface: the gameplay seat prefers world right-click; the integration seat considers a proximity hotkey/small radial less coupled. Gate 0 will test proximity interaction, world target picking, and any documented party-panel hook. The default prototype should use a proximity interaction unless world targeting proves reliable.

## 3. Product thesis and first proof

The first proof is not “an NPC can display dialogue.” It is:

> One specific NPC remembers one costly, meaningful interaction after time passes and after save/reload, and the memory changes how that same NPC speaks.

### Maya vertical slice

Maya Torres is a former ER nurse. NPCDepth creates a small authored incident: Maya has a shallow cut from scavenging and wants a clean dressing. This is explicitly an NPCDepth narrative incident, not a claim that Project Remnants' health simulation contains a dirty wound. Framework health/pain may enrich the dialogue later if a safe capability exists.

The player has one sterile bandage and receives three choices:

1. **Give her the last sterile bandage.** Consume the real item only after the transfer/timed action succeeds. Trust `+4`, affection `+2`, respect `-1`: Maya is grateful but questions using the last dressing on a minor cut.
2. **Save it for a serious wound.** Consume nothing. Respect `+3`: Maya agrees with the triage decision.
3. **“You're not worth wasting supplies on.”** Consume nothing. Trust `-4`, resentment `+6`.

After at least six in-game hours and across save/reload, Maya recalls the selected outcome. She then gives a nurse-specific medical-supply assessment. Her expertise remains available in every branch; relationship changes tone and willingness, not her competence.

Player-facing UI shows qualitative language such as “grateful, but questions your judgment.” Raw values and rule traces exist only in diagnostics.

Content budget:

- 1 pinned Maya instance and 1 reusable nurse profile
- 1 three-choice incident
- 3 immediate responses and 3 delayed recalls
- 1 nurse-specific inventory assessment
- 1 neutral fallback interaction
- roughly 25–35 localized strings

Explicitly postponed: romance, procedural biographies, live AI dialogue, personal quests, NPC-to-NPC relationship graphs, multiplayer, alternate frameworks, autonomous job bonuses, combat obedience/desertion, large content packs, and a full debug UI.

## 4. Lean architecture

```text
PZ callbacks / interaction UI
            |
    runtime coordinator
       |           |
Remnants adapter   persistence store
       |           |
       +---- pure Lua domain core ----+
             state, rules, migrations
                      |
              validated registries
```

### Adapter contract

Initial operations:

- `ProbeCapabilities()`
- `IsReady()`
- `ListEligibleCompanions()` or the smallest proven equivalent
- `GetPersistentFrameworkKey(character)`
- `ReadSnapshot(character)` returning plain fields such as display name, membership, profession, need, and assignment
- `TryReadNpcDepthId(character)`
- `TryWriteNpcDepthId(character, id)` only if a safe legitimate test proves third-party NPC ModData persists

The MVP performs no upstream gameplay mutation through NPCFW. Inventory consumption should use a normal Project Zomboid action and be confirmed before NPCDepth records the outcome.

Every adapter operation uses `pcall`, validates return shapes, and has a per-capability failure counter. Repeated failures disable only that capability for the current session and emit one actionable diagnostic.

Capability policy:

- Missing stable identity: disable durable personal state.
- Missing needs/assignment/health: omit those conditions and use authored fallbacks.
- Missing/malformed effect capability: fail closed; do not apply a partial outcome.
- Unknown upstream version/profile: independent Tier-0 UI may work, but NPCFW-dependent persistent writes remain disabled until a smoke test passes.

### Identity policy

Resolution order:

1. Exact persisted `npcDepthId` on the NPC, cross-checked against global state.
2. Exact proven framework key in `bindingsByFrameworkKey`.
3. Explicit player/debug relink after confirmation.
4. Otherwise unresolved/quarantined.

Name, profession, callsign, appearance, party slot, position, and spawn details are candidate hints only. A false automatic match is worse than an unresolved record.

### State envelope

```lua
{
    schemaVersion = 1,
    revision = 0,
    relationshipSubjectPolicy = "undecided",
    npcsById = {},
    bindingsByFrameworkKey = {},
    tombstonesById = {},
    quarantineById = {},
    metadata = {}
}
```

Each NPC record owns:

- `profileId`
- stored relationship axes: trust, respect, affection, fear, resentment
- memories, known topics, namespaced flags
- dialogue/incident state and cooldowns
- processed effect/idempotency tokens
- timestamps based on world age, not wall-clock time

Loyalty/commitment is derived initially. Current need, pain, position, assignment, and inventory are live snapshot data and should not be duplicated into persistent NPCDepth state.

Use pure sequential migrations that build and validate a replacement table before swapping the root. Keep a monotonic revision. Do not add an in-envelope checksum or continuously duplicated shadow copy in the MVP; both complicate unordered Lua state without providing an independent recovery location.

### Deterministic content system

- Namespaced IDs, registration-time validation, and duplicate rejection.
- Declarative, whitelisted conditions; no arbitrary Lua predicates in public content initially.
- Capture one immutable context snapshot per resolution.
- Sort every output-affecting traversal.
- Select by explicit priority descending, then fully qualified ID ascending.
- No randomness in the MVP.
- Return an explanation trace showing why rules were accepted or rejected.
- Apply effects separately from selection, with a stable idempotency key.

Recommended Build 42 layout:

```text
NPCDepth/
  common/media/lua/shared/
    NPCDepth_Init.lua
    NPCDepth/
      State.lua
      Migrations.lua
      Registry.lua
      DialogueResolver.lua
      Relationships.lua
      API.lua
    NPCDepthContent/
      MayaProfile.lua
      MayaDialogue.lua
  common/media/lua/client/
    NPCDepth_ClientInit.lua
    NPCDepth/
      ProjectRemnantsAdapter.lua
      Runtime.lua
      Interaction.lua
      DialoguePanel.lua
      Debug.lua
  42/
    mod.info
  tests/
    unit/
    fixtures/
```

Bootstrap files explicitly require modules in a known order. Module files avoid load-time side effects.

## 5. Phases and gates

### Gate 0 — Reproducible integration lab

Deliverables:

- Install the current Project Remnants Workshop item into a disposable test setup without editing its Workshop copy.
- Record Project Zomboid version/build ID, Remnants version/manifest, Lua source manifest, and available NPCFW.jar locations/hashes.
- Detect divergent Workshop/game-root JAR copies, but do not make a hash the API contract.
- Inventory current `npcfw*` definitions/call sites and runtime globals; call only read-only candidates through `pcall`.
- Verify dependency metadata, load order, agent readiness, and bounded timeout behavior.
- Produce a compatibility report for Remnants absent, Lua enabled but agent missing, agent not ready, and unknown version.
- Ask the Remnants author which minimum identity, membership, and snapshot calls they are willing to support.

Pass: one recruited companion can be identified in-session without save damage, and invalid configurations enter safe mode with a useful diagnostic.

### Gate 1 — Interaction and lifecycle identity spike

Deliverables:

- Test proximity hotkey/radial, world target/right-click, and any supported party-panel hook; record accuracy and coupling.
- Mint an NPCDepth ID and test exact binding candidates.
- Write sentinels to NPC ModData, original-player ModData, and global ModData.
- Test save/quit/reload, cell unload/reload, possession, dismiss/re-recruit, NPC death/corpse, original-survivor death/failover, player death/new character, NPCDepth disable/re-enable, load-order faults, and a Remnants version/profile mismatch.
- Confirm quitting without saving correctly rolls back to the last game save.
- Quarantine conflicts; prove zero automatic fingerprint cross-links.

Pass: one meaningful record returns to the same logical NPC after reload. If this fails, only Tier-0 diagnostics continue; content production stops.

### Gate 2 — Pure Lua core and test harness

Deliverables:

- State validation, clamped relationship changes, migrations, and fake adapter.
- Registry validation and duplicate rejection.
- Deterministic resolver plus explanation trace.
- Idempotent choice/effect application.
- Recorded snapshot fixtures and an offline runner compatible with Project Zomboid's Lua semantics.

Pass: identical fixture sequences always produce identical decisions/state; applying the same effect twice changes state once; invalid content and unsupported future state versions fail safely.

### Gate 3 — Transactional interaction

Deliverables:

- One player interaction surface plus a developer-only debug hotkey.
- Inventory requirement and confirmed bandage consumption.
- Target revalidation when the dialogue completes.
- Stale/cancelled actions consume nothing and change no relationship state.
- Qualitative player UI and numeric/debug trace.

Pass: every branch is mutually exclusive, repeat-safe, keyboard-usable, and safely closes if the target becomes invalid.

### Gate 4 — Durable Maya slice

Deliverables:

- Pin one eligible real NPC to Maya for the save.
- Resolve the shallow-cut incident exactly once.
- Persist axes, one memory, incident state, cooldown, and idempotency token.
- Recall the correct branch after six in-game hours and after reload.
- Show nurse-specific assessment with safe fallback when optional framework data is unavailable.

Pass: Maya remains the same logical person across lifecycle tests; thirty repeated Talk interactions create no extra relationship delta; player UI contains no raw scores; debug trace explains every selected line.

### Gate 5 — Extensibility proof and API v1

Deliverables:

- A separate local test content mod registers the next dummy profile/dialogue without editing core.
- Validate load order, IDs, localization keys, conditions/effects, collisions, and absence/incompatibility behavior.
- Freeze only the smallest API and event payloads actually proven by this pack.

Pass: the test pack works solely through the public registration surface. Only then begin a second production NPC or dialogue pack.

### Later gate — First organic world event

Ingest one meaningful Project Remnants transition, such as fulfilling a promise or completing a shared task. Prove transition-based detection, deduplication across update ticks/reload, bounded memory growth, and a visible later consequence.

## 6. Cross-cutting acceptance rules

- SP-only manifests and documentation.
- No edits to the Workshop copy; use a separate development mod and disposable saves.
- No NPCFW mutator calls in the first slice.
- Namespaced global state; disabling NPCDepth leaves inert data and does not break Remnants.
- NPC death tombstones a record; IDs are never recycled.
- One-time events rely on semantic idempotency, not cooldown alone.
- Future repeatable positive event families use diminishing returns and per-day caps; repeated harm is aggregated into escalating memories rather than silently erased.
- No timed dialogue choices, no meaning by color alone, scalable/wrapping text, localization keys, and pseudo-localization before content expansion.
- No per-tick full-registry scans. Performance budgets are measured in the spike before an update strategy is chosen.

## 7. Decisions needed from the user

Recommended defaults are shown first.

1. **Release target:** single-player-first and developed privately against disposable saves, with Workshop publication only after author contact and Gate 5.
2. **Relationship subject after player death:** relationships belong to the original survivor; a successor can view historical records but starts a new relationship subject.
3. **Identity failure:** durable person-specific identity is a hard release gate; Tier-0 session dialogue remains developer diagnostics only.
4. **First interaction:** use a proximity Talk key/small radial for the prototype; test world right-click and adopt it only if target selection is reliable. Use a party-panel action only with a supported Remnants hook.
5. **Maya and choice tone:** one named Maya per save, backed by a reusable nurse profile; the first decision has mixed consequences so generosity can raise trust while weak triage lowers respect.

## 8. Immediate next action

After the user confirms or changes the five decisions above, execute Gate 0 only. The first coding artifact should be a diagnostic compatibility probe, not the final dialogue engine.

## 9. Round-table turn — Claude/skeptical architect, 2026-08-29

Reviewed by the moderator seat. Accepted and modified recommendations are incorporated into `npcdepth-v0.1-code-plan.md`; this section remains as the original discussion record rather than an authoritative implementation contract.

Source note: `project-zomboid-npc-depth-handoff.md` is 0 bytes on disk. Any seat citing it as design reference is citing an empty file. It may still be recoverable from the git objects in this folder and should be recovered before the next round.

Spot-check of the plan's factual claims: 42.20 is the stable line, Project Remnants is SP-only alpha, and the installation guide describes `-javaagent` rather than JNA. Section 1 holds up.

### 9.1 Resolve `relationshipSubjectPolicy` now, at schemaVersion 1

This is the cheapest decision today and the most expensive one at schemaVersion 3. Possession is the failure case: if the player takes over Maya, `getPlayer()` *is* Maya, and every naive "player" read inverts.

Mint a `subjectId` on first run, store it in the envelope, and key relationship axes by `(subjectId, npcId)`. Never re-derive the subject from the live player object. Decision #2 in section 7 then falls out for free, and the successor-after-death case becomes a new `subjectId` with old records intact rather than a migration. Worth doing even though the MVP has exactly one subject.

### 9.2 Make manual pinning the primary identity path, not the fallback

Gate 1 currently blocks on the framework persisting a stable key, while Gate 4 treats "pin one eligible real NPC to Maya" as setup. Invert that.

The slice needs one durable person. A player-initiated pin plus an explicit re-confirm prompt is rule 3 of the existing identity resolution order — a legitimate identity source, not a workaround. If a stable framework key exists, it becomes an optimization that skips the re-confirm. This removes the single largest schedule risk in the plan: the content pipeline's dependence on a third-party alpha's persistence behavior.

### 9.3 Bound idempotency tokens at MVP, not at the later gate

`processed effect/idempotency tokens` is an append-only per-NPC set in the current design, and "bounded memory growth" appears only at the later organic-event gate. Make tokens semantic rather than per-invocation — `incidentId:choiceId` — so the set is bounded by content size. A UUID-per-application token set inside save-scoped ModData is a slow leak into the player's save file.

### 9.4 Serialization and load-order hazards

- Global ModData round-trips through the save and numeric-looking table keys can be coerced. Prefix every ID with a non-numeric namespace (`npcd:0001`) so `npcsById` keys survive the round trip.
- Keep all state save-scoped. Nothing written to a Lua-side file outside the save, or save-scumming desyncs the mod from the world — the exact failure that makes a memory mod feel broken.
- B42 auto-loads alphabetically within a load root and gives no cross-mod ordering guarantee. The adapter must never touch `npcfw*` at file-load time: probe on an event with a bounded readiness poll, cache per session, re-probe on `OnCreatePlayer` to survive possession.

### 9.5 Gate 2 needs a language subset, not just a runner

PZ's Lua is Kahlua2 on the JVM, not stock 5.1 — `string` library edges, `#` on tables with holes, no `os`/`io`. A harness that passes under LuaJIT and fails in-game is worse than no harness. Add a lint to Gate 2 that fails on forbidden globals and on known-divergent constructs, and write the domain core to that subset deliberately.

### 9.6 Maya slice: one credibility fix, one content fix, one budget correction

**Credibility.** "Give her the last sterile bandage" is authored fiction the player falsifies by opening their inventory and seeing twelve. The first thing the mod does is then lie about the world, which undercuts the premise that this NPC perceives reality. Gate the mixed-consequence variant on a declarative condition (`playerItemCount(sterile bandage) <= 1`) and author a lower-stakes variant otherwise. Bonus: this gives Gate 2's whitelisted-condition system a production caller instead of shipping with none.

**Content.** Fold the memory into the assessment rather than authoring a separate recall branch. Three delayed-recall lines are indistinguishable from a state variable picking line B; the player cannot experience that as memory. What reads as memory is unprompted specificity in a context that is not about the memory — Maya, mid medical-supply assessment, noting she will not recommend burning sterile dressings on scratches, because you did. Same string budget, materially stronger proof of the section 3 thesis.

**Budget.** Five independent axes require qualitative summary text spanning a five-dimensional space; 25–35 strings does not cover it. Either author the slice against the two axes that have real producers (trust and respect — fear has none in the MVP), keeping the other three in the schema but out of the UI, or raise the budget honestly.

### 9.7 Position on the open disagreement (section 2)

Side with the proximity hotkey, on a compatibility argument rather than an ergonomic one. World right-click means `OnFillWorldObjectContextMenu`, where Remnants almost certainly already has entries — that is an ordering and collision surface owned by an alpha mod that will keep changing. The proximity key is a surface NPCDepth owns entirely. This holds regardless of how well world target-picking tests at Gate 0.

### 9.8 Process note on Gate 0

"Ask the Remnants author for a supported contract" currently sits inside a blocking gate. Alpha authors reply on their own schedule or not at all. Send that message now, in parallel, and do not let Gate 0's pass condition depend on the reply.
