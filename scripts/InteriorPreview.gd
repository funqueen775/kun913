class_name InteriorPreview
extends CanvasLayer

signal exit_requested
signal player_message_submitted(npc_id: String, message: String)

const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const PAPER_DOLL := preload("res://scripts/PaperDoll64Sprite.gd")
const OFFICE_NPC := preload("res://scripts/OfficeNpcWalker.gd")
const INTERIOR_BOUNDS := Rect2(560, 420, 820, 300)
const PLAYER_SPEED := 260.0
const TALK_DISTANCE := 165.0
# 室内背景已换为完整场景图，角色保持可辨识但不遮挡家具与动线。
const CHARACTER_SCALE := 5.0 / 3.0

var _root: Control
var _title: Label
var _purpose: Label
var _shade: ColorRect
var _player: Node2D
var _player_sprite: PaperDoll64Sprite
var _npc: OfficeNpcWalker
var _npc_name: Label
var _npc_data: Dictionary = {}
var _talk_button: Button
var _dialog: Panel
var _dialog_text: Label
var _message_input: LineEdit
var _send_button: Button
var _touch_vector := Vector2.ZERO
var _exploration_enabled := false

func _ready() -> void:
	layer = 80
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.hide()

func present(location: Dictionary, texture_path: String) -> void:
	for child in _root.get_children():
		child.queue_free()
	_exploration_enabled = false
	_player = null
	_npc = null
	var backdrop := ColorRect.new()
	backdrop.color = Color("10151e")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)
	var room := TextureRect.new()
	room.texture = _load_texture(texture_path)
	room.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	room.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	room.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	room.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(room)
	_shade = ColorRect.new()
	_shade.color = Color(0.04, 0.07, 0.13, 0.08)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_shade)
	var plaque := Panel.new()
	plaque.position = Vector2(44, 34)
	plaque.size = Vector2(540, 68)
	plaque.add_theme_stylebox_override("panel", _panel_style())
	_root.add_child(plaque)
	_title = _label("%s 区 · %s" % [location["code"], location["name"]], 26, Color("fff0c9"))
	_title.position = Vector2(22, 12)
	_title.size = Vector2(496, 40)
	plaque.add_child(_title)
	var exit := Button.new()
	exit.text = "返回小镇  ·  Q"
	exit.position = Vector2(44, 118)
	exit.size = Vector2(210, 54)
	exit.add_theme_font_override("font", FONT)
	exit.add_theme_font_size_override("font_size", 20)
	exit.add_theme_color_override("font_color", Color("fff0c9"))
	exit.add_theme_stylebox_override("normal", _panel_style())
	exit.pressed.connect(exit_requested.emit)
	_root.add_child(exit)
	_build_interior_characters(location)
	_root.show()
	if room.texture == null:
		# Keep the preview usable when an editor import cache is missing.
		var notice := _label("室内素材加载失败：" + texture_path, 18, Color("ffd6b0"))
		notice.position = Vector2(44, 160)
		notice.size = Vector2(900, 40)
		_root.add_child(notice)

func dismiss() -> void:
	_root.hide()

func is_open() -> bool:
	return _root != null and _root.visible

func enable_exploration() -> void:
	if _player == null or _npc == null:
		return
	_exploration_enabled = true
	_player.show()
	_npc.show()
	_npc.process_mode = Node.PROCESS_MODE_INHERIT
	_update_talk_state()

func is_exploration_enabled() -> bool:
	return _exploration_enabled

func set_touch_vector(value: Vector2) -> void:
	_touch_vector = value.limit_length(1.0)

func set_phase(phase_id: String) -> void:
	if _shade == null:
		return
	var tint_by_phase := {
		"dawn": Color(0.30, 0.16, 0.05, 0.18),
		"day": Color(0.04, 0.07, 0.13, 0.08),
		"dusk": Color(0.30, 0.09, 0.04, 0.25),
		"night": Color(0.03, 0.07, 0.22, 0.42),
	}
	_shade.color = tint_by_phase.get(phase_id, tint_by_phase["day"])

func _process(delta: float) -> void:
	if not _exploration_enabled or not is_open() or _player == null:
		return
	if _message_input != null and _message_input.has_focus():
		_player_sprite.set_motion(Vector2.ZERO, 0.0)
		_update_talk_state()
		return
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if _touch_vector.length_squared() > 0.001:
		direction = _touch_vector
	var previous := _player.position
	var target := previous + direction * PLAYER_SPEED * delta
	target.x = clampf(target.x, INTERIOR_BOUNDS.position.x, INTERIOR_BOUNDS.end.x)
	target.y = clampf(target.y, INTERIOR_BOUNDS.position.y, INTERIOR_BOUNDS.end.y)
	_player.position = target
	_player.z_index = int(target.y)
	_player_sprite.set_motion(direction, previous.distance_to(target))
	_update_talk_state()

