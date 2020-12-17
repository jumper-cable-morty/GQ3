# Singleton

extends Node

func _ready():
	pause_mode = PAUSE_MODE_PROCESS # This script can't get paused
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("tilde"):
		if get_tree().paused:
#			Save.save_game() # Save when you leave the game. You can remove this line
			get_tree().quit()
		
		get_tree().paused = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
	if Input.is_mouse_button_pressed(BUTTON_LEFT):
		get_tree().paused = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
