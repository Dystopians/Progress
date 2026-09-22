## P11（征收能力）与 P12（采购透明度）效果的单元测试（docs/18 R-P11-01 / R-P12-01）。
##
## 载入出厂内容包，绕过 S02 资格链直接让政策生效，只驱动 JWPolicyEngine.apply_effects：
##   P11：增量 = min(人员上限, 系统上限) × 覆盖率，以上限夹住，只在落点季落一次；
##   P12：生效期内逐季按 E1—E16 更新行政执行能力，未生效零效应，每季净变动受 step_max 约束，
##        开张初期负荷先于收益（净效应为负），完整生效后为正。
## 纪律：JWResult 的故障登记是静态的，每个方法前后都 clear_pending()。
extends JWTest

const P10: int = 9
const P11: int = 10
const P12: int = 11


func before_each() -> void:
	JWResult.clear_pending()


func after_each() -> void:
	JWResult.clear_pending()


func _state() -> JWSimState:
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: JWContentLoader = JWContentLoader.new()
	var res: JWResult = loader.load_all("res://content", st)
	if res == null or not res.ok:
		fail("出厂内容包载入失败（code=%d）" % (0 if res == null else res.code))
		return null
	return st


## 让政策 p 从 q0 起生效（只测效果函数，不走 S02 资格链）。
func _force_effective(st: JWSimState, p: int, q0: int) -> void:
	st.policy.enabled[p] = 1
	st.policy.enacted_q[p] = q0 - 1
	st.policy.effective_from_q[p] = q0
	st.policy.budget_committed[p] = st.policy_defs.cost_one_off_uu[p]


func _set_param(st: JWSimState, p: int, slot: int, v: int) -> void:
	var idx: int = JWIds.idx_policy_param(p, slot)
	st.policy.params_ppm[idx] = v
	st.policy.params_uu[idx] = v


func _apply(st: JWSimState, q: int) -> int:
	return st.policy.apply_effects(st.policy_defs, st.capital, st.treasury, st.politics, st.pop,
			q, st.params)


func _landing_q(st: JWSimState, p: int) -> int:
	return st.policy.effective_from_q[p] + maxi(1, st.policy_defs.commission_delay_q[p])


# ── P11 ───────────────────────────────────────────────────────────────────

func test_p11_slots_resolved_by_key() -> void:
	var st: JWSimState = _state()
	if st == null:
		return
	ge_int(st.policy_defs.staff_slot[P11], 0, "P11 的 staffing_scale_ppm 槽位必须按键解析出来")
	ge_int(st.policy_defs.system_slot[P11], 0, "P11 的 system_scale_ppm 槽位必须按键解析出来")
	ge_int(st.policy_defs.mask_slot[P11], 0, "P11 的 region_mask 槽位必须按类型解析出来")
	var share_sum: int = 0
	for r: int in JWUnits.R:
		share_sum += st.params[JWUnits.Param.P11_REGION_BASE_SHARE_PPM_0 + r]
	eq_int(share_sum, JWUnits.PPM, "param.p11_region_base_share_ppm 四项之和必须 == 1 000 000")


func test_p11_full_scale_full_coverage() -> void:
	var st: JWSimState = _state()
	if st == null:
		return
	_force_effective(st, P11, 1)
	_set_param(st, P11, st.policy_defs.staff_slot[P11], JWUnits.PPM)
	_set_param(st, P11, st.policy_defs.system_slot[P11], JWUnits.PPM)
	st.policy.region_mask[P11] = 15
	var before: int = st.treasury.tax_capacity_ppm
	eq_int(_apply(st, _landing_q(st, P11) - 1), JWResult.OK, "落点季之前 apply_effects 必须成功")
	eq_int(st.treasury.tax_capacity_ppm, before, "落点季之前征收能力不得变化")
	eq_int(_apply(st, _landing_q(st, P11)), JWResult.OK, "落点季 apply_effects 必须成功")
	eq_int(st.treasury.tax_capacity_ppm - before, st.params[JWUnits.Param.P11_STAFF_GAIN_FULL_PPM],
			"满编满规模、全国覆盖：增量 == min(人员上限, 系统上限) == 满额增量")
	eq_int(_apply(st, _landing_q(st, P11) + 1), JWResult.OK, "落点季之后 apply_effects 必须成功")
	eq_int(st.treasury.tax_capacity_ppm - before, st.params[JWUnits.Param.P11_STAFF_GAIN_FULL_PPM],
			"效果只落一次：落点季之后不得重复增加")


