extends GameBase
## ポーカー（5枚のドローポーカー）。あなた＋CPU3人。
## 配られた5枚から好きな枚数を1回だけ交換し、役の強さで順位を決める。
## 1位3点・2位2点・3位1点。全5ラウンドの合計点で勝負。
## ジョーカーを入れた場合は、どのカードの代わりにもなる（同じ数字5枚のファイブカードもできる）。

signal player_acted

const NAMES := ["あなた", "CPU 1", "CPU 2", "CPU 3"]
const ROUNDS := 5
const PLACE_POINTS := [3, 2, 1, 0]
const HAND_NAMES := [
	"ブタ", "ワンペア", "ツーペア", "スリーカード", "ストレート",
	"フラッシュ", "フルハウス", "フォーカード", "ストレートフラッシュ", "ロイヤルストレートフラッシュ",
	"ファイブカード",
]

# 配置。よこ画面はCPUを横に3人、たて画面は縦に3段並べる。
var cpu_card := Vector2(72, 101)
var cpu_step := 78.0
var cpu_panel_width := 400.0
var hand_card := Vector2(120, 168)
var hand_step := 132.0
var hand_y := 380.0
var pile_center := Vector2(1120, 330)
var pile_card := Vector2(84, 118)

var deck: Array[Card] = []
var hands: Array = [[], [], [], []]
var points := [0, 0, 0, 0]
var round_points := [0, 0, 0, 0]
var results: Array = [[], [], [], []]
var round_no := 0
var joker_count := 0
var reveal_upto := 0  # この番号までのCPUは手札を表にしている
var scored := false
var selected := {}  # 手札の位置 -> true
var input_enabled := false
var waiting_next := false

var cpu_layers: Array[Control] = []
var cpu_labels: Array[Label] = []
var hand_layer: Control
var hand_label: Label
var status_label: Label
var main_button: Button


func _ready() -> void:
	setup_base("ポーカー")
	joker_count = Settings.POKER_JOKER_OPTIONS[Settings.poker_joker_option]["count"]
	var button_rect := Rect2(screen.x / 2.0 - 170, 590, 340, 64)
	var hand_label_y := 318.0
	if portrait:
		cpu_card = Vector2(80, 112)
		cpu_step = 88.0
		cpu_panel_width = 680.0
		hand_card = Vector2(124, 174)
		hand_y = 790.0
		hand_label_y = 718.0
		pile_center = Vector2(screen.x / 2.0, 600)
		button_rect = Rect2(160, 1020, 400, 80)
		place_message(Vector2(0, 668), Vector2(screen.x, 44), 22)
	else:
		place_message(Vector2(140, 250), Vector2(840, 44), 24)

	status_label = UI.label(self, "", Vector2(screen.x - 450, 6), Vector2(300, 44), 18 if portrait else 20,
			HORIZONTAL_ALIGNMENT_RIGHT)
	for p in range(1, 4):
		var pos := Vector2(20, 60 + (p - 1) * 152.0) if portrait else Vector2(20 + (p - 1) * 420.0, 64)
		cpu_labels.append(UI.label(self, "", pos, Vector2(cpu_panel_width, 36), 20))
		var layer := Control.new()
		layer.position = pos + Vector2(0, 38 if portrait else 46)
		add_child(layer)
		cpu_layers.append(layer)
	hand_label = UI.label(self, "", Vector2(0, hand_label_y), Vector2(screen.x, 36), 22)
	hand_layer = Control.new()
	add_child(hand_layer)
	main_button = UI.button(self, "", button_rect.position, button_rect.size, 28, _on_main)
	main_button.visible = false
	_run()


func _run() -> void:
	show_deck(pile_center, pile_card)
	for r in ROUNDS:
		round_no = r + 1
		await _play_round()
	_finish()


