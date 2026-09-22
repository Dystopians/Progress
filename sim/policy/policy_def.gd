## 12 项政策定义的运行时表示（docs/11 §5.12），以及机制注册表（MechanismRegistry）。
## 内容包只读。政策不能自带逻辑：它只能引用已注册机制并给参数（计划书 §09 的「伪深度」防线）。
##
## 骨架依据：docs/17_api_skeleton.md §4.8。
class_name JWPolicyDef
extends RefCounted

# ───────────────────────── 常量 ─────────────────────────

## 效果落点白名单（docs/11 §5.12），下标即 effect_target 码。
## 一切产能／容量／设施类效果只能落在 *_pending_* 上（V-PD-11 / INV-091）。
const EFFECT_TARGETS: PackedStringArray = [
	"state.region.grid_capacity_pending_uqs_per_q",
	"state.region.housing_pending_units",
	"state.region.irrigation_index_pending_ppm",
	"state.region.port_capacity_pending_uqs_per_q",
	"state.cell.capacity_pending_uqs_per_q",
	"state.pubserv.capacity_pending_uqs_per_q",
	"state.pubserv.teachers_persons",
	"state.pubserv.health_staff_persons",
	"state.policy.params_ppm",
	"state.policy.params_uu",
	"state.gov.tax_capacity_ppm",
	"state.politics.admin_capacity_ppm",
	"state.group.education_cohort_persons",
]

## 机制注册表：SimCore 里已实现的机制 ID，内容包的 mechanism_ids 必须全部命中（V-PD-08）。
##
## 下标即 mechanism_mask 的位序。mechanism_mask 进 content_hash，**位序一旦发布即不得重排**；
## 唯一合法的演进方式是在末尾追加。0..11 是 docs/17 §4.31 写死的原始 12 项，原样保留。
##
## 12..36 由 docs/17 §8 的 IR-02（「12 个机制 ID 先写死，十一项政策规格补齐后（OQ-220）复核清单」）
## 授权追加，并按 docs/18「待闭合三缺口」表的纪律执行：
##   「从**真实代码**抽取机制 ID 建成注册表（而不是从政策文件反向抄一遍——那样只会自证）」。
## 因此每一项后面都注明它所指的那处**已实现的 SimCore 函数**；找不到实现的名字一律不进表，
## 即便某个政策文件引用了它——那正是 V-PD-08 要拦的「政策自带逻辑」。
##
## 同一个函数不得注册成两个 ID：那是计划书 §09 的第二种伪深度（同一效果的两个名字）。
const MECHANISM_IDS: PackedStringArray = [
	# ── 0..11 原始 12 项（docs/17 §4.31，位序冻结） ──
	"mech.grid_capacity",           #  0 JWCapital.grid / add_pending(TARGET_REGION_GRID_PENDING)
	"mech.project_queue",           #  1 JWProjectQueue.launch / set_status / slots_used
	"mech.service_capacity",        #  2 JWCapital.pubserv_capacity
	"mech.tax_rate",                #  3 JWPolicyEngine.apply_pending_params → 税率参数生效
	"mech.transfer_payment",        #  4 JWPolicyEngine.transfer_due_into（含领取资格与应付额）
	"mech.investment_subsidy",      #  5 JWPolicyEngine.pay_subsidy
	"mech.training_seats",          #  6 JWPopulation.update_education（席位与 education_cohort）
	"mech.housing_stock",           #  7 JWCapital.housing_stock_of / housing_capacity_of
	"mech.irrigation_index",        #  8 JWCapital.irrigation
	"mech.port_capacity",           #  9 JWWorldMarket.delivery_remaining × JWCapital.port
	"mech.tax_capacity",            # 10 JWTreasury.collect_*_tax 里的 tax_capacity_ppm 闸门
	"mech.admin_capacity",          # 11 JWPolitics.set_admin_capacity
	# ── 12..36 IR-02 追加，逐项指名实现 ──
	"mech.income_tax",              # 12 JWTreasury.collect_income_tax（含 _bracket_tax 累进档）
	"mech.profit_tax",              # 13 JWTreasury.collect_profit_tax
	"mech.loss_carryforward",       # 14 JWSectorModel.compute_profit → state.cell.loss_carryforward_uu
	"mech.tax_receivable",          # 15 JWTreasury 的 state.gov.tax_receivable_uu 挂账
	"mech.disposable_income",       # 16 JWPopulation.settle_income_and_savings / disposable_income
	"mech.consumption_budget",      # 17 JWPopulation.consumption_budget_into
	"mech.output_plan",             # 18 JWSectorModel.plan_output（上季成交与未满足的需求预期）
	"mech.living_index",            # 19 JWPopulation.update_living_indices
	"mech.skill_transition",        # 20 JWPopulation.update_education 的 f_skill_out/f_skill_in 配对
	"mech.housing_occupancy",       # 21 JWMigration._check_housing / JWPricing.update_housing_rent
	"mech.construction_progress",   # 22 JWProjectQueue.compute_construction_capacity / advance_progress
	"mech.project_payment",         # 23 JWProjectQueue.payment_due_into / record_payment
	"mech.equipment_delivery",      # 24 JWWorldMarket.begin_quarter_delivery / delivery_remaining
	"mech.external_trade",          # 25 JWWorldMarket.record_export / record_import
	"mech.maintenance_backlog",     # 26 JWCapital.update_maintenance_and_availability（维护欠账）
	"mech.facility_availability",   # 27 JWCapital.availability（设施可用率，同一函数只登记一次）
	"mech.service_opex",            # 28 JWCapital.set_funding_ratio × JWUnits.PayLine.SERVICE_OPEX
	"mech.payment_priority",        # 29 JWTreasury.pay_line / add_arrears（支付优先级与欠付登记）
	"mech.budget_reservation",      # 30 JWTreasury.reserve / release_reservations
	"mech.claim_ledger",            # 31 JWPolicyEngine.claim_key_of（补助的幂等台账）
	"mech.firm_investment",         # 32 JWSectorModel.compute_invest_intent
	"mech.asset_commissioning",     # 33 JWAssetCommissioning.commission_ready / register_residual
	"mech.public_staffing",         # 34 JWLaborMarket.public_wage_due_into / pubserv_employment
	"mech.market_clearing",         # 35 JWInventory.collect_demand / ration / execute_trades
	"mech.policy_eligibility",      # 36 JWPolicyEngine.check_eligibility（权限/席位/否决/前置/冷却）
]

