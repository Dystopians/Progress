## 长期货币与价格水平（docs/18 R-PRICE-LONG-01 / R-MONEY-01；docs/53 M1-3）。
##
## 两件事：
## ① 价格水平指数 `state.money.price_level_ppm`：固定篮子（content.money.level_weight_ppm）下
##    各部门现价相对基年价的加权平均，每季 S07 定价之前按本季现价算一次。战役模式的价格、工资上下限随它移动。
## ② 货币发行（只在战役模式启用）：S04 付款之前，按「货币量跟随实际产出与目标价格水平」的规则发行，
##    政府现金与政府净值同额增加（铸币收益），全经济现金总量相应上升（INV-018 的期望值加上累计发行额）。
##    只发行、不回收；每季发行额有上限。旧剧本（单届模式）不启用，现金总量仍恒等于剧本登记值。
##
## 依赖秩与 sim/ 下其他状态块相同：只依赖 JWUnits / JWMath / JWResult。
class_name JWMoney
extends RefCounted

# ── §1.6 状态块协议 ─────────────────────────────────────────────────────────

const STATE_SCALAR_IDS: PackedStringArray = [
	"state.money.issued_total_uu",
	"state.money.price_level_ppm",
	"state.money.target_level_ppm",
	"content.money.enabled",
	"content.money.base_money_uu",
	"content.money.base_real_gdp_q_uu",
	"content.money.target_inflation_ppm_per_year",
	"content.money.adjust_ppm",
	"content.money.issue_cap_ppm",
	"content.money.band_floor_ppm",
	"content.money.band_ceil_ppm",
	"content.money.abs_floor_ppm",
	"content.money.abs_ceil_ppm",
	"content.money.wage_ceil_mult_ppm",
	# R-CLOSURE-01：长期存量流量闭合（外部现金下限、企业超额现金分配）。
	"content.money.base_row_cash_uu",
	"content.money.row_cash_floor_ppm",
	"content.money.firm_excess_buffer_ppm",
	"content.money.firm_excess_payout_ppm",
]
const STATE_SCALAR_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_PRICE, JWUnits.SUBSYS_GOV,
	JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV,
	JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV,
	JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV,
	JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV,
]
const STATE_ARRAY_IDS: PackedStringArray = [
	"state.money.real_gdp_ring_uu",
	"content.money.level_weight_ppm",
]
const STATE_ARRAY_SUBSYS: PackedInt64Array = [JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV]
## 本季发行额的流量归国库块（flow.gov.money_issued_uu），它要进 INV-027 的政府现金恒等式。
const FLOW_SCALAR_IDS: PackedStringArray = []
const FLOW_SCALAR_SUBSYS: PackedInt64Array = []
const FLOW_ARRAY_IDS: PackedStringArray = []
const FLOW_ARRAY_SUBSYS: PackedInt64Array = []

## 实际产出滚动窗口的长度（四季，抹掉季节性）。
const RING_N: int = 4

# ── 状态 ───────────────────────────────────────────────────────────────────

## state.money.issued_total_uu —— 开局以来累计发行额（μU）。写入者 S04
var issued_total: int = 0
## state.money.price_level_ppm —— 价格水平指数，基年 1 000 000。写入者 S07
var price_level_ppm: int = JWUnits.PPM
## state.money.target_level_ppm —— 发行规则的目标价格水平（按目标通胀逐季复利）。写入者 S04
var target_level_ppm: int = JWUnits.PPM
## state.money.real_gdp_ring_uu —— 最近四季的实际 GDP（基年价，μU），下标 q % 4。写入者 S07
var real_gdp_ring: PackedInt64Array = PackedInt64Array()

# ── 内容常量（剧本 money_rule；不进哈希与存档） ───────────────────────────

var enabled: int = 0
var base_money_uu: int = 0
var base_real_gdp_q_uu: int = 0
var target_inflation_ppm_per_year: int = 0
var adjust_ppm: int = 0
var issue_cap_ppm: int = 0
var band_floor_ppm: int = 0
var band_ceil_ppm: int = 0
var abs_floor_ppm: int = 0
var abs_ceil_ppm: int = 0
var wage_ceil_mult_ppm: int = JWUnits.PPM
var base_row_cash_uu: int = 0
var row_cash_floor_ppm: int = 0
var firm_excess_buffer_ppm: int = 0
var firm_excess_payout_ppm: int = 0
var level_weight_ppm: PackedInt64Array = PackedInt64Array()

