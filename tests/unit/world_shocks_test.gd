## 外部世界与冲击的契约测试（JWWorldMarket / JWShocks）。
##
## 依据：docs/18 裁定（R-SCALE-01、R-CREDIT-01）、docs/12 §1.1（01.6/01.7）与 §5.6 / §6.8、
## docs/10 §8.4 与 §14（INV-009/011/026/034/059/104…110）、docs/17 §4.22/§4.23 的接口契约、
## docs/30（`test_s_import_cap`、`T-S-P08-FAIL-NOORDER`、`T-S-D-11`）、docs/31（`ADV-06`/`ADV-H01`）。
##
## 本文件**不读被测模块的实现**，夹具一律按契约里登记的成员名与基年剧本
## （content/scenarios/chengwan/world.json 的 world_init_mirror）构造，期望值全部手算并在断言消息里写明来源。
extends JWTest

# ── 基年剧本常量（world.json #world_init_mirror / #external_credit，作为期望值的来源） ──

## content.world.base_credit_limit_uu（world.json external_credit.base_credit_limit_uu）
const BASE_CREDIT_LIMIT_UU: int = 12_000_000_000
## 剧本基准出口量 μQ_s/季（world.json export_demand.export_baseline_uqs_per_q）
const BASE_EXPORT_UQS: PackedInt64Array = [100_000, 350_000, 50_000, 0]
## 剧本外部交付能力 μQ_s/季（world.json world_init_mirror.delivery_capacity_uqs）
const DELIVERY_CAPACITY_UQS: PackedInt64Array = [400_000, 2_400_000, 600_000, 0]
## 剧本主权利率 ppm/季
const SOVEREIGN_RATE_INIT_PPM: int = 10_000

# ── 冲击下标与档位（docs/12 §01.6「for k in [S01, S02, S03]」，即稠密下标 0/1/2） ──

const K_S01_EXPORT: int = 0
const K_S02_IMPORT: int = 1
const K_S03_CREDIT: int = 2

## docs/11 §5.14：onset_profile ∈ {step, ramp_2q}，按登记顺序取稠密码 0/1
const ONSET_STEP: int = 0
const ONSET_RAMP_2Q: int = 1
## docs/11 §5.14：decay_profile ∈ {none, linear}，按登记顺序取稠密码 0/1
const DECAY_NONE: int = 0
const DECAY_LINEAR: int = 1

## content/shocks/shock_S0*.json 的 target_weights_ppm（S01 / S02 / S03 依次 4 个部门）
const TARGET_WEIGHTS_PPM: PackedInt64Array = [
	200_000, 700_000, 100_000, 0,
	0, 1_000_000, 0, 0,
	250_000, 250_000, 250_000, 250_000,
]

## 测试用参数：param.market_rate_base_ppm 与 param.rate_sensitivity_ppm
const MARKET_RATE_BASE_PPM: int = 10_000
const RATE_SENSITIVITY_PPM: int = 40_000

## shock_log 的列数与列序（docs/12 §01.6 的 append 元组：q, k, m, d, draw_index, raw_u64, mapped_value）
const SL_COLS: int = 7
const SL_Q: int = 0
const SL_KIND: int = 1
const SL_MAG: int = 2
const SL_DUR: int = 3
const SL_DRAW_INDEX: int = 4
const SL_RAW: int = 5
const SL_MAPPED: int = 6

## 让「到达抽样」必然命中：draw_ppm ∈ [0, 1e6)，恒 < 1e6（docs/12 §01.6「>= hazard 则 continue」）
const HAZARD_ALWAYS_PPM: int = 1_000_000
## 让「到达抽样」必然落空，但仍消耗一次抽样
const HAZARD_NEVER_PPM: int = 0
## 把某类冲击彻底挡在抽样之前（q < earliest_q，docs/12 §01.6 (c) 的第一道门）
const EARLIEST_NEVER_Q: int = 9_999

var _params: PackedInt64Array = PackedInt64Array()


func before_each() -> void:
	# 故障登记是静态的，不清会把上一条测试的故障带进本条，让断言指向错误的现场。
	JWResult.clear_pending()
	JWResult.set_step(JWUnits.Phase.S01)
	_params = PackedInt64Array()
	_params.resize(JWUnits.PARAM_N)
	_params.fill(0)
	_params[JWUnits.Param.MARKET_RATE_BASE_PPM] = MARKET_RATE_BASE_PPM
	_params[JWUnits.Param.RATE_SENSITIVITY_PPM] = RATE_SENSITIVITY_PPM


func after_each() -> void:
	JWResult.clear_pending()


# ── 夹具 ───────────────────────────────────────────────────────────────────

## 按基年剧本构造一个外部市场（docs/17 §4.22 成员表 + world.json world_init_mirror）。
func _new_world() -> JWWorldMarket:
	var w: JWWorldMarket = JWWorldMarket.new()
	w.allocate()
	w.base_export_uqs = BASE_EXPORT_UQS.duplicate()
	w.base_export_ppm = PackedInt64Array([1_000_000, 1_000_000, 1_000_000, 1_000_000])
	w.base_import_ppm = PackedInt64Array([1_000_000, 1_000_000, 1_000_000, 1_000_000])
	w.base_credit_limit = BASE_CREDIT_LIMIT_UU
	w.export_demand_ppm = PackedInt64Array([1_000_000, 1_000_000, 1_000_000, 1_000_000])
	w.import_price_ppm = PackedInt64Array([1_000_000, 1_000_000, 1_000_000, 1_000_000])
	w.delivery_capacity = DELIVERY_CAPACITY_UQS.duplicate()
	w.credit_limit = BASE_CREDIT_LIMIT_UU
	w.credit_used = 0
	w.sovereign_rate_ppm = SOVEREIGN_RATE_INIT_PPM
	w.current_account = 0
	return w


## 按 content/shocks/shock_S0*.json 构造三类冲击的内容层；到达率默认全 0（不抽中）。
func _new_shocks() -> JWShocks:
	var s: JWShocks = JWShocks.new()
	s.allocate()
	s.channel = PackedInt64Array([0, 1, 2])
	s.target_weights_ppm = TARGET_WEIGHTS_PPM.duplicate()
	s.hazard_ppm = PackedInt64Array([HAZARD_NEVER_PPM, HAZARD_NEVER_PPM, HAZARD_NEVER_PPM])
	s.earliest_q = PackedInt64Array([4, 4, 6])
	s.min_gap_q = PackedInt64Array([4, 4, 6])
	s.max_active = PackedInt64Array([1, 1, 1])
	s.mag_min = PackedInt64Array([-600_000, -200_000, -20_000])
	s.mag_max = PackedInt64Array([199_999, 599_999, 299_999])
	s.dur_min = PackedInt64Array([2, 3, 4])
	s.dur_max = PackedInt64Array([9, 10, 11])
	s.onset_profile = PackedInt64Array([ONSET_STEP, ONSET_STEP, ONSET_STEP])
	s.decay_profile = PackedInt64Array([DECAY_NONE, DECAY_NONE, DECAY_NONE])
	s.active = PackedInt64Array([0, 0, 0])
	s.remaining_q = PackedInt64Array([0, 0, 0])
	s.magnitude_ppm = PackedInt64Array([0, 0, 0])
	s.duration_q = PackedInt64Array([0, 0, 0])
	s.last_end_q = PackedInt64Array([-999, -999, -999])
	return s


