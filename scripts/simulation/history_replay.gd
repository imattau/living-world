class_name HistoryReplay
extends RefCounted

var _cached_world: WorldState
var _cached_engine := SimulationEngine.new()

func view_at(source_world: WorldState, target_year: int) -> WorldState:
	if source_world == null:
		return null
	var bounded_year := clampi(target_year, 0, source_world.year)
	if bounded_year == source_world.year:
		return source_world
	if _cached_world == null or not _matches_source(source_world):
		_reset_from_source(source_world)
	elif bounded_year < _cached_world.year:
		_reset_from_source(source_world)
	_cached_engine.advance_years(_cached_world, bounded_year - _cached_world.year)
	return _cached_world

func clear() -> void:
	_cached_world = null
	_cached_engine = SimulationEngine.new()

func _matches_source(source_world: WorldState) -> bool:
	return (
		_cached_world != null
		and _cached_world.seed == source_world.seed
		and _cached_world.generator_version == source_world.generator_version
		and _cached_world.simulation_version == source_world.simulation_version
	)

func _reset_from_source(source_world: WorldState) -> void:
	_cached_world = WorldGenerator.new().generate(source_world.seed)
	_cached_world.generator_version = source_world.generator_version
	_cached_world.simulation_version = source_world.simulation_version
	_cached_engine = SimulationEngine.new()
