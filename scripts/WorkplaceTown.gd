extends Node2D


const PAPER_DOLL := preload("res://scripts/PaperDoll64Sprite.gd")
const OFFICE_SET := preload("res://scripts/OfficeSet.gd")
const OFFICE_NPC := preload("res://scripts/OfficeNpcWalker.gd")
const MAP_DEBUG_OVERLAY := preload("res://scripts/MapDebugOverlay.gd")
const TIME_HUD := preload("res://scripts/WorldTimeHud.gd")
const INTERIOR_PREVIEW := preload("res://scripts/InteriorPreview.gd")
const DORM_ROOM := preload("res://scripts/DormRoom.gd")
const STORY_EVENT_PANEL := preload("res://scripts/StoryEventPanel.gd")
const MEMORY_WALL := preload("res://scripts/MemoryWallPanel.gd")
const LEDGER_BOOK := preload("res://scripts/WeekendLedgerBook.gd")
## 设置弹窗（2026-09-17 UI 打磨）：操作说明 + 退出游戏收编在这里。
const SETTINGS_PANEL := preload("res://scripts/SettingsPanel.gd")
const MONTHLY_LIFE := preload("res://scripts/MonthlyLife.gd")
const ENERGY_PANEL := preload("res://scripts/EnergyModalPanel.gd")
## 圆钮矢量图标（2026-09-17 晚：单字圆钮换图形，用户嫌字丑）。
const HUD_GLYPH := preload("res://scripts/ui/HudGlyph.gd")
const FREE_TIME_PANEL := preload("res://scripts/FreeTimePanel.gd")
const TRAINING_PANEL := preload("res://scripts/TrainingValleyPanel.gd")
const GROUND_GUIDE := preload("res://scripts/ui/GroundGuideLine.gd")
const CHINESE_FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const TOWN_MAP_PATH := "res://assets/town/workplace_town_no_labels.png"
const SOURCE_MAP_SIZE := Vector2(1678, 937)
const LOCATION_MARKER_RECTS := {
	"A": Rect2(250, 20, 230, 82),
	"B": Rect2(735, 25, 225, 82),
	"C": Rect2(1185, 60, 195, 82),
	"D": Rect2(1385, 525, 215, 82),
	"E": Rect2(755, 735, 195, 82),
	"F": Rect2(275, 635, 230, 82),
	"G": Rect2(160, 450, 215, 82),
	"H": Rect2(50, 210, 230, 100),
}
const WALKABILITY_MASK_PATH := "res://assets/town/walkability_mask.png"
const REGIONS_PATH := "res://data/town/regions.json"
const NPCS_PATH := "res://data/town/npcs.json"
const COLLISION_DATA_PATH := "res://data/town/collision.json"
const NAVIGATION_DATA_PATH := "res://data/town/navigation.json"
const WORLD_SIZE := Vector2(1920, 1080)
const PLAYER_SPEED := 270.0
const COLLISION_LAYER := 1
## 键盘移动的兜底键位（按物理键位读，换键盘布局也认"WASD 那四个位置"）。
## 为什么需要兜底：project.godot 的 InputMap 里 move_* 四条曾被写成 device=16，
## 而真实键盘事件 device=0，Godot 会比对 device → 一条都匹配不上，玩家完全走不动。
## 配置再被改坏 / 被别的引擎版本重写时，这里保证键盘照样能走。
const MOVE_LEFT_KEYS := [KEY_A, KEY_LEFT]
const MOVE_RIGHT_KEYS := [KEY_D, KEY_RIGHT]
const MOVE_UP_KEYS := [KEY_W, KEY_UP]
const MOVE_DOWN_KEYS := [KEY_S, KEY_DOWN]
const INTERACTION_DISTANCE := 230.0
const ENTRANCE_DISTANCE := 58.0
const ZONE_ZOOM := 3.15
const OUTDOOR_EXPLORATION_ZOOM := 1.55
const CAMERA_FOLLOW_SPEED := 5.4
## 自由缩放：滚轮 / ± 键 / 触屏双指捏合每次的倍率步长。
const MAP_ZOOM_STEP := 1.12
## 缩放上限倍数（相对基础缩放）：1.55 × 2.6 ≈ 4.0，足够贴近看清角色与招牌。
const MAP_ZOOM_MAX_FACTOR := 2.6
## 缩放下限倍数：总 zoom 不能低于 _cover_zoom，否则视野超出 0..1920 / 0..1080，
## 相机 limit 会把画面钉在一边并露出灰底。1.0 / 1.55 ≈ 0.645 时正好看全整张地图。
const MAP_ZOOM_MIN_FACTOR := 1.0 / OUTDOOR_EXPLORATION_ZOOM
## 地面引导线：玩家挪出这么远才重算路径。太小会每帧重跑 BFS，太大线头会跟人脱开。
const GUIDE_REPATH_DISTANCE := 10.0
## 引导线拐角切圆弧的采样段数。只影响观感：4 段已经看不出折角。
const GUIDE_CORNER_STEPS := 4
const INTERIOR_ASSETS := {
	"A": "res://assets/场景内部图/熊起东方总部.png",
	"B": "res://assets/场景内部图/云栖科技丘.png",
	"C": "res://assets/场景内部图/创意水巷.png",
	"D": "res://assets/场景内部图/树影图书馆.png",
	"E": "res://assets/场景内部图/松风训练谷.png",
	"F": "res://assets/场景内部图/观澜展会码头.png",
	"G": "res://assets/场景内部图/暖邻康护院.png",
	"H": "res://assets/场景内部图/慢生活园.png",
}
## 宿舍门口（H 区 · 慢生活园入口外）。出生、以及每天出门都落在这里。
## 坐标来自 data/town/regions.json 里 H 区的 entrance (375,465) 再往外让开一点，
## 免得一出宿舍就被"进入 H 区"的按钮糊脸；已用通行遮罩确认可走。
const DORM_DOOR_POSITION := Vector2(375, 500)
## 宵禁：到了这个钟点玩家会被强制送回宿舍，只能睡觉，第二天 WAKE_UP_HOUR 点才出门。
## 现在它只是兜底：正常节奏下精力耗尽时时间会先被拨到 ENERGY_CURFEW_JUMP_HOUR 点
## 并提醒回宿舍（见 _on_energy_exhausted），玩家自己走回去；磨蹭到 23 点才被这里收走。
const CURFEW_HOUR := 23
## 精力耗尽时把当天时间拨到的钟点（「下班」时段的晚上）。
## 不直接拨到 23:00：给玩家留一点自己走回宿舍的余地，宵禁仍然兜底。
const ENERGY_CURFEW_JUMP_HOUR := 22
const WAKE_UP_HOUR := 7
var WALKABLE_AREAS := [
	# Five destination forecourts / plazas.
	Rect2(70, 230, 330, 160), Rect2(760, 190, 330, 150), Rect2(1240, 420, 300, 200),
	Rect2(360, 680, 330, 210), Rect2(1150, 680, 340, 210),
	# Main road ring that connects every destination.
	Rect2(350, 330, 250, 500), Rect2(540, 300, 880, 120), Rect2(1320, 290, 220, 470),
	Rect2(350, 780, 1190, 160), Rect2(650, 620, 120, 230), Rect2(1040, 620, 120, 230),
]
var ZONES := [
	{"id": "a", "code": "A", "name": "启程广场·飓起东方总部", "rect": Rect2(75, 95, 315, 245), "center": Vector2(230, 210), "door": "bottom"},
	{"id": "b", "code": "B", "name": "云栖科技工厂", "rect": Rect2(760, 80, 320, 205), "center": Vector2(920, 180), "door": "bottom"},
	{"id": "c", "code": "C", "name": "创意水巷", "rect": Rect2(1450, 150, 390, 250), "center": Vector2(1645, 275), "door": "left"},
	{"id": "d", "code": "D", "name": "树影书院", "rect": Rect2(55, 420, 330, 250), "center": Vector2(220, 545), "door": "right"},
	{"id": "e", "code": "E", "name": "松风训练谷", "rect": Rect2(410, 760, 320, 230), "center": Vector2(570, 875), "door": "top"},
	{"id": "f", "code": "F", "name": "观澜会展码头", "rect": Rect2(255, 820, 330, 230), "center": Vector2(420, 930), "door": "top"},
	{"id": "g", "code": "G", "name": "暖邻康护院", "rect": Rect2(1320, 650, 360, 300), "center": Vector2(1500, 800), "door": "left"},
	{"id": "h", "code": "H", "name": "慢生活园·宿舍与桌游馆", "rect": Rect2(760, 760, 390, 250), "center": Vector2(955, 885), "door": "top"},
]
var NPCS := [
	{"zone": "a", "name": "陈工", "role": "邻组 Leader", "loadout": "bear_beige_blazer", "route": PackedVector2Array([Vector2(405, 345), Vector2(510, 345), Vector2(510, 390), Vector2(405, 390)]), "prompt": "结论是什么？预算和工期，一句话说完。"},
	{"zone": "b", "name": "王哥", "role": "技术 · 你的导师", "loadout": "bear_plaid_glasses", "route": PackedVector2Array([Vector2(850, 325), Vector2(1070, 325), Vector2(1070, 370), Vector2(850, 370)]), "prompt": "方案我看过了，先别急着推。说说你为什么选这条路线。"},
	{"zone": "c", "name": "小林", "role": "产品", "loadout": "bear_green_cardigan", "route": PackedVector2Array([Vector2(1435, 335), Vector2(1650, 335), Vector2(1650, 380), Vector2(1435, 380)]), "prompt": "客户那边催得很急，先帮我把需求优先级定下来。"},
	{"zone": "d", "name": "老周", "role": "资深", "loadout": "bear_orange_blazer", "route": PackedVector2Array([Vector2(1205, 680), Vector2(1285, 680), Vector2(1285, 800), Vector2(1205, 800)]), "prompt": "复盘会上有不同说法。你觉得该由谁来牵头？"},
	{"zone": "h", "name": "小赵", "role": "实习生", "loadout": "bear_green_cardigan", "route": PackedVector2Array([Vector2(365, 380), Vector2(405, 380), Vector2(405, 490), Vector2(365, 490)]), "prompt": "师兄，这个我搞不太定……能帮我看一眼吗？"},
]

var _office: OfficeSet
var _player: CharacterBody2D
var _player_sprite: Sprite2D
var _camera: Camera2D
## 相机铺满系数：视口比例 ≠ 16:9 时 > 1，让世界铺满视野（见 _apply_camera_cover）。
## _update_camera 的目标 zoom 都要乘它，否则会被 lerp 回 1.0，画面外又露出灰底。
var _cover_zoom := 1.0
## 上一帧的视口尺寸：变了才重算相机铺满（size_changed 信号时机不稳，会拿到过期尺寸）
var _last_viewport_size := Vector2.ZERO
## 玩家自由缩放的倍率（相对基础缩放），范围钳在 [MAP_ZOOM_MIN_FACTOR, MAP_ZOOM_MAX_FACTOR]。
## _update_camera 与 _apply_camera_cover 的目标 zoom 都要乘它，两边保持一致才不会互相打架。
var _map_zoom_factor := 1.0
var _map_zoom_hint: Label
## 鼠标拖动平移：按住左键拖动时，相机脱离玩家、按拖动量反向移动（地图跟着手走）。
## 松手后**保持**在当前视角不回弹 —— 拖动是"我去看看别处"；等玩家一有移动输入再滑回身上。
var _pan_offset := Vector2.ZERO
var _is_panning := false
var _pan_drag_origin := Vector2.ZERO
var _pan_offset_origin := Vector2.ZERO
## 触屏双指捏合：触控点 index -> 当前屏幕坐标
var _zoom_touches := {}
var _pinch_last_distance := 0.0
var _touch_vector := Vector2.ZERO
var _touch_active := false
var _active_zone: Dictionary = {}
var _nearby_zone: Dictionary = {}
var _nearby_npc: Dictionary = {}
var _npc_instances: Array[Dictionary] = []
var _zone_status: Control
var _interaction_button: Button
var _zone_button: Button
## 右上角功能圆钮（2026-09-17 UI 打磨）：记忆墙 / 周末手账 / 设置，横排一行。
## 旧的 190×56 长条按钮（退出游戏/记忆墙/周末手账）已删 —— 退出游戏收进设置弹窗。
## 原来 y=215 的「退出游戏」和精力条（同 y）整块叠在一起，这就是右上角「乱」的根源。
var _memory_wall_button: Button
var _ledger_book_button: Button
var _settings_button: Button
## 圆钮行下方那条悬停名称提示（鼠标划过圆钮时显示两三个字）。
var _hud_button_caption: Label
## 设置弹窗与它的停钟还原（同记忆墙的待遇：开着时世界时钟停住）。
var _settings_panel
var _settings_resume_clock := false
## 顶部提醒横幅（精力耗尽 → 回宿舍等）。整条横幅在超时后自毁。
var _toast_layer: CanvasLayer
var _toast_panel: Panel
var _toast_tween: Tween
var _dialog_label: Label
var _dialog_timer: Timer
var _last_walkable_position := Vector2.ZERO
var _debug_overlay
var _collision_debug_polygons: Array = []
var _coordinate_label: Label
var _walkability_image: Image
var _walkability_debug_sprite: Sprite2D
var _location_markers: Array[Sprite2D] = []
var _entrance_markers: Array[Polygon2D] = []
var _highlighted_zone_id := ""
var _time_hud: WorldTimeHud
var _interior_preview: InteriorPreview
var _environment_tint: ColorRect
var _story_event_panel: StoryEventPanel
var _story_event: Dictionary = {}
## 心湖记忆墙：读 user://workplace_town_memos.jsonl，把一路攒下的便签贴成一墙。
## 故意不写静态类型（也不给它 class_name）：免得依赖 .godot 里的全局类缓存，
## 那个缓存是编辑器扫描时才刷新的，切分支/新加类名时最容易在这里翻车。
var _memory_wall
## 开墙前世界时钟是不是在跑。关上要还原，否则玩家会莫名发现时间不走了。
var _wall_resume_clock := false
## 周末手账册（§6.2）：16 页，读 user://workplace_town_weekends.jsonl。同一个停钟待遇。
var _ledger_book
var _ledger_resume_clock := false
## 周末回声（§6.1）语料缓存：res://data/story/weekend_echo.json，懒加载一次。
var _echo_config := {}
## 周日（§13.1）= 周末收束的次日。-1 = 从没收束过周末，永不触发周日态。
var _sunday_day_index := -1
## 这个周日有没有坐下过（湖边/天台二选一，一个周日一次）。
var _sunday_sit_done := false
var _dorm: DormRoom
## 玩家在宿舍里（黑屏盖住地图）：此时人物不能动、地图不能缩放拖动。
var _in_dorm := false
## 已经处理过宵禁的那一天（"月-日"），避免同一天被反复拽回宿舍。
var _curfew_day_key := ""
var _zone_entered_msec := 0
var _decision_opened_msec := 0
var _choice_hover_count := 0
var _last_hovered_choice_id := ""
## 训练谷 · 熊熊有招（Batch 4）：M2-E08 邀约进入，按需实例化。
var _training_panel
## 月度生活系统：每月 3 点精力 / 公开数值 / 月底结算 / 好感度（见 scripts/MonthlyLife.gd）。
var _monthly_life
## 精力弹窗（居中模态，点「力」圆钮打开）与自由周末面板。
var _energy_panel
## 精力弹窗开着时世界时钟是否在跑（同设置弹窗的停钟待遇，关上还原）。
var _energy_resume_clock := false
var _free_time_panel
## 已经开过自由周末的月份（每 3 个月一次：第 3/6/9…月）。
var _weekend_done_months: Array[int] = []
## 地面引导线（见 scripts/ui/GroundGuideLine.gd）。写弱类型：理由同 _memory_wall。
var _guide_line
## 自由活动选定的区域 code（空 = 本周末没有目的地）。由自由周末面板回传。
var _free_guide_zone := ""
## 上次铺路时的玩家位置与目标：据此决定要不要重跑寻路。
var _guide_path_origin := Vector2(-99999, -99999)
var _guide_path_target := Vector2(-99999, -99999)
var _guide_path_urgent := false
## 左上角任务卡（主线提示）。名字沿用 _zone_status，因为它的 show()/hide()
## 散落在进出区域、进出宿舍各处；这里它已经从一行裸 Label 变成整块卡片。
## 卡内成员：小标签 / 主标题 / 区域徽标 / 副行。
var _objective_tag: Label
var _objective_title: Label
var _objective_badge: Label
var _objective_meta: Label
## 卡片左侧那条竖色条，到点态要换成橙金 —— 单独存一份好改色。
var _objective_accent: ColorRect
## 任务卡底板样式与"是否到点"：到点态要让边框呼吸起来。
var _objective_style: StyleBoxFlat
var _objective_urgent := false


