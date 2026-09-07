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

## Navigation overhaul: tile catalog + directional cell grid (post-chantier-A)

User feedback after chantier A: navigation still isn't good enough -- RoomMap::Recorder maps a
screen by blind trial and error, re-learning the same terrain (grass, walls) from scratch on
every single screen, and never sees the difference between "wall" and "one-way ledge" since it
only records a raw :ok/:blocked outcome, not what the tile actually is. Mandate: build a system
that looks at the screen and infers walkability like a human would, backed by a fact about the
game (a background tile never changes what it is over the course of the game) into a persistent,
cross-screen tile catalog, explicitly modeling one-way obstacles (confirmed in the DX manual --
see below), before resuming any other exploration. A full plan was proposed and approved before
starting (see chat; not duplicated here).

**New components, all in `lib/game_agents/zelda/`:**
- `tilemap_reader.rb` -- reads the BG layer's visible 20x18 tile grid directly from VRAM (mirrors
  `PPU::DotDrawer::CGB#compute_background_pixel`'s own addressing math, but callable standalone,
  no render-loop side effects). **Real finding along the way**: despite the ROM's `_dx.gbc`
  filename, `mmu.model.cgb?` is actually `false` for it at boot (no `--cgb` flag forcing CGB on
  this dual-compatible cartridge) -- it runs in plain DMG mode, which has no per-tile CGB
  attribute byte at all. `TilemapReader` is mode-aware; reading VRAM bank 1 on a DMG `@vram`
  (allocated with only 1 bank) silently returns `nil`, not an error, so this could have caused a
  confusing crash rather than a clean skip if left unguarded. Validated by dumping
  `overworld_front_yard`'s grid as ASCII and confirming it visually matches a screenshot exactly
  (grass checkerboard, the door as a 2-wide column, the house block, the bush row).
- `tile_catalog.rb` -- persistent catalog (`data/tile_catalog.json`), keyed by a hash of the
  tile's actual pixel pattern + palette (not its raw tile_index, which is only stable within one
  VRAM bank/addressing combination). Each entry: `category`, `passable_from` (a set of confirmed
  *travel* directions, so a ledge only leapable downward is `[:down]` -- never inferred
  symmetric), `confidence` (`:hypothesis`/`:confirmed`), `source`, `requires_item`. `requires_item`
  exists because the manual states Flippers are used *automatically* once obtained, implying water
  is likely a hard block before that -- a hypothesis to verify, not yet exercised.
