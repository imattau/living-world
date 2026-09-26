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
	_apply_migration(world, entity_ids, reports, target_year)
	_update_settlement_status(world, entity_ids, target_year)
	_apply_food_trade(world, entity_ids, target_year)
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

func _apply_migration(
	world: WorldState, entity_ids: Array[int], reports: Dictionary, year: int
) -> void:
	var proposals: Array[Dictionary] = []
	for origin_id in entity_ids:
		var origin: SettlementData = world.settlements[origin_id]
		if origin.status == SettlementData.STATUS_ABANDONED or origin.population <= 0:
			continue
		var origin_report: Dictionary = reports[origin_id]
		var origin_coverage: float = origin_report["food_coverage"]
		if origin_coverage >= 0.6:
			continue
		var requested := floori(float(origin.population) * 0.05)
		if requested <= 0:
			continue
		var candidates: Array[Dictionary] = []
		for destination_id in entity_ids:
			if destination_id == origin_id:
				continue
			var destination: SettlementData = world.settlements[destination_id]
			if destination.status == SettlementData.STATUS_ABANDONED:
				continue
			if not _regions_are_adjacent(world, origin.region_id, destination.region_id):
				continue
			var destination_report: Dictionary = reports[destination_id]
			var destination_coverage: float = destination_report["food_coverage"]
			var coverage_gap := destination_coverage - origin_coverage
			if coverage_gap < 0.25:
				continue
			var capacity_room := floori(maxf(0.0, _carrying_capacity(destination) - destination.population))
			if capacity_room <= 0:
				continue
			candidates.append({
				"id": destination_id,
				"weight": coverage_gap,
				"capacity": capacity_room,
			})
		if candidates.is_empty():
			continue
		var allocation := _split_integer_amount(requested, candidates)
		for destination_id in _sorted_integer_keys(allocation):
			var amount: int = allocation[destination_id]
			if amount <= 0:
				continue
			proposals.append({"origin": origin_id, "destination": int(destination_id), "amount": amount})

	# Resolve competing arrivals against each destination's capacity in one pass.
	var proposals_by_destination := {}
	var incoming_requested := {}
	for proposal_index in proposals.size():
		var destination_id: int = proposals[proposal_index]["destination"]
		if not proposals_by_destination.has(destination_id):
			proposals_by_destination[destination_id] = []
		proposals_by_destination[destination_id].append(proposal_index)
		incoming_requested[destination_id] = (
			int(incoming_requested.get(destination_id, 0)) + int(proposals[proposal_index]["amount"])
		)
	var migration_destination_ids := _sorted_integer_keys(proposals_by_destination)
	for destination_id in migration_destination_ids:
		var destination: SettlementData = world.settlements[destination_id]
		var room := floori(maxf(0.0, _carrying_capacity(destination) - destination.population))
		var requested_incoming: int = incoming_requested[destination_id]
		if requested_incoming <= room:
			continue
		var arrival_candidates: Array[Dictionary] = []
		var arrival_indexes: Array = proposals_by_destination[destination_id]
		for proposal_index in arrival_indexes:
			var proposal: Dictionary = proposals[proposal_index]
			arrival_candidates.append({
				"id": proposal_index,
				"weight": float(proposal["amount"]),
				"capacity": int(proposal["amount"]),
			})
		var scaled := _split_integer_amount(room, arrival_candidates)
		for proposal_index in arrival_indexes:
			proposals[proposal_index]["amount"] = int(scaled.get(proposal_index, 0))

	var population_delta := {}
	var moved_by_origin := {}
	var destinations_by_origin := {}
	for proposal in proposals:
		var amount: int = proposal["amount"]
		if amount <= 0:
			continue
		var origin_id: int = proposal["origin"]
		var destination_id: int = proposal["destination"]
		population_delta[origin_id] = int(population_delta.get(origin_id, 0)) - amount
		population_delta[destination_id] = int(population_delta.get(destination_id, 0)) + amount
		moved_by_origin[origin_id] = int(moved_by_origin.get(origin_id, 0)) + amount
		if not destinations_by_origin.has(origin_id):
			destinations_by_origin[origin_id] = []
		destinations_by_origin[origin_id].append(destination_id)
	for settlement_id in _sorted_integer_keys(population_delta):
		var settlement: SettlementData = world.settlements[settlement_id]
		settlement.population = maxi(0, settlement.population + int(population_delta[settlement_id]))
		var available_food: float = reports[settlement_id]["available_food"]
		settlement.food_coverage = available_food / maxf(1.0, float(settlement.population))
	for origin_id in _sorted_integer_keys(moved_by_origin):
		var origin: SettlementData = world.settlements[origin_id]
		var destination_ids: Array = destinations_by_origin[origin_id]
		destination_ids.sort()
		var participants: Array[int] = [origin_id]
		var destination_facts: Array[int] = []
		for destination_id in destination_ids:
			participants.append(int(destination_id))
			destination_facts.append(int(destination_id))
		_record_event(
			world,
			"population_migrated",
			year,
			origin.region_id,
			[origin_id],
			{
				"population_moved": int(moved_by_origin[origin_id]),
				"origin_food_coverage": float(reports[origin_id]["food_coverage"]),
				"destination_settlement_ids": destination_facts,
				"cause": "food_pressure",
			},
			participants
		)

