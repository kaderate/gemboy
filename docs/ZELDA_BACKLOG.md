# Zelda agent — backlog

Working log for the autonomous push. See `docs/ZELDA_AGENT.md` for the architecture design and
the session 1/2 spike write-up (world model, planner/executor, pause-capture pattern, primitives).
This file tracks task status only; `docs/zelda_world_model.json` and
`docs/zelda_ram_registry.json` hold the actual accumulated game-state data. All three are pushed
regularly so nothing is lost if the session container recycles.

## Status: autonomous push in progress (user asleep, proceeding per agreed plan)

## Done
- Save file created, name "A".
- 2 in-room NPC dialogues read cleanly (Tarin, second NPC), tile-ID scratch-buffer finding
  confirmed byte-for-byte across both (see ZELDA_AGENT.md).
- `move_tiles` / `find_link` / `interact` primitives built and validated (self-verifying via OAM,
  not blind taps).
- Pot contact tested: correctly triggers "too heavy" (real game constraint, not a primitive bug).
- START/pause tested 3x inside the starting room (short hold, long hold, held 5,000,000 steps,
  after a confirmed successful move): **no pause screen in any case**. Genuinely locked at this
  point in the intro, not a timing artifact.

## In progress / next up
1. Exit the starting house (door visible at the bottom of the room), re-test pause outside —
   the lock may be tied to "still inside the intro house", not to "can move yet".
2. Talk to a villager outside — 3rd independent tile-ID cross-check (session 1's original ask,
   not yet done), and starts populating the map graph beyond the starting room.
3. Find the sword (known early-LA beat, shortly after leaving the house) — unlocks `cut_grass`
   and real combat, currently blocked on "no item equipped".
4. Cut grass once the sword is found — last untested primitive from the original scope.
5. Populate `zelda_ram_registry.json` opportunistically: only hardware-standard addresses
   confirmed so far (OAM @0xFE00, LCDC/SCX/SCY @0xFF40/43/42, BG/window tilemaps @0x9800/0x9C00 —
   these are GB hardware architecture, not hypotheses). Link's own WRAM position/health/inventory
   addresses are still unmapped; `find_link`'s OAM-exclusion workaround is good enough for
   single-NPC rooms and isn't currently a blocker, so this stays opportunistic, not urgent.

## Open questions (not blockers, just unresolved)
- Exact milestone that unlocks pause (leaving the house? a specific flag?).
- Numeric confidence percentage vs. discrete tiers for the data model (see ZELDA_AGENT.md) —
  leaning tiers, not settled.
