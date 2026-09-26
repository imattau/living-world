class_name StateData
extends RefCounted

var id: int
var name: String
var government_type: String = "chiefdom"
var settlement_ids: Array[int] = []
var region_ids: Array[int] = []
var leader_label: String = "Founder"
var treasury: float = 0.0
var stability: float = 0.75
var relationships: Dictionary = {}
var at_war_with: Array[int] = []
