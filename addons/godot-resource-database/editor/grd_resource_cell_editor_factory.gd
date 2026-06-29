@tool
class_name GRDResourceCellEditorFactory
extends RefCounted

## Resource-first cell editor factory.  Uses GRDPropertyColumn metadata
## derived from Godot exported properties.  No schema/type system dependencies.
##
## Supports: scalar (String, StringName, int, float, bool), enum hints,
## Resource refs, Script refs, Array summary + Edit, Dictionary read-only.
## Changes apply via resource.set(key, value) with emit_changed.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SUMMARY_LENGTH: int = 40
const ROW_REFERENCE_ICON_SIZE: int = 18
const SELECT_LABEL_MAX_CHARS: int = 24
const ICON_SELECT_LABEL_MAX_CHARS: int = 16
const STRUCTURED_HEADER_CHAR_WIDTH: int = 7
const STRUCTURED_HEADER_PADDING: int = 18
const STRUCTURED_COL_WIDTH: int = 96
const STRUCTURED_ROW_HEIGHT: int = 34
const INLINE_TABLE_MIN_HEIGHT: int = 114
const TEXTURE_RESOURCE_CELL_HEIGHT: int = 32
const RESOURCE_PICKER_COMMIT_POLL_SECONDS: float = 0.15
const DEFAULT_ROW_REFERENCE_ICON_PROPERTY: StringName = &"icon"


class StructuredRowDragHandle:
	extends Button

	var owner_id: int = 0
	var row_index: int = -1
	var on_move: Callable

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if row_index < 0:
			return null
		var preview := Label.new()
		preview.text = "Move row %d" % row_index
		GRDTheme.style_label(preview, GRDTheme.FONT_SIZE_SMALL, GRDTheme.TEXT)
		set_drag_preview(preview)
		return {
			"type": "grd_structured_array_row",
			"owner_id": owner_id,
			"from_index": row_index,
		}

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		if not (data is Dictionary) or row_index < 0:
			return false
		var drag_data: Dictionary = data
		return drag_data.get("type", "") == "grd_structured_array_row" \
			and int(drag_data.get("owner_id", -1)) == owner_id \
			and int(drag_data.get("from_index", -1)) != row_index

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if _can_drop_data(_at_position, data) and on_move.is_valid():
			var drag_data: Dictionary = data
			on_move.call(int(drag_data.get("from_index", -1)), row_index)

const SUMMARY_TYPES: Array[int] = [
	TYPE_ARRAY, TYPE_DICTIONARY, TYPE_OBJECT,
	TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY,
	TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY,
	TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY,
	TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY,
]

const EDITABLE_SCALAR_TYPES: Array[int] = [
	TYPE_STRING, TYPE_STRING_NAME, TYPE_INT, TYPE_FLOAT, TYPE_BOOL,
]

static var _reference_cache: Dictionary = {}
static var _thumbnail_cache: Dictionary = {}
static var _assignable_scripts_cache: Dictionary = {}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

static func clear_caches() -> void:
	_reference_cache.clear()
	_thumbnail_cache.clear()
	_assignable_scripts_cache.clear()


## Creates an appropriate inline control for a cell based on GRDPropertyColumn.
## `on_change(new_value)` is called when the user edits the cell.
static func create_cell_editor(
	col: GRDPropertyColumn,
	value: Variant,
	resource: Resource,
	on_change: Callable,
	database_asset: GRDDatabaseAsset = null,
	cell_resource_stack: Dictionary = {},
) -> Control:
	if col == null:
		return read_only_label(str(value) if value != null else "")

	# Enum → OptionButton
	if col.is_enum():
		return _create_enum_editor(col, value, on_change)

	# Resource reference → table picker, inline cell resource, or EditorResourcePicker
	if col.is_resource_reference():
		if _is_row_schema_type(col.get_resource_type()):
			return _create_row_reference_editor(col, value, on_change, database_asset)
		if _is_cell_resource_type(col.get_resource_type()):
			return _create_cell_resource_editor(col, value, on_change, database_asset, cell_resource_stack)
		return _create_resource_editor(col, value, on_change)

	# Script reference → EditorResourcePicker constrained to Script
	if col.is_script():
		return _create_script_editor(col, value, on_change)

	# Scalar types
	if col.is_bool():
		return _create_bool_editor(value, on_change)
	if col.is_numeric():
		return _create_numeric_editor(col, value, on_change)

	# File path (project-relative or global) → LineEdit + Browse button
	if col.is_file_path() or col.is_global_file_path():
		return _create_file_path_editor(col, value, on_change)

	if col.is_string_like():
		return _create_string_editor(col, value, on_change)

	# Array → summary + edit button
	if col.is_array():
		return _create_array_editor(col, value, resource, on_change, database_asset)

	# Dictionary → read-only summary
	if col.is_dictionary():
		return read_only_label(_dict_summary(value))

	# Object (non-resource) → read-only
	if col.is_object():
		if value is Resource:
			return read_only_label(_resource_summary(value))
		return read_only_label(str(value) if value != null else "")

	# Fallback: read-only
	return read_only_label(str(value) if value != null else "")


# ---------------------------------------------------------------------------
# Scalar editors
# ---------------------------------------------------------------------------

static func _create_bool_editor(value: Variant, on_change: Callable) -> Control:
	var check: CheckBox = CheckBox.new()
	check.add_theme_font_size_override("font_size", GRDTheme.FONT_SIZE)
	check.add_theme_color_override("font_color", GRDTheme.TEXT)
	check.button_pressed = bool(value) if value != null else false
	check.text = ""
	check.custom_minimum_size.y = _compact_control_height()
	check.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	check.toggled.connect(func(pressed: bool) -> void:
		on_change.call(pressed)
	)
	return check


static func _create_numeric_editor(col: GRDPropertyColumn, value: Variant, on_change: Callable) -> Control:
	var spin: SpinBox = SpinBox.new()
	GRDTheme.style_spinbox(spin)
	spin.min_value = -999999999
	spin.max_value = 999999999
	if col.type == TYPE_FLOAT:
		spin.step = 0.01
		spin.value = float(value) if value != null else 0.0
	else:
		spin.step = 1
		spin.value = int(value) if value != null else 0
	spin.custom_minimum_size = Vector2(GRDTheme.scaled(80.0), _compact_control_height())
	spin.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	spin.value_changed.connect(func(val: float) -> void:
		if col.type == TYPE_FLOAT:
			on_change.call(val)
		else:
			on_change.call(int(val))
	)
	return spin


static func _create_string_editor(col: GRDPropertyColumn, value: Variant, on_change: Callable) -> Control:
	var edit: LineEdit = LineEdit.new()
	GRDTheme.style_input(edit)
	edit.text = str(value) if value != null else ""
	_sync_line_edit_tooltip(edit)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit.custom_minimum_size.y = _compact_control_height()
	edit.select_all_on_focus = true
	edit.text_changed.connect(func(_new_text: String) -> void:
		_sync_line_edit_tooltip(edit)
	)
	var submit := func(new_text: String) -> void:
		if col.type == TYPE_STRING_NAME:
			on_change.call(StringName(new_text))
		else:
			on_change.call(new_text)
		edit.release_focus()
	edit.text_submitted.connect(submit)
	edit.focus_exited.connect(func() -> void:
		var current: String = edit.text
		var prev: String = str(value) if value != null else ""
		if current != prev:
			if col.type == TYPE_STRING_NAME:
				on_change.call(StringName(current))
			else:
				on_change.call(current)
	)
	return edit


# ---------------------------------------------------------------------------
# File path editor
# ---------------------------------------------------------------------------

static func _create_file_path_editor(col: GRDPropertyColumn, value: Variant, on_change: Callable) -> Control:
	# EditorFileDialog is editor-only; fall back to plain string editor at runtime.
	if not Engine.is_editor_hint():
		return _create_string_editor(col, value, on_change)
	var stored_value: String = str(value) if value != null else ""

	var box: HBoxContainer = HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var edit: LineEdit = LineEdit.new()
	GRDTheme.style_input(edit)
	edit.text = _file_path_display_value(col, stored_value)
	_sync_file_path_tooltip(edit, col, stored_value)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit.custom_minimum_size.y = _compact_control_height()
	edit.select_all_on_focus = true
	edit.text_changed.connect(func(_new_text: String) -> void:
		_sync_file_path_tooltip(edit, col, _file_path_storage_value(col, edit.text))
	)
	box.add_child(edit)

	var browse_btn: Button = Button.new()
	browse_btn.text = "…"
	browse_btn.custom_minimum_size = Vector2(GRDTheme.scaled(28.0), _compact_control_height())
	browse_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	GRDTheme.style_button(browse_btn)
	box.add_child(browse_btn)

	# Apply text changes on submit / focus-exit.
	var emit_change := func(new_text: String) -> void:
		var new_stored_value: String = _file_path_storage_value(col, new_text)
		stored_value = new_stored_value
		edit.text = _file_path_display_value(col, stored_value)
		_sync_file_path_tooltip(edit, col, stored_value)
		on_change.call(stored_value)
	edit.text_submitted.connect(emit_change)
	edit.focus_exited.connect(func() -> void:
		var current: String = _file_path_storage_value(col, edit.text)
		var prev: String = stored_value
		if current != prev:
			stored_value = current
			edit.text = _file_path_display_value(col, stored_value)
			_sync_file_path_tooltip(edit, col, stored_value)
			on_change.call(stored_value)
	)

	# Browse button opens EditorFileDialog.
	browse_btn.pressed.connect(func() -> void:
		var fd: EditorFileDialog = EditorFileDialog.new()
		fd.title = "Select %s" % col.get_display_name()
		fd.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		if col.is_global_file_path():
			fd.access = EditorFileDialog.ACCESS_FILESYSTEM
		else:
			fd.access = EditorFileDialog.ACCESS_RESOURCES
		var filters: PackedStringArray = col.get_file_filter()
		if filters.size() > 0:
			fd.filters = filters
		var dialog_size := Vector2i(1200, 800)
		fd.min_size = dialog_size
		fd.file_selected.connect(func(selected: String) -> void:
			stored_value = _file_path_storage_value(col, selected)
			edit.text = _file_path_display_value(col, stored_value)
			_sync_file_path_tooltip(edit, col, stored_value)
			on_change.call(stored_value)
		)
		var tree: SceneTree = Engine.get_main_loop()
		if tree != null and tree.root != null:
			tree.root.add_child(fd)
		fd.popup_centered(dialog_size)
		fd.size = dialog_size
		(func() -> void:
			if is_instance_valid(fd):
				fd.size = dialog_size
		).call_deferred()
	)

	return box