## 效果落点码的具名常量（== EFFECT_TARGETS 的下标，重排即破坏性变更）。
## JWPolicyEngine.apply_effects 与 JWCapital.add_pending 用同一套码分派。
const TARGET_REGION_GRID_PENDING: int = 0
const TARGET_REGION_HOUSING_PENDING: int = 1
const TARGET_REGION_IRRIGATION_PENDING: int = 2
const TARGET_REGION_PORT_PENDING: int = 3
const TARGET_CELL_CAPACITY_PENDING: int = 4
const TARGET_PUBSERV_CAPACITY_PENDING: int = 5
const TARGET_PUBSERV_TEACHERS: int = 6
const TARGET_PUBSERV_HEALTH_STAFF: int = 7
const TARGET_POLICY_PARAMS_PPM: int = 8
const TARGET_POLICY_PARAMS_UU: int = 9
const TARGET_GOV_TAX_CAPACITY_PPM: int = 10
const TARGET_POLITICS_ADMIN_CAPACITY_PPM: int = 11
const TARGET_GROUP_EDUCATION_COHORT: int = 12
## == EFFECT_TARGETS.size()，一致性由 validate() 的自检守住
const TARGET_N: int = 13

## 落点是「强度量」（ppm 指数／比率）还是「外延量」（μQ／μU／人／套）。
## 下标 == 效果落点码，长度 TARGET_N。
## 1 == 强度量：作用到多个槽位时每个槽位取同一值，**不拆分**（拆一个 ppm 指数没有意义）；
## 0 == 外延量：作用到多个槽位时必须走 JWMath.split_lr_into，保证 Σ 精确等于 effect_magnitude。
const TARGET_IS_RATIO: PackedInt64Array = [
	0, 0, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0,
]

## content.policy.kind 的编码（docs/11 §5.12 的枚举顺序，值即下标，不得重排）。
## JWContentLoader 把 "rate|transfer|subsidy|project|capacity|admin" 折成这些值。
const POLICY_KIND_RATE: int = 0
const POLICY_KIND_TRANSFER: int = 1
const POLICY_KIND_SUBSIDY: int = 2
const POLICY_KIND_PROJECT: int = 3
const POLICY_KIND_CAPACITY: int = 4
const POLICY_KIND_ADMIN: int = 5
const POLICY_KIND_N: int = 6

## 首位玩家参数的约定：对 kind ∈ {rate, transfer} 的政策，slot 0 是该政策的**主速率参数**
## （P01/P02 的 rate_ppm、P03 的 replacement_ppm）。其余 kind 的 slot 0 是 region_mask，
## 不由本常量解释。docs/11 §5.12 的 player_params 顺序即此约定的来源。
const PARAM_SLOT_PRIMARY: int = 0

