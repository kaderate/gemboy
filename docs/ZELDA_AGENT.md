# Zelda-playing agent — design notes

Local, gitignored (see CLAUDE.md). Design discussion for having Claude play Link's Awakening DX
through gemboy over a long session, token-efficiently. Not a committed feature — a running
notebook. ROM is `roms/zelda_la_dx.gbc` (gitignored, not versioned).

## Why not frame-by-frame vision

A screenshot-per-decision loop is untenable: thousands of inputs per screen transition, most
frames contain no real decision ("walk in a straight line"), and vision tokens/turns add up fast.
Decouple *execution* (many frames, zero LLM cost) from *decision* (few calls, well-informed).

## Three-tier architecture

1. **Deterministic execution** between decisions — reused headless-input pattern already in the
   repo (`FakeKeys`, cycle-scheduled taps, `profiling/bench/`). Runs autonomously until a
   code-detected trigger fires: room/screen ID change, health drop, position stuck after N
   attempts (same idea as `STUCK_PC_THRESHOLD` in `rom_test_runner.rb`), textbox open, enemy in
   OAM within engagement range, puzzle object detected.
2. **RAM state, not vision, for facts.** Position, room ID, inventory, health: read directly from
   known addresses once mapped. Reliable, cheap, exact — vision is a fallback only (unmapped
   state, or a sanity check), never the primary channel.
3. **LLM decisions only at trigger points**, fed compact structured state, not images.

## Text/dialogue: pixel-bitmap matching, not tile-ID lookup

**Empirically confirmed, not assumed** (spike session, see below): dialogue tiles are NOT stable
character codes. The renderer reuses a **fixed scratch-buffer tile range** for text —
`0xD0-0xDF` (line 1) and `0xE0-0xEF` (line 2) in the observed room — rewriting the pixel content
of those tiles fresh for every textbox, regardless of speaker or content. Confirmed byte-for-byte
identical tile-ID sequences across two different NPCs with completely different dialogue text.

Consequence: decode text by reading each referenced tile's raw 8×8 pixel bitmap (via VRAM +
gemboy's own `Tile`/`BPPDecoder`) and matching against a font dictionary built once
(bitmap-hash → glyph), never by tile ID. A one-time static ROM text dump is a nice-to-have for
completeness later, not the primary extraction path — live capture-at-textbox already works and
needs no ROM-compression reverse engineering.

## Intra-screen mode state machine

```
Explore (default)
  ├─ enemy detected (OAM, engagement range) → Combat
  ├─ puzzle object/switch detected           → Puzzle
  └─ screen edge reached → room transition → next Planner cycle

Combat
  ├─ enemies cleared → Explore
  └─ no progress after N attempts, or health below safety cutoff → escalate to Planner
     (never grind to zero HP; some enemies are environmental/unkillable by design —
     Zora in deep water, beam turrets — this is the generic detector that catches them
     without needing a pre-built bestiary)

Puzzle
  ├─ solved  → Explore
  └─ blocked (no solution from observed data) → escalate to Planner
```

Combat detail: a single generic safety net (attempts-without-visible-progress + hard HP floor)
works day one, no bestiary needed. Per-enemy-type classification (this one needs bombs, that one
is a hazard not a target) is learned incrementally: log every escalation with full RAM context,
invest in identifying the exact flag only once a case recurs — cost paid per distinct case, not
per encounter.

Puzzle detail (overworld + dungeon): treated as a **bounded, isolated reasoning step**, not
free-form chat. Input packet = current room + adjacent known rooms' data, inventory, relevant
text-corpus entries, the specific blocker observed — nothing else. Anti-cheat-by-pretraining
measure: every named entity in the proposed plan is cross-checked by a **code validator** (not
self-restraint) against the known-facts store; anything referencing an unobserved room/item/
mechanic is flagged, not silently trusted. This is a discipline, not a hard guarantee — Claude's
weights already encode this well-known game — but it makes every decision's grounding auditable.

## Pause-capture decision pattern

Capture compact state **just before** pressing START, then actually pause. Two real benefits
beyond the "thinking is free" property (already true since the driver doesn't advance emulated
time while reasoning regardless):
- **Zero drift.** A real pause freezes all game logic (enemies, timers, animations). Whatever was
  captured pre-pause stays valid no matter how long reasoning takes — no risk of acting on stale
  info the way a live/real-time system would.
- **Clean, low-noise state.** The pause/inventory/map screen is a stable, game-structured view
  (hearts, inventory, map) vs. a live frame that might be mid-animation. Also a natural moment to
  re-equip the item appropriate to the next mode (sword before combat, bomb before a cracked-wall
  puzzle).

