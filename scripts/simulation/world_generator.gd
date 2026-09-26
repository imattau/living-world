class_name WorldGenerator
extends RefCounted

const GENERATOR_VERSION := 1
const MAP_WIDTH := 48
const MAP_HEIGHT := 48
const SEA_LEVEL := 0.38
const TARGET_REGION_COUNT := 20
const TARGET_SETTLEMENT_COUNT := 12
const MIN_SETTLEMENTS := 8
const SETTLEMENT_SPACING := 4
const RIVER_FLOW_THRESHOLD := 12
const D8_OFFSETS := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]
const RESOURCE_NAMES := ["food", "wood", "stone", "iron"]

var _generation_rng: SeededRandom
var _climate_rng: SeededRandom
var _society_rng: SeededRandom
var _world_seed: int

func generate(world_seed: int) -> WorldState:
	_world_seed = posmod(world_seed - 1, SeededRandom.SEED_MODULUS) + 1
	_generation_rng = SeededRandom.new(SeededRandom.derive_seed(world_seed, 1, GENERATOR_VERSION))
	_climate_rng = SeededRandom.new(SeededRandom.derive_seed(world_seed, 2, GENERATOR_VERSION))
	_society_rng = SeededRandom.new(SeededRandom.derive_seed(world_seed, 3, GENERATOR_VERSION))

	var world := WorldState.new()
	world.seed = _world_seed
	world.generator_version = GENERATOR_VERSION
	world.map = WorldMap.new()
	world.map.initialize(MAP_WIDTH, MAP_HEIGHT)

	_generate_elevation(world.map)
	_generate_climate_and_soil(world.map)
	_generate_hydrology(world.map)
	_generate_biomes_and_resources(world.map)
	var components := _find_land_components(world.map)
	_create_regions(world, components)
	_create_cultures(world)
	_create_settlements(world, components)
	_assign_cultures_by_origin(world, components)
	_create_initial_states(world, components)
	world.max_states = maxi(2, world.states.size() * 2)
	_recalculate_region_summaries(world)
	world.snapshots.append(WorldSerializer.make_checkpoint(world))
	return world

func _generate_elevation(map: WorldMap) -> void:
	var noise := _make_value_noise(map.width, map.height, [6, 12, 24], [0.55, 0.30, 0.15], _generation_rng)
	for y in map.height:
		var latitude := absf((float(y) / float(map.height - 1)) * 2.0 - 1.0)
		for x in map.width:
			var index := map.get_index(x, y)
			map.elevation[index] = clampf(0.15 + noise[index] * 0.85 + latitude * 0.04, 0.0, 1.0)
			map.is_land[index] = 1 if map.elevation[index] >= SEA_LEVEL else 0

func _generate_climate_and_soil(map: WorldMap) -> void:
	var rain_noise := _make_value_noise(map.width, map.height, [12, 24], [0.70, 0.30], _climate_rng)
	var soil_noise := _make_value_noise(map.width, map.height, [8, 16, 32], [0.50, 0.30, 0.20], _generation_rng)
	for y in map.height:
		var latitude := absf((float(y) / float(map.height - 1)) * 2.0 - 1.0)
		for x in map.width:
			var index := map.get_index(x, y)
			map.temperature[index] = clampf(
				1.0 - 0.85 * latitude - 0.35 * map.elevation[index], 0.0, 1.0
			)
			var wetness_band := 1.0 - 0.35 * absf(latitude - 0.35)
			map.rainfall[index] = clampf(rain_noise[index] * wetness_band, 0.0, 1.0)
			map.soil_potential[index] = soil_noise[index]

