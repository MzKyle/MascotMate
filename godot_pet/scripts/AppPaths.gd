extends RefCounted


static func data_dir() -> String:
	var override_dir = OS.get_environment("CRAYON_PET_CONFIG_DIR").strip_edges()
	if override_dir != "":
		if override_dir.is_absolute_path():
			return override_dir.simplify_path()
		return OS.get_environment("PWD").path_join(override_dir).simplify_path() if OS.get_environment("PWD") != "" else ProjectSettings.globalize_path(override_dir)
	return ProjectSettings.globalize_path("user://").simplify_path()
