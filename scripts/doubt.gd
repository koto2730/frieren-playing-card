extends GameBase
## ダウト。あなた＋CPU3人。A→2→…→K→A の順に、その数字として1〜4枚を裏向きで出す（うそでもよい）。
## うそだと思ったら「ダウト！」。うそなら出した人が、本当ならダウトした人が場のカードを全部引き取る。
## 最初に手札がなくなった人の勝ち。

signal human_played(cards: Array)
signal doubt_decided(doubt: bool)

const NAMES := ["あなた", "CPU 1", "CPU 2", "CPU 3"]
const MAX_PLAY := 4
const DOUBT_WINDOW := 2.5  # ほかの人が出したあと、ダウトできる時間（秒）

# 配置。よこ画面はCPUを横に3人、たて画面は縦に3段並べる。
var cpu_card := Vector2(64, 90)
var cpu_panel_width := 400.0
var hand_card := Vector2(84, 118)
var hand_y := 586.0
var pile_center := Vector2(640, 300)
var pile_card := Vector2(84, 118)

var hands: Array = [[], [], [], []]
var pile: Array = []
var number := 1
var current := 0
var selected: Array = []
var input_enabled := false
var doubt_open := false
var doubt_window_id := 0
var revealing := 0  # 表にして見せている枚数（その分は場の束から外して描く）

var cpu_layers: Array[Control] = []
var cpu_labels: Array[Label] = []
var hand_layer: Control
var hand_label: Label
var pile_layer: Control
var pile_label: Label
var number_label: Label
var reveal_layer: Control
var play_button: Button
var doubt_button: Button
var pass_button: Button
var timer_bar: ColorRect
var timer_tween: Tween
var hand_views := {}  # Card -> CardView


func _ready() -> void:
	setup_base("ダウト")
	var number_box_pos := Vector2(290, 245)
	var bar_rect := Rect2(960, 472, 300, 8)
	if portrait:
		cpu_card = Vector2(80, 112)
		cpu_panel_width = 680.0
		hand_card = Vector2(96, 134)
		hand_y = 876.0
		pile_center = Vector2(440, 610)
		number_box_pos = Vector2(70, 556)
		bar_rect = Rect2(60, 820, 600, 8)
		place_message(Vector2(0, 706), Vector2(screen.x, 40), 22)
	else:
		place_message(Vector2(40, 420), Vector2(900, 40), 24)

	for p in range(1, 4):
		var pos := Vector2(20, 60 + (p - 1) * 152.0) if portrait else Vector2(20 + (p - 1) * 420.0, 64)
		cpu_labels.append(UI.label(self, "", pos, Vector2(cpu_panel_width, 36), 22))
		var layer := Control.new()
		layer.position = pos + Vector2(0, 38 if portrait else 46)
		add_child(layer)
		cpu_layers.append(layer)

	var number_box := UI.panel(self, number_box_pos, Vector2(150, 110))
	UI.label(number_box, "いまの数字", Vector2(0, 6), Vector2(150, 24), 16)
	number_label = UI.label(number_box, "", Vector2(0, 30), Vector2(150, 74), 56)
	pile_layer = Control.new()
	add_child(pile_layer)
	pile_label = UI.label(self, "", Vector2(pile_center.x - 100, pile_center.y + pile_card.y / 2.0 + 4),
			Vector2(200, 30), 18)
	reveal_layer = Control.new()
	reveal_layer.z_index = FX_Z - 1
	add_child(reveal_layer)

	hand_label = UI.label(self, "", Vector2(20, 836) if portrait else Vector2(40, 516), Vector2(400, 36), 20,
			HORIZONTAL_ALIGNMENT_LEFT)
	hand_layer = Control.new()
	add_child(hand_layer)

	if portrait:
		play_button = UI.button(self, "", Vector2(210, 754), Vector2(300, 60), 26, _on_play)
		doubt_button = UI.button(self, "ダウト！", Vector2(60, 754), Vector2(290, 60), 28, _on_doubt.bind(true))
		pass_button = UI.button(self, "スルー", Vector2(370, 754), Vector2(290, 60), 26, _on_doubt.bind(false))
	else:
		play_button = UI.button(self, "", Vector2(980, 410), Vector2(270, 56), 26, _on_play)
		doubt_button = UI.button(self, "ダウト！", Vector2(960, 410), Vector2(150, 56), 26, _on_doubt.bind(true))
		pass_button = UI.button(self, "スルー", Vector2(1120, 410), Vector2(140, 56), 24, _on_doubt.bind(false))
	doubt_button.add_theme_color_override("font_color", Color("ffd84a"))
	timer_bar = ColorRect.new()
	timer_bar.color = Color("ffd84a")
	timer_bar.position = bar_rect.position
	timer_bar.size = bar_rect.size
	add_child(timer_bar)
	_show_buttons(false, false)
	_run()


