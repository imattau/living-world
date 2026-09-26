extends Control

const DEFAULT_SEED := 20_260_926
const WORLD_MAP_VIEW_SCRIPT := preload("res://scripts/presentation/world_map_view.gd")

var _seed_input: SpinBox
var _map_view: WorldMapView
var _summary_label: Label
var _selection_label: Label
var _world: WorldState

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
	title.text = "Living World — Seeded World Generator"
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

	var generate_button := Button.new()
	generate_button.text = "Generate world"
	generate_button.pressed.connect(_on_generate_pressed)
	header.add_child(generate_button)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)

	_map_view = WORLD_MAP_VIEW_SCRIPT.new()
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
	selection_title.add_theme_constant_override("margin_top", 12)
	sidebar.add_child(selection_title)

	_selection_label = Label.new()
	_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selection_label.text = "Click a settlement marker to inspect it."
	sidebar.add_child(_selection_label)

func _on_generate_pressed() -> void:
	_generate_world(int(_seed_input.value))

func _generate_world(seed_value: int) -> void:
	_world = WorldGenerator.new().generate(seed_value)
	_map_view.world = _world
	_map_view.queue_redraw()
	var land_count := 0
	var river_count := 0
	for cell_index in _world.map.is_land.size():
		land_count += _world.map.is_land[cell_index]
		river_count += _world.map.is_river[cell_index]
	_summary_label.text = (
		"Seed: %s\n" % _world.seed
		+ "Map: %d × %d\n" % [_world.map.width, _world.map.height]
		+ "Land cells: %d\n" % land_count
		+ "River cells: %d\n" % river_count
		+ "Regions: %d\n" % _world.regions.size()
		+ "Settlements: %d\n" % _world.settlements.size()
		+ "Cultures: %d\n" % _world.cultures.size()
		+ "Proto-states: %d\n" % _world.states.size()
		+ "\nEach run with the same seed reproduces the same starting geography."
	)
	_selection_label.text = "Click a settlement marker to inspect it."

func _on_settlement_selected(settlement_id: int) -> void:
	if not _world.settlements.has(settlement_id):
		return
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
		+ "Population: %s\n" % settlement.population
		+ "Region: %s\n" % region.name
		+ "Culture: %s\n" % culture.name
		+ "Political state: %s\n" % state_name
		+ "Fertility: %.2f\n" % settlement.fertility
		+ "Freshwater: %s\n" % ("yes" if settlement.freshwater_adjacent else "no")
		+ "Cell: %d, %d" % [position.x, position.y]
	)
