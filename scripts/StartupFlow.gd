extends Control

# 移植队友 web/ 的流程与素材：标题菜单 -> 三页小镇导览 -> Main.tscn。
const FONT := preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")
const TITLE_BG := preload("res://assets/ui/intro/title_bg.png")
const TOWN_ART := preload("res://assets/ui/intro/town_1.png")
const LIFE_ART := preload("res://assets/ui/intro/town_3.png")
const PROFILE_PATH := "user://workplace_town_profile.json"
const PAPER := Color("f6e6bd")
const INK := Color("4a2b1a")
const WOOD := Color("5b321f")
const BRICK := Color("b95035")

const PAGES := [
	{"tab":"小镇介绍", "kicker":"欢迎来到这里", "title":"从第一天入职开始", "body":"八个职场区域围绕湖心展开。你会在路演、协作、培训、员工关怀等不同情境里做出选择，也会慢慢认识在这里工作的人。", "art":TOWN_ART},
	{"tab":"人物名单", "kicker":"你会遇到的人", "title":"同事各有各的工作", "body":"他们不是围着玩家转的角色。每个人都有自己的区域、任务与工作节奏；靠近、交流和共同解决问题，才会慢慢建立联系。", "cast":true},
	{"tab":"开始旅程", "kicker":"怎么走完这一程", "title":"选择会留下记录", "body":"主线事件推进职业旅程，自由活动留给你安排。你的选择、停留和交流会被服务端记录，最终形成一份只属于你的成长报告。", "art":LIFE_ART},
]
const CAST := [
	["艾米", "总部接待", "A 区 · 熊起东方总部", "d8885b"],
	["陈工", "技术协作", "B 区 · 云栖科技丘", "7198b6"],
	["林总", "品牌顾问", "C 区 · 创意水巷", "bc825e"],
	["周岚", "培训导师", "D 区 · 树影书院", "8a786b"],
	["宁宁", "员工关怀", "G 区 · 暖邻康护院", "ba8a9d"],
]

var _mode := "title"
var _page := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rebuild()

func _rebuild() -> void:
	for child in get_children(): child.queue_free()
	_background()
	if _mode == "title": _title_screen()
	else: _intro_screen()

func _background() -> void:
	var bg := TextureRect.new()
	bg.texture = TITLE_BG
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.06, 0.09, 0.12, 0.32 if _mode == "title" else 0.60)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

func _title_screen() -> void:
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top.position = Vector2(-425, 32); top.size = Vector2(382, 50)
	top.add_theme_constant_override("separation", 10)
	add_child(top)
	for text in ["我的报告", "游戏设置", "帮助"]:
		var button := _button(text, false); button.custom_minimum_size = Vector2(120, 50); button.pressed.connect(_placeholder); top.add_child(button)
	var stack := VBoxContainer.new()
	stack.position = Vector2(155, 175); stack.size = Vector2(540, 590)
	stack.add_theme_constant_override("separation", 26); add_child(stack)
	var banner := Panel.new()
	banner.custom_minimum_size = Vector2(540, 162); banner.add_theme_stylebox_override("panel", _style(WOOD, Color("2e1a12"), 5, 4)); stack.add_child(banner)
	var title := _label("职 场 小 镇", 56, Color("ffefc7")); title.position = Vector2(22, 24); title.size = Vector2(496, 76); title.add_theme_color_override("font_outline_color", Color("2e1a12")); title.add_theme_constant_override("outline_size", 6); banner.add_child(title)
	var sub := _label("从第一天入职开始", 20, Color("edcf8e")); sub.position = Vector2(22, 106); sub.size = Vector2(496, 34); banner.add_child(sub)
	var menu := Panel.new()
	menu.custom_minimum_size = Vector2(540, 400); menu.add_theme_stylebox_override("panel", _style(Color("70412b", 0.96), Color("2e1a12"), 5, 5)); stack.add_child(menu)
	var gem := _label("◆", 30, Color("f6c664")); gem.position = Vector2(245, -22); gem.size = Vector2(50, 42); menu.add_child(gem)
	var column := VBoxContainer.new()
	column.position = Vector2(48, 42); column.size = Vector2(444, 310); column.add_theme_constant_override("separation", 14); menu.add_child(column)
	var continue_game := _button("继续游戏"); continue_game.pressed.connect(_start_intro); column.add_child(continue_game)
	var new_game := _button("开始新游戏"); new_game.pressed.connect(_start_intro); column.add_child(new_game)
	var load := _button("加载游戏"); load.pressed.connect(_start_intro); column.add_child(load)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 14); column.add_child(row)
	for text in ["我的报告", "游戏设置"]:
		var button := _button(text, false); button.size_flags_horizontal = Control.SIZE_EXPAND_FILL; button.pressed.connect(_placeholder); row.add_child(button)
	var exit := _button("退出游戏", false); exit.add_theme_color_override("font_color", Color("f1b09d")); exit.pressed.connect(_placeholder); column.add_child(exit)

