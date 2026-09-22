## 债券簿与国库的契约单元测试（docs/18 裁定 + docs/12 §2 + docs/10 §14.3）。
##
## 本文件与 sim/ledger/bond_book.gd、sim/ledger/treasury.gd 的实现**相互独立**：
## 全部期望值来自契约文本与内容包，而不是读实现反推出来的。若二者不一致，以契约为准。
##
## 期望值的三个来源，逐条在方法注释里注明：
##   1. docs/12 §2.1 的 02.0/02.3/02.4/02.5/02.6 伪码与「基年剧本的复核」表；
##   2. content/scenarios/chengwan/government_init.json（6 个开局债券批次、年度计划、支付优先级）
##      与 scenario.json（season_factor_ppm.gov_primary = 240000/250000/255000/255000）；
##   3. docs/10 §14.3 的 INV-027…INV-042 与 docs/30 §「T-U-D-*」用例表、docs/31 `ADV-C0*`。
##
## 纪律：JWResult 的故障登记是静态的，会跨测试方法残留；before_each 必须 clear_pending()，
## 否则「只登记本季第一次故障」的语义会让后面的断言读到上一个测试的现场。
extends JWTest

# ── 参数取值（docs/11 §5.15 的首版必备参数默认值表） ────────────────────────
#
# 这些参数在 content/parameters 里尚无身份证（docs/14 的 PR-019 警告列出了 7 项），
# 所以夹具必须自己给值，取 docs/11_data_contract.md §5.15 表中登记的默认值，逐项标注行号来源。

## docs/11 §5.15：`param.default_grace_q` = 2 季
const P_DEFAULT_GRACE_Q: int = 2
## docs/11 §5.15：`param.market_rate_base_ppm` = 10 000 ppm/季
const P_MARKET_RATE_BASE_PPM: int = 10_000
## docs/11 §5.15：`param.market_rate_slope_ppm` = 30 000 ppm
const P_MARKET_RATE_SLOPE_PPM: int = 30_000
## docs/11 §5.15：`param.coupon_min_ppm` / `param.coupon_max_ppm` = 2 000 / 60 000 ppm
const P_COUPON_MIN_PPM: int = 2_000
const P_COUPON_MAX_PPM: int = 60_000
## docs/11 §5.15：`param.household_bond_appetite_ppm` = 600 000 ppm
const P_HOUSEHOLD_BOND_APPETITE_PPM: int = 600_000
## docs/11 §5.15 / JWUnits.BOND_CAP0：`param.bond_batch_cap` = 512 批
const P_BOND_BATCH_CAP: int = 512

# ── 剧本常量（content/scenarios/chengwan/government_init.json，全部 μU，R-SCALE-01 后的新刻度） ──

## `annual_plan.expenditure_incl_interest_uu`（按定义**不含还本**）
const PLAN_EXPENDITURE_INCL_INTEREST_UU: int = 22_000_000_000
## `annual_plan.expenditure_lines_uu.interest`，INV-147 要求它 == 基年四季逐批次票息之和
const PLAN_INTEREST_LINE_UU: int = 2_033_700_000
## docs/12 §2.1 02.0「基年剧本的复核」表：全年到期本金
const YEAR_PRINCIPAL_UU: int = 3_600_000_000
## docs/12 §2.1 02.0：`gov_primary_annual_uu` = 22 000 000 000 − 2 033 700 000
const GOV_PRIMARY_ANNUAL_UU: int = 19_966_300_000
## docs/12 §2.1 02.0：`annual_cash_outflow_plan_uu` = 22 000 000 000 + 3 600 000 000
const ANNUAL_CASH_OUTFLOW_PLAN_UU: int = 25_600_000_000
## `_note_bonds`：开局未偿本金合计 50 U（V-FIN-02）
const SCENARIO_DEBT_TOTAL_UU: int = 50_000_000_000
## `_note_bonds`：国内 34 U / 外部 16 U
const SCENARIO_DEBT_INVPOOL_UU: int = 34_000_000_000
const SCENARIO_DEBT_ROW_UU: int = 16_000_000_000
## `invpool.cash_uu`
const SCENARIO_INVPOOL_CASH_UU: int = 9_000_000_000
## `gov.credit_limit_domestic_uu`
const SCENARIO_CREDIT_LIMIT_DOMESTIC_UU: int = 4_000_000_000

## scenario.json `season_factor_ppm.gov_primary`
const SEASON_GOV_PRIMARY_PPM: PackedInt64Array = [240_000, 250_000, 255_000, 255_000]

## docs/12 §2.1 02.0 的四季基本支出（新刻度下整除，无余数）
const PRIMARY_Q_UU: PackedInt64Array = [
	4_791_912_000, 4_991_575_000, 5_091_406_500, 5_091_406_500,
]

## docs/12 §2.1 02.0「基年剧本的复核」表：基年四季逐批次票息合计
const YEAR_INTEREST_BY_Q_UU: PackedInt64Array = [
	523_500_000, 513_450_000, 503_400_000, 493_350_000,
]

## docs/12 §2.2 的默认支付优先级（8 档全排列），与 government_init.json `payment_priority` 逐项一致
const DEFAULT_PRIORITY: PackedInt64Array = [
	JWUnits.PayLine.DEBT_SERVICE, JWUnits.PayLine.PUBLIC_WAGES,
	JWUnits.PayLine.STATUTORY_TRANSFERS, JWUnits.PayLine.SERVICE_OPEX,
	JWUnits.PayLine.PROJECT_CONTRACTS, JWUnits.PayLine.PROCUREMENT,
	JWUnits.PayLine.SUBSIDIES, JWUnits.PayLine.DISCRETIONARY,
]

# ── 夹具 ───────────────────────────────────────────────────────────────────

var accounts: JWAccount = null
var ledger: JWLedger = null
var bonds: JWBondBook = null
var treasury: JWTreasury = null
var world: JWWorldMarket = null
var params: PackedInt64Array = PackedInt64Array()
var seq: int = 0


func before_each() -> void:
	JWResult.clear_pending()
	JWResult.set_step(JWUnits.Phase.S02)

	accounts = JWAccount.new()
	accounts.allocate()
	ledger = JWLedger.new(accounts)
	ledger.allocate()
	ledger.set_context(0, JWUnits.Phase.S02)
	bonds = JWBondBook.new()
	bonds.allocate()
	treasury = JWTreasury.new()
	treasury.allocate()
	world = JWWorldMarket.new()
	world.allocate()

	params = PackedInt64Array()
	params.resize(JWUnits.PARAM_N)
	params.fill(0)
	params[JWUnits.Param.DEFAULT_GRACE_Q] = P_DEFAULT_GRACE_Q
	params[JWUnits.Param.MARKET_RATE_BASE_PPM] = P_MARKET_RATE_BASE_PPM
	params[JWUnits.Param.MARKET_RATE_SLOPE_PPM] = P_MARKET_RATE_SLOPE_PPM
	params[JWUnits.Param.COUPON_MIN_PPM] = P_COUPON_MIN_PPM
	params[JWUnits.Param.COUPON_MAX_PPM] = P_COUPON_MAX_PPM
	params[JWUnits.Param.HOUSEHOLD_BOND_APPETITE_PPM] = P_HOUSEHOLD_BOND_APPETITE_PPM
	params[JWUnits.Param.BOND_BATCH_CAP] = P_BOND_BATCH_CAP
	params[JWUnits.Param.AMOUNT_MAX_UU] = JWUnits.AMOUNT_MAX
	params[JWUnits.Param.QTY_MAX_UQS] = JWUnits.QTY_MAX
	params[JWUnits.Param.LOG_CAPACITY_ROWS] = JWUnits.LOG_CAP0

	# 支付优先级是剧本值（government_init.json /payment_priority），夹具按 docs/12 §2.2 默认序装填。
	for i: int in JWUnits.PAY_LINE_N:
		treasury.payment_priority[i] = DEFAULT_PRIORITY[i]

	seq = 1000


func after_each() -> void:
	JWResult.clear_pending()


# ── 夹具工具 ───────────────────────────────────────────────────────────────

## 用开账分录（q = −1，INV-023）给某主体注入现金。这是测试里唯一合法的「凭空给钱」路径。
## 开账只在 LOAD 期合法（phase == IDLE），所以临时把账本上下文切回 IDLE，写完立刻切回 S02。
func _fund_cash(agent: int, amount_uu: int) -> void:
	ledger.set_context(-1, JWUnits.Phase.IDLE)
	var rc: int = ledger.post_opening(agent, JWIds.ACC_CASH, amount_uu)
	ledger.set_context(0, JWUnits.Phase.S02)
	if rc != JWResult.OK:
		fail("夹具建立失败：post_opening(agent=%d, ACC_CASH, %d) 返回 %d" % [agent, amount_uu, rc])


