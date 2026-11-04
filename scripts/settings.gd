class_name Settings
extends RefCounted
## タイトルやルール設定で決めた設定を、各シーンへ受け渡すための置き場。

## ゲームごとに選べるルール。ルール選択で「あそぶ」を押すと、ルール設定画面でこれを選ぶ。
## 各項目: key（値の名前）, title, help（短い説明）, choices（[表示名, 値]）, default（choices の番号）
const GAME_OPTIONS := {
	"memory": [
		{"key": "memory_cpu_rate", "title": "CPUのつよさ", "help": "めくったカードを覚えている割合",
				"choices": [["よわい", 0.25], ["ふつう", 0.5], ["つよい", 0.85]], "default": 1},
	],
	"poker": [
		{"key": "poker_jokers", "title": "ジョーカー", "help": "どのカードの代わりにもなる",
				"choices": [["なし", 0], ["1枚", 1], ["2枚", 2]], "default": 0},
	],
	"solitaire": [
		{"key": "solitaire_draw", "title": "めくる枚数", "help": "山札から1回にめくる枚数",
				"choices": [["1枚", 1], ["3枚", 3]], "default": 0},
	],
	"daifugo": [
		{"key": "daifugo_rounds", "title": "対戦回数", "help": "何回戦の合計点で競うか",
				"choices": [["1回", 1], ["3回", 3], ["5回", 5]], "default": 1},
		{"key": "daifugo_jokers", "title": "ジョーカー", "help": "最強のカード。何にでもなる",
				"choices": [["なし", 0], ["1枚", 1], ["2枚", 2]], "default": 1},
		{"key": "daifugo_revolution", "title": "革命", "help": "4枚出しで強さが逆になる",
				"choices": [["あり", true], ["なし", false]], "default": 0},
		{"key": "daifugo_eight", "title": "8切り", "help": "8を出すと場が流れる",
				"choices": [["あり", true], ["なし", false]], "default": 0},
		{"key": "daifugo_stairs", "title": "階段", "help": "同じマークの3枚以上の連番",
				"choices": [["あり", true], ["なし", false]], "default": 0},
		{"key": "daifugo_eleven", "title": "11バック", "help": "Jを出すと流れるまで逆転",
				"choices": [["あり", true], ["なし", false]], "default": 1},
		{"key": "daifugo_shibari", "title": "しばり", "help": "同じマークが続くと固定",
				"choices": [["あり", true], ["なし", false]], "default": 1},
		{"key": "daifugo_spade3", "title": "スペ3返し", "help": "♠3がジョーカー1枚に勝つ",
				"choices": [["あり", true], ["なし", false]], "default": 1},
		{"key": "daifugo_miyako", "title": "都落ち", "help": "大富豪が1位をのがすと最下位",
				"choices": [["あり", true], ["なし", false]], "default": 1},
		{"key": "daifugo_exchange", "title": "カード交換", "help": "2回戦から階級で交換する",
				"choices": [["あり", true], ["なし", false]], "default": 0},
	],
}

static var values := {}

## ルール設定画面で選んでいるゲーム（ルール選択の RULES の1件）。
static var pending_rule := {}

## たて画面(720x1280)で遊ぶかどうか。起動引数 `-- --portrait` でも指定できる。
static var portrait := "--portrait" in OS.get_cmdline_user_args()
static var orientation_chosen := "--portrait" in OS.get_cmdline_user_args()


static func get_value(key: String) -> Variant:
	if values.has(key):
		return values[key]
	var option := _find(key)
	return option["choices"][option["default"]][1]


## 今の値の表示名（「ふつう」など）。
static func choice_name(key: String) -> String:
	var option := _find(key)
	var current: Variant = get_value(key)
	for choice: Array in option["choices"]:
		if choice[1] == current:
			return choice[0]
	return ""


static func _find(key: String) -> Dictionary:
	for game: String in GAME_OPTIONS:
		for option: Dictionary in GAME_OPTIONS[game]:
			if option["key"] == key:
				return option
	push_error("unknown option: " + key)
	return {}