func _generate_hydrology(map: WorldMap) -> void:
	var downstream := PackedInt32Array()
	downstream.resize(map.width * map.height)
	downstream.fill(-1)
	var flow := PackedInt32Array()
	flow.resize(map.width * map.height)
	flow.fill(0)
	var sorted_cells: Array[int] = []

	for index in map.width * map.height:
		if map.is_land[index] == 0:
			continue
		flow[index] = 1
		sorted_cells.append(index)
		var position := map.get_cell_position(index)
		var best_height := map.elevation[index]
		var best_index := -1
		for offset: Vector2i in D8_OFFSETS:
			var neighbor_x := position.x + offset.x
			var neighbor_y := position.y + offset.y
			if not _is_inside(map, neighbor_x, neighbor_y):
				continue
			var neighbor_index := map.get_index(neighbor_x, neighbor_y)
			if map.is_land[neighbor_index] == 0:
				continue
			var neighbor_height := map.elevation[neighbor_index]
			if neighbor_height < best_height or (
				is_equal_approx(neighbor_height, best_height)
				and best_index >= 0 and neighbor_index < best_index
			):
				best_height = neighbor_height
				best_index = neighbor_index
		downstream[index] = best_index
		if best_index < 0:
			map.is_lake[index] = 1

	sorted_cells.sort_custom(func(a: int, b: int) -> bool:
		if is_equal_approx(map.elevation[a], map.elevation[b]):
			return a < b
		return map.elevation[a] > map.elevation[b]
	)
	for index in sorted_cells:
		var target := downstream[index]
		if target >= 0:
			flow[target] += flow[index]
	for index in sorted_cells:
		if flow[index] >= RIVER_FLOW_THRESHOLD:
			map.is_river[index] = 1
			map.has_freshwater[index] = 1
		if map.is_lake[index] == 1:
			map.has_freshwater[index] = 1

	for index in sorted_cells:
		if map.has_freshwater[index] == 0:
			continue
		var position := map.get_cell_position(index)
		for offset: Vector2i in D8_OFFSETS:
			var nx := position.x + offset.x
			var ny := position.y + offset.y
			if _is_inside(map, nx, ny):
				var neighbor_index := map.get_index(nx, ny)
				if map.is_land[neighbor_index] == 1:
					map.has_freshwater[neighbor_index] = 1


func _generate_biomes_and_resources(map: WorldMap) -> void:
	var resource_rng := SeededRandom.new(SeededRandom.derive_seed(_world_seed, 4, GENERATOR_VERSION))
	for resource_index in WorldMap.RESOURCE_COUNT:
		map.resource_potential[resource_index] = _make_value_noise(
			map.width, map.height, [8, 16, 32], [0.50, 0.30, 0.20], resource_rng
		)
	for index in map.width * map.height:
		map.fertility[index] = clampf(
			0.55 * map.rainfall[index]
			+ 0.30 * map.soil_potential[index]
			+ 0.15 * float(map.has_freshwater[index]),
			0.0,
			1.0
		)
		if map.is_land[index] == 0:
			map.biome[index] = 0
			continue
		map.biome[index] = _classify_biome(map.temperature[index], map.rainfall[index])
		map.resource_potential[0][index] = clampf(
			map.resource_potential[0][index] * (0.5 + map.fertility[index]), 0.0, 1.0
		)
		var wood_suitability := 0.15
		if map.biome[index] == 3:
			wood_suitability = 0.45
		elif map.biome[index] == 4 or map.biome[index] == 5:
			wood_suitability = 1.0
		map.resource_potential[1][index] *= wood_suitability
		map.resource_potential[2][index] *= 0.4 + 0.6 * map.elevation[index]
		map.resource_potential[3][index] *= (
			0.2 + 0.8 * maxf(map.elevation[index], 1.0 - map.rainfall[index])
		)

