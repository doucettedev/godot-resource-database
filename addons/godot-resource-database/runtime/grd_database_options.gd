class_name GRDDatabaseOptions
extends RefCounted

## Global fallback for the property name used to read row IDs.
## Used when a GRDTableAsset.id_field is empty (default &"" means "use this").
var id_field: StringName = &"id"

## When true, rows missing the configured id_field produce ERROR issues.
## When false, missing IDs produce WARNING issues instead.
var strict_ids: bool = true

## Enable _get dynamic property sugar so db.table_name works at runtime.
var enable_dynamic_access: bool = true

## Build equality indexes for all scalar fields eagerly on load instead of lazily.
var eager_indexes: bool = false
