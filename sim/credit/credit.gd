## 投资池对生产单元的资本放贷（docs/18 R-INVCREDIT-01；docs/53 M2-8）。
##
## 为什么需要这一块：住户的正储蓄全额存进投资池，而投资池此前只有三个出口——付存款利息、
## 买国债、住户负储蓄时取款。四十季旧剧本里政府持续赤字，正好把储蓄吸走；四百年战役里
## 政府一旦把债还清，这笔钱就再也回不到循环，需求逐季漏光（实测 50 年后投资池 350 U、
## 实际 GDP 掉到 0.4%、失业 83%）。本块补上唯一缺的那条渠道：储蓄经投资池贷给企业去投资。
##
## 三条纪律：
## ① **只为资本支出放贷**。贷款额 = max(0, 本季投资意愿 − 自有现金)，不为工资与中间投入融资；
##    否则周转现金会被包装成贷款，杠杆没有上限。
## ② **不凭空创造购买力**。放贷受投资池现金约束（它借不出它没有的钱），贷款只是把住户已经
##    存进去的钱转出去；全经济现金总量不变（INV-017 / INV-018 照常成立）。
## ③ **杠杆有上限**。单元未偿本金不得超过其资本价值 × max_leverage_ppm；到顶就借不到，
##    投资因此受限——这是真实约束，不是惩罚。
##
## 记账：贷款计在投资池的应收（ACC_RECV）与生产单元的应付（ACC_PAY），双方净值都不变。
## 于是 INV-019（Σ 应收 == Σ 应付）与 INV-020（资产负债表恒等）自动成立，无需新增科目。
## 利息进投资池现金，再由 S06 既有的存款利息分配腿按存款份额回流各住户组。
##
## 违约不在本版：企业现金不足时少还本、少付息，欠款留在未偿本金里继续计息（R-INVCREDIT-01 第 6 条）。
## 破产与坏账清理归 M3。
##
## 战役剧本才启用（剧本 `credit_rule`）；旧剧本 enabled == 0，本块恒为空转。
class_name JWCredit
extends RefCounted

# ── §1.6 状态块协议 ─────────────────────────────────────────────────────────

const STATE_ARRAY_IDS: PackedStringArray = [
	"state.credit.principal_uu",
	"state.credit.arrears_uu",
	"state.credit.wc_principal_uu",
]
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
]
const STATE_SCALAR_IDS: PackedStringArray = [
	"content.credit.enabled",
	"content.credit.spread_ppm_per_q",
	"content.credit.amortize_ppm",
	"content.credit.max_leverage_ppm",
	"content.credit.min_draw_uu",
	"content.credit.pool_reserve_ppm",
	"content.credit.wc_cap_ppm",
]
const STATE_SCALAR_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
]
const FLOW_ARRAY_IDS: PackedStringArray = [
	"flow.credit.draw_uu",
	"flow.credit.interest_uu",
	"flow.credit.repay_uu",
]
const FLOW_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
]
const FLOW_SCALAR_IDS: PackedStringArray = []
const FLOW_SCALAR_SUBSYS: PackedInt64Array = []

# ── 状态 ───────────────────────────────────────────────────────────────────

## state.credit.principal_uu[] —— 各生产单元的未偿本金。写入者 S05（放款）、S06（还本）
var principal: PackedInt64Array = PackedInt64Array()
## state.credit.arrears_uu[] —— 到期未付的利息与本金累计（留在账上，不核销）。写入者 S06
var arrears: PackedInt64Array = PackedInt64Array()
## state.credit.wc_principal_uu[] —— 周转资金的未偿余额（短期、每季尽量还清）。写入者 S05 / S06
var wc_principal: PackedInt64Array = PackedInt64Array()

# ── 内容常量（剧本 credit_rule） ──────────────────────────────────────────

var enabled: int = 0
## 贷款利率 = 主权利率 + 本利差（每季 ppm）。
var spread_ppm_per_q: int = 0
## 每季按未偿本金的这个比例摊还本金。
var amortize_ppm: int = 0
## 未偿本金上限 = 单元资本价值 × 本系数。
var max_leverage_ppm: int = 0
## 低于这个额度不放款（避免为了几个 μU 走一遍四腿过账）。
var min_draw_uu: int = 0
## 投资池必须留下的现金比例（按存款负债计），保证住户取款不会被放贷掏空。
var pool_reserve_ppm: int = 0
## 周转资金上限 = 上季中间投入 × 本系数（1e6 == 一个季度的投入额）。
var wc_cap_ppm: int = 0

# ── 流量 ───────────────────────────────────────────────────────────────────

## flow.credit.draw_uu[] —— 本季放款额。写入者 S05
var f_draw: PackedInt64Array = PackedInt64Array()
## flow.credit.interest_uu[] —— 本季实付利息。写入者 S06
var f_interest: PackedInt64Array = PackedInt64Array()
## flow.credit.repay_uu[] —— 本季实还本金。写入者 S06
var f_repay: PackedInt64Array = PackedInt64Array()


