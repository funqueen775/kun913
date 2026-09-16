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
const CHINESE_FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const TOWN_MAP_PATH := "res://assets/town/workplace_town_no_labels.png"
const TOWN_MAP_TEXTURE: Texture2D = preload("res://assets/town/workplace_town_no_labels.png")
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
const CURFEW_HOUR := 23
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
var _zone_status: Label
var _interaction_button: Button
var _zone_button: Button
var _exit_zone_button: Button
var _quit_button: Button
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
var _memory_wall_button: Button
## 开墙前世界时钟是不是在跑。关上要还原，否则玩家会莫名发现时间不走了。
var _wall_resume_clock := false
var _dorm: DormRoom
## 玩家在宿舍里（黑屏盖住地图）：此时人物不能动、地图不能缩放拖动。
var _in_dorm := false
## 已经处理过宵禁的那一天（"月-日"），避免同一天被反复拽回宿舍。
var _curfew_day_key := ""
var _zone_entered_msec := 0
var _decision_opened_msec := 0
var _choice_hover_count := 0
var _last_hovered_choice_id := ""


func _ready() -> void:
	_load_map_data()
	_build_map_backdrop()
	_load_walkability_mask()
	_build_map_collisions()
	_build_player()
	_build_npcs()
	_build_camera()
	_build_hud()
	_build_location_markers()
	_build_debug_overlay()
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
		return
	# 宿舍黑屏期间人物钉住不动（CanvasLayer 盖住画面，动了对不上）。
	if _in_dorm:
		_player.velocity = Vector2.ZERO
		_player_sprite.set_motion(Vector2.ZERO, 0.0)
		return
	# 记忆墙同样盖住地图，人还在走就对不上；键盘不像鼠标，不受 CanvasLayer 拦。
	if _memory_wall != null and _memory_wall.is_open():
		_player.velocity = Vector2.ZERO
		_player_sprite.set_motion(Vector2.ZERO, 0.0)
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

func _process(_delta: float) -> void:
	if get_viewport_rect().size != _last_viewport_size:
		_apply_camera_cover()
	# 任务目标和入口采用低频呼吸动画，手机端无需额外粒子开销。
	var pulse := (sin(Time.get_ticks_msec() * 0.006) + 1.0) * 0.5
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
		# 宿舍黑屏盖在最上面，键盘只认"确认当前那一个选项"。
		if _in_dorm:
			if event.keycode == KEY_ESCAPE or event.keycode == KEY_Q or event.keycode == KEY_E or event.keycode == KEY_SPACE:
				_confirm_dorm_action()
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
	sprite.texture = TOWN_MAP_TEXTURE
	sprite.centered = false
	if sprite.texture != null:
		var source_size := sprite.texture.get_size()
		sprite.scale = Vector2(WORLD_SIZE.x / source_size.x, WORLD_SIZE.y / source_size.y)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = -100
	add_child(sprite)


func _load_map_texture(path: String) -> Texture2D:
	var imported := ResourceLoader.load(path, "Texture2D") as Texture2D
	if imported != null:
		return imported
	if OS.has_feature("web"):
		push_error("小镇贴图资源不存在: %s" % path)
		return null
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
			"route": route_points, "prompt": String(item.get("prompt", ""))
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


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	layer.layer = 100
	add_child(layer)
	_zone_status = Label.new()
	_zone_status.position = Vector2(34, 24)
	_zone_status.add_theme_font_override("font", CHINESE_FONT)
	_zone_status.add_theme_font_size_override("font_size", 24)
	_zone_status.add_theme_color_override("font_color", Color("f8e9be"))
	_zone_status.add_theme_color_override("font_outline_color", Color("18202b"))
	_zone_status.add_theme_constant_override("outline_size", 5)
	_zone_status.text = "职场小镇  ·  走进区域，开启职业情境"
	layer.add_child(_zone_status)
	_coordinate_label = Label.new()
	_coordinate_label.position = Vector2(34, 58)
	_coordinate_label.add_theme_font_override("font", CHINESE_FONT)
	_coordinate_label.add_theme_font_size_override("font_size", 18)
	_coordinate_label.add_theme_color_override("font_color", Color("fff2a8"))
	_coordinate_label.add_theme_color_override("font_outline_color", Color("18202b"))
	_coordinate_label.add_theme_constant_override("outline_size", 4)
	_coordinate_label.text = "地图坐标  x: 0  y: 0"
	_coordinate_label.hide()
	layer.add_child(_coordinate_label)
	_dialog_label = Label.new()
	_dialog_label.position = Vector2(34, 92)
	_dialog_label.size = Vector2(670, 88)
	_dialog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_label.add_theme_font_override("font", CHINESE_FONT)
	_dialog_label.add_theme_font_size_override("font_size", 20)
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
	_exit_zone_button = Button.new()
	_exit_zone_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_exit_zone_button.position = Vector2(-230, 26)
	_exit_zone_button.size = Vector2(190, 62)
	_exit_zone_button.text = "返回小镇  ·  Q"
	_exit_zone_button.add_theme_font_override("font", CHINESE_FONT)
	_exit_zone_button.add_theme_font_size_override("font_size", 19)
	_exit_zone_button.hide()
	_exit_zone_button.pressed.connect(_exit_zone)
	layer.add_child(_exit_zone_button)
	# 退出游戏。放在右上角时间面板**下面**：时间面板占 y 26..203 且层级更高，
	# 跟「返回小镇」按钮一样挤在 y=26 会被整块盖住，落到 215 才露得出来。
	_quit_button = Button.new()
	_quit_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_quit_button.position = Vector2(-230, 215)
	_quit_button.size = Vector2(190, 56)
	_quit_button.text = "退出游戏"
	_quit_button.add_theme_font_override("font", CHINESE_FONT)
	_quit_button.add_theme_font_size_override("font_size", 19)
	_quit_button.pressed.connect(_quit_game)
	layer.add_child(_quit_button)
	# 记忆墙入口：跟「退出游戏」同一列往下排（215 → 287），同样避开右上角时间面板。
	_memory_wall_button = Button.new()
	_memory_wall_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_memory_wall_button.position = Vector2(-230, 287)
	_memory_wall_button.size = Vector2(190, 56)
	_memory_wall_button.text = "记忆墙"
	_memory_wall_button.add_theme_font_override("font", CHINESE_FONT)
	_memory_wall_button.add_theme_font_size_override("font_size", 19)
	_memory_wall_button.pressed.connect(_open_memory_wall)
	layer.add_child(_memory_wall_button)
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
	_active_zone = _nearby_zone
	_nearby_zone = {}
	_zone_entered_msec = Time.get_ticks_msec()
	ApiClient.record_event("region_entered", {"regionId": String(_active_zone.get("code", ""))})
	_zone_button.hide()
	_exit_zone_button.hide()
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
		_interior_preview.set_phase(String(WorldClock.snapshot().get("phaseId", "day")))
	var event_opened := _open_due_event_for_active_zone()
	if not event_opened:
		_interior_preview.enable_exploration()


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
	_exit_zone_button.hide()
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
	_exit_zone_button.hide()
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


