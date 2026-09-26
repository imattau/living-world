class_name SimulationEngine
extends RefCounted

const ENVIRONMENT_STREAM_ID := 5
const CONFLICT_STREAM_ID := 7
const LEADERSHIP_STREAM_ID := 9
const FOOD_YIELD_PER_PERSON := 1.2
const FOOD_NEED_PER_PERSON := 1.0
const FOOD_STORE_CAP_YEARS := 2.0
const INFLUENCE_CAP := 5.0
const INFLUENCE_REGEN_PER_YEAR := 0.1
const FOOD_RELIEF_INFLUENCE_COST := 1.0
const FOOD_RELIEF_NEED_FRACTION := 0.5
const ABANDONMENT_POPULATION := 25
const YEARS_BELOW_ABANDONMENT_THRESHOLD := 5
const LEADER_MIN_DEATH_AGE := 60
const LEADER_DEATH_CHANCE_PER_YEAR_OVER_MIN := 0.02
const LEADER_MAX_DEATH_CHANCE := 0.35
const LOW_STABILITY_COUP_THRESHOLD := 0.15
const COUP_CHANCE_PER_YEAR := 0.15
const CONTESTED_STABILITY_CEILING := 0.35
const CRISIS_STABILITY_PENALTY := 0.12
const PEACEFUL_SUCCESSION_STABILITY_BONUS := 0.02
const HEIR_MIN_AGE := 20
const HEIR_MAX_AGE := 35
const FRAGMENTATION_STABILITY_THRESHOLD := 0.10
const YEARS_BELOW_FRAGMENTATION_THRESHOLD := 5
const FRAGMENTATION_MIN_SETTLEMENTS := 2
const FRAGMENTATION_SUCCESSOR_COUNT_SMALL := 2
const FRAGMENTATION_SUCCESSOR_COUNT_LARGE := 3
const FRAGMENTATION_LARGE_SPLIT_MIN_SETTLEMENTS := 5
const NEW_STATE_LEADER_AGE := 30
const NEW_STATE_STABILITY_FRAGMENT := 0.5
const FORMATION_STATE_STABILITY := 0.6
const FORMATION_POPULATION_THRESHOLD := 400
const CULTURE_DRIFT_MAX_PULL_WEIGHT := 0.15
const CULTURE_DRIFT_MAX_YEARLY_SHIFT_PER_DIMENSION := 0.05
const CULTURE_SPLIT_YEARS_THRESHOLD := 10

var last_year_events: Array[HistoryEvent] = []
var _pending_events: Array[HistoryEvent] = []

func advance_year(world: WorldState) -> Array[HistoryEvent]:
	last_year_events.clear()
	_pending_events.clear()
	if world == null or world.map == null:
		return last_year_events

	var target_year := world.year + 1
	_apply_scheduled_commands(world, target_year)
	var entity_ids := _sorted_settlement_ids(world)
	var weather := _sample_annual_weather(world, entity_ids, target_year)
	var reports := _calculate_harvests(world, entity_ids, weather)
	_apply_population_and_food(world, entity_ids, reports, target_year)
	_apply_migration(world, entity_ids, reports, target_year)
	_update_settlement_status(world, entity_ids, target_year)
	_apply_food_trade(world, entity_ids, target_year)
	_update_politics_and_conflict(world, target_year)
	_update_leadership(world, target_year)
	_update_state_cohesion(world, target_year)
	_update_territorial_growth(world, target_year)
	_update_culture_divergence(world, target_year)
	world.influence = minf(INFLUENCE_CAP, world.influence + INFLUENCE_REGEN_PER_YEAR)
	world.year = target_year
	for event in _pending_events:
		world.events.append(event)
		last_year_events.append(event)
	if world.year > 0 and world.year % 25 == 0:
		world.snapshots.append(WorldSerializer.make_checkpoint(world))
	return last_year_events.duplicate()

func available_influence(world: WorldState) -> float:
	if world == null:
		return 0.0
	var reserved := 0.0
	for command_index in range(world.command_cursor, world.command_log.size()):
		reserved += float(world.command_log[command_index].get("influence_cost", 0.0))
	return maxf(0.0, world.influence - reserved)

func queue_food_relief(world: WorldState, settlement_id: int) -> Dictionary:
	if world == null or not world.settlements.has(settlement_id):
		return {"ok": false, "message": "Choose a settlement first."}
	var settlement: SettlementData = world.settlements[settlement_id]
	if settlement.status == SettlementData.STATUS_ABANDONED or settlement.population <= 0:
		return {"ok": false, "message": "Abandoned settlements cannot receive food aid."}
	if available_influence(world) < FOOD_RELIEF_INFLUENCE_COST:
		return {"ok": false, "message": "Not enough Influence. Aid costs 1 point."}
	var command := {
		"sequence_number": world.next_command_sequence,
		"execute_year": world.year + 1,
		"type": "food_relief",
		"target_settlement_id": settlement_id,
		"influence_cost": FOOD_RELIEF_INFLUENCE_COST,
	}
	world.next_command_sequence += 1
	world.command_log.append(command)
	return {"ok": true, "message": "Food aid scheduled for year %d." % int(command["execute_year"])}

