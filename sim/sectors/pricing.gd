## 价格、工资率、住房使用成本的有界平滑调整。
##
## 结构性保证：S07 只写 pending，S08 末一次性 swap，S05 内价格全程是常量（INV-065/070）。
## 持有 log.clamp 与夹逼预算计数。
##
## 骨架依据：docs/17_api_skeleton.md §4.9。依赖秩 2，只允许引用秩 0/1。
## 公式依据：docs/12 §7.3（价格与工资）、§5.6（成交口径）、§8（消费价格指数）；
## 刻度依据：docs/18 R-SCALE-01（1 U = 1e9 μU，一切「先乘后除」只走 JWMath.mul_div_floor）。
class_name JWPricing
extends RefCounted

## §1.6 状态块协议：本块各数组所属子系统（与 STATE_ARRAY_IDS 等长）。
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_PRICE, JWUnits.SUBSYS_PRICE, JWUnits.SUBSYS_PRICE,
	JWUnits.SUBSYS_PRICE, JWUnits.SUBSYS_PRICE,
]

## 稳定 ID 注册表：下标 == 数组序号；顺序是 schema 的一部分，重排即破坏性变更（INV-136）。
const STATE_ARRAY_IDS: PackedStringArray = [
	"state.price.sector_uu_per_qs",
	"state.price.pending_uu_per_qs",
	"state.price.wage_uu_per_person_q",
	"state.price.wage_pending_uu_per_person_q",
	"state.price.housing_rent_uu_per_unit_q",
]
const STATE_SCALAR_IDS: PackedStringArray = [
	"state.price.clamp_budget_used_count",
]
const FLOW_ARRAY_IDS: PackedStringArray = [
	"flow.price.gap_ppm",
]
const FLOW_SCALAR_IDS: PackedStringArray = []

## log.clamp 的 field_code 编码：code == 类别 * CLAMP_FIELD_STRIDE + 下标。
## 下标是部门（价格）、技能档（工资）或地区（住房），一并编进 code，
## 因为 log.clamp 的行只有 {field_code, raw, clamped, bound} 四个整数，没有第五个位置放下标。
## 步长 100 > 任何一个维度常量（S=4 / K=3 / R=4），留足以后扩维的余量。
const CLAMP_FIELD_STRIDE: int = 100
## (c) 合成缺口截到 ±gap_cap_ppm
const CLAMP_FIELD_PRICE_GAP: int = 1
## (d) 单季价格变动截到 ±price_step_max_ppm
const CLAMP_FIELD_PRICE_STEP: int = 2
## (e) 下季价格截到 [p_floor, p_ceil]
const CLAMP_FIELD_PRICE_BOUND: int = 3
## 单季工资变动截到 ±wage_step_max_ppm
const CLAMP_FIELD_WAGE_STEP: int = 4
## 下季工资截到 [wage_floor_uu, wage_ceil_uu]
const CLAMP_FIELD_WAGE_BOUND: int = 5
## 住房使用成本（首版固定，只在退化输入时登记一行）
const CLAMP_FIELD_HOUSING_RENT: int = 6

## log.clamp 扩容倍率（1 500 000 ppm == 1.5 倍），写成分子分母避免出现小数字面量。
const LOG_GROWTH_NUM: int = 3
const LOG_GROWTH_DEN: int = 2

## swap_pending 的前置位：S07 已写过 price_pending。
const PENDING_PRICE: int = 1
## swap_pending 的前置位：S07 已写过 wage_pending。
const PENDING_WAGE: int = 2
## 两者齐备才允许 swap。
const PENDING_ALL: int = 3

## state.price.sector_uu_per_qs[] —— 长度 4，初值 1 000 000，单位 μU/Q_s。类 S，写入者 **仅 S08（swap）**。
var price: PackedInt64Array = PackedInt64Array()
## state.price.pending_uu_per_qs[] —— 长度 4，初值 = price，单位 μU/Q_s。类 S，写入者 **仅 S07**。
## 与 price 不互相放大：S05 读 price（常量），S07 写 price_pending，S08 把后者拷进前者，回路在数据流上被切断。
var price_pending: PackedInt64Array = PackedInt64Array()
## content.price.base_uu_per_qs[] —— 长度 4，初值 1 000 000，单位 μU/Q_s。类 C，写入者 LOAD。
## 唯一合法值是 JWUnits.BASE_PRICE（INV-148）；用于基年价（实际 GDP）口径。
var base_price: PackedInt64Array = PackedInt64Array()
## state.price.wage_uu_per_person_q[] —— 长度 3，初值来自剧本，单位 μU/人/季。类 S，写入者 **仅 S08（swap）**。
var wage: PackedInt64Array = PackedInt64Array()
## state.price.wage_pending_uu_per_person_q[] —— 长度 3，初值 = wage，单位 μU/人/季。类 S，写入者 **仅 S07**。
var wage_pending: PackedInt64Array = PackedInt64Array()
## state.price.housing_rent_uu_per_unit_q[] —— 长度 4，初值来自剧本，单位 μU/套/季。类 S，写入者 S07。
var housing_rent: PackedInt64Array = PackedInt64Array()
## content.labor.anchor_tightness_ppm —— ppm，类 C，写入者 LOAD（由剧本基年劳动力与在岗人数推出）。
## R-NAIRU-01：基年的 (空缺 − 失业) / 劳动力。工资只对「偏离基年松紧度」的部分作出反应，
## 基年失业率（计划书 §05：8%）就是工资不动的那一点。
var wage_anchor_tightness_ppm: int = 0
## flow.price.gap_ppm[] —— 长度 4，初值 0，单位 ppm。类 F，写入者 S07。
var gap_ppm: PackedInt64Array = PackedInt64Array()
## state.price.clamp_budget_used_count —— 初值 0，单位 计数。类 S，写入者 S07。
var clamp_used: int = 0

