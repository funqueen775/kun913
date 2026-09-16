extends Control

## 心湖记忆墙开窗自检：连拍 空墙 / 满墙 / 点开一张 三张图。
## 造句子用的是事件目录里真实的 memoryNote / outcome 文案，
## 但**只走 show_records()，不碰磁盘** —— 玩家的真实存档一个字节都不动。
const SHOT_DIR := "E:/03_Projects/bear/.workbuddy/tmp/shots"

var _wall


func _ready() -> void:
	_wall = load("res://scripts/MemoryWallPanel.gd").new()
	add_child(_wall)
	await _wait(0.5)

	_wall.show_records([])
	await _wait(0.4)
	await _shot("00_empty")

	_wall.show_records(_sample())
	await _wait(0.5)
	await _shot("01_wall")

	# 点开第 7 张（金便签）：它旁边那张是默认选中的灰便签，
	# 同一屏里能同时看到"被拿起来的那张"和"还贴在墙上的那张"。
	_wall._select(6)
	await _wait(0.4)
	await _shot("02_review")

	get_tree().quit()


## 从事件目录取真实的便签文案造 8 张：4 个事件 × 2 个选项。
func _sample() -> Array:
	var records: Array = []
	var minute := 0
	for value in WorldClock.MAIN_EVENTS:
		var event := Dictionary(value)
		var notes: Dictionary = event.get("memoryNote", {})
		var outcomes: Dictionary = event.get("outcome", {})
		var choices: Dictionary = {}
		for item in event.get("choices", []) as Array:
			var choice := Dictionary(item)
			choices[String(choice.get("id", ""))] = String(choice.get("text", ""))
		var taken := 0
		for choice_id in notes.keys():
			if taken >= 2:
				break
			var note := Dictionary(notes[choice_id])
			minute += 60 * 24 * 3
			records.append({
				"eventId": String(event.get("id", "")),
				"eventTitle": String(event.get("title", "")),
				"actTitle": String(event.get("actTitle", "")),
				"month": int(event.get("month", 1)),
				"day": int(event.get("day", 1)),
				"choiceId": String(choice_id),
				"choiceText": String(choices.get(choice_id, "")),
				"text": String(note.get("text", "")),
				"tone": String(note.get("tone", "gold")),
				"outcome": String(outcomes.get(choice_id, "")),
				"worldMinute": minute,
			})
			taken += 1
	return records


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/wall_%s.png" % [SHOT_DIR, name]
	var error := image.save_png(path)
	print("shot %s -> %s (%s)" % [name, path, error])