func _apply_scheduled_commands(world: WorldState, year: int) -> void:
	while world.command_cursor < world.command_log.size():
		var command: Dictionary = world.command_log[world.command_cursor]
		if int(command.get("execute_year", 0)) > year:
			break
		world.command_cursor += 1
		if str(command.get("type", "")) != "food_relief":
			continue
		var settlement_id := int(command.get("target_settlement_id", -1))
		var cost := float(command.get("influence_cost", FOOD_RELIEF_INFLUENCE_COST))
		if not world.settlements.has(settlement_id):
			continue
		var settlement: SettlementData = world.settlements[settlement_id]
		if settlement.status == SettlementData.STATUS_ABANDONED or settlement.population <= 0:
			_record_event(world, "intervention_failed", year, settlement.region_id, [settlement_id], {
				"intervention": "food_relief", "target_settlement_id": settlement_id,
				"reason": "target_unavailable", "influence_cost": cost,
			})
			continue
		if world.influence < cost:
			_record_event(world, "intervention_failed", year, settlement.region_id, [settlement_id], {
				"intervention": "food_relief", "target_settlement_id": settlement_id,
				"reason": "insufficient_influence", "influence_cost": cost,
			})
			continue
		var capacity := float(settlement.population) * FOOD_NEED_PER_PERSON * FOOD_STORE_CAP_YEARS
		var amount := minf(float(settlement.population) * FOOD_NEED_PER_PERSON * FOOD_RELIEF_NEED_FRACTION, maxf(0.0, capacity - settlement.food_store))
		if amount <= 0.0:
			_record_event(world, "intervention_failed", year, settlement.region_id, [settlement_id], {
				"intervention": "food_relief", "target_settlement_id": settlement_id,
				"reason": "store_full", "influence_cost": cost,
			})
			continue
		world.influence -= cost
		settlement.food_store += amount
		_record_event(world, "intervention_applied", year, settlement.region_id, [settlement_id], {
			"intervention": "food_relief", "target_settlement_id": settlement_id,
			"command_sequence": int(command.get("sequence_number", 0)),
			"influence_cost": cost, "food_added": amount,
			"target_population": settlement.population,
		})

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
	_apply_migration_culture_drift(world, proposals)
	for origin_id in _sorted_integer_keys(moved_by_origin):
		var origin: SettlementData = world.settlements[origin_id]
		var destination_ids: Array = destinations_by_origin[origin_id]
		destination_ids.sort()
		var participants: Array[int] = [origin_id]
		var destination_facts: Array[int] = []
		var destination_evidence: Array[Dictionary] = []
		for destination_id in destination_ids:
			participants.append(int(destination_id))
			destination_facts.append(int(destination_id))
			var destination_coverage: float = float(reports[int(destination_id)]["food_coverage"])
			destination_evidence.append({
				"settlement_id": int(destination_id),
				"food_coverage": destination_coverage,
				"coverage_gap": destination_coverage - float(reports[origin_id]["food_coverage"]),
			})
		var cause_links: Array[Dictionary] = []
		var food_cause := _find_active_food_cause(world, origin_id)
		if food_cause != null:
			cause_links.append({
				"category": "food_pressure",
				"event_id": food_cause.id,
				"strength": float(reports[origin_id]["food_coverage"]),
			})
		_record_event(
			world,
			"population_migrated",
			year,
			origin.region_id,
			[origin_id],
			{
				"population_moved": int(moved_by_origin[origin_id]),
				"origin_food_coverage": float(reports[origin_id]["food_coverage"]),
				"origin_food_coverage_threshold": 0.6,
				"destination_coverage_gap_threshold": 0.25,
				"destination_settlement_ids": destination_facts,
				"destination_food_coverages": destination_evidence,
				"cause": "food_pressure",
			},
			participants,
			cause_links
		)

func _apply_migration_culture_drift(world: WorldState, proposals: Array[Dictionary]) -> void:
	var cumulative_shift := {}
	for proposal in proposals:
		var amount: int = proposal["amount"]
		if amount <= 0:
			continue
		var origin_id: int = proposal["origin"]
		var destination_id: int = proposal["destination"]
		if not world.settlements.has(origin_id) or not world.settlements.has(destination_id):
			continue
		var origin_settlement: SettlementData = world.settlements[origin_id]
		var destination_settlement: SettlementData = world.settlements[destination_id]
		var origin_culture_id := origin_settlement.culture_id
		var destination_culture_id := destination_settlement.culture_id
		if origin_culture_id < 0 or destination_culture_id < 0 or origin_culture_id == destination_culture_id:
			continue
		if not world.cultures.has(origin_culture_id) or not world.cultures.has(destination_culture_id):
			continue
		var origin_culture: CultureData = world.cultures[origin_culture_id]
		var destination_culture: CultureData = world.cultures[destination_culture_id]
		var dimensions := mini(origin_culture.values.size(), destination_culture.values.size())
		if dimensions <= 0:
			continue
		var weight := clampf(
			float(amount) / float(maxi(1, destination_settlement.population)), 0.0, CULTURE_DRIFT_MAX_PULL_WEIGHT
		)
		if weight <= 0.0:
			continue
		if not cumulative_shift.has(destination_culture_id):
			var zeros: Array[float] = []
			zeros.resize(dimensions)
			zeros.fill(0.0)
			cumulative_shift[destination_culture_id] = zeros
		var shift_used: Array[float] = cumulative_shift[destination_culture_id]
		for index in dimensions:
			var used: float = shift_used[index]
			if used >= CULTURE_DRIFT_MAX_YEARLY_SHIFT_PER_DIMENSION:
				continue
			var remaining := CULTURE_DRIFT_MAX_YEARLY_SHIFT_PER_DIMENSION - used
			var delta := clampf(
				(origin_culture.values[index] - destination_culture.values[index]) * weight, -remaining, remaining
			)
			destination_culture.values[index] = clampf(destination_culture.values[index] + delta, 0.0, 1.0)
			shift_used[index] = used + absf(delta)

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
					"donor_surplus": surplus,
					"recipient_food_coverage": float(world.settlements[int(recipient_info["id"])].food_coverage),
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
	var donor_surplus_by_donor := {}
	var recipient_coverages_by_donor := {}
	for proposal in proposals:
		var amount: float = proposal["amount"]
		if amount <= 0.0:
			continue
		var donor_id: int = proposal["donor"]
		var recipient_id: int = proposal["recipient"]
		store_delta[donor_id] = float(store_delta.get(donor_id, 0.0)) - amount
		store_delta[recipient_id] = float(store_delta.get(recipient_id, 0.0)) + amount
		trade_by_donor[donor_id] = float(trade_by_donor.get(donor_id, 0.0)) + amount
		donor_surplus_by_donor[donor_id] = float(proposal["donor_surplus"])
		if not recipients_by_donor.has(donor_id):
			recipients_by_donor[donor_id] = []
			recipient_coverages_by_donor[donor_id] = []
		recipients_by_donor[donor_id].append(recipient_id)
		recipient_coverages_by_donor[donor_id].append({
			"settlement_id": recipient_id,
			"food_coverage": float(proposal["recipient_food_coverage"]),
		})
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
			{
				"food_amount": float(trade_by_donor[donor_id]),
				"donor_surplus_before_exchange": float(donor_surplus_by_donor[donor_id]),
				"recipient_ids": recipient_ids.duplicate(),
				"recipient_food_coverages_before_exchange": recipient_coverages_by_donor[donor_id].duplicate(true),
				"recipient_food_coverage_threshold": 0.75,
			},
			participants
		)