func _find_land_components(map: WorldMap) -> Dictionary:
	var component_ids := PackedInt32Array()
	component_ids.resize(map.width * map.height)
	component_ids.fill(-1)
	var component_sizes: Array[int] = []
	var next_component_id := 0
	for start_index in map.width * map.height:
		if map.is_land[start_index] == 0 or component_ids[start_index] >= 0:
			continue
		var queue: Array[int] = [start_index]
		component_ids[start_index] = next_component_id
		var head := 0
		var count := 0
		while head < queue.size():
			var index := queue[head]
			head += 1
			count += 1
			var position := map.get_cell_position(index)
			for offset: Vector2i in D8_OFFSETS:
				var nx := position.x + offset.x
				var ny := position.y + offset.y
				if not _is_inside(map, nx, ny):
					continue
				var neighbor_index := map.get_index(nx, ny)
				if map.is_land[neighbor_index] == 1 and component_ids[neighbor_index] < 0:
					component_ids[neighbor_index] = next_component_id
					queue.append(neighbor_index)
		component_sizes.append(count)
		next_component_id += 1
	return {"ids": component_ids, "sizes": component_sizes}

func _create_regions(world: WorldState, components: Dictionary) -> void:
	var map := world.map
	var component_ids: PackedInt32Array = components["ids"]
	var component_sizes: Array[int] = components["sizes"]
	var total_land := 0
	for size in component_sizes:
		total_land += size
	var eligible_components := {}
	for component_id in component_sizes.size():
		if float(component_sizes[component_id]) / maxf(1.0, float(total_land)) >= 0.08:
			eligible_components[component_id] = true

	var valid_cells: Array[int] = []
	for index in map.width * map.height:
		if map.is_land[index] == 0:
			continue
		var component_id := component_ids[index]
		if eligible_components.has(component_id):
			valid_cells.append(index)
	if valid_cells.is_empty():
		for index in map.width * map.height:
			if map.is_land[index] == 1:
				valid_cells.append(index)
	if valid_cells.is_empty():
		return

	var seeds: Array[int] = []
	var best_first := valid_cells[0]
	for index in valid_cells:
		if map.fertility[index] > map.fertility[best_first]:
			best_first = index
	seeds.append(best_first)
	var required_component_seeds := []
	for component_id in eligible_components.keys():
		if component_id != component_ids[best_first]:
			required_component_seeds.append(int(component_id))
	required_component_seeds.sort()
	for component_id in required_component_seeds:
		if seeds.size() >= TARGET_REGION_COUNT:
			break
		var component_best := -1
		for index in valid_cells:
			if component_ids[index] == component_id and (
				component_best < 0 or map.fertility[index] > map.fertility[component_best]
			):
				component_best = index
		if component_best >= 0:
			seeds.append(component_best)

	while seeds.size() < TARGET_REGION_COUNT and seeds.size() < valid_cells.size():
		var farthest_index := -1
		var farthest_distance := -1
		for candidate in valid_cells:
			var min_distance := 1_000_000
			for seed_index in seeds:
				if component_ids[candidate] != component_ids[seed_index]:
					continue
				var candidate_pos := map.get_cell_position(candidate)
				var seed_pos := map.get_cell_position(seed_index)
				var distance := absi(candidate_pos.x - seed_pos.x) + absi(candidate_pos.y - seed_pos.y)
				min_distance = mini(min_distance, distance)
			if min_distance > farthest_distance:
				farthest_distance = min_distance
				farthest_index = candidate
		if farthest_index < 0 or farthest_distance == 0:
			break
		seeds.append(farthest_index)

	for seed_index in seeds.size():
		var region := RegionData.new()
		region.id = world.allocate_entity_id()
		region.name = "Region %02d" % (seed_index + 1)
		world.regions[region.id] = region
		var seed_cell := seeds[seed_index]
		map.region_id[seed_cell] = region.id

	var queue: Array[int] = []
	for seed_cell in seeds:
		queue.append(seed_cell)
	var head := 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		var region_id := map.region_id[index]
		var position := map.get_cell_position(index)
		for offset: Vector2i in D8_OFFSETS:
			var nx := position.x + offset.x
			var ny := position.y + offset.y
			if not _is_inside(map, nx, ny):
				continue
			var neighbor_index := map.get_index(nx, ny)
			if map.is_land[neighbor_index] == 0 or map.region_id[neighbor_index] >= 0:
				continue
			if component_ids[neighbor_index] != component_ids[index]:
				continue
			map.region_id[neighbor_index] = region_id
			queue.append(neighbor_index)

	for index in map.width * map.height:
		var region_id := map.region_id[index]
		if region_id < 0:
			continue
		var region: RegionData = world.regions[region_id]
		region.cell_indices.append(index)
		var neighbors := _land_neighbors(map, index)
		for neighbor_index in neighbors:
			var neighbor_region_id := map.region_id[neighbor_index]
			if neighbor_region_id >= 0 and neighbor_region_id != region_id:
				var neighbor_ids: Array[int] = region.neighbor_ids
				if not neighbor_ids.has(neighbor_region_id):
					neighbor_ids.append(neighbor_region_id)
	for region_value in world.regions.values():
		var region: RegionData = region_value
		region.cell_indices.sort()
		region.neighbor_ids.sort()

