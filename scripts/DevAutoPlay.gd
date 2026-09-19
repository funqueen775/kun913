extends Node
## DevAutoPlay —— 开发自检专用「48 个月快速随机选」驱动器（非用户功能）。
##
## 用法（窗口肉眼验收，看完整盘自动演完 + 报告自己弹出来）：
##   godot --path . -- --dev-autoplay
## 无头自动验收（跑完出报告后自动退出，exit 0=通过 / 1=失败）：
##   godot --headless --path . -- --dev-autoplay --dev-autoplay-exit
## 可选：--dev-autoplay-seed=123 固定随机种子，复现同一条选择序列。
##
## 干什么：替玩家自动把 27 件主线事件（48 个月）全部走完 —— 每件随机选一个
## 选项，顺手关掉一切挡路的弹窗（手册 / 周末规划 / 宿舍 / 训练谷），终局演完
## 自动点「查看我的职业报告」→ 服务端结算并渲染整份报告。报告在窗口里直接
## 可见；stdout 另打一份验收摘要。
## 平时零存在感：命令行不带 --dev-autoplay 时本脚本什么都不做。

const TOWN_SCENE_SCRIPT := "res://scripts/WorkplaceTown.gd"

const MAX_FRAMES := 240_000          # 兜底：~66 分钟 @60fps，正常几秒到几十秒就演完
const BEAT_WAIT := 4                 # 剧情拍之间的喘息帧数（连点会出玄学）
const REPORT_RETRY_FRAMES := 90      # 报告拉取失败后的重试间隔（帧）
const REPORT_MAX_TRIES := 12
const FLUSH_WAIT_FRAMES := 600       # 等事件队列排空的最长等待

var _enabled := false
var _exit_after_report := false
var _seed := int(Time.get_unix_time_from_system()) % 100000
var _rng := RandomNumberGenerator.new()

var _town: Node = null
var _pending_event: Dictionary = {}
var _beat_wait := 0
var _frames := 0

# 终局 / 报告阶段
var _finale_started := false
var _finale_delay := 0
var _report_requested := false
var _report_tries := 0
var _retry_at := 0
var _report_fail_reason := ""
var _report: Dictionary = {}
var _report_received := false
var _quit_at := -1

# 统计
var _events_done := 0
var _fails := 0
var _choice_log: Array = []
## 收尾标记：跑完（成功或致命失败）后不再驱动，窗口保持现状即可。
var _done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg == "--dev-autoplay":
			_enabled = true
		elif arg == "--dev-autoplay-exit":
			_exit_after_report = true
		elif arg.begins_with("--dev-autoplay-seed="):
			_seed = int(arg.trim_prefix("--dev-autoplay-seed="))
	if not _enabled:
		return
	# 每次自动验收都从干净的 48 个月开始：清掉上次运行的会话/队列，
	# 让服务端开一个全新会话 —— 否则续用旧会话会拿回上次的旧报告。
	ApiClient.reset_session_for_clean_run()
	_rng.seed = _seed
	print("")
	print("========== DevAutoPlay 启动 ==========")
	print("种子 = %d（--dev-autoplay-seed=%d 可复现）" % [_seed, _seed])
	print("自动走完 48 个月主线：每件事件随机选一个选项")
	ApiClient.report_ready.connect(_on_report_ready)
	ApiClient.report_failed.connect(_on_report_failed)


