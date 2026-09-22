## 价格与市场的契约测试（独立于实现编写）。
##
## 依据（冲突时以上位者为准）：
##   docs/18_rulings.md          R-SCALE-01（1 U = 10⁹ μU；mul_div_floor 是唯一「先乘后除」入口）
##   docs/12_simulation_contract.md §5.6（市场闭合与配给）、§7.3（价格与工资的有界平滑）
##   docs/10_variable_dictionary.md §14.5（INV-059…INV-070）
##   docs/30_quality_gates.md    T-U-E-09 / T-X-E-12 / T-S-P04-NO-DEMAND-NO-BONUS
##   docs/31_adversarial_tests.md ADV-D01（拆单造货）、ADV-H05（存读档改市场结果）、ADV-J06（价格触顶）
##   docs/17_api_skeleton.md     §4.9 JWPricing / §4.17 JWInventory 的签名
##
## 本文件**不读被测模块的实现**，全部期望值由上述契约的公式在测试内独立复算得到。
## 若测试与实现不一致，以契约为准。
extends JWTest

# ── 参数取值（docs/11 §5.15 首版必备参数最小集的登记值） ────────────────────
#
# 这些参数在 content/parameters 里尚无身份证（docs/14 PR-019 全部 WARN），
# 因此夹具必须自带取值；取的就是 docs/11 §5.15 表里的登记值，不是随手编的数。

const P_GAP_CAP_PPM: int = 500_000
const P_GAP_GAIN_PPM: int = 200_000
const P_COVER_GAIN_PPM: int = 100_000
const P_STEP_MAX_PPM: int = 30_000
const P_FLOOR_PPM: int = 400_000
const P_CEIL_PPM: int = 2_500_000
const P_CLAMP_BUDGET: int = 240
const W_GAIN_PPM: int = 150_000
const W_STEP_MAX_PPM: int = 20_000

## docs/11 §5.15.2 给 param.wage_floor_uu / wage_ceil_uu 打了 ⚠：
## 机械迁移后的下限 5×10⁷ μU 比真实工资（约 1 360 μU）高四个数量级，
## 「在基年重拟合给出工资轨之前，不得把它们当作有效的硬界使用」。
## 夹具因此自带一对不会夹住任何工资的硬界，否则每个工资测试测的都是那条错误的下限。
const W_FLOOR_TEST_UU: int = 1
const W_CEIL_TEST_UU: int = 20_000_000_000

## R-SCALE-01 给出的新刻度人均季度劳动报酬量级（约 1 360 μU）。
const WAGE_TYPICAL_UU: int = 1_360
## R-SCALE-01 表格里旧刻度的人均季度劳动报酬量级（1…3 μU）。
const WAGE_OLD_SCALE_UU: int = 1

## 可库存标志（INV-049：energy 与 services 期末库存恒为 0）。
const STORABLE: PackedInt64Array = [1, 1, 0, 0]


func before_each() -> void:
	# 故障登记是静态的，跨测试会串味；每个测试从干净的登记开始。
	JWResult.clear_pending()


func after_each() -> void:
	JWResult.clear_pending()


# ── 夹具 ───────────────────────────────────────────────────────────────────

func _filled(n: int, v: int) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(n)
	a.fill(v)
	return a


func _iota(n: int) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(n)
	for i: int in n:
		a[i] = i
	return a


func _params() -> PackedInt64Array:
	var p: PackedInt64Array = PackedInt64Array()
	p.resize(JWUnits.PARAM_N)
	p.fill(0)
	p[JWUnits.Param.GAP_CAP_PPM] = P_GAP_CAP_PPM
	p[JWUnits.Param.PRICE_GAP_GAIN_PPM] = P_GAP_GAIN_PPM
	p[JWUnits.Param.PRICE_COVER_GAIN_PPM] = P_COVER_GAIN_PPM
	p[JWUnits.Param.PRICE_STEP_MAX_PPM] = P_STEP_MAX_PPM
	p[JWUnits.Param.PRICE_FLOOR_PPM] = P_FLOOR_PPM
	p[JWUnits.Param.PRICE_CEIL_PPM] = P_CEIL_PPM
	p[JWUnits.Param.PRICE_CLAMP_BUDGET_COUNT] = P_CLAMP_BUDGET
	p[JWUnits.Param.WAGE_GAIN_PPM] = W_GAIN_PPM
	p[JWUnits.Param.WAGE_STEP_MAX_PPM] = W_STEP_MAX_PPM
	p[JWUnits.Param.WAGE_FLOOR_UU] = W_FLOOR_TEST_UU
	p[JWUnits.Param.WAGE_CEIL_UU] = W_CEIL_TEST_UU
	p[JWUnits.Param.INVENTORY_TARGET_PPM] = 250_000
	return p


func _new_pricing(price0: int, wage0: int) -> JWPricing:
	var pr: JWPricing = JWPricing.new()
	pr.allocate()
	pr.base_price = _filled(JWUnits.S, JWUnits.BASE_PRICE)   # INV-148：唯一合法值
	pr.price = _filled(JWUnits.S, price0)
	pr.price_pending = _filled(JWUnits.S, price0)
	pr.wage = _filled(JWUnits.K, wage0)
	pr.wage_pending = _filled(JWUnits.K, wage0)
	pr.housing_rent = _filled(JWUnits.R, 1_000)
	return pr


func _new_inventory() -> JWInventory:
	var inv: JWInventory = JWInventory.new()
	inv.allocate()
	inv.m_supply = _filled(JWUnits.S, 0)
	inv.m_demand = _filled(JWUnits.MARKET_N, 0)
	inv.m_traded = _filled(JWUnits.MARKET_N, 0)
	inv.m_unmet = _filled(JWUnits.MARKET_N, 0)
	inv.m_rule = _filled(JWUnits.S, -1)          # −1：未被写过，便于发现「压根没写」
	inv.logistics_cost_ppm = _filled(JWUnits.OD_N, 0)
	return inv


func _new_rng(seed_value: int) -> JWRngStreams:
	var rng: JWRngStreams = JWRngStreams.new()
	rng.allocate()
	rng.root_seed = seed_value
	rng.begin_quarter(0)
	return rng


## 把某部门的一条买方需求写进 flow.market.demand_uqs（下标 = idx_market(s, buyer)）。
func _set_demand(inv: JWInventory, s: int, d: PackedInt64Array) -> void:
	for b: int in JWUnits.BUYER_CLASS_N:
		inv.m_demand[JWIds.idx_market(s, b)] = d[b]


func _demand_total(inv: JWInventory, s: int) -> int:
	var t: int = 0
	for b: int in JWUnits.BUYER_CLASS_N:
		t += inv.m_demand[JWIds.idx_market(s, b)]
	return t


func _traded_total(inv: JWInventory, s: int) -> int:
	var t: int = 0
	for b: int in JWUnits.BUYER_CLASS_N:
		t += inv.m_traded[JWIds.idx_market(s, b)]
	return t


func _unmet_total(inv: JWInventory, s: int) -> int:
	var t: int = 0
	for b: int in JWUnits.BUYER_CLASS_N:
		t += inv.m_unmet[JWIds.idx_market(s, b)]
	return t


func _market_slice(inv: JWInventory, src: PackedInt64Array, s: int) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(JWUnits.BUYER_CLASS_N)
	for b: int in JWUnits.BUYER_CLASS_N:
		a[b] = src[JWIds.idx_market(s, b)]
	return a


# ── §7.3 的独立复算（测试侧参考实现，逐行照抄契约，不看被测代码） ───────────

