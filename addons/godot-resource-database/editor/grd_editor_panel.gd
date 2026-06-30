@tool
class_name GRDEditorPanel
extends VBoxContainer

## Resource-first editor panel for Godot Resource Database.
## Provides: toolbar (DB path, table dropdown, search, add/remove row,
## validate, save), spreadsheet grid view, validation panel, dirty tracking.
## Columns are derived from row_script exported properties via GRDPropertyColumn.

signal status_message(text: String, is_error: bool)
signal refresh_plugin_requested(db_path: String)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _db_asset_path: String = ""
var _db_asset: GRDDatabaseAsset = null
var _db: GRDDatabase = null

var _selected_table_asset: GRDTableAsset = null
var _selected_table: GRDTable = null
var _selected_row_index: int = -1  # real row index
var _selected_row: GRDRow = null
var _undo_redo: EditorUndoRedoManager = null

# Dirty tracking
var _dirty_database: bool = false
var _dirty_rows: Dictionary = {}  # resource_path -> Resource (dirty dir rows)

# Column width hints for type-based sizing
const _COL_WIDTH_BOOL: int = 60
const _COL_WIDTH_NUMBER: int = 88
const _COL_WIDTH_DEFAULT: int = 260
const _COL_WIDTH_RESOURCE: int = 280
const _COL_WIDTH_STRING: int = 150
const _COL_WIDTH_ARRAY: int = 200

# ---------------------------------------------------------------------------
# UI references (built in _ready)
# ---------------------------------------------------------------------------

var _path_edit: LineEdit
var _load_btn: Button
var _save_btn: Button
var _add_row_btn: Button
var _dirty_label: Label
var _status_label: RichTextLabel
var _table_dropdown: OptionButton
var _search_edit: LineEdit
var _row_script_label: Label
var _actions_menu: MenuButton

var _spreadsheet: GRDSpreadsheetView
var _validation_panel: GRDValidationPanel

# Resource-first mode state
var _resource_first_mode: bool = false
var _property_columns: Array[GRDPropertyColumn] = []

var _browse_dialog: EditorFileDialog = null
var _table_dialog: AcceptDialog = null
var _table_name_edit: LineEdit = null
var _table_script_picker: OptionButton = null
var _editing_table_asset: GRDTableAsset = null
var _delete_table_dialog: ConfirmationDialog = null
var _delete_table_label: Label = null

const _MENU_BROWSE: int = 1
const _MENU_REFRESH: int = 2
const _MENU_ADD_TABLE: int = 3
const _MENU_EDIT_TABLE: int = 4
const _MENU_DELETE_TABLE: int = 5
const _MENU_GENERATE_CONSTANTS: int = 6
const _MENU_GENERATE_CSHARP_CONSTANTS: int = 7
const _MENU_VALIDATE: int = 8

const _CSHARP_KEYWORDS := {
	"abstract": true, "as": true, "base": true, "bool": true, "break": true,
	"byte": true, "case": true, "catch": true, "char": true, "checked": true,
	"class": true, "const": true, "continue": true, "decimal": true, "default": true,
	"delegate": true, "do": true, "double": true, "else": true, "enum": true,
	"event": true, "explicit": true, "extern": true, "false": true, "finally": true,
	"fixed": true, "float": true, "for": true, "foreach": true, "goto": true,
	"if": true, "implicit": true, "in": true, "int": true, "interface": true,
	"internal": true, "is": true, "lock": true, "long": true, "namespace": true,
	"new": true, "null": true, "object": true, "operator": true, "out": true,
	"override": true, "params": true, "private": true, "protected": true, "public": true,
	"readonly": true, "ref": true, "return": true, "sbyte": true, "sealed": true,
	"short": true, "sizeof": true, "stackalloc": true, "static": true, "string": true,
	"struct": true, "switch": true, "this": true, "throw": true, "true": true,
	"try": true, "typeof": true, "uint": true, "ulong": true, "unchecked": true,
	"unsafe": true, "ushort": true, "using": true, "virtual": true, "void": true,
	"volatile": true, "while": true
}


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_ui()
	_apply_compact_theme(self)
	_update_button_states()


func _build_ui() -> void:
	# ── Toolbar ──────────────────────────────────────────────────────
	var toolbar: HBoxContainer = HBoxContainer.new()
	toolbar.name = "Toolbar"
	add_child(toolbar)

	var db_label: Label = Label.new()
	db_label.text = "DB:"
	toolbar.add_child(db_label)

	_path_edit = LineEdit.new()
	_path_edit.placeholder_text = "res://path/to/database.tres"
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_edit.size_flags_stretch_ratio = 1.2
	_path_edit.text_submitted.connect(_on_path_submitted)
	toolbar.add_child(_path_edit)

	_load_btn = Button.new()
	_load_btn.text = "Load"
	_load_btn.pressed.connect(_on_load_pressed)
	toolbar.add_child(_load_btn)

	toolbar.add_child(_vsep())

	var tbl_label: Label = Label.new()
	tbl_label.text = "Table:"
	toolbar.add_child(tbl_label)

	_table_dropdown = OptionButton.new()
	_table_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table_dropdown.size_flags_stretch_ratio = 0.8
	_table_dropdown.custom_minimum_size.x = GRDTheme.scaled(140.0)
	_table_dropdown.item_selected.connect(_on_table_dropdown_selected)
	toolbar.add_child(_table_dropdown)

	# Row Script summary. Script changes live in the table dialog so they are deliberate.
	_row_script_label = Label.new()
	_row_script_label.text = "Script: (none)"
	_row_script_label.visible = false

	var search_label: Label = Label.new()
	search_label.text = "Search:"
	toolbar.add_child(search_label)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Filter rows..."
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.size_flags_stretch_ratio = 1.0
	_search_edit.text_changed.connect(_on_search_changed)
	toolbar.add_child(_search_edit)

	toolbar.add_child(_vsep())

	_add_row_btn = Button.new()
	_add_row_btn.text = "+Row"
	_add_row_btn.pressed.connect(_on_add_row_pressed)
	toolbar.add_child(_add_row_btn)

	_save_btn = Button.new()
	_save_btn.text = "Save"
	_save_btn.pressed.connect(_on_save_pressed)
	toolbar.add_child(_save_btn)

	_actions_menu = MenuButton.new()
	_actions_menu.text = "More"
	_actions_menu.tooltip_text = "Less common database actions"
	var popup := _actions_menu.get_popup()
	popup.add_item("Browse...", _MENU_BROWSE)
	popup.add_item("Refresh plugin", _MENU_REFRESH)
	popup.add_separator()
	popup.add_item("Add table", _MENU_ADD_TABLE)
	popup.add_item("Edit table", _MENU_EDIT_TABLE)
	popup.add_item("Delete table", _MENU_DELETE_TABLE)
	popup.add_separator()
	popup.add_item("Generate GDScript constants", _MENU_GENERATE_CONSTANTS)
	popup.add_item("Generate C# constants", _MENU_GENERATE_CSHARP_CONSTANTS)
	popup.add_item("Validate", _MENU_VALIDATE)
	popup.id_pressed.connect(_on_actions_menu_id_pressed)
	GRDTheme.style_popup_menu(popup)
	toolbar.add_child(_actions_menu)

	_dirty_label = Label.new()
	_dirty_label.text = ""
	GRDTheme.style_label(_dirty_label, GRDTheme.FONT_SIZE, GRDTheme.WARNING)
	toolbar.add_child(_dirty_label)

	# ── Status ───────────────────────────────────────────────────────
	_status_label = RichTextLabel.new()
	_status_label.name = "StatusLabel"
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.scroll_active = false
	_status_label.custom_minimum_size.y = GRDTheme.control_height()
	add_child(_status_label)

	# ── Spreadsheet view (fills remaining space) ─────────────────────
	_spreadsheet = GRDSpreadsheetView.new()
	_spreadsheet.name = "SpreadsheetView"
	_spreadsheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spreadsheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spreadsheet.cell_changed.connect(_on_cell_changed)
	_spreadsheet.row_selected.connect(_on_spreadsheet_row_selected)
	_spreadsheet.row_delete_requested.connect(_on_spreadsheet_row_delete_requested)
	_spreadsheet.row_move_requested.connect(_on_spreadsheet_row_move_requested)
	add_child(_spreadsheet)

	# ── Validation panel (collapsible, at bottom) ────────────────────
	_validation_panel = GRDValidationPanel.new()
	_validation_panel.name = "ValidationPanel"
	_validation_panel.custom_minimum_size.y = GRDTheme.scaled(24.0)
	add_child(_validation_panel)