## 把第 k 类冲击置为「已生效、强度 m、总期 d、剩余 r」，供 apply_to_world 单测使用。
func _arm(s: JWShocks, k: int, m: int, d: int, r: int, onset: int, decay: int) -> void:
	s.active[k] = 1
	s.magnitude_ppm[k] = m
	s.duration_q[k] = d
	s.remaining_q[k] = r
	s.onset_profile[k] = onset
	s.decay_profile[k] = decay


## 只让第 k 类冲击可能到达，其余两类被 earliest_q 挡在抽样之前（保证抽样次数可精确预期）。
func _only_channel_can_arrive(s: JWShocks, k: int) -> void:
	for j: int in JWUnits.SHOCK_N:
		if j == k:
			s.hazard_ppm[j] = HAZARD_ALWAYS_PPM
			s.earliest_q[j] = 0
			s.min_gap_q[j] = 0
		else:
			s.hazard_ppm[j] = HAZARD_NEVER_PPM
			s.earliest_q[j] = EARLIEST_NEVER_Q


## 把第 k 类冲击的强度／持续期定死成单点区间：draw_range(lo, lo) 恒返回 lo，各消耗一次抽样。
func _pin_magnitude_and_duration(s: JWShocks, k: int, m: int, d: int) -> void:
	s.mag_min[k] = m
	s.mag_max[k] = m
	s.dur_min[k] = d
	s.dur_max[k] = d


func _new_rng(seed_value: int) -> JWRngStreams:
	var r: JWRngStreams = JWRngStreams.new()
	r.allocate()
	r.root_seed = seed_value
	# 六条流的盐必须互不相同，否则它们会退化成同一条流（rng_streams.gd draw_raw 的说明）。
	r.salt = PackedInt64Array([101, 202, 303, 404, 505, 606])
	return r


func _new_accounts() -> JWAccount:
	var a: JWAccount = JWAccount.new()
	a.allocate()
	return a


# ── INV-105 汇率不可写 ─────────────────────────────────────────────────────

## 检验 INV-105（`fx_rate_ppm` 恒为 1 000 000，任何写入即 FAULT）与 docs/17 §4.22
## 「`set_fx_rate` 根本不存在」的结构性要求。
func test_fx_rate_is_constant_and_has_no_setter() -> void:
	eq_int(JWWorldMarket.FX_RATE_PPM, 1_000_000,
			"INV-105：固定汇率口径，FX_RATE_PPM 的唯一合法值来自 JWUnits.FX_RATE_PPM = 1 000 000")
	eq_int(JWWorldMarket.FX_RATE_PPM, JWUnits.FX_RATE_PPM,
			"INV-105：JWWorldMarket 不得另立一套汇率常量，必须等于 JWUnits.FX_RATE_PPM")
	var w: JWWorldMarket = _new_world()
	check_false(w.has_method("set_fx_rate"),
			"INV-105 / docs/17 §4.22：汇率没有写入路径，set_fx_rate 必须根本不存在，"
			+ "而不是存在但内部拒绝——存在即给了调用方一个可被误用的入口")


# ── INV-108 冲击落点：五个 setter 的区间 ──────────────────────────────────

## 检验 docs/17 §4.22 五个 setter 的后置条件（INV-108 白名单字段的取值域），
## 区间取自 docs/12 §01.7 与 world.json shock_binding.channels 的 clamp_range_ppm。
func test_world_setters_clamp_to_contract_ranges() -> void:
	var w: JWWorldMarket = _new_world()

	w.set_export_demand(1, 4_000_000)
	eq_int(w.export_demand(1), 3_000_000,
			"docs/12 §01.7：export_demand_ppm 上界 3 000 000（world.json clamp_range_ppm），超界应 clamp 不应直写")
	w.set_export_demand(1, -1)
	eq_int(w.export_demand(1), 0, "docs/12 §01.7：export_demand_ppm 下界 0")

	w.set_import_price(2, 9_000_000)
	eq_int(w.import_price(2), 5_000_000, "docs/12 §01.7：import_price_ppm 上界 5 000 000")
	w.set_import_price(2, 1)
	eq_int(w.import_price(2), 100_000,
			"docs/12 §01.7：import_price_ppm 下界 100 000（价格指数不得塌到 0，否则进口白送）")

	w.set_sovereign_rate(500_000)
	eq_int(w.sovereign_rate(), 100_000, "docs/12 §01.7：sovereign_rate_ppm_per_q 上界 100 000")
	w.set_sovereign_rate(-7)
	eq_int(w.sovereign_rate(), 0, "docs/12 §01.7：sovereign_rate_ppm_per_q 下界 0")

	w.set_credit_limit(-1)
	ge_int(w.credit_limit, 0, "docs/17 §4.22 后置：credit_limit >= 0（负额度不是业务量，是缺陷）")

	w.set_delivery_capacity(0, -5)
	ge_int(w.delivery_capacity[0], 0,
			"docs/10 §8.4：delivery_capacity_uqs 的值域是 ≥ 0，负交付能力会让 INV-104 的上界变成负数")


# ── INV-104 进口物量闸 ────────────────────────────────────────────────────

## 检验 INV-104 / docs/30 `test_s_import_cap` 的物量闸：
## `imports_uqs[s] <= world.delivery_capacity_uqs[s]`，超出部分是「本季没到货」而非欠货。
func test_import_is_capped_by_delivery_capacity() -> void:
	var w: JWWorldMarket = _new_world()
	w.begin_quarter_delivery()
	var s: int = JWUnits.Sector.MANU
	var cap: int = w.delivery_capacity[s]          # 2 400 000 μQ_s
	eq_int(w.delivery_remaining(s), cap,
			"docs/17 §4.22 begin_quarter_delivery 后置：_delivery_remaining == delivery_capacity")

	# 要 3 600 000，是交付能力的 1.5 倍；单价取基年价 1e9 μU/Q_s，value = qty*price/1e6。
	var want_qty: int = 3_600_000
	var want_value: int = JWMath.mul_div_floor(want_qty, JWUnits.BASE_PRICE, JWUnits.Q_SCALE)
	w.record_import(s, want_qty, want_value)

	eq_int(w.f_imports_uqs[s], cap,
			"INV-104 / test_s_import_cap：请求 3 600 000 μQ_s 而交付能力 2 400 000 μQ_s，"
			+ "只能按剩余额度成交，成交量必须恰好等于交付能力")
	eq_int(w.delivery_remaining(s), 0,
			"INV-104：额度用尽后剩余交付额度必须为 0，不得为负（负剩余等于把短缺记成了透支）")
	le_int(w.f_imports_uqs[s], w.delivery_capacity[s],
			"INV-104：flow.world.imports_uqs[s] <= state.world.delivery_capacity_uqs[s]")
	le_int(w.f_imports_uu, want_value,
			"INV-104：按剩余额度成交时付款额不得超过整单报价 %d μU，否则就是付了没到的货" % want_value)
	eq_int(JWResult.pending_code(), 0,
			"docs/17 §4.22：超交付能力是业务性短缺，不是故障，不得登记 Fault")

	# 同一季再来一笔：额度已尽，必须一颗也进不来（交付能力是每季独立上限）。
	w.record_import(s, 1_000_000, JWMath.mul_div_floor(1_000_000, JWUnits.BASE_PRICE, JWUnits.Q_SCALE))
	eq_int(w.f_imports_uqs[s], cap,
			"INV-104：本季额度已尽，追加的进口请求必须 0 成交，累计进口量仍为交付能力上限")