- `tile_classifier.rb` -- tests one **gameplay cell** of movement (16x16px = 2x2 BG tiles,
  matching `move_tiles`' real step size) and feeds the result into the catalog: `:ok` records
  `passable_from` for the direction actually traveled; `:blocked` hypothesizes `:wall`, but never
  overwrites a tile that already has *any* confirmed passable direction (a door blocked from one
  side isn't a wall). Cell identity uses exact integer arithmetic on Link's calibrated feet
  position -- no more `SNAP_RADIUS` fuzz-matching.
- `screen_map.rb` + `screen_grid.rb` -- frontier walk over cells, BFS pathfinding on confirmed
  `:ok` edges. Before physically testing a direction, checks `TileCatalog#skip_outcome`: skips
  (no movement) if either every one of the target cell's 4 tiles already has *this exact
  direction* confirmed passable, or every tile is hypothesized `:wall`. No "all `:walkable` ->
  skip anything" shortcut -- that would assume symmetry from one data point, which doors/ledges
  disprove. `RoomMap::Recorder` remains the cross-check tool, not replaced.

**A real bug found and fixed before this worked at all**: the skip path initially checked
`catalog.known?` (category resolved), but `TileClassifier` only ever wrote `passable_from` with
`category: :unknown` by default -- `known?` was therefore *always false*, so nothing was ever
skipped and the very first live test (30 cells, front_yard) took **80 minutes**. Fixed by (a)
adding `tracked?` (any data at all, whatever the category) as the real skip gate, and (b) having
`:blocked` outcomes actually feed the catalog too (hypothesized `:wall`), which was previously a
no-op. Verified the fix with an isolated, emulator-free unit test of `skip_outcome` before paying
for another live run. Measured real effect on a 2nd pass over the same screen with a catalog
carried over from the 1st: 12/25 direction checks skipped (48%) vs. 4/29 (14%) cold, wall-clock
390s -> 223s.

**Cross-validation finding**: `overworld_front_yard`'s starting cell's `:down` direction resolved
differently between the two tools -- `RoomMap` (which tests `down` first) found it `:ok`;
`ScreenMap` (which originally tested `up` first) found it `:blocked`. Root cause: this engine's
already-documented order/approach-dependent collision (see "Movement model" below) -- testing
`up` first moves Link, then reverses him back to nearly-but-not-exactly the same pixel position
before `down` is tried, changing the outcome. Not a new bug; `ScreenMap`'s direction order was
changed to match `RoomMap`'s default (`down, left, right, up`) so the two tools stay comparable,
but the underlying quirk is real and any future asymmetric result near a cell boundary should be
suspected of this before being trusted as a genuine one-way obstacle.

**Manual consulted** (`Notice_Zelda.pdf`, user-provided -- this sandbox's web egress is blocked
for generic domains, WebFetch/WebSearch returning `EGRESS_BLOCKED` even for manualzz.com,
archive.org and en.wikipedia.org, so it could not be fetched independently): confirms `LEAPING`
(off a ledge) is a **basic, itemless move**, available in the overworld and dungeons, one-way
(down only, "if there is no obstacle at the edge") -- directly validates the `ledge` category and
its asymmetric `passable_from` design. Also: swimming is automatic *once Flippers are obtained*,
not from the start (motivated `requires_item`). Also caught and worth a separate follow-up: the
starting-house NPC logged all session as "Tarkin" is actually named **Tarin** per the manual
(Marin's father) -- a transcription error, not a new character; the manual also names several
village NPCs never encountered yet (Grandpa Ulrira, Mr. Write, Crazy Tracy, the Owl), confirming
the village extends well past the 3 NPCs found so far.

**Status**: architecture built and validated on `overworld_front_yard`, `overworld_screen2` and
`starting_house` (`data/screen_maps/` + `data/tile_catalog.json`, all committed); `overworld_screen3`
partially built (see below). Each screen's build is still slow in absolute terms (~1.5-5h for a
full sweep, dominated by real per-attempt frame-timing cost, not the catalog logic) -- the
catalog's payoff is cumulative across screens/sessions (screen2's rebuild: 130 skipped vs. 30
tested; starting_house: 99 skipped vs. 40 tested). Not yet done: integrating the manual's terrain
categories as testable hypotheses, full village discovery, revisiting `house2_interior` with this
tool, and resuming `starting_house`'s exploration past its `max_cells: 30` cutoff (4 frontier cells
-- `[2,6]`, `[3,6]`, `[4,7]`, `[1,7]` -- still unresolved, queued but not yet reached).

**Two real bugs found and fixed while pushing front_yard past its first ~18 cells:**
1. `TileClassifier.probe`'s `:blocked` branch trusted `before_cell` unchanged on a non-`:ok`
   result instead of re-measuring the actual landed cell -- a `:blocked`/final-retry outcome can
   still carry several px of real "corner-slide" creep (up to nearly a full cell), occasionally
   enough to land in a cell that's neither `before_cell` nor the expected target. Fixed by
   re-deriving the real cell via `cell_for(after_pos)` and returning a new `:lost` outcome when it
   disagrees with both, rather than silently mislabeling drift as "stayed put".
2. `retries: 8` was too tight for a handful of "squeeze" cells needing a slow multi-press approach
   near a cell boundary (measured case: 2px short of the boundary after 8 attempts) -- bumped the
   CLI default to `retries: 20` (`run_screen_map.rb`), confirmed via replay that every previously-
   stuck cell in front_yard's "south cluster" eventually succeeds given the larger budget; none are
   permanently unrecoverable.