## log.clamp.* —— 容量 LOG_CAP0，类 L，写入者 S03 / S07 / S08。日志只有整数，展示文案由 Presentation 查模板表生成。
var log_field: PackedInt64Array = PackedInt64Array()
var log_raw: PackedInt64Array = PackedInt64Array()
var log_clamped: PackedInt64Array = PackedInt64Array()
var log_bound: PackedInt64Array = PackedInt64Array()

## 本季日志游标（日志不进 state_hash，不进存档）。写入者：S01 重置、S03/S07/S08 追加。
var _log_cursor: int = 0
## 本局日志扩容次数（诊断用，不进 state_hash）。
var _log_grow_count: int = 0
## 本季 S07 已写过哪些 pending 的位掩码（PENDING_PRICE | PENDING_WAGE）。
## 不是状态：S01 的 reset_flows() 清零，S08 的 swap_pending() 消费掉，不进存档也不进哈希。
## 它是 swap_pending 的「本季 S07 已跑过」前置条件的唯一可检验载体——
## 本类拿不到 phase，只能用数据流上的事实代替相位断言。
var _pending_written: int = 0


## 读取本季生效价格。S05 全程只读，不得写。
## 步骤：S03（招工预算）、S05（成交）、S06（税基）、S08（消费价格指数）
## 前置：s ∈ [0,4)
## 后置：不改状态
## 不变量：INV-065（S05 的任何函数不得写 price.*）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func price_of(s: int) -> int:
	if s < 0 or s >= price.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, s, price.size())
		return 0
	return price[s]


## 读取本季生效工资率（μU/人/季）。
## 步骤：S03（招工预算）、S05（成交）、S06（税基）、S08
## 前置：k ∈ [0,3)
## 后置：不改状态
## 不变量：INV-065、INV-070
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func wage_of(k: int) -> int:
	if k < 0 or k >= wage.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, k, wage.size())
		return 0
	return wage[k]


## 读取本季住房季度使用成本（μU/套/季）。
## 步骤：S06（可支配收入）、S07（迁移比较）
## 前置：r ∈ [0,4)
## 后置：不改状态
## 不变量：INV-083
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func rent_of(r: int) -> int:
	if r < 0 or r >= housing_rent.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, r, housing_rent.size())
		return 0
	return housing_rent[r]


## 读取基年价（μU/Q_s），实际 GDP 与库存计值的唯一价格来源。
## 步骤：S05（入库计值）、S06（实际增加值）
## 前置：s ∈ [0,4)
## 后置：不改状态
## 不变量：INV-117（实际量一律用数量口径 × 基年价重算，禁止名义值除价格指数）、INV-148
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func base_price_of(s: int) -> int:
	if s < 0 or s >= base_price.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, s, base_price.size())
		return 0
	return base_price[s]