func _update_politics_and_conflict(world: WorldState, year: int) -> void:
	var state_ids := _active_state_ids(world)
	if state_ids.size() < 2:
		return
	var food_pressure_by_state := {}
	for state_id in state_ids:
		food_pressure_by_state[state_id] = _state_food_pressure(world, int(state_id))
		var state: StateData = world.states[state_id]
		var pressure: float = food_pressure_by_state[state_id]
		state.stability = clampf(state.stability + (0.35 - pressure) * 0.01, 0.0, 1.0)

	var border_pairs: Array[Dictionary] = []
	for first_index in state_ids.size():
		var first_id: int = state_ids[first_index]
		for second_index in range(first_index + 1, state_ids.size()):
			var second_id: int = state_ids[second_index]
			var border_region_id := _shared_border_region(world, first_id, second_id)
			if border_region_id < 0:
				continue
			var first: StateData = world.states[first_id]
			var second: StateData = world.states[second_id]
			var contested := _has_contested_claim(world, first_id, second_id)
			var resource_pressure := clampf(3.0 * maxf(
				float(food_pressure_by_state[first_id]),
				float(food_pressure_by_state[second_id])
			), 0.0, 1.0)
			var cultural_distance := _cultural_distance(
				world, _state_dominant_culture(world, first_id), _state_dominant_culture(world, second_id)
			)
			var dispute_score := (
				0.20
				+ (0.30 if contested else 0.0)
				+ 0.30 * resource_pressure
				+ 0.20 * cultural_distance
			)
			var is_at_war := first.at_war_with.has(second_id) or second.at_war_with.has(first_id)
			var relation := {
				"dispute_score": dispute_score,
				"contested_claim": contested,
				"resource_pressure": resource_pressure,
				"cultural_distance": cultural_distance,
				"last_updated_year": year,
			}
			first.relationships[second_id] = relation.duplicate(true)
			second.relationships[first_id] = relation.duplicate(true)
			if not is_at_war and dispute_score >= 0.70 and first.stability >= 0.25 and second.stability >= 0.25:
				first.at_war_with.append(second_id)
				second.at_war_with.append(first_id)
				first.at_war_with.sort()
				second.at_war_with.sort()
				var cause_links: Array[Dictionary] = []
				if resource_pressure > 0.05:
					for state_id in [first_id, second_id]:
						var worst_settlement_id := _worst_food_settlement(world, int(state_id))
						if worst_settlement_id < 0:
							continue
						var food_cause := _find_active_food_cause(world, worst_settlement_id)
						if food_cause != null:
							cause_links.append({
								"category": "resource_pressure",
								"event_id": food_cause.id,
								"strength": resource_pressure,
							})
				_record_event(
					world,
					"war_declared",
					year,
					border_region_id,
					[first_id, second_id],
					{
						"dispute_score": dispute_score,
						"contested_claim": contested,
						"resource_pressure": resource_pressure,
						"cultural_distance": cultural_distance,
						"stability": [first.stability, second.stability],
					},
					[first_id, second_id],
					cause_links
				)
				is_at_war = true
			if is_at_war:
				border_pairs.append({"first": first_id, "second": second_id, "region": border_region_id})

	var rng := SeededRandom.new(
		SeededRandom.derive_seed(world.seed, CONFLICT_STREAM_ID, world.simulation_version * 65_537 + year)
	)
	for pair in border_pairs:
		var first_id: int = pair["first"]
		var second_id: int = pair["second"]
		var first: StateData = world.states[first_id]
		var second: StateData = world.states[second_id]
		var first_power := _state_military_strength(world, first_id)
		var second_power := _state_military_strength(world, second_id)
		var first_variance := 0.85 + rng.next_float() * 0.30
		var second_variance := 0.85 + rng.next_float() * 0.30
		var first_score := first_power * first_variance
		var second_score := second_power * second_variance
		var winner_id := first_id if first_score >= second_score else second_id
		var loser_id := second_id if winner_id == first_id else first_id
		var winner: StateData = world.states[winner_id]
		var loser: StateData = world.states[loser_id]
		var loser_population_before := _state_population(world, loser_id)
		var casualties := mini(loser_population_before, maxi(1, roundi(float(loser_population_before) * 0.002)))
		_apply_state_casualties(world, loser_id, casualties)
		winner.stability = clampf(winner.stability + 0.015, 0.0, 1.0)
		loser.stability = clampf(loser.stability - 0.04, 0.0, 1.0)
		var battle_cause_links: Array[Dictionary] = []
		var war_declaration := _find_war_declaration_event(world, first_id, second_id)
		if war_declaration != null:
			battle_cause_links.append({
				"category": "war_declared",
				"event_id": war_declaration.id,
				"strength": 1.0,
			})
		var battle_event_id := _record_event(
			world,
			"battle_resolved",
			year,
			int(pair["region"]),
			[winner_id, loser_id],
			{
				"winner_state_id": winner_id,
				"loser_state_id": loser_id,
				"winner_strength": first_score if winner_id == first_id else second_score,
				"loser_strength": second_score if loser_id == second_id else first_score,
				"casualties": casualties,
				"variance_factors": [first_variance, second_variance],
			},
			[winner_id, loser_id],
			battle_cause_links
		)
		_apply_annexation(world, year, int(pair["region"]), winner_id, loser_id, battle_event_id)
		if loser.stability < 0.10:
			first.at_war_with.erase(second_id)
			second.at_war_with.erase(first_id)
			_record_event(
				world,
				"peace_agreed",
				year,
				int(pair["region"]),
				[winner_id, loser_id],
				{
					"reason": "state_instability",
					"losing_state_stability": loser.stability,
					"winner_state_id": winner_id,
					"loser_state_id": loser_id,
				},
				[winner_id, loser_id]
			)

func _active_state_ids(world: WorldState) -> Array[int]:
	var active_ids: Array[int] = []
	for state_id in _sorted_integer_keys(world.states):
		var state: StateData = world.states[state_id]
		if not state.settlement_ids.is_empty():
			active_ids.append(state_id)
	return active_ids

func _apply_annexation(
	world: WorldState, year: int, border_region_id: int, winner_id: int, loser_id: int, battle_event_id: int
) -> void:
	if not world.regions.has(border_region_id):
		return
	var border_region: RegionData = world.regions[border_region_id]
	if border_region.controlling_state_id != loser_id:
		return
	var winner: StateData = world.states[winner_id]
	var loser: StateData = world.states[loser_id]
	var settlements_in_region: Array[int] = []
	for settlement_id in border_region.settlement_ids:
		if not world.settlements.has(settlement_id):
			continue
		var settlement: SettlementData = world.settlements[settlement_id]
		if settlement.state_id == loser_id:
			settlements_in_region.append(settlement_id)
	if settlements_in_region.is_empty():
		return
	var loser_remaining := 0
	for settlement_id in loser.settlement_ids:
		if settlements_in_region.has(settlement_id):
			continue
		var settlement: SettlementData = world.settlements[settlement_id]
		if settlement.status != SettlementData.STATUS_ABANDONED:
			loser_remaining += 1
	if loser_remaining <= 0:
		return

	border_region.controlling_state_id = winner_id
	if not winner.region_ids.has(border_region_id):
		winner.region_ids.append(border_region_id)
		winner.region_ids.sort()
	loser.region_ids.erase(border_region_id)
	for settlement_id in settlements_in_region:
		var settlement: SettlementData = world.settlements[settlement_id]
		settlement.state_id = winner_id
		loser.settlement_ids.erase(settlement_id)
		winner.settlement_ids.append(settlement_id)
	winner.settlement_ids.sort()
	_record_event(
		world,
		"territory_annexed",
		year,
		border_region_id,
		[winner_id, loser_id],
		{
			"region_id": border_region_id,
			"from_state_id": loser_id,
			"to_state_id": winner_id,
			"settlement_ids": settlements_in_region.duplicate(),
		},
		[winner_id, loser_id],
		[{"category": "battle_resolved", "event_id": battle_event_id, "strength": 1.0}]
	)

