@tool
class_name GRDValidationPanel
extends VBoxContainer

## Displays GRDDatabase.validate() issues in a collapsible panel with
## severity-colored entries.  No broad new validation rules are added;
## this is a display component for existing GRDDatabaseIssue data.

var _toggle_btn: Button
var _issue_rtl: RichTextLabel


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	add_theme_constant_override("separation", GRDTheme.scaled_int(4))
	var header: HBoxContainer = HBoxContainer.new()
	add_child(header)

	_toggle_btn = Button.new()
	_toggle_btn.text = "Validation (0 issues)"
	_toggle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GRDTheme.style_button(_toggle_btn)
	_toggle_btn.pressed.connect(_on_toggle)
	header.add_child(_toggle_btn)

	_issue_rtl = RichTextLabel.new()
	_issue_rtl.bbcode_enabled = true
	_issue_rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_issue_rtl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_issue_rtl.custom_minimum_size.y = GRDTheme.scaled(60.0)
	_issue_rtl.scroll_active = true
	_issue_rtl.visible = false
	GRDTheme.style_rich_text(_issue_rtl, GRDTheme.FONT_SIZE)
	add_child(_issue_rtl)


## Replaces the displayed issues.
func set_issues(issues: Array[GRDDatabaseIssue]) -> void:
	var count: int = issues.size()
	_toggle_btn.text = "Validation (%d issue%s)" % [
		count, "" if count == 1 else "s",
	]

	if issues.is_empty():
		_issue_rtl.text = "[color=#%s]No issues found.[/color]" % GRDTheme.SUCCESS.to_html(false)
		_issue_rtl.visible = true
		return

	var parts: PackedStringArray = PackedStringArray()
	for issue in issues:
		var color: String
		match issue.severity:
			GRDDatabaseIssue.Severity.ERROR:
				color = "#" + GRDTheme.ERROR.to_html(false)
			GRDDatabaseIssue.Severity.WARNING:
				color = "#" + GRDTheme.WARNING.to_html(false)
			_:
				color = "#" + GRDTheme.TEXT_MUTED.to_html(false)
		parts.append("[color=%s]%s[/color]" % [color, issue._to_string()])
	_issue_rtl.text = "\n".join(parts)
	_issue_rtl.visible = true


## Clears all displayed issues.
func clear() -> void:
	_toggle_btn.text = "Validation (0 issues)"
	_issue_rtl.text = ""
	_issue_rtl.visible = false


func _on_toggle() -> void:
	_issue_rtl.visible = not _issue_rtl.visible
