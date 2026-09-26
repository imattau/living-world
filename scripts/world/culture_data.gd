class_name CultureData
extends RefCounted

var id: int
var name: String
var origin_region_id: int = -1
var parent_ids: Array[int] = []
var language_label: String
var religion_label: String
var values: PackedFloat32Array()