func _process(_delta: float) -> void:
	if not _enabled:
		return
	_frames += 1
	if _frames > MAX_FRAMES and not _done:
		_fail("超时：%d 帧内没有跑完 48 个月（卡在 %s）" % [MAX_FRAMES, _where()])
		return

	if _town == null:
		if not _find_town():
			return
		print("[dev-autoplay] 进入小镇，开始自动走 48 个月……")
		return

	if _quit_at >= 0:
		if _frames >= _quit_at:
			get_tree().quit(0 if _fails == 0 else 1)
		return

	# 1) 先清挡路的弹窗（宿舍 / 周末规划 / 训练谷）。
	if _handle_blocking_panels():
		return

	# 2) 剧情面板开着 → 驱动它（拍推进 / 随机选 / 关手册）。
	var sp: Node = _town.get("_story_event_panel")
	if sp != null and is_instance_valid(sp) and sp.call("is_open"):
		if _pending_event.is_empty():
			# 面板可能被 main_event_reached 信号直接弹开（玩家恰好站在事件区），
			# 没经过 _enter_zone_and_present，把事件补进待办。面板演的永远是
			# 下一件未完成主线，所以 next_main_event() 就是它。
			_pending_event = WorldClock.next_main_event()
		_drive_story_panel(sp)
		return

	# 3) 剧情面板刚关 → 上一件事件结算完毕。
	if not _pending_event.is_empty():
		_events_done += 1
		print("[dev-autoplay] %2d/27  %s  已结算" % [_events_done, String(_pending_event.get("id", "?"))])
		_pending_event = {}

	# 4) 主线全部完成 → 终局演出 + 报告。
	if _all_main_events_done():
		_handle_endgame()
		return

	# 5) 事件到点但还没演 → 进区 + 弹面板。
	if not WorldClock.running and WorldClock.has_overdue_event():
		_enter_zone_and_present(WorldClock.next_main_event())
		return

	# 6) 时间在流 → 推进到下一个主线时点。
	if WorldClock.running:
		_advance_to_next_event()


# ------------------------------------------------------------------ 场景接管

## 找小镇场景（Main.tscn 的根节点 WorkplaceTown）；还在标题页就替玩家点「开始」。
func _find_town() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	if scene.name == "WorkplaceTown" and scene.get_script() != null \
			and String(scene.get_script().resource_path) == TOWN_SCENE_SCRIPT:
		_town = scene
		return true
	# 标题页 / 导览页：自动走 _enter_town（写 profile + 切 Main.tscn），等于点「开始新游戏」。
	var script_path := ""
	if scene.get_script() != null:
		script_path = String(scene.get_script().resource_path)
	if script_path.ends_with("StartupFlow.gd") and scene.has_method("_enter_town"):
		scene.call("_enter_town")
	return false


# ------------------------------------------------------------------ 弹窗清理

## 把会挡住自动流程的弹窗关掉。返回是否处理了某个弹窗（本帧不再往下走）。
func _handle_blocking_panels() -> bool:
	var dorm: Node = _town.get("_dorm")
	if dorm != null and is_instance_valid(dorm) and dorm.call("is_open"):
		# 宿舍 = 出门（点火 M1-E01）/ 睡觉（跨月）。_confirm_dorm_action 是官方自检入口。
		_town.call("_confirm_dorm_action")
		return true
	var ft: Node = _town.get("_free_time_panel")
	if ft != null and is_instance_valid(ft) and ft.call("is_open"):
		print("[dev-autoplay] 关掉自动弹出的周末规划面板")
		ft.call("close")
		return true
	var tr: Node = _town.get("_training_panel")
	if tr != null and is_instance_valid(tr) and tr.call("is_open"):
		print("[dev-autoplay] 关掉训练谷对局面板（M2-E08 随机选到了接受）")
		tr.call("close")
		return true
	return false


# ------------------------------------------------------------------ 剧情面板驱动

func _drive_story_panel(sp: Node) -> void:
	if _beat_wait > 0:
		_beat_wait -= 1
		return
	var stage := String(sp.call("current_stage"))
	match stage:
		"closed":
			_beat_wait = BEAT_WAIT
		"choices":
			_pick_random_choice(sp)
		"handbook":
			# 手册压在剧情面板上面：关掉它，剧情继续（_on_handbook_closed 自动推进）。
			var hb: Node = sp.get("_handbook")
			if hb != null and is_instance_valid(hb) and hb.call("is_open"):
				hb.call("close")
			_beat_wait = BEAT_WAIT
		_:
			# entry / narration / say / interact / outcome 都靠「点一下继续」。
			# typing 时 _advance 会先补满字，天然安全。
			sp.call("_advance")
			_beat_wait = BEAT_WAIT