## 检验 world.json dual_constraint_rule.forbidden_zh 第 4 条：
## 「禁止因为本季进口没用满交付能力而把剩余额度结转到下季」（INV-104 的每季独立性）。
func test_delivery_capacity_does_not_carry_over_between_quarters() -> void:
	var w: JWWorldMarket = _new_world()
	var s: int = JWUnits.Sector.MANU
	var cap: int = w.delivery_capacity[s]

	w.begin_quarter_delivery()
	var used: int = 400_000
	w.record_import(s, used, JWMath.mul_div_floor(used, JWUnits.BASE_PRICE, JWUnits.Q_SCALE))
	eq_int(w.delivery_remaining(s), cap - used,
			"docs/17 §4.22：一笔进口后剩余额度 == 交付能力 − 已用量")

	w.begin_quarter_delivery()
	eq_int(w.delivery_remaining(s), cap,
			"world.json dual_constraint_rule.forbidden_zh#4：交付能力是每季独立上限，"
			+ "上季未用满的 %d μQ_s 不得结转，新季剩余必须恰好重置为 %d μQ_s" % [cap - used, cap])


# ── INV-034 进口融资闸 + 双重约束的独立性 ────────────────────────────────

## 检验 INV-034（外部融资 ≤ `credit_limit_uu − credit_used_uu`）与 docs/30 `T-S-D-11`：
## 超额必须返回 `Reject.CREDIT_LIMIT` 且**一个字段都不改**。
func test_external_credit_headroom_is_exact_and_overdraw_is_rejected() -> void:
	var w: JWWorldMarket = _new_world()
	eq_int(w.credit_headroom(), BASE_CREDIT_LIMIT_UU,
			"INV-034 / docs/10 §8.4：external_capacity == credit_limit_uu − credit_used_uu，"
			+ "开局 credit_used == 0，故等于剧本额度 %d μU" % BASE_CREDIT_LIMIT_UU)

	var first: int = 5_000_000_000
	eq_int(w.use_external_credit(first), JWResult.OK,
			"INV-034：额度充裕时借款必须被接受")
	eq_int(w.credit_used, first, "INV-034：credit_used 必须精确累加已借金额")
	eq_int(w.credit_headroom(), BASE_CREDIT_LIMIT_UU - first,
			"INV-034：剩余额度 == 12 000 000 000 − 5 000 000 000")

	# 正好借满剩余额度：边界内，必须成功。
	var rest: int = BASE_CREDIT_LIMIT_UU - first
	eq_int(w.use_external_credit(rest), JWResult.OK,
			"INV-034：借满剩余额度是边界内的合法操作（<= headroom），不得拒绝")
	eq_int(w.credit_headroom(), 0, "INV-034：借满后剩余额度为 0")

	# 再多 1 μU：必须拒绝且状态逐字段不变（T-S-D-11 的「state_hash 逐位不变」在本类的落点）。
	var used_before: int = w.credit_used
	var limit_before: int = w.credit_limit
	var code: int = w.use_external_credit(1)
	rejects(code, JWResult.OK, "INV-034 / T-S-D-11：超出额度 1 μU 的借款必须被拒绝")
	eq_int(code, JWResult.Reject.CREDIT_LIMIT,
			"docs/17 §4.22：超额的拒绝码必须是 Reject.CREDIT_LIMIT(1009)，不得用别的码含混带过")
	eq_int(w.credit_used, used_before,
			"INV-034：被拒的借款不得改状态，credit_used 必须停在 %d μU" % used_before)
	eq_int(w.credit_limit, limit_before, "INV-034：被拒的借款不得顺手改额度")


## 检验 world.json dual_constraint_rule.independence_zh：物量闸与融资闸必须各自可单独失败；
## 任何把两者合成一个标量「外部可购买力」的实现都会让两条失败路径退化成一条（INV-104 + INV-034）。
func test_quantity_gate_and_finance_gate_fail_independently() -> void:
	var s: int = JWUnits.Sector.MANU

	# 情形一：交付能力为 0，额度充裕 —— 必须停在物量闸，融资闸照常放行。
	var w1: JWWorldMarket = _new_world()
	w1.set_delivery_capacity(s, 0)
	w1.begin_quarter_delivery()
	w1.record_import(s, 1_000_000, JWMath.mul_div_floor(1_000_000, JWUnits.BASE_PRICE, JWUnits.Q_SCALE))
	eq_int(w1.f_imports_uqs[s], 0,
			"INV-104：交付能力为 0 时本季根本没到货，成交量必须为 0（T-S-P04-FAIL-DELIVERY 的物量侧）")
	eq_int(w1.f_imports_uu, 0, "INV-104：没到货就不该有付款额")
	eq_int(w1.use_external_credit(1_000_000_000), JWResult.OK,
			"独立性：交付能力为 0 不得连带关掉融资闸，额度充裕时借款仍应成功")

	# 情形二：额度为 0，交付能力充裕 —— 必须停在融资闸，物量闸照常放行。
	var w2: JWWorldMarket = _new_world()
	w2.set_credit_limit(0)
	w2.begin_quarter_delivery()
	rejects(w2.use_external_credit(1), JWResult.OK,
			"INV-034：额度为 0 时任何新增外部借款都必须被拒（T-S-P04-FAIL-FINANCING 的融资侧）")
	eq_int(w2.credit_used, 0, "INV-034：被拒的借款不得记入 credit_used")
	ge_int(w2.delivery_remaining(s), 1_000_000,
			"独立性：额度为 0 不得连带把交付能力清零，物量闸的剩余额度应仍为剧本值 2 400 000 μQ_s")


# ── R-CREDIT-01 增量额度 ─────────────────────────────────────────────────

## 检验裁定 R-CREDIT-01（docs/18）与 INV-034 的增量额度表述：
## **存量外债不占用 `credit_used_uu`**，额度只约束本局新增的外部借款。
func test_stock_external_debt_does_not_consume_incremental_headroom() -> void:
	var w: JWWorldMarket = _new_world()
	var accounts: JWAccount = _new_accounts()

	eq_int(w.credit_used, 0,
			"R-CREDIT-01 / docs/10 §8.4：credit_used_uu 初值为 0，开局存量外债一律不计入")
	eq_int(w.credit_headroom(), BASE_CREDIT_LIMIT_UU,
			"R-CREDIT-01：开局可用额度是全额 %d μU，不因存量外债而打折" % BASE_CREDIT_LIMIT_UU)

	# 把一笔远大于额度的存量外债经形参传进来（docs/17 §4.22：同秩不得互引，外债降级成整数形参）。
	var stock_debt: int = 25_000_000_000
	w.settle_current_account(0, 0, stock_debt, accounts)

	eq_int(w.credit_used, 0,
			("R-CREDIT-01：存量外债 %d μU 经 settle_current_account 传入后，credit_used_uu 必须仍为 0"
			+ "——存量的约束已由还本付息现金流表达，再占一次额度是重复计算") % stock_debt)
	eq_int(w.credit_headroom(), BASE_CREDIT_LIMIT_UU,
			"R-CREDIT-01：可用额度必须仍是全额 %d μU，不得被存量外债扣减" % BASE_CREDIT_LIMIT_UU)
	eq_int(w.use_external_credit(BASE_CREDIT_LIMIT_UU), JWResult.OK,
			"R-CREDIT-01：存量外债 25 U 的情况下，仍应能借满 12 U 的增量额度")


