extends Control

## 宿舍「自己走出门」的真实游戏验收截图：起的是 Main.tscn 本体（带时间面板等小镇 HUD），
## 输入走真实的 InputMap 通道（`Input.action_press`），和玩家按 WASD 是同一条路。
## 用法：Godot --path <PROJ> --resolution 1920x1080 res://tools/dorm_ingame_shot.tscn
const SHOT_DIR := "E:/03_Projects/bear/.workbuddy/tmp/shots"

var _town: Node


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_town = (load("res://Main.tscn") as PackedScene).instantiate()
	add_child(_town)
	await _settle()
	await _shot("10_ingame_spawn")

	# 自己按 ↓ 走到门口：走的是小镇 → 宿舍那条真实的输入转发链
	Input.action_press("move_down")
	await _wait(1.6)
	Input.action_release("move_down")
	await _settle()
	print("[shot] spot=", _town._dorm.active_spot_id(), " pos=", _town._dorm.player_image_position())
	await _shot("11_ingame_at_door")

	_town._dorm.handle_key(KEY_E)
	await _settle()
	await _shot("12_ingame_confirm")

	get_tree().quit()


func _settle() -> void:
	for _index in 4:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/dorm_%s.png" % [SHOT_DIR, name]
	var error := image.save_png(path)
	print("[shot] %s -> err=%d" % [path, error])