func allocate() -> void:
	issued_total = 0
	price_level_ppm = JWUnits.PPM
	target_level_ppm = JWUnits.PPM
	real_gdp_ring.resize(RING_N)
	real_gdp_ring.fill(0)
	level_weight_ppm.resize(JWUnits.S)
	level_weight_ppm.fill(0)


# ── 规则 ───────────────────────────────────────────────────────────────────

## 价格水平指数：Σ w_s × p_s / base_s（ppm）。权重全 0（旧剧本未给篮子）时返回 1e6。
## 步骤：S07（定价之前）
## 前置：price / base_price 长 S
## 后置：price_level_ppm 被写
## 不变量：R-PRICE-LONG-01（现价逐位等于基年价时指数恰为 1 000 000，权重合计 1e6 由 LOAD 校验）
## 失败：长度不符 → INDEX_OUT_OF_RANGE
func update_price_level(price: PackedInt64Array, base_price: PackedInt64Array) -> int:
	if price.size() != JWUnits.S or base_price.size() != JWUnits.S \
			or level_weight_ppm.size() != JWUnits.S:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, price.size(), JWUnits.S)
	var wsum: int = JWMath.sum(level_weight_ppm)
	if wsum <= 0:
		price_level_ppm = JWUnits.PPM
		return JWResult.OK
	var acc: int = 0
	for s: int in JWUnits.S:
		if base_price[s] <= 0:
			return JWResult.raise_fault(JWResult.Fault.DIV_ZERO, s, base_price[s])
		# rounding: floor, reason=指数只取整一次（逐项 floor 的误差 < S μppm）
		acc += JWMath.mul_div_floor(level_weight_ppm[s], price[s], base_price[s])
	price_level_ppm = maxi(1, acc)
	return JWResult.OK


## 记下本季实际 GDP（滚动四季窗口）。
## 步骤：S07
## 前置：real_gdp_uu 是本季 S06 算出的实际 GDP
## 后置：real_gdp_ring[q % 4] 被写
## 不变量：无
## 失败：无
func record_real_gdp(q: int, real_gdp_uu: int) -> void:
	real_gdp_ring[q - JWMath.floor_div(q, RING_N) * RING_N] = maxi(0, real_gdp_uu)


## 本季应发行额（不动账；由 S04 过账后调用 note_issued）。
## 步骤：S04（付款之前）
## 前置：money_now_uu 是当前全经济现金总量
## 后置：target_level_ppm 按目标通胀复利一季（启用时）；不写其他状态
## 不变量：R-MONEY-01（发行额 ∈ [0, money_now × cap]；四季窗口未填满时不发行）
## 失败：无
func compute_issue(money_now_uu: int) -> int:
	if enabled == 0:
		return 0
	# 目标价格水平：年通胀率摊到四季，按季复利（π_q = π_y / 4，floor；与年率的复利差在 1e-4 量级内）。
	var pi_q: int = JWMath.floor_div(target_inflation_ppm_per_year, 4)
	target_level_ppm = maxi(1, target_level_ppm + JWMath.mul_ppm(target_level_ppm, pi_q))
	if base_real_gdp_q_uu <= 0 or base_money_uu <= 0:
		return 0
	var ysum: int = 0
	for i: int in RING_N:
		if real_gdp_ring[i] <= 0:
			return 0
		ysum += real_gdp_ring[i]
	var y_avg: int = JWMath.floor_div(ysum, RING_N)
	# 目标货币量 M* = M0 × (Y / Y0) × 目标价格水平。
	var m_star: int = JWMath.mul_div_floor(base_money_uu, y_avg, base_real_gdp_q_uu)
	m_star = JWMath.mul_ppm(m_star, target_level_ppm)
	var gap: int = m_star - money_now_uu
	if gap <= 0:
		return 0
	var issue: int = JWMath.mul_ppm(gap, adjust_ppm)
	var cap: int = JWMath.mul_ppm(money_now_uu, issue_cap_ppm)
	return JWMath.clamp_i(issue, 0, cap)


