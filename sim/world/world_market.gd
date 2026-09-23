## 外部世界（`agent.row` 的业务视图）：出口需求、进口交付能力、外部信用额度、固定汇率、经常账户。
##
## 首版**固定汇率、无外币债务、无估值变动**。
## 依赖秩 4（docs/17 §3.2）：只允许引用 ≤3 的类。
## 子系统归属：`JWUnits.SUBSYS_WORLD`。
##
## 结构性约束：
## - `state.world.*` 的唯一被写路径是本类的五个 setter，且只由 `JWShocks` 调用（INV-108）。
## - 汇率 `FX_RATE_PPM` 是常量，**不存在 `set_fx_rate`**（INV-105）。
## - 出口不由本类减库存：交易由 `JWInventory` 统一撮合与过账，本类只提供额度并接收
##   `record_export()` 回写（docs/17 §3.3，避免 4 ← 6 的反向边）。
class_name JWWorldMarket
extends RefCounted

## 本块各状态数组所属子系统（与 STATE_ARRAY_IDS 等长），用于 subsystem_hash 与 WriteGuard。
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_WORLD, JWUnits.SUBSYS_WORLD, JWUnits.SUBSYS_WORLD,
]

## 稳定 ID 注册表：下标 == 数组序号，内容是 docs/10 的稳定 ID 字符串。
## 只在加载与哈希时被读，结算期不触碰（无 String 进入热路径）。
const STATE_ARRAY_IDS: PackedStringArray = [
	"state.world.export_demand_ppm",
	"state.world.import_price_ppm",
	"state.world.delivery_capacity_uqs",
]
const STATE_SCALAR_IDS: PackedStringArray = [
	"state.world.credit_limit_uu",
	"state.world.credit_used_uu",
	"state.world.sovereign_rate_ppm_per_q",
	"state.world.current_account_uu",
	# R-TRADE-PRICE-01：相对价格对贸易的作用（战役模式；弹性为 0 时两者恒为 1e6，旧剧本逐位不变）。
	"state.world.export_competitiveness_ppm",
	"state.world.import_attractiveness_ppm",
	"content.world.trade_elasticity_ppm",
	# R-ROW-BUDGET-01：外部按自己手里的本国货币花钱（战役模式；旧剧本恒为 1e6）。
	"state.world.export_budget_ppm",
]
const FLOW_ARRAY_IDS: PackedStringArray = [
	"flow.world.exports_uqs",
	"flow.world.imports_uqs",
]
const FLOW_SCALAR_IDS: PackedStringArray = [
	"flow.world.exports_uu",
	"flow.world.imports_uu",
]

## `state.world.export_competitiveness_ppm`：出口量倍率。写入者 S01。
## 国内价格相对基年越高，同样的外部需求买走的实物越少（外国买家的预算不因我们涨价而变大）。
var export_competitiveness_ppm: int = JWUnits.PPM
## `state.world.import_attractiveness_ppm`：进口份额倍率。写入者 S01。国内越贵，越多需求转向进口。
var import_attractiveness_ppm: int = JWUnits.PPM
## `content.world.trade_elasticity_ppm`：相对价格的传导强度（0 == 不传导，1e6 == 单位弹性）。写入者 LOAD。
var trade_elasticity_ppm: int = 0
## `state.world.export_budget_ppm`：外部购买力倍率 = 外部现金 ÷ 开局外部现金（有界）。写入者 S01。
## 外国人赚到的本国货币会花回来：手头宽裕就多买我们的出口，拮据就少买。固定汇率下这是贸易
## 账户唯一的闭合——否则逆差的钱一直躺在国外（实测 15 年从 15 U 涨到 49 U），需求逐季漏出。
var export_budget_ppm: int = JWUnits.PPM
const EXPORT_BUDGET_MIN_PPM: int = 200_000
const EXPORT_BUDGET_MAX_PPM: int = 3_000_000


## R-ROW-BUDGET-01：按外部现金重算外部购买力倍率。
## 步骤：S01
## 前置：row_cash_uu 是季初外部现金；base_uu 是开局外部现金（0 == 不启用）
## 后置：export_budget_ppm ∈ [0.2, 3.0] × 1e6
## 失败：无
func update_row_budget(row_cash_uu: int, base_uu: int) -> void:
	if trade_elasticity_ppm <= 0 or base_uu <= 0:
		export_budget_ppm = JWUnits.PPM
		return
	# rounding: floor, reason=倍率只取整一次
	export_budget_ppm = JWMath.clamp_i(JWMath.mul_div_floor(maxi(row_cash_uu, 0), JWUnits.PPM, base_uu),
			EXPORT_BUDGET_MIN_PPM, EXPORT_BUDGET_MAX_PPM)

## 两个倍率的护栏：再极端的价格也不会让贸易归零或膨胀到荒谬。
const TRADE_MULT_MIN_PPM: int = 50_000
const TRADE_MULT_MAX_PPM: int = 2_000_000