## 检验 INV-034 的「**还本也不释放额度**」（R-CREDIT-01 / world.json external_credit.usage_rules_zh#6）。
func test_repayment_does_not_release_external_credit() -> void:
	var w: JWWorldMarket = _new_world()
	var accounts: JWAccount = _new_accounts()

	var borrowed: int = 5_000_000_000
	w.use_external_credit(borrowed)
	eq_int(w.credit_used, borrowed, "前置：已借 5 000 000 000 μU")

	# 净借款为负 == 本季净还本。按 R-CREDIT-01，额度不因此回流。
	w.settle_current_account(0, -borrowed, 0, accounts)
	eq_int(w.credit_used, borrowed,
			("INV-034 / R-CREDIT-01：净还本 %d μU 之后 credit_used_uu 必须不变；"
			+ "还本释放额度会让「增量额度」退化成「余额额度」，一局之内可无限循环借还") % borrowed)
	eq_int(w.credit_headroom(), BASE_CREDIT_LIMIT_UU - borrowed,
			"INV-034：还本后可用额度仍是 7 000 000 000 μU")
	check_false(w.has_method("release_external_credit"),
			"R-CREDIT-01：不存在任何释放额度的入口——有入口就一定会有人调用它")


## 检验 world.json external_credit.usage_rules_zh#5：
## S03 收紧额度时，**不得强制回收已借款**，只让可用额度取 0（INV-034 的下界）。
func test_credit_tightening_neither_recalls_nor_lends_more() -> void:
	var w: JWWorldMarket = _new_world()
	var s: JWShocks = _new_shocks()

	w.use_external_credit(BASE_CREDIT_LIMIT_UU)
	eq_int(w.credit_used, BASE_CREDIT_LIMIT_UU, "前置：额度已借满 12 000 000 000 μU")

	# eff = mul_ppm(500 000, 1e6) = 500 000 ⇒ credit_limit = mul_ppm(12e9, 1e6−5e5) = 6 000 000 000
	_arm(s, K_S03_CREDIT, 500_000, 4, 4, ONSET_STEP, DECAY_NONE)
	s.apply_to_world(w, 6, _params)

	eq_int(w.credit_limit, 6_000_000_000,
			"docs/12 §01.7：credit_limit_uu = mul_ppm(base 12 000 000 000, clamp(1e6 − eff 500 000)) "
			+ "= 6 000 000 000 μU")
	eq_int(w.credit_used, BASE_CREDIT_LIMIT_UU,
			"world.json external_credit.usage_rules_zh#5：收紧额度不得强制回收已借款，"
			+ "credit_used 必须停在 12 000 000 000 μU")
	ge_int(w.credit_headroom(), 0,
			"INV-034：credit_used(12e9) > credit_limit(6e9) 时可用额度取 0，不得返回负数——"
			+ "负额度会顺着 world.json 的 utilization_ppm 公式传进票息定价")
	rejects(w.use_external_credit(1), JWResult.OK,
			"INV-034：额度已被收紧到已用量之下，再借 1 μU 必须被拒")


# ── INV-106 / INV-110 外部账户 ───────────────────────────────────────────

## 检验 INV-106（docs/12 §6.8）：
## `current_account(q) == current_account(q−1) + 出口 − 进口 − 对外利息 + 对外净借款`。
func test_current_account_accumulates_per_inv106() -> void:
	var w: JWWorldMarket = _new_world()
	var accounts: JWAccount = _new_accounts()

	w.f_exports_uu = 3_000_000_000
	w.f_imports_uu = 1_200_000_000
	var interest: int = 150_000_000
	var net_borrowing: int = 400_000_000

	w.settle_current_account(interest, net_borrowing, 0, accounts)
	# 0 + 3 000 000 000 − 1 200 000 000 − 150 000 000 + 400 000 000
	eq_int(w.current_account, 2_050_000_000,
			"INV-106 / docs/12 §6.8：current_account += 出口 3e9 − 进口 1.2e9 − 对外利息 1.5e8 "
			+ "+ 对外净借款 4e8 = 2 050 000 000 μU")

	# 第二季同样的流量：必须是累计量，不是本季量。
	w.settle_current_account(interest, net_borrowing, 0, accounts)
	eq_int(w.current_account, 4_100_000_000,
			"INV-106：current_account_uu 是累计经常账户（docs/10 §8.4 标注为累计），"
			+ "第二次结算后应为 4 100 000 000 μU，而不是被本季值覆盖成 2 050 000 000")


## 检验 INV-110 的定义式（docs/12 §6.8）：`derived.world.net_foreign_position_uu == -agent.row.nw`。
func test_net_foreign_position_is_negated_row_net_worth() -> void:
	var w: JWWorldMarket = _new_world()
	var accounts: JWAccount = _new_accounts()

	eq_int(w.net_foreign_position(accounts), 0,
			"INV-110：全表为 0 时净对外头寸为 0")

	var row_nw: int = 7_500_000_000
	var bal: PackedInt64Array = PackedInt64Array()
	bal.resize(JWUnits.ACCOUNT_N)
	bal.fill(0)
	bal[JWIds.idx_account(JWIds.AGENT_ROW, JWIds.ACC_NW)] = row_nw
	eq_int(accounts.set_state_array(0, bal), JWResult.OK,
			"夹具前置：account.balance 是 JWAccount 的 0 号状态数组，长度 900")

	eq_int(w.net_foreign_position(accounts), -row_nw,
			"INV-110 / docs/12 §6.8：net_foreign_position_uu == −agent.row.nw；"
			+ "row 的净值为 +7 500 000 000 μU 时，本国净对外头寸必须是 −7 500 000 000 μU")


# ── 出口不能自造订单 ──────────────────────────────────────────────────────

## 检验 docs/30 `T-S-P08-FAIL-NOORDER`（`export_demand_ppm == 0` ⇒ 港口／交付能力提升后
## 出口增量 `== 0`，不能自造订单）与 INV-108（出口需求只由 shock.S01 写）。
func test_export_demand_is_untouched_by_delivery_capacity() -> void:
	var w: JWWorldMarket = _new_world()
	for s: int in JWUnits.S:
		w.set_export_demand(s, 0)

	# 把交付能力（港口升级 P08 的落点代理）翻十倍。
	for s: int in JWUnits.S:
		w.set_delivery_capacity(s, 24_000_000)

	for s: int in JWUnits.S:
		eq_int(w.export_demand(s), 0,
				"T-S-P08-FAIL-NOORDER / INV-108：外部需求只由 state.world.export_demand_ppm 决定，"
				+ "提高交付能力不得给部门 %d 凭空造出需求" % s)
		eq_int(JWMath.mul_ppm(w.base_export_uqs[s], w.export_demand(s)), 0,
				("T-S-P08-FAIL-NOORDER：外部需求为 0 时，部门 %d 的可实现出口量恒为 0，与交付能力"
				+ " 24 000 000 μQ_s 无关（world.json export_demand.realizable_export_rule step_01/step_05）") % s)