func _create_cultures(world: WorldState) -> void:
	for culture_index in 3:
		var culture := CultureData.new()
		culture.id = world.allocate_entity_id()
		culture.name = "Culture %02d" % (culture_index + 1)
		culture.language_label = "Language %02d" % (culture_index + 1)
		culture.religion_label = "Tradition %02d" % (culture_index + 1)
		culture.values = PackedFloat32Array([
			_society_rng.next_float(),
			_society_rng.next_float(),
			_society_rng.next_float(),
		])
		world.cultures[culture.id] = culture

func _create_settlements(world: WorldState, components: Dictionary) -> void:
	var map := world.map
	var component_ids: PackedInt32Array = components["ids"]
	var candidate_scores := PackedFloat32Array()
	candidate_scores.resize(map.width * map.height)
	var candidates: Array[int] = []
	for index in map.width * map.height:
		if map.is_land[index] == 0 or map.region_id[index] < 0:
			continue
		var freshwater := float(map.has_freshwater[index])
		var coast := 0.0
		var slope_total := 0.0
		var slope_samples := 0
		var position := map.get_cell_position(index)
		for offset: Vector2i in D8_OFFSETS:
			var nx := position.x + offset.x
			var ny := position.y + offset.y
			if not _is_inside(map, nx, ny):
				continue
			var neighbor_index := map.get_index(nx, ny)
			if map.is_land[neighbor_index] == 0:
				coast = 1.0
			else:
				slope_total += absf(map.elevation[index] - map.elevation[neighbor_index])
				slope_samples += 1
		var local_slope := slope_total / maxf(1.0, float(slope_samples))
		var resource_score := 0.0
		for resource_index in WorldMap.RESOURCE_COUNT:
			resource_score = maxf(resource_score, map.resource_potential[resource_index][index])
		candidate_scores[index] = (
			3.0 * map.fertility[index]
			+ 2.0 * freshwater
			+ resource_score
			+ 0.5 * coast
			- 2.0 * local_slope
		)
		candidates.append(index)

	candidates.sort_custom(func(a: int, b: int) -> bool:
		if is_equal_approx(candidate_scores[a], candidate_scores[b]):
			return a < b
		return candidate_scores[a] > candidate_scores[b]
	)
	var chosen: Array[int] = _pick_settlement_sites(candidates, candidate_scores, map, SETTLEMENT_SPACING)
	if chosen.size() < MIN_SETTLEMENTS:
		chosen = _pick_settlement_sites(candidates, candidate_scores, map, 2)
	if chosen.size() > TARGET_SETTLEMENT_COUNT:
		chosen.resize(TARGET_SETTLEMENT_COUNT)

	var culture_ids: Array = world.cultures.keys()
	culture_ids.sort()
	for settlement_index in chosen.size():
		var cell_index := chosen[settlement_index]
		var settlement := SettlementData.new()
		settlement.id = world.allocate_entity_id()
		settlement.name = "Settlement %02d" % (settlement_index + 1)
		settlement.region_id = map.region_id[cell_index]
		settlement.land_component_id = component_ids[cell_index]
		settlement.population = _society_rng.range_int(300, 1_200)
		settlement.status = SettlementData.STATUS_HAMLET if settlement.population < 500 else SettlementData.STATUS_VILLAGE
		settlement.food_store = float(settlement.population) * 0.5
		settlement.site_cell_index = cell_index
		settlement.fertility = map.fertility[cell_index]
		settlement.freshwater_adjacent = map.has_freshwater[cell_index] == 1
		settlement.culture_id = int(culture_ids[settlement_index % culture_ids.size()])
		settlement.resource_stores.resize(WorldMap.RESOURCE_COUNT)
		settlement.occupational_shares = PackedFloat32Array([0.65, 0.20, 0.10, 0.05])
		world.settlements[settlement.id] = settlement
		var region: RegionData = world.regions[settlement.region_id]
		region.settlement_ids.append(settlement.id)