Not yet verified in gemboy: what the actual pause screen shows, and that START behaves cleanly
mid-navigation-script. First item in the spike below.

## Planner / Executor split

- **Planner**: invoked when an Executor reports done/blocked, or on room transition. Reasons over
  the World Model (map graph, inventory, quest flags, text corpus) to pick the next bounded
  macro-goal. Low frequency, wide context.
- **Executor**: one bounded macro-goal, runs the mode state machine autonomously, only escalates
  at pause-captured decision points, reports a structured result back. Combat and Puzzle are
  natural candidates for a dedicated **sub-agent per encounter/puzzle** (not per keystroke — the
  sub-agent loops internally via its own tool calls until resolved, then reports once). Explore
  stays fully scripted/deterministic — no judgment calls in walking an empty corridor, a sub-agent
  there is pure waste.

## Data model: confidence must be traceable, not vibes

Every fact carries provenance, not a felt percentage. Confidence is a function of two measurable
things: **source tier** (`ram_read_verified` ≥2 independent cross-checks > `ram_read_hypothesis`
one-off > `vram_glyph_match` > `assumed_stale`, decaying with actions elapsed since last direct
observation) and **`verified_count`** (same cross-validation discipline already used empirically
for the dialogue tile-ID finding above — confirm twice in different contexts before trusting).

```json
{
  "value": 3,
  "source": "ram_read_verified",
  "address": "0xDB5A",
  "verified_count": 2,
  "observed_at": {"room": "0x0A", "action_seq": 142},
  "confidence": "high"
}
```

Open question, not yet settled: discrete tiers (`verified`/`probable`/`hypothesis`/`assumed`) vs.
a numeric percentage. Leaning tiers — a percentage implies precision ("why 90 and not 85?") that
doesn't actually exist; `verified_count` is the real number, confidence is just a readable label
over it.

## Storage: one source of truth, filtered views per agent

- **World Model** (persistent JSON): map graph (rooms, known exits, confidence per edge),
  inventory, NPCs encountered, text corpus, quest flags. Updated automatically by deterministic
  RAM reads at each decision point — mechanical, not an LLM judgment call.
- **RAM address registry** (separate file): the address hypotheses themselves
  (`0xDB5A → "life"`), each with its own `verified_count`, promoted from hypothesis to confirmed
  via the same empirical cross-validation discipline used for the tile-ID finding. Foundation
  everything else reads through.
- **Per-mode views**: Combat/Puzzle/Explore each get a filtered projection of the World Model
  scoped to what they need — no separate copies, no drift between stores.
- **Action log**: append-only JSONL, one line per action actually executed (scripted macros
  included, tagged `decided_by: "scripted"` — no LLM cost, still logged), each entry carrying
  pre-state (confidence-tagged), the action taken, `decided_by`, and the observed outcome delta.
  Feeds three things: debugging/audit trail, confidence recalibration (a "high" confidence fact
  that turned out wrong should downgrade its source), and the anti-cheat validator's evidence
  trail for puzzle reasoning.

## Spike log (this session)

Confirmed working: save-file creation flow (title → file select → name entry → gameplay), two
distinct in-room NPC dialogues triggered and read cleanly via framebuffer crop + nearest-neighbor
upscale (native 160×144 is below Anthropic's own <200px vision reliability warning — always
upscale, 4-6x is enough and still ~500-1100 tokens/image), the tile-ID scratch-buffer finding
above.

Not yet done / open: pixel-navigation via blind d-pad + screenshot trial-and-error proved
expensive and error-prone (repeatedly misidentified which OAM sprite was Link vs. a stationary
NPC). **Needs Link's actual RAM position** for reliable navigation — a WRAM-diff approach
(quiet-vs-quiet control diff to filter animation/timer noise, per-tap before/after diff) was
started but didn't isolate the address within budget. This is the concrete next unblock, not an
open feasibility question — the mechanism (diff a controlled action against an idle control) is
proven, just needs another pass with tighter isolation (e.g. diff many single-tile taps and keep
only bytes that move by a consistent small delta every time, not just once).

### Session 2: primitives + pause availability

Prototype primitives module: `scratchpad/bench/zelda_primitives.rb` (session-scoped tmp, not
committed — see note below). Ended up not needing the WRAM address hunt to become unblocked:

