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
		_reset_from_source(source_world, bounded_year)
	elif bounded_year < _cached_world.year:
		_reset_from_source(source_world, bounded_year)
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

func _reset_from_source(source_world: WorldState, target_year: int) -> void:
	var checkpoint: Dictionary = {}
	var checkpoint_year := -1
	for candidate in source_world.snapshots:
		var candidate_year := int(candidate.get("year", -1))
		if candidate_year <= target_year and candidate_year > checkpoint_year:
			checkpoint = candidate
			checkpoint_year = candidate_year
	if not checkpoint.is_empty() and typeof(checkpoint.get("state", {})) == TYPE_DICTIONARY:
		var decoded := WorldSerializer.from_state_dictionary(checkpoint["state"])
		if decoded.has("world"):
			_cached_world = decoded["world"]
			var event_cursor := clampi(int(checkpoint.get("event_cursor", 0)), 0, source_world.events.size())
			for event_index in event_cursor:
				_cached_world.events.append(source_world.events[event_index])
			_cached_world.snapshots = source_world.snapshots.duplicate(true)
		else:
			_cached_world = null
	if _cached_world == null:
		_cached_world = WorldGenerator.new().generate(source_world.seed)
		_cached_world.generator_version = source_world.generator_version
		_cached_world.simulation_version = source_world.simulation_version
	_cached_engine = SimulationEngine.new()