## R-TRADE-PRICE-01：按当前价格水平重算两个倍率。
## 步骤：S01
## 前置：price_level_ppm 是本季价格水平（旧剧本恒为 1e6）
## 后置：export_competitiveness_ppm 与 import_attractiveness_ppm 写入，均在护栏内
## 失败：无
func update_competitiveness(price_level_ppm: int) -> void:
	if trade_elasticity_ppm <= 0:
		export_competitiveness_ppm = JWUnits.PPM
		import_attractiveness_ppm = JWUnits.PPM
		return
	# 弹性折算后的相对价格：偏离基年的部分按弹性打折。
	var adj: int = JWUnits.PPM + JWMath.mul_ppm(price_level_ppm - JWUnits.PPM, trade_elasticity_ppm)
	adj = maxi(adj, 1)
	# rounding: floor, reason=倍率只取整一次，少算优于多算
	export_competitiveness_ppm = JWMath.clamp_i(
			JWMath.mul_div_floor(JWUnits.PPM, JWUnits.PPM, adj),
			TRADE_MULT_MIN_PPM, TRADE_MULT_MAX_PPM)
	import_attractiveness_ppm = JWMath.clamp_i(adj, TRADE_MULT_MIN_PPM, TRADE_MULT_MAX_PPM)


## `content.world.fx_rate_ppm`：汇率恒定（INV-105）。任何写入路径都不存在。
const FX_RATE_PPM: int = JWUnits.FX_RATE_PPM

# ── 冲击落点的区间护栏（docs/12 §01.7，逐字照抄，不得就地另立） ─────────────

## `export_demand_ppm[s]` 的合法区间下界（docs/12 §01.7）
const EXPORT_DEMAND_MIN_PPM: int = 0
## `export_demand_ppm[s]` 的合法区间上界（docs/12 §01.7）
const EXPORT_DEMAND_MAX_PPM: int = 3_000_000
## `import_price_ppm[s]` 的合法区间下界（docs/12 §01.7；> 0，故不是 0 而是 1e5）
const IMPORT_PRICE_MIN_PPM: int = 100_000
## `import_price_ppm[s]` 的合法区间上界（docs/12 §01.7）
const IMPORT_PRICE_MAX_PPM: int = 5_000_000
## `sovereign_rate_ppm_per_q` 的合法区间下界（docs/12 §01.7、docs/10 §8.4）
const SOVEREIGN_RATE_MIN_PPM: int = 0
## `sovereign_rate_ppm_per_q` 的合法区间上界（docs/12 §01.7、docs/10 §8.4）
const SOVEREIGN_RATE_MAX_PPM: int = 100_000

## `state.world.export_demand_ppm[]`，长 4（按 sector），单位 ppm，写入者 S01（冲击）。
var export_demand_ppm: PackedInt64Array = PackedInt64Array()
## `state.world.import_price_ppm[]`，长 4（按 sector），单位 ppm，写入者 S01（冲击）。
var import_price_ppm: PackedInt64Array = PackedInt64Array()
## `state.world.delivery_capacity_uqs[]`，长 4（按 sector），单位 μQ_s/季，写入者 S01。
var delivery_capacity: PackedInt64Array = PackedInt64Array()
## `state.world.credit_limit_uu`，单位 μU，写入者 S01、S02。
var credit_limit: int = 0
## `state.world.credit_used_uu`，单位 μU，写入者 S02。
var credit_used: int = 0
## `state.world.sovereign_rate_ppm_per_q`，单位 ppm/季，写入者 S01、S02。
var sovereign_rate_ppm: int = 0
## `state.world.current_account_uu`，单位 μU，写入者 S06。
var current_account: int = 0

## `flow.world.exports_uu`，单位 μU，写入者 S05。
var f_exports_uu: int = 0
## `flow.world.exports_uqs[]`，长 4，单位 μQ_s，写入者 S05。
var f_exports_uqs: PackedInt64Array = PackedInt64Array()
## `flow.world.imports_uu`，单位 μU，写入者 S05。
var f_imports_uu: int = 0
## `flow.world.imports_uqs[]`，长 4，单位 μQ_s，写入者 S05。
var f_imports_uqs: PackedInt64Array = PackedInt64Array()

## `content.world.base_export_uqs[]`，长 4，单位 μQ_s，写入者 LOAD。
var base_export_uqs: PackedInt64Array = PackedInt64Array()
## R-IMPORT-01：各产品国内使用中由进口满足的固定份额（ppm）。内容常量，加载器直接写入，不进状态块协议。
var import_share_ppm: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
## `content.world.base_export_ppm[]`，长 4，单位 ppm，写入者 LOAD。
var base_export_ppm: PackedInt64Array = PackedInt64Array()
## `content.world.base_import_ppm[]`，长 4，单位 ppm，写入者 LOAD。
var base_import_ppm: PackedInt64Array = PackedInt64Array()
## `content.world.base_credit_limit_uu`，单位 μU，写入者 LOAD。
var base_credit_limit: int = 0

## 本季剩余交付额度，长 4，单位 μQ_s；S05 入口由 begin_quarter_delivery() 重置。
var _delivery_remaining: PackedInt64Array = PackedInt64Array()

## 本季因交付能力耗尽而未能成交的进口需求，长 4，单位 μQ_s。
## docs/17 §4.22：超交付能力是业务性短缺（不是故障），必须「按剩余额度成交并记未满足需求」——
## 这里就是那笔未满足需求的落点。与 `_delivery_remaining` 同为 S05 工作缓冲，不进 state_hash。
var _import_shortfall_uqs: PackedInt64Array = PackedInt64Array()


