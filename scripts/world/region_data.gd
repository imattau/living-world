class_name RegionData
extends RefCounted

var id: int
var name: String
var cell_indices: Array[int] = []
var neighbor_ids: Array[int] = []
var settlement_ids: Array[int] = []
var fertility: float
var resource_yields := PackedFloat32Array()
var controlling_state_id: int = -1
