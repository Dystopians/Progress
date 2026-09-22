## 全部 `derived.*` 的汇总与一致性比对、约束诊断与溯源、结构化复盘。
##
## **只读。任何 S01…S08 的结算路径都不得调用本类**（docs/17 §3.1 规则 R-C，静态检查）。
## 唯一例外：S08 末 `JWTurnRunner` 调 `snapshot_and_verify()`。
## 依赖秩 9（docs/17 §3.2）：可读 ≤8 的全部类，只读不写。
##
## 全部成员是 `derived.*`（类 D）与 `log.explanations`（类 L），**都不进 `state_hash`**
## （docs/10 §11 的哈希排除清单），因此 STATE_ / FLOW_ 注册表为空。
##
## **本类不写任何展示文案**（docs/10 §12「SimCore 内不出现任何展示文案」）。
## 计划书 §13 末「解释器不冒充因果识别」在这里的落地是三件结构性事实，而不是措辞约定：
##   1. `e_kind` 是每一行的必填列，三类（已经发生 / 规则推断 / 情景预测）**逐行分栏存放**，
##      本类内部任何汇总都不跨 `e_kind` 求和（INV-140）；
##   2. `inferred` 行的载荷是 `e_constraint`（binding_code）与 `e_qty`（该约束的数量值），
##      **一个瓶颈一行**；本类不提供、也不计算「多个瓶颈的合计影响」——
##      「多个瓶颈不做相加」因此是数据结构上的事实，不是渲染层的自律；
##   3. `projected` 行只写日志，**不触碰任何 state.* / flow.***（INV-140，构建期静态检查）。
## 「模型中的限制因素」这类措辞由 Presentation 按 `e_cause` / `e_constraint` 查模板表生成。
class_name JWDiagnostics
extends RefCounted

## 本块各状态数组所属子系统（与 STATE_ARRAY_IDS 等长）。本块无状态数组，故为空。
const STATE_ARRAY_SUBSYS: PackedInt64Array = []

## 稳定 ID 注册表：本块全部字段是 derived.* 与 log.*，不进 state_hash，故四张表均为空。
const STATE_ARRAY_IDS: PackedStringArray = []
const STATE_SCALAR_IDS: PackedStringArray = []
const FLOW_ARRAY_IDS: PackedStringArray = []
const FLOW_SCALAR_IDS: PackedStringArray = []

# ── 分类汇总缓冲的长度（必须与 JWLedger 的同名常量一致，docs/11 §5.3 的枚举基数） ──

## JWUnits.ProdClass 的取值个数（none + 4 类）
const PROD_CLASS_N: int = 5
## JWUnits.ExpClass 的取值个数（none + C/G/I/dINV/X/M）
const EXP_CLASS_N: int = 7
## JWUnits.IncClass 的取值个数（none + 3 类）
const INC_CLASS_N: int = 4

## 滚动四季缓冲长度（derived.gdp.annual_nominal_uu 的口径）
const GDP_HISTORY_N: int = 4
## 「年化」= 季度值 × 4（docs/12 §02.6 的偿债率分母口径）
const QUARTERS_PER_YEAR: int = 4

## 日志扩容倍率 3/2（docs/10 §12「满则按 1.5 倍扩容并写一条告警」），写成分子分母避免小数字面量。
const LOG_GROWTH_NUM: int = 3
const LOG_GROWTH_DEN: int = 2

# ── 派生量编号（snapshot_and_verify 不一致时写进 Fault.detail_a） ───────────
#
# 编号是故障包与测试断言的一部分，**只许在末尾追加，不得重排**。

const DERIVED_ID_GDP_PRODUCTION: int = 0
const DERIVED_ID_GDP_EXPENDITURE: int = 1
const DERIVED_ID_GDP_INCOME: int = 2
const DERIVED_ID_PRICE_VARIANCE_TOTAL: int = 3
const DERIVED_ID_GDP_REAL: int = 4
const DERIVED_ID_GDP_ANNUAL_NOMINAL: int = 5
const DERIVED_ID_DEBT_TO_GDP_PPM: int = 6
const DERIVED_ID_DEBT_SERVICE_RATIO_PPM: int = 7
const DERIVED_ID_NEXT4Q_DEBT_SERVICE: int = 8
## 收入五分位占用 9…13（第 k 档的编号 == 该基址 + k）
const DERIVED_ID_INCOME_QUANTILE_BASE: int = 9
const DERIVED_ID_N: int = 14

# ── log.explanations 的本类自产码（其余 cause 码由调用方给出） ─────────────

## `e_entity` 的元信息哨兵：该行不指向任何经济实体，只描述日志通道自身。
## add_explanation() 拒绝调用方传入负 entity，因此这个值只可能来自本类的内部写入口。
const ENTITY_SELF: int = -1
## `e_cause`：日志容量耗尽并已按 1.5 倍扩容（告警行，金额与数量恒为 0，不影响任何加总）
const CAUSE_LOG_CAPACITY_GROWN: int = 1
## `e_cause`：情景推演结果（record_projection 写入的行的来源操作）
const CAUSE_PROJECTION: int = 2

## `_derived_hash_prev` 的逐槽盐值（纯位运算折叠，见 _mix）。长度 16，按 slot & 15 取用。
## 每个值都小于 2^63（首位十六进制数字 <= 7），否则不是合法的 int64 字面量。
const HASH_SALT: PackedInt64Array = [
	0x1F83D9AB5BE0CD19, 0x428A2F98D728AE22, 0x7137449123EF65CD, 0x0B5688C2B3E6C1FD,
	0x59F111F1B605D019, 0x123F82A4AF194F9B, 0x2B1C5ED5DA6D8118, 0x3956C25BF348B538,
	0x59F111F1B605D01B, 0x123F82A4AF194F9D, 0x2B1C5ED5DA6D811A, 0x3956C25BF348B53A,
	0x5807AA98A3030242, 0x12835B0145706FBE, 0x243185BE4EE4B28C, 0x550C7DC3D5FFB4E2,
]

## `derived.gdp.production_uu`，单位 μU（**权威口径**）。
var gdp_production: int = 0
## `derived.gdp.expenditure_uu`，单位 μU。
var gdp_expenditure: int = 0
## `derived.gdp.income_uu`，单位 μU。
var gdp_income: int = 0
## `derived.gdp.price_variance_total_uu`，单位 μU。
var price_variance_total: int = 0
## `derived.gdp.real_uu`，单位 μU（基年价）。
var gdp_real: int = 0
## `derived.gdp.annual_nominal_uu`，单位 μU（滚动四季）。
var gdp_annual_nominal: int = 0
## 滚动四季缓冲，长 4，单位 μU。
var _gdp_history: PackedInt64Array = PackedInt64Array()