static func _vsep() -> VSeparator:
	var sep := VSeparator.new()
	sep.custom_minimum_size.x = GRDTheme.scaled(3.0)
	return sep


static func _apply_compact_theme(root: Node) -> void:
	GRDTheme.apply_tree(root)


func get_database_path() -> String:
	return _db_asset_path


func set_undo_redo(undo_redo: EditorUndoRedoManager) -> void:
	_undo_redo = undo_redo


# ---------------------------------------------------------------------------
# Database loading
# ---------------------------------------------------------------------------

func load_database(path: String) -> void:
	if path.is_empty():
		_set_status("No path provided.", true)
		return

	if _dirty_database or _dirty_rows.size() > 0:
		push_warning("GRD: Loading new database — discarding unsaved changes.")
		_set_status("Loading — discarding unsaved changes.", true)

	_db_asset_path = path
	_path_edit.text = path
	GRDResourceCellEditorFactory.clear_caches()

	_db_asset = load(path) as GRDDatabaseAsset
	if _db_asset == null:
		_set_status("Failed to load GRDDatabaseAsset from: " + path, true)
		_db = null
		_db_asset = null
		_refresh_ui()
		return

	_db = GRDDatabase.load_from_asset(_db_asset, null, path)
	_dirty_database = false
	_selected_table_asset = null
	_selected_table = null
	_selected_row_index = -1
	_selected_row = null
	_dirty_rows.clear()
	if _normalize_project_file_paths_to_uids():
		_dirty_database = true

	var issue_count := _db.get_issues().size()
	var status_text: String = "Loaded %s — %d table(s), %d issue(s)." % [
		path.get_file(), _db.table_count(), issue_count
	]
	if _dirty_database:
		status_text += " Converted file paths to UIDs; save to persist."
	_set_status(
		status_text,
		issue_count > 0,
	)
	_refresh_ui()


func _rebuild_database() -> void:
	if _db_asset == null:
		return
	GRDResourceCellEditorFactory.clear_caches()
	_db = GRDDatabase.load_from_asset(_db_asset, null, _db_asset_path)
	if _selected_table_asset != null and _db != null:
		var tname: StringName = _selected_table_asset.table_name
		if _db.has_table(tname):
			_selected_table = _db.get_table(tname)
		else:
			_selected_table = null
			_selected_table_asset = null
			_selected_row_index = -1
			_selected_row = null


func _normalize_project_file_paths_to_uids() -> bool:
	if _db_asset == null:
		return false
	var changed: bool = false
	var seen: Dictionary = {}
	for table: GRDTableAsset in _db_asset.tables:
		if table == null:
			continue
		for row: Resource in table.rows:
			var row_changed: bool = _normalize_resource_file_paths_to_uids(row, seen)
			if row_changed and row != null and not row.resource_path.is_empty() and not row.resource_path.contains("::"):
				_dirty_rows[row.resource_path] = row
			changed = row_changed or changed
	if changed and _db_asset != null:
		_db_asset.emit_changed()
	return changed


func _normalize_resource_file_paths_to_uids(resource: Resource, seen: Dictionary) -> bool:
	if resource == null:
		return false
	var instance_id: int = resource.get_instance_id()
	if seen.has(instance_id):
		return false
	seen[instance_id] = true

	var changed: bool = false
	for property: Dictionary in resource.get_property_list():
		var usage: int = int(property.get("usage", 0))
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var prop_name: String = String(property.get("name", ""))
		if prop_name.is_empty() or prop_name == "script":
			continue
		var prop_type: int = int(property.get("type", TYPE_NIL))
		var prop_hint: int = int(property.get("hint", PROPERTY_HINT_NONE))
		var current_value: Variant = resource.get(prop_name)

		if prop_type == TYPE_STRING and prop_hint == PROPERTY_HINT_FILE:
			var current_path: String = String(current_value)
			var uid_path: String = GRDResourceCellEditorFactory.project_file_path_storage_value(current_path)
			if uid_path != current_path:
				resource.set(prop_name, uid_path)
				changed = true
		elif current_value is Resource:
			var child_resource: Resource = current_value as Resource
			if child_resource.resource_path.is_empty() or child_resource.resource_path.contains("::"):
				changed = _normalize_resource_file_paths_to_uids(child_resource, seen) or changed
		elif current_value is Array:
			for item in current_value:
				if item is Resource:
					var item_resource: Resource = item as Resource
					if item_resource.resource_path.is_empty() or item_resource.resource_path.contains("::"):
						changed = _normalize_resource_file_paths_to_uids(item_resource, seen) or changed
	if changed:
		resource.emit_changed()
	return changed


# ---------------------------------------------------------------------------
# UI refresh
# ---------------------------------------------------------------------------

func _refresh_ui() -> void:
	_refresh_table_dropdown()
	_refresh_spreadsheet()
	_update_button_states()
	_update_dirty_label()
	_validation_panel.clear()


func _refresh_table_dropdown() -> void:
	_table_dropdown.clear()
	if _db == null:
		return
	for table_name in _db.table_names():
		var table: GRDTable = _db.get_table(StringName(table_name))
		var count := table.size() if table != null else 0
		var ta: GRDTableAsset = _find_table_asset_by_name(StringName(table_name))
		var mode_str: String = ""
		if ta != null and ta.row_script != null:
			mode_str = " [R]"
		var idx: int = _table_dropdown.get_item_count()
		_table_dropdown.add_item("%s%s (%d)" % [table_name, mode_str, count])
		_table_dropdown.set_item_metadata(idx, table_name)

	# Auto-select first table if available and none is selected.
	if _table_dropdown.get_item_count() > 0 and _selected_table_asset == null:
		_table_dropdown.selected = 0
		_on_table_dropdown_selected(0)