func _assign_cultures_by_origin(world: WorldState, _components: Dictionary) -> void:
	var settlement_ids: Array = world.settlements.keys()
	settlement_ids.sort()
	if settlement_ids.is_empty():
		return
	var culture_ids: Array = world.cultures.keys()
	culture_ids.sort()
	var anchors: Array[int] = [int(settlement_ids[0])]
	while anchors.size() < mini(culture_ids.size(), settlement_ids.size()):
		var farthest_id := -1
		var farthest_distance := -1
		for settlement_id in settlement_ids:
			if anchors.has(settlement_id):
				continue
			var candidate: SettlementData = world.settlements[settlement_id]
			var candidate_point := world.map.get_cell_position(candidate.site_cell_index)
			var nearest_distance := 1_000_000
			for anchor_id in anchors:
				var anchor: SettlementData = world.settlements[anchor_id]
				var anchor_point := world.map.get_cell_position(anchor.site_cell_index)
				nearest_distance = mini(
					nearest_distance,
					absi(candidate_point.x - anchor_point.x) + absi(candidate_point.y - anchor_point.y)
				)
			if nearest_distance > farthest_distance:
				farthest_distance = nearest_distance
				farthest_id = settlement_id
		if farthest_id < 0:
			break
		anchors.append(farthest_id)

	for anchor_index in anchors.size():
		var anchor: SettlementData = world.settlements[anchors[anchor_index]]
		var culture: CultureData = world.cultures[culture_ids[anchor_index]]
		culture.origin_region_id = anchor.region_id
	for settlement_id in settlement_ids:
		var settlement: SettlementData = world.settlements[settlement_id]
		var point := world.map.get_cell_position(settlement.site_cell_index)
		var best_culture_id := int(culture_ids[0])
		var best_distance := 1_000_000
		for anchor_index in anchors.size():
			var anchor: SettlementData = world.settlements[anchors[anchor_index]]
			if settlement.land_component_id != anchor.land_component_id:
				continue
			var anchor_point := world.map.get_cell_position(anchor.site_cell_index)
			var distance := absi(point.x - anchor_point.x) + absi(point.y - anchor_point.y)
			if distance < best_distance:
				best_distance = distance
				best_culture_id = int(culture_ids[anchor_index])
		settlement.culture_id = best_culture_id

