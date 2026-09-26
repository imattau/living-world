extends Control

const DEFAULT_SEED := 20_260_926
const WORLD_MAP_VIEW_SCRIPT := preload("res://scripts/presentation/world_map_view.gd")
const HISTORY_REPLAY_SCRIPT := preload("res://scripts/simulation/history_replay.gd")
const WORLD_SAVE_STORE_SCRIPT := preload("res://scripts/simulation/world_save_store.gd")
const TREND_GRAPH_VIEW_SCRIPT := preload("res://scripts/presentation/trend_graph_view.gd")

const CHRONICLE_MAX_VISIBLE_EVENTS := 300
const CHRONICLE_FILTER_ALL := 0
const CHRONICLE_FILTER_WAR := 1
const CHRONICLE_FILTER_FOOD := 2
const CHRONICLE_FILTER_POLITICS := 3
const CHRONICLE_FILTER_TYPES := {
	CHRONICLE_FILTER_WAR: ["war_declared", "battle_resolved", "peace_agreed", "territory_annexed"],
	CHRONICLE_FILTER_FOOD: ["famine_began", "harvest_failure", "harvest_recovery", "population_migrated", "food_traded"],
	CHRONICLE_FILTER_POLITICS: [
		"ruler_died", "ruler_succeeded", "succession_crisis", "state_fragmented", "state_founded", "culture_split",
	],
}

var _seed_input: SpinBox
var _map_view: WorldMapView
var _year_label: Label
var _history_slider: HSlider
var _history_timer: Timer
var _storage_status_label: Label
var _summary_label: Label
var _selection_label: Label
var _food_aid_button: Button
var _chronicle_list: ItemList
var _chronicle_filter: OptionButton
var _event_detail_label: Label
var _trend_graph: TrendGraphView
var _state_legend: HBoxContainer
var _world: WorldState
var _display_world: WorldState
var _simulation_engine := SimulationEngine.new()
var _history_replay: HistoryReplay
var _save_store: WorldSaveStore
var _selected_settlement_id: int = -1
var _visible_events: Array[HistoryEvent] = []
var _updating_timeline := false

func _ready() -> void:
	_build_interface()
	_history_replay = HISTORY_REPLAY_SCRIPT.new() as HistoryReplay
	_save_store = WORLD_SAVE_STORE_SCRIPT.new() as WorldSaveStore
	_generate_world(DEFAULT_SEED)

