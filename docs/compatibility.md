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

Every non-verified result keeps `safeMode = true`. Iteration A does not persist identity or relationship state under any result.

## Reading the report

The final report is printed automatically to `console.txt`. From an in-game Lua debugger, the same session report is available through:

```lua
NPCDepth.GetCompatibilityReport()
NPCDepth.PrintCompatibilityReport()
NPCDepth.ReprobeCompatibility("manual-debug-request")
```

The report includes the observed game build, Remnants manifest metadata, visible framework-global names, per-capability status, and deduplicated diagnostics. It deliberately excludes live Java/NPC objects.

## Remaining Iteration A gate

Project Remnants is not installed in the current local Workshop library. The skeleton can therefore prove the `remnants_absent` path locally, but these steps remain evidence-gated:

1. Collect a baseline from one pinned Remnants build.
2. Inventory its shipped Lua `npcfw*` definitions and call sites.
3. Add only a verified read-only companion-discovery profile.
4. Select one recruited companion in a disposable in-game save.

No durable ID or save-state work begins until that gate passes.

