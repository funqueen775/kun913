extends Node

# Frontend transport boundary for the OpenAPI contract.
#
# 两种模式（由 data/integration/api_config.json 的 mode 决定）：
#   mock —— 事件只进本地队列，一个网络包都不发。行为与接入前完全一致（默认值）。
#   live —— 队列当重传缓冲：2xx 才出队；网络错误/超时/5xx 留在队头下轮重试；
#           4xx 说明 payload 本身不合格，重试一百次也一样 → 出队并明确告警（不静默丢、
#           也不让一颗坏事件把整条队列堵死）。
#
# live 下 sessionId 必须由服务端签发：后端 POST /events 会先查会话存在性，
# 客户端自带的 uuid 会一路 404 —— 所以 start_or_resume() 会先去换一个回来。
#
# 红线：这里只做传输。不落分数、不推剧情、不解释规则 —— 权威永远在服务端。
signal session_ready(session: Dictionary)
signal session_established(session_id: String)
signal event_recorded(envelope: Dictionary, response: Dictionary)
signal chat_recorded(npc_id: String, message: String)
signal transport_warning(message: String)
signal report_ready(report: Dictionary)   # GET /report 的成功回包（整份三层报告）
signal report_failed(reason: String)      # 拉不到报告的原因（mock 未接 / 404 未生成 / 网络错）

const CONFIG_PATH := "res://data/integration/api_config.json"
const QUEUE_PATH := "user://workplace_town_api_queue.json"
const SESSION_PATH := "user://workplace_town_api_session.json"
# 被后端拒收（4xx）的事件在这里留底，一行一条 JSONL —— 出队是为了不堵队列，
# 但玩家的选择不能真丢，事后可以从这个文件回捞。
const REJECTED_PATH := "user://workplace_town_api_rejected.jsonl"

const API_PREFIX := "/api/v1"
const CLIENT_CONTENT_VERSION := "v1"   # 后端只认这个版本；等于它才允许 live 发包
const FLUSH_INTERVAL := 2.0            # 重传轮询间隔（秒）
const REQUEST_TIMEOUT := 8.0           # 单次请求超时（秒）

var _mode := "mock"
var _base_url := ""
var _content_version := "v1"
var _session_id := ""
var _queue: Array = []
## 服务端最近一次下发的会话状态。**职级与处境的唯一权威来源**（2026-09-17 拍板）：
## Godot 只负责显示，本地不算也不镜像一份，否则同一个东西会有两份会漂移的真相。
## 没接到之前留空 —— 消费方按「还不知道」降级，绝不本地估算一个看起来像的值。
var _server_state: Dictionary = {}

var _http: HTTPRequest
var _flush_timer: Timer
var _in_flight := false          # HTTPRequest 同一时刻只允许一个请求在飞，重复 request() 返回 ERR_BUSY
var _in_flight_kind := ""        # "session" / "event"
var _session_confirmed := false  # 服务端是否签发过当前 sessionId
var _last_warning := ""          # 连续相同的告警只报一次，别每 2 秒刷屏

func _ready() -> void:
	_load_config()
	_load_local_state()
	# HTTPRequest 是节点，必须挂在树上才会转发信号。
	_http = HTTPRequest.new()
	_http.name = "Http"
	_http.timeout = REQUEST_TIMEOUT
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	# 重传轮询：什么模式都挂着，非 live 时 _flush_next 第一行就返回。
	_flush_timer = Timer.new()
	_flush_timer.name = "FlushTimer"
	_flush_timer.wait_time = FLUSH_INTERVAL
	_flush_timer.autostart = true
	add_child(_flush_timer)
	_flush_timer.timeout.connect(_flush_next)

