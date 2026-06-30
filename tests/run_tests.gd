## Headless test runner for Godot Resource Database addon.
##
## Run with:
##   fgvm g --args "--headless --path /path/to/project --script res://addons/godot-resource-database/tests/run_tests.gd"
##
## Covers:
##   - Runtime GRDRow path resolution and keys (Resource rows only)
##   - Runtime GRDTable queries, indexes, and row access
##   - Runtime GRDQuery fluent builder
##   - Runtime GRDDatabase load and validation
##   - GRDPropertyColumn helpers
##   - GRDTableAsset helpers
##   - GRDDatabaseIssue.format()
##   - GRDResourceCellEditorFactory basic create

extends SceneTree

var _passed := 0
var _failed := 0


func _init() -> void:
	_run_all_tests()
	quit()


func _run_all_tests() -> void:
	print("=== GRD Headless Test Suite (Resource-first) ===\n")

	# --- Runtime: GRDRow path resolution ---
	_test_row_path_resolution()
	_test_row_has_path_vs_null()
	_test_row_dotted_paths()
	_test_row_typed_getters()
	_test_row_keys()
	_test_row_as_dictionary()
	_test_row_resource_only()

	# --- Runtime: GRDTable ---
	_test_table_row_access()
	_test_table_where_eq()
	_test_table_where_eq_null()
	_test_table_find_eq()
	_test_table_where_predicate()
	_test_table_lazy_index()
	_test_table_eager_index()

	# --- Runtime: GRDQuery ---
	_test_query_fluent_chaining()
	_test_query_order_by()
	_test_query_limit_offset()
	_test_query_where_in()
	_test_query_where_ne()
	_test_query_where_gt_lt()
	_test_query_ids()
	_test_query_count()
	_test_query_first()
	_test_query_with_row_mapper()

	# --- Runtime: GRDDatabase ---
	_test_database_load_from_asset()
	_test_database_validation_missing_id()
	_test_database_validation_duplicate_id()
	_test_database_empty_table_name()
	_test_database_dynamic_access()
	_test_database_load_from_path_not_found()

	# --- GRDPropertyColumn ---
	_test_property_column_from_script()
	_test_property_column_from_resource()
	_test_property_column_filters()
	_test_property_column_helpers_scalar()
	_test_property_column_helpers_enum()
	_test_property_column_helpers_resource()
	_test_property_column_helpers_script()
	_test_property_column_helpers_array()
	_test_property_column_helpers_width()

	# --- GRDTableAsset helpers ---
	_test_table_asset_create_row()
	_test_table_asset_get_property_columns()
	_test_table_asset_validate_row_types()
	_test_table_asset_is_resource_first()
	_test_csharp_constants_generation()

	# --- Typed row database ---
	_test_typed_row_database_load()
	_test_typed_row_query_exported_properties()
	_test_typed_row_query_fluent()
	_test_typed_row_database_validation()
	_test_typed_row_database_create_and_query()
	_test_database_row_script_not_resource()

	# --- GRDDatabaseIssue ---
	_test_issue_format()

	# --- GRDResourceCellEditorFactory ---
	_test_resource_cell_editor_scalar()
	_test_resource_cell_editor_bool()
	_test_resource_cell_editor_enum()
	_test_resource_cell_editor_resource_ref()
	_test_resource_cell_editor_array()
	_test_resource_cell_editor_dictionary()
	_test_resource_cell_editor_property_column_integration()
	_test_resource_cell_editor_unlimited_nested_cell_resource_summary()

	print("\n=== Results: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("FAIL")
	else:
		print("OK")


# ===========================================================================
# Helpers
# ===========================================================================

func _assert(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("  PASS: ", description)
	else:
		_failed += 1
		print("  FAIL: ", description)


func _assert_eq(actual: Variant, expected: Variant, description: String) -> void:
	if actual == expected:
		_passed += 1
		print("  PASS: ", description)
	else:
		_failed += 1
		print("  FAIL: ", description, " (expected ", expected, ", got ", actual, ")")


func _make_simple_db() -> GRDDatabase:
	var db_asset := GRDDatabaseAsset.new()
	var table := GRDTableAsset.new()
	table.table_name = &"items"
	table.id_field = &"id"
	table.row_script = TypedTestRow.new().get_script()

	var row1 := TypedTestRow.new()
	row1.id = &"a"
	row1.name = "Alpha"
	row1.hp = 10
	row1.damage = 15.0
	row1.is_active = true
	row1.tags = ["x", "y"]

	var row2 := TypedTestRow.new()
	row2.id = &"b"
	row2.name = "Beta"
	row2.hp = 20
	row2.damage = 25.0
	row2.is_active = true
	row2.tags = ["z"]

	var row3 := TypedTestRow.new()
	row3.id = &"c"
	row3.name = "Gamma"
	row3.hp = 0
	row3.damage = 5.0
	row3.is_active = false
	row3.tags = []

	table.rows = [row1, row2, row3]
	db_asset.tables = [table]
	return GRDDatabase.load_from_asset(db_asset)


# ===========================================================================
# GRDRow path resolution tests
# ===========================================================================

func _test_row_path_resolution() -> void:
	print("\n[Row path resolution]")
	var row := TypedTestRow.new()
	row.id = &"r1"
	row.name = "deep"
	var gr := GRDRow.new(row, &"id")
	_assert_eq(gr.get_value("name"), "deep", "Get exported property value")


func _test_row_has_path_vs_null() -> void:
	print("\n[Row has_path vs null]")
	var row := TypedTestRow.new()
	row.id = &"r1"
	row.name = ""
	var gr := GRDRow.new(row, &"id")
	_assert(gr.has_path("name"), "has_path true for existing (empty) property")
	_assert_eq(gr.get_value("name", "default"), "", "get_value returns empty string (not default)")
	_assert(not gr.has_path("nonexistent"), "has_path false for missing key")
	_assert_eq(gr.get_value("nonexistent", 42), 42, "get_value returns default for missing key")


func _test_row_dotted_paths() -> void:
	print("\n[Row dotted paths]")
	var row := TypedTestRow.new()
	row.id = &"r1"
	row.name = "deep"
	var gr := GRDRow.new(row, &"id")
	_assert_eq(gr.get_value("name"), "deep", "Get exported property via path")
	_assert_eq(gr.get_value("name", "nope"), "deep", "Existing property returns value not default")


func _test_row_typed_getters() -> void:
	print("\n[Row typed getters]")
	var row := TypedTestRow.new()
	row.id = &"r1"
	row.name = "hello"
	row.hp = 42
	row.damage = 3.14
	row.is_active = true
	var gr := GRDRow.new(row, &"id")
	_assert_eq(gr.get_string("name"), "hello", "get_string")
	_assert_eq(gr.get_int("hp"), 42, "get_int")
	_assert_eq(gr.get_float("damage"), 3.14, "get_float")
	_assert_eq(gr.get_bool("is_active"), true, "get_bool")
	_assert_eq(gr.get_string("missing", "default"), "default", "get_string default")
	_assert_eq(gr.get_int("missing", -1), -1, "get_int default")
	_assert_eq(gr.get_float("missing", 0.5), 0.5, "get_float default")
	_assert_eq(gr.get_bool("missing", true), true, "get_bool default")


func _test_row_keys() -> void:
	print("\n[Row keys]")
	var row := TypedTestRow.new()
	row.id = &"r1"
	row.name = "test"
	var gr := GRDRow.new(row, &"id")
	var k := gr.keys()
	_assert(gr.has_key(&"id"), "Row has key 'id'")
	_assert(gr.has_key(&"name"), "Row has key 'name'")
	_assert(gr.has_key(&"hp"), "Row has key 'hp'")
	_assert(not gr.has_key(&"z"), "Row does not have key 'z'")


func _test_row_as_dictionary() -> void:
	print("\n[Row as_dictionary]")
	var row := TypedTestRow.new()
	row.id = &"r1"
	row.name = "test"
	row.hp = 1
	var gr := GRDRow.new(row, &"id")
	var dict := gr.as_dictionary()
	_assert(dict.has("id"), "as_dictionary has 'id'")
	_assert(dict.has("name"), "as_dictionary has 'name'")
	_assert(dict.has("hp"), "as_dictionary has 'hp'")
	_assert_eq(dict["name"], "test", "as_dictionary value name")


func _test_row_resource_only() -> void:
	print("\n[Row resource-only path]")
	var row := TypedTestRow.new()
	row.id = &"test"
	row.name = "only"
	var gr := GRDRow.new(row, &"id")
	_assert_eq(gr.get_resource(), row, "get_resource returns the resource")
	_assert_eq(gr.get_id(), &"test", "get_id returns id field")
	_assert_eq(gr.get_value("name"), "only", "get_value works")


# ===========================================================================
# GRDTable tests
# ===========================================================================

func _test_table_row_access() -> void:
	print("\n[Table row access]")
	var db := _make_simple_db()
	var t := db.get_table(&"items")
	_assert(t != null, "Table exists")
	_assert_eq(t.size(), 3, "Table has 3 rows")
	_assert(t.has_row(&"a"), "Table has row 'a'")
	_assert(t.has_row(&"b"), "Table has row 'b'")
	_assert(not t.has_row(&"z"), "Table does not have row 'z'")
	var all := t.all()
	_assert_eq(all.size(), 3, "all() returns 3 rows")


func _test_table_where_eq() -> void:
	print("\n[Table where_eq]")
	var db := _make_simple_db()
	var t := db.get_table(&"items")
	var results := t.where_eq("hp", 10)
	_assert_eq(results.size(), 1, "where_eq hp=10 returns 1 row")
	if results.size() > 0:
		_assert_eq(results[0].get_id(), "a", "where_eq hp=10 returns row 'a'")


func _test_table_where_eq_null() -> void:
	print("\n[Table where_eq null]")
	var db := _make_simple_db()
	var t := db.get_table(&"items")
	# hp=0 is the null-like value in our data (Gamma has hp=0).
	var results := t.where_eq("hp", 0)
	_assert_eq(results.size(), 1, "where_eq hp=0 returns 1 row (row c)")
	if results.size() > 0:
		_assert_eq(results[0].get_id(), "c", "where_eq hp=0 returns row 'c'")


func _test_table_find_eq() -> void:
	print("\n[Table find_eq]")
	var db := _make_simple_db()
	var t := db.get_table(&"items")
	var found := t.find_eq("name", "Beta")
	_assert(found != null, "find_eq returns non-null")
	if found != null:
		_assert_eq(found.get_id(), "b", "find_eq name=Beta returns row 'b'")
	var not_found := t.find_eq("name", "Nonexistent")
	_assert_eq(not_found, null, "find_eq returns null for missing")


func _test_table_where_predicate() -> void:
	print("\n[Table where predicate]")
	var db := _make_simple_db()
	var t := db.get_table(&"items")
	var results := t.where(func(r: GRDRow) -> bool:
		var hp: Variant = r.get_value("hp")
		return typeof(hp) == TYPE_INT and hp > 15)
	_assert_eq(results.size(), 1, "where hp>15 returns 1 row")
	if results.size() > 0:
		_assert_eq(results[0].get_id(), "b", "where hp>15 returns row 'b'")


func _test_table_lazy_index() -> void:
	print("\n[Table lazy index]")
	var db := _make_simple_db()
	var t := db.get_table(&"items")
	var r1 := t.where_eq("hp", 10)
	_assert_eq(r1.size(), 1, "Lazy index: first where_eq works")
	var r2 := t.where_eq("hp", 20)
	_assert_eq(r2.size(), 1, "Lazy index: second where_eq works")
	if r2.size() > 0:
		_assert_eq(r2[0].get_id(), "b", "Lazy index: hp=20 returns 'b'")


func _test_table_eager_index() -> void:
	print("\n[Table eager index]")
	var db_asset := GRDDatabaseAsset.new()
	var t_asset := GRDTableAsset.new()
	t_asset.table_name = &"eager_t"
	t_asset.id_field = &"id"
	t_asset.row_script = TypedTestRow.new().get_script()
	var r := t_asset.create_row()
	if r is TypedTestRow:
		(r as TypedTestRow).id = &"r1"
		(r as TypedTestRow).hp = 5
	t_asset.rows = [r]
	db_asset.tables = [t_asset]

	var opts := GRDDatabaseOptions.new()
	opts.eager_indexes = true
	var db := GRDDatabase.load_from_asset(db_asset, opts)
	var t := db.get_table(&"eager_t")
	var results := t.where_eq("hp", 5)
	_assert_eq(results.size(), 1, "Eager index: where_eq works after eager build")


# ===========================================================================
# GRDQuery tests
# ===========================================================================

func _test_query_fluent_chaining() -> void:
	print("\n[Query fluent chaining]")
	var db := _make_simple_db()
	var t := db.get_table(&"items")
	var results := t.query().where_gt("hp", 5).where_ne("name", "Beta").to_array()
	_assert_eq(results.size(), 1, "Chained gt+ne returns 1 row")
	if results.size() > 0:
		_assert_eq(results[0].get_id(), "a", "Chained result is row 'a'")


func _test_query_order_by() -> void:
	print("\n[Query order_by]")
	var db := _make_simple_db()
	var t := db.get_table(&"items")
	var results := t.query().order_by("hp", true).to_array()
	_assert_eq(results.size(), 3, "order_by asc: 3 rows")
	if results.size() >= 2:
		_assert_eq(results[0].get_id(), "c", "order_by asc: first is 'c' (hp=0)")
		_assert_eq(results[1].get_id(), "a", "order_by asc: second is 'a' (hp=10)")


func _test_query_limit_offset() -> void:
	print("\n[Query limit/offset]")
	var db := _make_simple_db()
	var t := db.get_table(&"items")
	var all_rows := t.query().order_by("name", true).to_array()
	_assert_eq(all_rows.size(), 3, "All rows ordered")
	var limited := t.query().order_by("name", true).limit(2).to_array()
	_assert_eq(limited.size(), 2, "Limit 2 returns 2 rows")
	var offset := t.query().order_by("name", true).offset(1).limit(1).to_array()
	_assert_eq(offset.size(), 1, "Offset 1 limit 1 returns 1 row")
	if offset.size() > 0:
		_assert_eq(offset[0].get_id(), "b", "Offset 1 is row 'b'")


func _test_query_where_in() -> void:
	print("\n[Query where_in]")
	var db := _make_simple_db()
	var t := db.get_table(&"items")
	var results := t.query().where_in("hp", [10, 30]).to_array()
	_assert_eq(results.size(), 1, "where_in [10,30] returns 1 row")
	if results.size() > 0:
		_assert_eq(results[0].get_id(), "a", "where_in result is 'a'")


func _test_query_where_ne() -> void:
	print("\n[Query where_ne]")
	var db := _make_simple_db()
	var t := db.get_table(&"items")
	var results := t.query().where_ne("name", "Alpha").to_array()
	_assert_eq(results.size(), 2, "where_ne Alpha returns 2 rows")


func _test_query_where_gt_lt() -> void:
	print("\n[Query where_gt/lt]")
	var db := _make_simple_db()
	var t := db.get_table(&"items")
	var gt := t.query().where_gt("hp", 10).to_array()
	_assert_eq(gt.size(), 1, "where_gt hp>10 returns 1")
	var lt := t.query().where_lt("hp", 20).to_array()
	_assert_eq(lt.size(), 2, "where_lt hp<20 returns 2")
	var gte := t.query().where_gte("hp", 20).to_array()
	_assert_eq(gte.size(), 1, "where_gte hp>=20 returns 1")
	var lte := t.query().where_lte("hp", 10).to_array()
	_assert_eq(lte.size(), 2, "where_lte hp<=10 returns 2")


func _test_query_ids() -> void:
	print("\n[Query ids]")
	var db := _make_simple_db()
	var t := db.get_table(&"items")
	var ids := t.query().order_by("hp", true).ids()
	_assert_eq(ids.size(), 3, "ids() returns 3 rows")


func _test_query_count() -> void:
	print("\n[Query count]")
	var db := _make_simple_db()
	var t := db.get_table(&"items")
	var c := t.query().where_gt("hp", 0).count()
	_assert_eq(c, 2, "count where hp>0 = 2")


func _test_query_first() -> void:
	print("\n[Query first]")
	var db := _make_simple_db()
	var t := db.get_table(&"items")
	var f := t.query().where_eq("hp", 20).first()
	_assert(f != null, "first() returns non-null")
	if f != null:
		_assert_eq(f.get_id(), "b", "first hp=20 is 'b'")
	var empty := t.query().where_eq("hp", 999).first()
	_assert_eq(empty, null, "first() returns null when no match")


func _test_query_with_row_mapper() -> void:
	print("\n[Query with row_mapper]")
	var db := _make_simple_db()
	var t := db.get_table(&"items")
	var mapped := t.query().order_by("hp", true).to_array()
	_assert(mapped.size() > 0, "Mapped query returns results")


# ===========================================================================
# GRDDatabase tests
# ===========================================================================

func _test_database_load_from_asset() -> void:
	print("\n[Database load_from_asset]")
	var db := _make_simple_db()
	_assert(db != null, "Database loaded")
	_assert_eq(db.table_count(), 1, "Database has 1 table")
	_assert(db.has_table(&"items"), "Database has 'items' table")


func _test_database_validation_missing_id() -> void:
	print("\n[Database validation: missing ID]")
	var db_asset := GRDDatabaseAsset.new()
	var t := GRDTableAsset.new()
	t.table_name = &"test"
	t.id_field = &"id"
	t.row_script = TypedTestRow.new().get_script()
	var r := t.create_row()
	# Leave id empty to trigger missing_id.
	t.rows = [r]
	db_asset.tables = [t]

	var opts := GRDDatabaseOptions.new()
	opts.strict_ids = false
	var db := GRDDatabase.load_from_asset(db_asset, opts)
	var issues := db.validate()
	var found := false
	for issue in issues:
		if issue.code == "missing_id":
			found = true
	_assert(found, "Validation reports missing_id issue")


func _test_database_validation_duplicate_id() -> void:
	print("\n[Database validation: duplicate ID]")
	var db_asset := GRDDatabaseAsset.new()
	var t := GRDTableAsset.new()
	t.table_name = &"test"
	t.id_field = &"id"
	t.row_script = TypedTestRow.new().get_script()
	var r1 := t.create_row()
	if r1 is TypedTestRow:
		(r1 as TypedTestRow).id = &"dup"
	var r2 := t.create_row()
	if r2 is TypedTestRow:
		(r2 as TypedTestRow).id = &"dup"
	t.rows = [r1, r2]
	db_asset.tables = [t]

	var db := GRDDatabase.load_from_asset(db_asset)
	var issues := db.validate()
	var found := false
	for issue in issues:
		if issue.code == "duplicate_id":
			found = true
	_assert(found, "Validation reports duplicate_id issue")


func _test_database_empty_table_name() -> void:
	print("\n[Database validation: empty table name]")
	var db_asset := GRDDatabaseAsset.new()
	var t := GRDTableAsset.new()
	t.table_name = &""
	t.id_field = &"id"
	db_asset.tables = [t]

	var db := GRDDatabase.load_from_asset(db_asset)
	var issues := db.validate()
	var found := false
	for issue in issues:
		if issue.code == "empty_table_name":
			found = true
	_assert(found, "Validation reports empty_table_name issue")


func _test_database_dynamic_access() -> void:
	print("\n[Database dynamic access]")
	var db := _make_simple_db()
	var t = db._get(&"items")
	_assert(t != null, "Dynamic access returns table")
	_assert(t is GRDTable, "Dynamic access returns GRDTable")


func _test_database_load_from_path_not_found() -> void:
	print("\n[Database load_from_path not found]")
	var db := GRDDatabase.load_from_path("res://nonexistent_path_12345.tres")
	_assert(db != null, "load_from_path returns non-null even for missing file")
	var issues := db.validate()
	var found := false
	for issue in issues:
		if issue.code == "load_failed":
			found = true
	_assert(found, "Validation reports load_failed for missing path")


# ===========================================================================
# GRDPropertyColumn tests
# ===========================================================================

func _test_property_column_from_script() -> void:
	print("\n[PropertyColumn from_script]")
	var cols := GRDPropertyColumn.from_script(TypedTestRow.new().get_script())
	_assert(cols.size() > 0, "from_script returns columns")
	var names: Array[StringName] = []
	for c in cols:
		names.append(c.name)
	_assert(names.has(&"id"), "Has 'id' property")
	_assert(names.has(&"name"), "Has 'name' property")
	_assert(names.has(&"hp"), "Has 'hp' property")
	_assert(names.has(&"damage"), "Has 'damage' property")
	_assert(names.has(&"is_active"), "Has 'is_active' property")
	_assert(names.has(&"tags"), "Has 'tags' property")
	for c in cols:
		if c.name == &"id":
			_assert_eq(c.type, TYPE_STRING_NAME, "id type is TYPE_STRING_NAME")
		if c.name == &"hp":
			_assert_eq(c.type, TYPE_INT, "hp type is TYPE_INT")


func _test_property_column_from_resource() -> void:
	print("\n[PropertyColumn from_resource]")
	var row := TypedTestRow.new()
	row.id = &"test"
	row.name = "Test Row"
	var cols := GRDPropertyColumn.from_resource(row)
	_assert(cols.size() > 0, "from_resource returns columns")
	var names: Array[StringName] = []
	for c in cols:
		names.append(c.name)
	_assert(names.has(&"id"), "Has 'id'")
	_assert(names.has(&"name"), "Has 'name'")


func _test_property_column_filters() -> void:
	print("\n[PropertyColumn filters]")
	var cols := GRDPropertyColumn.from_script(TypedTestRow.new().get_script())
	for c in cols:
		_assert(c.is_exported, "Column '%s' is_exported" % c.name)
		_assert((c.usage & PROPERTY_USAGE_STORAGE) != 0, "Column '%s' has STORAGE" % c.name)
		_assert((c.usage & PROPERTY_USAGE_EDITOR) != 0, "Column '%s' has EDITOR" % c.name)
	var names: Array[StringName] = []
	for c in cols:
		names.append(c.name)
	_assert(not names.has(&"resource_local_to_scene"), "Excludes resource_local_to_scene")
	_assert(not names.has(&"resource_path"), "Excludes resource_path")
	_assert(not names.has(&"resource_name"), "Excludes resource_name")
	_assert(not names.has(&"script"), "Excludes script")


func _test_property_column_helpers_scalar() -> void:
	print("\n[PropertyColumn helpers: scalar]")
	var cols := GRDPropertyColumn.from_script(TypedTestRow.new().get_script())
	var col_map: Dictionary = {}
	for c in cols:
		col_map[c.name] = c

	var id_col: GRDPropertyColumn = col_map[&"id"]
	_assert(id_col.is_scalar(), "id is_scalar")
	_assert(id_col.is_string_like(), "id is_string_like")
	_assert(not id_col.is_numeric(), "id not is_numeric")

	var hp_col: GRDPropertyColumn = col_map[&"hp"]
	_assert(hp_col.is_scalar(), "hp is_scalar")
	_assert(hp_col.is_numeric(), "hp is_numeric")
	_assert(not hp_col.is_string_like(), "hp not is_string_like")

	var bool_col: GRDPropertyColumn = col_map[&"is_active"]
	_assert(bool_col.is_scalar(), "is_active is_scalar")
	_assert(bool_col.is_bool(), "is_active is_bool")
	_assert(not bool_col.is_numeric(), "is_active not is_numeric")

	var tags_col: GRDPropertyColumn = col_map[&"tags"]
	_assert(tags_col.is_array(), "tags is_array")
	_assert(not tags_col.is_scalar(), "tags not is_scalar")


func _test_property_column_helpers_enum() -> void:
	print("\n[PropertyColumn helpers: enum]")
	var cols := GRDPropertyColumn.from_script(TypedTestRow.new().get_script())
	var col_map: Dictionary = {}
	for c in cols:
		col_map[c.name] = c

	var rarity_col: GRDPropertyColumn = col_map[&"rarity"]
	_assert(rarity_col.is_enum(), "rarity is_enum")
	var opts := rarity_col.get_enum_values()
	_assert_eq(opts.size(), 4, "rarity has 4 enum values")
	_assert(opts.has("common"), "rarity has 'common'")
	_assert(opts.has("uncommon"), "rarity has 'uncommon'")
	_assert(opts.has("rare"), "rarity has 'rare'")
	_assert(opts.has("epic"), "rarity has 'epic'")
	var alias_opts := rarity_col.get_enum_options()
	_assert_eq(alias_opts.size(), 4, "get_enum_options alias returns same count")


func _test_property_column_helpers_resource() -> void:
	print("\n[PropertyColumn helpers: resource]")
	var cols := GRDPropertyColumn.from_script(TypedTestRow.new().get_script())
	var col_map: Dictionary = {}
	for c in cols:
		col_map[c.name] = c

	var icon_col: GRDPropertyColumn = col_map[&"icon"]
	_assert(icon_col.is_resource_reference(), "icon is_resource_reference")
	_assert(icon_col.is_object(), "icon is_object")
	_assert_eq(icon_col.get_resource_type(), "Texture2D", "icon resource type = Texture2D")

	var stats_col: GRDPropertyColumn = col_map[&"stats"]
	_assert(stats_col.is_resource_reference(), "stats is_resource_reference")
	_assert_eq(stats_col.get_resource_type(), "NestedTestItem", "stats resource type = NestedTestItem")

	var mod_col: GRDPropertyColumn = col_map[&"modifiers"]
	_assert(mod_col.is_array(), "modifiers is_array")
	_assert(not mod_col.is_resource_reference(), "modifiers not is_resource_reference")


func _test_property_column_helpers_script() -> void:
	print("\n[PropertyColumn helpers: script]")
	var cols := GRDPropertyColumn.from_script(TypedTestRow.new().get_script())
	var col_map: Dictionary = {}
	for c in cols:
		col_map[c.name] = c

	var script_col: GRDPropertyColumn = col_map[&"behavior_script"]
	_assert(script_col.is_script(), "behavior_script is_script")
	_assert(script_col.is_resource_reference(), "behavior_script is_resource_reference")
	_assert_eq(script_col.get_resource_type(), "Script", "behavior_script resource type = Script")


func _test_property_column_helpers_array() -> void:
	print("\n[PropertyColumn helpers: array]")
	var cols := GRDPropertyColumn.from_script(TypedTestRow.new().get_script())
	var col_map: Dictionary = {}
	for c in cols:
		col_map[c.name] = c

	var tags_col: GRDPropertyColumn = col_map[&"tags"]
	_assert(tags_col.is_array(), "tags is_array")
	var elem_hint := tags_col.get_array_element_hint()
	_assert(not elem_hint.is_empty(), "tags has non-empty element hint")

	var mod_col: GRDPropertyColumn = col_map[&"modifiers"]
	_assert(mod_col.is_array(), "modifiers is_array")
	var mod_hint := mod_col.get_array_element_hint()
	_assert(not mod_hint.is_empty(), "modifiers has non-empty element hint")


func _test_property_column_helpers_width() -> void:
	print("\n[PropertyColumn helpers: width]")
	var cols := GRDPropertyColumn.from_script(TypedTestRow.new().get_script())
	var col_map: Dictionary = {}
	for c in cols:
		col_map[c.name] = c

	_assert_eq((col_map[&"is_active"] as GRDPropertyColumn).get_width_hint(), 96, "bool width fits header")
	_assert_eq((col_map[&"hp"] as GRDPropertyColumn).get_width_hint(), 100, "int width = 100")
	_assert_eq((col_map[&"rarity"] as GRDPropertyColumn).get_width_hint(), 140, "enum width = 140")
	_assert_eq((col_map[&"icon"] as GRDPropertyColumn).get_width_hint(), 200, "resource width = 200")
	_assert_eq((col_map[&"behavior_script"] as GRDPropertyColumn).get_width_hint(), 200, "script width = 200")
	_assert_eq((col_map[&"tags"] as GRDPropertyColumn).get_width_hint(), 200, "array width = 200")
	_assert_eq((col_map[&"name"] as GRDPropertyColumn).get_width_hint(), 150, "string width = 150")


# ===========================================================================
# GRDTableAsset helper tests
# ===========================================================================

func _test_table_asset_create_row() -> void:
	print("\n[TableAsset create_row]")
	var ta := GRDTableAsset.new()
	ta.row_script = TypedTestRow.new().get_script()
	var row: Resource = ta.create_row()
	_assert(row != null, "create_row returns non-null")
	_assert(row is TypedTestRow, "create_row returns TypedTestRow")
	if row is TypedTestRow:
		_assert_eq((row as TypedTestRow).id, &"", "New row has empty id")
		_assert_eq((row as TypedTestRow).hp, 0, "New row has hp=0")


func _test_table_asset_get_property_columns() -> void:
	print("\n[TableAsset get_property_columns]")
	var ta := GRDTableAsset.new()
	ta.row_script = TypedTestRow.new().get_script()
	var cols: Array[GRDPropertyColumn] = ta.get_property_columns()
	_assert(cols.size() > 0, "get_property_columns returns columns")
	_assert_eq(cols.size(), ta.get_exported_columns().size(), "get_exported_columns == get_property_columns")
	var names: Array[StringName] = []
	for c in cols:
		names.append(c.name)
	_assert(names.has(&"id"), "Columns include 'id'")
	_assert(names.has(&"hp"), "Columns include 'hp'")


func _test_table_asset_validate_row_types() -> void:
	print("\n[TableAsset validate_row_types]")
	var ta := GRDTableAsset.new()
	ta.row_script = TypedTestRow.new().get_script()
	var good_row: Resource = ta.create_row()
	if good_row is TypedTestRow:
		(good_row as TypedTestRow).id = &"good"
	ta.rows.append(good_row)
	# Add a wrong-type row (a different Resource subclass).
	var bad_row := NestedTestItem.new()
	(bad_row as NestedTestItem).label = "bad"
	ta.rows.append(bad_row)
	var issues: Array[String] = ta.validate_row_types()
	_assert_eq(issues.size(), 1, "validate_row_types finds 1 type mismatch")
	_assert(issues[0].contains("1"), "Issue mentions index 1")


func _test_table_asset_is_resource_first() -> void:
	print("\n[TableAsset is_resource_first]")
	var ta := GRDTableAsset.new()
	ta.row_script = TypedTestRow.new().get_script()
	_assert(ta.is_resource_first(), "row_script set = resource_first")
	ta.row_script = null
	_assert(not ta.is_resource_first(), "no row_script = not resource_first")


func _test_csharp_constants_generation() -> void:
	print("\n[C# constants generation]")
	var db_asset := GRDDatabaseAsset.new()
	var table := GRDTableAsset.new()
	table.table_name = &"items"
	table.id_field = &"id"
	table.row_script = TypedTestRow.new().get_script()

	var sword := TypedTestRow.new()
	sword.id = &"sword"
	sword.name = "Sword"
	var bad_id := TypedTestRow.new()
	bad_id.id = &"1-sword"
	bad_id.name = "Sanitized"
	table.rows = [sword, bad_id]
	db_asset.tables = [table]

	var source := GRDEditorPanel._build_csharp_constants_source(db_asset, "res://database/database.tres")
	_assert(source.contains("using Godot;"), "C# output imports Godot")
	_assert(source.contains("public static partial class Database"), "C# output declares Database partial class")
	_assert(source.contains("public static class Items"), "C# output declares nested table class")
	_assert(source.contains("public static readonly StringName TABLE = \"items\";"), "C# output declares TABLE")
	_assert(source.contains("public static readonly StringName ID_FIELD = \"id\";"), "C# output declares ID_FIELD")
	_assert(source.contains("public static readonly StringName NAME = \"name\";"), "C# output declares column constant")
	_assert(source.contains("public static class Id"), "C# output declares Id class")
	_assert(source.contains("public static readonly StringName SWORD = \"sword\";"), "C# output declares row ID constant")
	_assert(source.contains("public static readonly StringName ID_1_SWORD = \"1-sword\";"), "C# output sanitizes invalid row ID")
	_assert(source.contains("// Identifier sanitized from \"1-sword\"."), "C# output comments sanitized identifiers")


# ===========================================================================
# Typed row database tests
# ===========================================================================

func _make_typed_db() -> GRDDatabase:
	var db_asset := GRDDatabaseAsset.new()
	var table := GRDTableAsset.new()
	table.table_name = &"typed_items"
	table.id_field = &"id"
	table.row_script = TypedTestRow.new().get_script()

	var row1 := TypedTestRow.new()
	row1.id = &"sword"
	row1.name = "Sword"
	row1.hp = 100
	row1.damage = 15.0
	row1.is_active = true
	row1.tags = ["weapon", "melee"]

	var row2 := TypedTestRow.new()
	row2.id = &"shield"
	row2.name = "Shield"
	row2.hp = 200
	row2.damage = 0.0
	row2.is_active = true
	row2.tags = ["armor"]

	var row3 := TypedTestRow.new()
	row3.id = &"potion"
	row3.name = "Potion"
	row3.hp = 0
	row3.damage = 0.0
	row3.is_active = false
	row3.tags = ["consumable"]

	table.rows = [row1, row2, row3]
	db_asset.tables = [table]
	return GRDDatabase.load_from_asset(db_asset)


func _test_typed_row_database_load() -> void:
	print("\n[Typed row database load]")
	var db := _make_typed_db()
	_assert(db != null, "Typed DB loaded")
	_assert_eq(db.table_count(), 1, "Has 1 table")
	_assert(db.has_table(&"typed_items"), "Has typed_items table")
	var t := db.get_table(&"typed_items")
	_assert_eq(t.size(), 3, "Has 3 rows")


func _test_typed_row_query_exported_properties() -> void:
	print("\n[Typed row query exported properties]")
	var db := _make_typed_db()
	var t := db.get_table(&"typed_items")
	var results := t.where_eq("hp", 100)
	_assert_eq(results.size(), 1, "where_eq hp=100 returns 1 row")
	if results.size() > 0:
		_assert_eq(results[0].get_id(), "sword", "hp=100 is sword")
	var by_name := t.where_eq("name", "Shield")
	_assert_eq(by_name.size(), 1, "where_eq name=Shield returns 1 row")
	if by_name.size() > 0:
		_assert_eq(by_name[0].get_id(), "shield", "name=Shield is shield")
	var active := t.where_eq("is_active", true)
	_assert_eq(active.size(), 2, "where_eq is_active=true returns 2 rows")


func _test_typed_row_query_fluent() -> void:
	print("\n[Typed row query fluent]")
	var db := _make_typed_db()
	var t := db.get_table(&"typed_items")
	var results := t.query() \
		.where_eq("is_active", true) \
		.where_gt("hp", 100) \
		.order_by("hp", false) \
		.to_array()
	_assert_eq(results.size(), 1, "Fluent: active + hp>100 returns 1")
	if results.size() > 0:
		_assert_eq(results[0].get_id(), "shield", "Fluent result is shield")


func _test_typed_row_database_validation() -> void:
	print("\n[Typed row database validation]")
	var db_asset := GRDDatabaseAsset.new()
	var table := GRDTableAsset.new()
	table.table_name = &"mixed"
	table.id_field = &"id"
	table.row_script = TypedTestRow.new().get_script()
	var good := TypedTestRow.new()
	good.id = &"good"
	table.rows.append(good)
	# Wrong type row.
	var bad := NestedTestItem.new()
	(bad as NestedTestItem).label = "bad"
	table.rows.append(bad)
	db_asset.tables = [table]

	var db := GRDDatabase.load_from_asset(db_asset)
	var issues := db.validate()
	var found_mismatch := false
	for issue in issues:
		if issue.code == "row_type_mismatch":
			found_mismatch = true
	_assert(found_mismatch, "Validation reports row_type_mismatch")


func _test_typed_row_database_create_and_query() -> void:
	print("\n[Typed row database create and query]")
	var ta := GRDTableAsset.new()
	ta.table_name = &"dynamic_typed"
	ta.id_field = &"id"
	ta.row_script = TypedTestRow.new().get_script()
	var row1: Resource = ta.create_row()
	if row1 is TypedTestRow:
		(row1 as TypedTestRow).id = &"item1"
		(row1 as TypedTestRow).name = "Item One"
		(row1 as TypedTestRow).hp = 50
	ta.rows.append(row1)
	var row2: Resource = ta.create_row()
	if row2 is TypedTestRow:
		(row2 as TypedTestRow).id = &"item2"
		(row2 as TypedTestRow).name = "Item Two"
		(row2 as TypedTestRow).hp = 75
	ta.rows.append(row2)

	var db_asset := GRDDatabaseAsset.new()
	db_asset.tables = [ta]
	var db := GRDDatabase.load_from_asset(db_asset)
	var t := db.get_table(&"dynamic_typed")
	_assert(t != null, "dynamic_typed table exists")
	_assert_eq(t.size(), 2, "Has 2 rows")

	var found := t.find_eq("hp", 75)
	_assert(found != null, "find_eq hp=75 returns non-null")
	if found != null:
		_assert_eq(found.get_id(), "item2", "hp=75 is item2")

	var cols: Array[GRDPropertyColumn] = ta.get_property_columns()
	_assert(cols.size() > 0, "get_property_columns returns data")


func _test_database_row_script_not_resource() -> void:
	print("\n[Database row_script_not_resource]")
	var script := GDScript.new()
	script.source_code = "extends Node\nfunc _init(): pass"
	script.reload()
	var db_asset := GRDDatabaseAsset.new()
	var table := GRDTableAsset.new()
	table.table_name = &"bad_script"
	table.id_field = &"id"
	table.row_script = script
	table.rows = []
	db_asset.tables = [table]
	var db := GRDDatabase.load_from_asset(db_asset)
	var issues := db.validate()
	var found := false
	for issue in issues:
		if issue.code == "row_script_not_resource":
			found = true
	_assert(found, "Validation reports row_script_not_resource when script does not produce Resource")


# ===========================================================================
# GRDDatabaseIssue tests
# ===========================================================================

func _test_issue_format() -> void:
	print("\n[Issue format]")
	var issue := GRDDatabaseIssue.new(
		"test_code",
		"Test message",
		"test/location",
		GRDDatabaseIssue.Severity.WARNING,
	)
	var formatted := issue.format()
	_assert(formatted.contains("WARNING"), "format() contains WARNING")
	_assert(formatted.contains("test_code"), "format() contains code")
	_assert(formatted.contains("Test message"), "format() contains message")
	_assert(formatted.contains("test/location"), "format() contains location")
	var to_str := str(issue)
	_assert_eq(to_str, formatted, "_to_string() equals format()")


# ===========================================================================
# GRDResourceCellEditorFactory tests
# ===========================================================================

func _test_resource_cell_editor_scalar() -> void:
	print("\n[ResourceCellEditor: scalar]")
	var str_col := GRDPropertyColumn.new()
	str_col.name = &"name"
	str_col.type = TYPE_STRING
	var changed_val: Variant = null
	var on_change := func(v: Variant) -> void: changed_val = v
	var ctrl := GRDResourceCellEditorFactory.create_cell_editor(str_col, "hello", null, on_change)
	_assert(ctrl != null, "String editor created")
	_assert(ctrl is LineEdit, "String editor is LineEdit")

	var int_col := GRDPropertyColumn.new()
	int_col.name = &"hp"
	int_col.type = TYPE_INT
	ctrl = GRDResourceCellEditorFactory.create_cell_editor(int_col, 42, null, on_change)
	_assert(ctrl != null, "Int editor created")
	_assert(ctrl is SpinBox, "Int editor is SpinBox")

	var float_col := GRDPropertyColumn.new()
	float_col.name = &"damage"
	float_col.type = TYPE_FLOAT
	ctrl = GRDResourceCellEditorFactory.create_cell_editor(float_col, 3.14, null, on_change)
	_assert(ctrl != null, "Float editor created")
	_assert(ctrl is SpinBox, "Float editor is SpinBox")

	var sn_col := GRDPropertyColumn.new()
	sn_col.name = &"tag"
	sn_col.type = TYPE_STRING_NAME
	ctrl = GRDResourceCellEditorFactory.create_cell_editor(sn_col, &"fast", null, on_change)
	_assert(ctrl != null, "StringName editor created")
	_assert(ctrl is LineEdit, "StringName editor is LineEdit")


func _test_resource_cell_editor_bool() -> void:
	print("\n[ResourceCellEditor: bool]")
	var bool_col := GRDPropertyColumn.new()
	bool_col.name = &"is_active"
	bool_col.type = TYPE_BOOL
	var changed_val: Variant = null
	var on_change := func(v: Variant) -> void: changed_val = v
	var ctrl := GRDResourceCellEditorFactory.create_cell_editor(bool_col, true, null, on_change)
	_assert(ctrl != null, "Bool editor created")
	_assert(ctrl is CheckBox, "Bool editor is CheckBox")
	var check: CheckBox = ctrl as CheckBox
	_assert(check.button_pressed, "CheckBox shows true")


func _test_resource_cell_editor_enum() -> void:
	print("\n[ResourceCellEditor: enum]")
	var enum_col := GRDPropertyColumn.new()
	enum_col.name = &"rarity"
	enum_col.type = TYPE_STRING
	enum_col.hint = PROPERTY_HINT_ENUM
	enum_col.hint_string = "common,uncommon,rare,epic"
	var changed_val: Variant = null
	var on_change := func(v: Variant) -> void: changed_val = v
	var ctrl := GRDResourceCellEditorFactory.create_cell_editor(enum_col, "common", null, on_change)
	_assert(ctrl != null, "Enum editor created")
	_assert(ctrl is OptionButton, "Enum editor is OptionButton")
	var opt: OptionButton = ctrl as OptionButton
	_assert_eq(opt.item_count, 4, "Enum has 4 items")
	_assert_eq(opt.selected, 0, "Enum defaults to first item (common)")


func _test_resource_cell_editor_resource_ref() -> void:
	print("\n[ResourceCellEditor: resource ref]")
	var res_col := GRDPropertyColumn.new()
	res_col.name = &"icon"
	res_col.type = TYPE_OBJECT
	res_col.hint = PROPERTY_HINT_RESOURCE_TYPE
	res_col.hint_string = "Texture2D"
	var changed_val: Variant = null
	var on_change := func(v: Variant) -> void: changed_val = v
	var ctrl := GRDResourceCellEditorFactory.create_cell_editor(res_col, null, null, on_change)
	_assert(ctrl != null, "Resource ref editor created")
	if Engine.is_editor_hint():
		_assert(ctrl is EditorResourcePicker, "Resource ref editor is EditorResourcePicker")
	else:
		_assert(ctrl is Label, "Resource ref editor falls back to Label in headless")


func _test_resource_cell_editor_array() -> void:
	print("\n[ResourceCellEditor: array]")
	var arr_col := GRDPropertyColumn.new()
	arr_col.name = &"tags"
	arr_col.type = TYPE_ARRAY
	var changed_val: Variant = null
	var on_change := func(v: Variant) -> void: changed_val = v
	var ctrl := GRDResourceCellEditorFactory.create_cell_editor(arr_col, ["a", "b"], null, on_change)
	_assert(ctrl != null, "Array editor created")
	_assert(ctrl is HBoxContainer, "Array editor is HBoxContainer")
	var hbox: HBoxContainer = ctrl as HBoxContainer
	_assert_eq(hbox.get_child_count(), 2, "Array editor has label + button")


func _test_resource_cell_editor_dictionary() -> void:
	print("\n[ResourceCellEditor: dictionary]")
	var dict_col := GRDPropertyColumn.new()
	dict_col.name = &"config"
	dict_col.type = TYPE_DICTIONARY
	var ctrl := GRDResourceCellEditorFactory.create_cell_editor(dict_col, {"key": "val"}, null, func(_v: Variant) -> void: pass)
	_assert(ctrl != null, "Dictionary editor created")
	_assert(ctrl is Label, "Dictionary editor is read-only Label")


func _test_resource_cell_editor_property_column_integration() -> void:
	print("\n[ResourceCellEditor: PropertyColumn integration]")
	var cols := GRDPropertyColumn.from_script(TypedTestRow.new().get_script())
	_assert(cols.size() > 0, "Property columns available")

	var row := TypedTestRow.new()
	row.id = &"test"
	row.name = "Test"
	row.hp = 10
	row.damage = 2.5
	row.is_active = true
	row.rarity = "rare"
	row.tags = ["a", "b"]

	for col in cols:
		var on_change := func(v: Variant) -> void: pass
		var value: Variant = row.get(String(col.name))
		var ctrl: Control = GRDResourceCellEditorFactory.create_cell_editor(col, value, row, on_change)
		_assert(ctrl != null, "Editor created for column '%s'" % col.name)

	# Verify name column produces LineEdit.
	var name_ctrl: Control = GRDResourceCellEditorFactory.create_cell_editor(
		cols[1], row.name, row, func(_v: Variant) -> void: pass,
	)
	_assert(name_ctrl is LineEdit, "name column produces LineEdit")
	_assert_eq((name_ctrl as LineEdit).text, "Test", "LineEdit shows correct text")

	var hp_ctrl: Control = GRDResourceCellEditorFactory.create_cell_editor(
		cols[2], row.hp, row, func(_v: Variant) -> void: pass,
	)
	_assert(hp_ctrl is SpinBox, "hp column produces SpinBox")
	_assert_eq((hp_ctrl as SpinBox).value, 10.0, "SpinBox shows correct value")


func _test_resource_cell_editor_unlimited_nested_cell_resource_summary() -> void:
	print("\n[ResourceCellEditor: unlimited nested cell resource summary]")
	var root := NestedCellTestItem.new()
	root.label = "level_0"
	var current := root
	for i in range(1, 6):
		var child := NestedCellTestItem.new()
		child.label = "level_%d" % i
		current.child = child
		current = child

	var summary := GRDResourceCellEditorFactory.resource_summary(root)
	_assert(summary.contains("level_5"), "Summary includes GRDCellResource nesting past previous depth cap")

	current.child = root
	summary = GRDResourceCellEditorFactory.resource_summary(root)
	_assert(summary.contains("NestedCellTestItem[cycle]"), "Summary stops cyclic GRDCellResource nesting")

	var col := GRDPropertyColumn.new()
	col.name = &"child"
	col.type = TYPE_OBJECT
	col.hint = PROPERTY_HINT_RESOURCE_TYPE
	col.hint_string = "NestedCellTestItem"
	var editor_root := NestedCellTestItem.new()
	var ctrl := GRDResourceCellEditorFactory.create_cell_editor(col, editor_root, null, func(_value: Variant) -> void:
		pass
	)
	_assert(ctrl != null, "Recursive GRDCellResource editor is created")
	_assert(editor_root.child == null, "Recursive GRDCellResource editor does not auto-create child forever")

	var container := NestedCellContainerTestItem.new()
	container.children = [NestedCellTestItem.new()]
	var array_col := GRDPropertyColumn.new()
	array_col.name = &"containers"
	array_col.type = TYPE_ARRAY
	array_col.hint_string = "NestedCellContainerTestItem"
	array_col.element_script = NestedCellContainerTestItem.new().get_script()
	ctrl = GRDResourceCellEditorFactory.create_cell_editor(array_col, [container], null, func(_value: Variant) -> void:
		pass
	)
	_assert(_control_tree_contains_text(ctrl, "label"), "Nested GRDCellResource arrays render structured editors")
	_assert(_control_tree_contains_text(ctrl, "Container 1"), "Nested GRDCellResource arrays render parent rows as cards")
	_assert(_control_tree_contains_text(ctrl, "+ Add Container"), "Nested GRDCellResource array add button uses item label")


func _control_tree_contains_text(ctrl: Control, text: String) -> bool:
	if ctrl is Button and (ctrl as Button).text == text:
		return true
	if ctrl is Label and (ctrl as Label).text == text:
		return true
	for child in ctrl.get_children():
		if child is Control and _control_tree_contains_text(child as Control, text):
			return true
	return false