func _ready() -> void:
	_load_map_data()
	_build_map_backdrop()
	_load_walkability_mask()
	_build_map_collisions()
	_build_player()
	_build_guide_line()
	_build_npcs()
	_build_camera()
	_build_hud()
	_build_location_markers()
	_build_debug_overlay()
	_build_monthly_life()
	_build_world_time()
	_build_interior_preview()
	_build_story_event_panel()
	_build_memory_wall()
	_build_dorm_room()
	# 开局就站在宿舍里：黑屏 + 唯一一个「离开宿舍」。
	_enter_dorm(false)


## 键盘移动输入：先问 InputMap（方便以后在游戏里改键），拿不到就直接按物理键位兜底。
## 返回的方向已归一化，斜着走不会比直着走快。
func _read_move_input() -> Vector2:
	var from_actions := Input.get_vector("move_left", "move_right", "move_up", "move_down").limit_length(1.0)
	if from_actions != Vector2.ZERO:
		return from_actions
	return Vector2(
		float(_any_move_key_pressed(MOVE_RIGHT_KEYS)) - float(_any_move_key_pressed(MOVE_LEFT_KEYS)),
		float(_any_move_key_pressed(MOVE_DOWN_KEYS)) - float(_any_move_key_pressed(MOVE_UP_KEYS))
	).limit_length(1.0)


func _any_move_key_pressed(keys: Array) -> bool:
	for key in keys:
		if Input.is_physical_key_pressed(key):
			return true
	return false


func _physics_process(delta: float) -> void:
	if _player == null or _player_sprite == null:
		return
	if _interior_preview != null and _interior_preview.is_open():
		_interior_preview.set_touch_vector(_touch_vector)
		_hide_guide_line()
		return
	# 宿舍里小镇的人不动，但输入要转给宿舍那份"同一套操作"：
	# 玩家在宿舍屏里自己走到门口/床边才出门、才睡觉。
	if _in_dorm:
		_player.velocity = Vector2.ZERO
		_player_sprite.set_motion(Vector2.ZERO, 0.0)
		_hide_guide_line()
		if _dorm != null:
			var dorm_direction := _read_move_input()
			if _touch_active:
				dorm_direction = _touch_vector
			_dorm.set_move_input(dorm_direction)
		return
	# 记忆墙同样盖住地图，人还在走就对不上；键盘不像鼠标，不受 CanvasLayer 拦。
	if _memory_wall != null and _memory_wall.is_open():
		_player.velocity = Vector2.ZERO
		_player_sprite.set_motion(Vector2.ZERO, 0.0)
		_hide_guide_line()
		return
	var direction := _read_move_input()
	if _touch_active:
		direction = _touch_vector
	var wanted_position := _player.position + direction * PLAYER_SPEED * delta
	if direction != Vector2.ZERO and _is_walkable_position(wanted_position) and _is_inside_active_zone(wanted_position):
		_player.velocity = direction * PLAYER_SPEED
		_player.move_and_slide()
		if _is_walkable_position(_player.position):
			_last_walkable_position = _player.position
		else:
			_player.position = _last_walkable_position
			_player.velocity = Vector2.ZERO
	else:
		_player.velocity = Vector2.ZERO
	_player_sprite.set_motion(direction, _player.velocity.length() * delta)
	_update_zone_state()
	_update_nearby_npc()
	_update_camera(delta)
	_refresh_guide_line()

func _process(_delta: float) -> void:
	if get_viewport_rect().size != _last_viewport_size:
		_apply_camera_cover()
	# 任务目标和入口采用低频呼吸动画，手机端无需额外粒子开销。
	var pulse := (sin(Time.get_ticks_msec() * 0.006) + 1.0) * 0.5
	# 主线到点时，任务卡边框跟着一起呼吸 —— 静态的橙色在这张底图上不够抓眼。
	if _objective_urgent and _objective_style != null:
		_objective_style.border_color = Color(1.0, 0.62, 0.20, 0.55 + pulse * 0.45)
		_objective_accent.modulate = Color(1, 1, 1, 0.72 + pulse * 0.28)
	for index in _entrance_markers.size():
		var marker := _entrance_markers[index]
		if not is_instance_valid(marker):
			continue
		var zone: Dictionary = ZONES[index] if index < ZONES.size() else {}
		var is_target := String(zone.get("id", "")).to_lower() == _highlighted_zone_id.to_lower()
		# 目标入口保持纯黄，只改变亮度和大小，不再变成橙色。
		marker.modulate = Color(1.0, 1.0, 0.0, 0.78 + pulse * 0.22) if is_target else Color(1.0, 0.96, 0.05, 1.0)
		marker.scale = Vector2.ONE * (1.0 + (0.16 + pulse * 0.10) if is_target else 1.0)

## 拖动中的移动与松手走 _input 而不是 _unhandled_input：
## 拖动时鼠标很可能划过按钮/摇杆，那些 Control 会吃掉事件，_unhandled_input 就收不到松手了
## → 会一直卡在"拖动中"。这里抢在 GUI 之前收，并顺手把事件标记为已处理（拖动时不希望误触按钮）。
func _input(event: InputEvent) -> void:
	if not _is_panning:
		return
	if event is InputEventMouseMotion:
		_update_map_pan(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_end_map_pan()


## 拖动中窗口失焦（Alt+Tab 之类）会收不到鼠标松手：
## 不兜这一下，光标就卡在"抓手"上、`_is_panning` 也一直是 true。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_end_map_pan()


func _unhandled_input(event: InputEvent) -> void:
	if _handle_map_zoom_input(event):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		# 宿舍盖在最上面时，键盘整套交给宿舍屏自己处理（走动、开确认框）。
		if _in_dorm:
			if _dorm != null:
				_dorm.handle_key(event.keycode)
			return
		if _interior_preview != null and _interior_preview.is_open():
			if event.keycode == KEY_ESCAPE or event.keycode == KEY_Q:
				_exit_zone()
			return
		if event.keycode == KEY_F3:
			_debug_overlay.set_overlay_visible(not _debug_overlay.visible_overlay)
			_walkability_debug_sprite.visible = _debug_overlay.visible_overlay
			_coordinate_label.visible = _debug_overlay.visible_overlay
			return
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_Q:
			_exit_zone()
			return
		if event.keycode == KEY_E or event.keycode == KEY_SPACE:
			_begin_primary_action()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _debug_overlay != null and _debug_overlay.visible_overlay:
			var world_position := get_global_mouse_position()
			_coordinate_label.text = "地图坐标  x: %d  y: %d" % [roundi(world_position.x), roundi(world_position.y)]
		_begin_map_pan(event.position)


## 地图自由缩放入口。返回 true 表示这个事件已被缩放消费掉，别再往下传。
func _handle_map_zoom_input(event: InputEvent) -> bool:
	if _is_map_input_locked():
		_zoom_touches.clear()
		_pinch_last_distance = 0.0
		return false
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(MAP_ZOOM_STEP)
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 / MAP_ZOOM_STEP)
			return true
	if event is InputEventMagnifyGesture:
		# 触控板 / 触屏的捏合手势，factor > 1 表示张开（放大）
		_zoom_by(event.factor)
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				_zoom_by(MAP_ZOOM_STEP)
				return true
			KEY_MINUS, KEY_KP_SUBTRACT:
				_zoom_by(1.0 / MAP_ZOOM_STEP)
				return true
			KEY_0, KEY_KP_0:
				# 一键回到默认视野
				_set_map_zoom(1.0)
				return true
	return _handle_pinch_zoom(event)