func _update_leadership(world: WorldState, year: int) -> void:
	var state_ids := _active_state_ids(world)
	if state_ids.is_empty():
		return
	var rng := SeededRandom.new(
		SeededRandom.derive_seed(world.seed, LEADERSHIP_STREAM_ID, world.simulation_version * 65_537 + year)
	)
	for state_id in state_ids:
		var state: StateData = world.states[state_id]
		state.leader_age += 1
		var death_chance := clampf(
			float(state.leader_age - LEADER_MIN_DEATH_AGE) * LEADER_DEATH_CHANCE_PER_YEAR_OVER_MIN,
			0.0,
			LEADER_MAX_DEATH_CHANCE
		)
		var died := death_chance > 0.0 and rng.next_float() < death_chance
		var coup := (
			not died
			and state.stability < LOW_STABILITY_COUP_THRESHOLD
			and rng.next_float() < COUP_CHANCE_PER_YEAR
		)
		if not died and not coup:
			continue

		var previous_leader_id := state.leader_id
		var stability_before := state.stability
		var home_region_id := _state_home_region(world, state_id)
		if died:
			_record_event(
				world,
				"ruler_died",
				year,
				home_region_id,
				[state_id],
				{"previous_leader_id": previous_leader_id, "age": state.leader_age, "cause": "old_age"}
			)

		var contested := coup or stability_before < CONTESTED_STABILITY_CEILING
		var crisis := contested and rng.next_float() < 0.5
		state.leader_id = world.allocate_entity_id()
		state.leader_since_year = year
		state.leader_age = rng.range_int(HEIR_MIN_AGE, HEIR_MAX_AGE)
		state.leader_ordinal += 1
		state.leader_label = "%s %s" % [state.name, _roman_numeral(state.leader_ordinal)]
		if crisis:
			state.stability = clampf(state.stability - CRISIS_STABILITY_PENALTY, 0.0, 1.0)
		elif not contested:
			state.stability = clampf(state.stability + PEACEFUL_SUCCESSION_STABILITY_BONUS, 0.0, 1.0)

		var cause_links: Array[Dictionary] = []
		var battle_cause := _find_causal_event(world, ["battle_resolved"], state_id)
		if battle_cause != null and int(battle_cause.facts.get("loser_state_id", -1)) == state_id:
			cause_links.append({
				"category": "military_defeat",
				"event_id": battle_cause.id,
				"strength": stability_before,
			})
		var food_pressure := _state_food_pressure(world, state_id)
		if food_pressure > 0.4:
			var worst_settlement_id := _worst_food_settlement(world, state_id)
			if worst_settlement_id >= 0:
				var food_cause := _find_active_food_cause(world, worst_settlement_id)
				if food_cause != null:
					cause_links.append({
						"category": "food_pressure",
						"event_id": food_cause.id,
						"strength": food_pressure,
					})
		_record_event(
			world,
			"succession_crisis" if crisis else "ruler_succeeded",
			year,
			home_region_id,
			[state_id],
			{
				"previous_leader_id": previous_leader_id,
				"new_leader_id": state.leader_id,
				"method": "coup" if coup else "hereditary",
				"stability_before": stability_before,
				"stability_after": state.stability,
			},
			[state_id],
			cause_links
		)

func _state_home_region(world: WorldState, state_id: int) -> int:
	var state: StateData = world.states[state_id]
	if not state.region_ids.is_empty():
		return state.region_ids[0]
	return -1

func _update_state_cohesion(world: WorldState, year: int) -> void:
	for state_id in _active_state_ids(world):
		var state: StateData = world.states[state_id]
		if state.stability < FRAGMENTATION_STABILITY_THRESHOLD:
			state.years_below_fragmentation_threshold += 1
		else:
			state.years_below_fragmentation_threshold = 0
		if state.years_below_fragmentation_threshold < YEARS_BELOW_FRAGMENTATION_THRESHOLD:
			continue
		if state.settlement_ids.size() < FRAGMENTATION_MIN_SETTLEMENTS:
			continue
		var successor_count := FRAGMENTATION_SUCCESSOR_COUNT_SMALL
		if state.settlement_ids.size() >= FRAGMENTATION_LARGE_SPLIT_MIN_SETTLEMENTS:
			successor_count = FRAGMENTATION_SUCCESSOR_COUNT_LARGE
		if world.states.size() - 1 + successor_count > world.max_states:
			successor_count = FRAGMENTATION_SUCCESSOR_COUNT_SMALL
		if world.states.size() - 1 + successor_count > world.max_states:
			continue
		_fragment_state(world, year, state_id, successor_count)