func _pick_random_choice(sp: Node) -> void:
	var choices: Array = _pending_event.get("choices", [])
	if choices.is_empty():
		_fail("事件 %s 没有可选选项，无法随机选" % String(_pending_event.get("id", "?")))
		return
	var choice: Dictionary = choices[_rng.randi_range(0, choices.size() - 1)]
	var choice_id := String(choice.get("id", "option_a"))
	var event_id := String(_pending_event.get("id", ""))
	var duration := int(_pending_event.get("durationMinutes", 45))
	_choice_log.append("%s→%s" % [event_id, choice_id])
	sp.call("_on_choice_picked", event_id, choice_id, duration)
	print("[dev-autoplay] %s  随机选了 %s" % [event_id, choice_id])
	_beat_wait = BEAT_WAIT


# ------------------------------------------------------------------ 时间推进

## 把时间一路拨到下一个未完成主线事件的时点（由 WorldClock 的主线守卫停在事件上）。
func _advance_to_next_event() -> void:
	var guard := 0
	while WorldClock.running and guard < 96:
		# 睡觉 = 跨月；睡醒当天有事件会补一枪点火。两个都只停在事件时点，绝不吞剧情。
		WorldClock.sleep_to_next_month(7)
		WorldClock.fire_due_event_today()
		guard += 1
	if guard >= 96:
		_fail("推进时间卡死（96 次跨月都没碰到事件）")
		return
	if not WorldClock.running and not _all_main_events_done():
		print("[dev-autoplay] 第 %d 月 事件已到点：%s" % [
			int(WorldClock.snapshot().get("month", 1)),
			String(WorldClock.next_main_event().get("id", "?"))])


## 事件到点了：把玩家「瞬移」进事件所在的区，走真实的 _open_due_event_for_active_zone
## 弹剧情面板（绕开走路/进门，但面板演出、埋点、结算全是真链路）。
func _enter_zone_and_present(event: Dictionary) -> void:
	if event.is_empty():
		return
	var code := String(event.get("locationId", ""))
	var zone: Dictionary = _town.call("_zone_by_code", code)
	if zone.is_empty():
		_fail("事件 %s 的区 %s 查不到 zone 定义" % [event.get("id", "?"), code])
		return
	_pending_event = event
	_town.set("_active_zone", zone)
	_town.set("_nearby_zone", {})
	var opened: bool = _town.call("_open_due_event_for_active_zone")
	if not opened:
		# 兜底：直接让面板演（理论上 _open_due_event_for_active_zone 必成功）。
		var sp: Node = _town.get("_story_event_panel")
		if sp != null and is_instance_valid(sp):
			sp.call("present", event.duplicate(true))
		else:
			_fail("剧情面板不存在，无法演事件 %s" % event.get("id", "?"))


func _all_main_events_done() -> bool:
	return WorldClock.next_main_event().is_empty()


# ------------------------------------------------------------------ 终局 + 报告

func _handle_endgame() -> void:
	var finale: Node = _town.get("_finale")
	if finale != null and is_instance_valid(finale) and finale.get("visible") and not _report_requested:
		# 终局演出：只在报告请求发出前推进。报告点开后面板可能仍盖在底下，
		# 不能让它把下面的「等报告 → 退出」分支挡住。
		if not _finale_started:
			_finale_started = true
			print("[dev-autoplay] 终局演出开始（六幕回放 + 四熊告别）……")
			_finale_delay = 75   # 让终局在屏幕上待 ~1.2s 再点「查看我的职业报告」
		_finale_delay -= 1
		if _finale_delay <= 0 and not _report_requested:
			_report_requested = true
			print("[dev-autoplay] 自动点开「查看我的职业报告」")
			finale.call("_on_report_pressed")
			# 面板 open() 自己会同步发一次生成请求，别在下一帧抢发撞车
			# （会先吃到「上一个请求还在路上」的失败，虽然后面重试能成，
			# 但失败态文字会残留到报告渲染出来为止）。等它失败再由重试接手。
			_retry_at = _frames + REPORT_RETRY_FRAMES
		return
	if not _report_requested:
		return
	# 报告请求已发出：等事件队列排空 → 生成报告（重试由 report_failed 驱动）。
	if ApiClient.pending_event_count() > 0:
		if _frames % 60 == 0:
			print("[dev-autoplay] 等事件队列排空…… pending=%d" % ApiClient.pending_event_count())
		return
	if _report_received:
		# 报告已到且渲染完，多留几帧给画面 → 按需退出。
		if _exit_after_report and _quit_at < 0:
			_quit_at = _frames + 45
		return
	# 报告还没回来：等队列排空，再隔 REPORT_RETRY_FRAMES 帧重试（失败原因见 report_failed）。
	if ApiClient.pending_event_count() == 0 and _frames >= _retry_at:
		_try_generate_report()