func _build_interior_characters(location: Dictionary) -> void:
	_player = Node2D.new()
	_player.name = "InteriorPlayer"
	_player.position = Vector2(1060, 500)
	_player.z_index = 900
	_root.add_child(_player)
	var shadow := Polygon2D.new()
	shadow.polygon = PackedVector2Array([Vector2(-24, -4), Vector2(24, -4), Vector2(30, 2), Vector2(18, 8), Vector2(-18, 8), Vector2(-30, 2)])
	shadow.color = Color(0.03, 0.04, 0.05, 0.3)
	_player.add_child(shadow)
	_player_sprite = PAPER_DOLL.new()
	_player_sprite.position = Vector2(-32, -72)
	_player_sprite.scale = Vector2.ONE * CHARACTER_SCALE
	_player_sprite.configure_motion_speed(PLAYER_SPEED)
	_player.add_child(_player_sprite)
	shadow.scale = Vector2.ONE * CHARACTER_SCALE

	# 所有临时室内图统一预留中央活动区；后续替换美术时只需微调这组点。
	var route := PackedVector2Array([Vector2(720, 610), Vector2(900, 610), Vector2(900, 700), Vector2(720, 700)])
	_npc = OFFICE_NPC.new()
	_npc_data = _npc_for_location(location)
	_npc.name = "InteriorNpc"
	_npc.configure(String(_npc_data.get("loadout", "neutral_hoodie")), route, 52.0, 20260914 + String(location.get("code", "A")).unicode_at(0))
	_npc.scale = Vector2.ONE * CHARACTER_SCALE
	_root.add_child(_npc)
	_npc_name = _label("%s · %s" % [_npc_data.get("name", "场景 NPC"), _npc_data.get("role", "区域协作")], 17, Color("fff2c7"))
	_npc_name.position = Vector2(-18, -88)
	_npc_name.size = Vector2(170, 28)
	_npc_name.scale = Vector2.ONE / CHARACTER_SCALE
	_npc_name.add_theme_color_override("font_outline_color", Color("172033"))
	_npc_name.add_theme_constant_override("outline_size", 4)
	_npc.add_child(_npc_name)

	_talk_button = Button.new()
	_talk_button.name = "TalkToInteriorNpc"
	_talk_button.text = "与%s交流" % _npc_data.get("name", "NPC")
	_talk_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_talk_button.position = Vector2(-390, -150)
	_talk_button.size = Vector2(350, 82)
	_talk_button.add_theme_font_override("font", FONT)
	_talk_button.add_theme_font_size_override("font_size", 22)
	_talk_button.add_theme_color_override("font_color", Color("fff4d4"))
	_talk_button.add_theme_stylebox_override("normal", _button_style(Color("9f4c36")))
	_talk_button.add_theme_stylebox_override("hover", _button_style(Color("bf6241")))
	_talk_button.z_index = 1900
	_talk_button.pressed.connect(_talk_to_chen)
	_talk_button.hide()
	_root.add_child(_talk_button)

	_dialog = Panel.new()
	_dialog.name = "InteriorNpcDialog"
	_dialog.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_dialog.offset_left = 330
	_dialog.offset_top = -330
	_dialog.offset_right = -330
	_dialog.offset_bottom = -70
	_dialog.add_theme_stylebox_override("panel", _panel_style())
	_dialog.z_index = 2000
	_dialog.hide()
	_root.add_child(_dialog)
	_dialog_text = _label("%s：欢迎来到%s。有什么想了解的吗？" % [_npc_data.get("name", "NPC"), location.get("name", "这个区域")], 21, Color("fff0c9"))
	_dialog_text.position = Vector2(36, 18)
	_dialog_text.size = Vector2(1188, 92)
	_dialog.add_child(_dialog_text)
	_message_input = LineEdit.new()
	_message_input.name = "PlayerMessageInput"
	_message_input.placeholder_text = "输入你想对%s说的话……" % _npc_data.get("name", "NPC")
	_message_input.position = Vector2(36, 126)
	_message_input.size = Vector2(950, 72)
	_message_input.add_theme_font_override("font", FONT)
	_message_input.add_theme_font_size_override("font_size", 21)
	_message_input.add_theme_color_override("font_color", Color("3a2618"))
	_message_input.add_theme_color_override("font_placeholder_color", Color("8f735c"))
	_message_input.add_theme_stylebox_override("normal", _input_style())
	_message_input.text_submitted.connect(func(_value: String): _send_player_message())
	_dialog.add_child(_message_input)
	_send_button = Button.new()
	_send_button.name = "SendMessageButton"
	_send_button.text = "发送"
	_send_button.position = Vector2(1008, 126)
	_send_button.size = Vector2(180, 72)
	_send_button.add_theme_font_override("font", FONT)
	_send_button.add_theme_font_size_override("font_size", 22)
	_send_button.add_theme_color_override("font_color", Color("fff4d4"))
	_send_button.add_theme_stylebox_override("normal", _button_style(Color("9f4c36")))
	_send_button.add_theme_stylebox_override("hover", _button_style(Color("bf6241")))
	_send_button.pressed.connect(_send_player_message)
	_dialog.add_child(_send_button)
	var close_button := Button.new()
	close_button.name = "CloseDialogButton"
	close_button.text = "关闭"
	close_button.position = Vector2(1080, 18)
	close_button.size = Vector2(108, 52)
	close_button.add_theme_font_override("font", FONT)
	close_button.add_theme_font_size_override("font_size", 18)
	close_button.add_theme_stylebox_override("normal", _button_style(Color("6f4933")))
	close_button.pressed.connect(_close_dialog)
	_dialog.add_child(close_button)

	_player.hide()
	_npc.hide()
	_npc.process_mode = Node.PROCESS_MODE_DISABLED

