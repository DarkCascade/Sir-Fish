# Sir Fish — Expedition Phase II: the Rune Floor

**A product requirements document.** It says what the expedition must become and why,
and where the answer is already decided. Where it names a file, a constant or an issue,
that is a real thing in this repo. Read it before changing it.

- **Status:** draft, 2026-09-27. The direction is decided; the open questions in §8
  need answers before their parts are built.
- **Decision:** 10.2 in the backlog doc (§10). The Rune Floor style becomes the default
  for expeditions. It was decided after a phone playtest of the demo on 2026-09-27.
- **Board:** the `rune-floor-spike` label. Epic [#210](https://github.com/DarkCascade/Sir-Fish/issues/210); milestones [#211](https://github.com/DarkCascade/Sir-Fish/issues/211) to [#217](https://github.com/DarkCascade/Sir-Fish/issues/217);
  open questions Q1 [#218](https://github.com/DarkCascade/Sir-Fish/issues/218), Q2 [#219](https://github.com/DarkCascade/Sir-Fish/issues/219), Q3 [#220](https://github.com/DarkCascade/Sir-Fish/issues/220).

---

## 0. In one paragraph

Today an expedition splits the screen in two: the fight on top, and the console below
it (status strip, slot cabinet, special invokers). The two things that matter most, the
fight and the board, sit furthest apart. The Rune Floor puts the board on the ground
between the party and the enemies, under a tactical camera, and moves each hero's health,
charge and special button into one plate per hero at the bottom of the screen. The spike
(PRs #197, #201, #202) proved it on a phone for combat. Phase II makes it the whole
expedition: departure, travel, every encounter type, the boss, the wipe and the return
home. It also sets the path for other expedition types to exist beside it.

---

## 1. Decisions this rests on

| # | Decision | Where |
|---|---|---|
| 7.1 | The slot is the main character mechanically; the party is the emotional read | backlog §7 |
| 10.1 | The Gilded Guppy is a magic lantern: parked behind the party, its reels are the slides, and the amulet Sir Fish was given at his knighting is the lens that projects the board. The board is light, not stone | backlog §10, #196 |
| 10.2 | **The Rune Floor is the default expedition style.** Other styles may exist for variety (§7) | backlog §10 (new) |
| 10.3 | **The dock is design A: hero plates.** Health bar on top, portrait in a segmented charge ring, the special's name in a full-width pill, the whole plate is the special's button | #202, [dock mockups](https://claude.ai/artifact/FQVDmc88ycEfTGLpmijQQQ) |
| 10.4 | **No text below `Tuning.MIN_FONT_SIZE` (36 px, about 13 pt on a phone)** | CLAUDE.md best practice 4, `tests/test_font_floor.gd`, #205 |

---

## 2. Goals and non-goals

**Goals**
- One place to watch. During a fight the player's eyes stay on the island: the board, the
  heroes, the enemies, and the plates under their thumb.
- Legible on a phone. Every piece of text meets decision 10.4, and every control is at
  least 44 pt (about 122 px) in both directions.
- The same rules. The Rune Floor changes presentation only. Bag, draw, paylines, owner
  swings, charge, damage, loot, XP and gold all stay the shipped systems, and the sims
  keep describing the real game.
- The encounter track is a place. The islands ahead of the party are the expedition's
  progress: what is next is visible, not listed.
- Room for more than one style (§7), without two copies of every rule.

**Non-goals**
- No balance changes. Specials rebalance separately (#204); the payline glow is #203.
- No new enemies, items or quests.
- No new biome art. §8 Q1 asks whether biomes can dress the surroundings; Phase II builds
  the hook and the Endless Wood only.
- Not the bandit-camps tutorial (§9 of the backlog), though Phase II must not block it.

---

## 3. An expedition, beat by beat

1. **Depart.** The player accepts a quest at the mayor's office. The screen fades to the
   first island: the party stands on the moss, the Guppy is parked behind them, and the
   islands of the encounter track hang ahead in the void.
2. **Travel** (§5.6). The party crosses to the next island. The board is dark while they
   travel; the Guppy follows.
3. **Arrive at a fight.** Sir Fish's amulet flares and the board unfolds onto the ground as
   light. Enemies run in across the bridge. The reels spin on their own, as today; icons
   rise out of their runes, lines light up, motes fly to the heroes they feed.
4. **Press specials.** A plate lights gold when its hero's special can fire. A tap fires it.
   These presses are the only input a fight accepts, as today.
5. **Clear it.** Drops pop over the fallen. The board fades. The party moves on.
6. **Loot and shop islands** (§5.4, §5.5) resolve without a board.
7. **The boss island** (§5.3). The nameplate plays during the crossing; the board and dock
   take the black-glass boss theme; the boss fight is the last encounter.
8. **Victory or wipe** (§5.7). A win walks off to the result modal and home to the mayor;
   a wipe plays the wipe cinematic, then the result modal.

---

## 4. What exists, and what is missing

| Part | State after the spike | Phase II |
|---|---|---|
| Tactical camera, main island, bridge, far islands | Built, demo-only (`scripts/demo/rune_floor_world.gd`, `rune_floor_scenery.gd`) | Promote out of `demo/`; drive the far islands from the real encounter list |
| Board on the ground | Built: `RuneFloor` mirrors the hidden real `SlotMachine` through four signals (`board_dealt`, `reel_stopped`, `lines_won`, `cell_resolved`) | Keep the mirror; add light-projection art (§5.9) and the boss theme |
| Hero plates | Built (#202): `HeroPlate`, `PlateHpBar`, `PlateChargeRing` | Boss theme; one- and two-hero parties; move out of `demo/` |
| Combat loop | Built on the real `BattleDirector`, overlay and slot | Wire into `RunController` instead of the demo's own loop |
| Travel | None: the demo never travels | §5.6 |
| Loot, shop, boss nameplate, wipe cinematic, result, retry | None in the Rune Floor; all exist for the console expedition in `RunController` | §5.3 to §5.7 |
| Progress readout | Hud's `ExpeditionMinimap`, hidden in the demo | §5.8 |
| The Guppy and the amulet on screen | Not built (#196 checklist) | §5.9 and §8 Q2 |
| Biome surroundings | One void | §8 Q1 |
| Save safety | The demo suspends saving (`SaveGame.suspended`) because it runs a throwaway party | A real expedition saves as today; the flag stays for the demo |

---

## 5. Requirements

### 5.1 The screen

- **Three layers:** a thin top bar, the 3D world filling the whole 1080 × 1920 canvas, and
  the plate dock over its bottom band (about 433 px, per #202). No console.
- **Top bar:** the quest name and the progress readout (§5.8), plus the Hud's bag and party
  buttons where they are today. Text meets decision 10.4. The demo's top bar has three
  grandfathered labels (#205) that must be raised as part of this work.
- **Overlay:** enemy health bars, damage numbers and status icons stay the shared
  `BattleOverlay`. Hero health lives only on the plates, not over the heroes.
- **The board's footprint** stays clear of the dock and of the enemy bars at every enemy
  count (1 to 3) and for the boss's scaled model.

### 5.2 Combat

- Starts on arrival exactly as `RunController._arrive()` does today:
  `director.start_combat(ids, is_boss, drop floor, level)`.
- The real `SlotMachine` keeps running hidden, and `RuneFloor` keeps mirroring it. The
  board must never own a rule. This is what keeps the combat sims honest (backlog: sim
  calibration).
- **Board states:** dark while travelling; unfolds on arrival; lit through the fight;
  fades once the last enemy dies, before the drops.
- Payline beam brightness per #203.
- Callouts ("Strike ×3", "2 lines!") stay above 36 px on screen.

### 5.3 The boss

- The black-glass nameplate (`overlay.boss_nameplate`) plays during the crossing to the
  boss island, as it does during travel today.
- Its `impact` beat applies the boss theme to the **dock and board** instead of the console
  (`console.apply_boss_theme()` today). The plates need a boss face, as the old invokers had.
  The board's rim and runes shift to the black-glass palette.
- The boss island is visibly different from the start of the expedition (the demo already
  marks it with `boss_glow`), so the player can see the end from the first island.

### 5.4 Loot encounters

- The island ahead carries the chest (`treasure_chest.tscn`). On arrival the party stands
  where it would for a fight; the chest sits where the board would be. It pops, opens and
  throws item glyphs exactly as `_run_loot()` does.
- No board, no plates lit. The plates still show health.

### 5.5 Shop encounters

- The island carries the shop building (`shop_building.tscn`, the Meshy hut) in the board's
  place. The shop modal opens and blocks as today (`shop_modal.open(def)` / `closed`).
- The modal must meet decision 10.4. It is one of the densest screens in the game; check it
  at phone width.

### 5.6 The transition between encounters

Today travel is a treadmill: the party runs in place for `EncounterDef.travel_duration`
(2.5 s by default), the ground scrolls under them (`OverworldField`), and `TRAVEL_DECEL_TIME`
eases it to a stop. The boss nameplate and the next fight's enemy preload
(`director.preload_encounter()`) both run inside that window.

The Rune Floor transition is a crossing from one island to the next:

1. The board fades (the Guppy's lantern closes). Drops and item glyphs have already
   landed.
2. The party turns up-run and runs across the bridge; the Guppy rolls after them.
3. The camera follows at the same framing, so the next island arrives in the same place
   on screen that the last one held.
4. On arrival the party settles into its slots, the camera settles, and the encounter
   starts (§5.2 to §5.5).

**Implementation: a treadmill, not real traversal.** Keep the party at `PARTY_ANCHOR` and
slide the islands back down `RUN_DIR`, the way `OverworldField` slides the ground. The next
island docks exactly where the current one was. Why:

- Every slot, the camera and the board are solved against `PARTY_ANCHOR` and `RUN_DIR`
  (`battle_world.gd`). A treadmill changes none of that. Moving the party would mean
  re-anchoring the director, the camera and the board on every encounter.
- The retry path already resets a scrolling world (`world.parallax.reset_tiles()`).
- The current island slides out of view behind the camera, so only two or three islands
  ever exist at once. That matters for the web build (§6.3).

The crossing must fit inside `travel_duration`, so the preload and nameplate timing are
unchanged. The bridge is the one piece of geometry that has to stretch or be re-laid for
each crossing.

### 5.7 Start, victory, wipe and retry

- **Start:** the first island is already under the party when the screen fades in; the
  first crossing is to encounter 0.
- **Victory:** the existing victory run-off (`_run_complete()`, 2 s), then the result modal
  and `SceneRouter.go(MAYOR)` as today.
- **Wipe:** `_play_wipe_cinematic()` (time slows, camera push, desaturation) must work
  under the tactical camera. Its push-in is authored for the console-era camera; re-author
  it for this one.
- **Retry:** `_on_retry()` resets the islands to the start of the track.
- **Endless mode:** new levels generate new islands; there is no end island. The demo's
  loop is a good model of this.

### 5.8 Progress

- The islands ahead **are** the progress readout: loot, shop and boss islands each read at
  a glance (the demo already shapes them differently).
- Keep Hud's `ExpeditionMinimap` in the top bar as the exact readout (where am I, how many
  left). It is text-free by design, so it is unaffected by decision 10.4. Revisit it if the
  islands prove sufficient on a phone.

### 5.9 The Guppy, the amulet and Sir Fish

Decision 10.1 is made; how it shows on screen is §8 Q2. Whatever the answer:

- The board reads as projected light, not a carved slab. The stone slab and gold rim in the
  demo are stand-ins (#196).
- Sir Fish remains the emotional read on state (`sir_fish.gd`: cheers on a payout, darts
  when a hero is hit, slumps on a wipe). The console took his tank with it; he needs a home
  on this screen or his reactions are lost.

### 5.10 Routing, saving and the Hud

- `SceneRouter.Place.QUEST` routes to the expedition scene for the quest's style (§6.1).
- A real expedition saves as today (`RunController` and `QuestResult` call
  `SaveGame.save_profile()`). Only the demo suspends saving.
- The town's **Rune Floor (demo)** button goes once Phase II ships, or is kept as a
  debug-only route.

---

## 6. Implementation notes

### 6.1 Choosing the style

- Add `enum ExpeditionStyle { RUNE_FLOOR, CLASSIC }` and a style field. The natural home
  is `AreaDef`, since a style is about the place (islands in a void, a road through a wood),
  with an optional override on `QuestDef` for a special quest. Default: `RUNE_FLOOR`.
- `SceneRouter.PATHS[Place.QUEST]` becomes a lookup by style: `main.tscn` for CLASSIC and
  a new `expedition_rune_floor.tscn` for RUNE_FLOOR. `test_scene_router` has to follow.
- **One `RunController` for every style.** It reaches for `world`, `overlay`, `console` and
  `shop_modal` by fixed node paths today, and calls `console.apply_boss_theme()` /
  `clear_boss_theme()` directly. Give it a small presentation interface instead:
  - `boss_theme(on)`,
  - `board_visible(on)`,
  - `begin_travel(def)` / `end_travel()`.

  The console implements it for CLASSIC; the Rune Floor's world and dock implement it for
  RUNE_FLOOR. Nothing about encounters, loot or results forks.
- `RuneFloorWorld` already extends `battle_world.gd` and inherits the real slot geometry,
  with `party_setback` / `enemy_setback` pushing each side off the board. Keep that design:
  it is what lets `BattleDirector` run unmodified.

### 6.2 Promoting the spike

- Move `scripts/demo/rune_floor*.gd`, `hero_plate.gd` and `plate_*.gd` to
  `scripts/expedition/` (or `scripts/battle/rune_floor/`), with scenes to match. Keep the
  demo scene as a thin wrapper, or delete it with its town button.
- The scenery is built in code from primitives (`rune_floor_scenery.gd`). Split it into
  **the island** (per encounter, reused) and **the surround** (per biome, §8 Q1) before
  adding a second biome.

### 6.3 Web performance

The web build is the phone build, and its biggest past cost was WebGL shader linking
(`design documents/Sir Fish - Shader Link Counting Experiment.md`, `ShaderWarmup`).

- Add the Rune Floor's materials (`CelMaterials.cel_opaque()`, the additive beam and glow
  materials, the rune tiles) to `ShaderWarmup`, or the first fight will hitch on a phone.
- The board draws each dealt icon through its own small `SubViewport` (nine of them). Profile
  this on a phone; an atlas or a shared viewport may be needed.
- The treadmill (§5.6) keeps at most two or three islands alive at once.
- Test against `Sir Fish - Web Performance Acceptance Testing Spec.md`.

### 6.4 Testing

- **Headless:**
  - A style-routing test.
  - A `RunController` test that walks a COMBAT / LOOT / SHOP / boss list through the Rune
    Floor presentation without a scene tree, as far as the interface allows.
  - `test_font_floor` stays green.
- **Live, through MCP:** each encounter type, a boss, a wipe and a retry, captured with
  `get_game_screenshot`.
- **On a phone:** the definition of done (§10) is a phone playtest, as the spike's was.

---

## 7. Other expedition types

"Expedition type" here means how an expedition is presented and paced. The rules stay the
same across types, and every type is built on the §6.1 interface.

### 7.1 Classic (the console expedition)

The shipped expedition: the fight in the top 764 px, the console below it.

- **Keep it** as a selectable style. Nothing needs building, since it is today's `main.tscn`.
- **Freeze its art.** New console art (for example #140, the cabinet bottom) waits until a
  quest actually uses this style.
- **The cost of keeping it:** every board-facing feature needs a second presentation
  (glyphs, callouts, the boss theme, audio cues #184). The shared `SlotMachine` signals keep
  the rules single, but not the art.
- **A good use:** a "cabinet" quest type where the slot is the fiction's focus (a gambling
  den, a Guppy repair job). That is a design question, not a Phase II task.

### 7.2 The road (the overworld prototype)

The overhead field from `ee47894`: the party runs single file along `RUN_DIR` across a real
scattered field (`OverworldField`), melee blinks, ranged and magic aim in 3D. It exists
today only behind `main_layout.hide_console`, as a framing aid with no UI.

- **Fit:** travel-heavy quests (an escort, a long road between towns) where the journey is
  the point.
- **Needs:** a board placement (the Rune Floor's board cannot sit on a moving field), the
  plate dock, and the §6.1 interface.
- **Status:** an idea, not scheduled.

### 7.3 Candidates the Rune Floor makes cheap

These are ideas for later decisions, not requirements.

- **The Hold:** one island, waves until a timer or a boss. The demo's loop is exactly this,
  and so is endless mode.
- **The Descent:** islands going down rather than along, into a cave. It pairs with the
  Emberdeep biome (`Art Direction/Sir Fish - Level Idea - Emberdeep.md`) and with §8 Q1.
- **The Bridge:** a fight on the bridge itself, with a narrow front and one enemy at a time.

---

## 8. Open questions

### Q1. Can the surroundings change per area: a forest for one expedition, a cave for another?

The phone playtest screenshot circles three regions: the void left of the island, the gap
above it between the far islands, and the void to its right. Today all three are black
void with fog (`fog_begin` 22, `fog_end` 70), drifting motes and a scatter of distant
islets.

**Yes, technically, and cheaply.** Those regions are simply whatever the camera sees beyond
the island's edge. `AreaDef.field_profile` already exists as an "authored, not yet consumed"
hook for exactly this. A per-area **surround** scene can fill them without touching the
island, the board or the fight:
- **Forest (the Endless Wood):** trunks and canopy rising from below the island's edge,
  green mist, fireflies instead of arcane motes.
- **Cave (the Emberdeep):** rock walls on both sides, stalactites hanging into the top gap,
  ember glow from below instead of lantern light from above (Emberdeep's own "light comes
  from below" note), and Ember palette fog.

**The real question is whether the islands stay floating in every biome.** Floating islands
in a void read as a board game's spaces and suit the magic-lantern fiction. But "a floating
island in a forest" needs a reason, where "a clearing in a forest" and "a ledge in a
cavern" do not.

- **Option A:** islands everywhere, with only the surround changing. Cheapest, and
  consistent. Recommended for Phase II.
- **Option B:** the island becomes the biome's own ground (a clearing, a ledge), and the
  bridges become paths or rope walks. More art per biome, and more natural.
- **Option C:** A in the wood, and B only where the biome demands it (the Emberdeep's
  ledges over lava).

Also to decide: whether the surround may carry gameplay-free motion (falling leaves,
dripping water), which costs frames on a phone.

### Q2. How does the art connect the Gilded Guppy and Sir Fish's amulet to the board?

Decision 10.1 settles the fiction. What is not settled is what the player sees. The #196
checklist is the starting point: the parked Guppy, Sir Fish wearing the amulet, a beam to
the board, the board as light, and the dock framed as part of the coach.

- **Option A, the Guppy in frame:** the coach's back end is parked at the bottom edge of the
  screen, behind the party. Sir Fish's tank sits on its roof, and the amulet's beam runs from
  him to the board. Most literal. But the bottom band is the dock (§5.1), so the Guppy would
  have to sit between the heroes and the plates, which is space the fight uses.
- **Option B, the dock is the Guppy:** the plate dock is dressed as the coach's rail or
  dashboard (the brass of mockup B's "Guppy's rail" over design A's plates). Sir Fish's tank
  sits in its centre, and the beam rises from the dock to the board. No world space is spent
  on the coach, and Sir Fish is back beside the player's thumb, where spec 17.7 put him.
  **Recommended.**
- **Option C, the beam only:** the Guppy stays off-screen; a cone of light from the bottom
  edge and a lens flare on arrival do the work. Cheapest, and it risks the fiction never
  landing.

Also to decide:
- Whether the board unfolding on arrival is shown as the amulet flaring (Sir Fish animates)
  or as the reels spinning up.
- Whether the Guppy is seen rolling during the crossings (§5.6). That is simple in Option A
  and implied in B.
- The amulet's design. A Meshy concept costs credits and needs the `needs-meshy` label.

### Q3. Smaller questions

- **Classic:** keep it selectable, or retire it (§7.1)? Retiring it deletes the console,
  the Sir Fish tank's current home and several grandfathered small fonts (#205).
- **The minimap:** keep it next to the islands, or rely on the islands alone (§5.8)?
- **One- and two-hero parties:** the dock has three plate slots. Centre the plates that
  exist, or keep empty slots as "recruit to fill" teasers?

---

## 9. Milestones

1. **Plumbing:** the style field, routing, and the `RunController` presentation interface,
   with CLASSIC unchanged. No visible change.
2. **Combat expedition on the Rune Floor:** fights only, with board fade-in and fade-out,
   plates, and the treadmill crossing between fights. Phone playtest.
3. **Loot, shop, boss:** the three non-fight islands, the boss theme on the dock and board,
   and the nameplate during the crossing.
4. **Start and end:** the victory walk-off, the wipe cinematic under the tactical camera,
   retry and endless mode.
5. **The Guppy and the amulet:** per Q2. May need Meshy credits.
6. **Biome surround hook:** per Q1, shipping the Endless Wood surround only.
7. **Web performance pass** (§6.3), then the default flips: RUNE_FLOOR for every area.

## 10. Definition of done

- Every quest and endless mode plays on the Rune Floor by default, start to finish,
  including a boss, a shop, loot, a wipe and a retry.
- CLASSIC still plays when an area asks for it.
- A phone playtest on the Pages build: every text readable (decision 10.4), no hitch on the
  first fight, and the islands readable as progress.
- `python tools/run_tests.py` is green, including `test_font_floor`.
- The backlog doc records the answers to Q1 to Q3, with issues linked.

## 11. Deliberately deferred

- New biome art beyond the hook (Q1).
- The road and the §7.3 candidates.
- Specials rebalance (#204) and payline glow (#203), each its own issue.
- Audio (#184), which should be built against this screen rather than the console.
