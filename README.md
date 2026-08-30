# NPCDepth

NPCDepth is an experimental single-player add-on for Project Zomboid Build 42 and Project Remnants. Iteration A (a load-safe compatibility probe plus one pinned, read-only roster profile) is complete, and Iteration B has begun with the schema v1 persistent store. NPCDepth does not alter companions or implement relationship gameplay yet: the store holds its own namespaced state and never writes to Remnants-owned data.

## Current behavior

- Waits until `OnGameStart` before observing Project Remnants.
- Detects whether Mod ID `ProjectRemnants` is active.
- Inventories visible `npcfw*` globals without invoking unknown functions.
- Recognizes the pinned Project Remnants roster surface and copies recruited-companion rows into plain diagnostic snapshots.
- Stops after a bounded number of attempts and enters safe mode when the agent is unavailable or its API profile is unknown.
- Prints a Tier-0 compatibility report to the Project Zomboid console.
- Binds a validated schema v1 envelope to Global ModData and proves, with sentinels, that Build 42 preserves the key
  and value shapes the schema needs before enabling durable writes.

The pinned profile calls only `npcfwGetPlayerFactionRoster()` under the compatibility circuit breaker. Stable NPC identity is verified: on 2026-08-29 a recruited companion's `frameworkKey` survived a disposable save/reload unchanged, so durable identity work is unblocked.

Project Remnants is intentionally not a hard manifest dependency yet. That allows the probe to load and explain an absent or incomplete installation.

## Development workflow

Collect a read-only local baseline:

```powershell
./tools/Collect-RemnantsBaseline.ps1
```

Install the development mod into the local Project Zomboid mods folder:

```powershell
./tools/Install-DevMod.ps1
```

Replacing an existing development install is recoverable: pass `-Force` and the installer moves the previous directory to a timestamped backup before installing the new copy.

Validate manifests and boundaries, compile every Lua file with Project Zomboid's bundled Kahlua compiler, and exercise
the compatibility, schema, migration, and sentinel fixtures under the bundled runtime:

```powershell
./tools/Test-NPCDepth.ps1
```

See [docs/compatibility.md](docs/compatibility.md) for report meanings and the Iteration A identity-gate evidence, and
[docs/state-schema.md](docs/state-schema.md) for the persistent state contract and the ModData sentinel gate.
