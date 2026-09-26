class_name WorldMapView
extends Control

signal settlement_selected(settlement_id: int)

var world: WorldState
var _map_origin := Vector2.ZERO
var _cell_size := 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func _draw() -> void:
	if world == null or world.map == null:
		return
	var map := world.map
	_cell_size = minf(size.x / float(map.width), size.y / float(map.height))
	var map_size := Vector2(float(map.width), float(map.height)) * _cell_size
	_map_origin = (size - map_size) * 0.5

	for y in map.height:
		for x in map.width:
			var index := map.get_index(x, y)
			var rect := Rect2(
				_map_origin + Vector2(x, y) * _cell_size,
				Vector2.ONE * _cell_size
			)
			var color := _biome_color(map.biome[index])
			if map.is_land[index] == 0:
				color = Color("253b50")
			elif map.is_lake[index] == 1:
				color = Color("416f8b")
			elif map.is_river[index] == 1:
				color = Color("568bac")
			if map.is_land[index] == 1:
				var controlling_state_id := _controlling_state_at(map, x, y)
				if controlling_state_id >= 0:
					color = color.lerp(state_color(controlling_state_id), 0.32)
			draw_rect(rect, color)
			if map.is_land[index] == 1 and _has_region_edge(map, x, y):
				draw_rect(rect, Color(0.055, 0.07, 0.08, 0.26), false, 1.0)

	for y in map.height:
		for x in map.width:
			if map.is_land[map.get_index(x, y)] == 0:
				continue
			_draw_state_border_if_needed(map, x, y)

	for settlement_value in world.settlements.values():
		var settlement: SettlementData = settlement_value
		var position := map.get_cell_position(settlement.site_cell_index)
		var center := _map_origin + (Vector2(position) + Vector2(0.5, 0.5)) * _cell_size
		var marker_radius := maxf(2.5, _cell_size * (0.22 + minf(float(settlement.population) / 8_000.0, 0.12)))
		draw_circle(center, marker_radius, Color("f4dfaa"))
		draw_arc(center, marker_radius + 1.5, 0.0, TAU, 16, Color("19242c"), 1.0)

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT or world == null:
		return
	if _cell_size <= 0.0:
		return
	var map_point := (mouse_event.position - _map_origin) / _cell_size
	var cell_x := floori(map_point.x)
	var cell_y := floori(map_point.y)
	if cell_x < 0 or cell_y < 0 or cell_x >= world.map.width or cell_y >= world.map.height:
		return
	var cell_index := world.map.get_index(cell_x, cell_y)
	for settlement_value in world.settlements.values():
		var settlement: SettlementData = settlement_value
		if settlement.site_cell_index == cell_index:
			settlement_selected.emit(settlement.id)
			accept_event()
			return

func _controlling_state_at(map: WorldMap, x: int, y: int) -> int:
	var region_id := map.region_id[map.get_index(x, y)]
	if region_id < 0 or world == null or not world.regions.has(region_id):
		return -1
	var region: RegionData = world.regions[region_id]
	return region.controlling_state_id

static func state_color(state_id: int) -> Color:
	var hue := fposmod(float(state_id) * 0.6180339887, 1.0)
	return Color.from_hsv(hue, 0.55, 0.85)

func _draw_state_border_if_needed(map: WorldMap, x: int, y: int) -> void:
	var this_state := _controlling_state_at(map, x, y)
	var top_left := _map_origin + Vector2(x, y) * _cell_size
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
		var nx := x + offset.x
		var ny := y + offset.y
		if nx >= map.width or ny >= map.height:
			continue
		if map.is_land[map.get_index(nx, ny)] == 0:
			continue
		var neighbor_state := _controlling_state_at(map, nx, ny)
		if neighbor_state == this_state:
			continue
		var edge_start := top_left
		var edge_end := top_left
		if offset.x == 1:
			edge_start += Vector2(_cell_size, 0.0)
			edge_end += Vector2(_cell_size, _cell_size)
		else:
			edge_start += Vector2(0.0, _cell_size)
			edge_end += Vector2(_cell_size, _cell_size)
		draw_line(edge_start, edge_end, Color(0.05, 0.05, 0.06, 0.85), 2.0)

func _has_region_edge(map: WorldMap, x: int, y: int) -> bool:
	var index := map.get_index(x, y)
	var this_region := map.region_id[index]
	if this_region < 0:
		return false
	for offset: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var nx := x + offset.x
		var ny := y + offset.y
		if nx < 0 or ny < 0 or nx >= map.width or ny >= map.height:
			continue
		var neighbor_index := map.get_index(nx, ny)
		if map.is_land[neighbor_index] == 1 and map.region_id[neighbor_index] != this_region:
			return true
	return false

func _biome_color(biome_id: int) -> Color:
	match biome_id:
		1:
			return Color("c9c8bb")
		2:
			return Color("c7a45f")
		3:
			return Color("99ad72")
		4:
			return Color("4f8067")
		5:
			return Color("32765b")
		_:
			return Color("253b50")
