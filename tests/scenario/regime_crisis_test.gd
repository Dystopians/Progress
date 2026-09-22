## 战役模式的国家延续（docs/18 R-REGIME-01、R-CRISIS-01、R-LABOR-SHRINK-01；docs/53 M1-6/M1-7）。
extends JWTest

const CAMPAIGN: String = "res://content#campaign_1600"


func _game(spec: String, seed_v: int) -> JWGame:
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_test_regime"
	check(g.new_game(spec, seed_v, 0).ok, "开局 " + spec)
	return g


func _advance(g: JWGame) -> JWResult:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(JWCommands.ARG_SLOTS)
	a.fill(0)
	g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, a)
	return g.advance_quarter()


func test_track_escalates_fast_recovers_slow() -> void:
	var c: JWCrisis = JWCrisis.new()
	c.allocate()
	c.final_window_q = 3
	check(not c.step_track(0, 2, 10), "升级不终局")
	eq_int(c.stage[0], 2, "目标 2 ⇒ 直接跳到危机")
	c.step_track(0, 0, 11)
	eq_int(c.stage[0], 1, "目标回到 0 ⇒ 每季只降一级")
	c.step_track(0, 3, 12)
	eq_int(c.stage[0], 3, "进入最后补救窗口")
	check(not c.step_track(0, 3, 13), "窗口未满")
	check(not c.step_track(0, 3, 14), "窗口未满")
	check(c.step_track(0, 3, 15), "窗口届满且条件仍在 ⇒ 终局")
	var d: JWCrisis = JWCrisis.new()
	d.allocate()
	d.final_window_q = 3
	d.step_track(0, 3, 0)
	check(not d.step_track(0, 2, 5), "窗口期内条件缓解 ⇒ 降级，不终局")
	eq_int(d.stage[0], 2, "降到危机")


func test_fiscal_target_mapping() -> void:
	eq_int(JWCrisis.fiscal_target(0, 2, 0, 100, 0, 4), 0, "无事")
	eq_int(JWCrisis.fiscal_target(1, 2, 0, 100, 0, 4), 1, "审查失败一次 ⇒ 预警")
	eq_int(JWCrisis.fiscal_target(0, 2, 101, 100, 0, 4), 1, "欠付超限 ⇒ 预警")
	eq_int(JWCrisis.fiscal_target(2, 2, 0, 100, 0, 4), 2, "审查连败到失去资格 ⇒ 危机")
	eq_int(JWCrisis.fiscal_target(0, 2, 0, 100, 1, 4), 2, "付不出第 1 档 ⇒ 危机")
	eq_int(JWCrisis.fiscal_target(0, 2, 0, 100, 4, 4), 3, "连续违约达宽限期 ⇒ 最后补救窗口")


func test_lost_election_changes_government_not_game() -> void:
	var g: JWGame = _game(CAMPAIGN, 21)
	var st: JWSimState = g.get("_st") as JWSimState
	eq_int(st.crisis.enabled, 1, "战役剧本启用国家延续规则")
	# 夹具：选举前一季把支持度基准压到 0，本季选举必然落选。
	for q: int in 15:
		check(_advance(g).ok, "推进到选举前")
	var debt0: int = st.bonds.debt_outstanding()
	var term0: int = st.politics.term_index
	# 支持度在 S08 以基准为起点重算，直接写 support 会被覆盖；压低基准才能让本季选举必然落选。
	for gi: int in JWUnits.GROUP:
		st.politics.base_support[gi] = 0
	var r: JWResult = _advance(g)
	check(r.ok, "选举季推进成功（落选不终局）")
	check(not st.politics.run_terminated, "国家延续")
	eq_int(st.crisis.gov_changes, 1, "政府更替一次")
	check(st.politics.seats_gov * 2 > st.politics.seats_total, "新政府取得过半席位")
	eq_int(st.politics.term_index, term0 + 1, "进入新一届")
	eq_int(st.politics.next_election_q, 15 + st.crisis.election_period_q, "下次选举按周期排定")
	eq_int(st.bonds.debt_outstanding(), debt0 + st.treasury.f_new_borrowing - st.treasury.f_principal_paid
			- st.treasury.f_writeoffs, "更替不清债：债务按本季流量正常变动")
	eq_int(st.politics.support[0], st.politics.base_support[0], "各组支持度回到基年水平")


func test_term_mode_still_terminates_on_lost_election() -> void:
	var g: JWGame = _game("res://content", 21)
	var st: JWSimState = g.get("_st") as JWSimState
	eq_int(st.crisis.enabled, 0, "旧剧本不启用")
	for q: int in 15:
		_advance(g)
	# 支持度在 S08 以基准为起点重算，直接写 support 会被覆盖；压低基准才能让本季选举必然落选。
	for gi: int in JWUnits.GROUP:
		st.politics.base_support[gi] = 0
	_advance(g)
	check(st.politics.run_terminated, "旧剧本落选即终局（规则不变）")
	eq_int(st.politics.termination_reason, JWUnits.Termination.LOST_ELECTION, "终局原因：落选")


func test_legitimacy_collapse_after_final_window() -> void:
	var g: JWGame = _game(CAMPAIGN, 22)
	var st: JWSimState = g.get("_st") as JWSimState
	var window: int = st.crisis.final_window_q
	var ended_q: int = -1
	for q: int in window + 4:
		for gi: int in JWUnits.GROUP:
			st.politics.trust[gi] = 0
		var r: JWResult = _advance(g)
		if st.politics.run_terminated:
			ended_q = q
			break
		check(r.ok, "第 %d 季推进" % q)
	eq_int(st.crisis.stage[JWCrisis.TRACK_LEGITIMACY], JWCrisis.STAGE_FINAL, "合法性轨在最后补救窗口")
	check(st.politics.run_terminated, "窗口届满且信任仍低 ⇒ 国家解体")
	eq_int(st.politics.termination_reason, JWUnits.Termination.STATE_COLLAPSE, "终局原因：国家解体")
	eq_int(ended_q, window, "恰在进入窗口后第 %d 季终局" % window)


func test_forced_separation_when_labor_force_shrinks() -> void:
	var g: JWGame = _game(CAMPAIGN, 23)
	var st: JWSimState = g.get("_st") as JWSimState
	check(_advance(g).ok, "推进一季")
	# 夹具：某地区某技能的劳动年龄人口骤减到在岗人数以下（模拟长期人口收缩）。
	var r: int = 3
	var k: int = 2
	var gidx: int = JWIds.idx_group(r, JWUnits.Age.WORKING, k)
	var employed: int = 0
	for s: int in JWUnits.S:
		employed += st.labor.cell_employment[JWIds.idx_emp(JWIds.idx_cell(r, s), k)]
	employed += st.labor.pub_employment[JWIds.idx_pubserv_emp(r, k)]
	check(employed > 10, "夹具前提：有在岗者")
	var cut: int = st.pop.population[gidx] - employed + 5
	st.pop.population[gidx] -= cut
	st.pop.rebase_after_load(st.migration.in_by_group(), st.migration.out_by_group())
	var res: JWResult = _advance(g)
	check(res.ok, "劳动力缩减到在岗人数以下时照常结算（不再 EMPLOYMENT_OVERFLOW）")
