class_name SettlementData
extends RefCounted

const STATUS_HAMLET := 0
const STATUS_VILLAGE := 1
const STATUS_TOWN := 2
const STATUS_CITY := 3
const STATUS_ABANDONED := 4

var id: int
var name: String
var region_id: int
var land_component_id: int = -1
var founding_year: int = 0
var status: int = STATUS_HAMLET
var population: int
var food_store: float
var food_coverage: float = 1.0
var previous_food_coverage: float = 1.0
var years_in_food_stress: int = 0
var years_below_abandonment_threshold: int = 0
var resource_stores := PackedFloat32Array()
var occupational_shares := PackedFloat32Array()
var culture_id: int = -1
var state_id: int = -1
var site_cell_index: int
var fertility: float
var freshwater_adjacent: bool
