extends Node

# Frontend transport boundary for the OpenAPI contract. The backend is not
# deployed yet, so mock mode preserves every raw event locally and never blocks play.
signal session_ready(session: Dictionary)
signal event_recorded(envelope: Dictionary, response: Dictionary)
signal chat_recorded(npc_id: String, message: String)
signal transport_warning(message: String)

const CONFIG_PATH := "res://data/integration/api_config.json"
const QUEUE_PATH := "user://workplace_town_api_queue.json"
const SESSION_PATH := "user://workplace_town_api_session.json"

var _mode := "mock"
var _base_url := ""
var _content_version := "v1"
var _session_id := ""
var _queue: Array = []

func _ready() -> void:
	_load_config()
	_load_local_state()

func start_or_resume() -> Dictionary:
	if _session_id.is_empty():
		_session_id = _uuid_v4()
		_save_session()
	var session := {
		"sessionId": _session_id,
		"contentVersion": _content_version,
		"state": {"chapterId":"M1", "currentNodeId":"M1-E01", "unlockedRegionIds":["A", "H"]}
	}
	session_ready.emit(session)
	return session

func record_event(event_type: String, payload: Dictionary, duration_seconds := 0) -> Dictionary:
	var session := start_or_resume()
	var envelope := {
		"eventId": _uuid_v4(),
		"eventType": event_type,
		"contentVersion": _content_version,
		"clientTime": _iso_time(),
		"durationSeconds": maxi(0, duration_seconds),
		"payload": payload.duplicate(true),
	}
	_queue.append(envelope)
	_save_queue()
	# M4 has not exposed a real server URL. The local response mirrors only the
	# contract's transport shape; it never derives score or progression locally.
	var response := {"eventId": envelope["eventId"], "accepted": true, "duplicate": false, "state": session["state"]}
	event_recorded.emit(envelope, response)
	if _mode == "live":
		if _base_url.is_empty() or _base_url.contains("example.com") or _content_version != "v1":
			transport_warning.emit("未发送到后端：当前剧情版本或服务地址尚未完成联调，事件已安全保存在本地队列。")
		else:
			transport_warning.emit("后端实时发送尚未实现；事件已安全保存在本地队列。")
	return response

func record_npc_chat(npc_id: String, message: String, region_id: String) -> void:
	record_event("npc_dialogue_complete", {"regionId":region_id, "npcId":npc_id, "messageLength":message.length()})
	chat_recorded.emit(npc_id, message)

func pending_event_count() -> int:
	return _queue.size()

func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	var config = JSON.parse_string(file.get_as_text())
	if config is Dictionary:
		_mode = String(config.get("mode", _mode))
		_base_url = String(config.get("baseUrl", _base_url)).rstrip("/")
		_content_version = String(config.get("contentVersion", _content_version))

func _load_local_state() -> void:
	if FileAccess.file_exists(SESSION_PATH):
		var session_file := FileAccess.open(SESSION_PATH, FileAccess.READ)
		var session = JSON.parse_string(session_file.get_as_text())
		if session is Dictionary:
			_session_id = String(session.get("sessionId", ""))
	if FileAccess.file_exists(QUEUE_PATH):
		var queue_file := FileAccess.open(QUEUE_PATH, FileAccess.READ)
		var saved_queue = JSON.parse_string(queue_file.get_as_text())
		if saved_queue is Array:
			_queue = saved_queue

func _save_session() -> void:
	var file := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"sessionId":_session_id, "contentVersion":_content_version}))

func _save_queue() -> void:
	var file := FileAccess.open(QUEUE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_queue))

func _iso_time() -> String:
	var value := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02dT%02d:%02d:%02d+08:00" % [value.year, value.month, value.day, value.hour, value.minute, value.second]

func _uuid_v4() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var hex := ""
	for index in 32:
		hex += "%x" % rng.randi_range(0, 15)
	return "%s-%s-4%s-%s%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(13, 3), "89ab"[rng.randi_range(0, 3)], hex.substr(17, 3), hex.substr(20, 12)]
