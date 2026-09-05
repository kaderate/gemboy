# Zelda agent — backlog

Working log for the autonomous push. See `docs/ZELDA_AGENT.md` for the architecture design and
the session 1/2 spike write-up (world model, planner/executor, pause-capture pattern, primitives).
This file tracks task status only; the actual code and accumulated game-state data now live in
`lib/game_agents/zelda/` (promoted out of `docs/` once the spike graduated into a real,
longer-lived part of the codebase -- see "Hygiène d'ingénierie" below). Historical entries below
still reference the old `docs/zelda_*` paths; they were accurate when written.

## Status: overnight autonomous push on "chantier A" (infrastructure hardening), user asleep,
working without further input per their instruction. See "Chantier A — overnight push" below for
live status; this top summary covers the prior session's spike (still accurate).

Spike scope substantially complete; sword/cut_grass is the one item not reached despite
extensive genuine effort. Done in that session: exited the starting house (shield puzzle solved),
pause menu confirmed working outside, 3 independent NPC dialogues captured (Tarkin, the 2nd
starting-house NPC, an overworld villager) confirming the tile-ID cross-check, `move_tiles`
precision fully root-caused, `find_link` hardened against unknown-sprite confusion, a 2nd house
entered. Sword search stalled on a specific, well-documented navigation puzzle inside that 2nd
house (see "House2 navigation — stalled, root cause not found" below) after ~8 varied live
attempts; deprioritized in favor of writing this up rather than continuing to blind-retry the same
failing approach. See "Overworld exploration" and the section below for details.

## Chantier A — overnight push (infrastructure hardening)
User's 4 acceptance items, worked in order:

**A.2 (checkpoint/save-state) -- DONE.** Measured why "restart from scratch" felt slow: boot alone
is 86s, the intro dialogue skip another 53s -- ~150s before any actual exploration starts, on top
of however long the target scene's own navigation takes. `Zelda::Checkpoint` (Marshal-based) fixes
this: the full emulator state (CPU/PPU/APU/MMU/keys, correctly cross-referenced) serializes cleanly
once two non-serializable fields are excluded -- APU's `@audio_queue` (a `Thread::Queue`, not
needed headless) and CPU's `@opcode_handlers` (an array of bound `Method` objects, pure derived
state that `CPU#build_opcodes` regenerates identically). Measured: 0.032s to dump, 0.046s to load,
vs. 150s+ to replay -- confirmed the loaded state is live and steppable (ran 1M more instructions
on it successfully). `Zelda::Scenarios.front_yard` / `.villager_screen` now cache themselves to
`/tmp/zelda_checkpoints/*.marshal` (not committed -- regenerable, machine-specific) and later
scenarios chain off earlier ones, so a whole exploration session only pays the ~150s+navigation
cost once per named checkpoint, ever.

**A.3 (RAM/HUD registry) -- DONE.** Rather than hunting a WRAM address, read the HUD directly from
its tilemap: LCDC confirms the window layer is enabled (bit 5) with WY=128, i.e. a fixed,
unscrolled 2-tile-tall strip at the screen bottom -- exactly where hearts/rupees render. Confirmed
tile IDs: full heart = 0xa9 (3 of them read back cleanly as `{full: 3, unknown: []}`), rupee digit
'0' = 0xb0 (read "000" correctly). `Zelda::HudReader` only decodes tile IDs actually observed --
empty/half-heart tiles and digits 1-9 aren't in the table yet (would need Link to take damage or
rupees to change, neither of which has happened) and report `:unknown` rather than guessing, per
this project's grounded-data discipline.