func _run() -> void:
	await _deal()
	while true:
		_refresh()
		var cards: Array
		if current == 0:
			cards = await _human_turn()
		else:
			cards = await _cpu_turn(current)
		await _play_cards(current, cards)

		var caller := await _doubt_phase(current, cards.size())
		if caller >= 0:
			await _resolve_doubt(caller, current, cards)
		if hands[current].is_empty():
			break
		number = number % 13 + 1
		current = (current + 1) % 4
	_finish(current)


func _deal() -> void:
	var deck := Card.make_deck()
	for i in deck.size():
		hands[i % 4].append(deck[i])
	_sort_hand()
	set_message("カードを配ります")
	_refresh_labels()
	show_deck(pile_center, pile_card)
	var positions: Array = []
	for p in 4:
		positions.append(_card_positions(p))
	var items: Array = []
	for i in 13:
		for p in 4:
			items.append({"card": hands[p][i], "to": positions[p][i], "size": _card_size(p), "face_up": p == 0})
	# 配っている間は手札を出さない
	var dealt := hands
	hands = [[], [], [], []]
	await deal_cards(items, 0.03)
	hands = dealt
	hide_deck()
	_refresh()
	set_message("A から順に出していきます")
	await wait(0.8)


func _human_turn() -> Array:
	selected.clear()
	set_message("「%s」として出すカードを選んでください（うそでもOK）" % _rank_name(number))
	input_enabled = true
	_update_play_button()
	_show_buttons(true, false)
	_refresh()
	var cards: Array = await human_played
	input_enabled = false
	_show_buttons(false, false)
	return cards


func _cpu_turn(p: int) -> Array:
	set_message("%s の番です" % NAMES[p])
	await wait(0.7)
	var honest: Array = hands[p].filter(func(c: Card) -> bool: return c.rank == number)
	if not honest.is_empty():
		var cards := honest.duplicate()
		# たまに本物にうそを1枚まぜる
		if cards.size() < MAX_PLAY and hands[p].size() > cards.size() and randf() < 0.2:
			cards.append(_far_card(p, cards))
		return cards
	# 持っていないので、しばらく出番が来ない数字のカードでうそをつく
	return [_far_card(p, [])]


## 次に出番が来るまでいちばん遠い数字のカード。
func _far_card(p: int, exclude: Array) -> Card:
	var best: Card = null
	var best_distance := -1
	for card: Card in hands[p]:
		if card in exclude:
			continue
		var distance := (card.rank - number + 13) % 13
		if distance > best_distance:
			best_distance = distance
			best = card
	return best


func _cpu_wants_doubt(q: int, player: int, count: int) -> bool:
	var have: int = hands[q].filter(func(c: Card) -> bool: return c.rank == number).size()
	if have + count > 4:
		return true  # 同じ数字は4枚しかないので、確実にうそ
	var chance := 0.08 + 0.12 * (count - 1) + 0.08 * have
	if hands[player].size() <= 2:
		chance += 0.3  # あがりそうなら止めにいく
	return randf() < chance


## ほかの人がダウトするかを決める。あなたは出した人でなければ、まず先に選べる。
func _doubt_phase(player: int, count: int) -> int:
	if player != 0:
		set_message("%s が「%s」を%d枚出した。ダウトする？" % [NAMES[player], _rank_name(number), count])
		doubt_window_id += 1
		doubt_open = true
		_show_buttons(false, true)
		timer_bar.size.x = _timer_width()
		timer_tween = timer_bar.create_tween()
		timer_tween.tween_property(timer_bar, "size:x", 0.0, DOUBT_WINDOW)
		get_tree().create_timer(DOUBT_WINDOW).timeout.connect(_on_doubt_timeout.bind(doubt_window_id))
		var doubt: bool = await doubt_decided
		doubt_open = false
		timer_tween.kill()
		_show_buttons(false, false)
		if doubt:
			return 0
	else:
		set_message("あなたは「%s」を%d枚出した" % [_rank_name(number), count])
		await wait(0.6)
	for k in range(1, 4):
		var q := (player + k) % 4
		if q != 0 and _cpu_wants_doubt(q, player, count):
			return q
	return -1


