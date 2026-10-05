extends GameBase
## ババ抜き。あなた＋CPU3人。自分の番では、ひとつ前の人の手札から1枚引く。

signal human_picked(index: int)

const NAMES := ["あなた", "CPU 1", "CPU 2", "CPU 3"]
const DISCARD_CARD := Vector2(84, 118)

# 配置。よこ画面はCPUを横に3人、たて画面は縦に3段並べる。
var cpu_card := Vector2(64, 90)
var cpu_panel_width := 400.0
var hand_card := Vector2(84, 118)
var hand_per_row := 14
var hand_y := 586.0
var discard_y := 250.0

var hands: Array = [[], [], [], []]
var done := [false, false, false, false]
var out_order: Array[int] = []
var current := 0
var pick_from := -1  # あなたが引ける相手。引けないときは-1

var cpu_layers: Array[Control] = []
var cpu_labels: Array[Label] = []
var hand_layer: Control
var hand_label: Label
var discard_layer: Control


func _ready() -> void:
	setup_base("ババ抜き")
	if portrait:
		cpu_card = Vector2(80, 112)
		cpu_panel_width = 680.0
		hand_card = Vector2(96, 134)
		hand_per_row = 7
		hand_y = 850.0
		discard_y = 530.0
		place_message(Vector2(0, 740), Vector2(screen.x, 44), 22)
	else:
		place_message(Vector2(140, 450), Vector2(1000, 44), 26)

	for p in range(1, 4):
		var pos := Vector2(20, 60 + (p - 1) * 152.0) if portrait else Vector2(20 + (p - 1) * 420.0, 64)
		cpu_labels.append(UI.label(self, "", pos, Vector2(cpu_panel_width, 36), 22))
		var layer := Control.new()
		layer.position = pos + Vector2(0, 38 if portrait else 46)
		add_child(layer)
		cpu_layers.append(layer)
	discard_layer = Control.new()
	add_child(discard_layer)
	hand_label = UI.label(self, "", Vector2(20, 800) if portrait else Vector2(40, 540), Vector2(400, 36), 20,
			HORIZONTAL_ALIGNMENT_LEFT)
	hand_layer = Control.new()
	add_child(hand_layer)

	var deck := Card.make_deck(1)
	for i in deck.size():
		hands[i % 4].append(deck[i])
	_run()


func _run() -> void:
	set_message("カードを配りました。そろっているペアを捨てます")
	_refresh()
	await wait(1.4)
	for p in 4:
		_discard_all_pairs(p)
		if hands[p].is_empty():
			_finish_player(p)
	_refresh()
	await wait(0.8)

	while _active_count() > 1:
		if done[current]:
			current = _next_active(current)
			continue
		var src := _prev_active(current)
		var fast: bool = done[0]
		var index := 0
		if current == 0:
			pick_from = src
			set_message("あなたの番です。%s の手札から1枚引いてください" % NAMES[src])
			_refresh()
			index = await human_picked
			pick_from = -1
		else:
			_refresh()
			await wait(0.15 if fast else 0.8)
			index = randi() % hands[src].size()

		var card: Card = hands[src][index]
		hands[src].remove_at(index)
		hands[current].append(card)
		var partner := _find_partner(current, card)
		var text := _draw_text(current, src, card)
		if partner != null:
			hands[current].erase(card)
			hands[current].erase(partner)
			_show_discard(current, card, partner)
			text += " → %s のペアを捨てた！" % Card.RANK_NAMES[card.rank - 1]
		if current != 0:
			hands[current].shuffle()
		set_message(text)

		if hands[src].is_empty():
			_finish_player(src)
		if hands[current].is_empty():
			_finish_player(current)
		_refresh()
		await wait(0.2 if fast else 1.1)
		current = _next_active(current)

	_finish()


func _draw_text(p: int, src: int, card: Card) -> String:
	if p == 0:
		if card.is_joker():
			return "ジョーカーを引いてしまった…"
		return "あなたは %s を引いた" % card.label()
	if src == 0:
		return "%s があなたの %s を引いた" % [NAMES[p], card.label()]
	return "%s が %s から1枚引いた" % [NAMES[p], NAMES[src]]


