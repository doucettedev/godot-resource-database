class_name GRDQuery
extends RefCounted

## Fluent, clone-on-chain query builder for GRDTable.
##
## The first equality filter in a query is automatically dispatched through
## the table's lazy index.  All other filters are applied linearly.
##
## `where_contains` operates on Array-typed values and checks for membership.
## `where_in` checks whether the field value is one of the given candidates.

var _table: GRDTable
var _row_mapper: Callable
var _filters: Array[Dictionary] = []
var _order_field: String = ""
var _order_ascending: bool = true
var _limit_count: int = -1
var _offset_count: int = 0


func _init(table: GRDTable, row_mapper: Callable = Callable()) -> void:
	_table = table
	_row_mapper = row_mapper


func _clone() -> GRDQuery:
	var q: GRDQuery = GRDQuery.new(_table, _row_mapper)
	q._filters = _filters.duplicate()
	q._order_field = _order_field
	q._order_ascending = _order_ascending
	q._limit_count = _limit_count
	q._offset_count = _offset_count
	return q


# ---------------------------------------------------------------------------
# Filter methods
# ---------------------------------------------------------------------------

func where_eq(field_path: String, value: Variant) -> GRDQuery:
	return _append_filter({"type": "eq", "field": field_path, "value": value})


func where_ne(field_path: String, value: Variant) -> GRDQuery:
	return _append_filter({"type": "ne", "field": field_path, "value": value})


func where_gt(field_path: String, value: Variant) -> GRDQuery:
	return _append_filter({"type": "gt", "field": field_path, "value": value})


func where_gte(field_path: String, value: Variant) -> GRDQuery:
	return _append_filter({"type": "gte", "field": field_path, "value": value})


func where_lt(field_path: String, value: Variant) -> GRDQuery:
	return _append_filter({"type": "lt", "field": field_path, "value": value})


func where_lte(field_path: String, value: Variant) -> GRDQuery:
	return _append_filter({"type": "lte", "field": field_path, "value": value})


## Checks whether the field value is one of the candidates in `value`.
## `value` must be an Array; non-Array values are silently ignored.
func where_in(field_path: String, value: Array) -> GRDQuery:
	return _append_filter({"type": "in", "field": field_path, "value": value})


## Checks whether the field value (which must be an Array) contains `value`.
func where_contains(field_path: String, value: Variant) -> GRDQuery:
	return _append_filter({"type": "contains", "field": field_path, "value": value})


func where(predicate: Callable) -> GRDQuery:
	return _append_filter({"type": "predicate", "predicate": predicate})


# ---------------------------------------------------------------------------
# Nested array-element query
# ---------------------------------------------------------------------------

## Opens a nested query on array_field_path.  At least one element must
## satisfy ALL chained conditions for the row to match.
func where_any(array_field_path: String) -> GRDNestedQuery:
	var q: GRDQuery = _clone()
	return GRDNestedQuery.new(q, array_field_path)


# ---------------------------------------------------------------------------
# Ordering / pagination
# ---------------------------------------------------------------------------

func order_by(field_path: String, ascending: bool = true) -> GRDQuery:
	var q: GRDQuery = _clone()
	q._order_field = field_path
	q._order_ascending = ascending
	return q


func limit(count: int) -> GRDQuery:
	var q: GRDQuery = _clone()
	q._limit_count = maxi(count, -1)
	return q


func offset(count: int) -> GRDQuery:
	var q: GRDQuery = _clone()
	q._offset_count = maxi(count, 0)
	return q


# ---------------------------------------------------------------------------
# Execution
# ---------------------------------------------------------------------------

## Returns matching rows as an Array.  If a row_mapper was provided each
## element is the mapped value.
func to_array() -> Array:
	var rows: Array[GRDRow] = _execute()
	if _row_mapper.is_valid():
		var mapped: Array = []
		for row in rows:
			mapped.append(_row_mapper.call(row))
		return mapped
	return rows


## Returns the first matching row, or null.
func first() -> Variant:
	var rows: Array[GRDRow] = _execute()
	if rows.is_empty():
		return null
	if _row_mapper.is_valid():
		return _row_mapper.call(rows[0])
	return rows[0]


## Count of rows matching filters (ignores offset/limit).
func count() -> int:
	return _execute(true).size()


## Returns IDs of all matching rows.
func ids() -> PackedStringArray:
	var rows: Array[GRDRow] = _execute()
	var out: PackedStringArray = PackedStringArray()
	for row in rows:
		var id: Variant = row.get_id()
		if id != null:
			out.append(String(id))
	return out


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _append_filter(filter: Dictionary) -> GRDQuery:
	var q: GRDQuery = _clone()
	q._filters.append(filter)
	return q


func _execute(skip_offset_limit: bool = false) -> Array[GRDRow]:
	var rows: Array[GRDRow] = []
	var filters: Array[Dictionary] = _filters

	if filters.is_empty():
		rows = _table.all()
	elif filters[0].get("type") == "eq":
		# Optimised path: use the table's indexed where_eq for the first eq.
		rows = _table.where_eq(filters[0]["field"], filters[0]["value"])
		rows = _apply_filters(rows, filters.slice(1))
	else:
		rows = _apply_filters(_table.all(), filters)

	if _order_field != "":
		rows = _sort_rows(rows)

	if not skip_offset_limit:
		if _offset_count > 0:
			rows = rows.slice(_offset_count)
		if _limit_count >= 0:
			rows = rows.slice(0, _limit_count)

	return rows


