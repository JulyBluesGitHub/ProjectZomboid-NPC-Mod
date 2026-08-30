# Project Zomboid — NPC Depth Mod: Architecture & Spec

A self-contained technical brief. Written so an AI agent (or a human) can
understand the concept, the game's coding model, the proposed architecture, and
the extension points WITHOUT needing Project Zomboid or its mods installed.

Target game version: Project Zomboid Build 42 (Unstable, 42.20.x as of writing).
This is a design/architecture document first; it does not depend on a specific
filesystem or drive layout.

---

## 0. TL;DR

We want NPCs in Project Zomboid to have human depth: persistent identity,
multi-dimensional relationships, meaningful conditional dialogue, and
background-driven usefulness at a base — and we want it built as an extensible
PLATFORM that other mods (dialogue packs, NPC profiles, campaign quests) can
plug into as separate Workshop items.

Key reframe: an existing mod, "Project Remnants," already provides the full NPC
body (locomotion, combat, spawning, needs, jobs, inventory, save/load). We do
NOT build that. We build the social/identity depth layer on top of it, behind an
adapter so we are not welded to any one framework.

---

## 1. The goal (the user's vision)

NPCs should:

- exist and be functional beyond combat
- have a relationship system with the player
- talk about themselves, their past, and their needs
- be useful at a base in ways driven by their background
- give the player a reason to care about them
- integrate with other "campaign-style" mods

And the build itself should be extensible: new NPCs, new dialogue, and new
mods should be addable without rewriting the core.

---

## 2. How Project Zomboid is coded (the building blocks)

Understanding these fundamentals is required before designing the mod. This is
the part a game-less agent must internalize.

### 2.1 Two layers: Java engine + Lua scripting

Project Zomboid is a Java application (engine classes under the `zombie.*`
package) with a **Lua scripting layer** that drives most gameplay logic, UI,
and content. The split:

- **Java** (closed source, by The Indie Stone): world simulation, rendering,
  pathfinding, core AI, save serialization. Modders generally cannot change
  Java — but they CAN call into it.
- **Lua** (open, the modding surface): UI, context menus, timed actions,
  recipes, item definitions, and — crucially for us — any gameplay logic a
  modder wants to add on top of the engine.

Mods are almost always pure Lua. The engine exposes its Java objects and methods
to Lua automatically; Lua code reads and mutates the live game state.

### 2.2 Lua load order (this determines WHERE code goes)

Lua files live under `media/lua/` and load in a strict order:

1. `shared/` — loads first, runs on both client and server. Put logic that must
   exist on both sides here (data definitions, shared functions).
2. `client/` — loads next, client only. UI, context menus, timed actions,
   rendering overlays. THIS is where dialogue UI and interaction menus go.
3. `server/` — loads only when a game/save actually starts. World logic,
   spawning, farming, weather.

Rule of thumb: dialogue UI and context menus = `client/`. Persistent state and
relationship logic that must survive save/load = handle via ModData (see 2.5),
not by dumping it in `server/`.

### 2.3 The event / callback system

Almost all Zomboid Lua is event-driven. Java fires an event; Lua registers a
callback function:

```lua
local function onGameStart()
    print("My mod loaded")
end
Events.OnGameStart.Add(onGameStart)   -- pass the FUNCTION, no parentheses
```

**The classic beginner bug:** `Events.OnGameStart.Add(onGameStart())` calls the
function immediately and registers its return value (usually nil) instead of
registering the function. Always pass the bare reference.

Common events: `OnGameStart`, `OnGameBoot`, `OnPlayerUpdate`, `OnKeyPressed`,
`OnCharacterDeath`, `OnFillContainer`, `OnNewGame`, `OnLoad`, `OnCreatePlayer`,
and many more.

### 2.4 Custom events (how mods talk to each other)

A mod can register its OWN event types in Lua, then fire them. Other mods
subscribe. This is the mechanism for the campaign-interoperability requirement:

```lua
LuaEventManager.AddEvent("MyMod_OnSomethingChanged")  -- register
Events.MyMod_OnSomethingChanged.Add(callback)          -- subscribe
triggerEvent("MyMod_OnSomethingChanged", arg1, arg2)   -- fire from Lua
```

### 2.5 ModData (persistence)

Every game character (and player) has a `getModData()` method that returns a
Lua table saved into the save file. This is the standard persistence layer for
custom mod state — no external files needed, survives save/load automatically:

```lua
local data = player:getModData()
data.NPCDepth = { ... }   -- persists across saves
```

