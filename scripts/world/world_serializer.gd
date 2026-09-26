class_name WorldSerializer
extends RefCounted

static func make_checkpoint(world: WorldState) -> Dictionary:
	return {
		"year": world.year,
		"event_cursor": world.events.size(),
		"command_cursor": world.command_cursor,
		"state": to_state_dictionary(world),
	}

static func to_save_dictionary(world: WorldState) -> Dictionary:
	var event_log: Array[Dictionary] = []
	for event in world.events:
		event_log.append(event.to_dictionary())
	return {
		"format_version": 1,
		"state": to_state_dictionary(world),
		"event_log": event_log,
		"command_log": world.command_log.duplicate(true),
		"snapshots": world.snapshots.duplicate(true),
	}

static func to_state_dictionary(world: WorldState) -> Dictionary:
	var regions: Array[Dictionary] = []
	for entity_id in _sorted_integer_keys(world.regions):
		var region: RegionData = world.regions[entity_id]
		regions.append({
			"id": region.id,
			"name": region.name,
			"cell_indices": region.cell_indices.duplicate(),
			"neighbor_ids": region.neighbor_ids.duplicate(),
			"settlement_ids": region.settlement_ids.duplicate(),
			"fertility": region.fertility,
			"resource_yields": region.resource_yields,
			"controlling_state_id": region.controlling_state_id,
		})
	var settlements: Array[Dictionary] = []
	for entity_id in _sorted_integer_keys(world.settlements):
		var settlement: SettlementData = world.settlements[entity_id]
		settlements.append({
			"id": settlement.id,
			"name": settlement.name,
			"region_id": settlement.region_id,
			"land_component_id": settlement.land_component_id,
			"founding_year": settlement.founding_year,
			"status": settlement.status,
			"population": settlement.population,
			"food_store": settlement.food_store,
			"food_coverage": settlement.food_coverage,
			"previous_food_coverage": settlement.previous_food_coverage,
			"years_in_food_stress": settlement.years_in_food_stress,
			"years_below_abandonment_threshold": settlement.years_below_abandonment_threshold,
			"resource_stores": settlement.resource_stores,
			"occupational_shares": settlement.occupational_shares,
			"culture_id": settlement.culture_id,
			"state_id": settlement.state_id,
			"site_cell_index": settlement.site_cell_index,
			"fertility": settlement.fertility,
			"freshwater_adjacent": settlement.freshwater_adjacent,
		})
	var cultures: Array[Dictionary] = []
	for entity_id in _sorted_integer_keys(world.cultures):
		var culture: CultureData = world.cultures[entity_id]
		cultures.append({
			"id": culture.id,
			"name": culture.name,
			"origin_region_id": culture.origin_region_id,
			"parent_ids": culture.parent_ids.duplicate(),
			"language_label": culture.language_label,
			"religion_label": culture.religion_label,
			"values": culture.values,
		})
	var states: Array[Dictionary] = []
	for entity_id in _sorted_integer_keys(world.states):
		var state: StateData = world.states[entity_id]
		var relationship_records: Array[Dictionary] = []
		for other_id in _sorted_integer_keys(state.relationships):
			relationship_records.append({
				"other_state_id": other_id,
				"record": state.relationships[other_id].duplicate(true),
			})
		states.append({
			"id": state.id,
			"name": state.name,
			"government_type": state.government_type,
			"settlement_ids": state.settlement_ids.duplicate(),
			"region_ids": state.region_ids.duplicate(),
			"leader_label": state.leader_label,
			"treasury": state.treasury,
			"stability": state.stability,
			"relationships": relationship_records,
			"at_war_with": state.at_war_with.duplicate(),
		})
	return {
		"seed": world.seed,
		"generator_version": world.generator_version,
		"simulation_version": world.simulation_version,
		"year": world.year,
		"next_entity_id": world.next_entity_id,
		"next_event_id": world.next_event_id,
		"command_cursor": world.command_cursor,
		"next_command_sequence": world.next_command_sequence,
		"influence": world.influence,
		"map": _map_to_dictionary(world.map),
		"regions": regions,
		"settlements": settlements,
		"cultures": cultures,
		"states": states,
	}