## R-PSLOT-01：按玩家参数的键与类型解析出的槽位（加载期写入，类 C，不进状态块；−1 == 该政策没有这个旋钮）。
## PARAM_SLOT_PRIMARY 的「slot 0 是主速率」只对 rate / transfer 两类成立；其余各类的 slot 0 是 region_mask，
## 补助率在 P09 的 slot 2。按键解析让每个消费方读到它真正要的那一格，而不是按位置猜。
## region_mask（类型 mask）的槽位。
var mask_slot: PackedInt64Array = PackedInt64Array()
## 速率槽位：effect.rate_ref 指向的玩家参数；缺省时 rate / transfer 类取 PARAM_SLOT_PRIMARY。
var rate_slot: PackedInt64Array = PackedInt64Array()
## 每 cell 每季补助上限（cap_per_cell_per_q_uu）的槽位。
var cap_slot: PackedInt64Array = PackedInt64Array()
## 合格投资门槛（min_investment_ratio_ppm，相对期初资本）的槽位。
var min_ratio_slot: PackedInt64Array = PackedInt64Array()
## 每季数量旋钮（P05 的 seats_per_q_units）的槽位。
var qty_slot: PackedInt64Array = PackedInt64Array()
## 培训方向（P05 的 track：0 低→中、1 中→高、2 两档兼顾）的槽位。
var track_slot: PackedInt64Array = PackedInt64Array()
## R-P11-01：人员规模（staffing_scale_ppm）与系统规模（system_scale_ppm）的槽位。
var staff_slot: PackedInt64Array = PackedInt64Array()
var system_slot: PackedInt64Array = PackedInt64Array()
## R-P12-01：披露门槛、抽查比例、申诉范围的槽位。
var disclosure_slot: PackedInt64Array = PackedInt64Array()
var audit_slot: PackedInt64Array = PackedInt64Array()
var appeal_slot: PackedInt64Array = PackedInt64Array()
## R-P10-01：每季拨款（grant_per_q_uu）的槽位：投运后运行费义务的拨付上限。
var grant_slot: PackedInt64Array = PackedInt64Array()

## spend_lines 的条数（进口设备／国产材料／施工服务），docs/17 §4.8 的 12×3 行宽。
const SPEND_LINE_N: int = 3

# ───────────────── §1.6 状态块协议的注册表 ─────────────────
# 内容包不进 state_hash（进 content_hash，由 JWContentLoader 负责）：
# 本类只实现 allocate() 与 set_state_array()，其余协议方法返回空。

## 本块各数组所属子系统（与 STATE_ARRAY_IDS 等长），用于 subsystem_hash 与 WriteGuard。
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY,
	JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY,
	JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY,
	JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY,
	JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY,
	JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY,
	JWUnits.SUBSYS_POLICY,
]

## 稳定 ID 注册表：下标 == 数组序号，内容是 docs/10 的稳定 ID 字符串。
## 只在加载与哈希时被读，结算期不触碰（无 String 进入热路径）。
const STATE_ARRAY_IDS: PackedStringArray = [
	"content.policy.kind",
	"content.policy.authority_bit",
	"content.policy.min_seats_ppm",
	"content.policy.requires_bloc_mask",
	"content.policy.requires_budget_review",
	"content.policy.cost_one_off_uu",
	"content.policy.cost_per_quarter_uu",
	"content.policy.planned_quarters",
	"content.policy.spend_line_uu",
	"content.policy.opex_per_q_uu",
	"content.policy.required_construction_uqs",
	"content.policy.required_equipment_uqs",
	"content.policy.lag_enact_to_effect_q",
	"content.policy.commission_delay_q",
	"content.policy.effect_kind",
	"content.policy.effect_target",
	"content.policy.effect_magnitude",
	"content.policy.param_min_ppm",
	"content.policy.param_max_ppm",
	"content.policy.param_default",
	"content.policy.cooldown_q",
	"content.policy.toggle_cost_uu",
	"content.policy.exit_compensation_ppm",
	"content.policy.political_reaction",
	"content.policy.mechanism_mask",
]
const STATE_SCALAR_IDS: PackedStringArray = []
const FLOW_ARRAY_IDS: PackedStringArray = []
const FLOW_SCALAR_IDS: PackedStringArray = []

## 每个槽位的契约长度（与 STATE_ARRAY_IDS 等长）。
## 12 == POLICY_N；36 == POLICY_N*3（spend_line）或 POLICY_N*BLOC_N（political_reaction）；
## 48 == POLICY_PARAM_N。长度是 schema 的一部分（INV-136），set_state_array 逐项校验。
const STATE_ARRAY_LEN: PackedInt64Array = [
	12, 12, 12, 12, 12, 12, 12, 12, 36, 12, 12, 12, 12, 12, 12, 12, 12,
	48, 48, 48, 12, 12, 12, 36, 12,
]

