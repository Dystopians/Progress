## 研究与科技（docs/18 R-RESEARCH-01；docs/53 M2-1）。
extends JWTest

const CAMPAIGN: String = "res://content#campaign_1600"


func _game(spec: String, seed_v: int) -> JWGame:
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_test_research"
	check(g.new_game(spec, seed_v, 0).ok, "开局 " + spec)
	return g


func _advance(g: JWGame) -> JWResult:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(JWCommands.ARG_SLOTS)
	a.fill(0)
	g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, a)
	return g.advance_quarter()


func _focus(g: JWGame, t: int) -> void:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(JWCommands.ARG_SLOTS)
	a.fill(0)
	a[JWCommands.SLOT_TECH] = t
	g.submit_command(JWCommands.Kind.SET_RESEARCH_FOCUS, a)


func test_tech_cards_loaded_and_topological() -> void:
	var g: JWGame = _game(CAMPAIGN, 31)
	var r: JWResearch = (g.get("_st") as JWSimState).research
	eq_int(r.enabled, 1, "战役剧本启用研究")
	eq_int(r.tech_count, 8, "载入 8 张占位科技卡")
	for t: int in r.tech_count:
		ge_int(r.cost[t], 1, "科技 %d 有正的研究成本" % t)
		# 前置只能指向更靠前的科技（下标即拓扑序，无环）。
		check(r.prereq_mask[t] < (1 << t), "科技 %d 的前置都在它之前" % t)
	check(r.is_available(0), "无前置的科技开局即可研究")
	check(not r.is_available(1), "有前置的科技开局不可研究")


func test_points_come_from_education_and_high_skill() -> void:
	var g: JWGame = _game(CAMPAIGN, 32)
	var st: JWSimState = g.get("_st") as JWSimState
	var r: JWResearch = st.research
	eq_int(r.points_of(0, 0), 0, "没有教育交付也没有高技能在业 ⇒ 没有研究点")
	eq_int(r.points_of(1_000_000, 0), JWMath.mul_ppm(1_000_000, r.points_per_edu_ppm), "教育项按系数折算")
	check(_advance(g).ok, "推进一季")
	ge_int(st.research.f_points_gained, 1, "实际结算一季后确有研究点（%d）" % st.research.f_points_gained)
	eq_int(st.research.points_pool, st.research.f_points_gained, "没有方向时点数进池子，不浪费")


func test_focus_progress_and_completion_unlocks_successor() -> void:
	var g: JWGame = _game(CAMPAIGN, 33)
	var st: JWSimState = g.get("_st") as JWSimState
	var r: JWResearch = st.research
	_focus(g, 0)
	check(_advance(g).ok, "推进一季（已设方向）")
	eq_int(r.focus, 0, "方向已设定")
	ge_int(r.progress[0], 1, "进度开始累积")
	eq_int(r.points_pool, 0, "有方向时池子清空投入该方向")
	check(r.progress[0] < r.cost[0], "一季远不足以研完一项（成本按五十年切片标定）")
	# 直接把进度推到成本前一点，下一季必然完成（夹具：只改进度，不改规则）。
	r.progress[0] = r.cost[0] - 1
	check(_advance(g).ok, "推进一季（完成季）")
	eq_int(r.status[0], JWResearch.ST_DONE, "科技 0 完成")
	eq_int(r.focus, JWResearch.NO_FOCUS, "完成后方向清空，等玩家再选")
	check((r.completed_mask & 1) == 1, "完成位图置位")
	eq_int(r.status[1], JWResearch.ST_AVAILABLE, "后继科技变为可研究")
	check(r.is_available(1), "后继前置已满足")
	ge_int(r.points_pool, 0, "超出成本的点数留在池子里（不浪费）")


func test_focus_command_rejections() -> void:
	var g: JWGame = _game(CAMPAIGN, 34)
	var st: JWSimState = g.get("_st") as JWSimState
	eq_int(st.research.set_focus(1), JWResult.Reject.PRECONDITION, "前置未完成 ⇒ 拒绝")
	eq_int(st.research.set_focus(99), JWResult.Reject.NOT_FOUND, "不存在的科技 ⇒ 拒绝")
	eq_int(st.research.set_focus(0), JWResult.OK, "可研究 ⇒ 受理")
	eq_int(st.research.set_focus(JWResearch.NO_FOCUS), JWResult.OK, "撤销方向 ⇒ 受理")
	eq_int(st.research.focus, JWResearch.NO_FOCUS, "方向已撤销")


func test_term_mode_has_no_research() -> void:
	var g: JWGame = _game("res://content", 35)
	var st: JWSimState = g.get("_st") as JWSimState
	eq_int(st.research.enabled, 0, "旧剧本不启用研究")
	check(_advance(g).ok, "推进一季")
	eq_int(st.research.f_points_gained, 0, "旧剧本没有研究点")
	eq_int(st.research.set_focus(0), JWResult.Reject.PRECONDITION, "旧剧本设方向被拒")


func test_research_survives_save_load() -> void:
	var g: JWGame = _game(CAMPAIGN, 36)
	var st: JWSimState = g.get("_st") as JWSimState
	_focus(g, 0)
	check(_advance(g).ok, "推进一季")
	var prog: int = st.research.progress[0]
	check(g.save_game("test_research").ok, "存档")
	var h: JWGame = JWGame.new()
	h.autosave_slot = "autosave_test_research2"
	check(h.new_game(CAMPAIGN, 99, 0).ok, "另开一局")
	check(h.load_game("test_research").ok, "读档")
	var st2: JWSimState = h.get("_st") as JWSimState
	eq_int(st2.research.progress[0], prog, "研究进度随存档往返")
	eq_int(st2.research.focus, 0, "研究方向随存档往返")
