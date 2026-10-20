extends RefCounted


static func read_dictionary(path: String, validator := Callable()) -> Dictionary:
	for candidate in [path, path + ".bak"]:
		var parsed = _read(candidate)
		if typeof(parsed) == TYPE_DICTIONARY and (not validator.is_valid() or validator.call(parsed)):
			return parsed
	return {}


static func write_dictionary(path: String, value: Dictionary, validator := Callable()) -> Error:
	if path == "":
		return ERR_INVALID_PARAMETER
	var result = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if result != OK:
		return result
	var temporary = path + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value, "\t"))
	file.flush()
	result = file.get_error()
	file.close()
	if result != OK:
		return result
	# Never replace the valid backup with a corrupt primary file.
	var previous = _read(path)
	if typeof(previous) == TYPE_DICTIONARY and (not validator.is_valid() or validator.call(previous)):
		result = DirAccess.copy_absolute(path, path + ".bak")
		if result != OK:
			return result
	return DirAccess.rename_absolute(temporary, path)


static func _read(path: String):
	if not FileAccess.file_exists(path):
		return null
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var json = JSON.new()
	return json.data if json.parse(file.get_as_text()) == OK else null