static func from_save_dictionary(data: Dictionary) -> Dictionary:
	if int(data.get("format_version", -1)) != 1:
		return {"error": "Unsupported save format version."}
	if typeof(data.get("state")) != TYPE_DICTIONARY or typeof(data.get("event_log")) != TYPE_ARRAY:
		return {"error": "Save file is missing its world state or event log."}
	var result := from_state_dictionary(data["state"])
	if result.has("error"):
		return result
	var world: WorldState = result["world"]
	if data.has("command_log"):
		if typeof(data["command_log"]) != TYPE_ARRAY:
			return {"error": "Save command log is invalid."}
		var expected_sequence := 1
		for command_value in data["command_log"]:
			if typeof(command_value) != TYPE_DICTIONARY or not command_value.has("sequence_number") or not command_value.has("execute_year") or not command_value.has("type") or not command_value.has("target_settlement_id") or not command_value.has("influence_cost"):
				return {"error": "Save command log contains an invalid entry."}
			var command: Dictionary = command_value
			if int(command["sequence_number"]) != expected_sequence or int(command["execute_year"]) < 1 or float(command["influence_cost"]) < 0.0 or str(command["type"]) != "food_relief":
				return {"error": "Save command log counters are invalid."}
			world.command_log.append(command.duplicate(true))
			expected_sequence += 1
		world.next_command_sequence = maxi(world.next_command_sequence, expected_sequence)
		if world.command_cursor < 0 or world.command_cursor > world.command_log.size():
			return {"error": "Save command cursor is invalid."}
	for event_data in data["event_log"]:
		if typeof(event_data) != TYPE_DICTIONARY or not event_data.has("id") or not event_data.has("year") or not event_data.has("type"):
			return {"error": "Save event log contains an invalid entry."}
		if typeof(event_data.get("facts", {})) != TYPE_DICTIONARY or typeof(event_data.get("cause_links", [])) != TYPE_ARRAY:
			return {"error": "Save event data is malformed."}
		world.events.append(_event_from_dictionary(event_data))
	if data.has("snapshots"):
		if typeof(data["snapshots"]) != TYPE_ARRAY:
			return {"error": "Save checkpoints are invalid."}
		for checkpoint in data["snapshots"]:
			if typeof(checkpoint) != TYPE_DICTIONARY or not checkpoint.has("year") or not checkpoint.has("event_cursor") or typeof(checkpoint.get("state", {})) != TYPE_DICTIONARY:
				return {"error": "Save checkpoint data is malformed."}
		world.snapshots = data["snapshots"].duplicate(true)
	if not world.events.is_empty() and int(world.events[-1].id) >= world.next_event_id:
		return {"error": "Save event counter does not follow its event log."}
	return {"world": world}

static func from_state_dictionary(data: Dictionary) -> Dictionary:
	for required_key in ["seed", "year", "map", "regions", "settlements", "cultures", "states"]:
		if not data.has(required_key):
			return {"error": "World checkpoint is missing '%s'." % required_key}
	if typeof(data["map"]) != TYPE_DICTIONARY:
		return {"error": "World checkpoint map is invalid."}
	var world := WorldState.new()
	world.seed = int(data["seed"])
	world.generator_version = int(data.get("generator_version", 1))
	world.simulation_version = int(data.get("simulation_version", 1))
	world.year = int(data["year"])
	world.next_entity_id = int(data.get("next_entity_id", 1))
	world.next_event_id = int(data.get("next_event_id", 1))
	world.command_cursor = int(data.get("command_cursor", 0))
	world.next_command_sequence = int(data.get("next_command_sequence", 1))
	world.influence = float(data.get("influence", 3.0))
	world.map = _map_from_dictionary(data["map"])
	if world.map == null:
		return {"error": "World checkpoint map data is incomplete."}
	for region_data in data["regions"]:
		var region := RegionData.new()
		region.id = int(region_data["id"])
		region.name = str(region_data["name"])
		region.cell_indices = _int_array(region_data["cell_indices"])
		region.neighbor_ids = _int_array(region_data["neighbor_ids"])
		region.settlement_ids = _int_array(region_data["settlement_ids"])
		region.fertility = float(region_data["fertility"])
		region.resource_yields = PackedFloat32Array(region_data["resource_yields"])
		region.controlling_state_id = int(region_data.get("controlling_state_id", -1))
		world.regions[region.id] = region
	for settlement_data in data["settlements"]:
		var settlement := SettlementData.new()
		settlement.id = int(settlement_data["id"])
		settlement.name = str(settlement_data["name"])
		settlement.region_id = int(settlement_data["region_id"])
		settlement.land_component_id = int(settlement_data.get("land_component_id", -1))
		settlement.founding_year = int(settlement_data.get("founding_year", 0))
		settlement.status = int(settlement_data["status"])
		settlement.population = int(settlement_data["population"])
		settlement.food_store = float(settlement_data["food_store"])
		settlement.food_coverage = float(settlement_data["food_coverage"])
		settlement.previous_food_coverage = float(settlement_data["previous_food_coverage"])
		settlement.years_in_food_stress = int(settlement_data["years_in_food_stress"])
		settlement.years_below_abandonment_threshold = int(settlement_data["years_below_abandonment_threshold"])
		settlement.resource_stores = PackedFloat32Array(settlement_data["resource_stores"])
		settlement.occupational_shares = PackedFloat32Array(settlement_data["occupational_shares"])
		settlement.culture_id = int(settlement_data["culture_id"])
		settlement.state_id = int(settlement_data["state_id"])
		settlement.site_cell_index = int(settlement_data["site_cell_index"])
		settlement.fertility = float(settlement_data["fertility"])
		settlement.freshwater_adjacent = bool(settlement_data["freshwater_adjacent"])
		world.settlements[settlement.id] = settlement
	for culture_data in data["cultures"]:
		var culture := CultureData.new()
		culture.id = int(culture_data["id"])
		culture.name = str(culture_data["name"])
		culture.origin_region_id = int(culture_data["origin_region_id"])
		culture.parent_ids = _int_array(culture_data["parent_ids"])
		culture.language_label = str(culture_data["language_label"])
		culture.religion_label = str(culture_data["religion_label"])
		culture.values = PackedFloat32Array(culture_data["values"])
		world.cultures[culture.id] = culture
	for state_data in data["states"]:
		var state := StateData.new()
		state.id = int(state_data["id"])
		state.name = str(state_data["name"])
		state.government_type = str(state_data["government_type"])
		state.settlement_ids = _int_array(state_data["settlement_ids"])
		state.region_ids = _int_array(state_data["region_ids"])
		state.leader_label = str(state_data["leader_label"])
		state.treasury = float(state_data["treasury"])
		state.stability = float(state_data["stability"])
		for relationship in state_data.get("relationships", []):
			state.relationships[int(relationship["other_state_id"])] = relationship["record"].duplicate(true)
		state.at_war_with = _int_array(state_data.get("at_war_with", []))
		world.states[state.id] = state
	if world.year < 0 or world.next_entity_id <= 0 or world.next_event_id <= 0 or world.command_cursor < 0 or world.next_command_sequence <= 0 or world.influence < 0.0:
		return {"error": "World checkpoint contains invalid counters."}
	return {"world": world}

