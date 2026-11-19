extends SceneTree

const AtomicJson = preload("res://scripts/AtomicJson.gd")
const ConfigStoreScript = preload("res://scripts/ConfigStore.gd")
const StateStoreScript = preload("res://scripts/StateStore.gd")
const TestSupport = preload("res://tests/TestSupport.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var directory := TestSupport.config_dir()
	if directory == "":
		push_error("An isolated CRAYON_PET_CONFIG_DIR is required.")
		quit(1)
		return
	_test_config(directory)
	await _test_state(directory)
	if failures == 0:
		print("Godot persistence tests passed.")
	quit(0 if failures == 0 else 1)


func _test_config(directory: String) -> void:
	var store = ConfigStoreScript.new()
	var path := directory.path_join("config.json")
	_check(store.configure() == OK and FileAccess.file_exists(path), "First start saves default config")
	var legacy := '{"app":{"display_scale":1.25,"extra":{"value":4},"ai_expression":{"custom":true}},"pins":{"max_count":2}}\n'
	_write_fixture(path, legacy)
	_check(store.load_config() == OK and FileAccess.get_file_as_string(path) == legacy, "Legacy config loads without a rewrite")
	_check(store.app_config().get("display_scale") == 1.25 and store.onboarding_version() == 0, "Legacy settings and defaults")
	var changes := []
	store.config_changed.connect(func(next): changes.append(next))
	_check(store.set_app_config({"skin_id": "test-skin"}) == OK, "Persist the skin alongside cached settings")
	_check(store.set_ai_expression_config({"enabled": true}) == OK, "Persist a partial settings update")
	_check(FileAccess.get_file_as_string(path + ".bak").contains("test-skin"), "Keep the previous valid config")
	_check(store.set_ai_expression_config({"enabled": true}) == OK and changes.size() == 2, "An unchanged setting does not signal a change")
	var reloaded = ConfigStoreScript.new()
	_check(reloaded.configure() == OK, "Reload saved settings")
	var saved: Dictionary = reloaded.get_config()
	_check(saved["app"].get("skin_id") == "test-skin" and saved["app"].get("extra", {}).get("value") == 4
		and saved["app"].get("ai_expression", {}).get("custom") == true and saved["pins"].get("max_count") == 2,
		"Skin and partial updates preserve other settings")
	reloaded.free()

	var primary := FileAccess.get_file_as_string(path)
	var backup := FileAccess.get_file_as_string(path + ".bak")
	DirAccess.make_dir_absolute(path + ".bak.tmp")
	_check(store.set_dialogue_tone("calm") != OK, "Report a backup staging failure")
	_check(FileAccess.get_file_as_string(path) == primary and FileAccess.get_file_as_string(path + ".bak") == backup
		and changes.size() == 2 and store.app_config()["dialogue_tone"] == "gentle",
		"A failed save leaves the files, active config and signal unchanged")
	DirAccess.remove_absolute(path + ".bak.tmp")
	_check(store.set_dialogue_tone("calm") == OK and changes.size() == 3, "Retry a failed settings save")
	if OS.get_name() == "Windows":
		_check(DirAccess.rename_absolute(path, path + ".swap") == OK, "Simulate an interrupted Windows replacement")
		_check(store.load_config() == OK and store.app_config()["dialogue_tone"] == "calm"
			and not FileAccess.file_exists(path + ".swap"), "Recover the displaced primary before the older backup")

	backup = FileAccess.get_file_as_string(path + ".bak")
	_write_fixture(path, '{"app":')
	_check(AtomicJson.read_file(path)["error"] == ERR_PARSE_ERROR, "Distinguish a JSON parse error")
	_check(store.load_config() == OK and store.app_config()["skin_id"] == "test-skin", "Recover settings from a valid backup")
	_check(FileAccess.get_file_as_string(path + ".bak") == backup and _has_archive(directory, "config.json", '{"app":'),
		"Recovery preserves the good backup and damaged bytes")

	var invalid := '{"app":[]}'
	_write_fixture(path, invalid)
	_write_fixture(path + ".bak", "also broken")
	_check(store.load_config() == ERR_INVALID_DATA and store.app_config()["skin_id"] == "classic_shinchan",
		"Schema failure and corrupt backup use in-memory defaults")
	_check(FileAccess.get_file_as_string(path) == invalid and FileAccess.get_file_as_string(path + ".bak") == "also broken",
		"Loading defaults leaves both damaged originals intact")
	_check(store.set_dialogue_tone("calm") == OK and store.set_onboarding_version(1) == OK
		and _has_archive(directory, "config.json", invalid) and _has_archive(directory, "config.json.bak", "also broken"),
		"Subsequent changes can save while preserving both damaged files")

	DirAccess.remove_absolute(path)
	DirAccess.make_dir_absolute(path)
	_check(store.load_config() == ERR_FILE_CANT_READ and store.app_config()["dialogue_tone"] == "calm", "Read failure can use a backup")
	_check(store.set_dialogue_tone("short_cute") == ERR_FILE_CANT_READ, "Refuse to overwrite an unreadable primary")
	DirAccess.remove_absolute(path)
	_check(store.load_config() == OK, "Restore a missing primary from backup")
	store.free()


func _test_state(directory: String) -> void:
	var store = StateStoreScript.new()
	root.add_child(store)
	var path := directory.path_join("state.json")
	_check(store.flush_save() == OK, "Write initial state")
	var primary := FileAccess.get_file_as_string(path)
	for index in range(20):
		store.record_interaction("pet", index + 1)
	_check(store.dirty and store.save_timer.time_left > 4.9 and FileAccess.get_file_as_string(path) == primary
		and not FileAccess.file_exists(path + ".bak"), "Rapid changes restart the 5 s timer without writing")
	Engine.time_scale = 25.0
	await store.save_timer.timeout
	Engine.time_scale = 1.0
	_check(not store.dirty and FileAccess.get_file_as_string(path + ".bak") == primary
		and AtomicJson.read_dictionary(path).get("memory", {}).get("interaction_counts", {}).get("pet") == 20,
		"The debounce writes the batch once")
	primary = FileAccess.get_file_as_string(path)
	DirAccess.make_dir_absolute(path + ".bak.tmp")
	store.record_prompt("food", 21)
	_check(store.flush_save() != OK and store.dirty and not store.save_timer.is_stopped()
		and FileAccess.get_file_as_string(path) == primary, "A failed save keeps the dirty state and schedules a bounded retry")
	DirAccess.remove_absolute(path + ".bak.tmp")
	Engine.time_scale = 25.0
	await store.save_timer.timeout
	Engine.time_scale = 1.0
	await process_frame
	_check(not store.dirty, "Scheduled retry flushes pending state")
	store.feed()
	store.free()

	store = StateStoreScript.new()
	root.add_child(store)
	var saved: Dictionary = store.snapshot()
	_check(saved["mood"] == 75 and saved["memory"].get("last_prompt_kind") == "food"
		and not store.dirty, "Exiting flushes and reopening preserves state and memory")
	var backup := FileAccess.get_file_as_string(path + ".bak")
	_write_fixture(path, '{"mood":[]}')
	_check(store.load_state() == OK and store.dirty and store.snapshot()["mood"] == 70, "Recover state from a valid backup")
	_check(store.flush_save() == OK and FileAccess.get_file_as_string(path + ".bak") == backup, "Damaged state never replaces a valid backup")
	_write_fixture(path, "bad primary")
	_write_fixture(path + ".bak", "bad backup")
	_check(store.load_state() == ERR_PARSE_ERROR and not store.dirty and store.snapshot()["mood"] == 70,
		"Unrecoverable state falls back without scheduling an overwrite")
	store.free()
	_check(FileAccess.get_file_as_string(path) == "bad primary" and FileAccess.get_file_as_string(path + ".bak") == "bad backup",
		"Exit leaves unrecoverable originals untouched")

	_write_fixture(path, '{"mood":82,"energy":42}')
	store = StateStoreScript.new()
	root.add_child(store)
	_check(store.snapshot()["version"] == 2 and store.snapshot()["mood"] == 82 and store.snapshot()["energy"] == 42, "Unversioned legacy state loads")
	store.free()


func _has_archive(directory: String, basename: String, contents: String) -> bool:
	for file in DirAccess.get_files_at(directory):
		if file.begins_with(basename + ".corrupt-") and FileAccess.get_file_as_string(directory.path_join(file)) == contents:
			return true
	return false


func _write_fixture(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(content)
		file.close()
	else:
		_check(false, "Could not write fixture " + path)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
