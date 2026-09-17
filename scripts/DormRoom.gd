class_name DormRoom
extends CanvasLayer

## 宿舍：玩家每天出发、每天结束的地方。
##
## 排版：左侧「慢生活园」美术图卡片（完整不裁切），右侧信息栏
## （眉题 / 标题 / 分隔线 / 描述 / 行动提示条），暖色羊皮纸系配色。
## 家园装饰系统整体后置（见 docs/家园系统设计说明_V1.md），
## 届时本屏是"宿舍场景 + 陈列层"的底座。
##
## 2026-09-16 改造：这张图不再只是"插画 + 一个按钮"，玩家可以**自己走**。
##   · 白天 —— 从大厅出发，走到蓝色双开门前，弹出「要离开宿舍吗」确认框，点了才出门；
##   · 23:00 后 —— 人被送回宿舍门口，走回自己卧室门口，床边弹「上床睡觉」确认框。
##
## 能不能站由 `assets/town/dorm_walkable_mask.png` 决定（由
## `tools/build_dorm_walkability_mask.py` 从底图的地板色算出来，白=可站）。
## 角色与站位一律用**底图像素坐标**（1448×1086），换算交给 `_room` 这一层缩放节点。

signal leave_requested
signal sleep_requested

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const PAPER_DOLL := preload("res://scripts/PaperDoll64Sprite.gd")

## 美术交付宿舍图后填这里（留空 = 纯黑屏）。
## 2026-09-16：接「慢生活园」整图当宿舍背景。家园装饰系统后置，
## 届时玩家房间需美术出空房版再分层（设计说明 §3）。
const DORM_IMAGE_PATH := "res://assets/town/dorm_slow_life.jpg"
const WALKABLE_MASK_PATH := "res://assets/town/dorm_walkable_mask.png"
## 掩膜是底图的 1/2 尺寸，采样前先把底图坐标缩到掩膜坐标。
const MASK_SCALE := 0.5
## 图片加载失败时的兜底尺寸（正常从贴图读，不依赖这个值）。
const FALLBACK_IMAGE_SIZE := Vector2(1448, 1086)

const CURFEW_HOUR := 23
const WAKE_UP_HOUR := 7

## 走动速度（底图像素/秒）：横穿大厅大约 0.8 秒，出门这一步不磨人。
const MOVE_SPEED := 320.0
## 纸娃娃在底图坐标系里的缩放。64×80 的画面缩到 ≈109×136 ——
## 和底图里的门、床、书架量出来的比例对得上（1 米 ≈ 80 底图像素）。
const CHARACTER_SCALE := 1.7

## 站位（底图像素坐标，都经过掩膜核验：可站、且互相连通）
const SPAWN_DAY := Vector2(700, 438)
const SPAWN_CURFEW := Vector2(700, 646)
## 蓝色双开门前的落脚点
const DOOR_SPOT := Vector2(700, 620)
const DOOR_RADIUS := 74.0
## 玩家卧室门口（两排书架之间那道缝）
const BED_SPOT := Vector2(742, 322)
const BED_RADIUS := 92.0

## 配色（与记忆墙/手册同一羊皮纸系）
const INK_BG := Color("0b0812")
const CARD_BG := Color("14100c")
const CARD_BORDER := Color("4a2619")
const PARCHMENT := Color("f6e6c2")
const PARCHMENT_SOFT := Color("e8d3ac")
const KICKER := Color("c9a97a")
const ACCENT := Color("9f4c36")
const ACCENT_HOVER := Color("bf6241")
const OUTLINE := Color("23170f")
const GOLD := Color("f0b45a")
const NIGHT_BLUE := Color("8fb8e8")

## 左侧图卡与右侧信息栏的版面基准（1920×1080）
const CARD_RECT := Rect2(100, 70, 960, 940)
const CARD_PAD := 18.0
const COL_X := 1160.0
const COL_W := 660.0

var _root: Control
var _photo: TextureRect
var _kicker: Label
var _title: Label
var _desc: Label
var _hint: Label
var _prompt: Button
var _scrim: ColorRect
var _joystick: Control
var _confirm_panel: Panel
var _confirm_title: Label
var _confirm_desc: Label
var _confirm_yes: Button
var _confirm_no: Button