static func _file_path_display_value(col: GRDPropertyColumn, value: String) -> String:
	if col.is_global_file_path() or value.is_empty():
		return value
	return ResourceUID.ensure_path(value)


static func _file_path_storage_value(col: GRDPropertyColumn, value: String) -> String:
	if col.is_global_file_path() or value.is_empty() or value.begins_with("uid://"):
		return value
	return project_file_path_storage_value(value)


static func project_file_path_storage_value(value: String) -> String:
	if value.is_empty() or value.begins_with("uid://") or not value.begins_with("res://"):
		return value
	var converted: Variant = ResourceUID.path_to_uid(value)
	if typeof(converted) == TYPE_STRING:
		var converted_text: String = String(converted)
		return converted_text if converted_text.begins_with("uid://") else value
	if typeof(converted) == TYPE_INT:
		var converted_id: int = int(converted)
		return ResourceUID.id_to_text(converted_id) if converted_id != ResourceUID.INVALID_ID else value
	return value


static func _sync_file_path_tooltip(edit: LineEdit, col: GRDPropertyColumn, stored_value: String) -> void:
	if col.is_global_file_path() or stored_value.is_empty():
		edit.tooltip_text = edit.text
		return
	var display_value: String = _file_path_display_value(col, stored_value)
	edit.tooltip_text = "%s\n%s" % [display_value, stored_value] if stored_value != display_value else display_value


# ---------------------------------------------------------------------------
# Enum editor
# ---------------------------------------------------------------------------

static func _create_enum_editor(col: GRDPropertyColumn, value: Variant, on_change: Callable) -> Control:
	var opts: PackedStringArray = col.get_enum_values()
	var option: OptionButton = OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	option.custom_minimum_size.y = _compact_control_height()

	var current_str: String = str(value) if value != null else ""
	var selected_idx: int = 0
	var found_match: bool = false

	for j in opts.size():
		var opt_idx: int = option.get_item_count()
		_add_text_option(option, opts[j], opt_idx)
		option.set_item_metadata(opt_idx, opts[j])
		if opts[j] == current_str:
			selected_idx = opt_idx
			found_match = true

	# If current value is non-empty but not in options, append it so data is not lost.
	if current_str != "" and not found_match:
		var opt_idx: int = option.get_item_count()
		_add_text_option(option, "%s (custom)" % current_str, opt_idx)
		option.set_item_metadata(opt_idx, current_str)
		selected_idx = opt_idx

	option.selected = selected_idx
	_update_option_tooltip(option)
	option.item_selected.connect(func(idx: int) -> void:
		_update_option_tooltip(option)
		on_change.call(option.get_item_metadata(idx))
	)
	_style_cell_option(option)
	return option


# ---------------------------------------------------------------------------
# Resource reference editors
# ---------------------------------------------------------------------------

static func _create_resource_editor(col: GRDPropertyColumn, value: Variant, on_change: Callable) -> Control:
	# EditorResourcePicker is editor-only; fall back to read-only in headless.
	if not Engine.is_editor_hint():
		return read_only_label(_resource_summary(value))
	var picker: EditorResourcePicker = EditorResourcePicker.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var base_type: String = col.get_resource_type()
	picker.custom_minimum_size.y = _resource_picker_height(value, base_type)
	var committed_resource: Resource = value as Resource if value is Resource else null
	if value is Resource:
		picker.edited_resource = value
	if not base_type.is_empty():
		picker.base_type = base_type
	var commit_picker_value := func(new_res: Resource) -> void:
		if new_res == committed_resource:
			return
		committed_resource = new_res
		picker.custom_minimum_size.y = _resource_picker_height(committed_resource, base_type)
		picker.update_minimum_size()
		on_change.call(committed_resource)
	picker.resource_changed.connect(commit_picker_value)
	picker.resource_selected.connect(func(selected: Resource, _inspect: bool) -> void:
		if selected != null:
			EditorInterface.inspect_object(selected, "", true)
	)
	# EditorResourcePicker can update its displayed edited_resource without
	# emitting resource_changed through this embedded-plugin path. Poll the
	# picker-local value and commit only when it actually differs, so Save gets
	# enabled for the same value the user sees.
	var commit_timer := Timer.new()
	commit_timer.wait_time = RESOURCE_PICKER_COMMIT_POLL_SECONDS
	commit_timer.autostart = true
	commit_timer.timeout.connect(func() -> void:
		commit_picker_value.call(picker.edited_resource)
	)
	picker.add_child(commit_timer)
	return picker


static func _create_script_editor(col: GRDPropertyColumn, value: Variant, on_change: Callable) -> Control:
	# EditorResourcePicker is editor-only; fall back to read-only in headless.
	if not Engine.is_editor_hint():
		return read_only_label(_resource_summary(value))
	var picker: EditorResourcePicker = EditorResourcePicker.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picker.custom_minimum_size.y = _resource_picker_height()
	picker.base_type = "Script"
	if value is Script:
		picker.edited_resource = value
	elif value is Resource:
		picker.edited_resource = value
	picker.resource_changed.connect(func(new_res: Resource) -> void:
		on_change.call(new_res)
	)
	return picker


static func _create_row_reference_editor(col: GRDPropertyColumn, value: Variant, on_change: Callable, database_asset: GRDDatabaseAsset) -> Control:
	var type_name: String = col.get_resource_type()
	var available_ids: PackedStringArray = _get_available_ids_for_type(database_asset, type_name)
	if database_asset == null or available_ids.is_empty():
		return _create_resource_editor(col, value, on_change)

	var option: OptionButton = OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	option.custom_minimum_size.y = _compact_control_height()

	_add_text_option(option, "(none)", 0)
	option.set_item_metadata(0, "")
	var current_id: String = _get_resource_id(value as Resource) if value is Resource else ""
	var selected_idx: int = 0
	for id_value in available_ids:
		var opt_idx: int = option.get_item_count()
		_add_row_reference_option(option, database_asset, type_name, id_value, opt_idx)
		option.set_item_metadata(opt_idx, id_value)
		if id_value == current_id:
			selected_idx = opt_idx
	option.selected = selected_idx
	_update_option_tooltip(option)
	option.item_selected.connect(func(idx: int) -> void:
		_update_option_tooltip(option)
		var selected_id: String = option.get_item_metadata(idx)
		var selected_resource: Resource = null if selected_id.is_empty() else _find_resource_by_id(database_asset, type_name, selected_id)
		on_change.call(selected_resource)
	)
	_style_cell_option(option)
	return option


static func _create_cell_resource_editor(col: GRDPropertyColumn, value: Variant, on_change: Callable, database_asset: GRDDatabaseAsset, cell_resource_stack: Dictionary = {}) -> Control:
	var base_script: Script = GRDPropertyColumn._resolve_class_script(col.get_resource_type())
	if base_script == null:
		return _create_resource_editor(col, value, on_change)

	var current: Resource = value as Resource if value is Resource else null
	if current == null:
		if cell_resource_stack.has(base_script):
			return read_only_label("(null)")
		return _create_empty_cell_resource_stub(col, base_script, on_change, database_asset, cell_resource_stack)

	var container: VBoxContainer = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.custom_minimum_size.y = _inline_table_min_height()
	_rebuild_cell_resource_editor(container, col, base_script, current, on_change, database_asset, cell_resource_stack)
	return container


static func _create_empty_cell_resource_stub(col: GRDPropertyColumn, base_script: Script, on_change: Callable, database_asset: GRDDatabaseAsset, cell_resource_stack: Dictionary) -> Control:
	var container: VBoxContainer = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(row)

	var label: Label = read_only_label("(none)")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var add_btn: Button = Button.new()
	add_btn.text = "+ Add"
	add_btn.tooltip_text = "Create %s" % col.get_resource_type()
	add_btn.custom_minimum_size.y = _compact_control_height()
	GRDTheme.style_button(add_btn)
	row.add_child(add_btn)

	add_btn.pressed.connect(func() -> void:
		var created = base_script.new()
		if created is Resource:
			var current: Resource = created as Resource
			on_change.call(current)
			container.custom_minimum_size.y = _inline_table_min_height()
			_rebuild_cell_resource_editor(container, col, base_script, current, on_change, database_asset, cell_resource_stack)
	)
	return container