func _play_round() -> void:
	deck = Card.make_deck(joker_count)
	hands = [[], [], [], []]
	results = [[], [], [], []]
	round_points = [0, 0, 0, 0]
	reveal_upto = 0
	scored = false
	selected.clear()
	_refresh()
	set_message("ラウンド %d　カードを配ります" % round_no)
	await wait(0.4)

	# 先に5枚ずつ決めて（あなたの手札は並べ替えて）から、1枚ずつ順番に配る
	var dealt: Array = [[], [], [], []]
	var order: Array = []
	for i in 5:
		for p in 4:
			var card: Card = deck.pop_back()
			dealt[p].append(card)
			order.append([p, card])
	dealt[0].sort_custom(_by_strength)
	var positions: Array = []
	for p in 4:
		positions.append(_card_positions(p))
	var items: Array = []
	for entry: Array in order:
		var p: int = entry[0]
		items.append({"card": entry[1], "to": positions[p][dealt[p].find(entry[1])], "size": _card_size(p),
				"face_up": p == 0})
	await deal_cards(items, 0.05)
	hands = dealt
	_refresh()

	await _human_exchange()
	for p in range(1, 4):
		await _cpu_exchange(p)
	await _showdown()

	main_button.text = "つぎのラウンドへ" if round_no < ROUNDS else "結果を見る"
	main_button.visible = true
	waiting_next = true
	await player_acted
	waiting_next = false
	main_button.visible = false


func _human_exchange() -> void:
	set_message("交換するカードを選んでください（何枚でも、0枚でもOK）")
	input_enabled = true
	_update_main_button()
	main_button.visible = true
	_refresh()
	await player_acted
	input_enabled = false
	main_button.visible = false
	var indices: Array = selected.keys()
	indices.sort()
	selected.clear()
	if indices.is_empty():
		set_message("あなたは交換しなかった")
		_refresh()
		await wait(0.6)
		return
	set_message("あなたは%d枚交換" % indices.size())
	await _exchange(0, indices)
	hands[0].sort_custom(_by_strength)
	_refresh()
	await wait(0.5)


func _cpu_exchange(p: int) -> void:
	set_message("%s が考えています…" % NAMES[p])
	await wait(0.5)
	var indices := _cpu_discards(hands[p])
	set_message("%s は%s" % [NAMES[p], "%d枚交換" % indices.size() if not indices.is_empty() else "交換しなかった"])
	await _exchange(p, indices)
	await wait(0.4)


## 選んだ位置のカードを捨てて、山札から同じ位置に新しいカードを配る。
func _exchange(p: int, indices: Array) -> void:
	if indices.is_empty():
		return
	var positions := _card_positions(p)
	for index: int in indices:
		fly_card(hands[p][index], positions[index], pile_center - pile_card / 2.0, _card_size(p), pile_card,
				p == 0, 0.25)
		hands[p][index] = null
		_refresh()
		await wait(0.06)
	await wait(0.3)
	for index: int in indices:
		var card: Card = deck.pop_back()
		await fly_card(card, pile_center - pile_card / 2.0, positions[index], pile_card, _card_size(p), p == 0, 0.22)
		hands[p][index] = card
		_refresh()


func _showdown() -> void:
	set_message("勝負！")
	for p in 4:
		results[p] = evaluate(hands[p])
	# CPUの手札を1人ずつめくる
	for p in range(1, 4):
		reveal_upto = p
		_refresh()
		for view: CardView in cpu_layers[p - 1].get_children():
			view.set_face_up(false)
			view.flip(true)
		await wait(0.7)

	var winners: Array = []
	for p in 4:
		var place := 0
		for q in 4:
			if compare(results[q], results[p]) > 0:
				place += 1
		round_points[p] = PLACE_POINTS[place]
		points[p] += round_points[p]
		if place == 0:
			winners.append(p)
	scored = true
	var winner_names: Array = winners.map(func(p: int) -> String: return NAMES[p])
	set_message("%s の勝ち！（%s）" % ["・".join(winner_names), HAND_NAMES[results[winners[0]][0]]])
	_refresh()
	if 0 in winners:
		celebrate(null, true)


func _on_hand_card(index: int) -> void:
	if not input_enabled:
		return
	if selected.has(index):
		selected.erase(index)
	else:
		selected[index] = true
	_update_main_button()
	_refresh()


func _on_main() -> void:
	if input_enabled or waiting_next:
		player_acted.emit()


func _update_main_button() -> void:
	main_button.text = "%d枚交換する" % selected.size() if not selected.is_empty() else "このまま勝負"


func _card_size(p: int) -> Vector2:
	return hand_card if p == 0 else cpu_card