func _refresh_spreadsheet() -> void:
	var profile_start_ms: int = Time.get_ticks_msec()
	if _selected_table == null or _selected_table_asset == null:
		_spreadsheet.clear()
		return

	# Build per-row metadata FIRST so _compute_columns() sees current cache.
	var meta_start_ms: int = Time.get_ticks_msec()
	_build_resource_meta()
	var meta_ms: int = Time.get_ticks_msec() - meta_start_ms
	var columns_start_ms: int = Time.get_ticks_msec()
	var columns: Array[Dictionary]
	if _resource_first_mode:
		columns = _compute_columns_resource_first()
	else:
		columns = _compute_columns()
	var columns_ms: int = Time.get_ticks_msec() - columns_start_ms
	var rows_start_ms: int = Time.get_ticks_msec()
	var rows: Array[GRDRow] = _selected_table.all_readonly()
	var rows_ms: int = Time.get_ticks_msec() - rows_start_ms

	# Pass resource-first property columns to spreadsheet for type display.
	var grid_start_ms: int = Time.get_ticks_msec()
	_spreadsheet.set_data(columns, rows, _selected_table_asset, _property_columns if _resource_first_mode else [], _db_asset)
	var grid_ms: int = Time.get_ticks_msec() - grid_start_ms

	# Re-apply search text if any.
	if not _search_edit.text.strip_edges().is_empty():
		_spreadsheet.set_search(_search_edit.text)

	var total_ms: int = Time.get_ticks_msec() - profile_start_ms
	if total_ms >= 50:
		print("GRD refresh '%s': total=%dms meta=%dms columns=%dms rows=%dms grid=%dms row_count=%d col_count=%d" % [
			String(_selected_table_asset.table_name), total_ms, meta_ms, columns_ms, rows_ms, grid_ms, rows.size(), columns.size(),
		])


func _deferred_refresh_spreadsheet() -> void:
	if not is_inside_tree():
		return
	_refresh_spreadsheet()


# ---------------------------------------------------------------------------
# Column computation
# ---------------------------------------------------------------------------

func _compute_columns() -> Array[Dictionary]:
	# Legacy mode: no row_script set. Return empty columns — spreadsheet
	# shows read-only cells only.
	return []


func _compute_columns_resource_first() -> Array[Dictionary]:
	var columns: Array[Dictionary] = []
	if _selected_table_asset == null or _selected_table_asset.row_script == null:
		return columns
	var sticky_columns := _get_sticky_columns()

	var id_field: StringName = _selected_table_asset.id_field
	if id_field == &"":
		id_field = &"id"

	for col in _property_columns:
		var pname: StringName = col.name
		var is_id: bool = pname == id_field
		var width: int = col.get_width_hint()

		columns.append({
			"key": pname,
			"display": col.get_display_name(),
			"width": width,
			"read_only": col.read_only,
			"sticky": sticky_columns.has(pname),
			"is_id": is_id,
			"is_declared": true,
			"property_column": col,
		})

	# Ensure ID field is always present.
	if not _has_column_key(columns, id_field):
		columns.insert(0, {
			"key": id_field,
			"display": String(id_field),
			"width": _COL_WIDTH_DEFAULT,
			"read_only": true,
			"sticky": sticky_columns.has(id_field),
			"is_id": true,
			"is_declared": true,
			"property_column": null,
		})

	return columns


func _get_sticky_columns() -> Dictionary:
	var result: Dictionary = {}
	if _selected_table_asset == null or _selected_table_asset.row_script == null:
		return result
	var schema = _selected_table_asset.row_script.new()
	if schema == null or not schema.has_method("get_sticky_columns"):
		return result
	for column_name in schema.get_sticky_columns():
		result[StringName(column_name)] = true
	return result


static func _has_column_key(columns: Array[Dictionary], key: StringName) -> bool:
	for col in columns:
		if col.get("key") == key:
			return true
	return false


func _collect_all_row_keys() -> Array[StringName]:
	var keys_set: Dictionary = {}
	var keys_order: Array[StringName] = []
	if _selected_table == null:
		return keys_order
	for row in _selected_table.all():
		for key in row.keys():
			if not keys_set.has(key):
				keys_set[key] = true
				keys_order.append(key)
	return keys_order


# ---------------------------------------------------------------------------
# Resource metadata
# ---------------------------------------------------------------------------

var _cached_meta: Dictionary = {}
var _cached_meta_resource: Resource = null


func _build_resource_meta() -> Dictionary:
	if _selected_table == null:
		_cached_meta = {}
		_cached_meta_resource = null
		return _cached_meta
	var rows: Array[GRDRow] = _selected_table.all_readonly()
	if rows.is_empty():
		_cached_meta = {}
		_cached_meta_resource = null
		return _cached_meta
	var resource: Resource = rows[0].get_resource()
	if resource == null:
		_cached_meta = {}
		_cached_meta_resource = null
		return _cached_meta
	if resource == _cached_meta_resource:
		return _cached_meta
	var map: Dictionary = {}
	for p in resource.get_property_list():
		if p.name in GRDRow._BUILTIN_RESOURCE_PROPS:
			continue
		map[p.name] = p
	_cached_meta = map
	_cached_meta_resource = resource
	return _cached_meta


func _find_table_asset_by_name(table_name: StringName) -> GRDTableAsset:
	if _db_asset == null:
		return null
	for ta in _db_asset.tables:
		if ta != null and ta.table_name == table_name:
			return ta
	return null


# ---------------------------------------------------------------------------
# Dirty tracking
# ---------------------------------------------------------------------------

func _mark_row_dirty(resource: Resource) -> void:
	if resource == null:
		return
	_dirty_database = true
	resource.emit_changed()
	if _selected_table_asset != null:
		_selected_table_asset.emit_changed()
	if _db_asset != null:
		_db_asset.emit_changed()
	if not resource.resource_path.is_empty() and not resource.resource_path.contains("::"):
		_dirty_rows[resource.resource_path] = resource
	_update_dirty_label()
	_update_button_states()


func _mark_database_dirty() -> void:
	_dirty_database = true
	if _db_asset != null:
		_db_asset.emit_changed()
	_update_dirty_label()
	_update_button_states()


func _mark_table_asset_changed(table_asset: GRDTableAsset) -> void:
	if table_asset == null:
		return
	table_asset.emit_changed()
	if _db_asset != null:
		_db_asset.emit_changed()


func _set_database_tables(tables: Array[GRDTableAsset]) -> void:
	if _db_asset == null:
		return
	var next_tables: Array[GRDTableAsset] = []
	for table in tables:
		next_tables.append(table)
	_db_asset.tables = next_tables
	_db_asset.notify_property_list_changed()
	_db_asset.emit_changed()


func _set_table_rows(table_asset: GRDTableAsset, rows: Array[Resource]) -> void:
	if table_asset == null:
		return
	var next_rows: Array[Resource] = []
	for row in rows:
		next_rows.append(row)
	table_asset.rows = next_rows
	table_asset.notify_property_list_changed()
	table_asset.emit_changed()


func _copy_table_rows(table_asset: GRDTableAsset) -> Array[Resource]:
	var rows: Array[Resource] = []
	if table_asset == null:
		return rows
	for row in table_asset.rows:
		rows.append(row)
	return rows


func _apply_table_rows_change(
	table_asset: GRDTableAsset,
	rows: Array[Resource],
	selected_resource: Resource,
	status_text: String,
) -> void:
	if table_asset == null:
		return
	_set_table_rows(table_asset, rows)
	_mark_table_asset_changed(table_asset)
	_mark_database_dirty()
	_rebuild_database()

	_selected_row_index = -1
	_selected_row = null
	if selected_resource != null:
		var idx: int = table_asset.rows.find(selected_resource)
		if idx != -1:
			_selected_row_index = idx

	_refresh_ui()
	_spreadsheet.refresh_row_heights()
	if not status_text.is_empty():
		_set_status(status_text, false)