func _build_interface() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)

	var title := Label.new()
	title.text = "Living World — Seeded History"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(seed_label)

	_seed_input = SpinBox.new()
	_seed_input.min_value = 1
	_seed_input.max_value = SeededRandom.SEED_MODULUS - 1
	_seed_input.step = 1
	_seed_input.value = DEFAULT_SEED
	_seed_input.custom_minimum_size.x = 150
	header.add_child(_seed_input)

	_year_label = Label.new()
	header.add_child(_year_label)

	var advance_one_button := Button.new()
	advance_one_button.text = "Advance 1 year"
	advance_one_button.pressed.connect(_on_advance_one_year_pressed)
	header.add_child(advance_one_button)

	var advance_ten_button := Button.new()
	advance_ten_button.text = "Advance 10 years"
	advance_ten_button.pressed.connect(_on_advance_ten_years_pressed)
	header.add_child(advance_ten_button)

	var generate_button := Button.new()
	generate_button.text = "Generate world"
	generate_button.pressed.connect(_on_generate_pressed)
	header.add_child(generate_button)

	var save_button := Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(_on_save_pressed)
	header.add_child(save_button)

	var load_button := Button.new()
	load_button.text = "Load"
	load_button.pressed.connect(_on_load_pressed)
	header.add_child(load_button)

	var timeline_row := HBoxContainer.new()
	timeline_row.add_theme_constant_override("separation", 10)
	column.add_child(timeline_row)

	var timeline_title := Label.new()
	timeline_title.text = "Inspect year"
	timeline_row.add_child(timeline_title)

	_history_slider = HSlider.new()
	_history_slider.min_value = 0
	_history_slider.max_value = 0
	_history_slider.step = 1
	_history_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_slider.value_changed.connect(_on_history_year_changed)
	timeline_row.add_child(_history_slider)

	_storage_status_label = Label.new()
	_storage_status_label.custom_minimum_size.x = 180
	timeline_row.add_child(_storage_status_label)

	_history_timer = Timer.new()
	_history_timer.one_shot = true
	_history_timer.wait_time = 0.18
	_history_timer.timeout.connect(_show_inspected_year)
	add_child(_history_timer)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)

	var map_column := VBoxContainer.new()
	map_column.add_theme_constant_override("separation", 6)
	map_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(map_column)

	_map_view = WORLD_MAP_VIEW_SCRIPT.new() as WorldMapView
	_map_view.custom_minimum_size = Vector2(560, 560)
	_map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_view.settlement_selected.connect(_on_settlement_selected)
	map_column.add_child(_map_view)

	var legend_scroll := ScrollContainer.new()
	legend_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	legend_scroll.custom_minimum_size.y = 26
	map_column.add_child(legend_scroll)

	_state_legend = HBoxContainer.new()
	_state_legend.add_theme_constant_override("separation", 14)
	legend_scroll.add_child(_state_legend)

	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 290
	sidebar.add_theme_constant_override("separation", 10)
	content.add_child(sidebar)

	var overview_title := Label.new()
	overview_title.text = "World overview"
	overview_title.add_theme_font_size_override("font_size", 20)
	sidebar.add_child(overview_title)

	_summary_label = Label.new()
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.add_child(_summary_label)

	var trend_title := Label.new()
	trend_title.text = "Population · wars (red) · famine (amber)"
	trend_title.add_theme_font_size_override("font_size", 13)
	sidebar.add_child(trend_title)

	_trend_graph = TREND_GRAPH_VIEW_SCRIPT.new() as TrendGraphView
	_trend_graph.custom_minimum_size = Vector2(0, 70)
	_trend_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.add_child(_trend_graph)

	var selection_title := Label.new()
	selection_title.text = "Selected settlement"
	selection_title.add_theme_font_size_override("font_size", 18)
	sidebar.add_child(selection_title)

	_selection_label = Label.new()
	_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selection_label.text = "Click a settlement marker to inspect it."
	sidebar.add_child(_selection_label)

	_food_aid_button = Button.new()
	_food_aid_button.text = "Send food aid (1 Influence)"
	_food_aid_button.pressed.connect(_on_send_food_aid_pressed)
	sidebar.add_child(_food_aid_button)

	var chronicle_header := HBoxContainer.new()
	chronicle_header.add_theme_constant_override("separation", 10)
	sidebar.add_child(chronicle_header)

	var chronicle_title := Label.new()
	chronicle_title.text = "Recorded history"
	chronicle_title.add_theme_font_size_override("font_size", 18)
	chronicle_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chronicle_header.add_child(chronicle_title)

	_chronicle_filter = OptionButton.new()
	_chronicle_filter.add_item("All events", CHRONICLE_FILTER_ALL)
	_chronicle_filter.add_item("War & conflict", CHRONICLE_FILTER_WAR)
	_chronicle_filter.add_item("Food & population", CHRONICLE_FILTER_FOOD)
	_chronicle_filter.add_item("Politics & culture", CHRONICLE_FILTER_POLITICS)
	_chronicle_filter.item_selected.connect(_on_chronicle_filter_changed)
	chronicle_header.add_child(_chronicle_filter)

	var chronicle_scroll := ScrollContainer.new()
	chronicle_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chronicle_scroll.custom_minimum_size.y = 150
	sidebar.add_child(chronicle_scroll)

	_chronicle_list = ItemList.new()
	_chronicle_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chronicle_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chronicle_list.item_selected.connect(_on_history_event_selected)
	chronicle_scroll.add_child(_chronicle_list)

	_event_detail_label = Label.new()
	_event_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_event_detail_label.custom_minimum_size.y = 74
	_event_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.add_child(_event_detail_label)

func _on_generate_pressed() -> void:
	_generate_world(int(_seed_input.value))
	_storage_status_label.text = "New world generated."