## S01 §01.7：冲击落到外部账户（**这是 state.world.* 的唯一被写路径**）。
## 步骤：S01 §01.7
## 前置：调用方是 JWShocks（静态检查：本 setter 的调用点只出现在 sim/world/shocks.gd）
## 后置：export_demand ∈ [0, 3e6]
## 不变量：INV-108（冲击只写 world.* 白名单）、INV-105（fx_rate 不可写）
## 失败：越界 → clamp 并写 log.clamp
func set_export_demand(s: int, value_ppm: int) -> int:
	# 下标与长度一起校验：allocate() 之前被调到就是工程性错误，不能让它写进一个短数组。
	if s < 0 or s >= JWUnits.S or export_demand_ppm.size() != JWUnits.S:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, s, JWUnits.S)
	# docs/12 §01.7：clamp(base + mul_ppm(eff, weight), 0, 3_000_000)。
	# 合成在 JWShocks 侧完成，本 setter 只负责落地前的最后一道护栏。
	var clamped: int = JWMath.clamp_i(value_ppm, EXPORT_DEMAND_MIN_PPM, EXPORT_DEMAND_MAX_PPM)
	# log.clamp 由 JWPricing 持有（docs/17 §4.9），本 setter 的签名里没有它，
	# 无法在此写日志 —— 已登记为接口变更请求，不用「假装写过」来掩盖。
	export_demand_ppm[s] = clamped
	return JWResult.OK


## S01 §01.7：冲击落到外部账户（**这是 state.world.* 的唯一被写路径**）。
## 步骤：S01 §01.7
## 前置：调用方是 JWShocks（静态检查：本 setter 的调用点只出现在 sim/world/shocks.gd）
## 后置：import_price ∈ [1e5, 5e6]
## 不变量：INV-108（冲击只写 world.* 白名单）、INV-105（fx_rate 不可写）
## 失败：越界 → clamp 并写 log.clamp
func set_import_price(s: int, value_ppm: int) -> int:
	if s < 0 or s >= JWUnits.S or import_price_ppm.size() != JWUnits.S:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, s, JWUnits.S)
	# 下界是 1e5 而不是 0：docs/10 §8.4 要求进口价格指数恒 > 0，
	# 取 0 会让 external_price_uu_per_qs 变成 0，即「白送的进口」。
	var clamped: int = JWMath.clamp_i(value_ppm, IMPORT_PRICE_MIN_PPM, IMPORT_PRICE_MAX_PPM)
	import_price_ppm[s] = clamped
	return JWResult.OK


## S01 §01.7：冲击落到外部账户（**这是 state.world.* 的唯一被写路径**）。
## 步骤：S01 §01.7
## 前置：调用方是 JWShocks（静态检查：本 setter 的调用点只出现在 sim/world/shocks.gd）
## 后置：sovereign_rate ∈ [0, 1e5]
## 不变量：INV-108（冲击只写 world.* 白名单）、INV-105（fx_rate 不可写）
## 失败：越界 → clamp 并写 log.clamp
func set_sovereign_rate(value_ppm: int) -> int:
	# docs/12 §01.7：clamp(param.market_rate_base_ppm + mul_ppm(eff, rate_sensitivity), 0, 1e5)。
	sovereign_rate_ppm = JWMath.clamp_i(value_ppm, SOVEREIGN_RATE_MIN_PPM, SOVEREIGN_RATE_MAX_PPM)
	return JWResult.OK


## S01 §01.7：冲击落到外部账户（**这是 state.world.* 的唯一被写路径**）。
## 步骤：S01 §01.7
## 前置：调用方是 JWShocks（静态检查：本 setter 的调用点只出现在 sim/world/shocks.gd）
## 后置：credit_limit >= 0
## 不变量：INV-108（冲击只写 world.* 白名单）、INV-034
## 失败：越界 → clamp 并写 log.clamp
func set_credit_limit(value_uu: int) -> int:
	# docs/12 §01.7：credit_limit = mul_ppm(base_credit_limit, clamp(1e6 − eff, 0, 1e6))。
	credit_limit = JWMath.clamp_i(value_uu, 0, JWUnits.AMOUNT_MAX)
	# **不动 credit_used**：外部收紧把额度压到已用额度以下时，正确表现是本季再也借不到新钱
	# （credit_headroom() 下限 0），而不是倒扣已用额度 —— 后者等于凭空还给玩家一截可借空间。
	# 裁定 R-CREDIT-01：额度约束的是**新增**外部借款，存量外债不占用，也不因额度变动而被追溯。
	return JWResult.OK


## S01 §01.7：冲击落到外部账户（**这是 state.world.* 的唯一被写路径**）。
## 步骤：S01 §01.7
## 前置：调用方是 JWShocks（静态检查：本 setter 的调用点只出现在 sim/world/shocks.gd）
## 后置：delivery_capacity[s] >= 0
## 不变量：INV-108（冲击只写 world.* 白名单）、INV-104
## 失败：越界 → clamp 并写 log.clamp
func set_delivery_capacity(s: int, value_uqs: int) -> int:
	if s < 0 or s >= JWUnits.S or delivery_capacity.size() != JWUnits.S:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, s, JWUnits.S)
	delivery_capacity[s] = JWMath.clamp_i(value_uqs, 0, JWUnits.QTY_MAX)
	# 本季已经开始（_delivery_remaining 已由 S05 入口重置）之后再改交付能力不会追溯本季剩余额度：
	# S01 在 S05 之前跑，二者在同一季内不重叠；这正是「交付能力是每季独立上限」的实现（world.json
	# forbidden_zh 第 4 条：不得把本季没用满的交付能力结转到下季）。
	return JWResult.OK