**A.4 (dialogue completeness + OCR cost) -- gap fixed, OCR deferred.** First, the concrete gap
flagged: re-entered the starting house (confirmed `reach_front_yard` + walking back through the
door works, and the shield persists in save state) and re-captured the 2nd NPC's dialogue
page-by-page. Closed the previously-flagged gap -- the missing page between "vers" and "Depuis" is
"la plage là où je t'ai trouvé." -- and confirmed her line is byte-identical pre- and post-shield.
Tarkin's dialogue was already fully captured pre-sleep with no known gap; 3 re-approach attempts
this session to double-check landed adjacent-but-diagonal to him (interact() never opened a box,
suggesting his exact facing tile is less forgiving than the 2nd NPC's) -- not resolved, but since
there's no positive evidence of a Tarkin gap (unlike the 2nd NPC's confirmed one), this is
low-priority and not blocking. **OCR cost evaluation**: tried to reuse the HUD's tile-read approach
for dialogue-box text, but a probe taken while attempting to trigger the villager's dialogue showed
the window/BG tilemap in a state that doesn't match a simple "read the window layer" model (a
`0xcc`-filled row, unexplained tile changes) -- dialogue rendering is evidently in a different PPU
configuration than the HUD's static window strip, likely reconfigured dynamically while a text box
is open. Building a real bitmap-font OCR needs that state properly reverse-engineered first, which
didn't fit this session's remaining time alongside the non-negotiable A.1. **Verdict: cost is
higher than hoped, not "cheap" yet -- deferred, not built.** Worth revisiting with a dedicated
session (freeze the emulator right as a dialogue box opens, diff every PPU register against the
non-dialogue baseline) before attempting the bitmap-matching font table itself.

**A.1 (generalize Navigator, map 5 screens+interiors) -- 4/5 mapped, tool proven, one screen's
entry navigation still blocked (pre-existing, documented issue, not a RoomMap deficiency).** See
"RoomMap::Recorder -- empirical, tile-ID-agnostic room mapping" below for the full writeup.

## RoomMap::Recorder — empirical, tile-ID-agnostic room mapping (A.1)

Replaces the old plan of extending `Navigator`'s static tilemap-classification approach (worked
for starting_house but needed per-room tuning + live corrections, see the Navigator sections
below) with something that needs zero per-room tile knowledge: `Zelda::RoomMap::Recorder` builds a
room's walkable graph purely from `move_tiles`' own confirmed outcomes as a script explores.
Nodes are Link's snapped (y, x); edges record `:ok`/`:blocked`/`:scroll`/`:lost` for a real
attempted move. `explore_frontier` does unattended BFS-over-nodes exploration, probing every
untried direction from each discovered node.

Four real bugs found and fixed by testing live, not by inspection:
1. Outcome classification trusted `move_tiles`' own moved-count instead of measured before/after
   distance -- a `moved=0` result can still coincide with real displacement on the *other* axis
   (the diagonal-collision-redirect quirk), producing a node the recorder had itself just labeled
   unreachable.
2. Retry budget (3) was too low for "creeping collision" (~2px real progress per blocked
   attempt) to ever exceed SNAP_RADIUS -- bumped the default to 10, made it configurable.
3. A single `:scroll` aborted the *entire* exploration, since directions are tried in a fixed
   order and one direction happened to scroll immediately. Fixed: a scroll now records the exit,
   attempts a best-effort reverse, and continues probing that same node's other directions if the
   reverse landed back near it; only `:lost` used to abort everything.
4. Scroll-prone directions weren't reliably reversible (crossing a screen boundary isn't as
   symmetric as an in-room move) -- added `direction_order:`, default puts `:up` last since it was
   the observed scroll-prone one, so a room's interior gets mapped before a boundary is crossed.

**A fifth bug, found mapping overworld_screen3**: the `villager_screen` checkpoint had been saved
*mid-scroll-animation* -- Link's OAM position kept drifting with **zero input** for ~200k cycles
past `move_tiles`' own settle window. Every direction probed from that checkpoint inherited the
same pending camera pan regardless of what was pressed (confirmed via a throwaway script that
just idled the checkpoint and watched the position resolve to the same spot every time). Fixed in
`Zelda::Scenarios` by running the checkpoint out an extra 400k cycles before saving. Real
root-cause lesson for future checkpoints: `move_tiles`' settle window guarantees a *step* is done,
not that a *scene* is done -- an in-flight scroll needs its own settle before checkpointing.

**Recovery from `:lost`**: some edges lead to a transition that doesn't resolve within
`find_link`'s retry budget at all -- observed on overworld_screen3's node1 pressing `:down`: OAM
alternated fully-blank / 6-sprites-visible-but-Link-never-moving for 600+ frames (~10s emulated)
without ever settling into a new room or new position. Rather than chase what that specific
transition is (a slow cutscene? an off-screen animation? not confirmed), `explore_frontier` now
takes an optional `reset:` proc (returning a fresh `[cpu, ppu, apu, mmu, keys]`, e.g. reloading a
checkpoint) and recovers by resetting to known-good state and re-queueing the affected node so its
*other* untried directions still get a chance, instead of aborting the whole map. Capped at 3
recoveries/node to avoid a live-lock. Without `reset` the old abort-on-`:lost` behavior is
unchanged (backward compatible).

