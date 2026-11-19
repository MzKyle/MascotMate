extends RefCounted


static func read_dictionary(path: String, validator := Callable()) -> Dictionary:
	return load_dictionary(path, validator).get("data", {})


static func load_dictionary(path: String, validator := Callable()) -> Dictionary:
	var primary := read_file(path, validator)
	primary["primary_error"] = primary["error"]
	if primary["error"] == OK:
		return primary

	var failure := primary
	var candidates := [path + ".bak"]
	if OS.get_name() == "Windows":
		candidates = [path + ".swap", path + ".bak", path + ".bak.swap"]
	for candidate in candidates:
		var backup := read_file(candidate, validator)
		if backup["error"] == OK:
			push_warning("Using %s for %s (%s)" % [candidate, path, primary["detail"]])
			backup["primary_error"] = primary["error"]
			return backup
		if not can_replace(backup["error"]) or failure["error"] == ERR_FILE_NOT_FOUND:
			failure = backup
		if backup["error"] != ERR_FILE_NOT_FOUND:
			push_warning("Cannot load %s (%s)" % [candidate, backup["detail"]])
	if failure["error"] != ERR_FILE_NOT_FOUND:
		push_warning("Cannot load %s (%s)" % [path, primary["detail"]])
	failure["primary_error"] = primary["error"]
	return failure


static func read_file(path: String, validator := Callable()) -> Dictionary:
	if DirAccess.dir_exists_absolute(path):
		return _read_error(ERR_FILE_CANT_READ, "expected a file, found a directory")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var error := FileAccess.get_open_error()
		return _read_error(error, error_string(error))
	var length := file.get_length()
	var bytes := file.get_buffer(length)
	var error := file.get_error()
	file.close()
	if bytes.size() != length or error not in [OK, ERR_FILE_EOF]:
		return _read_error(ERR_FILE_CANT_READ, "incomplete read (%s)" % error_string(error))
	var json := JSON.new()
	var utf8 := bytes.slice(3) if bytes.size() >= 3 and bytes[0] == 0xef and bytes[1] == 0xbb and bytes[2] == 0xbf else bytes
	var content := utf8.get_string_from_utf8()
	if content.to_utf8_buffer() != utf8:
		return _read_error(ERR_PARSE_ERROR, "invalid UTF-8")
	if json.parse(content) != OK:
		return _read_error(ERR_PARSE_ERROR, "line %d: %s" % [json.get_error_line() + 1, json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY or (validator.is_valid() and not validator.call(json.data)):
		return _read_error(ERR_INVALID_DATA, "invalid JSON structure")
	return {"error": OK, "data": json.data, "bytes": bytes}


static func can_replace(error: Error) -> bool:
	return error in [OK, ERR_FILE_NOT_FOUND, ERR_PARSE_ERROR, ERR_INVALID_DATA]


static func is_number(value: Variant, whole := false) -> bool:
	if typeof(value) == TYPE_STRING:
		if not value.is_valid_float():
			return false
	elif typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return is_finite(number) and (not whole or number == floor(number))


static func write_dictionary(path: String, value: Dictionary, validator := Callable(), archive_invalid := false) -> Error:
	if path == "":
		return ERR_INVALID_PARAMETER
	if validator.is_valid() and not validator.call(value):
		return ERR_INVALID_DATA
	var result := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if result != OK:
		return result
	var primary := read_file(path, validator)
	if not can_replace(primary["error"]):
		return primary["error"]
	var temporary := path + ".tmp"
	result = _stage(temporary, JSON.stringify(value, "\t").to_utf8_buffer())
	if result == OK and primary["error"] == OK:
		# Refresh the backup only from a primary that passed the same validation.
		result = _save_backup(path + ".bak", primary["bytes"], validator, archive_invalid)
	if result == OK:
		result = _publish(temporary, path, primary["error"], archive_invalid)
	_remove_temporary(temporary)
	return result


static func _read_error(error: Error, detail: String) -> Dictionary:
	return {"error": error, "detail": detail}


static func _stage(path: String, bytes: PackedByteArray) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var written := file.store_buffer(bytes)
	file.flush()
	var result := file.get_error()
	file.close()
	if result != OK:
		return result
	# The Windows and Linux drivers do not surface fflush()'s return value.
	# Check the actual staged bytes after closing before publishing the file.
	return OK if written and FileAccess.get_file_as_bytes(path) == bytes else ERR_FILE_CANT_WRITE


static func _save_backup(path: String, bytes: PackedByteArray, validator: Callable, archive_invalid: bool) -> Error:
	var previous := read_file(path, validator)
	if not can_replace(previous["error"]):
		return previous["error"]
	var temporary := path + ".tmp"
	var result := _stage(temporary, bytes)
	if result == OK:
		result = _publish(temporary, path, previous["error"], archive_invalid)
	_remove_temporary(temporary)
	return result


static func _publish(temporary: String, path: String, previous_error: Error, archive_invalid: bool) -> Error:
	var archive := archive_invalid and previous_error in [ERR_PARSE_ERROR, ERR_INVALID_DATA]
	var displaced := ""
	if archive:
		displaced = "%s.corrupt-%d-%d-%d" % [path, int(Time.get_unix_time_from_system()), OS.get_process_id(), Time.get_ticks_usec()]
	elif OS.get_name() == "Windows" and previous_error != ERR_FILE_NOT_FOUND:
		# Godot's Windows rename deletes the target before calling MoveFileW.
		# Move it aside first so a failed or interrupted publication is recoverable.
		displaced = path + ".swap"
	if displaced != "":
		var moved := DirAccess.rename_absolute(path, displaced)
		if moved != OK:
			return moved
	var result := DirAccess.rename_absolute(temporary, path)
	if result != OK:
		if displaced != "" and DirAccess.rename_absolute(displaced, path) != OK:
			push_error("Could not restore %s after a failed write. Previous file: %s" % [path, displaced])
		return result
	if archive:
		push_warning("Preserved damaged JSON at %s" % displaced)
	if OS.get_name() == "Windows":
		_remove_temporary(path + ".swap")
	return OK


static func _remove_temporary(path: String) -> void:
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
		push_warning("Could not remove temporary JSON file %s" % path)
