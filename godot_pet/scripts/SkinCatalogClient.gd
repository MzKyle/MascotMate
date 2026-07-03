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
	var url = _catalog_url()
	if not _is_allowed_catalog_url(url):
		_load_fallback_catalog("在线皮肤源地址不可用。")
		return
	var err = catalog_request.request(url)
	if err != OK:
		_load_fallback_catalog("在线皮肤源请求失败。")


func load_fallback_catalog() -> Array:
	_load_fallback_catalog("")
	return entries.duplicate(true)


func request_preview(entry: Dictionary) -> void:
	var skin_id = str(entry.get("id", ""))
	var preview_ref = str(entry.get("preview", ""))
	if skin_id == "" or preview_ref == "":
		return
	var target = _resolve_ref(preview_ref)
	if catalog_is_local:
		if FileAccess.file_exists(target):
			emit_signal("preview_ready", skin_id, target)
		return
	var cache_path = cache_root.path_join("previews").path_join("%s_%s" % [_safe_file_part(skin_id), preview_ref.get_file()])
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
		_load_fallback_catalog("在线皮肤源暂不可用。")
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_load_fallback_catalog("在线皮肤源格式错误。")
		return
	_apply_catalog(parsed, _catalog_url(), false, false)


func _load_fallback_catalog(reason: String) -> void:
	for path in _fallback_catalog_candidates():
		if not FileAccess.file_exists(path):
			continue
		var file = FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed = JSON.parse_string(file.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			_apply_catalog(parsed, path, true, reason != "")
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


func _apply_catalog(catalog: Dictionary, base: String, local: bool, offline: bool) -> void:
	var raw_entries = catalog.get("skins", [])
	entries = []
	if typeof(raw_entries) == TYPE_ARRAY:
		for item in raw_entries:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			if str(item.get("id", "")) == "":
				continue
			entries.append(item.duplicate(true))
	catalog_base = base
	catalog_is_local = local
	var source_label = "本地精选源" if local else "在线精选源"
	emit_signal("catalog_loaded", entries.duplicate(true), source_label, offline)


func _resolve_ref(ref: String) -> String:
	if ref.begins_with("https://") or ref.begins_with("http://"):
		return ref
	var base_dir = catalog_base.get_base_dir()
	if catalog_is_local:
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