func _apply_food_trade(world: WorldState, entity_ids: Array[int], year: int) -> void:
	var proposals: Array[Dictionary] = []
	for donor_id in entity_ids:
		var donor: SettlementData = world.settlements[donor_id]
		if donor.status == SettlementData.STATUS_ABANDONED or donor.state_id < 0:
			continue
		var annual_reserve := float(donor.population) * FOOD_NEED_PER_PERSON
		var surplus := donor.food_store - annual_reserve
		var transfer_limit := surplus * 0.10
		if transfer_limit <= 0.0:
			continue
		var recipients: Array[Dictionary] = []
		var total_weight := 0.0
		for recipient_id in entity_ids:
			if recipient_id == donor_id:
				continue
			var recipient: SettlementData = world.settlements[recipient_id]
			if recipient.status == SettlementData.STATUS_ABANDONED or recipient.state_id != donor.state_id:
				continue
			if not _regions_are_adjacent(world, donor.region_id, recipient.region_id):
				continue
			if recipient.food_coverage >= 0.75:
				continue
			var store_cap := float(recipient.population) * FOOD_NEED_PER_PERSON * FOOD_STORE_CAP_YEARS
			var storage_room := maxf(0.0, store_cap - recipient.food_store)
			var weight := maxf(0.0, 0.75 - recipient.food_coverage)
			if storage_room <= 0.0 or weight <= 0.0:
				continue
			recipients.append({"id": recipient_id, "weight": weight, "room": storage_room})
			total_weight += weight
		if recipients.is_empty() or total_weight <= 0.0:
			continue
		for recipient_info in recipients:
			var amount := minf(
				float(recipient_info["room"]),
				transfer_limit * float(recipient_info["weight"]) / total_weight
			)
			if amount > 0.0:
				proposals.append({
					"donor": donor_id,
					"recipient": int(recipient_info["id"]),
					"amount": amount,
				})

	# Scale simultaneous arrivals if several donors target the same stores.
	var indexes_by_recipient := {}
	var requested_by_recipient := {}
	for proposal_index in proposals.size():
		var recipient_id: int = proposals[proposal_index]["recipient"]
		if not indexes_by_recipient.has(recipient_id):
			indexes_by_recipient[recipient_id] = []
		indexes_by_recipient[recipient_id].append(proposal_index)
		requested_by_recipient[recipient_id] = (
			float(requested_by_recipient.get(recipient_id, 0.0)) + float(proposals[proposal_index]["amount"])
		)
	for recipient_id in _sorted_integer_keys(indexes_by_recipient):
		var recipient: SettlementData = world.settlements[recipient_id]
		var store_cap := float(recipient.population) * FOOD_NEED_PER_PERSON * FOOD_STORE_CAP_YEARS
		var room := maxf(0.0, store_cap - recipient.food_store)
		var requested: float = requested_by_recipient[recipient_id]
		if requested <= room:
			continue
		var scale := room / requested if requested > 0.0 else 0.0
		for proposal_index in indexes_by_recipient[recipient_id]:
			proposals[proposal_index]["amount"] = float(proposals[proposal_index]["amount"]) * scale

	var store_delta := {}
	var trade_by_donor := {}
	var recipients_by_donor := {}
	for proposal in proposals:
		var amount: float = proposal["amount"]
		if amount <= 0.0:
			continue
		var donor_id: int = proposal["donor"]
		var recipient_id: int = proposal["recipient"]
		store_delta[donor_id] = float(store_delta.get(donor_id, 0.0)) - amount
		store_delta[recipient_id] = float(store_delta.get(recipient_id, 0.0)) + amount
		trade_by_donor[donor_id] = float(trade_by_donor.get(donor_id, 0.0)) + amount
		if not recipients_by_donor.has(donor_id):
			recipients_by_donor[donor_id] = []
		recipients_by_donor[donor_id].append(recipient_id)
	for settlement_id in _sorted_integer_keys(store_delta):
		var settlement: SettlementData = world.settlements[settlement_id]
		var food_change: float = store_delta[settlement_id]
		settlement.food_store = maxf(0.0, settlement.food_store + food_change)
		if settlement.population > 0:
			settlement.food_coverage = maxf(
				0.0,
				settlement.food_coverage + food_change / float(settlement.population)
			)
	for donor_id in _sorted_integer_keys(trade_by_donor):
		var recipient_ids: Array = recipients_by_donor[donor_id]
		recipient_ids.sort()
		var donor: SettlementData = world.settlements[donor_id]
		var participants: Array[int] = [int(donor_id)]
		for recipient_id in recipient_ids:
			participants.append(int(recipient_id))
		_record_event(
			world,
			"food_traded",
			year,
			donor.region_id,
			[int(donor_id)],
			{"food_amount": float(trade_by_donor[donor_id]), "recipient_ids": recipient_ids.duplicate()},
			participants
		)