static func _rebuild_cell_resource_editor(container: VBoxContainer, col: GRDPropertyColumn, base_script: Script, current: Resource, on_change: Callable, database_asset: GRDDatabaseAsset, cell_resource_stack: Dictionary) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

	var next_stack := cell_resource_stack.duplicate()
	var current_script: Script = current.get_script()
	if current_script != null:
		next_stack[current_script] = true

	var assignable_scripts: Array[Script] = _get_assignable_scripts(base_script)
	var type_select: OptionButton = null
	if assignable_scripts.size() > 1:
		type_select = OptionButton.new()
		var selected_idx: int = 0
		for i in assignable_scripts.size():
			var script: Script = assignable_scripts[i]
			var label: String = script.get_global_name()
			if label.is_empty():
				label = script.resource_path.get_file().get_basename()
			_add_text_option(type_select, label, i)
			type_select.set_item_metadata(i, script)
			if script == current_script:
				type_select.set_item_tooltip(i, _format_resource_summary(current))
				selected_idx = i
		type_select.selected = selected_idx
		type_select.tooltip_text = _format_resource_summary(current)
		type_select.item_selected.connect(func(idx: int) -> void:
			var selected_script: Script = type_select.get_item_metadata(idx)
			var created = selected_script.new()
			if created is Resource:
				current = created as Resource
				on_change.call(current)
				_rebuild_cell_resource_editor(container, col, base_script, current, on_change, database_asset, cell_resource_stack)
		)
		_style_cell_option(type_select)
		container.add_child(type_select)

	for child_col in _get_cell_resource_columns(current):
		var row: BoxContainer = VBoxContainer.new() if child_col.is_array() else HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label: Label = Label.new()
		label.text = child_col.get_display_name()
		if child_col.is_array():
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			label.custom_minimum_size.x = GRDTheme.scaled(90.0)
		GRDTheme.style_label(label, GRDTheme.FONT_SIZE_SMALL, GRDTheme.TEXT_MUTED)
		row.add_child(label)
		var editor: Control = create_cell_editor(child_col, current.get(String(child_col.name)), current, func(new_value: Variant) -> void:
			current.set(String(child_col.name), new_value)
			on_change.call(current)
			if assignable_scripts.size() > 1:
				var selected_text: String = _format_resource_summary(current)
				var selected_index: int = type_select.selected
				if selected_index >= 0:
					type_select.set_item_tooltip(selected_index, selected_text)
					type_select.tooltip_text = selected_text
		, database_asset, next_stack)
		editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(editor)
		container.add_child(row)


static func _get_cell_resource_columns(current: Resource) -> Array[GRDPropertyColumn]:
	var cols: Array[GRDPropertyColumn] = GRDPropertyColumn.from_resource(current)
	if not cols.is_empty():
		return cols
	var script: Script = current.get_script() if current != null else null
	return GRDPropertyColumn.from_script(script)


# ---------------------------------------------------------------------------
# Array editor (summary + edit button)
# ---------------------------------------------------------------------------

static func _create_array_editor(
	col: GRDPropertyColumn,
	value: Variant,
	resource: Resource,
	on_change: Callable,
	database_asset: GRDDatabaseAsset = null,
) -> Control:
	# Typed row-reference arrays use a compact list of row ID selects.
	if _is_row_reference_array(col, value) and database_asset != null:
		return _create_row_reference_array_inline(col, value, on_change, database_asset)

	# Structured typed Resource arrays → inline table editor.
	if _is_structured_array(col, value):
		return _create_structured_array_inline(col, value, resource, on_change, database_asset)

	# Untyped or unsupported arrays → summary + Edit (JSON popup).
	var box: HBoxContainer = HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var summary: Label = Label.new()
	summary.text = _array_summary(value, col)
	summary.tooltip_text = _array_detail(value)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.clip_text = true
	GRDTheme.style_label(summary, GRDTheme.FONT_SIZE, GRDTheme.TEXT_MUTED)
	box.add_child(summary)

	var edit_btn: Button = Button.new()
	edit_btn.text = "Edit"
	edit_btn.custom_minimum_size.y = _compact_control_height()
	edit_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(edit_btn)

	edit_btn.pressed.connect(func() -> void:
		_open_array_edit_popup(col, value, resource, on_change)
	)

	return box


## Opens a popup for editing an Array value.
## Shows a simple JSON-like text editor for the array.
static func _open_array_edit_popup(
	col: GRDPropertyColumn,
	value: Variant,
	resource: Resource,
	on_change: Callable,
) -> void:
	var popup: PopupPanel = PopupPanel.new()
	popup.title = "Edit %s" % col.get_display_name()
	popup.min_size = Vector2i(420, 300)

	var outer: VBoxContainer = VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	popup.add_child(outer)

	var info: Label = Label.new()
	info.text = "Edit the array value (JSON format)."
	GRDTheme.style_label(info, GRDTheme.FONT_SIZE_SMALL, GRDTheme.TEXT_MUTED)
	outer.add_child(info)

	var text_edit: TextEdit = TextEdit.new()
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_edit.text = JSON.stringify(value, "  ") if value != null else "[]"
	outer.add_child(text_edit)

	var status: Label = Label.new()
	status.add_theme_color_override("font_color", Color(1.0, 0.62, 0.38))
	outer.add_child(status)

	var buttons: HBoxContainer = HBoxContainer.new()
	outer.add_child(buttons)

	var apply_btn: Button = Button.new()
	apply_btn.text = "Apply"
	buttons.add_child(apply_btn)

	var cancel_btn: Button = Button.new()
	cancel_btn.text = "Cancel"
	buttons.add_child(cancel_btn)

	apply_btn.pressed.connect(func() -> void:
		var parsed: Variant = JSON.parse_string(text_edit.text)
		if parsed is Array:
			on_change.call(parsed)
			popup.queue_free()
		else:
			status.text = "Invalid JSON — must be an array."
	)
	cancel_btn.pressed.connect(func() -> void:
		popup.queue_free()
	)

	popup.popup_hide.connect(func() -> void:
		if popup.is_inside_tree():
			popup.queue_free()
	)

	var tree: SceneTree = Engine.get_main_loop()
	if tree != null and tree.root != null:
		tree.root.add_child(popup)
	popup.popup_centered(Vector2i(440, 380))


# ---------------------------------------------------------------------------
# Structured array editor (table UI for typed Resource arrays)
# ---------------------------------------------------------------------------

## Returns true when the array column has a resolved element_script and
## the element class has exported properties suitable for table editing.
static func _is_structured_array(col: GRDPropertyColumn, value: Variant) -> bool:
	var elem_script: Script = _resolve_structured_array_element_script(col, value)
	if elem_script == null:
		return false
	var elem_cols: Array[GRDPropertyColumn] = GRDPropertyColumn.from_script(elem_script)
	return elem_cols.size() > 0


## Infers the element Script from the first Resource element in an array.
static func _get_element_script_from_value(arr: Array) -> Script:
	for item in arr:
		if item is Resource:
			var scr: Script = (item as Resource).get_script()
			if scr != null:
				return scr
	return null


static func _resolve_structured_array_element_script(col: GRDPropertyColumn, value: Variant) -> Script:
	if value is Array:
		var concrete_script: Script = _get_element_script_from_value(value as Array)
		if concrete_script != null:
			return concrete_script
	return col.element_script


static func _is_row_reference_array(col: GRDPropertyColumn, value: Variant) -> bool:
	var elem_script: Script = _resolve_structured_array_element_script(col, value)
	return elem_script != null and _script_inherits_named(elem_script, "GRDRowSchema")


static func _create_row_reference_array_inline(
	col: GRDPropertyColumn,
	value: Variant,
	on_change: Callable,
	database_asset: GRDDatabaseAsset,
) -> Control:
	var elem_script: Script = _resolve_structured_array_element_script(col, value)
	var type_name: String = elem_script.get_global_name() if elem_script != null else ""
	var available_ids: PackedStringArray = _get_available_ids_for_type(database_asset, type_name)
	if type_name.is_empty() or available_ids.is_empty():
		return _create_array_editor_fallback(col, value, null, on_change)

	var working_elements: Array[Resource] = []
	if value is Array:
		for item in value as Array:
			if item is Resource:
				working_elements.append(item as Resource)

	var container: VBoxContainer = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rebuild_row_reference_array_inline(container, col, type_name, available_ids, working_elements, value, database_asset, on_change)
	return container


static func _emit_row_reference_array_change(working_elements: Array[Resource], template_value: Variant, on_change: Callable) -> void:
	var result: Array = template_value.duplicate() if template_value is Array else []
	result.clear()
	for elem in working_elements:
		if elem != null:
			result.append(elem)
	on_change.call(result)