## 检验 docs/17 §4.22 `record_export` 的前置
## （`qty <= min(mul_ppm(base_export_uqs, export_demand_ppm), delivery_capacity)`）
## 与 world.json export_demand.no_self_dealing_rules_zh：没有订单就没有出口。
func test_export_cannot_be_recorded_without_external_demand() -> void:
	var w: JWWorldMarket = _new_world()
	var s: int = JWUnits.Sector.MANU
	w.set_export_demand(s, 0)
	w.set_delivery_capacity(s, 24_000_000)
	w.begin_quarter_delivery()

	var qty: int = 350_000
	w.record_export(s, qty, JWMath.mul_div_floor(qty, JWUnits.BASE_PRICE, JWUnits.Q_SCALE))

	eq_int(w.f_exports_uqs[s], 0,
			"docs/17 §4.22 record_export 前置 + world.json no_self_dealing_rules_zh："
			+ "export_demand_ppm == 0 时出口上限为 0，登记一笔 350 000 μQ_s 的出口必须 0 成交——"
			+ "否则外部世界成了不需要订单的无限买家")
	eq_int(w.f_exports_uu, 0, "INV-026：没有对手方订单就不该有对外收款")


# ── 三类冲击经外部账户传导（INV-108） ────────────────────────────────────

## 检验 docs/12 §01.7 的 S01 传导式与 INV-108（只写 world.* 白名单，且不串道）：
## `export_demand_ppm[s] = clamp(base + mul_ppm(eff, target_weights[S01][s]), 0, 3e6)`。
func test_shock_s01_transmits_to_export_demand_only() -> void:
	var w: JWWorldMarket = _new_world()
	var s: JWShocks = _new_shocks()
	# 强度 +500 000 ppm，step/none ⇒ decay = 1e6 ⇒ eff = 500 000
	_arm(s, K_S01_EXPORT, 500_000, 5, 5, ONSET_STEP, DECAY_NONE)
	s.apply_to_world(w, 4, _params)

	# base 1 000 000 + mul_ppm(500 000, 权重)
	eq_int(w.export_demand(0), 1_100_000,
			"docs/12 §01.7：agri 权重 200 000 ⇒ 1 000 000 + mul_ppm(500 000, 200 000) = 1 100 000 ppm")
	eq_int(w.export_demand(1), 1_350_000,
			"docs/12 §01.7：manu 权重 700 000 ⇒ 1 000 000 + 350 000 = 1 350 000 ppm")
	eq_int(w.export_demand(2), 1_050_000,
			"docs/12 §01.7：energy 权重 100 000 ⇒ 1 000 000 + 50 000 = 1 050 000 ppm")
	eq_int(w.export_demand(3), 1_000_000,
			"docs/12 §01.7：services 权重 0 ⇒ 保持基准 1 000 000 ppm")

	for i: int in JWUnits.S:
		eq_int(w.import_price(i), 1_000_000,
				"INV-108：S01 是出口需求通道，不得串到 import_price_ppm[%d]" % i)
	eq_int(w.credit_limit, BASE_CREDIT_LIMIT_UU,
			"INV-108：S01 不得改外部信用额度（S03 eff == 0 ⇒ 额度回到基准 12 000 000 000 μU）")
	eq_int(w.sovereign_rate(), MARKET_RATE_BASE_PPM,
			"docs/12 §01.7：S03 未生效时主权利率 == param.market_rate_base_ppm = 10 000 ppm")


## 检验 docs/12 §01.7 的负向 S01：`mul_ppm` 对负数向 −∞ 取整（JWMath 的 floor 语义），
## 结果不得靠「先取绝对值再取反」凑出来。
func test_shock_s01_negative_magnitude_floors_toward_negative_infinity() -> void:
	var w: JWWorldMarket = _new_world()
	var s: JWShocks = _new_shocks()
	# 剧本下界 −600 000 ppm（shock_S01.json magnitude_ppm.min）
	_arm(s, K_S01_EXPORT, -600_000, 5, 5, ONSET_STEP, DECAY_NONE)
	s.apply_to_world(w, 4, _params)

	eq_int(w.export_demand(0), 880_000,
			"docs/12 §01.7：mul_ppm(−600 000, 200 000) = floor(−120 000) = −120 000 ⇒ 880 000 ppm")
	eq_int(w.export_demand(1), 580_000,
			"docs/12 §01.7：mul_ppm(−600 000, 700 000) = −420 000 ⇒ 580 000 ppm")
	eq_int(w.export_demand(2), 940_000,
			"docs/12 §01.7：mul_ppm(−600 000, 100 000) = −60 000 ⇒ 940 000 ppm")
	ge_int(w.export_demand(0), 0, "docs/12 §01.7：export_demand_ppm 的下界 0 恒成立")


## 检验 docs/12 §01.7 的 S02 传导式与 INV-108：
## `import_price_ppm[s] = clamp(base + mul_ppm(eff, target_weights[S02][s]), 1e5, 5e6)`。
func test_shock_s02_transmits_to_import_price_only() -> void:
	var w: JWWorldMarket = _new_world()
	var s: JWShocks = _new_shocks()
	_arm(s, K_S02_IMPORT, 300_000, 6, 6, ONSET_STEP, DECAY_NONE)
	s.apply_to_world(w, 5, _params)

	eq_int(w.import_price(1), 1_300_000,
			"docs/12 §01.7：S02 权重集中在 manu（1 000 000 ppm）⇒ 1 000 000 + 300 000 = 1 300 000 ppm")
	eq_int(w.import_price(0), 1_000_000, "INV-108：S02 在 agri 上的权重为 0，价格指数保持基准")
	eq_int(w.import_price(2), 1_000_000, "INV-108：S02 在 energy 上的权重为 0，价格指数保持基准")
	eq_int(w.import_price(3), 1_000_000, "INV-108：S02 在 services 上的权重为 0，价格指数保持基准")

	for i: int in JWUnits.S:
		eq_int(w.export_demand(i), 1_000_000,
				"INV-108：S02 是进口价格通道，不得串到 export_demand_ppm[%d]" % i)
	eq_int(w.credit_limit, BASE_CREDIT_LIMIT_UU, "INV-108：S02 不得改外部信用额度")


## 检验 docs/12 §01.7 的 S03 传导式（额度与利率**共用同一次抽样**，world.json shock_binding.rules_zh#5）：
## `credit_limit = mul_ppm(base, clamp(1e6 − eff, 0, 1e6))`；
## `sovereign_rate = clamp(market_rate_base + mul_ppm(eff, rate_sensitivity), 0, 1e5)`。
func test_shock_s03_transmits_to_credit_limit_and_sovereign_rate() -> void:
	var w: JWWorldMarket = _new_world()
	var s: JWShocks = _new_shocks()
	_arm(s, K_S03_CREDIT, 250_000, 8, 8, ONSET_STEP, DECAY_NONE)
	s.apply_to_world(w, 7, _params)

	eq_int(w.credit_limit, 9_000_000_000,
			"docs/12 §01.7：mul_ppm(12 000 000 000, clamp(1e6 − 250 000)) = 9 000 000 000 μU")
	eq_int(w.sovereign_rate(), 20_000,
			"docs/12 §01.7：10 000 + mul_ppm(250 000, 40 000) = 10 000 + 10 000 = 20 000 ppm/季")

	for i: int in JWUnits.S:
		eq_int(w.export_demand(i), 1_000_000,
				"INV-108：S03 是外部信用通道，不得改 export_demand_ppm[%d]" % i)
		eq_int(w.import_price(i), 1_000_000,
				"INV-108：S03 是外部信用通道，不得改 import_price_ppm[%d]" % i)