func _split_integer_amount(total: int, candidates: Array[Dictionary]) -> Dictionary:
	var allocations := {}
	for candidate in candidates:
		allocations[int(candidate["id"])] = 0
	var remaining := maxi(0, total)
	while remaining > 0:
		var chosen_id := -1
		var best_priority := -1.0
		for candidate in candidates:
			var candidate_id: int = candidate["id"]
			var allocated: int = allocations[candidate_id]
			if allocated >= int(candidate["capacity"]):
				continue
			var priority := float(candidate["weight"]) / float(allocated + 1)
			if priority > best_priority or (is_equal_approx(priority, best_priority) and candidate_id < chosen_id):
				best_priority = priority
				chosen_id = candidate_id
		if chosen_id < 0:
			break
		allocations[chosen_id] = int(allocations[chosen_id]) + 1
		remaining -= 1
	return allocations

func _regions_are_adjacent(world: WorldState, first_region_id: int, second_region_id: int) -> bool:
	if first_region_id == second_region_id:
		return true
	if not world.regions.has(first_region_id) or not world.regions.has(second_region_id):
		return false
	var region: RegionData = world.regions[first_region_id]
	return region.neighbor_ids.has(second_region_id)

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
	facts: Dictionary,
	participant_ids: Array[int] = []
) -> void:
	var event := HistoryEvent.new()
	event.id = world.next_event_id
	world.next_event_id += 1
	event.year = year
	event.type = event_type
	event.location_region_id = region_id
	for subject_id in subject_ids:
		event.subject_ids.append(subject_id)
	for participant_id in participant_ids:
		event.participant_ids.append(participant_id)
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
	return _sorted_integer_keys(world.settlements)

func _sorted_integer_keys(dictionary: Dictionary) -> Array[int]:
	var keys: Array[int] = []
	for key in dictionary.keys():
		keys.append(int(key))
	keys.sort()
	return keys
