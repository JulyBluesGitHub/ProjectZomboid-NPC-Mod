# NPCDepth

NPCDepth is an experimental single-player add-on for Project Zomboid Build 42 and Project Remnants. The current code is **Iteration A only**: a load-safe compatibility probe plus one pinned, read-only roster profile. It does not write save data, alter companions, or implement relationship gameplay yet.

## Current behavior

- Waits until `OnGameStart` before observing Project Remnants.
- Detects whether Mod ID `ProjectRemnants` is active.
- Inventories visible `npcfw*` globals without invoking unknown functions.
- Recognizes the pinned Project Remnants roster surface and copies recruited-companion rows into plain diagnostic snapshots.
- Stops after a bounded number of attempts and enters safe mode when the agent is unavailable or its API profile is unknown.
- Prints a Tier-0 compatibility report to the Project Zomboid console.

The pinned profile calls only `npcfwGetPlayerFactionRoster()` under the compatibility circuit breaker. Stable NPC identity remains unverified until a recruited companion survives the disposable save/reload lifecycle test.

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

Validate manifests, compile every Lua file with Project Zomboid's bundled Kahlua compiler, and exercise absent/timeout/unknown-profile/circuit-breaker fixtures under the bundled runtime:

```powershell
./tools/Test-IterationA.ps1
```

See [docs/compatibility.md](docs/compatibility.md) for report meanings and the remaining Iteration A gate.
