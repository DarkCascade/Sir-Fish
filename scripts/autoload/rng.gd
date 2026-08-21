extends Node
## RNG — one seeded RandomNumberGenerator for the whole game, so a run can be
## reproduced from a seed. Every system draws from here rather than from the
## global randf()/randi() so determinism stays possible (spec 8.1).

var rng := RandomNumberGenerator.new()
var seed_value: int = 0

func _ready() -> void:
	randomize_seed()

func randomize_seed() -> void:
	rng.randomize()
	seed_value = rng.seed

func set_seed(value: int) -> void:
	seed_value = value
	rng.seed = value

func randf() -> float:
	return rng.randf()

func randf_range(from: float, to: float) -> float:
	return rng.randf_range(from, to)

func randi_range(from: int, to: int) -> int:
	return rng.randi_range(from, to)

func pick(array: Array) -> Variant:
	if array.is_empty():
		return null
	return array[rng.randi_range(0, array.size() - 1)]

## Weighted pick over an array of integer weights; returns the chosen index.
func weighted_index(weights: Array) -> int:
	var total: int = 0
	for w: int in weights:
		total += w
	if total <= 0:
		return 0
	var roll: int = rng.randi_range(1, total)
	var acc: int = 0
	for i: int in range(weights.size()):
		acc += int(weights[i])
		if roll <= acc:
			return i
	return weights.size() - 1