### 2.6 Global namespace discipline

Polluting the global namespace is slow and causes collisions. The convention:
**expose exactly one global table per mod**, keep everything else `local`.

```lua
NPCDepth = NPCDepth or {}
local internalHelper = function() end   -- local, not global
```

### 2.7 The Java <-> Lua bridge (how Project Remnants' framework works)

The existing NPC framework ("NPCFW") ships as a Java agent (`NPCFW.jar`) loaded
via JNA (Java Native Access). It registers a set of global Lua functions
prefixed `npcfw*` (e.g. `npcfwGetNPC(id)`, `npcfwPossess(id)`). Lua code calls
these like normal functions to command the Java-side NPC system.

This matters for our design: our add-on talks to the NPCs through these
`npcfw*` functions. If a future/better NPC framework appears, we only replace
the thin adapter that calls them — see section 6.

---

## 3. How Project Zomboid mods are structured

### 3.1 Build 41 (flat layout)

```text
MyMod/
  mod.info
  poster.png
  media/
    lua/
      shared/    # both sides, loads first
      client/    # UI, context menus, timed actions
      server/    # world logic, spawning
    scripts/     # .txt: items, recipes, vehicle defs
    textures/    # PNGs
```

### 3.2 Build 42 (versioned layout — we target this)

One mod can ship content for multiple game versions via a `common/` folder plus
per-version folders:

```text
MyMod/
  common/
    media/        # content shared by every build
  media/          # (Project Remnants also keeps some files here)
  42/
    mod.info      # the Build 42 manifest
    poster.png
    media/        # Build 42 only
  41/             # optional, only if also supporting Build 41
    mod.info
    media/
```

`common/media/` holds build-agnostic stuff; version folders hold build-specific
content. The game loads `common/` plus the folder matching the running build.

### 3.3 mod.info (the manifest)

```text
name=Project Remnants
id=ProjectRemnants
loadModAfter=AutoDriveRoadGrid
description=Early human NPC survivor party mod for Build 42...
poster=preview.png
```

Key fields: `name`, `id` (unique), `description`, `poster`, plus optional
`require=` (dependencies) and `loadModAfter=` (load ordering). A `workshop.txt`
adds Workshop metadata for distribution.

---

## 4. The existing framework we build on: Project Remnants