## 检验 docs/12 §01.7 主权利率的上界 clamp（区间 [0, 100 000]，world.json shock_binding S03 clamp_range_ppm）。
func test_shock_s03_sovereign_rate_clamps_at_upper_bound() -> void:
	var w: JWWorldMarket = _new_world()
	var s: JWShocks = _new_shocks()
	_params[JWUnits.Param.RATE_SENSITIVITY_PPM] = 1_000_000
	# eff = 299 999（剧本上界）⇒ 10 000 + 299 999 = 309 999，超过上界 100 000
	_arm(s, K_S03_CREDIT, 299_999, 8, 8, ONSET_STEP, DECAY_NONE)
	s.apply_to_world(w, 7, _params)

	eq_int(w.sovereign_rate(), 100_000,
			"docs/12 §01.7：10 000 + mul_ppm(299 999, 1 000 000) = 309 999 ppm 超过上界，"
			+ "必须 clamp 到 100 000 ppm/季")
	ge_int(w.credit_limit, 0, "docs/17 §4.22 后置：credit_limit >= 0")


## 检验 docs/12 §01.7 的「无冲击即回到剧本基准」：eff == 0 时三条通道都必须写回 base_*，
## 而不是保留上一季被冲击改过的值（否则冲击永不退出）。
func test_inactive_shocks_restore_world_to_scenario_base() -> void:
	var w: JWWorldMarket = _new_world()
	var s: JWShocks = _new_shocks()

	# 先用一次冲击把三条通道都推离基准。
	_arm(s, K_S01_EXPORT, 500_000, 5, 5, ONSET_STEP, DECAY_NONE)
	_arm(s, K_S02_IMPORT, 300_000, 6, 6, ONSET_STEP, DECAY_NONE)
	_arm(s, K_S03_CREDIT, 250_000, 8, 8, ONSET_STEP, DECAY_NONE)
	s.apply_to_world(w, 4, _params)
	ne_int(w.export_demand(1), 1_000_000, "前置：S01 已把 manu 出口需求推离基准")

	# 冲击到期（docs/12 §01.6 (b)：remaining 归零时 active 与 magnitude 一并清零）。
	for k: int in JWUnits.SHOCK_N:
		s.active[k] = 0
		s.magnitude_ppm[k] = 0
		s.remaining_q[k] = 0
	s.apply_to_world(w, 9, _params)

	for i: int in JWUnits.S:
		eq_int(w.export_demand(i), 1_000_000,
				"docs/12 §01.7：eff == 0 ⇒ export_demand_ppm[%d] 必须写回 base_export_ppm = 1 000 000 ppm" % i)
		eq_int(w.import_price(i), 1_000_000,
				"docs/12 §01.7：eff == 0 ⇒ import_price_ppm[%d] 必须写回 base_import_ppm = 1 000 000 ppm" % i)
	eq_int(w.credit_limit, BASE_CREDIT_LIMIT_UU,
			"docs/12 §01.7：eff == 0 ⇒ credit_limit = mul_ppm(base, 1 000 000) = 12 000 000 000 μU")
	eq_int(w.sovereign_rate(), MARKET_RATE_BASE_PPM,
			"docs/12 §01.7：eff == 0 ⇒ sovereign_rate = param.market_rate_base_ppm = 10 000 ppm")


## 检验 docs/12 §01.7 的线性衰减：`decay_ppm = mul_div_floor(remaining_q, 1e6, duration_q)`。
## 用 onset=ramp_2q 且 decay=linear，使「非 step / 非 none」这一分支在两种读法下都必然被取到。
func test_linear_decay_scales_effect_by_remaining_over_duration() -> void:
	var w: JWWorldMarket = _new_world()
	var s: JWShocks = _new_shocks()
	# decay_ppm = floor(3 * 1e6 / 8) = 375 000；eff = mul_ppm(400 000, 375 000) = 150 000
	_arm(s, K_S01_EXPORT, 400_000, 8, 3, ONSET_RAMP_2Q, DECAY_LINEAR)
	s.apply_to_world(w, 10, _params)

	eq_int(w.export_demand(1), 1_105_000,
			"docs/12 §01.7：decay = mul_div_floor(3, 1e6, 8) = 375 000；eff = 150 000；"
			+ "manu 权重 700 000 ⇒ 1 000 000 + mul_ppm(150 000, 700 000) = 1 105 000 ppm")
	eq_int(w.export_demand(0), 1_030_000,
			"docs/12 §01.7：agri 权重 200 000 ⇒ 1 000 000 + mul_ppm(150 000, 200 000) = 1 030 000 ppm")

	# 同一条冲击、剩余期更少 ⇒ 效应必须更弱（衰减是单调的）。
	var w2: JWWorldMarket = _new_world()
	s.remaining_q[K_S01_EXPORT] = 1
	s.apply_to_world(w2, 12, _params)
	eq_int(w2.export_demand(1), 1_035_000,
			"docs/12 §01.7：decay = mul_div_floor(1, 1e6, 8) = 125 000；eff = 50 000 ⇒ 1 035 000 ppm")
	le_int(w2.export_demand(1), w.export_demand(1),
			"docs/12 §01.7：线性衰减必须单调——剩余 1 季的效应不得强于剩余 3 季")


## 检验 INV-108 的结构性要求：`apply_to_world` 只写 `state.world.*` 白名单，
## **不得写任何国内账户、产能、库存或人口**。用逐子系统哈希把「没被碰过」变成可执行断言。
func test_apply_to_world_writes_no_domestic_subsystem() -> void:
	var st: JWSimState = JWSimState.new()
	st.allocate_all()

	st.world.base_export_ppm = PackedInt64Array([1_000_000, 1_000_000, 1_000_000, 1_000_000])
	st.world.base_import_ppm = PackedInt64Array([1_000_000, 1_000_000, 1_000_000, 1_000_000])
	st.world.base_credit_limit = BASE_CREDIT_LIMIT_UU
	st.shocks.target_weights_ppm = TARGET_WEIGHTS_PPM.duplicate()
	st.shocks.onset_profile = PackedInt64Array([ONSET_STEP, ONSET_STEP, ONSET_STEP])
	st.shocks.decay_profile = PackedInt64Array([DECAY_NONE, DECAY_NONE, DECAY_NONE])
	_arm(st.shocks, K_S01_EXPORT, 500_000, 5, 5, ONSET_STEP, DECAY_NONE)
	_arm(st.shocks, K_S03_CREDIT, 250_000, 8, 8, ONSET_STEP, DECAY_NONE)

	var before: PackedStringArray = PackedStringArray()
	for sub: int in JWUnits.SUBSYS_N:
		before.append(st.subsystem_hash(sub))

	st.shocks.apply_to_world(st.world, 7, st.params)

	for sub: int in JWUnits.SUBSYS_N:
		if sub == JWUnits.SUBSYS_WORLD:
			continue
		eq_str(st.subsystem_hash(sub), before[sub],
				"INV-108：apply_to_world 只允许写 state.world.* 白名单，"
				+ "子系统 %d 的 subsystem_hash 必须逐位不变" % sub)
	ne_int(st.world.export_demand(1), 1_000_000,
			"夹具自检：本次冲击确实改动了 world.export_demand_ppm，"
			+ "否则上面的『别的子系统没变』是空跑出来的")