## S05 入口：重置本季剩余交付额度。
## 步骤：S05 §5.1
## 前置：phase == S05
## 后置：_delivery_remaining == delivery_capacity
## 不变量：INV-104（imports <= delivery_capacity）
## 失败：无
func begin_quarter_delivery() -> void:
	if delivery_capacity.size() != JWUnits.S or _delivery_remaining.size() != JWUnits.S \
			or _import_shortfall_uqs.size() != JWUnits.S:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				_delivery_remaining.size(), JWUnits.S)
		return
	# 未满足需求同属本季口径：上季的短缺不得混进本季的诊断。
	_import_shortfall_uqs.fill(0)
	# 逐元素拷贝而不是 duplicate()：热路径内不新建对象（docs/17 §1.4）。
	# 每季从头给满，不结转上季剩余 —— 交付能力是每季独立上限（world.json forbidden_zh 第 4 条）。
	for s: int in JWUnits.S:
		_delivery_remaining[s] = delivery_capacity[s]


## S05：登记一笔出口成交（由 JWInventory 在撮合买方类 4 后回调）。
## 步骤：S05 §5.6
## 前置：qty <= min(mul_ppm(base_export_uqs, export_demand_ppm), delivery_capacity)
## 后置：f_exports_* 增加；post(kind=EXPORT, row.cash → 卖方.cash)
## 不变量：INV-026（对外必有 agent.row 对手方）、INV-059
## 失败：无
func record_export(s: int, qty_uqs: int, value_uu: int) -> int:
	if s < 0 or s >= JWUnits.S or f_exports_uqs.size() != JWUnits.S \
			or base_export_uqs.size() != JWUnits.S or export_demand_ppm.size() != JWUnits.S \
			or delivery_capacity.size() != JWUnits.S:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, s, JWUnits.S)
	# 负数不是「业务性短缺」而是调用方算错了：flow.world.exports_* 在 docs/10 §8.4 里恒 >= 0。
	# 用越界码登记（与 JWRngStreams 对「长度不符」的用法一致：形参落在契约区间之外）。
	if qty_uqs < 0 or value_uu < 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, qty_uqs, value_uu)
	if qty_uqs == 0 and value_uu == 0:
		return JWResult.OK
	# 出口额度（docs/12 §5.6 买方类 4）：外部需求与交付能力取小。
	# **这是「不能自造订单」的结构性落点**：撮合侧就算算错了额度，也过不了这道回写闸。
	# 与进口各自独立受同一个上限约束、不共享额度池（world.json delivery_capacity_semantics_zh），
	# 所以这里读 delivery_capacity 而不是 _delivery_remaining，也不扣减后者。
	# R-TRADE-01：出口通道倍率（伙伴份额）折进外部需求；旧剧本恒为 1e6。
	var potential_uqs: int = JWMath.mul_ppm(base_export_uqs[s], export_demand_with_partners(s))
	var cap_uqs: int = potential_uqs
	if delivery_capacity[s] < cap_uqs:
		cap_uqs = delivery_capacity[s]
	var acc_qty: int = f_exports_uqs[s] + qty_uqs
	if acc_qty > cap_uqs:
		# 超额即「凭空的货」：本季对外交货量超过了外部需求与交付能力共同给出的上限。
		# 截到上限会与 JWInventory 已经过账的实物腿对不上（静默改账），所以这里只报不改。
		return JWResult.raise_fault(JWResult.Fault.UNBOUNDED_PRODUCTION, acc_qty, cap_uqs)
	if acc_qty > JWUnits.QTY_MAX:
		return JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, acc_qty, JWUnits.QTY_MAX)
	var acc_value: int = f_exports_uu + value_uu
	if acc_value > JWUnits.AMOUNT_MAX:
		return JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, acc_value, JWUnits.AMOUNT_MAX)
	# 只回写流量：过账（kind=EXPORT，row.cash → 卖方.cash）与卖方减库存都在 JWInventory 侧，
	# 本类秩 4 不得引用秩 6 的 JWInventory（docs/17 §3.3）。
	f_exports_uqs[s] = acc_qty
	f_exports_uu = acc_value
	return JWResult.OK