func test_p11_min_rule_and_region_coverage() -> void:
	var st: JWSimState = _state()
	if st == null:
		return
	_force_effective(st, P11, 1)
	_set_param(st, P11, st.policy_defs.staff_slot[P11], 500_000)
	_set_param(st, P11, st.policy_defs.system_slot[P11], JWUnits.PPM)
	st.policy.region_mask[P11] = 1 << JWUnits.Region.HAIJIA
	var before: int = st.treasury.tax_capacity_ppm
	_apply(st, _landing_q(st, P11))
	var staff_cap: int = JWMath.mul_ppm(st.params[JWUnits.Param.P11_STAFF_GAIN_FULL_PPM], 500_000)
	var expect: int = JWMath.mul_ppm(staff_cap,
			st.params[JWUnits.Param.P11_REGION_BASE_SHARE_PPM_0 + JWUnits.Region.HAIJIA])
	eq_int(st.treasury.tax_capacity_ppm - before, expect,
			"人员半编：取 min（人员一侧）；只覆盖海岬：乘海岬税基份额")


func test_p11_ceiling_clamp() -> void:
	var st: JWSimState = _state()
	if st == null:
		return
	_force_effective(st, P11, 1)
	_set_param(st, P11, st.policy_defs.staff_slot[P11], JWUnits.PPM)
	_set_param(st, P11, st.policy_defs.system_slot[P11], JWUnits.PPM)
	st.policy.region_mask[P11] = 15
	var ceiling: int = st.params[JWUnits.Param.P11_TAX_CAPACITY_CEILING_PPM]
	st.treasury.tax_capacity_ppm = ceiling - 10_000
	_apply(st, _landing_q(st, P11))
	eq_int(st.treasury.tax_capacity_ppm, ceiling, "增量越过上限的部分必须被夹掉")
	# 已经在上限之上（例如事件推高）：本政策不得把它拉低。
	var st2: JWSimState = _state()
	if st2 == null:
		return
	_force_effective(st2, P11, 1)
	_set_param(st2, P11, st2.policy_defs.staff_slot[P11], JWUnits.PPM)
	_set_param(st2, P11, st2.policy_defs.system_slot[P11], JWUnits.PPM)
	st2.policy.region_mask[P11] = 15
	st2.treasury.tax_capacity_ppm = ceiling + 20_000
	_apply(st2, _landing_q(st2, P11))
	eq_int(st2.treasury.tax_capacity_ppm, ceiling + 20_000, "已在上限之上时本政策不改征收能力")


# ── P12 ───────────────────────────────────────────────────────────────────

## P12 夹具：本季采购 1.05 U（高于默认披露门槛 0.1 U）、全国运行费足额到位。
func _p12_state(q0: int) -> JWSimState:
	var st: JWSimState = _state()
	if st == null:
		return null
	_force_effective(st, P12, q0)
	st.treasury.f_pay_procurement = 1_050_000_000
	for r: int in JWUnits.R:
		st.capital.f_pub_funding_ratio[r] = JWUnits.PPM
	return st


func test_p12_zero_effect_before_effective() -> void:
	var st: JWSimState = _p12_state(5)
	if st == null:
		return
	var before: int = st.politics.admin_capacity_ppm
	for q: int in range(0, 5):
		eq_int(_apply(st, q), JWResult.OK, "未生效季 apply_effects 必须成功")
	eq_int(st.politics.admin_capacity_ppm, before, "INV-095：生效季之前行政执行能力不得变化")


