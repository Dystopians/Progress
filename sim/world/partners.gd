## 贸易伙伴分账（docs/18 R-TRADE-01；docs/53 M2-4）。
##
## **不新增主体**：现金仍然只在唯一的外部账户（agent.row）里。伙伴是外部账户之下的**备查子账**，
## 每季把外部账户的现金变动按各伙伴的贸易份额分摊到子账上，并逐季对平：
##     Σ 各伙伴子账变动 == 外部账户现金变动          （INV-P01）
## 贸易安排是命令：改某个伙伴的出口需求份额、进口供给份额与关系；份额改变的是**通道**，
## 不凭空创造外国的库存或购买力——总量仍由 `JWWorldMarket` 的交付能力与需求决定。
##
## 战役剧本才启用（剧本 `trade_rule`）；旧剧本 partner_count == 0，本块恒为空转。
class_name JWPartners
extends RefCounted

# ── §1.6 状态块协议 ─────────────────────────────────────────────────────────

const STATE_ARRAY_IDS: PackedStringArray = [
	"state.partner.export_share_ppm",
	"state.partner.import_share_ppm",
	"state.partner.price_mult_ppm",
	"state.partner.relation_ppm",
	"state.partner.treaty_mask",
	"state.partner.balance_uu",
]
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_WORLD, JWUnits.SUBSYS_WORLD, JWUnits.SUBSYS_WORLD,
	JWUnits.SUBSYS_WORLD, JWUnits.SUBSYS_WORLD, JWUnits.SUBSYS_WORLD,
]
const STATE_SCALAR_IDS: PackedStringArray = [
	"content.partner.count",
	"content.trade.quota_step_ppm",
	"content.trade.treaty_price_bonus_ppm",
]
const STATE_SCALAR_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_WORLD, JWUnits.SUBSYS_WORLD, JWUnits.SUBSYS_WORLD,
]
const FLOW_ARRAY_IDS: PackedStringArray = []
const FLOW_ARRAY_SUBSYS: PackedInt64Array = []
const FLOW_SCALAR_IDS: PackedStringArray = []
const FLOW_SCALAR_SUBSYS: PackedInt64Array = []

## 伙伴表容量（M2 的切片用 3 个；M3 战争线要用到时再扩）。
const CAP0: int = 8

## 条约位：0 == 贸易协定（降进口价、提出口额度）。
const TREATY_TRADE: int = 0

# ── 状态 ───────────────────────────────────────────────────────────────────

var export_share_ppm: PackedInt64Array = PackedInt64Array()
var import_share_ppm: PackedInt64Array = PackedInt64Array()
var price_mult_ppm: PackedInt64Array = PackedInt64Array()
var relation_ppm: PackedInt64Array = PackedInt64Array()
var treaty_mask: PackedInt64Array = PackedInt64Array()
## 子账余额（μU，正 == 外部欠我方的净额方向上的累计；只作备查，不参与任何支付）。
var balance_uu: PackedInt64Array = PackedInt64Array()

# ── 内容常量 ───────────────────────────────────────────────────────────────

var partner_count: int = 0
var quota_step_ppm: int = 0
var treaty_price_bonus_ppm: int = 0


func allocate() -> void:
	export_share_ppm = _zeros(CAP0)
	import_share_ppm = _zeros(CAP0)
	price_mult_ppm = _filled(CAP0, JWUnits.PPM)
	relation_ppm = _zeros(CAP0)
	treaty_mask = _zeros(CAP0)
	balance_uu = _zeros(CAP0)
	partner_count = 0
	quota_step_ppm = 0
	treaty_price_bonus_ppm = 0


static func _zeros(n: int) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(n)
	a.fill(0)
	return a


static func _filled(n: int, v: int) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(n)
	a.fill(v)
	return a


# ── 规则 ───────────────────────────────────────────────────────────────────

## 出口需求的伙伴合计倍率（ppm）：各伙伴出口份额之和。没有伙伴时返回 1e6（不改变原行为）。
func export_multiplier_ppm() -> int:
	if partner_count <= 0:
		return JWUnits.PPM
	var acc: int = 0
	for p: int in partner_count:
		acc += export_share_ppm[p]
	return maxi(0, acc)


## 进口价格的伙伴合计倍率（ppm）：按进口份额加权的价格系数；有贸易协定的伙伴再减一档。
func import_price_multiplier_ppm() -> int:
	if partner_count <= 0:
		return JWUnits.PPM
	var wsum: int = 0
	for p: int in partner_count:
		wsum += import_share_ppm[p]
	if wsum <= 0:
		return JWUnits.PPM
	var acc: int = 0
	for p2: int in partner_count:
		var mult: int = price_mult_ppm[p2]
		if ((treaty_mask[p2] >> TREATY_TRADE) & 1) == 1:
			mult = maxi(1, mult - treaty_price_bonus_ppm)
		# rounding: floor, reason=加权只取整一次
		acc += JWMath.mul_div_floor(import_share_ppm[p2], mult, wsum)
	return maxi(1, acc)