func _next_seq() -> int:
	seq += 1
	return seq


## 发行一个批次并在失败时立刻把夹具问题暴露出来（返回批次下标）。
##
## 债券在账本上有两条腿：政府的 ACC_DEBT 与债权人的 ACC_BONDHOLD。剧本存量债的这两条腿
## 由 q = −1 的开账分录生成（INV-023），本夹具照此补齐；否则还本时账本无处冲销，
## 测的就不是国库而是一个残缺的账。
## `outstanding_uu` >= 0 时把未偿本金改写成剧本登记值（面值已还过若干期的存量债），
## 开账腿按未偿本金而不是面值走。
func _issue(issue_q: int, principal_uu: int, coupon_ppm: int, maturity_q: int,
		amortization: int, holder: int, outstanding_uu: int = -1) -> int:
	var b: int = bonds.issue(_next_seq(), issue_q, principal_uu, coupon_ppm,
			maturity_q, amortization, holder)
	if b < 0:
		fail("夹具建立失败：issue(issue_q=%d, face=%d, coupon=%d, maturity=%d) 返回 %d"
				% [issue_q, principal_uu, coupon_ppm, maturity_q, b])
		return b
	var opening_uu: int = principal_uu
	if outstanding_uu >= 0:
		bonds.principal_outstanding[b] = outstanding_uu
		opening_uu = outstanding_uu
	var holder_agent: int = JWIds.AGENT_INVPOOL if holder == JWUnits.Holder.INVPOOL \
			else JWIds.AGENT_ROW
	ledger.set_context(-1, JWUnits.Phase.IDLE)
	var rc_debt: int = ledger.post_opening(JWIds.AGENT_GOV, JWIds.ACC_DEBT, opening_uu)
	var rc_hold: int = ledger.post_opening(holder_agent, JWIds.ACC_BONDHOLD, opening_uu)
	ledger.set_context(0, JWUnits.Phase.S02)
	if rc_debt != JWResult.OK or rc_hold != JWResult.OK:
		fail("夹具建立失败：债券开账腿返回 debt=%d bondhold=%d" % [rc_debt, rc_hold])
	return b


func _sum_interest_due() -> int:
	var t: int = 0
	for b: int in bonds.count:
		t += bonds.interest_due[b]
	return t


func _sum_principal_due() -> int:
	var t: int = 0
	for b: int in bonds.count:
		t += bonds.principal_due[b]
	return t


## 按 docs/12 §2.3 + §2.4 的次序跑一季的计提与排程，返回 (利息, 本金) 之和。
func _accrue_and_schedule(q: int) -> PackedInt64Array:
	var rc_i: int = bonds.accrue_interest(q)
	if rc_i != JWResult.OK:
		fail("q=%d 的 accrue_interest 返回 %d；计提不需要现金，不应产生业务失败（docs/17 §4.11）"
				% [q, rc_i])
	var rc_p: int = bonds.schedule_principal(q)
	if rc_p != JWResult.OK:
		fail("q=%d 的 schedule_principal 返回 %d；读预生成的分期表不应失败（INV-037）" % [q, rc_p])
	return PackedInt64Array([_sum_interest_due(), _sum_principal_due()])


## 装载 government_init.json 的 6 个开局批次。
## 两笔 level_principal 的 `principal_outstanding_uu` 由内容包直接给出（面值已还过若干期），
## 夹具照抄剧本值——它与分期表的一致性正是 INV-037 要检验的对象，不能由夹具自己算出来。
func _load_scenario_bonds() -> void:
	# bond.q-20_01：bullet，8 U，8 000 ppm，q=26 到期，invpool
	_issue(-20, 8_000_000_000, 8_000, 26, JWUnits.Amortization.BULLET, JWUnits.Holder.INVPOOL)
	# bond.q-16_01：bullet，7 U，8 500 ppm，q=34 到期，invpool
	_issue(-16, 7_000_000_000, 8_500, 34, JWUnits.Amortization.BULLET, JWUnits.Holder.INVPOOL)
	# bond.q-12_01：level_principal，面值 14.4 U，9 500 ppm，q=24 到期，invpool，已还 11 期
	_issue(-12, 14_400_000_000, 9_500, 24,
			JWUnits.Amortization.LEVEL_PRINCIPAL, JWUnits.Holder.INVPOOL, 10_000_000_000)
	# bond.q-8_01：level_principal，面值 13.5 U，12 500 ppm，q=19 到期，row，已还 7 期
	_issue(-8, 13_500_000_000, 12_500, 19,
			JWUnits.Amortization.LEVEL_PRINCIPAL, JWUnits.Holder.ROW, 10_000_000_000)
	# bond.q-4_01：bullet，9 U，11 000 ppm，q=12 到期，invpool
	_issue(-4, 9_000_000_000, 11_000, 12, JWUnits.Amortization.BULLET, JWUnits.Holder.INVPOOL)
	# bond.q-2_01：bullet，6 U，13 500 ppm，q=7 到期，row
	_issue(-2, 6_000_000_000, 13_500, 7, JWUnits.Amortization.BULLET, JWUnits.Holder.ROW)


## 某一档的收款方向量。三档的 flow 数组有固定口径长度，调用方必须按该口径给满：
##   statutory_transfers → 36 个群组（flow.gov.pay_transfers_uu[36]）
##   service_opex        → 12 个 (region, service_kind) 槽（flow.gov.pay_opex_uu[12]）
##   subsidies           → 16 个 cell（flow.gov.pay_subsidies_uu[16]）
## 其余档按「逐笔收款方」给，长度自由。
func _line_payees(line: int, target_agent: int) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	if line == JWUnits.PayLine.STATUTORY_TRANSFERS:
		for g: int in JWUnits.GROUP:
			out.append(JWIds.agent_of_group(g))
	elif line == JWUnits.PayLine.SERVICE_OPEX:
		for i: int in JWUnits.OPEX_N:
			out.append(JWIds.agent_of_pubserv(JWMath.floor_div(i, JWUnits.SERVICE_KIND)))
	elif line == JWUnits.PayLine.SUBSIDIES:
		for c: int in JWUnits.CELL:
			out.append(JWIds.agent_of_cell(c))
	else:
		out.append(target_agent)
	return out


## 与 _line_payees 等长的应付额向量：只有 target_agent 对应的那一格非 0。
func _line_dues(line: int, target_agent: int, amount_uu: int) -> PackedInt64Array:
	var payees: PackedInt64Array = _line_payees(line, target_agent)
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(payees.size())
	out.fill(0)
	if payees.size() == 1:
		out[0] = amount_uu
		return out
	for i: int in payees.size():
		if payees[i] == target_agent:
			out[i] = amount_uu
			return out
	fail("夹具建立失败：第 %d 档的收款方向量里找不到 agent %d" % [line, target_agent])
	return out


# ══════════════════════════════════════════════════════════════════════════
# 一、逐批次计息与「固定利率不重定价」
# ══════════════════════════════════════════════════════════════════════════

