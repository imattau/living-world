extends SceneTree

const WORLD_COUNT := 20
const YEARS_TO_SIMULATE := 250
const FIRST_SEED := 26_092_600

func _initialize() -> void:
	call_deferred("_run_evaluation")

func _run_evaluation() -> void:
	var rows: Array[Dictionary] = []
	for world_index in WORLD_COUNT:
		var seed_value := FIRST_SEED + world_index * 1_009
		var world := WorldGenerator.new().generate(seed_value)
		var starting_population := 0
		for settlement_value in world.settlements.values():
			var starting_settlement: SettlementData = settlement_value
			starting_population += starting_settlement.population
		SimulationEngine.new().advance_years(world, YEARS_TO_SIMULATE)
		rows.append(_summarize_world(world, starting_population))
		print(JSON.stringify(rows[-1]))
	print("EVALUATION_SUMMARY " + JSON.stringify(_summarize_collection(rows)))
	quit()

func _summarize_world(world: WorldState, starting_population: int) -> Dictionary:
	var population_total := 0
	var surviving_settlements := 0
	var famine_events := 0
	var food_stress_events := 0
	var migration_events := 0
	var trade_events := 0
	var wars_declared := 0
	var battles := 0
	var peace_events := 0
	var ruler_deaths := 0
	var successions := 0
	var succession_crises := 0
	var territories_annexed := 0
	var states_fragmented := 0
	var states_founded := 0
	var events_with_facts := 0
	var events_with_cause_links := 0
	var maximum_dispute_score := 0.0
	var maximum_resource_pressure := 0.0
	var contested_pairs := 0
	for checkpoint in world.snapshots:
		var checkpoint_state: Dictionary = checkpoint.get("state", {})
		for state_data in checkpoint_state.get("states", []):
			for relation_data in state_data.get("relationships", []):
				var relation: Dictionary = relation_data.get("record", {})
				maximum_dispute_score = maxf(maximum_dispute_score, float(relation.get("dispute_score", 0.0)))
				maximum_resource_pressure = maxf(maximum_resource_pressure, float(relation.get("resource_pressure", 0.0)))
				if int(state_data["id"]) < int(relation_data["other_state_id"]) and bool(relation.get("contested_claim", false)):
					contested_pairs += 1
	for settlement_id in world.settlements.keys():
		var settlement: SettlementData = world.settlements[settlement_id]
		population_total += settlement.population
		if settlement.status != SettlementData.STATUS_ABANDONED:
			surviving_settlements += 1
	for event in world.events:
		if not event.facts.is_empty():
			events_with_facts += 1
		if not event.cause_links.is_empty():
			events_with_cause_links += 1
		match event.type:
			"famine_began":
				famine_events += 1
			"harvest_failure":
				food_stress_events += 1
			"population_migrated":
				migration_events += 1
			"food_traded":
				trade_events += 1
			"war_declared":
				wars_declared += 1
			"battle_resolved":
				battles += 1
			"peace_agreed":
				peace_events += 1
			"ruler_died":
				ruler_deaths += 1
			"ruler_succeeded":
				successions += 1
			"succession_crisis":
				succession_crises += 1
			"territory_annexed":
				territories_annexed += 1
			"state_fragmented":
				states_fragmented += 1
			"state_founded":
				states_founded += 1
	var active_state_ids := {}
	for settlement_value in world.settlements.values():
		var settlement: SettlementData = settlement_value
		if settlement.state_id >= 0 and settlement.population > 0:
			active_state_ids[settlement.state_id] = true
	return {
		"seed": world.seed,
		"population_at_year_250": population_total,
		"settlements_surviving": surviving_settlements,
		"settlements_total": world.settlements.size(),
		"active_states": active_state_ids.size(),
		"famine_events": famine_events,
		"food_stress_events": food_stress_events,
		"migration_events": migration_events,
		"trade_events": trade_events,
		"wars_declared": wars_declared,
		"battles": battles,
		"peace_events": peace_events,
		"ruler_deaths": ruler_deaths,
		"successions": successions,
		"succession_crises": succession_crises,
		"territories_annexed": territories_annexed,
		"states_fragmented": states_fragmented,
		"states_founded": states_founded,
		"events_total": world.events.size(),
		"events_with_facts_percent": 100.0 * float(events_with_facts) / maxf(1.0, float(world.events.size())),
		"events_with_cause_links": events_with_cause_links,
		"maximum_dispute_score": maximum_dispute_score,
		"maximum_resource_pressure": maximum_resource_pressure,
		"contested_border_pairs": contested_pairs,
		"population_at_year_0": starting_population,
	}