func start_or_resume() -> Dictionary:
	if _live_ready():
		# live：sessionId 由服务端签发，客户端自带的 uuid 会被 404。
		if _session_id.is_empty():
			_session_id = _uuid_v4()      # 占位，服务端 id 到达后替换
		if not _session_confirmed:
			_ensure_session()
	elif _session_id.is_empty():
		# mock：保持接入前的行为，本地自己生成 id。
		_session_id = _uuid_v4()
		_save_session()
	# 有服务端状态就用它，没有才退回本地占位形状（首次握手是异步的，
	# 第一次调用拿不到很正常；session_established 之后自然就接上了）。
	var initial: Dictionary = {"chapterId":"M1", "currentNodeId":"M1-E01", "unlockedRegionIds":["A", "H"]}
	var session := {
		"sessionId": _session_id,
		"contentVersion": _content_version,
		"state": _server_state.duplicate(true) if not _server_state.is_empty() else initial,
	}
	session_ready.emit(session)
	return session


## 服务端下发的最新会话状态（只读副本）。空字典 = 还没接到服务端任何回包，
## 或者当前是 mock 模式 —— 调用方要按「还不知道」处理，不要编。
func server_state() -> Dictionary:
	return _server_state.duplicate(true)


## 每次拿到服务端回包都刷新权威状态。302 重定向之外的所有成功响应都带 state。
func _absorb_state(response: Dictionary) -> void:
	var state = response.get("state", {})
	if state is Dictionary and not (state as Dictionary).is_empty():
		_server_state = (state as Dictionary).duplicate(true)
	var sid := String(response.get("sessionId", ""))
	if not sid.is_empty():
		_session_id = sid

## 连接状态：会话是否已被服务端签发过。UI 拿它显示「已连接/未连接」，
## 探针拿它判断还需不需要等 session_established —— 那个信号每个会话只会发一次。
func is_session_confirmed() -> bool:
	return _session_confirmed

## 当前会话 id。未确认时是本地占位值（服务端不认），确认后是服务端签发的权威 id。
func current_session_id() -> String:
	return _session_id

## 契约硬要求：每个事件的 payload.regionId 必须是 A–H 单字母，缺了或错了会被服务端 400 拒收
## （server.py post_event）。与其让每个埋点各自兜底 —— FreeTimePanel 有、WorkplaceTown 好几处
## 没有，漏一个就静默丢一批事件 —— 统一在传输层补齐：先认 regionId，再从 zone / locationId
## 这类同义字段推断，都落空才退回总部 "A"。宁可标成总部，也不要发空串让整条事件被隔离。
## 2026-09-18：隔离日志里 112 条事件正是这么丢的（node_enter 传空串、explore_click 缺字段）。
static func normalize_region_id(payload: Dictionary) -> String:
	for key in ["regionId", "zone", "locationId", "region", "zoneId"]:
		var raw := String(payload.get(key, "")).strip_edges()
		if raw.is_empty():
			continue
		var code := raw.split("_")[0].to_upper()
		if code.length() == 1 and "ABCDEFGH".contains(code):
			return code
	return "A"

func record_event(event_type: String, payload: Dictionary, duration_seconds := 0) -> Dictionary:
	var session := start_or_resume()
	var safe_payload: Dictionary = payload.duplicate(true)
	safe_payload["regionId"] = normalize_region_id(safe_payload)
	var envelope := {
		"eventId": _uuid_v4(),
		"eventType": event_type,
		"contentVersion": _content_version,
		"clientTime": _iso_time(),
		"durationSeconds": maxi(0, duration_seconds),
		"payload": safe_payload,
	}
	_queue.append(envelope)
	_save_queue()
	# 返回值只镜像契约的传输形状，供调用方做本地反馈（调用方一律忽略它）。
	# 真正的 accepted / state 以服务端响应为准，走 event_recorded 信号回来。
	var response := {"eventId": envelope["eventId"], "accepted": true, "duplicate": false, "state": session["state"]}
	event_recorded.emit(envelope, response)
	if _mode == "live" and not _live_ready():
		_warn("未发送到后端：剧情版本或服务地址尚未填好，事件已安全保存在本地队列。")
	elif _live_ready():
		_flush_next()
	return response

