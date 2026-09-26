class_name SimulationEngine
extends RefCounted

const ENVIRONMENT_STREAM_ID := 5
const FOOD_YIELD_PER_PERSON := 1.2
const FOOD_NEED_PER_PERSON := 1.0
const FOOD_STORE_CAP_YEARS := 2.0
const ABANDONMENT_POPULATION := 25
const YEARS_BELOW_ABANDONMENT_THRESHOLD := 5

var last_year_events: Array[HistoryEvent] = []
var _pending_events: Array[HistoryEvent] = []

func advance_year(world: WorldState) -> Array[HistoryEvent]:
	last_year_events.clear()
	_pending_events.clear()
	if world == null or world.map == null:
		return last_year_events

	var target_year := world.year + 1
	var entity_ids := _sorted_settlement_ids(world)
	var weather := _sample_annual_weather(world, entity_ids, target_year)
	var reports := _calculate_harvests(world, entity_ids, weather)
	_apply_population_and_food(world, entity_ids, reports, target_year)
	_update_settlement_status(world, entity_ids, target_year)
	world.year = target_year
	for event in _pending_events:
		world.events.append(event)
		last_year_events.append(event)
	return last_year_events.duplicate()

func advance_years(world: WorldState, count: int) -> Array[HistoryEvent]:
	var advanced_events: Array[HistoryEvent] = []
	for _year_index in maxi(0, count):
		advanced_events.append_array(advance_year(world))
	return advanced_events

func _sample_annual_weather(
	world: WorldState, entity_ids: Array[int], year: int
) -> Dictionary:
	var versioned_year := world.simulation_version * 65_537 + year
	var rng := SeededRandom.new(
		SeededRandom.derive_seed(world.seed, ENVIRONMENT_STREAM_ID, versioned_year)
	)
	var weather_by_settlement := {}
	for settlement_id in entity_ids:
		var settlement: SettlementData = world.settlements[settlement_id]
		var baseline_rainfall := world.map.rainfall[settlement.site_cell_index]
		var variation := (rng.next_float() - 0.5) * 0.10
		weather_by_settlement[settlement_id] = clampf(
			0.75 + 0.50 * baseline_rainfall + variation, 0.75, 1.25
		)
	return weather_by_settlement

func _calculate_harvests(
	world: WorldState, entity_ids: Array[int], weather: Dictionary
) -> Dictionary:
	var reports := {}
	for settlement_id in entity_ids:
		var settlement: SettlementData = world.settlements[settlement_id]
		var food_yield := 0.0
		if settlement.status != SettlementData.STATUS_ABANDONED:
			food_yield = (
				float(settlement.population)
				* settlement.fertility
				* FOOD_YIELD_PER_PERSON
				* float(weather[settlement_id])
			)
		var available_food := settlement.food_store + food_yield
		var food_need := float(settlement.population) * FOOD_NEED_PER_PERSON
		var coverage := 1.0
		if food_need > 0.0:
			coverage = available_food / food_need
		reports[settlement_id] = {
			"weather_factor": float(weather[settlement_id]),
			"food_yield": food_yield,
			"available_food": available_food,
			"food_coverage": coverage,
			"previous_food_coverage": settlement.food_coverage,
			"population_before": settlement.population,
		}
	return reports

func _apply_population_and_food(
	world: WorldState, entity_ids: Array[int], reports: Dictionary, year: int
) -> void:
	for settlement_id in entity_ids:
		var settlement: SettlementData = world.settlements[settlement_id]
		if settlement.status == SettlementData.STATUS_ABANDONED:
			settlement.population = 0
			settlement.food_store = 0.0
			settlement.previous_food_coverage = 0.0
			settlement.food_coverage = 0.0
			continue

		var report: Dictionary = reports[settlement_id]
		var coverage: float = report["food_coverage"]
		var previous_coverage: float = report["previous_food_coverage"]
		var population_before: int = report["population_before"]
		var natural_growth_rate := 0.0
		if coverage >= 1.0:
			natural_growth_rate = 0.01
		elif coverage > 0.5:
			natural_growth_rate = (coverage - 0.5) * 0.02
		var carrying_capacity := _carrying_capacity(settlement)
		var capacity_factor := maxf(0.0, 1.0 - float(population_before) / carrying_capacity)
		natural_growth_rate *= capacity_factor
		var mortality_rate := 0.0
		if coverage < 0.5:
			mortality_rate = (0.5 - maxf(0.0, coverage)) * 0.06
		var population_change := roundi(
			float(population_before) * clampf(natural_growth_rate - mortality_rate, -0.03, 0.015)
		)
		settlement.population = maxi(0, population_before + population_change)

		var consumed_food := float(population_before) * FOOD_NEED_PER_PERSON
		var remaining_food := maxf(0.0, float(report["available_food"]) - consumed_food)
		var store_limit := float(settlement.population) * FOOD_NEED_PER_PERSON * FOOD_STORE_CAP_YEARS
		settlement.food_store = minf(remaining_food, store_limit)
		settlement.previous_food_coverage = previous_coverage
		settlement.food_coverage = coverage

		if coverage < 0.75:
			settlement.years_in_food_stress += 1
		else:
			settlement.years_in_food_stress = 0
		_record_food_events(
			world,
			settlement,
			year,
			coverage,
			previous_coverage,
			float(report["weather_factor"]),
			float(report["available_food"]),
			population_before
		)

