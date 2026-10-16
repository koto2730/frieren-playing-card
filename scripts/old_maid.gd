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
var cards_visible := false  # 配り終わるまでは手札を出さない
var card_views: Array = [[], [], [], []]

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

	_run()


func _deal() -> void:
	var deck := Card.make_deck(1)
	for i in deck.size():
		hands[i % 4].append(deck[i])
	hands[0].sort_custom(func(a: Card, b: Card) -> bool: return a.order() < b.order())

	# 山札から1枚ずつ順番に配る
	set_message("カードを配ります")
	_refresh()
	show_deck(Vector2(screen.x / 2.0, discard_y + 44 + DISCARD_CARD.y / 2.0), DISCARD_CARD)
	var positions: Array = []
	for p in 4:
		positions.append(_card_positions(p))
	var items: Array = []
	for i in hands[0].size():
		for p in 4:
			if i < hands[p].size():
				items.append({"card": hands[p][i], "to": positions[p][i], "size": _card_size(p), "face_up": p == 0})
	await deal_cards(items, 0.03)
	hide_deck()
	cards_visible = true
	_refresh()


func _run() -> void:
	await _deal()
	set_message("そろっているペアを捨てます")
	await wait(1.2)
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
			set_message("%s が %s の手札から選んでいます…" % [NAMES[current], NAMES[src]])
			_refresh()
			index = await _cpu_think(src, fast)

		# 引いたカードが相手の手札から自分の手札へ移動する
		var card: Card = hands[src][index]
		var from: Vector2 = _card_positions(src)[index]
		hands[src].remove_at(index)
		_refresh()
		var landing := _card_positions(current, hands[current].size() + 1)
		await fly_card(card, from, landing[landing.size() - 1], _card_size(src), _card_size(current),
				current == 0 or src == 0, 0.12 if fast else 0.35)
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


## CPUがどれを引くか迷う演出。カードの上をカーソルが行ったり来たりしてから1枚に決める。
func _cpu_think(src: int, fast: bool) -> int:
	var count: int = hands[src].size()
	var chosen := randi() % count
	if fast:
		await wait(0.15)
		return chosen

	var positions := _card_positions(src)
	var views: Array = card_views[src]
	var spot := Vector2(_visible_width(src) / 2.0, _card_size(src).y * 0.4)
	# いくつか寄り道してから、最後に選ぶカードへ
	var stops: Array[int] = []
	if count > 1:
		for i in randi_range(2, 4):
			var candidate := randi() % count
			if not stops.is_empty() and candidate == stops[stops.size() - 1]:
				candidate = (candidate + 1) % count
			stops.append(candidate)
	stops.append(chosen)

	var cursor := _make_cursor()
	var mark: Label = cursor.get_node("Mark")
	cursor.position = positions[stops[0]] + spot + Vector2(0, -50)
	for n in stops.size():
		var index := stops[n]
		var target: Vector2 = positions[index] + spot
		var move := cursor.create_tween()
		move.tween_property(cursor, "position", target, 0.26).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await move.finished
		_lift(views, index, true)
		if n < stops.size() - 1:
			# うーん、と小さく揺れて迷う
			var hesitate := cursor.create_tween()
			hesitate.tween_property(cursor, "position:x", target.x + 6, 0.08)
			hesitate.tween_property(cursor, "position:x", target.x - 6, 0.12)
			hesitate.tween_property(cursor, "position:x", target.x, 0.08)
			hesitate.tween_interval(randf_range(0.1, 0.4))
			await hesitate.finished
			_lift(views, index, false)
		else:
			# これ！と押し込む
			await wait(0.3)
			mark.text = "！"
			var press := cursor.create_tween()
			press.tween_property(cursor, "position:y", target.y + 10, 0.08)
			press.tween_property(cursor, "position:y", target.y, 0.1)
			await press.finished
			await wait(0.15)
	cursor.queue_free()
	return chosen


func _make_cursor() -> Control:
	var cursor := Control.new()
	cursor.z_index = FX_Z + 5
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cursor)
	# 下向きの矢印。先端が (0, 0)
	var shape := PackedVector2Array([
		Vector2(-8, -56), Vector2(8, -56), Vector2(8, -28), Vector2(20, -28),
		Vector2(0, 0), Vector2(-20, -28), Vector2(-8, -28),
	])
	var arrow := Polygon2D.new()
	arrow.polygon = shape
	arrow.color = Color.YELLOW
	cursor.add_child(arrow)
	var edge := Line2D.new()
	edge.points = shape
	edge.closed = true
	edge.width = 3.0
	edge.default_color = Color(0.1, 0.1, 0.1)
	cursor.add_child(edge)
	var mark := UI.outline(UI.label(cursor, "？", Vector2(14, -74), Vector2(40, 40), 30), 10)
	mark.name = "Mark"
	mark.modulate = Color.YELLOW
	return cursor


func _lift(views: Array, index: int, up: bool) -> void:
	if index >= views.size() or not is_instance_valid(views[index]):
		return
	var view: CardView = views[index]
	var base_y: float = view.get_meta("base_y")
	view.create_tween().tween_property(view, "position:y", base_y - 14.0 if up else base_y, 0.1)


func _card_size(p: int) -> Vector2:
	return hand_card if p == 0 else cpu_card


## p の手札が count 枚のときの、各カードの位置（画面上の左上座標）。
func _card_positions(p: int, count: int = -1) -> Array[Vector2]:
	if count < 0:
		count = hands[p].size()
	if p == 0:
		return UI.row_positions(count, hand_per_row, hand_card, hand_y)
	var positions: Array[Vector2] = []
	var step := _cpu_step(count)
	var start_x := (cpu_panel_width - (step * (count - 1) + cpu_card.x)) / 2.0
	for i in count:
		positions.append(cpu_layers[p - 1].position + Vector2(start_x + i * step, 0))
	return positions


func _cpu_step(count: int) -> float:
	return minf(cpu_card.x + 4, (cpu_panel_width - cpu_card.x) / maxf(count - 1, 1))


## 重なって並んでいるとき、1枚あたり見えている幅。
func _visible_width(p: int) -> float:
	return hand_card.x if p == 0 else minf(cpu_card.x, _cpu_step(hands[p].size()))


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

		card_views[p] = []
		var cpu_positions := _card_positions(p)
		for i in (count if cards_visible else 0):
			var view := CardView.new()
			layer.add_child(view)
			view.setup(hands[p][i], cpu_card, false)
			view.position = cpu_positions[i] - layer.position
			view.set_meta("base_y", view.position.y)
			card_views[p].append(view)
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
	card_views[0] = []
	var positions := _card_positions(0)
	for i in (hand.size() if cards_visible else 0):
		var view := CardView.new()
		hand_layer.add_child(view)
		view.setup(hand[i], hand_card)
		view.position = positions[i]
		view.set_meta("base_y", view.position.y)
		card_views[0].append(view)


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
		show_result("あなたは %d位！" % (out_order.find(0) + 1), lines, out_order.find(0) == 0)