func _update_dirty_label() -> void:
	var parts: PackedStringArray = PackedStringArray()
	if _dirty_database:
		parts.append("Database modified")
	if _dirty_rows.size() > 0:
		parts.append("%d row(s) modified" % _dirty_rows.size())
	_dirty_label.text = ("* " + " | ".join(parts)) if not parts.is_empty() else ""


func _update_button_states() -> void:
	var has_db: bool = _db_asset != null
	var has_table: bool = _selected_table_asset != null
	var has_dirty: bool = _dirty_database or _dirty_rows.size() > 0

	_save_btn.disabled = not has_dirty
	_save_btn.text = "Save" if has_dirty else "Save (clean)"
	_add_row_btn.disabled = not (has_table and _resource_first_mode)
	_table_dropdown.disabled = not has_db or _table_dropdown.get_item_count() == 0
	_set_actions_menu_disabled(_MENU_VALIDATE, not has_db)
	_set_actions_menu_disabled(_MENU_ADD_TABLE, not has_db)
	_set_actions_menu_disabled(_MENU_EDIT_TABLE, not has_db or not has_table)
	_set_actions_menu_disabled(_MENU_DELETE_TABLE, not has_db or not has_table)
	_set_actions_menu_disabled(_MENU_GENERATE_CONSTANTS, not has_db)

	_row_script_label.visible = has_table
	if has_table:
		_row_script_label.text = "Script: %s" % _get_table_script_label(_selected_table_asset)
		_table_dropdown.tooltip_text = _row_script_label.text
	else:
		_row_script_label.text = "Script: (none)"
		_table_dropdown.tooltip_text = ""


func _set_actions_menu_disabled(id: int, disabled: bool) -> void:
	if _actions_menu == null:
		return
	var popup := _actions_menu.get_popup()
	var index := popup.get_item_index(id)
	if index != -1:
		popup.set_item_disabled(index, disabled)


# ---------------------------------------------------------------------------
# Signal handlers: toolbar
# ---------------------------------------------------------------------------

func _on_path_submitted(new_text: String) -> void:
	load_database(new_text.strip_edges())


func _on_load_pressed() -> void:
	load_database(_path_edit.text.strip_edges())


func _on_refresh_plugin_pressed() -> void:
	refresh_plugin_requested.emit(_db_asset_path)


func _on_browse_pressed() -> void:
	if _browse_dialog == null:
		_browse_dialog = EditorFileDialog.new()
		_browse_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_browse_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		_browse_dialog.title = "Open GRDDatabaseAsset"
		_browse_dialog.filters = PackedStringArray([
			"*.tres ; TRES Files", "*.res ; RES Files",
		])
		_browse_dialog.min_size = Vector2i(1200, 800)
		_browse_dialog.file_selected.connect(func(path: String) -> void:
			_path_edit.text = path
			load_database(path)
		)
		add_child(_browse_dialog)
	var dialog_size := Vector2i(1200, 800)
	_browse_dialog.popup_centered(dialog_size)
	_browse_dialog.size = dialog_size
	(func() -> void:
		if is_instance_valid(_browse_dialog):
			_browse_dialog.size = dialog_size
	).call_deferred()


func _on_actions_menu_id_pressed(id: int) -> void:
	match id:
		_MENU_BROWSE:
			_on_browse_pressed()
		_MENU_REFRESH:
			_on_refresh_plugin_pressed()
		_MENU_ADD_TABLE:
			_on_add_table_pressed()
		_MENU_EDIT_TABLE:
			_on_edit_table_pressed()
		_MENU_DELETE_TABLE:
			_on_delete_table_pressed()
		_MENU_GENERATE_CONSTANTS:
			_on_generate_constants_pressed()
		_MENU_GENERATE_CSHARP_CONSTANTS:
			_on_generate_csharp_constants_pressed()
		_MENU_VALIDATE:
			_on_validate_pressed()


func _on_table_dropdown_selected(index: int) -> void:
	var table_name: StringName = _table_dropdown.get_item_metadata(index)
	_selected_table_asset = _find_table_asset_by_name(table_name)
	_selected_table = _db.get_table(table_name) if _db != null else null
	_selected_row_index = -1
	_selected_row = null

	# Detect resource-first mode.
	_resource_first_mode = _selected_table_asset != null \
		and _selected_table_asset.row_script != null
	_update_property_columns()
	_refresh_spreadsheet()
	_update_button_states()
	if _selected_table_asset != null:
		if _resource_first_mode:
			_set_status("Resource-first mode: columns from '%s' exports." % _selected_table_asset.row_script.resource_path.get_file(), false)
		else:
			_set_status("No row script set. Set a Resource row script to enable editing.", true)


func _on_search_changed(new_text: String) -> void:
	_spreadsheet.set_search(new_text)


# ---------------------------------------------------------------------------
# Signal handlers: spreadsheet
# ---------------------------------------------------------------------------

func _on_cell_changed(row_index: int, key: StringName, new_value: Variant) -> void:
	if _selected_table != null:
		var all_rows: Array[GRDRow] = _selected_table.all_readonly()
		if row_index >= 0 and row_index < all_rows.size():
			var row: GRDRow = all_rows[row_index]
			_mark_row_dirty(row.get_resource())

	if _selected_table_asset != null:
		var id_field: StringName = _selected_table_asset.id_field
		if id_field == &"":
			id_field = &"id"
		if key == id_field:
			_rebuild_database()
			_refresh_spreadsheet()
			_update_button_states()
			_try_restore_selection_after_id_change(row_index)
		else:
			# Do not rebuild the spreadsheet during resource picker commits: it can
			# replace the active picker before Godot finishes applying the resource,
			# leaving the dirty row saved with the old value.  Texture resource cells
			# reserve their preview height in the editor factory, so a height sync is
			# enough here.
			_spreadsheet.refresh_row_heights()


func _try_restore_selection_after_id_change(changed_row_real_idx: int) -> void:
	if _selected_table == null:
		return
	var rows: Array[GRDRow] = _selected_table.all_readonly()
	if changed_row_real_idx >= 0 and changed_row_real_idx < rows.size():
		_selected_row_index = changed_row_real_idx
		_selected_row = rows[changed_row_real_idx]
	else:
		_selected_row_index = -1
		_selected_row = null


func _on_spreadsheet_row_selected(filtered_idx: int) -> void:
	var real_idx: int = _spreadsheet.get_selected_row_index()
	_selected_row_index = real_idx
	if _selected_table != null:
		var rows: Array[GRDRow] = _selected_table.all_readonly()
		if real_idx >= 0 and real_idx < rows.size():
			_selected_row = rows[real_idx]
		else:
			_selected_row = null
	else:
		_selected_row = null
	_update_button_states()


func _on_spreadsheet_row_delete_requested(row_index: int) -> void:
	_selected_row_index = row_index
	if _selected_table != null:
		var rows: Array[GRDRow] = _selected_table.all_readonly()
		_selected_row = rows[row_index] if row_index >= 0 and row_index < rows.size() else null
	else:
		_selected_row = null
	_on_remove_row_pressed()