func _update_settlement_status(world: WorldState, entity_ids: Array[int], year: int) -> void:
	for settlement_id in entity_ids:
		var settlement: SettlementData = world.settlements[settlement_id]
		if settlement.status == SettlementData.STATUS_ABANDONED:
			continue
		if settlement.population < ABANDONMENT_POPULATION:
			settlement.years_below_abandonment_threshold += 1
		else:
			settlement.years_below_abandonment_threshold = 0
		if settlement.years_below_abandonment_threshold >= YEARS_BELOW_ABANDONMENT_THRESHOLD:
			settlement.status = SettlementData.STATUS_ABANDONED
			_record_event(
				world,
				"settlement_abandoned",
				year,
				settlement.region_id,
				[settlement.id],
				{"population": settlement.population, "years_below_threshold": settlement.years_below_abandonment_threshold}
			)
			continue

		var new_status := _status_for_population(settlement.population)
		if new_status != settlement.status:
			var previous_status := settlement.status
			settlement.status = new_status
			_record_event(
				world,
				"settlement_status_changed",
				year,
				settlement.region_id,
				[settlement.id],
				{
					"from": _status_name(previous_status),
					"to": _status_name(new_status),
					"population": settlement.population,
				}
			)

func _record_food_events(
	world: WorldState,
	settlement: SettlementData,
	year: int,
	coverage: float,
	previous_coverage: float,
	weather_factor: float,
	available_food: float,
	population_before: int
) -> void:
	var was_famine := previous_coverage < 0.5
	var is_famine := coverage < 0.5
	var was_harvest_stress := previous_coverage < 0.75
	var is_harvest_stress := coverage < 0.75
	if is_famine and not was_famine:
		_record_event(
			world,
			"famine_began",
			year,
			settlement.region_id,
			[settlement.id],
			{
				"food_coverage": coverage,
				"available_food": available_food,
				"weather_factor": weather_factor,
				"population": population_before,
			}
		)
	elif is_harvest_stress and not was_harvest_stress:
		_record_event(
			world,
			"harvest_failure",
			year,
			settlement.region_id,
			[settlement.id],
			{
				"food_coverage": coverage,
				"weather_factor": weather_factor,
				"population": population_before,
			}
		)
	elif not is_harvest_stress and was_harvest_stress:
		_record_event(
			world,
			"harvest_recovery",
			year,
			settlement.region_id,
			[settlement.id],
			{"food_coverage": coverage, "population": settlement.population}
		)

func _record_event(
	world: WorldState,
	event_type: String,
	year: int,
	region_id: int,
	subject_ids: Array[int],
	facts: Dictionary
) -> void:
	var event := HistoryEvent.new()
	event.id = world.next_event_id
	world.next_event_id += 1
	event.year = year
	event.type = event_type
	event.location_region_id = region_id
	event.subject_ids = subject_ids.duplicate()
	event.facts = facts.duplicate(true)
	_pending_events.append(event)

func _carrying_capacity(settlement: SettlementData) -> float:
	var freshwater_bonus := 300.0 if settlement.freshwater_adjacent else 0.0
	return 500.0 + 1_500.0 * settlement.fertility + freshwater_bonus

func _status_for_population(population: int) -> int:
	if population < 500:
		return SettlementData.STATUS_HAMLET
	if population < 2_000:
		return SettlementData.STATUS_VILLAGE
	if population < 8_000:
		return SettlementData.STATUS_TOWN
	return SettlementData.STATUS_CITY

func _status_name(status: int) -> String:
	match status:
		SettlementData.STATUS_HAMLET:
			return "hamlet"
		SettlementData.STATUS_VILLAGE:
			return "village"
		SettlementData.STATUS_TOWN:
			return "town"
		SettlementData.STATUS_CITY:
			return "city"
		SettlementData.STATUS_ABANDONED:
			return "abandoned"
		_:
			return "unknown"

func _sorted_settlement_ids(world: WorldState) -> Array[int]:
	var ids: Array[int] = []
	for key in world.settlements.keys():
		ids.append(int(key))
	ids.sort()
	return ids
