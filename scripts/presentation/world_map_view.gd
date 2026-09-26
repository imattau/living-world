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
			draw_rect(rect, color)
			if map.is_land[index] == 1 and _has_region_edge(map, x, y):
				draw_rect(rect, Color(0.055, 0.07, 0.08, 0.26), false, 1.0)

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
