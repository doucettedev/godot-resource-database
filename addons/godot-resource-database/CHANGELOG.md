# Changelog

All notable changes to Godot Resource Database are documented here.

This project uses [Semantic Versioning](https://semver.org/). While the addon is pre-1.0, breaking API changes increment the minor version.

## [0.2.0]

### Breaking Changes

- Renamed row/table schema APIs for clearer table-first terminology:
  - `GRDRowSchema` -> `GRDTableSchema`
  - `GRDPropertyColumn` -> `GRDColumn`
  - `GRDDatabaseIssue` -> `GRDValidationIssue`
- Renamed the editor factory script from `grd_property_editor_factory.gd` to `grd_cell_editor_factory.gd`.

### Added

- File menu and editor UX improvements.
- GDScript constant generation for table names, column names, row IDs, and runtime table access.
- Inline editing support for complex `GRDCellSchema` values.
- README sections reserved for screenshots of the editor, table references, and complex cell schemas.

### Changed

- Refined README setup, schema, querying, and editor feature documentation.
- Improved spreadsheet editor panel behavior and validation display.

## [0.1.0] - Initial release

### Added

- Godot editor plugin for Resource-backed database tables.
- Spreadsheet-style editor tab for table rows and exported schema properties.
- Runtime `GRDDatabase`, `GRDTable`, `GRDRow`, and query APIs.
- Validation for duplicate IDs, table names, schema mismatches, null rows, and row type issues.