func allocate() -> void:
	principal = _zeros(JWUnits.CELL)
	arrears = _zeros(JWUnits.CELL)
	wc_principal = _zeros(JWUnits.CELL)
	f_draw = _zeros(JWUnits.CELL)
	f_interest = _zeros(JWUnits.CELL)
	f_repay = _zeros(JWUnits.CELL)
	enabled = 0
	spread_ppm_per_q = 0
	amortize_ppm = 0
	max_leverage_ppm = 0
	min_draw_uu = 0
	pool_reserve_ppm = 0
	wc_cap_ppm = 0


static func _zeros(n: int) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(n)
	a.fill(0)
	return a


# ── 规则 ───────────────────────────────────────────────────────────────────

## 本季贷款利率（每季 ppm）：主权利率 + 利差。企业借钱不会比政府便宜。
func loan_rate_ppm_per_q(sovereign_ppm_per_q: int) -> int:
	return maxi(0, sovereign_ppm_per_q + spread_ppm_per_q)


## 单元还能借多少：杠杆上限减去未偿本金。
## 步骤：S05
## 前置：capital_value_uu 是该单元本季的资本价值
## 后置：不改状态
## 失败：无（负值一律归零）
func headroom_of(cell: int, capital_value_uu: int) -> int:
	if enabled == 0 or cell < 0 or cell >= JWUnits.CELL:
		return 0
	if max_leverage_ppm <= 0 or capital_value_uu <= 0:
		return 0
	var cap: int = JWMath.mul_ppm(capital_value_uu, max_leverage_ppm)
	return maxi(0, cap - principal[cell])


## 投资池本季可放贷的现金：现金减去必须留存的准备（按存款负债计）。
## 步骤：S05
## 前置：pool_cash_uu / deposit_liab_uu 取自账户
## 后置：不改状态
## 失败：无
func lendable(pool_cash_uu: int, deposit_liab_uu: int) -> int:
	if enabled == 0:
		return 0
	var reserve: int = JWMath.mul_ppm(maxi(deposit_liab_uu, 0), pool_reserve_ppm)
	return maxi(0, pool_cash_uu - reserve)


## 本单元本季该借多少：投资意愿减自有现金，受杠杆余量与放贷额度双重上限。
## 步骤：S05
## 前置：intent_uu 是本季投资意愿，cash_uu 是自有现金，budget_uu 是投资池剩余可放贷额
## 后置：不改状态；低于 min_draw_uu 返回 0
## 失败：无
func draw_for(cell: int, intent_uu: int, cash_uu: int, capital_value_uu: int, budget_uu: int) -> int:
	if enabled == 0 or intent_uu <= 0 or budget_uu <= 0:
		return 0
	var need: int = intent_uu - maxi(cash_uu, 0)
	if need < min_draw_uu:
		return 0
	var x: int = mini(need, mini(headroom_of(cell, capital_value_uu), budget_uu))
	return x if x >= min_draw_uu else 0


## R-INVCREDIT-01 第 10 条：周转资金。企业买不起中间投入时的短期垫款，
## 上限是「上季中间投入 × wc_cap_ppm」，与资本贷款共用投资池的可贷额。
## 它治的是流动性，不是清偿力：S06 一有现金就先还它，所以余额不会长期累积。
## 步骤：S05（市场开市之前）
## 前置：input_prev_uu 是上季该单元的中间投入额；cash_uu 是自有现金
## 后置：不改状态
## 失败：无
func wc_draw_for(cell: int, input_prev_uu: int, cash_uu: int, budget_uu: int) -> int:
	if enabled == 0 or wc_cap_ppm <= 0 or input_prev_uu <= 0 or budget_uu <= 0:
		return 0
	if cell < 0 or cell >= JWUnits.CELL:
		return 0
	var need: int = input_prev_uu - maxi(cash_uu, 0)
	if need <= 0:
		return 0
	var cap: int = JWMath.mul_ppm(input_prev_uu, wc_cap_ppm)
	var room: int = maxi(0, cap - wc_principal[cell])
	var x: int = mini(need, mini(room, budget_uu))
	return maxi(x, 0)


