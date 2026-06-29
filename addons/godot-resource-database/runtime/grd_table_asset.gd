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
@export var row_script: Script = null


# ---------------------------------------------------------------------------
# Resource-first helpers (active API)
# ---------------------------------------------------------------------------

## Returns the row_script, or null if not set.
func get_row_script() -> Script:
	return row_script


## Creates a new row Resource instance using row_script.
## Returns null if row_script is not set.
func create_row() -> Resource:
	if row_script == null:
		return null
	var instance: Object = row_script.new()
	if instance is Resource:
		return instance as Resource
	return null


## Returns property columns derived from row_script's exported properties.
## This is the primary column source for the spreadsheet editor.
## Falls back to sampling the first row's property list if row_script is null.
func get_property_columns() -> Array[GRDPropertyColumn]:
	if row_script != null:
		return GRDPropertyColumn.from_script(row_script)
	# Fallback: sample the first row.
	if not rows.is_empty() and rows[0] != null and rows[0] is Resource:
		return GRDPropertyColumn.from_resource(rows[0] as Resource)
	return []


## Alias for get_property_columns() — returns the same data.
func get_exported_columns() -> Array[GRDPropertyColumn]:
	return get_property_columns()


## Validates that all rows match the expected type when row_script is set.
## Returns an array of issue descriptions (empty = all valid).
func validate_row_types() -> Array[String]:
	var issues: Array[String] = []
	if row_script == null:
		return issues
	for i in rows.size():
		var res: Resource = rows[i]
		if res == null:
			issues.append("Row %d is null" % i)
			continue
		if not _script_matches_row(res, row_script):
			issues.append("Row %d script does not extend %s" % [i, str(row_script)])
	return issues


## Returns the id_field, defaulting to &"id" when empty.
func get_id_field() -> StringName:
	return id_field if id_field != &"" else &"id"


## Returns true if this table uses the canonical Resource-first path.
## (row_script is set — directory mode is no longer supported).
func is_resource_first() -> bool:
	return row_script != null


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
