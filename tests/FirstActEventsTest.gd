extends Node

## 第一幕主线事件的 Godot 集成测试（v2.3：M1-E02B 复活后第一幕 5 件）。
##
## 驱动的是真实链路：小镇节点 → _enter_nearby_zone() → StoryEventPanel 演出。
## 面板是 beats 分镜版（无旧版 "intro" 页）：入场拍（entry，2.3s 动画，玩家点击可跳过）
## → say/narration/interact 分镜 → 选择拍（choices）→ 结果拍（outcome）→ 结算收起。

const MAIN_SCENE := preload("res://Main.tscn")
const OUTPUT_DIR := "res://test_artifacts"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var expected := [
		{"id": "M1-E01", "month": 1, "day": 1, "hour": 9, "zone": "B", "title": "新员工手册"},
		{"id": "M1-E02B", "month": 2, "day": 1, "hour": 9, "zone": "A", "title": "第一次被轻视"},
		{"id": "M1-E02", "month": 3, "day": 1, "hour": 9, "zone": "A", "title": "技术选型"},
		{"id": "M1-E03", "month": 5, "day": 1, "hour": 9, "zone": "B", "title": "评测集要不要建"},
		{"id": "M1-E04", "month": 7, "day": 1, "hour": 23, "zone": "B", "title": "AI 代码标注"},
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
		if panel == null or not panel.is_open():
			_fail("%s 进入 %s 区后未显示事件面板" % [spec["id"], spec["zone"]])
			return
		if panel.current_stage() != "entry":
			_fail("%s 事件面板未先进入入场拍（stage=%s）" % [spec["id"], panel.current_stage()])
			return
		if not _tree_has_text(panel, String(spec["title"])):
			_fail("%s 入场卡标题错误" % spec["id"])
			return
		await RenderingServer.frame_post_draw
		_save_screenshot("%s_entry.png" % String(spec["id"]).to_lower())
		# 跳过入场动画（= 玩家在动画途中点击）
		panel._advance()
		await get_tree().process_frame
		# 一路点到「选择拍」：打字中点击只补字，下一拍要再点一次
		if not await _drive_to_choices(panel, String(spec["id"])):
			return
		var choices: Node = panel.get_node("EventOverlay/UiLayer")
		var choice_count := 0
		for child in choices.get_children():
			if child.name.begins_with("Choice_"):
				choice_count += 1
		if choice_count != 3:
			_fail("%s 选项数量为 %d" % [spec["id"], choice_count])
			return
		await RenderingServer.frame_post_draw
		_save_screenshot("%s_choices.png" % String(spec["id"]).to_lower())
		var hit := panel.get_node_or_null("EventOverlay/UiLayer/Choice_option_b/Hit_option_b") as Button
		if hit == null:
			_fail("%s 找不到选项 option_b 按钮" % spec["id"])
			return
		hit.pressed.emit()
		await get_tree().process_frame
		if panel.current_stage() != "outcome":
			_fail("%s 选择后未进入结果拍（stage=%s）" % [spec["id"], panel.current_stage()])
			return
		# 结果拍打字机：第一次点补字，第二次点结算收起
		panel._advance()
		panel._advance()
		await get_tree().process_frame
		if panel.is_open():
			_fail("%s 完成选择后面板没有关闭" % spec["id"])
			return
		var next_event := WorldClock.next_main_event()
		if index < expected.size() - 1 and String(next_event.get("id", "")) != String(expected[index + 1]["id"]):
			_fail("%s 完成后没有切换到下一事件" % spec["id"])
			return
		if index == expected.size() - 1:
			# 第一幕五件全做完后，主线继续到第二幕第一件（M2-E05）
			if String(next_event.get("id", "")) != "M2-E05":
				_fail("第一幕五件完成后应轮到 M2-E05，实际=%s" % String(next_event.get("id", "?")))
				return
		town.free()
		await get_tree().process_frame
	if not _test_time_gates(expected):
		return
	print("FIRST_ACT_EVENTS_PASS events=5 entries=5 choices_each=3 locations=B,A,A,B,B event4_hour=23")
	get_tree().quit(0)


## 从入场拍之后一路点到选择拍：处理打字机（两次点击一拍）、interact（翻开手册）。
func _drive_to_choices(panel, event_id: String) -> bool:
	var guard := 0
	while panel.current_stage() != "choices" and guard < 80:
		match panel.current_stage():
			"handbook":
				panel._handbook.close()
			_:
				panel._advance()
		await get_tree().process_frame
		guard += 1
	if panel.current_stage() != "choices":
		_fail("%s 未能进入选择拍（stage=%s）" % [event_id, panel.current_stage()])
		return false
	return true


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