func test_p12_load_before_gain() -> void:
	var st: JWSimState = _p12_state(1)
	if st == null:
		return
	var before: int = st.politics.admin_capacity_ppm
	# 生效首季：项目期尚未花钱（进度 0）⇒ 有效审核强度 0，只剩流程负荷。
	_apply(st, 1)
	var d: int = st.politics.admin_capacity_ppm - before
	check(d < 0, "计划书 §09「初期流程成本」：生效首季净变动必须为负（实际 %d）" % d)
	ge_int(d, -st.params[JWUnits.Param.PROC_TRANSPARENCY_STEP_MAX_PPM], "单季净变动不得越过 step_max")


func test_p12_full_effect_positive_and_bounded() -> void:
	var st: JWSimState = _p12_state(1)
	if st == null:
		return
	# 完整生效：项目期已花完、爬坡已满。
	st.policy.budget_spent[P12] = st.policy.budget_committed[P12]
	st.politics.admin_capacity_ppm = 600_000
	var step_max: int = st.params[JWUnits.Param.PROC_TRANSPARENCY_STEP_MAX_PPM]
	var q: int = 10
	var prev: int = st.politics.admin_capacity_ppm
	while q < 14:
		_apply(st, q)
		var d: int = st.politics.admin_capacity_ppm - prev
		check(d > 0, "完整生效后净效应必须为正（第 %d 季实际 %d）" % [q, d])
		le_int(d, step_max, "单季净变动不得越过 step_max")
		prev = st.politics.admin_capacity_ppm
		q += 1


func test_p12_deterministic() -> void:
	var a: JWSimState = _p12_state(1)
	var b: JWSimState = _p12_state(1)
	if a == null or b == null:
		return
	for q: int in range(1, 8):
		_apply(a, q)
		_apply(b, q)
	eq_int(a.politics.admin_capacity_ppm, b.politics.admin_capacity_ppm, "同一输入两次推进结果必须逐位相同")


# ── P10（R-P10-01：每季拨款是投运后运行费义务的拨付上限） ─────────────────────

func test_p10_grant_slot_and_shortfall() -> void:
	var st: JWSimState = _state()
	if st == null:
		return
	var gs: int = st.policy_defs.grant_slot[P10]
	ge_int(gs, 0, "P10 的 grant_per_q_uu 槽位必须按键解析出来")
	eq_int(st.policy.grant_shortfall(P10, st.policy_defs), 0, "未投运：没有义务就没有欠额")
	_force_effective(st, P10, 1)
	_set_param(st, P10, gs, 0)
	var committed0: int = st.treasury.service_opex_committed
	eq_int(_apply(st, _landing_q(st, P10)), JWResult.OK, "落点季 apply_effects 必须成功")
	var opex: int = st.policy_defs.opex_per_q_uu[P10]
	check(opex > 0, "夹具前提：P10 有投运后运行费")
	eq_int(st.policy.opex_landed[P10], opex, "落点季记下并入运行费池的每季额")
	eq_int(st.treasury.service_opex_committed, committed0 + opex, "运行费池同步增加")
	eq_int(st.policy.grant_shortfall(P10, st.policy_defs), opex, "拨款 0 ⇒ 欠额 == 全部运行费")
	_set_param(st, P10, gs, opex - 5_000_000)
	eq_int(st.policy.grant_shortfall(P10, st.policy_defs), 5_000_000, "拨款不足 ⇒ 欠额 == 差额")
	_set_param(st, P10, gs, opex + 2_000_000)
	eq_int(st.policy.grant_shortfall(P10, st.policy_defs), 0, "拨款足额 ⇒ 无欠额")
	st.policy.enabled[P10] = 0
	eq_int(st.policy.grant_shortfall(P10, st.policy_defs), opex, "退出后拨款为 0，义务仍在 ⇒ 欠额 == 全部运行费")
	eq_int(st.policy.grant_shortfall(P11, st.policy_defs), 0, "没有拨款槽的政策不受拨款上限约束")


# ── P11 断供 / 退出衰减（R-P11-02） ─────────────────────────────────────────

func _upkeep(st: JWSimState, q: int) -> int:
	return st.policy.upkeep_effects(st.policy_defs, st.capital, st.treasury, st.politics, q, st.params)