func note_wc_draw(cell: int, amount_uu: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL or amount_uu < 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
	wc_principal[cell] = JWMath.check_amount(wc_principal[cell] + amount_uu)
	f_draw[cell] = JWMath.check_amount(f_draw[cell] + amount_uu)
	return JWResult.OK


func note_wc_repay(cell: int, amount_uu: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL or amount_uu < 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
	if amount_uu > wc_principal[cell]:
		return JWResult.raise_fault(JWResult.Fault.STOCK_IDENTITY, amount_uu, wc_principal[cell])
	wc_principal[cell] = wc_principal[cell] - amount_uu
	f_repay[cell] = JWMath.check_amount(f_repay[cell] + amount_uu)
	return JWResult.OK


## 记一笔放款（过账成功之后调用）。
func note_draw(cell: int, amount_uu: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL or amount_uu < 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
	principal[cell] = JWMath.check_amount(principal[cell] + amount_uu)
	f_draw[cell] = JWMath.check_amount(f_draw[cell] + amount_uu)
	return JWResult.OK


## 本季应付利息（未偿本金 × 季利率）。
func interest_due(cell: int, sovereign_ppm_per_q: int) -> int:
	if enabled == 0 or cell < 0 or cell >= JWUnits.CELL:
		return 0
	# rounding: floor, reason=利息只取整一次，少收优于多收
	return JWMath.mul_ppm(principal[cell] + wc_principal[cell],
			loan_rate_ppm_per_q(sovereign_ppm_per_q))


## 本季应还本金（未偿本金 × 摊还率；不足 1 μU 时把余额一次还清，避免永远挂着零头）。
func principal_due(cell: int) -> int:
	if enabled == 0 or cell < 0 or cell >= JWUnits.CELL:
		return 0
	var p: int = principal[cell]
	if p <= 0:
		return 0
	var due: int = JWMath.mul_ppm(p, amortize_ppm)
	return p if due <= 0 else mini(due, p)


## 记一笔实付利息（过账成功之后调用）；少付的部分进欠款。
func note_interest(cell: int, paid_uu: int, due_uu: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
	f_interest[cell] = JWMath.check_amount(f_interest[cell] + paid_uu)
	if due_uu > paid_uu:
		arrears[cell] = JWMath.check_amount(arrears[cell] + (due_uu - paid_uu))
	return JWResult.OK


## 记一笔实还本金（过账成功之后调用）。
func note_repay(cell: int, paid_uu: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL or paid_uu < 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
	if paid_uu > principal[cell]:
		return JWResult.raise_fault(JWResult.Fault.STOCK_IDENTITY, paid_uu, principal[cell])
	principal[cell] = principal[cell] - paid_uu
	f_repay[cell] = JWMath.check_amount(f_repay[cell] + paid_uu)
	return JWResult.OK


## 未偿本金合计（资本贷款；INV-C01 的一半）。
func principal_total() -> int:
	return JWMath.sum(principal)


## 周转资金余额合计。
func wc_total() -> int:
	return JWMath.sum(wc_principal)


## INV-C01：Σ 未偿本金 == 投资池的应收余额。
## 步骤：季末
## 前置：accounts 已完成本季全部过账
## 后置：不改状态
## 失败：不等 → Fault.STOCK_IDENTITY，detail_b = 残差
func check_consistency(accounts: JWAccount) -> int:
	if enabled == 0:
		return JWResult.OK
	if accounts == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, 0)
	var claim: int = accounts.get_balance(JWIds.idx_account(JWIds.AGENT_INVPOOL, JWIds.ACC_RECV))
	var total: int = principal_total() + wc_total()
	if claim != total:
		return JWResult.raise_fault(JWResult.Fault.STOCK_IDENTITY, total, claim - total)
	return JWResult.OK


# ── §1.6 状态块协议 ─────────────────────────────────────────────────────────

func state_array(i: int) -> PackedInt64Array:
	match i:
		0: return principal
		1: return arrears
		2: return wc_principal
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i < 0 or i >= STATE_ARRAY_IDS.size():
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	if v.size() != JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v.size(), JWUnits.CELL)
	var d: PackedInt64Array = v.duplicate()
	match i:
		0: principal = d
		1: arrears = d
		2: wc_principal = d
	return JWResult.OK


func state_scalar(i: int) -> int:
	match i:
		0: return enabled
		1: return spread_ppm_per_q
		2: return amortize_ppm
		3: return max_leverage_ppm
		4: return min_draw_uu
		5: return pool_reserve_ppm
		6: return wc_cap_ppm
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


func set_state_scalar(i: int, v: int) -> int:
	match i:
		0: enabled = v
		1: spread_ppm_per_q = v
		2: amortize_ppm = v
		3: max_leverage_ppm = v
		4: min_draw_uu = v
		5: pool_reserve_ppm = v
		6: wc_cap_ppm = v
		_:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return JWResult.OK


func flow_array(i: int) -> PackedInt64Array:
	match i:
		0: return f_draw
		1: return f_interest
		2: return f_repay
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
	return PackedInt64Array()


func set_flow_array(i: int, v: PackedInt64Array) -> int:
	if i < 0 or i >= FLOW_ARRAY_IDS.size():
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
	if v.size() != JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v.size(), JWUnits.CELL)
	var d: PackedInt64Array = v.duplicate()
	match i:
		0: f_draw = d
		1: f_interest = d
		2: f_repay = d
	return JWResult.OK


func flow_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, 0)
	return 0


func set_flow_scalar(i: int, _v: int) -> int:
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, 0)


func reset_flows() -> void:
	f_draw.fill(0)
	f_interest.fill(0)
	f_repay.fill(0)


func flow_abs_sum() -> int:
	return JWMath.sum_abs(f_draw) + JWMath.sum_abs(f_interest) + JWMath.sum_abs(f_repay)
