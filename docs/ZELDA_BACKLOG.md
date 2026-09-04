# Zelda agent — backlog

Working log for the autonomous push. See `docs/ZELDA_AGENT.md` for the architecture design and
the session 1/2 spike write-up (world model, planner/executor, pause-capture pattern, primitives).
This file tracks task status only; `docs/zelda_world_model.json` and
`docs/zelda_ram_registry.json` hold the actual accumulated game-state data. All three are pushed
regularly so nothing is lost if the session container recycles.

## Status: movement-precision root cause SOLVED this session; next blocker is room collision
geometry (needs a static walkable-tile grid), not the story gate. See "Movement model" and
"Blocked" below before resuming.

## Movement model — solved
Root-caused via a fork-per-trial hold-duration sweep (boot once, fork a child per direction/hold
combo, time precisely via `run_steps`'s returned real T-cycle count rather than guessing from
instruction counts): **movement is tile-locked**. Any directional press held >=1 frame (below
that: zero effect) commits to one fixed, deterministic ~22-28 frame trajectory regardless of
holding longer -- 1/2/4/8/16-frame holds all produced byte-identical outcomes. Exactly two
results: settles at ~+/-14px along the pressed axis (completed step), or bounces back to within a
few px of the start (collision). All the previously-reported 7-31px noise was from reading OAM
mid-animation, not real variance. Full method + data in `zelda_world_model.json.movement_model`.

`move_tiles` (docs/zelda_primitives.rb) rewritten accordingly: short 2-frame trigger press, fixed
28-frame settle wait, then a single reliable read. Verified against real room geometry -- now
correctly reports `moved=0` on genuine collisions instead of misleading partial deltas.

**Residual finding, not a primitive bug**: re-testing the Tarin route with the fixed primitive
still hit trouble -- a request for pure `:down` movement near the start position produced an
unexpected +14px **lateral** (X) shift, reproduced independently with both the old and new
`move_tiles`. Read as the room's narrow bed/table corridor causing a diagonal collision-redirect
near a corner (bump a corner, slide sideways) -- real game geometry, not a timing artifact. This
is precisely the class of problem a static walkable-tile grid (built from the BG tilemap) would
avoid, by routing around known obstacles instead of discovering them by bumping into them
order-dependently. That's the next concrete step (see "Next up").

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

**WRAM diff attempted, inconclusive**: bracketed the exact block-trigger event (snapshot right
before crossing the threshold vs. right after the message appears) -- 28 bytes changed, too many
to isolate confidently in one pass (dialogue-box-opening side effects are mixed in with whatever
the actual gate flag is). Full list logged in this run's script output, not worth reproducing here
verbatim; the method is sound (same one that cracked the tile-ID and OAM findings) but needs a
second bracketing point to subtract the noise -- e.g. diff *this* diff against a diff from an
unrelated dialogue trigger (Marin's), keeping only addresses that changed here but not there.
Not done this session.

**Second attempt to reach Tarin directly also failed** -- not narrative-blocked this time, a
genuine navigation limitation: chaining `move_tiles(right, 4)` then `move_tiles(down, 2)` from the
start position both times funneled back to the exact same door-threshold tile (70, 112) instead of
reaching Tarin at (120, 80). The room's open floor is a narrow corridor between the beds and the
table/pots; `move_tiles` verifies each *segment* correctly (real OAM displacement, stops on
collision) but has no path-planning across multiple segments -- it'll happily walk you back into
the same bottleneck twice. **Real, useful finding**: don't chain multi-segment moves blindly in a
cluttered room; check a screenshot (or OAM position against expected waypoint) between segments,
or route around known obstacles explicitly rather than "right then down".

**Third round (this session, puzzle-solving spike), root cause finally isolated**: built and
validated an anti-cheat puzzle-solving embryo (`zelda_puzzle_packet_starting_house.json` +
`zelda_puzzle_validator.rb` + `zelda_puzzle_hypotheses_starting_house.json`, 5/5 hypotheses
grounded and passing validation; a deliberate bad-hypothesis test citing "sword" and a nonexistent
object was correctly rejected, confirming the validator works). Top hypothesis `h1_reread_tarin`
required physically walking back to Tarin, so I made 5 more navigation attempts with progressively
better data:
- `down(1)+right(1)`: landed (61,70), right blocked immediately.
- `right(2)+down(3)`: landed (52,70) then (112,70) -- back at the door threshold again.
- `down(2)+right(1..6)`: **best approach yet**, landed (92,108) -- much closer to Tarin (80,120).
  A full OAM dump at this checkpoint confirmed only 3 sprite pairs exist in the room (Link +
  Tarin + second NPC), each exactly matching the `STATIONARY` exclusion list -- so `find_link`'s
  tracking is accurate, ruling out "wrong sprite tracked" as an explanation.
- From (92,108): `right(1)` blocked (table edge), `up(1)` overshot to (61,108) -- past Tarin's row.

**Root cause identified**: `move_tiles`'s single directional tap (hold: 350,000 cycles) does not
produce a fixed tile-sized displacement. Measured deltas for nominally identical "move 1 tile"
calls in this session alone: 7px, 16px, and 31px. A tile is ~16px, so a single call reporting
`moved=1` can silently overshoot by nearly 2 tiles or undershoot by half a tile. That's exactly
consistent with every failed final-approach this session and last: not a story gate, not a
tracking bug, but the primitive's own imprecision compounding over the last 1-2 tiles where
alignment actually matters. **Fix (not yet done)**: shorten the hold duration and/or stop based on
absolute target-coordinate proximity rather than a fixed "n taps" count, so `move_tiles` can
reliably land on a specific adjacent tile instead of just "the right general direction".

**`move_tiles` rewritten** to advance in short 60,000-cycle taps and stop on net displacement
crossing ~1 tile, instead of one long 350,000-cycle hold per tile (see `zelda_primitives.rb`).
Re-tested the same route (`down(2)+right(3)+up(1)`) with the new version: landed at (61,108),
matching the earlier best result closely -- a single tap can still cover 15-31px in one step
(observed again: one `up(1)` call jumped the full 31px in what looked like 1-2 taps), so **the fix
improves diagnosability but did not fully solve precision**. Likely explanation, not yet confirmed:
Zelda's movement may be tile-locked (once triggered, Link finishes the full tile-step animation
regardless of when the key is released), which would make hold-duration tuning fundamentally the
wrong lever -- the fix would instead be measuring/predicting tile-boundary landings rather than
metering input duration. Not chased further this session.