func _on_dorm_sleep() -> void:
	_in_dorm = false
	if _dorm != null:
		_dorm.dismiss()
	WorldClock.sleep_until_next_morning(WAKE_UP_HOUR)
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


## 宿舍里只有那一个按钮，键盘（Q / E / 空格 / Esc）点的是同一个。
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
	_time_hud.month_advance_requested.connect(_on_month_advance_requested)
	_on_world_time_changed(WorldClock.snapshot())
	var environment_layer := CanvasLayer.new()
	environment_layer.layer = 40
	add_child(environment_layer)
	_environment_tint = ColorRect.new()
	_environment_tint.color = Color(1, 1, 1, 0)
	_environment_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_environment_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	environment_layer.add_child(_environment_tint)


func _on_world_time_changed(snapshot: Dictionary) -> void:
	if _time_hud != null:
		_time_hud.set_time(snapshot)
	if _interior_preview != null and _interior_preview.is_open():
		_interior_preview.set_phase(String(snapshot.get("phaseId", "day")))
	_check_curfew(snapshot)
	_refresh_objective_hint()
	if _environment_tint == null:
		return
	var tint_by_phase := {
		"dawn": Color(0.93, 0.64, 0.34, 0.14),
		"day": Color(1, 1, 1, 0.0),
		"dusk": Color(0.84, 0.38, 0.18, 0.23),
		"night": Color(0.07, 0.14, 0.35, 0.42),
	}
	_environment_tint.color = tint_by_phase.get(String(snapshot["phaseId"]), Color(1, 1, 1, 0))


func _on_month_advance_requested() -> void:
	WorldClock.advance_month()


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
	if not _active_zone.is_empty() and String(_active_zone.get("code", "")) == String(event.get("locationId", "")):
		_story_event = event.duplicate(true)
		_story_event_panel.present(_story_event)


func _refresh_objective_hint() -> void:
	if _zone_status == null:
		return
	var next_event := WorldClock.next_main_event()
	var snapshot := WorldClock.snapshot()
	if not next_event.is_empty() and _is_event_due(next_event, snapshot):
		_zone_status.text = "主线任务：%s · 前往 %s 区" % [
			String(next_event.get("title", "")),
			String(next_event.get("locationId", "")),
		]
		return
	if next_event.is_empty():
		_zone_status.text = "职场小镇  ·  主线已完成，自由探索职业区域"
		return
	_zone_status.text = "职场小镇  ·  前往黄色入口，进入职业区域"


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
	_dialog_label.text = "%s：%s" % [_nearby_npc["name"], _nearby_npc["prompt"]]
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


## 结果拍看完、玩家点「结束」之后才真正结算。
## 在那之前事件不算完成，时间不推进，玩家也不会被宵禁打断。
func _on_story_outcome_acknowledged(event_id: String, choice_id: String, duration_minutes: int) -> void:
	var file := FileAccess.open("user://workplace_town_events.jsonl", FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open("user://workplace_town_events.jsonl", FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(JSON.stringify({"eventId": event_id, "choiceId": choice_id, "durationMinutes": duration_minutes, "worldMinute": WorldClock.world_minute}))
	_story_event_panel.dismiss()
	WorldClock.complete_main_event(event_id)
	WorldClock.advance_minutes(float(duration_minutes))
	_story_event = {}
	if _interior_preview != null and _interior_preview.is_open():
		_interior_preview.enable_exploration()
	# 补一次宵禁检查：23:00 撞上主线事件时，先让玩家把结果看完再送回宿舍。
	_check_curfew(WorldClock.snapshot())

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
	ApiClient.record_event("handbook_read", {
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