## 触屏双指捏合：两指距离张开 → 放大，收拢 → 缩小。
## 单指（拖摇杆、点按钮）不参与，避免和左下角摇杆抢手势。
func _handle_pinch_zoom(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		if event.pressed:
			_zoom_touches[event.index] = event.position
		else:
			_zoom_touches.erase(event.index)
		if _zoom_touches.size() < 2:
			_pinch_last_distance = 0.0
		return false
	if event is InputEventScreenDrag:
		if not _zoom_touches.has(event.index):
			return false
		_zoom_touches[event.index] = event.position
		if _zoom_touches.size() < 2:
			_pinch_last_distance = 0.0
			return false
		var indices := _zoom_touches.keys()
		indices.sort()
		var first: Vector2 = _zoom_touches[indices[0]]
		var second: Vector2 = _zoom_touches[indices[1]]
		var distance := first.distance_to(second)
		if _pinch_last_distance > 0.0 and distance > 0.0:
			# 单帧比例变化夹一下，手指甩得再快也不会一帧跳到极限
			_zoom_by(clampf(distance / _pinch_last_distance, 0.8, 1.25))
		_pinch_last_distance = distance
		return true
	return false


func _zoom_by(step: float) -> void:
	_set_map_zoom(_map_zoom_factor * step)


## 倍率钳制：下限保证「视野不超世界」（不露灰底），上限防止放太大糊成马赛克。
func _set_map_zoom(value: float) -> void:
	var clamped := clampf(value, MAP_ZOOM_MIN_FACTOR, MAP_ZOOM_MAX_FACTOR)
	if is_equal_approx(clamped, _map_zoom_factor):
		return
	_map_zoom_factor = clamped
	_update_zoom_hint()
	# 视野大小变了，可移动范围也跟着变，平移偏移要重新钳一次，
	# 否则缩小后相机会被相机 limit 钉在边上，玩家再移动时有一段"空转"。
	_clamp_pan_offset()


func _update_zoom_hint() -> void:
	if _map_zoom_hint == null:
		return
	_map_zoom_hint.text = "滚轮 / 双指缩放  ·  拖动平移  ·  %d%%" % roundi(_map_zoom_factor * 100.0)


## 室内 / 剧情面板打开时不给缩放与拖动：那些界面盖住了地图，
## 此时改倍率或视角只会在退出后突然跳变一次，观感很差。
func _is_map_input_locked() -> bool:
	if _in_dorm:
		return true
	if _interior_preview != null and _interior_preview.is_open():
		return true
	if _story_event_panel != null and _story_event_panel.is_open():
		return true
	return false


## 当前场景的基础缩放：室外 = 探索视角，在区域内 = 区域视角。
func _base_zoom() -> float:
	return ZONE_ZOOM if not _active_zone.is_empty() else OUTDOOR_EXPLORATION_ZOOM


## 相机跟随的基准点：室外跟着玩家，区域内看区域中心。
func _camera_anchor() -> Vector2:
	if not _active_zone.is_empty():
		var center: Vector2 = _active_zone["center"]
		return center
	if _player != null:
		return _player.position
	return WORLD_SIZE * 0.5


func _begin_map_pan(screen_position: Vector2) -> void:
	if _is_map_input_locked():
		return
	_is_panning = true
	_pan_drag_origin = screen_position
	_pan_offset_origin = _pan_offset
	# 光标给个"抓手"反馈，松手恢复
	Input.set_default_cursor_shape(Input.CURSOR_DRAG)


func _update_map_pan(screen_position: Vector2) -> void:
	if not _is_panning or _camera == null:
		return
	# 屏幕位移 ÷ zoom = 世界位移；鼠标向右拖 → 相机向左走，画面里的地图才跟着手走
	_pan_offset = _pan_offset_origin - (screen_position - _pan_drag_origin) / _camera.zoom
	_clamp_pan_offset()


func _end_map_pan() -> void:
	if not _is_panning:
		return
	_is_panning = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


## 相机最多走到「视野边缘贴住世界边缘」为止：再往外拖也看不见东西，只是白攒偏移。
## 不做这一步的话，拖过边界再松手，玩家移动时相机会先"空转"一段才跟上。
func _clamp_pan_offset() -> void:
	# 没平移过就直接返回：既省计算，也保证「只有滚轮缩放、没拖过鼠标」时偏移恒为 0
	if _camera == null or _pan_offset == Vector2.ZERO:
		return
	var half := get_viewport().get_visible_rect().size / _camera.zoom * 0.5
	# 参考系必须是「没平移时相机实际会待的位置」，也就是被 limit 钳过之后的落点。
	# 直接拿玩家位置当参考系是错的：玩家常常就站在可显示范围外（比如出生点 y=810，
	# 而 1080 世界里相机的 y 上限是 739.5，全靠 limit 兜着），那样一算就会凭空
	# 冒出一个 -70 的偏移 —— 表现是"只滚了下滚轮，画面就自己挪了一截"。
	var base_center := _camera_anchor().clamp(half, WORLD_SIZE - half)
	_pan_offset = (base_center + _pan_offset).clamp(half, WORLD_SIZE - half) - base_center


## 玩家一有移动输入就把视角滑回身上（拖动只是"去看看别处"，不是新的停留点）。
func _decay_pan_offset(delta: float) -> void:
	if _pan_offset == Vector2.ZERO or _is_panning:
		return
	var moving := false
	if _touch_active:
		moving = _touch_vector != Vector2.ZERO
	else:
		moving = _read_move_input() != Vector2.ZERO
	if not moving:
		return
	# 比相机跟随更快地收回（否则相机自身还在 lerp，两级平滑叠一起会显得迟钝）
	_pan_offset = _pan_offset.lerp(Vector2.ZERO, minf(delta * CAMERA_FOLLOW_SPEED * 2.5, 1.0))
	if _pan_offset.length() < 1.0:
		_pan_offset = Vector2.ZERO


func _build_player() -> void:
	_player = CharacterBody2D.new()
	_player.name = "Player"
	# 出生在慢生活园的宿舍门口（H 区），不再是 E 区入口。
	_player.position = DORM_DOOR_POSITION
	_last_walkable_position = _player.position
	_player.collision_layer = 2
	_player.collision_mask = COLLISION_LAYER
	_player.z_index = 30
	add_child(_player)
	var body_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 17
	body_shape.shape = circle
	body_shape.position = Vector2(0, -10)
	_player.add_child(body_shape)
	var shadow := Polygon2D.new()
	shadow.polygon = PackedVector2Array([Vector2(-24, -4), Vector2(24, -4), Vector2(31, 2), Vector2(18, 8), Vector2(-18, 8), Vector2(-31, 2)])
	shadow.color = Color(0.04, 0.06, 0.08, 0.28)
	shadow.position = Vector2(0, 2)
	_player.add_child(shadow)
	_player_sprite = PAPER_DOLL.new()
	_player_sprite.position = Vector2(-32, -72)
	_player_sprite.configure_motion_speed(PLAYER_SPEED)
	_player.add_child(_player_sprite)
	_player_sprite.set_loadout("bear_green_cardigan")


func _build_npcs() -> void:
	for index in NPCS.size():
		var npc_data: Dictionary = NPCS[index]
		var safe_route := _sanitize_npc_route(npc_data["route"] as PackedVector2Array)
		if safe_route.size() < 2:
			push_warning("NPC %s 没有找到安全巡逻路线，已暂停移动。" % npc_data["name"])
			continue
		var character: Node2D = OFFICE_NPC.new()
		character.configure(String(npc_data["loadout"]), safe_route, 30.0 + index * 2.0, 100 + index)
		add_child(character)
		var name_tag := Label.new()
		name_tag.text = "%s  %s" % [npc_data["name"], npc_data["role"]]
		name_tag.position = Vector2(-62, -112)
		name_tag.add_theme_font_override("font", CHINESE_FONT)
		name_tag.add_theme_font_size_override("font_size", 16)
		name_tag.add_theme_color_override("font_color", Color("fff5d6"))
		name_tag.add_theme_color_override("font_outline_color", Color("20232d"))
		name_tag.add_theme_constant_override("outline_size", 4)
		name_tag.z_index = 2
		name_tag.hide()
		character.add_child(name_tag)
		var entry: Dictionary = npc_data.duplicate()
		entry["character"] = character
		entry["name_tag"] = name_tag
		_npc_instances.append(entry)


# NPC 不能像玩家一样依赖物理碰撞来"推回"，否则会在建筑边缘抖动。
# 创建路线时先把每个点和每一段路线都采样到通行遮罩上，确保不会经过红色碰撞区。
func _sanitize_npc_route(source_route: PackedVector2Array) -> PackedVector2Array:
	var route := PackedVector2Array()
	for source_point in source_route:
		var safe_point := _nearest_npc_walkable_point(source_point)
		if safe_point == Vector2.INF:
			continue
		if route.is_empty():
			route.append(safe_point)
			continue
		if _is_npc_route_segment_safe(route[-1], safe_point):
			route.append(safe_point)
	# A loop must also have a safe final segment back to its first point.
	if route.size() > 2 and not _is_npc_route_segment_safe(route[-1], route[0]):
		route.remove_at(route.size() - 1)
	return route


func _nearest_npc_walkable_point(source_point: Vector2) -> Vector2:
	if _is_walkable_position(source_point):
		return source_point
	# Search in small rings so a point near a red outline moves onto the closest road,
	# instead of jumping across a building or lake.
	for radius in range(12, 181, 12):
		for angle_degrees in range(0, 360, 30):
			var candidate := source_point + Vector2.RIGHT.rotated(deg_to_rad(float(angle_degrees))) * radius
			if _is_walkable_position(candidate):
				return candidate
	return Vector2.INF


func _is_npc_route_segment_safe(from: Vector2, to: Vector2) -> bool:
	var distance := from.distance_to(to)
	var steps := maxi(1, ceili(distance / 8.0))
	for index in range(steps + 1):
		var point := from.lerp(to, float(index) / float(steps))
		if not _is_walkable_position(point):
			return false
	return true


func _build_camera() -> void:
	_camera = Camera2D.new()
	# 室外镜头从玩家身边开始，不再一次展示完整地图。
	# 世界坐标、碰撞和角色位置不变，只有 Camera2D 负责等比缩放与取景。
	_camera.position = _player.position if _player != null else WORLD_SIZE * 0.5
	_camera.zoom = Vector2.ONE * OUTDOOR_EXPLORATION_ZOOM
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = CAMERA_FOLLOW_SPEED
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(WORLD_SIZE.x)
	_camera.limit_bottom = int(WORLD_SIZE.y)
	add_child(_camera)
	_camera.make_current()
	_apply_camera_cover()
	# 平滑是从 (0,0) 滑向世界中心的，头一两秒画面会带着偏移（左侧露灰底），
	# 开局直接落位，不参与平滑
	_camera.reset_smoothing()
	# 窗口尺寸变了（拖拽/转屏）都要重算铺满
	get_viewport().size_changed.connect(_apply_camera_cover)


## 窗口比例和世界（16:9）不一致时，project.godot 的 stretch aspect=expand 会把视口
## 撑到比世界更宽/更高，相机视野超出 0..1920 / 0..1080 的限制范围，
## 画面外就露出灰底（左侧那条灰就是它）。
## 解法：把相机 zoom 拉到「世界铺满视野」（等比 cover，多出的部分裁掉），
## 世界坐标、区域触发、NPC 全都不动 —— 只动相机。
func _apply_camera_cover() -> void:
	if _camera == null:
		return
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	_last_viewport_size = vp
	# view_in_world = vp / zoom，要两个方向都 <= 世界尺寸，zoom 取较大者
	_cover_zoom = maxf(vp.x / WORLD_SIZE.x, vp.y / WORLD_SIZE.y)
	# 铺满系数只是地板：再乘上当前场景的基础缩放与玩家自由缩放倍率才是最终 zoom。
	# 少了后两项，窗口一变 zoom 就会被拽回 1.0，接着又被 _update_camera 拉回去 —— 画面会抖。
	_camera.zoom = Vector2.ONE * _cover_zoom * _base_zoom() * _map_zoom_factor


func _build_walls() -> void:
	for rect in _wall_rects():
		var wall := StaticBody2D.new()
		wall.collision_layer = COLLISION_LAYER
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		shape.position = rect.get_center()
		wall.add_child(shape)
		add_child(wall)


func _build_map_backdrop() -> void:
	var sprite := Sprite2D.new()
	sprite.name = "TownMapReference"
	sprite.texture = _load_map_texture(TOWN_MAP_PATH)
	sprite.centered = false
	if sprite.texture != null:
		var source_size := sprite.texture.get_size()
		sprite.scale = Vector2(WORLD_SIZE.x / source_size.x, WORLD_SIZE.y / source_size.y)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = -100
	add_child(sprite)


func _load_map_texture(path: String) -> Texture2D:
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK:
		push_error("小镇底图加载失败: %s" % path)
		return null
	return ImageTexture.create_from_image(image)


func _load_walkability_mask() -> void:
	_walkability_image = Image.new()
	if _walkability_image.load(ProjectSettings.globalize_path(WALKABILITY_MASK_PATH)) != OK:
		push_error("道路通行遮罩加载失败: %s" % WALKABILITY_MASK_PATH)
		_walkability_image = null
		return
	_walkability_debug_sprite = Sprite2D.new()
	_walkability_debug_sprite.name = "WalkabilityDebugMask"
	_walkability_debug_sprite.texture = ImageTexture.create_from_image(_walkability_image)
	_walkability_debug_sprite.centered = false
	_walkability_debug_sprite.modulate = Color(0.15, 1.0, 0.25, 0.28)
	_walkability_debug_sprite.z_index = 70
	_walkability_debug_sprite.visible = false
	add_child(_walkability_debug_sprite)


func _build_map_collisions() -> void:
	# Player movement is constrained by the pixel mask. Static bodies remain only
	# at the world edge so approximate polygons cannot block a valid curved road.
	_add_wall_collider(Rect2(0, 0, 1920, 18))
	_add_wall_collider(Rect2(0, 1062, 1920, 18))
	_add_wall_collider(Rect2(0, 0, 18, 1080))
	_add_wall_collider(Rect2(1902, 0, 18, 1080))
	var payload := _read_json(COLLISION_DATA_PATH)
	for layer in payload.get("layers", []):
		var layer_id := String(layer.get("id", ""))
		for polygon in layer.get("polygons", []):
			var points := _to_points(polygon)
			_collision_debug_polygons.append(points)
			if layer_id == "decorations":
				_add_polygon_collider(polygon)


func _to_points(points_data: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in points_data:
		if point is Array and point.size() >= 2:
			points.append(Vector2(float(point[0]), float(point[1])))
	return points


func _load_map_data() -> void:
	var region_payload := _read_json(REGIONS_PATH)
	var loaded_zones: Array = []
	for item in region_payload.get("regions", []):
		var rect_data: Dictionary = item.get("rect", {})
		var rect := Rect2(float(rect_data.get("x", 0)), float(rect_data.get("y", 0)), float(rect_data.get("w", 0)), float(rect_data.get("h", 0)))
		loaded_zones.append({
			"id": String(item.get("id", "")), "code": String(item.get("id", "")), "name": String(item.get("name", "")),
			"purpose": String(item.get("purpose", "")), "rect": rect, "center": rect.get_center(),
			"entrance": _dictionary_to_vector(item.get("entrance", {})), "door": "bottom"
		})
	if loaded_zones.size() == 8:
		ZONES = loaded_zones
	var npc_payload := _read_json(NPCS_PATH)
	var loaded_npcs: Array = []
	for item in npc_payload.get("npcs", []):
		var route_points := PackedVector2Array()
		for point in item.get("route", []):
			if point is Array and (point as Array).size() >= 2:
				route_points.append(Vector2(float(point[0]), float(point[1])))
		loaded_npcs.append({
			"zone": String(item.get("zone", "")).to_lower(), "name": String(item.get("name", "")),
			"role": String(item.get("role", "")), "loadout": String(item.get("loadout", "")),
			"route": route_points, "prompt": String(item.get("prompt", "")),
			"sunday_prompt": _string_array(item.get("sunday_prompt", [])),
		})
	if loaded_npcs.size() > 0:
		NPCS = loaded_npcs
	print("[WorkplaceTown] 载入区域 %d 个、NPC %d 位（来源 %s）" % [ZONES.size(), NPCS.size(), NPCS_PATH])
	var navigation_payload := _read_json(NAVIGATION_DATA_PATH)
	var loaded_areas: Array = []
	for item in navigation_payload.get("walkableRegions", []):
		var values: Array = item.get("rect", [])
		if values.size() == 4:
			loaded_areas.append(Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3])))
	if not loaded_areas.is_empty():
		WALKABLE_AREAS = loaded_areas


func _dictionary_to_vector(value: Dictionary) -> Vector2:
	return Vector2(float(value.get("x", 0)), float(value.get("y", 0)))


