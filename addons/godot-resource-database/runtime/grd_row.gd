class_name GRDRow
extends RefCounted

## Lightweight adapter that presents a Resource-backed row through a uniform
## interface: dotted path resolution, keys from exported/storage properties.
##
## `has_path()` and `get_value()` distinguish "path not found" from "path
## exists but value is null": `has_path()` returns false only when the
## property cannot be resolved, and `get_value(default)` applies the
## default only when the path is missing, not when the resolved value is null.

## Built-in Resource property names that should NOT appear as column keys.
const _BUILTIN_RESOURCE_PROPS: Array[StringName] = [
	&"resource_local_to_scene",
	&"resource_path",
	&"resource_name",
	&"script",
]

var _resource: Resource
var _id_field: StringName


func _init(resource: Resource, id_field: StringName = &"id") -> void:
	_resource = resource
	_id_field = id_field


## The underlying Godot Resource.
func get_resource() -> Resource:
	return _resource


## Row identifier resolved from the configured id_field property.
func get_id() -> Variant:
	if _resource == null:
		return null
	var result: Array = _resolve_tracked(_resource, String(_id_field))
	return result[1] if result[0] else null


# ---------------------------------------------------------------------------
# Path resolution — public API
# ---------------------------------------------------------------------------

## Resolves a dotted path against the underlying resource.
## Returns `default_value` only when the path cannot be resolved (missing
## property / dictionary key).  Returns the actual value — including null —
## when the path resolves successfully.
func get_value(path: String, default_value: Variant = null) -> Variant:
	if _resource == null or path.is_empty():
		return default_value
	var result: Array = _resolve_tracked(_resource, path)
	return result[1] if result[0] else default_value


## Returns true when the dotted path resolves to an existing value
## (the value itself may be null).
func has_path(path: String) -> bool:
	if _resource == null or path.is_empty():
		return false
	return _resolve_tracked(_resource, path)[0]


# ---------------------------------------------------------------------------
# Keys
# ---------------------------------------------------------------------------

## Returns all visible column names: exported/storage property names (minus
## built-ins and the script property).
func keys() -> Array[StringName]:
	var result: Array[StringName] = []
	if _resource == null:
		return result

	var props: Array[Dictionary] = _resource.get_property_list()
	for p in props:
		if not (p.usage & PROPERTY_USAGE_STORAGE):
			continue
		var prop_name: StringName = StringName(p.name)
		if prop_name in _BUILTIN_RESOURCE_PROPS:
			continue
		result.append(prop_name)

	return result


## Returns true when the key list includes the given name.
func has_key(key: StringName) -> bool:
	return _array_contains_name(keys(), key)


# ---------------------------------------------------------------------------
# Typed getters
# ---------------------------------------------------------------------------

func get_string(key: String, default_value: String = "") -> String:
	var v: Variant = get_value(key)
	return v if typeof(v) == TYPE_STRING else default_value


func get_int(key: String, default_value: int = 0) -> int:
	var v: Variant = get_value(key)
	return v if typeof(v) == TYPE_INT else default_value


func get_float(key: String, default_value: float = 0.0) -> float:
	var v: Variant = get_value(key)
	if typeof(v) == TYPE_FLOAT:
		return v
	if typeof(v) == TYPE_INT:
		return float(v)
	return default_value


func get_bool(key: String, default_value: bool = false) -> bool:
	var v: Variant = get_value(key)
	return v if typeof(v) == TYPE_BOOL else default_value


func get_array(key: String) -> Array:
	var v: Variant = get_value(key)
	return v if typeof(v) == TYPE_ARRAY else []


func get_dictionary(key: String) -> Dictionary:
	var v: Variant = get_value(key)
	return v if typeof(v) == TYPE_DICTIONARY else {}


func as_dictionary() -> Dictionary:
	var dict: Dictionary = {}
	for key in keys():
		dict[key] = get_value(String(key))
	return dict


func get_raw() -> Dictionary:
	return as_dictionary()


# ---------------------------------------------------------------------------
# Internal: tracked path resolution (distinguishes missing from null)
# ---------------------------------------------------------------------------

## Resolves a dotted path and reports whether the path was found.
## Returns [found: bool, value: Variant].
## When found is true the value may still be null (explicit null).
## When found is false the path could not be resolved.
static func _resolve_tracked(root: Variant, path: String) -> Array:
	var parts: PackedStringArray = path.split(".")
	var current: Variant = root
	for part in parts:
		var seg: Array = _resolve_segment_tracked(current, part)
		if not seg[0]:
			return seg  # [false, null]
		current = seg[1]
	return [true, current]


## Resolves a single segment and reports found/not-found.
static func _resolve_segment_tracked(current: Variant, segment: String) -> Array:
	match typeof(current):
		TYPE_OBJECT:
			if current is Resource:
				if _resource_has_property(current as Resource, segment):
					return [true, current.get(segment)]
				return [false, null]
			return [false, null]
		TYPE_DICTIONARY:
			var dict: Dictionary = current
			if dict.has(segment):
				return [true, dict[segment]]
			return [false, null]
		TYPE_ARRAY:
			if segment.is_valid_int():
				var idx: int = segment.to_int()
				var arr: Array = current
				if idx >= 0 and idx < arr.size():
					return [true, arr[idx]]
			return [false, null]
		_:
			return [false, null]


## Returns true when the Resource has a declared property with the given name.
static func _resource_has_property(resource: Resource, property_name: String) -> bool:
	for p in resource.get_property_list():
		if p.name == property_name:
			return true
	return false


# ---------------------------------------------------------------------------
# Internal: static path resolution for query module (simpler, null = not-found)
# ---------------------------------------------------------------------------

## Resolves a dotted path.  Returns null when any segment cannot be resolved.
## Used by the query module where null means "does not match".
static func _resolve_dotted(root: Variant, path: String) -> Variant:
	var result: Array = _resolve_tracked(root, path)
	return result[1] if result[0] else null


## Linear search for a StringName inside an Array[StringName].
static func _array_contains_name(array: Array[StringName], target: StringName) -> bool:
	for name in array:
		if name == target:
			return true
	return false
