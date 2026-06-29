class_name GRDDatabaseIssue
extends RefCounted


enum Severity {
	ERROR,
	WARNING,
	INFO,
}


var code: String
var message: String
var location: String
var severity: Severity


func _init(
	p_code: String = "",
	p_message: String = "",
	p_location: String = "",
	p_severity: Severity = Severity.ERROR,
) -> void:
	code = p_code
	message = p_message
	location = p_location
	severity = p_severity


## Returns a human-readable representation of this issue.
## Format: "[SEVERITY] code: message (location)"
func format() -> String:
	return "[%s] %s: %s (%s)" % [Severity.keys()[severity], code, message, location]


func _to_string() -> String:
	return format()
