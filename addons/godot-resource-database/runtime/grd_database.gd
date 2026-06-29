class_name GRDDatabase
extends RefCounted

## Root database context that wraps a GRDDatabaseAsset into a queryable
## collection of tables. No editor-only APIs are used.

var _tables: Dictionary = {}   # StringName -> GRDTable
var _options: GRDDatabaseOptions
var _issues: Array[GRDDatabaseIssue] = []
var _asset: GRDDatabaseAsset = null
var _source_path: String = ""


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

## Load a database from a GRDDatabaseAsset resource path.
static func load_from_path(
	path: String,
	options: GRDDatabaseOptions = null,
) -> GRDDatabase:
	if options == null:
		options = GRDDatabaseOptions.new()

	var asset: Resource = load(path)
	if asset == null:
		var db: GRDDatabase = GRDDatabase.new()
		db._source_path = path
		db._options = options
		db._issues.append(GRDDatabaseIssue.new(
			"load_failed",
			"Cannot load resource: " + path,
			path,
		))
		return db

	if not (asset is GRDDatabaseAsset):
		var db: GRDDatabase = GRDDatabase.new()
		db._source_path = path
		db._options = options
		db._issues.append(GRDDatabaseIssue.new(
			"invalid_asset",
			"Resource is not a GRDDatabaseAsset: " + path,
			path,
		))
		return db

	return load_from_asset(asset as GRDDatabaseAsset, options, path)


## Load a database from an already-loaded GRDDatabaseAsset.
## Optional source_path is recorded for issue location context.
static func load_from_asset(
	asset: GRDDatabaseAsset,
	options: GRDDatabaseOptions = null,
	source_path: String = "",
) -> GRDDatabase:
	var db: GRDDatabase = GRDDatabase.new()
	db._asset = asset
	db._source_path = source_path

	if options == null:
		options = GRDDatabaseOptions.new()
	db._options = options

	for table_asset in asset.tables:
		if table_asset == null:
			continue
		db._add_table_asset(table_asset)

	db._validate()

	if options.eager_indexes:
		db._build_all_indexes()

	return db


# ---------------------------------------------------------------------------
# Table access
# ---------------------------------------------------------------------------

func get_table(name: StringName) -> GRDTable:
	return _tables.get(name, null)


func table(name: StringName) -> GRDTable:
	return get_table(name)


func try_get_table(name: StringName) -> GRDTable:
	return get_table(name)


func has_table(name: StringName) -> bool:
	return _tables.has(name)


func table_names() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for key in _tables:
		out.append(String(key))
	return out


## Number of tables in the database.
func table_count() -> int:
	return _tables.size()


# ---------------------------------------------------------------------------
# Diagnostics
# ---------------------------------------------------------------------------

func get_issues() -> Array[GRDDatabaseIssue]:
	return _issues.duplicate()


func validate() -> Array[GRDDatabaseIssue]:
	return get_issues()


# ---------------------------------------------------------------------------
# Dynamic sugar
# ---------------------------------------------------------------------------

func _get(property: StringName) -> Variant:
	if not _options.enable_dynamic_access:
		return null
	return _tables.get(property, null)


# ---------------------------------------------------------------------------
# Internal: table construction
# ---------------------------------------------------------------------------

func _add_table_asset(table_asset: GRDTableAsset) -> void:
	var table_name: StringName = table_asset.table_name

	# Validate empty table names.
	if table_name == &"":
		_issues.append(GRDDatabaseIssue.new(
			"empty_table_name",
			"A table asset has an empty table_name.",
			_source_path,
			GRDDatabaseIssue.Severity.WARNING,
		))
		# Still add with an empty-string name so the data isn't silently lost.

	# Validate duplicate table names.
	if _tables.has(table_name):
		_issues.append(GRDDatabaseIssue.new(
			"duplicate_table_name",
			"Duplicate table name '%s' — later table overwrites earlier." % String(table_name),
			_source_path + "/" + String(table_name),
			GRDDatabaseIssue.Severity.WARNING,
		))

	var table: GRDTable = GRDTable.new(table_asset, _options)
	# Collect issues raised during table construction (directory load failures, etc.).
	_issues.append_array(table.get_build_issues())
	_tables[table_name] = table