func _npc_for_location(location: Dictionary) -> Dictionary:
	var code := String(location.get("code", "")).to_lower()
	var catalog := {
		"a": {"npcId":"amy", "name":"艾米", "role":"总部接待", "loadout":"skirt_woman"},
		"b": {"npcId":"chengong", "name":"陈工", "role":"技术协作", "loadout":"neutral_hoodie"},
		"c": {"npcId":"linzong", "name":"林总", "role":"品牌顾问", "loadout":"suit_man"},
		"d": {"npcId":"zhoulan", "name":"周岚", "role":"培训导师", "loadout":"elder_man"},
		"e": {"npcId":"xiaomo", "name":"小莫", "role":"训练教练", "loadout":"street_creator"},
		"f": {"npcId":"azhe", "name":"阿哲", "role":"会展统筹", "loadout":"suit_man"},
		"g": {"npcId":"ningning", "name":"宁宁", "role":"员工关怀", "loadout":"energetic_ponytail"},
		"h": {"npcId":"lele", "name":"乐乐", "role":"生活运营", "loadout":"neutral_hoodie"},
	}
	return catalog.get(code, catalog["b"])

func _update_talk_state() -> void:
	if _talk_button == null or _npc == null or _player == null:
		return
	var nearby := _player.position.distance_to(_npc.position) <= TALK_DISTANCE
	_talk_button.visible = _exploration_enabled and nearby and not _dialog.visible

func _talk_to_chen() -> void:
	if not _exploration_enabled:
		return
	_dialog.show()
	_talk_button.hide()
	_message_input.grab_focus()

func _send_player_message() -> void:
	var message := _message_input.text.strip_edges()
	if message.is_empty():
		return
	player_message_submitted.emit(String(_npc_data.get("npcId", "npc")), message)
	_dialog_text.text = "你：%s\n%s：%s" % [message, _npc_data.get("name", "NPC"), _local_npc_reply(message)]
	_message_input.clear()
	_message_input.grab_focus()

func _local_npc_reply(message: String) -> String:
	# This deterministic placeholder will later be replaced by the model service.
	if message.contains("任务") or message.contains("工作"):
		return "今天先熟悉区域任务和协作流程。遇到不确定的地方及时同步，我们一起确认优先级。"
	if message.contains("问题") or message.contains("不懂") or message.contains("不会"):
		return "没关系，把具体问题说清楚就好。我会先帮你拆解，再决定找谁一起处理。"
	if message.contains("你好") or message.contains("您好"):
		return "你好，欢迎加入团队。之后工作和协作上的问题都可以来找我。"
	return "我听到了。你可以继续说说你的判断和顾虑，我们一起把下一步理清楚。"

func _close_dialog() -> void:
	_message_input.release_focus()
	_dialog.hide()
	_update_talk_state()

func _load_texture(path: String) -> Texture2D:
	var imported := load(path) as Texture2D
	if imported != null:
		return imported
	var image := Image.new()
	var absolute_path := ProjectSettings.globalize_path(path)
	if image.load(absolute_path) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("23170f"))
	label.add_theme_constant_override("outline_size", 3)
	return label

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("54321f", 0.93)
	style.border_color = Color("d49a4c")
	style.set_border_width_all(3)
	style.set_corner_radius_all(3)
	return style

func _button_style(color: Color) -> StyleBoxFlat:
	var style := _panel_style()
	style.bg_color = color
	style.border_color = Color("4a2619")
	return style

func _input_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fff8e8")
	style.border_color = Color("b77b48")
	style.set_border_width_all(3)
	style.set_corner_radius_all(3)
	style.content_margin_left = 18
	style.content_margin_right = 18
	return style