## INV-036（利息逐批次 floor 计提，禁止求和后乘平均利率）；docs/30 `T-U-D-01`。
func test_coupon_is_per_batch_and_survives_a_new_issue() -> void:
	# docs/30 T-U-D-01 的原始夹具在新刻度下 ×1000：两批面值各 10 000 000 000 μU（10 U）。
	var a: int = _issue(0, 10_000_000_000, 10_000, 20,
			JWUnits.Amortization.BULLET, JWUnits.Holder.INVPOOL)
	var b: int = _issue(0, 10_000_000_000, 20_000, 20,
			JWUnits.Amortization.BULLET, JWUnits.Holder.INVPOOL)
	var coupon_a_at_issue: int = bonds.coupon_ppm[a]
	var coupon_b_at_issue: int = bonds.coupon_ppm[b]

	# 第三批以高得多的票息发行——「重定价」缺陷会在这一刻把 A/B 一起拖上去。
	var c: int = _issue(1, 10_000_000_000, 30_000, 20,
			JWUnits.Amortization.BULLET, JWUnits.Holder.INVPOOL)

	eq_int(bonds.accrue_interest(1), JWResult.OK, "accrue_interest(1) 应成功（计提不需要现金）")
	# mul_div_floor(10 000 000 000, 10 000, 1 000 000) = 100 000 000
	eq_int(bonds.interest_due[a], 100_000_000,
			"批 A 本季利息应为 mul_div_floor(1e10, 10000, 1e6) = 100 000 000 μU（docs/12 §2.3(a)）")
	eq_int(bonds.interest_due[b], 200_000_000,
			"批 B 本季利息应为 mul_div_floor(1e10, 20000, 1e6) = 200 000 000 μU（docs/12 §2.3(a)）")
	eq_int(bonds.interest_due[c], 300_000_000,
			"批 C 本季利息应为 mul_div_floor(1e10, 30000, 1e6) = 300 000 000 μU（docs/12 §2.3(a)）")
	eq_int(bonds.coupon_ppm[a], coupon_a_at_issue,
			"批 A 的 coupon_ppm_per_q 发行后被改写即违反 INV-036「旧债不重定价」")
	eq_int(bonds.coupon_ppm[b], coupon_b_at_issue,
			"批 B 的 coupon_ppm_per_q 发行后被改写即违反 INV-036「旧债不重定价」")

	# 求和后乘平均利率的实现会给出 3 × mul_div_floor(1e10, 20000, 1e6) = 600 000 000，
	# 与逐批次合计恰好相同，因此这里必须断言**逐批次的分布**而不是合计（上面三条已做）。
	eq_int(_sum_interest_due(), 600_000_000,
			"三批合计利息 100 000 000 + 200 000 000 + 300 000 000 = 600 000 000 μU")


## INV-036 / INV-006 / 裁定 R-SCALE-01 连带要求 1：契约上界处必须走 mul_div_floor，裸乘必溢出。
func test_interest_at_contract_ceiling_does_not_overflow() -> void:
	# AMOUNT_MAX(4e15) × coupon_max(60 000) = 2.4e20 > INT64_MAX(9.22e18)：裸乘必登记 INT_OVERFLOW。
	var b: int = _issue(0, JWUnits.AMOUNT_MAX, P_COUPON_MAX_PPM, 8,
			JWUnits.Amortization.BULLET, JWUnits.Holder.INVPOOL)
	JWResult.clear_pending()

	eq_int(bonds.accrue_interest(1), JWResult.OK, "上界处计提不应返回故障码")
	check_false(JWResult.has_pending(),
			"上界处计提登记了故障（码 %d）——说明实现用了裸乘而不是 mul_div_floor（R-SCALE-01 连带要求 1）"
					% JWResult.pending_code())
	eq_int(bonds.interest_due[b],
			JWMath.mul_div_floor(JWUnits.AMOUNT_MAX, P_COUPON_MAX_PPM, JWUnits.PPM),
			"上界处利息应精确等于 mul_div_floor(AMOUNT_MAX, 60000, PPM) = 240 000 000 000 000 μU")


## INV-004（计提余数进 `*_remainder_ppmuu` 累加器，满 1e6 结转 1 μU）；docs/12 §2.3(b)。
func test_interest_remainder_carries_one_uu_when_full() -> void:
	# 面值 3 000 010 μU × 50 000 ppm / 1e6 = 150 000.5 μU/季：
	# 每季 floor 得 150 000，余 500 000 ppm·μU；两季满 1 000 000 结转 1 μU。
	var b: int = _issue(0, 3_000_010, 50_000, 40,
			JWUnits.Amortization.BULLET, JWUnits.Holder.INVPOOL)

	bonds.accrue_interest(1)
	eq_int(bonds.interest_due[b], 150_000,
			"第 1 季 floor(3 000 010 × 0.05) = 150 000 μU（docs/12 §2.3 少付优于多付）")
	eq_int(bonds.interest_remainder[b], 500_000,
			"第 1 季余数应为 (3 000 010 × 50 000) mod 1e6 = 500 000 ppm·μU（INV-004）")

	bonds.accrue_interest(2)
	eq_int(bonds.interest_due[b], 150_001,
			"第 2 季余数累计到 1 000 000，必须结转 1 μU，本季利息 150 001 μU（INV-004）")
	eq_int(bonds.interest_remainder[b], 0,
			"结转后余数应减去 1 000 000 归 0；不归零即长期多付（INV-041）")

	bonds.accrue_interest(3)
	eq_int(bonds.interest_due[b], 150_000, "第 3 季重新 floor，回到 150 000 μU")
	in_range_int(bonds.interest_remainder[b], 0, 999_999,
			"余数累加器任何时刻都必须落在 [0, 999 999]（docs/17 §4.11 后置条件）")


## INV-041（票息余数累加器长期不漂移，120 季累计误差 ≤ 1 μU/批次）；docs/30 `T-X-D-03` 的单元版。
func test_coupon_accrual_does_not_drift_over_120_quarters() -> void:
	# 面值 1 000 000 003 μU × 8 000 ppm 的真值是 8 000 000.024 μU/季，永远除不尽。
	var face: int = 1_000_000_003
	var coupon: int = 8_000
	var b: int = _issue(0, face, coupon, 40, JWUnits.Amortization.BULLET, JWUnits.Holder.INVPOOL)

	var total: int = 0
	var out_of_range: int = 0
	for q: int in range(1, 121):
		bonds.accrue_interest(q)
		total += bonds.interest_due[b]
		if bonds.interest_remainder[b] < 0 or bonds.interest_remainder[b] > 999_999:
			out_of_range += 1

	eq_int(out_of_range, 0, "余数累加器 120 季内必须全程落在 [0, 999 999]（INV-004/INV-041）")
	# 真值下界：floor(120 × 1 000 000 003 × 8 000 / 1e6)。中间量 9.6e14，不溢出。
	var exact_floor: int = JWMath.mul_div_floor(JWMath.mul(120, face), coupon, JWUnits.PPM)
	var drift: int = JWMath.absi(total - exact_floor)
	le_int(drift, 1,
			"120 季累计票息 %d 与真值下界 %d 相差 %d μU，超过 INV-041 的 1 μU/批次上界"
					% [total, exact_floor, drift])


## INV-036：已结清（MATURED）的批次不得继续计息。
func test_matured_batch_stops_accruing_interest() -> void:
	var b: int = _issue(0, 1_000_000_000, 10_000, 1,
			JWUnits.Amortization.BULLET, JWUnits.Holder.INVPOOL)
	_accrue_and_schedule(1)
	eq_int(bonds.principal_due[b], 1_000_000_000,
			"bullet 在 maturity_q 应一次还清全部未偿本金（docs/12 §2.4）")
	eq_int(bonds.apply_principal_payment(b, 1_000_000_000), JWResult.OK, "足额还本应成功")
	eq_int(bonds.principal_outstanding[b], 0, "还清后未偿本金为 0")
	eq_int(bonds.status[b], JWUnits.BondStatus.MATURED,
			"未偿本金归 0 的批次 status 必须转 MATURED（docs/17 §4.11 后置条件）")

	bonds.accrue_interest(2)
	eq_int(bonds.interest_due[b], 0,
			"已 MATURED 的批次本季利息必须为 0；前置条件是 status == ACTIVE 且 outstanding > 0")
	eq_int(bonds.debt_outstanding(), 0, "结清后 Σ active outstanding == 0（INV-035）")


# ══════════════════════════════════════════════════════════════════════════
# 二、到期本金与分期表（INV-037 / docs/12 §01.8）
# ══════════════════════════════════════════════════════════════════════════

## INV-037；docs/12 §1.1 01.8「起点为什么是 issue_q + 1 而不是 issue_q」。
func test_level_principal_schedule_starts_at_issue_q_plus_one() -> void:
	# 面值 8 000 000 003，issue_q = 0，maturity_q = 8 ⇒ n = 8 期，等权重最大余数法：
	# 8 000 000 003 = 8 × 1 000 000 000 + 3 ⇒ 最早的 3 期各 +1 μU。
	var face: int = 8_000_000_003
	var b: int = _issue(0, face, 10_000, 8,
			JWUnits.Amortization.LEVEL_PRINCIPAL, JWUnits.Holder.INVPOOL)

	bonds.schedule_principal(0)
	eq_int(bonds.principal_due[b], 0,
			"发行当季不得还本：第一期落在 issue_q + 1，否则发行季末 outstanding < 面值，INV-035 当季即破")

	var total: int = 0
	for q: int in range(1, 9):
		bonds.schedule_principal(q)
		total += bonds.principal_due[b]
	eq_int(total, face,
			"分期表各期之和必须精确等于面值 %d μU（INV-003/INV-037，等权重最大余数法）" % face)

	bonds.schedule_principal(1)
	eq_int(bonds.principal_due[b], 1_000_000_001,
			"余 3 μU 按最大余数法给最早的 3 期，第 1 期应为 1 000 000 001 μU（docs/12 §1.1 01.8）")
	bonds.schedule_principal(4)
	eq_int(bonds.principal_due[b], 1_000_000_000,
			"第 4 期已不在最早 3 期内，应为 1 000 000 000 μU")
	bonds.schedule_principal(9)
	eq_int(bonds.principal_due[b], 0, "到期季之后不得再排本金（分期表覆盖 issue_q+1 … maturity_q 闭区间）")