## S05：登记一笔进口（含项目进口设备与企业投资进口设备）。
## 步骤：S05 §5.6、S04 §4.4（项目设备）
## 前置：qty <= _delivery_remaining[s]；买方现金与外部信用额度双重约束
## 后置：_delivery_remaining 扣减；f_imports_* 增加；post(kind=IMPORT)
## 不变量：INV-104（**双重约束**，test_s_import_cap）、INV-026
## 失败：超交付能力 → 按剩余额度成交并记未满足需求（业务性短缺，不是故障）
func record_import(s: int, qty_uqs: int, value_uu: int) -> int:
	if s < 0 or s >= JWUnits.S or f_imports_uqs.size() != JWUnits.S \
			or _delivery_remaining.size() != JWUnits.S \
			or _import_shortfall_uqs.size() != JWUnits.S:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, s, JWUnits.S)
	if qty_uqs < 0 or value_uu < 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, qty_uqs, value_uu)
	if qty_uqs == 0 and value_uu == 0:
		return JWResult.OK
	# 物量闸（world.json gate_a_quantity_zh，INV-104；docs/12 §4.4 第 1071 行
	# `delivered_uqs = min(本季已订设备量, 剩余额)`）：本季剩余交付能力是硬上限，
	# 超出的部分**不是欠货而是本季根本没到货**（docs/16 gate_a_quantity_zh）。
	# 按 docs/17 §4.22「失败」行：超交付能力是业务性短缺，不是故障 ——
	# 按剩余额度成交，短缺量登记在 _import_shortfall_uqs 里由调用方读取，
	# 不得 raise_fault，也不得把差额记成负的剩余额度（那等于把短缺记成透支）。
	var filled_uqs: int = qty_uqs
	if filled_uqs > _delivery_remaining[s]:
		filled_uqs = _delivery_remaining[s]
	if filled_uqs < 0:
		filled_uqs = 0
	# 短缺量累计（docs/12 §13「记欠付／延期／取消／配给／未满足」在本类的落点）。
	_import_shortfall_uqs[s] += qty_uqs - filled_uqs
	# 金额腿按成交比例缩：只付到货的那部分，付了没到的货就是静默改账。
	# 先乘后除一律走 mul_div_floor（新刻度下 value_uu * filled 会溢出 int64）。
	var filled_uu: int = value_uu
	if qty_uqs > 0 and filled_uqs < qty_uqs:
		filled_uu = JWMath.mul_div_floor(value_uu, filled_uqs, qty_uqs)
	if filled_uqs == 0 and filled_uu == 0:
		# 一颗也没到货：额度一分不扣、流量一分不记，本季这笔全部落进未满足需求。
		return JWResult.OK
	var acc_qty: int = f_imports_uqs[s] + filled_uqs
	if acc_qty > JWUnits.QTY_MAX:
		return JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, acc_qty, JWUnits.QTY_MAX)
	var acc_value: int = f_imports_uu + filled_uu
	if acc_value > JWUnits.AMOUNT_MAX:
		return JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, acc_value, JWUnits.AMOUNT_MAX)
	_delivery_remaining[s] -= filled_uqs
	f_imports_uqs[s] = acc_qty
	f_imports_uu = acc_value
	# **不动 credit_used**：融资闸（gate_b_finance_zh）走的是「外债 → 国库现金 → 付款」三段，
	# 禁止用外部信用额度直接抵扣进口货款（world.json forbidden_zh 第 2 条）。
	return JWResult.OK


## 本季该部门剩余的进口交付额度（只读查询）。
## 步骤：S04 §4.4、S05 §5.6
## 前置：s ∈ [0, JWUnits.S)
## 后置：不改状态
## 不变量：INV-104
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回 0
func delivery_remaining(s: int) -> int:
	if s < 0 or s >= JWUnits.S or _delivery_remaining.size() != JWUnits.S:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, s, JWUnits.S)
		return 0
	return _delivery_remaining[s]


## 本季该部门因交付能力耗尽而未成交的进口需求（只读查询）。
## 步骤：S04 §4.4、S05 §5.6
## 前置：s ∈ [0, JWUnits.S)
## 后置：不改状态
## 不变量：INV-104（超交付能力是未满足需求，不是透支，也不是故障）
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回 0
func import_shortfall(s: int) -> int:
	if s < 0 or s >= JWUnits.S or _import_shortfall_uqs.size() != JWUnits.S:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, s, JWUnits.S)
		return 0
	return _import_shortfall_uqs[s]


## S02：外部融资额度占用与释放（由 JWTreasury 调用）。
## 步骤：S02 §2.6
## 前置：amount <= credit_limit − credit_used
## 后置：credit_used 增加
## 不变量：INV-034
## 失败：超额 → 返回 Reject.CREDIT_LIMIT，不改状态
func use_external_credit(amount_uu: int) -> int:
	# 负数不是「释放」：本签名的后置只写了「credit_used 增加」，而 R-CREDIT-01 把额度定义成
	# **增量额度**（存量外债不占用）。要不要有释放路径是契约问题，不是实现者可以就地发明的。
	if amount_uu < 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, amount_uu, 0)
	if amount_uu == 0:
		return JWResult.OK
	# INV-034：外部 <= credit_limit − credit_used。headroom 已带下限 0。
	if amount_uu > credit_headroom():
		# 业务性拒绝，不是故障：不改状态，差额由 JWTreasury 回到 §2.5 的排序／延期／重组分支。
		return JWResult.Reject.CREDIT_LIMIT
	var used: int = credit_used + amount_uu
	if used > JWUnits.AMOUNT_MAX:
		return JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, used, JWUnits.AMOUNT_MAX)
	credit_used = used
	return JWResult.OK