## docs/12 §7.3 (a)+(b)+(c)：合成后的 gap_ppm。
func _expected_gap_ppm(s: int, supply: PackedInt64Array, demand: PackedInt64Array,
		inv_uqs: PackedInt64Array, inv_target_uqs: PackedInt64Array,
		storable: PackedInt64Array, p: PackedInt64Array) -> int:
	var s_uqs: int = supply[s]
	var d_uqs: int = 0
	for b: int in JWUnits.BUYER_CLASS_N:
		d_uqs += demand[JWIds.idx_market(s, b)]

	var gap_cap: int = p[JWUnits.Param.GAP_CAP_PPM]
	var gap_demand: int = gap_cap
	if s_uqs != 0:
		gap_demand = JWMath.clamp_i(
				JWMath.mul_div_floor(d_uqs - s_uqs, JWUnits.PPM, s_uqs),
				-JWUnits.PPM, JWUnits.PPM)

	var gap_cover: int = 0
	if storable[s] != 0:
		var it: int = 0
		var iv: int = 0
		for r: int in JWUnits.R:
			it += inv_target_uqs[JWIds.idx_cell(r, s)]
			iv += inv_uqs[JWIds.idx_cell(r, s)]
		if it < 1:
			it = 1
		gap_cover = JWMath.clamp_i(
				JWMath.mul_div_floor(it - iv, JWUnits.PPM, it),
				-JWUnits.PPM, JWUnits.PPM)

	return JWMath.clamp_i(
			JWMath.mul_ppm(gap_demand, p[JWUnits.Param.PRICE_GAP_GAIN_PPM])
			+ JWMath.mul_ppm(gap_cover, p[JWUnits.Param.PRICE_COVER_GAIN_PPM]),
			-gap_cap, gap_cap)


## docs/12 §7.3 (d)+(e)：由本季生效价 price_cur 推出的 pending。
func _expected_pending(price_cur: int, base_price: int, gap_ppm: int,
		p: PackedInt64Array) -> int:
	var delta_raw: int = JWMath.mul_ppm(price_cur, gap_ppm)
	var max_step: int = JWMath.mul_ppm(price_cur, p[JWUnits.Param.PRICE_STEP_MAX_PPM])
	var delta: int = JWMath.clamp_i(delta_raw, -max_step, max_step)
	var p_floor: int = JWMath.mul_ppm(base_price, p[JWUnits.Param.PRICE_FLOOR_PPM])
	var p_ceil: int = JWMath.mul_ppm(base_price, p[JWUnits.Param.PRICE_CEIL_PPM])
	return JWMath.clamp_i(price_cur + delta, p_floor, p_ceil)


## docs/12 §7.3 工资段：由本季生效工资推出的 wage_pending。
func _expected_wage_pending(wage_cur: int, vacancies: int, unemployed: int,
		labor_force: int, p: PackedInt64Array) -> int:
	var lf: int = labor_force
	if lf < 1:
		lf = 1
	var gap: int = JWMath.clamp_i(
			JWMath.mul_div_floor(vacancies - unemployed, JWUnits.PPM, lf),
			-JWUnits.PPM, JWUnits.PPM)
	var step: int = JWMath.mul_ppm(wage_cur, p[JWUnits.Param.WAGE_STEP_MAX_PPM])
	var delta: int = JWMath.clamp_i(
			JWMath.mul_ppm_2(wage_cur, gap, p[JWUnits.Param.WAGE_GAIN_PPM]), -step, step)
	return JWMath.clamp_i(wage_cur + delta,
			p[JWUnits.Param.WAGE_FLOOR_UU], p[JWUnits.Param.WAGE_CEIL_UU])


# ══════════════════════════════════════════════════════════════════════════
#  一、价格边界与刻度（INV-066、R-SCALE-01）
# ══════════════════════════════════════════════════════════════════════════

## 检验 INV-066 与 docs/11 §5.15 注 3：
## 相对界（ppm）与绝对界（μU/Q_s）必须是同一约束的两种写法。
## R-SCALE-01 把 PRICE_MIN/MAX 各 ×1000，若常量与参数卡不同源，
## 价格会在一个错误的箱子里平滑（docs/12 §7.3 (e) 原话）。
func test_price_bounds_are_the_rescaled_constants() -> void:
	eq_int(JWUnits.BASE_PRICE, 1_000_000_000,
			"R-SCALE-01 裁定表：BASE_PRICE 新值 1 000 000 000 μU/Q_s")
	eq_int(JWUnits.U_SCALE, 1_000_000_000, "R-SCALE-01 裁定表：U_SCALE 新值 10⁹")
	eq_int(JWMath.mul_ppm(JWUnits.BASE_PRICE, P_FLOOR_PPM), JWUnits.PRICE_MIN,
			"docs/11 §5.15 注 3：PRICE_MIN == mul_ppm(BASE_PRICE, price_floor_ppm)")
	eq_int(JWMath.mul_ppm(JWUnits.BASE_PRICE, P_CEIL_PPM), JWUnits.PRICE_MAX,
			"docs/11 §5.15 注 3：PRICE_MAX == mul_ppm(BASE_PRICE, price_ceil_ppm)")
	eq_int(JWUnits.PRICE_MIN, 400_000_000, "R-SCALE-01 裁定表：PRICE_MIN 新值 4×10⁸")
	eq_int(JWUnits.PRICE_MAX, 2_500_000_000, "R-SCALE-01 裁定表：PRICE_MAX 新值 2.5×10⁹")


## 检验 R-SCALE-01 的裁定理由本身：新刻度下 ±2% 的有界平滑必须产生**非零**变化。
## 旧刻度下人均季度劳动报酬只有 1…3 μU，mul_ppm(w, 20 000) 对 w ≤ 49 恒为 0，
## 工资整局 40 季被冻结——这正是重定标的理由（docs/18 R-SCALE-01 表格第 6 行、
## docs/12 §7.3 工资段的引注）。本测试同时钉死「旧刻度确实为 0」与「新刻度确实非 0」，
## 因为只断言后者的话，把刻度改回去测试依然会绿。
func test_rescaled_two_percent_adjustment_is_nonzero() -> void:
	# (1) 旧刻度：2% 步长对 1…3 μU 的工资恒为 0 —— 被证伪的那个方案。
	eq_int(JWMath.mul_ppm(WAGE_OLD_SCALE_UU, W_STEP_MAX_PPM), 0,
			"旧刻度工资 1 μU：2% 步长 floor 后为 0（R-SCALE-01 表格：工资被冻结）")
	eq_int(JWMath.mul_ppm(3, W_STEP_MAX_PPM), 0, "旧刻度工资 3 μU：2% 步长仍为 0")
	eq_int(JWMath.mul_ppm(49, W_STEP_MAX_PPM), 0,
			"docs/12 §7.3 引注：w ≤ 49 时 mul_ppm(w, 20 000) 恒为 0")

	# (2) 新刻度：同一个 2% 步长在 1 360 μU 上给出 27 μU，第一次真的会动。
	eq_int(JWMath.mul_ppm(WAGE_TYPICAL_UU, W_STEP_MAX_PPM), 27,
			"新刻度工资 1 360 μU：2% 步长 == floor(1360×20000/1e6) == 27 μU")

	# (3) 端到端：把「全部劳动力都是空缺」的极端缺口喂给 update_wages，
	#     wage_pending 必须真的离开原值（旧刻度下它恒等于原值）。
	var p: PackedInt64Array = _params()
	var pr: JWPricing = _new_pricing(JWUnits.BASE_PRICE, WAGE_TYPICAL_UU)
	var lf: int = 1_000_000
	var rc: int = pr.update_wages(lf, 0, lf, p)
	eq_int(rc, JWResult.OK, "update_wages 在合法输入上不应返回故障码")
	var want: int = _expected_wage_pending(WAGE_TYPICAL_UU, lf, 0, lf, p)
	eq_int(want, WAGE_TYPICAL_UU + 27, "契约复算：1360 + clamp(204, ±27) == 1387")
	for k: int in JWUnits.K:
		eq_int(pr.wage_pending[k], want,
				"docs/12 §7.3 工资段复算值（技能档 %d）" % k)
		ne_int(pr.wage_pending[k], pr.wage[k],
				"R-SCALE-01 的验收点：新刻度下 ±2%% 调整必须产生非零变化（技能档 %d）" % k)

	# (4) 住房租金同理：旧刻度 1 μU/套/季 的 2% 是 0，新刻度 1 000 μU 的 2% 是 20。
	eq_int(JWMath.mul_ppm(1, W_STEP_MAX_PPM), 0, "旧刻度租金 1 μU：2% 为 0")
	eq_int(JWMath.mul_ppm(1_000, W_STEP_MAX_PPM), 20, "新刻度租金 1 000 μU：2% 为 20")


