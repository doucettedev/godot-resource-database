class_name GRDExampleItemRow
extends Resource

## Example typed row script for the Godot Resource Database.
## This demonstrates how to define a custom row with exported properties
## that the editor and runtime can read.

@export var id: StringName = &""
@export var display_name: String = ""
@export var damage: int = 0
@export var speed: float = 1.0
@export var is_consumable: bool = false
@export var tags: Array[String] = []