## 居民消费价格指数（派生，纯函数；实际 GDP 函数禁止引用它，INV-117）。
## 步骤：S06/S08 读
## 前置：consumption_weight 为各产品消费量权重（由 JWPopulation 传入）
## 后置：不改状态
## 不变量：INV-117（静态检查：实际 GDP 计算不得出现本函数）
## 失败：权重全 0 → 返回 1_000_000（基年）
##
## 拉氏口径：index = Σ p_t·w / Σ p_0·w。直接求和会在 QTY_MAX × PRICE_MAX 处溢出 int64
## （1e12 × 2.5e9 = 2.5e21），所以先把权重整体归一到 ppm 份额再加权：
## 份额 ≤ 1e6、价格 ≤ 2.5e9，乘积 ≤ 2.5e15，全程留足裕度（docs/18 R-SCALE-01）。
## 归一与加权都用 mul_div_floor，p_t 与 p_0 走完全相同的算式——
## 于是「报告期价逐位等于基年价」时分子分母逐位相等，指数精确等于 1 000 000，基年不漂移。
func consumer_index_ppm(consumption_weight_uqs: PackedInt64Array) -> int:
	var n: int = consumption_weight_uqs.size()
	if n != price.size() or n != base_price.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, n, price.size())
		return JWUnits.PPM
	var w_sum: int = 0
	for s: int in n:
		var w: int = consumption_weight_uqs[s]
		if w < 0:
			JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, s, w)
			return JWUnits.PPM
		if w_sum > JWUnits.INT64_MAX - w:
			JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, w_sum, w)
			return JWUnits.PPM
		w_sum += w
	if w_sum == 0:
		# 权重全 0：没有消费篮子就没有消费价格，返回基年 1 000 000，不编一个出来。
		return JWUnits.PPM
	var num: int = 0
	var den: int = 0
	for s: int in n:
		# rounding: floor, reason=M1，权重归一到 ppm 份额只取整一次；少给优于凭空多给
		var share: int = JWMath.mul_div_floor(consumption_weight_uqs[s], JWUnits.PPM, w_sum)
		num += JWMath.mul_div_floor(price[s], share, JWUnits.PPM)
		den += JWMath.mul_div_floor(base_price[s], share, JWUnits.PPM)
	if den <= 0:
		# 基年价缺失（未 allocate / 未载入）：没有可比基准，返回基年值而不是 0 或除零。
		JWResult.raise_fault(JWResult.Fault.DIV_ZERO, den, JWUnits.PPM)
		return JWUnits.PPM
	# rounding: floor, reason=M1，指数只取整一次
	var idx: int = JWMath.mul_div_floor(num, JWUnits.PPM, den)
	if idx < 1:
		# docs/10 §9.1 区间 > 0：现价全 0 只可能是未载入，取最小合法值，不返回 0。
		return 1
	return idx


## S07 §7.3：按供需缺口与库存偏离更新下季价格，写 pending。
## 步骤：S07 §7.3
## 前置：supply/demand/inventory/inventory_target 为本季已结算的实际值；price_pending 尚未被本季写过
## 后置：price_pending[s] ∈ [floor, ceil]，|price_pending − price| <= step_max；每次夹逼写 log.clamp 并计数
## 不变量：INV-065, INV-066, INV-067, INV-068, INV-069
## 失败：不产生业务失败；越界参数 → INDEX_OUT_OF_RANGE
##
## 形参布局（docs/10 §9.2 / §0.5）：
##   supply_uqs  长 S；
##   demand_uqs  长 MARKET_N（部门 × 买方类，idx_market(s,b)），也接受已按部门汇总的长 S；
##   inventory_uqs / inventory_target_uqs 长 CELL（idx_cell(r,s)），也接受已按部门汇总的长 S；
##   storable    长 S（content.io.storable，0 表示不可库存）；
##   params      长 PARAM_N，下标见 JWUnits.Param。
##
## 「不在同一季循环放大」：本函数只写 price_pending 与 flow.price.gap_ppm，
## 读的 price 是本季常量，S08 末才 swap（INV-065）。
## R-PRICE-LONG-01：战役模式的长期上下限（不是状态：S07 定价前由编排器按本季价格水平写入，用完即弃）。
## 关闭时（旧剧本）走原来的绝对上下限，行为逐位不变。
var _lr_on: bool = false
var _lr_level_ppm: int = JWUnits.PPM
var _lr_band_floor_ppm: int = 0
var _lr_band_ceil_ppm: int = 0
var _lr_abs_floor_ppm: int = 0
var _lr_abs_ceil_ppm: int = 0
var _lr_wage_ceil_mult_ppm: int = JWUnits.PPM
## R-WAGEFLOOR-01：工资上下限跟随的滞后价格水平（价格带仍用当季水平）。
var _lr_wage_level_ppm: int = JWUnits.PPM


## 写入本季的长期上下限参数（编排器 S07 调用；on == false 即关闭）。
func set_long_run_bounds(on: bool, level_ppm: int, band_floor_ppm: int, band_ceil_ppm: int,
		abs_floor_ppm: int, abs_ceil_ppm: int, wage_ceil_mult_ppm: int,
		wage_level_ppm: int = -1) -> void:
	_lr_on = on
	_lr_level_ppm = maxi(1, level_ppm)
	# R-WAGEFLOOR-01：法定工资上下限跟随的是**滞后**价格水平（缺省退回当季值）。
	_lr_wage_level_ppm = maxi(1, wage_level_ppm if wage_level_ppm > 0 else level_ppm)
	_lr_band_floor_ppm = band_floor_ppm
	_lr_band_ceil_ppm = band_ceil_ppm
	_lr_abs_floor_ppm = abs_floor_ppm
	_lr_abs_ceil_ppm = abs_ceil_ppm
	_lr_wage_ceil_mult_ppm = wage_ceil_mult_ppm