**Closest approach yet**: from (61,108), one short right tap (20,000 cycles) followed by 3
`interact` calls produced a screenshot with Link visibly adjacent to Tarin's table area (compare
`/tmp/zelda_tarin10_afterinteract.png` if still on disk -- not persisted to the repo) -- but
`find_link` returned nil at that point (OAM ambiguity) and no dialogue box opened, so the
interaction did not land precisely enough to trigger Tarin's conversation. This is the best
positional result across all attempts this session; picking up from exactly this route with one
more small rightward/upward nudge is the most promising next step, not a fresh approach.

Stopping here for this session -- the root cause is well-diagnosed, the primitive is measurably
better (even if not fully precise), and this exact near-miss route is a concrete, promising handoff
point rather than another guessed hold duration. Clear next steps are written down above for
whoever (me or the user) picks this back up.

## Next up (once unblocked)
0. **Build a static walkable-tile grid for the room** from the BG tilemap (Navigator design, see
   ZELDA_AGENT.md) instead of continuing to discover obstacles by bumping into them. The room's
   objects are already cataloged with tile IDs and positions in
   `zelda_puzzle_packet_starting_house.json` -- reuse that to mark blocked cells, then run a real
   pathfind (A*) to Tarin instead of another hand-picked direction sequence. Movement precision
   itself is no longer the blocker (see "Movement model" above).
1. Once routed, re-attempt `h1_reread_tarin` from `zelda_puzzle_hypotheses_starting_house.json` --
   walk to (80,120)/(80,128) precisely and capture Tarin's full dialogue. Puzzle-solving embryo
   (packet + validator + hypotheses) is built and ready to consume the result the moment this is
   reachable.
2. Get past the door, talk to a villager outside — 3rd independent tile-ID cross-check (original
   session 1 ask, still not done), starts populating the map graph beyond the starting room.
3. Find the sword (known early-LA beat) — unlocks `cut_grass` and real combat.
4. Cut grass once the sword is found — last untested primitive from the original scope.
5. Re-test pause once outside — the lock may be tied to "still inside the intro house" rather
   than a general early-game milestone; worth confirming either way.

## Open questions (not blockers, just unresolved)
- Numeric confidence percentage vs. discrete tiers for the data model (see ZELDA_AGENT.md) —
  leaning tiers, not settled.
