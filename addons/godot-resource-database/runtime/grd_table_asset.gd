@tool
class_name GRDTableAsset
extends Resource

## A table of typed Resource rows. This is the canonical runtime contract.
## Rows are Godot Resources with exported properties; the spreadsheet
## columns are derived from those property definitions.

## Unique table name used for lookup.
@export var table_name: StringName = &""

## Property name read from each row resource to obtain its ID.
@export var id_field: StringName = &"id"

## Embedded rows. Each row is a Resource with exported properties.
@export var rows: Array[Resource] = []

## The Script class that defines the row's exported properties.
## When set, create_row() uses this to instantiate new rows, and
## get_property_columns() derives columns from this script's exports.
@export var schema: Script = null


# ---------------------------------------------------------------------------
# Resource-first helpers (active API)
# ---------------------------------------------------------------------------

## Returns the schema, or null if not set.
func get_schema() -> Script:
	return schema


## Creates a new row Resource instance using schema.
## Returns null if schema is not set.
func create_row() -> Resource:
	if schema == null:
		return null
	var instance: Object = schema.new()
	if instance is Resource:
		return instance as Resource
	return null


## Returns property columns derived from schema's exported properties.
## This is the primary column source for the spreadsheet editor.
## Falls back to sampling the first row's property list if schema is null.
func get_property_columns() -> Array[GRDColumn]:
	if schema != null:
		return GRDColumn.from_script(schema)
	# Fallback: sample the first row.
	if not rows.is_empty() and rows[0] != null and rows[0] is Resource:
		return GRDColumn.from_resource(rows[0] as Resource)
	return []


## Alias for get_property_columns() — returns the same data.
func get_exported_columns() -> Array[GRDColumn]:
	return get_property_columns()


## Validates that all rows match the expected type when schema is set.
## Returns an array of issue descriptions (empty = all valid).
func validate_row_types() -> Array[String]:
	var issues: Array[String] = []
	if schema == null:
		return issues
	for i in rows.size():
		var res: Resource = rows[i]
		if res == null:
			issues.append("Row %d is null" % i)
			continue
		if not _script_matches_row(res, schema):
			issues.append("Row %d script does not extend %s" % [i, str(schema)])
	return issues


## Returns the id_field, defaulting to &"id" when empty.
func get_id_field() -> StringName:
	return id_field if id_field != &"" else &"id"


## Returns true if this table uses the canonical Resource-first path.
## (schema is set — directory mode is no longer supported).
func is_resource_first() -> bool:
	return schema != null


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

## Returns true when the resource's script is or extends the target script.
func _script_matches_row(res: Resource, target: Script) -> bool:
	var scr: Script = res.get_script()
	if scr == null:
		return false
	while scr != null:
		if scr == target:
			return true
		scr = scr.get_base_script()
	return false