func _try_generate_report() -> void:
	_report_tries += 1
	if _report_tries > REPORT_MAX_TRIES:
		_fail("报告生成重试 %d 次仍失败：%s" % [REPORT_MAX_TRIES, _report_fail_reason])
		return
	_retry_at = _frames + REPORT_RETRY_FRAMES
	print("[dev-autoplay] 请求服务端生成报告（第 %d 次）……" % _report_tries)
	ApiClient.generate_report()


func _on_report_ready(report: Dictionary) -> void:
	if not _enabled or not _report_requested:
		return
	_report = report
	_report_received = true
	var layers := report.get("layers", {}) as Dictionary
	var persona := layers.get("persona", {}) as Dictionary
	_check("报告回包含 layers 三层", layers.has("persona") and layers.has("market") and layers.has("crossHints"),
		str(layers.keys()))
	_check("persona 含 radar 六柱", (persona.get("radar", []) as Array).size() == 6,
		"n=%d" % (persona.get("radar", []) as Array).size())
	_check("decisionCount 覆盖全部 27 件主线（26 测评 + M2-E08 非测评）",
		int(report.get("decisionCount", 0)) >= 26,
		"decisionCount=%d" % int(report.get("decisionCount", 0)))
	print("")
	print("========== DevAutoPlay 完成 ==========")
	print("随机种子 = %d" % _seed)
	print("主线事件已结算 = %d / 27" % _events_done)
	print("选择序列 = %s" % "  ".join(_choice_log))
	print("decisionCount = %d" % int(report.get("decisionCount", 0)))
	print("报告 generatedAt = %s" % String(report.get("generatedAt", "?")))
	if _fails == 0:
		print("DEVAUTOPLAY_PASS")
	else:
		print("DEVAUTOPLAY_FAIL (%d)" % _fails)
	_done = true


func _on_report_failed(reason: String) -> void:
	if not _enabled or not _report_requested:
		return
	_report_fail_reason = reason
	print("[dev-autoplay] 报告拉取失败：%s" % reason.substr(0, 120))
	# 失败可能是队列还在飞 / 会话刚重握，隔一会重试（_try_generate_report 有次数上限）。
	_report_tries = maxi(0, _report_tries - 1)


# ------------------------------------------------------------------ 断言与收尾

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("PASS  ", name, "  ", detail)
	else:
		_fails += 1
		print("FAIL  ", name, "  ", detail)


func _fail(reason: String) -> void:
	_fails += 1
	_done = true
	print("DEVAUTOPLAY_FAIL   ", reason)
	if _exit_after_report:
		_quit_at = _frames + 5
	else:
		# 窗口模式不退出，方便肉眼排查，但打满告警。
		print("（窗口模式不退出：请查看屏幕状态排查）")


func _where() -> String:
	if _town == null:
		return "还没进入小镇"
	var sp: Node = _town.get("_story_event_panel")
	if sp != null and is_instance_valid(sp) and sp.call("is_open"):
		return "剧情面板 %s（stage=%s）" % [String(_pending_event.get("id", "?")), sp.call("current_stage")]
	if not WorldClock.running:
		return "时间停住（world_minute=%d）" % WorldClock.world_minute
	return "时间在流（第 %d 月）" % int(WorldClock.snapshot().get("month", 1))
