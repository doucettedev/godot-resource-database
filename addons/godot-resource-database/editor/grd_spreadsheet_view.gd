@tool
class_name GRDSpreadsheetView
extends VBoxContainer

## Spreadsheet-like table view that renders GRDRow data in a grid with
## inline cell editors.  Resource-first architecture only: columns are
## derived from GRDPropertyColumn via row_script exported properties.
## Provides visible-cell text search, row selection, and a cell_changed
## signal for dirty tracking.

signal cell_changed(row_index: int, key: StringName, new_value: Variant)
signal row_selected(row_index: int)
signal row_delete_requested(row_index: int)
signal row_move_requested(from_index: int, to_index: int)


class RowDragHandle:
	extends Button

	var view: GRDSpreadsheetView
	var row_index: int = -1

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if view == null or row_index < 0:
			return null
		var preview := Label.new()
		preview.text = "Move row %d" % row_index
		GRDTheme.style_label(preview, GRDTheme.FONT_SIZE_SMALL, GRDTheme.TEXT)
		set_drag_preview(preview)
		return {
			"type": "grd_row",
			"table_asset": view._table_asset,
			"from_index": row_index,
		}

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		if view == null or not (data is Dictionary) or row_index < 0:
			return false
		var drag_data: Dictionary = data
		return drag_data.get("type", "") == "grd_row" \
			and drag_data.get("table_asset", null) == view._table_asset \
			and int(drag_data.get("from_index", -1)) != row_index

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if _can_drop_data(_at_position, data):
			var drag_data: Dictionary = data
			view.row_move_requested.emit(int(drag_data.get("from_index", -1)), row_index)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Column definitions.  Each dictionary contains:
##   "key"        : StringName  – property name
##   "display"    : String      – header label
##   "width"      : int         – minimum pixel width
##   "read_only"  : bool
##   "sticky"     : bool        – stays visible during horizontal scroll
##   "is_id"      : bool
##   "is_declared": bool        – true when ANY row declares this prop (hint only)
##   "property_column": GRDPropertyColumn or null  (resource-first mode)
var _columns: Array[Dictionary] = []
var _rows: Array[GRDRow] = []
var _filtered_indices: Array[int] = []
var _search_text: String = ""
var _id_field: StringName = &"id"
var _table_asset: GRDTableAsset = null
var _selected_filtered_idx: int = -1
var _property_columns: Array[GRDPropertyColumn] = []
var _database_asset: GRDDatabaseAsset = null
var _rebuild_generation: int = 0

# Cell panel references grouped by filtered row for selection highlighting.
var _row_panels: Array[Array] = []

const _ROW_NUMBER_WIDTH: int = 98
const _CELL_SEPARATION: int = 0
const _DEFAULT_COL_WIDTH: int = 150
const _ROW_MIN_HEIGHT: int = 42
const _STICKY_COLUMN_Z_INDEX: int = 10
const _STICKY_HEADER_Z_INDEX: int = 20
const _STICKY_COLUMN_HEADER_Z_INDEX: int = 30
const _ROWS_PER_BUILD_CHUNK: int = 1

# ---------------------------------------------------------------------------
# UI references (built in _ready)
# ---------------------------------------------------------------------------

var _row_count_label: Label
var _body_scroll: ScrollContainer
var _body: GridContainer
var _sticky_cells: Array[Dictionary] = []


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	_row_count_label = Label.new()
	_row_count_label.text = "0 rows"
	GRDTheme.style_label(_row_count_label, GRDTheme.FONT_SIZE_SMALL, GRDTheme.TEXT_MUTED)
	add_child(_row_count_label)

	_body_scroll = ScrollContainer.new()
	_body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_body_scroll)

	_body = GridContainer.new()
	_body.add_theme_constant_override("h_separation", 0)
	_body.add_theme_constant_override("v_separation", 0)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_body_scroll.add_child(_body)
	_body_scroll.get_h_scroll_bar().value_changed.connect(_on_horizontal_scroll_changed)
	_body_scroll.get_v_scroll_bar().value_changed.connect(_on_vertical_scroll_changed)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Sets the data for this spreadsheet view and rebuilds the grid.