# ══════════════════════════════════════════════════════════════════════════
#  二、有界平滑只改下一季、同季不放大（INV-065、INV-067、INV-070）
# ══════════════════════════════════════════════════════════════════════════

## 检验 INV-065：价格只在 S07 写 pending，S05 的任何函数不得读到被改过的价格。
## update_prices 之后，state.price.sector_uu_per_qs 必须逐位不变，
## 且 price_of() 仍返回本季生效价——「只改下一季」的最小可判定形式。
func test_update_prices_writes_pending_only_not_current() -> void:
	var p: PackedInt64Array = _params()
	var pr: JWPricing = _new_pricing(JWUnits.BASE_PRICE, WAGE_TYPICAL_UU)
	var before: PackedInt64Array = pr.price.duplicate()

	var supply: PackedInt64Array = _filled(JWUnits.S, 1_000_000)
	var demand: PackedInt64Array = _filled(JWUnits.MARKET_N, 0)
	for s: int in JWUnits.S:
		demand[JWIds.idx_market(s, JWUnits.BuyerClass.HOUSEHOLD)] = 3_000_000
	var inv_uqs: PackedInt64Array = _filled(JWUnits.CELL, 0)
	var inv_target: PackedInt64Array = _filled(JWUnits.CELL, 250_000)

	var rc: int = pr.update_prices(supply, demand, inv_uqs, inv_target, STORABLE, p)
	eq_int(rc, JWResult.OK, "update_prices 在合法输入上不应返回故障码")
	eq_int_array(pr.price, before,
			"INV-065：S07 只写 pending，state.price.sector_uu_per_qs 本季必须逐位不变")
	for s: int in JWUnits.S:
		eq_int(pr.price_of(s), before[s],
				"INV-065：price_of() 在 swap 之前必须仍返回本季生效价（部门 %d）" % s)
		ne_int(pr.price_pending[s], before[s],
				"缺口为正时 pending 必须已经被写过（部门 %d）" % s)


## 检验 INV-065「同季不放大」：docs/12 §7.3 (d) 的被乘数是
## state.price.sector_uu_per_qs，不是 pending。因此把 pending 预置成任何值
## 都不得影响本次计算结果——回路在数据流上被切断（docs/17 §4.9 的「两个写入者」注）。
func test_update_prices_is_not_amplified_within_quarter() -> void:
	var p: PackedInt64Array = _params()
	var supply: PackedInt64Array = _filled(JWUnits.S, 1_000_000)
	var demand: PackedInt64Array = _filled(JWUnits.MARKET_N, 0)
	for s: int in JWUnits.S:
		demand[JWIds.idx_market(s, JWUnits.BuyerClass.HOUSEHOLD)] = 2_000_000
	var inv_uqs: PackedInt64Array = _filled(JWUnits.CELL, 100_000)
	var inv_target: PackedInt64Array = _filled(JWUnits.CELL, 250_000)

	# A：pending == price（正常入季状态）
	var a: JWPricing = _new_pricing(JWUnits.BASE_PRICE, WAGE_TYPICAL_UU)
	a.update_prices(supply, demand, inv_uqs, inv_target, STORABLE, p)

	# B：pending 被预置成顶格价（模拟「上一次计算的结果又被当作输入」）
	var b: JWPricing = _new_pricing(JWUnits.BASE_PRICE, WAGE_TYPICAL_UU)
	b.price_pending = _filled(JWUnits.S, JWUnits.PRICE_MAX)
	b.update_prices(supply, demand, inv_uqs, inv_target, STORABLE, p)

	eq_int_array(b.price_pending, a.price_pending,
			"INV-065：pending 的既有内容不得进入本季计算（否则同季价格自我放大）")
	for s: int in JWUnits.S:
		var want: int = _expected_pending(JWUnits.BASE_PRICE, JWUnits.BASE_PRICE,
				_expected_gap_ppm(s, supply, demand, inv_uqs, inv_target, STORABLE, p), p)
		eq_int(a.price_pending[s], want,
				"docs/12 §7.3 (d)(e) 复算值：被乘数只能是本季生效价（部门 %d）" % s)


## 检验 INV-067：|price_next − price_cur| ≤ mul_ppm(price_cur, price_step_max_ppm)。
## 用极端缺口（供给 1 μQ、需求 10¹² μQ）逼出最大步长，断言步长封顶精确生效。
func test_price_step_cap_is_never_exceeded() -> void:
	var p: PackedInt64Array = _params()
	var pr: JWPricing = _new_pricing(JWUnits.BASE_PRICE, WAGE_TYPICAL_UU)
	var supply: PackedInt64Array = _filled(JWUnits.S, 1)
	var demand: PackedInt64Array = _filled(JWUnits.MARKET_N, 0)
	for s: int in JWUnits.S:
		demand[JWIds.idx_market(s, JWUnits.BuyerClass.HOUSEHOLD)] = JWUnits.QTY_MAX
	var inv_uqs: PackedInt64Array = _filled(JWUnits.CELL, 0)
	var inv_target: PackedInt64Array = _filled(JWUnits.CELL, 250_000)

	pr.update_prices(supply, demand, inv_uqs, inv_target, STORABLE, p)
	var max_step: int = JWMath.mul_ppm(JWUnits.BASE_PRICE, P_STEP_MAX_PPM)
	eq_int(max_step, 30_000_000, "3% 步长在基年价上 == 30 000 000 μU/Q_s（docs/10 §9.1）")
	for s: int in JWUnits.S:
		le_int(JWMath.absi(pr.price_pending[s] - pr.price[s]), max_step,
				"INV-067：单季变动不得超过 mul_ppm(price_cur, price_step_max_ppm)（部门 %d）" % s)
		eq_int(pr.price_pending[s], JWUnits.BASE_PRICE + max_step,
				"极端短缺下必须**恰好**顶到步长上限，不多不少（部门 %d）" % s)


## 检验 INV-066：pending 永远落在 [mul_ppm(base, floor_ppm), mul_ppm(base, ceil_ppm)]。
## 从贴近上界与贴近下界两侧各推一次，绝对界必须在步长之后再夹一道。
func test_price_never_leaves_absolute_bounds() -> void:
	var p: PackedInt64Array = _params()

	# 上界：起价 2 490 000 000，步长 74 700 000，若无绝对界会冲到 2 564 700 000。
	var up: JWPricing = _new_pricing(2_490_000_000, WAGE_TYPICAL_UU)
	var supply_u: PackedInt64Array = _filled(JWUnits.S, 1_000_000)
	var demand_u: PackedInt64Array = _filled(JWUnits.MARKET_N, 0)
	for s: int in JWUnits.S:
		demand_u[JWIds.idx_market(s, JWUnits.BuyerClass.HOUSEHOLD)] = 3_000_000
	var inv_zero: PackedInt64Array = _filled(JWUnits.CELL, 0)
	var target_u: PackedInt64Array = _filled(JWUnits.CELL, 250_000)
	up.update_prices(supply_u, demand_u, inv_zero, target_u, STORABLE, p)
	for s: int in JWUnits.S:
		eq_int(up.price_pending[s], JWUnits.PRICE_MAX,
				"INV-066：越过上界必须被夹到 PRICE_MAX = 2.5×10⁹（部门 %d）" % s)

	# 下界：起价 410 000 000，步长 12 300 000，若无绝对界会跌到 397 700 000。
	var dn: JWPricing = _new_pricing(410_000_000, WAGE_TYPICAL_UU)
	var supply_d: PackedInt64Array = _filled(JWUnits.S, 1_000_000)
	var demand_d: PackedInt64Array = _filled(JWUnits.MARKET_N, 0)
	var inv_high: PackedInt64Array = _filled(JWUnits.CELL, 1_250_000)
	var target_d: PackedInt64Array = _filled(JWUnits.CELL, 250_000)
	dn.update_prices(supply_d, demand_d, inv_high, target_d, STORABLE, p)
	for s: int in JWUnits.S:
		eq_int(dn.price_pending[s], JWUnits.PRICE_MIN,
				"INV-066：跌破下界必须被夹到 PRICE_MIN = 4×10⁸（部门 %d）" % s)
		in_range_int(dn.price_pending[s], JWUnits.PRICE_MIN, JWUnits.PRICE_MAX,
				"INV-066：价格恒在绝对界内（部门 %d）" % s)