## jsonl/json 里的字符串数组兜底（sunday_prompt 等纯文案字段）。
func _string_array(value) -> Array:
	var out: Array = []
	if value is Array:
		for item in (value as Array):
			if item is String and not (item as String).is_empty():
				out.append(item)
	elif value is String and not (value as String).is_empty():
		out.append(value)
	return out


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("地图数据文件不存在，使用脚本内置默认值: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _add_polygon_collider(points_data: Array) -> void:
	if points_data.size() < 3:
		return
	var polygon := PackedVector2Array()
	for point in points_data:
		if point is Array and point.size() >= 2:
			polygon.append(Vector2(float(point[0]), float(point[1])))
	if polygon.size() < 3:
		return
	var body := StaticBody2D.new()
	body.collision_layer = COLLISION_LAYER
	var shape := CollisionPolygon2D.new()
	shape.polygon = polygon
	body.add_child(shape)
	add_child(body)


func _is_walkable_position(position: Vector2) -> bool:
	if _walkability_image == null or _walkability_image.is_empty():
		for area in WALKABLE_AREAS:
			if (area as Rect2).grow(-17.0).has_point(position):
				return true
		return false
	var sample_offsets: Array[Vector2] = [Vector2.ZERO, Vector2(-8, 0), Vector2(8, 0), Vector2(0, -8), Vector2(0, 8)]
	for offset: Vector2 in sample_offsets:
		var sample: Vector2 = position + offset
		var x := clampi(roundi(sample.x), 0, _walkability_image.get_width() - 1)
		var y := clampi(roundi(sample.y), 0, _walkability_image.get_height() - 1)
		var pixel := _walkability_image.get_pixel(x, y)
		if pixel.a < 0.5 or pixel.r < 0.5:
			return false
	return true


func _is_inside_active_zone(position: Vector2) -> bool:
	if _active_zone.is_empty():
		return true
	return (_active_zone["rect"] as Rect2).grow(28.0).has_point(position)


func _build_location_markers() -> void:
	for zone in ZONES:
		var code := String(zone["code"])
		var source_rect: Rect2 = LOCATION_MARKER_RECTS.get(code, Rect2())
		var marker := Sprite2D.new()
		marker.name = "LocationMarker%s" % code
		marker.texture = _load_map_texture("res://assets/ui/location_markers/%s.png" % code)
		# 牌子固定在对应建筑上方；镜头移动时与地图保持相对位置。
		marker.position = source_rect.get_center() * (WORLD_SIZE / SOURCE_MAP_SIZE)
		marker.scale = WORLD_SIZE / SOURCE_MAP_SIZE
		marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		marker.z_index = 45
		# 底图无地名；玩家进入区域框时才显示原图裁出的独立木牌。
		marker.visible = false
		add_child(marker)
		_location_markers.append(marker)
		var entrance_marker := Polygon2D.new()
		entrance_marker.name = "Entrance%s" % zone["code"]
		entrance_marker.polygon = PackedVector2Array([Vector2(0, -14), Vector2(12, 8), Vector2(0, 15), Vector2(-12, 8)])
		entrance_marker.color = Color("fff500")
		entrance_marker.position = zone["entrance"]
		entrance_marker.z_index = 44
		add_child(entrance_marker)
		_entrance_markers.append(entrance_marker)


## 地面引导线。z_index = -50：高于地图底图(-100)，低于 NPC(0) 与玩家(30) ——
## 线是铺在路面上的一层漆，人踩在它上面才对。
func _build_guide_line() -> void:
	_guide_line = GROUND_GUIDE.new()
	_guide_line.name = "GroundGuideLine"
	_guide_line.z_index = -50
	add_child(_guide_line)


func _hide_guide_line() -> void:
	if _guide_line == null:
		return
	_guide_line.clear()
	_guide_path_target = Vector2(-99999, -99999)


## 每帧问一次"现在该把人引到哪儿"，再决定要不要重铺这条路。
## 玩家只挪了一点点时只把线头挪过去（set_origin），不重跑寻路 —— BFS 虽便宜，
## 但每帧重建 PackedVector2Array 会让虚线相位在世界坐标里抖。
func _refresh_guide_line(force: bool = false) -> void:
	if _guide_line == null or _player == null:
		return
	# 人在区域内部 / 不在小镇上时，小镇的地面引导没有意义。
	if not _active_zone.is_empty():
		_hide_guide_line()
		return
	var target := _resolve_guide_target()
	if target.is_empty():
		_hide_guide_line()
		return
	var goal: Vector2 = target["position"]
	var urgent: bool = target["urgent"]
	var unchanged := not force \
		and goal.distance_to(_guide_path_target) < 1.0 \
		and urgent == _guide_path_urgent \
		and _player.position.distance_to(_guide_path_origin) < GUIDE_REPATH_DISTANCE
	if unchanged:
		_guide_line.set_origin(_player.position)
		return
	_guide_path_origin = _player.position
	_guide_path_target = goal
	_guide_path_urgent = urgent
	_guide_line.set_path(_build_guide_path(_player.position, goal), urgent)


## 现在该把玩家引到哪儿。只有"此刻真的有地方要去"才铺线：
##   1) 已经到点、还没走完的主线事件 —— 不去就进不了剧情，最强引导（urgent）；
##   2) 本周末自由活动选定的组团/活动所在区域 —— 玩家自己安排的目的地。
##
## 故意**不**给"还没到点的下一个主线"铺线：那是两个月后的事，现在就在地上拖一条
## 穿两条街的线，玩家会读成"立刻过去"。未来的安排只写在左上角任务卡里当信息，
## 不当指令（2026-09-16 用户纠正）。
##
## 返回空字典表示"此刻没有目的地"，此时不画线。
func _resolve_guide_target() -> Dictionary:
	var next_event := WorldClock.next_main_event()
	var snapshot := WorldClock.snapshot()
	if not next_event.is_empty() and _is_event_due(next_event, snapshot):
		var due_zone := _zone_by_code(String(next_event.get("locationId", "")))
		if not due_zone.is_empty():
			return {
				"position": due_zone["entrance"], "code": String(due_zone["code"]),
				"title": String(next_event.get("title", "")), "urgent": true,
			}
	if not _free_guide_zone.is_empty():
		var free_zone := _zone_by_code(_free_guide_zone)
		if not free_zone.is_empty():
			return {
				"position": free_zone["entrance"], "code": String(free_zone["code"]),
				"title": "自由活动", "urgent": false,
			}
	return {}


## 按区域 code（"A".."H"）取 ZONES 条目；找不到返回空字典。
func _zone_by_code(code: String) -> Dictionary:
	var wanted := code.strip_edges().to_upper()
	if wanted.is_empty():
		return {}
	for zone in ZONES:
		if String(zone.get("code", "")).to_upper() == wanted:
			return zone
	return {}


## 自由活动面板里的组团名（"D_树影书院" / "心湖" / "A_总部"）→ 区域 code。
## 前缀字母能直接对上就用；"心湖"这种没有区域的组团返回空（湖中心走不进去）。
func _zone_code_from_free_label(label: String) -> String:
	var trimmed := label.strip_edges()
	if trimmed.is_empty():
		return ""
	var head := trimmed.split("_")[0]
	if head.length() == 1 and not _zone_by_code(head).is_empty():
		return head.to_upper()
	# 兜底：按区域名做包含匹配，"树影书院" → D、"慢生活园" → H。
	for zone in ZONES:
		var zone_name := String(zone.get("name", ""))
		if zone_name.is_empty():
			continue
		if zone_name.contains(trimmed) or trimmed.contains(zone_name.split("·")[0]):
			return String(zone.get("code", "")).to_upper()
	return ""


## 沿道路求一条从 from 到 to 的引导路径。
##
## 做法：把 WALKABLE_AREAS（道路环的若干矩形）看成一张图，两个矩形相交即相邻，
## BFS 出矩形序列，再取**每对相邻矩形交集的中心**当通道点。
## 之所以不用真寻路也不会穿墙：矩形是凸的，而通道点同时落在前后两个矩形内，
## 于是 every 相邻两点的线段都整体留在同一个矩形里 —— 而矩形就是可走区域。
func _build_guide_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var straight := PackedVector2Array([from, to])
	if WALKABLE_AREAS.size() < 2:
		return straight
	var start_index := _closest_area_index(from)
	var goal_index := _closest_area_index(to)
	if start_index < 0 or goal_index < 0:
		return straight
	var chain := _breadth_first_area_chain(start_index, goal_index)
	if chain.is_empty():
		return straight
	var path := PackedVector2Array()
	path.append(from)
	for index in chain.size() - 1:
		path.append(_shared_center(WALKABLE_AREAS[chain[index]] as Rect2, WALKABLE_AREAS[chain[index + 1]] as Rect2))
	path.append(to)
	return _smooth_guide_path(path)


## 两个道路矩形的公共边界中点，用作穿过这对矩形的通道点。
##
## 不用 Rect2.intersection()：它对"贴边但零面积"的一对会返回空矩形 Rect2()，
## 于是 get_center() 给出 (0,0)，路径中间会凭空插一个原点坐标，
## 整条线斜穿整张地图。而贴边恰恰是这份数据的常态 —— b_forecourt 的底边
## 就正好压在 north_road 的顶边上。这里手算 near/far，退化成一个点也照收。
func _shared_center(first: Rect2, second: Rect2) -> Vector2:
	var near := Vector2(maxf(first.position.x, second.position.x), maxf(first.position.y, second.position.y))
	var far := Vector2(minf(first.end.x, second.end.x), minf(first.end.y, second.end.y))
	if near.x > far.x or near.y > far.y:
		# 理论上进不来（BFS 只走相交的矩形对），留个兜底免得再出现原点坐标。
		return (first.get_center() + second.get_center()) * 0.5
	return (near + far) * 0.5


## 包含该点的矩形下标；都不包含时取最近的一个。
func _closest_area_index(point: Vector2) -> int:
	var best := -1
	var best_distance := INF
	for index in WALKABLE_AREAS.size():
		var area: Rect2 = WALKABLE_AREAS[index]
		if area.has_point(point):
			return index
		var distance := point.distance_to(area.get_center())
		if distance < best_distance:
			best_distance = distance
			best = index
	return best


## 两个道路矩形是否连通。必须把"贴边"也算连通：data/town/navigation.json 里
## b_forecourt 的底边 (y=340) 正好压在 north_road 的顶边 (y=340) 上，而
## Godot 的 Rect2.intersects() 默认不含边界 → B 区会被判成孤岛，
## 引导路径退化成一条横穿心湖的直线。include_borders 把这类贴边接回图上。
func _areas_connect(first: int, second: int) -> bool:
	return (WALKABLE_AREAS[first] as Rect2).intersects(WALKABLE_AREAS[second] as Rect2, true)


## BFS 出矩形下标序列（含首尾）。不连通时返回空数组，调用方退化成两点直线。
func _breadth_first_area_chain(start_index: int, goal_index: int) -> Array[int]:
	if start_index == goal_index:
		var single: Array[int] = [start_index]
		return single
	var queue: Array[int] = [start_index]
	var came_from := {start_index: -1}
	while not queue.is_empty():
		var current: int = queue.pop_front()
		if current == goal_index:
			break
		for neighbour in WALKABLE_AREAS.size():
			if neighbour == current or came_from.has(neighbour):
				continue
			if not _areas_connect(current, neighbour):
				continue
			came_from[neighbour] = current
			queue.append(neighbour)
	if not came_from.has(goal_index):
		return [] as Array[int]
	var chain: Array[int] = []
	var cursor: int = goal_index
	while cursor != -1:
		chain.push_front(cursor)
		cursor = int(came_from[cursor])
	return chain


## 把 90° 硬拐角切成二次贝塞尔圆弧。不切的话，沿着道路矩形走出来的折线
## 在拐点处是个尖角，叠上 21px 的投影带会像墙角的描边而不是"路"。
func _smooth_guide_path(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var smoothed := PackedVector2Array()
	smoothed.append(points[0])
	for index in range(1, points.size() - 1):
		var previous := points[index - 1]
		var corner := points[index]
		var following := points[index + 1]
		if previous.distance_to(corner) < 0.001 or corner.distance_to(following) < 0.001:
			continue
		var radius := minf(52.0, minf(previous.distance_to(corner), corner.distance_to(following)) * 0.42)
		if radius < 6.0:
			smoothed.append(corner)
			continue
		var entry := corner + (previous - corner).normalized() * radius
		var exit := corner + (following - corner).normalized() * radius
		for step in range(1, GUIDE_CORNER_STEPS + 1):
			var t := float(step) / float(GUIDE_CORNER_STEPS)
			# de Casteljau 求二次贝塞尔 B(t)，控制点是 corner。
			smoothed.append(entry.lerp(corner, t).lerp(corner.lerp(exit, t), t))
	smoothed.append(points[points.size() - 1])
	return smoothed


func _build_debug_overlay() -> void:
	_debug_overlay = MAP_DEBUG_OVERLAY.new()
	_debug_overlay.name = "MapDebugOverlay"
	_debug_overlay.z_index = 80
	_debug_overlay.configure(WALKABLE_AREAS, ZONES, _collision_debug_polygons)
	add_child(_debug_overlay)


func _wall_rects() -> Array[Rect2]:
	return [Rect2(400, 120, 1060, 18), Rect2(400, 940, 1060, 18), Rect2(400, 120, 18, 838), Rect2(1442, 120, 18, 838), Rect2(1100, 265, 18, 127), Rect2(1100, 476, 18, 289)]


func _build_zone_enclosures() -> void:
	for zone in ZONES:
		_add_enclosure_colliders(zone["rect"] as Rect2, String(zone["door"]))


func _add_enclosure_colliders(rect: Rect2, door_side: String) -> void:
	var thickness := 18.0
	var door_width := 76.0
	var top := Rect2(rect.position.x, rect.position.y - thickness * 0.5, rect.size.x, thickness)
	var bottom := Rect2(rect.position.x, rect.end.y - thickness * 0.5, rect.size.x, thickness)
	var left := Rect2(rect.position.x - thickness * 0.5, rect.position.y, thickness, rect.size.y)
	var right := Rect2(rect.end.x - thickness * 0.5, rect.position.y, thickness, rect.size.y)
	if door_side == "top" or door_side == "bottom":
		var wall := top if door_side == "top" else bottom
		var gap_start := wall.position.x + (wall.size.x - door_width) * 0.5
		_add_wall_collider(Rect2(wall.position.x, wall.position.y, gap_start - wall.position.x, wall.size.y))
		_add_wall_collider(Rect2(gap_start + door_width, wall.position.y, wall.end.x - gap_start - door_width, wall.size.y))
		_add_wall_collider(left)
		_add_wall_collider(right)
		_add_wall_collider(bottom if door_side == "top" else top)
	else:
		var wall := left if door_side == "left" else right
		var gap_start := wall.position.y + (wall.size.y - door_width) * 0.5
		_add_wall_collider(Rect2(wall.position.x, wall.position.y, wall.size.x, gap_start - wall.position.y))
		_add_wall_collider(Rect2(wall.position.x, gap_start + door_width, wall.size.x, wall.end.y - gap_start - door_width))
		_add_wall_collider(top)
		_add_wall_collider(bottom)
		_add_wall_collider(right if door_side == "left" else left)


func _add_wall_collider(rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var wall := StaticBody2D.new()
	wall.collision_layer = COLLISION_LAYER
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.get_center()
	wall.add_child(shape)
	add_child(wall)


## 左上角任务卡：整块深色底板 + 左侧金色竖条 + 右侧区域徽标。
## 原来这里只有一行 24px 裸文字，压在花花绿绿的小镇底图上几乎被背景吞掉；
## 主线是玩家唯一"必须做"的事，视觉权重得压过附近的坐标 / 对话提示。
## 2026-09-17 UI 打磨：432×98 → 500×122 → 560×160，字号整体上调两档（用户反馈「字太小」第二轮）。
func _build_objective_card(layer: CanvasLayer) -> void:
	var card := Panel.new()
	card.name = "ObjectiveCard"
	card.position = Vector2(26, 20)
	card.size = Vector2(560, 160)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_style = StyleBoxFlat.new()
	_objective_style.bg_color = Color(0.07, 0.10, 0.14, 0.84)
	_objective_style.border_color = Color(0.85, 0.70, 0.36, 0.80)
	_objective_style.set_border_width_all(2)
	_objective_style.set_corner_radius_all(10)
	_objective_style.shadow_color = Color(0, 0, 0, 0.38)
	_objective_style.shadow_size = 9
	card.add_theme_stylebox_override("panel", _objective_style)
	layer.add_child(card)
	_zone_status = card

	# 左侧竖色条：一眼区分"到点了（橙金）/ 还没到（暖黄）"。
	_objective_accent = ColorRect.new()
	_objective_accent.position = Vector2(0, 0)
	_objective_accent.size = Vector2(6, 160)
	_objective_accent.color = Color("ffd24a")
	_objective_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(_objective_accent)

	_objective_tag = _make_card_label("当前目标", 20, Color("f0cf8a"), card, Vector2(24, 14), Vector2(320, 28))
	_objective_title = _make_card_label("", 36, Color("fff4d6"), card, Vector2(24, 48), Vector2(400, 56))
	_objective_meta = _make_card_label("", 19, Color("d9bd85"), card, Vector2(24, 112), Vector2(512, 30))
	_objective_badge = _make_card_label("", 36, Color("ffd966"), card, Vector2(430, 46), Vector2(106, 58))
	_objective_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# 三行文字都可能很长（"Agent 出错了算谁的"）。Label 默认不裁剪、会直接画出卡片外
	# （meta 行曾画出 500px 卡右边框，截图确诊），所以三行全部 clip + 省略号，
	# 标题再配一个按字数收缩字号的兜底。
	for label in [_objective_tag, _objective_title, _objective_meta]:
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# 伪粗体：Regular 中文在深底上笔画偏细，撑不起"主线"的分量。
	for label in [_objective_title, _objective_badge]:
		var bold := FontVariation.new()
		bold.base_font = CHINESE_FONT
		bold.variation_embolden = 0.5
		label.add_theme_font_override("font", bold)


func _make_card_label(text: String, font_size: int, color: Color, parent: Control, position: Vector2, size: Vector2) -> Label:
	var label := Label.new()
	label.position = position
	label.size = size
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", CHINESE_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.03, 0.05, 0.08, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	parent.add_child(label)
	return label


## 刷新任务卡的四行内容。标题按字数收缩字号，长标题不缩会被省略号吃掉后半句。
func _set_objective(tag: String, title: String, meta: String, badge: String, urgent: bool) -> void:
	if _zone_status == null:
		return
	_objective_tag.text = tag
	_objective_title.text = title
	_objective_meta.text = meta
	_objective_badge.text = badge
	_objective_badge.visible = not badge.is_empty()
	var title_size := 36
	if title.length() > 15:
		title_size = 28
	elif title.length() > 11:
		title_size = 32
	_objective_title.add_theme_font_size_override("font_size", title_size)
	var accent := Color("ff9f2e") if urgent else Color("ffd24a")
	_objective_accent.color = accent
	_objective_accent.modulate = Color(1, 1, 1, 1)
	_objective_badge.add_theme_color_override("font_color", Color("ffc453") if urgent else Color("ffd966"))
	_objective_urgent = urgent
	if not urgent:
		_objective_style.border_color = Color(0.85, 0.70, 0.36, 0.80)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	layer.layer = 100
	add_child(layer)
	_build_objective_card(layer)
	_coordinate_label = Label.new()
	_coordinate_label.position = Vector2(34, 190)
	_coordinate_label.add_theme_font_override("font", CHINESE_FONT)
	_coordinate_label.add_theme_font_size_override("font_size", 22)
	_coordinate_label.add_theme_color_override("font_color", Color("fff2a8"))
	_coordinate_label.add_theme_color_override("font_outline_color", Color("18202b"))
	_coordinate_label.add_theme_constant_override("outline_size", 4)
	_coordinate_label.text = "地图坐标  x: 0  y: 0"
	_coordinate_label.hide()
	layer.add_child(_coordinate_label)
	_dialog_label = Label.new()
	_dialog_label.position = Vector2(34, 226)
	_dialog_label.size = Vector2(760, 108)
	_dialog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_label.add_theme_font_override("font", CHINESE_FONT)
	_dialog_label.add_theme_font_size_override("font_size", 27)
	_dialog_label.add_theme_color_override("font_color", Color("ffffff"))
	_dialog_label.add_theme_color_override("font_outline_color", Color("172033"))
	_dialog_label.add_theme_constant_override("outline_size", 5)
	_dialog_label.hide()
	layer.add_child(_dialog_label)
	_dialog_timer = Timer.new()
	_dialog_timer.one_shot = true
	_dialog_timer.timeout.connect(_hide_dialog)
	add_child(_dialog_timer)
	_interaction_button = Button.new()
	_interaction_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_interaction_button.position = Vector2(-390, -150)
	_interaction_button.size = Vector2(350, 82)
	_interaction_button.add_theme_font_override("font", CHINESE_FONT)
	_interaction_button.add_theme_font_size_override("font_size", 22)
	_interaction_button.hide()
	_interaction_button.pressed.connect(_begin_interaction)
	layer.add_child(_interaction_button)
	_zone_button = Button.new()
	_zone_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_zone_button.position = Vector2(-390, -150)
	_zone_button.size = Vector2(350, 82)
	_zone_button.add_theme_font_override("font", CHINESE_FONT)
	_zone_button.add_theme_font_size_override("font_size", 22)
	_zone_button.hide()
	_zone_button.pressed.connect(_enter_nearby_zone)
	layer.add_child(_zone_button)
	# 右上角功能圆钮排（记忆墙 / 周末手账 / 设置），退出游戏收进设置弹窗。
	_build_hud_button_row(layer)
	_build_settings_panel()
	# 自由缩放的操作提示 + 当前倍率。放左下角摇杆上方：
	# 右上角被「第一幕」时间面板占着，放那里会被整块盖住。
	# 字号必须够大 + 伪粗体：18px 的 Regular 中文横画只有 1px 宽，
	# 外面套 3px 描边后亮色笔画整根被吃掉，整行看上去是一团暗色。
	var zoom_font := FontVariation.new()
	zoom_font.base_font = CHINESE_FONT
	zoom_font.variation_embolden = 0.55
	_map_zoom_hint = Label.new()
	_map_zoom_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_map_zoom_hint.position = Vector2(44, -228)
	_map_zoom_hint.size = Vector2(460, 32)
	_map_zoom_hint.add_theme_font_override("font", zoom_font)
	_map_zoom_hint.add_theme_font_size_override("font_size", 20)
	_map_zoom_hint.add_theme_color_override("font_color", Color(1.0, 0.94, 0.76, 0.92))
	_map_zoom_hint.add_theme_color_override("font_outline_color", Color("18202b"))
	_map_zoom_hint.add_theme_constant_override("outline_size", 3)
	layer.add_child(_map_zoom_hint)
	_update_zoom_hint()
	_build_mobile_joystick(layer)


## ---------- 右上角功能圆钮排（2026-09-17 UI 打磨） ----------

## 圆钮行的 y 起点：时间面板（y 26..234）正下方。48px 圆 + 8px 间距，一行 4 颗
## （设/账/忆/力）；点「力」开精力弹窗选动作（2026-09-17 第三批拍板）。
const HUD_CIRCLE_ROW_Y := 250.0
const HUD_CIRCLE_SIZE := 48.0

## 从右往左：设置 / 周末手账 / 记忆墙。悬停圆钮时行下方显示名称提示。
func _build_hud_button_row(layer: CanvasLayer) -> void:
	var defs := [
		{"glyph": "设", "tip": "设置 · 操作说明 / 退出游戏", "caption": "设置", "cb": _open_settings},
		{"glyph": "账", "tip": "周末手账 · 翻看走过的每个周末", "caption": "周末手账", "cb": _open_ledger_book},
		{"glyph": "忆", "tip": "记忆墙 · 回看一路攒下的便签", "caption": "记忆墙", "cb": _open_memory_wall},
		{"glyph": "力", "tip": "本月精力 · 花 1 点做一件事", "caption": "本月精力", "cb": _open_energy_modal},
	]
	for i in defs.size():
		var button := _make_circle_button(
			layer,
			String(defs[i]["glyph"]),
			String(defs[i]["tip"]),
			Vector2(-15.0 - HUD_CIRCLE_SIZE * (i + 1) - 8.0 * i, HUD_CIRCLE_ROW_Y)
		)
		button.pressed.connect(_on_circle_button_press.bind(button))
		button.pressed.connect(Callable(defs[i]["cb"]))
		button.mouse_entered.connect(_on_circle_button_hover.bind(button, 1.08))
		button.mouse_entered.connect(_show_hud_button_caption.bind(String(defs[i]["caption"])))
		button.mouse_exited.connect(_on_circle_button_hover.bind(button, 1.0))
		button.mouse_exited.connect(_hide_hud_button_caption)
		if String(defs[i]["glyph"]) == "设":
			_settings_button = button
		elif String(defs[i]["glyph"]) == "账":
			_ledger_book_button = button
		elif String(defs[i]["glyph"]) == "忆":
			_memory_wall_button = button
		# 「力」钮不存成员变量：弹窗实例在 _build_monthly_life 里，见 _open_energy_modal。
	# （2026-09-17 第三批拍板）旧的 4 颗精力动作圆钮已删：整块精力模块收进
	# 一颗「力」钮，点开居中模态弹窗（EnergyModalPanel）再选要做什么。
	_hud_button_caption = Label.new()
	_hud_button_caption.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hud_button_caption.position = Vector2(-410, HUD_CIRCLE_ROW_Y + HUD_CIRCLE_SIZE + 8)
	_hud_button_caption.size = Vector2(395, 24)
	_hud_button_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud_button_caption.add_theme_font_override("font", CHINESE_FONT)
	_hud_button_caption.add_theme_font_size_override("font_size", 17)
	_hud_button_caption.add_theme_color_override("font_color", Color("f3d59a"))
	_hud_button_caption.add_theme_color_override("font_outline_color", Color("18202b"))
	_hud_button_caption.add_theme_constant_override("outline_size", 3)
	_hud_button_caption.hide()
	layer.add_child(_hud_button_caption)


## 圆钮构造。⚠ 顺序必须是 anchors 预设 → position → size（与旧按钮/精力条同款）：
## TOP_RIGHT 锚点下先设 size 会把右边界推到屏幕外，再设 position 也救不回来。
func _make_circle_button(layer: CanvasLayer, glyph: String, tip: String, pos: Vector2) -> Button:
	var button := Button.new()
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.position = pos
	button.size = Vector2(HUD_CIRCLE_SIZE, HUD_CIRCLE_SIZE)
	# 2026-09-17 晚：单字换矢量图标。glyph 参数不再是显示文字，只当图标种类标识
	# （「设/账/忆/力」的 if 链和 tooltip 仍靠它）。字体 override 留着无害，不拆。
	button.text = ""
	button.tooltip_text = tip
	var glyph_view := HUD_GLYPH.new()
	glyph_view.kind = glyph
	glyph_view.size = Vector2(HUD_CIRCLE_SIZE, HUD_CIRCLE_SIZE)
	glyph_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(glyph_view)
	button.add_theme_font_override("font", CHINESE_FONT)
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", Color("ffe5a8"))
	button.add_theme_color_override("font_hover_color", Color("fff4d6"))
	button.add_theme_color_override("font_pressed_color", Color("f0cf8a"))
	button.add_theme_color_override("font_outline_color", Color("23170f"))
	button.add_theme_constant_override("outline_size", 3)
	button.add_theme_stylebox_override("normal", _circle_style(Color(0.329, 0.196, 0.122, 0.94), Color("d49a4c")))
	button.add_theme_stylebox_override("hover", _circle_style(Color(0.42, 0.247, 0.149), Color("ffc453")))
	button.add_theme_stylebox_override("pressed", _circle_style(Color(0.278, 0.165, 0.098), Color("d49a4c")))
	button.pivot_offset = button.size / 2.0
	layer.add_child(button)
	return button


func _circle_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(HUD_CIRCLE_SIZE / 2.0))
	style.shadow_color = Color(0, 0, 0, 0.30)
	style.shadow_size = 6
	return style


func _on_circle_button_hover(button: Button, target_scale: float) -> void:
	var t := button.create_tween()
	t.tween_property(button, "scale", Vector2(target_scale, target_scale), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_circle_button_press(button: Button) -> void:
	button.pivot_offset = button.size / 2.0
	var t := button.create_tween()
	t.tween_property(button, "scale", Vector2(0.92, 0.92), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(button, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _show_hud_button_caption(caption: String) -> void:
	if _hud_button_caption == null:
		return
	_hud_button_caption.text = caption
	_hud_button_caption.show()


func _hide_hud_button_caption() -> void:
	if _hud_button_caption != null:
		_hud_button_caption.hide()


## ---------- 设置弹窗 ----------

func _build_settings_panel() -> void:
	_settings_panel = SETTINGS_PANEL.new()
	_settings_panel.name = "SettingsPanel"
	_settings_panel.settings_closed.connect(_on_settings_closed)
	_settings_panel.quit_requested.connect(_quit_game)
	add_child(_settings_panel)


func _open_settings() -> void:
	if _settings_panel == null:
		_build_settings_panel()
	if _settings_panel.is_open():
		return
	# 记忆墙 / 手账开着时设置钮在弹层之下点不到；这里再兜一层。
	if (_memory_wall != null and _memory_wall.is_open()) \
			or (_ledger_book != null and _ledger_book.is_open()):
		return
	# 与记忆墙同待遇：设置开着时世界时钟停住。
	_settings_resume_clock = WorldClock.running
	if _settings_resume_clock:
		WorldClock.set_running(false)
	_settings_panel.open()


func _on_settings_closed() -> void:
	if _settings_resume_clock:
		WorldClock.set_running(true)
	_settings_resume_clock = false


func _build_mobile_joystick(layer: CanvasLayer) -> void:
	var joystick := Control.new()
	joystick.position = Vector2(44, 875)
	joystick.size = Vector2(150, 150)
	joystick.mouse_filter = Control.MOUSE_FILTER_STOP
	joystick.draw.connect(func():
		joystick.draw_circle(Vector2(75, 75), 65, Color(0.11, 0.16, 0.21, 0.40))
		joystick.draw_arc(Vector2(75, 75), 65, 0, TAU, 40, Color(1, 1, 1, 0.58), 3)
		joystick.draw_circle(Vector2(75, 75) + _touch_vector * 38, 25, Color(1, 1, 1, 0.78))
	)
	joystick.gui_input.connect(func(event):
		if event is InputEventScreenTouch or event is InputEventMouseButton:
			_touch_active = event.pressed
			if not _touch_active:
				_touch_vector = Vector2.ZERO
		if event is InputEventScreenDrag or event is InputEventMouseMotion:
			if _touch_active:
				_touch_vector = (joystick.get_local_mouse_position() - Vector2(75, 75)).limit_length(55) / 55.0
		joystick.queue_redraw()
	)
	layer.add_child(joystick)


func _update_zone_state() -> void:
	_update_location_marker_visibility()
	if not _active_zone.is_empty():
		_nearby_zone = {}
		_zone_button.hide()
		return
	_nearby_zone = {}
	for zone in ZONES:
		var entrance: Vector2 = zone["entrance"]
		if _player.position.distance_to(entrance) <= ENTRANCE_DISTANCE:
			_nearby_zone = zone
			_zone_button.text = "进入 %s区  ·  E" % zone["code"]
			_zone_button.show()
			return
	_zone_button.hide()


func _update_location_marker_visibility() -> void:
	var entered_code := ""
	if _active_zone.is_empty() and _player != null:
		for zone in ZONES:
			if (zone["rect"] as Rect2).has_point(_player.position):
				entered_code = String(zone["code"])
				break
	for marker in _location_markers:
		marker.visible = marker.name == "LocationMarker%s" % entered_code


func _enter_nearby_zone() -> void:
	if _nearby_zone.is_empty() or not _active_zone.is_empty():
		return
	# 夜晚/22 点后进 H 区 = 回宿舍（任务卡许诺「走到 H 区宿舍按 E」就睡）：
	# 直接开宿舍屏（门口能出、床边能睡），不开慢生活园室内预览——
	# 那里面没有任何睡觉交互，玩家会被困住只能干等 23 点宵禁兜底。
	# 2026-09-17 晚：精力见底后白天进 H 区也开宿舍屏——「精力用完只提示不跳 22:00」
	# 之后，玩家结束本月的唯一入口就是自己回宿舍上床睡觉，白天必须进得去。
	# 精力还有结余的白天仍走室内预览，保留逛桌游馆的入口。
	if String(_nearby_zone.get("code", "")) == "H" and (_needs_sleep() or _energy_spent_out()):
		_nearby_zone = {}
		_enter_dorm(false)
		return
	_active_zone = _nearby_zone
	_nearby_zone = {}
	_zone_entered_msec = Time.get_ticks_msec()
	ApiClient.record_event("region_entered", {"regionId": String(_active_zone.get("code", ""))})
	_zone_button.hide()
	_zone_status.hide()
	_dialog_label.hide()
	for marker in _location_markers:
		marker.hide()
	for npc in _npc_instances:
		var is_current := String(npc["zone"]).to_lower() == String(_active_zone["id"]).to_lower()
		var character := npc["character"] as Node2D
		var tag := npc["name_tag"] as Label
		character.visible = is_current
		tag.visible = is_current
	var texture_path := String(INTERIOR_ASSETS.get(String(_active_zone["code"]), ""))
	if not texture_path.is_empty():
		_interior_preview.present(_active_zone, texture_path)
		_interior_preview.set_phase(String(WorldClock.snapshot().get("phaseId", "work")))
	var event_opened := _open_due_event_for_active_zone()
	if not event_opened:
		_interior_preview.enable_exploration()
		# 回声不跟剧情开场抢话：有事件先演事件，回声留给下次进来。
		# 周日坐下优先于回声——这个周日只有一次坐下，回声不在这天的话下次还在。
		if not (_is_sunday() and _maybe_show_sunday_sit()):
			_maybe_show_weekend_echo()


func _exit_zone() -> void:
	if _active_zone.is_empty():
		return
	var region_id := String(_active_zone.get("code", ""))
	if _zone_entered_msec > 0:
		ApiClient.record_event("zone_dwell", {
			"regionId": region_id,
			"durationMs": maxi(0, Time.get_ticks_msec() - _zone_entered_msec),
		})
	_zone_entered_msec = 0
	_active_zone = {}
	_nearby_npc = {}
	_interaction_button.hide()
	_zone_status.show()
	if _interior_preview != null:
		_interior_preview.dismiss()
	_refresh_objective_hint()
	for marker in _location_markers:
		marker.hide()
	for npc in _npc_instances:
		(npc["character"] as Node2D).show()
		(npc["name_tag"] as Label).hide()
	_hide_dialog()


## ---------------------------------------------------------------------------
## 宿舍 / 宵禁
## 玩家每天从慢生活园的宿舍出发，晚上 CURFEW_HOUR 点必须回到宿舍。
## 到点没回来也没关系 —— 人会被直接送回宿舍，那一晚只剩「睡觉」一个选项，
## 睡醒是第二天 WAKE_UP_HOUR 点，重新出现在宿舍门口。
## ---------------------------------------------------------------------------

func _build_dorm_room() -> void:
	_dorm = DORM_ROOM.new()
	_dorm.leave_requested.connect(_on_dorm_leave)
	_dorm.sleep_requested.connect(_on_dorm_sleep)
	add_child(_dorm)


func _enter_dorm(curfew: bool) -> void:
	if _dorm == null:
		return
	if not _active_zone.is_empty():
		_exit_zone()
	_in_dorm = true
	_hide_dialog()
	_interaction_button.hide()
	_zone_button.hide()
	_zone_status.hide()
	if curfew:
		# 宵禁这一晚把时间钉住：不然玩家发呆的功夫，游戏时间会一路跑到后半夜。
		WorldClock.set_running(false)
	_dorm.present(curfew)


func _on_dorm_leave() -> void:
	_in_dorm = false
	if _dorm != null:
		_dorm.dismiss()
	_place_player_at_dorm_door()
	_zone_status.show()
	_refresh_objective_hint()
	# 开局第 1 月 1 日 09:00 正好是 E01 的时点。时间不自动流之后它不会自己演，
	# 所以「出门」这个动作补一次点火 —— 出门报到，剧情接上。
	WorldClock.trigger_event_at_now()


func _on_dorm_sleep() -> void:
	_in_dorm = false
	if _dorm != null:
		_dorm.dismiss()
	# 睡觉 = 结束本月（2026-09-17 晚拍板）：直接进下一个月 1 日早上；
	# 路上有未结算主线时守卫会停在事件上，绝不把剧情睡过去。
	WorldClock.sleep_to_next_month(WAKE_UP_HOUR)
	# 睡醒当天挂着主线（多在 9:00）→ 补一枪点火，事件门亮起来引导玩家走过去。
	# 不补这枪，停钟世界没人把 7:00 推到 9:00，剧情会永远挂起（跳月卡死的根因）。
	WorldClock.fire_due_event_today()
	_place_player_at_dorm_door()
	_zone_status.show()
	_refresh_objective_hint()


## 出门时把人钉在宿舍门口，并让相机直接落位 ——
## 不落位的话镜头会从昨晚待的地方一路滑过来，看着像瞬移失败。
func _place_player_at_dorm_door() -> void:
	if _player == null:
		return
	_player.position = DORM_DOOR_POSITION
	_player.velocity = Vector2.ZERO
	_last_walkable_position = _player.position
	if _camera != null:
		_camera.position = _player.position
		_camera.reset_smoothing()


## 宿舍现在要玩家自己走到门口 / 床边才出确认框（见 scripts/DormRoom.gd），
## 这里只留一个"直接执行"的入口给自检脚本用。
func _confirm_dorm_action() -> void:
	if _dorm == null:
		return
	if _dorm.is_curfew():
		_on_dorm_sleep()
	else:
		_on_dorm_leave()


## 一过 CURFEW_HOUR 点就把玩家送回宿舍，同一天只送一次。
func _check_curfew(snapshot: Dictionary) -> void:
	if _dorm == null or _in_dorm:
		return
	if int(snapshot.get("hour", 0)) < CURFEW_HOUR:
		return
	var day_key := "%d-%d" % [int(snapshot.get("month", 1)), int(snapshot.get("day", 1))]
	if _curfew_day_key == day_key:
		return
	# 主线剧情开着时先让玩家把选择做完；WorldClock 暂停也说明有事件等处理，
	# 这时候拽人回宿舍，那个事件就再也触发不到了。
	if _story_event_panel != null and _story_event_panel.is_open():
		return
	if not WorldClock.running:
		return
	_curfew_day_key = day_key
	_enter_dorm(true)


## ---------- 精力耗尽联动（2026-09-17 UI 打磨批次） ----------

## 玩家花掉本月最后 1 点精力（MonthlyLife.energy_exhausted）：
## 2026-09-17 晚拍板：只弹一条提示 —— 不拨时间、不催睡觉。
## 玩家自己决定接下来干嘛：继续逛小镇，或回宿舍上床睡觉结束本月
## （精力见底后，白天走进 H 区也直接开宿舍屏，见 _enter_nearby_zone）。
func _on_energy_exhausted() -> void:
	_show_reminder_toast("本月精力用完了", "下个月初补满 3 点 · 想结束这个月就回宿舍睡一觉")


## 顶部提醒横幅：屏幕顶上下滑入 → 停 3.6s → 上滑淡出自毁。全程不挡鼠标。
## 新横幅来了先撕旧的，避免叠罗汉。
func _show_reminder_toast(title: String, sub: String) -> void:
	if _toast_layer == null:
		_toast_layer = CanvasLayer.new()
		_toast_layer.layer = 190
		add_child(_toast_layer)
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	if _toast_panel != null:
		_toast_panel.queue_free()
	var panel := Panel.new()
	_toast_panel = panel
	panel.position = Vector2((1920.0 - 600.0) / 2.0, -100)
	panel.size = Vector2(600, 92)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.329, 0.196, 0.122, 0.97)
	style.border_color = Color("ffc453")
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 14
	panel.add_theme_stylebox_override("panel", style)
	_toast_layer.add_child(panel)
	# 左侧圆徽 + 标题 + 副文案。
	var chip := Panel.new()
	chip.position = Vector2(20, 26)
	chip.size = Vector2(40, 40)
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = Color("ef9f27")
	chip_style.set_corner_radius_all(20)
	chip.add_theme_stylebox_override("panel", chip_style)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(chip)
	var chip_label := Label.new()
	chip_label.text = "息"
	chip_label.add_theme_font_override("font", CHINESE_FONT)
	chip_label.add_theme_font_size_override("font_size", 20)
	chip_label.add_theme_color_override("font_color", Color("3a2410"))
	chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip_label.size = Vector2(40, 40)
	chip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(chip_label)
	var title_label := Label.new()
	title_label.text = title
	title_label.position = Vector2(76, 14)
	title_label.size = Vector2(500, 32)
	title_label.add_theme_font_override("font", CHINESE_FONT)
	title_label.add_theme_font_size_override("font_size", 23)
	title_label.add_theme_color_override("font_color", Color("ffe5a8"))
	title_label.add_theme_color_override("font_outline_color", Color("23170f"))
	title_label.add_theme_constant_override("outline_size", 3)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title_label)
	var sub_label := Label.new()
	sub_label.text = sub
	sub_label.position = Vector2(76, 48)
	sub_label.size = Vector2(500, 28)
	sub_label.add_theme_font_override("font", CHINESE_FONT)
	sub_label.add_theme_font_size_override("font_size", 17)
	sub_label.add_theme_color_override("font_color", Color("fff0c9"))
	sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(sub_label)
	# 滑入 → 停留 → 滑出自毁。
	_toast_tween = create_tween()
	_toast_tween.tween_property(panel, "position:y", 36.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(3.6)
	_toast_tween.tween_property(panel, "position:y", -100.0, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_toast_tween.parallel().tween_property(panel, "modulate:a", 0.0, 0.26)
	_toast_tween.tween_callback(panel.queue_free)


func _update_nearby_npc() -> void:
	_nearby_npc = {}
	if _active_zone.is_empty():
		_interaction_button.hide()
		return
	for npc in _npc_instances:
		if String(npc["zone"]).to_lower() != String(_active_zone["id"]).to_lower():
			continue
		var npc_position := (npc["character"] as Node2D).position
		if _player.position.distance_to(npc_position) <= INTERACTION_DISTANCE:
			_nearby_npc = npc
			_interaction_button.text = "与 %s 交谈  ·  E" % npc["name"]
			_interaction_button.show()
			return
	_interaction_button.hide()


func _update_camera(delta: float) -> void:
	if _camera == null or _player == null:
		return
	# 玩家自由缩放倍率叠在场景基础缩放之上：缩到最小时（下限）视野正好铺满整个世界。
	var target_zoom := Vector2.ONE * _base_zoom() * _cover_zoom * _map_zoom_factor
	# 拖动平移：相机可以暂时离开玩家去看别处，玩家一有移动输入就滑回去
	_decay_pan_offset(delta)
	var target_position := _camera_anchor() + _pan_offset
	if _is_panning:
		# 拖动中不做平滑，手感才跟手（松手后重新交给 lerp）
		_camera.position = target_position
	else:
		_camera.position = _camera.position.lerp(target_position, minf(delta * CAMERA_FOLLOW_SPEED, 1.0))
	_camera.zoom = _camera.zoom.lerp(target_zoom, minf(delta * 4.2, 1.0))


func _build_world_time() -> void:
	_time_hud = TIME_HUD.new()
	add_child(_time_hud)
	WorldClock.time_changed.connect(_on_world_time_changed)
	WorldClock.main_event_reached.connect(_on_main_event_reached)
	_on_world_time_changed(WorldClock.snapshot())
	var environment_layer := CanvasLayer.new()
	environment_layer.layer = 40
	add_child(environment_layer)
	_environment_tint = ColorRect.new()
	_environment_tint.color = Color(1, 1, 1, 0)
	_environment_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_environment_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	environment_layer.add_child(_environment_tint)


## 月度生活系统 + 两块面板。MonthlyLife 故意不做 autoload：
## 引用从这里下发，探针也能直接 new（见 build/probe_free_time.gd）。
func _build_monthly_life() -> void:
	_monthly_life = MONTHLY_LIFE.new()
	_monthly_life.name = "MonthlyLife"
	add_child(_monthly_life)
	# 2026-09-17（24 件基准拍板 #2/#7）：精力与时间脱钩。
	# 精力 = 每月 3 点的养成额度，不再承担「推进时段」的职责；
	# 时间推进改为双驱动：睡觉跨天（_on_dorm_sleep）+ 主线事件结算推进一拍
	# （_on_story_outcome_acknowledged → WorldClock.advance_phase）。
	# 弹窗自己监听 state_changed 刷新圆点/置灰；「精力耗尽」信号挂在 MonthlyLife 上
	# （2026-09-17 自 EnergyPanel 上移）：弹窗行动卡是唯一消费路径，走 spend_energy
	# —— 花掉最后 1 点 → 只弹顶部横幅提示（2026-09-17 晚拍板：不再跳 22:00）。
	_monthly_life.energy_exhausted.connect(_on_energy_exhausted)
	# 主线门禁（2026-09-17 晚拍板）：当月主线没过完，花精力一律被 MonthlyLife 硬拦、
	# 弹窗按钮置灰。判定在 WorldClock.main_event_due，用 Callable 注入——
	# MonthlyLife 刻意不依赖 autoload，探针才能直接 new 出来测。
	_monthly_life.main_gate = _main_event_gate
	# 精力弹窗（2026-09-17 第三批拍板）：右上角只留一颗「力」钮，点开居中模态弹窗选动作。
	_energy_panel = ENERGY_PANEL.new()
	_energy_panel.setup(_monthly_life)
	_energy_panel.main_gate = _main_event_gate
	_energy_panel.closed.connect(_on_energy_modal_closed)
	add_child(_energy_panel)
	_free_time_panel = FREE_TIME_PANEL.new()
	_free_time_panel.setup(_monthly_life)
	_free_time_panel.weekend_closed.connect(_on_weekend_closed)
	_free_time_panel.memo_requested.connect(_on_memo_recorded)
	_free_time_panel.weekend_ledger.connect(_on_weekend_ledger)
	_free_time_panel.zone_focused.connect(_on_free_zone_focused)
	add_child(_free_time_panel)


## 自由周末选了组团 → 把地面指引线改指那个区域，任务卡同时换成"自由活动"。
## 组团名到区域 code 的换算在 _zone_code_from_free_label（"D_树影书院" → "D"）。
func _on_free_zone_focused(zone_label: String) -> void:
	_free_guide_zone = _zone_code_from_free_label(zone_label)
	_refresh_objective_hint()
	_refresh_guide_line(true)


func _on_weekend_closed(month: int) -> void:
	if not _weekend_done_months.has(month):
		_weekend_done_months.append(month)
	# 收束即清理目的地引导（2026-09-17）：残留曾让任务卡和地面线在周末过完后
	# 继续喊「周末目的地 · 跟着地面指引走」，把玩家骗到已过完的区域踩空。
	# 先把目的地捕获下来，收尾时若人正好还站在那里，补一句周末余韵。
	var stayed_zone := _free_guide_zone
	_free_guide_zone = ""
	# 契约 payload.regionId 是必填且强制 ^[A-H]$（server.py post_event），缺了会被 400 拒。
	# weekend_close 是全局收束事件、没有天然区域，取当前所在区域；取不到就退回总部 A。
	var close_region := String(_active_zone.get("code", "")) if not _active_zone.is_empty() else ""
	ApiClient.record_event("weekend_close", {
		"regionId": close_region if close_region.length() == 1 else "A",
		"month": month,
		"snapshot": WorldClock.snapshot(),
	})
	WorldClock.set_running(true)
	# 时间恢复流动后再刷任务卡：此刻 _free_guide_zone 已空，卡会回到「下一个主线」。
	_refresh_objective_hint()
	# 周日 = 周末收束的次日（§13.1）。这一天的打开方式：NPC 说周日闲话（不加好感）、
	# 湖边/天台可以坐下待一会儿；什么日程都没有。
	_sunday_day_index = int(WorldClock.snapshot().get("dayIndex", -1)) + 1
	_sunday_sit_done = false
	_check_curfew(WorldClock.snapshot())
	# 周末余韵：人正好还站在刚过完的目的地区，给一句收束台词，让「过完了」有落点。
	if not stayed_zone.is_empty() and not _active_zone.is_empty() \
			and String(_active_zone.get("code", "")) == stayed_zone:
		var zone_name := String(_zone_by_code(stayed_zone).get("name", "目的地"))
		_dialog_label.text = "%s的热闹还没散尽。你在人群边上又站了一会儿。" % zone_name
		_dialog_label.show()
		_dialog_timer.start(8.0)
	# 面板关掉、人回到小镇上：这时候才该重新铺线（面板开着时玩家看不到地图）。
	# 引导目的地已清空，这条刷新会把旧线撤掉、也不会再铺向过完的周末。
	_refresh_guide_line(true)


## 今天是不是「周日」（周末收束后的那一天）。没收束过任何周末时恒否。
func _is_sunday() -> bool:
	return _sunday_day_index >= 0 \
		and int(WorldClock.snapshot().get("dayIndex", -1)) == _sunday_day_index


## 周日的坐下时刻（§13.1：湖边 + 天台各一个「坐下」，走遍小镇想待会儿就待会儿）。
## 湖边（心湖）与天台（A_总部）都在 A 区——进 A 区就算走到位，一個周日只坐一次。
## 只落 zone_dwell（进区/出区本来就会记），不加任何数值、不进 events.jsonl。
func _maybe_show_sunday_sit() -> bool:
	if _sunday_sit_done or _active_zone.is_empty() \
			or String(_active_zone.get("code", "")) != "A":
		return false
	_sunday_sit_done = true
	var line := "你在湖边坐下。水面把云搬得很慢，你也没急着去哪。"
	if int(WorldClock.snapshot().get("dayIndex", 0)) % 2 == 1:
		line = "天台的风还是那个风。今天它只负责吹，不负责让你清醒。"
	_dialog_label.text = line
	_dialog_label.show()
	_dialog_timer.start(8.0)
	return true


## 每 3 个月一个自由周末（第 3/6/9…月）。进月时若该月没有待结算的主线事件
## （或主线已结完），就弹自由周末；本月还有主线时先推主线，主线结完自然轮到周末。
func _maybe_open_weekend(snapshot: Dictionary) -> void:
	if _free_time_panel == null or _monthly_life == null:
		return
	var month := int(snapshot["month"])
	if month % 3 != 0 or _weekend_done_months.has(month):
		return
	if _in_dorm or _free_time_panel.is_open():
		return
	var next_event := WorldClock.next_main_event()
	if not next_event.is_empty() and int(next_event["month"]) == month:
		return
	# 开面板期间世界时钟停住：周末是要慢慢挑的，不该边挑边被宵禁拽走。
	WorldClock.set_running(false)
	_free_time_panel.open_for_month(month)


func _on_world_time_changed(snapshot: Dictionary) -> void:
	if _monthly_life != null:
		# 跨天 → 体力回满；跨月 → 补一次月底工资结算（见 MonthlyLife.sync）。
		_monthly_life.sync(int(snapshot["month"]), int(snapshot.get("dayIndex", 0)))
	if _time_hud != null:
		_time_hud.set_time(snapshot)
	_maybe_open_weekend(snapshot)
	if _interior_preview != null and _interior_preview.is_open():
		_interior_preview.set_phase(String(snapshot.get("phaseId", "work")))
	_check_curfew(snapshot)
	_refresh_objective_hint()
	if _environment_tint == null:
		return
	# 键必须与 WorldClock.PHASES 的 id 一一对应，漏一个就会退成「不压色」。
	var tint_by_phase := {
		"morning": Color(0.93, 0.72, 0.42, 0.12),
		"work": Color(1, 1, 1, 0.0),
		"offwork": Color(0.88, 0.46, 0.20, 0.20),
		"night": Color(0.07, 0.14, 0.35, 0.42),
	}
	_environment_tint.color = tint_by_phase.get(String(snapshot["phaseId"]), Color(1, 1, 1, 0))


## （原「跳空白日/跳到下个内容日」逻辑已删：2026-09-17 晚拍板，睡觉 = 进下月，
## 不再吞月份——那套跳法曾把月 2 整个吞掉、还让事件门停在 7:00 永远点不亮。）


## 该回宿舍了吗：走到夜晚时段就该睡了。
## 2026-09-17：删掉「体力 ≤ 1」条件 —— 精力改月度后整个月大多 ≤ 1，
## 那个旧条件会让任务卡从月初就一直喊「精力见底」。
## 2026-09-17 第三批：22 点起也算「该回了」——精力耗尽横幅在 22:00 就喊玩家
## 回宿舍睡一觉，任务卡与宿舍入口必须跟这个口径一致（旧口径要 23 点夜晚段才认，
## 玩家 22:00 走到宿舍会被「按了没反应」困住，只能干等宵禁）。
## 2026-09-17 晚：精力耗尽不再替玩家跳 22:00，这个判定保留给「夜晚/22 点后进 H 区」。
func _needs_sleep() -> bool:
	if _in_dorm:
		return false
	if int(WorldClock.snapshot().get("phaseIndex", 0)) >= WorldClock.PHASES.size() - 1:
		return true
	return int(WorldClock.snapshot().get("hour", 0)) >= ENERGY_CURFEW_JUMP_HOUR


## 本月精力已见底（H 区白天开宿舍屏的条件之一）：
## 精力用完只提示不跳时间之后，玩家结束本月的入口 = 自己回宿舍上床睡觉。
func _energy_spent_out() -> bool:
	return _monthly_life != null and int(_monthly_life.energy) <= 0


## MonthlyLife.spend_energy 与精力弹窗共用的主线门禁：
## 当月主线没过完 → 不许花精力（Callable 注入，MonthlyLife/弹窗都不依赖 autoload）。
func _main_event_gate() -> bool:
	return WorldClock.main_event_due()


func _on_main_event_reached(event: Dictionary) -> void:
	_highlighted_zone_id = String(event.get("locationId", ""))
	ApiClient.record_event("event_trigger", {
		"regionId": String(event.get("locationId", "")),
		"storyId": String(event.get("id", "")),
		"snapshot": WorldClock.snapshot(),
	})
	if _time_hud != null:
		_time_hud.show_event_gate(event)
	_refresh_objective_hint()
	# 事件到点 = 引导线切成"救火"态（橙金 + 加速流动），必须立刻重铺。
	_refresh_guide_line(true)
	if not _active_zone.is_empty() and String(_active_zone.get("code", "")) == String(event.get("locationId", "")):
		_story_event = event.duplicate(true)
		_story_event_panel.present(_story_event)


func _refresh_objective_hint() -> void:
	_apply_objective_content()
	# 任务卡和地面引导线是同一份"当前目标"的两种说法，永远一起刷新：
	# 分开调用时最容易出现"卡上写着去 B 区、地上那条线却还指着 D 区"。
	_refresh_guide_line(true)


## 按优先级决定任务卡上写什么。优先级必须与 _resolve_guide_target 保持一致：
## 夜晚该睡 > 到点主线 > 自由活动 > 未到点主线 > 主线已完结。
func _apply_objective_content() -> void:
	if _zone_status == null:
		return
	# 夜晚排最前：时段走到夜晚 = 今天的事拍完了，该睡了。
	if _needs_sleep():
		_set_objective(
			"夜深了",
			"回 H 区宿舍睡一觉",
			"次日 %02d:00 出发 · 走到 H 区宿舍按 E" % WAKE_UP_HOUR,
			"H 区",
			true
		)
		return
	var next_event := WorldClock.next_main_event()
	var snapshot := WorldClock.snapshot()
	if not next_event.is_empty() and _is_event_due(next_event, snapshot):
		var due_zone := _zone_by_code(String(next_event.get("locationId", "")))
		_set_objective(
			"主线 · 现在就去做",
			String(next_event.get("title", "")),
			"已到点 · 去 %s 区跟着地面指引走" % String(due_zone.get("code", "?")),
			"%s 区" % String(due_zone.get("code", "?")),
			true
		)
		return
	if not _free_guide_zone.is_empty():
		var free_zone := _zone_by_code(_free_guide_zone)
		if not free_zone.is_empty():
			_set_objective(
				"自由活动",
				String(free_zone.get("name", "")),
				"周末目的地 · 跟着地面指引走",
				"%s 区" % String(free_zone.get("code", "?")),
				false
			)
			return
	if next_event.is_empty():
		_set_objective("主线已完成", "自由探索职业区域", "随便走走，或打开右上角「记忆墙」回顾一路的选择", "", false)
		return
	var upcoming_zone := _zone_by_code(String(next_event.get("locationId", "")))
	var event_month := int(next_event.get("month", 1))
	var months_left := event_month - int(snapshot.get("month", 1))
	var when := "第 %d 月 %02d 日" % [event_month, int(next_event.get("day", 1))]
	if months_left > 0:
		when += " · 还有 %d 个月" % months_left
	else:
		when += " · 本月内"
	_set_objective(
		"下一个主线",
		String(next_event.get("title", "")),
		"%s · 到点后地面才会出现指引线" % when,
		"%s 区" % String(upcoming_zone.get("code", "?")),
		false
	)


func _is_event_due(event: Dictionary, snapshot: Dictionary) -> bool:
	if WorldClock.running:
		return false
	var event_minute := ((int(event.get("month", 1)) - 1) * 30 + (int(event.get("day", 1)) - 1)) * 24 * 60 + int(event.get("hour", 9)) * 60
	return int(snapshot.get("worldMinute", 0)) >= event_minute


func _build_interior_preview() -> void:
	_interior_preview = INTERIOR_PREVIEW.new()
	_interior_preview.exit_requested.connect(_exit_zone)
	_interior_preview.player_message_submitted.connect(_on_interior_message_submitted)
	add_child(_interior_preview)

func _build_story_event_panel() -> void:
	_story_event_panel = STORY_EVENT_PANEL.new()
	_story_event_panel.choice_confirmed.connect(_on_story_choice_confirmed)
	_story_event_panel.outcome_acknowledged.connect(_on_story_outcome_acknowledged)
	_story_event_panel.decision_opened.connect(_on_decision_opened)
	_story_event_panel.choice_hovered.connect(_on_choice_hovered)
	_story_event_panel.handbook_recorded.connect(_on_handbook_recorded)
	_story_event_panel.memo_recorded.connect(_on_memo_recorded)
	add_child(_story_event_panel)


## 心湖记忆墙。数据在磁盘上，所以它是常驻节点 —— 不依附于任何一次剧情事件。
func _build_memory_wall() -> void:
	_memory_wall = MEMORY_WALL.new()
	_memory_wall.name = "MemoryWall"
	_memory_wall.wall_closed.connect(_on_memory_wall_closed)
	add_child(_memory_wall)


func _open_memory_wall() -> void:
	if _memory_wall == null:
		return
	if _memory_wall.is_open():
		return
	# 开墙期间世界时钟停住：一墙便签是要慢慢看的，不该边看边被宵禁拽走。
	_wall_resume_clock = WorldClock.running
	if _wall_resume_clock:
		WorldClock.set_running(false)
	_memory_wall.open()


func _on_memory_wall_closed() -> void:
	if _wall_resume_clock:
		WorldClock.set_running(true)
	_wall_resume_clock = false


## 周末手账册（§6.2）：16 页，已过是卡、未到是「还没到」的空格。
func _build_ledger_book() -> void:
	_ledger_book = LEDGER_BOOK.new()
	_ledger_book.name = "WeekendLedgerBook"
	_ledger_book.book_closed.connect(_on_ledger_book_closed)
	add_child(_ledger_book)


func _open_ledger_book() -> void:
	if _ledger_book == null:
		_build_ledger_book()
	if _ledger_book.is_open():
		return
	# 与记忆墙同一待遇：看手账时世界时钟停住。
	_ledger_resume_clock = WorldClock.running
	if _ledger_resume_clock:
		WorldClock.set_running(false)
	_ledger_book.open(_read_weekend_records(), int(WorldClock.snapshot().get("month", 1)))


func _on_ledger_book_closed() -> void:
	if _ledger_resume_clock:
		WorldClock.set_running(true)
	_ledger_resume_clock = false


## 读全部周末手账（jsonl → 数组）。文件不存在就是新档：返回空，手账册全页「还没到」。
func _read_weekend_records() -> Array:
	var records: Array = []
	var f := FileAccess.open("user://workplace_town_weekends.jsonl", FileAccess.READ)
	if f == null:
		return records
	while not f.eof_reached():
		var raw := f.get_line()
		if raw.strip_edges().is_empty():
			continue
		var parsed = JSON.parse_string(raw)
		if parsed is Dictionary:
			records.append(parsed)
	f.close()
	return records


## ---- D 件·回声（§6.1）：进区域时同行者冒一句提起上周末的话 ----

func _load_echo_config() -> Dictionary:
	if not _echo_config.is_empty():
		return _echo_config
	var f := FileAccess.open("res://data/story/weekend_echo.json", FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_echo_config = parsed
	return _echo_config


## 进区域时最多冒一句；没演过 / 都消费完了 / 活动没词，就安静。
## 消费在展示之后：整条手账 echoConsumed 写回 jsonl，不做复读机。
func _maybe_show_weekend_echo() -> void:
	var echo_cfg := _load_echo_config()
	if echo_cfg.is_empty():
		return
	var picked: Dictionary = _monthly_life.pick_weekend_echo(
		_read_weekend_records(), String(_active_zone.get("code", "")),
		echo_cfg, MONTHLY_LIFE.NPC_NAMES)
	if picked.is_empty():
		return
	_dialog_label.text = "%s：%s" % [String(picked.get("npcName", "有人")), String(picked.get("line", ""))]
	_dialog_label.show()
	_dialog_timer.start(6.0)
	_monthly_life.consume_weekend_echo(
		"user://workplace_town_weekends.jsonl",
		int(picked.get("month", 0)), String(picked.get("slotId", "")))

func _open_due_event_for_active_zone() -> bool:
	var next_event := WorldClock.next_main_event()
	if next_event.is_empty() or _active_zone.is_empty():
		return false
	if String(next_event.get("locationId", "")) != String(_active_zone.get("code", "")):
		return false
	if WorldClock.running:
		return false
	_story_event = next_event.duplicate(true)
	_story_event_panel.present(_story_event)
	return true


func _begin_interaction() -> void:
	if _nearby_npc.is_empty():
		return
	# 周日闲话（§13.1）：只换台词，**不加好感**——加了玩家就会把周日刷成好感资源。
	var prompt := String(_nearby_npc.get("prompt", ""))
	var sunday_lines = _nearby_npc.get("sunday_prompt", [])
	if _is_sunday() and sunday_lines is Array and not (sunday_lines as Array).is_empty():
		prompt = String((sunday_lines as Array)[randi() % (sunday_lines as Array).size()])
	_dialog_label.text = "%s：%s" % [_nearby_npc["name"], prompt]
	_dialog_label.show()
	_dialog_timer.start(6.0)


func _begin_primary_action() -> void:
	if _active_zone.is_empty():
		_enter_nearby_zone()
	else:
		_begin_interaction()


func _hide_dialog() -> void:
	if _dialog_label != null:
		_dialog_label.hide()

## 退出游戏：直接结束程序。标题页那个「退出游戏」按钮也是同一个动作。
func _quit_game() -> void:
	get_tree().quit()

## 记忆便签落盘：心湖记忆墙的唯一数据源。
## 便签原本是「弹一下就没了」的装饰，写进 user:// 之后玩家下次进游戏还能翻到
## 「第 1 月 15 日 · 新员工手册」当时贴了什么 —— 这是 E27 那句质问的情感承重墙。
## 自由周末手账落盘（§7.2 weekend_ledger / §8）。一个周末一条，独立于主线便签：
## 主线便签进记忆墙，周末手账是「我的周末」这个容器（二期手账册读它）。
func _on_weekend_ledger(record: Dictionary) -> void:
	if record.is_empty():
		return
	# B 件发射端（设计说明 §13.4）：把在场一幕的应答上报后端（encounter_choice，
	# 契约叙事流补充枚举）。只报标签与选项，不带任何数值；没演过这一幕就不发。
	var enc_v = record.get("encounter", {})
	var enc: Dictionary = enc_v if enc_v is Dictionary else {}
	var enc_tags: Array = enc.get("tags", []) if enc.get("tags", []) is Array else []
	if not enc.is_empty() and not enc_tags.is_empty():
		var enc_slot_id := String(enc.get("slotId", ""))
		var enc_zone := ""
		var enc_targets: Array = []
		for slot in record.get("slots", []):
			if slot is Dictionary and String(slot.get("slotId", "")) == enc_slot_id:
				enc_zone = String(slot.get("zone", ""))
				var t = slot.get("targets", [])
				enc_targets = t if t is Array else []
				break
		# regionId 与 weekend_close 同规：单字母 A-H，解析不出退回总部 A（400 拒空值）。
		var region := enc_zone.strip_edges().split("_")[0].to_upper() if not enc_zone.is_empty() else ""
		var payload := {
			"regionId": region if (region.length() == 1 and "ABCDEFGH".contains(region)) else "A",
			"activityId": String(enc.get("activityId", "")),
			"optionId": String(enc.get("optionId", "")),
			"memoryTags": enc_tags,
			"month": int(record.get("month", 0)),
		}
		if not enc_targets.is_empty():
			payload["npcId"] = String(enc_targets[0])
		ApiClient.record_event("encounter_choice", payload)
	var line := record.duplicate(true)
	line["worldMinute"] = WorldClock.world_minute
	var file := FileAccess.open("user://workplace_town_weekends.jsonl", FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open("user://workplace_town_weekends.jsonl", FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(JSON.stringify(line))
	file.close()


func _on_memo_recorded(event_id: String, memo: Dictionary) -> void:
	if event_id.is_empty() or memo.is_empty():
		return
	var line := memo.duplicate(true)
	line["eventId"] = event_id
	line["worldMinute"] = WorldClock.world_minute
	var file := FileAccess.open("user://workplace_town_memos.jsonl", FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open("user://workplace_town_memos.jsonl", FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(JSON.stringify(line))
	file.close()

func _on_story_choice_confirmed(event_id: String, choice_id: String, duration_minutes: int) -> void:
	var event_data := WorldClock.next_main_event()
	var region_id := String(event_data.get("locationId", ""))
	ApiClient.record_event("option_click", {
		"regionId": region_id,
		"storyId": event_id,
		"choiceId": _contract_choice_id(event_id, choice_id),
		"hesitationMs": maxi(0, Time.get_ticks_msec() - _decision_opened_msec),
		"switchCount": maxi(0, _choice_hover_count - 1),
		"snapshot": WorldClock.snapshot(),
	}, duration_minutes * 60)


## 主线事件结算 = 时间推进的第二驱动：把时段往前推一拍（早上 → 上班后 → 下班 → 夜晚）。
## 2026-09-17（拍板 #7）：拆掉「花 1 点精力 = 推一个时段」的旧联动 ——
## 精力是月度养成额度，不再承担时间职责。一拍 = advance_phase()，精确落到下个时段起点；
## 事件本身的 duration_minutes 只进埋点（option_click），不再换算成钟面时间。
func _on_story_outcome_acknowledged(event_id: String, choice_id: String, duration_minutes: int) -> void:
	var file := FileAccess.open("user://workplace_town_events.jsonl", FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open("user://workplace_town_events.jsonl", FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(JSON.stringify({"eventId": event_id, "choiceId": choice_id, "durationMinutes": duration_minutes, "worldMinute": WorldClock.world_minute}))
	_story_event_panel.dismiss()
	WorldClock.complete_main_event(event_id)
	WorldClock.advance_phase()
	_story_event = {}
	# 训练谷邀约（Batch 4）：M2-E08 选「接受」→ 直接进对局。邀约本身仍正常结算推进。
	if event_id == "M2-E08" and choice_id == "option_a":
		_open_training_valley()
	if _interior_preview != null and _interior_preview.is_open():
		_interior_preview.enable_exploration()
	# 补一次宵禁检查：23:00 撞上主线事件时，先让玩家把结果看完再送回宿舍。
	_check_curfew(WorldClock.snapshot())

## 训练谷面板：按需实例化一次（同 free_time_panel 惯例）。
## 奖励落账在面板内部走 MonthlyLife.add_money；reward_earned 信号留给对局遥测（暂缓）。
func _open_training_valley() -> void:
	if _training_panel == null:
		_training_panel = TRAINING_PANEL.new()
		_training_panel.setup(_monthly_life)
		add_child(_training_panel)
	if _monthly_life != null:
		_training_panel.open(_monthly_life.month)


func _on_decision_opened(event_id: String) -> void:
	_decision_opened_msec = Time.get_ticks_msec()
	_choice_hover_count = 0
	_last_hovered_choice_id = ""
	ApiClient.record_event("node_enter", {
		"regionId": String(_active_zone.get("code", "")),
		"storyId": event_id,
	})

func _on_choice_hovered(event_id: String, choice_id: String) -> void:
	if choice_id == _last_hovered_choice_id:
		return
	_last_hovered_choice_id = choice_id
	_choice_hover_count += 1
	ApiClient.record_event("option_hover", {
		"regionId": String(_active_zone.get("code", "")),
		"storyId": event_id,
		"choiceId": _contract_choice_id(event_id, choice_id),
		"hoverCount": _choice_hover_count,
	})

## 手册阅读埋点：V5.27 对 E01 的要求是记录「各章阅读时长与跳过行为」。
## 这份数据回答的是"玩家第一天到底想先弄明白什么"——比选项本身更早暴露取向。
func _on_handbook_recorded(event_id: String, records: Dictionary) -> void:
	if records.is_empty():
		return
	var line := {
		"eventId": event_id,
		"totalMs": int(records.get("totalMs", 0)),
		"chapters": records.get("chapters", {}),
		"worldMinute": WorldClock.world_minute,
	}
	var file := FileAccess.open("user://workplace_town_handbook.jsonl", FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open("user://workplace_town_handbook.jsonl", FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(JSON.stringify(line))
		file.close()
	# 契约事件名是 manual_read（openapi PlayerEvent.eventType / constants.TRACKING_EVENTS），
	# 旧名 handbook_read 不在枚举里 → 报告侧永远读不到，等于埋了个寂寞还污染事件流。
	ApiClient.record_event("manual_read", {
		"regionId": String(_active_zone.get("code", "")) if not _active_zone.is_empty() else "B",
		"storyId": event_id,
		"totalMs": line["totalMs"],
		"chapters": line["chapters"],
		"snapshot": WorldClock.snapshot(),
	})

func _on_interior_message_submitted(npc_id: String, message: String) -> void:
	var region_id := String(_active_zone.get("code", "")) if not _active_zone.is_empty() else "A"
	ApiClient.record_npc_chat(npc_id, message, region_id)

func _contract_choice_id(event_id: String, choice_id: String) -> String:
	if choice_id.begins_with("option_"):
		var suffix := choice_id.trim_prefix("option_")
		var index: String = String({"a":"01", "b":"02", "c":"03"}.get(suffix, suffix))
		return "%s-C%s" % [event_id, index]
	return choice_id


## ---------- 精力弹窗开关（2026-09-17 第三批拍板：整模块收进一颗「力」钮） ----------

## 点「力」圆钮 → 打开居中模态弹窗（见 EnergyModalPanel.gd）。
## 停钟照 _open_settings 的模式：开着弹窗时世界时钟停住，关上还原；
## MonthlyLife 的 energy_exhausted 信号不经过这里，照样能触发跳晚 + 横幅。
func _open_energy_modal() -> void:
	if _energy_panel == null or _monthly_life == null:
		return
	_energy_resume_clock = WorldClock.running
	if _energy_resume_clock:
		WorldClock.set_running(false)
	_energy_panel.open()


## 弹窗关闭回调：还原停钟（含花完最后 1 点后的 0.8s 自动关弹窗）。
func _on_energy_modal_closed() -> void:
	if _energy_resume_clock:
		WorldClock.set_running(true)
		_energy_resume_clock = false
