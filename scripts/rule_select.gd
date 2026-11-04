extends Control
## ルール選択画面。ゲームを追加するときは RULES に1行足す。
## "options" があるゲームは、「あそぶ」のあとにルール設定画面（Settings.GAME_OPTIONS）をはさむ。

const RULES := [
	{
		"name": "七ならべ",
		"scene": "res://scenes/sevens.tscn",
		"desc": "7を起点に、同じマークの\n隣の数字を並べていく。\nパスは3回まで。\n（あなた＋CPU3人）",
	},
	{
		"name": "ババ抜き",
		"scene": "res://scenes/old_maid.tscn",
		"desc": "隣の人から1枚引いて、\n同じ数字のペアを捨てる。\n最後にジョーカーを\n持っていた人の負け。",
	},
	{
		"name": "神経衰弱",
		"scene": "res://scenes/memory.tscn",
		"options": "memory",
		"desc": "2枚めくって同じ数字なら\nもらえて、もう1回。\n多く取った方の勝ち。\n（CPUのつよさを選べる）",
	},
	{
		"name": "ブラックジャック",
		"scene": "res://scenes/blackjack.tscn",
		"desc": "合計を21に近づける。\nヒットで1枚引き、\nスタンドで勝負。\n（全5ラウンド）",
	},
	{
		"name": "ダウト",
		"scene": "res://scenes/doubt.tscn",
		"desc": "A,2,3…の順に裏向きで\n出す。うそもOK。\nあやしいと思ったら\n「ダウト！」",
	},
	{
		"name": "ポーカー",
		"scene": "res://scenes/poker.tscn",
		"options": "poker",
		"desc": "5枚で役を作る。\n交換は1回だけ。\n全5ラウンドの合計点。\n（ジョーカーを選べる）",
	},
	{
		"name": "大富豪",
		"scene": "res://scenes/daifugo.tscn",
		"options": "daifugo",
		"desc": "強いカードを出して\n先に手札をなくす。\n2とジョーカーが強い。\n（地方ルールを選べる）",
	},
	{
		"name": "ソリティア",
		"scene": "res://scenes/solitaire.tscn",
		"options": "solitaire",
		"desc": "7列の場札を並べかえ、\nA→Kを4組積めばクリア。\n1人で遊ぶ。\n（めくる枚数を選べる）",
	},
]

## パネルの並べ方とパネル内の配置。よこ画面は4列、たて画面は2列に並べる。
const LAYOUT_LANDSCAPE := {
	"columns": 4, "panel": Vector2(292, 222), "gap": 12.0, "top": 140.0,
	"name_y": 8.0, "name_h": 44.0, "name_font": 28,
	"desc_y": 54.0, "desc_h": 100.0, "desc_font": 16,
	"play": Rect2(87, 160, 118, 50), "play_font": 24,
}
const LAYOUT_PORTRAIT := {
	"columns": 2, "panel": Vector2(340, 250), "gap": 12.0, "top": 116.0,
	"name_y": 10.0, "name_h": 46.0, "name_font": 30,
	"desc_y": 58.0, "desc_h": 120.0, "desc_font": 18,
	"play": Rect2(80, 186, 180, 52), "play_font": 26,
}


func _ready() -> void:
	UI.apply_orientation(get_tree())
	var p := Settings.portrait
	var screen := UI.screen()
	var layout: Dictionary = LAYOUT_PORTRAIT if p else LAYOUT_LANDSCAPE
	var panel_size: Vector2 = layout["panel"]
	UI.background(self)
	UI.card_backdrop(self, 0.55)
	UI.outline(UI.label(self, "ルールをえらぶ", Vector2(0, 26 if p else 36), Vector2(screen.x, 80), 52), 12)

	var columns: int = layout["columns"]
	var gap: float = layout["gap"]
	var top: float = layout["top"]
	@warning_ignore("integer_division")
	var rows := (RULES.size() + columns - 1) / columns
	for i in RULES.size():
		var rule: Dictionary = RULES[i]
		@warning_ignore("integer_division")
		var row := i / columns
		# 最後の段が埋まらないときは、その段だけ中央に寄せる
		var in_row := columns if row < rows - 1 else RULES.size() - row * columns
		var start_x := (screen.x - (in_row * panel_size.x + (in_row - 1) * gap)) / 2.0
		var pos := Vector2(start_x + (i % columns) * (panel_size.x + gap), top + row * (panel_size.y + gap))
		var panel := UI.panel(self, pos, panel_size)
		UI.label(panel, rule["name"], Vector2(0, layout["name_y"]), Vector2(panel_size.x, layout["name_h"]),
				layout["name_font"])
		var desc := UI.label(panel, rule["desc"], Vector2(10, layout["desc_y"]),
				Vector2(panel_size.x - 20, layout["desc_h"]), layout["desc_font"])
		desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		var play: Rect2 = layout["play"]
		UI.button(panel, "あそぶ", play.position, play.size, layout["play_font"], _start.bind(rule))

	UI.button(self, "タイトルへ", Vector2(screen.x / 2.0 - 100, 1176 if p else 640), Vector2(200, 50), 22,
			_back_to_title)


func _start(rule: Dictionary) -> void:
	if rule.has("options"):
		Settings.pending_rule = rule
		get_tree().change_scene_to_file(UI.SCENE_GAME_OPTIONS)
	else:
		get_tree().change_scene_to_file(rule["scene"])


func _back_to_title() -> void:
	get_tree().change_scene_to_file(UI.SCENE_TITLE)