func _fragment_state(world: WorldState, year: int, state_id: int, successor_count: int) -> void:
	var state: StateData = world.states[state_id]
	var clusters := _cluster_settlements(world, state.settlement_ids, successor_count)
	if clusters.size() < 2:
		return

	var home_region_id := _state_home_region(world, state_id)
	var stability_before := state.stability
	var affected_settlement_ids := state.settlement_ids.duplicate()
	var successor_ids: Array[int] = []
	for cluster in clusters:
		var successor := StateData.new()
		successor.id = world.allocate_entity_id()
		successor.name = "%s-%d" % [state.name, successor_ids.size() + 1]
		successor.government_type = state.government_type
		successor.leader_id = world.allocate_entity_id()
		successor.leader_since_year = year
		successor.leader_age = NEW_STATE_LEADER_AGE
		successor.stability = NEW_STATE_STABILITY_FRAGMENT
		for settlement_id in cluster:
			var settlement: SettlementData = world.settlements[settlement_id]
			settlement.state_id = successor.id
			successor.settlement_ids.append(settlement_id)
		successor.settlement_ids.sort()
		world.states[successor.id] = successor
		successor_ids.append(successor.id)

	var affected_region_ids := {}
	for settlement_id in affected_settlement_ids:
		var settlement: SettlementData = world.settlements[settlement_id]
		affected_region_ids[settlement.region_id] = true
	_reassign_region_control(world, affected_settlement_ids)
	var affected_state_ids := {}
	affected_state_ids[state_id] = true
	for successor_id in successor_ids:
		affected_state_ids[successor_id] = true
	for region_id in affected_region_ids.keys():
		var region: RegionData = world.regions[region_id]
		if region.controlling_state_id >= 0:
			affected_state_ids[region.controlling_state_id] = true
	_rebuild_region_ids(world, _sorted_integer_keys(affected_state_ids))

	state.settlement_ids.clear()
	state.dissolved_year = year
	state.years_below_fragmentation_threshold = 0

	var cause_links: Array[Dictionary] = []
	var crisis_cause := _find_causal_event(world, ["succession_crisis"], state_id)
	if crisis_cause != null:
		cause_links.append({
			"category": "succession_crisis",
			"event_id": crisis_cause.id,
			"strength": stability_before,
		})
	var battle_cause := _find_causal_event(world, ["battle_resolved"], state_id)
	if battle_cause != null and int(battle_cause.facts.get("loser_state_id", -1)) == state_id:
		cause_links.append({
			"category": "military_defeat",
			"event_id": battle_cause.id,
			"strength": stability_before,
		})
	_record_event(
		world,
		"state_fragmented",
		year,
		home_region_id,
		[state_id],
		{
			"parent_state_id": state_id,
			"successor_state_ids": successor_ids.duplicate(),
			"stability_before": stability_before,
		},
		successor_ids,
		cause_links
	)

func _cluster_settlements(world: WorldState, settlement_ids: Array[int], cluster_count: int) -> Array:
	var ids := settlement_ids.duplicate()
	ids.sort()
	if ids.size() < cluster_count:
		cluster_count = ids.size()
	if cluster_count < 2:
		return []
	var anchors: Array[int] = [ids[0]]
	while anchors.size() < cluster_count:
		var farthest_id := -1
		var farthest_distance := -1
		for candidate_id in ids:
			if anchors.has(candidate_id):
				continue
			var candidate: SettlementData = world.settlements[candidate_id]
			var candidate_pos := world.map.get_cell_position(candidate.site_cell_index)
			var nearest_distance := 1_000_000
			for anchor_id in anchors:
				var anchor: SettlementData = world.settlements[anchor_id]
				var anchor_pos := world.map.get_cell_position(anchor.site_cell_index)
				nearest_distance = mini(
					nearest_distance,
					absi(candidate_pos.x - anchor_pos.x) + absi(candidate_pos.y - anchor_pos.y)
				)
			if nearest_distance > farthest_distance:
				farthest_distance = nearest_distance
				farthest_id = candidate_id
		if farthest_id < 0:
			break
		anchors.append(farthest_id)

	var clusters: Array = []
	for anchor_id in anchors:
		var cluster: Array[int] = [anchor_id]
		clusters.append(cluster)
	for settlement_id in ids:
		if anchors.has(settlement_id):
			continue
		var settlement: SettlementData = world.settlements[settlement_id]
		var settlement_pos := world.map.get_cell_position(settlement.site_cell_index)
		var best_anchor_index := 0
		var best_distance := 1_000_000
		for anchor_index in anchors.size():
			var anchor: SettlementData = world.settlements[anchors[anchor_index]]
			var anchor_pos := world.map.get_cell_position(anchor.site_cell_index)
			var distance := absi(settlement_pos.x - anchor_pos.x) + absi(settlement_pos.y - anchor_pos.y)
			if distance < best_distance:
				best_distance = distance
				best_anchor_index = anchor_index
		var target_cluster: Array[int] = clusters[best_anchor_index]
		target_cluster.append(settlement_id)
	return clusters

func _reassign_region_control(world: WorldState, settlement_ids: Array[int]) -> void:
	var region_ids := {}
	for settlement_id in settlement_ids:
		if not world.settlements.has(settlement_id):
			continue
		var settlement: SettlementData = world.settlements[settlement_id]
		region_ids[settlement.region_id] = true
	for region_id in _sorted_integer_keys(region_ids):
		var region: RegionData = world.regions[region_id]
		var population_by_state := {}
		for member_id in region.settlement_ids:
			if not world.settlements.has(member_id):
				continue
			var member: SettlementData = world.settlements[member_id]
			if member.state_id < 0 or member.status == SettlementData.STATUS_ABANDONED:
				continue
			population_by_state[member.state_id] = (
				int(population_by_state.get(member.state_id, 0)) + member.population
			)
		var candidate_state_ids := _sorted_integer_keys(population_by_state)
		var controlling_id := -1
		var largest_population := -1
		for candidate_state_id in candidate_state_ids:
			var population: int = population_by_state[candidate_state_id]
			if population > largest_population:
				largest_population = population
				controlling_id = candidate_state_id
		region.controlling_state_id = controlling_id

func _rebuild_region_ids(world: WorldState, state_ids: Array[int]) -> void:
	for state_id in state_ids:
		if world.states.has(state_id):
			var state: StateData = world.states[state_id]
			state.region_ids.clear()
	for region_id in _sorted_integer_keys(world.regions):
		var region: RegionData = world.regions[region_id]
		if region.controlling_state_id >= 0 and state_ids.has(region.controlling_state_id):
			if world.states.has(region.controlling_state_id):
				var state: StateData = world.states[region.controlling_state_id]
				state.region_ids.append(region.id)
	for state_id in state_ids:
		if world.states.has(state_id):
			world.states[state_id].region_ids.sort()