## `derived.labor.unemployment_ppm`，单位 ppm。
var unemployment_ppm: int = 0
## `derived.fiscal.debt_to_gdp_ppm`，单位 ppm。
var debt_to_gdp_ppm: int = 0
## `derived.fiscal.debt_service_ratio_ppm`，单位 ppm。
var debt_service_ratio_ppm: int = 0
## `derived.fiscal.next4q_debt_service_uu`，单位 μU。
var next4q_debt_service: int = 0
## `derived.living.consumption_index_ppm`，单位 ppm。
var living_consumption_index: int = 0
## `derived.living.public_service_index_ppm`，单位 ppm。
var living_service_index: int = 0
## `derived.income_quantile_uu[5]`，长 5，单位 μU（近似量，**不存在精确基尼系数字段**）。
var income_quantile: PackedInt64Array = PackedInt64Array()

## `derived.region.population_persons`，长 4，单位 人。
var region_population: PackedInt64Array = PackedInt64Array()
## `derived.group.labor_force_persons`，长 36，单位 人。
var labor_force: PackedInt64Array = PackedInt64Array()
## `derived.region.electricity_availability_ppm`，长 4，单位 ppm。
var electricity_availability: PackedInt64Array = PackedInt64Array()
## `derived.region.housing_occupied_units`，长 4，单位 套。
var housing_occupied: PackedInt64Array = PackedInt64Array()
## `derived.region.slots_used`，长 4，单位 个。
var slots_used: PackedInt64Array = PackedInt64Array()
## `derived.cell.capacity_value_drift_ppm`，长 16，单位 ppm。
var capacity_value_drift: PackedInt64Array = PackedInt64Array()

## `log.explanations.entity`，长 LOG_CAP0。
var e_entity: PackedInt64Array = PackedInt64Array()
## `log.explanations.cause`，长 LOG_CAP0。
var e_cause: PackedInt64Array = PackedInt64Array()
## `log.explanations.amount_uu`，长 LOG_CAP0。
var e_amount: PackedInt64Array = PackedInt64Array()
## `log.explanations.qty_uqs`，长 LOG_CAP0。
var e_qty: PackedInt64Array = PackedInt64Array()
## `log.explanations.q`，长 LOG_CAP0。
var e_q: PackedInt64Array = PackedInt64Array()
## `log.explanations.constraint_code`，长 LOG_CAP0。
var e_constraint: PackedInt64Array = PackedInt64Array()
## `log.explanations.kind`（ACCOUNTED / INFERRED / PROJECTED），长 LOG_CAP0。
var e_kind: PackedInt64Array = PackedInt64Array()

## INV-014 的重算比对缓存：最近一次 snapshot_and_verify() 通过后全部 derived.* 的折叠值。
## 只作诊断用（逐项比对才是权威检查），不进 state_hash、不进存档。
var _derived_hash_prev: int = 0
## 本季日志游标（已写行数），每季 S01 由 log_reset_quarter() 归零。
var _log_cursor: int = 0
## 日志当前容量（行）；写满时按 1.5 倍扩容并写一条告警行。
var _log_capacity: int = 0
## 本局日志扩容次数（诊断用；不进 state_hash）。
var _log_grow_count: int = 0

## 本季是否已经把一个季度 GDP 推进过滚动四季缓冲（0 未推进 / 1 已推进）。
## 存在的唯一理由：`compute_gdp()` 在 S06 被调用一次，`snapshot_and_verify()` 在 S08 又调用一次；
## 若每次调用都推一格，重算就会把缓冲多移一位，`gdp_annual_nominal` 的比对必然假红。
## 有了它，`compute_gdp()` 在同一季内**幂等**：第二次只覆盖最新一格。由 log_reset_quarter() 归零。
var _gdp_slot_filled: int = 0

## ledger.aggregate_classes() 的三口径分类缓冲（预分配，热路径不新建）。
var _agg_prod: PackedInt64Array = PackedInt64Array()
var _agg_exp: PackedInt64Array = PackedInt64Array()
var _agg_inc: PackedInt64Array = PackedInt64Array()

## 五分位：逐组人均可支配收入（μU/人/季），长 GROUP。
var _q_pc: PackedInt64Array = PackedInt64Array()
## 五分位：按 _q_pc 升序（并列按组下标升序）的组下标，长 GROUP。
var _q_order: PackedInt64Array = PackedInt64Array()

## snapshot_and_verify() 的「本季已写值」暂存：标量部分，长 DERIVED_ID_N。
var _verify_saved: PackedInt64Array = PackedInt64Array()


