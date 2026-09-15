extends Node2D


const PAPER_DOLL := preload("res://scripts/PaperDoll64Sprite.gd")
const OFFICE_SET := preload("res://scripts/OfficeSet.gd")
const OFFICE_NPC := preload("res://scripts/OfficeNpcWalker.gd")
const MAP_DEBUG_OVERLAY := preload("res://scripts/MapDebugOverlay.gd")
const TIME_HUD := preload("res://scripts/WorldTimeHud.gd")
const INTERIOR_PREVIEW := preload("res://scripts/InteriorPreview.gd")
const STORY_EVENT_PANEL := preload("res://scripts/StoryEventPanel.gd")
const CHINESE_FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const TOWN_MAP_PATH := "res://assets/town/workplace_town_reference.png"
const WALKABILITY_MASK_PATH := "res://assets/town/walkability_mask.png"
const REGIONS_PATH := "res://data/town/regions.json"
const NPCS_PATH := "res://data/town/npcs.json"
const COLLISION_DATA_PATH := "res://data/town/collision.json"
const NAVIGATION_DATA_PATH := "res://data/town/navigation.json"
const WORLD_SIZE := Vector2(1920, 1080)
const PLAYER_SPEED := 270.0
const COLLISION_LAYER := 1
const INTERACTION_DISTANCE := 230.0
const ENTRANCE_DISTANCE := 58.0
const ZONE_ZOOM := 3.15
const OUTDOOR_EXPLORATION_ZOOM := 1.55
const CAMERA_FOLLOW_SPEED := 5.4
const INTERIOR_ASSETS := {
	"A": "res://assets/generated/interiors/office_placeholder.png",
	"B": "res://assets/generated/b_technology_office.png",
	"C": "res://assets/placeholders/interiors/c_market.png",
	"D": "res://assets/placeholders/interiors/d_library.png",
	"E": "res://assets/placeholders/interiors/e_training.png",
	"F": "res://assets/placeholders/interiors/f_dock.png",
	"G": "res://assets/placeholders/interiors/g_clinic.png",
	"H": "res://assets/placeholders/interiors/h_living.png",
}
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
	{"zone": "a", "name": "陈工", "role": "邻组 Leader", "loadout": "suit_man", "route": PackedVector2Array([Vector2(405, 345), Vector2(510, 345), Vector2(510, 390), Vector2(405, 390)]), "prompt": "结论是什么？预算和工期，一句话说完。"},
	{"zone": "b", "name": "王哥", "role": "技术 · 你的导师", "loadout": "neutral_hoodie", "route": PackedVector2Array([Vector2(850, 325), Vector2(1070, 325), Vector2(1070, 370), Vector2(850, 370)]), "prompt": "方案我看过了，先别急着推。说说你为什么选这条路线。"},
	{"zone": "c", "name": "小林", "role": "产品", "loadout": "energetic_ponytail", "route": PackedVector2Array([Vector2(1435, 335), Vector2(1650, 335), Vector2(1650, 380), Vector2(1435, 380)]), "prompt": "客户那边催得很急，先帮我把需求优先级定下来。"},
	{"zone": "d", "name": "老周", "role": "资深", "loadout": "elder_man", "route": PackedVector2Array([Vector2(1205, 680), Vector2(1285, 680), Vector2(1285, 800), Vector2(1205, 800)]), "prompt": "复盘会上有不同说法。你觉得该由谁来牵头？"},
	{"zone": "h", "name": "小赵", "role": "实习生", "loadout": "street_creator", "route": PackedVector2Array([Vector2(365, 380), Vector2(405, 380), Vector2(405, 490), Vector2(365, 490)]), "prompt": "师兄，这个我搞不太定……能帮我看一眼吗？"},
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
var _dialog_label: Label
var _dialog_timer: Timer
var _last_walkable_position := Vector2.ZERO
var _debug_overlay
var _collision_debug_polygons: Array = []
var _coordinate_label: Label
var _walkability_image: Image
var _walkability_debug_sprite: Sprite2D
var _location_markers: Array[Label] = []
var _entrance_markers: Array[Polygon2D] = []
var _highlighted_zone_id := ""
var _time_hud: WorldTimeHud
var _interior_preview: InteriorPreview
var _environment_tint: ColorRect
var _story_event_panel: StoryEventPanel
var _story_event: Dictionary = {}
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


func _physics_process(delta: float) -> void:
	if _player == null or _player_sprite == null:
		return
	if _interior_preview != null and _interior_preview.is_open():
		_interior_preview.set_touch_vector(_touch_vector)
		return
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
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

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
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