## 图片实际绘制矩形（贴图按 KEEP_ASPECT_CENTERED 缩放后落在卡片中间）
var _image_rect := Rect2()
var _image_size := FALLBACK_IMAGE_SIZE
## 底图坐标系容器：position/scale 由 `_sync_room()` 维护
var _room: Node2D
var _player: Node2D
var _player_sprite: PaperDoll64Sprite
var _marker: Node2D
## 可站掩膜（Image）。加载不到就退化成"整张图都能站"，至少不卡死玩家。
var _mask: Image

var _curfew := false
## 键盘来的输入（小镇每帧转发）与触屏摇杆来的输入分开存，摇杆优先。
var _key_input := Vector2.ZERO
var _stick_input := Vector2.ZERO
var _stick_active := false
var _active_spot_id := ""
var _confirm_open := false
var _last_viewport_size := Vector2.ZERO


func _ready() -> void:
	layer = 110
	name = "DormRoom"
	_mask = _load_mask()
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.color = INK_BG
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)

	_build_photo_card()
	_build_text_column()
	_build_room_layer()
	_build_joystick()
	_build_confirm_dialog()

	_root.hide()


func _process(delta: float) -> void:
	if not is_open():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size != _last_viewport_size:
		_sync_room()
	_step_player(delta)
	_refresh_marker()


## ---------------------------------------------------------------------------
## 对外接口（WorkplaceTown 调用）
## ---------------------------------------------------------------------------

func present(curfew: bool) -> void:
	_curfew = curfew
	_refresh()
	_close_confirm()
	_teleport(SPAWN_CURFEW if _curfew else SPAWN_DAY)
	_active_spot_id = ""
	_key_input = Vector2.ZERO
	_stick_input = Vector2.ZERO
	_stick_active = false
	_root.show()
	_sync_room()
	_refresh_prompt()
	if _joystick != null:
		_joystick.queue_redraw()


func dismiss() -> void:
	_root.hide()
	_close_confirm()


func is_open() -> bool:
	return _root != null and _root.visible


func is_curfew() -> bool:
	return _curfew


## 玩家本帧的移动输入（归一化）。宿舍里人也归玩家控制，只是换了块画布。
func set_move_input(direction: Vector2) -> void:
	if _confirm_open:
		_key_input = Vector2.ZERO
		return
	_key_input = direction.limit_length(1.0)


func _effective_input() -> Vector2:
	if _confirm_open:
		return Vector2.ZERO
	# 触屏摇杆优先：小镇那份摇杆被宿舍黑幕盖住收不到事件，这里自带一个。
	if _stick_input != Vector2.ZERO:
		return _stick_input
	return _key_input


## 键盘确认键统一从这里进（WorkplaceTown._unhandled_input 转发）。
## E/空格 = 在热点上打开确认框；确认框里 Enter = 确认、Esc = 再等等。
func handle_key(keycode: int) -> void:
	if not is_open():
		return
	if _confirm_open:
		if keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
			confirm_yes()
		elif keycode == KEY_ESCAPE:
			confirm_cancel()
		return
	if keycode == KEY_E or keycode == KEY_SPACE:
		if not _active_spot_id.is_empty():
			open_confirm()


## ---------------------------------------------------------------------------
## 玩法
## ---------------------------------------------------------------------------

func _step_player(delta: float) -> void:
	if _player == null:
		return
	var direction := _effective_input()
	if direction == Vector2.ZERO:
		_player_sprite.set_motion(Vector2.ZERO, 0.0)
		_refresh_prompt()
		return
	var from := _player.position
	var step := direction * MOVE_SPEED * delta
	# 贴墙滑行：整体不让走时，分别试单轴，避免被家具角卡死。
	var target := from
	if _can_stand(from + step):
		target = from + step
	elif _can_stand(Vector2(from.x + step.x, from.y)):
		target = Vector2(from.x + step.x, from.y)
	elif _can_stand(Vector2(from.x, from.y + step.y)):
		target = Vector2(from.x, from.y + step.y)
	_player.position = target
	# 距离按精灵自己的局部尺度给（角色挂在 CHARACTER_SCALE 缩放的锚点下），步频才和镇里一致。
	_player_sprite.set_motion(direction, from.distance_to(target) * CHARACTER_SCALE)
	_refresh_prompt()