func update_prices(supply_uqs: PackedInt64Array, demand_uqs: PackedInt64Array,
		inventory_uqs: PackedInt64Array, inventory_target_uqs: PackedInt64Array,
		storable: PackedInt64Array, params: PackedInt64Array) -> int:
	var n: int = JWUnits.S
	if price.size() != n or price_pending.size() != n or base_price.size() != n \
			or gap_ppm.size() != n:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, price.size(), n)
	if supply_uqs.size() != n or storable.size() != n:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, supply_uqs.size(), n)
	if demand_uqs.size() != JWUnits.MARKET_N and demand_uqs.size() != n:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				demand_uqs.size(), JWUnits.MARKET_N)
	if inventory_uqs.size() != JWUnits.CELL and inventory_uqs.size() != n:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				inventory_uqs.size(), JWUnits.CELL)
	if inventory_target_uqs.size() != inventory_uqs.size():
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				inventory_target_uqs.size(), inventory_uqs.size())
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)

	var gap_cap: int = params[JWUnits.Param.GAP_CAP_PPM]
	var gain: int = params[JWUnits.Param.PRICE_GAP_GAIN_PPM]
	var cover_gain: int = params[JWUnits.Param.PRICE_COVER_GAIN_PPM]
	var step_max_ppm: int = params[JWUnits.Param.PRICE_STEP_MAX_PPM]
	var floor_ppm: int = params[JWUnits.Param.PRICE_FLOOR_PPM]
	var ceil_ppm: int = params[JWUnits.Param.PRICE_CEIL_PPM]
	if gap_cap < 0 or step_max_ppm < 0 or floor_ppm > ceil_ppm:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, floor_ppm, ceil_ppm)

	var demand_by_class: bool = demand_uqs.size() == JWUnits.MARKET_N
	var inv_by_cell: bool = inventory_uqs.size() == JWUnits.CELL

	for s: int in n:
		# (a) 供需缺口（ppm，有界）。供给为 0 时没有可比基数，按契约直接取 gap_cap_ppm：
		# 「一份都供不出来」就是最大短缺信号，不是 0 缺口。
		var sup: int = supply_uqs[s]
		var dem: int = 0
		if demand_by_class:
			for b: int in JWUnits.BUYER_CLASS_N:
				dem += demand_uqs[JWIds.idx_market(s, b)]
		else:
			dem = demand_uqs[s]
		var gap_demand: int = gap_cap
		if sup > 0:
			# rounding: floor, reason=R-SCALE-01，(D−S)×1e6 在 QTY_MAX 处逼近上限，只走 mul_div_floor
			gap_demand = JWMath.clamp_i(
					JWMath.mul_div_floor(dem - sup, JWUnits.PPM, sup),
					-JWUnits.PPM, JWUnits.PPM)

		# (b) 库存偏离（ppm，有界；不可库存部门为 0）。
		var gap_cover: int = 0
		if storable[s] != 0:
			var inv_now: int = 0
			var inv_target: int = 0
			if inv_by_cell:
				for r: int in JWUnits.R:
					var c: int = JWIds.idx_cell(r, s)
					inv_now += inventory_uqs[c]
					inv_target += inventory_target_uqs[c]
			else:
				inv_now = inventory_uqs[s]
				inv_target = inventory_target_uqs[s]
			if inv_target < 1:
				# 契约的 max(·, 1)：目标为 0 时分母取 1，缺口自然落在 ±100% 的夹逼里。
				inv_target = 1
			# rounding: floor, reason=R-SCALE-01，同 (a)
			gap_cover = JWMath.clamp_i(
					JWMath.mul_div_floor(inv_target - inv_now, JWUnits.PPM, inv_target),
					-JWUnits.PPM, JWUnits.PPM)

		# (c) 合成并截断（记 log.clamp）。两项各自先缩放再相加，是契约的写法，不合并成一个系数。
		var gap_raw: int = JWMath.mul_ppm(gap_demand, gain) + JWMath.mul_ppm(gap_cover, cover_gain)
		var gap: int = _clamp_logged(CLAMP_FIELD_PRICE_GAP * CLAMP_FIELD_STRIDE + s,
				gap_raw, -gap_cap, gap_cap)
		gap_ppm[s] = gap

		# (d) 原始变动与步长封顶（记 log.clamp）。
		# mul_ppm 对负数向 −∞ 取整，降价方向多减 1 μU：这是契约锁定的确定性偏置
		# （T-U-PRICE-NEG-ROUNDING），不得改成向零截断，也不得事后补偿。
		var p_cur: int = price[s]
		var delta_raw: int = JWMath.mul_ppm(p_cur, gap)
		var max_step: int = JWMath.mul_ppm(p_cur, step_max_ppm)
		var delta: int = _clamp_logged(CLAMP_FIELD_PRICE_STEP * CLAMP_FIELD_STRIDE + s,
				delta_raw, -max_step, max_step)

		# (e) 绝对上下限（记 log.clamp）。相对护栏（base × floor/ceil_ppm）与绝对护栏
		# （JWUnits.PRICE_MIN/MAX，JWMath.check_price 的区间）取交集，只留一个夹逼点：
		# 两个点会把同一次撞墙记两次，夹逼预算 INV-069 就失去了标定意义。
		var p_floor: int = JWMath.mul_ppm(base_price[s], floor_ppm)
		var p_ceil: int = JWMath.mul_ppm(base_price[s], ceil_ppm)
		if p_floor < JWUnits.PRICE_MIN:
			p_floor = JWUnits.PRICE_MIN
		if p_ceil > JWUnits.PRICE_MAX:
			p_ceil = JWUnits.PRICE_MAX
		if _lr_on:
			# R-PRICE-LONG-01：[max(基年价×水平×带宽下限, 基年价×绝对下限), min(基年价×水平×带宽上限, 基年价×绝对上限)]；
			# 水平越过绝对护栏时两端相交，下限取上限（价格钉在护栏上，照常记夹逼）。
			var at_level: int = JWMath.mul_ppm(base_price[s], _lr_level_ppm)
			p_floor = maxi(JWMath.mul_ppm(at_level, _lr_band_floor_ppm),
					JWMath.mul_ppm(base_price[s], _lr_abs_floor_ppm))
			p_ceil = mini(JWMath.mul_ppm(at_level, _lr_band_ceil_ppm),
					JWMath.mul_ppm(base_price[s], _lr_abs_ceil_ppm))
			p_floor = maxi(p_floor, 1)
			if p_floor > p_ceil:
				p_floor = p_ceil
		if p_floor > p_ceil:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p_floor, p_ceil)
		price_pending[s] = _clamp_logged(CLAMP_FIELD_PRICE_BOUND * CLAMP_FIELD_STRIDE + s,
				p_cur + delta, p_floor, p_ceil)

	_pending_written |= PENDING_PRICE
	return JWResult.OK