func _update_territorial_growth(world: WorldState, year: int) -> void:
	if world.states.size() >= world.max_states:
		return
	for region_id in _sorted_integer_keys(world.regions):
		if world.states.size() >= world.max_states:
			return
		var region: RegionData = world.regions[region_id]
		if region.controlling_state_id >= 0:
			continue
		var population := 0
		var capital_id := -1
		var capital_population := -1
		var candidate_settlement_ids: Array[int] = []
		for settlement_id in region.settlement_ids:
			if not world.settlements.has(settlement_id):
				continue
			var settlement: SettlementData = world.settlements[settlement_id]
			if settlement.status == SettlementData.STATUS_ABANDONED or settlement.state_id >= 0:
				continue
			population += settlement.population
			candidate_settlement_ids.append(settlement_id)
			if settlement.population > capital_population:
				capital_population = settlement.population
				capital_id = settlement_id
		if population < FORMATION_POPULATION_THRESHOLD or capital_id < 0:
			continue

		var new_state := StateData.new()
		new_state.id = world.allocate_entity_id()
		new_state.name = "State %d" % new_state.id
		new_state.government_type = "chiefdom"
		new_state.leader_id = world.allocate_entity_id()
		new_state.leader_since_year = year
		new_state.leader_age = NEW_STATE_LEADER_AGE
		new_state.stability = FORMATION_STATE_STABILITY
		for settlement_id in candidate_settlement_ids:
			var settlement: SettlementData = world.settlements[settlement_id]
			settlement.state_id = new_state.id
			new_state.settlement_ids.append(settlement_id)
		new_state.settlement_ids.sort()
		region.controlling_state_id = new_state.id
		new_state.region_ids.append(region.id)
		world.states[new_state.id] = new_state
		_record_event(
			world,
			"state_founded",
			year,
			region.id,
			[new_state.id],
			{
				"region_id": region.id,
				"capital_settlement_id": capital_id,
				"founding_population": population,
			}
		)

func _update_culture_divergence(world: WorldState, year: int) -> void:
	for culture_id in _sorted_integer_keys(world.cultures):
		var culture: CultureData = world.cultures[culture_id]
		var settlements_by_state := {}
		for settlement_id in _sorted_settlement_ids(world):
			var settlement: SettlementData = world.settlements[settlement_id]
			if settlement.culture_id != culture_id or settlement.status == SettlementData.STATUS_ABANDONED:
				continue
			var state_key: int = settlement.state_id
			if not settlements_by_state.has(state_key):
				settlements_by_state[state_key] = []
			settlements_by_state[state_key].append(settlement_id)
		if settlements_by_state.size() < 2:
			culture.years_states_diverged = 0
			continue
		culture.years_states_diverged += 1
		if culture.years_states_diverged < CULTURE_SPLIT_YEARS_THRESHOLD:
			continue
		_split_culture(world, year, culture_id, settlements_by_state)

func _split_culture(world: WorldState, year: int, culture_id: int, settlements_by_state: Dictionary) -> void:
	var culture: CultureData = world.cultures[culture_id]
	var group_state_ids := _sorted_integer_keys(settlements_by_state)
	var largest_state_id := group_state_ids[0]
	var largest_size := -1
	for state_key in group_state_ids:
		var group: Array = settlements_by_state[state_key]
		if group.size() > largest_size:
			largest_size = group.size()
			largest_state_id = state_key

	var existing_children := 0
	for other_culture_id in world.cultures.keys():
		var other: CultureData = world.cultures[other_culture_id]
		if other.parent_ids.has(culture_id):
			existing_children += 1

	var child_culture_ids: Array[int] = []
	for state_key in group_state_ids:
		if state_key == largest_state_id:
			continue
		var group: Array = settlements_by_state[state_key]
		existing_children += 1
		var child := CultureData.new()
		child.id = world.allocate_entity_id()
		child.name = "%s %s" % [culture.name, _roman_numeral(existing_children + 1)]
		child.origin_region_id = culture.origin_region_id
		child.parent_ids.append(culture_id)
		child.language_label = culture.language_label
		child.religion_label = culture.religion_label
		child.values = culture.values.duplicate()
		world.cultures[child.id] = child
		for settlement_id in group:
			var settlement: SettlementData = world.settlements[settlement_id]
			settlement.culture_id = child.id
		child_culture_ids.append(child.id)

	culture.years_states_diverged = 0
	var home_region_id := -1
	if largest_state_id >= 0 and world.states.has(largest_state_id):
		home_region_id = _state_home_region(world, largest_state_id)
	_record_event(
		world,
		"culture_split",
		year,
		home_region_id,
		[culture_id],
		{
			"parent_culture_id": culture_id,
			"child_culture_ids": child_culture_ids.duplicate(),
			"state_ids_involved": group_state_ids.duplicate(),
		},
		child_culture_ids
	)

func _state_food_pressure(world: WorldState, state_id: int) -> float:
	var weighted_pressure := 0.0
	var population_total := 0.0
	for settlement_id in _sorted_settlement_ids(world):
		var settlement: SettlementData = world.settlements[settlement_id]
		if settlement.state_id != state_id or settlement.status == SettlementData.STATUS_ABANDONED:
			continue
		var weight := float(settlement.population)
		population_total += weight
		weighted_pressure += weight * clampf((0.75 - settlement.food_coverage) / 0.75, 0.0, 1.0)
	return weighted_pressure / population_total if population_total > 0.0 else 0.0

func _state_population(world: WorldState, state_id: int) -> int:
	var total := 0
	for settlement_id in _sorted_settlement_ids(world):
		var settlement: SettlementData = world.settlements[settlement_id]
		if settlement.state_id == state_id and settlement.status != SettlementData.STATUS_ABANDONED:
			total += settlement.population
	return total

func _worst_food_settlement(world: WorldState, state_id: int) -> int:
	var worst_id := -1
	var worst_coverage := INF
	for settlement_id in _sorted_settlement_ids(world):
		var settlement: SettlementData = world.settlements[settlement_id]
		if settlement.state_id != state_id or settlement.status == SettlementData.STATUS_ABANDONED:
			continue
		if settlement.food_coverage < worst_coverage:
			worst_coverage = settlement.food_coverage
			worst_id = settlement_id
	return worst_id

func _state_dominant_culture(world: WorldState, state_id: int) -> int:
	var population_by_culture := {}
	for settlement_id in _sorted_settlement_ids(world):
		var settlement: SettlementData = world.settlements[settlement_id]
		if settlement.state_id != state_id or settlement.status == SettlementData.STATUS_ABANDONED:
			continue
		population_by_culture[settlement.culture_id] = (
			int(population_by_culture.get(settlement.culture_id, 0)) + settlement.population
		)
	var dominant_id := -1
	var largest_population := -1
	for culture_id in _sorted_integer_keys(population_by_culture):
		var population: int = population_by_culture[culture_id]
		if population > largest_population:
			largest_population = population
			dominant_id = culture_id
	return dominant_id

func _cultural_distance(world: WorldState, first_culture_id: int, second_culture_id: int) -> float:
	if first_culture_id < 0 or second_culture_id < 0 or first_culture_id == second_culture_id:
		return 0.0
	if not world.cultures.has(first_culture_id) or not world.cultures.has(second_culture_id):
		return 0.0
	var first: CultureData = world.cultures[first_culture_id]
	var second: CultureData = world.cultures[second_culture_id]
	var dimensions := mini(first.values.size(), second.values.size())
	if dimensions <= 0:
		return 0.0
	var total := 0.0
	for index in dimensions:
		total += absf(first.values[index] - second.values[index])
	return clampf(total / float(dimensions), 0.0, 1.0)