## 让 P11 完成一次满额建设并投运（落点季 apply_effects），返回落点季。
func _p11_built(st: JWSimState) -> int:
	_force_effective(st, P11, 1)
	_set_param(st, P11, st.policy_defs.staff_slot[P11], JWUnits.PPM)
	_set_param(st, P11, st.policy_defs.system_slot[P11], JWUnits.PPM)
	st.policy.region_mask[P11] = 15
	var ql: int = _landing_q(st, P11)
	eq_int(_apply(st, ql), JWResult.OK, "P11 落点季 apply_effects 必须成功")
	return ql


func test_p11_starvation_decays_to_floor_and_recovers_to_built() -> void:
	var st: JWSimState = _state()
	if st == null:
		return
	var floor_ppm: int = st.params[JWUnits.Param.P11_CAPACITY_FLOOR_PPM]
	eq_int(floor_ppm, st.treasury.tax_capacity_ppm, "地板 == 剧本基年征收能力（加载期交叉校验）")
	eq_int(st.treasury.tax_capacity_built_ppm, floor_ppm, "开局建成水平 == 基年征收能力")
	var ql: int = _p11_built(st)
	var built: int = st.treasury.tax_capacity_ppm
	check(built > floor_ppm, "夹具前提：满额建设抬高了征收能力")
	eq_int(st.treasury.tax_capacity_built_ppm, built, "落点季记下建成水平")
	check(st.policy.opex_landed[P11] > 0, "行政类政策落点并入运行费义务")
	var decay: int = st.params[JWUnits.Param.P11_CAPACITY_DECAY_PPM]
	var recover: int = st.params[JWUnits.Param.P11_CAPACITY_RECOVER_PPM]
	check(recover < decay, "恢复慢于下降")
	# 中州完全欠拨一季：降 decay。
	st.capital.f_pub_funding_ratio[JWUnits.Region.ZHONGZHOU] = 0
	eq_int(_upkeep(st, ql + 1), JWResult.OK, "upkeep 成功")
	eq_int(st.treasury.tax_capacity_ppm, built - decay, "完全断供一季 ⇒ 降 decay")
	# 半额欠拨：降 decay/2。
	st.capital.f_pub_funding_ratio[JWUnits.Region.ZHONGZHOU] = 500_000
	_upkeep(st, ql + 2)
	eq_int(st.treasury.tax_capacity_ppm, built - decay - JWMath.mul_ppm(decay, 500_000), "欠拨一半 ⇒ 按比例降")
	# 足额：回升 recover，封顶建成水平。
	st.capital.f_pub_funding_ratio[JWUnits.Region.ZHONGZHOU] = JWUnits.PPM
	var before: int = st.treasury.tax_capacity_ppm
	_upkeep(st, ql + 3)
	eq_int(st.treasury.tax_capacity_ppm, mini(built, before + recover), "足额 ⇒ 回升 recover")
	for k: int in 40:
		_upkeep(st, ql + 4 + k)
	eq_int(st.treasury.tax_capacity_ppm, built, "长期足额 ⇒ 回到建成水平，不越过")
	# 长期完全断供：停在地板，不向 0 滑。
	st.capital.f_pub_funding_ratio[JWUnits.Region.ZHONGZHOU] = 0
	for k2: int in 40:
		_upkeep(st, ql + 50 + k2)
	eq_int(st.treasury.tax_capacity_ppm, floor_ppm, "长期断供 ⇒ 停在地板（基年征收能力）")


func test_p11_repeal_releases_opex_and_decays() -> void:
	var st: JWSimState = _state()
	if st == null:
		return
	var ql: int = _p11_built(st)
	var built: int = st.treasury.tax_capacity_ppm
	var opex: int = st.policy.opex_landed[P11]
	var committed: int = st.treasury.service_opex_committed
	st.policy.cooldown_until_q[P11] = 0
	# 夹具扮演 S02 的开启：本次开启签入的承诺记入备查额（真实流程由 try_enact 登记），撤回才有东西可释放。
	eq_int(st.treasury.record_commitment(st.policy._commit_of_current_enactment(P11, st.policy_defs)), JWResult.OK,
			"夹具：登记本次开启的承诺")
	var rc: int = st.policy.try_repeal(P11, st.policy_defs, st.treasury, st.ledger, st.accounts, ql + 1)
	eq_int(rc, JWResult.OK, "撤回受理")
	eq_int(st.treasury.service_opex_committed, committed - opex, "行政类撤回解除运行费义务（exit_rule）")
	eq_int(st.policy.opex_landed[P11], 0, "义务记录清零")
	# 退出后即使中州足额，征收能力也按完全断供回落。
	st.capital.f_pub_funding_ratio[JWUnits.Region.ZHONGZHOU] = JWUnits.PPM
	_upkeep(st, ql + 1)
	eq_int(st.treasury.tax_capacity_ppm, built - st.params[JWUnits.Param.P11_CAPACITY_DECAY_PPM],
			"退出后没有运行费 ⇒ 按完全断供回落")