## S07 §7.3 末：工资率同法（空缺 vs 失业），写 wage_pending。
## 步骤：S07 §7.3
## 前置：vacancies/unemployed/labor_force 来自 S03 的实际结果
## 后置：wage_pending[k] ∈ [wage_floor, wage_ceil]，步长受 wage_step_max_ppm 约束
## 不变量：INV-070（不在季内出清）、INV-069（夹逼计数）
## 失败：labor_force == 0 → gap 记 0，不除零
##
## 松紧度是全国一个数（空缺与失业都不分技能档，docs/12 §7.3 的分母是 labor_force_total），
## 三档工资各自按自己的现值走同一比例的有界平滑，技能溢价结构因此保持不变。
func update_wages(vacancies_persons: int, unemployed_persons: int,
		labor_force_persons: int, params: PackedInt64Array) -> int:
	var k_n: int = JWUnits.K
	if wage.size() != k_n or wage_pending.size() != k_n:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, wage.size(), k_n)
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	var wage_gain: int = params[JWUnits.Param.WAGE_GAIN_PPM]
	var step_max_ppm: int = params[JWUnits.Param.WAGE_STEP_MAX_PPM]
	var wage_floor: int = params[JWUnits.Param.WAGE_FLOOR_UU]
	var wage_ceil: int = params[JWUnits.Param.WAGE_CEIL_UU]
	if step_max_ppm < 0 or wage_floor > wage_ceil:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, wage_floor, wage_ceil)
	if _lr_on:
		# R-PRICE-LONG-01：工资上下限随价格水平移动；上限另乘实际工资增长余量（四百年的实际工资可以数倍增长）。
		wage_floor = JWMath.mul_ppm(wage_floor, _lr_wage_level_ppm)
		wage_ceil = JWMath.mul_ppm(JWMath.mul_ppm(wage_ceil, _lr_wage_level_ppm),
				_lr_wage_ceil_mult_ppm)
	if wage_floor < 1:
		# docs/10 §9.1：工资率区间 > 0。下界至少 1 μU，避免把工资清成 0。
		wage_floor = 1

	var tightness: int = 0
	if labor_force_persons > 0:
		# rounding: floor, reason=R-SCALE-01，(空缺−失业)×1e6 只走 mul_div_floor
		tightness = JWMath.clamp_i(
				JWMath.mul_div_floor(vacancies_persons - unemployed_persons,
						JWUnits.PPM, labor_force_persons),
				-JWUnits.PPM, JWUnits.PPM)
	# R-NAIRU-01：松紧度按基年锚点去偏。未去偏时基年 8% 失业、零空缺给出 −8% 的恒定负缺口，
	# 工资每季无条件下调约 1.2%，十年跌去三成，所得税税基随之萎缩（无命令基线第 27—35 季审查连败）。
	tightness = JWMath.clamp_i(tightness - wage_anchor_tightness_ppm, -JWUnits.PPM, JWUnits.PPM)

	for k: int in k_n:
		var w_cur: int = wage[k]
		# mul_ppm_2 == 契约的 mul_ppm(wage_cur, mul_ppm(tightness, wage_gain))：
		# 先把两个 ppm 合成一个系数，再对 wage_cur 只取整一次（M2）。
		var delta_raw: int = JWMath.mul_ppm_2(w_cur, tightness, wage_gain)
		var max_step: int = JWMath.mul_ppm(w_cur, step_max_ppm)
		var delta: int = _clamp_logged(CLAMP_FIELD_WAGE_STEP * CLAMP_FIELD_STRIDE + k,
				delta_raw, -max_step, max_step)
		wage_pending[k] = _clamp_logged(CLAMP_FIELD_WAGE_BOUND * CLAMP_FIELD_STRIDE + k,
				w_cur + delta, wage_floor, wage_ceil)

	_pending_written |= PENDING_WAGE
	return JWResult.OK


