extends Control

const DEFAULT_SEED := 20_260_926
const WORLD_MAP_VIEW_SCRIPT := preload("res://scripts/presentation/world_map_view.gd")

var _seed_input: SpinBox
var _map_view: WorldMapView
var _year_label: Label
var _summary_label: Label
var _selection_label: Label
var _chronicle_label: Label
var _world: WorldState
var _simulation_engine := SimulationEngine.new()
var _selected_settlement_id: int = -1

func _ready() -> void:
	_build_interface()
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

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)

	_map_view = WORLD_MAP_VIEW_SCRIPT.new() as WorldMapView
	_map_view.custom_minimum_size = Vector2(560, 560)
	_map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_view.settlement_selected.connect(_on_settlement_selected)
	content.add_child(_map_view)

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

	var selection_title := Label.new()
	selection_title.text = "Selected settlement"
	selection_title.add_theme_font_size_override("font_size", 18)
	sidebar.add_child(selection_title)

	_selection_label = Label.new()
	_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selection_label.text = "Click a settlement marker to inspect it."
	sidebar.add_child(_selection_label)

	var chronicle_title := Label.new()
	chronicle_title.text = "Recent history"
	chronicle_title.add_theme_font_size_override("font_size", 18)
	sidebar.add_child(chronicle_title)

	var chronicle_scroll := ScrollContainer.new()
	chronicle_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chronicle_scroll.custom_minimum_size.y = 170
	sidebar.add_child(chronicle_scroll)

	_chronicle_label = Label.new()
	_chronicle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chronicle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chronicle_scroll.add_child(_chronicle_label)

func _on_generate_pressed() -> void:
	_generate_world(int(_seed_input.value))

func _on_advance_one_year_pressed() -> void:
	_advance_years(1)

func _on_advance_ten_years_pressed() -> void:
	_advance_years(10)

func _generate_world(seed_value: int) -> void:
	_simulation_engine = SimulationEngine.new()
	_world = WorldGenerator.new().generate(seed_value)
	_selected_settlement_id = -1
	_refresh_world_view()

func _advance_years(count: int) -> void:
	if _world == null:
		return
	_simulation_engine.advance_years(_world, count)
	_refresh_world_view()

func _refresh_world_view() -> void:
	_map_view.world = _world
	_map_view.queue_redraw()
	_year_label.text = "Year %d" % _world.year
	var land_count := 0
	var river_count := 0
	var population_total := 0
	for cell_index in _world.map.is_land.size():
		land_count += _world.map.is_land[cell_index]
		river_count += _world.map.is_river[cell_index]
	for settlement_value in _world.settlements.values():
		var settlement: SettlementData = settlement_value
		population_total += settlement.population
	_summary_label.text = (
		"Seed: %s\n" % _world.seed
		+ "Map: %d × %d\n" % [_world.map.width, _world.map.height]
		+ "Land cells: %d\n" % land_count
		+ "River cells: %d\n" % river_count
		+ "Regions: %d\n" % _world.regions.size()
		+ "Settlements: %d\n" % _world.settlements.size()
		+ "Cultures: %d\n" % _world.cultures.size()
		+ "States: %d\n" % _world.states.size()
		+ "Population: %s\n" % _format_number(population_total)
		+ "Recorded events: %d" % _world.events.size()
	)
	_refresh_chronicle()
	if _selected_settlement_id >= 0 and _world.settlements.has(_selected_settlement_id):
		_on_settlement_selected(_selected_settlement_id)
	else:
		_selection_label.text = "Click a settlement marker to inspect it."

func _refresh_chronicle() -> void:
	var lines: Array[String] = []
	var start_index := maxi(0, _world.events.size() - 12)
	for event_index in range(_world.events.size() - 1, start_index - 1, -1):
		var event: HistoryEvent = _world.events[event_index]
		var title := event.type.replace("_", " ").capitalize()
		var line := "Year %d · %s" % [event.year, title]
		if event.type in ["war_declared", "battle_resolved", "peace_agreed"]:
			var state_names: Array[String] = []
			for state_id in event.participant_ids:
				if _world.states.has(state_id):
					var participant_state: StateData = _world.states[state_id]
					state_names.append(participant_state.name)
			if not state_names.is_empty():
				line += " — " + PackedStringArray(state_names).join(" vs ")
		elif not event.subject_ids.is_empty() and _world.settlements.has(event.subject_ids[0]):
			var settlement: SettlementData = _world.settlements[event.subject_ids[0]]
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
			if _world.states.has(winner_id):
				var winner_state: StateData = _world.states[winner_id]
				winner_name = winner_state.name
			line += " — %s won; %s casualties" % [winner_name, _format_number(int(event.facts["casualties"]))]
		elif event.type == "peace_agreed":
			line += " (peace)"
		lines.append(line)
	_chronicle_label.text = "No events yet." if lines.is_empty() else "\n".join(lines)

func _format_number(value: int) -> String:
	var digits := str(value)
	var result := ""
	for digit_index in digits.length():
		if digit_index > 0 and (digits.length() - digit_index) % 3 == 0:
			result += ","
		result += digits[digit_index]
	return result

func _on_settlement_selected(settlement_id: int) -> void:
	if not _world.settlements.has(settlement_id):
		return
	_selected_settlement_id = settlement_id
	var settlement: SettlementData = _world.settlements[settlement_id]
	var region: RegionData = _world.regions[settlement.region_id]
	var culture: CultureData = _world.cultures[settlement.culture_id]
	var state_name := "Independent"
	if settlement.state_id >= 0 and _world.states.has(settlement.state_id):
		var state: StateData = _world.states[settlement.state_id]
		state_name = state.name
	var position := _world.map.get_cell_position(settlement.site_cell_index)
	_selection_label.text = (
		"%s\n" % settlement.name
		+ "Population: %s\n" % _format_number(settlement.population)
		+ "Food coverage: %.0f%%\n" % (settlement.food_coverage * 100.0)
		+ "Region: %s\n" % region.name
		+ "Culture: %s\n" % culture.name
		+ "Political state: %s\n" % state_name
		+ "Fertility: %.2f\n" % settlement.fertility
		+ "Freshwater: %s\n" % ("yes" if settlement.freshwater_adjacent else "no")
		+ "Cell: %d, %d" % [position.x, position.y]
	)