func _resolve_doubt(caller: int, player: int, cards: Array) -> void:
	set_message("%s「ダウト！」" % NAMES[caller])
	await _pop_doubt_text()
	# 出したカードを表にして見せる。そのカードは場の束からは外して描く
	revealing = cards.size()
	_refresh()
	UI.clear_children(reveal_layer)
	for i in cards.size():
		var view := CardView.new()
		reveal_layer.add_child(view)
		view.setup(cards[i], pile_card, false)
		view.position = pile_center - pile_card / 2.0 + Vector2((i - (cards.size() - 1) / 2.0) * (pile_card.x + 6), 0)
		view.flip(true)
	await wait(1.0)
	var truthful := cards.all(func(c: Card) -> bool: return c.rank == number)
	var taker := caller if truthful else player
	if truthful:
		set_message("本当に「%s」だった！ %s が場の%d枚を引き取る" % [_rank_name(number), NAMES[taker], pile.size()])
	else:
		set_message("うそだった！ %s が場の%d枚を引き取る" % [NAMES[taker], pile.size()])
	await wait(1.6)
	UI.clear_children(reveal_layer)
	revealing = 0
	_refresh()

	# 場のカードが引き取る人のところへ飛んでいく
	var goal := _seat_goal(taker)
	var shown := mini(pile.size(), 8)
	for i in shown:
		fly_card(pile[i], pile_center - pile_card / 2.0, goal, pile_card, _card_size(taker), false, 0.3)
		await wait(0.05)
	var taken := pile.duplicate()
	pile.clear()
	_refresh()
	await wait(0.35)
	hands[taker].append_array(taken)
	if taker == 0:
		_sort_hand()
	_refresh()
	await wait(0.4)


func _pop_doubt_text() -> void:
	var text := UI.outline(UI.label(self, "ダウト！", pile_center - Vector2(200, 150), Vector2(400, 90), 64), 14)
	text.modulate = Color("ffd84a")
	text.z_index = FX_Z + 2
	text.pivot_offset = text.size / 2.0
	text.scale = Vector2(0.4, 0.4)
	var tween := text.create_tween()
	tween.tween_property(text, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.5)
	tween.tween_property(text, "modulate:a", 0.0, 0.25)
	tween.tween_callback(text.queue_free)
	await tween.finished


## 手札から場へ、裏向きでカードを飛ばす。
func _play_cards(p: int, cards: Array) -> void:
	var froms: Array = []
	for card: Card in cards:
		froms.append(_card_origin(p, card))
	for card: Card in cards:
		hands[p].erase(card)
	selected.clear()
	_refresh()
	for i in cards.size():
		var to := pile_center - pile_card / 2.0 + Vector2(randf_range(-6, 6), randf_range(-6, 6))
		fly_card(cards[i], froms[i], to, _card_size(p), pile_card, false, 0.3)
		await wait(0.08)
	await wait(0.3)
	pile.append_array(cards)
	_refresh()


func _card_origin(p: int, card: Card) -> Vector2:
	if p == 0 and hand_views.has(card):
		return hand_views[card].position
	var index: int = hands[p].find(card)
	return _card_positions(p)[maxi(index, 0)]


func _seat_goal(p: int) -> Vector2:
	if p == 0:
		return Vector2(screen.x / 2.0 - hand_card.x / 2.0, hand_y)
	var layer := cpu_layers[p - 1]
	return layer.position + Vector2(cpu_panel_width / 2.0 - cpu_card.x / 2.0, 0)


func _card_size(p: int) -> Vector2:
	return hand_card if p == 0 else cpu_card