func _on_spreadsheet_row_move_requested(from_index: int, to_index: int) -> void:
	if _selected_table_asset == null or from_index == to_index:
		return
	if not _resource_first_mode:
		_set_status("Set a Resource row script before reordering rows.", true)
		return
	if from_index < 0 or from_index >= _selected_table_asset.rows.size():
		return
	if to_index < 0 or to_index >= _selected_table_asset.rows.size():
		return

	var before_rows: Array[Resource] = _copy_table_rows(_selected_table_asset)
	var after_rows: Array[Resource] = before_rows.duplicate()
	var moved_resource: Resource = after_rows[from_index]
	after_rows.remove_at(from_index)
	after_rows.insert(to_index, moved_resource)
	var move_status: String = "Moved row %d to %d in table '%s'." % [from_index, to_index, String(_selected_table_asset.table_name)]
	var undo_status: String = "Undid row move in table '%s'." % String(_selected_table_asset.table_name)

	if _undo_redo != null:
		_undo_redo.create_action("Move GRD Row")
		_undo_redo.add_do_method(
			self,
			"_apply_table_rows_change",
			_selected_table_asset,
			after_rows,
			moved_resource,
			move_status,
		)
		_undo_redo.add_undo_method(
			self,
			"_apply_table_rows_change",
			_selected_table_asset,
			before_rows,
			moved_resource,
			undo_status,
		)
		_undo_redo.commit_action()
	else:
		_apply_table_rows_change(_selected_table_asset, after_rows, moved_resource, move_status)


# ---------------------------------------------------------------------------
# Signal handlers: table management
# ---------------------------------------------------------------------------

func _on_add_table_pressed() -> void:
	if _db_asset == null:
		_set_status("No database loaded.", true)
		return
	_ensure_table_dialog()
	_editing_table_asset = null
	_table_dialog.title = "Create Table"
	_table_dialog.ok_button_text = "Create"
	_table_name_edit.text = _next_unique_table_name()
	_populate_table_script_picker(null)
	_table_dialog.popup_centered(Vector2i(420, 170))


func _on_edit_table_pressed() -> void:
	if _db_asset == null or _selected_table_asset == null:
		return
	_ensure_table_dialog()
	_editing_table_asset = _selected_table_asset
	_table_dialog.title = "Edit Table"
	_table_dialog.ok_button_text = "Apply"
	_table_name_edit.text = String(_selected_table_asset.table_name)
	_populate_table_script_picker(_selected_table_asset.row_script)
	_table_dialog.popup_centered(Vector2i(420, 170))


func _on_delete_table_pressed() -> void:
	if _db_asset == null or _selected_table_asset == null:
		return
	var table_name: StringName = _selected_table_asset.table_name
	_ensure_delete_table_dialog()
	_delete_table_label.text = "Delete table '%s' and all its rows?" % String(table_name)
	_delete_table_dialog.popup_centered(Vector2i(380, 100))


func _ensure_table_dialog() -> void:
	if _table_dialog != null:
		return
	_table_dialog = AcceptDialog.new()
	_table_dialog.title = "Create Table"
	_table_dialog.ok_button_text = "Create"
	var box: VBoxContainer = VBoxContainer.new()
	_table_dialog.add_child(box)
	var label: Label = Label.new()
	label.text = "Table name:"
	box.add_child(label)
	_table_name_edit = LineEdit.new()
	_table_name_edit.placeholder_text = "items"
	box.add_child(_table_name_edit)
	var script_label: Label = Label.new()
	script_label.text = "Row script:"
	box.add_child(script_label)
	_table_script_picker = OptionButton.new()
	_table_script_picker.tooltip_text = "Resource script used to create rows and derive columns."
	box.add_child(_table_script_picker)
	_table_dialog.confirmed.connect(_create_table_from_dialog)
	add_child(_table_dialog)
	GRDTheme.apply_tree(_table_dialog)


func _create_table_from_dialog() -> void:
	var table_name := StringName(_table_name_edit.text.strip_edges())
	if table_name == &"":
		_set_status("Table name cannot be empty.", true)
		return
	var existing_table := _find_table_asset_by_name(table_name)
	if existing_table != null and existing_table != _editing_table_asset:
		_set_status("Table '%s' already exists." % String(table_name), true)
		return
	var row_script: Script = _get_selected_table_script()
	if _editing_table_asset != null:
		_apply_table_settings(_editing_table_asset, table_name, row_script)
		_editing_table_asset = null
		return
	var table := GRDTableAsset.new()
	table.table_name = table_name
	table.id_field = &"id"
	table.rows = []
	table.row_script = row_script
	var tables: Array[GRDTableAsset] = []
	for database_table in _db_asset.tables:
		tables.append(database_table)
	tables.append(table)
	_set_database_tables(tables)
	_mark_table_asset_changed(table)
	_mark_database_dirty()
	_selected_table_asset = table
	_rebuild_database()
	_refresh_ui()
	_select_table_in_dropdown(table_name)
	if row_script != null:
		_set_status("Created table '%s'." % String(table_name), false)
	else:
		_set_status("Created table '%s'. Edit the table to set a Resource row script before adding rows." % String(table_name), false)


func _apply_table_settings(table: GRDTableAsset, table_name: StringName, row_script: Script) -> void:
	table.table_name = table_name
	table.row_script = row_script
	_mark_table_asset_changed(table)
	_mark_database_dirty()
	_selected_table_asset = table
	_rebuild_database()
	_refresh_ui()
	_select_table_in_dropdown(table_name)
	_set_status("Updated table '%s'." % String(table_name), false)


func _ensure_delete_table_dialog() -> void:
	if _delete_table_dialog != null:
		return
	_delete_table_dialog = ConfirmationDialog.new()
	_delete_table_dialog.title = "Delete Table"
	_delete_table_label = Label.new()
	_delete_table_label.text = ""
	_delete_table_dialog.add_child(_delete_table_label)
	_delete_table_dialog.confirmed.connect(_execute_delete_table)
	add_child(_delete_table_dialog)
	GRDTheme.apply_tree(_delete_table_dialog)


func _execute_delete_table() -> void:
	if _db_asset == null or _selected_table_asset == null:
		return
	var table_name: StringName = _selected_table_asset.table_name
	var next_tables: Array[GRDTableAsset] = []
	for ta in _db_asset.tables:
		if ta != _selected_table_asset:
			next_tables.append(ta)
	_set_database_tables(next_tables)
	_selected_table_asset = null
	_selected_table = null
	_selected_row_index = -1
	_selected_row = null
	_mark_database_dirty()
	_rebuild_database()
	_refresh_ui()
	_set_status("Deleted table '%s'." % String(table_name), false)


# ---------------------------------------------------------------------------
# Row script helpers
# ---------------------------------------------------------------------------