func set_data(
	columns: Array[Dictionary],
	rows: Array[GRDRow],
	table_asset: GRDTableAsset,
	property_columns: Array[GRDPropertyColumn] = [],
	database_asset: GRDDatabaseAsset = null,
) -> void:
	_columns = columns
	_rows = rows
	_table_asset = table_asset
	_property_columns = property_columns
	_database_asset = database_asset
	_id_field = &"id"
	if table_asset != null and table_asset.id_field != &"":
		_id_field = table_asset.id_field
	_filtered_indices.clear()
	_selected_filtered_idx = -1
	_search_text = ""
	_rebuild_grid()


## Updates the visible-cell search filter and rebuilds.
func set_search(query: String) -> void:
	_search_text = query.strip_edges().to_lower()
	_rebuild_grid()


## Returns the filtered-row index of the selected row, or -1.
func get_selected_filtered_index() -> int:
	return _selected_filtered_idx


## Returns the real (unfiltered) row index of the selected row, or -1.
func get_selected_row_index() -> int:
	if _selected_filtered_idx >= 0 and _selected_filtered_idx < _filtered_indices.size():
		return _filtered_indices[_selected_filtered_idx]
	return -1


## Rebuilds the grid from current data.
func refresh() -> void:
	_rebuild_grid()


## Re-syncs row panel minimum heights from current cell content sizes.
## Deferred to the next frame so texture previews and resource pickers
## have settled their minimum sizes before measurement.
func refresh_row_heights() -> void:
	call_deferred("_deferred_sync_all_row_heights")
	call_deferred("_deferred_sync_all_row_heights_after_frame")


func _deferred_sync_all_row_heights_after_frame() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	_deferred_sync_all_row_heights()


func _deferred_sync_all_row_heights() -> void:
	if not is_inside_tree():
		return
	for row_cells in _row_panels:
		_sync_panel_row_min_height(row_cells)
	_body.queue_sort()
	_refresh_sticky_cell_positions()
	call_deferred("_refresh_sticky_cell_positions")


## Clears all data and UI.
func clear() -> void:
	_columns.clear()
	_rows.clear()
	_filtered_indices.clear()
	_selected_filtered_idx = -1
	_table_asset = null
	_database_asset = null
	_rebuild_grid()


# ---------------------------------------------------------------------------
# Grid rebuild
# ---------------------------------------------------------------------------

func _rebuild_grid() -> void:
	_rebuild_generation += 1
	var rebuild_generation: int = _rebuild_generation
	var profile_start_ms: int = Time.get_ticks_msec()
	# Clear existing UI nodes.
	var clear_start_ms: int = Time.get_ticks_msec()
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_row_panels.clear()
	_sticky_cells.clear()
	var clear_ms: int = Time.get_ticks_msec() - clear_start_ms

	var filter_start_ms: int = Time.get_ticks_msec()
	_filter_rows()
	var filter_ms: int = Time.get_ticks_msec() - filter_start_ms
	_row_count_label.text = "%d / %d rows" % [_filtered_indices.size(), _rows.size()]
	_body.columns = _columns.size() + 1

	var header_start_ms: int = Time.get_ticks_msec()
	_build_header()
	var header_ms: int = Time.get_ticks_msec() - header_start_ms

	if _filtered_indices.is_empty():
		call_deferred("_refresh_sticky_cell_positions")
		return

	_build_rows_chunked(rebuild_generation, Time.get_ticks_msec(), profile_start_ms, clear_ms, filter_ms, header_ms)


func _build_rows_chunked(rebuild_generation: int, rows_start_ms: int, profile_start_ms: int, clear_ms: int, filter_ms: int, header_ms: int) -> void:
	var filtered_idx: int = 0
	while filtered_idx < _filtered_indices.size():
		if rebuild_generation != _rebuild_generation or not is_inside_tree():
			return
		var chunk_end: int = mini(filtered_idx + _ROWS_PER_BUILD_CHUNK, _filtered_indices.size())
		while filtered_idx < chunk_end:
			_build_row(filtered_idx)
			filtered_idx += 1
		if filtered_idx < _filtered_indices.size():
			await get_tree().process_frame

	# Re-apply selection highlight.
	if _selected_filtered_idx >= 0 and _selected_filtered_idx < _row_panels.size():
		_highlight_row(_selected_filtered_idx)

	# Deferred height re-sync: texture previews, EditorResourcePicker,
	# and image controls need one layout pass before their minimum sizes
	# are accurate.  The immediate _sync in _build_row provides a
	# baseline (_ROW_MIN_HEIGHT floor); this corrects it.
	call_deferred("_deferred_sync_all_row_heights")
	call_deferred("_refresh_sticky_cell_positions")

	var rows_ms: int = Time.get_ticks_msec() - rows_start_ms
	var total_ms: int = Time.get_ticks_msec() - profile_start_ms
	if total_ms >= 50:
		print("GRD grid rebuild: total=%dms clear=%dms filter=%dms header=%dms rows=%dms rows=%d cols=%d cells=%d" % [
			total_ms, clear_ms, filter_ms, header_ms, rows_ms, _filtered_indices.size(), _columns.size(), _filtered_indices.size() * (_columns.size() + 1),
		])