# ────────────── 成员变量（SoA，类 = C，写入者 = LOAD） ──────────────

## rate/transfer/subsidy/project/capacity/admin
var kind: PackedInt64Array = PackedInt64Array()
## 法定权限位
var authority_bit: PackedInt64Array = PackedInt64Array()
## 最低席位比例（ppm）
var min_seats_ppm: PackedInt64Array = PackedInt64Array()
## 需要哪些集团不否决（位掩码）
var requires_bloc_mask: PackedInt64Array = PackedInt64Array()
## 0/1
var requires_budget_review: PackedInt64Array = PackedInt64Array()
## μU
var cost_one_off_uu: PackedInt64Array = PackedInt64Array()
## μU
var cost_per_quarter_uu: PackedInt64Array = PackedInt64Array()
## 季
var planned_quarters: PackedInt64Array = PackedInt64Array()
## μU/季，长度 36（12×3：进口设备／国产材料／施工服务），下标 p*3+line
var spend_line_uu: PackedInt64Array = PackedInt64Array()
## μU/季
var opex_per_q_uu: PackedInt64Array = PackedInt64Array()
## μQ_services
var required_construction_uqs: PackedInt64Array = PackedInt64Array()
## μQ_manu
var required_equipment_uqs: PackedInt64Array = PackedInt64Array()
## 季
var lag_enact_to_effect_q: PackedInt64Array = PackedInt64Array()
## 季，>= 1（INV-091）
var commission_delay_q: PackedInt64Array = PackedInt64Array()
## 效果种类码
var effect_kind: PackedInt64Array = PackedInt64Array()
## 效果落点码（白名单内，V-PD-10/11）
var effect_target: PackedInt64Array = PackedInt64Array()
## 按 effect_kind 解释（μQ/季 或 ppm 或 μU）
var effect_magnitude: PackedInt64Array = PackedInt64Array()
## 玩家参数 valid_range 下界，长度 48，下标 JWIds.idx_policy_param(p, j)
var param_min_ppm: PackedInt64Array = PackedInt64Array()
## 玩家参数 valid_range 上界，长度 48
var param_max_ppm: PackedInt64Array = PackedInt64Array()
## 玩家参数默认值，长度 48
var param_default: PackedInt64Array = PackedInt64Array()
## 季
var cooldown_q: PackedInt64Array = PackedInt64Array()
## μU
var toggle_cost_uu: PackedInt64Array = PackedInt64Array()
## ppm
var exit_compensation_ppm: PackedInt64Array = PackedInt64Array()
## ppm，长度 36（12×3 集团），下标 p*BLOC_N+b
var political_reaction: PackedInt64Array = PackedInt64Array()
## 引用的机制位掩码
var mechanism_mask: PackedInt64Array = PackedInt64Array()

# ───────────────────────── 方法 ─────────────────────────

## 机制 ID → 位序号。内容包加载时用来把 mechanism_ids 折成 mechanism_mask。
## 步骤：LOAD
## 前置：!JWIds.frozen（可用字符串）
## 后置：不改状态
## 不变量：INV-099（政策只能引用已注册机制）
## 失败：未注册 → 返回 -1，调用方转 Load.MECH_UNKNOWN
static func mechanism_index(mech_id: String) -> int:
	# 线性查找：表长 37，只在加载期跑一次（每政策 <= 8 条），不值得为它建字典
	# ——结算期不许有 String，字典只会多一份加载期才用得上的常驻结构。
	for i: int in MECHANISM_IDS.size():
		if MECHANISM_IDS[i] == mech_id:
			return i
	return -1


## 效果落点 → 白名单码。
## 步骤：LOAD
## 前置：同上
## 后置：不改状态
## 不变量：INV-091（V-PD-11：只能落在 *_pending_*）
## 失败：不在白名单 → 返回 -1，调用方转 Load.EFFECT_TARGET
static func effect_target_code(target_id: String) -> int:
	# V-PD-11 不需要额外判断：白名单里一切产能／容量／设施项本身就只有 *_pending_* 形态，
	# 落在 *_active_* 上的字符串根本不在表里，查不到即 -1。
	for i: int in EFFECT_TARGETS.size():
		if EFFECT_TARGETS[i] == target_id:
			return i
	return -1


## 读取访问器（结算期只用这些，全是整数下标）。
## 步骤：S02（资格与成本）、S04（转移与补助）、S05（项目）、S07（效果落点）
## 前置：p ∈ [0,12)
## 后置：不改状态
## 不变量：INV-095（效应函数在未生效时返回零效应——判定在 JWPolicyEngine，本类只给数据）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func cost_per_quarter(p: int) -> int:
	if p < 0 or p >= JWUnits.POLICY_N or p >= cost_per_quarter_uu.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, JWUnits.POLICY_N)
		return 0
	return cost_per_quarter_uu[p]


