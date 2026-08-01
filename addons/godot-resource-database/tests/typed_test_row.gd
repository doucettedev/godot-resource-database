class_name TypedTestRow
extends Resource

## A typed Resource row for testing the Resource-first architecture.
## Exercises enum, resource-reference, script, nested, and array metadata
## to prove GRDColumn filters and helpers.

@export var id: StringName = &""
@export var name: String = ""
@export var hp: int = 0
@export var damage: float = 0.0
@export var is_active: bool = true
@export var tags: Array[String] = []
@export var aliases: Array[StringName] = []
@export var levels: Array[int] = []
@export var spawn_times_minutes: Array[float] = []
@export var toggles: Array[bool] = []
@export var exceptionally_long_property_header_for_width: int = 0

## Enum column — @export_enum gives PROPERTY_HINT_ENUM.
@export_enum("common", "uncommon", "rare", "epic") var rarity: String = "common"

## Resource reference column — PROPERTY_HINT_RESOURCE_TYPE.
@export var icon: Texture2D = null

## Nested Resource reference — another typed Resource.
@export var stats: NestedTestItem = null

## Array of nested Resources.
@export var modifiers: Array[NestedTestItem] = []

## Script-typed reference (PROPERTY_HINT_RESOURCE_TYPE with hint "Script").
@export var behavior_script: Script = null
