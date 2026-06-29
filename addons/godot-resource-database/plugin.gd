@tool
extends EditorPlugin

var _panel: GRDEditorPanel = null
var _last_db_path: String = ""

const _METADATA_SECTION := "godot_resource_database"
const _LAST_DB_METADATA_KEY := "last_database_path"


func _enter_tree() -> void:
	_last_db_path = _load_last_db_path()
	_create_panel()


func _create_panel() -> void:
	GRDTheme.set_editor_metrics(
		EditorInterface.get_editor_scale(),
		EditorInterface.get_editor_theme().default_font_size,
	)
	_panel = GRDEditorPanel.new()
	_panel.set_undo_redo(get_undo_redo())
	_panel.name = "GRDEditorPanel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.refresh_plugin_requested.connect(_on_refresh_plugin_requested)
	_panel.visible = false
	var main_screen: Control = EditorInterface.get_editor_main_screen()
	main_screen.add_child(_panel)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	if not _last_db_path.is_empty():
		_panel.call_deferred("load_database", _last_db_path)


func _exit_tree() -> void:
	_destroy_panel()


func _destroy_panel() -> void:
	if _panel != null:
		_last_db_path = _panel.get_database_path()
		_save_last_db_path(_last_db_path)
		var parent: Node = _panel.get_parent()
		if parent != null:
			parent.remove_child(_panel)
		_panel.queue_free()
		_panel = null


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "Resource DB"


func _get_plugin_icon() -> Texture2D:
	return preload("res://addons/godot-resource-database/icon_tab.svg")


func _make_visible(visible: bool) -> void:
	if _panel != null:
		if visible:
			_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		_panel.visible = visible


func _on_refresh_plugin_requested(db_path: String) -> void:
	_last_db_path = db_path
	_save_last_db_path(_last_db_path)
	_destroy_panel()
	call_deferred("_create_panel")
	if EditorInterface.has_method("set_main_screen_editor"):
		EditorInterface.call_deferred("set_main_screen_editor", _get_plugin_name())


func _load_last_db_path() -> String:
	var settings := EditorInterface.get_editor_settings()
	if settings == null:
		return ""
	var value: Variant = settings.get_project_metadata(_METADATA_SECTION, _LAST_DB_METADATA_KEY, "")
	return value if value is String else ""


func _save_last_db_path(path: String) -> void:
	var settings := EditorInterface.get_editor_settings()
	if settings == null:
		return
	settings.set_project_metadata(_METADATA_SECTION, _LAST_DB_METADATA_KEY, path)