## S06 §6.8：经常账户与对外头寸。
## external_debt_uu 由 JWTurnRunner 取自 bonds.debt_outstanding_of_holder(JWUnits.Holder.ROW)：
## 本类与 JWBondBook 同为秩 4，同秩之间不得互相引用（§3.2/§3.3），故降级成整数形参。
## 步骤：S06 §6.8
## 前置：本季出口、进口、对外利息、对外净借款已确定；external_debt_uu 来自本季已结算的 JWBondBook
## 后置：current_account += 出口 − 进口 − 对外利息 + 对外净借款
## 不变量：INV-106、INV-107（外债 == Σ holder==row 的未偿本金）、INV-110（Δ净头寸 == −(经常+金融)）
## 失败：残差不为 0 → Fault.LEDGER_IMBALANCE
func settle_current_account(external_interest_uu: int, external_net_borrowing_uu: int,
		external_debt_uu: int, accounts: JWAccount) -> int:
	if accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, JWIds.AGENT_ROW, 0)
	# 对外利息与外债余额都不可能为负；净借款可正可负（净还本时为负）。
	if external_interest_uu < 0 or external_debt_uu < 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				external_interest_uu, external_debt_uu)
	# docs/12 §6.8 / INV-106，逐项照抄：
	#   current_account += exports − imports − 对外利息 + 对外净借款
	var delta: int = f_exports_uu - f_imports_uu - external_interest_uu + external_net_borrowing_uu
	var acc: int = current_account + delta
	if acc > JWUnits.AMOUNT_MAX or acc < -JWUnits.AMOUNT_MAX:
		return JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, acc, JWUnits.AMOUNT_MAX)
	current_account = acc
	# INV-107：外债口径两侧必须一致 —— 债券表侧的 Σ(holder == row) principal_outstanding_uu
	# 与账本侧 agent.row 的 bondhold（面值口径，world.json external_accounts）。
	# 不一致说明发行／还本／减记三条路径里有一条没有双边入账，属恒等式破裂，按 §6.10 立即停，
	# **不做任何自动修正**。
	var row_bondhold: int = accounts.get_balance(
			JWIds.idx_account(JWIds.AGENT_ROW, JWIds.ACC_BONDHOLD))
	var residual: int = row_bondhold - external_debt_uu
	if residual != 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, external_debt_uu, residual)
	return JWResult.OK


## 派生只读：该部门的出口需求乘数（供 S05 出口额度与报告）。
## 步骤：全部
## 前置：s ∈ [0, JWUnits.S)
## 后置：不改状态
## 不变量：INV-105（fx 恒定）
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回 0
func export_demand(s: int) -> int:
	if s < 0 or s >= JWUnits.S or export_demand_ppm.size() != JWUnits.S:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, s, JWUnits.S)
		return 0
	return export_demand_ppm[s]


## 派生只读：该部门的进口价格乘数（供 S05 进口计价与报告）。
## 步骤：全部
## 前置：s ∈ [0, JWUnits.S)
## 后置：不改状态
## 不变量：INV-105（fx 恒定）
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回 0
## R-TRADE-01：伙伴合计倍率（不是状态：每季 S01 由 JWPartners 写入，旧剧本恒为 1e6）。
var partner_export_mult_ppm: int = JWUnits.PPM
var partner_import_price_mult_ppm: int = JWUnits.PPM


## 出口需求（已含伙伴通道倍率）。R-TRADE-01：伙伴份额改变的是通道，不改变本国的产能与外国的基准需求。
## 本季实际有效的外部需求：基础需求 × 伙伴通道倍率（R-TRADE-01）× 相对价格倍率（R-TRADE-PRICE-01）。
## 需求侧与 record_export 的上限断言**必须**读同一个函数，否则断言会比实际成交更紧。
func export_demand_with_partners(s: int) -> int:
	if s < 0 or s >= export_demand_ppm.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, s, export_demand_ppm.size())
		return 0
	if partner_export_mult_ppm == JWUnits.PPM and export_competitiveness_ppm == JWUnits.PPM \
			and export_budget_ppm == JWUnits.PPM:
		return export_demand_ppm[s]
	var v: int = JWMath.mul_ppm(export_demand_ppm[s], partner_export_mult_ppm)
	v = JWMath.mul_ppm(v, export_competitiveness_ppm)
	v = JWMath.mul_ppm(v, export_budget_ppm)
	return JWMath.clamp_i(v, EXPORT_DEMAND_MIN_PPM, EXPORT_DEMAND_MAX_PPM)


func import_price(s: int) -> int:
	if s < 0 or s >= JWUnits.S or import_price_ppm.size() != JWUnits.S:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, s, JWUnits.S)
		return 0
	# R-TRADE-01：按进口份额加权的伙伴价格系数（含贸易协定的折扣）；旧剧本恒为 1e6。
	if partner_import_price_mult_ppm == JWUnits.PPM:
		return import_price_ppm[s]
	return JWMath.clamp_i(JWMath.mul_ppm(import_price_ppm[s], partner_import_price_mult_ppm),
			IMPORT_PRICE_MIN_PPM, IMPORT_PRICE_MAX_PPM)


## 派生只读：主权利率（供 S02 新发债定价）。
## 步骤：全部
## 前置：无
## 后置：不改状态
## 不变量：INV-105、INV-038
## 失败：无
func sovereign_rate() -> int:
	return sovereign_rate_ppm


## 派生只读：外部信用剩余额度 == credit_limit − credit_used。
## 步骤：全部
## 前置：无
## 后置：不改状态
## 不变量：INV-034
## 失败：无
func credit_headroom() -> int:
	# 下限 0：外部收紧把 credit_limit 压到 credit_used 以下时，剩余额度是 0 而不是负数
	# （负数会在 min() 里变成「负的可借量」，把拒绝路径变成一个反向加款的路径）。
	var head: int = credit_limit - credit_used
	if head < 0:
		return 0
	return head


