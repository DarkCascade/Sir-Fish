# Sir Fish — Level Idea: The Emberdeep

**Status: idea sketch, not a spec.** Written to keep the thought from
evaporating. Nothing here is decided and nothing is costed.

A volcanic cave biome that uses the **Ember** palette from
`Sir Fish - Art Style A - Lantern Spec.md` §9.

---

## The idea in a paragraph

The path stops being a forest and becomes a throat of rock. Sir Fish descends
into a flooded lava tube where the water is warm and wrong — steam off the
surface, black glass underfoot, the only light coming up from below instead of
down from the canopy. The bioluminescent blue that lights the whole game is
absent here; what lights the Emberdeep is the heat itself.

## Why Ember is right here, having been wrong everywhere else

This is the part worth remembering. Ember was rejected as a *console* hue
because it collides with `C_FIRE` (11°), `C_DANGER` (17°) and `C_DEFEND` (29°) —
a warm frame mutes the game's most time-critical feedback.

**A biome inverts that argument.** The palette goes on the *world*, not the
chrome. The console stays Lantern teal, and teal furniture over an ember cave
is a near-complementary pairing — the strongest world/frame separation anywhere
in the game, better than the forest gets. The very quality that disqualified
Ember as UI is what makes it a good biome: it is unmistakably **not** the
forest, at a glance, from across the room.

This is the same move §6.1e already makes for the reliquary modals — a scoped
exception where a hue is allowed to lead because its subject earns it. The
Emberdeep would be the second such exception, and the first one attached to a
*place* rather than a layer.

## Motif notes

- **Light comes from below.** Every other scene in the game is lit from above.
  Flipping the key light is most of the atmosphere for free.
- **Black glass, not brown rock.** Cooled obsidian reads darker and colder than
  cave-brown, which keeps the ember glow as the only warm thing and stops the
  screen turning to mud.
- **Heat haze instead of fog.** The forest's depth fog has a warm-side twin.
- **The water is still there.** Sir Fish is a fish. A dry cave wastes him —
  make it a flooded tube, with the surface overhead as a shifting orange ceiling.
- **Sound** (whenever audio happens): drips, distant pressure, no wind. The
  forest is open and noisy; the Emberdeep should feel enclosed.

## What it reuses vs. what is genuinely new

**Reuses:** the combat system untouched; the encounter/quest structure
(`quest.enemy_pool` / `boss_pool` in `game_state.gd`); every existing mesh and
rig; the scatter machinery in `overworld_field.gd`.

**New, and this is where the cost is:** the game has **no biome system today**.
There is one `battle_world.tscn` and one parallax set, so a second environment
is the real structural work — not the palette, which is four constants plus a
world set. Worth deciding early whether a biome is:

1. a palette *transform* of the forest, the way `Tuning.storm_tint()` already
   works — cheap, one source of truth, but everything keeps the forest's shapes; or
2. a genuine second world with its own props and parallax — expensive, correct,
   and the thing that makes it feel like a different place.

The storm precedent says (1) is viable and (2) is what the idea actually wants.

## Open questions for later

- **Do the danger signals still read?** Ember-on-ember is the risk that killed
  it as chrome, and here it lands on damage numbers over a hot ground. Likely
  needs `C_DANGER` pushed toward magenta *for this biome only* — which is a
  scoped exception on top of a scoped exception, so tread carefully.
- **New enemies, or existing ones re-tinted?** A magma variant of an existing
  silhouette is a fraction of the cost of a new Meshy → Blender → Godot pass.
- **Where does it sit in the run?** A deep-depth biome, a quest destination, or
  an alternate branch? The endless-mode depth pools in `game_state.gd` are the
  obvious hook.
- **Does the fish tank change?** `SirFishTank` in the status panel is a constant
  presence. Warm water is a cheap, funny touch.

## Where the numbers already are

Ember's solved values — verified to clear the `lantern` readability profile —
are in `Sir Fish - Art Style A - Lantern Spec.md` §9, and `Sir Fish - Proof 2 -
Lantern Hues.html` renders them. They were solved as *chrome*, so a world set
still has to be derived; the four chrome constants are the starting hue family,
not the answer.