static func _rebuild_row_reference_array_inline(
	container: VBoxContainer,
	col: GRDPropertyColumn,
	type_name: String,
	available_ids: PackedStringArray,
	working_elements: Array[Resource],
	template_value: Variant,
	database_asset: GRDDatabaseAsset,
	on_change: Callable,
) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

	for i in working_elements.size():
		var idx: int = i
		var row: HBoxContainer = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.add_child(row)

		var option: OptionButton = OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		option.custom_minimum_size.y = _compact_control_height()
		var current_id: String = _get_resource_id(working_elements[idx])
		var selected_idx: int = 0
		for id_i in available_ids.size():
			var id_value: String = available_ids[id_i]
			_add_row_reference_option(option, database_asset, type_name, id_value, id_i)
			option.set_item_metadata(id_i, id_value)
			if id_value == current_id:
				selected_idx = id_i
		option.selected = selected_idx
		_update_option_tooltip(option)
		option.item_selected.connect(func(selected: int) -> void:
			_update_option_tooltip(option)
			var selected_id: String = option.get_item_metadata(selected)
			var selected_resource: Resource = _find_resource_by_id(database_asset, type_name, selected_id)
			if selected_resource != null:
				working_elements[idx] = selected_resource
				_emit_row_reference_array_change(working_elements, template_value, on_change)
		)
		_style_cell_option(option)
		row.add_child(option)

		var remove_btn: Button = Button.new()
		remove_btn.text = "x"
		remove_btn.custom_minimum_size = Vector2(GRDTheme.scaled(28.0), _compact_control_height())
		GRDTheme.style_button(remove_btn)
		remove_btn.pressed.connect(func() -> void:
			working_elements.remove_at(idx)
			_rebuild_row_reference_array_inline(container, col, type_name, available_ids, working_elements, template_value, database_asset, on_change)
			_emit_row_reference_array_change(working_elements, template_value, on_change)
		)
		row.add_child(remove_btn)

	var add_row: HBoxContainer = HBoxContainer.new()
	add_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var add_btn: Button = Button.new()
	add_btn.text = "+ Add %s" % _array_item_label(col, _resolve_structured_array_element_script(col, template_value))
	add_btn.custom_minimum_size.y = _compact_control_height()
	GRDTheme.style_button(add_btn)
	add_btn.pressed.connect(func() -> void:
		var selected_resource: Resource = _find_resource_by_id(database_asset, type_name, available_ids[0])
		if selected_resource != null:
			working_elements.append(selected_resource)
			_rebuild_row_reference_array_inline(container, col, type_name, available_ids, working_elements, template_value, database_asset, on_change)
			_emit_row_reference_array_change(working_elements, template_value, on_change)
	)
	add_row.add_child(add_btn)
	container.add_child(add_row)


## Returns a summary string for structured arrays (e.g. "3 rows").
static func _structured_array_summary(value: Variant) -> String:
	if not (value is Array):
		return str(value) if value != null else "(null)"
	var arr: Array = value as Array
	if arr.is_empty():
		return "0 rows"
	var count: int = arr.size()
	return "%d row%s" % [count, "s" if count != 1 else ""]


## Creates an inline table editor for typed Resource arrays directly in the cell.
## Each row has editors for the element's properties; changes call on_change immediately.
static func _create_structured_array_inline(
	col: GRDPropertyColumn,
	value: Variant,
	resource: Resource,
	on_change: Callable,
	database_asset: GRDDatabaseAsset,
) -> Control:
	# Resolve element script.
	var elem_script: Script = _resolve_structured_array_element_script(col, value)
	if elem_script == null:
		return _create_array_editor_fallback(col, value, resource, on_change)

	var element_columns: Array[GRDPropertyColumn] = GRDPropertyColumn.from_script(elem_script)
	if element_columns.is_empty():
		return _create_array_editor_fallback(col, value, resource, on_change)

	# Working copy of elements — edits happen in-place on these.
	var working_elements: Array[Resource] = []
	if value is Array:
		for item in (value as Array):
			if item is Resource:
				working_elements.append((item as Resource).duplicate() as Resource)

	var container: VBoxContainer = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.custom_minimum_size.y = _inline_table_min_height()

	_rebuild_structured_array_inline(
		container, col, elem_script, working_elements, element_columns, value, database_asset, on_change,
	)
	return container


static func _emit_structured_array_change(
	working_elements: Array[Resource],
	template_value: Variant,
	on_change: Callable,
) -> void:
	var result: Array = template_value.duplicate() if template_value is Array else []
	result.clear()
	for elem in working_elements:
		result.append(elem)
	on_change.call(result)


static func _rebuild_structured_array_inline(
	container: VBoxContainer,
	col: GRDPropertyColumn,
	elem_script: Script,
	working_elements: Array[Resource],
	element_columns: Array[GRDPropertyColumn],
	template_value: Variant,
	database_asset: GRDDatabaseAsset,
	on_change: Callable,
) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	container.custom_minimum_size.y = 0.0
	container.update_minimum_size()

	if working_elements.is_empty():
		var empty_row: HBoxContainer = HBoxContainer.new()
		empty_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var empty_label: Label = Label.new()
		empty_label.text = "0 rows"
		empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		GRDTheme.style_label(empty_label, GRDTheme.FONT_SIZE_SMALL, GRDTheme.TEXT_MUTED)
		empty_row.add_child(empty_label)
		_add_inline_add_button(empty_row, col, elem_script, working_elements, container, element_columns, template_value, database_asset, on_change)
		container.add_child(empty_row)
		_queue_structured_array_layout_refresh(container)
		return

	if _uses_nested_cell_card_layout(element_columns):
		var item_label: String = _array_item_label(col, elem_script)
		for i in working_elements.size():
			var idx: int = i
			var elem: Resource = working_elements[idx]
			var on_move: Callable = func(from_index: int, to_index: int) -> void:
				if from_index < 0 or from_index >= working_elements.size():
					return
				if to_index < 0 or to_index >= working_elements.size() or from_index == to_index:
					return
				var moved: Resource = working_elements[from_index]
				working_elements.remove_at(from_index)
				working_elements.insert(to_index, moved)
				_rebuild_structured_array_inline(container, col, elem_script, working_elements, element_columns, template_value, database_asset, on_change)
				_emit_structured_array_change(working_elements, template_value, on_change)
			var on_remove: Callable = func() -> void:
				working_elements.remove_at(idx)
				_rebuild_structured_array_inline(container, col, elem_script, working_elements, element_columns, template_value, database_asset, on_change)
				_emit_structured_array_change(working_elements, template_value, on_change)
			var on_elem_changed: Callable = func() -> void:
				_emit_structured_array_change(working_elements, template_value, on_change)
			_build_structured_card_row(container, elem, element_columns, database_asset, item_label, idx, on_move, on_remove, on_elem_changed)

		var add_card_row: HBoxContainer = HBoxContainer.new()
		add_card_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_add_inline_add_button(add_card_row, col, elem_script, working_elements, container, element_columns, template_value, database_asset, on_change)
		container.add_child(add_card_row)
		_queue_structured_array_layout_refresh(container)
		return

	var grid: GridContainer = GridContainer.new()
	grid.columns = element_columns.size() + 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	container.add_child(grid)

	_build_structured_header(grid, element_columns)
	for i in working_elements.size():
		var idx: int = i
		var elem: Resource = working_elements[idx]
		var row_bg: Color = GRDTheme.BG if idx % 2 == 0 else GRDTheme.BG_ALT
		var on_move: Callable = func(from_index: int, to_index: int) -> void:
			if from_index < 0 or from_index >= working_elements.size():
				return
			if to_index < 0 or to_index >= working_elements.size() or from_index == to_index:
				return
			var moved: Resource = working_elements[from_index]
			working_elements.remove_at(from_index)
			working_elements.insert(to_index, moved)
			_rebuild_structured_array_inline(container, col, elem_script, working_elements, element_columns, template_value, database_asset, on_change)
			_emit_structured_array_change(working_elements, template_value, on_change)
		var on_remove: Callable = func() -> void:
			working_elements.remove_at(idx)
			_rebuild_structured_array_inline(container, col, elem_script, working_elements, element_columns, template_value, database_asset, on_change)
			_emit_structured_array_change(working_elements, template_value, on_change)
		var on_elem_changed: Callable = func() -> void:
			_emit_structured_array_change(working_elements, template_value, on_change)
		_build_structured_row(
			grid, elem, element_columns, database_asset, idx, on_move, on_remove, on_elem_changed, row_bg,
		)

	var add_row: HBoxContainer = HBoxContainer.new()
	add_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_inline_add_button(add_row, col, elem_script, working_elements, container, element_columns, template_value, database_asset, on_change)
	container.add_child(add_row)
	_queue_structured_array_layout_refresh(container)


## Appends a compact "+ Add Row" button to a container.
static func _add_inline_add_button(
	parent: HBoxContainer,
	col: GRDPropertyColumn,
	elem_script: Script,
	working_elements: Array[Resource],
	container: VBoxContainer,
	element_columns: Array[GRDPropertyColumn],
	template_value: Variant,
	database_asset: GRDDatabaseAsset,
	on_change: Callable,
) -> void:
	var add_btn: Button = Button.new()
	add_btn.text = "+ Add %s" % _array_item_label(col, elem_script) if _uses_nested_cell_card_layout(element_columns) else "+ Add Row"
	add_btn.custom_minimum_size.y = _compact_control_height()
	add_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	GRDTheme.style_button(add_btn)
	add_btn.pressed.connect(func() -> void:
		var new_elem = elem_script.new()
		if new_elem is Resource:
			working_elements.append(new_elem as Resource)
			_rebuild_structured_array_inline(container, col, elem_script, working_elements, element_columns, template_value, database_asset, on_change)
			_emit_structured_array_change(working_elements, template_value, on_change)
	)
	parent.add_child(add_btn)