func _can_stand(image_position: Vector2) -> bool:
	if image_position.x < 0.0 or image_position.y < 0.0:
		return false
	if image_position.x >= _image_size.x or image_position.y >= _image_size.y:
		return false
	if _mask == null:
		return true
	var x := clampi(int(image_position.x * MASK_SCALE), 0, _mask.get_width() - 1)
	var y := clampi(int(image_position.y * MASK_SCALE), 0, _mask.get_height() - 1)
	return _mask.get_pixel(x, y).r > 0.5


func _teleport(image_position: Vector2) -> void:
	if _player == null:
		return
	_player.position = image_position


## 当前站在哪个热点上（空 = 不在任何热点）。门口的判定半径比床边小，
## 免得站在大厅中间就弹出"要出门了吗"。
func _resolve_spot() -> String:
	if _player == null:
		return ""
	var distance_door := _player.position.distance_to(DOOR_SPOT)
	var distance_bed := _player.position.distance_to(BED_SPOT)
	# 2026-09-17 第三批修复：床边热点不再只认宵禁 —— 旧代码只有 curfew 分支会返回
	# "bed"，非宵禁自己回宿舍（22:00 按精力横幅提示回来的）/ 开局在宿舍里的玩家
	# 走到床边也弹不出「上床睡觉」，只能干等 23:00 宵禁强制送回。
	if distance_bed <= BED_RADIUS:
		return "bed"
	if distance_door <= DOOR_RADIUS:
		return "door"
	return ""


func open_confirm() -> void:
	if _confirm_open or _active_spot_id.is_empty():
		return
	_confirm_open = true
	_key_input = Vector2.ZERO
	_stick_input = Vector2.ZERO
	var leaving := _active_spot_id == "door" and not _curfew
	if leaving:
		_confirm_title.text = "现在出门？"
		_confirm_desc.text = "走出这扇门，今天就算开始了。\n晚 %02d:00 之前记得回来。" % CURFEW_HOUR
		_confirm_yes.text = "离开宿舍  ·  Enter"
	else:
		_confirm_title.text = "上床睡觉？"
		_confirm_desc.text = "一觉睡到明早 %02d:00，体力回满。\n今天没做完的事就留在今天了。" % WAKE_UP_HOUR
		_confirm_yes.text = "这就睡  ·  Enter"
	_confirm_no.text = "再待一会儿  ·  Esc"
	_scrim.show()
	_confirm_panel.show()
	_confirm_yes.grab_focus()


func confirm_yes() -> void:
	if not _confirm_open:
		return
	var leaving := _active_spot_id == "door" and not _curfew
	_close_confirm()
	if leaving:
		leave_requested.emit()
	else:
		sleep_requested.emit()


func confirm_cancel() -> void:
	_close_confirm()


func is_confirm_open() -> bool:
	return _confirm_open


func active_spot_id() -> String:
	return _active_spot_id


func player_image_position() -> Vector2:
	return _player.position if _player != null else Vector2.ZERO


## 仅供自检：把玩家直接放到某个底图坐标。
func set_player_image_position(image_position: Vector2) -> void:
	_teleport(image_position)


func is_walkable_image_position(image_position: Vector2) -> bool:
	return _can_stand(image_position)


## ---------------------------------------------------------------------------
## 场景搭建
## ---------------------------------------------------------------------------

## 左侧：圆角卡片包住整张宿舍图（KEEP_ASPECT_CENTERED，不再裁上下）。
func _build_photo_card() -> void:
	var card := Panel.new()
	card.position = CARD_RECT.position
	card.size = CARD_RECT.size
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = CARD_BG
	card_style.border_color = CARD_BORDER
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(10)
	card_style.shadow_color = Color(0, 0, 0, 0.45)
	card_style.shadow_size = 22
	card_style.shadow_offset = Vector2(0, 6)
	card.add_theme_stylebox_override("panel", card_style)
	_root.add_child(card)

	_photo = TextureRect.new()
	_photo.name = "DormPhoto"
	_photo.texture = _load_texture(DORM_IMAGE_PATH)
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_photo.position = Vector2(CARD_PAD, CARD_PAD)
	_photo.size = CARD_RECT.size - Vector2(CARD_PAD, CARD_PAD) * 2.0
	_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(_photo)
	if _photo.texture != null:
		_image_size = _photo.texture.get_size()