## 检验 docs/12 §7.3 全式（(a)…(e)）与 flow.price.gap_ppm 的登记值。
## 三个用例刻意取不整除的数，把 floor 偏置（含负方向向 −∞）暴露出来：
## T-U-PRICE-NEG-ROUNDING 规定降价方向多 1 μU，**不得改为向零截断**。
func test_update_prices_matches_contract_formula() -> void:
	var p: PackedInt64Array = _params()
	var cases: Array[Dictionary] = [
		{"s": 0, "supply": 777_777, "demand": 1_234_567, "inv": 333_333, "target": 1_000_001},
		{"s": 1, "supply": 2_000_003, "demand": 500_009, "inv": 4_444_444, "target": 1_111_111},
		{"s": 0, "supply": 1_000_000, "demand": 1_000_000, "inv": 250_000, "target": 250_000},
	]
	for c: Dictionary in cases:
		var s: int = int(c["s"])
		var pr: JWPricing = _new_pricing(JWUnits.BASE_PRICE, WAGE_TYPICAL_UU)
		var supply: PackedInt64Array = _filled(JWUnits.S, 1_000_000)
		supply[s] = int(c["supply"])
		var demand: PackedInt64Array = _filled(JWUnits.MARKET_N, 0)
		demand[JWIds.idx_market(s, JWUnits.BuyerClass.HOUSEHOLD)] = int(c["demand"])
		# 其余部门保持供需相等，只让被测部门产生缺口。
		for other: int in JWUnits.S:
			if other != s:
				demand[JWIds.idx_market(other, JWUnits.BuyerClass.HOUSEHOLD)] = 1_000_000
		var inv_uqs: PackedInt64Array = _filled(JWUnits.CELL, 0)
		var target: PackedInt64Array = _filled(JWUnits.CELL, 0)
		for r: int in JWUnits.R:
			for ss: int in JWUnits.S:
				inv_uqs[JWIds.idx_cell(r, ss)] = 0
				target[JWIds.idx_cell(r, ss)] = 0
		inv_uqs[JWIds.idx_cell(0, s)] = int(c["inv"])
		target[JWIds.idx_cell(0, s)] = int(c["target"])

		var rc: int = pr.update_prices(supply, demand, inv_uqs, target, STORABLE, p)
		eq_int(rc, JWResult.OK, "update_prices 不应在合法输入上失败")
		var want_gap: int = _expected_gap_ppm(s, supply, demand, inv_uqs, target, STORABLE, p)
		var want: int = _expected_pending(JWUnits.BASE_PRICE, JWUnits.BASE_PRICE, want_gap, p)
		eq_int(pr.price_pending[s], want,
				"docs/12 §7.3 (a)…(e) 逐行复算（部门 %d，S=%d D=%d I=%d IT=%d）"
				% [s, int(c["supply"]), int(c["demand"]), int(c["inv"]), int(c["target"])])
		eq_int(pr.gap_ppm[s], want_gap,
				"flow.price.gap_ppm 必须登记 §7.3 (c) 合成并截断后的 gap（部门 %d）" % s)
		in_range_int(pr.gap_ppm[s], -P_GAP_CAP_PPM, P_GAP_CAP_PPM,
				"§7.3 (c)：gap 必须被 ±gap_cap_ppm 截断（部门 %d）" % s)
	check_false(JWResult.has_pending(), "三个合法用例都不得登记任何故障")


## 检验 §7.3 (a) 的除零守卫：S_uqs == 0 时取 param.gap_cap_ppm，不得触发 DIV_ZERO。
func test_price_gap_uses_cap_when_supply_is_zero() -> void:
	var p: PackedInt64Array = _params()
	var pr: JWPricing = _new_pricing(JWUnits.BASE_PRICE, WAGE_TYPICAL_UU)
	var supply: PackedInt64Array = _filled(JWUnits.S, 0)
	var demand: PackedInt64Array = _filled(JWUnits.MARKET_N, 0)
	demand[JWIds.idx_market(0, JWUnits.BuyerClass.HOUSEHOLD)] = 1_000_000
	var inv_uqs: PackedInt64Array = _filled(JWUnits.CELL, 250_000)
	var target: PackedInt64Array = _filled(JWUnits.CELL, 250_000)

	pr.update_prices(supply, demand, inv_uqs, target, STORABLE, p)
	check_false(JWResult.has_pending(),
			"§7.3 (a)：供给为 0 走 gap_cap 分支，不得出现 DIV_ZERO")
	# 供给 0、库存恰好等于目标 ⇒ gap == clamp(mul_ppm(gap_cap, gap_gain), ±gap_cap)
	var want_gap: int = _expected_gap_ppm(0, supply, demand, inv_uqs, target, STORABLE, p)
	eq_int(want_gap, JWMath.mul_ppm(P_GAP_CAP_PPM, P_GAP_GAIN_PPM),
			"契约复算：gap_demand 取 gap_cap_ppm 后再乘 price_gap_gain_ppm")
	eq_int(pr.gap_ppm[0], want_gap, "§7.3 (a)：S == 0 时 gap_demand_ppm == param.gap_cap_ppm")


## 检验 §7.3 (b) 与 INV-049：不可库存部门（energy / services）的库存偏离项恒为 0。
## 若实现忘了看 storable，给 energy 塞库存就会凭空推动价格。
func test_nonstorable_sector_ignores_inventory_gap() -> void:
	var p: PackedInt64Array = _params()
	var pr: JWPricing = _new_pricing(JWUnits.BASE_PRICE, WAGE_TYPICAL_UU)
	var supply: PackedInt64Array = _filled(JWUnits.S, 1_000_000)
	var demand: PackedInt64Array = _filled(JWUnits.MARKET_N, 0)
	for s: int in JWUnits.S:
		demand[JWIds.idx_market(s, JWUnits.BuyerClass.HOUSEHOLD)] = 1_000_000  # 供需恰好相等
	var inv_uqs: PackedInt64Array = _filled(JWUnits.CELL, 5_000_000)           # 全部塞满库存
	var target: PackedInt64Array = _filled(JWUnits.CELL, 250_000)

	pr.update_prices(supply, demand, inv_uqs, target, STORABLE, p)
	for s: int in JWUnits.S:
		if STORABLE[s] == 0:
			eq_int(pr.gap_ppm[s], 0,
					"§7.3 (b)：storable == 0 的部门库存偏离项恒为 0（部门 %d）" % s)
			eq_int(pr.price_pending[s], JWUnits.BASE_PRICE,
					"供需相等且库存项为 0 ⇒ 不可库存部门价格不动（部门 %d）" % s)
		else:
			check(pr.gap_ppm[s] < 0,
					"可库存部门库存远超目标 ⇒ gap 必须为负（部门 %d）" % s)