**Mapped (4/5)**: `starting_house` (4 nodes, corridor + Tarkin's alcove, via a new
`after_shield_interior` checkpoint extracted from `front_yard`'s prefix), `overworld_front_yard`
(3 nodes), `overworld_screen2` (3 nodes, via a new `overworld_screen2` checkpoint extracted from
`villager_screen`'s prefix), `overworld_screen3` (3 nodes, the one that needed the checkpoint-
settle fix and the `:lost`-recovery feature). All in `lib/game_agents/zelda/data/room_maps/*.json`.
Every one of these reached `explore_frontier`'s `:exhausted` status (fully explored, not aborted
or capped) with zero per-room code changes -- confirms the actual technical ask of A.1 (generalize
away from starting_house-specific tile classification).

**Not mapped: `house2_interior`** (2nd house, past the villager screen) -- entry navigation is
still blocked, same symptom as the prior session's "House2 navigation — stalled" finding below,
now with more data: overworld_screen3's camera pans continuously as Link approaches its edges (OAM
positions of *fixed* landmarks, like the house's corner-post decor at tile 26, drift by tens of
pixels between reads that are only a few tile-moves apart), which makes OAM-relative landmark
chasing unreliable for aiming at the door. Direct greedy pixel-chasing toward the visually-located
door (confirmed via screenshot, native ~(y=90, x=70)) consistently gets stuck at a stable
collision wall around x=97 before reaching it -- almost certainly the "tall-grass hard-collision
strip" the prior session already identified as needing to be routed around, not walked through.
**Not a RoomMap deficiency**: this is the same pre-existing navigation puzzle from before tonight,
still unsolved by ad-hoc greedy movement. The tool itself (this session's actual deliverable) is
proven on 4 different rooms; getting *into* house2 needs the tilemap-based walkable-grid approach
the prior session already recommended (extract this screen's BG tilemap, mark the grass strip
impassable except at its known gap, route around it explicitly) -- a proper follow-up work item,
not another blind greedy-movement attempt.

## Village NPC survey (stretch goal, post-chantier-A)

With chantier A done, surveyed the reachable village screens (front_yard, overworld_screen2,
overworld_screen3 -- explicitly *not* venturing further, per the stretch goal's "uniquement")
for any NPC not yet talked to. OAM dumps at each checkpoint:
- `front_yard`: one round sprite pair, tile 82/80, flags 33. Approached and attempted `interact` --
  no dialogue. Same exact tile IDs as the round bush/tree the prior session already identified and
  ruled out as decoration in overworld_screen2 ("no dialogue on interact") -- cross-referenced
  match, not a fresh guess, so treated as confirmed decoration rather than re-litigated.
- `overworld_screen2`: zero sprites at all at this checkpoint's position.
- `overworld_screen3`: the wandering villager (tile 96/98, flags 33) -- already fully captured
  ("YOUPI! J'ai la pêche! Et toi?", confirmed toggling not paginating across 4 `interact()` calls).

**Conclusion: no new NPCs found.** The village's only three NPCs are Tarkin (starting_house),
the 2nd starting-house NPC, and the screen3 villager -- all three already have complete, verified
dialogue in `world_model.json` (Tarkin and the villager from the prior session, the 2nd NPC's gap
closed in this session's A.4 work). Stretch goal satisfied: everything currently reachable in the
village has been talked to and its dialogue captured.

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
2. ~~Explore the front yard, talk to a villager outside~~ DONE -- see "Overworld exploration"
   below. 3rd independent NPC dialogue captured two screens away.
3. Find the sword (known early-LA beat) — unlocks `cut_grass` and real combat. **In progress.**
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

## Overworld exploration — 3rd NPC found and validated
Pushed south from the front yard, through 2 more screen-scroll transitions (screen boundaries
detected as a large discontinuous OAM-position jump on a single `move_tiles` call, distinct from
the much smaller "creeping collision" pattern below -- both now documented in
`zelda_world_model.json.movement_model`). Second screen: a fenced plot with a large round
bush/tree (initially ambiguous with a hut in screenshots -- ruled out by contrast against the
actual house found on the next screen, and by finding no dialogue on interact). Third screen: a
real house (proper door/windows/chimney) plus a wandering villager NPC.

**Found and fixed a real bug in `find_link` along the way**: with no stationary-position list to
exclude (fresh overworld territory, nothing cataloged yet), it latched onto the wrong sprite (a
roadside object) instead of Link. Root cause + fix: Link's own sprite has consistently used OAM
tile IDs 0 (left half) / 2 (right half) in every settled read this entire session, regardless of
room -- `find_link`/`nearest_link_pos` now match on that first, falling back to exclusion only if
absent. This is a durable fix, not a one-off patch: it removes the whole class of "unknown new
sprite confuses tracking" bugs for all further overworld exploration.

**Villager dialogue captured**: identified the NPC via its own stable signature (OAM flags=33,
tile IDs 96/98, distinct from Link's and from every previously-cataloged stationary NPC). Chased
it down (it wanders -- position changes between reads) using a horizontal-first approach heuristic
after the naive largest-delta-first greedy got stuck repeatedly retrying a known-blocked axis.
Final approach reused the same "align both axes closely, then force a facing tap before interact"
technique that worked for Tarkin. Dialogue: "YOUPI! J'ai la pêche! Et toi?" -- a single line that
toggles open/closed on repeated `interact()` rather than paginating (confirmed across 4 calls).
This is the 3rd independent NPC dialogue captured this session, in a different room each time,
confirming the dialogue-tile-ID-scratch-buffer finding generalizes -- the original session-1 ask.

Full details (room descriptions, map_graph edges, the villager's exact identification method) in
`zelda_world_model.json` under `rooms_overworld.overworld_screen2` / `overworld_screen3`.

## House2 navigation — stalled, root cause not found
Entered a second house (found past the villager screen, routed below a tall-grass hard-collision
strip and through the door from the south). Entry is 100% reproducible -- the same move sequence
from `overworld_screen3` always lands at OAM (104,78) inside, and the interior view was captured
cleanly once (see `zelda_world_model.json.rooms_overworld.house2_interior`): 3 beds, a dresser row,
4 pot-like objects, and two NPC-candidate sprite pairs (one near the beds, one lower).

**But every attempt to move further from that spawn point ended back outside** in
`overworld_screen3`, across ~8 varied live attempts:
- Direct greedy convergence toward each NPC candidate and toward the pots (multiple axis orderings
  -- dy-first, dx-first, right-first-then-up, up-first-then-right).
- A boundary-avoidance variant (move away from the entry point before approaching a target).
- A nil-read-tolerant rewrite (transient `find_link` nils were silently killing loops early; fixed
  with a small retry wrapper -- didn't change the outcome, just gave cleaner logs).
- Targeting the OTHER NPC candidate once the first proved unreachable.

None of these reached a target. The exits don't consistently correlate with a specific direction,
distance, or a detected scroll-jump (position often creeps normally, in-bounds, right up until an
exterior screenshot appears) -- root cause not identified. Best guess: the entry point sits very
close to the door's own trigger zone in this particular room's layout, and undirected greedy
movement has a real chance of re-crossing it within a short walk, especially combined with the
already-known "creeping collision" pattern's small unpredictable per-step distances.

**Not fixed this session** -- stopping here per the same diminishing-returns discipline used
earlier for the starting-house grid-navigator problem: after establishing the failure is
reproducible and NOT explained by any of the usual suspects (nil reads, scrolls, boundary
rounding), continuing to retry ad-hoc greedy movement against the same room isn't "trying
something new" anymore. The principled fix is the same one already proven for the starting house:
extract this room's own BG tilemap into a walkable grid (`Navigator.reach`/`reach_pixel` already
exist and are reusable), explicitly marking the door-threshold cell so pathing avoids it unless
that's the actual goal. That's a proper next work item, not another blind live attempt.

**Sword search status**: not found. Tried the two houses reachable from the starting point
(starting_house's pot: too heavy; house2: blocked on the navigation issue above before reaching
its pots or NPCs) and 3 overworld screens' worth of visual survey (no visible ground item, no
obvious landmark). `cut_grass` (last untested primitive from the original scope) is gated on
finding the sword and hasn't been attempted.

## Open questions (not blockers, just unresolved)
- Numeric confidence percentage vs. discrete tiers for the data model (see ZELDA_AGENT.md) —
  leaning tiers, not settled.