## S02：贸易安排（命令 16）。mode 0 == 调出口额度，1 == 调进口额度，2 == 缔结贸易协定。
## 额度每次按 quota_step_ppm 增减一档，份额落在 [0, 1e6]；关系随之升降一档。
func arrange(partner: int, mode: int, up: int) -> int:
	if partner_count <= 0:
		return JWResult.Reject.PRECONDITION
	if partner < 0 or partner >= partner_count:
		return JWResult.Reject.NOT_FOUND
	var step: int = quota_step_ppm if up != 0 else -quota_step_ppm
	if mode == 0:
		export_share_ppm[partner] = JWMath.clamp_i(export_share_ppm[partner] + step, 0, JWUnits.PPM)
	elif mode == 1:
		import_share_ppm[partner] = JWMath.clamp_i(import_share_ppm[partner] + step, 0, JWUnits.PPM)
	elif mode == 2:
		if ((treaty_mask[partner] >> TREATY_TRADE) & 1) == 1:
			return JWResult.Reject.ALREADY_ENACTED
		treaty_mask[partner] = treaty_mask[partner] | (1 << TREATY_TRADE)
	else:
		return JWResult.Reject.PARAM_RANGE
	# 关系：扩大通道或缔约提升关系，收缩则下降（有界）。
	var d: int = 50_000 if (mode == 2 or up != 0) else -50_000
	relation_ppm[partner] = JWMath.clamp_i(relation_ppm[partner] + d, -JWUnits.PPM, JWUnits.PPM)
	return JWResult.OK


## S06 末：把本季外部账户的现金变动按贸易份额摊到各伙伴子账，并对平（INV-P01）。
## 返回未摊出的残差（正常为 0；没有份额时全部记在第 0 个伙伴上，不丢）。
func settle_subledger(row_cash_delta: int, tiebreak: PackedInt64Array,
		weights: PackedInt64Array, out: PackedInt64Array) -> int:
	if partner_count <= 0 or row_cash_delta == 0:
		return 0
	var sign: int = 1 if row_cash_delta > 0 else -1
	var amount: int = row_cash_delta * sign
	var wsum: int = 0
	for p: int in partner_count:
		weights[p] = maxi(0, export_share_ppm[p] + import_share_ppm[p])
		tiebreak[p] = p
		wsum += weights[p]
	if wsum <= 0:
		balance_uu[0] += row_cash_delta
		return 0
	var res: int = JWMath.split_lr_into(amount, weights, tiebreak, out)
	if JWMath._split_last_fault != 0:
		return JWMath._split_last_fault
	if res != 0:
		balance_uu[0] += res * sign
	for p2: int in partner_count:
		balance_uu[p2] += out[p2] * sign
	return 0


## INV-P01 的核对：Σ 子账余额 == 累计的外部现金变动（由调用方给出）。
func balance_total() -> int:
	var acc: int = 0
	for p: int in partner_count:
		acc += balance_uu[p]
	return acc


# ── §1.6 状态块协议 ─────────────────────────────────────────────────────────

func state_array(i: int) -> PackedInt64Array:
	match i:
		0: return export_share_ppm
		1: return import_share_ppm
		2: return price_mult_ppm
		3: return relation_ppm
		4: return treaty_mask
		5: return balance_uu
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i < 0 or i >= STATE_ARRAY_IDS.size():
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	if v.size() != CAP0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v.size(), CAP0)
	var d: PackedInt64Array = v.duplicate()
	match i:
		0: export_share_ppm = d
		1: import_share_ppm = d
		2: price_mult_ppm = d
		3: relation_ppm = d
		4: treaty_mask = d
		5: balance_uu = d
	return JWResult.OK


func state_scalar(i: int) -> int:
	match i:
		0: return partner_count
		1: return quota_step_ppm
		2: return treaty_price_bonus_ppm
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


func set_state_scalar(i: int, v: int) -> int:
	match i:
		0: partner_count = v
		1: quota_step_ppm = v
		2: treaty_price_bonus_ppm = v
		_:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return JWResult.OK


func flow_array(i: int) -> PackedInt64Array:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, 0)
	return PackedInt64Array()


func flow_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, 0)
	return 0


func reset_flows() -> void:
	pass


func flow_abs_sum() -> int:
	return 0
