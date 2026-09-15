extends Node

const MAIN_SCENE := preload("res://Main.tscn")
const OUTPUT_DIR := "res://test_artifacts"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var expected := [
		{"id": "M1-E01", "month": 1, "day": 15, "hour": 9, "zone": "B", "title": "新员工手册"},
		{"id": "M1-E02", "month": 3, "day": 15, "hour": 9, "zone": "A", "title": "技术选型"},
		{"id": "M1-E03", "month": 5, "day": 15, "hour": 9, "zone": "B", "title": "评测集要不要建"},
		{"id": "M1-E04", "month": 7, "day": 15, "hour": 23, "zone": "B", "title": "AI 代码标注"},
	]
	for index in expected.size():
		var spec: Dictionary = expected[index]
		WorldClock.set("_completed_main_event_ids", _prior_ids(expected, index))
		WorldClock.world_minute = _world_minute(spec)
		WorldClock.running = false
		var town := MAIN_SCENE.instantiate()
		add_child(town)
		await get_tree().process_frame
		await get_tree().process_frame
		var zone := _find_zone(town.ZONES, String(spec["zone"]))
		if zone.is_empty():
			_fail("%s 找不到区域 %s" % [spec["id"], spec["zone"]])
			return
		town.set("_nearby_zone", zone)
		town.call("_enter_nearby_zone")
		await get_tree().process_frame
		var panel = town.get("_story_event_panel")
		if panel == null or not panel.is_open() or panel.current_stage() != "intro":
			_fail("%s 进入 %s 区后未显示介绍" % [spec["id"], spec["zone"]])
			return
		if not _tree_has_text(panel, String(spec["title"])):
			_fail("%s 介绍页标题错误" % spec["id"])
			return
		await RenderingServer.frame_post_draw
		_save_screenshot("%s_intro.png" % String(spec["id"]).to_lower())
		var continue_button := panel.get_node("EventOverlay/StoryIntro/ContinueButton") as Button
		continue_button.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		if panel.current_stage() != "choices":
			_fail("%s 点击继续后未显示选项" % spec["id"])
			return
		var choices: Node = panel.get_node("EventOverlay/StoryChoices")
		var choice_count := 0
		for child in choices.get_children():
			if child is Button and child.name.begins_with("Choice_"):
				choice_count += 1
		if choice_count != 3:
			_fail("%s 选项数量为 %d" % [spec["id"], choice_count])
			return
		await RenderingServer.frame_post_draw
		_save_screenshot("%s_choices.png" % String(spec["id"]).to_lower())
		var choice_button := panel.get_node("EventOverlay/StoryChoices/Choice_option_b") as Button
		choice_button.pressed.emit()
		await get_tree().process_frame
		if panel.is_open():
			_fail("%s 完成选择后面板没有关闭" % spec["id"])
			return
		var next_event := WorldClock.next_main_event()
		if index < expected.size() - 1 and String(next_event.get("id", "")) != String(expected[index + 1]["id"]):
			_fail("%s 完成后没有切换到下一事件" % spec["id"])
			return
		if index == expected.size() - 1 and not next_event.is_empty():
			_fail("第一幕四个事件完成后仍有待办事件")
			return
		town.free()
		await get_tree().process_frame
	if not _test_time_gates(expected):
		return
	print("FIRST_ACT_EVENTS_PASS events=4 intros=4 choices_each=3 locations=B,A,B,B event4_hour=23")
	get_tree().quit(0)


func _test_time_gates(expected: Array) -> bool:
	var completed: Array[String] = []
	WorldClock.set("_completed_main_event_ids", completed)
	WorldClock.set("_minute_remainder", 0.0)
	WorldClock.world_minute = 9 * 60
	WorldClock.running = false
	for spec: Dictionary in expected:
		WorldClock.running = true
		WorldClock.advance_minutes(float(WorldClock.MINUTES_PER_DAY * 240))
		if WorldClock.running or WorldClock.world_minute != _world_minute(spec):
			_fail("%s 时间闸门不正确，实际=%d 预期=%d running=%s" % [spec["id"], WorldClock.world_minute, _world_minute(spec), WorldClock.running])
			return false
		WorldClock.complete_main_event(String(spec["id"]))
	return true


func _prior_ids(expected: Array, count: int) -> Array[String]:
	var ids: Array[String] = []
	for index in count:
		ids.append(String(expected[index]["id"]))
	return ids


func _find_zone(zones: Array, code: String) -> Dictionary:
	for zone: Dictionary in zones:
		if String(zone.get("code", "")) == code:
			return zone
	return {}


func _world_minute(spec: Dictionary) -> int:
	return ((int(spec["month"]) - 1) * WorldClock.DAYS_PER_MONTH + int(spec["day"]) - 1) * WorldClock.MINUTES_PER_DAY + int(spec["hour"]) * 60


func _tree_has_text(root: Node, text: String) -> bool:
	if root is Label and (root as Label).text.contains(text):
		return true
	for child in root.get_children():
		if _tree_has_text(child, text):
			return true
	return false


func _save_screenshot(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path("%s/%s" % [OUTPUT_DIR, file_name]))
	if error != OK:
		_fail("截图保存失败：%s" % error_string(error))


func _fail(message: String) -> void:
	push_error("FIRST_ACT_EVENTS_FAIL " + message)
	get_tree().quit(1)
