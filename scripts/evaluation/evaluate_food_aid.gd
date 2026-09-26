extends SceneTree

const WORLD_COUNT := 20
const YEARS_TO_SIMULATE := 250
const INTERVENTION_YEAR := 100
const FIRST_SEED := 26_092_600

func _initialize() -> void:
	call_deferred("_run_evaluation")

func _run_evaluation() -> void:
	var rows: Array[Dictionary] = []
	for world_index in WORLD_COUNT:
		var seed_value := FIRST_SEED + world_index * 1_009
		var control := WorldGenerator.new().generate(seed_value)
		var treated := WorldGenerator.new().generate(seed_value)
		var engine := SimulationEngine.new()
		engine.advance_years(control, INTERVENTION_YEAR)
		engine.advance_years(treated, INTERVENTION_YEAR)
		var target_id := _most_food_stressed_settlement(control)
		var queue_result := engine.queue_food_relief(treated, target_id)
		engine.advance_years(control, YEARS_TO_SIMULATE - INTERVENTION_YEAR)
		engine.advance_years(treated, YEARS_TO_SIMULATE - INTERVENTION_YEAR)
		rows.append(_compare_pair(seed_value, target_id, control, treated, bool(queue_result.get("ok", false))))
		print(JSON.stringify(rows[-1]))
	print("FOOD_AID_SUMMARY " + JSON.stringify(_summarize(rows)))
	quit()

func _most_food_stressed_settlement(world: WorldState) -> int:
	var selected_id := -1
	var lowest_coverage := INF
	var most_stress_years := -1
	for settlement_value in world.settlements.values():
		var settlement: SettlementData = settlement_value
		if settlement.status == SettlementData.STATUS_ABANDONED or settlement.population <= 0:
			continue
		if (
			settlement.food_coverage < lowest_coverage
			or (is_equal_approx(settlement.food_coverage, lowest_coverage) and settlement.years_in_food_stress > most_stress_years)
			or (is_equal_approx(settlement.food_coverage, lowest_coverage) and settlement.years_in_food_stress == most_stress_years and settlement.id < selected_id)
		):
			selected_id = settlement.id
			lowest_coverage = settlement.food_coverage
			most_stress_years = settlement.years_in_food_stress
	return selected_id

func _compare_pair(seed_value: int, target_id: int, control: WorldState, treated: WorldState, queued: bool) -> Dictionary:
	var control_target: SettlementData = control.settlements[target_id]
	var treated_target: SettlementData = treated.settlements[target_id]
	var applied := 0
	var failed := 0
	var target_famines_control := 0
	var target_famines_treated := 0
	for event in control.events:
		if event.type == "famine_began" and target_id in event.subject_ids:
			target_famines_control += 1
	for event in treated.events:
		if event.type == "intervention_applied" and int(event.facts.get("target_settlement_id", target_id)) == target_id:
			applied += 1
		elif event.type == "intervention_failed":
			failed += 1
		if event.type == "famine_began" and target_id in event.subject_ids:
			target_famines_treated += 1
	return {
		"seed": seed_value,
		"simulation_version": treated.simulation_version,
		"target_settlement_id": target_id,
		"target_population_at_year_250_control": control_target.population,
		"target_population_at_year_250_treated": treated_target.population,
		"target_population_difference": treated_target.population - control_target.population,
		"target_survived_control": control_target.status != SettlementData.STATUS_ABANDONED,
		"target_survived_treated": treated_target.status != SettlementData.STATUS_ABANDONED,
		"target_food_stress_streak_control": control_target.years_in_food_stress,
		"target_food_stress_streak_treated": treated_target.years_in_food_stress,
		"target_famine_events_control": target_famines_control,
		"target_famine_events_treated": target_famines_treated,
		"intervention_queued": queued,
		"intervention_applied": applied,
		"intervention_failed": failed,
	}

func _summarize(rows: Array[Dictionary]) -> Dictionary:
	var population_differences: Array[int] = []
	var stress_differences: Array[int] = []
	var population_up := 0
	var population_down := 0
	var population_equal := 0
	var queued := 0
	var applied := 0
	var failed := 0
	var target_famines_control := 0
	var target_famines_treated := 0
	var seeds_with_target_famine_control := 0
	var seeds_with_target_famine_treated := 0
	var survival_control := 0
	var survival_treated := 0
	for row in rows:
		var population_difference := int(row["target_population_difference"])
		var stress_difference := int(row["target_food_stress_streak_treated"]) - int(row["target_food_stress_streak_control"])
		population_differences.append(population_difference)
		stress_differences.append(stress_difference)
		population_up += 1 if population_difference > 0 else 0
		population_down += 1 if population_difference < 0 else 0
		population_equal += 1 if population_difference == 0 else 0
		queued += 1 if bool(row["intervention_queued"]) else 0
		applied += int(row["intervention_applied"])
		failed += int(row["intervention_failed"])
		target_famines_control += int(row["target_famine_events_control"])
		target_famines_treated += int(row["target_famine_events_treated"])
		seeds_with_target_famine_control += 1 if int(row["target_famine_events_control"]) > 0 else 0
		seeds_with_target_famine_treated += 1 if int(row["target_famine_events_treated"]) > 0 else 0
		survival_control += 1 if bool(row["target_survived_control"]) else 0
		survival_treated += 1 if bool(row["target_survived_treated"]) else 0
	population_differences.sort()
	stress_differences.sort()
	return {
		"world_pairs": rows.size(),
		"simulation_version": int(rows[0]["simulation_version"]),
		"years_each": YEARS_TO_SIMULATE,
		"intervention_year": INTERVENTION_YEAR,
		"targets_queued": queued,
		"interventions_applied": applied,
		"interventions_failed": failed,
		"target_population_difference_min_median_max": [population_differences[0], population_differences[population_differences.size() / 2], population_differences[-1]],
		"targets_with_population_up_down_equal": [population_up, population_down, population_equal],
		"target_food_stress_streak_difference_min_median_max": [stress_differences[0], stress_differences[stress_differences.size() / 2], stress_differences[-1]],
		"target_survival_control_treated": [survival_control, survival_treated],
		"target_famine_events_control_treated": [target_famines_control, target_famines_treated],
		"seeds_with_target_famine_control_treated": [seeds_with_target_famine_control, seeds_with_target_famine_treated],
	}