func _card_positions(p: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if p == 0:
		var start_x := (screen.x - (hand_step * 4 + hand_card.x)) / 2.0
		for i in 5:
			positions.append(Vector2(start_x + i * hand_step, hand_y))
		return positions
	var cpu_start := (cpu_panel_width - (cpu_step * 4 + cpu_card.x)) / 2.0
	for i in 5:
		positions.append(cpu_layers[p - 1].position + Vector2(cpu_start + i * cpu_step, 0))
	return positions


func _refresh() -> void:
	status_label.text = "ラウンド %d/%d" % [round_no, ROUNDS] + ("　ジョーカー%d枚" % joker_count if joker_count > 0 else "")
	var best := 0
	if scored:
		for p in 4:
			best = maxi(best, round_points[p])
	for p in range(1, 4):
		var layer := cpu_layers[p - 1]
		UI.clear_children(layer)
		var positions := _card_positions(p)
		for i in hands[p].size():
			if hands[p][i] == null:
				continue
			var view := CardView.new()
			layer.add_child(view)
			view.setup(hands[p][i], cpu_card, p <= reveal_upto)
			view.position = positions[i] - layer.position
		var lbl := cpu_labels[p - 1]
		lbl.text = "%s  %s" % [NAMES[p], _score_text(p)]
		lbl.modulate = Color.YELLOW if scored and round_points[p] == best else Color.WHITE

	UI.clear_children(hand_layer)
	var hand_positions := _card_positions(0)
	for i in hands[0].size():
		if hands[0][i] == null:
			continue
		var view := CardView.new()
		hand_layer.add_child(view)
		view.setup(hands[0][i], hand_card)
		view.position = hand_positions[i] - Vector2(0, 26 if selected.has(i) else 0)
		view.set_dimmed(selected.has(i))
		view.set_clickable(input_enabled)
		view.pressed.connect(_on_hand_card.bind(i))
	var hand_name := ""
	if hands[0].size() == 5 and not hands[0].has(null):
		hand_name = HAND_NAMES[evaluate(hands[0])[0]]
	hand_label.text = "あなた  %s  %s" % [hand_name, _score_text(0)]
	hand_label.modulate = Color.YELLOW if scored and round_points[0] == best else Color.WHITE


## 名前の横に出す文字。めくったCPUは役の名前、勝負がついたら得点も出す。
func _score_text(p: int) -> String:
	var text := ""
	if p != 0 and p <= reveal_upto:
		text = HAND_NAMES[results[p][0]] + "  "
	if scored:
		return text + "+%d（計%d点）" % [round_points[p], points[p]]
	return text + "計%d点" % points[p]


func _by_strength(a: Card, b: Card) -> bool:
	return _value(a) < _value(b) or (_value(a) == _value(b) and a.suit < b.suit)


## 並べ替えや比べるときの数字の強さ（Aは14）。ジョーカーはいちばん右に並ぶよう15にする。
static func _value(card: Card) -> int:
	if card.is_joker():
		return 15
	return 14 if card.rank == 1 else card.rank


## 役の強さ。[役の番号, 同じ役どうしで比べる数字…] の配列で、前から順に比べる。
## ジョーカーは、いちばん強くなるカードに置きかえて考える。
static func evaluate(hand: Array) -> Array:
	var naturals: Array = hand.filter(func(c: Card) -> bool: return not c.is_joker())
	var wilds := hand.size() - naturals.size()
	if wilds == 0:
		return _evaluate_natural(hand)
	# 置きかえ先のマークは、フラッシュになりうるマークと、それ以外の1つだけ試せば十分
	var suits := {}
	for card: Card in naturals:
		suits[card.suit] = true
	var suit_choices: Array = [suits.keys()[0], (suits.keys()[0] + 1) % 4] if suits.size() == 1 else [0]
	var candidates: Array = []
	for suit: int in suit_choices:
		for rank in range(1, 14):
			candidates.append(Card.new(suit, rank))
	return _best_with_wilds(naturals, wilds, candidates)


static func _best_with_wilds(cards: Array, wilds: int, candidates: Array) -> Array:
	if wilds == 0:
		return _evaluate_natural(cards)
	var best: Array = []
	for candidate: Card in candidates:
		var result := _best_with_wilds(cards + [candidate], wilds - 1, candidates)
		if best.is_empty() or compare(result, best) > 0:
			best = result
	return best


static func _evaluate_natural(hand: Array) -> Array:
	var values: Array = []
	var suits := {}
	for card: Card in hand:
		values.append(_value(card))
		suits[card.suit] = true
	values.sort()
	values.reverse()
	var counts := {}
	for v: int in values:
		counts[v] = counts.get(v, 0) + 1
	var groups: Array = counts.keys()
	groups.sort_custom(func(a: int, b: int) -> bool:
		return counts[a] > counts[b] or (counts[a] == counts[b] and a > b))
	var shape: Array = groups.map(func(v: int) -> int: return counts[v])
	var flush := suits.size() == 1
	var straight_high := 0
	if groups.size() == 5:
		if values[0] - values[4] == 4:
			straight_high = values[0]
		elif values[0] == 14 and values[1] == 5:
			straight_high = 5  # A-2-3-4-5
	if shape[0] == 5:
		return [10, groups[0]]
	if straight_high > 0 and flush:
		return [9 if straight_high == 14 else 8, straight_high]
	if shape[0] == 4:
		return [7] + groups
	if shape[0] == 3 and shape[1] == 2:
		return [6] + groups
	if flush:
		return [5] + values
	if straight_high > 0:
		return [4, straight_high]
	if shape[0] == 3:
		return [3] + groups
	if shape[0] == 2 and shape[1] == 2:
		return [2] + groups
	if shape[0] == 2:
		return [1] + groups
	return [0] + values


static func compare(a: Array, b: Array) -> int:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return 1 if a[i] > b[i] else -1
	return 0


## CPUが捨てるカードの位置。できた役は残し、あと1枚でフラッシュ・ストレートなら狙う。
func _cpu_discards(hand: Array) -> Array:
	var category: int = evaluate(hand)[0]
	if category >= 4:
		return []
	if hand.any(func(c: Card) -> bool: return c.is_joker()):
		return _cpu_discards_with_joker(hand)
	var values: Array = hand.map(func(c: Card) -> int: return _value(c))
	var counts := {}
	for v: int in values:
		counts[v] = counts.get(v, 0) + 1
	var discards: Array = []
	if category >= 1:
		# ペア系は、ペアになっていないカードを捨てる
		for i in 5:
			if counts[values[i]] == 1:
				discards.append(i)
		return discards
	var by_suit := {}
	for i in 5:
		by_suit.get_or_add(hand[i].suit, []).append(i)
	for suit: int in by_suit:
		if by_suit[suit].size() == 4:
			for i in 5:
				if not i in by_suit[suit]:
					return [i]
	for skip in 5:
		var rest: Array = []
		for i in 5:
			if i != skip:
				rest.append(values[i])
		rest.sort()
		if rest[3] - rest[0] <= 4 or (rest[3] == 14 and rest[2] <= 5):
			return [skip]
	# 何もなければ、いちばん強いカードだけ残す
	var keep := 0
	for i in 5:
		if values[i] > values[keep]:
			keep = i
	for i in 5:
		if i != keep:
			discards.append(i)
	return discards


## ジョーカーを持っているとき。ジョーカーと、2枚以上そろっている数字は残す。
## そろっている数字がなければ、ジョーカーといちばん強いカードを残す。
func _cpu_discards_with_joker(hand: Array) -> Array:
	var counts := {}
	for card: Card in hand:
		if not card.is_joker():
			counts[_value(card)] = counts.get(_value(card), 0) + 1
	var has_group: bool = counts.values().any(func(n: int) -> bool: return n >= 2)
	var keep_high := -1
	if not has_group:
		for i in 5:
			if not hand[i].is_joker() and (keep_high < 0 or _value(hand[i]) > _value(hand[keep_high])):
				keep_high = i
	var discards: Array = []
	for i in 5:
		var card: Card = hand[i]
		if card.is_joker() or i == keep_high:
			continue
		if has_group and counts[_value(card)] >= 2:
			continue
		discards.append(i)
	return discards


func _finish() -> void:
	var order: Array = [0, 1, 2, 3]
	order.sort_custom(func(a: int, b: int) -> bool: return points[a] > points[b] or (points[a] == points[b] and a < b))
	var lines: Array = []
	var place := 0
	for i in order.size():
		var p: int = order[i]
		if i == 0 or points[p] < points[order[i - 1]]:
			place = i + 1
		lines.append("%d位  %s  %d点" % [place, NAMES[p], points[p]])
	var top: int = points[order[0]]
	if points[0] == top:
		show_result("あなたの勝ち！", lines, true)
	else:
		show_result("%s の勝ち…" % NAMES[order[0]], lines)
