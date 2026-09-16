extends Control

## 宿舍屏开窗自检：连拍 平时 / 宵禁 两张图。
## 只 new DormRoom 面板自己 present，不驱动 WorldClock、不碰玩家存档。
const SHOT_DIR := "E:/03_Projects/bear/.workbuddy/tmp/shots"

var _dorm


func _ready() -> void:
	_dorm = load("res://scripts/DormRoom.gd").new()
	add_child(_dorm)
	await _wait(0.6)

	_dorm.present(false)
	await _wait(0.4)
	await _shot("00_day")

	_dorm.present(true)
	await _wait(0.4)
	await _shot("01_curfew")

	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/dorm_%s.png" % [SHOT_DIR, name]
	var error := image.save_png(path)
	print("shot %s -> %s (%s)" % [name, path, error])