**Data-loss bug, fixed**: `run_screen_map.rb` only saved the catalog/grid on `ScreenMap.build`'s
*normal* return, so a `timeout`-wrapper SIGTERM (or any hard kill) mid-build lost the entire run's
discoveries -- confirmed losing an 18-cell, ~1h run this way. Fixed with an `on_grid_ready:`
callback (`ScreenMap.build` hands the caller a live reference to the in-progress grid the moment
it's created) + `Signal.trap('TERM'/'INT')` in `run_screen_map.rb` that saves the real
in-progress state before exiting. Validated: a subsequent SIGTERM'd run saved real, consistent
partial data instead of nothing.

**Door-exit input lock, found and fixed**: right after loading the `front_yard` checkpoint (saved
mid-door-exit, `Scenarios.front_yard`'s tail is a "walk south out the door" sequence), every
direction except `:down` produced **exactly 0px** on single presses -- not even the creep a real
wall bump leaves. A few more `:down` presses clear it, after which all directions behave normally.
`ScreenMap.build`'s own exploration never hit this because `DIRECTIONS` happens to test `:down`
first and every checkpoint built so far exits south -- pure luck, not a guarantee for a future
checkpoint entered from a different direction (e.g. `house2_interior`). Fixed generically:
`TileClassifier.clear_entry_lock!(entry_direction:)` runs one full `probe` in the known entry
direction before any navigation -- a normal multi-press cell crossing already presses far more
than the few px the lock needs to clear, so it's a side effect of the very first real step, not a
separate detection mechanism (an earlier single-press auto-detect version was tried and discarded:
a press in a still-locked direction can show a few px of *reversed* drift from the previous step,
not real free movement, which fooled a naive "did position change" check). `ScreenMap.navigate!`
(new, in `screen_map.rb`) is the actual A-to-B primitive this catalog was built for: given any
current position and a target cell, computes the path via `grid.path_to` and executes it via
`walk_path!`, no live tile testing at all. Validated end-to-end on `front_yard`
(`[5,5]` spawn -> `[5,3]` -> `[5,7]`, both hops landing exactly on the expected cell).

**Cross-validation, done for the 2 screens with both graphs**: compared `ScreenGrid` against
`RoomMap::Recorder`'s empirical graph (converting room_map's pixel nodes to gameplay cells).
`front_yard`: 4/4 agree. `overworld_screen2`: initially 3 mismatches, all traced to the *older*,
already-committed `screen_map` predating this session's catalog corrections (a tile the old,
buggy exploration had hypothesized `:wall` got corrected to passable by a later, unrelated
screen's test -- `record_passable!` resets a wrong `:wall` hypothesis, exactly as designed, but
the stale `screen_map.json` was never rebuilt against the corrected catalog); rebuilding
`overworld_screen2` from scratch resolved all 3, leaving one residual "disagreement" that's a
known `RoomMap::Recorder` artifact, not a real bug: its `record_move` accepts the *first* attempt
whose delta exceeds `SNAP_RADIUS` as `:ok` and stops, even when that's only a partial step toward
a screen-scroll boundary that needs several more presses to actually trigger -- so a genuine
scroll-exit edge can get recorded as an in-room `:ok` instead of `:scroll`. `starting_house` and
`overworld_screen3` don't have a `ScreenMap` yet (see below) so aren't cross-validated.

**Cross-validation, `overworld_screen3` (done later, after both graphs existed)**: same method
(RoomMap's 3 pixel nodes -> gameplay cells via `TileClassifier.cell_for`), a pure data comparison,
no live emulation needed. RoomMap's `villager_screen`-era graph is tiny (3 nodes: `[2,9]`, `[3,9]`,
`[3,8]`) with several duplicate append-only edge entries (de-duped by `[cell, direction]` before
comparing); of 8 unique edges, 5 agree outright and the 3 that don't are both explained by the same
two already-documented `RoomMap::Recorder` limitations, not new bugs:
- `[2,9]->right` and `[3,9]->right` both recorded as a same-node self-loop (`0->0`/`1->1`, "ok" but
  landing back at the starting node) where `ScreenGrid` records `:exit` -- exactly the
  `SNAP_RADIUS`-vs-scroll-boundary artifact already found on `overworld_screen2` above: a partial
  step toward the screen's real east exit (visible in the world map as the "à l'est" stub, never
  followed) reads as "no real move" to RoomMap's coarser sampling.