func _populate_table_script_picker(current_script: Script) -> void:
	_table_script_picker.clear()
	_table_script_picker.add_item("(none)")
	_table_script_picker.set_item_metadata(0, "")

	var seen: Dictionary = {}

	# Project global scripts that extend GRDRowSchema.
	for gcls in ProjectSettings.get_global_class_list():
		var script_path: String = gcls.get("path", "")
		if script_path.is_empty():
			continue
		var loaded = load(script_path)
		if loaded is Script and _script_extends_row_schema(loaded as Script):
			var gname: String = gcls.get("class", "")
			if gname != "" and not seen.has(gname):
				seen[gname] = true

	var type_names: PackedStringArray = PackedStringArray(seen.keys())
	type_names.sort()

	for type_name in type_names:
		var idx: int = _table_script_picker.get_item_count()
		_table_script_picker.add_item(type_name)
		_table_script_picker.set_item_metadata(idx, type_name)

	# Select current row_script if set; include fallback for unresolvable scripts.
	if current_script != null:
		var current_name: String = current_script.get_global_name()

		# 1) Try match by global name.
		if current_name != "":
			for i in _table_script_picker.get_item_count():
				if _table_script_picker.get_item_metadata(i) == current_name:
					_table_script_picker.selected = i
					return

		# 2) Fallback: match by script identity.
		for i in _table_script_picker.get_item_count():
			var meta: String = _table_script_picker.get_item_metadata(i)
			if meta.is_empty():
				continue
			var scr: Script = _resolve_script_from_type_name(meta)
			if scr != null and scr == current_script:
				_table_script_picker.selected = i
				return

		# 3) Script not in filtered list — append with fallback label.
		var fallback_label: String = current_name if not current_name.is_empty() \
			else current_script.resource_path.get_file().get_basename()
		var fallback_meta: String = current_script.resource_path if not current_script.resource_path.is_empty() \
			else fallback_label
		var idx: int = _table_script_picker.get_item_count()
		_table_script_picker.add_item("%s [unavailable]" % fallback_label)
		_table_script_picker.set_item_metadata(idx, fallback_meta)
		_table_script_picker.selected = idx
		return

	_table_script_picker.selected = 0


func _get_selected_table_script() -> Script:
	if _table_script_picker == null or _table_script_picker.selected < 0:
		return null
	var type_name: String = _table_script_picker.get_item_metadata(_table_script_picker.selected)
	if type_name.is_empty():
		return null
	var script: Script = _resolve_script_from_type_name(type_name)
	if script == null:
		_set_status("Could not resolve script for type '%s'." % type_name, true)
	return script


func _get_table_script_label(table: GRDTableAsset) -> String:
	if table == null or table.row_script == null:
		return "(none)"
	var global_name: String = table.row_script.get_global_name()
	if not global_name.is_empty():
		return global_name
	if not table.row_script.resource_path.is_empty():
		return table.row_script.resource_path.get_file()
	return "(unnamed script)"


func _resolve_script_from_type_name(type_name: String) -> Script:
	if type_name.begins_with("res://"):
		var direct: Variant = load(type_name)
		if direct is Script:
			return direct as Script
	for gcls in ProjectSettings.get_global_class_list():
		if gcls.get("class", "") == type_name:
			var path: String = gcls.get("path", "")
			if not path.is_empty():
				var loaded: Variant = load(path)
				if loaded is Script:
					return loaded as Script
	return null


func _update_property_columns() -> void:
	_property_columns.clear()
	if _selected_table_asset == null or _selected_table_asset.row_script == null:
		return
	_property_columns = GRDPropertyColumn.from_script(_selected_table_asset.row_script)


# ---------------------------------------------------------------------------
# Signal handlers: add / remove rows
# ---------------------------------------------------------------------------

func _on_add_row_pressed() -> void:
	if _selected_table_asset == null:
		return
	if not _resource_first_mode:
		_set_status("Set a Resource row script before adding rows.", true)
		return

	var new_row: Resource = _create_new_row_resource()
	if new_row == null:
		_set_status("Failed to create new row resource.", true)
		return

	var before_rows: Array[Resource] = _copy_table_rows(_selected_table_asset)
	var after_rows: Array[Resource] = before_rows.duplicate()
	after_rows.append(new_row)
	var add_status: String = "Row added to table '%s'." % String(_selected_table_asset.table_name)
	var undo_status: String = "Undid row add in table '%s'." % String(_selected_table_asset.table_name)

	if _undo_redo != null:
		_undo_redo.create_action("Add GRD Row")
		_undo_redo.add_do_method(
			self,
			"_apply_table_rows_change",
			_selected_table_asset,
			after_rows,
			new_row,
			add_status,
		)
		_undo_redo.add_do_method(new_row, "emit_changed")
		_undo_redo.add_undo_method(
			self,
			"_apply_table_rows_change",
			_selected_table_asset,
			before_rows,
			null,
			undo_status,
		)
		_undo_redo.commit_action()
	else:
		_apply_table_rows_change(_selected_table_asset, after_rows, new_row, add_status)
		new_row.emit_changed()


func _create_new_row_resource() -> Resource:
	if _selected_table_asset.row_script != null:
		var new_row: Resource = _selected_table_asset.create_row()
		if new_row == null:
			_set_status("Failed to create row from script.", true)
			return null
		# Auto-fill ID field if empty.
		var id_field: StringName = _selected_table_asset.get_id_field()
		var current_id: Variant = new_row.get(String(id_field)) if new_row.has_method("get") else null
		if current_id == null or str(current_id).is_empty():
			var new_id: StringName = _generate_unique_id()
			new_row.set(String(id_field), new_id)
		return new_row
	_set_status("Set a Resource row script before adding rows.", true)
	return null


func _generate_unique_id() -> StringName:
	var base: String = "row_%d" % (_selected_table_asset.rows.size() + 1)
	var candidate: StringName = StringName(base)
	var counter: int = 1
	while _has_row_with_id(candidate):
		counter += 1
		candidate = StringName("%s_%d" % [base, counter])
	return candidate


func _has_row_with_id(id: StringName) -> bool:
	if _selected_table == null:
		return false
	return _selected_table.has_row(id)


func _on_remove_row_pressed() -> void:
	if _selected_table_asset == null:
		return
	if not _resource_first_mode:
		_set_status("Set a Resource row script before removing rows.", true)
		return
	if _selected_row == null:
		return

	var resource: Resource = _selected_row.get_resource()
	if resource == null:
		_set_status("Selected row has no underlying Resource.", true)
		return

	var idx: int = _selected_table_asset.rows.find(resource)
	if idx == -1:
		_set_status("Row Resource not found in table asset rows array.", true)
		return

	var before_rows: Array[Resource] = _copy_table_rows(_selected_table_asset)
	var after_rows: Array[Resource] = before_rows.duplicate()
	after_rows.remove_at(idx)
	var remove_status: String = "Row removed from table '%s'." % String(_selected_table_asset.table_name)
	var undo_status: String = "Restored row in table '%s'." % String(_selected_table_asset.table_name)

	if _undo_redo != null:
		_undo_redo.create_action("Remove GRD Row")
		_undo_redo.add_do_method(
			self,
			"_apply_table_rows_change",
			_selected_table_asset,
			after_rows,
			null,
			remove_status,
		)
		_undo_redo.add_undo_method(
			self,
			"_apply_table_rows_change",
			_selected_table_asset,
			before_rows,
			resource,
			undo_status,
		)
		_undo_redo.commit_action()
	else:
		_apply_table_rows_change(_selected_table_asset, after_rows, null, remove_status)


# ---------------------------------------------------------------------------
# Signal handlers: save
# ---------------------------------------------------------------------------