static func _uses_nested_cell_card_layout(element_columns: Array[GRDPropertyColumn]) -> bool:
	for col in element_columns:
		if col.is_array() and col.element_script != null and _script_inherits_named(col.element_script, "GRDCellResource"):
			return true
		if col.is_resource_reference() and _is_cell_resource_type(col.get_resource_type()):
			return true
	return false


static func _array_item_label(col: GRDPropertyColumn, elem_script: Script) -> String:
	var label: String = String(col.name)
	if label.ends_with("ies"):
		label = label.substr(0, label.length() - 3) + "y"
	elif label.ends_with("s") and label.length() > 1:
		label = label.substr(0, label.length() - 1)
	elif elem_script != null and not elem_script.get_global_name().is_empty():
		label = elem_script.get_global_name().trim_suffix("Schema")
	return label.replace("_", " ").capitalize()


static func _build_structured_card_row(
	parent: VBoxContainer,
	elem: Resource,
	element_columns: Array[GRDPropertyColumn],
	database_asset: GRDDatabaseAsset,
	item_label: String,
	item_index: int,
	on_move: Callable,
	on_remove: Callable,
	on_element_changed: Callable,
) -> void:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var item_number: int = item_index + 1
	var is_even: bool = item_number % 2 == 0
	var card_bg: Color = GRDTheme.PANEL if is_even else GRDTheme.BG
	var card_border: Color = GRDTheme.BORDER.lightened(0.18 if is_even else 0.04)
	card.add_theme_stylebox_override(
		"panel",
		GRDTheme.panel_style(card_bg, card_border, 6, 8, 1),
	)
	parent.add_child(card)

	var wrap: HBoxContainer = HBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("separation", GRDTheme.scaled_int(6))
	card.add_child(wrap)

	var stripe: ColorRect = ColorRect.new()
	stripe.color = GRDTheme.ACCENT_DARK if is_even else GRDTheme.BORDER
	stripe.custom_minimum_size.x = GRDTheme.scaled(4.0)
	stripe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.add_child(stripe)

	var body: VBoxContainer = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", GRDTheme.scaled_int(6))
	wrap.add_child(body)

	var header: HBoxContainer = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(header)

	var drag_handle: StructuredRowDragHandle = StructuredRowDragHandle.new()
	drag_handle.owner_id = parent.get_instance_id()
	drag_handle.row_index = item_index
	drag_handle.on_move = on_move
	drag_handle.text = "☰"
	drag_handle.tooltip_text = "Drag to reorder %s" % item_label.to_lower()
	drag_handle.focus_mode = Control.FOCUS_NONE
	drag_handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	drag_handle.custom_minimum_size = Vector2(GRDTheme.scaled(24.0), _compact_control_height())
	drag_handle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	GRDTheme.style_button(drag_handle)
	header.add_child(drag_handle)

	var title: Label = Label.new()
	title.text = "%s %d" % [item_label, item_number]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GRDTheme.style_label(title, GRDTheme.FONT_SIZE_SMALL, GRDTheme.TEXT)
	header.add_child(title)

	var remove_btn: Button = Button.new()
	remove_btn.text = "×"
	remove_btn.focus_mode = Control.FOCUS_NONE
	remove_btn.custom_minimum_size = Vector2(GRDTheme.scaled(24.0), _compact_control_height())
	GRDTheme.style_button(remove_btn)
	remove_btn.pressed.connect(func() -> void:
		on_remove.call()
	)
	header.add_child(remove_btn)

	for ec in element_columns:
		var editor: Control = _create_structured_cell_editor(elem, ec, database_asset, on_element_changed)
		var row: BoxContainer = VBoxContainer.new() if ec.is_array() else HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var label: Label = Label.new()
		label.text = ec.get_display_name()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if ec.is_array() else Control.SIZE_SHRINK_BEGIN
		if not ec.is_array():
			label.custom_minimum_size.x = GRDTheme.scaled(110.0)
		GRDTheme.style_label(label, GRDTheme.FONT_SIZE_TINY, GRDTheme.TEXT_MUTED)
		row.add_child(label)

		editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(editor)
		body.add_child(row)


static func _queue_structured_array_layout_refresh(container: VBoxContainer) -> void:
	if container == null:
		return
	container.update_minimum_size()
	if container.get_parent() is Container:
		(container.get_parent() as Container).queue_sort()
	(func() -> void:
		if not is_instance_valid(container):
			return
		container.update_minimum_size()
		var parent := container.get_parent()
		if parent is Container:
			(parent as Container).queue_sort()
	).call_deferred()


## Fallback for arrays that can't use structured inline editing.
static func _create_array_editor_fallback(
	col: GRDPropertyColumn,
	value: Variant,
	resource: Resource,
	on_change: Callable,
) -> Control:
	var box: HBoxContainer = HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var summary: Label = Label.new()
	summary.text = _array_summary(value, col)
	summary.tooltip_text = _array_detail(value)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.clip_text = true
	GRDTheme.style_label(summary, GRDTheme.FONT_SIZE, GRDTheme.TEXT_MUTED)
	box.add_child(summary)

	var edit_btn: Button = Button.new()
	edit_btn.text = "Edit"
	edit_btn.custom_minimum_size.y = _compact_control_height()
	edit_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(edit_btn)

	edit_btn.pressed.connect(func() -> void:
		_open_array_edit_popup(col, value, resource, on_change)
	)

	return box


## Opens a popup with a table-based editor for typed Resource arrays.
static func _open_structured_array_popup(
	col: GRDPropertyColumn,
	value: Variant,
	resource: Resource,
	on_change: Callable,
	database_asset: GRDDatabaseAsset,
) -> void:
	# Resolve element script.
	var elem_script: Script = _resolve_structured_array_element_script(col, value)
	if elem_script == null:
		_open_array_edit_popup(col, value, resource, on_change)
		return

	var element_columns: Array[GRDPropertyColumn] = GRDPropertyColumn.from_script(elem_script)
	if element_columns.is_empty():
		_open_array_edit_popup(col, value, resource, on_change)
		return

	var popup: PopupPanel = PopupPanel.new()
	popup.title = "Edit %s" % col.get_display_name()
	popup.min_size = Vector2i(540, 380)

	var outer: VBoxContainer = VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	popup.add_child(outer)

	# Clone working elements (duplicate to avoid mutating originals until Apply).
	var working_elements: Array[Resource] = []
	if value is Array:
		for item in (value as Array):
			if item is Resource:
				working_elements.append((item as Resource).duplicate() as Resource)

	var rows_container: GridContainer = GridContainer.new()
	rows_container.columns = element_columns.size() + 2
	rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_container.add_theme_constant_override("h_separation", 0)
	rows_container.add_theme_constant_override("v_separation", 0)

	var rebuild_rows: Callable = func() -> void:
		_rebuild_structured_rows(rows_container, working_elements, element_columns, database_asset)

	_build_structured_header(rows_container, element_columns)

	# Scrollable table area.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows_container)
	outer.add_child(scroll)

	rebuild_rows.call()

	# Bottom bar: Add / Cancel / Apply.
	var bottom: HBoxContainer = HBoxContainer.new()
	outer.add_child(bottom)

	var add_btn: Button = Button.new()
	add_btn.text = "+ Add Row"
	GRDTheme.style_button(add_btn)
	add_btn.pressed.connect(func() -> void:
		var new_elem = elem_script.new()
		if new_elem is Resource:
			working_elements.append(new_elem as Resource)
			rebuild_rows.call()
	)
	bottom.add_child(add_btn)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)

	var cancel_btn: Button = Button.new()
	cancel_btn.text = "Cancel"
	GRDTheme.style_button(cancel_btn)
	cancel_btn.pressed.connect(func() -> void:
		popup.queue_free()
	)
	bottom.add_child(cancel_btn)

	var apply_btn: Button = Button.new()
	apply_btn.text = "Apply"
	GRDTheme.style_button(apply_btn, true)
	apply_btn.pressed.connect(func() -> void:
		var result: Array = []
		for elem in working_elements:
			result.append(elem)
		on_change.call(result)
		popup.queue_free()
	)
	bottom.add_child(apply_btn)

	popup.popup_hide.connect(func() -> void:
		if popup.is_inside_tree():
			popup.queue_free()
	)

	var tree: SceneTree = Engine.get_main_loop()
	if tree != null and tree.root != null:
		tree.root.add_child(popup)
	popup.popup_centered(Vector2i(540, 380))


## Appends structured table header cells to a GridContainer.
static func _build_structured_header(grid: GridContainer, element_columns: Array[GRDPropertyColumn]) -> void:
	var row_cells: Array[PanelContainer] = []
	var drag_spacer: Control = Control.new()
	drag_spacer.custom_minimum_size.y = _compact_control_height()
	var drag_spacer_wrapped: PanelContainer = _wrap_structured_cell(drag_spacer, GRDTheme.scaled_int(28), true)
	grid.add_child(drag_spacer_wrapped)
	row_cells.append(drag_spacer_wrapped)

	for ec in element_columns:
		var label: Label = Label.new()
		label.text = ec.get_display_name()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		label.custom_minimum_size.y = _compact_control_height()
		label.clip_text = false
		label.tooltip_text = ec.get_display_name()
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		GRDTheme.style_label(label, GRDTheme.FONT_SIZE_TINY, GRDTheme.TEXT_MUTED.lightened(0.08))
		label.add_theme_font_size_override("font_size", max(1, GRDTheme.font_size_tiny() - 3))
		var wrapped: PanelContainer = _wrap_structured_cell(label, _get_structured_col_width(ec), true)
		grid.add_child(wrapped)
		row_cells.append(wrapped)

	# Remove button column spacer.
	var spacer: Control = Control.new()
	spacer.custom_minimum_size.y = _compact_control_height()
	var spacer_wrapped: PanelContainer = _wrap_structured_cell(spacer, GRDTheme.scaled_int(28), true)
	grid.add_child(spacer_wrapped)
	row_cells.append(spacer_wrapped)
	_sync_structured_row_height(row_cells)