## 读取某政策第 line 条支出线的季度计划额（0 进口设备 / 1 国产材料 / 2 施工服务）。
## 步骤：S02 §2.7（展开分季支出计划）、S04 §4.4（项目履约付款）
## 前置：p ∈ [0,12)，line ∈ [0,3)
## 后置：不改状态
## 不变量：INV-092（Σ spend_plan == total_cost 由调用方在 launch 时保证）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func spend_line(p: int, line: int) -> int:
	if p < 0 or p >= JWUnits.POLICY_N or line < 0 or line >= SPEND_LINE_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, line)
		return 0
	var idx: int = p * SPEND_LINE_N + line
	if idx >= spend_line_uu.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, idx, spend_line_uu.size())
		return 0
	return spend_line_uu[idx]


## 读取玩家参数 j 的合法区间（min, max）。Vector2i 是整数对，不含 float。
## 步骤：S02 §2.1（apply_pending_params 的区间校验）
## 前置：p ∈ [0,12)，j ∈ [0,4)
## 后置：不改状态
## 不变量：INV-138（命令不得携带任何直接状态值）；V-PD-09
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 (0, 0)
func param_range(p: int, j: int) -> Vector2i:
	if p < 0 or p >= JWUnits.POLICY_N or j < 0 or j >= JWIds.POLICY_PARAM_STRIDE:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, j)
		return Vector2i(0, 0)
	var idx: int = JWIds.idx_policy_param(p, j)
	if idx >= param_min_ppm.size() or idx >= param_max_ppm.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, idx, param_min_ppm.size())
		return Vector2i(0, 0)
	return Vector2i(param_min_ppm[idx], param_max_ppm[idx])


## 读取效果落点码。
## 步骤：S07 §7.1 之后（JWPolicyEngine.apply_effects 的分派依据）
## 前置：p ∈ [0,12)
## 后置：不改状态
## 不变量：INV-091（一切能力类只能落在 *_pending_*）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func effect_target_of(p: int) -> int:
	if p < 0 or p >= JWUnits.POLICY_N or p >= effect_target.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, JWUnits.POLICY_N)
		return 0
	return effect_target[p]


## 读取政策 p 对集团 b 的政治反应（ppm）。
## 步骤：S02（表态更新）、S08（政治结算）
## 前置：p ∈ [0,12)，b ∈ [0,3)
## 后置：不改状态
## 不变量：INV-121..128（政治量的界与单调性由 JWPolitics 保证，本类只给数据）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func political_reaction_of(p: int, b: int) -> int:
	if p < 0 or p >= JWUnits.POLICY_N or b < 0 or b >= JWUnits.BLOC_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, b)
		return 0
	var idx: int = p * JWUnits.BLOC_N + b
	if idx >= political_reaction.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, idx, political_reaction.size())
		return 0
	return political_reaction[idx]