## p の手札が今の枚数のときの各カードの位置。枚数が多いときは重ねて並べる。
func _card_positions(p: int) -> Array[Vector2]:
	var count: int = hands[p].size()
	var positions: Array[Vector2] = []
	if p == 0:
		var rows := 2 if portrait and count > 7 else 1
		var per_row := ceili(count / float(rows))
		var step := minf(hand_card.x + 4, (screen.x - 40 - hand_card.x) / maxf(per_row - 1, 1))
		for i in count:
			@warning_ignore("integer_division")
			var row := i / per_row
			var in_row := mini(per_row, count - row * per_row)
			var start_x := (screen.x - (step * (in_row - 1) + hand_card.x)) / 2.0
			positions.append(Vector2(start_x + (i % per_row) * step, hand_y + row * (hand_card.y + 8)))
		return positions
	var cpu_step := minf(cpu_card.x + 4, (cpu_panel_width - cpu_card.x) / maxf(count - 1, 1))
	var cpu_start := (cpu_panel_width - (cpu_step * (count - 1) + cpu_card.x)) / 2.0
	for i in count:
		positions.append(cpu_layers[p - 1].position + Vector2(cpu_start + i * cpu_step, 0))
	return positions


func _sort_hand() -> void:
	hands[0].sort_custom(func(a: Card, b: Card) -> bool: return a.order() < b.order())


func _rank_name(rank: int) -> String:
	return Card.RANK_NAMES[rank - 1]


func _on_hand_card(card: Card) -> void:
	if not input_enabled:
		return
	if card in selected:
		selected.erase(card)
	elif selected.size() < MAX_PLAY:
		selected.append(card)
	_update_play_button()
	_refresh()


func _on_play() -> void:
	if input_enabled and not selected.is_empty():
		human_played.emit(selected.duplicate())


func _on_doubt(doubt: bool) -> void:
	if doubt_open:
		doubt_decided.emit(doubt)


func _on_doubt_timeout(window_id: int) -> void:
	if doubt_open and window_id == doubt_window_id:
		doubt_decided.emit(false)


func _update_play_button() -> void:
	play_button.text = "%d枚出す" % selected.size() if not selected.is_empty() else "カードを選んでね"
	play_button.disabled = selected.is_empty()


func _show_buttons(play: bool, doubt: bool) -> void:
	play_button.visible = play
	doubt_button.visible = doubt
	pass_button.visible = doubt
	timer_bar.visible = doubt


func _timer_width() -> float:
	return 600.0 if portrait else 300.0


func _refresh() -> void:
	_refresh_labels()
	for p in range(1, 4):
		var layer := cpu_layers[p - 1]
		UI.clear_children(layer)
		var positions := _card_positions(p)
		for i in hands[p].size():
			var view := CardView.new()
			layer.add_child(view)
			view.setup(hands[p][i], cpu_card, false)
			view.position = positions[i] - layer.position

	UI.clear_children(hand_layer)
	hand_views.clear()
	var positions := _card_positions(0)
	for i in hands[0].size():
		var card: Card = hands[0][i]
		var view := CardView.new()
		hand_layer.add_child(view)
		view.setup(card, hand_card)
		view.position = positions[i] - Vector2(0, 22 if card in selected else 0)
		view.set_clickable(input_enabled)
		view.pressed.connect(_on_hand_card.bind(card))
		hand_views[card] = view

	UI.clear_children(pile_layer)
	for i in mini(pile.size() - revealing, 6):
		var view := CardView.new()
		pile_layer.add_child(view)
		view.setup(null, pile_card, false)
		view.position = pile_center - pile_card / 2.0 - Vector2(i * 2, i * 2)
	pile_label.text = "場 %d枚" % pile.size() if not pile.is_empty() else ""
	number_label.text = _rank_name(number)


func _refresh_labels() -> void:
	for p in range(1, 4):
		var lbl := cpu_labels[p - 1]
		lbl.text = "%s%s  残り%d枚" % ["▶ " if p == current else "", NAMES[p], hands[p].size()]
		lbl.modulate = Color.YELLOW if p == current else Color.WHITE
	hand_label.text = "%sあなたの手札  %d枚" % ["▶ " if current == 0 else "", hands[0].size()]
	hand_label.modulate = Color.YELLOW if current == 0 else Color.WHITE


func _finish(winner: int) -> void:
	_refresh()
	var order: Array = [0, 1, 2, 3]
	order.erase(winner)
	order.sort_custom(func(a: int, b: int) -> bool: return hands[a].size() < hands[b].size())
	order.push_front(winner)
	var lines: Array = []
	for i in order.size():
		var p: int = order[i]
		lines.append("%d位  %s%s" % [i + 1, NAMES[p], "（あがり）" if p == winner else "（残り%d枚）" % hands[p].size()])
	if winner == 0:
		show_result("あなたの勝ち！", lines, true)
	else:
		show_result("%s の勝ち…" % NAMES[winner], lines)
