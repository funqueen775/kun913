extends Control

## 剧情演出开窗自检：连拍 入场 / 旁白 / 说话 / 可交互 / 手册 / 选项 / 结果 / 独处 共 8 张图。
const SHOT_DIR := "E:/03_Projects/bear/.workbuddy/tmp/shots"
## 入场拍自动跳走需要 CARD_IN + HOLD + OUT（0.35 + 1.45 + 0.5）秒，留点余量。
const ENTRY_WAIT := 2.6
## 打字机每 0.022 秒出 2 字，最长的一段话也在 2 秒内出完。
const TYPE_WAIT := 2.0

var _panel: CanvasLayer


func _ready() -> void:
	_panel = load("res://scripts/StoryEventPanel.gd").new()
	add_child(_panel)
	await _run_e01()
	await _run_e04()
	await _run_e02()
	get_tree().quit()


## E01：小熊 + 王哥两人在场，中间真的翻开手册，最后三章选一。
func _run_e01() -> void:
	_panel.present(WorldClock.MAIN_EVENTS[0])
	await _wait(1.2)
	await _shot("00_entry")
	await _wait(ENTRY_WAIT)
	await _wait(TYPE_WAIT)
	await _shot("01_narration")
	await _goto_beat(1)
	await _shot("02_xiaoxiong_say")
	await _goto_beat(2)
	await _shot("03_wange_say")
	await _goto_beat(5)
	await _shot("04_xiaoxiong_handbook")
	await _goto_beat(6)
	await _shot("05_interact")
	_panel._advance()
	await _wait(1.0)
	await _shot("06_handbook")
	_panel._handbook.close()
	await _wait(0.8)
	await _shot("07_choices")
	_panel._on_choice_picked("M1-E01", "option_b", 45)
	await _wait(2.6)
	await _shot("08_outcome")


## E04：空场独处（cast 为空）—— 对照 E01 的两人在场。
func _run_e04() -> void:
	_panel.present(WorldClock.MAIN_EVENTS[3])
	await _wait(ENTRY_WAIT + TYPE_WAIT)
	await _shot("09_e04_alone")


## E02：双立绘，选项要能和两个人同时站住。
func _run_e02() -> void:
	_panel.present(WorldClock.MAIN_EVENTS[1])
	await _wait(ENTRY_WAIT + TYPE_WAIT)
	_panel._advance()
	await _wait(0.8)
	await _shot("10_e02_two_cast_choices")
	_panel._on_choice_picked("M1-E02", "option_a", 60)
	await _wait(2.6)
	await _shot("11_e02_gray_note")


## 推进到指定 beat：打字中第一次点击只是把字补满，所以要循环到 beat_index 真的到达。
func _goto_beat(index: int) -> void:
	var guard := 0
	while _panel.beat_index() < index and guard < 24:
		_panel._advance()
		await _wait(TYPE_WAIT)
		guard += 1
	await _wait(0.4)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/story_%s.png" % [SHOT_DIR, name]
	var error := image.save_png(path)
	print("shot %s -> %s (%s)" % [name, path, error])