## INV-037：`Σ_{q' >= q} scheduled_principal(b, q') == principal_outstanding[b]`（S01 的唯一可执行写法）。
func test_scheduled_principal_tail_equals_outstanding_for_scenario_bonds() -> void:
	_load_scenario_bonds()
	# 剧本值：q-12_01 的 q>=0 剩 25 期 × 400 000 000 = 10 000 000 000；
	#         q-8_01 的 q>=0 剩 20 期 × 500 000 000 = 10 000 000 000（docs/12 §1.1 01.8 复核表）。
	var tail: PackedInt64Array = PackedInt64Array()
	tail.resize(bonds.count)
	tail.fill(0)
	for q: int in range(0, 35):  # 最大 maturity_q == 34
		bonds.schedule_principal(q)
		for b: int in bonds.count:
			tail[b] += bonds.principal_due[b]

	for b: int in bonds.count:
		eq_int(tail[b], bonds.principal_outstanding[b],
				"批次 %d 的 Σ_{q'>=0} 分期额 %d 必须精确等于未偿本金 %d（INV-037；表与账脱钩即 BOND_MISMATCH）"
						% [b, tail[b], bonds.principal_outstanding[b]])
	eq_int(JWMath.sum(tail), SCENARIO_DEBT_TOTAL_UU,
			"六个批次的 q>=0 到期本金合计必须等于开局未偿本金 50 000 000 000 μU（V-FIN-02）")


## INV-035 / INV-107：未偿本金合计与债权人口径是同一套账。
func test_debt_outstanding_matches_scenario_and_splits_by_holder() -> void:
	_load_scenario_bonds()
	eq_int(bonds.debt_outstanding(), SCENARIO_DEBT_TOTAL_UU,
			"开局 Σ active outstanding 必须精确等于 government_init.json 的 50 000 000 000 μU（INV-035）")
	eq_int(bonds.debt_outstanding_of_holder(JWUnits.Holder.INVPOOL), SCENARIO_DEBT_INVPOOL_UU,
			"invpool 持有额应为 8+7+10+9 = 34 000 000 000 μU（_note_bonds「国内 34 U」）")
	eq_int(bonds.debt_outstanding_of_holder(JWUnits.Holder.ROW), SCENARIO_DEBT_ROW_UU,
			"row 持有额应为 10+6 = 16 000 000 000 μU（_note_bonds 登记的外部 16 U，INV-107）")
	eq_int(bonds.debt_outstanding_of_holder(JWUnits.Holder.INVPOOL)
			+ bonds.debt_outstanding_of_holder(JWUnits.Holder.ROW), bonds.debt_outstanding(),
			"两个债权人口径之和必须精确等于债务总额，否则 INV-025 在季末必破")


## INV-028 / INV-035：超额还本是表与账脱钩，必须 Fault.BOND_MISMATCH 而不是静默截断。
func test_over_payment_of_principal_is_a_fault() -> void:
	var b: int = _issue(0, 1_000_000_000, 10_000, 8,
			JWUnits.Amortization.BULLET, JWUnits.Holder.INVPOOL)
	JWResult.clear_pending()

	var rc: int = bonds.apply_principal_payment(b, 1_000_000_001)
	rejects(rc, JWResult.OK, "还本额超过未偿本金 1 μU 必须被拒（docs/17 §4.11 前置：amount <= outstanding）")
	eq_int(rc, JWResult.Fault.BOND_MISMATCH, "超额还本的失败码应为 Fault.BOND_MISMATCH")
	eq_int(bonds.principal_outstanding[b], 1_000_000_000,
			"被拒的还本不得改动未偿本金（禁止静默改账）")


## INV-038：未付到期本金不得自动展期——余额与分期表都不许被挪到后面的季度。
func test_unpaid_principal_is_not_silently_rolled_over() -> void:
	var b: int = _issue(0, 1_000_000_000, 10_000, 1,
			JWUnits.Amortization.BULLET, JWUnits.Holder.INVPOOL)
	_accrue_and_schedule(1)
	var due_at_maturity: int = bonds.principal_due[b]
	eq_int(due_at_maturity, 1_000_000_000, "q=1 是到期季，应排出全部本金")

	# 不支付，直接登记欠付（S02 §2.5 的短缺分支）。
	eq_int(bonds.register_interest_arrears(b, due_at_maturity), JWResult.OK,
			"登记欠付是业务性短缺，不应失败（docs/17 §4.11）")
	eq_int(bonds.status[b], JWUnits.BondStatus.DEFAULTED,
			"欠付登记后批次 status 必须转 DEFAULTED（INV-030/INV-038）")
	eq_int(bonds.principal_outstanding[b], 1_000_000_000,
			"未付本金不得从未偿余额里消失——那等于静默减记（INV-028）")

	bonds.schedule_principal(2)
	eq_int(bonds.principal_due[b], 0,
			"到期季之后不得再排出本金：若为非 0，说明实现把未付本金自动展期到了下一季（INV-038，ADV-C01）")
	eq_int(bonds.debt_outstanding(), 1_000_000_000,
			"违约不减记：Σ active outstanding 必须保持 1 000 000 000 μU（INV-028/INV-035）")


## INV-038：`debt_service_next4q` 是市场利率的输入，必须等于未来四季利息 + 本金。
func test_debt_service_next4q_covers_exactly_four_quarters() -> void:
	# 单批 level_principal：面值 4 000 000 000，8 期，每期 500 000 000（整除，无余数）。
	var b: int = _issue(0, 4_000_000_000, 10_000, 8,
			JWUnits.Amortization.LEVEL_PRINCIPAL, JWUnits.Holder.INVPOOL)
	var expect: int = 0
	# 逐季模拟 q=1..4：先计提再排本金再还本，累加得到「未来四季偿债额」的契约口径。
	var snapshot: int = bonds.principal_outstanding[b]
	for q: int in range(1, 5):
		var sums: PackedInt64Array = _accrue_and_schedule(q)
		expect += sums[0] + sums[1]
		bonds.apply_principal_payment(b, bonds.principal_due[b])
	# 还原余额后再问 next4q，保证二者站在同一个时点上。
	bonds.principal_outstanding[b] = snapshot
	bonds.status[b] = JWUnits.BondStatus.ACTIVE

	ge_int(expect, 0, "未来四季偿债额不应为负（夹具自检）")
	eq_int(bonds.debt_service_next4q(1), expect,
			"debt_service_next4q(1) 应等于 q=1..4 的逐批次利息 + 到期本金合计 %d μU（docs/17 §4.11）"
					% expect)


# ══════════════════════════════════════════════════════════════════════════
# 三、R-SEASON-01：季节系数的作用基数
# ══════════════════════════════════════════════════════════════════════════

## INV-042：`Σ season_factor_ppm == 1 000 000`（加载期断言的可执行写法）。
func test_season_factor_sums_to_one_million() -> void:
	eq_int(JWMath.sum(SEASON_GOV_PRIMARY_PPM), JWUnits.PPM,
			"scenario.json 的 gov_primary 季节系数 240000+250000+255000+255000 必须为 1 000 000（INV-042）")
	eq_int(SEASON_GOV_PRIMARY_PPM.size(), 4, "季节系数必须是四季（docs/11 §5.2）")