# ── INV-109 / INV-011 抽样、写日志、重载不重抽 ───────────────────────────

## 检验 INV-109（每次冲击抽样写 `shock_log`，含 draw_index / raw_u64 / mapped_value）
## 与 INV-011（本季 log.rng 条数 == Σ Δdraw_count）。
func test_shock_arrival_writes_shock_log_and_rng_log() -> void:
	var w: JWWorldMarket = _new_world()
	var s: JWShocks = _new_shocks()
	var rng: JWRngStreams = _new_rng(20260912)
	_only_channel_can_arrive(s, K_S01_EXPORT)
	_pin_magnitude_and_duration(s, K_S01_EXPORT, 150_000, 5)

	var q: int = 11
	rng.begin_quarter(q)
	s.resolve_quarter(rng, w, q, _params)

	check(s.is_active(K_S01_EXPORT),
			"docs/12 §01.6 (c)：hazard == 1 000 000 时 draw_ppm ∈ [0, 1e6) 恒小于它，冲击必然到达")
	eq_int(s.magnitude(K_S01_EXPORT), 150_000,
			"docs/12 §01.6：mag_min == mag_max == 150 000 ⇒ draw_range 必然返回 150 000 ppm")
	eq_int(s.remaining(K_S01_EXPORT), 5,
			"docs/12 §01.6：dur_min == dur_max == 5 ⇒ remaining_q 必然置为 5 季")

	var rows: PackedInt64Array = s.export_shock_log()
	eq_int(rows.size(), SL_COLS,
			"INV-109：一次到达写且只写一行 shock_log，每行 7 列（q, kind, mag, dur, draw_index, raw, mapped）")
	eq_int(rows[SL_Q], q, "INV-109：shock_log 必须登记抽样发生的季次 q == %d" % q)
	eq_int(rows[SL_KIND], K_S01_EXPORT, "INV-109：shock_log 必须登记冲击类别 k == 0（S01）")
	eq_int(rows[SL_MAG], 150_000, "INV-109：shock_log 的强度列必须等于实际生效强度 150 000 ppm")
	eq_int(rows[SL_DUR], 5, "INV-109：shock_log 的持续期列必须等于实际生效期数 5 季")
	ge_int(rows[SL_DRAW_INDEX], 0,
			"INV-109 / 计划书 §07：shock_log 必须登记 draw_index，否则重放时无法定位是哪一次抽样")
	ne_int(rows[SL_RAW], 0,
			"INV-109：shock_log 必须登记 raw_u64；恒为 0 说明这一列根本没写")

	# 到达抽样 1 次 + 强度 1 次 + 持续期 1 次 == 3（mag/dur 为单点区间，draw_below(1) 各 1 次）。
	eq_int(rng.draws_this_quarter_of(JWUnits.RngStream.SHOCK), 3,
			"docs/12 §01.6：一次到达恰好消耗 3 次 rng.shock 抽样（到达、强度、持续期）")
	eq_int(rng.log_row_count(), rng.draws_this_quarter(),
			"INV-011：本季 log.rng 条数必须精确等于 Σ Δdraw_count")


## 检验 docs/12 §01.6 (c)：到达抽样落空时**不写 shock_log**，但那一次抽样仍要进 log.rng（INV-011）。
func test_no_arrival_still_logs_the_draw_but_writes_no_shock_row() -> void:
	var w: JWWorldMarket = _new_world()
	var s: JWShocks = _new_shocks()
	var rng: JWRngStreams = _new_rng(777)
	# 三类都放开门禁但 hazard == 0：draw_ppm >= 0 恒成立 ⇒ 必然 continue。
	for k: int in JWUnits.SHOCK_N:
		s.hazard_ppm[k] = HAZARD_NEVER_PPM
		s.earliest_q[k] = 0
		s.min_gap_q[k] = 0

	rng.begin_quarter(3)
	s.resolve_quarter(rng, w, 3, _params)

	for k: int in JWUnits.SHOCK_N:
		check_false(s.is_active(k), "docs/12 §01.6：hazard == 0 时第 %d 类冲击必然不到达" % k)
	eq_int(s.export_shock_log().size(), 0,
			"INV-109：没有冲击到达就不该有 shock_log 行——落空不是事件，写进去会让重放复用一条空记录")
	eq_int(rng.draws_this_quarter_of(JWUnits.RngStream.SHOCK), 3,
			"docs/12 §01.6：三类冲击各做一次到达抽样，共 3 次；"
			+ "少抽会让 hazard 变成「不抽就不会中」的假随机")
	eq_int(rng.log_row_count(), rng.draws_this_quarter(),
			"INV-011：落空的那次抽样同样要写 log.rng")


## 检验 docs/12 §01.6 (b)：既有冲击的衰减分支在抽样**之前** `continue`，
## 因此衰减季不得消耗任何 rng.shock 抽样（否则冲击的存在会改变后续随机序列）。
func test_decay_branch_consumes_no_draw_and_clears_on_expiry() -> void:
	var w: JWWorldMarket = _new_world()
	var s: JWShocks = _new_shocks()
	var rng: JWRngStreams = _new_rng(31415)
	# 三类的 hazard 全开——若实现走到了 (c) 分支就会抽样，从而被本测试抓到。
	for k: int in JWUnits.SHOCK_N:
		s.hazard_ppm[k] = HAZARD_ALWAYS_PPM
		s.earliest_q[k] = 0
		s.min_gap_q[k] = 0
	_arm(s, K_S01_EXPORT, 200_000, 4, 2, ONSET_STEP, DECAY_NONE)
	_arm(s, K_S02_IMPORT, 300_000, 4, 1, ONSET_STEP, DECAY_NONE)
	_arm(s, K_S03_CREDIT, 100_000, 4, 3, ONSET_STEP, DECAY_NONE)

	rng.begin_quarter(20)
	s.resolve_quarter(rng, w, 20, _params)

	eq_int(rng.draws_this_quarter_of(JWUnits.RngStream.SHOCK), 0,
			"docs/12 §01.6 (b)：三类冲击都在衰减中，本季一次抽样也不该发生")
	eq_int(s.remaining(K_S01_EXPORT), 1, "docs/12 §01.6 (b)：remaining_q 每季减 1，2 → 1")
	check(s.is_active(K_S01_EXPORT), "docs/12 §01.6 (b)：remaining_q 未归零时冲击仍生效")
	eq_int(s.remaining(K_S02_IMPORT), 0, "docs/12 §01.6 (b)：remaining_q 1 → 0")
	check_false(s.is_active(K_S02_IMPORT),
			"docs/12 §01.6 (b)：remaining_q 归零时必须同时把 active 清 0")
	eq_int(s.magnitude(K_S02_IMPORT), 0,
			"docs/12 §01.6 (b)：remaining_q 归零时必须同时把 magnitude_ppm 清 0，"
			+ "否则 01.7 会拿一条已结束的冲击继续传导")
	eq_int(s.export_shock_log().size(), 0, "INV-109：衰减不是新抽样，不写 shock_log")