## 检验 INV-068 / T-U-E-09（test_u_price_fixpoint）：
## 缺口恒为 0 时价格序列严格不变，取整偏置不累积；且 log.clamp 行数增量为 0。
## 契约要求 120 季，本测试照跑 120 季并在最后逐位比对。
func test_price_fixpoint_zero_gap_over_120_quarters() -> void:
	var p: PackedInt64Array = _params()
	var pr: JWPricing = _new_pricing(JWUnits.BASE_PRICE, WAGE_TYPICAL_UU)
	var start: PackedInt64Array = pr.price.duplicate()
	var start_wage: PackedInt64Array = pr.wage.duplicate()

	var supply: PackedInt64Array = _filled(JWUnits.S, 1_000_000)
	var demand: PackedInt64Array = _filled(JWUnits.MARKET_N, 0)
	for s: int in JWUnits.S:
		demand[JWIds.idx_market(s, JWUnits.BuyerClass.HOUSEHOLD)] = 1_000_000
	var inv_uqs: PackedInt64Array = _filled(JWUnits.CELL, 250_000)
	var target: PackedInt64Array = _filled(JWUnits.CELL, 250_000)

	var drifted: int = 0
	var swap_failed: int = 0
	for qq: int in 120:
		pr.update_prices(supply, demand, inv_uqs, target, STORABLE, p)
		pr.update_wages(0, 0, 1_000_000, p)
		if pr.swap_pending() != JWResult.OK:
			swap_failed += 1
		for s: int in JWUnits.S:
			if pr.price[s] != start[s]:
				drifted += 1

	eq_int(swap_failed, 0, "swap_pending() 在 S07 写过 pending 后必须成功（120 季）")
	eq_int(drifted, 0,
			"INV-068 / T-U-E-09：缺口恒为 0 时价格序列严格不变（120 季 × 4 部门的漂移次数）")
	eq_int_array(pr.price, start, "T-U-E-09：120 季后价格逐位等于初值")
	eq_int_array(pr.wage, start_wage, "INV-070：缺口为 0 时工资同样不漂移")
	eq_int(pr.clamp_used, 0, "T-U-E-09：无扰动时不得发生任何夹逼")
	eq_int(pr.log_row_count(), 0, "T-U-E-09：log.clamp 行数增量必须为 0")
	for s: int in JWUnits.S:
		eq_int(pr.gap_ppm[s], 0, "供需与库存都无偏离 ⇒ gap_ppm 为 0（部门 %d）" % s)


## 检验 INV-069 / ADV-J06：每次夹逼生效都写 log.clamp 并计数。
## 极端短缺必然同时触发步长夹逼与绝对上界夹逼，二者都必须留痕。
func test_clamp_is_logged_and_counted() -> void:
	var p: PackedInt64Array = _params()
	var pr: JWPricing = _new_pricing(2_490_000_000, WAGE_TYPICAL_UU)
	eq_int(pr.clamp_used, 0, "夹具入口计数应为 0")
	eq_int(pr.log_row_count(), 0, "夹具入口日志应为空")

	var supply: PackedInt64Array = _filled(JWUnits.S, 1)
	var demand: PackedInt64Array = _filled(JWUnits.MARKET_N, 0)
	for s: int in JWUnits.S:
		demand[JWIds.idx_market(s, JWUnits.BuyerClass.HOUSEHOLD)] = JWUnits.QTY_MAX
	var inv_uqs: PackedInt64Array = _filled(JWUnits.CELL, 0)
	var target: PackedInt64Array = _filled(JWUnits.CELL, 250_000)

	pr.update_prices(supply, demand, inv_uqs, target, STORABLE, p)
	ge_int(pr.clamp_used, JWUnits.S,
			"INV-069：4 个部门各至少发生一次夹逼（步长封顶 + 绝对上界），计数不得少于 4")
	ge_int(pr.log_row_count(), pr.clamp_used,
			"INV-069：每次生效的夹逼都必须有一条 log.clamp（ADV-J06 断言 log 行数 ≥ 计数）")
	for s: int in JWUnits.S:
		eq_int(pr.price_pending[s], JWUnits.PRICE_MAX,
				"极端短缺下价格必须停在上界而不是穿过去（部门 %d）" % s)


## 检验 INV-065 / INV-070：swap_pending() 是价格与工资切换的**唯一时点**（S08 §8.7）。
## 切换之前 price_of 必须仍是旧价，切换之后必须逐位等于 pending。
func test_swap_pending_is_the_only_transition_point() -> void:
	var p: PackedInt64Array = _params()
	var pr: JWPricing = _new_pricing(JWUnits.BASE_PRICE, WAGE_TYPICAL_UU)
	var supply: PackedInt64Array = _filled(JWUnits.S, 1_000_000)
	var demand: PackedInt64Array = _filled(JWUnits.MARKET_N, 0)
	for s: int in JWUnits.S:
		demand[JWIds.idx_market(s, JWUnits.BuyerClass.HOUSEHOLD)] = 2_000_000
	var inv_uqs: PackedInt64Array = _filled(JWUnits.CELL, 0)
	var target: PackedInt64Array = _filled(JWUnits.CELL, 250_000)

	pr.update_prices(supply, demand, inv_uqs, target, STORABLE, p)
	pr.update_wages(900_000, 100_000, 1_000_000, p)
	for s: int in JWUnits.S:
		eq_int(pr.price_of(s), JWUnits.BASE_PRICE,
				"INV-065：S07 之后、S08 之前，本季生效价仍是旧价（部门 %d）" % s)
	for k: int in JWUnits.K:
		eq_int(pr.wage_of(k), WAGE_TYPICAL_UU,
				"INV-070：工资同样不在季内出清（技能档 %d）" % k)

	var expected_price: PackedInt64Array = pr.price_pending.duplicate()
	var expected_wage: PackedInt64Array = pr.wage_pending.duplicate()
	var rc: int = pr.swap_pending()
	eq_int(rc, JWResult.OK, "S08 §8.7：pending 已写过时 swap_pending 必须成功")
	eq_int_array(pr.price, expected_price, "S08 后置：price 逐位等于 price_pending")
	eq_int_array(pr.wage, expected_wage, "S08 后置：wage 逐位等于 wage_pending")
	for s: int in JWUnits.S:
		ne_int(pr.price_of(s), JWUnits.BASE_PRICE,
				"swap 之后新价才生效——「只改下一季」的另一半（部门 %d）" % s)


# ══════════════════════════════════════════════════════════════════════════
#  三、工资与租金（INV-070、INV-083）
# ══════════════════════════════════════════════════════════════════════════

## 检验 INV-070 + INV-067 的工资侧：update_wages 只写 wage_pending，
## 步长受 wage_step_max_ppm 约束，硬界受 wage_floor_uu / wage_ceil_uu 约束。
func test_update_wages_writes_pending_only_and_is_bounded() -> void:
	var p: PackedInt64Array = _params()
	var cases: Array[Dictionary] = [
		{"vac": 900_000, "unemp": 100_000, "lf": 1_000_000},   # 极紧，向上顶步长
		{"vac": 0, "unemp": 900_000, "lf": 1_000_000},         # 极松，向下顶步长
		{"vac": 500_000, "unemp": 500_000, "lf": 1_000_000},   # 恰好平衡
		{"vac": 7, "unemp": 3, "lf": 999_983},                 # 不整除，验 floor 偏置
	]
	for c: Dictionary in cases:
		var pr: JWPricing = _new_pricing(JWUnits.BASE_PRICE, WAGE_TYPICAL_UU)
		var before: PackedInt64Array = pr.wage.duplicate()
		var rc: int = pr.update_wages(int(c["vac"]), int(c["unemp"]), int(c["lf"]), p)
		eq_int(rc, JWResult.OK, "update_wages 不应在合法输入上失败")
		eq_int_array(pr.wage, before,
				"INV-070：update_wages 只写 pending，本季生效工资逐位不变")
		var want: int = _expected_wage_pending(WAGE_TYPICAL_UU, int(c["vac"]),
				int(c["unemp"]), int(c["lf"]), p)
		var step: int = JWMath.mul_ppm(WAGE_TYPICAL_UU, W_STEP_MAX_PPM)
		for k: int in JWUnits.K:
			eq_int(pr.wage_pending[k], want,
					"docs/12 §7.3 工资段复算（vac=%d unemp=%d lf=%d，技能档 %d）"
					% [int(c["vac"]), int(c["unemp"]), int(c["lf"]), k])
			le_int(JWMath.absi(pr.wage_pending[k] - before[k]), step,
					"INV-067 工资侧：单季变动不得超过 mul_ppm(wage_cur, wage_step_max_ppm)")
			in_range_int(pr.wage_pending[k], W_FLOOR_TEST_UU, W_CEIL_TEST_UU,
					"INV-070：wage_pending 必须落在 [wage_floor_uu, wage_ceil_uu]")