## S06 §6.4：GDP 三口径与价差调节项。
## 步骤：S06 §6.4（由 JWTurnRunner 在 S06 末调用，只读状态、只写 derived.*）
## 前置：本季全部分录已写；三分类码完备（INV-114 已通过）
## 后置：gdp_production = Σ value_added + Σ pubserv(wage + dep)；
##       gdp_expenditure = C + G + I + dINV + X − M；
##       price_variance_total = Σ 入库交易的 (qty − value)
## 不变量：INV-111, INV-112（禁止 Σ 销售额）, INV-115（残差恰为 0）, INV-116, INV-117,
##          INV-118（无命令跑满基年四季 Σ == 100 000 000 μU，容差 0）, INV-119
## 失败：INV-115 残差 != 0 → Fault.GDP_IDENTITY；
##       全国 gdp_production <= 0 → Fault.GDP_IDENTITY（模型已发散，OQ-219）
func compute_gdp(sectors: JWSectorModel, capital: JWCapital, inventory: JWInventory,
		world: JWWorldMarket, treasury: JWTreasury, ledger: JWLedger) -> int:
	if sectors == null or capital == null or inventory == null or world == null \
			or treasury == null or ledger == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, 0)
	if _agg_exp.size() != EXP_CLASS_N or _gdp_history.size() != GDP_HISTORY_N:
		# allocate() 没跑过。宁可显式失败，也不在结算路径上偷偷 resize（docs/10 §0.6）。
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				_agg_exp.size(), EXP_CLASS_N)
	if capital.f_pub_output.size() != JWUnits.PUBSERV \
			or inventory.f_pub_intermediate.size() != JWUnits.PUBSERV:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				capital.f_pub_output.size(), JWUnits.PUBSERV)
	if sectors.f_operating_surplus.size() != JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				sectors.f_operating_surplus.size(), JWUnits.CELL)

	# ── (0) 覆盖性检验（INV-114）+ 支出法的分类汇总 ───────────────────────
	# 唯一数据源是本季账本行的三个分类码（docs/11 §5.3 的 kind → 三分类白名单，
	# 即 JWUnits.KIND_PROD_CLASS / KIND_EXP_CLASS / KIND_INC_CLASS 三张表）。
	# 覆盖性是「三法一致」的真正检验（docs/10 §9.4）：漏标、错标、重复计入都在这里红。
	var cls: int = ledger.aggregate_classes(_agg_prod, _agg_exp, _agg_inc)
	if cls != JWResult.OK:
		return cls

	# ── (1) 公共非市场产出的增加值（§6.3：其增加值 == wage_bill + depreciation） ──
	# f_pub_output == wage_bill + intermediate + depreciation，故 wage + dep == output − intermediate。
	# 这样只用本签名里已有的两个域类就能取到，不必再引入 JWLaborMarket（秩约束）。
	var pub_va_total: int = 0
	var g_uu: int = 0
	var r: int = 0
	while r < JWUnits.PUBSERV:
		var pub_out: int = capital.f_pub_output[r]
		g_uu += pub_out
		pub_va_total += pub_out - inventory.f_pub_intermediate[r]
		r += 1
	JWMath.check_amount(g_uu)

	# ── (2) 生产法（权威口径，INV-112：禁止用 Σ 销售额求和） ─────────────
	var production: int = 0
	var real: int = 0
	var income: int = 0
	var i: int = 0
	while i < JWUnits.CELL:
		var va: int = sectors.value_added(i)
		var os: int = sectors.f_operating_surplus[i]
		production += va
		real += sectors.value_added_real(i)
		# §6.4 收入法：Σ_i (wage_bill + operating_surplus)。营业盈余按残差定义
		# （operating_surplus == value_added − wage_bill，docs/10 §9.3），
		# 所以 wage_bill 由同一条定义式反解，收入法因此是**恒等式而非独立计算**（INV-116）。
		# 它真正的检验内容是上面 (0) 的覆盖性检验，不是这里的加总。
		income += (va - os) + os
		i += 1
	production += pub_va_total
	# 实际口径（INV-117）：逐 cell 的基年价增加值直接相加；公共非市场产出按成本计价（§6.3），
	# 成本项（工资与折旧）本来就只有一轨账，**禁止**用任何价格指数去折算它。
	real += pub_va_total
	income += pub_va_total
	JWMath.check_amount(production)
	JWMath.check_amount(real)
	JWMath.check_amount(income)

	# ── (3) 支出法分解 C + G + I + dINV + X − M ─────────────────────────
	# C：居民消费成交额（现价）。账本 exp_class == C 的分类腿之和（kind 3 居民消费；kind 25 迁移成本自 R-MIGRATE-01 起是再分配类，不进 C）。
	#    分类腿是收款腿（+amount），故桶内恒为正额，符号由本式显式给出。
	var c_uu: int = _agg_exp[JWUnits.ExpClass.C]
	# I：资本品购入额（现价），账本 exp_class == I（kind 7 资本品购入 + kind 19 项目履约付款）。
	var i_uu: int = _agg_exp[JWUnits.ExpClass.I]
	# dINV：存货变动，**基年价**。d_inventory_* 是数量口径（μQ），按 docs/12 §0.3.3 的
	#       at_base() 换算成 μU；R-SCALE-01 之后 μU 与 μQ 的数值不再碰巧相等，必须显式换算。
	var dinv_qty: int = 0
	var k: int = 0
	while k < JWUnits.CELL:
		dinv_qty += inventory.d_inventory_output(k) + inventory.d_inventory_input(k)
		k += 1
	var dinv_uu: int = _at_base(dinv_qty)
	# X / M：flow.world.exports_uu 与 flow.world.imports_uu（§6.4 逐字口径）。
	var x_uu: int = world.f_exports_uu
	var m_uu: int = world.f_imports_uu
	var expenditure: int = c_uu + g_uu + i_uu + dinv_uu + x_uu - m_uu
	JWMath.check_amount(expenditure)

	# ── (4) 价差调节项（INV-119：逐笔可追溯到入库交易的 at_base(qty) − paid） ──
	var pv: int = inventory.price_variance_total()

	# ── (5) 落盘。先写后检：故障包要能看见这一季实际算出的三口径，而不是一组空值。 ──
	gdp_production = production
	gdp_expenditure = expenditure
	gdp_income = income
	price_variance_total = pv
	gdp_real = real
	if _gdp_slot_filled == 0:
		# 本季第一次：整体左移一格，最新一季落在末位。
		var s: int = 0
		while s < GDP_HISTORY_N - 1:
			_gdp_history[s] = _gdp_history[s + 1]
			s += 1
		_gdp_slot_filled = 1
	_gdp_history[GDP_HISTORY_N - 1] = production
	gdp_annual_nominal = JWMath.sum(_gdp_history)

	# ── (6) 恒等式（INV-115，残差必须恰为 0；绝不做「平衡修正」） ─────────
	var expected: int = production + pv
	if expenditure != expected:
		return JWResult.raise_fault(JWResult.Fault.GDP_IDENTITY, expenditure, expected)
	# INV-116：收入法按残差定义必然等于生产法；不等即说明上式的反解被人改过。
	if income != production:
		return JWResult.raise_fault(JWResult.Fault.GDP_IDENTITY, income, production)
	# 模型已发散（OQ-219）：全国增加值非正不是「经济很差」，是核算已经没有意义。
	if production <= 0:
		return JWResult.raise_fault(JWResult.Fault.GDP_IDENTITY, production, 1)
	return JWResult.OK