## INV-147 / docs/30 `T-U-D-14`：年度计划的利息项 == 基年四季逐批次票息之和。
## 同时是 R-SEASON-01 的输入：`interest_year_uu` 必须由 bond_book 算出来，不是抄计划表。
func test_scenario_year_interest_equals_annual_plan_line() -> void:
	_load_scenario_bonds()
	var interest_year: int = 0
	var principal_year: int = 0
	for q: int in range(0, 4):
		var sums: PackedInt64Array = _accrue_and_schedule(q)
		eq_int(sums[0], YEAR_INTEREST_BY_Q_UU[q],
				"基年第 %d 季逐批次票息合计应为 %d μU（docs/12 §2.1 02.0 复核表）"
						% [q, YEAR_INTEREST_BY_Q_UU[q]])
		interest_year += sums[0]
		principal_year += sums[1]
		for b: int in bonds.count:
			if bonds.principal_due[b] > 0:
				bonds.apply_principal_payment(b, bonds.principal_due[b])

	eq_int(interest_year, PLAN_INTEREST_LINE_UU,
			"基年全年逐批次票息 %d 必须逐 μU 等于 annual_plan.expenditure_lines_uu.interest = 2 033 700 000（INV-147 / V-FIN-05）"
					% interest_year)
	eq_int(principal_year, YEAR_PRINCIPAL_UU,
			"基年全年到期本金应为两笔 level_principal 各 4 × 400 000 000 与 4 × 500 000 000 = 3 600 000 000 μU")


## 裁定 R-SEASON-01 + INV-042：季节系数只作用于「年度支出 − 利息 − 还本」，
## 且 docs/12 §2.1 02.0 的**三条校验式必须同时成立**。
func test_season_factor_base_excludes_interest_and_principal() -> void:
	var gov_primary_annual: int = PLAN_EXPENDITURE_INCL_INTEREST_UU - PLAN_INTEREST_LINE_UU
	eq_int(gov_primary_annual, GOV_PRIMARY_ANNUAL_UU,
			"基本支出年额 = 22 000 000 000 − 2 033 700 000 = 19 966 300 000 μU（R-SEASON-01 (c)）")

	var tiebreak: PackedInt64Array = PackedInt64Array([0, 1, 2, 3])
	var parts: PackedInt64Array = JWMath.split_lr(gov_primary_annual, SEASON_GOV_PRIMARY_PPM, tiebreak)
	eq_int(parts.size(), 4, "最大余数法拆四季应返回 4 项（拆分失败时 split_lr 返回空数组）")
	for t: int in 4:
		eq_int(parts[t], PRIMARY_Q_UU[t],
				"第 %d 季基本支出应为 %d μU（docs/12 §2.1 02.0 复核表；新刻度下整除，无余数）"
						% [t, PRIMARY_Q_UU[t]])

	# 校验式 1：四季合计 == 基本支出年额（最大余数法的后置断言，INV-003）
	eq_int(JWMath.sum(parts), gov_primary_annual,
			"四季合计必须精确等于基本支出年额 %d μU（INV-003/INV-042）" % gov_primary_annual)
	# 校验式 2：四季合计 + 全年利息 + 全年还本 == 现金口径年计划（钉住「还本也在现金计划里」）
	eq_int(JWMath.sum(parts) + PLAN_INTEREST_LINE_UU + YEAR_PRINCIPAL_UU,
			ANNUAL_CASH_OUTFLOW_PLAN_UU,
			"四季合计 + 利息 + 还本必须等于 annual_cash_outflow_plan_uu = 25 600 000 000 μU（R-SEASON-01 校验式 2）")
	# 校验式 3：四季合计 + 全年利息 == 支出口径年计划（钉住「还本不是支出」）
	eq_int(JWMath.sum(parts) + PLAN_INTEREST_LINE_UU, PLAN_EXPENDITURE_INCL_INTEREST_UU,
			"四季合计 + 利息必须等于 expenditure_incl_interest_uu = 22 000 000 000 μU（R-SEASON-01 校验式 3）")


## 裁定 R-SEASON-01：用错基数（拿支出总额或现金口径总额去乘季节系数）必须被上面的三条校验式抓住。
## 本测试证明「基数选错」是可观测的，而不是一个无差别的记法问题。
func test_wrong_season_base_is_detectable() -> void:
	var tiebreak: PackedInt64Array = PackedInt64Array([0, 1, 2, 3])
	var wrong_a: PackedInt64Array = JWMath.split_lr(
			PLAN_EXPENDITURE_INCL_INTEREST_UU, SEASON_GOV_PRIMARY_PPM, tiebreak)
	var wrong_b: PackedInt64Array = JWMath.split_lr(
			ANNUAL_CASH_OUTFLOW_PLAN_UU, SEASON_GOV_PRIMARY_PPM, tiebreak)

	ne_int(wrong_a[0], PRIMARY_Q_UU[0],
			"以「支出总额 22 000 000 000」为基数会给出 5 280 000 000 μU，与契约的 4 791 912 000 不同——"
			+ "若实现两者都通过，说明校验式没有真的跑")
	ne_int(wrong_b[0], PRIMARY_Q_UU[0],
			"以「现金口径 25 600 000 000」为基数会给出 6 144 000 000 μU，同样与契约值不同")
	ne_int(JWMath.sum(wrong_a) + PLAN_INTEREST_LINE_UU, PLAN_EXPENDITURE_INCL_INTEREST_UU,
			"错基数下「四季合计 + 利息 == 22 000 000 000」必然不成立，这正是校验式 3 的作用")


# ══════════════════════════════════════════════════════════════════════════
# 四、国库：偿债支付、欠付、延期、禁止无提示负余额
# ══════════════════════════════════════════════════════════════════════════

## INV-039：`payment_priority` 是 8 类支出的全排列；docs/30 `T-U-D-10` ①。
func test_payment_priority_is_a_permutation_of_eight_lines() -> void:
	eq_int(treasury.payment_priority.size(), JWUnits.PAY_LINE_N,
			"payment_priority 必须恰好 8 项（docs/12 §2.2）")
	var seen: PackedInt64Array = PackedInt64Array()
	seen.resize(JWUnits.PAY_LINE_N)
	seen.fill(0)
	var out_of_range: int = 0
	for i: int in treasury.payment_priority.size():
		var v: int = treasury.payment_priority[i]
		if v < 0 or v >= JWUnits.PAY_LINE_N:
			out_of_range += 1
		else:
			seen[v] += 1
	eq_int(out_of_range, 0, "payment_priority 的每一项都必须落在 [0, 7]")
	for line: int in JWUnits.PAY_LINE_N:
		eq_int(seen[line], 1,
				"第 %d 档在 payment_priority 中出现 %d 次；全排列要求恰好一次（INV-039）" % [line, seen[line]])


## INV-027 / INV-028 / INV-035 / INV-016：现金充足时到期利息与本金必须足额支付。
func test_debt_service_pays_in_full_when_cash_suffices() -> void:
	var b: int = _issue(0, 1_000_000_000, 10_000, 1,
			JWUnits.Amortization.BULLET, JWUnits.Holder.INVPOOL)
	var sums: PackedInt64Array = _accrue_and_schedule(1)
	var obligations: int = sums[0] + sums[1]
	eq_int(obligations, 1_010_000_000,
			"到期义务 = 利息 mul_div_floor(1e9, 10000, 1e6)=10 000 000 + 本金 1 000 000 000")

	_fund_cash(JWIds.AGENT_GOV, obligations)
	treasury.begin_quarter(accounts)
	var holder_before: int = accounts.cash_of(JWIds.AGENT_INVPOOL)

	eq_int(treasury.pay_debt_service(bonds, ledger, accounts, 1, params), JWResult.OK,
			"现金充足时 pay_debt_service 不应返回失败")
	eq_int(treasury.f_interest_paid, 10_000_000, "flow.gov.interest_paid_uu 应等于本季应付利息")
	eq_int(treasury.f_principal_paid, 1_000_000_000, "flow.gov.principal_paid_uu 应等于本季到期本金")
	eq_int(accounts.cash_of(JWIds.AGENT_GOV), 0,
			"国库现金应恰好用尽：cash_end == cash_start − 利息 − 还本，残差必须为 0（INV-027）")
	eq_int(accounts.cash_of(JWIds.AGENT_INVPOOL) - holder_before, obligations,
			"债权人现金必须同额增加——融资与偿债都必须有对手方（INV-026）")
	eq_int(treasury.arrears, 0, "足额支付后不得产生任何欠付（INV-030）")
	eq_int(bonds.debt_outstanding(), 0,
			"还清后 debt == Σ active outstanding == 0（INV-028/INV-035）")
	eq_int(bonds.status[b], JWUnits.BondStatus.MATURED, "还清的批次应转 MATURED，而不是停在 ACTIVE")