## S07：住房季度使用成本（按占用率）。
## 步骤：S07 §7.3
## 前置：occupied/capacity 来自 S07 的人口结果
## 后置：housing_rent[r] > 0
## 不变量：INV-083（住房恒等式由 JWCapital/JWPopulation 保证，本函数只定价）
## 失败：capacity == 0 → 保持原值，写 log.clamp
##
## **首版按 OQ-244 的取法：租金由剧本给出，S07 不更新。**
## docs/12 §7.3 只给了价格与工资两套公式，租金的更新规则「三稿都没给」（docs/13 OQ-244），
## 内容包已经按这条取法写死并作为验收依据：
##   content/events/event_E03.json 的 rent_is_fixed_note_zh「首版租金固定……S07 不更新」，
##   content/scenarios/chengwan/population_init.json 的 _note_housing_zh 同。
## 因此本函数**只做输入体检，不改值**：自行发明一条占用率公式会同时违反
## 「禁止实现者自行假定」（docs/18 末节）与上述内容包注记，且会改变住房负担率与迁移闸的行为。
## 缺一个参数族（参照占用率、gain、step、floor/ceil）才能实现，已在 open_questions 登记。
## capacity == 0 的退化输入按骨架契约写一行 log.clamp（raw == clamped，不计入夹逼预算）。
func update_housing_rent(occupied_units: PackedInt64Array, capacity_units: PackedInt64Array,
		params: PackedInt64Array) -> int:
	var r_n: int = JWUnits.R
	if housing_rent.size() != r_n:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, housing_rent.size(), r_n)
	if occupied_units.size() != r_n or capacity_units.size() != r_n:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				occupied_units.size(), r_n)
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	for r: int in r_n:
		if capacity_units[r] <= 0:
			# 没有容量就没有占用率：保持原值并留痕，不静默跳过，也不把租金改成 0。
			log_clamp(CLAMP_FIELD_HOUSING_RENT * CLAMP_FIELD_STRIDE + r,
					housing_rent[r], housing_rent[r], housing_rent[r])
	return JWResult.OK


## S08 收尾：价格与工资的唯一切换点。
## 步骤：S08 §8.7
## 前置：phase == S08；本季 S07 已写过 pending
## 后置：price == price_pending 且 wage == wage_pending（逐位）
## 不变量：INV-065, INV-070
## 失败：phase 不对 → Fault.PHASE_VIOLATION
##
## 本类不持有 phase（秩 2 不得引用 SimState），所以前置条件落在数据流上：
## 只有本季 S07 的 update_prices 与 update_wages 都写过 pending 才允许 swap，
## 拷完即清标志——同季重复 swap、或 S07 未跑就 swap，都会被判 PHASE_VIOLATION 而不是静默生效。
func swap_pending() -> int:
	if _pending_written != PENDING_ALL:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, _pending_written, PENDING_ALL)
	if price.size() != price_pending.size() or wage.size() != wage_pending.size():
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				price.size(), price_pending.size())
	for s: int in price.size():
		price[s] = price_pending[s]
	for k: int in wage.size():
		wage[k] = wage_pending[k]
	_pending_written = 0
	return JWResult.OK


## 夹逼登记（供其它类复用同一条日志通道）。
## 步骤：S03, S07, S08
## 前置：field_code 已在文案表登记
## 后置：log.clamp 多一行。**不动 clamp_used**（理由见下）
## 不变量：INV-011（日志行数对账）
## 失败：日志满 → 扩容并写告警行，不失败
##
## 裁定（集成期，INV-013 与 INV-069 的边界）：`clamp_used` 就是
## `state.price.clamp_budget_used_count`，属 SUBSYS_PRICE 的**状态**，而 PRICE 只在
## S07/S08 可写（JWUnits.WRITABLE_SUBSYS）。本函数的文档写着「步骤：S03, S07, S08」——
## JWLaborMarket 在 S03 的工资资金闸、JWPopulation 在 S07 的席位截断都复用这条日志通道。
## 若本函数顺手把 clamp_used 加 1，S03 的一次招工夹逼就成了一次对 PRICE 状态的写入，
## WriteGuard 立刻判 WRITE_OUT_OF_SCOPE —— 实测就是这样（S03/SUBSYS_PRICE）。
## 两条契约里只能让一条退：让计数退。因为 `param.price_clamp_budget_count` 标定的是
## **价格 / 工资 / 租金护栏**的撞墙预算（docs/12 §7.3），把招工摩擦、席位截断算进这本账
## 本来就是口径错配。计数因此下沉到 `_clamp_logged`（价格族护栏的唯一入口）。
## 日志通道照常对所有调用者开放：`log.clamp` 不进 state_hash，写它不构成越权写入。
func log_clamp(field_code: int, raw: int, clamped: int, bound: int) -> void:
	if _log_cursor >= log_field.size():
		_log_grow()
	log_field[_log_cursor] = field_code
	log_raw[_log_cursor] = raw
	log_clamped[_log_cursor] = clamped
	log_bound[_log_cursor] = bound
	_log_cursor += 1