## 检验 docs/17 §4.9 update_wages 的失败条款：labor_force == 0 时
## 「gap 记 0，不除零」。取空经济体（无劳动力、无空缺、无失业）这一两文档一致的情形。
func test_update_wages_zero_labor_force_does_not_divide_by_zero() -> void:
	var p: PackedInt64Array = _params()
	var pr: JWPricing = _new_pricing(JWUnits.BASE_PRICE, WAGE_TYPICAL_UU)
	var rc: int = pr.update_wages(0, 0, 0, p)
	eq_int(rc, JWResult.OK, "劳动力为 0 是业务情形，不是故障")
	check_false(JWResult.has_pending(),
			"docs/17 §4.9：labor_force == 0 时 gap 记 0，不得触发 DIV_ZERO")
	for k: int in JWUnits.K:
		eq_int(pr.wage_pending[k], WAGE_TYPICAL_UU,
				"gap == 0 ⇒ wage_pending 等于原工资（技能档 %d）" % k)


## 检验 docs/17 §4.9 update_housing_rent 的后置与失败条款：
## 后置 housing_rent[r] > 0；capacity == 0 → 保持原值并写 log.clamp。
## INV-083 的住房恒等式由别的类保证，本函数只定价。
func test_housing_rent_stays_positive_and_zero_capacity_keeps_value() -> void:
	var p: PackedInt64Array = _params()
	var pr: JWPricing = _new_pricing(JWUnits.BASE_PRICE, WAGE_TYPICAL_UU)
	var before: PackedInt64Array = pr.housing_rent.duplicate()
	var occupied: PackedInt64Array = PackedInt64Array([900_000, 500_000, 1_000_000, 0])
	var capacity: PackedInt64Array = PackedInt64Array([1_000_000, 1_000_000, 1_000_000, 0])

	var rc: int = pr.update_housing_rent(occupied, capacity, p)
	eq_int(rc, JWResult.OK, "update_housing_rent 不应在合法输入上失败")
	for r: int in JWUnits.R:
		ge_int(pr.housing_rent[r], 1,
				"docs/17 §4.9 后置：housing_rent[r] > 0（地区 %d）" % r)
	eq_int(pr.housing_rent[3], before[3],
			"docs/17 §4.9 失败条款：capacity == 0 时保持原值（地区 3）")
	ge_int(pr.log_row_count(), 1,
			"docs/17 §4.9：capacity == 0 的那一次必须写 log.clamp")


# ══════════════════════════════════════════════════════════════════════════
#  四、市场配给（INV-059、INV-060、INV-061、INV-064）
# ══════════════════════════════════════════════════════════════════════════

## 检验 INV-061 与 §5.6：Σ demand ≤ supply ⇒ 全额成交，rationing_rule == none。
func test_ration_none_when_supply_covers_demand() -> void:
	var inv: JWInventory = _new_inventory()
	inv.m_supply[JWUnits.Sector.AGRI] = 1_000_000
	inv.m_supply[JWUnits.Sector.MANU] = 1_000_000
	var d: PackedInt64Array = PackedInt64Array([100_000, 50_000, 30_000, 20_000, 10_000, 5_000])
	_set_demand(inv, JWUnits.Sector.AGRI, d)

	var rc: int = inv.ration(0, _new_rng(1))
	eq_int(rc, JWResult.OK, "配给在供给充足时不应失败")
	for b: int in JWUnits.BUYER_CLASS_N:
		eq_int(inv.m_traded[JWIds.idx_market(JWUnits.Sector.AGRI, b)], d[b],
				"§5.6：供给充足则全额成交（买方类 %d）" % b)
		eq_int(inv.m_unmet[JWIds.idx_market(JWUnits.Sector.AGRI, b)], 0,
				"§5.6：全额成交则未满足为 0（买方类 %d）" % b)
	for s: int in JWUnits.S:
		eq_int(inv.m_rule[s], JWUnits.Rationing.NONE,
				"INV-061：充足 ⇒ rationing_rule == none（部门 %d）" % s)


## 检验 INV-060 + INV-061 + §5.6 第一级：公开优先级按买方类下标 0..4 逐档满足，
## 后面的吃剩余。默认优先级即 `0 居民 / 1 公共服务 / 2 政府采购 / 3 企业投入 / 4 出口`。
## 供给 100 000，需求 50 000/30 000/40 000/20 000/10 000（合计 150 000）：
## 居民与公共服务足额，政府采购只剩 20 000，企业与出口为 0。
func test_ration_priority_order_is_public_and_exact() -> void:
	var inv: JWInventory = _new_inventory()
	var s: int = JWUnits.Sector.AGRI
	inv.m_supply[s] = 100_000
	# 第 6 个买方类 FIRM_CAPITAL（R-INVEST-01）排在出口之后：给它 5 000 需求，验证它最后才被满足。
	var d: PackedInt64Array = PackedInt64Array([50_000, 30_000, 40_000, 20_000, 10_000, 5_000])
	_set_demand(inv, s, d)

	var rc: int = inv.ration(0, _new_rng(7))
	eq_int(rc, JWResult.OK, "优先级配给不应失败")
	var want: PackedInt64Array = PackedInt64Array([50_000, 30_000, 20_000, 0, 0, 0])
	eq_int_array(_market_slice(inv, inv.m_traded, s), want,
			"§5.6 第一级：逐档满足、后面的吃剩余（期望 50 000/30 000/20 000/0/0/0，资本品最后）")
	var want_unmet: PackedInt64Array = PackedInt64Array([0, 0, 20_000, 20_000, 10_000, 5_000])
	eq_int_array(_market_slice(inv, inv.m_unmet, s), want_unmet,
			"INV-064：未成交需求必须写 unmet_demand，不得静默消失")
	eq_int(_traded_total(inv, s), inv.m_supply[s],
			"INV-060：Σ alloc == min(可供, Σ 需求) == 供给 100 000")
	eq_int(inv.m_rule[s], JWUnits.Rationing.PRIORITY,
			"INV-061：走了优先级路径 ⇒ rationing_rule == priority")
	for b: int in JWUnits.BUYER_CLASS_N:
		le_int(inv.m_traded[JWIds.idx_market(s, b)], d[b],
				"INV-060：alloc_i ≤ requested_i（买方类 %d）" % b)