# ── P12 撤回后的行政能力回落（R-P12-02） ─────────────────────────────────────

func test_p12_exit_decay_window() -> void:
	var st: JWSimState = _state()
	if st == null:
		return
	# P12 曾经生效，第 10 季撤回。
	st.policy.enabled[P12] = 0
	st.policy.effective_from_q[P12] = 3
	st.policy.exit_pending_q[P12] = 10
	var decay_q: int = st.params[JWUnits.Param.PROC_TRANSPARENCY_DECAY_Q]
	var rate: int = st.params[JWUnits.Param.PROC_TRANSPARENCY_DECAY_PPM]
	var step_max: int = st.params[JWUnits.Param.PROC_TRANSPARENCY_STEP_MAX_PPM]
	st.politics.set_admin_capacity(700_000)
	_upkeep(st, 9)
	eq_int(st.politics.admin_capacity_ppm, 700_000, "撤回季之前不回落")
	var a: int = 700_000
	for k: int in decay_q:
		_upkeep(st, 10 + k)
		a = a - JWMath.clamp_i(JWMath.mul_ppm(rate, a), 0, step_max)
		eq_int(st.politics.admin_capacity_ppm, a, "回落期第 %d 季按比例回落" % (k + 1))
	_upkeep(st, 10 + decay_q)
	eq_int(st.politics.admin_capacity_ppm, a, "回落期满即静默")
	check(700_000 - a > 0, "回落确实发生")


func test_p12_exit_before_effective_has_no_decay() -> void:
	var st: JWSimState = _state()
	if st == null:
		return
	st.policy.enabled[P12] = 0
	st.policy.effective_from_q[P12] = 12
	st.policy.exit_pending_q[P12] = 10
	st.politics.set_admin_capacity(700_000)
	_upkeep(st, 10)
	eq_int(st.politics.admin_capacity_ppm, 700_000, "撤回时尚未生效 ⇒ 没有收益也没有回落")


## E17（policy_P12.json /effect/_note_formula_steps）：生效期内每季把 8 个中间量写进 log.explanations
## （kind = accounted，cause = EXPLAIN_P12_BASE + k），其中净变动一行等于本季行政执行能力的实际变动。
func test_p12_e17_explanations_logged() -> void:
	var st: JWSimState = _p12_state(1)
	if st == null:
		return
	st.diag.log_reset_quarter()
	var before: int = st.politics.admin_capacity_ppm
	eq_int(st.policy.apply_effects(st.policy_defs, st.capital, st.treasury, st.politics, st.pop, 5, st.params, st.diag),
			JWResult.OK, "apply_effects 带诊断通道必须成功")
	var got: Dictionary = {}
	for i: int in st.diag.log_row_count():
		var c: int = st.diag.e_cause[i]
		if c >= JWPolicyEngine.EXPLAIN_P12_BASE and c < JWPolicyEngine.EXPLAIN_P12_BASE + 8:
			eq_int(st.diag.e_kind[i], JWUnits.ExplainKind.ACCOUNTED, "E17 行是 accounted")
			eq_int(st.diag.e_entity[i], P12, "E17 行的实体是 P12")
			got[c - JWPolicyEngine.EXPLAIN_P12_BASE] = st.diag.e_amount[i]
	eq_int(got.size(), 8, "E17 写满 8 个中间量")
	if got.has(7):
		eq_int(int(got[7]), st.politics.admin_capacity_ppm - before, "净变动一行 == 行政执行能力的实际变动")

