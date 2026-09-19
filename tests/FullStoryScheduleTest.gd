extends Node


func _ready() -> void:
	var events: Array = WorldClock.MAIN_EVENTS
	# 2026-09-19（v2.3）：E02/E13/E15 三件复活进 MAIN_EVENTS，主线从 24 件扩到 27 件
	# （M1-E02B 插第一幕，M2-E09/M2-E10 插第二幕）。
	if events.size() != 27:
		_fail("主线事件数量应为 27，实际为 %d" % events.size())
		return
	for index in events.size():
		var event: Dictionary = events[index]
		if (event.get("choices", []) as Array).size() != 3:
			_fail("%s 必须有 3 个选项" % String(event.get("id", "?")))
			return
		if (event.get("outcome", {}) as Dictionary).size() != 3:
			_fail("%s 必须有 3 条结果反馈" % String(event.get("id", "?")))
			return
		if (event.get("memoryNote", {}) as Dictionary).size() != 3:
			_fail("%s 必须有 3 条记忆便签" % String(event.get("id", "?")))
			return
	var last: Dictionary = events.back()
	if int(last.get("month", 0)) != 48 or String(last.get("id", "")) != "M6-E24":
		_fail("终局事件必须是第 48 月的 M6-E24")
		return
	print("FULL_STORY_SCHEDULE_PASS events=27 end_month=48")
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error("FULL_STORY_SCHEDULE_FAIL " + message)
	get_tree().quit(1)