func _on_save_pressed() -> void:
	var saved_count: int = 0
	var skipped: PackedStringArray = PackedStringArray()
	var errors: PackedStringArray = PackedStringArray()
	if _normalize_project_file_paths_to_uids():
		_dirty_database = true

	if _dirty_database and _db_asset != null and not _db_asset_path.is_empty():
		var err: Error = ResourceSaver.save(_db_asset, _db_asset_path)
		if err == OK:
			_dirty_database = false
			saved_count += 1
			_set_status("Saved database: %s" % _db_asset_path.get_file(), false)
		else:
			errors.append("Failed to save database: %s (error %d)" % [_db_asset_path, err])
			_set_status("Save failed: %s" % errors[errors.size() - 1], true)
			return

	var dirty_keys: Array = _dirty_rows.keys()
	for rpath in dirty_keys:
		var res: Resource = _dirty_rows[rpath]
		if res == null:
			skipped.append(str(rpath) + " (null resource)")
			continue
		var actual_path: String = res.resource_path
		if actual_path.contains("::"):
			_dirty_rows.erase(rpath)
			continue
		if actual_path.is_empty() or not actual_path.begins_with("res://"):
			skipped.append(str(rpath) + " (no valid res:// path)")
			continue
		var err: Error = ResourceSaver.save(res, actual_path)
		if err == OK:
			saved_count += 1
			_dirty_rows.erase(rpath)
		else:
			errors.append("Failed to save row: %s (error %d)" % [actual_path, err])

	if errors.size() > 0:
		_set_status("Save completed with errors: %s" % "; ".join(errors), true)
	elif skipped.size() > 0:
		_set_status(
			"Saved %d resource(s). Skipped: %s" % [saved_count, "; ".join(skipped)],
			false,
		)
	else:
		if saved_count > 0:
			_set_status("Saved %d resource(s)." % saved_count, false)
		else:
			_set_status("Nothing to save.", false)

	_update_dirty_label()
	_update_button_states()

	if saved_count > 0:
		_rebuild_database()
		_refresh_ui()


# ---------------------------------------------------------------------------
# Signal handlers: validate
# ---------------------------------------------------------------------------

func _on_validate_pressed() -> void:
	if _db_asset == null:
		_set_status("No database loaded.", true)
		return

	_rebuild_database()

	if _db == null:
		_set_status("Database failed to load.", true)
		return

	var issues: Array[GRDDatabaseIssue] = _db.validate()
	_validation_panel.set_issues(issues)

	if issues.is_empty():
		_set_status("Validation passed — no issues found.", false)
	else:
		_set_status("Validation — %d issue(s) found." % issues.size(), true)


func _on_generate_constants_pressed() -> void:
	if _db_asset == null or _db_asset_path.is_empty():
		_set_status("No database loaded.", true)
		return

	var out_path := _db_asset_path.get_basename() + ".gd"
	var source := _build_constants_source(_db_asset, _db_asset_path)
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		_set_status("Failed to write constants: %s" % out_path, true)
		return

	file.store_string(source)
	EditorInterface.get_resource_filesystem().scan()
	_set_status("Generated constants: %s" % out_path, false)


func _on_generate_csharp_constants_pressed() -> void:
	if _db_asset == null or _db_asset_path.is_empty():
		_set_status("No database loaded.", true)
		return

	var gd_path := _db_asset_path.get_basename() + ".gd"
	var gd_file := FileAccess.open(gd_path, FileAccess.WRITE)
	if gd_file == null:
		_set_status("Failed to write GDScript bridge target: %s" % gd_path, true)
		return
	gd_file.store_string(_build_constants_source(_db_asset, _db_asset_path))

	var out_path := _db_asset_path.get_base_dir().path_join("Database.Generated.cs")
	var source := _build_csharp_constants_source(_db_asset, _db_asset_path)
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		_set_status("Failed to write C# constants: %s" % out_path, true)
		return

	file.store_string(source)
	EditorInterface.get_resource_filesystem().scan()
	_set_status("Generated C# constants: %s" % out_path, false)


static func _build_constants_source(db_asset: GRDDatabaseAsset, db_path: String) -> String:
	var generated_class_name := _script_class_name_from_path(db_path)
	var lines := PackedStringArray()
	var used_table_classes := {}

	lines.append("# Generated from %s. Do not edit by hand." % db_path)
	lines.append("@tool")
	lines.append("class_name %s" % generated_class_name)
	lines.append("extends RefCounted")
	lines.append("")

	for table: GRDTableAsset in db_asset.tables:
		if table == null or table.table_name == &"":
			continue

		var table_class := _unique_identifier(
			_pascal_identifier(String(table.table_name), "Table"),
			used_table_classes,
		)
		var used_constants := {
			"TABLE": true,
			"ID_FIELD": true,
			"ALL_COLUMNS": true,
			"Id": true,
		}
		var column_constants := PackedStringArray()
		var id_constants := _row_id_constants(table)

		lines.append("class %s:" % table_class)
		lines.append("\tconst TABLE := &\"%s\"" % _escape_string(String(table.table_name)))
		lines.append("\tconst ID_FIELD := &\"%s\"" % _escape_string(String(table.get_id_field())))

		for column: GRDPropertyColumn in table.get_property_columns():
			if column == null or column.name == &"":
				continue
			var constant_name := _unique_identifier(
				_constant_identifier(String(column.name), "COLUMN"),
				used_constants,
			)
			column_constants.append(constant_name)
			lines.append("\tconst %s := &\"%s\"" % [constant_name, _escape_string(String(column.name))])

		if not column_constants.is_empty():
			lines.append("")
			lines.append("\tconst ALL_COLUMNS := [")
			for constant_name in column_constants:
				lines.append("\t\t%s," % constant_name)
			lines.append("\t]")

		if not id_constants.is_empty():
			lines.append("")
			lines.append("\tclass Id:")
			for constant_name in id_constants:
				lines.append("\t\tconst %s := &\"%s\"" % [constant_name, _escape_string(id_constants[constant_name])])
		lines.append("")

	lines.append("static var raw: GRDDatabase = GRDDatabase.load_from_path(\"%s\")" % _escape_string(db_path))
	lines.append("")
	lines.append("static func table(name: StringName) -> GRDTable:")
	lines.append("\treturn raw.get_table(name)")

	return "\n".join(lines)