func _state_military_strength(world: WorldState, state_id: int) -> float:
	var strength := 0.0
	for settlement_id in _sorted_settlement_ids(world):
		var settlement: SettlementData = world.settlements[settlement_id]
		if settlement.state_id != state_id or settlement.status == SettlementData.STATUS_ABANDONED:
			continue
		strength += float(settlement.population) * (0.5 + 0.5 * clampf(settlement.food_coverage, 0.0, 1.5))
	return strength

func _apply_state_casualties(world: WorldState, state_id: int, casualties: int) -> void:
	var population := _state_population(world, state_id)
	if population <= 0 or casualties <= 0:
		return
	var candidates: Array[Dictionary] = []
	for settlement_id in _sorted_settlement_ids(world):
		var settlement: SettlementData = world.settlements[settlement_id]
		if settlement.state_id != state_id or settlement.status == SettlementData.STATUS_ABANDONED:
			continue
		candidates.append({
			"id": settlement_id,
			"weight": float(settlement.population),
			"capacity": settlement.population,
		})
	var losses := _split_integer_amount(mini(casualties, population), candidates)
	for settlement_id in _sorted_integer_keys(losses):
		var settlement: SettlementData = world.settlements[settlement_id]
		settlement.population = maxi(0, settlement.population - int(losses[settlement_id]))

func _shared_border_region(world: WorldState, first_state_id: int, second_state_id: int) -> int:
	for region_id in _sorted_integer_keys(world.regions):
		var region: RegionData = world.regions[region_id]
		if region.controlling_state_id != first_state_id:
			continue
		for neighbor_id in region.neighbor_ids:
			if not world.regions.has(neighbor_id):
				continue
			var neighbor: RegionData = world.regions[neighbor_id]
			if neighbor.controlling_state_id == second_state_id:
				return region_id
	return -1

func _has_contested_claim(world: WorldState, first_state_id: int, second_state_id: int) -> bool:
	for region_id in _sorted_integer_keys(world.regions):
		var region: RegionData = world.regions[region_id]
		if region.controlling_state_id != first_state_id and region.controlling_state_id != second_state_id:
			continue
		for settlement_id in region.settlement_ids:
			if not world.settlements.has(settlement_id):
				continue
			var settlement: SettlementData = world.settlements[settlement_id]
			if (region.controlling_state_id == first_state_id and settlement.state_id == second_state_id) or (
				region.controlling_state_id == second_state_id and settlement.state_id == first_state_id
			):
				return true
	return false

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
			var cause_links: Array[Dictionary] = []
			var food_cause := _find_active_food_cause(world, settlement.id)
			if food_cause != null:
				cause_links.append({
					"category": "food_pressure",
					"event_id": food_cause.id,
					"strength": settlement.food_coverage,
				})
			_record_event(
				world,
				"settlement_abandoned",
				year,
				settlement.region_id,
				[settlement.id],
				{"population": settlement.population, "years_below_threshold": settlement.years_below_abandonment_threshold},
				[],
				cause_links
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
	participant_ids: Array[int] = [],
	cause_links: Array[Dictionary] = []
) -> int:
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
	event.cause_links = cause_links.duplicate(true) if not cause_links.is_empty() else _causes_for_event(world, event)
	_pending_events.append(event)
	return event.id

# Finds the most recent event of the given types that names `subject_id`
# among its subjects, searching this year's not-yet-committed events first
# and then the world's committed history. Used to link an outcome (a
# migration, a war, an abandonment) back to the condition that caused it.
func _find_causal_event(world: WorldState, event_types: Array[String], subject_id: int) -> HistoryEvent:
	for index in range(_pending_events.size() - 1, -1, -1):
		var event: HistoryEvent = _pending_events[index]
		if event_types.has(event.type) and event.subject_ids.has(subject_id):
			return event
	for index in range(world.events.size() - 1, -1, -1):
		var event: HistoryEvent = world.events[index]
		if event_types.has(event.type) and event.subject_ids.has(subject_id):
			return event
	return null

func _find_active_food_cause(world: WorldState, settlement_id: int) -> HistoryEvent:
	var event := _find_causal_event(
		world, ["famine_began", "harvest_failure", "harvest_recovery"], settlement_id
	)
	if event == null or event.type == "harvest_recovery":
		return null
	return event

func _find_war_declaration_event(world: WorldState, first_state_id: int, second_state_id: int) -> HistoryEvent:
	for index in range(_pending_events.size() - 1, -1, -1):
		var event: HistoryEvent = _pending_events[index]
		if event.type == "war_declared" and event.subject_ids.has(first_state_id) and event.subject_ids.has(second_state_id):
			return event
	for index in range(world.events.size() - 1, -1, -1):
		var event: HistoryEvent = world.events[index]
		if event.type == "war_declared" and event.subject_ids.has(first_state_id) and event.subject_ids.has(second_state_id):
			return event
	return null

