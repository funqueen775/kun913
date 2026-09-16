extends Node


func _ready() -> void:
	var events: Array = WorldClock.MAIN_EVENTS
	if events.size() != 24:
		_fail("主线事件数量应为 24，实际为 %d" % events.size())
		return
	for index in events.size():
		var event: Dictionary = events[index]
		var expected_id := "M%d-E%02d" % [index / 4 + 1, index + 1]
		if String(event.get("id", "")) != expected_id:
			_fail("事件 %d 的 ID 应为 %s" % [index + 1, expected_id])
			return
		if (event.get("choices", []) as Array).size() != 3:
			_fail("%s 必须有 3 个选项" % expected_id)
			return
		if (event.get("outcome", {}) as Dictionary).size() != 3:
			_fail("%s 必须有 3 条结果反馈" % expected_id)
			return
		if (event.get("memoryNote", {}) as Dictionary).size() != 3:
			_fail("%s 必须有 3 条记忆便签" % expected_id)
			return
	var last: Dictionary = events.back()
	if int(last.get("month", 0)) != 48 or String(last.get("id", "")) != "M6-E24":
		_fail("终局事件必须是第 48 月的 M6-E24")
		return
	print("FULL_STORY_SCHEDULE_PASS acts=6 events=24 end_month=48")
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error("FULL_STORY_SCHEDULE_FAIL " + message)
	get_tree().quit(1)