## S06：财政派生量（债务/GDP、偿债率、未来四季到期）。
## 步骤：S06 末
## 前置：compute_gdp 已完成
## 后置：三项写入；**债务/GDP 单独展示并注明不能替代偿付能力分析**
## 不变量：INV-038（偿债率是新发债利率的单调输入）
## 失败：gdp == 0 → 用 max(gdp,1)，不除零
func compute_fiscal(bonds: JWBondBook, treasury: JWTreasury, q: int) -> int:
	if bonds == null or treasury == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, 0)
	if q < 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, q, 0)

	# 债务/GDP：分母是**滚动四季名义 GDP**（docs/20 §「债务（存量）· 名义 GDP（四季滚动）· 比率」）。
	# 展示纪律：这个比率单独展示并紧跟免责句，**不能替代偿付能力分析**（计划书 §07）；
	# 本类只给数，措辞由 Presentation 的模板负责。
	var debt: int = bonds.debt_outstanding()
	var gdp_denom: int = gdp_annual_nominal
	if gdp_denom < 1:
		gdp_denom = 1
	# 裸乘 debt × 1e6 在新刻度下会溢出（AMOUNT_MAX 4e15 × PPM 1e6 = 4e21 > int64），
	# 必须走 mul_div_floor（裁定 R-SCALE-01 的强制要求 1）。
	debt_to_gdp_ppm = JWMath.mul_div_floor(debt, JWUnits.PPM, gdp_denom)

	# 未来四季到期本金 + 利息（计划书 §07 财政页必须展示）。口径与 §02.6 的 dsr 分子同一个函数，
	# 保证 INV-038 的「利率对偿债率单调不减」两端用的是同一个数。
	next4q_debt_service = bonds.debt_service_next4q(q)

	# 偿债率：docs/12 §02.6 的定义式
	#   dsr_ppm = mul_div_floor(未来4季(利息+本金)_uu, 1e6, max(年化收入_uu, 1))
	# 年化收入在本签名下的唯一可得口径是本季实收三项 × 4（本季 S06 已写完收入）。
	# S02 用的是年计划的 receipts；两者在基年一致，偏离即预算执行偏差本身。
	# 若要让两端严格同源，需要 JWTreasury 暴露年化收入口径（已登记 interface_request）。
	var receipts_q: int = treasury.f_receipts_income_tax + treasury.f_receipts_profit_tax \
			+ treasury.f_receipts_other
	var receipts_annual: int = JWMath.mul(receipts_q, QUARTERS_PER_YEAR)
	if receipts_annual < 1:
		receipts_annual = 1
	debt_service_ratio_ppm = JWMath.mul_div_floor(next4q_debt_service, JWUnits.PPM,
			receipts_annual)
	return JWResult.OK


## S08：收入五分位近似（**不存在精确基尼系数字段**）。
## 步骤：S08
## 前置：各组可支配收入已算出
## 后置：income_quantile[5] 写入
## 不变量：INV-120（近似量，展示必须标注「未模拟组内差异」；静态检查无 gini 字段）
## 失败：无
func compute_income_quantiles(pop: JWPopulation) -> int:
	if pop == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, 0)
	if income_quantile.size() != JWUnits.QUANTILE_N or _q_pc.size() != JWUnits.GROUP \
			or _q_order.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				income_quantile.size(), JWUnits.QUANTILE_N)
	if pop.population.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				pop.population.size(), JWUnits.GROUP)
	income_quantile.fill(0)

	# (a) 逐组人均可支配收入。组内差异**没有被模拟**（INV-120）：一个组是一个点，
	#     所以下面切出来的五档是「按人口排序的组序列」的分位，是近似量，不是个体分布的分位。
	var total_pop: int = 0
	var g: int = 0
	while g < JWUnits.GROUP:
		var persons: int = pop.population[g]
		if persons < 0:
			persons = 0
		var denom: int = persons
		if denom < 1:
			denom = 1
		_q_pc[g] = JWMath.floor_div(pop.disposable_income(g), denom)
		_q_order[g] = g
		total_pop += persons
		g += 1
	if total_pop <= 0:
		return JWResult.OK

	# (b) 按人均收入升序排序（并列按组下标升序，保证重放逐位可复现）。
	#     插入排序：n == 36，且不新建任何对象。
	var a: int = 1
	while a < JWUnits.GROUP:
		var key: int = _q_order[a]
		var b: int = a - 1
		while b >= 0 and _q_before(key, _q_order[b]):
			_q_order[b + 1] = _q_order[b]
			b -= 1
		_q_order[b + 1] = key
		a += 1

	# (c) 按累计人口切五档；跨界的组按人数拆到相邻两档（人数之和精确等于 total_pop）。
	#     每档取该档的人口加权人均可支配收入。
	var quant: int = 0
	while quant < JWUnits.QUANTILE_N:
		var lo: int = JWMath.mul_div_floor(total_pop, quant, JWUnits.QUANTILE_N)
		var hi: int = JWMath.mul_div_floor(total_pop, quant + 1, JWUnits.QUANTILE_N)
		var acc_income: int = 0
		var acc_persons: int = 0
		var cum: int = 0
		var t: int = 0
		while t < JWUnits.GROUP:
			var gi: int = _q_order[t]
			var n: int = pop.population[gi]
			if n < 0:
				n = 0
			var seg_lo: int = cum
			var seg_hi: int = cum + n
			cum = seg_hi
			var take_lo: int = seg_lo if seg_lo > lo else lo
			var take_hi: int = seg_hi if seg_hi < hi else hi
			var overlap: int = take_hi - take_lo
			if overlap > 0:
				acc_income += JWMath.mul(_q_pc[gi], overlap)
				acc_persons += overlap
			t += 1
		var d: int = acc_persons
		if d < 1:
			d = 1
		income_quantile[quant] = JWMath.floor_div(acc_income, d)
		quant += 1
	return JWResult.OK


## S08 §8.6：结构化复盘（三类信息严格分栏）。
## 步骤：S08 §8.6
## 前置：kind ∈ {ACCOUNTED, INFERRED, PROJECTED}
## 后置：三类分别写入 log.explanations；
##       accounted 可下钻到分录；inferred 只给 binding_code 与五项约束值（**多个瓶颈不做相加**）；
##       projected 必须标注假设
## 不变量：INV-140（三类分离；**projected 条目禁止回写任何状态字段**，静态检查）、INV-123
## 失败：projected 条目触碰状态 → 静态检查失败（构建期）；
##       kind 越界 / entity 为负 / cause 为负 / constraint 为负 → 登记 INDEX_OUT_OF_RANGE 且**不写行**
func add_explanation(kind: int, entity: int, cause: int, amount_uu: int, qty_uqs: int,
		constraint_code: int, q: int) -> void:
	# 前置条件破裂一律显式登记并拒写：半条无法溯源的解释行比没有这一行更坏
	# （计划书 §13 末「解释器不冒充因果识别」——不可追溯的行就是在冒充）。
	if kind < JWUnits.ExplainKind.ACCOUNTED or kind > JWUnits.ExplainKind.PROJECTED:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, kind,
				JWUnits.ExplainKind.PROJECTED)
		return
	# 「每条变化附实体 ID、来源操作、金额/数量、时间与约束」：前两项是必填，负值表示未登记。
	# 负 entity 由 ENTITY_SELF 独占，只有本类的内部写入口能用。
	if entity < 0:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, entity, 0)
		return
	if cause < 0 or constraint_code < 0:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cause, constraint_code)
		return
	# 区间护栏：越界只登记 INT_OVERFLOW，不改数（写进去的必须是调用方真正算出的数）。
	JWMath.check_amount(amount_uu)
	JWMath.check_qty(qty_uqs)
	_write_row(kind, entity, cause, amount_uu, qty_uqs, constraint_code, q)