func _summarize_collection(rows: Array[Dictionary]) -> Dictionary:
	var population_values: Array[int] = []
	var initial_population_values: Array[int] = []
	var surviving_values: Array[int] = []
	var famine_values: Array[int] = []
	var active_state_values: Array[int] = []
	var war_values: Array[int] = []
	var migration_values: Array[int] = []
	var trade_values: Array[int] = []
	var total_events := 0
	var total_facts_events := 0.0
	var total_cause_links := 0
	var seeds_with_famine := 0
	var seeds_with_migration := 0
	var seeds_with_trade := 0
	var seeds_with_war := 0
	var total_famines := 0
	var total_migrations := 0
	var total_trades := 0
	var total_wars := 0
	var total_battles := 0
	var total_peaces := 0
	var total_ruler_deaths := 0
	var total_successions := 0
	var total_succession_crises := 0
	var total_territories_annexed := 0
	var total_states_fragmented := 0
	var total_states_founded := 0
	for row in rows:
		population_values.append(int(row["population_at_year_250"]))
		initial_population_values.append(int(row["population_at_year_0"]))
		surviving_values.append(int(row["settlements_surviving"]))
		famine_values.append(int(row["famine_events"]))
		active_state_values.append(int(row["active_states"]))
		war_values.append(int(row["wars_declared"]))
		migration_values.append(int(row["migration_events"]))
		trade_values.append(int(row["trade_events"]))
		total_events += int(row["events_total"])
		total_facts_events += float(row["events_with_facts_percent"]) * float(row["events_total"]) / 100.0
		total_cause_links += int(row["events_with_cause_links"])
		seeds_with_famine += 1 if int(row["famine_events"]) > 0 else 0
		seeds_with_migration += 1 if int(row["migration_events"]) > 0 else 0
		seeds_with_trade += 1 if int(row["trade_events"]) > 0 else 0
		seeds_with_war += 1 if int(row["wars_declared"]) > 0 else 0
		total_famines += int(row["famine_events"])
		total_migrations += int(row["migration_events"])
		total_trades += int(row["trade_events"])
		total_wars += int(row["wars_declared"])
		total_battles += int(row["battles"])
		total_peaces += int(row["peace_events"])
		total_ruler_deaths += int(row["ruler_deaths"])
		total_successions += int(row["successions"])
		total_succession_crises += int(row["succession_crises"])
		total_territories_annexed += int(row["territories_annexed"])
		total_states_fragmented += int(row["states_fragmented"])
		total_states_founded += int(row["states_founded"])
	population_values.sort()
	initial_population_values.sort()
	surviving_values.sort()
	famine_values.sort()
	active_state_values.sort()
	war_values.sort()
	migration_values.sort()
	trade_values.sort()
	return {
		"worlds": rows.size(),
		"years_each": YEARS_TO_SIMULATE,
		"population_min": population_values[0],
		"population_median": population_values[population_values.size() / 2],
		"population_max": population_values[-1],
		"initial_population_min": initial_population_values[0],
		"initial_population_median": initial_population_values[initial_population_values.size() / 2],
		"initial_population_max": initial_population_values[-1],
		"settlements_surviving_min": surviving_values[0],
		"settlements_surviving_median": surviving_values[surviving_values.size() / 2],
		"active_states_median": active_state_values[active_state_values.size() / 2],
		"famine_events_median": famine_values[famine_values.size() / 2],
		"wars_declared_median": war_values[war_values.size() / 2],
		"migration_events_median": migration_values[migration_values.size() / 2],
		"trade_events_median": trade_values[trade_values.size() / 2],
		"events_with_facts_percent": 100.0 * total_facts_events / maxf(1.0, float(total_events)),
		"events_with_cause_links": total_cause_links,
		"events_total": total_events,
		"seeds_with_famine": seeds_with_famine,
		"seeds_with_migration": seeds_with_migration,
		"seeds_with_trade": seeds_with_trade,
		"seeds_with_war": seeds_with_war,
		"famine_events_total": total_famines,
		"migration_events_total": total_migrations,
		"trade_events_total": total_trades,
		"wars_declared_total": total_wars,
		"battles_total": total_battles,
		"peace_events_total": total_peaces,
		"ruler_deaths_total": total_ruler_deaths,
		"successions_total": total_successions,
		"succession_crises_total": total_succession_crises,
		"territories_annexed_total": total_territories_annexed,
		"states_fragmented_total": total_states_fragmented,
		"states_founded_total": total_states_founded,
	}