func _on_save_pressed() -> void:
	var result: Dictionary = _save_store.save_world(_world)
	_storage_status_label.text = str(result.get("message", "Save failed."))

func _on_load_pressed() -> void:
	var result: Dictionary = _save_store.load_world()
	_storage_status_label.text = str(result.get("message", "Load failed."))
	if not bool(result.get("ok", false)):
		return
	_history_timer.stop()
	_world = result["world"]
	_display_world = _world
	_simulation_engine = SimulationEngine.new()
	_history_replay.clear()
	_selected_settlement_id = -1
	_seed_input.value = _world.seed
	_refresh_world_view()

func _on_advance_one_year_pressed() -> void:
	_advance_years(1)

func _on_advance_ten_years_pressed() -> void:
	_advance_years(10)

func _generate_world(seed_value: int) -> void:
	_history_timer.stop()
	_simulation_engine = SimulationEngine.new()
	_world = WorldGenerator.new().generate(seed_value)
	_display_world = _world
	_history_replay.clear()
	_selected_settlement_id = -1
	_refresh_world_view()

func _advance_years(count: int) -> void:
	if _world == null:
		return
	_history_timer.stop()
	_simulation_engine.advance_years(_world, count)
	_updating_timeline = true
	_history_slider.max_value = _world.year
	_history_slider.value = _world.year
	_updating_timeline = false
	_display_world = _world
	_refresh_world_view()

func _refresh_world_view() -> void:
	if _display_world == null:
		_display_world = _world
	var viewed := _display_world
	_map_view.world = viewed
	_map_view.queue_redraw()
	_year_label.text = "Head %d · Viewing %d" % [_world.year, viewed.year]
	_updating_timeline = true
	_history_slider.max_value = _world.year
	_history_slider.value = viewed.year
	_updating_timeline = false
	var land_count := 0
	var river_count := 0
	var population_total := 0
	for cell_index in viewed.map.is_land.size():
		land_count += viewed.map.is_land[cell_index]
		river_count += viewed.map.is_river[cell_index]
	for settlement_value in viewed.settlements.values():
		var settlement: SettlementData = settlement_value
		population_total += settlement.population
	var influence_summary := "Influence: %.1f / 5.0" % viewed.influence
	if viewed == _world:
		influence_summary += " (%.1f available)" % _simulation_engine.available_influence(_world)
	else:
		influence_summary += " (historical)"
	_summary_label.text = (
		"Seed: %s\n" % viewed.seed
		+ "Map: %d × %d\n" % [viewed.map.width, viewed.map.height]
		+ "Land cells: %d\n" % land_count
		+ "River cells: %d\n" % river_count
		+ "Regions: %d\n" % viewed.regions.size()
		+ "Settlements: %d\n" % viewed.settlements.size()
		+ "Cultures: %d\n" % viewed.cultures.size()
		+ "States: %d\n" % viewed.states.size()
		+ "Population: %s\n" % _format_number(population_total)
		+ influence_summary + "\n"
		+ "Recorded events: %d" % viewed.events.size()
	)
	_refresh_state_legend(viewed)
	_refresh_trend_graph(viewed)
	_update_food_aid_button()
	_refresh_chronicle()
	if _selected_settlement_id >= 0 and viewed.settlements.has(_selected_settlement_id):
		_on_settlement_selected(_selected_settlement_id)
	else:
		_selection_label.text = "Click a settlement marker to inspect it."

func _refresh_state_legend(viewed: WorldState) -> void:
	for child in _state_legend.get_children():
		child.queue_free()
	var state_ids := viewed.states.keys()
	state_ids.sort()
	for state_id in state_ids:
		var state: StateData = viewed.states[state_id]
		if state.settlement_ids.is_empty():
			continue
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 4)
		var swatch := ColorRect.new()
		swatch.color = WorldMapView.state_color(int(state_id))
		swatch.custom_minimum_size = Vector2(12, 12)
		chip.add_child(swatch)
		var name_label := Label.new()
		name_label.text = state.name
		name_label.add_theme_font_size_override("font_size", 12)
		chip.add_child(name_label)
		_state_legend.add_child(chip)

