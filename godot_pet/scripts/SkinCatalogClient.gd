extends Node

signal catalog_loaded(entries, source_label, offline)
signal catalog_failed(message)
signal preview_ready(skin_id, path)
signal download_progress(skin_id, downloaded_bytes, total_bytes)
signal skin_downloaded(skin_id, path)
signal skin_download_failed(skin_id, message)

const DEFAULT_CATALOG_URL := "https://raw.githubusercontent.com/MzKyle/Crayon-Shinchan-Desktop-Pat/main/skin_catalog/catalog.json"
const MAX_PACKAGE_BYTES := 100 * 1024 * 1024

var repo_root := ""
var config_dir := ""
var cache_root := ""
var catalog_request: HTTPRequest
var download_request: HTTPRequest
var progress_timer: Timer
var entries := []
var curated_entries := []
var external_entries := []
var catalog_base := ""
var catalog_is_local := false
var active_download_id := ""
var active_download_entry := {}
var active_download_path := ""


func configure(root: String, user_config_dir: String) -> void:
	repo_root = root
	config_dir = user_config_dir
	cache_root = config_dir.path_join("catalog_cache")
	DirAccess.make_dir_recursive_absolute(cache_root.path_join("previews"))
	DirAccess.make_dir_recursive_absolute(cache_root.path_join("downloads"))
	if catalog_request == null:
		catalog_request = HTTPRequest.new()
		catalog_request.request_completed.connect(_on_catalog_request_completed)
		add_child(catalog_request)
	if download_request == null:
		download_request = HTTPRequest.new()
		download_request.request_completed.connect(_on_download_request_completed)
		add_child(download_request)
	if progress_timer == null:
		progress_timer = Timer.new()
		progress_timer.wait_time = 0.2
		progress_timer.timeout.connect(_emit_download_progress)
		add_child(progress_timer)


func load_catalog() -> void:
	curated_entries = []
	external_entries = []
	_load_external_index_fallback()
	_emit_combined_catalog("皮肤商店", true)
	var url = _catalog_url()
	if not _is_allowed_catalog_url(url):
		_load_fallback_catalog("在线皮肤源地址不可用。", true)
		call_deferred("_refresh_external_from_helper")
		return
	var err = catalog_request.request(url)
	if err != OK:
		_load_fallback_catalog("在线皮肤源请求失败。", true)
	call_deferred("_refresh_external_from_helper")


func load_fallback_catalog() -> Array:
	curated_entries = []
	external_entries = []
	_load_external_index_fallback()
	_load_fallback_catalog("", false)
	_emit_combined_catalog("本地皮肤商店", true)
	return entries.duplicate(true)


func request_preview(entry: Dictionary) -> void:
	var skin_id = str(entry.get("id", ""))
	var preview_ref = str(entry.get("preview", ""))
	var preview_url = str(entry.get("preview_url", ""))
	if skin_id == "" or preview_ref == "":
		if preview_url == "":
			return
	var target = preview_url if preview_url != "" else _resolve_ref(preview_ref)
	var is_remote = target.begins_with("https://") or target.begins_with("http://")
	if not is_remote and catalog_is_local:
		if FileAccess.file_exists(target):
			emit_signal("preview_ready", skin_id, target)
		return
	if not is_remote and FileAccess.file_exists(target):
		emit_signal("preview_ready", skin_id, target)
		return
	var preview_file = preview_ref.get_file() if preview_ref != "" else target.get_file()
	var cache_path = cache_root.path_join("previews").path_join("%s_%s" % [_safe_file_part(skin_id), preview_file])
	if FileAccess.file_exists(cache_path):
		emit_signal("preview_ready", skin_id, cache_path)
		return
	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(func(result, response_code, _headers, body):
		if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
			var file = FileAccess.open(cache_path, FileAccess.WRITE)
			if file != null:
				file.store_buffer(body)
				emit_signal("preview_ready", skin_id, cache_path)
		request.queue_free()
	)
	request.request(target)