func _build_header() -> void:
	var header_panels: Array[PanelContainer] = []

	# Row-number column header.
	var num_header: PanelContainer = _wrap_grid_cell(Label.new(), _scaled_row_number_width(), true, GRDTheme.BG, true)
	header_panels.append(num_header)
	var num_label: Label = num_header.get_child(0) as Label
	num_label.text = "#"
	GRDTheme.style_label(num_label, GRDTheme.FONT_SIZE_SMALL, GRDTheme.TEXT)
	num_label.add_theme_constant_override("outline_size", 1)
	_body.add_child(num_header)
	_register_sticky_cell(num_header, 0.0, 0.0, 0.0, 0.0)

	var sticky_left: float = float(_scaled_row_number_width())
	var natural_left: float = float(_scaled_row_number_width())
	for col in _columns:
		var header_cell: VBoxContainer = VBoxContainer.new()
		var wrapped_header: PanelContainer = _wrap_grid_cell(header_cell, _scaled_column_width(col.width), true, GRDTheme.BG, _is_sticky_column(col))
		header_panels.append(wrapped_header)
		_body.add_child(wrapped_header)
		if _is_sticky_column(col):
			_register_sticky_cell(wrapped_header, sticky_left, natural_left, 0.0, 0.0)
			sticky_left += float(_scaled_column_width(col.width))
		else:
			_register_sticky_cell(wrapped_header, -1.0, -1.0, 0.0, 0.0)
		natural_left += float(_scaled_column_width(col.width))

		var label: Label = Label.new()
		label.text = col.display
		label.clip_text = true
		label.tooltip_text = String(col.key)
		GRDTheme.style_label(label, GRDTheme.FONT_SIZE, GRDTheme.TEXT)
		header_cell.add_child(label)

		var type_label: Label = Label.new()
		type_label.text = _column_type_text(col)
		type_label.clip_text = true
		GRDTheme.style_label(type_label, GRDTheme.FONT_SIZE_TINY, GRDTheme.TEXT_MUTED)
		header_cell.add_child(type_label)

	_sync_panel_row_min_height(header_panels)