## 情景预测结果的登记口（**跑预测的是 Application 层的 JWGame.preview_four_quarters()**，
## 它用 duplicate_state() + JWTurnRunner 空命令跑 4 季；SimCore 不认识 systems/，故本类只收结果）。
## 步骤：S08 §8.6（可按 OQ-230 缓存或降频）
## 前置：value 来自同一个 SimCore 的副本推进结果，**不得来自任何第二套近似模型**
## 后置：写入 kind == PROJECTED 的 log.explanations 条目
## 不变量：INV-140（projected 条目禁止回写任何状态字段，静态检查）
## 失败：q_offset < 0 或 metric_code < 0 → 登记 INDEX_OUT_OF_RANGE 且**不写行**
func record_projection(q_offset: int, metric_code: int, value: int) -> void:
	if q_offset < 0 or metric_code < 0:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, q_offset, metric_code)
		return
	JWMath.check_amount(value)
	# 本函数**只写日志**：下面这一行之外没有任何赋值，任何 state.* / flow.* 都不在本函数的可达范围内
	# （本类连 JWSimState 都不认识，规则 R-B）。这就是 INV-140 的结构性保证。
	#
	# 列的含义（与 accounted / inferred 行不同，由 e_cause == CAUSE_PROJECTION 标识）：
	#   e_entity = metric_code（被预测的指标），e_amount = value，
	#   e_q      = q_offset —— **相对季偏移**，不是绝对季号。本签名不带绝对 q，
	#              绝对基准由 Presentation 用当前季补齐后渲染成「到第 N 季」。
	_write_row(JWUnits.ExplainKind.PROJECTED, metric_code, CAUSE_PROJECTION, value, 0, 0,
			q_offset)


## 季末：全部 derived.* 重算并与本季已写值比对（调试构建每季，发布构建抽季）。
## 形参是 compute_gdp / compute_fiscal / compute_income_quantiles 三者形参的并集：
## 本类秩 9，不得引用秩 10 的 JWSimState（§3.1 规则 R-B），故由 JWTurnRunner 逐个传入域类。
## 步骤：S08 末
## 前置：本季结算已完成
## 后置：不改任何 state.* / flow.*
## 不变量：INV-014（派生一致性）
## 失败：不一致 → Fault.LEDGER_IMBALANCE，detail_a = 派生量编号
func snapshot_and_verify(sectors: JWSectorModel, capital: JWCapital, inventory: JWInventory,
		world: JWWorldMarket, treasury: JWTreasury, ledger: JWLedger,
		bonds: JWBondBook, pop: JWPopulation, q: int) -> int:
	if pop == null or bonds == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, 0)
	if _verify_saved.size() != DERIVED_ID_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				_verify_saved.size(), DERIVED_ID_N)

	# (a) 扣下本季已写值。三族派生量（GDP / 财政 / 五分位）在本季分别由 S06 与 S08 写过一次，
	#     它们才是 INV-014 意义上「有前一个写者」的量，下面重算并逐项比对的就是这三族。
	_save_derived()

	# (b) 重算。compute_gdp 在同一季内幂等（见 _gdp_slot_filled），所以滚动四季不会被多推一格。
	var rc: int = compute_gdp(sectors, capital, inventory, world, treasury, ledger)
	if rc != JWResult.OK:
		_restore_derived()
		return rc
	rc = compute_fiscal(bonds, treasury, q)
	if rc != JWResult.OK:
		_restore_derived()
		return rc
	rc = compute_income_quantiles(pop)
	if rc != JWResult.OK:
		_restore_derived()
		return rc

	# (c) 逐项比对。不一致即 LEDGER_IMBALANCE，detail_a = 派生量编号，detail_b = 重算值。
	#     **不做任何「就近取值」「容差放过」**：派生量对不上说明结算路径与重算路径读到了不同的账。
	var bad: int = _first_mismatch()
	if bad >= 0:
		var recomputed: int = _current_derived(bad)
		_restore_derived()
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, bad, recomputed)

	# (d) 纯派生（本季没有第二个写者，重算即定值）。
	rc = _recompute_pure_derived(sectors, capital, pop)
	if rc != JWResult.OK:
		return rc

	_derived_hash_prev = _derived_fold()
	return JWResult.OK


## §1.6 状态块协议：LOAD 期一次性 resize 到 §2 的契约长度。
## 步骤：LOAD
## 前置：维度常量已确定
## 后置：全部 derived 数组与七条 log.explanations 定长，此后不再 resize（日志扩容除外）
## 不变量：docs/10 §0.6（加载期一次性 resize）
## 失败：无
func allocate() -> void:
	_gdp_history.resize(GDP_HISTORY_N)
	_gdp_history.fill(0)
	income_quantile.resize(JWUnits.QUANTILE_N)
	income_quantile.fill(0)

	region_population.resize(JWUnits.R)
	region_population.fill(0)
	labor_force.resize(JWUnits.GROUP)
	labor_force.fill(0)
	electricity_availability.resize(JWUnits.R)
	electricity_availability.fill(0)
	housing_occupied.resize(JWUnits.R)
	housing_occupied.fill(0)
	slots_used.resize(JWUnits.R)
	slots_used.fill(0)
	capacity_value_drift.resize(JWUnits.CELL)
	capacity_value_drift.fill(0)

	e_entity.resize(JWUnits.LOG_CAP0)
	e_entity.fill(0)
	e_cause.resize(JWUnits.LOG_CAP0)
	e_cause.fill(0)
	e_amount.resize(JWUnits.LOG_CAP0)
	e_amount.fill(0)
	e_qty.resize(JWUnits.LOG_CAP0)
	e_qty.fill(0)
	e_q.resize(JWUnits.LOG_CAP0)
	e_q.fill(0)
	e_constraint.resize(JWUnits.LOG_CAP0)
	e_constraint.fill(0)
	e_kind.resize(JWUnits.LOG_CAP0)
	e_kind.fill(0)
	_log_capacity = JWUnits.LOG_CAP0
	_log_cursor = 0

	_agg_prod.resize(PROD_CLASS_N)
	_agg_prod.fill(0)
	_agg_exp.resize(EXP_CLASS_N)
	_agg_exp.fill(0)
	_agg_inc.resize(INC_CLASS_N)
	_agg_inc.fill(0)
	_q_pc.resize(JWUnits.GROUP)
	_q_pc.fill(0)
	_q_order.resize(JWUnits.GROUP)
	_q_order.fill(0)
	_verify_saved.resize(DERIVED_ID_N)
	_verify_saved.fill(0)


## §1.6 状态块协议：按下标只读取用状态数组（本块注册表为空）。
## 步骤：加载、哈希、存档
## 前置：i ∈ [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：docs/10 §11（derived.* 与 log.* 不进 state_hash）
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回空数组
func state_array(i: int) -> PackedInt64Array:
	# 注册表为空 ⇒ 合法下标集合为空集 ⇒ 任何下标都越界。能走到这里就说明调用方没按注册表遍历。
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, 0)
	return PackedInt64Array()


