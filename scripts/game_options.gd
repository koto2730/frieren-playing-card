extends Control
## ルール設定画面。ルール選択で選んだゲームの、選べるルール（Settings.GAME_OPTIONS）を並べる。
## 1行に「名前・短い説明」と、選択肢のボタンを置く。項目が多いときは、よこ画面で2列にする。

const ROW_HEIGHT := 84.0

var rule := {}
var row_buttons := {}  # key -> Array[Button]


func _ready() -> void:
	UI.apply_orientation(get_tree())
	rule = Settings.pending_rule
	var p := Settings.portrait
	var screen := UI.screen()
	UI.background(self)
	UI.card_backdrop(self, 0.4)
	UI.outline(UI.label(self, "%s のルール" % rule.get("name", ""), Vector2(0, 26 if p else 30), Vector2(screen.x, 70),
			44), 12)

	var options: Array = Settings.GAME_OPTIONS.get(rule.get("options", ""), [])
	var columns := 2 if not p and options.size() > 5 else 1
	var column_width := 600.0 if columns == 2 else (680.0 if p else 760.0)
	@warning_ignore("integer_division")
	var per_column := (options.size() + columns - 1) / columns
	var total_width := columns * column_width + (columns - 1) * 20.0
	var top := 120.0 if p else 112.0
	var panel_height := per_column * ROW_HEIGHT + 16
	var panel := UI.panel(self, Vector2((screen.x - total_width) / 2.0 - 10, top - 8),
			Vector2(total_width + 20, panel_height))
	for i in options.size():
		@warning_ignore("integer_division")
		var column := i / per_column
		var row := i % per_column
		var pos := Vector2(10 + column * (column_width + 20), 8 + row * ROW_HEIGHT)
		_build_row(panel, options[i], pos, column_width)

	var buttons_y := top + panel_height + (40 if p else 24)
	UI.button(self, "もどる", Vector2(screen.x / 2.0 - 290, buttons_y), Vector2(260, 64), 26, _back)
	UI.button(self, "はじめる", Vector2(screen.x / 2.0 + 30, buttons_y), Vector2(260, 64), 30, _start)


func _build_row(parent: Control, option: Dictionary, pos: Vector2, width: float) -> void:
	var text_width := width * 0.42
	UI.label(parent, option["title"], pos + Vector2(4, 6), Vector2(text_width, 34), 24, HORIZONTAL_ALIGNMENT_LEFT)
	var help := UI.label(parent, option["help"], pos + Vector2(4, 40), Vector2(text_width, 26), 15,
			HORIZONTAL_ALIGNMENT_LEFT)
	help.modulate = Color(0.8, 0.8, 0.8)

	var choices: Array = option["choices"]
	var spacing := 6.0
	var area := width - text_width - 8
	var button_size := Vector2(minf(130, (area - spacing * (choices.size() - 1)) / choices.size()), 52)
	var start_x := pos.x + text_width + 8 + (area - (choices.size() * (button_size.x + spacing) - spacing))
	var buttons: Array[Button] = []
	for i in choices.size():
		buttons.append(UI.button(parent, choices[i][0], Vector2(start_x + i * (button_size.x + spacing), pos.y + 14),
				button_size, 20, _select.bind(option["key"], i)))
	row_buttons[option["key"]] = buttons
	_show_selection(option)


func _select(key: String, index: int) -> void:
	var option := _option(key)
	Settings.values[key] = option["choices"][index][1]
	_show_selection(option)


func _show_selection(option: Dictionary) -> void:
	var current: Variant = Settings.get_value(option["key"])
	var buttons: Array = row_buttons[option["key"]]
	for i in buttons.size():
		var chosen: bool = option["choices"][i][1] == current
		buttons[i].modulate = Color.YELLOW if chosen else Color(0.7, 0.7, 0.7)
		buttons[i].text = ("● " if chosen else "") + option["choices"][i][0]


func _option(key: String) -> Dictionary:
	for option: Dictionary in Settings.GAME_OPTIONS[rule["options"]]:
		if option["key"] == key:
			return option
	return {}


func _start() -> void:
	get_tree().change_scene_to_file(rule["scene"])


func _back() -> void:
	get_tree().change_scene_to_file(UI.SCENE_RULE_SELECT)
