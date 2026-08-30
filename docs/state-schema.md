# NPCDepth persistent state — schema v1

Schema v1 is the durable envelope NPCDepth keeps in Project Zomboid's Global ModData. It landed with V01-005 (Iteration B, step 1). No gameplay content writes to it yet: V01-005 delivers the store, its validation, and the evidence that Build 42 preserves the shapes the schema depends on.

## Layout

One namespaced envelope is authoritative, bound to `ModData.getOrCreate("NPCDepth")`:

```lua
{
    schemaVersion = 1,
    revision = 0,
    activeSubjectId = nil,          -- or an existing subject id
    subjectsById = {},              -- ["npcd:subject:<n>-<tag>"] = { status, createdAtWorldHours }
    npcsById = {},                  -- ["npcd:npc:<n>-<tag>"] = { status, profileId, socialBySubjectId }
    bindings = {
        npcByFrameworkKey = {},     -- Remnants npcId -> NPCDepth npc id
        subjectByFrameworkKey = {}  -- upstream survivor evidence -> subject id
    },
    tombstonesById = {},
    quarantineById = {},
    metadata = { idCounter = 0 }
}
```

Each `socialBySubjectId` record holds `relationships`, `incidentsById`, `memoriesById`, and `knownTopics`. Social history is stored per subject, so two survivors keep independent standing with the same NPC.

## Rules the validator enforces

`NPCDepth.State.Validate(state)` returns `ok, errors` and never mutates. It rejects:

- a `schemaVersion` other than the current one, or a negative/non-integer `revision`
- ids that do not carry the `npcd:subject:` or `npcd:npc:` prefix
- **any persisted key that could be read as a number** — see the sentinel section
- relationship values outside `0..100`, non-integers, or axes outside `affection`, `fear`, `resentment`, `respect`, `trust`
- social records, bindings, or `activeSubjectId` pointing at ids that do not exist
- a tombstoned id reused by a live record — ids are burned permanently
- statuses outside `active`/`inactive` (subjects), `alive`/`dead` (NPCs), `pending`/`resolved` (incidents)

Ids are minted from `metadata.idCounter`, not `math.random`, so the same sequence of calls always produces the same ids under test.

## Loading and migration

`NPCDepth.Migrations.Load(raw)` returns `status, state, reason, errors`:

| Status | Meaning |
|---|---|
| `created` | The store was empty; a fresh v1 state was built. |
| `loaded` | The stored state already matches the current schema and validated. |
| `migrated` | An older state was upgraded into a **separate** replacement table. |
| `refused` | Nothing was mutated and the caller must not persist. |

Refusal reasons include `future_schema` (a state written by a newer NPCDepth is left byte-for-byte alone rather than downgraded), `invalid_state`, `no_migration_path`, `migration_failed`, and `migration_did_not_advance`. A migration validates the old state, builds a new table, validates that, and only then replaces the root.

Schema v1 is the first version, so `Migrations.steps` is empty.

## The ModData sentinel gate

Build 42 ModData is **not** assumed to round-trip Lua faithfully. Before enabling durable writes, `GlobalStore.Bind()` writes a sentinel to `ModData.getOrCreate("NPCDepth_Sentinel")`, re-opens the store, and verifies what comes back: a numeric-looking string key (`"12345"`), a namespaced key, booleans, integers, negatives, a float, nested tables, a dense array, and an empty table.

The numeric-looking key is the one the plan explicitly refused to assume. If the bridge coerces `"12345"` into `12345`, every id map in the schema breaks silently, so a coercing store fails the gate.

Two independent results are reported:

- `sentinel.roundTrip` — the write survived a re-open in this session. **This gates persistence.**
- `sentinel.crossSession` — a payload written by an earlier session came back after a reload. On a first run this is `pending_reload`; it resolves on the next session. A same-session rebind reports `not_evaluated` rather than claiming evidence it does not have.

Store statuses: `bound` (sentinel verified, persistence enabled), `degraded` (envelope bound and reporting, sentinel failed, **durable writes disabled**), `refused` (state not loadable, nothing touched), `unavailable` (no ModData).

## Reading it in game

```lua
NPCDepth.GetStoreReport()      -- status, sentinel results, schema version, revision, errors
NPCDepth.GetStateSnapshot()    -- deep copy; mutating it cannot corrupt persisted state
NPCDepth.PrintStoreReport()    -- same report into console.txt
NPCDepth.RebindStore("reason") -- rebind and re-run the sentinel
```

The report prints automatically at `OnGameStart`, after the compatibility report. The store binds independently of Project Remnants, so it reports even when the framework is absent.

## Remaining gate

`crossSession = "verified"` has been proven under the fixture runner but **not yet in a live Build 42 save**. Load a disposable save, quit, reload, and confirm the printed report shows `sentinel.crossSession=verified` with `writeCount` greater than 1 before V01-006 begins writing durable identity.

## Boundaries the test suite enforces

`tools/Test-NPCDepth.ps1` fails the build if:

- any module outside `client/NPCDepth/GlobalStore.lua` references `ModData`
- any module references `getPlayer`
- a `shared/` module references a Project Zomboid global, `os`/`io`, or `math.random`

Full-line comments are stripped before scanning, so a module may name the globals it is forbidden to call.