## 检验 docs/12 §01.6 (c) 的两道门在抽样**之前**判定：
## `q < earliest_q` 或 `q − last_end_q < min_gap_q` 时直接 continue，不消耗抽样。
func test_earliest_and_min_gap_gate_before_sampling() -> void:
	var w: JWWorldMarket = _new_world()
	var s: JWShocks = _new_shocks()
	var rng: JWRngStreams = _new_rng(2718)
	for k: int in JWUnits.SHOCK_N:
		s.hazard_ppm[k] = HAZARD_ALWAYS_PPM
	# k=0 被 earliest_q 挡住；k=1 被 min_gap_q 挡住；k=2 两道门都放行。
	s.earliest_q = PackedInt64Array([12, 0, 0])
	s.min_gap_q = PackedInt64Array([0, 4, 0])
	s.last_end_q = PackedInt64Array([-999, 8, -999])
	_pin_magnitude_and_duration(s, K_S03_CREDIT, 90_000, 4)

	var q: int = 10
	rng.begin_quarter(q)
	s.resolve_quarter(rng, w, q, _params)

	check_false(s.is_active(K_S01_EXPORT),
			"docs/12 §01.6 (c)：q=10 < earliest_q=12，S01 不得到达")
	check_false(s.is_active(K_S02_IMPORT),
			"docs/12 §01.6 (c)：q−last_end_q = 10−8 = 2 < min_gap_q = 4，S02 处在冷却期内不得到达")
	check(s.is_active(K_S03_CREDIT),
			"docs/12 §01.6 (c)：S03 两道门都放行且 hazard == 1e6，必然到达")
	eq_int(rng.draws_this_quarter_of(JWUnits.RngStream.SHOCK), 3,
			"docs/12 §01.6 (c)：被门禁挡住的两类不得抽样；只有 S03 的 3 次抽样（到达、强度、持续期）。"
			+ "抽 5 次说明门禁判定被放在了抽样之后，冷却期会污染随机序列")


## 检验 INV-109 / docs/31 `ADV-H01`（别名 ADV-06）：
## 存档重载后再推进同一季，必须**复用 shock_log 且不推进 rng.shock 计数器**。
func test_reload_reuses_shock_log_without_redrawing() -> void:
	var q: int = 14
	var seed_value: int = 987654321

	# 分支一：直接推进。
	var w1: JWWorldMarket = _new_world()
	var s1: JWShocks = _new_shocks()
	var rng1: JWRngStreams = _new_rng(seed_value)
	_only_channel_can_arrive(s1, K_S02_IMPORT)
	_pin_magnitude_and_duration(s1, K_S02_IMPORT, 420_000, 6)
	rng1.begin_quarter(q)
	s1.resolve_quarter(rng1, w1, q, _params)
	check(s1.is_active(K_S02_IMPORT), "前置：分支一必须抽中 S02 冲击")
	var rows: PackedInt64Array = s1.export_shock_log()
	eq_int(rows.size(), SL_COLS, "前置：分支一写了一行 shock_log")

	# 分支二：从「该季开始之前」的存档读档——draw_count 停在 0，shock_log 灌回。
	var w2: JWWorldMarket = _new_world()
	var s2: JWShocks = _new_shocks()
	var rng2: JWRngStreams = _new_rng(seed_value)
	_only_channel_can_arrive(s2, K_S02_IMPORT)
	_pin_magnitude_and_duration(s2, K_S02_IMPORT, 420_000, 6)
	var load_result: JWResult = s2.load_shock_log(rows)
	check(load_result.ok,
			"INV-131：export_shock_log 的输出必须能被 load_shock_log 原样吃回去（存档往返）")
	eq_int(rng2.draw_count_of(JWUnits.RngStream.SHOCK), 0, "前置：读档后 rng.shock 计数器为 0")

	rng2.begin_quarter(q)
	s2.resolve_quarter(rng2, w2, q, _params)

	eq_int(rng2.draws_this_quarter_of(JWUnits.RngStream.SHOCK), 0,
			"INV-109 / ADV-06：本季已有 shock_log 记录时必须复用，rng.shock 增量必须精确为 0；"
			+ "只要大于 0，读档重抽（save-scum）就成立了")
	eq_int(rng2.draw_count_of(JWUnits.RngStream.SHOCK), 0,
			"INV-109：复用记录不得推进累计计数器")
	eq_int(s2.magnitude(K_S02_IMPORT), s1.magnitude(K_S02_IMPORT),
			"ADV-06：复用后的强度必须与首次逐字段相同（%d ppm）" % s1.magnitude(K_S02_IMPORT))
	eq_int(s2.remaining(K_S02_IMPORT), s1.remaining(K_S02_IMPORT),
			"ADV-06：复用后的剩余期数必须与首次逐字段相同（%d 季）" % s1.remaining(K_S02_IMPORT))
	check(s2.is_active(K_S02_IMPORT), "ADV-06：复用后冲击必须同样处于激活态")
	eq_int(s2.export_shock_log().size(), SL_COLS,
			"INV-109：复用不得追加第二行记录——同一 (q, k) 出现两行，重放会取到哪一行就不确定了")

	# 传导结果也必须逐位相同（复用的是记录，不是只有记录的标签）。
	s1.apply_to_world(w1, q, _params)
	s2.apply_to_world(w2, q, _params)
	eq_int(w2.import_price(1), w1.import_price(1),
			"INV-133：save → load → advance 与直接 advance 的 import_price_ppm 必须逐位相同")


## 检验 INV-009（随机流结构性独立）：在 `rng.event` 上多抽任意次，
## 都不得改变 `rng.shock` 抽出来的冲击（「多写一句新闻就改变经济抽样」）。
func test_shock_sampling_is_independent_of_event_stream() -> void:
	var q: int = 9

	var w1: JWWorldMarket = _new_world()
	var s1: JWShocks = _new_shocks()
	var rng1: JWRngStreams = _new_rng(424242)
	_only_channel_can_arrive(s1, K_S01_EXPORT)
	rng1.begin_quarter(q)
	s1.resolve_quarter(rng1, w1, q, _params)

	var w2: JWWorldMarket = _new_world()
	var s2: JWShocks = _new_shocks()
	var rng2: JWRngStreams = _new_rng(424242)
	_only_channel_can_arrive(s2, K_S01_EXPORT)
	rng2.begin_quarter(q)
	# 先在 event 流上额外抽 1 000 次（等价于「本季多触发了一千条新闻」）。
	for i: int in 1000:
		rng2.draw_ppm(JWUnits.RngStream.EVENT, 0)
	s2.resolve_quarter(rng2, w2, q, _params)

	eq_int(s2.magnitude(K_S01_EXPORT), s1.magnitude(K_S01_EXPORT),
			"INV-009：rng.event 多抽 1 000 次后，rng.shock 抽出的冲击强度必须逐位不变")
	eq_int(s2.remaining(K_S01_EXPORT), s1.remaining(K_S01_EXPORT),
			"INV-009：rng.event 多抽 1 000 次后，冲击持续期必须逐位不变")
	eq_int(rng2.draws_this_quarter_of(JWUnits.RngStream.SHOCK),
			rng1.draws_this_quarter_of(JWUnits.RngStream.SHOCK),
			"INV-009：两条流的计数器互不影响，rng.shock 的本季抽样次数必须相同")
	eq_int(rng2.draws_this_quarter_of(JWUnits.RngStream.EVENT), 1000,
			"INV-009：rng.event 自身的计数器增量必须恰好是额外抽的 1 000 次")
