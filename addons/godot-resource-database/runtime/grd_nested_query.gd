class_name GRDNestedQuery
extends RefCounted

## Nested array-element query builder.
##
## Returned by GRDQuery.where_any(array_field).  Collects conditions that
## must ALL match on at least ONE element of the array field.
## Call end() to finalize and return to the parent GRDQuery.

var _parent_query: GRDQuery
var _array_field: String
var _filters: Array[Dictionary] = []


func _init(parent_query: GRDQuery, array_field: String) -> void:
	_parent_query = parent_query
	_array_field = array_field


func _clone() -> GRDNestedQuery:
	var q: GRDNestedQuery = GRDNestedQuery.new(_parent_query, _array_field)
	q._filters = _filters.duplicate()
	return q


# ---------------------------------------------------------------------------
# Nested filter methods
# ---------------------------------------------------------------------------

func where_eq(field_path: String, value: Variant) -> GRDNestedQuery:
	return _append({"type": "eq", "field": field_path, "value": value})


func where_ne(field_path: String, value: Variant) -> GRDNestedQuery:
	return _append({"type": "ne", "field": field_path, "value": value})


func where_gt(field_path: String, value: Variant) -> GRDNestedQuery:
	return _append({"type": "gt", "field": field_path, "value": value})


func where_gte(field_path: String, value: Variant) -> GRDNestedQuery:
	return _append({"type": "gte", "field": field_path, "value": value})


func where_lt(field_path: String, value: Variant) -> GRDNestedQuery:
	return _append({"type": "lt", "field": field_path, "value": value})


func where_lte(field_path: String, value: Variant) -> GRDNestedQuery:
	return _append({"type": "lte", "field": field_path, "value": value})


## Checks whether the element field value is one of the candidates.
## `value` must be an Array.
func where_in(field_path: String, value: Array) -> GRDNestedQuery:
	return _append({"type": "in", "field": field_path, "value": value})


## Checks whether the element field value (which must be an Array) contains `value`.
func where_contains(field_path: String, value: Variant) -> GRDNestedQuery:
	return _append({"type": "contains", "field": field_path, "value": value})


func where(predicate: Callable) -> GRDNestedQuery:
	return _append({"type": "predicate", "predicate": predicate})


# ---------------------------------------------------------------------------
# Finalize
# ---------------------------------------------------------------------------

## Appends all collected nested filters as a single "nested_any" filter on
## the parent GRDQuery and returns the parent for further chaining.
func end() -> GRDQuery:
	var q: GRDQuery = _parent_query._clone()
	q._filters.append({
		"type": "nested_any",
		"field": _array_field,
		"nested_filters": _filters.duplicate(),
	})
	return q


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _append(filter: Dictionary) -> GRDNestedQuery:
	var q: GRDNestedQuery = _clone()
	q._filters.append(filter)
	return q