## §1.7 日志协议：每季 S01 重置本季游标（日志不进 state_hash）。
## 步骤：S01
## 前置：phase == S01
## 后置：log_row_count() == 0
## 不变量：INV-011 / INV-139（日志行数对账）
## 失败：无
func log_reset_quarter() -> void:
	_log_cursor = 0


## §1.7 日志协议：本季已写行数，供 INV-011 / INV-139 对账。
## 步骤：任意
## 前置：无
## 后置：不改状态
## 不变量：INV-011, INV-139
## 失败：无
func log_row_count() -> int:
	return _log_cursor


## §1.7 日志协议：当前容量；写满时按 1 500 000 ppm 扩容并写一条告警行。
## 步骤：任意
## 前置：无
## 后置：不改状态
## 不变量：INV-011
## 失败：无
func log_capacity() -> int:
	return log_field.size()


## 本局日志扩容发生的次数（诊断用；扩容不写额外行，避免污染 log.clamp 的行数对账）。
## 步骤：每季末 / 诊断
## 前置：无
## 后置：不改状态
## 不变量：INV-139
## 失败：无
func log_grow_count() -> int:
	return _log_grow_count


## 四张 log 数组按 1 500 000 ppm（1.5 倍）同步扩容（docs/10 §12）。
## 步骤：写日志时容量耗尽
## 前置：无
## 后置：四张数组等长且 > 原长
## 不变量：INV-139
## 失败：无
func _log_grow() -> void:
	var cap: int = log_field.size()
	var next_cap: int = JWUnits.LOG_CAP0
	if cap > 0:
		# rounding: ceil, reason=扩容宁可多要一行，也不能因取整停在原容量上
		next_cap = JWMath.ceil_div(JWMath.mul(cap, LOG_GROWTH_NUM), LOG_GROWTH_DEN)
	if next_cap <= cap:
		next_cap = cap + 1
	log_field.resize(next_cap)
	log_raw.resize(next_cap)
	log_clamped.resize(next_cap)
	log_bound.resize(next_cap)
	_log_grow_count += 1


## 夹逼 + 按需登记。只有护栏真的生效（raw != clamped）才写 log.clamp 并计数，
## 这正是 docs/12 §7.3「每次 clamp 生效都写 log.clamp 并 clamp_budget_used_count += 1」的字面含义，
## 也是 T-U-E-09（缺口恒为 0 时 log.clamp 行数增量 == 0）能成立的前提。
## 步骤：S07
## 前置：lo <= hi
## 后置：返回 clamp_i(raw, lo, hi)；生效时日志多一行、clamp_used += 1
## 不变量：INV-066, INV-067, INV-069
## 失败：lo > hi → JWMath.clamp_i 登记 INDEX_OUT_OF_RANGE 并返回 lo
func _clamp_logged(field_code: int, raw: int, lo: int, hi: int) -> int:
	var v: int = JWMath.clamp_i(raw, lo, hi)
	if v != raw:
		var bound: int = hi
		if raw < lo:
			bound = lo
		log_clamp(field_code, raw, v, bound)
		# 只有真的被护栏改了值才算一次夹逼：计数是「撞墙次数」，不是「检查次数」，
		# 否则 INV-069 的预算标定会被没生效的检查稀释。
		# 计数在这里而不在 log_clamp 里：见 log_clamp 的裁定说明（INV-013 的边界）。
		clamp_used += 1
	return v


## §1.6 状态块协议：LOAD 期一次性 resize 到 §2 的契约长度。
## 步骤：LOAD
## 前置：尚未 allocate
## 后置：price/price_pending/base_price/housing_rent/gap_ppm 长度 S，wage/wage_pending 长度 K，
##       四条日志数组长度 LOG_CAP0
## 不变量：INV-136
## 失败：无
##
## base_price 例外：它是内容常量且唯一合法值就是 JWUnits.BASE_PRICE（INV-148），
## 而 §1.6 的注册表里没有它的位置（它不进 state_hash 也不进存档），因此没有 setter。
## 在这里直接落定，既满足 INV-148，也不留下能写出非法基年价的通路。
func allocate() -> void:
	price.resize(JWUnits.S)
	price.fill(0)
	price_pending.resize(JWUnits.S)
	price_pending.fill(0)
	base_price.resize(JWUnits.S)
	base_price.fill(JWUnits.BASE_PRICE)
	wage.resize(JWUnits.K)
	wage.fill(0)
	wage_pending.resize(JWUnits.K)
	wage_pending.fill(0)
	housing_rent.resize(JWUnits.R)
	housing_rent.fill(0)
	gap_ppm.resize(JWUnits.S)
	gap_ppm.fill(0)
	log_field.resize(JWUnits.LOG_CAP0)
	log_field.fill(0)
	log_raw.resize(JWUnits.LOG_CAP0)
	log_raw.fill(0)
	log_clamped.resize(JWUnits.LOG_CAP0)
	log_clamped.fill(0)
	log_bound.resize(JWUnits.LOG_CAP0)
	log_bound.fill(0)
	clamp_used = 0
	_log_cursor = 0
	_log_grow_count = 0
	_pending_written = 0


