extends Node

const AtomicJson = preload("res://scripts/AtomicJson.gd")
const POLL_SECONDS := 0.35
const RUN_MSEC := 20_000
const MAX_BYTES := 4096
const MAX_RETAINED := 512

var _directory := ""
var _handler: Callable
var _id_pattern := RegEx.new()
var _completed := {}
var _active := {}
var _result := {}
var _last_issue := ""


func configure(data_dir: String, handler: Callable) -> void:
	_directory = data_dir.path_join("commands-v1")
	_handler = handler
	_id_pattern.compile("^[0-9]{12}-[0-9a-f]{24}$")
	for old_name in ["companion_console_command.json", "skin_store_command.json"]:
		var path := data_dir.path_join(old_name)
		if FileAccess.file_exists(path):
			push_warning("Legacy desktop command preserved at %s; its execution cannot be confirmed" % path)
	var timer := Timer.new()
	timer.wait_time = POLL_SECONDS
	timer.timeout.connect(poll)
	add_child(timer)
	timer.start()


func poll() -> void:
	if not _active.is_empty():
		_poll_active()
		return
	if not DirAccess.dir_exists_absolute(_directory):
		return
	if _completed.size() > MAX_RETAINED:
		_completed.clear()
	var entries := DirAccess.get_directories_at(_directory)
	entries.sort()
	for id in entries:
		if _completed.has(id) or _id_pattern.search(id) == null:
			continue
		var directory := _directory.path_join(id)
		var markers := DirAccess.get_files_at(directory)
		var running := ""
		var terminal := "result.json" in markers or "expired" in markers
		for marker in markers:
			var fields := marker.split(".")
			if fields[0] == "interrupted" and fields.size() == 3 and fields[1].is_valid_int() and fields[2].is_valid_int():
				terminal = true
			elif fields[0] == "running" and fields.size() == 2 and fields[1].is_valid_int():
				running = marker
		if terminal:
			if "pending" in markers:
				push_warning("Ignoring duplicate desktop command %s" % id)
			_completed[id] = true
			continue
		if running != "":
			var started_msec := int(running.get_slice(".", 1))
			if _unix_msec() >= started_msec + RUN_MSEC:
				_interrupt(directory, running)
			return
		if "pending" in markers:
			_take_command(directory, id, entries.size())
			return


func _exit_tree() -> void:
	if not _result.is_empty():
		_flush_result()


func _take_command(directory: String, id: String, retained: int) -> void:
	var path := directory.path_join("request.json")
	var loaded := AtomicJson.read_file(path, Callable(), MAX_BYTES)
	var request: Dictionary = loaded.get("data", {})
	var valid: bool = loaded["error"] == OK and _valid_request(request, id)
	var started_msec := _unix_msec()
	var pending := directory.path_join("pending")
	if valid and started_msec / 1000.0 >= request["expires_at"]:
		if _move(pending, directory.path_join("expired")):
			print_verbose("Desktop command %s %s expired before starting" % [id, request["command"]])
		return
	var running := "running.%d" % started_msec
	if not _move(pending, directory.path_join(running)):
		return
	_active = {
		"id": id,
		"directory": directory,
		"marker": running,
		"started_msec": started_msec,
		"started_tick": Time.get_ticks_msec(),
		"command": request.get("command", "") if valid else "",
		"created_at": request.get("created_at", 0) if valid else 0,
		"expires_at": request.get("expires_at", 0) if valid else 0,
	}
	if not valid:
		push_warning("Invalid desktop command %s: %s" % [id, loaded.get("detail", "invalid request fields")])
		_finish("failed", "invalid_request")
	elif _unix_msec() / 1000.0 >= request["expires_at"]:
		_finish("expired", "not_started")
	else:
		print_verbose("Desktop command %s %s running at %.3f (%d retained)" % [id, request["command"], started_msec / 1000.0, retained])
		_execute(request)


func _execute(request: Dictionary) -> void:
	var outcome = await _handler.call(request)
	if _active.get("id") != request["id"]:
		return
	if typeof(outcome) != TYPE_DICTIONARY or typeof(outcome.get("ok")) != TYPE_BOOL:
		_finish("failed", "missing_result", true)
	elif outcome["ok"]:
		_finish("succeeded")
	else:
		_finish("failed", str(outcome.get("error", "execution_failed")))


func _poll_active() -> void:
	if not _result.is_empty():
		_flush_result()
		if _active.is_empty():
			return
	if Time.get_ticks_msec() - int(_active["started_tick"]) < RUN_MSEC:
		return
	var path: String = _active["directory"]
	var marker: String = _active["marker"]
	if not FileAccess.file_exists(path.path_join(marker)) or _interrupt(path, marker):
		_active.clear()
		_result.clear()


func _finish(status: String, error := "", outcome_unknown := false) -> void:
	_result = {
		"id": _active["id"],
		"command": _active["command"],
		"status": status,
		"created_at": _active["created_at"],
		"expires_at": _active["expires_at"],
		"started_at": _active["started_msec"] / 1000.0 if status != "expired" else null,
		"finished_at": Time.get_unix_time_from_system(),
		"error": error,
		"outcome_unknown": outcome_unknown,
	}
	_flush_result()


func _flush_result() -> void:
	var error := AtomicJson.publish_dictionary(_active["directory"].path_join("result.json"), _result, false, MAX_BYTES)
	if error not in [OK, ERR_ALREADY_EXISTS]:
		_warn_once("Could not record desktop command %s: %s" % [_active["id"], error_string(error)])
		return
	var elapsed := Time.get_ticks_msec() - int(_active["started_tick"])
	var message := "Desktop command %s %s %s in %d ms %s" % [_result["id"], _result["command"], _result["status"], elapsed, _result["error"]]
	if _result["status"] == "failed":
		push_warning(message)
	else:
		print_verbose(message)
	_completed[_result["id"]] = true
	_active.clear()
	_result.clear()
	_last_issue = ""


func _interrupt(directory: String, running: String) -> bool:
	var target := "interrupted.%s.%d" % [running.get_slice(".", 1), _unix_msec()]
	if not _move(directory.path_join(running), directory.path_join(target)):
		return false
	push_warning("Desktop command %s interrupted; execution outcome unknown" % directory.get_file())
	return true


func _move(from: String, to: String) -> bool:
	var error := DirAccess.rename_absolute(from, to)
	if error == OK:
		_last_issue = ""
		return true
	if FileAccess.file_exists(from):
		_warn_once("Could not move desktop command marker %s: %s" % [from, error_string(error)])
	return false


func _warn_once(message: String) -> void:
	if _last_issue != message:
		push_warning(message)
		_last_issue = message


func _valid_request(request: Dictionary, id: String) -> bool:
	return request.get("id") == id and typeof(request.get("command")) == TYPE_STRING \
		and typeof(request.get("payload")) == TYPE_DICTIONARY and typeof(request.get("created_at")) == TYPE_FLOAT \
		and typeof(request.get("expires_at")) == TYPE_FLOAT and is_finite(request["created_at"]) \
		and is_finite(request["expires_at"]) and request["expires_at"] >= request["created_at"]


func _unix_msec() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)