## 右侧：眉题 → 标题 → 分隔线 → 描述 → 行动提示条 → 操作小字。
func _build_text_column() -> void:
	_kicker = _label("H 区 · 员工宿舍", 20, KICKER, 0)
	_kicker.position = Vector2(COL_X, 296)
	_kicker.size = Vector2(COL_W, 34)
	_root.add_child(_kicker)

	_title = _label("慢生活园", 56, PARCHMENT, 5)
	_title.position = Vector2(COL_X, 338)
	_title.size = Vector2(COL_W, 84)
	_root.add_child(_title)

	var divider := ColorRect.new()
	divider.color = ACCENT
	divider.position = Vector2(COL_X + 2, 444)
	divider.size = Vector2(140, 3)
	_root.add_child(divider)

	_desc = _label("", 22, PARCHMENT_SOFT, 2)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(COL_W - 20, 0)
	_desc.size = Vector2(COL_W - 20, 150)
	_desc.position = Vector2(COL_X, 486)
	_root.add_child(_desc)

	_prompt = Button.new()
	_prompt.name = "DormPrompt"
	_prompt.position = Vector2(COL_X, 664)
	_prompt.size = Vector2(460, 96)
	_prompt.add_theme_font_override("font", FONT)
	_prompt.add_theme_font_size_override("font_size", 25)
	_prompt.add_theme_color_override("font_color", Color("fff4d4"))
	_prompt.add_theme_color_override("font_hover_color", Color("fff8e0"))
	_prompt.add_theme_color_override("font_disabled_color", Color("d8c6a2"))
	_prompt.add_theme_stylebox_override("normal", _button_style(ACCENT))
	_prompt.add_theme_stylebox_override("hover", _button_style(ACCENT_HOVER))
	_prompt.add_theme_stylebox_override("pressed", _button_style(Color("7e3c2a")))
	_prompt.add_theme_stylebox_override("disabled", _button_style(Color("3a2a20")))
	_prompt.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_prompt.pressed.connect(_on_prompt_pressed)
	_root.add_child(_prompt)

	_hint = _label("W / A / S / D 或 方向键 走动 · E 交互", 18, KICKER, 0)
	_hint.position = Vector2(COL_X, 780)
	_hint.size = Vector2(COL_W, 30)
	_root.add_child(_hint)


## 底图坐标系容器：玩家、影子、目标地贴都挂在它下面，用底图像素坐标摆位。
## 画序靠**树序**决定，不用 z_index —— z_index 是 CanvasLayer 内全局的，
## 一旦给玩家一个按 y 排的 z，确认框和黑幕就会被玩家盖住。地贴先加、玩家后加即可。
func _build_room_layer() -> void:
	_room = Node2D.new()
	_room.name = "DormRoomFloor"
	_root.add_child(_room)

	_marker = Node2D.new()
	_marker.name = "DormSpotMarker"
	_marker.draw.connect(_draw_marker)
	_room.add_child(_marker)

	_player = Node2D.new()
	_player.name = "DormPlayer"
	_room.add_child(_player)
	var shadow := Polygon2D.new()
	shadow.polygon = PackedVector2Array([
		Vector2(-15, -2), Vector2(15, -2), Vector2(19, 2),
		Vector2(11, 5), Vector2(-11, 5), Vector2(-19, 2),
	])
	shadow.color = Color(0.04, 0.06, 0.08, 0.30)
	shadow.scale = Vector2.ONE * CHARACTER_SCALE
	_player.add_child(shadow)
	var anchor := Node2D.new()
	anchor.scale = Vector2.ONE * CHARACTER_SCALE
	_player.add_child(anchor)
	_player_sprite = PAPER_DOLL.new()
	# 与小镇上的玩家同一套造型，出门前后是同一个人。
	_player_sprite.position = Vector2(-32, -72)
	_player_sprite.configure_motion_speed(MOVE_SPEED * CHARACTER_SCALE)
	anchor.add_child(_player_sprite)
	_player_sprite.set_loadout("bear_green_cardigan")