## 检验 INV-060 + INV-003 + §5.6 第二级：gov.ration_mode == 1 时按需求量比例，
## 用最大余数法（split_largest_remainder），各项之和精确等于可分配量。
## 100 000 按 50/30/40/20/10（千）拆分 ⇒ 33 333/20 000/26 667/13 333/6 667。
func test_ration_proportional_matches_largest_remainder() -> void:
	var inv: JWInventory = _new_inventory()
	var s: int = JWUnits.Sector.AGRI
	inv.m_supply[s] = 100_000
	var d: PackedInt64Array = PackedInt64Array([50_000, 30_000, 40_000, 20_000, 10_000, 0])
	_set_demand(inv, s, d)

	var rc: int = inv.ration(1, _new_rng(7))
	eq_int(rc, JWResult.OK, "比例配给不应失败")
	var reference: PackedInt64Array = JWMath.split_lr(100_000, d,
			_iota(JWUnits.BUYER_CLASS_N))
	eq_int_array(reference, PackedInt64Array([33_333, 20_000, 26_667, 13_333, 6_667, 0]),
			"最大余数法的算术自检：余下的 2 μQ 给余数最大的政府采购与出口")
	eq_int_array(_market_slice(inv, inv.m_traded, s), reference,
			"§5.6 第二级：档内按需求量比例，走 split_largest_remainder（INV-003）")
	eq_int(_traded_total(inv, s), 100_000,
			"INV-060：Σ alloc 精确等于可分配量，一分不多一分不少")
	eq_int(inv.m_rule[s], JWUnits.Rationing.PROPORTIONAL,
			"INV-061：ration_mode == 1 ⇒ rationing_rule == proportional")
	for b: int in JWUnits.BUYER_CLASS_N:
		le_int(inv.m_traded[JWIds.idx_market(s, b)], d[b],
				"INV-060：alloc_i ≤ requested_i（买方类 %d）" % b)


## 检验 INV-059：逐部门 Σ 成交 + Σ 未满足 == Σ 需求，且 Σ 成交 ≤ 供给。
## 四个部门同时给出「充足 / 短缺 / 零供给 / 零需求」四种形态，一次全覆盖。
func test_ration_conserves_demand_across_all_sectors() -> void:
	var inv: JWInventory = _new_inventory()
	inv.m_supply[0] = 1_000_000        # 充足
	inv.m_supply[1] = 300_000          # 短缺
	inv.m_supply[2] = 0                # 零供给（电力已在 §5.2 分配完）
	inv.m_supply[3] = 500_000          # 零需求
	_set_demand(inv, 0, PackedInt64Array([100_000, 1, 2, 3, 4, 5]))
	_set_demand(inv, 1, PackedInt64Array([200_000, 150_000, 90_000, 7, 33_333, 11]))
	_set_demand(inv, 2, PackedInt64Array([10, 20, 30, 40, 50, 60]))
	_set_demand(inv, 3, PackedInt64Array([0, 0, 0, 0, 0, 0]))

	var rc: int = inv.ration(0, _new_rng(11))
	eq_int(rc, JWResult.OK, "混合形态下配给不应失败")
	for s: int in JWUnits.S:
		eq_int(_traded_total(inv, s) + _unmet_total(inv, s), _demand_total(inv, s),
				"INV-059：Σ 成交 + Σ 未满足 == Σ 需求（部门 %d）" % s)
		le_int(_traded_total(inv, s), inv.m_supply[s],
				"INV-059：Σ 成交 ≤ 供给（部门 %d）" % s)
		for b: int in JWUnits.BUYER_CLASS_N:
			ge_int(inv.m_traded[JWIds.idx_market(s, b)], 0,
					"成交量不得为负（部门 %d 买方类 %d）" % [s, b])
			ge_int(inv.m_unmet[JWIds.idx_market(s, b)], 0,
					"未满足量不得为负（部门 %d 买方类 %d）" % [s, b])


## 检验 §5.6 的分支判定与 INV-064：供给为 0 而需求为正时，
## 全部需求进 unmet；判定式是 `Σ demand <= supply`，0 < 需求 ⇒ 走配给分支而非 none。
func test_ration_zero_supply_leaves_everything_unmet() -> void:
	var inv: JWInventory = _new_inventory()
	var s: int = JWUnits.Sector.MANU
	inv.m_supply[s] = 0
	var d: PackedInt64Array = PackedInt64Array([10, 20, 30, 40, 50, 60])
	_set_demand(inv, s, d)

	var rc: int = inv.ration(0, _new_rng(3))
	eq_int(rc, JWResult.OK, "零供给是业务结果，不是故障")
	eq_int(_traded_total(inv, s), 0, "INV-059：没有供给就没有成交")
	eq_int_array(_market_slice(inv, inv.m_unmet, s), d,
			"INV-064：全部需求原样进 unmet_demand，不得静默消失")
	eq_int(inv.m_rule[s], JWUnits.Rationing.PRIORITY,
			"§5.6：Σ demand(150) > supply(0) ⇒ 走配给分支，rule 不是 none")


## 检验「未售商品进库存不得计为收入」（§5.9 表「需求为 0 而产量 > 0」一行、
## T-S-P04-NO-DEMAND-NO-BONUS、INV-059）。
## 需求为 0 时：成交为 0、未满足为 0、rule 为 none，且配给阶段不得写 sold 流量——
## 按 INV-062 的计价式 mul_div_floor(成交量, 价格, 1e6)，成交为 0 就意味着收入为 0。
func test_unsold_output_is_not_traded_and_yields_no_revenue() -> void:
	var inv: JWInventory = _new_inventory()
	var s: int = JWUnits.Sector.AGRI
	inv.m_supply[s] = 1_000_000_000        # 产量很大
	_set_demand(inv, s, PackedInt64Array([0, 0, 0, 0, 0, 0]))   # 没有任何销路

	var rc: int = inv.ration(0, _new_rng(5))
	eq_int(rc, JWResult.OK, "无需求是正常业务结果")
	eq_int(_traded_total(inv, s), 0, "没有需求就没有成交")
	eq_int(_unmet_total(inv, s), 0, "需求为 0 ⇒ 未满足也为 0")
	eq_int(inv.m_rule[s], JWUnits.Rationing.NONE,
			"INV-061：Σ demand(0) ≤ supply ⇒ rationing_rule == none")
	var revenue_uu: int = JWMath.mul_div_floor(_traded_total(inv, s),
			JWUnits.BASE_PRICE, JWUnits.Q_SCALE)
	eq_int(revenue_uu, 0,
			"INV-062：收入 == mul_div_floor(成交量, 价格, 1e6)；未售出的产量不是成交量")
	eq_int(JWMath.sum(inv.f_sold), 0,
			"§5.6：配给阶段不得写 flow.cell.sold_uqs —— 未售出的货只能留在库存里")


## 检验 §5.6「两级都完全确定」与 ADV-H05（存读档改市场结果）：
## 配给结果不得依赖随机流，换种子必须逐位一致。
func test_ration_is_deterministic_regardless_of_rng() -> void:
	var d0: PackedInt64Array = PackedInt64Array([50_000, 30_000, 40_000, 20_000, 10_000, 5_000])
	var a: JWInventory = _new_inventory()
	a.m_supply[0] = 100_000
	_set_demand(a, 0, d0)
	a.ration(0, _new_rng(1))

	var b: JWInventory = _new_inventory()
	b.m_supply[0] = 100_000
	_set_demand(b, 0, d0)
	b.ration(0, _new_rng(987_654_321))

	eq_int_array(b.m_traded, a.m_traded,
			"§5.6：配给两级都完全确定，换 root_seed 成交必须逐位一致（ADV-H05）")
	eq_int_array(b.m_unmet, a.m_unmet, "§5.6：未满足量同样不得依赖随机流")
	eq_int_array(b.m_rule, a.m_rule, "INV-061：rationing_rule 不得依赖随机流")