func _refresh_trend_graph(viewed: WorldState) -> void:
	var point_years := PackedInt32Array()
	var points := PackedFloat32Array()
	for checkpoint in viewed.snapshots:
		var checkpoint_year := int(checkpoint.get("year", 0))
		if checkpoint_year > viewed.year:
			continue
		var state_dict: Dictionary = checkpoint.get("state", {})
		var settlements_data: Array = state_dict.get("settlements", [])
		var population := 0
		for settlement_data in settlements_data:
			population += int(settlement_data.get("population", 0))
		point_years.append(checkpoint_year)
		points.append(float(population))
	var current_population := 0
	for settlement_value in viewed.settlements.values():
		var settlement: SettlementData = settlement_value
		current_population += settlement.population
	if point_years.is_empty() or point_years[-1] != viewed.year:
		point_years.append(viewed.year)
		points.append(float(current_population))

	var war_years := {}
	var famine_years := {}
	for event in viewed.events:
		if event.year > viewed.year:
			continue
		if event.type == "battle_resolved" or event.type == "war_declared":
			war_years[event.year] = true
		elif event.type == "famine_began":
			famine_years[event.year] = true
	var war_years_array := PackedInt32Array()
	for year in war_years.keys():
		war_years_array.append(int(year))
	war_years_array.sort()
	var famine_years_array := PackedInt32Array()
	for year in famine_years.keys():
		famine_years_array.append(int(year))
	famine_years_array.sort()

	_trend_graph.set_data(point_years, points, war_years_array, famine_years_array, maxi(1, viewed.year))

func _on_chronicle_filter_changed(_index: int) -> void:
	_refresh_chronicle()

func _refresh_chronicle() -> void:
	_chronicle_list.clear()
	_visible_events.clear()
	var viewed := _display_world
	var filter_id := CHRONICLE_FILTER_ALL
	if _chronicle_filter.selected >= 0:
		filter_id = _chronicle_filter.get_item_id(_chronicle_filter.selected)
	var allowed_types: Array = CHRONICLE_FILTER_TYPES.get(filter_id, [])
	var shown := 0
	for event_index in range(viewed.events.size() - 1, -1, -1):
		if shown >= CHRONICLE_MAX_VISIBLE_EVENTS:
			break
		var event: HistoryEvent = viewed.events[event_index]
		if filter_id != CHRONICLE_FILTER_ALL and not allowed_types.has(event.type):
			continue
		var title := event.type.replace("_", " ").capitalize()
		var line := "Year %d · %s" % [event.year, title]
		if event.type in ["war_declared", "battle_resolved", "peace_agreed", "territory_annexed"]:
			var state_names: Array[String] = []
			for state_id in event.participant_ids:
				if viewed.states.has(state_id):
					var participant_state: StateData = viewed.states[state_id]
					state_names.append(participant_state.name)
			if not state_names.is_empty():
				line += " — " + " vs ".join(PackedStringArray(state_names))
		elif not event.subject_ids.is_empty() and viewed.settlements.has(event.subject_ids[0]):
			var settlement: SettlementData = viewed.settlements[event.subject_ids[0]]
			line += " — " + settlement.name
		if event.facts.has("food_coverage"):
			line += " (food %.0f%%)" % (float(event.facts["food_coverage"]) * 100.0)
		if event.facts.has("population_moved"):
			line += " (%s people)" % _format_number(int(event.facts["population_moved"]))
		if event.facts.has("food_amount"):
			line += " (%.0f food)" % float(event.facts["food_amount"])
		if event.type == "war_declared" and event.facts.has("dispute_score"):
			line += " (dispute %.2f)" % float(event.facts["dispute_score"])
		elif event.type == "battle_resolved" and event.facts.has("winner_state_id"):
			var winner_id := int(event.facts["winner_state_id"])
			var winner_name := "State %d" % winner_id
			if viewed.states.has(winner_id):
				var winner_state: StateData = viewed.states[winner_id]
				winner_name = winner_state.name
			line += " — %s won; %s casualties" % [winner_name, _format_number(int(event.facts["casualties"]))]
		elif event.type == "peace_agreed":
			line += " (peace)"
		_visible_events.append(event)
		_chronicle_list.add_item(line)
		shown += 1
	if _visible_events.is_empty():
		_chronicle_list.add_item("No events yet.")
		_chronicle_list.set_item_disabled(0, true)
		_event_detail_label.text = "Advance the simulation to record events."
	else:
		_chronicle_list.select(0)
		_on_history_event_selected(0)