func _intro_screen() -> void:
	var frame := Panel.new()
	frame.position = Vector2(110, 56); frame.size = Vector2(1700, 968); frame.add_theme_stylebox_override("panel", _style(PAPER, WOOD, 8, 8)); add_child(frame)
	var back := _button("返回", false); back.position = Vector2(36, 34); back.size = Vector2(132, 52); back.pressed.connect(_back); frame.add_child(back)
	var heading := _label("认识职场小镇", 34, INK); heading.position = Vector2(300, 26); heading.size = Vector2(1100, 48); frame.add_child(heading)
	var sub := _label("先了解这里怎么过，再决定怎么开始", 18, Color("7a5533")); sub.position = Vector2(300, 74); sub.size = Vector2(1100, 28); frame.add_child(sub)
	var tabs := HBoxContainer.new(); tabs.position = Vector2(140, 132); tabs.size = Vector2(1400, 56); tabs.add_theme_constant_override("separation", 12); frame.add_child(tabs)
	for index in PAGES.size():
		var tab := Button.new(); tab.text = String(PAGES[index]["tab"]); tab.custom_minimum_size = Vector2(220, 56); tab.add_theme_font_override("font", FONT); tab.add_theme_font_size_override("font_size", 20); tab.add_theme_color_override("font_color", INK if index == _page else Color("7a5533")); tab.add_theme_stylebox_override("normal", _style(Color("e9cf98") if index == _page else Color("f8e9c6"), Color("865139"), 2, 3)); tab.pressed.connect(func(): _go_page(index)); tabs.add_child(tab)
	var page: Dictionary = PAGES[_page]
	if page.get("cast", false): _cast_content(frame, page)
	else: _text_content(frame, page)
	_footer(frame)

func _text_content(frame: Panel, page: Dictionary) -> void:
	var panel := Panel.new(); panel.position = Vector2(94, 224); panel.size = Vector2(1512, 535); panel.add_theme_stylebox_override("panel", _style(Color("fff5db", 0.76), Color("c69458"), 2, 5)); frame.add_child(panel)
	var kicker := _label(String(page["kicker"]), 20, BRICK); kicker.position = Vector2(56, 46); kicker.size = Vector2(600, 34); panel.add_child(kicker)
	var title := _label(String(page["title"]), 39, INK); title.position = Vector2(52, 88); title.size = Vector2(620, 62); panel.add_child(title)
	var body := _label(String(page["body"]), 22, Color("634330")); body.position = Vector2(56, 168); body.size = Vector2(620, 245); body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT; body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; panel.add_child(body)
	var artbox := Panel.new(); artbox.position = Vector2(790, 28); artbox.size = Vector2(660, 478); artbox.add_theme_stylebox_override("panel", _style(WOOD, Color("3a2115"), 5, 4)); panel.add_child(artbox)
	var art := TextureRect.new(); art.texture = page["art"] as Texture2D; art.position = Vector2(12, 12); art.size = Vector2(636, 454); art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; artbox.add_child(art)

