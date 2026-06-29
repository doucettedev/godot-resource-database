# Godot Resource Database

A Godot editor plugin that provides a spreadsheet-like database editing experience backed by Godot `Resource` files. Query, validate, and edit resource-based tables without leaving the editor.

## Installation

1. Copy the `addons/godot-resource-database/` folder into your project's `addons/` directory.
2. Open **Project > Project Settings > Plugins** and enable **Godot Resource Database**.
3. The **Resource DB** tab will appear in the editor.

## Asset Model

| Resource | Purpose |
|---|---|
| `GRDRowSchema` | Base class for table schemas — extends this for each table |
| `GRDCellResource` | Base class for nested editable cell resources within a row |
| `GRDDatabaseAsset` | Top-level collection of tables |
| `GRDTableAsset` | One table: name, id field, rows, row_script |
| `GRDPropertyColumn` | Column descriptor derived from `@export` property metadata |
| `GRDRow` | Lightweight adapter over Resource-backed rows |

## Quickstart

### 1. Define Table Schemas

Top-level table schemas go under `res://database/schema/` and extend `GRDRowSchema`. Exported properties become spreadsheet columns automatically.

```gdscript
class_name ItemsSchema
extends GRDRowSchema

@export var icon: Texture2D
@export_file("*.tscn") var scene: String
@export var in_demo: bool
@export var stats: Array[StatValueSchema]
@export var upgrade_1: UpgradeSchema


func get_sticky_columns() -> PackedStringArray:
    return PackedStringArray(["id", "icon"])
```

### 2. Define Nested Cell Resources

Editable cells that need structured data extend `GRDCellResource`. These show up as inline editable cells in the spreadsheet.

```gdscript
class_name StatValueSchema
extends GRDCellResource

@export var stat: StatsSchema
@export var flat: float
@export var percent: float
```

### 3. Create the Database

Create or open `res://database/database.tres` (a `GRDDatabaseAsset`). Add a `GRDTableAsset` for each table and set:

| Property | Description |
|---|---|
| `table_name` | Unique name for lookup (e.g. `&"items"`) |
| `id_field` | Property on each row used as its ID (default `&"id"`) |
| `row_script` | The `GRDRowSchema` script for this table |

All `@export` properties on the row script become columns in the spreadsheet. Override `get_sticky_columns()` to pin columns to the left (optional).

### 4. Querying

Generate constants from the editor panel first: **More > Generate GDScript constants**. This writes a sibling script next to the database asset, named from the asset file. For `res://database/database.tres`, the generated script is `res://database/database.gd` with `class_name Database`.

Use the generated class for both constants and runtime table access:

```gdscript
var items := Database.table(Database.Items.TABLE)
var sword := items.get_row(Database.Items.Id.SWORD)
print(sword.get_value(Database.Items.NAME))
```

The generated script includes:

- one inner class per table
- `TABLE`, `ID_FIELD`, column constants, and row ID constants
- `raw`, the loaded `GRDDatabase`
- `table(name)`, a shortcut for `raw.get_table(name)`

You can also load a database manually when you need a different asset at runtime:

```gdscript
var db := GRDDatabase.load_from_path("res://database/database.tres")
var table: GRDTable = db.get_table(&"items")

# Find by equality (uses lazy index).
var rows := table.where_eq("name", "Sword")
for r in rows:
    print(r.get_id(), " -> ", r.get_value("damage"))

# Fluent query builder.
var strong := table.query() \
    .where_gt("damage", 5) \
    .order_by("damage", false) \
    .limit(3) \
    .to_array()

# Predicate filter.
var expensive := table.where(func(r: GRDRow) -> bool:
    return r.get_value("damage", 0) > 100)
```

### Dotted Path Access

```gdscript
# Resolves nested Resource properties, Dictionary keys, and arrays.
var first_tag := row.get_value("tags.0", "")
var label := row.get_value("stats.label", "")
```

## Runtime Query API

### GRDDatabase

| Method | Description |
|---|---|
| `load_from_path(path, options)` | Load from a `.tres`/`.res` path |
| `load_from_asset(asset, options)` | Load from an already-loaded asset |
| `get_table(name)` | Get a table by name |
| `has_table(name)` | Check if a table exists |
| `table_names()` | All table names |
| `table_count()` | Number of tables |
| `validate()` / `get_issues()` | Validation issues from loading |

### GRDTable

| Method | Description |
|---|---|
| `all()` | All rows in insertion order |
| `get_row(id)` | Row by ID |
| `size()` | Row count |
| `where_eq(field, value)` | Equality query (indexed) |
| `find_eq(field, value)` | First match |
| `where(predicate)` | Predicate filter |
| `query()` | Fluent query builder |

### GRDQuery (fluent builder)

| Method | Description |
|---|---|
| `where_eq`, `where_ne`, `where_gt`, `where_gte`, `where_lt`, `where_lte` | Comparison filters |
| `where_in(field, array)` | Value in candidate set |
| `where_contains(field, value)` | Array membership |
| `where_any(field)` | Nested array-element query |
| `where(predicate)` | Custom predicate |
| `order_by(field, ascending)` | Sort results |
| `limit(n)`, `offset(n)` | Pagination |
| `to_array()`, `first()`, `count()`, `ids()` | Terminal operations |

### GRDRow

| Method | Description |
|---|---|
| `get_id()` | Row identifier |
| `get_value(path, default)` | Dotted path resolution |
| `has_path(path)` | Path existence check |
| `keys()` | Visible column names |
| `as_dictionary()` | All keys/values as Dictionary |
| `get_string`, `get_int`, `get_float`, `get_bool` | Typed getters |

## Editor Features

- Open/select a `GRDDatabaseAsset` by path or file dialog
- List tables with row counts and resource-first indicators
- Row script picker for setting typed Resource scripts
- Spreadsheet-style row/column view with property-derived columns
- Inline cell editors for `String`, `StringName`, `int`, `float`, `bool`, enums, `Resource` references, `Script` references, and `Array` properties
- Visible-cell search (filters displayed rows)
- Validation panel showing errors, warnings, and info issues
- Add/remove rows (uses `create_row()` with auto-ID)
- Dirty tracking with explicit Save semantics

## Validation

`GRDDatabase.validate()` reports issues at load time:

- Duplicate/missing row IDs
- Empty/duplicate table names
- Row type mismatches (rows don't match `row_script`)
- Row script does not produce a `Resource` instance
- Null rows

Issues have three severity levels: `ERROR`, `WARNING`, and `INFO`. Use `format()` or `str(issue)` for human-readable output.