## INV-016 / ADV-C04：现金为 0 时短缺必须显露为欠付，**不得出现负国库余额，也不得报故障**。
func test_debt_service_shortfall_becomes_arrears_not_negative_cash() -> void:
	var b: int = _issue(0, 1_000_000_000, 20_000, 1,
			JWUnits.Amortization.BULLET, JWUnits.Holder.INVPOOL)
	var sums: PackedInt64Array = _accrue_and_schedule(1)
	var obligations: int = sums[0] + sums[1]
	eq_int(obligations, 1_020_000_000, "到期义务 = 20 000 000 利息 + 1 000 000 000 本金")

	treasury.begin_quarter(accounts)
	var arrears_before: int = treasury.arrears
	JWResult.clear_pending()
	treasury.pay_debt_service(bonds, ledger, accounts, 1, params)

	ge_int(accounts.cash_of(JWIds.AGENT_GOV), 0,
			"国库现金任何时刻都必须 >= 0；先扣成负数再想办法是 INV-016 明令禁止的路径")
	check_false(JWResult.has_pending(),
			"现金不足是**业务性短缺**（ARREARS 语义），不是故障；此处登记了故障码 %d（docs/12 §0.6）"
					% JWResult.pending_code())
	eq_int(treasury.arrears - arrears_before, obligations,
			"一分未付时新增欠付必须精确等于全部到期义务 %d μU（INV-030）" % obligations)
	eq_int(treasury.arrears, JWMath.sum(treasury.arrears_by_payee),
			"arrears 必须恒等于 Σ arrears_by_payee（INV-030）")
	eq_int(bonds.status[b], JWUnits.BondStatus.DEFAULTED,
			"未获清偿的批次必须转 DEFAULTED（docs/12 §2.5），否则违约在状态里不可见")
	eq_int(bonds.debt_outstanding(), 1_000_000_000,
			"未付本金不得减记：debt_end == debt_start + 借款 − 还本 − 确认减记（INV-028）")
	eq_int(treasury.f_interest_paid, 0, "一分未付时 flow.gov.interest_paid_uu 必须为 0")
	eq_int(treasury.f_principal_paid, 0, "一分未付时 flow.gov.principal_paid_uu 必须为 0")


## INV-039 / docs/12 §2.5：债务档内利息先于本金；现金只够利息时本金必须整笔转欠付。
func test_debt_service_pays_interest_before_principal() -> void:
	var b: int = _issue(0, 1_000_000_000, 20_000, 1,
			JWUnits.Amortization.BULLET, JWUnits.Holder.INVPOOL)
	_accrue_and_schedule(1)
	var interest_due: int = bonds.interest_due[b]
	var principal_due: int = bonds.principal_due[b]

	_fund_cash(JWIds.AGENT_GOV, interest_due)
	treasury.begin_quarter(accounts)
	JWResult.clear_pending()
	treasury.pay_debt_service(bonds, ledger, accounts, 1, params)

	eq_int(treasury.f_interest_paid, interest_due,
			"现金恰好等于应付利息时利息必须足额支付（docs/12 §2.5 的支付次序：利息在前）")
	eq_int(treasury.f_principal_paid, 0, "现金已用尽，本金必须一分未付")
	eq_int(treasury.arrears, principal_due,
			"欠付必须精确等于未付本金 %d μU，不多不少（INV-030）" % principal_due)
	eq_int(accounts.cash_of(JWIds.AGENT_GOV), 0, "国库现金用尽后为 0，不得为负（INV-016）")
	eq_int(bonds.principal_outstanding[b], principal_due,
			"未付的本金仍挂在未偿余额上（INV-028/INV-035）")


## INV-040 / docs/30 `T-S-D-12`：连续付不出第 1 档要累计成宽限期计数，且足额支付后归零。
func test_default_streak_counts_consecutive_failed_debt_service() -> void:
	# 每季**当季**新发一个长期 bullet 批次。这样第 q 季一定存在一个此前从未计提过、状态必为
	# ACTIVE 的批次，「本季第 1 档有应付额」不依赖「已违约批次是否继续计息」这个契约未明确的
	# 问题（docs/12 §2.3 的前置只写 status == active）。
	var q_ok: int = P_DEFAULT_GRACE_Q + 2
	treasury.begin_quarter(accounts)
	JWResult.clear_pending()

	for q: int in range(1, P_DEFAULT_GRACE_Q + 2):
		_issue(q - 1, 1_000_000_000, 20_000, 30,
				JWUnits.Amortization.BULLET, JWUnits.Holder.INVPOOL)
		_accrue_and_schedule(q)
		ge_int(_sum_interest_due(), 1,
				"夹具自检：第 %d 季必须存在应付利息，否则「付不出第 1 档」无从谈起" % q)
		treasury.pay_debt_service(bonds, ledger, accounts, q, params)
		eq_int(treasury._default_streak_q, q,
				"第 %d 个连续付不出第 1 档的季度，_default_streak_q 应为 %d（INV-040 的宽限期计数）"
						% [q, q])

	ge_int(treasury._default_streak_q, P_DEFAULT_GRACE_Q + 1,
			"连续 param.default_grace_q(%d) + 1 季付不出第 1 档后，计数必须已越过宽限期（INV-040）"
					% P_DEFAULT_GRACE_Q)

	# 补足现金并足额支付一季：连续计数必须归零，否则宽限期会被历史违约永久污染。
	_issue(q_ok - 1, 1_000_000_000, 20_000, 30,
			JWUnits.Amortization.BULLET, JWUnits.Holder.INVPOOL)
	_accrue_and_schedule(q_ok)
	_fund_cash(JWIds.AGENT_GOV, 100_000_000_000)
	treasury.pay_debt_service(bonds, ledger, accounts, q_ok, params)
	eq_int(treasury._default_streak_q, 0,
			"足额支付第 1 档后 _default_streak_q 必须归零；「连续」两字要求计数可被打断（INV-040）")


## INV-030 / docs/30 `T-U-A-07`：add_arrears 是欠付的唯一入口，且三处登记必须同步。
func test_add_arrears_keeps_total_and_per_payee_in_sync() -> void:
	var payee: int = JWIds.agent_of_group(0)
	treasury.add_arrears(payee, 300_000_000, JWUnits.PayLine.STATUTORY_TRANSFERS)

	eq_int(treasury.arrears, 300_000_000, "gov.arrears_uu 增量应为 300 000 000 μU（T-U-A-07）")
	eq_int(treasury.arrears_by_payee[payee], 300_000_000, "同额记在该收款方名下")
	eq_int(treasury.arrears, JWMath.sum(treasury.arrears_by_payee),
			"arrears == Σ arrears_by_payee（INV-030）；不等即欠付被单边登记")
	eq_int(treasury.f_arrears_added[payee], 300_000_000,
			"flow.gov.arrears_added_uu 必须同步登记，否则季末的 INV-030 恒等式无从对账")

	treasury.add_arrears(payee, 200_000_000, JWUnits.PayLine.STATUTORY_TRANSFERS)
	eq_int(treasury.arrears, 500_000_000, "第二笔欠付应累加，不是覆盖")
	eq_int(treasury.f_arrears_added[payee], 500_000_000, "flow 同样累加")
	ge_int(treasury.arrears, 0, "arrears 恒 >= 0（INV-030）")


## INV-030：超额清偿欠付是账不平，必须 Fault.LEDGER_IMBALANCE，且不得改动欠付余额。
func test_clear_arrears_rejects_over_clearing() -> void:
	var payee: int = JWIds.agent_of_group(1)
	treasury.add_arrears(payee, 100_000_000, JWUnits.PayLine.SERVICE_OPEX)
	_fund_cash(JWIds.AGENT_GOV, 1_000_000_000)
	JWResult.clear_pending()

	var rc: int = treasury.clear_arrears(payee, 100_000_001, ledger, accounts)
	rejects(rc, JWResult.OK, "清偿额超过该收款方欠付 1 μU 必须被拒（docs/17 §4.12 前置条件）")
	eq_int(rc, JWResult.Fault.LEDGER_IMBALANCE, "超额清偿的失败码应为 Fault.LEDGER_IMBALANCE")
	eq_int(treasury.arrears_by_payee[payee], 100_000_000, "被拒的清偿不得改动欠付余额")
	eq_int(treasury.arrears, JWMath.sum(treasury.arrears_by_payee),
			"失败路径之后 arrears 与逐收款方之和仍须一致（INV-030）")


