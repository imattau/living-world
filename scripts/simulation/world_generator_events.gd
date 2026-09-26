class_name WorldGeneratorEvents
extends RefCounted

static func append_settlement_founded_events(world: WorldState) -> void:
	var settlement_ids: Array = world.settlements.keys()
	settlement_ids.sort()
	for settlement_id in settlement_ids:
		var settlement: SettlementData = world.settlements[settlement_id]
		var event := HistoryEvent.new()
		event.id = world.next_event_id
		world.next_event_id += 1
		event.year = 0
		event.type = "settlement_founded"
		event.location_region_id = settlement.region_id
		event.subject_ids = [settlement.id]
		var status_name := "hamlet" if settlement.status == SettlementData.STATUS_HAMLET else "village"
		event.facts = {"population": settlement.population, "status": status_name}
		world.events.append(event)