static func _rebuild_structured_rows(
	rows_container: GridContainer,
	working_elements: Array[Resource],
	element_columns: Array[GRDPropertyColumn],
	database_asset: GRDDatabaseAsset,
) -> void:
	for child in rows_container.get_children():
		rows_container.remove_child(child)
		child.queue_free()
	_build_structured_header(rows_container, element_columns)

	for i in working_elements.size():
		var idx: int = i
		var elem: Resource = working_elements[idx]
		var row_bg: Color = GRDTheme.BG if idx % 2 == 0 else GRDTheme.BG_ALT
		var on_move: Callable = func(from_index: int, to_index: int) -> void:
			if from_index < 0 or from_index >= working_elements.size():
				return
			if to_index < 0 or to_index >= working_elements.size() or from_index == to_index:
				return
			var moved: Resource = working_elements[from_index]
			working_elements.remove_at(from_index)
			working_elements.insert(to_index, moved)
			_rebuild_structured_rows(rows_container, working_elements, element_columns, database_asset)
		var on_remove: Callable = func() -> void:
			working_elements.remove_at(idx)
			_rebuild_structured_rows(rows_container, working_elements, element_columns, database_asset)
		_build_structured_row(
			rows_container, elem, element_columns, database_asset, idx, on_move, on_remove, Callable(), row_bg,
		)


## Appends a single structured table row to a GridContainer.
static func _build_structured_row(
	grid: GridContainer,
	elem: Resource,
	element_columns: Array[GRDPropertyColumn],
	database_asset: GRDDatabaseAsset,
	row_index: int,
	on_move: Callable,
	on_remove: Callable,
	on_element_changed: Callable = Callable(),
	bg: Color = GRDTheme.BG,
) -> void:
	var row_cells: Array[PanelContainer] = []
	var drag_handle: StructuredRowDragHandle = StructuredRowDragHandle.new()
	drag_handle.owner_id = grid.get_instance_id()
	drag_handle.row_index = row_index
	drag_handle.on_move = on_move
	drag_handle.text = "☰"
	drag_handle.tooltip_text = "Drag to reorder row"
	drag_handle.focus_mode = Control.FOCUS_NONE
	drag_handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	drag_handle.custom_minimum_size = Vector2(GRDTheme.scaled(24.0), _compact_control_height())
	drag_handle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	drag_handle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	GRDTheme.style_button(drag_handle)
	var drag_wrapped: PanelContainer = _wrap_structured_cell(drag_handle, GRDTheme.scaled_int(28), false, bg)
	grid.add_child(drag_wrapped)
	row_cells.append(drag_wrapped)

	for ec in element_columns:
		var cell: Control = _create_structured_cell_editor(elem, ec, database_asset, on_element_changed)
		var wrapped: PanelContainer = _wrap_structured_cell(cell, _get_structured_col_width(ec), false, bg)
		grid.add_child(wrapped)
		row_cells.append(wrapped)

	# Remove button.
	var remove_btn: Button = Button.new()
	remove_btn.text = "×"
	remove_btn.focus_mode = Control.FOCUS_NONE
	remove_btn.custom_minimum_size = Vector2(GRDTheme.scaled(24.0), _compact_control_height())
	remove_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	remove_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	GRDTheme.style_button(remove_btn)
	remove_btn.pressed.connect(func() -> void:
		on_remove.call()
	)
	var remove_wrapped: PanelContainer = _wrap_structured_cell(remove_btn, GRDTheme.scaled_int(28), false, bg)
	grid.add_child(remove_wrapped)
	row_cells.append(remove_wrapped)
	_sync_structured_row_height(row_cells)


static func _wrap_structured_cell(child: Control, width: int, is_header: bool, bg: Color = GRDTheme.BG) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.custom_minimum_size.y = _structured_row_height()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = float(width)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		"panel",
		GRDTheme.panel_style(
			GRDTheme.HEADER if is_header else bg,
			GRDTheme.BORDER,
			3 if is_header else 2,
			5 if is_header else 1,
			1,
		),
	)
	child.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if width <= GRDTheme.scaled_int(32) else Control.SIZE_EXPAND_FILL
	child.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	child.custom_minimum_size.y = max(child.custom_minimum_size.y, _compact_control_height())
	panel.add_child(child)
	return panel


static func _sync_structured_row_height(row_cells: Array[PanelContainer]) -> void:
	var height: float = float(_structured_row_height())
	for panel in row_cells:
		if panel.get_child_count() > 0:
			var child := panel.get_child(0) as Control
			if child != null:
				height = max(height, child.get_combined_minimum_size().y)
	for panel in row_cells:
		panel.custom_minimum_size.y = height


static func _structured_row_height() -> int:
	return GRDTheme.scaled_int(STRUCTURED_ROW_HEIGHT)


static func _inline_table_min_height() -> int:
	return GRDTheme.scaled_int(INLINE_TABLE_MIN_HEIGHT)


## Creates an inline editor for a single property within a structured array row.
static func _create_structured_cell_editor(
	elem: Resource,
	col: GRDPropertyColumn,
	database_asset: GRDDatabaseAsset,
	on_element_changed: Callable = Callable(),
) -> Control:
	var prop_name: String = String(col.name)
	var current_value: Variant = elem.get(prop_name) if elem.has_method("get") else null

	# Resource reference → ID select (OptionButton).
	if col.is_resource_reference() and database_asset != null:
		if _is_row_schema_type(col.get_resource_type()):
			return _create_id_select_editor(elem, col, current_value, database_asset, on_element_changed)
		if _is_cell_resource_type(col.get_resource_type()):
			return _create_structured_cell_resource_editor(elem, col, current_value, database_asset, on_element_changed)

	# Enum → OptionButton.
	if col.is_enum():
		return _create_structured_enum_editor(elem, col, prop_name, current_value, on_element_changed)

	# Scalar types.
	if col.is_bool():
		return _create_structured_bool_editor(elem, prop_name, current_value, on_element_changed)
	if col.is_numeric():
		return _create_structured_numeric_editor(elem, col, prop_name, current_value, on_element_changed)
	if col.is_file_path() or col.is_global_file_path():
		return _create_structured_file_path_editor(elem, col, prop_name, current_value, on_element_changed)
	if col.is_string_like():
		return _create_structured_string_editor(elem, col, prop_name, current_value, on_element_changed)
	if col.is_array():
		return _create_array_editor(col, current_value, elem, func(new_value: Variant) -> void:
			elem.set(prop_name, new_value)
			if on_element_changed.is_valid():
				on_element_changed.call()
		, database_asset)

	# Fallback: read-only.
	return read_only_label(str(current_value) if current_value != null else "")


static func _create_structured_cell_resource_editor(elem: Resource, col: GRDPropertyColumn, current_value: Variant, database_asset: GRDDatabaseAsset, on_element_changed: Callable = Callable()) -> Control:
	return _create_cell_resource_editor(col, current_value, func(new_value: Variant) -> void:
		elem.set(String(col.name), new_value)
		if on_element_changed.is_valid():
			on_element_changed.call()
	, database_asset)


# ---------------------------------------------------------------------------
# Structured row cell editors
# ---------------------------------------------------------------------------

static func _create_structured_bool_editor(
	elem: Resource, prop_name: String, current_value: Variant,
	on_element_changed: Callable = Callable(),
) -> Control:
	var check: CheckBox = CheckBox.new()
	check.add_theme_font_size_override("font_size", GRDTheme.FONT_SIZE)
	check.add_theme_color_override("font_color", GRDTheme.TEXT)
	check.button_pressed = bool(current_value) if current_value != null else false
	check.text = ""
	check.custom_minimum_size.y = _compact_control_height()
	check.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	check.toggled.connect(func(pressed: bool) -> void:
		elem.set(prop_name, pressed)
		if on_element_changed.is_valid():
			on_element_changed.call()
	)
	return check


static func _create_structured_numeric_editor(
	elem: Resource, col: GRDPropertyColumn, prop_name: String, current_value: Variant,
	on_element_changed: Callable = Callable(),
) -> Control:
	var spin: SpinBox = SpinBox.new()
	GRDTheme.style_spinbox(spin)
	spin.min_value = -999999999
	spin.max_value = 999999999
	if col.type == TYPE_FLOAT:
		spin.step = 0.01
		spin.value = float(current_value) if current_value != null else 0.0
	else:
		spin.step = 1
		spin.value = int(current_value) if current_value != null else 0
	spin.custom_minimum_size = Vector2(GRDTheme.scaled(80.0), _compact_control_height())
	spin.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	spin.value_changed.connect(func(val: float) -> void:
		if col.type == TYPE_FLOAT:
			elem.set(prop_name, val)
		else:
			elem.set(prop_name, int(val))
		if on_element_changed.is_valid():
			on_element_changed.call()
	)
	return spin