## INV-033：预留只减少可用额度，不产生任何现金移动；季末必须归零。
func test_reserve_moves_no_cash_and_releases_to_zero() -> void:
	_fund_cash(JWIds.AGENT_GOV, 1_000_000_000)
	var cash_before: int = accounts.cash_of(JWIds.AGENT_GOV)

	eq_int(treasury.reserve(400_000_000, accounts), JWResult.OK, "额度内的预留应被接受")
	eq_int(accounts.cash_of(JWIds.AGENT_GOV), cash_before,
			"预留**不写任何资金行**：混记会让 INV-027 失衡（docs/12 §2.2）")
	eq_int(treasury.reserved_memo, 400_000_000, "reserved_memo 应记 400 000 000 μU")
	le_int(treasury.reserved_memo, accounts.cash_of(JWIds.AGENT_GOV),
			"reserved_memo <= cash（INV-033）")

	var rc: int = treasury.reserve(700_000_000, accounts)
	rejects(rc, JWResult.OK, "可用额度只剩 600 000 000，再预留 700 000 000 必须被拒")
	eq_int(rc, JWResult.Reject.BUDGET_INSUFFICIENT, "额度不足的拒绝码应为 Reject.BUDGET_INSUFFICIENT")
	eq_int(treasury.reserved_memo, 400_000_000, "被拒的预留不得改动 reserved_memo")
	eq_int(accounts.cash_of(JWIds.AGENT_GOV), cash_before, "被拒路径同样不得移动现金")

	eq_int(treasury.release_reservations(), JWResult.OK, "释放预留应成功")
	eq_int(treasury.reserved_memo, 0, "预留必须季末归零：要么执行要么释放（INV-033）")


## INV-003 / INV-030 / INV-039：一档之内按收款方拆分必须精确，短缺部分转欠付并置延期标记。
func test_pay_line_split_is_exact_and_shortfall_becomes_arrears() -> void:
	# 法定转移的收款方口径是 36 个群组（flow.gov.pay_transfers_uu[36]），
	# 因此 due_by_payee 按群组稠密下标给，只有 3 个组有应付额。
	var payees: PackedInt64Array = PackedInt64Array()
	var due: PackedInt64Array = PackedInt64Array()
	for g: int in JWUnits.GROUP:
		payees.append(JWIds.agent_of_group(g))
		due.append(0)
	due[3] = 300_000_001
	due[4] = 200_000_000
	due[5] = 100_000_000
	var total_due: int = JWMath.sum(due)

	# 现金只有应付额的一半左右，强制走「部分支付 + 欠付」分支。
	_fund_cash(JWIds.AGENT_GOV, 300_000_000)
	treasury.begin_quarter(accounts)
	JWResult.clear_pending()

	treasury.pay_line(JWUnits.PayLine.STATUTORY_TRANSFERS, payees, due,
			JWUnits.Kind.TRANSFER, ledger, accounts)

	var paid: int = 0
	for g: int in JWUnits.GROUP:
		paid += accounts.cash_of(JWIds.agent_of_group(g))
	eq_int(paid, 300_000_000,
			"可用现金 300 000 000 必须被全额派出去（部分支付，不得少付也不得多付）")
	ge_int(accounts.cash_of(JWIds.AGENT_GOV), 0, "国库现金不得为负（INV-016）")
	eq_int(paid + treasury.arrears, total_due,
			"实付 %d + 欠付 %d 必须精确等于应付 %d μU；差一分即 INV-003/INV-030 破裂"
					% [paid, treasury.arrears, total_due])
	eq_int(treasury.arrears, JWMath.sum(treasury.arrears_by_payee),
			"欠付总额与逐收款方之和必须一致（INV-030）")
	eq_int(treasury.deferral_flag[JWUnits.PayLine.STATUTORY_TRANSFERS], 1,
			"未足额支付的档必须置 deferral_flag = 1（docs/17 §4.12 后置条件）")
	check_false(JWResult.has_pending(),
			"部分支付是业务性短缺而非故障，此处登记了故障码 %d" % JWResult.pending_code())


## INV-039 / docs/30 `T-U-D-10` ②③④⑤：现金恰好够前 3 档时，第 4..8 档必须一分未付。
func test_priority_order_pays_top_lines_and_defers_the_rest() -> void:
	# 第 1 档（debt_service）走 S02 的 pay_debt_service；第 2..8 档走 S04 的 pay_line。
	_issue(0, 1_000_000_000, 10_000, 1,
			JWUnits.Amortization.BULLET, JWUnits.Holder.INVPOOL)
	var sums: PackedInt64Array = _accrue_and_schedule(1)
	var debt_due: int = sums[0] + sums[1]  # 10 000 000 + 1 000 000 000

	# 各档的应付额。第 2/3 档足以吃光剩余现金，第 4..8 档必须一分未付。
	var line_due: PackedInt64Array = PackedInt64Array([
		0,            # 第 1 档由 pay_debt_service 处理
		300_000_000,  # public_wages
		200_000_000,  # statutory_transfers
		50_000_000,   # service_opex
		50_000_000,   # project_contracts
		50_000_000,   # procurement
		50_000_000,   # subsidies
		50_000_000,   # discretionary
	])
	# 每档一个**专属**收款方，才能逐档量出实付额（互不重叠：群组 21+、pubserv 17..20、cell 1..16）。
	var line_payee: PackedInt64Array = PackedInt64Array([
		JWIds.AGENT_INVPOOL,                # 第 1 档：债权人
		JWIds.agent_of_group(0),            # public_wages
		JWIds.agent_of_group(1),            # statutory_transfers
		JWIds.agent_of_pubserv(0),          # service_opex
		JWIds.agent_of_cell(1),             # project_contracts
		JWIds.agent_of_cell(2),             # procurement
		JWIds.agent_of_cell(0),             # subsidies
		JWIds.agent_of_group(2),            # discretionary
	])
	var line_kind: PackedInt64Array = PackedInt64Array([
		JWUnits.Kind.BOND_INTEREST, JWUnits.Kind.PUBLIC_WAGE_PAYMENT, JWUnits.Kind.TRANSFER,
		JWUnits.Kind.SERVICE_OPEX, JWUnits.Kind.PROJECT_PAYMENT, JWUnits.Kind.GOV_PROCUREMENT,
		JWUnits.Kind.SUBSIDY, JWUnits.Kind.TRANSFER,
	])

	# 现金恰好等于前 3 档（debt_service + public_wages + statutory_transfers）之和。
	var cash: int = debt_due + line_due[1] + line_due[2]
	_fund_cash(JWIds.AGENT_GOV, cash)
	treasury.begin_quarter(accounts)
	JWResult.clear_pending()

	for i: int in JWUnits.PAY_LINE_N:
		var line: int = treasury.payment_priority[i]
		if line == JWUnits.PayLine.DEBT_SERVICE:
			treasury.pay_debt_service(bonds, ledger, accounts, 1, params)
			continue
		var payee: PackedInt64Array = _line_payees(line, line_payee[line])
		var due: PackedInt64Array = _line_dues(line, line_payee[line], line_due[line])
		treasury.pay_line(line, payee, due, line_kind[line], ledger, accounts)

	eq_int(treasury.f_interest_paid + treasury.f_principal_paid, debt_due,
			"第 1 档必须足额支付 %d μU（INV-039：实际支付顺序与优先级一致）" % debt_due)
	eq_int(accounts.cash_of(line_payee[JWUnits.PayLine.PUBLIC_WAGES]),
			line_due[JWUnits.PayLine.PUBLIC_WAGES],
			"第 2 档 public_wages 必须足额支付 300 000 000 μU")
	eq_int(accounts.cash_of(line_payee[JWUnits.PayLine.STATUTORY_TRANSFERS]),
			line_due[JWUnits.PayLine.STATUTORY_TRANSFERS],
			"第 3 档 statutory_transfers 必须足额支付 200 000 000 μU")

	var deferred_total: int = 0
	for line: int in range(JWUnits.PayLine.SERVICE_OPEX, JWUnits.PAY_LINE_N):
		eq_int(accounts.cash_of(line_payee[line]), 0,
				"第 %d 档在现金耗尽后必须一分未付（T-U-D-10 ③）" % (line + 1))
		eq_int(treasury.deferral_flag[line], 1, "第 %d 档必须置延期标记（INV-039）" % (line + 1))
		deferred_total += line_due[line]

	eq_int(treasury.arrears, deferred_total,
			"欠付增量必须精确等于第 4..8 档应付额之和 %d μU（T-U-D-10 ④）" % deferred_total)
	eq_int(accounts.cash_of(JWIds.AGENT_GOV), 0,
			"期末国库现金应恰好为 0（T-U-D-10 ⑤：不为负，也没有凭空剩下的钱）")
	check_false(JWResult.has_pending(),
			"按优先级推迟是设计内的行为，不应登记故障（此处为 %d）" % JWResult.pending_code())