func _causes_for_event(world: WorldState, event: HistoryEvent) -> Array[Dictionary]:
	var causes: Array[Dictionary] = []
	match event.type:
		"intervention_applied":
			causes.append(_condition_cause("player_action", "food_aid_command", {
				"command_sequence": int(event.facts.get("command_sequence", 0)),
				"target_settlement_id": int(event.facts.get("target_settlement_id", -1)),
				"influence_cost": float(event.facts.get("influence_cost", 0.0)),
			}, 1.0))
		"intervention_failed":
			causes.append(_condition_cause("player_action", "food_aid_command_failed", {
				"reason": str(event.facts.get("reason", "unknown")),
				"target_settlement_id": int(event.facts.get("target_settlement_id", -1)),
			}, 1.0))
		"famine_began":
			causes.append(_condition_cause("food_shortage", "coverage_below_famine_threshold", {
				"food_coverage": float(event.facts.get("food_coverage", 0.0)),
				"threshold": 0.5,
				"weather_factor": float(event.facts.get("weather_factor", 1.0)),
			}, 1.0))
		"harvest_failure":
			causes.append(_condition_cause("food_shortage", "coverage_below_stress_threshold", {
				"food_coverage": float(event.facts.get("food_coverage", 0.0)),
				"threshold": 0.75,
				"weather_factor": float(event.facts.get("weather_factor", 1.0)),
			}, 1.0))
		"harvest_recovery":
			causes.append(_condition_cause("food_recovery", "coverage_recovered", {
				"food_coverage": float(event.facts.get("food_coverage", 0.0)),
				"threshold": 0.75,
			}, 1.0))
			_append_recent_event_cause(world, event, causes, ["famine_began", "harvest_failure", "intervention_applied"], event.subject_ids, "recovery_after", 10)
		"population_migrated":
			causes.append(_condition_cause("food_pressure", "origin_food_coverage", {
				"food_coverage": float(event.facts.get("origin_food_coverage", 0.0)),
				"threshold": float(event.facts.get("origin_food_coverage_threshold", 0.6)),
				"destination_coverage_gap_threshold": float(event.facts.get("destination_coverage_gap_threshold", 0.25)),
				"destination_food_coverages": event.facts.get("destination_food_coverages", []),
				"population_moved": int(event.facts.get("population_moved", 0)),
			}, 0.9))
			_append_recent_event_cause(world, event, causes, ["famine_began", "harvest_failure"], event.subject_ids, "migration_after", 5)
		"food_traded":
			causes.append(_condition_cause("food_exchange", "surplus_met_local_shortage", {
				"donor_settlement_id": event.subject_ids[0] if not event.subject_ids.is_empty() else -1,
				"donor_surplus_before_exchange": float(event.facts.get("donor_surplus_before_exchange", 0.0)),
				"recipient_settlement_ids": event.facts.get("recipient_ids", []),
				"recipient_food_coverages_before_exchange": event.facts.get("recipient_food_coverages_before_exchange", []),
				"recipient_food_coverage_threshold": float(event.facts.get("recipient_food_coverage_threshold", 0.75)),
				"food_amount": float(event.facts.get("food_amount", 0.0)),
			}, 0.8))
			for recipient_value in event.facts.get("recipient_ids", []):
				_append_recent_event_cause(world, event, causes, ["famine_began", "harvest_failure"], [int(recipient_value)], "aid_to_stressed_settlement", 3)
		"war_declared":
			causes.append(_condition_cause("territorial_dispute", "dispute_threshold_reached", {
				"dispute_score": float(event.facts.get("dispute_score", 0.0)),
				"threshold": 0.7,
				"contested_claim": bool(event.facts.get("contested_claim", false)),
				"participant_state_ids": event.participant_ids.duplicate(),
			}, 1.0))
			causes.append(_condition_cause("resource_competition", "food_pressure_raised_dispute", {
				"resource_pressure": float(event.facts.get("resource_pressure", 0.0)),
			}, 0.8))
			causes.append(_condition_cause("state_stability", "both_states_above_war_threshold", {
				"stability": event.facts.get("stability", []),
				"threshold": 0.25,
			}, 1.0))
		"battle_resolved":
			_append_recent_event_cause(world, event, causes, ["war_declared"], event.participant_ids, "engagement_in_war", 5)
			causes.append(_condition_cause("military_strength", "seeded_strength_comparison", {
				"winner_state_id": int(event.facts.get("winner_state_id", -1)),
				"winner_strength": float(event.facts.get("winner_strength", 0.0)),
				"loser_strength": float(event.facts.get("loser_strength", 0.0)),
				"variance_factors": event.facts.get("variance_factors", []),
			}, 1.0))
		"peace_agreed":
			_append_recent_event_cause(world, event, causes, ["battle_resolved"], event.participant_ids, "instability_after_battle", 1)
			causes.append(_condition_cause("state_instability", "peace_threshold_reached", {
				"loser_state_id": int(event.facts.get("loser_state_id", -1)),
				"losing_state_stability": float(event.facts.get("losing_state_stability", 0.0)),
				"threshold": 0.1,
			}, 1.0))
		"settlement_abandoned":
			causes.append(_condition_cause("population_decline", "below_abandonment_threshold", {
				"population": int(event.facts.get("population", 0)),
				"years_below_threshold": int(event.facts.get("years_below_threshold", 0)),
				"population_threshold": ABANDONMENT_POPULATION,
				"required_years": YEARS_BELOW_ABANDONMENT_THRESHOLD,
			}, 1.0))
			_append_recent_event_cause(world, event, causes, ["famine_began", "harvest_failure"], event.subject_ids, "decline_after_food_stress", 10)
		"settlement_status_changed":
			causes.append(_condition_cause("population_change", "population_crossed_status_band", {
				"population": int(event.facts.get("population", 0)),
				"from_status": str(event.facts.get("from", "")),
				"to_status": str(event.facts.get("to", "")),
				"status_population_boundaries": [500, 2000, 8000],
			}, 1.0))
	return causes

func _append_recent_event_cause(
	world: WorldState,
	event: HistoryEvent,
	causes: Array[Dictionary],
	event_types: Array,
	entity_ids: Array,
	category: String,
	max_year_gap: int
) -> void:
	var source := _find_recent_event(world, event_types, entity_ids, event.year, max_year_gap)
	if source == null:
		return
	causes.append({
		"event_id": source.id,
		"category": category,
		"strength": 0.8,
	})

func _find_recent_event(world: WorldState, event_types: Array, entity_ids: Array, year: int, max_year_gap: int) -> HistoryEvent:
	var latest: HistoryEvent
	var candidates: Array[HistoryEvent] = []
	candidates.append_array(world.events)
	candidates.append_array(_pending_events)
	for candidate in candidates:
		if not event_types.has(candidate.type) or candidate.year > year or year - candidate.year > max_year_gap:
			continue
		var matching_entity_count := 0
		for entity_id in entity_ids:
			if candidate.subject_ids.has(int(entity_id)) or candidate.participant_ids.has(int(entity_id)):
				matching_entity_count += 1
		var pair_cause := event_types.has("war_declared") or event_types.has("battle_resolved")
		var required_matches := mini(2, entity_ids.size()) if pair_cause else 1
		if matching_entity_count >= required_matches and (latest == null or candidate.id > latest.id):
			latest = candidate
	return latest

func _condition_cause(category: String, condition: String, evidence: Dictionary, strength: float) -> Dictionary:
	return {
		"category": category,
		"condition": condition,
		"evidence": evidence.duplicate(true),
		"strength": strength,
	}

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

const ROMAN_NUMERAL_VALUES := [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
const ROMAN_NUMERAL_SYMBOLS := ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]

func _roman_numeral(value: int) -> String:
	var remaining := value
	var result := ""
	for index in ROMAN_NUMERAL_VALUES.size():
		while remaining >= ROMAN_NUMERAL_VALUES[index]:
			remaining -= ROMAN_NUMERAL_VALUES[index]
			result += ROMAN_NUMERAL_SYMBOLS[index]
	return result

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