static func _build_csharp_constants_source(db_asset: GRDDatabaseAsset, db_path: String) -> String:
	var lines := PackedStringArray()
	var used_table_classes := {
		"Database": true,
		"Row": true,
		"Script": true,
		"Table": true,
	}

	lines.append("// Generated from %s. Do not edit by hand." % db_path)
	lines.append("using Godot;")
	lines.append("")
	lines.append("namespace Game.Database;")
	lines.append("")
	lines.append("public static partial class Database")
	lines.append("{")

	for table: GRDTableAsset in db_asset.tables:
		if table == null or table.table_name == &"":
			continue

		var table_result := _csharp_unique_identifier(
			_csharp_pascal_identifier(String(table.table_name), "Table"),
			used_table_classes,
		)
		var table_class: String = table_result["name"]
		var used_constants := {
			"TABLE": true,
			"ID_FIELD": true,
			"Id": true,
		}
		var id_constants := _csharp_row_id_constants(table)

		if table_result["sanitized"]:
			lines.append("    // Identifier sanitized from \"%s\"." % _csharp_escape_string(String(table.table_name)))
		lines.append("    public static class %s" % table_class)
		lines.append("    {")
		lines.append("        public static readonly StringName TABLE = \"%s\";" % _csharp_escape_string(String(table.table_name)))
		lines.append("        public static readonly StringName ID_FIELD = \"%s\";" % _csharp_escape_string(String(table.get_id_field())))

		for column: GRDPropertyColumn in table.get_property_columns():
			if column == null or column.name == &"":
				continue
			var column_result := _csharp_unique_identifier(
				_csharp_constant_identifier(String(column.name), "COLUMN"),
				used_constants,
			)
			if column_result["sanitized"]:
				lines.append("        // Identifier sanitized from \"%s\"." % _csharp_escape_string(String(column.name)))
			lines.append("        public static readonly StringName %s = \"%s\";" % [column_result["name"], _csharp_escape_string(String(column.name))])

		if not id_constants.is_empty():
			lines.append("")
			lines.append("        public static class Id")
			lines.append("        {")
			for item: Dictionary in id_constants:
				if item["sanitized"]:
					lines.append("            // Identifier sanitized from \"%s\"." % _csharp_escape_string(item["value"]))
				lines.append("            public static readonly StringName %s = \"%s\";" % [item["name"], _csharp_escape_string(item["value"])])
			lines.append("        }")

		lines.append("    }")
		lines.append("")

	lines.append("    private static readonly GDScript Script =")
	lines.append("        GD.Load<GDScript>(\"%s\");" % _csharp_escape_string(db_path.get_basename() + ".gd"))
	lines.append("")
	lines.append("    public static GodotObject Table(StringName name)")
	lines.append("    {")
	lines.append("        return Script.Call(\"table\", name).AsGodotObject();")
	lines.append("    }")
	lines.append("")
	lines.append("    public static GodotObject Row(StringName table, StringName id)")
	lines.append("    {")
	lines.append("        return Table(table).Call(\"get_row\", id).AsGodotObject();")
	lines.append("    }")
	lines.append("}")

	return "\n".join(lines) + "\n"


static func _row_id_constants(table: GRDTableAsset) -> Dictionary:
	var result := {}
	var used := {}
	var id_field := String(table.get_id_field())
	if id_field.is_empty():
		return result

	for row in table.rows:
		if row == null:
			continue
		var id_value: Variant = row.get(id_field)
		if id_value == null or String(id_value).is_empty():
			continue
		var constant_name := _unique_identifier(_constant_identifier(String(id_value), "ID"), used)
		result[constant_name] = String(id_value)
	return result


static func _csharp_row_id_constants(table: GRDTableAsset) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var used := {}
	var id_field := String(table.get_id_field())
	if id_field.is_empty():
		return result

	for row in table.rows:
		if row == null:
			continue
		var id_value: Variant = row.get(id_field)
		if id_value == null or String(id_value).is_empty():
			continue
		var id_string := String(id_value)
		var item := _csharp_unique_identifier(_csharp_constant_identifier(id_string, "ID"), used)
		item["value"] = id_string
		result.append(item)
	return result


static func _script_class_name_from_path(path: String) -> String:
	return _pascal_identifier(path.get_file().get_basename(), "Database")


static func _pascal_identifier(value: String, fallback: String) -> String:
	var words := _identifier_words(value)
	if words.is_empty():
		return fallback

	var result := ""
	for word in words:
		result += word.substr(0, 1).to_upper() + word.substr(1).to_lower()
	if _starts_with_digit(result):
		result = fallback + result
	return result


static func _csharp_pascal_identifier(value: String, fallback: String) -> Dictionary:
	var name := _pascal_identifier(value, fallback)
	var sanitized := _csharp_source_needs_comment(value)
	if _is_csharp_keyword(name):
		name += "_"
		sanitized = true
	return {"name": name, "sanitized": sanitized}


static func _constant_identifier(value: String, fallback: String) -> String:
	var words := _identifier_words(value)
	if words.is_empty():
		return fallback

	var result := "_".join(words).to_upper()
	if _starts_with_digit(result):
		result = fallback + "_" + result
	return result


static func _csharp_constant_identifier(value: String, fallback: String) -> Dictionary:
	var name := _constant_identifier(value, fallback)
	var sanitized := _csharp_source_needs_comment(value)
	if _is_csharp_keyword(name):
		name += "_"
		sanitized = true
	return {"name": name, "sanitized": sanitized}


static func _identifier_words(value: String) -> PackedStringArray:
	var words := PackedStringArray()
	var current := ""

	for i in value.length():
		var ch := value.substr(i, 1)
		if _is_identifier_char(ch):
			current += ch
		elif not current.is_empty():
			words.append(current)
			current = ""

	if not current.is_empty():
		words.append(current)
	return words


static func _is_identifier_char(ch: String) -> bool:
	return (ch >= "a" and ch <= "z") \
		or (ch >= "A" and ch <= "Z") \
		or (ch >= "0" and ch <= "9")


static func _starts_with_digit(value: String) -> bool:
	if value.is_empty():
		return false
	var ch := value.substr(0, 1)
	return ch >= "0" and ch <= "9"


static func _unique_identifier(base: String, used: Dictionary) -> String:
	var candidate := base
	var index := 2
	while used.has(candidate):
		candidate = "%s_%d" % [base, index]
		index += 1
	used[candidate] = true
	return candidate


static func _csharp_unique_identifier(base_result: Dictionary, used: Dictionary) -> Dictionary:
	var base: String = base_result["name"]
	var candidate := base
	var index := 2
	var sanitized: bool = base_result["sanitized"]
	while used.has(candidate):
		candidate = "%s_%d" % [base, index]
		index += 1
		sanitized = true
	used[candidate] = true
	return {"name": candidate, "sanitized": sanitized}


static func _is_csharp_keyword(value: String) -> bool:
	return _CSHARP_KEYWORDS.has(value)


static func _csharp_source_needs_comment(value: String) -> bool:
	if value.is_empty() or _starts_with_digit(value):
		return true
	for i in value.length():
		var ch := value.substr(i, 1)
		if not (_is_identifier_char(ch) or ch == "_"):
			return true
	return _is_csharp_keyword(value)


static func _escape_string(value: String) -> String:
	return value.replace("\\", "\\\\").replace("\"", "\\\"")


static func _csharp_escape_string(value: String) -> String:
	return value.replace("\\", "\\\\").replace("\"", "\\\"")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _select_table_in_dropdown(table_name: StringName) -> void:
	for i in _table_dropdown.get_item_count():
		if _table_dropdown.get_item_metadata(i) == table_name:
			_table_dropdown.selected = i
			_on_table_dropdown_selected(i)
			return


func _next_unique_table_name() -> String:
	var idx := 1
	while _find_table_asset_by_name(StringName("table_%d" % idx)) != null:
		idx += 1
	return "table_%d" % idx


# ---------------------------------------------------------------------------
# Script inheritance helpers
# ---------------------------------------------------------------------------

static func _script_extends_row_schema(script: Script) -> bool:
	while script != null:
		if script.get_global_name() == "GRDRowSchema":
			return true
		script = script.get_base_script()
	return false


# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------

func _set_status(text: String, is_error: bool) -> void:
	if is_error:
		_status_label.text = "[color=red]%s[/color]" % text
	else:
		_status_label.text = "[color=green]%s[/color]" % text
	status_message.emit(text, is_error)