func _build_player() -> void:
	_player = CharacterBody2D.new()
	_player.name = "Player"
	_player.position = Vector2(945, 810)
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
	_camera.zoom = Vector2(_cover_zoom, _cover_zoom)


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
		var marker := Label.new()
		marker.text = "%s  %s" % [zone["code"], zone["name"]]
		marker.position = (zone["rect"] as Rect2).get_center() + Vector2(-48, -72)
		marker.add_theme_font_override("font", CHINESE_FONT)
		marker.add_theme_font_size_override("font_size", 18)
		marker.add_theme_color_override("font_color", Color("fff4ce"))
		marker.add_theme_color_override("font_outline_color", Color("29221c"))
		marker.add_theme_constant_override("outline_size", 5)
		marker.z_index = 45
		# 地点名称已经绘制在底图中，运行时不再叠加文字，避免重复。
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
	_zone_status.text = "职场小镇  ·  前往黄色入口，进入职业区域"
	for marker in _location_markers:
		marker.hide()
	for npc in _npc_instances:
		(npc["character"] as Node2D).show()
		(npc["name_tag"] as Label).hide()
	_hide_dialog()


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
	var target_position := _player.position
	var target_zoom := Vector2.ONE * OUTDOOR_EXPLORATION_ZOOM * _cover_zoom
	if not _active_zone.is_empty():
		target_position = _active_zone["center"]
		target_zoom = Vector2.ONE * ZONE_ZOOM * _cover_zoom
	_camera.position = _camera.position.lerp(target_position, minf(delta * CAMERA_FOLLOW_SPEED, 1.0))
	_camera.zoom = _camera.zoom.lerp(target_zoom, minf(delta * 4.2, 1.0))


func _build_world_time() -> void:
	_time_hud = TIME_HUD.new()
	add_child(_time_hud)
	WorldClock.time_changed.connect(_on_world_time_changed)
	WorldClock.main_event_reached.connect(_on_main_event_reached)
	_time_hud.advance_requested.connect(_on_time_advance_requested)
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
	if _environment_tint == null:
		return
	var tint_by_phase := {
		"dawn": Color(0.93, 0.64, 0.34, 0.14),
		"day": Color(1, 1, 1, 0.0),
		"dusk": Color(0.84, 0.38, 0.18, 0.23),
		"night": Color(0.07, 0.14, 0.35, 0.42),
	}
	_environment_tint.color = tint_by_phase.get(String(snapshot["phaseId"]), Color(1, 1, 1, 0))


func _on_time_advance_requested(days: int) -> void:
	WorldClock.advance_days(days)


func _on_main_event_reached(event: Dictionary) -> void:
	_highlighted_zone_id = String(event.get("locationId", ""))
	ApiClient.record_event("event_trigger", {
		"regionId": String(event.get("locationId", "")),
		"storyId": String(event.get("id", "")),
		"snapshot": WorldClock.snapshot(),
	})
	if _time_hud != null:
		_time_hud.show_event_gate(event)
	if _zone_status != null:
		_zone_status.text = "主线事件已到达：%s · 前往 %s 区" % [event["title"], event["locationId"]]
	if not _active_zone.is_empty() and String(_active_zone.get("code", "")) == String(event.get("locationId", "")):
		_story_event = event.duplicate(true)
		_story_event_panel.present(_story_event)


func _build_interior_preview() -> void:
	_interior_preview = INTERIOR_PREVIEW.new()
	_interior_preview.exit_requested.connect(_exit_zone)
	_interior_preview.player_message_submitted.connect(_on_interior_message_submitted)
	add_child(_interior_preview)

func _build_story_event_panel() -> void:
	_story_event_panel = STORY_EVENT_PANEL.new()
	_story_event_panel.choice_confirmed.connect(_on_story_choice_confirmed)
	_story_event_panel.decision_opened.connect(_on_decision_opened)
	_story_event_panel.choice_hovered.connect(_on_choice_hovered)
	add_child(_story_event_panel)

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

func _on_interior_message_submitted(npc_id: String, message: String) -> void:
	var region_id := String(_active_zone.get("code", "")) if not _active_zone.is_empty() else "A"
	ApiClient.record_npc_chat(npc_id, message, region_id)

func _contract_choice_id(event_id: String, choice_id: String) -> String:
	if choice_id.begins_with("option_"):
		var suffix := choice_id.trim_prefix("option_")
		var index: String = String({"a":"01", "b":"02", "c":"03"}.get(suffix, suffix))
		return "%s-C%s" % [event_id, index]
	return choice_id