## 加载期九项必填与成本一致性校验。
## 步骤：LOAD
## 前置：12 个 JSON 已解析
## 后置：不改状态
## 不变量：INV-099；V-PD-01..11
## 失败：Load.POLICY_COUNT / POLICY_FIELDS / POLICY_COST / COMMISSION_LAG /
##       POLICY_TEST_MISSING / MECH_UNKNOWN / PARAM_RANGE / EFFECT_TARGET
##
## 说明：V-PD-05（capacity_unit_ref 指向真实部门）与 V-PD-06/07（test_id 在测试注册表中存在）
## 校验的是 JSON 层字段，运行时 SoA 里没有对应列，只能由 JWContentLoader 在解析阶段判定；
## 本函数负责 SoA 层能判定的全部条目，**不做「大概齐」的替代判断**。
func validate() -> JWResult:
	# 自检：白名单与具名码表必须同步，否则一切按码分派的逻辑都建立在错位的表上。
	if EFFECT_TARGETS.size() != TARGET_N or TARGET_IS_RATIO.size() != TARGET_N:
		return JWResult.make_err(JWResult.Load.EFFECT_TARGET, EFFECT_TARGETS.size(), TARGET_N)
	if STATE_ARRAY_LEN.size() != STATE_ARRAY_IDS.size():
		return JWResult.make_err(JWResult.Load.POLICY_FIELDS,
				STATE_ARRAY_LEN.size(), STATE_ARRAY_IDS.size())

	# V-PD-01：12 项齐全 —— SoA 层的表达就是每个槽位都恰好是契约长度。
	for i: int in STATE_ARRAY_IDS.size():
		var arr: PackedInt64Array = _array_ref(i)
		if arr.size() != STATE_ARRAY_LEN[i]:
			return JWResult.make_err(JWResult.Load.POLICY_COUNT, i, arr.size())

	for p: int in JWUnits.POLICY_N:
		# V-PD-02：九项必填在 SoA 层的可判定部分（成本、时滞、效果、退出、政治反应）。
		if cost_one_off_uu[p] < 0 or cost_per_quarter_uu[p] < 0 or opex_per_q_uu[p] < 0:
			return JWResult.make_err(JWResult.Load.POLICY_FIELDS, p, cost_one_off_uu[p])
		if planned_quarters[p] < 1:
			return JWResult.make_err(JWResult.Load.POLICY_FIELDS, p, planned_quarters[p])
		if lag_enact_to_effect_q[p] < 0 or cooldown_q[p] < 0 or toggle_cost_uu[p] < 0:
			return JWResult.make_err(JWResult.Load.POLICY_FIELDS, p, lag_enact_to_effect_q[p])
		if kind[p] < 0 or kind[p] >= POLICY_KIND_N:
			return JWResult.make_err(JWResult.Load.POLICY_FIELDS, p, kind[p])
		if exit_compensation_ppm[p] < 0 or exit_compensation_ppm[p] > JWUnits.PPM:
			return JWResult.make_err(JWResult.Load.POLICY_FIELDS, p, exit_compensation_ppm[p])
		if min_seats_ppm[p] < 0 or min_seats_ppm[p] > JWUnits.PPM:
			return JWResult.make_err(JWResult.Load.POLICY_FIELDS, p, min_seats_ppm[p])
		if requires_budget_review[p] < 0 or requires_budget_review[p] > 1:
			return JWResult.make_err(JWResult.Load.POLICY_FIELDS, p, requires_budget_review[p])

		# V-PD-03：per_quarter × planned == one_off，且 Σ spend_lines == per_quarter。
		# 精确相等，加载器不做归一化补偿；这里也不做。
		var total: int = JWMath.mul(cost_per_quarter_uu[p], planned_quarters[p])
		if total != cost_one_off_uu[p]:
			return JWResult.make_err(JWResult.Load.POLICY_COST, p, total)
		var line_sum: int = 0
		for line: int in SPEND_LINE_N:
			var v: int = spend_line_uu[p * SPEND_LINE_N + line]
			if v < 0:
				return JWResult.make_err(JWResult.Load.POLICY_COST, p, v)
			line_sum += v
		if line_sum != cost_per_quarter_uu[p]:
			return JWResult.make_err(JWResult.Load.POLICY_COST, p, line_sum)

		# V-PD-04：commission_delay_q >= 1（INV-091 的加载期防线）。
		if commission_delay_q[p] < 1:
			return JWResult.make_err(JWResult.Load.COMMISSION_LAG, p, commission_delay_q[p])

		# V-PD-08：mechanism_ids 非空，且每个 ID 都已注册。
		# 未注册的 ID 在 mechanism_index() 处就返回 -1，折不进掩码，所以到这里只需判非空
		# 与位宽越界（高位被置 1 说明加载器折进了一个不存在的机制）。
		if mechanism_mask[p] == 0:
			return JWResult.make_err(JWResult.Load.MECH_UNKNOWN, p, 0)
		if mechanism_mask[p] < 0 or mechanism_mask[p] >= (1 << MECHANISM_IDS.size()):
			return JWResult.make_err(JWResult.Load.MECH_UNKNOWN, p, mechanism_mask[p])

		# V-PD-10 / V-PD-11：effect.target 在白名单内。
		if effect_target[p] < 0 or effect_target[p] >= TARGET_N:
			return JWResult.make_err(JWResult.Load.EFFECT_TARGET, p, effect_target[p])

		# 项目类政策的施工量必须为正，否则 S05 的 Δconstruction 会除零（INV-088）。
		if kind[p] == POLICY_KIND_PROJECT and required_construction_uqs[p] <= 0:
			return JWResult.make_err(JWResult.Load.POLICY_FIELDS, p, required_construction_uqs[p])
		if required_construction_uqs[p] < 0 or required_equipment_uqs[p] < 0:
			return JWResult.make_err(JWResult.Load.POLICY_FIELDS, p, required_construction_uqs[p])

		# V-PD-09：每个玩家参数项 default ∈ [min, max]，且区间本身不倒挂。
		for j: int in JWIds.POLICY_PARAM_STRIDE:
			var idx: int = JWIds.idx_policy_param(p, j)
			if param_min_ppm[idx] > param_max_ppm[idx]:
				return JWResult.make_err(JWResult.Reject.PARAM_RANGE, idx, param_min_ppm[idx])
			if param_default[idx] < param_min_ppm[idx] or param_default[idx] > param_max_ppm[idx]:
				return JWResult.make_err(JWResult.Reject.PARAM_RANGE, idx, param_default[idx])

		# 政治反应的界（ppm，可正可负）。
		for b: int in JWUnits.BLOC_N:
			var reaction: int = political_reaction[p * JWUnits.BLOC_N + b]
			if reaction < -JWUnits.PPM or reaction > JWUnits.PPM:
				return JWResult.make_err(JWResult.Load.POLICY_FIELDS, p, reaction)

	return JWResult.make_ok()


