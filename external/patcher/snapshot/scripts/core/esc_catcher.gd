extends Node
## Calls on_esc when Esc is pressed (UI.choice dialogs: Esc cancels).

var on_esc: Callable


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and on_esc.is_valid() and is_inside_tree():
		get_viewport().set_input_as_handled()   # (before: the callback may change scene)
		on_esc.call()