func _create_initial_states(world: WorldState, _components: Dictionary) -> void:
	var settlement_ids: Array = world.settlements.keys()
	settlement_ids.sort()
	if settlement_ids.size() < 3:
		return
	var anchors: Array[int] = [int(settlement_ids[0])]
	while anchors.size() < 3:
		var farthest_id := -1
		var farthest_distance := -1
		for settlement_id in settlement_ids:
			if anchors.has(settlement_id):
				continue
			var candidate: SettlementData = world.settlements[settlement_id]
			var nearest_distance := 1_000_000
			for anchor_id in anchors:
				var anchor: SettlementData = world.settlements[anchor_id]
				var candidate_pos := world.map.get_cell_position(candidate.site_cell_index)
				var anchor_pos := world.map.get_cell_position(anchor.site_cell_index)
				nearest_distance = mini(
					nearest_distance,
					absi(candidate_pos.x - anchor_pos.x) + absi(candidate_pos.y - anchor_pos.y)
				)
			if nearest_distance > farthest_distance:
				farthest_distance = nearest_distance
				farthest_id = settlement_id
		anchors.append(farthest_id)

	var state_for_settlement := {}
	for settlement_id in settlement_ids:
		var settlement: SettlementData = world.settlements[settlement_id]
		var best_anchor_id := -1
		var best_distance := 1_000_000
		for anchor_index in anchors.size():
			var anchor: SettlementData = world.settlements[anchors[anchor_index]]
			if settlement.land_component_id != anchor.land_component_id:
				continue
			var point := world.map.get_cell_position(settlement.site_cell_index)
			var anchor_point := world.map.get_cell_position(anchor.site_cell_index)
			var distance := absi(point.x - anchor_point.x) + absi(point.y - anchor_point.y)
			if distance < best_distance:
				best_distance = distance
				best_anchor_id = anchor_index
		if best_anchor_id >= 0:
			state_for_settlement[settlement_id] = best_anchor_id

	var states_by_anchor := {}
	for anchor_index in anchors.size():
		var has_members := false
		for membership in state_for_settlement.values():
			if int(membership) == anchor_index:
				has_members = true
				break
		if not has_members:
			continue
		var state := StateData.new()
		state.id = world.allocate_entity_id()
		state.name = "State %02d" % (anchor_index + 1)
		state.government_type = "chiefdom"
		state.leader_id = world.allocate_entity_id()
		state.leader_since_year = 0
		state.leader_age = _society_rng.range_int(25, 45)
		world.states[state.id] = state
		states_by_anchor[anchor_index] = state

	for settlement_id in state_for_settlement.keys():
		var anchor_index: int = state_for_settlement[settlement_id]
		if not states_by_anchor.has(anchor_index):
			continue
		var settlement: SettlementData = world.settlements[settlement_id]
		var state: StateData = states_by_anchor[anchor_index]
		settlement.state_id = state.id
		state.settlement_ids.append(settlement.id)
	for state_value in world.states.values():
		var state: StateData = state_value
		state.region_ids.clear()
	for region_value in world.regions.values():
		var region: RegionData = region_value
		var population_by_state := {}
		for settlement_id in region.settlement_ids:
			var settlement: SettlementData = world.settlements[settlement_id]
			if settlement.state_id < 0:
				continue
			population_by_state[settlement.state_id] = (
				int(population_by_state.get(settlement.state_id, 0)) + settlement.population
			)
		var state_ids: Array = population_by_state.keys()
		state_ids.sort()
		var largest_population := -1
		for state_id in state_ids:
			var state_population: int = population_by_state[state_id]
			if state_population > largest_population:
				largest_population = state_population
				region.controlling_state_id = int(state_id)
		if region.controlling_state_id >= 0:
			var controlling_state: StateData = world.states[region.controlling_state_id]
			controlling_state.region_ids.append(region.id)
	for state_value in world.states.values():
		var state: StateData = state_value
		state.region_ids.sort()