## 槽位号 → 成员数组引用（只在加载与校验期用）。
## 步骤：LOAD
## 前置：i ∈ [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136（下标顺序是 schema 的一部分）
## 失败：越界 → 返回空数组
func _array_ref(i: int) -> PackedInt64Array:
	match i:
		0: return kind
		1: return authority_bit
		2: return min_seats_ppm
		3: return requires_bloc_mask
		4: return requires_budget_review
		5: return cost_one_off_uu
		6: return cost_per_quarter_uu
		7: return planned_quarters
		8: return spend_line_uu
		9: return opex_per_q_uu
		10: return required_construction_uqs
		11: return required_equipment_uqs
		12: return lag_enact_to_effect_q
		13: return commission_delay_q
		14: return effect_kind
		15: return effect_target
		16: return effect_magnitude
		17: return param_min_ppm
		18: return param_max_ppm
		19: return param_default
		20: return cooldown_q
		21: return toggle_cost_uu
		22: return exit_compensation_ppm
		23: return political_reaction
		24: return mechanism_mask
	return PackedInt64Array()


# ───────────── §1.6 状态块协议（只实现 allocate 与 set_state_array） ─────────────

## LOAD 期一次性 resize 到 §2.1 的契约长度。
## 步骤：LOAD
## 前置：尚未填充任何内容
## 后置：全部 SoA 数组长度等于契约长度（12 / 36 / 48）且清零
## 不变量：INV-136（数组下标顺序是 schema 的一部分）
## 失败：无
func allocate() -> void:
	var n: int = JWUnits.POLICY_N
	var n3: int = JWUnits.POLICY_N * SPEND_LINE_N
	var np: int = JWUnits.POLICY_PARAM_N
	var nb: int = JWUnits.POLICY_N * JWUnits.BLOC_N
	kind.resize(n)
	kind.fill(0)
	# PackedInt64Array 是值类型：必须逐个成员 resize，不能在数组字面量上循环（那改的是副本）。
	mask_slot.resize(n)
	mask_slot.fill(-1)
	rate_slot.resize(n)
	rate_slot.fill(-1)
	cap_slot.resize(n)
	cap_slot.fill(-1)
	min_ratio_slot.resize(n)
	min_ratio_slot.fill(-1)
	qty_slot.resize(n)
	qty_slot.fill(-1)
	track_slot.resize(n)
	track_slot.fill(-1)
	staff_slot.resize(n)
	staff_slot.fill(-1)
	system_slot.resize(n)
	system_slot.fill(-1)
	disclosure_slot.resize(n)
	disclosure_slot.fill(-1)
	audit_slot.resize(n)
	audit_slot.fill(-1)
	appeal_slot.resize(n)
	appeal_slot.fill(-1)
	grant_slot.resize(n)
	grant_slot.fill(-1)
	authority_bit.resize(n)
	authority_bit.fill(0)
	min_seats_ppm.resize(n)
	min_seats_ppm.fill(0)
	requires_bloc_mask.resize(n)
	requires_bloc_mask.fill(0)
	requires_budget_review.resize(n)
	requires_budget_review.fill(0)
	cost_one_off_uu.resize(n)
	cost_one_off_uu.fill(0)
	cost_per_quarter_uu.resize(n)
	cost_per_quarter_uu.fill(0)
	planned_quarters.resize(n)
	# 计划工期的下界是 1（V-PD-03 的 per_quarter × planned == one_off 在 0 期时恒成立，
	# 会把「没填工期」伪装成合法），所以初值取 1 而不是 0。
	planned_quarters.fill(1)
	spend_line_uu.resize(n3)
	spend_line_uu.fill(0)
	opex_per_q_uu.resize(n)
	opex_per_q_uu.fill(0)
	required_construction_uqs.resize(n)
	required_construction_uqs.fill(0)
	required_equipment_uqs.resize(n)
	required_equipment_uqs.fill(0)
	lag_enact_to_effect_q.resize(n)
	lag_enact_to_effect_q.fill(0)
	commission_delay_q.resize(n)
	# INV-091：投运至少滞后一季，初值即下界。
	commission_delay_q.fill(1)
	effect_kind.resize(n)
	effect_kind.fill(0)
	effect_target.resize(n)
	effect_target.fill(0)
	effect_magnitude.resize(n)
	effect_magnitude.fill(0)
	param_min_ppm.resize(np)
	param_min_ppm.fill(0)
	param_max_ppm.resize(np)
	param_max_ppm.fill(0)
	param_default.resize(np)
	param_default.fill(0)
	cooldown_q.resize(n)
	cooldown_q.fill(0)
	toggle_cost_uu.resize(n)
	toggle_cost_uu.fill(0)
	exit_compensation_ppm.resize(n)
	exit_compensation_ppm.fill(0)
	political_reaction.resize(nb)
	political_reaction.fill(0)
	mechanism_mask.resize(n)
	mechanism_mask.fill(0)