func _build_confirm_dialog() -> void:
	_scrim = ColorRect.new()
	_scrim.name = "DormConfirmScrim"
	_scrim.color = Color(0.02, 0.02, 0.04, 0.62)
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.hide()
	_root.add_child(_scrim)

	_confirm_panel = Panel.new()
	_confirm_panel.name = "DormConfirm"
	_confirm_panel.position = Vector2(650, 386)
	_confirm_panel.size = Vector2(620, 308)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("1b1510")
	panel_style.border_color = GOLD
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(8)
	panel_style.shadow_color = Color(0, 0, 0, 0.55)
	panel_style.shadow_size = 26
	_confirm_panel.add_theme_stylebox_override("panel", panel_style)
	_confirm_panel.hide()
	_root.add_child(_confirm_panel)

	_confirm_title = _label("", 32, PARCHMENT, 3)
	_confirm_title.position = Vector2(40, 30)
	_confirm_title.size = Vector2(540, 48)
	_confirm_panel.add_child(_confirm_title)

	_confirm_desc = _label("", 20, PARCHMENT_SOFT, 0)
	_confirm_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_desc.custom_minimum_size = Vector2(540, 0)
	_confirm_desc.size = Vector2(540, 84)
	_confirm_desc.position = Vector2(40, 88)
	_confirm_panel.add_child(_confirm_desc)

	_confirm_yes = _make_confirm_button("", ACCENT, ACCENT_HOVER)
	_confirm_yes.name = "DormConfirmYes"
	_confirm_yes.position = Vector2(40, 196)
	_confirm_yes.size = Vector2(268, 76)
	_confirm_yes.pressed.connect(confirm_yes)
	_confirm_panel.add_child(_confirm_yes)

	_confirm_no = _make_confirm_button("", Color("4a3a2c"), Color("63503f"))
	_confirm_no.name = "DormConfirmNo"
	_confirm_no.position = Vector2(326, 196)
	_confirm_no.size = Vector2(254, 76)
	_confirm_no.pressed.connect(confirm_cancel)
	_confirm_panel.add_child(_confirm_no)


func _make_confirm_button(text: String, normal: Color, hover: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color("fff4d4"))
	button.add_theme_color_override("font_hover_color", Color("fff8e0"))
	button.add_theme_stylebox_override("normal", _button_style(normal))
	button.add_theme_stylebox_override("hover", _button_style(hover))
	button.add_theme_stylebox_override("pressed", _button_style(Color("7e3c2a")))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button


## 图片在屏幕上的实际绘制矩形（= 卡片位置 + 内边距 + 等比缩放后的居中偏移）。
func _sync_room() -> void:
	if _photo == null or _room == null:
		return
	_last_viewport_size = get_viewport().get_visible_rect().size
	var box_position := CARD_RECT.position + _photo.position
	var box_size := _photo.size
	var source := _image_size if _image_size.x > 0.0 else FALLBACK_IMAGE_SIZE
	var factor := minf(box_size.x / source.x, box_size.y / source.y)
	var drawn := source * factor
	_image_rect = Rect2(box_position + (box_size - drawn) * 0.5, drawn)
	_room.position = _image_rect.position
	_room.scale = Vector2.ONE * (drawn.x / source.x)


func _refresh() -> void:
	# 宵禁时给画面压一层夜色，让"该睡了"先被看见再被读到。
	_photo.modulate = Color(0.72, 0.78, 0.95) if _curfew else Color.WHITE
	if _curfew:
		_kicker.text = "%02d:00 · 宵禁" % CURFEW_HOUR
		_title.text = "该回宿舍了"
		_desc.text = "宿舍 %02d:00 关门，再晚就只能睡走廊了。\n今天到此为止，走到床边睡一觉，明早 %02d:00 再出门。" % [CURFEW_HOUR, WAKE_UP_HOUR]
	else:
		_kicker.text = "H 区 · 员工宿舍"
		_title.text = "慢生活园"
		_desc.text = "你在这里开始一天，也在这里结束一天。\n记住：晚上 %02d:00 之前必须回到宿舍。" % CURFEW_HOUR