# ══════════════════════════════════════════════════════════════════════════
# 五、发债：对手方能力、借款不是收入、增量额度
# ══════════════════════════════════════════════════════════════════════════

## INV-034 / docs/30 `T-S-D-11` / ADV-C03：国内额度与对手方现金**两个上限都要查**，且发行是全有全无。
func test_issue_debt_rejects_when_counterparty_capacity_is_short() -> void:
	treasury.credit_limit_domestic = SCENARIO_CREDIT_LIMIT_DOMESTIC_UU  # 4 000 000 000
	_fund_cash(JWIds.AGENT_INVPOOL, 1_000_000_000)
	world.credit_limit = 0
	world.credit_used = 0
	# 国内能力 = min(4 000 000 000, mul_ppm(1 000 000 000, 600 000)) = 600 000 000；外部能力 = 0。
	var capacity: int = JWMath.mul_ppm(1_000_000_000, P_HOUSEHOLD_BOND_APPETITE_PPM)
	eq_int(capacity, 600_000_000, "夹具自检：认购能力 = 1 000 000 000 × 600 000 ppm = 600 000 000 μU")

	var gov_cash_before: int = accounts.cash_of(JWIds.AGENT_GOV)
	JWResult.clear_pending()
	var rc: int = treasury.issue_debt(1_000_000_000, bonds, world, ledger, accounts,
			0, _next_seq(), params)

	rejects(rc, JWResult.OK, "需求 1 000 000 000 超过 600 000 000 的对手方能力，必须被拒（INV-034）")
	eq_int(rc, JWResult.Reject.CREDIT_LIMIT, "额度不足的拒绝码应为 Reject.CREDIT_LIMIT")
	eq_int(bonds.debt_outstanding(), 0,
			"T-S-D-11 断言 gov.debt_uu 增量 == 0：被拒的发行不得留下半张债券")
	eq_int(bonds.count, 0, "被拒的发行不得写入任何批次")
	eq_int(accounts.cash_of(JWIds.AGENT_GOV), gov_cash_before, "被拒的发行不得改动国库现金")
	eq_int(treasury.f_new_borrowing, 0, "被拒的发行不得登记新增借款")


## INV-029 / docs/30 `T-U-D-06`：新增借款不进收入，且必须有真实对手方（INV-026/INV-034）。
func test_borrowing_is_not_income_and_has_a_counterparty() -> void:
	treasury.credit_limit_domestic = SCENARIO_CREDIT_LIMIT_DOMESTIC_UU
	_fund_cash(JWIds.AGENT_INVPOOL, SCENARIO_INVPOOL_CASH_UU)  # 9 000 000 000
	world.credit_limit = 0
	world.credit_used = 0
	var face: int = 2_000_000_000
	var gov_before: int = accounts.cash_of(JWIds.AGENT_GOV)
	var pool_before: int = accounts.cash_of(JWIds.AGENT_INVPOOL)
	JWResult.clear_pending()

	eq_int(treasury.issue_debt(face, bonds, world, ledger, accounts, 0, _next_seq(), params),
			JWResult.OK,
			"国内能力 min(4 000 000 000, 9 000 000 000×600 000ppm=5 400 000 000) = 4 000 000 000 >= 2 000 000 000，应成功")
	eq_int(accounts.cash_of(JWIds.AGENT_GOV) - gov_before, face,
			"国库现金应增加面值 2 000 000 000 μU（T-U-D-06）")
	eq_int(pool_before - accounts.cash_of(JWIds.AGENT_INVPOOL), face,
			"投资池现金必须同额减少：融资必须有对手方，不能凭空生钱（INV-026/INV-034）")
	eq_int(bonds.debt_outstanding(), face, "债务应增加面值（INV-028/INV-035）")
	eq_int(treasury.f_new_borrowing, face, "flow.gov.new_borrowing_uu 应单独登记 2 000 000 000 μU")
	eq_int(treasury.f_receipts_income_tax, 0, "借款不得混进个人所得税收入（INV-029）")
	eq_int(treasury.f_receipts_profit_tax, 0, "借款不得混进利润税收入（INV-029）")
	eq_int(treasury.f_receipts_other, 0, "借款不得混进非税收入（INV-029）")
	eq_int(accounts.get_balance(JWIds.idx_account(JWIds.AGENT_INVPOOL, JWIds.ACC_BONDHOLD)), face,
			"债权人持债科目应同额增加，否则 INV-025 在季末必破")


## INV-038：新发批次的票息由规则给出并夹在 [coupon_min, coupon_max]，不低于市场基准利率。
func test_new_issue_coupon_is_rule_priced_within_bounds() -> void:
	treasury.credit_limit_domestic = SCENARIO_CREDIT_LIMIT_DOMESTIC_UU
	_fund_cash(JWIds.AGENT_INVPOOL, SCENARIO_INVPOOL_CASH_UU)
	world.credit_limit = 0
	world.credit_used = 0
	world.sovereign_rate_ppm = P_MARKET_RATE_BASE_PPM
	JWResult.clear_pending()

	eq_int(treasury.issue_debt(1_000_000_000, bonds, world, ledger, accounts, 0, _next_seq(), params),
			JWResult.OK, "能力充足时发行应成功")
	eq_int(bonds.count, 1, "应恰好新增一个批次，**不得自动合并批次**（docs/12 §2.4）")
	var b: int = bonds.count - 1
	in_range_int(bonds.coupon_ppm[b], P_COUPON_MIN_PPM, P_COUPON_MAX_PPM,
			"票息必须夹在 [param.coupon_min_ppm=2000, param.coupon_max_ppm=60000]（docs/12 §2.6）")
	ge_int(bonds.coupon_ppm[b], P_MARKET_RATE_BASE_PPM,
			"dsr >= 0 且 slope >= 0 时 market_ppm >= param.market_rate_base_ppm = 10 000；"
			+ "新发票息低于基准即违反 INV-038")
	eq_int(bonds.issue_q[b], 0, "发行季应记为 q=0")
	bonds.schedule_principal(0)
	eq_int(bonds.principal_due[b], 0,
			"本季（q == issue_q）不还本：分期表覆盖 issue_q+1 … maturity_q（docs/12 §2.6 末）")


## 裁定 R-CREDIT-01 / INV-034：外部额度是**增量额度**——存量外债不占用 credit_used，还本也不释放。
func test_external_credit_limit_is_incremental_only() -> void:
	_load_scenario_bonds()
	world.credit_limit = 5_000_000_000
	world.credit_used = 0

	eq_int(bonds.debt_outstanding_of_holder(JWUnits.Holder.ROW), SCENARIO_DEBT_ROW_UU,
			"夹具自检：开局存量外债 16 000 000 000 μU")
	eq_int(world.credit_used, 0,
			"存量外债 16 000 000 000 μU **不占用** credit_used（R-CREDIT-01；占一次就是重复计算）")
	eq_int(world.credit_headroom(), 5_000_000_000,
			"额度余量应为 credit_limit − credit_used = 5 000 000 000 μU，与存量外债无关")

	# 把国内通道关死，逼迫新增借款全部走外部额度。外部债权人 agent.row 的现金取剧本值 15 U
	# （scenario.json `_note_total_cash_uu` 的 agent.row 15 000 000 000 μU）。
	_fund_cash(JWIds.AGENT_ROW, 15_000_000_000)
	treasury.credit_limit_domestic = 0
	world.sovereign_rate_ppm = P_MARKET_RATE_BASE_PPM
	JWResult.clear_pending()
	eq_int(treasury.issue_debt(1_000_000_000, bonds, world, ledger, accounts, 0, _next_seq(), params),
			JWResult.OK, "外部额度 5 000 000 000 足够，1 000 000 000 的外部发行应成功")
	eq_int(world.credit_used, 1_000_000_000,
			"**新增**外部借款必须占用额度：credit_used 应为 1 000 000 000 μU（INV-034）")

	# 足额付掉一季的利息与本金，额度不得被「还本」释放。
	_accrue_and_schedule(1)
	_fund_cash(JWIds.AGENT_GOV, 100_000_000_000)
	treasury.begin_quarter(accounts)
	treasury.pay_debt_service(bonds, ledger, accounts, 1, params)
	ge_int(treasury.f_principal_paid, 900_000_000,
			"夹具自检：q=1 应至少还掉两笔 level_principal 的 400 000 000 + 500 000 000")
	eq_int(world.credit_used, 1_000_000_000,
			"还本**不释放**额度：credit_used 必须仍为 1 000 000 000 μU（R-CREDIT-01）")