- **`find_link`**: Link has **no fixed OAM slot** — the game reassigns which of the 40 sprite
  slots renders him between frames (confirmed: a moving sprite pair at slot 16/17 one frame
  reappeared at slot 2/3 the next, same approximate position, different slot). Worked around by
  exclusion instead of address-hunting: read all active OAM sprites, drop any matching a
  known-stationary NPC's fixed (Y, X), whatever's left is Link. Good enough for a single room with
  no wandering third sprite; a real WRAM address will be needed once enemies/moving NPCs share a
  room with Link. OAM reads can land on a transient frame where Link's sprite briefly isn't drawn
  (mid-animation) — `find_link` retries a few times with a short settle rather than trusting one
  sample; fixed the very first flaky result.
- **`move_tiles(direction, n)`**: one tile at a time, each step verified against real OAM
  displacement (not "hope the hold duration was right") — stops early on a wall/object collision
  instead of overshooting blind. Tested clean: 3/3 tiles down, correctly stopped at 1/3 tiles left
  (blocked by the table). This replaces the trial-and-error tapping from session 1 entirely.
- **`interact`** (talk / lift-pot, same input — a single A tap): reused as-is from the already-
  validated talk primitive. Walked Link to a pot via `move_tiles` and made contact; game responded
  with the same "too heavy" message as session 1's accidental encounter — confirms the primitive
  triggers the right game response even when the *outcome* isn't a successful lift (this pot needs
  a strength upgrade item Link doesn't have yet). The primitive is correct; reading the outcome
  (lifted vs. rejected) is a job for the text/dialogue decoder, not the primitive itself.
- **`cut_grass`**: not tested. The HUD shows both B and A item slots empty (`B[ ] A[ ]`) this
  early — Link has no sword yet (LA's opening: it's found shortly after leaving the house). Nothing
  to swing. Deferred until after the sword pickup rather than forced.
- **START pause menu**: tried mid-gameplay, right after character creation — **no pause screen
  appeared**, gameplay continued unaffected (tried both a short and a generous hold). Pause looks
  to be gated behind some early-game milestone, not available from frame one of a new file. Needs
  re-testing after Link leaves the house. The zero-drift pause-capture design from the last
  discussion still stands as the target pattern — just can't validate the pause screen's exact
  content yet.

Net effect on the earlier open question: navigation is unblocked without needing the WRAM address
first — exclusion-based `find_link` plus self-verifying `move_tiles` is enough to build on now.
The WRAM address remains worth pinning down later purely for robustness in rooms with other moving
sprites, not as a blocker.

Everything under `scratchpad/bench/zelda_*.rb` referenced above lives in the session's temp
scratchpad, not this repo — copy anything worth keeping into a real location before it's gone.
(Update: `zelda_primitives.rb` has since been copied to `docs/zelda_primitives.rb` and tracked —
see session 3.)

### Session 3: autonomous push — hit a real story gate, primitives held up under more use

See `docs/ZELDA_BACKLOG.md` for the live task status; this is the narrative summary.

Set up `docs/ZELDA_BACKLOG.md` and the `zelda_world_model.json` / `zelda_ram_registry.json` data
files (this session's "note your own progress" ask) — all four docs files now tracked via
`.gitignore` exceptions rather than living only in the ephemeral session scratchpad.

`move_tiles`/`find_link`/`interact` held up across ~20 more calls. Two new findings, both now in
the backlog: **(1)** `move_tiles` only checks direction *sign*, not magnitude, so a partial slide
along an obstacle still counts as "moved" — and it has no multi-segment path planning, so chaining
two segments in a cluttered room can silently funnel back to the same bottleneck tile instead of
reaching the intended waypoint (this is what stalled a second attempt to reach Tarin). **(2)** the
starting house's south door is a genuine **story gate**, not a pathing bug — Tarin blocks it with
a repeating, repositioning message, survives fully exhausting the second NPC's dialogue and a 10M-
step idle wait, and a bracketing WRAM diff came back too noisy (28 changed bytes, dialogue-open
side effects mixed in with whatever the real gate flag is) to isolate in one pass.

Separately, re-attempted the Link-position WRAM hunt with a stronger method than session 1's
single before/after diff: keep only addresses with a *consistent* small delta across 4 repeated
same-direction taps. That found 4 real candidates in one pass (a much stronger signal) — but a
follow-up direction cross-check (RIGHT/LEFT should flip sign, DOWN should leave a true X byte flat)
ruled out all 4 as animation/step counters, not coordinates. Decision: keep OAM-exclusion as the
accepted method; the stronger diff method itself is worth reusing for the door-gate flag hunt.

Stopped for this session on the door gate specifically — diminishing returns on further blind
retrying — rather than a hard blocker on the overall approach. Everything else (primitives,
tracking infra, methodology) is in good shape to resume from.