func _recalculate_region_summaries(world: WorldState) -> void:
	for region_value in world.regions.values():
		var region: RegionData = region_value
		var fertility_total := 0.0
		var resource_totals := PackedFloat32Array()
		resource_totals.resize(WorldMap.RESOURCE_COUNT)
		for cell_index in region.cell_indices:
			fertility_total += world.map.fertility[cell_index]
			for resource_index in WorldMap.RESOURCE_COUNT:
				resource_totals[resource_index] += world.map.resource_potential[resource_index][cell_index]
		var cell_count := maxf(1.0, float(region.cell_indices.size()))
		region.fertility = fertility_total / cell_count
		region.resource_yields.resize(WorldMap.RESOURCE_COUNT)
		for resource_index in WorldMap.RESOURCE_COUNT:
			region.resource_yields[resource_index] = resource_totals[resource_index] / cell_count

func _pick_settlement_sites(
	candidates: Array[int], _scores: PackedFloat32Array, map: WorldMap, minimum_spacing: int
) -> Array[int]:
	var chosen: Array[int] = []
	for candidate in candidates:
		var point := map.get_cell_position(candidate)
		var is_spaced := true
		for chosen_index in chosen:
			var chosen_point := map.get_cell_position(chosen_index)
			var distance := absi(point.x - chosen_point.x) + absi(point.y - chosen_point.y)
			if distance < minimum_spacing:
				is_spaced = false
				break
		if is_spaced:
			chosen.append(candidate)
			if chosen.size() >= TARGET_SETTLEMENT_COUNT:
				break
	return chosen

func _make_value_noise(
	width: int,
	height: int,
	lattice_sizes: Array[int],
	weights: Array[float],
	rng: SeededRandom
) -> PackedFloat32Array:
	var output := PackedFloat32Array()
	output.resize(width * height)
	var total_weight := 0.0
	for octave_index in lattice_sizes.size():
		var spacing := lattice_sizes[octave_index]
		var lattice_width := ceili(float(width - 1) / float(spacing)) + 1
		var lattice_height := ceili(float(height - 1) / float(spacing)) + 1
		var lattice := PackedFloat32Array()
		lattice.resize(lattice_width * lattice_height)
		for lattice_index in lattice.size():
			lattice[lattice_index] = rng.next_float()
		for y in height:
			var grid_y := mini(floori(float(y) / float(spacing)), lattice_height - 2)
			var fraction_y := _smoothstep(float(y - grid_y * spacing) / float(spacing))
			for x in width:
				var grid_x := mini(floori(float(x) / float(spacing)), lattice_width - 2)
				var fraction_x := _smoothstep(float(x - grid_x * spacing) / float(spacing))
				var top_left := lattice[grid_y * lattice_width + grid_x]
				var top_right := lattice[grid_y * lattice_width + grid_x + 1]
				var bottom_left := lattice[(grid_y + 1) * lattice_width + grid_x]
				var bottom_right := lattice[(grid_y + 1) * lattice_width + grid_x + 1]
				var top := lerpf(top_left, top_right, fraction_x)
				var bottom := lerpf(bottom_left, bottom_right, fraction_x)
				var index := y * width + x
				output[index] += lerpf(top, bottom, fraction_y) * weights[octave_index]
		total_weight += weights[octave_index]
	if total_weight > 0.0:
		for index in output.size():
			output[index] /= total_weight
	return output

func _classify_biome(temperature: float, rainfall: float) -> int:
	# IDs: 0 ocean, 1 tundra, 2 desert, 3 grassland, 4 forest, 5 rainforest.
	if temperature < 0.22:
		return 1
	if rainfall < 0.22:
		return 2
	if rainfall < 0.48:
		return 3
	if rainfall < 0.78:
		return 4
	return 5

func _land_neighbors(map: WorldMap, index: int) -> Array[int]:
	var result: Array[int] = []
	var position := map.get_cell_position(index)
	for offset: Vector2i in D8_OFFSETS:
		var nx := position.x + offset.x
		var ny := position.y + offset.y
		if _is_inside(map, nx, ny):
			var neighbor_index := map.get_index(nx, ny)
			if map.is_land[neighbor_index] == 1:
				result.append(neighbor_index)
	return result

func _is_inside(map: WorldMap, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < map.width and y < map.height

func _smoothstep(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)