func record_npc_chat(npc_id: String, message: String, region_id: String) -> void:
	record_event("npc_dialogue_complete", {"regionId":region_id, "npcId":npc_id, "messageLength":message.length()})
	chat_recorded.emit(npc_id, message)

func pending_event_count() -> int:
	return _queue.size()


## 拉取报告（GET /sessions/{sid}/report）。Batch 3（2026-09-17）：
## 沿用同一个 HTTPRequest 串行骨架（kind="report"），不开第二套传输。
## 红线：报告只在服务端算 —— mock 模式下这里就是拿不到报告，如实说，不做本地兜底计算
## （scoring_cards 不得下发前端，本地没有可算的数据）。
func fetch_report() -> void:
	if not _live_ready():
		report_failed.emit("报告只在服务端生成。当前未连接后端（mode=%s），配好 live 后再来。" % _mode)
		return
	if _in_flight:
		report_failed.emit("上一个请求还在路上，稍等一下再试。")
		return
	if not _session_confirmed:
		# 本地还没换到权威 sessionId：先去要一个，用户稍后再点。
		_ensure_session()
		report_failed.emit("正在向服务端要会话，稍等一两秒再点一次。")
		return
	_in_flight = true
	_in_flight_kind = "report"
	var err := _http.request(
		"%s%s/sessions/%s/report" % [_base_url, API_PREFIX, _session_id],
		PackedStringArray(), HTTPClient.METHOD_GET)
	if err != OK:
		_in_flight = false
		_in_flight_kind = ""
		report_failed.emit("请求未能发出（错误码 %d）。" % err)

## live 是否真的可以发包：mode=live + 地址合规 + 版本等于后端认的那个。
func _live_ready() -> bool:
	return _mode == "live" and not _base_url.is_empty() \
		and not _base_url.contains("example.com") \
		and _content_version == CLIENT_CONTENT_VERSION

## 串行发送队头事件。HTTPRequest 一次只能有一个请求在飞，所以必须一个一个来。
func _flush_next() -> void:
	if not _live_ready() or _in_flight:
		return
	if not _session_confirmed:
		_ensure_session()
		return
	if _queue.is_empty():
		return
	var envelope: Dictionary = _queue[0]
	_in_flight = true
	_in_flight_kind = "event"
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Idempotency-Key: %s" % String(envelope.get("eventId", "")),
	])
	var err := _http.request(
		"%s%s/sessions/%s/events" % [_base_url, API_PREFIX, _session_id],
		headers, HTTPClient.METHOD_POST, JSON.stringify(envelope))
	if err != OK:
		_in_flight = false
		_in_flight_kind = ""
		_warn("请求未能发出（错误码 %d），事件留在本地队列等待重试。" % err)

## 向服务端要一个权威 sessionId。失败不阻塞游戏，下一轮继续试。
func _ensure_session() -> void:
	if _in_flight or not _live_ready():
		return
	_in_flight = true
	_in_flight_kind = "session"
	var err := _http.request(
		_base_url + API_PREFIX + "/sessions",
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify({"contentVersion": _content_version}))
	if err != OK:
		_in_flight = false
		_in_flight_kind = ""
		_warn("建会话请求未能发出（错误码 %d），稍后重试。" % err)

