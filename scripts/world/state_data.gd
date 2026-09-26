class_name StateData
extends RefCounted

var id: int
var name: String
var government_type: String = "chiefdom"
var settlement_ids: Array[int] = []
var region_ids: Array[int] = []
var leader_label: String = "Founder"
var leader_id: int = -1
var leader_since_year: int = 0
var leader_age: int = 30
var leader_ordinal: int = 1
var succession_rule: String = "hereditary"
var treasury: float = 0.0
var stability: float = 0.75
var relationships: Dictionary = {}
var at_war_with: Array[int] = []