func _find_partner(p: int, card: Card) -> Card:
	if card.is_joker():
		return null
	for other: Card in hands[p]:
		if other != card and other.rank == card.rank:
			return other
	return null


func _discard_all_pairs(p: int) -> void:
	var kept: Array = []
	for card: Card in hands[p]:
		var matched := false
		if not card.is_joker():
			for i in kept.size():
				if kept[i].rank == card.rank:
					kept.remove_at(i)
					matched = true
					break
		if not matched:
			kept.append(card)
	hands[p] = kept


func _finish_player(p: int) -> void:
	if done[p]:
		return
	done[p] = true
	out_order.append(p)


func _active_count() -> int:
	return done.count(false)


func _next_active(p: int) -> int:
	for i in range(1, 5):
		var q := (p + i) % 4
		if not done[q]:
			return q
	return p


func _prev_active(p: int) -> int:
	for i in range(1, 4):
		var q := (p - i + 4) % 4
		if not done[q]:
			return q
	return p


func _on_cpu_card_pressed(p: int, index: int) -> void:
	if pick_from != p:
		return
	human_picked.emit(index)


func _show_discard(p: int, a: Card, b: Card) -> void:
	UI.clear_children(discard_layer)
	var cx := screen.x / 2.0
	UI.label(discard_layer, "%s が捨てたペア" % NAMES[p], Vector2(cx - 200, discard_y), Vector2(400, 36), 20)
	var cards := [a, b]
	for i in 2:
		var view := CardView.new()
		discard_layer.add_child(view)
		view.setup(cards[i], DISCARD_CARD)
		view.position = Vector2(cx - DISCARD_CARD.x - 4 + i * (DISCARD_CARD.x + 8), discard_y + 44)


func _refresh() -> void:
	for p in range(1, 4):
		var layer := cpu_layers[p - 1]
		var lbl := cpu_labels[p - 1]
		UI.clear_children(layer)
		var count: int = hands[p].size()
		if done[p]:
			lbl.text = "%s  あがり（%d位）" % [NAMES[p], out_order.find(p) + 1]
		elif pick_from == p:
			lbl.text = "▼ %s  ここから1枚引く" % NAMES[p]
		else:
			lbl.text = "%s%s  残り%d枚" % ["▶ " if p == current else "", NAMES[p], count]
		lbl.modulate = Color.YELLOW if (pick_from == p or (p == current and not done[p])) else Color.WHITE

		var step := minf(cpu_card.x + 4, (cpu_panel_width - cpu_card.x) / maxf(count - 1, 1))
		var start_x := (cpu_panel_width - (step * (count - 1) + cpu_card.x)) / 2.0
		for i in count:
			var view := CardView.new()
			layer.add_child(view)
			view.setup(hands[p][i], cpu_card, false)
			view.position = Vector2(start_x + i * step, 0)
			view.set_clickable(pick_from == p)
			view.set_dimmed(pick_from >= 0 and pick_from != p)
			view.pressed.connect(_on_cpu_card_pressed.bind(p, i))

	UI.clear_children(hand_layer)
	var hand: Array = hands[0]
	hand.sort_custom(func(a: Card, b: Card) -> bool: return a.order() < b.order())
	if done[0]:
		hand_label.text = "あなた  あがり（%d位）" % (out_order.find(0) + 1)
	else:
		hand_label.text = "あなたの手札  %d枚" % hand.size()
	var positions := UI.row_positions(hand.size(), hand_per_row, hand_card, hand_y)
	for i in hand.size():
		var view := CardView.new()
		hand_layer.add_child(view)
		view.setup(hand[i], hand_card)
		view.position = positions[i]


func _finish() -> void:
	var loser := done.find(false)
	pick_from = -1
	current = -1
	_refresh()
	var lines: Array = []
	for i in out_order.size():
		lines.append("%d位  %s" % [i + 1, NAMES[out_order[i]]])
	lines.append("負け  %s（ジョーカー）" % NAMES[loser])
	if loser == 0:
		show_result("ババが残った…", lines)
	else:
		show_result("あなたは %d位！" % (out_order.find(0) + 1), lines)