func _cast_content(frame: Panel, page: Dictionary) -> void:
	var title := _label(String(page["title"]), 38, INK); title.position = Vector2(110, 226); title.size = Vector2(1460, 52); frame.add_child(title)
	var cards := HBoxContainer.new(); cards.position = Vector2(90, 310); cards.size = Vector2(1520, 360); cards.add_theme_constant_override("separation", 16); frame.add_child(cards)
	for person in CAST:
		var card := Panel.new(); card.custom_minimum_size = Vector2(288, 360); card.size_flags_horizontal = Control.SIZE_EXPAND_FILL; card.add_theme_stylebox_override("panel", _style(Color("fff4d8"), Color("865139"), 3, 5)); cards.add_child(card)
		var portrait := Panel.new(); portrait.position = Vector2(87, 24); portrait.size = Vector2(114, 114); portrait.add_theme_stylebox_override("panel", _style(Color(str(person[3])), WOOD, 4, 57)); card.add_child(portrait)
		var initial := _label(String(person[0]).left(1), 48, PAPER); initial.position = Vector2(16, 18); initial.size = Vector2(82, 76); portrait.add_child(initial)
		var name := _label(String(person[0]), 26, INK); name.position = Vector2(24, 150); name.size = Vector2(240, 36); card.add_child(name)
		var role := _label(String(person[1]), 18, BRICK); role.position = Vector2(24, 191); role.size = Vector2(240, 30); card.add_child(role)
		var place := _label(String(person[2]), 16, Color("7a5533")); place.position = Vector2(22, 239); place.size = Vector2(244, 56); place.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; card.add_child(place)
	var note := _label(String(page["body"]), 19, Color("7a5533")); note.position = Vector2(160, 704); note.size = Vector2(1380, 52); note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; frame.add_child(note)

func _footer(frame: Panel) -> void:
	var counter := _label("第 %d / %d 页" % [_page + 1, PAGES.size()], 18, Color("7a5533")); counter.position = Vector2(102, 825); counter.size = Vector2(180, 42); counter.add_theme_stylebox_override("normal", _style(Color("ead19c"), Color("865139"), 2, 4)); frame.add_child(counter)
	var hint := _label("先认识小镇，再开始上班", 18, Color("7a5533")); hint.position = Vector2(510, 825); hint.size = Vector2(550, 42); frame.add_child(hint)
	var previous := _button("上一页", false); previous.position = Vector2(1110, 817); previous.size = Vector2(135, 56); previous.disabled = _page == 0; previous.pressed.connect(func(): _go_page(_page - 1)); frame.add_child(previous)
	var skip := _button("跳过", false); skip.position = Vector2(1260, 817); skip.size = Vector2(120, 56); skip.pressed.connect(_enter_town); frame.add_child(skip)
	var next := _button("进入小镇" if _page == PAGES.size() - 1 else "继续"); next.position = Vector2(1395, 817); next.size = Vector2(180, 56); next.pressed.connect(_enter_town if _page == PAGES.size() - 1 else func(): _go_page(_page + 1)); frame.add_child(next)

func _start_intro() -> void: _mode = "intro"; _page = 0; _rebuild()
func _back() -> void: _mode = "title"; _rebuild()
func _go_page(index: int) -> void: _page = clampi(index, 0, PAGES.size() - 1); _rebuild()
func _placeholder() -> void: pass

func _enter_town() -> void:
	var file := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"sessionId":"local-" + str(Time.get_unix_time_from_system()), "avatarId":"energetic_ponytail", "contentVersion":"v1", "currentNodeId":"M1-E01", "unlockedRegionIds":["A", "H"]}))
	get_tree().change_scene_to_file("res://Main.tscn")

func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new(); label.text = value; label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; label.add_theme_font_override("font", FONT); label.add_theme_font_size_override("font_size", font_size); label.add_theme_color_override("font_color", color); label.add_theme_color_override("font_outline_color", Color("fff5dd")); label.add_theme_constant_override("outline_size", 2); return label

func _button(value: String, primary := true) -> Button:
	var button := Button.new(); button.text = value; button.custom_minimum_size = Vector2(0, 58); button.add_theme_font_override("font", FONT); button.add_theme_font_size_override("font_size", 21 if primary else 18); button.add_theme_color_override("font_color", Color("fff4d5")); var color := BRICK if primary else Color("865139"); button.add_theme_stylebox_override("normal", _style(color, Color("3a2115"), 3, 3)); button.add_theme_stylebox_override("hover", _style(color.lightened(0.14), Color("3a2115"), 3, 3)); return button

func _style(background: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new(); style.bg_color = background; style.border_color = border; style.set_border_width_all(width); style.set_corner_radius_all(radius); return style
