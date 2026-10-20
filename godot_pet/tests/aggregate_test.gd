extends SceneTree

const EventStore = preload("res://scripts/CompanionEventStore.gd")
const Memory = preload("res://scripts/CompanionMemory.gd")
const Profile = preload("res://scripts/CompanionLongTermProfile.gd")
const Brain = preload("res://scripts/BehaviorBrain.gd")
const Support = preload("res://tests/TestSupport.gd")
var failed := false


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failed = true


func _run() -> void:
	var directory = Support.config_dir()
	var now = Support.unix_for_local_datetime(2026, 1, 2, 12)
	var store = EventStore.new()
	get_root().add_child(store)
	store.configure(directory)
	var memory = Memory.new()
	get_root().add_child(memory)
	memory.configure(directory, store)
	var profile = Profile.new()
	get_root().add_child(profile)
	profile.configure(directory, store, memory)
	for days_ago in [0, 1, 2, 3, 6, 7, 29, 30]:
		for index in range(40):
			store.record_event("pet_head", "user", {"mode": "活泼", "period": "entertainment"}, {}, [], {}, {}, now - days_ago * 86400 + index)
	_check(store.all_events().size() == 200, "Raw history must remain bounded")
	_check(store.aggregate(1, now)["total_events"] == 40, "Today must retain all events")
	_check(store.aggregate(3, now)["total_events"] == 120, "Three calendar days boundary failed")
	_check(store.aggregate(7, now)["total_events"] == 200, "Seven calendar days boundary failed")
	_check(store.aggregate(30, now)["total_events"] == 280, "Thirty calendar days boundary failed")
	_check(store.aggregate(0, now)["total_events"] == 320, "Lifetime lost evicted history")
	# Future days do not leak into the current calendar window.
	store.record_event("future", "system", {}, {}, [], {}, {}, now + 86400)
	_check(store.aggregate(7, now)["total_events"] == 200, "Future day counted in current window")
	var brain = Brain.new()
	brain._record_automatic_event({"type": "prompt"}, {"event_store": store, "memory_store": memory}, now)
	for index in range(205):
		store.record_event("auto_prompt", "system", {"mode": "安静", "period": "work"}, {}, [], {}, {}, now + index)
	_check(profile.snapshot()["lifetime"]["counts"].get("auto_prompt") == 206, "Automatic events were not ingested immediately")
	_check(memory.snapshot()["daily"]["counts"].get("pet_head") == 40, "Memory lost today's evicted interactions")
	_check(memory.snapshot()["relationship"]["familiarity"] == 100, "Eviction reduced relationship")
	profile.refresh(now)
	profile.refresh(now)
	_check(profile.snapshot()["lifetime"]["total_events"] == 527, "Refresh duplicated aggregates")
	store.configure(directory)
	profile.refresh(now)
	_check(store.aggregate(30, now)["total_events"] == 486, "Restart lost thirty-day history")
	_check(profile.snapshot()["lifetime"]["total_events"] == 527, "Restart duplicated lifetime counts")
	# A failed write must leave the durable primary intact; a later retry saves pending events.
	var original_path = store.event_path
	var before = FileAccess.get_file_as_string(original_path)
	var blocker = FileAccess.open(directory.path_join("blocker"), FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker.close()
	store.event_path = directory.path_join("blocker/events.json")
	store.record_event("pending", "system", {}, {}, [], {}, {}, now)
	_check(store.last_save_error != OK, "Write failure was not reported")
	_check(FileAccess.get_file_as_string(original_path) == before, "Write failure changed durable data")
	store.event_path = original_path
	_check(store.flush_save() == OK, "Pending events could not be retried")
	var backup = JSON.parse_string(FileAccess.get_file_as_string(original_path + ".bak"))
	var corrupt = FileAccess.open(original_path, FileAccess.WRITE)
	corrupt.store_string("{broken")
	corrupt.close()
	store.configure(directory)
	_check(store.aggregate(0)["total_events"] == 527 and store.all_events()[-1]["id"] == backup["events"][-1]["id"], "Invalid JSON did not recover the valid backup")
	var malformed = backup.duplicate(true)
	malformed["daily"][EventStore.date_for_unix(now)]["total_events"] = "broken"
	corrupt = FileAccess.open(original_path, FileAccess.WRITE)
	corrupt.store_string(JSON.stringify(malformed))
	corrupt.close()
	store.configure(directory)
	_check(store.aggregate(0)["total_events"] == 527 and store.all_events()[-1]["id"] == backup["events"][-1]["id"], "Invalid aggregate schema did not recover the valid backup")
	_check(store.flush_save() == OK, "Recovered data could not be saved")
	_check(JSON.parse_string(FileAccess.get_file_as_string(original_path + ".bak")) == backup, "Recovery overwrote the valid backup")
	var boundary_store = EventStore.new()
	get_root().add_child(boundary_store)
	boundary_store.configure(directory.path_join("calendar-boundaries"))
	var midnight = Support.unix_for_local_datetime(2026, 1, 2, 0)
	for at in [midnight, midnight - 1, midnight - 2 * 86400, midnight - 2 * 86400 - 1, midnight - 6 * 86400, midnight - 6 * 86400 - 1, midnight - 29 * 86400, midnight - 29 * 86400 - 1, midnight + 86400]:
		boundary_store.record_event("boundary", "system", {}, {}, [], {}, {}, at)
	_check(boundary_store.aggregate(1, midnight)["total_events"] == 1, "Today midnight boundary failed")
	_check(boundary_store.aggregate(3, midnight)["total_events"] == 3, "Three-day midnight boundary failed")
	_check(boundary_store.aggregate(7, midnight)["total_events"] == 5, "Seven-day midnight boundary failed")
	_check(boundary_store.aggregate(30, midnight)["total_events"] == 7, "Thirty-day midnight/year boundary failed")
	brain.free()
	print("Godot daily aggregate tests passed." if not failed else "Godot daily aggregate tests failed.")
	quit(1 if failed else 0)
