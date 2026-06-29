class_name GRDPropertyColumn
extends RefCounted

## Describes a single column derived from Godot exported property metadata.
## Resource-first architecture. Columns are inferred from row_script or
## row instance property lists, not from manual column definitions.

## Property name (e.g. &"id", &"name", &"hp").
var name: StringName = &""

## Human-readable display name (defaults to name if empty).
var display_name: String = ""

## Godot Variant type constant (TYPE_STRING, TYPE_INT, etc.).
var type: int = 0

## Godot property hint constant (PROPERTY_HINT_NONE, PROPERTY_HINT_ENUM, etc.).
var hint: int = 0

## Hint string (e.g. "Option1,Option2" for enums, "Texture2D" for resource hints).
var hint_string: String = ""

## Property usage flags (PROPERTY_USAGE_STORAGE, PROPERTY_USAGE_EDITOR, etc.).
var usage: int = 0

## Whether the property is read-only in the editor.
var read_only: bool = false

## Suggested column width for spreadsheet display (0 = auto).
var width: int = 0

## Whether this property is an exported, editor-visible, storage property.
## True only when usage has STORAGE | EDITOR | SCRIPT_VARIABLE bits set.
var is_exported: bool = false

## Resolved element Script for typed array properties (null if not a Resource type).
var element_script: Script = null


# ---------------------------------------------------------------------------
# Factory methods
# ---------------------------------------------------------------------------