- Workshop ID: 3738362476 (Pat's NPC - Project Remnants [B42 SP])
- Ships `NPCFW.jar` (Java) + a large Lua layer (client/shared)
- Already provides (do NOT reinvent): recruitable companions, party creation,
  control switching, shared inventory, persistent save/load, professions,
  traits, skills, XP, needs (hunger/thirst/fatigue/morale/sanity/pain/
  unhappiness), farming, cooking, hauling, guard duty, sleeping, self-care,
  leisure, safehouse jobs and storage, situational dialogue, gestures.

Observed `npcfw*` bridge functions (grep of its Lua; treat as UNSTABLE — no
formal API contract): npcfwIsReady, npcfwInit, npcfwLoad*, npcfwIsPossessing,
npcfwGetOriginalPlayer, npcfwPossess, npcfwUnpossess, npcfwTransferControl,
npcfwGetNPC, npcfwIsControlledCharacter, npcfwOrderFollow/Stay/Clear,
npcfwOrderOriginalFollow/Stay, npcfwArePartyMembersLinked, npcfwSendToSafehouse,
npcfwGetPartySafehouseSummary, npcfwGetDrivingSpeedMode, npcfwSetDrivingSpeedMode,
npcfwStopDriving, npcfwIsDriving, npcfwToggleVehicleDriveRecording,
npcfwIsVehicleDriveRecording, npcfwGetVehicleDriveRecordingPath,
npcfwGetVehicleDriveRecordingError, npcfwIsPartyRestActive.

It also confirms ModData as its persistence mechanism (per-character keys like
`npcfwCallsign_` and `npcfwPartySlotOrder`).

---

## 5. What is missing (the depth layer we build)

The existing dialogue communicates STATE but not IDENTITY. Four gaps:

### 5.1 Personal identity
Each NPC needs persistent data: former occupation, hometown, family situation,
personal values, likes/dislikes, fears, habits, long-term objective, authored
memories, skills (proud/ashamed), and topics they will or will not discuss.

### 5.2 Multi-dimensional relationship memory
Not one "friendship" number. Six axes:
- Trust — will you protect/provide for them?
- Respect — are you competent/dependable?
- Affection — do they personally like you?
- Fear — do they obey out of fear?
- Resentment — do they remember neglect?
- Loyalty — will they take risks for the group?

These change from concrete events, not repeated "Compliment" clicks. Examples:
bandage a wound -> trust up; repeatedly leave them hungry -> resentment up;
survive a dangerous trip together -> respect + loyalty up; force a cowardly
character onto guard duty -> stress + resentment up.

### 5.3 Conditional dialogue
Dialogue selection = identity + present need + relationship state + recent
memories + location + assigned job + world age + campaign flags. A former nurse
should not just say "I used to be a nurse" — she should ask for medical supplies,
notice an untreated injury, object when medicine is wasted, gain confidence when
assigned as medic, and reveal personal history only after enough trust.

### 5.4 Background-driven specialization
Profession changes how well AND how happily an NPC does a job: carpenter builds
faster and wastes fewer materials; nurse detects serious wounds; farmer catches
disease early; mechanic diagnoses faults and requests specific parts.

---

## 6. Proposed architecture: the NPCDepth platform

Add-on mod name: NPCDepth.

### 6.1 Core principle: content vs code

Split everything into two categories:

- **ENGINE (code)** — the dialogue selection logic, relationship updates,
  persistence, event plumbing. Rarely changes once built.
- **CONTENT (data)** — profiles, dialogue packs, memories, traits. Added as Lua
  data files with no engine changes.

Adding a new NPC or a new conversation must be a data-file change, never an
engine change. This is what makes the mod extensible.

### 6.2 File layout

```text
NPCDepth/
  common/
    media/lua/
      shared/
        NPCDepth_Core.lua          # the engine: state, event bus, registry
        NPCDepth_Relationships.lua # relationship axes + update rules
        NPCDepth_Memories.lua      # memory store + triggers
        NPCDepth_Events.lua        # custom event definitions
      client/
        NPCDepth_ProjectRemnantsAdapter.lua  # bridge to NPCFW (the ONLY
                                             # place npcfw* is called)
        NPCDepth_ContextMenu.lua   # right-click -> "Talk"
        NPCDepth_DialogueEngine.lua # selection + variable substitution
        NPCDepth_DialogueUI.lua     # panel
        NPCDepth_DebugUI.lua        # dev inspection
      content/                      # <-- DATA, not code (see 6.3)
        profiles/
          former_nurse.lua
          carpenter.lua
        dialogue/
          nurse_pack.lua
          generic_pack.lua
  42/
    mod.info
```

### 6.3 The adapter (decoupling decision)

```
Our social systems
        |
Project Remnants adapter   <-- the only file that touches npcfw*
        |
NPCFW Java bridge
        |
Actual NPC character
```

If a better NPC framework appears later, we rewrite ONE file (the adapter), not
the whole mod. The rest of NPCDepth only sees a small internal interface the
adapter implements (e.g. `Adapter.GetNpcId(character)`, `Adapter.GetNeeds(npc)`,
`Adapter.GetProfession(npc)`).

---

## 7. Extension points (how we keep adding + make separate mods)

This is the explicit answer to "leave room to grow." NPCDepth is a PLATFORM
with registries. Other mods register content into it.

### 7.1 Profile registry
`NPCDepth.RegisterProfile(profile)` — a profile is a data table describing one
NPC archetype (former nurse, carpenter, etc.). New backgrounds = new data file
in `content/profiles/`, one `RegisterProfile` call. No engine change.

### 7.2 Dialogue pack registry
`NPCDepth.RegisterDialoguePack(pack)` — a pack is a set of dialogue nodes tagged
with conditions (trigger, relationship threshold, need state, location, job).
New conversations = new data file in `content/dialogue/`. No engine change.

This means **dialogue packs can be their own separate Workshop mods** that
depend on NPCDepth and register content on load. Same for **profile packs** and
**campaign/quest mods**.

### 7.3 Relationship/event hooks
Other mods subscribe to NPCDepth events:

```lua
Events.NPCDepth_OnRelationshipChanged.Add(function(npcId, stat, old, new)
    if npcId == "maya" and stat == "trust" and new >= 50 then
        Campaign.UnlockQuest("HospitalSearch")
    end
end)
```

Events to expose: OnRelationshipChanged, OnDialogueCompleted, OnMemoryAdded,
OnPersonalQuestStarted, OnPersonalQuestCompleted.

### 7.4 Public API surface
```lua
NPCDepth.GetRelationship(npcId)
NPCDepth.AddMemory(npcId, memory)
NPCDepth.SetCampaignFlag(npcId, flag, value)
NPCDepth.StartDialogue(npcId, conversationId)
NPCDepth.RegisterProfile(profile)
NPCDepth.RegisterDialoguePack(pack)
```

### 7.5 Personal quest layer (future)
Quests as data + hooks, driven by campaign mods. A remembered fact ("a boy
named Ethan... I told his mother I'd keep him safe") becomes a location quest,
morale event, or conflict — driven by an external campaign mod through the
event hooks above, NOT hard-coded into NPCDepth.

### 7.6 Separate mods summary
All of these can be distinct Workshop items that only `require` NPCDepth:
- NPCDepth (the platform/engine)
- NPCDepth-Profiles (content pack)
- NPCDepth-Dialogue (content pack)
- NPCDepth-Campaign (quest/campaign content)
- NPCDepth-Adapters (support for alternative NPC frameworks)

---

## 8. Persistence schema

```lua
player:getModData().NPCDepth = {
    schemaVersion = 1,
    npcs = {
        ["npc-id"] = {
            profileId = "former_nurse_01",
            trust = 12, respect = 8, affection = 3,
            fear = 0, resentment = 1, loyalty = 4,
            memories = {}, knownTopics = {}, campaignFlags = {}
        }
    }
}
```

`schemaVersion` enables migrating existing saves when the structure changes.

---

## 9. First prototype (the vertical slice to prove the loop)

Do NOT build romance, procedural life stories, autonomous quests, and full
campaign integration at once. Prototype 1 proves this loop:

1. Right-click a recruited Project Remnants NPC.
2. Select "Talk".
3. Open a dialogue panel.
4. Display: name, former occupation, current need, current assignment, and a
   qualitative relationship status.
5. Offer three contextual choices.
6. NPC responds based on background + current hunger/fatigue/pain + existing
   trust + one recent remembered event.
7. Relationship state changes.
8. Save.
9. Reload.
10. Confirm the NPC remembers the interaction.

Example:

    Maya Torres
    Former occupation: Nurse
    Current state: Tired and slightly hungry
    Relationship: Cautiously trusting

    [Ask about her past]
    [Ask what the base needs]
    [Thank her for treating your wound]

Response:
    "I worked nights at St. Peregrin before everything collapsed.
    I'm not ready to talk about what happened there."

Later, after more trust:
    "There was a boy there named Ethan. I told his mother I'd keep
    him safe. I still don't know whether either of them made it out."

---

## 10. Authored vs AI-generated dialogue

Recommendation: authored, deterministic dialogue as the foundation — NOT live
LLM generation. Reasons: offline, consistent characterization, no invented
facts, translatable, testable, cheap, reliable campaign conditions. AI may
generate/edit dialogue packs during development; the shipped mod stays
deterministic and offline (optional AI module later).

---

## 11. Feasibility, risks, and open questions

Confidence split (keep honest):
- FACT: foundation exists, much exposed to Lua.
- INFERENCE: a social-depth add-on is viable without decompiling Java.
- UNKNOWN: Project Remnants has no formal stable API; `npcfw*` may change.
- MAIN RISK: coupling to a fast-moving Build 42 mod. (Mitigated by the adapter.)

Open questions to resolve before/while building:
1. Does NPCFW expose a stable unique NPC ID to key relationship data on?
2. Which `npcfw*` functions are safe to call from a separate add-on?
3. How does the mod expose "recruited companion" state so the adapter can tell
   which NPCs are party members?
4. Is there a dialogue hook/event, or must the add-on supply its own trigger
   (context menu) and UI?
5. Does player-character ModData reliably persist NPC-keyed state across
   save/reload in Build 42?
6. Contact the Project Remnants author before publishing anything that depends
   on undocumented interfaces.

Safety rules: develop against a disposable save; never edit the Workshop copy;
declare Project Remnants as a dependency; ask the author before publishing.

Note: if the `npcfw*` Lua surface proves insufficient, a JAR add-on is
technically possible (the game loads Java mods) but is a much harder path
(Java, engine API decompilation). Prefer staying Lua-only until proven otherwise.

---

## 12. Key principle

NPC depth does not come from thousands of dialogue lines. It comes from memory,
consequences, differentiated capability, and relationships that alter gameplay.

Next action: build the vertical slice. First proof = one NPC who remembers one
meaningful interaction after a save/reload. If that works, the platform has a
foundation.