# 派生只读：外债 `derived.world.external_debt_uu`（INV-107）**不在本类**。
# 它等于 Σ (holder == row) bond.principal_outstanding_uu，这两个数组由 JWBondBook 持有（规则 R-A），
# 故按规则 R-C「派生量由其所有者以纯函数形式提供」，唯一提供者是
#     JWBondBook.debt_outstanding_of_holder(JWUnits.Holder.ROW)
# 本类秩 4 与 JWBondBook 同秩，不得引用它（§3.2/§3.3）。需要该值的调用方自行向 JWBondBook 取。


## 派生只读：对外净头寸（对外资产 − 对外负债）。
## 步骤：全部
## 前置：accounts 已完成本季结算
## 后置：不改状态
## 不变量：INV-107、INV-110
## 失败：无
func net_foreign_position(accounts: JWAccount) -> int:
	if accounts == null:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, JWIds.AGENT_ROW, 0)
		return 0
	# docs/12 §6.8 与 world.json identities_zh：
	#   derived.world.net_foreign_position_uu == −agent.row.nw
	# 本国的对外净头寸就是外部世界净值的相反数：row 对本国的净债权为正，本国净头寸即为负。
	var row_nw: int = accounts.net_worth_of(JWIds.AGENT_ROW)
	if row_nw == JWMath.INT64_MIN:
		JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, row_nw, 0)
		return 0
	return -row_nw


## §1.6 状态块协议：LOAD 期一次性 resize 到 §2 的契约长度。
## 步骤：LOAD
## 前置：维度常量已确定
## 后置：全部数组长度固定，此后不再 resize
## 不变量：docs/10 §0.6（加载期一次性 resize）
## 失败：无
func allocate() -> void:
	export_demand_ppm.resize(JWUnits.S)
	export_demand_ppm.fill(0)
	import_price_ppm.resize(JWUnits.S)
	import_price_ppm.fill(0)
	delivery_capacity.resize(JWUnits.S)
	delivery_capacity.fill(0)
	f_exports_uqs.resize(JWUnits.S)
	f_exports_uqs.fill(0)
	f_imports_uqs.resize(JWUnits.S)
	f_imports_uqs.fill(0)
	base_export_uqs.resize(JWUnits.S)
	base_export_uqs.fill(0)
	base_export_ppm.resize(JWUnits.S)
	base_export_ppm.fill(0)
	base_import_ppm.resize(JWUnits.S)
	base_import_ppm.fill(0)
	_delivery_remaining.resize(JWUnits.S)
	_delivery_remaining.fill(0)
	_import_shortfall_uqs.resize(JWUnits.S)
	_import_shortfall_uqs.fill(0)
	# 标量一并归零：allocate() 在内容载入之前跑，此时任何非 0 都只能来自上一局的残留。
	credit_limit = 0
	credit_used = 0
	sovereign_rate_ppm = 0
	current_account = 0
	# R-TRADE-PRICE-01：默认无传导（倍率恒为基准），由剧本的弹性打开。
	export_competitiveness_ppm = JWUnits.PPM
	import_attractiveness_ppm = JWUnits.PPM
	trade_elasticity_ppm = 0
	export_budget_ppm = JWUnits.PPM
	f_exports_uu = 0
	f_imports_uu = 0
	base_credit_limit = 0


## §1.6 状态块协议：按下标只读取用状态数组（返回引用，调用方不得写）。
## 步骤：加载、哈希、存档
## 前置：i ∈ [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136（下标顺序是 schema 的一部分）
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回空数组
func state_array(i: int) -> PackedInt64Array:
	# 下标顺序即 STATE_ARRAY_IDS 的顺序，重排是 schema 破坏性变更（INV-136）。
	if i == 0:
		return export_demand_ppm
	if i == 1:
		return import_price_ppm
	if i == 2:
		return delivery_capacity
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


## §1.6 状态块协议：写入状态数组，**仅 LOAD / MIG**。
## 步骤：LOAD / MIG
## 前置：调用点位于 systems/content_loader.gd 或 systems/saves.gd（静态检查）
## 后置：对应成员被整体替换，长度必须与契约一致
## 不变量：INV-136
## 失败：越界或长度不符 → 返回对应 Fault / Load 码
func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i < 0 or i >= STATE_ARRAY_IDS.size():
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	if v.size() != JWUnits.S:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v.size(), JWUnits.S)
	# duplicate()：Godot 4 的 Packed*Array 传参是引用语义，直接赋值会让本块的权威状态
	# 与调用方的临时数组共用同一块内存（与 JWRngStreams.set_state_array 同一理由）。
	if i == 0:
		export_demand_ppm = v.duplicate()
		return JWResult.OK
	if i == 1:
		import_price_ppm = v.duplicate()
		return JWResult.OK
	delivery_capacity = v.duplicate()
	return JWResult.OK


## §1.6 状态块协议：按下标读取状态标量。
## 步骤：加载、哈希、存档
## 前置：i ∈ [0, STATE_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回 0
func state_scalar(i: int) -> int:
	if i == 0:
		return credit_limit
	if i == 1:
		return credit_used
	if i == 2:
		return sovereign_rate_ppm
	if i == 3:
		return current_account
	if i == 4:
		return export_competitiveness_ppm
	if i == 5:
		return import_attractiveness_ppm
	if i == 6:
		return trade_elasticity_ppm
	if i == 7:
		return export_budget_ppm
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