## Create a GRDPropertyColumn from a Godot property dictionary.
## The dict comes from Script.get_script_property_list() or
## Object.get_property_list() and contains: name, class_name, type,
## hint, hint_string, usage, etc.
static func from_property_dict(dict: Dictionary) -> GRDPropertyColumn:
	var col := GRDPropertyColumn.new()
	col.name = StringName(dict.get("name", ""))
	col.display_name = String(dict.get("name", ""))
	col.type = int(dict.get("type", 0))
	col.hint = int(dict.get("hint", 0))
	col.hint_string = String(dict.get("hint_string", ""))
	col.usage = int(dict.get("usage", 0))
	col.read_only = (col.usage & PROPERTY_USAGE_READ_ONLY) != 0
	# is_exported requires STORAGE + EDITOR + SCRIPT_VARIABLE — a property
	# that is persisted, visible in the inspector, and driven by @export.
	col.is_exported = (
		(col.usage & PROPERTY_USAGE_STORAGE) != 0
		and (col.usage & PROPERTY_USAGE_EDITOR) != 0
		and (col.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0
	)
	# Resolve element script for typed arrays.
	if col.type == TYPE_ARRAY and not col.hint_string.is_empty():
		col.element_script = resolve_element_script_from_hint(col.hint_string)
	return col


## Build an array of GRDPropertyColumn from a Script's property list.
## Filters to exported/editor-visible/storage properties only,
## excluding built-in Resource props. Base script exports are listed first,
## then derived script exports.
static func from_script(script: Script) -> Array[GRDPropertyColumn]:
	var result: Array[GRDPropertyColumn] = []
	if script == null:
		return result
	var seen: Dictionary = {}
	_append_script_columns_base_first(script, result, seen)
	return result


static func _append_script_columns_base_first(script: Script, result: Array[GRDPropertyColumn], seen: Dictionary) -> void:
	var base_script := script.get_base_script()
	if base_script != null:
		_append_script_columns_base_first(base_script, result, seen)

	for dict in script.get_script_property_list():
		var col := from_property_dict(dict)
		# Only include exported properties (storage + editor + script_variable).
		if not col.is_exported:
			continue
		# Skip built-in Resource properties.
		if col.name in GRDRow._BUILTIN_RESOURCE_PROPS:
			continue
		# get_script_property_list() includes inherited exports; preserve the
		# earliest/base-most occurrence and skip duplicates from derived lists.
		if seen.has(col.name):
			continue
		seen[col.name] = true
		result.append(col)


## Build an array of GRDPropertyColumn from a Resource instance's property list.
## This is the fallback when row_script is not set.
static func from_resource(resource: Resource) -> Array[GRDPropertyColumn]:
	var result: Array[GRDPropertyColumn] = []
	if resource == null:
		return result
	for dict in resource.get_property_list():
		var col := from_property_dict(dict)
		if not col.is_exported:
			continue
		if col.name in GRDRow._BUILTIN_RESOURCE_PROPS:
			continue
		result.append(col)
	return result


# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------

## Get the display name for this column (falls back to name).
func get_display_name() -> String:
	if display_name != "":
		return display_name
	return String(name)


# ---------------------------------------------------------------------------
# Type classification helpers
# ---------------------------------------------------------------------------

## Returns true if the Variant type is a scalar (int, float, string, string_name, bool).
func is_scalar() -> bool:
	return is_bool() or is_numeric() or is_string_like()


## Returns true if the type is TYPE_BOOL.
func is_bool() -> bool:
	return type == TYPE_BOOL


## Returns true if the type is TYPE_INT or TYPE_FLOAT.
func is_numeric() -> bool:
	return type == TYPE_INT or type == TYPE_FLOAT


## Returns true if the type is TYPE_STRING or TYPE_STRING_NAME.
func is_string_like() -> bool:
	return type == TYPE_STRING or type == TYPE_STRING_NAME


## Returns true if the type is TYPE_OBJECT (Resource, Node, etc.).
func is_object() -> bool:
	return type == TYPE_OBJECT


## Returns true if the type is TYPE_ARRAY.
func is_array() -> bool:
	return type == TYPE_ARRAY


## Returns true if the type is TYPE_DICTIONARY.
func is_dictionary() -> bool:
	return type == TYPE_DICTIONARY


## Returns true when the property is a Script-typed resource reference.
## Detected via TYPE_OBJECT + PROPERTY_HINT_RESOURCE_TYPE with hint "Script".
func is_script() -> bool:
	return type == TYPE_OBJECT and hint == PROPERTY_HINT_RESOURCE_TYPE and hint_string == "Script"


## Returns true when the property is a Resource-typed reference
## (any resource type, not just Script).
func is_resource_reference() -> bool:
	return type == TYPE_OBJECT and hint == PROPERTY_HINT_RESOURCE_TYPE


# ---------------------------------------------------------------------------
# File path helpers
# ---------------------------------------------------------------------------

## Returns true when the property hint indicates a project-relative file path
## (PROPERTY_HINT_FILE).
func is_file_path() -> bool:
	return type == TYPE_STRING and hint == PROPERTY_HINT_FILE


## Returns true when the property hint indicates a global (filesystem) file path
## (PROPERTY_HINT_GLOBAL_FILE).
func is_global_file_path() -> bool:
	return type == TYPE_STRING and hint == PROPERTY_HINT_GLOBAL_FILE


## Returns the file filter string for file-path properties.
## The hint_string for PROPERTY_HINT_FILE / PROPERTY_HINT_GLOBAL_FILE contains
## semicolon-separated filter patterns (e.g. "*.tscn;Scene files;*.tres;Resources").
## Returns an empty PackedStringArray when there are no filters or the property
## is not a file path.
func get_file_filter() -> PackedStringArray:
	if not (is_file_path() or is_global_file_path()):
		return PackedStringArray()
	if hint_string.is_empty():
		return PackedStringArray()
	return PackedStringArray(hint_string.split(";", false))


# ---------------------------------------------------------------------------
# Enum helpers
# ---------------------------------------------------------------------------

## Returns true if this property hint indicates an enum type.
func is_enum() -> bool:
	return hint == PROPERTY_HINT_ENUM


## Returns enum values as a PackedStringArray (empty if not an enum).
func get_enum_values() -> PackedStringArray:
	if not is_enum() or hint_string.is_empty():
		return PackedStringArray()
	return PackedStringArray(hint_string.split(",", false))


## Alias for get_enum_values() — returns the same data.
func get_enum_options() -> PackedStringArray:
	return get_enum_values()


# ---------------------------------------------------------------------------
# Resource reference helpers
# ---------------------------------------------------------------------------

## Returns true if this property hint indicates a resource type.
func is_resource() -> bool:
	return hint == PROPERTY_HINT_RESOURCE_TYPE


## Returns the resource base type hint string (e.g. "Texture2D").
func get_resource_type() -> String:
	if not is_resource():
		return ""
	return hint_string


# ---------------------------------------------------------------------------
# Array helpers
# ---------------------------------------------------------------------------

## Returns the element type hint for an Array property.
## For typed arrays (e.g. Array[int]), returns the element type string.
## For untyped arrays, returns an empty string.
func get_array_element_hint() -> String:
	if not is_array():
		return ""
	# hint_string for typed arrays contains the element type class name.
	return hint_string


## Returns true if this is a typed array whose element type resolves to a Resource subclass.
func is_typed_resource_array() -> bool:
	return is_array() and element_script != null


## Attempts to resolve the element Script from a typed array hint_string.
static func resolve_element_script_from_hint(hint_str: String) -> Script:
	var class_name_str: String = _extract_array_element_class_name(hint_str)
	if class_name_str.is_empty():
		return null
	return _resolve_class_script(class_name_str)


## Extracts the class name from a typed array hint_string.
## Handles both plain "ClassName" and Godot 4 "type_int/hint_int:ClassName" formats.
static func _extract_array_element_class_name(hint: String) -> String:
	if hint.is_empty():
		return ""
	# Handle Godot 4 typed array format: "type_int/hint_int:ClassName"
	var colon_pos: int = hint.rfind(":")
	if colon_pos >= 0 and hint.find("/") >= 0:
		var name_part: String = hint.substr(colon_pos + 1).strip_edges()
		if not name_part.is_empty():
			return name_part
	# Plain class name
	return hint.strip_edges()


## Resolves a Script from a global class name via ProjectSettings.
static func _resolve_class_script(class_name_str: String) -> Script:
	if class_name_str.is_empty():
		return null
	for gcls in ProjectSettings.get_global_class_list():
		if gcls.get("class", "") == class_name_str:
			var path: String = gcls.get("path", "")
			if not path.is_empty():
				var loaded = load(path)
				if loaded is Script:
					return loaded as Script
	return null


# ---------------------------------------------------------------------------
# Width hint
# ---------------------------------------------------------------------------

## Returns a suggested column width for spreadsheet display.
## Returns a non-zero hint based on type, or 0 for auto sizing.
func get_width_hint() -> int:
	if width > 0:
		return width
	# Type-based defaults.
	if is_bool():
		return maxi(80, 24 + get_display_name().length() * 8)
	if is_numeric():
		return 100
	if is_enum():
		return 140
	if is_resource_reference():
		return 200
	if is_object():
		return 200
	if is_array():
		return 200
	# Default for strings and unknowns.
	return 150
