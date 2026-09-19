class_name DormRoom
extends CanvasLayer

## 宿舍：玩家每天出发、每天结束的地方。
##
## 排版（2026-09-18 二次改造）：底图按 COVER 缩放**铺满整个视口**，无图卡无黑边；
## 右侧信息浮层（眉题/标题/描述/提示条）**整个删掉**——指引靠门口/床边的呼吸光环地贴，
## 交互 = 走到热点上按 E / Enter 弹确认框。
## 玩法层不受影响：站位、掩膜、热点判定全部仍是底图像素坐标。
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
const CARD_BORDER := Color("4a2619")
const PARCHMENT := Color("f6e6c2")
const PARCHMENT_SOFT := Color("e8d3ac")
const ACCENT := Color("9f4c36")
const ACCENT_HOVER := Color("bf6241")
const OUTLINE := Color("23170f")
const GOLD := Color("f0b45a")

## 全屏版式（2026-09-18 晚二改）：主图按 **min** 缩放放进视口，上限
## PHOTO_MAX_SCALE = 1.0（原像素尺寸，最清晰、视角也最小）；
## 四周不够的地方用**同一张图的暗化放大版**垫底 —— 既没有黑边，也不会把房间放到过大。
const PHOTO_MAX_SCALE := 1.0
const BACKDROP_DIM := Color(0.42, 0.4, 0.38)

var _root: Control
var _backdrop: TextureRect
var _photo: TextureRect
var _scrim: ColorRect
var _joystick: Control
var _spot_prompt: Button
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

	_build_backdrop_image()
	_build_room_layer()
	_build_spot_prompt()
	_build_joystick()
	_build_confirm_dialog()

	_root.hide()


func _process(delta: float) -> void:
	if not is_open():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size != _last_viewport_size:
		_sync_room()
	# 站在哪个热点上（空 = 不在任何热点）：每帧重算，确认框开着时冻结，
	# 否则确认框弹出的瞬间人就还没动、判定却可能漂走。
	if not _confirm_open:
		_active_spot_id = _resolve_spot()
	_step_player(delta)
	_update_spot_prompt()


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

## 双层底图：主图按 min 缩放居中（≤ PHOTO_MAX_SCALE，原像素最清晰），
## 背后垫一张**同一张图的暗化 COVER 版**补足四周 —— 没有黑边，主图也不会被放到过大。
## 绘制矩形由 _sync_room() 维护。
func _build_backdrop_image() -> void:
	var texture := _load_texture(DORM_IMAGE_PATH)
	if texture != null:
		_image_size = texture.get_size()

	_backdrop = TextureRect.new()
	_backdrop.name = "DormBackdrop"
	_backdrop.texture = texture
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	_backdrop.modulate = BACKDROP_DIM
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_backdrop)

	_photo = TextureRect.new()
	_photo.name = "DormPhoto"
	_photo.texture = texture
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo.stretch_mode = TextureRect.STRETCH_SCALE
	_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_photo)


## 门口/床边的「靠近才出现」胶囊提示，与 InteriorPreview 的门口提示同一套样式
## （深底金边圆角胶囊，锚在视口底部正中）。点击 = 走到热点上按 E 同一条路（open_confirm）。
func _build_spot_prompt() -> void:
	_spot_prompt = Button.new()
	_spot_prompt.name = "DormSpotPrompt"
	_spot_prompt.text = "离开宿舍 · E"
	_spot_prompt.anchor_left = 0.5
	_spot_prompt.anchor_right = 0.5
	_spot_prompt.anchor_top = 1.0
	_spot_prompt.anchor_bottom = 1.0
	_spot_prompt.offset_left = -130
	_spot_prompt.offset_right = 130
	_spot_prompt.offset_top = -216
	_spot_prompt.offset_bottom = -150
	_spot_prompt.focus_mode = Control.FOCUS_NONE
	_spot_prompt.add_theme_font_override("font", FONT)
	_spot_prompt.add_theme_font_size_override("font_size", 20)
	_spot_prompt.add_theme_color_override("font_color", Color("ffe9b8"))
	_spot_prompt.add_theme_color_override("font_hover_color", Color("fff6d8"))
	_spot_prompt.add_theme_color_override("font_disabled_color", Color("bfa77f"))
	_spot_prompt.add_theme_stylebox_override("normal", _spot_prompt_style(Color("2b1a10", 0.88)))
	_spot_prompt.add_theme_stylebox_override("hover", _spot_prompt_style(Color("472814", 0.94)))
	_spot_prompt.add_theme_stylebox_override("disabled", _spot_prompt_style(Color("241a12", 0.82)))
	_spot_prompt.add_theme_stylebox_override("pressed", _spot_prompt_style(Color("5a3418", 0.94)))
	_spot_prompt.pressed.connect(open_confirm)
	_spot_prompt.hide()
	_root.add_child(_spot_prompt)