## 提示条随"站在哪"变：不在热点上时是灰的指路，站上去了才亮成可点。
func _refresh_prompt() -> void:
	if _prompt == null:
		return
	_active_spot_id = _resolve_spot()
	match _active_spot_id:
		"door":
			if _curfew:
				_prompt.text = "%02d:00 了，门已经锁了" % CURFEW_HOUR
				_prompt.disabled = true
			else:
				_prompt.text = "离开宿舍  ·  E"
				_prompt.disabled = false
		"bed":
			_prompt.text = "上床睡觉  ·  E"
			_prompt.disabled = false
		_:
			_prompt.disabled = true
			if _curfew:
				_prompt.text = "走回床边就能睡（WASD 走动）"
			elif _player != null and _player.position.y < 520.0:
				_prompt.text = "往下走，到蓝色双开门前"
			else:
				_prompt.text = "走近门口的蓝色双开门"


func _on_prompt_pressed() -> void:
	open_confirm()


func _close_confirm() -> void:
	_confirm_open = false
	if _scrim != null:
		_scrim.hide()
	if _confirm_panel != null:
		_confirm_panel.hide()
	_refresh_prompt()


## 目标地贴：呼吸光环 + 中心圆点。门口暖金、床边冷蓝。
func _refresh_marker() -> void:
	if _marker == null:
		return
	var target := BED_SPOT if _curfew else DOOR_SPOT
	_marker.position = target
	_marker.queue_redraw()


func _draw_marker() -> void:
	if _marker == null:
		return
	var pulse := (sin(Time.get_ticks_msec() * 0.004) + 1.0) * 0.5
	var color := NIGHT_BLUE if _curfew else GOLD
	var radius := BED_RADIUS if _curfew else DOOR_RADIUS
	_marker.draw_circle(Vector2.ZERO, radius * 0.62, Color(color, 0.10 + pulse * 0.07))
	_marker.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(color, 0.55 + pulse * 0.35), 5.0)
	_marker.draw_arc(Vector2.ZERO, radius * (0.74 + pulse * 0.10), 0.0, TAU, 48, Color(color, 0.28), 3.0)


## 触屏摇杆：小镇那份在 CanvasLayer 40 上、被宿舍的黑幕盖住收不到事件，
## 所以宿舍屏自带一个，样式与小镇完全一致（玩家不该察觉换了一套操作）。
func _build_joystick() -> void:
	_joystick = Control.new()
	_joystick.name = "DormJoystick"
	_joystick.position = Vector2(44, 875)
	_joystick.size = Vector2(150, 150)
	_joystick.mouse_filter = Control.MOUSE_FILTER_STOP
	var joystick := _joystick
	joystick.draw.connect(func():
		joystick.draw_circle(Vector2(75, 75), 65, Color(0.11, 0.16, 0.21, 0.40))
		joystick.draw_arc(Vector2(75, 75), 65, 0, TAU, 40, Color(1, 1, 1, 0.58), 3)
		joystick.draw_circle(Vector2(75, 75) + _stick_input * 38, 25, Color(1, 1, 1, 0.78))
	)
	joystick.gui_input.connect(func(event):
		if event is InputEventScreenTouch or event is InputEventMouseButton:
			_stick_active = event.pressed
			if not _stick_active:
				_stick_input = Vector2.ZERO
		if event is InputEventScreenDrag or event is InputEventMouseMotion:
			if _stick_active and not _confirm_open:
				_stick_input = (joystick.get_local_mouse_position() - Vector2(75, 75)).limit_length(55) / 55.0
		joystick.queue_redraw()
	)
	_root.add_child(joystick)


func _load_mask() -> Image:
	var imported := load(WALKABLE_MASK_PATH) as Texture2D
	if imported != null:
		var from_texture := imported.get_image()
		if from_texture != null:
			return from_texture
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(WALKABLE_MASK_PATH)) == OK:
		return image
	push_warning("宿舍可站掩膜加载失败，将退化成整张图都能走：" + WALKABLE_MASK_PATH)
	return null


func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var imported := load(path) as Texture2D
	if imported != null:
		return imported
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK:
		return null
	return ImageTexture.create_from_image(image)


func _label(value: String, font_size: int, color: Color, outline: int) -> Label:
	var label := Label.new()
	label.text = value
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", outline)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = CARD_BORDER
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	return style