## R-CLOSURE-01：外部现金补足额。外部持有的本国现金低于「开局外部现金 × 下限」时补到下限：
## 经济含义是本国以新发行的货币买入外汇储备（政府对外部的债权），出口因此不会因外国手里没有本国货币而停摆。
## 补足额计入累计发行（INV-018），但不进政府现金（INV-027 不受影响）。
func row_topup(row_cash_uu: int) -> int:
	if enabled == 0 or row_cash_floor_ppm <= 0 or base_row_cash_uu <= 0:
		return 0
	var floor_uu: int = JWMath.mul_ppm(base_row_cash_uu, row_cash_floor_ppm)
	return maxi(0, floor_uu - row_cash_uu)


## 过账成功之后登记累计额（本季流量由国库登记）。
func note_issued(amount_uu: int) -> void:
	issued_total += amount_uu


## 战役模式的价格上下限（μU/Q_s）：[max(base×水平×带宽下限, base×绝对下限), min(base×水平×带宽上限, base×绝对上限)]。
## 两者冲突（水平已越过绝对护栏）时下限取上限，价格钉在护栏上并由调用方记夹逼。
## 返回 [floor, ceil]。
func price_bounds(base_uu: int) -> PackedInt64Array:
	var at_level: int = JWMath.mul_ppm(base_uu, price_level_ppm)
	var lo: int = maxi(JWMath.mul_ppm(at_level, band_floor_ppm), JWMath.mul_ppm(base_uu, abs_floor_ppm))
	var hi: int = mini(JWMath.mul_ppm(at_level, band_ceil_ppm), JWMath.mul_ppm(base_uu, abs_ceil_ppm))
	lo = maxi(lo, 1)
	if lo > hi:
		lo = hi
	return PackedInt64Array([lo, hi])


# ── §1.6 状态块协议 ─────────────────────────────────────────────────────────

func state_array(i: int) -> PackedInt64Array:
	if i == 0:
		return real_gdp_ring
	if i == 1:
		return level_weight_ppm
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i == 0:
		if v.size() != RING_N:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v.size(), RING_N)
		real_gdp_ring = v.duplicate()
		return JWResult.OK
	if i == 1:
		if v.size() != JWUnits.S:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v.size(), JWUnits.S)
		level_weight_ppm = v.duplicate()
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())


func state_scalar(i: int) -> int:
	match i:
		0: return issued_total
		1: return price_level_ppm
		2: return target_level_ppm
		3: return enabled
		4: return base_money_uu
		5: return base_real_gdp_q_uu
		6: return target_inflation_ppm_per_year
		7: return adjust_ppm
		8: return issue_cap_ppm
		9: return band_floor_ppm
		10: return band_ceil_ppm
		11: return abs_floor_ppm
		12: return abs_ceil_ppm
		13: return wage_ceil_mult_ppm
		14: return base_row_cash_uu
		15: return row_cash_floor_ppm
		16: return firm_excess_buffer_ppm
		17: return firm_excess_payout_ppm
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


func set_state_scalar(i: int, v: int) -> int:
	match i:
		0: issued_total = v
		1: price_level_ppm = v
		2: target_level_ppm = v
		3: enabled = v
		4: base_money_uu = v
		5: base_real_gdp_q_uu = v
		6: target_inflation_ppm_per_year = v
		7: adjust_ppm = v
		8: issue_cap_ppm = v
		9: band_floor_ppm = v
		10: band_ceil_ppm = v
		11: abs_floor_ppm = v
		12: abs_ceil_ppm = v
		13: wage_ceil_mult_ppm = v
		14: base_row_cash_uu = v
		15: row_cash_floor_ppm = v
		16: firm_excess_buffer_ppm = v
		17: firm_excess_payout_ppm = v
		_:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return JWResult.OK


func flow_array(i: int) -> PackedInt64Array:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
	return PackedInt64Array()


func flow_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_SCALAR_IDS.size())
	return 0


func reset_flows() -> void:
	pass


func flow_abs_sum() -> int:
	return 0