- `[2,9]->up` recorded as a same-node self-loop while `ScreenGrid` confirms a real `:ok` -- same
  root cause as `overworld_screen2`'s residual disagreement (this engine's order/approach-dependent
  "creeping collision", see "Movement model" below): a small enough real displacement snaps back to
  the nearest known `RoomMap` node (itself) without creating a new one, even though the move was
  genuinely a step, not a bounce.

No real disagreement found on any of the 4 mapped screens once each known `RoomMap` artifact is
accounted for -- `ScreenGrid` is trustworthy against the empirical baseline everywhere it's been
checked.

**A fifth, minor bug found while extending `overworld_screen3` further (46 vs. 39 cells, 34
resolved): `ScreenGrid#edges_for` silently polluted the saved grid with phantom cells.** After a
second `ScreenMap.build` pass (`max_cells: 60`, `status: exhausted`), several cells came back with
`edges: {}` (e.g. `[2,4]`, `[4,4]`, `[6,4]`) that never once appeared in the run's own per-cell
progress log -- meaning they were never popped from the exploration frontier at all, unlike `[6,7]`
and `[6,5]` (genuinely attempted, correctly `SKIPPED` after exhausting their recovery budget, see
above). Root cause: `edges_for(cell) = (@cells[cell] ||= {})` auto-created a `@cells` entry on
*any* read, not just a write -- `ScreenGrid#neighbors`/`#path_to`'s BFS (used by `navigate_to` and
`walk_back_to_cell!` for ordinary in-run pathing, not just the caller-facing `navigate!`) calls
`edges_for` on every cell it merely looks at while walking the graph, so a cell reachable via an
already-confirmed edge but never itself tested got a blank entry silently written into the
persisted grid -- indistinguishable, by content alone, from a cell RoomMap-style tooling would
call a genuine "discovered but not yet explored" neighbor. Fixed by splitting the accessor:
`edges_for` is now pure read (`@cells[cell] || {}`, never mutates), and a new `record_edge!(cell,
dir, outcome)` is the only way to create/update an entry, used by `ScreenMap.apply_outcome!`'s 3
call sites. Verified in isolation (no emulator needed): a `path_to` BFS that walks through and past
several cells no longer adds anything to `grid.cells` beyond what was explicitly `record_edge!`'d,
and a bare `edges_for` read on an untouched cell stays a no-op. Full rspec (1237 examples) and
rubocop stay clean. **Not retroactively cleaned up**: already-saved `screen_maps/*.json` files
(`front_yard`, `overworld_screen2`, `overworld_screen3`, `starting_house`) may still carry a few
phantom zero-edge cells from before this fix -- harmless for pathfinding (an empty-edges cell just
never offers a route through itself) but slightly inflates any "cells pending" count read from
those files (e.g. the Koholint report's stats) until each screen gets a fresh rebuild.

**`overworld_screen3` (villager_screen checkpoint): partially built, `[6,7]` genuinely
unreachable so far.** First pass: 27/40 cells resolved (`data/screen_maps/overworld_screen3.json`,
catalog now 54 tiles), then `[6,7]` failed all 7 attempts and the build aborted with `:lost`.
Root cause fixed properly (see `ScreenMap.build`'s new skip-on-exhaustion behavior above); a
second pass with the fix and `max_cells: 60` reached 29/60 cells before `[6,7]` exhausted its
budget a second and third time (it kept getting re-queued by neighbors discovering fresh `:ok`
edges into it) and was skipped each time without taking down the rest of the exploration --
direct proof the fix works, not just a unit-level claim. Live diagnostic confirms
`ScreenMap.navigate!` to `[6,7]` itself fails, landing one cell short at `[6,8]` -- the problem is
reaching `[6,7]` at all, not testing directions from it once there. OAM dumps show a sprite pair
whose tile IDs and position change between reads in a way the other (static, `flags=33`) decor
sprites don't -- consistent with, but not confirmed as, this screen's known wandering villager NPC
(see "Village NPC survey" below) transiently blocking the path. Stopped the second run manually
(clean `SIGTERM`, safely saved) after observing steady RSS growth over ~1.75h with no sign of
leveling off (roughly 5MB/15s by the end, ~1.4GB total). A quick read of `checkpoint.rb` found no
obvious retained-reference bug: `Checkpoint.load` does a fresh `Marshal.load` per `reset.call`
(one per recoverable retry -- `[6,7]` alone triggered this dozens of times), replacing the old
cpu/ppu/apu/mmu references normally; each reset also allocates a full emulator state (VRAM/WRAM
arrays included), so the growth is plausibly Ruby's allocator not returning fragmented pages to
the OS after heavy large-object churn, not necessarily a true unbounded leak -- not confirmed
either way. Not chased further this session (diminishing returns after ~3.5h combined on this one
screen); a proper follow-up would (a) log the suspect sprite's position across several fresh
attempts at just the `[6,7]` edge to confirm/rule out the NPC-collision hypothesis, and (b) watch
`GC.stat`/RSS on a `ScreenMap.build` run with `GC.compact` called between resets to see if that
alone flattens the growth before assuming a real leak.

**`overworld_screen3`, third pass (after the per-direction budget, SCX/SCY, and catalog-skip-gate
fixes above): 46 cells referenced, 34 resolved, `status: exhausted` (frontier fully drained, not
cut off by `max_cells: 60`).** `[6,7]` (the suspected wandering-villager cell) and its neighbor
`[6,5]` both correctly `SKIPPED` after exhausting their own recovery budget, without stalling
anything else -- same clean behavior already proven on `starting_house`. Several other cells came
back with empty edges without ever appearing in the run's progress log at all; traced to the
`ScreenGrid#edges_for` phantom-cell bug (see the cross-validation section above) rather than a new
exploration issue -- fixed there, not re-run here (a full rebuild is 3-4h; the phantom entries are
harmless for pathfinding, just cosmetic pending-count noise). `[6,7]`'s underlying cause (villager
NPC transiently blocking the only approach) is still not confirmed, just consistently reproduced.

**`starting_house` (after_shield_interior checkpoint): a real `find_link` bug found, plus a
deeper `TileClassifier.probe` limitation exposed, both blocking this screen.** First attempt
started exploring from `[4,7]` and every direction resolved `:exit` -- implausible for an
enclosed room. Root cause: right after Tarkin's dialogue, Link's sprite renders in an idle pose
using non-tile-0 OAM tiles (confirmed via a live OAM dump); `find_link_by_tile` finds nothing, and
with no `stationary_positions` given (`run_screen_map.rb` always passed `[]`), the exclusion
fallback grabs the *first* OAM sprite -- Tarkin, standing at `(80,120)` -- as "Link". Fixed
`run_screen_map.rb` to pass the already-existing `Zelda::Scenarios::STATIONARY_STARTING_HOUSE`
(its 4 coordinates matched the misidentified sprites exactly) whenever `checkpoint_method ==
'after_shield_interior'`; confirmed the fix by re-running -- spawn now correctly resolves to
`[3,3]`, matching Link's real (non-tile-0) sprite position.

That fix exposed a second, independent issue: `[3,3] -> :down` still resolved `:exit`. Live
diagnostic (`probe` run standalone with the correct exclusions) shows this is *not* a
misidentification -- final OAM confirms real Link (tile 0/2) -- but a genuine `TileClassifier`
limitation: the room's open floor lets a multi-press retry sequence cover more than
`SCROLL_JUMP_THRESHOLD` (40px) of real distance while overshooting the immediate `expected`
neighbor cell (landed at `[5,4]`, two rows down, not the adjacent `[4,3]`) -- `probe` only ever
compares against that single expected neighbor, so a same-room jump of more than one cell gets
misclassified as a screen-scroll exit. This is different from the front_yard/screen2 findings
(those were catalog staleness and a `RoomMap::Recorder` artifact); this one is a real gap in
`probe`'s scroll-detection heuristic for rooms with open space, and it would need something
sturdier than a raw pixel-distance threshold to fix properly -- e.g. checking SCX/SCY (real
camera scroll) before trusting a big jump as a screen exit, rather than inferring it from OAM
distance alone. `starting_house`'s ScreenGrid data was discarded rather than committed with a
wrong `:exit` edge in it; the `find_link` fix (`run_screen_map.rb`) is real and committed.

**Fixed in a follow-up pass**: `probe` now checks SCX/SCY (`0xFF43`/`0xFF42`) before and after
each attempt instead of a raw pixel-distance threshold -- `:scroll` only fires when the camera
itself actually panned. Validated against known-good data before trusting it on anything new: on
`front_yard`, `[5,5] -> :down` (an ordinary in-screen `:ok` move) shows `scroll` unchanged
(`[0,0] -> [0,0]`), while `[8,5] -> :down` (a real, already-confirmed screen exit) shows it change
(`[0,0] -> [0,68]`) -- both classify correctly, so the fix doesn't regress the screens already
validated. On `starting_house`, `[3,3] -> :down` (the actual bug) now resolves `:lost` instead of
`:exit`, with `scroll` confirmed unchanged (`[0,0]`) -- correctly recognized as a real same-room
overshoot rather than a screen transition. `:lost` is the right category here (not a new one):
`ScreenMap`'s existing recoverable-retry/skip machinery already handles it, and no other outcome
in the current vocabulary fits "genuinely not a scroll, but not the expected neighbor either".
`RoomMap::Recorder` keeps its own separate, still pixel-distance-based `SCROLL_JUMP_THRESHOLD` --
out of scope here since it's the cross-check tool, not blocking anything.

**A third bug, in `ScreenMap.visit_cell!` itself, found right after the SCX/SCY fix**: a fresh
build still produced almost nothing (`cells: [{row:3, col:3, edges:{}}]`) -- `[3,3]`'s `down`
resolves `:lost` on every single reset (confirmed via a 4-direction diagnostic: `down` lands
`[5,4]` every time, a deterministic diagonal corner-redirect, not transient noise), and the old
code shared ONE recovery budget (`MAX_RECOVERIES_PER_CELL`) across all 4 directions of a cell.
Since `DIRECTIONS` tries `down` first, all attempts were spent retrying the hopeless `down` before
`right` (which resolves `:ok` immediately, landing exactly on `[3,4]`) ever got a turn -- the whole
cell hit its skip threshold without a single direction other than `down` being tried. Fixed by
keying the recovery budget per `[cell, dir]` instead of per `cell` (`ScreenMap.visit_cell!`,
extracted into a new `explore_direction!` to keep the method under rubocop's line limit): each
direction now gets its own budget, and giving up on one direction no longer costs the others their
chance. Validated: rubocop clean (only the file's existing tolerated `ParameterLists` offenses,
plus one more instance on the new method, same category), full rspec suite green (1237 examples),
then a real `ScreenMap.build` re-run on `starting_house` confirmed the fix live -- `[3,3]` now
correctly records `right: :ok` (and only that edge; `down`/`left`/`up` stay unresolved rather than
forcing a cell-wide skip), and the build reached 30 fully-probed cells (34 total referenced,
4 still-empty frontier cells queued by neighbors but not yet reached when `max_cells: 30` cut the
run off cleanly) with **zero cells skipped** for exhausting their budget -- catalog grew from 54 to
92 tiles, 40 live probes vs. 99 skipped via the catalog (71% skip rate, this screen's tiles now
mostly known). `starting_house.json` + the enriched `tile_catalog.json` are committed.

**A fourth, more serious finding: the catalog-skip fast path can produce a wrong edge, found by
simply re-running the same screen with a warmer catalog.** Bumping `max_cells` to try to finish
`starting_house`'s 4 leftover frontier cells and re-running `run_screen_map.rb` against the
now-92-tile catalog produced a *worse* result, not a better one: only 24 cells (vs. the previous
34, several previously-resolved cells like `[5,3]`/`[5,5]`/`[4,2]` came back empty) and,
concretely wrong, **`[3,3] -> :down` now resolved `:ok`** -- directly contradicting the
SCX/SCY-verified, live-tested `:lost` finding above (a real, reproducible diagonal corner-redirect
to `[5,4]`, not noise). The run's own stats prove why: `stats={:skipped=>60}`, **zero `:tested`
entries at all** -- every single direction on every cell was resolved purely from
`TileCatalog#skip_outcome`, no live movement happened anywhere in the whole build. Root cause:
`skip_outcome` decides purely from the TARGET cell's tile pattern + travel direction (by design --
that's the whole point of the catalog), but `[3,3]`'s block on `:down` isn't a property of the
destination tile at all -- it's a position-specific hitbox/corner effect near the *source* cell
`[3,3]` itself (this room's floor tile repeats identically across many cells, so once any
same-pattern cell elsewhere records `passable_from: [:down]` -- plausibly from an entirely
different, unrelated cell sharing the same generic floor pattern -- every cell with that pattern,
`[3,3]`'s target included, is trusted to be safely enterable via `:down`, silently overriding the
specific, already-diagnosed exception). This is the same order/approach-dependent collision class
already documented under "Movement model" and the front_yard/screen2 cross-validation finding, but
it's the first time it's been shown to actively corrupt a *result* rather than just cause two tools
to disagree -- the catalog's core premise ("a tile never changes what it is") holds for the tile
itself, but does NOT extend to "every approach into a tile behaves the same," which this room's
`[3,3]` corner disproves outright. **Not fixed**: discarded the bad rerun (`git checkout --`
restored the good 34-cell/committed version) rather than let a fully-unverified, skip-only rebuild
overwrite real live-tested data. Two credible fixes, neither chosen yet: (a) require at least one
live-tested edge per cell before trusting any of its skip-derived edges (a soft "verify locally,
trust globally" rule), or (b) never let `record_passable!`/`record_blocked!` cross-contaminate
between different screens or even different cells of the same screen when a corner/hitbox quirk is
suspected nearby -- effectively scoping some tile facts to be screen/cell-local rather than
globally cumulative, which cuts against the catalog's original cross-screen premise and needs a
real design decision, not a quick patch. Until decided, treat any all-skip (`stats` with no
`:tested` key) rebuild of an already-explored screen as suspect, not as free validation.

**Fix (a) chosen and implemented, with a real bug of its own found and fixed along the way.**
Added a `live_probed` gate (per-cell, reset fresh at the start of every `ScreenMap.build`):
`resolve_direction!` only consults `TileCatalog#skip_outcome` for a cell once that cell already
has at least one CONFIRMED (non-`:lost`) live-tested edge of its own, forcing the first direction
tried on any not-yet-visited cell (`:down`, given `DIRECTIONS`' order) to always be live. First
implementation attempt marked `live_probed[cell] = true` right after any live attempt, `:lost`
included -- looked right in isolation, but `explore_direction!`'s own per-direction recovery loop
retries the *exact same* `[cell, dir]` after a `reset.call`, and since `live_probed[cell]` was
already (wrongly) true from the first `:lost` attempt, the retry fell straight back into
`skip_outcome` and reproduced the identical wrong `:ok`. Caught by re-validating live rather than
trusting the rubocop+rspec pass alone: an isolated `TileClassifier.probe(cpu, ppu, apu, keys, mmu,
:down, ...)` run 3x fresh against `after_shield_interior` kept confirming `:lost` (landing
`[4,4]`), while the actual `ScreenMap.build` rebuild still recorded `[3,3] -> :down: ok` with
`stats={:tested=>17, ...}` proving live tests *did* run somewhere, just not decisively for this
exact cell/direction. Fixed by only setting `live_probed[cell] = true` when the live probe's
outcome isn't `:lost` (i.e., a genuine edge was actually recorded, not just attempted) --
`resolve_direction!`'s tail:
```ruby
outcome = TileClassifier.probe_and_classify!(...)
live_probed[cell] = true unless outcome == :lost
outcome
```
Re-validated: rubocop clean (7 pre-existing `ParameterLists` offenses, no new categories), full
rspec green (1237 examples), then a real rebuild against the already-warm (92-tile) catalog --
`[3,3]` now correctly resolves to `{right: :ok, up: :blocked}` with `down`/`left` staying
unresolved (`stats={:tested=>47, :skipped=>91}`, 37 cells total), matching the isolated diagnostic
instead of contradicting it. `starting_house.json` + `tile_catalog.json` re-committed with this
data. Fix (b) (scoping some catalog facts away from global reuse) stays unimplemented -- (a) alone
resolved every case found so far; only worth revisiting if a future screen shows the same
cross-contamination pattern surviving this gate.

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

**Update: a 4th NPC found, now that `house2_interior` is reachable.** "Pépé le Ramollo" -- an OAM
sprite pair initially guessed, from a static screenshot alone, to be part of the room's "pot
cluster" (see the `house2_interior` ScreenMap writeup above). `interact()` from the room's now-
mapped ScreenGrid opened a real dialogue box, disproving the pot guess. Full 4-page cycle captured
(confirmed via an 11-`interact()` run showing the exact toggle/loop pattern already established for
the overworld villager): "Heu... Hum... Comment dire? / Téléphone... A l'extérieur... / Pépé le
Ramollo n'a pas l'air / d'être un grand causeur..." Notable: this mentions a telephone "outside" --
plausibly Link's Awakening's canonical phone-booth hint mechanic, read directly from this dialogue,
not assumed from external LA-lore knowledge. Whether an actual phone booth exists and is findable
on this ROM is untested. A second sprite pair (tile 116/118) sitting one tile-row below the first
was suspected as a separate object and tested independently (approached from `[5,4]` facing up,
different cell than the first attempt) -- same dialogue, same text, confirming it's just the lower
half of Pépé's own 4-tile sprite body (a 2x2 tile block, common for anything taller than 8px on
this hardware), not a distinct entity. Only one NPC in the room. The room's visible "4 vase/pot"
shapes are most likely static background tiles, not OAM sprites at all.

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

## House2 navigation — entry re-solved with ScreenMap tooling, in-room navigation still open
Picked back up with the now-validated `ScreenMap`/`TileClassifier` tooling (per-direction recovery,
SCX/SCY scroll detection, the catalog-skip gate) after the section below's older, now-stale entry
sequence was lost and this session's own first live attempt (`house2_door_approach.rb`, kept for
the record) got stuck at the same tall-grass wall the older session had already diagnosed. Route:
`ScreenMap.navigate!` to `overworld_screen3`'s `[6,6]` (the confirmed cell right at the grass
strip's southern edge), then plain `move_tiles` pushes -- not `TileClassifier.probe`, whose retry
budget is scoped to completing *one* gameplay cell and gives up (`:blocked`) well before the room
transition itself triggers -- looped 15x `:down`, 20x `:left`, 11x `:up`. Confirmed live, twice
independently (once via a throwaway diagnostic, once via the committed `Scenarios.house2_interior`
checkpoint replaying the exact same sequence): both runs land at the identical `{y: 124, x: 80}`
with 8 OAM sprites, and a screenshot at that point matches `world_model.json`'s historical interior
description exactly (bed with round headboard, dresser row along the top wall, two more beds,
potted-plant objects, a 2x2 vase arrangement). The room transition itself only fires on the 11th
consecutive `:up` push -- individual pushes had already been reporting `moved=0` for several presses
before that, the same "creeping collision" pattern documented in the movement model, just requiring
more consecutive pushes than any single `probe` call's own retry budget covers. Captured as
`Zelda::Scenarios.house2_interior` (chains off `villager_screen`).

**In-room navigation (the actual historical blocker below) also now solved**: a `ScreenMap.build`
pass over the interior itself -- the exact problem every prior ad-hoc greedy-movement attempt
failed at -- finished cleanly: `status: exhausted` in ~2h5m, 27 cells (rows 2-7, cols 1-8) fully
resolved, `stats={tested: 54, skipped: 72}` (catalog grew 93 -> 97 tiles). `[4,4]` (near the room's
central obstacles) needed several recovery attempts before finally resolving cleanly, and was never
the kind of dead end `[6,7]`/`[6,5]` were on `overworld_screen3` -- no cell was ever `SKIPPED`.
`data/screen_maps/house2_interior.json` is committed; `ScreenMap.navigate!` can now reach any
resolved cell in this room -- e.g. toward the two NPC-candidate sprites or the pot cluster -- purely
from the map, no more live probing needed for already-confirmed cells. Interacting with those
NPCs/objects and resuming the sword search inside this room is the natural next step, not yet done.

## House2 navigation — stalled, root cause not found (historical, pre-ScreenMap)
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