static func _create_structured_string_editor(
	elem: Resource, col: GRDPropertyColumn, prop_name: String, current_value: Variant,
	on_element_changed: Callable = Callable(),
) -> Control:
	var edit: LineEdit = LineEdit.new()
	GRDTheme.style_input(edit)
	edit.text = str(current_value) if current_value != null else ""
	_sync_line_edit_tooltip(edit)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit.custom_minimum_size.y = _compact_control_height()
	edit.text_changed.connect(func(_new_text: String) -> void:
		_sync_line_edit_tooltip(edit)
	)
	edit.text_submitted.connect(func(new_text: String) -> void:
		if col.type == TYPE_STRING_NAME:
			elem.set(prop_name, StringName(new_text))
		else:
			elem.set(prop_name, new_text)
		if on_element_changed.is_valid():
			on_element_changed.call()
		edit.release_focus()
	)
	edit.focus_exited.connect(func() -> void:
		var current: String = edit.text
		if col.type == TYPE_STRING_NAME:
			elem.set(prop_name, StringName(current))
		else:
			elem.set(prop_name, current)
		if on_element_changed.is_valid():
			on_element_changed.call()
	)
	return edit


static func _create_structured_file_path_editor(
	elem: Resource, col: GRDPropertyColumn, prop_name: String, current_value: Variant,
	on_element_changed: Callable = Callable(),
) -> Control:
	var stored_value: String = str(current_value) if current_value != null else ""
	var edit: LineEdit = LineEdit.new()
	GRDTheme.style_input(edit)
	edit.text = _file_path_display_value(col, stored_value)
	_sync_file_path_tooltip(edit, col, stored_value)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit.custom_minimum_size.y = _compact_control_height()
	edit.text_changed.connect(func(_new_text: String) -> void:
		_sync_file_path_tooltip(edit, col, _file_path_storage_value(col, edit.text))
	)
	var commit := func(new_text: String) -> void:
		stored_value = _file_path_storage_value(col, new_text)
		edit.text = _file_path_display_value(col, stored_value)
		_sync_file_path_tooltip(edit, col, stored_value)
		elem.set(prop_name, stored_value)
		if on_element_changed.is_valid():
			on_element_changed.call()
		edit.release_focus()
	edit.text_submitted.connect(commit)
	edit.focus_exited.connect(func() -> void:
		var next_value: String = _file_path_storage_value(col, edit.text)
		if next_value != stored_value:
			commit.call(edit.text)
	)
	return edit


static func _sync_line_edit_tooltip(edit: LineEdit) -> void:
	edit.tooltip_text = edit.text


static func _create_structured_enum_editor(
	elem: Resource, col: GRDPropertyColumn, prop_name: String, current_value: Variant,
	on_element_changed: Callable = Callable(),
) -> Control:
	var opts: PackedStringArray = col.get_enum_values()
	var option: OptionButton = OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	option.custom_minimum_size.y = _compact_control_height()

	var current_str: String = str(current_value) if current_value != null else ""
	var selected_idx: int = 0
	var found_match: bool = false

	for j in opts.size():
		var opt_idx: int = option.get_item_count()
		_add_text_option(option, opts[j], opt_idx)
		option.set_item_metadata(opt_idx, opts[j])
		if opts[j] == current_str:
			selected_idx = opt_idx
			found_match = true

	if current_str != "" and not found_match:
		var opt_idx: int = option.get_item_count()
		_add_text_option(option, "%s (custom)" % current_str, opt_idx)
		option.set_item_metadata(opt_idx, current_str)
		selected_idx = opt_idx

	option.selected = selected_idx
	_update_option_tooltip(option)
	option.item_selected.connect(func(idx: int) -> void:
		_update_option_tooltip(option)
		elem.set(prop_name, option.get_item_metadata(idx))
		if on_element_changed.is_valid():
			on_element_changed.call()
	)
	_style_cell_option(option)
	return option


## Creates an OptionButton populated with IDs from matching tables for a
## Resource reference property (e.g. stat: StatsSchema → IDs from stats table).
static func _create_id_select_editor(
	elem: Resource,
	col: GRDPropertyColumn,
	current_value: Variant,
	database_asset: GRDDatabaseAsset,
	on_element_changed: Callable = Callable(),
) -> Control:
	var type_name: String = col.get_resource_type()
	var available_ids: PackedStringArray = _get_available_ids_for_type(database_asset, type_name)

	var option: OptionButton = OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	option.custom_minimum_size.y = _compact_control_height()

	# Add empty / unlinked option.
	var empty_idx: int = option.get_item_count()
	_add_text_option(option, "(none)", empty_idx)
	option.set_item_metadata(empty_idx, "")

	# Determine current ID for pre-selection.
	var current_id: String = ""
	if current_value is Resource:
		current_id = _get_resource_id(current_value as Resource)

	var selected_idx: int = 0

	for j in available_ids.size():
		var opt_idx: int = option.get_item_count()
		_add_row_reference_option(option, database_asset, type_name, available_ids[j], opt_idx)
		option.set_item_metadata(opt_idx, available_ids[j])
		if available_ids[j] == current_id:
			selected_idx = opt_idx

	option.selected = selected_idx
	_update_option_tooltip(option)
	option.item_selected.connect(func(idx: int) -> void:
		_update_option_tooltip(option)
		var selected_id: String = option.get_item_metadata(idx)
		var selected_resource: Resource = null
		if selected_id.is_empty():
			elem.set(String(col.name), null)
		else:
			var found: Resource = _find_resource_by_id(database_asset, type_name, selected_id)
			if found != null:
				selected_resource = found
				elem.set(String(col.name), found)
		if on_element_changed.is_valid():
			on_element_changed.call()
	)
	_style_cell_option(option)
	return option


# ---------------------------------------------------------------------------
# Structured array helpers
# ---------------------------------------------------------------------------

static func _get_structured_col_width(ec: GRDPropertyColumn) -> int:
	var header_width: int = _structured_header_width(ec)
	return max(GRDTheme.scaled_int(STRUCTURED_COL_WIDTH), header_width)


static func _structured_header_width(ec: GRDPropertyColumn) -> int:
	return GRDTheme.scaled_int(ec.get_display_name().length() * STRUCTURED_HEADER_CHAR_WIDTH + STRUCTURED_HEADER_PADDING)


## Returns all IDs from tables whose row_script global name matches type_name.
static func _get_available_ids_for_type(
	db_asset: GRDDatabaseAsset, type_name: String,
) -> PackedStringArray:
	var cache: Dictionary = _get_reference_cache(db_asset, type_name)
	return cache.get("ids", PackedStringArray())


static func _get_reference_cache(db_asset: GRDDatabaseAsset, type_name: String) -> Dictionary:
	if db_asset == null or type_name.is_empty():
		return {"ids": PackedStringArray(), "by_id": {}}

	var cache_key: String = "%d:%s" % [db_asset.get_instance_id(), type_name]
	if _reference_cache.has(cache_key):
		return _reference_cache[cache_key]

	var ids: PackedStringArray = PackedStringArray()
	var by_id: Dictionary = {}
	for ta in db_asset.tables:
		if ta == null or ta.row_script == null:
			continue
		var script_name: String = ta.row_script.get_global_name()
		if script_name == type_name:
			var id_field: StringName = ta.get_id_field()
			for row_res in ta.rows:
				if row_res != null and row_res.has_method("get"):
					var id_val = row_res.get(String(id_field))
					if id_val != null and not str(id_val).is_empty():
						var id_string: String = str(id_val)
						ids.append(id_string)
						by_id[id_string] = row_res
	var cache: Dictionary = {"ids": ids, "by_id": by_id}
	_reference_cache[cache_key] = cache
	return cache


## Finds a Resource instance by type and ID across all matching tables.
static func _find_resource_by_id(
	db_asset: GRDDatabaseAsset, type_name: String, id_value: String,
) -> Resource:
	if id_value.is_empty():
		return null
	var cache: Dictionary = _get_reference_cache(db_asset, type_name)
	var by_id: Dictionary = cache.get("by_id", {})
	return by_id.get(id_value, null) as Resource


## Reads the id property from a Resource instance.
static func _get_resource_id(res: Resource, id_field: StringName = &"id") -> String:
	if res == null:
		return ""
	if res.has_method("get"):
		var val = res.get(String(id_field))
		if val != null:
			return str(val)
	return ""


static func _add_row_reference_option(option: OptionButton, db_asset: GRDDatabaseAsset, type_name: String, id_value: String, opt_idx: int) -> void:
	var icon: Texture2D = _get_row_reference_icon_thumbnail(_find_resource_by_id(db_asset, type_name, id_value))
	if icon != null:
		option.add_icon_item(icon, _ellipsize(id_value, ICON_SELECT_LABEL_MAX_CHARS), opt_idx)
	else:
		option.add_item(_ellipsize(id_value, SELECT_LABEL_MAX_CHARS), opt_idx)
	option.set_item_tooltip(opt_idx, id_value)


static func _add_text_option(option: OptionButton, text: String, opt_idx: int) -> void:
	option.add_item(_ellipsize(text, SELECT_LABEL_MAX_CHARS), opt_idx)
	option.set_item_tooltip(opt_idx, text)


static func _style_cell_option(option: OptionButton) -> void:
	GRDTheme.style_option(option)
	option.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


static func _update_option_tooltip(option: OptionButton) -> void:
	if option.selected >= 0:
		option.tooltip_text = option.get_item_tooltip(option.selected)


static func _ellipsize(text: String, max_chars: int) -> String:
	if text.length() <= max_chars:
		return text
	return text.left(max_chars - 1) + "…"