## §1.6 状态块协议：写入状态数组，**仅 LOAD / MIG**（本块注册表为空）。
## 步骤：LOAD / MIG
## 前置：调用点位于 systems/content_loader.gd 或 systems/saves.gd（静态检查）
## 后置：不改状态
## 不变量：docs/10 §11
## 失败：越界 → 返回 Fault.INDEX_OUT_OF_RANGE
@warning_ignore("unused_parameter")
func set_state_array(i: int, v: PackedInt64Array) -> int:
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, 0)


## §1.6 状态块协议：按下标读取状态标量（本块注册表为空）。
## 步骤：加载、哈希、存档
## 前置：i ∈ [0, STATE_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：docs/10 §11
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回 0
func state_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, 0)
	return 0


## §1.6 状态块协议：写入状态标量，**仅 LOAD / MIG**（本块注册表为空）。
## 步骤：LOAD / MIG
## 前置：调用点位于 systems/content_loader.gd 或 systems/saves.gd（静态检查）
## 后置：不改状态
## 不变量：docs/10 §11
## 失败：越界 → 返回 Fault.INDEX_OUT_OF_RANGE
@warning_ignore("unused_parameter")
func set_state_scalar(i: int, v: int) -> int:
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, 0)


## §1.6 状态块协议：按下标只读取用流量数组（本块注册表为空）。
## 步骤：报告、哈希对账
## 前置：i ∈ [0, FLOW_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-013
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回空数组
func flow_array(i: int) -> PackedInt64Array:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, 0)
	return PackedInt64Array()


## §1.6 状态块协议：按下标读取流量标量（本块注册表为空）。
## 步骤：报告、哈希对账
## 前置：i ∈ [0, FLOW_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-013
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回 0
func flow_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, 0)
	return 0


## §1.6 状态块协议：全部 FLOW_* 归零，**仅 S01**（本块无流量，是空实现）。
## 步骤：S01 §01.3
## 前置：调用点位于 systems/turn_runner.gd 的 _step_s01（静态检查）
## 后置：不改状态
## 不变量：INV-013
## 失败：无
func reset_flows() -> void:
	# 本块的成员全是 derived.*（类 D）与 log.*（类 L），没有一个 FLOW_*，
	# 所以「整表清零」在这里没有任何对象可清。derived.* 由季末重算覆盖，
	# **不在这里清零**——清零会让 INV-014 的比对拿到一组假的 0。
	pass


## §1.6 状态块协议：S01 清零后的自检，非 0 即 FLOW_NOT_RESET（本块恒 0）。
## 步骤：S01 §01.3 末
## 前置：reset_flows() 刚被调用
## 后置：不改状态
## 不变量：INV-013
## 失败：无
func flow_abs_sum() -> int:
	return 0


## §1.7 日志通道协议：每季 S01 重置本季游标（日志不进 state_hash）。
## 步骤：S01 §01.1
## 前置：phase == S01
## 后置：_log_cursor == 0
## 不变量：INV-011 / INV-139（行数对账）
## 失败：无
func log_reset_quarter() -> void:
	_log_cursor = 0
	# 新的一季 ⇒ 滚动四季缓冲允许再推进一格（compute_gdp 的季内幂等开关）。
	_gdp_slot_filled = 0


## §1.7 日志通道协议：本季已写行数，供 INV-011 / INV-139 对账。
## 步骤：每季末
## 前置：无
## 后置：不改状态
## 不变量：INV-011、INV-139
## 失败：无
func log_row_count() -> int:
	return _log_cursor


## §1.7 日志通道协议：当前容量；写满时按 1.5 倍扩容并写一条告警行。
## 步骤：每季末
## 前置：无
## 后置：不改状态
## 不变量：INV-139
## 失败：无
func log_capacity() -> int:
	return _log_capacity


## 本局日志扩容发生的次数（诊断用；不进 state_hash）。
## 步骤：每季末 / 诊断
## 前置：无
## 后置：不改状态
## 不变量：INV-139
## 失败：无
func log_grow_count() -> int:
	return _log_grow_count


# ── 内部实现（本类私有） ───────────────────────────────────────────────────

## 基年价计值：μQ_s → μU（docs/12 §0.3.3）。
## 步骤：S06 §6.4
## 前置：|qty_uqs| <= QTY_MAX
## 后置：返回 floor(qty × BASE_PRICE / Q_SCALE)，精确无余数（1e9 / 1e6 == 1000 整除）
## 不变量：INV-117、INV-148
## 失败：溢出转 mul_div_floor 的失败路径
##
## 裸乘 QTY_MAX × BASE_PRICE == 1e21 会溢出 int64；mul_div_floor 的中间量是 1e15，安全（R-SCALE-01）。
static func _at_base(qty_uqs: int) -> int:
	return JWMath.mul_div_floor(qty_uqs, JWUnits.BASE_PRICE, JWUnits.Q_SCALE)


## 五分位排序的全序：人均收入升序 → 组下标升序。
## 步骤：S08
## 前置：x, y ∈ [0, GROUP)
## 后置：返回 true 表示 x 应排在 y 前
## 不变量：INV-014（重放逐位可复现，故必须是全序）
## 失败：无
func _q_before(x: int, y: int) -> bool:
	var vx: int = _q_pc[x]
	var vy: int = _q_pc[y]
	if vx != vy:
		return vx < vy
	return x < y


## 追加一行 log.explanations（本类唯一的写行入口）。
## 步骤：S08 §8.6
## 前置：调用方已校验过列值
## 后置：_log_cursor += 1；必要时先扩容并写一条告警行
## 不变量：INV-139、INV-140（kind 逐行落地，三类不混存）
## 失败：无
func _write_row(kind: int, entity: int, cause: int, amount_uu: int, qty_uqs: int,
		constraint_code: int, q: int) -> void:
	_ensure_row_space()
	e_kind[_log_cursor] = kind
	e_entity[_log_cursor] = entity
	e_cause[_log_cursor] = cause
	e_amount[_log_cursor] = amount_uu
	e_qty[_log_cursor] = qty_uqs
	e_constraint[_log_cursor] = constraint_code
	e_q[_log_cursor] = q
	_log_cursor += 1