## §1.6 状态块协议：只读取用（返回引用，调用方不得写）。
## 步骤：LOAD / 哈希 / 存档
## 前置：i ∈ [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func state_array(i: int) -> PackedInt64Array:
	if i == 0:
		return price
	if i == 1:
		return price_pending
	if i == 2:
		return wage
	if i == 3:
		return wage_pending
	if i == 4:
		return housing_rent
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


## §1.6 状态块协议：仅 LOAD / MIG（静态检查：调用点必须在 systems/content_loader.gd 或 systems/saves.gd）。
## 步骤：LOAD / MIG
## 前置：allocate() 已调用；v 长度与契约一致
## 后置：对应数组逐位等于 v
## 不变量：INV-136、INV-148（base_price 必须逐位等于 JWUnits.BASE_PRICE）
## 失败：越界或长度不符 → INDEX_OUT_OF_RANGE / Load.SCHEMA_HEADER
##
## duplicate()：Godot 4 的 Packed*Array 传参是引用语义，直接赋值会让本块的状态
## 与调用方的临时数组共用同一块内存，此后调用方改一位就等于偷改了权威状态。
func set_state_array(i: int, v: PackedInt64Array) -> int:
	var want: int = JWUnits.S
	if i == 2 or i == 3:
		want = JWUnits.K
	elif i == 4:
		# 租金按地区排列（R-SCENARIO-02 的 5 区测试查出：此前按部门数 S 校验，4 区时两者恰好相等）。
		want = JWUnits.R
	if i < 0 or i >= STATE_ARRAY_IDS.size():
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i,
				STATE_ARRAY_IDS.size())
	if v.size() != want:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v.size(), want)
	if i == 0:
		price = v.duplicate()
	elif i == 1:
		price_pending = v.duplicate()
	elif i == 2:
		wage = v.duplicate()
	elif i == 3:
		wage_pending = v.duplicate()
	else:
		housing_rent = v.duplicate()
	return JWResult.OK


## §1.6 状态块协议：读标量状态。
## 步骤：LOAD / 哈希 / 存档
## 前置：i ∈ [0, STATE_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func state_scalar(i: int) -> int:
	if i == 0:
		return clamp_used
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


## §1.6 状态块协议：写标量状态，仅 LOAD / MIG。
## 步骤：LOAD / MIG
## 前置：i ∈ [0, STATE_SCALAR_IDS.size())
## 后置：对应标量等于 v
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE
func set_state_scalar(i: int, v: int) -> int:
	if i != 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i,
				STATE_SCALAR_IDS.size())
	if v < 0:
		# docs/10 §9.1：夹逼计数区间 ≥ 0。负数只可能来自坏存档，拒绝写入而不是默默接受。
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v, 0)
	clamp_used = v
	return JWResult.OK


## §1.6 状态块协议：读流量数组（只读取用）。
## 步骤：诊断 / 报告
## 前置：i ∈ [0, FLOW_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-010
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func flow_array(i: int) -> PackedInt64Array:
	if i == 0:
		return gap_ppm
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
	return PackedInt64Array()


## §1.6 状态块协议：本类无标量流量，恒返回 0。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：INV-010
## 失败：无
func flow_scalar(i: int) -> int:
	return 0


## §1.6 状态块协议：仅 S01；全部 FLOW_* 归零。
## 步骤：S01 §01.3
## 前置：phase == S01
## 后置：gap_ppm 全 0
## 不变量：INV-010
## 失败：无
##
## 同时清掉「本季 S07 已写过 pending」的标志：它与流量同一个生命周期（每季重来），
## 清在这里才能保证跨季不残留、S08 的相位断言有意义。
func reset_flows() -> void:
	gap_ppm.fill(0)
	_pending_written = 0


## §1.6 状态块协议：S01 清零后的自检，非 0 即 FLOW_NOT_RESET。
## 步骤：S01 §01.3 末
## 前置：reset_flows() 已调用
## 后置：不改状态
## 不变量：INV-010
## 失败：无
func flow_abs_sum() -> int:
	return JWMath.sum_abs(gap_ppm)


## §1.6 状态块协议：读档时写回流量数组（R-SAVE-01，由 tools/gen_flow_setters.py 按 flow_array 逐项对称生成）。
## 步骤：LOAD（JWSaves 经 JWSimState 调用）
## 前置：v 的长度与本块当前分配的长度一致（长度是 schema 的一部分，INV-136）
## 后置：对应成员被整体替换
## 不变量：INV-133（读档后与原进程逐位相同）
## 失败：下标越界或长度不符 → INDEX_OUT_OF_RANGE
func set_flow_array(i: int, v: PackedInt64Array) -> int:
	if i == 0:
		if v.size() != gap_ppm.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		gap_ppm = v.duplicate()
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