static func _get_row_reference_icon_thumbnail(row_resource: Resource) -> Texture2D:
	if row_resource == null:
		return null
	var icon_value: Variant = row_resource.get(String(DEFAULT_ROW_REFERENCE_ICON_PROPERTY))
	if not (icon_value is Texture2D):
		return null
	return _make_icon_thumbnail(icon_value as Texture2D)


static func _make_icon_thumbnail(texture: Texture2D) -> Texture2D:
	var cache_key: int = texture.get_instance_id()
	if _thumbnail_cache.has(cache_key):
		return _thumbnail_cache[cache_key]
	var image: Image = texture.get_image()
	if image == null:
		return texture
	var icon_size := GRDTheme.scaled_int(ROW_REFERENCE_ICON_SIZE)
	image.resize(icon_size, icon_size, Image.INTERPOLATE_LANCZOS)
	var thumbnail := ImageTexture.create_from_image(image)
	_thumbnail_cache[cache_key] = thumbnail
	return thumbnail


static func _is_row_schema_type(type_name: String) -> bool:
	var script: Script = GRDPropertyColumn._resolve_class_script(type_name)
	return _script_inherits_named(script, "GRDRowSchema")


static func _is_cell_resource_type(type_name: String) -> bool:
	var script: Script = GRDPropertyColumn._resolve_class_script(type_name)
	return _script_inherits_named(script, "GRDCellResource")


static func _get_assignable_scripts(base_script: Script) -> Array[Script]:
	var cache_key: String = base_script.resource_path if base_script != null else ""
	if _assignable_scripts_cache.has(cache_key):
		return _assignable_scripts_cache[cache_key]

	var scripts: Array[Script] = []
	if base_script != null:
		scripts.append(base_script)
	for gcls in ProjectSettings.get_global_class_list():
		var path: String = gcls.get("path", "")
		if path.is_empty():
			continue
		var loaded = load(path)
		if loaded is Script and loaded != base_script and _script_inherits_script(loaded as Script, base_script):
			scripts.append(loaded as Script)
	_assignable_scripts_cache[cache_key] = scripts
	return scripts


static func _script_inherits_named(script: Script, class_name_value: String) -> bool:
	while script != null:
		if script.get_global_name() == class_name_value:
			return true
		script = script.get_base_script()
	return false


static func _script_inherits_script(script: Script, base_script: Script) -> bool:
	while script != null:
		if script == base_script:
			return true
		script = script.get_base_script()
	return false


# ---------------------------------------------------------------------------
# Read-only helpers
# ---------------------------------------------------------------------------

## Creates a read-only label control for a cell value.
static func read_only_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.tooltip_text = text
	GRDTheme.style_label(label, GRDTheme.FONT_SIZE, GRDTheme.TEXT_MUTED)
	return label


# ---------------------------------------------------------------------------
# Summary / display helpers
# ---------------------------------------------------------------------------

## Shared core: builds a compact, useful summary for a Variant value.
## Shows script class names for Resources, exported properties for
## GRDCellResource instances, id fields for referenced resources, and
## truncated array summaries. `seen` prevents infinite recursion from cycles.
static func _format_resource_summary(value: Variant, seen: Dictionary = {}) -> String:
	if value == null:
		return "(null)"
	if value is Resource:
		var r: Resource = value as Resource
		var class_label: String = _resource_display_name(r)
		# GRDCellResource → class name + exported properties.
		if r is GRDCellResource:
			var instance_id: int = r.get_instance_id()
			if seen.has(instance_id):
				return "%s[cycle]" % class_label
			seen[instance_id] = true
			var props: String = _cell_resource_props_summary(r, seen)
			seen.erase(instance_id)
			if props != "":
				return "%s(%s)" % [class_label, props]
			return class_label
		# Non-cell resources with an id field → show id.
		var id_val: String = _get_resource_id(r)
		if not id_val.is_empty():
			return id_val
		# Fallback: resource_name / path / class.
		var rname: String = r.resource_name if r.resource_name != "" else ""
		var rpath: String = r.resource_path if r.resource_path != "" else ""
		if rname != "" and rpath != "":
			return "%s (%s)" % [rname, rpath.get_file()]
		elif rname != "":
			return rname
		elif rpath != "":
			return rpath.get_file()
		else:
			return "[%s]" % r.get_class()
	return str(value)


## Returns the best display name for a Resource, preferring script global name.
static func _resource_display_name(r: Resource) -> String:
	var scr: Script = r.get_script()
	if scr != null:
		var gn: String = scr.get_global_name()
		if not gn.is_empty():
			return gn
	if r.resource_name != "":
		return r.resource_name
	if r.resource_path != "":
		return r.resource_path.get_file()
	return r.get_class()


## Builds a compact exported-property summary for a GRDCellResource.
## Example output: stats=[...], flat=0.0, percent=0.1
static func _cell_resource_props_summary(r: Resource, seen: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var cols: Array[GRDPropertyColumn] = _get_cell_resource_columns(r)
	for col in cols:
		var val: Variant = r.get(String(col.name)) if r.has_method("get") else null
		var val_str: String = _summarize_property_value(val, col, seen)
		parts.append("%s=%s" % [String(col.name), val_str])
	return ", ".join(parts)


## Summarizes a single property value for compact display within a
## GRDCellResource property list.
static func _summarize_property_value(value: Variant, col: GRDPropertyColumn, seen: Dictionary) -> String:
	if value == null:
		return "null"
	# Resource reference → show id if available, else full summary.
	if col.is_resource_reference() and value is Resource:
		var r: Resource = value as Resource
		var id_val: String = _get_resource_id(r)
		if not id_val.is_empty():
			return id_val
		return _format_resource_summary(r, seen)
	# Typed array → compact element summary.
	if col.is_array() and value is Array:
		return _compact_array_summary(value as Array, seen)
	# Scalar types.
	if col.is_bool():
		return "true" if bool(value) else "false"
	if col.is_numeric():
		return str(value)
	if col.is_string_like():
		var s: String = str(value)
		return s if s.length() <= 24 else s.substr(0, 24) + "…"
	# Dictionary / fallback.
	if col.is_dictionary() and value is Dictionary:
		return "Dict{%d}" % (value as Dictionary).size()
	return str(value)


## Compact array summary for property display within GRDCellResource.
static func _compact_array_summary(arr: Array, seen: Dictionary) -> String:
	if arr.is_empty():
		return "[]"
	var parts: PackedStringArray = PackedStringArray()
	var limit: int = mini(arr.size(), 3)
	for i in limit:
		var item: Variant = arr[i]
		if item is Resource:
			parts.append(_format_resource_summary(item, seen))
		else:
			var s: String = str(item)
			if s.length() > 16:
				s = s.substr(0, 16) + "…"
			parts.append(s)
	var result: String = "[%s]" % ", ".join(parts)
	if arr.size() > limit:
		result += " +%d" % (arr.size() - limit)
	return result


## Backward-compatible private wrapper — delegates to shared core.
static func _resource_summary(value: Variant) -> String:
	return _format_resource_summary(value)


static func _dict_summary(value: Variant) -> String:
	if value is Dictionary:
		return "Dict{%d}" % (value as Dictionary).size()
	return str(value) if value != null else "(null)"


static func _array_summary(value: Variant, col: GRDPropertyColumn) -> String:
	if not (value is Array):
		return str(value) if value != null else "(null)"
	var arr: Array = value as Array
	if arr.is_empty():
		return "[]"
	# Summarize first few elements.
	var parts: PackedStringArray = PackedStringArray()
	var limit: int = mini(arr.size(), 3)
	for i in limit:
		var item: Variant = arr[i]
		if item is Resource:
			parts.append(_resource_summary(item))
		else:
			var s: String = str(item)
			if s.length() > 20:
				s = s.substr(0, 20) + "..."
			parts.append(s)
	var summary: String = "[%s]" % ", ".join(parts)
	if arr.size() > limit:
		summary += " +%d" % (arr.size() - limit)
	return summary


static func _array_detail(value: Variant) -> String:
	if not (value is Array):
		return str(value) if value != null else ""
	return JSON.stringify(value, "  ")


# ---------------------------------------------------------------------------
# Public utility helpers (used by spreadsheet and other UI)
# ---------------------------------------------------------------------------

static func _compact_control_height() -> int:
	return GRDTheme.control_height()


static func _resource_picker_height(value: Variant = null, base_type: String = "") -> int:
	var is_texture_type := base_type == "Texture2D" \
		or (not base_type.is_empty() and ClassDB.is_parent_class(base_type, "Texture2D"))
	if value is Texture2D or is_texture_type:
		return max(GRDTheme.control_height(), GRDTheme.scaled_int(TEXTURE_RESOURCE_CELL_HEIGHT))
	return GRDTheme.control_height()


## Returns a human-readable summary of a Resource value.
static func resource_summary(value: Variant) -> String:
	return _format_resource_summary(value)


## Returns a human-readable summary of a value for search/display.
static func value_summary(value: Variant, vtype: int) -> String:
	match vtype:
		TYPE_ARRAY:
			var arr: Array = value as Array
			return "Array[%d]" % arr.size()
		TYPE_DICTIONARY:
			var dict: Dictionary = value as Dictionary
			return "Dict{%d}" % dict.size()
		TYPE_OBJECT:
			return resource_summary(value)
		_:
			return str(value)