## 保证至少还有一行可写；写满则扩容并写一条告警行。
## 步骤：S08 §8.6
## 前置：无
## 后置：_log_cursor < _log_capacity
## 不变量：INV-139
## 失败：无
func _ensure_row_space() -> void:
	if _log_cursor < _log_capacity:
		return
	_log_grow()
	# 告警行：金额与数量恒为 0，entity 是 ENTITY_SELF（不指向任何经济实体），
	# 所以它进不了任何「支出构成」的加总——「支出构成可准确加总」这条红线不会被元信息污染。
	# 扩容后至少多出 2 行（见 _next_capacity），这里直接写不必再递归检查。
	e_kind[_log_cursor] = JWUnits.ExplainKind.ACCOUNTED
	e_entity[_log_cursor] = ENTITY_SELF
	e_cause[_log_cursor] = CAUSE_LOG_CAPACITY_GROWN
	e_amount[_log_cursor] = 0
	e_qty[_log_cursor] = 0
	e_constraint[_log_cursor] = 0
	e_q[_log_cursor] = _log_grow_count
	_log_cursor += 1


## 七张列数组按 1.5 倍同步扩容（docs/10 §12）。
## 步骤：日志写满时
## 前置：无
## 后置：七张数组等长且至少比原长多 2
## 不变量：INV-139
## 失败：无
func _log_grow() -> void:
	var cap: int = _log_capacity
	var next_cap: int = JWUnits.LOG_CAP0
	if cap > 0:
		# rounding: ceil, reason=1.5 倍扩容宁可多要一行也不能因取整停在原容量上
		next_cap = JWMath.ceil_div(JWMath.mul(cap, LOG_GROWTH_NUM), LOG_GROWTH_DEN)
	# 至少 +2：扩容之后要先写一行告警行，再写调用方那一行。
	if next_cap < cap + 2:
		next_cap = cap + 2
	e_entity.resize(next_cap)
	e_cause.resize(next_cap)
	e_amount.resize(next_cap)
	e_qty.resize(next_cap)
	e_q.resize(next_cap)
	e_constraint.resize(next_cap)
	e_kind.resize(next_cap)
	_log_capacity = next_cap
	_log_grow_count += 1


## 按编号读当前派生量标量。
## 步骤：S08 末
## 前置：id ∈ [0, DERIVED_ID_N)
## 后置：不改状态
## 不变量：INV-014
## 失败：越界 → 返回 0（调用方的循环由 DERIVED_ID_N 界定，走不到这里）
func _current_derived(id: int) -> int:
	if id == DERIVED_ID_GDP_PRODUCTION:
		return gdp_production
	if id == DERIVED_ID_GDP_EXPENDITURE:
		return gdp_expenditure
	if id == DERIVED_ID_GDP_INCOME:
		return gdp_income
	if id == DERIVED_ID_PRICE_VARIANCE_TOTAL:
		return price_variance_total
	if id == DERIVED_ID_GDP_REAL:
		return gdp_real
	if id == DERIVED_ID_GDP_ANNUAL_NOMINAL:
		return gdp_annual_nominal
	if id == DERIVED_ID_DEBT_TO_GDP_PPM:
		return debt_to_gdp_ppm
	if id == DERIVED_ID_DEBT_SERVICE_RATIO_PPM:
		return debt_service_ratio_ppm
	if id == DERIVED_ID_NEXT4Q_DEBT_SERVICE:
		return next4q_debt_service
	var k: int = id - DERIVED_ID_INCOME_QUANTILE_BASE
	if k >= 0 and k < JWUnits.QUANTILE_N:
		return income_quantile[k]
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, id, DERIVED_ID_N)
	return 0


## 按编号写回派生量标量（只用于比对失败后的还原）。
## 步骤：S08 末
## 前置：id ∈ [0, DERIVED_ID_N)
## 后置：该派生量恢复成本季结算路径写下的值
## 不变量：INV-014
## 失败：越界 → 登记 INDEX_OUT_OF_RANGE
func _set_derived(id: int, v: int) -> void:
	if id == DERIVED_ID_GDP_PRODUCTION:
		gdp_production = v
	elif id == DERIVED_ID_GDP_EXPENDITURE:
		gdp_expenditure = v
	elif id == DERIVED_ID_GDP_INCOME:
		gdp_income = v
	elif id == DERIVED_ID_PRICE_VARIANCE_TOTAL:
		price_variance_total = v
	elif id == DERIVED_ID_GDP_REAL:
		gdp_real = v
	elif id == DERIVED_ID_GDP_ANNUAL_NOMINAL:
		gdp_annual_nominal = v
	elif id == DERIVED_ID_DEBT_TO_GDP_PPM:
		debt_to_gdp_ppm = v
	elif id == DERIVED_ID_DEBT_SERVICE_RATIO_PPM:
		debt_service_ratio_ppm = v
	elif id == DERIVED_ID_NEXT4Q_DEBT_SERVICE:
		next4q_debt_service = v
	else:
		var k: int = id - DERIVED_ID_INCOME_QUANTILE_BASE
		if k >= 0 and k < JWUnits.QUANTILE_N:
			income_quantile[k] = v
		else:
			JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, id, DERIVED_ID_N)


## 扣下「本季已写值」。
## 步骤：S08 末
## 前置：_verify_saved 已 allocate
## 后置：_verify_saved 持有重算前的全部可比派生量
## 不变量：INV-014
## 失败：无
func _save_derived() -> void:
	var id: int = 0
	while id < DERIVED_ID_N:
		_verify_saved[id] = _current_derived(id)
		id += 1


## 还原成「本季已写值」。
## 步骤：S08 末（比对失败或重算中途出错）
## 前置：_save_derived() 已跑过
## 后置：派生量回到结算路径写下的值，故障包看到的是结算的真实产物
## 不变量：INV-014
## 失败：无
func _restore_derived() -> void:
	var id: int = 0
	while id < DERIVED_ID_N:
		_set_derived(id, _verify_saved[id])
		id += 1


## 找出第一个与「本季已写值」不一致的派生量编号。
## 步骤：S08 末
## 前置：_save_derived() 已跑过且已重算
## 后置：不改状态
## 不变量：INV-014
## 失败：无（全部一致返回 −1）
func _first_mismatch() -> int:
	var id: int = 0
	while id < DERIVED_ID_N:
		if _current_derived(id) != _verify_saved[id]:
			return id
		id += 1
	return -1