static func _map_to_dictionary(map: WorldMap) -> Dictionary:
	var resources: Array = []
	for resource_field in map.resource_potential:
		resources.append(resource_field)
	return {
		"width": map.width,
		"height": map.height,
		"elevation": map.elevation,
		"temperature": map.temperature,
		"rainfall": map.rainfall,
		"fertility": map.fertility,
		"soil_potential": map.soil_potential,
		"biome": map.biome,
		"region_id": map.region_id,
		"is_land": map.is_land,
		"is_river": map.is_river,
		"is_lake": map.is_lake,
		"has_freshwater": map.has_freshwater,
		"resource_potential": resources,
	}

static func _map_from_dictionary(data: Dictionary) -> WorldMap:
	if not data.has("width") or not data.has("height"):
		return null
	var width := int(data["width"])
	var height := int(data["height"])
	if width <= 0 or height <= 0 or width * height > 4_000_000:
		return null
	var map := WorldMap.new()
	map.initialize(width, height)
	for key in [
		"elevation", "temperature", "rainfall", "fertility", "soil_potential", "biome", "region_id",
		"is_land", "is_river", "is_lake", "has_freshwater", "resource_potential",
	]:
		if not data.has(key):
			return null
	if typeof(data["resource_potential"]) != TYPE_ARRAY or data["resource_potential"].size() != WorldMap.RESOURCE_COUNT:
		return null
	map.elevation = PackedFloat32Array(data["elevation"])
	map.temperature = PackedFloat32Array(data["temperature"])
	map.rainfall = PackedFloat32Array(data["rainfall"])
	map.fertility = PackedFloat32Array(data["fertility"])
	map.soil_potential = PackedFloat32Array(data["soil_potential"])
	map.biome = PackedInt32Array(data["biome"])
	map.region_id = PackedInt32Array(data["region_id"])
	map.is_land = PackedByteArray(data["is_land"])
	map.is_river = PackedByteArray(data["is_river"])
	map.is_lake = PackedByteArray(data["is_lake"])
	map.has_freshwater = PackedByteArray(data["has_freshwater"])
	map.resource_potential.clear()
	for resource_field in data["resource_potential"]:
		map.resource_potential.append(PackedFloat32Array(resource_field))
	var expected_cells := map.width * map.height
	for field_size in [
		map.elevation.size(), map.temperature.size(), map.rainfall.size(), map.fertility.size(),
		map.soil_potential.size(), map.biome.size(), map.region_id.size(), map.is_land.size(),
		map.is_river.size(), map.is_lake.size(), map.has_freshwater.size(),
	]:
		if field_size != expected_cells:
			return null
	if map.resource_potential.size() != WorldMap.RESOURCE_COUNT:
		return null
	for resource_field in map.resource_potential:
		if resource_field.size() != expected_cells:
			return null
	return map

static func _event_from_dictionary(data: Dictionary) -> HistoryEvent:
	var event := HistoryEvent.new()
	event.id = int(data["id"])
	event.year = int(data["year"])
	event.type = str(data["type"])
	event.location_region_id = int(data.get("location_region_id", -1))
	event.location_cell_index = int(data.get("location_cell_index", -1))
	event.subject_ids = _int_array(data.get("subject_ids", []))
	event.participant_ids = _int_array(data.get("participant_ids", []))
	event.facts = data.get("facts", {}).duplicate(true)
	event.cause_links = data.get("cause_links", []).duplicate(true)
	return event

static func _int_array(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value in values:
		result.append(int(value))
	return result

static func _sorted_integer_keys(dictionary: Dictionary) -> Array[int]:
	var keys: Array[int] = []
	for key in dictionary.keys():
		keys.append(int(key))
	keys.sort()
	return keys