static func _wrap_grid_cell(child: Control, width: int, is_header: bool = false, bg: Color = GRDTheme.BG, fixed_width: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	if fixed_width:
		panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		panel.size_flags_stretch_ratio = 0.0
	else:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_stretch_ratio = float(width)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := GRDTheme.panel_style(
		GRDTheme.HEADER if is_header else bg,
		GRDTheme.BORDER,
		3,
		5,
		3,
	)
	panel.add_theme_stylebox_override("panel", style)
	panel.clip_contents = false
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	child.clip_contents = false
	panel.add_child(child)
	return panel


func _build_row(filtered_idx: int) -> void:
	var real_idx: int = _filtered_indices[filtered_idx]
	var row: GRDRow = _rows[real_idx]
	var resource: Resource = row.get_resource()

	var row_cells: Array = []
	_row_panels.append(row_cells)
	var row_bg: Color = GRDTheme.BG if real_idx % 2 == 0 else GRDTheme.BG_ALT

	# --- Row number ---
	var row_actions := HBoxContainer.new()
	var num_label: Label = Label.new()
	num_label.text = str(real_idx)
	num_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GRDTheme.style_label(num_label, GRDTheme.FONT_SIZE_TINY, GRDTheme.TEXT_DIM)
	row_actions.add_child(num_label)

	var drag_handle := RowDragHandle.new()
	drag_handle.view = self
	drag_handle.row_index = real_idx
	drag_handle.text = "☰"
	drag_handle.tooltip_text = "Drag to reorder row"
	drag_handle.focus_mode = Control.FOCUS_NONE
	drag_handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	drag_handle.custom_minimum_size = Vector2(GRDTheme.scaled(18.0), GRDTheme.scaled(22.0))
	drag_handle.add_theme_font_size_override("font_size", GRDTheme.font_size_small())
	drag_handle.add_theme_color_override("font_color", GRDTheme.TEXT_MUTED)
	drag_handle.add_theme_color_override("font_hover_color", Color.WHITE)
	drag_handle.add_theme_stylebox_override("normal", GRDTheme.panel_style(Color.TRANSPARENT, Color.TRANSPARENT, GRDTheme.RADIUS, 2, 1))
	drag_handle.add_theme_stylebox_override("hover", GRDTheme.panel_style(GRDTheme.ACCENT_DARK, GRDTheme.ACCENT, GRDTheme.RADIUS, 2, 1))
	drag_handle.add_theme_stylebox_override("pressed", GRDTheme.panel_style(GRDTheme.ACCENT_DARK.lightened(0.08), GRDTheme.ACCENT, GRDTheme.RADIUS, 2, 1))
	drag_handle.add_theme_stylebox_override("focus", GRDTheme.focus_style())
	row_actions.add_child(drag_handle)

	var delete_btn := Button.new()
	delete_btn.text = "×"
	delete_btn.tooltip_text = "Remove row"
	delete_btn.focus_mode = Control.FOCUS_NONE
	delete_btn.custom_minimum_size = Vector2(GRDTheme.scaled(22.0), GRDTheme.scaled(22.0))
	delete_btn.add_theme_font_size_override("font_size", GRDTheme.font_size_small())
	delete_btn.add_theme_color_override("font_color", GRDTheme.TEXT_MUTED)
	delete_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	delete_btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	delete_btn.add_theme_stylebox_override("normal", GRDTheme.panel_style(Color.TRANSPARENT, Color.TRANSPARENT, GRDTheme.RADIUS, 3, 1))
	delete_btn.add_theme_stylebox_override("hover", GRDTheme.panel_style(GRDTheme.ERROR.darkened(0.55), GRDTheme.ERROR.darkened(0.15), GRDTheme.RADIUS, 3, 1))
	delete_btn.add_theme_stylebox_override("pressed", GRDTheme.panel_style(GRDTheme.ERROR.darkened(0.35), GRDTheme.ERROR, GRDTheme.RADIUS, 3, 1))
	delete_btn.add_theme_stylebox_override("focus", GRDTheme.focus_style())
	delete_btn.pressed.connect(func() -> void:
		row_delete_requested.emit(real_idx)
	)
	row_actions.add_child(delete_btn)

	var num_cell: PanelContainer = _wrap_grid_cell(row_actions, _scaled_row_number_width(), false, row_bg, true)
	_connect_row_selection(num_cell, filtered_idx)
	_body.add_child(num_cell)
	_register_sticky_cell(num_cell, 0.0, 0.0)
	row_cells.append(num_cell)

	var sticky_left: float = float(_scaled_row_number_width())
	var natural_left: float = float(_scaled_row_number_width())
	for col in _columns:
		var key: String = String(col.key)
		var value: Variant = row.get_value(key)
		var cell: Control

		# Resource-first mode: branch on property_column.
		var prop_col: GRDPropertyColumn = col.get("property_column", null) as GRDPropertyColumn
		if prop_col != null:
			var is_missing: bool = value == null and not row.has_path(key)

			if is_missing:
				cell = GRDResourceCellEditorFactory.read_only_label("(not set)")
				cell.add_theme_color_override("font_color", GRDTheme.TEXT_DIM)
			elif prop_col.read_only:
				cell = _create_read_only_cell(value)
			else:
				var cur_filtered_idx: int = filtered_idx
				var captured_prop_col: GRDPropertyColumn = prop_col
				var captured_key: String = key
				var on_change: Callable = func(new_value: Variant) -> void:
					var r_idx: int = _filtered_indices[cur_filtered_idx]
					if resource != null:
						resource.set(captured_prop_col.name, new_value)
						resource.emit_changed()
					cell_changed.emit(r_idx, StringName(captured_key), new_value)
					refresh_row_heights()
				cell = GRDResourceCellEditorFactory.create_cell_editor(
					prop_col, value, resource, on_change, _database_asset,
				)
		else:
			# No property_column — read-only fallback.
			cell = _create_read_only_cell(value)

		GRDTheme.apply_tree(cell, false)
		var wrapped_cell: PanelContainer = _wrap_grid_cell(cell, _scaled_column_width(col.width), false, row_bg, _is_sticky_column(col))
		_connect_row_selection(wrapped_cell, filtered_idx)
		_body.add_child(wrapped_cell)
		if _is_sticky_column(col):
			_register_sticky_cell(wrapped_cell, sticky_left, natural_left)
			sticky_left += float(_scaled_column_width(col.width))
		natural_left += float(_scaled_column_width(col.width))
		row_cells.append(wrapped_cell)

	_sync_panel_row_min_height(row_cells)


func _connect_row_selection(_panel: PanelContainer, _filtered_idx: int) -> void:
	pass


static func _sync_panel_row_min_height(panels: Array) -> void:
	var max_height: float = 0.0
	for panel in panels:
		if not (panel is PanelContainer):
			continue
		var panel_container := panel as PanelContainer
		panel_container.custom_minimum_size.y = 0.0
		if panel_container.get_child_count() > 0:
			var child := panel_container.get_child(0) as Control
			if child != null:
				max_height = max(max_height, child.get_combined_minimum_size().y)
	max_height = max(max_height, float(GRDTheme.scaled_int(_ROW_MIN_HEIGHT)))
	for panel in panels:
		if panel is PanelContainer:
			(panel as PanelContainer).custom_minimum_size.y = max_height


func _register_sticky_cell(
	panel: PanelContainer,
	sticky_left: float,
	natural_left: float,
	sticky_top: float = -1.0,
	natural_top: float = -1.0,
) -> void:
	panel.z_as_relative = false
	if sticky_top >= 0.0 and sticky_left >= 0.0:
		panel.z_index = _STICKY_COLUMN_HEADER_Z_INDEX
	elif sticky_top >= 0.0:
		panel.z_index = _STICKY_HEADER_Z_INDEX
	else:
		panel.z_index = _STICKY_COLUMN_Z_INDEX
	_sticky_cells.append({
		"panel": panel,
		"sticky_left": sticky_left,
		"natural_left": natural_left,
		"sticky_top": sticky_top,
		"natural_top": natural_top,
	})
	_update_sticky_cell_position(
		panel,
		sticky_left,
		natural_left,
		sticky_top,
		natural_top,
		_body_scroll.get_h_scroll_bar().value,
		_body_scroll.get_v_scroll_bar().value,
	)


func _on_horizontal_scroll_changed(value: float) -> void:
	_refresh_sticky_cell_positions(value, -1.0)


func _on_vertical_scroll_changed(value: float) -> void:
	_refresh_sticky_cell_positions(-1.0, value)


func _refresh_sticky_cell_positions(horizontal_scroll_value: float = -1.0, vertical_scroll_value: float = -1.0) -> void:
	if horizontal_scroll_value < 0.0:
		horizontal_scroll_value = _body_scroll.get_h_scroll_bar().value
	if vertical_scroll_value < 0.0:
		vertical_scroll_value = _body_scroll.get_v_scroll_bar().value
	for entry in _sticky_cells:
		var panel: PanelContainer = entry.get("panel", null) as PanelContainer
		if panel != null:
			_update_sticky_cell_position(
				panel,
				float(entry.get("sticky_left", 0.0)),
				float(entry.get("natural_left", 0.0)),
				float(entry.get("sticky_top", -1.0)),
				float(entry.get("natural_top", -1.0)),
				horizontal_scroll_value,
				vertical_scroll_value,
			)


static func _update_sticky_cell_position(
	panel: PanelContainer,
	sticky_left: float,
	natural_left: float,
	sticky_top: float,
	natural_top: float,
	horizontal_scroll_value: float,
	vertical_scroll_value: float,
) -> void:
	if sticky_left >= 0.0:
		panel.position.x = round(max(natural_left, horizontal_scroll_value + sticky_left))
	if sticky_top >= 0.0:
		panel.position.y = round(max(natural_top, vertical_scroll_value + sticky_top))


static func _is_sticky_column(col: Dictionary) -> bool:
	return bool(col.get("sticky", false))


static func _scaled_row_number_width() -> int:
	return GRDTheme.scaled_int(_ROW_NUMBER_WIDTH)


static func _scaled_column_width(width: int) -> int:
	return GRDTheme.scaled_int(width)


static func _column_type_text(col: Dictionary) -> String:
	# Resource-first: use GRDPropertyColumn.
	var prop_col: GRDPropertyColumn = col.get("property_column", null) as GRDPropertyColumn
	if prop_col != null:
		return _property_column_type_text(prop_col)
	return "INFERRED"


## Returns a human-readable type string for a GRDPropertyColumn.
static func _property_column_type_text(col: GRDPropertyColumn) -> String:
	if col == null:
		return ""
	if col.is_enum():
		var opts: PackedStringArray = col.get_enum_values()
		if opts.size() > 0:
			return "enum(%s)" % ", ".join(opts)
		return "enum"
	if col.is_script():
		return "Script"
	if col.is_resource_reference():
		var rtype: String = col.get_resource_type()
		return "Resource[%s]" % rtype if not rtype.is_empty() else "Resource"
	if col.is_bool():
		return "bool"
	if col.is_numeric():
		return "int" if col.type == TYPE_INT else "float"
	if col.is_string_like():
		if col.is_file_path():
			return "File"
		if col.is_global_file_path():
			return "GlobalFile"
		return "StringName" if col.type == TYPE_STRING_NAME else "String"
	if col.is_array():
		var elem: String = col.get_array_element_hint()
		if not elem.is_empty():
			return "Array[%s]" % elem
		return "Array"
	if col.is_dictionary():
		return "Dictionary"
	# Fallback to Variant type name.
	return type_string(col.type)


func _create_read_only_cell(value: Variant) -> Control:
	var vtype: int = typeof(value)
	if vtype == TYPE_OBJECT and value is Resource:
		return GRDResourceCellEditorFactory.read_only_label(
			GRDResourceCellEditorFactory.resource_summary(value),
		)
	if vtype in GRDResourceCellEditorFactory.SUMMARY_TYPES:
		return GRDResourceCellEditorFactory.read_only_label(
			GRDResourceCellEditorFactory.value_summary(value, vtype),
		)
	return GRDResourceCellEditorFactory.read_only_label(str(value) if value != null else "")


# ---------------------------------------------------------------------------
# Row selection & highlighting
# ---------------------------------------------------------------------------

func _select_row(filtered_idx: int) -> void:
	_selected_filtered_idx = filtered_idx
	_highlight_row(filtered_idx)
	row_selected.emit(filtered_idx)


func _highlight_row(filtered_idx: int) -> void:
	for i in _row_panels.size():
		var bg_color: Color
		if i == filtered_idx:
			bg_color = GRDTheme.ACCENT_DARK
		else:
			# Restore alternating row background
			var fi: int = i
			if fi >= 0 and fi < _filtered_indices.size():
				var ri: int = _filtered_indices[fi]
				bg_color = GRDTheme.BG if ri % 2 == 0 else GRDTheme.BG_ALT
			else:
				bg_color = Color.TRANSPARENT
		for cell_panel in _row_panels[i]:
			if cell_panel is PanelContainer:
				var existing_style := (cell_panel as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
				var panel_style: StyleBoxFlat = existing_style.duplicate() as StyleBoxFlat if existing_style != null else GRDTheme.panel_style(bg_color, GRDTheme.BORDER, 3, 5, 3)
				panel_style.bg_color = bg_color
				(cell_panel as PanelContainer).add_theme_stylebox_override("panel", panel_style)


# ---------------------------------------------------------------------------
# Search / filtering
# ---------------------------------------------------------------------------

func _filter_rows() -> void:
	_filtered_indices.clear()
	if _search_text.is_empty():
		for i in _rows.size():
			_filtered_indices.append(i)
		return

	for i in _rows.size():
		if _row_matches_search(_rows[i]):
			_filtered_indices.append(i)


func _row_matches_search(row: GRDRow) -> bool:
	for col in _columns:
		var key: String = String(col.key)
		var value: Variant = row.get_value(key)
		var text: String = _cell_display_text(value)
		if text.to_lower().contains(_search_text):
			return true
	return false


## Returns a plain-text representation of a cell value suitable for search.
static func _cell_display_text(value: Variant) -> String:
	var vtype: int = typeof(value)
	if vtype in GRDResourceCellEditorFactory.EDITABLE_SCALAR_TYPES or vtype == TYPE_NODE_PATH:
		return str(value) if value != null else ""
	if vtype == TYPE_OBJECT and value is Resource:
		return GRDResourceCellEditorFactory.resource_summary(value)
	return GRDResourceCellEditorFactory.value_summary(value, vtype)
