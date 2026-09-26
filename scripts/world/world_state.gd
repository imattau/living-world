class_name WorldState
extends RefCounted

var seed: int
var generator_version: int = 1
var simulation_version: int = 4
var year: int = 0
var map: WorldMap
var regions: Dictionary = {}
var settlements: Dictionary = {}
var cultures: Dictionary = {}
var states: Dictionary = {}
var events: Array[HistoryEvent] = []
var snapshots: Array[Dictionary] = []
var command_log: Array[Dictionary] = []
var command_cursor: int = 0
var next_command_sequence: int = 1
var influence: float = 3.0
var next_entity_id: int = 1
var next_event_id: int = 1

func allocate_entity_id() -> int:
	var allocated_id := next_entity_id
	next_entity_id += 1
	return allocated_id