## §1.6 状态块协议：写入状态标量，**仅 LOAD / MIG**。
## 步骤：LOAD / MIG
## 前置：调用点位于 systems/content_loader.gd 或 systems/saves.gd（静态检查）
## 后置：对应成员被写
## 不变量：INV-136
## 失败：越界 → 返回 Fault.INDEX_OUT_OF_RANGE
func set_state_scalar(i: int, v: int) -> int:
	if i == 0:
		credit_limit = v
		return JWResult.OK
	if i == 1:
		credit_used = v
		return JWResult.OK
	if i == 2:
		sovereign_rate_ppm = v
		return JWResult.OK
	if i == 3:
		current_account = v
		return JWResult.OK
	if i == 4:
		export_competitiveness_ppm = v
		return JWResult.OK
	if i == 5:
		import_attractiveness_ppm = v
		return JWResult.OK
	if i == 6:
		trade_elasticity_ppm = v
		return JWResult.OK
	if i == 7:
		export_budget_ppm = v
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())


## §1.6 状态块协议：按下标只读取用流量数组。
## 步骤：报告、哈希对账
## 前置：i ∈ [0, FLOW_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-013
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回空数组
func flow_array(i: int) -> PackedInt64Array:
	if i == 0:
		return f_exports_uqs
	if i == 1:
		return f_imports_uqs
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
	return PackedInt64Array()


## §1.6 状态块协议：按下标读取流量标量。
## 步骤：报告、哈希对账
## 前置：i ∈ [0, FLOW_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-013
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回 0
func flow_scalar(i: int) -> int:
	if i == 0:
		return f_exports_uu
	if i == 1:
		return f_imports_uu
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_SCALAR_IDS.size())
	return 0


## §1.6 状态块协议：全部 FLOW_* 归零，**仅 S01**。
## 步骤：S01 §01.3
## 前置：调用点位于 systems/turn_runner.gd 的 _step_s01（静态检查）
## 后置：全部流量成员为 0；随后 flow_abs_sum() 必须为 0
## 不变量：INV-013
## 失败：无（非零由 flow_abs_sum 转 Fault.FLOW_NOT_RESET）
func reset_flows() -> void:
	f_exports_uqs.fill(0)
	f_imports_uqs.fill(0)
	f_exports_uu = 0
	f_imports_uu = 0
	# _delivery_remaining 不在 FLOW_ARRAY_IDS 里（它是 S05 的工作缓冲，不进 state_hash），
	# 但它是流量类成员：在此一并归零，保证「S05 之外不存在可用的剩余交付额度」，
	# 也保证「本季没用满的交付能力不会结转到下季」（world.json forbidden_zh 第 4 条）。
	if _delivery_remaining.size() == JWUnits.S:
		_delivery_remaining.fill(0)
	# 未满足进口需求同为 S05 工作缓冲：不进 FLOW_ARRAY_IDS（不进 state_hash），
	# 但每季必须归零，否则上季的短缺会被当成本季的诊断读出去。
	if _import_shortfall_uqs.size() == JWUnits.S:
		_import_shortfall_uqs.fill(0)


## §1.6 状态块协议：S01 清零后的自检，非 0 即 FLOW_NOT_RESET。
## 步骤：S01 §01.3 末
## 前置：reset_flows() 刚被调用
## 后置：不改状态
## 不变量：INV-013
## 失败：无（调用方据返回值转 Fault.FLOW_NOT_RESET）
func flow_abs_sum() -> int:
	# 只统计 FLOW_* 注册表里的四个成员：自检必须与「被清零的注册表」严格同一口径，
	# 否则一个未登记的缓冲就能让 S01 自检报出一个没人能对账的数。
	var acc: int = JWMath.sum_abs(f_exports_uqs) + JWMath.sum_abs(f_imports_uqs)
	acc += JWMath.absi(f_exports_uu)
	acc += JWMath.absi(f_imports_uu)
	return acc


## §1.6 状态块协议：读档时写回流量数组（R-SAVE-01，由 tools/gen_flow_setters.py 按 flow_array 逐项对称生成）。
## 步骤：LOAD（JWSaves 经 JWSimState 调用）
## 前置：v 的长度与本块当前分配的长度一致（长度是 schema 的一部分，INV-136）
## 后置：对应成员被整体替换
## 不变量：INV-133（读档后与原进程逐位相同）
## 失败：下标越界或长度不符 → INDEX_OUT_OF_RANGE
func set_flow_array(i: int, v: PackedInt64Array) -> int:
	if i == 0:
		if v.size() != f_exports_uqs.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_exports_uqs = v.duplicate()
		return JWResult.OK
	if i == 1:
		if v.size() != f_imports_uqs.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_imports_uqs = v.duplicate()
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())


## §1.6 状态块协议：读档时写回流量标量（R-SAVE-01，由 tools/gen_flow_setters.py 按 flow_scalar 逐项对称生成）。
## 步骤：LOAD
## 前置：无
## 后置：对应成员被赋值
## 不变量：INV-133
## 失败：下标越界 → INDEX_OUT_OF_RANGE
func set_flow_scalar(i: int, v: int) -> int:
	if i == 0:
		f_exports_uu = v
		return JWResult.OK
	if i == 1:
		f_imports_uu = v
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_SCALAR_IDS.size())