func download_skin(entry: Dictionary) -> void:
	if str(entry.get("source_type", "curated_package")) == "external_browser":
		emit_signal("skin_download_failed", str(entry.get("id", "")), "第三方皮肤需要打开原站下载后导入。")
		return
	if active_download_id != "":
		emit_signal("skin_download_failed", str(entry.get("id", "")), "已有皮肤正在下载。")
		return
	var skin_id = str(entry.get("id", ""))
	var package_ref = str(entry.get("package", ""))
	if skin_id == "" or package_ref == "":
		emit_signal("skin_download_failed", skin_id, "皮肤包信息不完整。")
		return
	var target = _resolve_ref(package_ref)
	if catalog_is_local:
		var message = _validate_download(entry, target)
		if message == "":
			emit_signal("skin_downloaded", skin_id, target)
		else:
			emit_signal("skin_download_failed", skin_id, message)
		return

	active_download_id = skin_id
	active_download_entry = entry.duplicate(true)
	active_download_path = cache_root.path_join("downloads").path_join("%s_%s" % [_safe_file_part(skin_id), package_ref.get_file()])
	if FileAccess.file_exists(active_download_path):
		DirAccess.remove_absolute(active_download_path)
	download_request.download_file = active_download_path
	var err = download_request.request(target)
	if err != OK:
		_clear_active_download()
		emit_signal("skin_download_failed", skin_id, "下载请求启动失败。")
		return
	progress_timer.start()


func _catalog_url() -> String:
	var override_url = OS.get_environment("MASCOTMATE_SKIN_CATALOG_URL").strip_edges()
	if override_url == "":
		override_url = OS.get_environment("CRAYON_PET_SKIN_CATALOG_URL").strip_edges()
	return override_url if override_url != "" else DEFAULT_CATALOG_URL


func _is_allowed_catalog_url(url: String) -> bool:
	if url.begins_with("https://"):
		return true
	if url.begins_with("http://127.0.0.1") or url.begins_with("http://localhost"):
		return true
	return false


func _on_catalog_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_load_fallback_catalog("在线皮肤源暂不可用。", true)
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_load_fallback_catalog("在线皮肤源格式错误。", true)
		return
	_apply_curated_catalog(parsed, _catalog_url(), false)
	_emit_combined_catalog("皮肤商店", false)


