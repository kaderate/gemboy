# Zelda agent — backlog

Working log for the autonomous push. See `docs/ZELDA_AGENT.md` for the architecture design and
the session 1/2 spike write-up (world model, planner/executor, pause-capture pattern, primitives).
This file tracks task status only; `docs/zelda_world_model.json` and
`docs/zelda_ram_registry.json` hold the actual accumulated game-state data. All three are pushed
regularly so nothing is lost if the session container recycles.

## Status: OUT OF THE HOUSE. h1_reread_tarin confirmed (Tarkin gives Link a Level-1 Shield on a
second conversation, reached via `Navigator.reach_pixel`), and that shield resolved the south-door
gate -- Link is now outside in the front yard. The starting-room puzzle from this session's spike
is fully solved end to end. See "Navigator — pixel-greedy fallback succeeded" and "Exited the
house" below.

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

## Navigator (grid + pathfinding) — built, mechanically sound, hit a real precision limit
Built per the Navigator design discussed with the user (isolated procedure: emulator state +
room map + a goal from a central planner in, `{status, final_position, updated grid}` out).
Components, all in `docs/zelda_navigator.rb` + `docs/zelda_room_grid_starting_house.json`:
- Static walkable grid extracted from the real BG tilemap (`0x9800`, confirmed SCX=SCY=0 so the
  room is fully on-screen) -- cross-checked against the puzzle packet's object catalog and matches
  exactly (Tarin row8/col14, table rows10-11/cols14-17, beds rows4-7/cols2-3, etc., all confirmed
  byte-for-byte). Downsampled to 16px cells (2x2 BG tiles) to match move_tiles's measured step.
- BFS pathfinding to a cell adjacent to a named target, path compression into (direction, count)
  runs to minimize `move_tiles` calls.
- Closed-loop execution: verify real displacement after each run; a shortfall is retried once in
  place (this room's collision is order/approach-dependent, so a single failed attempt isn't
  trusted as a permanent obstacle) before being recorded as a grid correction and triggering a
  replan from the actual current position.
- `nearest_walkable` fallback for when the rounded OAM-to-cell mapping lands on a cell the grid
  disagrees is walkable (Link is standing there, so it must be).

**Tested live against the Tarin route, repeatedly, and the algorithm itself works correctly at
every level** (BFS finds valid paths, compression is correct, the closed loop retries and
replans as designed, corrections persist to disk) -- but never reached Tarin, because of a real,
well-diagnosed limit rather than a bug:

**Root cause of the residual unreliability**: the bed corridor is narrow enough that Link's true
pixel position, rounded to a 16px grid cell, is frequently ambiguous -- different runs (all
deterministic, same script) landed the *same* first move in different cells across attempts, and
once `nearest_walkable` silently substitutes a different starting cell than Link's true one (to
route around a falsely-blocked rounding artifact), the plan's first run is computed for a
position Link isn't actually standing in, producing a spurious "collision" that looks like a new
real obstacle but is actually a bookkeeping mismatch. Confirmed by tracing one run in detail: a
throwaway calibration move landed Link at a cell whose rounding was ambiguous, `nearest_walkable`
silently picked a *different* plausible cell to plan from, and the resulting mismatch is what
produced yet another "newly blocked" cell that contradicted an earlier run's finding for the same
cell. This explains the whole pattern of runs each blocking different, sometimes contradictory,
cells -- it's a 16px-grid resolution problem meeting a genuinely narrow passage, not noise and not
a story gate.

**Not fixed this session** (stopping here rather than continuing to patch around it blind, per the
same discipline as the earlier movement-model investigation). Two credible fixes, not yet chosen:
1. Track Link's continuous pixel position for execution/verification, and use the grid only for
   coarse route planning (which cells to pass through), not for deciding whether a specific run
   succeeded -- removes the rounding ambiguity from the hot path entirely.
2. Validate the Navigator end-to-end on a more open target first (the second NPC, or the door
   itself, both reachable without threading this exact corridor) to prove the full loop out, then
   return to tighten precision for this one narrow passage specifically.

Both `docs/zelda_navigator.rb` and `docs/zelda_room_grid_starting_house.json` are committed with
the base grid corrected for the 3 well-evidenced permanently-blocked cells found this session
((2,4), (3,5), (4,4) in 16px-cell coordinates) and an empty `corrections_from_play` (reset after
each test to avoid persisting the rounding-artifact false positives traced above).

## Navigator — pixel-greedy fallback succeeded (fix 1, chosen and validated)
Went with fix 1 above: `Navigator.reach_pixel` (docs/zelda_navigator.rb) tracks Link's continuous
OAM pixel position directly and never converts to/from grid cells at all -- no rounding, so none
of the grid-based Navigator's ambiguity can occur. Greedy: always try the axis with the larger
remaining delta first, fall back to the other axis then a perpendicular sidestep on a blocked
attempt, re-measure via `find_link` (already precise, see Movement model) after every single
`move_tiles` call. `prefer_axis:` lets a caller override the greedy axis choice with known-good
domain knowledge (see below).