func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var kind := _in_flight_kind
	_in_flight = false
	_in_flight_kind = ""
	var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300

	if kind == "session":
		if ok:
			var parsed = JSON.parse_string(body.get_string_from_utf8())
			if parsed is Dictionary and parsed.has("sessionId"):
				_absorb_state(parsed)
				_session_id = String(parsed["sessionId"])
				_session_confirmed = true
				_save_session()
				_last_warning = ""
				session_established.emit(_session_id)
				_flush_next()
			else:
				_warn("后端建会话返回里没有 sessionId，事件继续留在本地队列。")
		else:
			_warn("后端未接受建会话（code=%d），事件继续留在本地队列。" % code)
		return

	if kind == "report":
		# Batch 3：报告是只读拉取，成败都直接回信号，不碰事件队列。
		if ok:
			var report = JSON.parse_string(body.get_string_from_utf8())
			if report is Dictionary and (report as Dictionary).has("layers"):
				_last_warning = ""
				report_ready.emit(report)
			else:
				report_failed.emit("报告响应形状不对（缺 layers），请联系排查。")
		elif code == 404:
			# 404 有两种可能：报告真没生成，或 sessionId 已失效（后端换库/重建过）。
			# 后者必须作废本地会话重新握手 —— 否则 _session_confirmed 一直为真，
			# 每次点「我的报告」都拿废 id 去问，玩家会永远卡在同一句提示上。
			_session_confirmed = false
			_session_id = ""
			_save_session()
			_ensure_session()
			report_failed.emit("服务端不认当前会话（后端可能重建过），已重新连接，稍等一两秒再点一次。")
		else:
			report_failed.emit("拉取报告失败（code=%d）。" % code)
		return

	if kind != "event":
		return

	if ok:
		var sent: Dictionary = _queue.pop_front() if not _queue.is_empty() else {}
		_save_queue()
		_last_warning = ""
		var parsed_body = JSON.parse_string(body.get_string_from_utf8())
		if parsed_body is Dictionary:
			# 服务端算完会回权威 state（职级 / 处境跟着这一跳更新）
			_absorb_state(parsed_body)
			event_recorded.emit(sent, parsed_body)
		_flush_next()          # 队列还有就接着发
		return

	if code >= 400 and code < 500:
		# payload 或状态不合格 —— 重试一百次结果一样。出队，但不真丢：
		# 先落一份隔离日志，再说清楚是哪个事件被拒、为什么。
		# 否则一颗坏事件会把整条队列永久堵死，后面所有事件跟着积压。
		var bad: Dictionary = _queue.pop_front() if not _queue.is_empty() else {}
		_save_queue()
		_quarantine(bad, code, body)
		_warn("后端拒收事件「%s」（code=%d）已移出队列并留底隔离日志：%s"
			% [String(bad.get("eventType", "")), code, _brief_error(body)])
		if code == 404:
			# 会话没了（后端换库/重建）→ 作废本地会话，下一轮重新要一个
			_session_confirmed = false
			_session_id = ""
			_save_session()
		_flush_next()
		return

	_warn("发送失败（code=%d, result=%d），事件留在本地队列等待重试。" % [code, result])

func _warn(message: String) -> void:
	if message == _last_warning:
		return
	_last_warning = message
	transport_warning.emit(message)

## 被拒事件留底（JSONL 追加）。写不进去也不能影响主流程 —— 传输层不阻塞游戏。
func _quarantine(envelope: Dictionary, code: int, body: PackedByteArray) -> void:
	var record := {
		"ts": _iso_time(), "code": code, "error": _brief_error(body), "envelope": envelope,
	}
	var file: FileAccess = null
	if FileAccess.file_exists(REJECTED_PATH):
		file = FileAccess.open(REJECTED_PATH, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
	else:
		file = FileAccess.open(REJECTED_PATH, FileAccess.WRITE)
	if file != null:
		file.store_line(JSON.stringify(record))
		file.close()

func _brief_error(body: PackedByteArray) -> String:
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary and parsed.has("error"):
		return String(parsed["error"])
	var raw := body.get_string_from_utf8()
	return raw.substr(0, 120) if not raw.is_empty() else "（无响应体）"

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
			# 只有服务端签发过的 sessionId 才能直接复用，否则要重新去要一个。
			_session_confirmed = bool(session.get("confirmed", false))
	if FileAccess.file_exists(QUEUE_PATH):
		var queue_file := FileAccess.open(QUEUE_PATH, FileAccess.READ)
		var saved_queue = JSON.parse_string(queue_file.get_as_text())
		if saved_queue is Array:
			_queue = saved_queue

func _save_session() -> void:
	var file := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({
			"sessionId": _session_id,
			"contentVersion": _content_version,
			"confirmed": _session_confirmed,
		}))

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