func _on_history_year_changed(_value: float) -> void:
	if _updating_timeline:
		return
	_history_timer.start()

func _show_inspected_year() -> void:
	if _world == null:
		return
	_display_world = _history_replay.view_at(_world, int(_history_slider.value))
	_refresh_world_view()

func _on_history_event_selected(item_index: int) -> void:
	if item_index < 0 or item_index >= _visible_events.size():
		return
	var event: HistoryEvent = _visible_events[item_index]
	var detail := "Year %d · %s\n" % [event.year, event.type.replace("_", " ").capitalize()]
	var fact_keys: Array[String] = []
	for key in event.facts.keys():
		fact_keys.append(str(key))
	fact_keys.sort()
	for fact_key in fact_keys:
		detail += "%s: %s\n" % [fact_key.replace("_", " ").capitalize(), str(event.facts[fact_key])]
	if not event.cause_links.is_empty():
		detail += "Causes:\n"
		for cause in event.cause_links:
			detail += "• %s (event %s, strength %s)\n" % [
				str(cause.get("category", "condition")),
				str(cause.get("event_id", "condition")),
				str(cause.get("strength", "—")),
			]
	else:
		detail += "Cause evidence is recorded in the event facts above."
	_event_detail_label.text = detail.strip_edges()

func _format_number(value: int) -> String:
	var digits := str(value)
	var result := ""
	for digit_index in digits.length():
		if digit_index > 0 and (digits.length() - digit_index) % 3 == 0:
			result += ","
		result += digits[digit_index]
	return result

func _on_send_food_aid_pressed() -> void:
	if _world == null or _display_world != _world or _selected_settlement_id < 0:
		return
	var result := _simulation_engine.queue_food_relief(_world, _selected_settlement_id)
	_storage_status_label.text = str(result.get("message", "Could not schedule food aid."))
	_update_food_aid_button()

func _update_food_aid_button() -> void:
	if _food_aid_button == null:
		return
	var can_spend := _world != null and _display_world == _world and _selected_settlement_id >= 0
	if can_spend and _world.settlements.has(_selected_settlement_id):
		var target: SettlementData = _world.settlements[_selected_settlement_id]
		can_spend = target.status != SettlementData.STATUS_ABANDONED and target.population > 0
	else:
		can_spend = false
	_food_aid_button.disabled = not can_spend or _simulation_engine.available_influence(_world) < 1.0

func _on_settlement_selected(settlement_id: int) -> void:
	var viewed := _display_world
	if viewed == null or not viewed.settlements.has(settlement_id):
		return
	_selected_settlement_id = settlement_id
	var settlement: SettlementData = viewed.settlements[settlement_id]
	var region: RegionData = viewed.regions[settlement.region_id]
	var culture: CultureData = viewed.cultures[settlement.culture_id]
	var state_name := "Independent"
	var leader_line := ""
	if settlement.state_id >= 0 and viewed.states.has(settlement.state_id):
		var state: StateData = viewed.states[settlement.state_id]
		state_name = state.name
		leader_line = "Ruled by: %s (since year %d)\n" % [state.leader_label, state.leader_since_year]
	var position := viewed.map.get_cell_position(settlement.site_cell_index)
	_selection_label.text = (
		"%s\n" % settlement.name
		+ "Population: %s\n" % _format_number(settlement.population)
		+ "Food coverage: %.0f%%\n" % (settlement.food_coverage * 100.0)
		+ "Region: %s\n" % region.name
		+ "Culture: %s\n" % culture.name
		+ "Political state: %s\n" % state_name
		+ leader_line
		+ "Fertility: %.2f\n" % settlement.fertility
		+ "Freshwater: %s\n" % ("yes" if settlement.freshwater_adjacent else "no")
		+ "Cell: %d, %d" % [position.x, position.y]
	)
	_update_food_aid_button()
