extends SceneTree

signal allow_completion

const CommandQueueScript = preload("res://scripts/CommandQueue.gd")
const AtomicJson = preload("res://scripts/AtomicJson.gd")
const TestSupport = preload("res://tests/TestSupport.gd")

var pending_root := ""
var handled := []
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data_dir := TestSupport.config_dir()
	if data_dir == "":
		quit(1)
		return
	pending_root = data_dir.path_join("commands-v1")
	for index in range(9, -1, -1):
		_fixture(index, "async" if index == 0 else "sync")
	var queue = _new_queue(data_dir)
	queue.poll()
	queue.poll()
	_check(handled == [0] and not FileAccess.file_exists(_record(0).path_join("result.json")),
		"An unfinished async command blocks later execution and has no success receipt")
	_check(not _running_file(0).is_empty() and FileAccess.file_exists(_record(1).path_join("pending")),
		"Running and pending markers are distinct")
	allow_completion.emit()
	_check(_receipt(0).get("status") == "succeeded", "Report success only after the signal awaited by the handler")
	for _index in range(9):
		queue.poll()
	_check(handled == range(10), "FIFO order comes from the command ID sequence")
	_check(_receipt(5).get("status") == "failed" and _receipt(5).get("error") == "test_failure", "Publish a definite failure")

	# Force a fresh scan of a duplicate and of an abandoned running command.
	queue.free()
	_touch(_record(0).path_join("pending"))
	_fixture(10, "sync", true)
	_fixture(11, "sync")
	var old_start := int(Time.get_unix_time_from_system() * 1000) - CommandQueueScript.RUN_MSEC - 1
	DirAccess.rename_absolute(_record(11).path_join("pending"), _record(11).path_join("running.%d" % old_start))
	_fixture(12, "sync")
	DirAccess.make_dir_absolute(_record(12).path_join("result.json.tmp"))
	queue = _new_queue(data_dir)
	queue.poll()
	queue.poll()
	_check(FileAccess.file_exists(_record(10).path_join("expired")) and _running_file(11).is_empty(),
		"Drop expired eligibility and recover an interrupted claim after restart")
	queue.poll()
	queue.poll()
	_check(handled == range(10) + [12] and _receipt(12).is_empty(), "A failed receipt write cannot reexecute the command")
	DirAccess.remove_absolute(_record(12).path_join("result.json.tmp"))
	queue.poll()
	_check(_receipt(12).get("status") == "succeeded" and handled == range(10) + [12], "Retry receipt publication only")
	if failures == 0:
		print("Godot command queue tests passed.")
	quit(0 if failures == 0 else 1)


func _new_queue(data_dir: String):
	var queue = CommandQueueScript.new()
	root.add_child(queue)
	queue.configure(data_dir, _execute)
	return queue


func _execute(request: Dictionary) -> Dictionary:
	var index := int(request["payload"]["index"])
	handled.append(index)
	if request["command"] == "async":
		await allow_completion
	return {"ok": index != 5, "error": "test_failure"}


func _fixture(index: int, command: String, elapsed := false) -> void:
	var path := _record(index)
	DirAccess.make_dir_recursive_absolute(path)
	var now := Time.get_unix_time_from_system()
	_check(AtomicJson.publish_dictionary(path.path_join("request.json"), {
		"id": path.get_file(), "command": command, "payload": {"index": index},
		"created_at": now - 10 if elapsed else now, "expires_at": now - 1 if elapsed else now + 120,
	}) == OK, "Create a command request fixture")
	_touch(path.path_join("pending"))


func _record(index: int) -> String:
	return pending_root.path_join("%012d-0123456789abcdef01234567" % (index + 1))


func _touch(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "Create marker " + path)
	if file != null:
		file.close()


func _running_file(index: int) -> String:
	for file in DirAccess.get_files_at(_record(index)):
		if file.begins_with("running."):
			return file
	return ""


func _receipt(index: int) -> Dictionary:
	return AtomicJson.read_file(_record(index).path_join("result.json")).get("data", {})


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