## Validates all tables: IDs, row types.
func _validate() -> void:
	for table_name in _tables:
		var table: GRDTable = _tables[table_name]
		var ta: GRDTableAsset = _find_table_asset(table_name)
		var table_loc: String = String(table_name)

		# --- Typed row validation ---
		if ta != null:
			_validate_typed_rows(ta, table_loc)

		# --- ID validation ---
		_validate_ids(table, table_loc, ta)


## Validates Resource-first table setup: row_script, row types, non-null rows.
func _validate_typed_rows(ta: GRDTableAsset, table_loc: String) -> void:
	# When row_script is set, validate it can produce a Resource instance.
	if ta.row_script != null:
		var test_row: Resource = ta.create_row()
		if test_row == null:
			_issues.append(GRDDatabaseIssue.new(
				"row_script_not_resource",
				"row_script in table '%s' does not produce a Resource instance." % table_loc,
				table_loc,
				GRDDatabaseIssue.Severity.ERROR,
			))

		# Validate row types match row_script.
		var type_issues: Array[String] = ta.validate_row_types()
		for msg in type_issues:
			_issues.append(GRDDatabaseIssue.new(
				"row_type_mismatch",
				"Table '%s': %s" % [table_loc, msg],
				table_loc,
				GRDDatabaseIssue.Severity.WARNING,
			))

	# Non-null rows check.
	for i in ta.rows.size():
		if ta.rows[i] == null:
			_issues.append(GRDDatabaseIssue.new(
				"null_row",
				"Table '%s' has a null row at index %d." % [table_loc, i],
				table_loc,
				GRDDatabaseIssue.Severity.ERROR,
			))


## Validates duplicate/missing IDs across all rows.
func _validate_ids(table: GRDTable, table_loc: String, ta: GRDTableAsset) -> void:
	var seen_ids: Dictionary = {}
	var id_field_name: String = String(ta.id_field) if ta != null else String(_options.id_field)

	for row in table.all():
		var raw_id: Variant = row.get_id()

		# Missing ID.
		if raw_id == null or str(raw_id).is_empty():
			var severity: GRDDatabaseIssue.Severity
			if _options.strict_ids:
				severity = GRDDatabaseIssue.Severity.ERROR
			else:
				severity = GRDDatabaseIssue.Severity.WARNING
			_issues.append(GRDDatabaseIssue.new(
				"missing_id",
				"Row in table '%s' has no value for id_field '%s'." % [table_loc, id_field_name],
				table_loc,
				severity,
			))
			continue

		var id_str: String = str(raw_id)

		# Duplicate ID.
		if seen_ids.has(id_str):
			_issues.append(GRDDatabaseIssue.new(
				"duplicate_id",
				"Duplicate id '%s' in table '%s'." % [id_str, table_loc],
				table_loc + "/" + id_str,
				GRDDatabaseIssue.Severity.ERROR,
			))
		seen_ids[id_str] = true


## Find the GRDTableAsset for a given table name in the source asset.
func _find_table_asset(table_name: StringName) -> GRDTableAsset:
	if _asset == null:
		return null
	for ta in _asset.tables:
		if ta != null and ta.table_name == table_name:
			return ta
	return null


func _build_all_indexes() -> void:
	for table_name in _tables:
		var table: GRDTable = _tables[table_name]
		var rows: Array[GRDRow] = table.all()
		if rows.is_empty():
			continue
		var sample: GRDRow = rows[0]
		for key in sample.keys():
			if GRDTable._is_scalar(sample.get_value(String(key))):
				table.ensure_index(String(key))