func _apply_filters(rows: Array[GRDRow], filters: Array) -> Array[GRDRow]:
	for f in filters:
		var ftype: String = f.get("type", "")
		var field: String = f.get("field", "")
		var value: Variant = f.get("value", null)
		var predicate: Callable = f.get("predicate", Callable())

		match ftype:
			"eq":
				rows = rows.filter(func(r: GRDRow) -> bool: return r.get_value(field) == value)
			"ne":
				rows = rows.filter(func(r: GRDRow) -> bool: return r.get_value(field) != value)
			"gt":
				rows = rows.filter(func(r: GRDRow) -> bool:
					var v: Variant = r.get_value(field)
					return _values_comparable(v, value) and v > value)
			"gte":
				rows = rows.filter(func(r: GRDRow) -> bool:
					var v: Variant = r.get_value(field)
					return _values_comparable(v, value) and v >= value)
			"lt":
				rows = rows.filter(func(r: GRDRow) -> bool:
					var v: Variant = r.get_value(field)
					return _values_comparable(v, value) and v < value)
			"lte":
				rows = rows.filter(func(r: GRDRow) -> bool:
					var v: Variant = r.get_value(field)
					return _values_comparable(v, value) and v <= value)
			"in":
				if typeof(value) == TYPE_ARRAY:
					var haystack: Array = value
					rows = rows.filter(func(r: GRDRow) -> bool: return haystack.has(r.get_value(field)))
			"contains":
				rows = rows.filter(func(r: GRDRow) -> bool:
					var arr: Variant = r.get_value(field)
					return typeof(arr) == TYPE_ARRAY and (arr as Array).has(value))
			"predicate":
				rows = rows.filter(predicate)
			"nested_any":
				var nested_filters: Array = f.get("nested_filters", [])
				rows = rows.filter(func(r: GRDRow) -> bool:
					var arr: Variant = r.get_value(field)
					if typeof(arr) != TYPE_ARRAY:
						return false
					for element in (arr as Array):
						if _element_matches_all(element, nested_filters):
							return true
					return false)

	return rows


# ---------------------------------------------------------------------------
# Nested element matching (Resource or Dictionary)
# ---------------------------------------------------------------------------

## Resolves a dotted path on a variant that may be a Resource, Dictionary,
## or an element inside a nested array.
static func _element_resolve(element: Variant, path: String) -> Variant:
	if element == null or path.is_empty():
		return null
	# For GRDRow-backed elements (Resource rows inside arrays).
	if element is Resource:
		return GRDRow._resolve_dotted(element, path)
	# For raw dictionaries.
	if typeof(element) == TYPE_DICTIONARY:
		return _dict_resolve(element as Dictionary, path)
	return null


static func _dict_resolve(dict: Dictionary, path: String) -> Variant:
	var parts: PackedStringArray = path.split(".")
	var current: Variant = dict
	for part in parts:
		if typeof(current) == TYPE_DICTIONARY:
			var d: Dictionary = current
			if d.has(part):
				current = d[part]
			else:
				return null
		else:
			return null
	return current


static func _element_matches_all(element: Variant, filters: Array) -> bool:
	for f in filters:
		if not _element_matches_one(element, f):
			return false
	return true


static func _element_matches_one(element: Variant, f: Dictionary) -> bool:
	var ftype: String = f.get("type", "")
	var field: String = f.get("field", "")
	var value: Variant = f.get("value", null)
	var predicate: Callable = f.get("predicate", Callable())
	var ev: Variant = _element_resolve(element, field)

	match ftype:
		"eq":
			return ev == value
		"ne":
			return ev != value
		"gt":
			return _values_comparable(ev, value) and ev > value
		"gte":
			return _values_comparable(ev, value) and ev >= value
		"lt":
			return _values_comparable(ev, value) and ev < value
		"lte":
			return _values_comparable(ev, value) and ev <= value
		"in":
			if typeof(value) == TYPE_ARRAY:
				return (value as Array).has(ev)
			return false
		"contains":
			return typeof(ev) == TYPE_ARRAY and (ev as Array).has(value)
		"predicate":
			return predicate.call(element)
	return false


func _sort_rows(rows: Array[GRDRow]) -> Array[GRDRow]:
	var field: String = _order_field
	var asc: bool = _order_ascending
	rows.sort_custom(func(a: GRDRow, b: GRDRow) -> bool:
		var va: Variant = a.get_value(field)
		var vb: Variant = b.get_value(field)
		if va == null and vb == null:
			return false
		if va == null:
			return not asc
		if vb == null:
			return asc
		if not _values_comparable(va, vb):
			return false  # Incomparable values maintain relative order.
		return va < vb if asc else va > vb)
	return rows


# ---------------------------------------------------------------------------
# Type-safe comparison helpers
# ---------------------------------------------------------------------------

## Returns true when two values can be safely compared with < > <= >=.
## Null values are never comparable.  int and float are mutually comparable.
## Different non-numeric types are not comparable (avoids runtime errors).
static func _values_comparable(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return false
	var ta: int = typeof(a)
	var tb: int = typeof(b)
	if ta == tb:
		return true
	# Allow int <-> float numeric comparisons.
	if (ta == TYPE_INT or ta == TYPE_FLOAT) and (tb == TYPE_INT or tb == TYPE_FLOAT):
		return true
	return false
