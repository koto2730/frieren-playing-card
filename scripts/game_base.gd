class_name GameBase
extends Control
## 各ゲーム共通の土台。背景・タイトル・メッセージ・結果表示を持つ。
## ゲームが終わると結果を出し、ルール選択へ戻る。

const RESULT_PANEL_SIZE := Vector2(600, 460)

var message_label: Label
var portrait := false
var screen := UI.LANDSCAPE


func setup_base(game_title: String) -> void:
	UI.apply_orientation(get_tree())
	portrait = Settings.portrait
	screen = UI.screen()
	UI.background(self)
	UI.label(self, game_title, Vector2(20, 6), Vector2(240, 44), 30, HORIZONTAL_ALIGNMENT_LEFT)
	message_label = UI.label(self, "", Vector2(0, 6), Vector2(screen.x, 44), 22)
	UI.button(self, "やめる", Vector2(screen.x - 140, 10), Vector2(120, 36), 18, _go_rule_select)


func place_message(pos: Vector2, label_size: Vector2, font_size: int) -> void:
	message_label.position = pos
	message_label.size = label_size
	message_label.add_theme_font_size_override("font_size", font_size)


func set_message(text: String) -> void:
	message_label.text = text


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func show_result(headline: String, lines: Array) -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.65)
	shade.size = screen
	shade.z_index = 100  # 重ねて並べたカードより手前に出す
	add_child(shade)

	var panel := UI.panel(shade, (screen - RESULT_PANEL_SIZE) / 2.0, RESULT_PANEL_SIZE)

	UI.label(panel, headline, Vector2(0, 24), Vector2(600, 70), 44)
	UI.label(panel, "\n".join(lines), Vector2(40, 110), Vector2(520, 230), 26)
	UI.button(panel, "ルール選択へ", Vector2(170, 370), Vector2(260, 60), 28, _go_rule_select)


func _go_rule_select() -> void:
	get_tree().change_scene_to_file(UI.SCENE_RULE_SELECT)