**First attempt still got stuck** (`status: :stuck` at (52,68)) -- greedy chose `:right` first
(larger delta) which walked Link toward a column where `:down` is genuinely blocked (matches the
very first tile-lock sweep's finding at that exact spot). Forcing `prefer_axis: :y` didn't fully
fix it either -- `:down` from the very start position bounces (matches the documented lateral-
redirect quirk). **What actually worked**: run the already-validated concrete opening sequence
(`down(2)`, `right(3)`, `up(1)`) first to clear the room's cluttered entry corridor, THEN switch to
`reach_pixel`-style fine convergence for the final approach. During that fine convergence, a
"blocked" (`moved=0`) `:down` call still let Link creep ~2px closer per call in a slow diagonal
slide -- not a real wall, a shallow collision surface below the detection threshold. Looping this
~25 times converged Link to (78,102), then closing the remaining X gap and forcing one final
facing-right tap (even though `moved=0`, a blocked tap still sets facing direction) let `interact`
finally trigger Tarkin's second conversation. **Result: full dialogue captured, Tarkin gives Link
a Level-1 Shield** -- see `zelda_world_model.json` for the transcript and
`zelda_puzzle_hypotheses_starting_house.json`'s `h1_reread_tarin` outcome.

Concrete validated route (see `zelda_tarin_dialogue_capture.rb`-equivalent in
`docs/zelda_navigator.rb`'s usage pattern): `down(2)` -> `right(3)` -> `up(1)` -> pixel-greedy
converge toward `{y:80,x:112}` -> close remaining X -> force `:right` facing tap -> `interact`.

## Exited the house — the starting-room puzzle is fully solved
With the shield in hand, greedy-navigated back toward the south door (target `{y:148,x:72}`,
same "blocked but creeping" pattern as the Tarkin approach: individual `:down` pushes near the
door reported `moved=0` yet position still crept south a few px each time). After ~7 pushes a
scene transition occurred -- Y/X reset to new coordinates and the screenshot confirmed **Link is
now standing outside**, in a grass front-yard south of the house, house roof and door visible at
the top of the screen, a tree to the northeast and a bush cluster to the southwest.

This resolves the entire session's blocker: the south door was never a pathing bug or an
unconditional story lock -- it was gated on Tarkin's second conversation (getting the shield),
exactly as the puzzle-solving spike's `h1_reread_tarin` hypothesis predicted, using only grounded,
captured dialogue text (never guessed from pretrained LA knowledge). `zelda_world_model.json`'s
`rooms.starting_house.exits.south_door` is updated to `status: RESOLVED`, and a new
`rooms_overworld.overworld_front_yard` entry captures the first observations outside.

**Open question, low priority**: whether the door checks for the shield item specifically, or
merely for having completed that second conversation with Tarkin -- untested, doesn't block
further progress.

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

## Next up (starting-house puzzle done, picking up in the overworld)
0. ~~Build a static walkable-tile grid~~ done (`zelda_navigator.rb`'s cell-based `reach`), but
   superseded in practice by `reach_pixel` for tight spaces -- keep both, prefer `reach_pixel` for
   cluttered rooms and `reach` for open ones where cell rounding isn't an issue.
1. ~~Re-attempt h1_reread_tarin~~ done -- see "Exited the house" above.
2. Explore the front yard, talk to a villager outside — 3rd independent tile-ID cross-check
   (original session 1 ask, still not done), starts populating the map graph beyond the starting
   room. `rooms_overworld.overworld_front_yard` in the world model has the first observations.
3. Find the sword (known early-LA beat) — unlocks `cut_grass` and real combat.
4. Cut grass once the sword is found — last untested primitive from the original scope.
5. ~~Re-test pause outside~~ DONE, see "Pause menu — now available outside" below.
6. Low priority: confirm whether the door's unlock condition is the shield item specifically or
   just having completed Tarkin's second conversation (see "Exited the house" open question).

## Pause menu — now available outside
Tested via `tap_key(:start)` right at the front-yard checkpoint: the pause/inventory-select wheel
(8 numbered slots, "APPUYEZ SUR SELECT" prompt) opens correctly. Confirms the earlier hypothesis
in `zelda_world_model.json` -- the lock observed inside the starting house was tied to that
specific pre-shield/pre-exit game state, not a general early-game restriction. Reusable checkpoint
for further scripted exploration now lives in `docs/zelda_scenario_exit_house.rb`
(`reach_front_yard(cpu, ppu, apu, keys, mmu)`) so the slow opening sequence doesn't need
re-deriving in every new script.

## Open questions (not blockers, just unresolved)
- Numeric confidence percentage vs. discrete tiers for the data model (see ZELDA_AGENT.md) —
  leaning tiers, not settled.
