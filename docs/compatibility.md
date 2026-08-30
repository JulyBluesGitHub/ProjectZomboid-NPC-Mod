# Iteration A compatibility probe

## Safety boundary

The probe is diagnostic-only. It performs no persistent writes and does not call an unknown `npcfw*` function merely because the function exists. All Project Remnants observations live in `ProjectRemnantsAdapter.lua`; the rest of NPCDepth consumes plain Lua tables.

The mod waits for `Events.OnGameStart`, checks once every 60 ticks, and stops after 20 observations. An absent Remnants mod finishes immediately. A present mod whose Java agent never exposes framework globals finishes in safe mode after the bounded wait.

## Result values

| Result | Meaning | Expected action |
|---|---|---|
| `probing` | Remnants is active but the bounded readiness window is still open. | Wait for the final report. |
| `remnants_absent` | Mod ID `ProjectRemnants` is not active. | Install/enable Remnants when integration testing is desired. |
| `agent_not_ready` | Remnants is active but no `npcfw*` globals appeared before the timeout. | Verify the Java-agent installation and restart the game. |
| `unknown_profile` | Framework globals exist, but NPCDepth has no verified adapter profile for this exact build. | Capture the baseline and add a read-only profile from observed source/runtime evidence. |
| `profile_verified` | The pinned roster surface matched and returned valid plain companion snapshots. | Recruit one disposable-save companion and verify its snapshot before and after save/reload. |
| `profile_read_failed` | The pinned surface matched, but roster reads repeatedly failed validation. | Keep safe mode enabled and inspect the capability diagnostic/circuit state. |

Every non-verified result keeps `safeMode = true`. Iteration A does not persist identity or relationship state under any result.

## Reading the report

The final report is printed automatically to `console.txt`. From an in-game Lua debugger, the same session report and defensive companion-snapshot copies are available through:

```lua
NPCDepth.GetCompatibilityReport()
NPCDepth.GetCompanionSnapshots()
NPCDepth.PrintCompatibilityReport()
NPCDepth.ReprobeCompatibility("manual-debug-request")
```

The report includes the observed game build, Remnants manifest metadata, visible framework-global names, per-capability status, and deduplicated diagnostics. It deliberately excludes live Java/NPC objects.

## Remaining Iteration A gate

The 2026-08-29 baseline pins Project Zomboid app build `24909800` and the Workshop `NPCFW.jar` hash recorded in [remnants-baseline-20260829.md](remnants-baseline-20260829.md). Shipped Remnants Lua verifies `npcfwGetPlayerFactionRoster()` as a read-only roster source. The profile copies only scalar row fields and never returns live Java/NPC objects.

Completed:

1. Collected the pinned Remnants manifest, Lua, launcher, and JAR evidence.
2. Inventoried shipped `npcfw*` call sites.
3. Added the verified read-only roster profile and Kahlua fixtures.

Remaining:

1. Select one recruited companion in a disposable in-game save.
2. Save, reload, and confirm whether its `npcId` is stable before enabling durable identity work.

No durable ID or save-state work begins until that gate passes.

