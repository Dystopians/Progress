## P10「每季基础医疗拨款」的场景测试（docs/18 R-P10-01；policy_P10.json effect_chain 1—4、exit_rule）。
## 两局同种子对照：P10 已投运、义务已并入运行费池（夹具扮演 LOAD），只有拨款旋钮不同。
## 拨款低于义务 ⇒ 作用地区实拨额减少、funding_ratio < 1 ⇒ 可用率按断供规则衰减；拨款足额 ⇒ 足额拨付。
extends JWTest

const P10: int = 9


func _game(grant: int) -> JWGame:
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_test"
	var r: JWResult = g.new_game("res://content", 1_000_000, 40)
	check(r != null and r.ok, "开局成功")
	var st: JWSimState = g.get("_st") as JWSimState
	var defs: JWPolicyDef = st.policy_defs
	# 落点季在开局之前（生效季 −10 + 投运时滞 < 0），项目期也已结束：本局只剩投运后的运行费义务。
	st.policy.enabled[P10] = 1
	st.policy.enacted_q[P10] = -20
	st.policy.effective_from_q[P10] = -10
	st.policy.region_mask[P10] = 15
	var opex: int = defs.opex_per_q_uu[P10]
	st.policy.opex_landed[P10] = opex
	st.treasury.service_opex_committed += opex
	var idx: int = JWIds.idx_policy_param(P10, defs.grant_slot[P10])
	st.policy.params_ppm[idx] = grant
	st.policy.params_uu[idx] = grant
	return g


func _advance(g: JWGame) -> void:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(JWCommands.ARG_SLOTS)
	a.fill(0)
	g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, a)
	var r: JWResult = g.advance_quarter()
	check(r == null or r.ok, "推进成功")


func test_grant_below_obligation_starves_availability() -> void:
	var probe: JWGame = _game(0)
	var opex: int = (probe.get("_st") as JWSimState).policy_defs.opex_per_q_uu[P10]
	check(opex > 0, "夹具前提：P10 有投运后运行费")
	var starve: JWGame = probe
	var full: JWGame = _game(opex + 2_000_000)
	for i: int in 2:
		_advance(starve)
		_advance(full)
	var s0: JWSimState = starve.get("_st") as JWSimState
	var s1: JWSimState = full.get("_st") as JWSimState
	var any_short: bool = false
	var avail_starve: int = 0
	var avail_full: int = 0
	for r: int in JWUnits.R:
		eq_int(s1.capital.f_pub_funding_ratio[r], JWUnits.PPM, "拨款足额 ⇒ 地区 %d 足额拨付" % r)
		le_int(s0.capital.f_pub_funding_ratio[r], s1.capital.f_pub_funding_ratio[r],
				"拨款为 0 的一局，地区 %d 的到位率不高于足额局" % r)
		if s0.capital.f_pub_funding_ratio[r] < JWUnits.PPM:
			any_short = true
		avail_starve += s0.capital.pub_availability[r]
		avail_full += s1.capital.pub_availability[r]
	check(any_short, "拨款为 0 ⇒ 至少一个地区欠拨（funding_ratio < 1）")
	check(avail_starve < avail_full, "欠拨 ⇒ 可用率低于足额局（实测 %d / %d）" % [avail_starve, avail_full])
	eq_int(s0.treasury.service_opex_committed, s1.treasury.service_opex_committed,
			"义务不因拨款不足而消失（INV-102 同构：只降可用率，不删资产、不减义务）")


func test_exit_stops_grant_but_keeps_obligation() -> void:
	var g: JWGame = _game(50_000_000)
	var st: JWSimState = g.get("_st") as JWSimState
	st.policy.enabled[P10] = 0
	_advance(g)
	var any_short: bool = false
	for r: int in JWUnits.R:
		if st.capital.f_pub_funding_ratio[r] < JWUnits.PPM:
			any_short = true
	check(any_short, "退出后不再拨款：已投运包的运行费欠拨（policy_P10.json exit_rule）")
	check(st.policy.opex_landed[P10] > 0, "退出不回收义务记录")
