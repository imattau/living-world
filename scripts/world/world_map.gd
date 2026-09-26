class_name WorldMap
extends RefCounted

const RESOURCE_COUNT := 4

var width: int
var height: int
var elevation := PackedFloat32Array()
var temperature := PackedFloat32Array()
var rainfall := PackedFloat32Array()
var fertility := PackedFloat32Array()
var soil_potential := PackedFloat32Array()
var biome := PackedInt32Array()
var region_id := PackedInt32Array()
var is_land := PackedByteArray()
var is_river := PackedByteArray()
var is_lake := PackedByteArray()
var has_freshwater := PackedByteArray()
var resource_potential: Array[PackedFloat32Array] = []

func initialize(map_width: int, map_height: int) -> void:
	width = map_width
	height = map_height
	var cell_count := width * height
	elevation.resize(cell_count)
	temperature.resize(cell_count)
	rainfall.resize(cell_count)
	fertility.resize(cell_count)
	soil_potential.resize(cell_count)
	biome.resize(cell_count)
	region_id.resize(cell_count)
	region_id.fill(-1)
	is_land.resize(cell_count)
	is_river.resize(cell_count)
	is_lake.resize(cell_count)
	has_freshwater.resize(cell_count)
	for _resource_index in RESOURCE_COUNT:
		var field := PackedFloat32Array()
		field.resize(cell_count)
		resource_potential.append(field)

func get_index(x: int, y: int) -> int:
	return y * width + x

func get_cell_position(index: int) -> Vector2i:
	return Vector2i(index % width, floori(float(index) / float(width)))