func _load_fallback_catalog(reason: String, emit_now: bool) -> void:
	for path in _fallback_catalog_candidates():
		if not FileAccess.file_exists(path):
			continue
		var file = FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed = JSON.parse_string(file.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			_apply_curated_catalog(parsed, path, true)
			if emit_now:
				_emit_combined_catalog("皮肤商店", reason != "")
			return
	if reason != "":
		emit_signal("catalog_failed", reason)
	else:
		emit_signal("catalog_failed", "没有可用的皮肤精选源。")


func _fallback_catalog_candidates() -> Array:
	return [
		repo_root.path_join("skin_catalog").path_join("catalog.json"),
		OS.get_executable_path().get_base_dir().path_join("skin_catalog").path_join("catalog.json"),
		OS.get_executable_path().get_base_dir().path_join("..").path_join("skin_catalog").path_join("catalog.json").simplify_path(),
	]


func _apply_curated_catalog(catalog: Dictionary, base: String, local: bool) -> void:
	var raw_entries = catalog.get("skins", [])
	curated_entries = []
	if typeof(raw_entries) == TYPE_ARRAY:
		for item in raw_entries:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			if str(item.get("id", "")) == "":
				continue
			var entry = item.duplicate(true)
			entry["source_type"] = str(entry.get("source_type", "curated_package"))
			entry["_catalog_base"] = base
			entry["_catalog_is_local"] = local
			curated_entries.append(entry)
	catalog_base = base
	catalog_is_local = local


func _load_external_index_fallback() -> void:
	for path in _external_index_candidates():
		if not FileAccess.file_exists(path):
			continue
		var file = FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed = JSON.parse_string(file.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY and _apply_external_index(parsed):
			return


func _external_index_candidates() -> Array:
	return [
		cache_root.path_join("cachomon").path_join("index.json"),
		repo_root.path_join("skin_catalog").path_join("cachomon_index.json"),
		OS.get_executable_path().get_base_dir().path_join("skin_catalog").path_join("cachomon_index.json"),
		OS.get_executable_path().get_base_dir().path_join("..").path_join("skin_catalog").path_join("cachomon_index.json").simplify_path(),
	]


func _apply_external_index(index: Dictionary) -> bool:
	var raw_entries = index.get("entries", [])
	if typeof(raw_entries) != TYPE_ARRAY:
		return false
	var parsed_entries := []
	for item in raw_entries:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		if str(item.get("id", "")) == "":
			continue
		var entry = item.duplicate(true)
		entry["source_type"] = "external_browser"
		entry["source"] = str(entry.get("source", "cachomon"))
		parsed_entries.append(entry)
	if parsed_entries.is_empty():
		return false
	external_entries = parsed_entries
	return true


func _emit_combined_catalog(source_label: String, offline: bool) -> void:
	entries = []
	entries.append_array(external_entries)
	entries.append_array(curated_entries)
	emit_signal("catalog_loaded", entries.duplicate(true), source_label, offline)


func _refresh_external_from_helper() -> void:
	var output := []
	var code = _execute_helper([
		"fetch-cachomon-index",
		"--safe",
		"--json",
		"--cache-root",
		cache_root.path_join("cachomon"),
		"--timeout",
		"10",
	], output)
	if code != 0:
		return
	var parsed = JSON.parse_string("\n".join(output))
	if typeof(parsed) == TYPE_DICTIONARY and _apply_external_index(parsed):
		_emit_combined_catalog("皮肤商店", false)


func _resolve_ref(ref: String) -> String:
	if ref.begins_with("https://") or ref.begins_with("http://"):
		return ref
	var base = catalog_base
	var local = catalog_is_local
	var base_dir = base.get_base_dir()
	if local:
		return base_dir.path_join(ref).simplify_path()
	return "%s/%s" % [base_dir.trim_suffix("/"), ref.trim_prefix("/")]


func _on_download_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var skin_id = active_download_id
	var entry = active_download_entry.duplicate(true)
	var path = active_download_path
	progress_timer.stop()
	_clear_active_download()
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		emit_signal("skin_download_failed", skin_id, "皮肤包下载失败。")
		return
	var message = _validate_download(entry, path)
	if message != "":
		emit_signal("skin_download_failed", skin_id, message)
		return
	emit_signal("skin_downloaded", skin_id, path)


func _emit_download_progress() -> void:
	if active_download_id == "":
		return
	emit_signal(
		"download_progress",
		active_download_id,
		download_request.get_downloaded_bytes(),
		download_request.get_body_size()
	)


func _clear_active_download() -> void:
	active_download_id = ""
	active_download_entry = {}
	active_download_path = ""


func _validate_download(entry: Dictionary, path: String) -> String:
	if not FileAccess.file_exists(path):
		return "皮肤包文件不存在。"
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "皮肤包无法读取。"
	var size = file.get_length()
	if size <= 0 or size > MAX_PACKAGE_BYTES:
		return "皮肤包大小不合法。"
	var expected_size = int(entry.get("size_bytes", 0))
	if expected_size > 0 and expected_size != size:
		return "皮肤包大小校验失败。"
	var expected_hash = str(entry.get("sha256", "")).to_lower()
	if expected_hash == "":
		return "皮肤包缺少 SHA-256 校验。"
	if _sha256_file(path) != expected_hash:
		return "皮肤包 SHA-256 校验失败。"
	return ""


func _sha256_file(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		var remaining = int(file.get_length() - file.get_position())
		context.update(file.get_buffer(mini(65536, remaining)))
	return context.finish().hex_encode()


func _safe_file_part(value: String) -> String:
	var result := ""
	for index in range(value.length()):
		var c = value.substr(index, 1)
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c in ["-", "_"]:
			result += c
		else:
			result += "_"
	return result


func _execute_helper(args: Array, output: Array) -> int:
	var helper = _helper_path()
	if helper != "":
		return OS.execute(helper, args, output, true, true)
	var helper_script = _helper_script_path()
	if helper_script == "":
		output.append("pet_helper.py not found")
		return 2
	var python = _find_python()
	if python == "":
		output.append("Python not found")
		return 2
	return OS.execute(python, [helper_script] + args, output, true, true)


func _helper_path() -> String:
	var helper_name = "pet_helper.exe" if OS.get_name() == "Windows" else "pet_helper"
	var candidates = [
		repo_root.path_join("scripts").path_join(helper_name),
		OS.get_executable_path().get_base_dir().path_join("scripts").path_join(helper_name),
	]
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""


func _helper_script_path() -> String:
	var candidates = [
		repo_root.path_join("scripts").path_join("pet_helper.py"),
		OS.get_executable_path().get_base_dir().path_join("scripts").path_join("pet_helper.py"),
		OS.get_executable_path().get_base_dir().path_join("..").path_join("scripts").path_join("pet_helper.py").simplify_path(),
	]
	for path in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""


func _find_python() -> String:
	for candidate in ["python3", "python"]:
		var output := []
		var code = OS.execute(candidate, ["--version"], output, true, true)
		if code == 0:
			return candidate
	return ""
