extends Control
## タイトル画面。画面の向き（よこ／たて）もここで選ぶ。

const FAN_CARDS := [[0, 1], [1, 13], [2, 12], [3, 11], [0, 7]]
const FAN_CARD_SIZE := Vector2(150, 210)
const ORIENTATION_BUTTON := Vector2(230, 52)


func _ready() -> void:
	if not Settings.orientation_chosen:
		Settings.orientation_chosen = true
		# ブラウザやスマホでは、最初は今の画面の形に合わせておく
		if OS.has_feature("web") or OS.has_feature("mobile"):
			var window_size := get_window().size
			Settings.portrait = window_size.y > window_size.x
	UI.apply_orientation(get_tree())

	var p := Settings.portrait
	var screen := UI.screen()
	var cx := screen.x / 2.0
	UI.background(self)
	UI.card_backdrop(self, 0.62)
	var title := UI.label(self, "トランプゲーム", Vector2(0, 170 if p else 36), Vector2(screen.x, 110), 84)
	UI.outline(title, 16)
	_build_fan(Vector2(cx, 400 if p else 176))

	var select_y := 700.0 if p else 434.0
	UI.outline(UI.label(self, "画面の向き（スマホは「たて」がおすすめ）", Vector2(0, select_y), Vector2(screen.x, 30), 20), 8)
	_orientation_button("よこ画面", false, Vector2(cx - ORIENTATION_BUTTON.x - 10, select_y + 36))
	_orientation_button("たて画面", true, Vector2(cx + 10, select_y + 36))

	UI.button(self, "スタート", Vector2(cx - 150, 880 if p else 546), Vector2(300, 72), 36, _on_start)
	# ブラウザやスマホではアプリを閉じるボタンは意味がないので出さない
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		UI.button(self, "おわる", Vector2(cx - 75, 990 if p else 636), Vector2(150, 44), 20, get_tree().quit)


func _build_fan(top_center: Vector2) -> void:
	var count := FAN_CARDS.size()
	for i in count:
		var view := CardView.new()
		add_child(view)
		view.setup(Card.new(FAN_CARDS[i][0], FAN_CARDS[i][1]), FAN_CARD_SIZE)
		var offset := i - (count - 1) / 2.0
		view.position = top_center + Vector2(-FAN_CARD_SIZE.x / 2.0 + offset * 90, absf(offset) * 14)
		view.rotation_degrees = offset * 9
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _orientation_button(text: String, portrait: bool, pos: Vector2) -> void:
	var selected := Settings.portrait == portrait
	var btn := UI.button(self, ("● " if selected else "") + text, pos, ORIENTATION_BUTTON, 22,
			_set_orientation.bind(portrait))
	btn.modulate = Color.YELLOW if selected else Color(0.75, 0.75, 0.75)


func _set_orientation(portrait: bool) -> void:
	if Settings.portrait == portrait:
		return
	Settings.portrait = portrait
	get_tree().reload_current_scene()


func _on_start() -> void:
	get_tree().change_scene_to_file(UI.SCENE_RULE_SELECT)