## 检验 INV-062 与 ADV-D01（拆单造货）：
## 付款额 == mul_div_floor(成交量_uqs, 价格_uu_per_qs, Q_SCALE)；
## 拆单后的现金差额必须 ≤ 1 μU（ADV-D01 的验收上界），且拆单**不可能多付**。
## 旧写法 idiv_floor(成交量 × 价格, 1e6) 在新刻度下裸乘溢出 271 倍，已作废（INV-062）。
func test_trade_value_is_mul_div_floor_and_split_safe() -> void:
	var price: int = 1_000_000_001                  # 刻意取非整千的病态价（ADV-D01 变体）
	eq_int(JWMath.mul_div_floor(1_234_567, JWUnits.BASE_PRICE, JWUnits.Q_SCALE),
			1_234_567_000, "INV-062：基年价下 1 234 567 μQ_s 的付款额")
	eq_int(JWMath.mul_div_floor(1_234_567, price, JWUnits.Q_SCALE), 1_234_567_001,
			"INV-062：非整千价格下按 floor 计价，余数被截掉而非四舍五入")

	var lot: int = 12_345
	var lots: int = 100
	var whole: int = JWMath.mul_div_floor(lot * lots, price, JWUnits.Q_SCALE)
	var split: int = JWMath.mul_div_floor(lot, price, JWUnits.Q_SCALE) * lots
	ge_int(whole - split, 0, "ADV-D01：拆单只可能少付，不可能多付")
	le_int(whole - split, 1,
			"ADV-D01 验收：若不合并计价，拆 100 笔的现金差额上界为 1 μU")
	eq_int(JWMath.mul_div_floor(JWUnits.QTY_MAX, JWUnits.PRICE_MAX, JWUnits.Q_SCALE),
			2_500_000_000_000_000,
			"INV-062：契约上界处的计价必须走 mul_div_floor（裸乘 2.5×10²¹ 溢出）")
	le_int(JWMath.mul_div_floor(JWUnits.QTY_MAX, JWUnits.PRICE_MAX, JWUnits.Q_SCALE),
			JWUnits.AMOUNT_MAX, "计价结果必须仍在 AMOUNT_MAX 之内")
	check_false(JWResult.has_pending(), "全程走 mul_div_floor，不得登记 INT_OVERFLOW")


## 检验 INV-065 的另一半：平滑「只改下一季」，但**下一季必须真的改**，
## 且下一季的步长以**新的生效价**为基数（docs/12 §7.3 (d) 的被乘数是当季生效价）。
## 若实现把步长基数写死成基年价或上上季价，第二季的落点就会偏。
func test_price_compounds_across_quarters_not_within_one() -> void:
	var p: PackedInt64Array = _params()
	var pr: JWPricing = _new_pricing(JWUnits.BASE_PRICE, WAGE_TYPICAL_UU)
	var supply: PackedInt64Array = _filled(JWUnits.S, 1)
	var demand: PackedInt64Array = _filled(JWUnits.MARKET_N, 0)
	for s: int in JWUnits.S:
		demand[JWIds.idx_market(s, JWUnits.BuyerClass.HOUSEHOLD)] = JWUnits.QTY_MAX
	var inv_uqs: PackedInt64Array = _filled(JWUnits.CELL, 0)
	var target: PackedInt64Array = _filled(JWUnits.CELL, 250_000)

	# 第一季：1 000 000 000 + 3% == 1 030 000 000
	pr.update_prices(supply, demand, inv_uqs, target, STORABLE, p)
	pr.update_wages(0, 0, 1_000_000, p)
	eq_int(pr.swap_pending(), JWResult.OK, "第一季 swap 应成功")
	eq_int(pr.price_of(0), 1_030_000_000,
			"第一季落点：10⁹ + mul_ppm(10⁹, 30 000) == 1 030 000 000")

	# 第二季：步长基数换成 1 030 000 000，30 900 000 ⇒ 1 060 900 000
	pr.update_prices(supply, demand, inv_uqs, target, STORABLE, p)
	pr.update_wages(0, 0, 1_000_000, p)
	eq_int(pr.swap_pending(), JWResult.OK, "第二季 swap 应成功")
	eq_int(JWMath.mul_ppm(1_030_000_000, P_STEP_MAX_PPM), 30_900_000,
			"契约复算：第二季的步长上限以新的生效价为基数")
	eq_int(pr.price_of(0), 1_060_900_000,
			"INV-067：第二季落点 == 1 030 000 000 + 30 900 000，步长基数不得是上上季价")
	le_int(pr.price_of(0), JWUnits.PRICE_MAX, "INV-066：逐季累积仍不得越过绝对上界")


## 检验 docs/10 §9 `derived.price.consumer_index_ppm`（基年 1 000 000、恒 > 0）
## 与 docs/17 §4.9 的失败条款（权重全 0 → 返回 1 000 000）。
## INV-117 的「实际 GDP 不得引用本函数」是静态检查，不在本用例内。
func test_consumer_index_is_base_year_normalized() -> void:
	var pr: JWPricing = _new_pricing(JWUnits.BASE_PRICE, WAGE_TYPICAL_UU)
	eq_int(pr.consumer_index_ppm(_filled(JWUnits.S, 0)), JWUnits.PPM,
			"docs/17 §4.9 失败条款：权重全 0 → 返回 1 000 000（基年）")

	var w: PackedInt64Array = PackedInt64Array([400_000, 300_000, 100_000, 200_000])
	eq_int(pr.consumer_index_ppm(w), JWUnits.PPM,
			"docs/10 §9：价格等于基年价时消费价格指数恒为 1 000 000")

	var doubled: JWPricing = _new_pricing(2 * JWUnits.BASE_PRICE, WAGE_TYPICAL_UU)
	eq_int(doubled.consumer_index_ppm(w), 2 * JWUnits.PPM,
			"全部价格翻倍 ⇒ 指数翻倍（指数是相对基年价的加权比值）")
	ge_int(doubled.consumer_index_ppm(w), 1, "docs/10 §9：consumer_index_ppm 恒 > 0")


## 检验 §7.3 (b) 对「未售商品」的唯一合法出路：
## 卖不掉的产量堆在库存里，只能在下一季**压低**价格，绝不能变成任何形式的收益。
## 供需恰好相等而库存是目标的 5 倍 ⇒ gap 为负，pending 严格小于本季价并顶到步长上限。
func test_unsold_inventory_pushes_next_quarter_price_down() -> void:
	var p: PackedInt64Array = _params()
	var pr: JWPricing = _new_pricing(JWUnits.BASE_PRICE, WAGE_TYPICAL_UU)
	var s: int = JWUnits.Sector.AGRI
	var supply: PackedInt64Array = _filled(JWUnits.S, 1_000_000)
	var demand: PackedInt64Array = _filled(JWUnits.MARKET_N, 0)
	for ss: int in JWUnits.S:
		demand[JWIds.idx_market(ss, JWUnits.BuyerClass.HOUSEHOLD)] = 1_000_000
	var inv_uqs: PackedInt64Array = _filled(JWUnits.CELL, 0)
	var target: PackedInt64Array = _filled(JWUnits.CELL, 0)
	inv_uqs[JWIds.idx_cell(0, s)] = 3_000_000        # 积压
	target[JWIds.idx_cell(0, s)] = 1_000_000

	pr.update_prices(supply, demand, inv_uqs, target, STORABLE, p)
	eq_int(pr.gap_ppm[s], -100_000,
			"§7.3 (b)(c) 复算：clamp(IT−I 的 ppm, ±1e6) == −1e6，乘 cover_gain 10% == −100 000")
	eq_int(pr.price_pending[s], 970_000_000,
			"§7.3 (d)(e) 复算：delta_raw −1×10⁸ 被步长封到 −3×10⁷ ⇒ 10⁹ − 3×10⁷")
	check(pr.price_pending[s] < pr.price[s],
			"积压库存只能压低下季价格，不得抬价（T-S-P04-NO-DEMAND-NO-BONUS 的价格侧）")
	eq_int_array(pr.price, _filled(JWUnits.S, JWUnits.BASE_PRICE),
			"INV-065：压价同样只写 pending，本季生效价不动")
	ge_int(pr.clamp_used, 1, "INV-069：步长封顶生效了，必须计数")
