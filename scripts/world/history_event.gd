class_name HistoryEvent
extends RefCounted

var id: int
var year: int
var type: String
var location_region_id: int = -1
var location_cell_index: int = -1
var subject_ids: Array[int] = []
var participant_ids: Array[int] = []
var facts: Dictionary = {}
var cause_links: Array[Dictionary] = []

func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"year": year,
		"type": type,
		"location_region_id": location_region_id,
		"location_cell_index": location_cell_index,
		"subject_ids": subject_ids.duplicate(),
		"participant_ids": participant_ids.duplicate(),
		"facts": facts.duplicate(true),
		"cause_links": cause_links.duplicate(true),
	}