## 只读取用（返回引用，调用方不得写）。
## 步骤：LOAD / 深拷贝 / 指标读取
## 前置：i ∈ [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：docs/17 §4.8（内容包进 content_hash 而非 state_hash）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
##
## 返回真数组。「内容包不进 state_hash / 不入档」由 JWSimState 按稳定 ID 前缀 `content.` 统一排除
## （HASH_EXCLUDED_PREFIXES / SAVE_EXCLUDED_PREFIXES），不需要也不应该靠这里交空数组来实现：
## 空数组会让 duplicate_state()（情景预测的副本）把 12 项政策定义全部复制成 0 长度——
## set_state_array 按契约长度拒收，副本停在 allocate() 的全零定义上，预测跑的是另一套政策；
## 注册表的 content.policy.* 条目也因此读不出任何元素（事件 metric 同样读不到）。
func state_array(i: int) -> PackedInt64Array:
	if i < 0 or i >= STATE_ARRAY_IDS.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
		return PackedInt64Array()
	return _array_ref(i)


## 仅 LOAD / MIG：由 JWContentLoader 把解析好的数组装进对应槽位。
## 步骤：LOAD
## 前置：i ∈ [0, STATE_ARRAY_IDS.size())；v 的长度等于该槽位的契约长度
## 后置：对应成员数组 == v
## 不变量：INV-136
## 失败：下标或长度不符 → 返回 Load.POLICY_FIELDS
func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i < 0 or i >= STATE_ARRAY_IDS.size():
		return JWResult.Load.POLICY_FIELDS
	if v.size() != STATE_ARRAY_LEN[i]:
		return JWResult.Load.POLICY_FIELDS
	match i:
		0: kind = v
		1: authority_bit = v
		2: min_seats_ppm = v
		3: requires_bloc_mask = v
		4: requires_budget_review = v
		5: cost_one_off_uu = v
		6: cost_per_quarter_uu = v
		7: planned_quarters = v
		8: spend_line_uu = v
		9: opex_per_q_uu = v
		10: required_construction_uqs = v
		11: required_equipment_uqs = v
		12: lag_enact_to_effect_q = v
		13: commission_delay_q = v
		14: effect_kind = v
		15: effect_target = v
		16: effect_magnitude = v
		17: param_min_ppm = v
		18: param_max_ppm = v
		19: param_default = v
		20: cooldown_q = v
		21: toggle_cost_uu = v
		22: exit_compensation_ppm = v
		23: political_reaction = v
		24: mechanism_mask = v
		_: return JWResult.Load.POLICY_FIELDS
	return JWResult.OK


## 内容包无标量状态项。
## 步骤：LOAD
## 前置：无
## 后置：不改状态
## 不变量：docs/17 §4.8
## 失败：无
func state_scalar(i: int) -> int:
	return 0


## 内容包无标量状态项。
## 步骤：LOAD
## 前置：无
## 后置：不改状态
## 不变量：docs/17 §4.8
## 失败：无
func set_state_scalar(i: int, v: int) -> int:
	return JWResult.OK


## 内容包无流量项。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：docs/12 §01.3（流量注册表整表清零）
## 失败：无
func flow_array(i: int) -> PackedInt64Array:
	return PackedInt64Array()


## 内容包无流量项。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：docs/12 §01.3
## 失败：无
func flow_scalar(i: int) -> int:
	return 0


## 仅 S01；本类无流量，空实现。
## 步骤：S01 §01.3
## 前置：无
## 后置：不改状态
## 不变量：docs/12 §01.3
## 失败：无
func reset_flows() -> void:
	# 内容包是常量，没有任何流量项可清——这不是遗漏，是 C 类数据的定义。
	pass


## S01 清零后的自检，非 0 即 FLOW_NOT_RESET。本类无流量，恒 0。
## 步骤：S01 §01.3
## 前置：reset_flows() 已执行
## 后置：不改状态
## 不变量：docs/12 §01.3
## 失败：无
func flow_abs_sum() -> int:
	return 0
