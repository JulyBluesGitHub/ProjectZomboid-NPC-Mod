# Draft — Project Remnants Integration Request

Preferred channel: the Project Remnants Discord linked from the Workshop page  
Timing: during Gate 0; a reply is not required for private diagnostic work  
Sender: the NPCDepth project owner before any public Workshop release

## Suggested message

Hi! I'm developing a small single-player Lua add-on called NPCDepth for Project Remnants. Its goal is persistent character identity, authored memories, relationship-aware dialogue, and background-specific social content.

The add-on will declare Project Remnants as a dependency, stay behind a thin adapter, and avoid modifying or decompiling NPCFW.jar. The first prototype also avoids NPCFW gameplay mutators. Before publishing anything, I would like to use the smallest read-only surface you are comfortable supporting.

Could you confirm or recommend:

1. A companion identifier that remains stable across possession, save/reload, cell unload/reload, and dismiss/re-recruit.
2. Whether a separate add-on may safely store its own namespaced ID in companion ModData, and whether NPCFW preserves that field when reconstructing companions.
3. The supported way to determine whether an IsoPlayer is a recruited/eligible party companion.
4. The supported way to identify the original survivor while another companion is possessed.
5. A readiness signal or event after which read-only NPCFW calls are safe.
6. Any read-only profession, needs, or assignment access you recommend for add-ons.
7. Your preferred add-on/load-order rules and anything NPCDepth should avoid to remain compatible.

I am happy to pin and test against a specific Remnants version, share the adapter surface and diagnostics, and keep the public API clearly marked experimental until the integration is proven. I will not present undocumented behavior as officially supported without your confirmation.

Thanks for considering it—and for explicitly making space for Workshop-hosted Remnants add-ons.
