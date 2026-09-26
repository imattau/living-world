class_name WorldSaveStore
extends RefCounted

const DEFAULT_SAVE_PATH := "user://saves/living-world.json"

func save_world(world: WorldState, path: String = DEFAULT_SAVE_PATH) -> Dictionary:
	if world == null:
		return {"ok": false, "message": "There is no world to save."}
	_ensure_checkpoints(world)
	var absolute_directory := ProjectSettings.globalize_path(path.get_base_dir())
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "message": "Could not create save directory (error %d)." % directory_error}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "Could not open save file (error %d)." % FileAccess.get_open_error()}
	file.store_string(JSON.stringify(WorldSerializer.to_save_dictionary(world), "\t"))
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return {"ok": false, "message": "Could not finish writing save file (error %d)." % write_error}
	return {"ok": true, "message": "Saved year %d." % world.year}

func load_world(path: String = DEFAULT_SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "message": "No save file exists yet."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "message": "Could not read save file (error %d)." % FileAccess.get_open_error()}
	var content := file.get_as_text()
	file.close()
	var parser := JSON.new()
	var parse_error := parser.parse(content)
	if parse_error != OK:
		return {
			"ok": false,
			"message": "Save file is invalid at line %d: %s" % [parser.get_error_line(), parser.get_error_message()],
		}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok": false, "message": "Save file root must be an object."}
	var decoded := WorldSerializer.from_save_dictionary(parser.data)
	if decoded.has("error"):
		return {"ok": false, "message": str(decoded["error"])}
	return {"ok": true, "world": decoded["world"], "message": "Loaded year %d." % decoded["world"].year}

func _ensure_checkpoints(world: WorldState) -> void:
	var expected_latest := floori(float(world.year) / 25.0) * 25
	var has_expected_latest := not world.snapshots.is_empty() and (
		int(world.snapshots[0].get("year", -1)) == 0
		and int(world.snapshots[-1].get("year", -1)) == expected_latest
	)
	if has_expected_latest:
		return
	var initial_world := WorldGenerator.new().generate(world.seed)
	initial_world.generator_version = world.generator_version
	initial_world.simulation_version = world.simulation_version
	SimulationEngine.new().advance_years(initial_world, world.year)
	world.snapshots = initial_world.snapshots.duplicate(true)
