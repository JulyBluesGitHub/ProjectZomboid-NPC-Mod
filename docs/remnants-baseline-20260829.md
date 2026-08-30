# Project Remnants pinned baseline — 2026-08-29

This is the durable summary of the read-only `Collect-RemnantsBaseline.ps1` run. The full machine-local JSON remains under the ignored `artifacts/baselines/` directory because it contains absolute installation paths.

## Target

- Project Zomboid Steam app build: `24909800`
- `projectzomboid.jar` SHA-256: `80e405a4bfc42f6072e75b3735f458a6514143da011d3226007ded305a442f44`
- Project Remnants Workshop ID / Mod ID: `3738362476` / `ProjectRemnants`
- Remnants `mod.info` SHA-256: `a24fdf8bb948df242c71acf876a2b6517a0d7071bf9c78ffa599152619877aa2`
- Workshop `NPCFW.jar` length: `1833702` bytes
- Workshop `NPCFW.jar` SHA-256: `40494c1dba5b7cc54fa0916d8f92323fb44e973bef8687606a8bc3b25d1fc82f`
- Java agent launch path: the Steam Workshop `NPCFW.jar`

The game root also contains an older `NPCFW.jar` (`583469` bytes, SHA-256 `f199b1aee1463cc45d416b6f3ff322e71a182f9a4f2d8299bc44122c12d47719`). The hashes diverge, but `ProjectZomboid64.json` points at the current Workshop JAR. NPCDepth does not use the stale game-root copy and does not treat a JAR hash as the runtime API contract.

## Verified read-only roster surface

The pinned Remnants Lua uses these bridge functions as reads under `pcall`:

- `npcfwGetPlayerFactionRoster()` returns an indexable roster of recruited faction members.
- Each consumed row includes `npcId`, `displayName`, `assignment`, `isPartyMember`, `isBaseResident`, `isLive`, `safehouseJob`, `safehouseJobLabel`, and `currentSafehouseTask`.
- `npcfwGetPlayerFactionMemberIds()` supplies IDs which Remnants passes to `npcfwGetNPC()` for live-object lookup. NPCDepth does not use that live-object path in this profile.
- `npcfwGetAssignmentOf(npc)` and `npcfwIsPlayerFactionMember(npc)` corroborate the roster semantics in the shipped context-menu code. NPCDepth does not call either during discovery.

Primary shipped call sites:

- `42/media/lua/client/NPCFW_FactionManagementUI.lua`, roster normalization around lines 920–951.
- `42/media/lua/client/NPCFW_ContextMenu.lua`, roster consumption around lines 432–453 and recruited-member checks around lines 63–73.
- `42/media/lua/client/NPCFW_CookRequestUI.lua`, roster lookup around lines 594–619.
- `42/media/lua/client/NPCFW_Gibberish.lua`, faction ID discovery around lines 813–826.

Profile `project-remnants-42-roster-20260829` recognizes the Workshop ID plus the observed read-only function cluster. It calls only `npcfwGetPlayerFactionRoster()`, validates and bounds the returned shape, and copies scalar values into plain Lua snapshots.

## Capability boundary

Verified now:

- Framework global readiness.
- Recruited-companion discovery.
- Assignment fields included in roster snapshots.

Still unverified:

- Whether `npcId` is stable across save/reload, unload/reload, possession, and dismiss/re-recruit.
- Original-survivor identity during possession.
- NPC ModData ownership/tagging.
- Needs and profession reads.

No persistence or relationship work is authorized by this baseline. The next gate is one recruited companion in a disposable save, observed before and after save/reload.
