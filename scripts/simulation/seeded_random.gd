class_name SeededRandom
extends RefCounted

const MODULUS: int = 2_147_483_647
const MULTIPLIER: int = 48_271
const SEED_MODULUS: int = MODULUS - 1

var _state: int = 1

func _init(seed_value: int = 1) -> void:
	_state = posmod(seed_value, SEED_MODULUS) + 1

func next_int() -> int:
	_state = (_state * MULTIPLIER) % MODULUS
	return _state

func next_float() -> float:
	return float(next_int() - 1) / float(SEED_MODULUS - 1)

func range_int(minimum: int, maximum: int) -> int:
	assert(maximum >= minimum, "maximum must be at least minimum")
	var span := maximum - minimum + 1
	return minimum + (next_int() % span)

static func derive_seed(world_seed: int, subsystem_id: int, version: int) -> int:
	var safe_world_seed := posmod(world_seed - 1, SEED_MODULUS) + 1
	return 1 + posmod(
		safe_world_seed + subsystem_id * 104_729 + version * 13_007,
		SEED_MODULUS
	)
