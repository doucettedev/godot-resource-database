class_name GRDTable
extends RefCounted

## Wraps a GRDTableAsset into a queryable in-memory table. Builds lazy
## equality indexes and provides query entry-points backed by GRDRow adapters
## over Resource objects.

var _name: StringName
var _id_field: StringName
var _rows: Dictionary = {}        # id_str -> GRDRow  (only rows with valid IDs)
var _row_order: Array[GRDRow] = []
var _indexes: Dictionary = {}      # field_path -> { normalized_value -> Array[GRDRow] }
var _asset: GRDTableAsset
var _options: GRDDatabaseOptions
var _build_issues: Array[GRDDatabaseIssue] = []


func _init(
	asset: GRDTableAsset,
	options: GRDDatabaseOptions = null,
) -> void:
	_asset = asset
	_options = options if options != null else GRDDatabaseOptions.new()
	_name = asset.table_name
	# id_field: use asset value when non-empty, otherwise fall back to options.
	_id_field = asset.id_field if asset.id_field != &"" else _options.id_field
	_build_rows()


# ---------------------------------------------------------------------------
# Accessors
# ---------------------------------------------------------------------------

func get_name() -> StringName:
	return _name


func get_asset() -> GRDTableAsset:
	return _asset


func size() -> int:
	return _row_order.size()


func has_row(id: StringName) -> bool:
	return _rows.has(id)


func get_row(id: StringName) -> GRDRow:
	return _rows.get(id, null)


func try_get_row(id: StringName) -> GRDRow:
	return get_row(id)


func row_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for key in _rows:
		out.append(String(key))
	return out


## Returns all rows in insertion order (includes rows with missing IDs).
func all() -> Array[GRDRow]:
	return _row_order.duplicate()


## Returns the live row array. Read only; callers that sort or mutate must use all().
func all_readonly() -> Array[GRDRow]:
	return _row_order


## Issues encountered during row loading (directory mode, type mismatches, etc.).
func get_build_issues() -> Array[GRDDatabaseIssue]:
	return _build_issues.duplicate()


# ---------------------------------------------------------------------------
# Equality queries (with lazy index)
# ---------------------------------------------------------------------------

## Returns all rows where the field equals value. Builds a lazy index on
## first call for each non-null scalar field.
## Null value queries bypass the index and scan linearly.
func where_eq(field_path: String, value: Variant) -> Array[GRDRow]:
	if value == null:
		# Null is never indexed — linear scan.
		return where(func(r: GRDRow) -> bool: return r.get_value(field_path) == null)
	_ensure_index(field_path)
	var idx: Dictionary = _indexes.get(field_path, {})
	var key: Variant = _normalize_scalar(value)
	var indexed_rows: Array[GRDRow] = []
	if idx.has(key):
		for row in idx[key]:
			indexed_rows.append(row)
	return indexed_rows


## Returns the first row where field equals value, or null.
func find_eq(field_path: String, value: Variant) -> GRDRow:
	var results: Array[GRDRow] = where_eq(field_path, value)
	return results[0] if not results.is_empty() else null


## Returns all rows matching a custom predicate.
func where(predicate: Callable) -> Array[GRDRow]:
	var results: Array[GRDRow] = []
	for row in _row_order:
		if predicate.call(row):
			results.append(row)
	return results


# ---------------------------------------------------------------------------
# Index management
# ---------------------------------------------------------------------------

func ensure_index(field_path: String) -> void:
	_ensure_index(field_path)


func clear_index(field_path: String) -> void:
	_indexes.erase(field_path)


func clear_indexes() -> void:
	_indexes.clear()


func _ensure_index(field_path: String) -> void:
	if _indexes.has(field_path):
		return
	var idx: Dictionary = {}
	for row in _row_order:
		var value: Variant = row.get_value(field_path)
		if value != null and _is_scalar(value):
			var key: Variant = _normalize_scalar(value)
			if not idx.has(key):
				idx[key] = []
			idx[key].append(row)
	_indexes[field_path] = idx


# ---------------------------------------------------------------------------
# Fluent query API
# ---------------------------------------------------------------------------

func query() -> GRDQuery:
	return GRDQuery.new(self)


# ---------------------------------------------------------------------------
# Internal: row construction from asset
# ---------------------------------------------------------------------------

func _build_rows() -> void:
	for res in _asset.rows:
		if res == null:
			continue
		_add_resource_row(res)


func _add_resource_row(res: Resource) -> void:
	var row: GRDRow = GRDRow.new(res, _id_field)
	_row_order.append(row)
	var raw_id: Variant = row.get_id()
	if raw_id == null or str(raw_id).is_empty():
		# Row has no ID — still in _row_order but not ID-indexable.
		return
	var id_str: StringName = StringName(str(raw_id))
	if not _rows.has(id_str):
		_rows[id_str] = row
	# Duplicate IDs: first row wins in _row_order index; validation catches it.


# ---------------------------------------------------------------------------
# Scalar helpers
# ---------------------------------------------------------------------------

static func _is_scalar(value: Variant) -> bool:
	var t: int = typeof(value)
	return t == TYPE_INT \
		or t == TYPE_FLOAT \
		or t == TYPE_STRING \
		or t == TYPE_BOOL \
		or t == TYPE_STRING_NAME \
		or t == TYPE_NODE_PATH


static func _normalize_scalar(value: Variant) -> Variant:
	var t: int = typeof(value)
	if t == TYPE_STRING_NAME or t == TYPE_NODE_PATH:
		return String(value)
	return value
