class_name GameBase
extends Control
## 各ゲーム共通の土台。背景・タイトル・メッセージ・結果表示と、
## 山札から配る／カードが飛ぶ／花吹雪といった演出を持つ。
## ゲームが終わると結果を出し、ルール選択へ戻る。

const RESULT_PANEL_SIZE := Vector2(600, 460)
const FX_Z := 50  # 飛んでいるカードは場のカードより手前
const SHADE_Z := 100
const DEAL_TIME := 0.26
const PETAL_COLORS := [
	Color("ffb7c5"), Color("ff8fab"), Color("ffd6e0"), Color("ffffff"), Color("ffe08a"), Color("f7a8d8"),
]

static var _petal_texture: ImageTexture

var message_label: Label
var portrait := false
var screen := UI.LANDSCAPE

var fx_layer: Control
var deck_pile: Control
var deck_center := Vector2.ZERO
var deck_card_size := Vector2(84, 118)


func setup_base(game_title: String) -> void:
	UI.apply_orientation(get_tree())
	portrait = Settings.portrait
	screen = UI.screen()
	UI.background(self)
	UI.label(self, game_title, Vector2(20, 6), Vector2(240, 44), 30, HORIZONTAL_ALIGNMENT_LEFT)
	message_label = UI.label(self, "", Vector2(0, 6), Vector2(screen.x, 44), 22)
	UI.button(self, "やめる", Vector2(screen.x - 140, 10), Vector2(120, 36), 18, _go_rule_select)
	fx_layer = Control.new()
	fx_layer.z_index = FX_Z
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx_layer)


func place_message(pos: Vector2, label_size: Vector2, font_size: int) -> void:
	message_label.position = pos
	message_label.size = label_size
	message_label.add_theme_font_size_override("font_size", font_size)


func set_message(text: String) -> void:
	message_label.text = text


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## 山札（裏向きの束）を center に置く。配るカードはここから飛び出す。
func show_deck(center: Vector2, card_size: Vector2) -> void:
	if deck_pile != null:
		deck_pile.queue_free()
	deck_center = center
	deck_card_size = card_size
	deck_pile = Control.new()
	deck_pile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(deck_pile)
	for i in 4:
		var view := CardView.new()
		deck_pile.add_child(view)
		view.setup(null, card_size, false)
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.position = center - card_size / 2.0 - Vector2(i * 2, i * 2)


func hide_deck() -> void:
	if deck_pile == null:
		return
	var pile := deck_pile
	deck_pile = null
	var tween := pile.create_tween()
	tween.tween_property(pile, "modulate:a", 0.0, 0.2)
	tween.tween_callback(pile.queue_free)


## 山札から順番にカードを配る。items の各要素は
## {card, to(左上の位置), size, face_up(着いたら表にする), keep(着いたあと残す)}。
## keep のカードは全部配り終わるまでその場に残るので、直後に本物を並べれば切れ目なくつながる。
func deal_cards(items: Array, interval: float = 0.04) -> void:
	if items.is_empty():
		return
	var kept: Array[CardView] = []
	var last: Tween
	for i in items.size():
		var item: Dictionary = items[i]
		var view := _make_flyer(item["card"], deck_center - deck_card_size / 2.0, deck_card_size, item["size"], false)
		view.visible = false
		var tween := view.create_tween()
		tween.tween_interval(maxf(i * interval, 0.001))
		tween.tween_callback(view.show)
		tween.tween_property(view, "position", item["to"], DEAL_TIME) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(view, "scale", Vector2.ONE, DEAL_TIME)
		if item.get("face_up", false):
			tween.tween_callback(view.set_face_up.bind(true))
		if item.get("keep", true):
			kept.append(view)
		else:
			tween.tween_callback(view.queue_free)
		last = tween
	await last.finished
	for view in kept:
		view.queue_free()


## カード1枚を from から to へ飛ばす（位置は左上）。着いたら消えるので、呼んだ側で本物を置く。
func fly_card(card: Card, from: Vector2, to: Vector2, from_size: Vector2, to_size: Vector2,
		face_up: bool = true, duration: float = 0.28) -> void:
	var view := _make_flyer(card, from, from_size, to_size, face_up)
	var tween := view.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(view, "position", to, duration)
	tween.tween_property(view, "scale", Vector2.ONE, duration)
	await tween.finished
	view.queue_free()


func _make_flyer(card: Card, pos: Vector2, from_size: Vector2, to_size: Vector2, face_up: bool) -> CardView:
	var view := CardView.new()
	fx_layer.add_child(view)
	view.setup(card, to_size, face_up)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.pivot_offset = Vector2.ZERO
	view.scale = from_size / to_size
	view.position = pos
	return view


## 花吹雪を降らせる。burst が true なら一度だけぱっと散らす。
func celebrate(parent: Node = null, burst: bool = false) -> void:
	var petals := CPUParticles2D.new()
	petals.texture = _get_petal_texture()
	petals.position = Vector2(screen.x / 2.0, -30)
	petals.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	petals.emission_rect_extents = Vector2(screen.x / 2.0, 4)
	petals.amount = 90 if burst else 160
	petals.lifetime = 7.0 if portrait else 5.0
	petals.direction = Vector2.DOWN
	petals.spread = 28.0
	petals.gravity = Vector2(0, 70)
	petals.initial_velocity_min = 110.0
	petals.initial_velocity_max = 260.0
	petals.angle_min = 0.0
	petals.angle_max = 360.0
	petals.angular_velocity_min = -240.0
	petals.angular_velocity_max = 240.0
	petals.scale_amount_min = 0.7
	petals.scale_amount_max = 1.5
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offsets := PackedFloat32Array()
	for i in PETAL_COLORS.size():
		offsets.append(float(i) / PETAL_COLORS.size())
	ramp.offsets = offsets
	ramp.colors = PackedColorArray(PETAL_COLORS)
	petals.color_initial_ramp = ramp
	if burst:
		petals.one_shot = true
		petals.explosiveness = 0.85
		petals.z_index = FX_Z + 1
		get_tree().create_timer(petals.lifetime + 0.5).timeout.connect(petals.queue_free)
	else:
		petals.preprocess = 0.6
	(parent if parent != null else self).add_child(petals)


static func _get_petal_texture() -> ImageTexture:
	if _petal_texture == null:
		# 小さな楕円の花びら
		var image := Image.create(16, 10, false, Image.FORMAT_RGBA8)
		for y in 10:
			for x in 16:
				var d := Vector2((x - 7.5) / 8.0, (y - 4.5) / 5.0).length()
				image.set_pixel(x, y, Color(1, 1, 1, clampf((1.0 - d) * 4.0, 0.0, 1.0)))
		_petal_texture = ImageTexture.create_from_image(image)
	return _petal_texture


func show_result(headline: String, lines: Array, won: bool = false) -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.65)
	shade.size = screen
	shade.z_index = SHADE_Z  # 重ねて並べたカードや飛んでいるカードより手前に出す
	add_child(shade)
	if won:
		celebrate(shade)

	var panel := UI.panel(shade, (screen - RESULT_PANEL_SIZE) / 2.0, RESULT_PANEL_SIZE)

	UI.label(panel, headline, Vector2(0, 24), Vector2(600, 70), 44)
	UI.label(panel, "\n".join(lines), Vector2(40, 110), Vector2(520, 230), 26)
	UI.button(panel, "ルール選択へ", Vector2(170, 370), Vector2(260, 60), 28, _go_rule_select)


func _go_rule_select() -> void:
	get_tree().change_scene_to_file(UI.SCENE_RULE_SELECT)
