## 选择型事件（docs/18 R-EVENTCHOICE-01；docs/53 M2-5）。
## 事件本身仍然只写主观量（INV-130）：选项只是内容里预填的**普通命令**，命令 17 只留档、不产生任何经济效果。
extends JWTest

const CAMPAIGN: String = "res://content#campaign_1600"


func _game(seed_v: int) -> JWGame:
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_test_choice"
	check(g.new_game(CAMPAIGN, seed_v, 0).ok, "战役开局")
	return g


func _args(v: Array) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(JWCommands.ARG_SLOTS)
	a.fill(0)
	for i: int in v.size():
		a[i] = int(v[i])
	return a


func _advance(g: JWGame) -> JWResult:
	g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, _args([]))
	return g.advance_quarter()


func test_choice_counts_loaded() -> void:
	var st: JWSimState = _game(71).get("_st") as JWSimState
	var n: int = 0
	for e: int in JWUnits.EVENT_N:
		if st.politics.event_choice_count[e] > 0:
			n += 1
			ge_int(st.politics.event_choice_count[e], 2, "选择型事件至少两个选项")
	eq_int(n, 6, "6 条事件带选项")


func test_window_opens_and_choice_recorded() -> void:
	var g: JWGame = _game(72)
	var st: JWSimState = g.get("_st") as JWSimState
	var e: int = -1
	for i: int in JWUnits.EVENT_N:
		if st.politics.event_choice_count[i] > 0:
			e = i
			break
	ge_int(e, 0, "找到一条选择型事件")
	# 夹具：直接开一个待决窗口（等价于该事件在本季触发）。
	st.politics.note_event_fired(e, st.q, 2)
	eq_int(st.politics.event_pending_until_q[e], st.q + 2, "待决窗口到第 q+2 季")
	check(st.politics.has_pending_choice(), "有待决事件")
	g.submit_command(JWCommands.Kind.EVENT_CHOICE, _args([e, 1]))
	check(_advance(g).ok, "推进一季")
	eq_int(st.politics.event_chosen_option[e], 1, "记下选了第 1 个选项")
	eq_int(st.politics.event_pending_until_q[e], -1, "窗口关闭")
	check(not st.politics.has_pending_choice(), "不再有待决事件")


func test_window_expires_without_choosing() -> void:
	var g: JWGame = _game(73)
	var st: JWSimState = g.get("_st") as JWSimState
	var e: int = 0
	while e < JWUnits.EVENT_N and st.politics.event_choice_count[e] <= 0:
		e += 1
	st.politics.note_event_fired(e, st.q, 1)
	for i: int in 3:
		check(_advance(g).ok, "推进第 %d 季" % i)
	eq_int(st.politics.event_pending_until_q[e], -1, "窗口过期自动关闭")
	eq_int(st.politics.event_chosen_option[e], -1, "没选就是没选，不替玩家选")


func test_choice_rejections() -> void:
	var g: JWGame = _game(74)
	var st: JWSimState = g.get("_st") as JWSimState
	var e: int = 0
	while e < JWUnits.EVENT_N and st.politics.event_choice_count[e] <= 0:
		e += 1
	eq_int(st.politics.take_event_choice(e, 0, st.q), JWResult.Reject.PRECONDITION, "没有待决窗口 ⇒ 拒绝")
	st.politics.note_event_fired(e, st.q, 2)
	eq_int(st.politics.take_event_choice(e, 9, st.q), JWResult.Reject.PARAM_RANGE, "选项越界 ⇒ 拒绝")
	var plain: int = 0
	while plain < JWUnits.EVENT_N and st.politics.event_choice_count[plain] > 0:
		plain += 1
	if plain < JWUnits.EVENT_N:
		eq_int(st.politics.take_event_choice(plain, 0, st.q), JWResult.Reject.PRECONDITION,
				"非选择型事件 ⇒ 拒绝")


func test_batch_pauses_on_pending_choice() -> void:
	var g: JWGame = _game(75)
	var st: JWSimState = g.get("_st") as JWSimState
	var e: int = 0
	while e < JWUnits.EVENT_N and st.politics.event_choice_count[e] <= 0:
		e += 1
	st.politics.note_event_fired(e, st.q, 4)
	var r: Dictionary = g.advance_batch(4)
	eq_int(int(r["advanced"]), 1, "有事件等决定 ⇒ 推进一季就停")
	eq_int(int(r["reason"]), JWGame.Pause.EVENT_CHOICE, "暂停原因是「需要选择的事件」")