## 重算「本季没有第二个写者」的那部分派生量（重算即定值，无可比对象）。
## 步骤：S08 末
## 前置：本季 S03..S07 已完成
## 后置：region/group/cell 的派生数组与两个全国指数、失业率写入；不改任何 state.* / flow.*
## 不变量：INV-051、INV-075、INV-083、INV-141、INV-149
## 失败：维度不符 → Fault.INDEX_OUT_OF_RANGE
func _recompute_pure_derived(sectors: JWSectorModel, capital: JWCapital,
		pop: JWPopulation) -> int:
	if sectors == null or capital == null or pop == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, 0)
	if region_population.size() != JWUnits.R or labor_force.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				region_population.size(), JWUnits.R)
	if pop.population.size() != JWUnits.GROUP or pop.housing_occupied.size() != JWUnits.GROUP \
			or pop.consumption_index.size() != JWUnits.GROUP \
			or pop.service_access.size() != JWUnits.GROUP_SVC_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				pop.population.size(), JWUnits.GROUP)
	if sectors.f_elec_supply.size() != JWUnits.R or sectors.f_elec_demand.size() != JWUnits.R:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				sectors.f_elec_supply.size(), JWUnits.R)

	# (1) 地区人口（INV-141）与已占用住房（INV-083）。
	var r: int = 0
	while r < JWUnits.R:
		region_population[r] = pop.region_population(r)
		housing_occupied[r] = 0
		r += 1
	var g: int = 0
	while g < JWUnits.GROUP:
		housing_occupied[JWIds.REGION_OF_GROUP[g]] += pop.housing_occupied[g]
		g += 1

	# (2) 劳动力与失业率（INV-075）。
	#     labor_force 与 unemployed 的权威计算在 S03；这里是同一条定义式的季末重算。
	#     employed > labor_force 属于 S03 的 EMPLOYMENT_OVERFLOW 范畴，本类不越权改判，
	#     只把失业人数截在 0 —— 派生展示量不得为负（docs/10 §9.3 区间 ≥ 0）。
	var unemployed_total: int = 0
	var labor_total: int = 0
	g = 0
	while g < JWUnits.GROUP:
		var lf: int = pop.labor_force(g)
		labor_force[g] = lf
		var jobless: int = lf - pop.employed_total(g)
		if jobless < 0:
			jobless = 0
		unemployed_total += jobless
		labor_total += lf
		g += 1
	var labor_denom: int = labor_total
	if labor_denom < 1:
		labor_denom = 1
	unemployment_ppm = JWMath.mul_div_floor(unemployed_total, JWUnits.PPM, labor_denom)

	# (3) 电力可用率（INV-051）：当期需求被满足的比例 = 当期供给 ÷ 当期需求。
	#     需求为 0 时定义为 1 000 000（没有需求 ⇒ 需求全被满足），不是 0；
	#     写成 0 会让「本地区不用电」在报告里显示成「完全停电」。
	r = 0
	while r < JWUnits.R:
		var demand: int = sectors.f_elec_demand[r]
		if demand < 1:
			electricity_availability[r] = JWUnits.PPM
		else:
			electricity_availability[r] = JWMath.clamp_i(
					JWMath.mul_div_floor(sectors.f_elec_supply[r], JWUnits.PPM, demand),
					0, JWUnits.PPM)
		r += 1

	# (4) 全国消费指数与公共服务指数（docs/12 §7.8，INV-149）。
	#     按人口加权的算术平均：分子是 Σ(指数 × 人口)，分母是总人口，只 floor 一次。
	#     这是一个标量，不存在需要「凑和恰好等于总额」的分项，故不走最大余数法。
	#     **报告口径**：这是相对基年的自身基准，不冒充国际排名（计划书 §05）。
	var cons_num: int = 0
	var svc_num: int = 0
	var pop_total: int = 0
	g = 0
	while g < JWUnits.GROUP:
		var persons: int = pop.population[g]
		if persons < 0:
			persons = 0
		pop_total += persons
		cons_num += JWMath.mul(pop.consumption_index[g], persons)
		var svc_sum: int = 0
		var kind: int = 0
		while kind < JWUnits.SERVICE_KIND:
			svc_sum += pop.service_access[JWIds.idx_group_svc(g, kind)]
			kind += 1
		# rounding: floor, reason=三类服务的组内均值，少给优于凭空多给（M1）
		svc_num += JWMath.mul(JWMath.floor_div(svc_sum, JWUnits.SERVICE_KIND), persons)
		g += 1
	var pop_denom: int = pop_total
	if pop_denom < 1:
		pop_denom = 1
	living_consumption_index = JWMath.floor_div(cons_num, pop_denom)
	living_service_index = JWMath.floor_div(svc_num, pop_denom)

	# (5) derived.region.construction_slots_used 与 derived.cell.capacity_value_drift_ppm
	#     在本方法的形参表里**没有数据来源**：
	#       · 已占槽位要数 state.project.queue_slot_held，需要 JWProjectQueue；
	#       · 产能–资本漂移要 JWCapital.capacity_value_drift_ppm(cell, io)，需要 JWIoTable。
	#     docs/17 §4.26 钉死了本方法的签名（三个计算方法形参的并集），两者都不在其中。
	#     契约没给的数不猜：这两张表保持 allocate() 的 0，并已登记为接口请求。
	#     **不写一个看起来合理的假值**——那才是「解释器冒充因果识别」。
	return JWResult.OK


## 全部派生量的折叠值（INV-014 的诊断缓存）。
## 步骤：S08 末
## 前置：比对已通过
## 后置：不改状态
## 不变量：INV-014
## 失败：无
##
## 纯位运算（XOR）折叠：XOR 对 int64 是全函数，不会触发算术溢出，也就不会为了算一个诊断值
## 去登记一条 INT_OVERFLOW。逐槽盐值保证「两个数值相同的字段互相抵消」不会发生。
## 它只是缓存，权威检查是 _first_mismatch() 的逐项比对。
func _derived_fold() -> int:
	var h: int = 0
	var id: int = 0
	while id < DERIVED_ID_N:
		h = _mix(h, _current_derived(id), id)
		id += 1
	h = _mix(h, unemployment_ppm, DERIVED_ID_N)
	h = _mix(h, living_consumption_index, DERIVED_ID_N + 1)
	h = _mix(h, living_service_index, DERIVED_ID_N + 2)
	var i: int = 0
	while i < JWUnits.R:
		h = _mix(h, region_population[i], i)
		h = _mix(h, housing_occupied[i], i + 1)
		h = _mix(h, electricity_availability[i], i + 2)
		h = _mix(h, slots_used[i], i + 3)
		i += 1
	i = 0
	while i < JWUnits.GROUP:
		h = _mix(h, labor_force[i], i)
		i += 1
	i = 0
	while i < JWUnits.CELL:
		h = _mix(h, capacity_value_drift[i], i)
		i += 1
	return h


## 折叠一步：XOR 混入一个带槽位盐的值。
## 步骤：S08 末
## 前置：无
## 后置：返回新的折叠值
## 不变量：INV-014
## 失败：无
static func _mix(h: int, v: int, slot: int) -> int:
	return h ^ v ^ HASH_SALT[slot & 15]