func _spot_prompt_style(bg: Color) -> StyleBoxFlat:
	# 与 InteriorPreview._door_prompt_style 完全同款：深底金边的圆角胶囊。
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color("d49a4c")
	style.set_border_width_all(2)
	style.set_corner_radius_all(28)
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


## 底图坐标系容器：玩家、影子都挂在它下面，用底图像素坐标摆位。
## 画序靠**树序**决定，不用 z_index —— z_index 是 CanvasLayer 内全局的，
## 一旦给玩家一个按 y 排的 z，确认框和黑幕就会被玩家盖住。
func _build_room_layer() -> void:
	_room = Node2D.new()
	_room.name = "DormRoomFloor"
	_root.add_child(_room)

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


## 双层底图的绘制矩形：
##   主图 = **min** 缩放（上限 PHOTO_MAX_SCALE）居中放进视口 —— 原像素尺寸、最清晰；
##   背景垫图 = **max** 缩放 COVER 铺满视口，压暗补足四周。
## _room 的原点 = 主图 (0,0) 在屏幕上的落点，所以站位/热点等底图坐标不用跟着版式改。
func _sync_room() -> void:
	if _photo == null or _room == null:
		return
	_last_viewport_size = get_viewport().get_visible_rect().size
	var box_size := _last_viewport_size
	var source := _image_size if _image_size.x > 0.0 else FALLBACK_IMAGE_SIZE
	var photo_factor := minf(minf(box_size.x / source.x, box_size.y / source.y), PHOTO_MAX_SCALE)
	var photo_drawn := source * photo_factor
	var photo_offset := (box_size - photo_drawn) * 0.5
	_image_rect = Rect2(photo_offset, photo_drawn)
	_photo.position = photo_offset
	_photo.size = photo_drawn
	if _backdrop != null:
		var backdrop_factor := maxf(box_size.x / source.x, box_size.y / source.y)
		var backdrop_drawn := source * backdrop_factor
		_backdrop.position = (box_size - backdrop_drawn) * 0.5
		_backdrop.size = backdrop_drawn
	_room.position = photo_offset
	_room.scale = Vector2.ONE * photo_factor


func _refresh() -> void:
	# 宵禁时给画面压一层夜色，让"该睡了"先被看见。
	_photo.modulate = Color(0.72, 0.78, 0.95) if _curfew else Color.WHITE


func _close_confirm() -> void:
	_confirm_open = false
	if _scrim != null:
		_scrim.hide()
	if _confirm_panel != null:
		_confirm_panel.hide()


## 站上门口/床边才出现的胶囊提示（与 InteriorPreview 的门口提示同一套交互）：
## 宵禁时门口的胶囊变灰锁死；确认框打开时收起，别挡确认框。
func _update_spot_prompt() -> void:
	if _spot_prompt == null:
		return
	if _confirm_open:
		_spot_prompt.hide()
		return
	match _active_spot_id:
		"door":
			if _curfew:
				_spot_prompt.text = "%02d:00 了，门已经锁了" % CURFEW_HOUR
				_spot_prompt.disabled = true
			else:
				_spot_prompt.text = "离开宿舍 · E"
				_spot_prompt.disabled = false
			_spot_prompt.show()
		"bed":
			_spot_prompt.text = "上床睡觉 · E"
			_spot_prompt.disabled = false
			_spot_prompt.show()
		_:
			_spot_prompt.hide()


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
