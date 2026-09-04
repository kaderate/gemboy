# Zelda agent — backlog

Working log for the autonomous push. See `docs/ZELDA_AGENT.md` for the architecture design and
the session 1/2 spike write-up (world model, planner/executor, pause-capture pattern, primitives).
This file tracks task status only; `docs/zelda_world_model.json` and
`docs/zelda_ram_registry.json` hold the actual accumulated game-state data. All three are pushed
regularly so nothing is lost if the session container recycles.

## Status: paused, blocked on the starting-room door — see "Blocked" below before resuming

## Done
- Save file created, name "A".
- 2 in-room NPC dialogues read cleanly (Tarin, second NPC), tile-ID scratch-buffer finding
  confirmed byte-for-byte across both (see ZELDA_AGENT.md). Second NPC's dialogue now fully
  exhausted (5 pages, full text in `zelda_world_model.json`).
- `move_tiles` / `find_link` / `interact` primitives built and validated (self-verifying via OAM,
  not blind taps). Both `move_tiles` and `find_link` held up across ~15 more calls this session.
- Pot contact tested twice: correctly triggers "too heavy" both times (real game constraint, not
  a primitive bug).
- START/pause tested 4x inside the starting room (short hold, long hold, 5,000,000-step hold,
  after a confirmed move): **no pause screen in any case**. Confirmed locked before the door is
  passable, not a timing artifact.
- WRAM hunt for Link's true position: found 4 candidates (`0xD314/D31E/D324/D32E`) via a stronger
  method (consistent-small-delta across 4 consecutive taps, not a single diff), then **ruled all
  4 out** via direction cross-check -- they increase on every tap regardless of direction, so
  they're activity/animation counters, not (X, Y). **Decision: keep OAM-exclusion as the accepted
  method**, don't re-open this unless a room with other moving sprites breaks it. Full method
  writeup in the registry so a future attempt doesn't repeat the same first pass.

## Blocked
**Cannot leave the starting house.** Tarin stops Link at the south door ("Hé mon gars, attends un
peu !"). Tried and ruled out: 3 different door-alignment columns, fully exhausting the second
NPC's dialogue first, waiting 10M idle steps in case a scripted event resolves on its own. The
block appears to reposition Link (not a one-time interrupt you can just walk through after
dismissing) -- this smells like a real story gate, not a pathing bug. Full detail and attempted
list in `zelda_world_model.json` under `rooms.starting_house.exits.south_door`.

**Next step, not yet done**: a WRAM diff bracketing the block-trigger event itself (snapshot right
before crossing the threshold vs. right after the message appears) to find the actual flag/counter
being checked -- same method that worked for the OAM/tile-ID findings, just not yet applied to
this specific event. Stopped blind retrying in favor of writing this up, rather than continuing to
burn cycles on trial and error with a poor cost/value ratio.

## Next up (once unblocked)
1. Get past the door, talk to a villager outside — 3rd independent tile-ID cross-check (original
   session 1 ask, still not done), starts populating the map graph beyond the starting room.
2. Find the sword (known early-LA beat) — unlocks `cut_grass` and real combat.
3. Cut grass once the sword is found — last untested primitive from the original scope.
4. Re-test pause once outside — the lock may be tied to "still inside the intro house" rather
   than a general early-game milestone; worth confirming either way.

## Open questions (not blockers, just unresolved)
- Numeric confidence percentage vs. discrete tiers for the data model (see ZELDA_AGENT.md) —
  leaning tiers, not settled.
