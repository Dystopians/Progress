## 36 个群组的人口守恒、出生／死亡／成年／退休／技能队列，以及群组的收入、消费、
## 储蓄、住房与民生指数（docs/10 §6）。
##
## 不含四个主观量（生活／预期／信任／支持）——那四个由 JWPolitics 持有（INV-121 的结构性落地）。
## 群组现金与存款余额在 JWAccount，本类只持有「非余额」的人口与流量字段。
##
## 骨架依据：docs/17_api_skeleton.md §4.14。
class_name JWPopulation
extends RefCounted

## 本块各数组所属子系统（与 STATE_ARRAY_IDS 等长），用于 subsystem_hash 与 WriteGuard。
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_GROUP, JWUnits.SUBSYS_GROUP, JWUnits.SUBSYS_GROUP, JWUnits.SUBSYS_GROUP,
	JWUnits.SUBSYS_GROUP, JWUnits.SUBSYS_GROUP, JWUnits.SUBSYS_GROUP,
	JWUnits.SUBSYS_GROUP, JWUnits.SUBSYS_GROUP,
]

## 稳定 ID 注册表：下标 == 数组序号，内容是 docs/10 的稳定 ID 字符串。
## 只在加载与哈希时被读，结算期不触碰（无 String 进入热路径）。
const STATE_ARRAY_IDS: PackedStringArray = [
	"state.group.population_persons",
	"state.group.participation_ppm",
	"state.group.employed_persons",
	"state.group.education_cohort_persons",
	"state.group.housing_units_occupied",
	"state.group.service_access_ppm",
	"state.group.consumption_index_ppm",
	# R-CONS-01：两项跨季量（上季末写、下季读），必须进存档与状态哈希。
	"state.group.disposable_prev_uu",
	"state.group.nonlabor_net_prev_uu",
]

## 与 STATE_ARRAY_IDS 等长的契约长度表（docs/17 §4.14 的成员表）。
const STATE_ARRAY_LEN: PackedInt64Array = [
	JWUnits.GROUP, JWUnits.GROUP, JWUnits.GROUP_EMP_N, JWUnits.EDU_N,
	JWUnits.GROUP, JWUnits.GROUP_SVC_N, JWUnits.GROUP,
	JWUnits.GROUP, JWUnits.GROUP,
]

const STATE_SCALAR_IDS: PackedStringArray = []

## 内容表（C 类）的稳定 ID，下标从 STATE_ARRAY_IDS.size() 起算，经 set_state_array() 写入。
## 与 JWMigration 同一约定：内容表不进 state_hash，但需要一条 LOAD 期的写入通路。
const CONTENT_ARRAY_IDS: PackedStringArray = [
	"content.demography.birth_ppm",
	"content.demography.death_ppm",
	"content.demography.age_out_ppm",
	"content.demography.support_out_weight_ppm",
	"content.base_per_capita_real_income_uu",
	"content.base_real_consumption_uqs",
	"content.base_delivered_service",
	"content.cells_init.equity_share_ppm",
]

## 与 CONTENT_ARRAY_IDS 等长的契约长度表。
const CONTENT_ARRAY_LEN: PackedInt64Array = [
	JWUnits.R, JWUnits.GROUP, JWUnits.A, JWUnits.GROUP,
	JWUnits.GROUP, JWUnits.GROUP, JWUnits.GROUP_SVC_N, JWUnits.CELL * JWUnits.GROUP,
]

const FLOW_ARRAY_IDS: PackedStringArray = [
	"flow.group.births_persons",
	"flow.group.deaths_persons",
	"flow.group.age_in_persons",
	"flow.group.age_out_persons",
	"flow.group.skill_in_persons",
	"flow.group.skill_out_persons",
	"flow.group.migrate_rejected_persons",
	"flow.group.wage_income_uu",
	"flow.group.transfer_income_uu",
	"flow.group.support_in_uu",
	"flow.group.support_out_uu",
	"flow.group.property_income_uu",
	"flow.group.income_tax_paid_uu",
	"flow.group.consumption_uu",
	"flow.group.consumption_by_product_uu",
	"flow.group.consumption_by_product_uqs",
	"flow.group.housing_cost_uu",
	"flow.group.unmet_consumption_uu",
	"flow.group.savings_uu",
	"flow.group.fees_paid_uu",
]

const FLOW_SCALAR_IDS: PackedStringArray = []

## 同一地区的受养组数（minor 3 档 + elder 3 档），pay_household_support 的定长拆分宽度。
const DEPENDENT_PER_REGION: int = 6

# ── 来源操作码（log.ledger.cause）与取整登记点码（log.rounding.site_code） ────
#
# 首版没有中央的 cause／site 码注册表（docs/10 §2.5 只规定了列，没有规定码）。
# 这里用本模块自有的号段 1400+，在注册表建立前保持稳定；已在 interface_requests 登记。

## 组间赡养转移（S04 §4.5）
const CAUSE_HOUSEHOLD_SUPPORT: int = 1401
## 企业可分配利润分回群组（S06 §6.7）
const CAUSE_PROPERTY_DISTRIBUTION: int = 1402
## 投资池存款利息分回群组（S06 §6.7）
const CAUSE_DEPOSIT_INTEREST: int = 1403
## 储蓄的存款腿（群组 → 投资池）
const CAUSE_DEPOSIT_PLACE: int = 1404
## 负储蓄的取款腿（投资池 → 群组）
const CAUSE_DEPOSIT_WITHDRAW: int = 1405

## 赡养付出额被付出方现金上限缩减
const SITE_SUPPORT_CASH_CAPPED: int = 1411
## 本地区没有受养人口，赡养额原样交回
const SITE_SUPPORT_NO_DEPENDENT: int = 1412
## 企业分配额被企业现金上限缩减
const SITE_DISTRIBUTION_CASH_CAPPED: int = 1413
## 该 cell 的股权份额全为 0，可分配额无处可分
const SITE_DISTRIBUTION_NO_EQUITY: int = 1414
## 利息分配额被投资池现金上限缩减
const SITE_INTEREST_CASH_CAPPED: int = 1415
## 全部群组存款为 0，利息无处可分
const SITE_INTEREST_NO_DEPOSIT: int = 1416
## 培训申请席位被 teachers × student_teacher_ratio 的上限截断
const SITE_EDU_SEATS_CAPPED: int = 1417
## 结业人数超过该组当前人口，超出部分留在队列
const SITE_EDU_GRADUATE_CAPPED: int = 1418
## 取款额被投资池现金或自身债权上限缩减
const SITE_DEPOSIT_WITHDRAW_CAPPED: int = 1419

# ── 状态（S 类，进 state_hash） ────────────────────────────────────────────────

## state.group.population_persons[]，36，人。写入者 S07。
var population: PackedInt64Array = PackedInt64Array()
## state.group.participation_ppm[]，36，ppm（非 working 组必须 0）。写入者 S07。
var participation_ppm: PackedInt64Array = PackedInt64Array()
## state.group.employed_persons[]，180（GROUP × 5 槽位）。人。
## 写入者 S03（由 JWLaborMarket 回写）与 S07（流出配对，见 apply_employment_cut）。
var employed: PackedInt64Array = PackedInt64Array()
## state.group.education_cohort_persons[]，288（GROUP × EDU_SLOT），人。写入者 S07。
var education_cohort: PackedInt64Array = PackedInt64Array()
## state.group.housing_units_occupied[]，36，套。写入者 S07。
var housing_occupied: PackedInt64Array = PackedInt64Array()
## state.group.service_access_ppm[]，108（GROUP × SERVICE_KIND），ppm。写入者 S07。
var service_access: PackedInt64Array = PackedInt64Array()
## state.group.consumption_index_ppm[]，36，ppm，初值 1 000 000。写入者 S07。
var consumption_index: PackedInt64Array = PackedInt64Array()

# ── 流量（F 类，每季 S01 清零） ───────────────────────────────────────────────

## flow.group.births_persons[]，36，人。写入者 S07。
var f_births: PackedInt64Array = PackedInt64Array()
## flow.group.deaths_persons[]，36，人。写入者 S07。
var f_deaths: PackedInt64Array = PackedInt64Array()
## flow.group.age_in_persons[]，36，人。写入者 S07。
var f_age_in: PackedInt64Array = PackedInt64Array()
## flow.group.age_out_persons[]，36，人。写入者 S07。
var f_age_out: PackedInt64Array = PackedInt64Array()
## flow.group.skill_in_persons[]，36，人。写入者 S07。
var f_skill_in: PackedInt64Array = PackedInt64Array()
## flow.group.skill_out_persons[]，36，人。写入者 S07。
var f_skill_out: PackedInt64Array = PackedInt64Array()
## flow.group.migrate_rejected_persons[]，36，人。写入者 S07（由 JWMigration 写）。
var f_migrate_rejected: PackedInt64Array = PackedInt64Array()
## flow.group.wage_income_uu[]，36，μU。写入者 S04。
var f_wage_income: PackedInt64Array = PackedInt64Array()
## flow.group.transfer_income_uu[]，36，μU。写入者 S04。
var f_transfer_income: PackedInt64Array = PackedInt64Array()
## flow.group.support_in_uu[]，36，μU。写入者 S04。
var f_support_in: PackedInt64Array = PackedInt64Array()
## flow.group.support_out_uu[]，36，μU。写入者 S04。
var f_support_out: PackedInt64Array = PackedInt64Array()
## flow.group.property_income_uu[]，36，μU。写入者 S06。
var f_property_income: PackedInt64Array = PackedInt64Array()
## flow.group.income_tax_paid_uu[]，36，μU。写入者 S06。
var f_income_tax_paid: PackedInt64Array = PackedInt64Array()
## flow.group.consumption_uu[]，36，μU。写入者 S05。
var f_consumption: PackedInt64Array = PackedInt64Array()
## flow.group.consumption_by_product_uu[]，144（GROUP × S），μU。写入者 S05。
var f_consumption_by_product_uu: PackedInt64Array = PackedInt64Array()
## flow.group.consumption_by_product_uqs[]，144（GROUP × S），μQ_s。写入者 S05。
var f_consumption_by_product_uqs: PackedInt64Array = PackedInt64Array()
## flow.group.housing_cost_uu[]，36，μU。写入者 S05。
var f_housing_cost: PackedInt64Array = PackedInt64Array()
## flow.group.unmet_consumption_uu[]，36，μU。写入者 S05。
var f_unmet_consumption: PackedInt64Array = PackedInt64Array()
## flow.group.savings_uu[]，36，μU（可为负）。写入者 S06。
var f_savings: PackedInt64Array = PackedInt64Array()

# ── 内容（C 类，LOAD 期写入，运行期只读） ─────────────────────────────────────

## content.demography.birth_ppm[]，4（按地区），ppm。写入者 LOAD。
var birth_ppm: PackedInt64Array = PackedInt64Array()
## content.demography.death_ppm[]，36，ppm。写入者 LOAD。
var death_ppm: PackedInt64Array = PackedInt64Array()
## content.demography.age_out_ppm[]，3（按年龄档），ppm。写入者 LOAD。
var age_out_ppm: PackedInt64Array = PackedInt64Array()
## content.demography.support_out_weight_ppm[]，36，ppm。写入者 LOAD。
var support_out_weight_ppm: PackedInt64Array = PackedInt64Array()
## content.base_per_capita_real_income_uu[]，36，μU。写入者 LOAD。
var base_real_income: PackedInt64Array = PackedInt64Array()
## content.base_real_consumption_uqs[]，36，μQ。写入者 LOAD。
var base_real_cons: PackedInt64Array = PackedInt64Array()
## content.base_delivered_service[]，108，μQ。写入者 LOAD。
var base_delivered_service: PackedInt64Array = PackedInt64Array()
## content.cells_init.equity_share_ppm[]，576（16 cell × 36 组），ppm。写入者 LOAD。
var equity_share_ppm: PackedInt64Array = PackedInt64Array()

# ── 内部快照与缓冲（不进 state_hash；热路径不分配） ───────────────────────────

## 36，人。S07 入口快照，供 INV-072 的逐组来源去向核对。
var _population_prev: PackedInt64Array = PackedInt64Array()
## 36，人。本季迁出汇总，由 JWMigration 经 record_migration_out() 登记（§7.7 的 outflow 需要它）。
var _migrate_out: PackedInt64Array = PackedInt64Array()
## 36，μU。上季（S06 末）的可支配收入，S04 §4.5 的赡养池基数。
var _disposable_prev: PackedInt64Array = PackedInt64Array()
## state.group.nonlabor_net_prev_uu —— 36，μU（可负）。上季「财产收入 − 个税 − 公共服务收费」（R-CONS-01）。
## 本季 S05 消费预算的一项：财产收入在 S06 才到账、个税在 S06 才扣，同季的预算看不见它们，
## 只能以上季实现值进入。开局为 0（第 0 季没有上季）。
var _nonlabor_prev: PackedInt64Array = PackedInt64Array()
## flow.group.fees_paid_uu[] —— 36，μU。本季缴纳的公共服务收费（R-FEE-01），可支配收入的扣减项。
var f_fees_paid: PackedInt64Array = PackedInt64Array()
## 36，μU。本季起点的 cash + deposit_claim 快照，INV-086 的 Δ 核对基准。
var _balance_start: PackedInt64Array = PackedInt64Array()
## 本季是否已取过 _balance_start 快照（未取时 INV-086 只做定义式自检，见 settle_income_and_savings）。
var _balance_start_valid: bool = false

## 定长拆分 scratch：同地区受养组（6）
var _sc_dep_group: PackedInt64Array = PackedInt64Array()
var _sc_dep_w: PackedInt64Array = PackedInt64Array()
var _sc_dep_tb: PackedInt64Array = PackedInt64Array()
var _sc_dep_out: PackedInt64Array = PackedInt64Array()
## 定长拆分 scratch：4 个产品（恩格尔权重）
var _sc_prod_w: PackedInt64Array = PackedInt64Array()
var _sc_prod_tb: PackedInt64Array = PackedInt64Array()
var _sc_prod_out: PackedInt64Array = PackedInt64Array()
## 定长拆分 scratch：36 个群组（股权份额、存款份额、教育席位）
var _sc_grp_w: PackedInt64Array = PackedInt64Array()
var _sc_grp_tb: PackedInt64Array = PackedInt64Array()
var _sc_grp_out: PackedInt64Array = PackedInt64Array()
## 定长多腿过账 scratch：存款双边 4 腿
var _sc_legs_acc: PackedInt64Array = PackedInt64Array()
var _sc_legs_delta: PackedInt64Array = PackedInt64Array()
## 36，μU。本季 savings 的中转缓冲（存款腿在全部收入落账后统一执行）
var _sc_savings: PackedInt64Array = PackedInt64Array()
## 最近一次 update_education() 被上限截掉的席位数（ADV-03 的可观测量，不进 state_hash）
var _edu_seats_clamped: int = 0


## 读取一个数值参数（params 下标即 JWUnits.Param）。
## 步骤：全部
## 前置：0 <= idx < params.size()
## 后置：不改状态
## 不变量：INV-007
## 失败：越界 → raise_fault(INDEX_OUT_OF_RANGE) 返回 0（调用方据此走零效应路径）
func _param_of(params: PackedInt64Array, idx: int) -> int:
	if idx < 0 or idx >= params.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, idx, params.size())
		return 0
	return params[idx]


## 群组下标合法性检查。
## 步骤：全部
## 前置：无
## 后置：不改状态
## 不变量：—
## 失败：越界 → raise_fault(INDEX_OUT_OF_RANGE) 返回 false
func _group_ok(g: int) -> bool:
	if g < 0 or g >= JWUnits.GROUP:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, g, JWUnits.GROUP)
		return false
	return true


## 把 n 个人从 g_from 配对转移到 g_to，并写指定的一对流量数组。
## 一切人口移动（成年、退休、技能升档）都经本函数，保证「有来源必有去向」（INV-072）。
## 步骤：S07 §7.4 / §7.6
## 前置：0 <= n <= population[g_from]；g_from != g_to
## 后置：population 两侧等量增减；out_flow[g_from] 与 in_flow[g_to] 等量增加
## 不变量：INV-071（转移不产生净流入或净流出）、INV-072、INV-074、INV-082
## 失败：人数为负或超过来源人口 → raise_fault(POPULATION_NOT_CONSERVED) 返回 0；否则返回实际转移人数
func _move_paired(g_from: int, g_to: int, n: int,
		out_flow: PackedInt64Array, in_flow: PackedInt64Array) -> int:
	if n <= 0:
		return 0
	if g_from == g_to:
		JWResult.raise_fault(JWResult.Fault.POPULATION_NOT_CONSERVED, g_from, n)
		return 0
	if n > population[g_from]:
		# 前置破裂：不静默截断，登记故障后按现有人口转移，保证账面仍然守恒。
		JWResult.raise_fault(JWResult.Fault.POPULATION_NOT_CONSERVED, g_from,
				n - population[g_from])
		n = population[g_from]
		if n <= 0:
			return 0
	population[g_from] = population[g_from] - n
	population[g_to] = population[g_to] + n
	out_flow[g_from] = out_flow[g_from] + n
	in_flow[g_to] = in_flow[g_to] + n
	return n


## 劳动力（纯函数，INV-075 的分母）。非 working 组恒返回 0。
## 步骤：S03 §3.4、S07 迁移
## 前置：participation_ppm[g] == 0 当 age != working
## 后置：不改状态
## 不变量：INV-074, INV-075
## 失败：无
func labor_force(g: int) -> int:
	if not _group_ok(g):
		return 0
	# INV-074：非 working 组的参与率必须是 0，这里再挡一次，不依赖数据正确。
	if JWIds.AGE_OF_GROUP[g] != JWUnits.Age.WORKING:
		return 0
	# rounding: floor, reason=INV-075 的定义式 idiv_floor(pop × participation_ppm, 1e6)
	return JWMath.mul_ppm(population[g], participation_ppm[g])


## 某（地区，技能）的劳动力合计（对 3 个年龄档求和，实际只有 working 档非零）。
## 步骤：S03 §3.4、S07 迁移
## 前置：participation_ppm[g] == 0 当 age != working
## 后置：不改状态
## 不变量：INV-074, INV-075
## 失败：无
func labor_force_region_skill(r: int, k: int) -> int:
	if r < 0 or r >= JWUnits.R or k < 0 or k >= JWUnits.K:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, r, k)
		return 0
	var acc: int = 0
	for a: int in JWUnits.A:
		acc += labor_force(JWIds.idx_group(r, a, k))
	return acc


## 某组在全部 5 个就业槽位（4 部门 + pubserv）上的在岗人数合计。
## 步骤：S03 §3.4、S04 §4.1、S07 §7.7
## 前置：employed 已由 S03 写定
## 后置：不改状态
## 不变量：INV-076, INV-077
## 失败：无
func employed_total(g: int) -> int:
	if not _group_ok(g):
		return 0
	var acc: int = 0
	for slot: int in (JWUnits.S + 1):
		acc += employed[JWIds.idx_group_emp(g, slot)]
	return acc


## 地区人口（S07 §7.9 的排放暴露与迁移推力输入）。
## 步骤：S07 §7.9
## 前置：本季人口流动已完成
## 后置：不改状态
## 不变量：INV-071, INV-072
## 失败：无
func region_population(r: int) -> int:
	if r < 0 or r >= JWUnits.R:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, r, JWUnits.R)
		return 0
	var acc: int = 0
	for a: int in JWUnits.A:
		for k: int in JWUnits.K:
			acc += population[JWIds.idx_group(r, a, k)]
	return acc


## 全国人口（INV-071 的守恒口径）。
## 步骤：S07 §7.4
## 前置：本季人口流动已完成
## 后置：不改状态
## 不变量：INV-071
## 失败：无
func nation_population() -> int:
	return JWMath.sum(population)


## S04 §4.5：组间赡养转移（未成年与老年组的消费资金来源）。
## 步骤：S04 §4.5
## 前置：pool 来自 working 组上季可支配收入 × support_out_weight_ppm；默认只在同地区内发生（OQ-208）
## 后置：Σ support_in == Σ support_out 精确成立；逐笔 post(kind=HOUSEHOLD_SUPPORT)
## 不变量：INV-085、INV-003（按人口权重用 split_lr 拆分）
## 失败：拆分和不等 → Fault.SPLIT_MISMATCH；付出方现金不足 → 缩减该组付出额并记 log.rounding
func pay_household_support(ledger: JWLedger, accounts: JWAccount, params: PackedInt64Array) -> int:
	if ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, JWUnits.Phase.S04, 0)
	# params 目前不参与本式（赡养权重是内容表 support_out_weight_ppm，不是参数卡）；
	# 形参保留是为了签名稳定（docs/17 §4.14），这里显式读一次做存在性自检。
	if params.size() < JWUnits.PARAM_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, params.size(), JWUnits.PARAM_N)
	for r: int in JWUnits.R:
		# 受养组：同地区的 minor 与 elder 共 6 组，权重 == 人口（docs/12 §4.5）
		var j: int = 0
		for a: int in JWUnits.A:
			if a == JWUnits.Age.WORKING:
				continue
			for k: int in JWUnits.K:
				var gd: int = JWIds.idx_group(r, a, k)
				_sc_dep_group[j] = gd
				_sc_dep_w[j] = population[gd]
				_sc_dep_tb[j] = gd
				j += 1
		for k2: int in JWUnits.K:
			var g: int = JWIds.idx_group(r, JWUnits.Age.WORKING, k2)
			# rounding: floor, reason=M1，上季可支配收入按 support_out_weight_ppm 缩放只取整一次
			var want: int = JWMath.mul_ppm(_disposable_prev[g], support_out_weight_ppm[g])
			if want <= 0:
				continue
			JWMath.check_amount(want)
			var pay: int = want
			var cash: int = accounts.cash_of(JWIds.agent_of_group(g))
			if pay > cash:
				# 付出方现金不足：缩减该组付出额并登记（docs/17 §4.14），不欠账、不透支。
				pay = maxi(cash, 0)
				ledger.log_rounding(SITE_SUPPORT_CASH_CAPPED, want, pay, want - pay)
			if pay <= 0:
				continue
			var residual: int = JWMath.split_lr_into(pay, _sc_dep_w, _sc_dep_tb, _sc_dep_out)
			if JWMath._split_last_fault != 0:
				return JWMath._split_last_fault
			if residual != 0:
				# 本地区没有受养人口：原额交回付出方（不过账），残差显式登记（split_lr_into 的契约）。
				ledger.log_rounding(SITE_SUPPORT_NO_DEPENDENT, pay, 0, residual)
				continue
			var paid: int = 0
			for j2: int in DEPENDENT_PER_REGION:
				var amt: int = _sc_dep_out[j2]
				if amt <= 0:
					continue
				var gd2: int = _sc_dep_group[j2]
				var rc: int = ledger.post(JWUnits.Kind.HOUSEHOLD_SUPPORT,
						JWIds.idx_account(JWIds.agent_of_group(g), JWIds.ACC_CASH),
						JWIds.idx_account(JWIds.agent_of_group(gd2), JWIds.ACC_CASH),
						amt, 0, -1, CAUSE_HOUSEHOLD_SUPPORT, g)
				if rc != 0:
					return rc
				f_support_in[gd2] = f_support_in[gd2] + amt
				paid += amt
			f_support_out[g] = f_support_out[g] + paid
	# INV-085：双边精确相等，逐季检查（不是「一般成立」）。
	var sum_in: int = JWMath.sum(f_support_in)
	var sum_out: int = JWMath.sum(f_support_out)
	if sum_in != sum_out:
		return JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, sum_out, sum_in)
	return 0


## S04 §4.2：登记法定转移的**实付额**为居民转移收入（与公职工资的 record_public_wage_paid 对称）。
## 步骤：S04 §4.2（pay_line 之后）
## 前置：paid 是 treasury 对该组的实付额（欠付部分不计入——不能把未收到的钱算作收入）
## 后置：f_transfer_income[g] += paid
## 不变量：INV-086（Δcash + Δdeposit == savings 逐组精确；漏登这一笔即现金凭空多出 paid）
## 失败：越界 / 负额 → Fault
func record_transfer_paid(g: int, paid: int) -> int:
	if not _group_ok(g):
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, g, JWUnits.GROUP)
	if paid < 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, g, paid)
	f_transfer_income[g] = JWMath.check_amount(f_transfer_income[g] + paid)
	return JWResult.OK


## R-CONS-01 补遗：开局（第 0 季、尚未推进）给「上季可支配收入」一个基年估计 = 本组基年工资收入
## （在岗人数 × 本技能工资率），使赡养转移从第 0 季起就按常态运转。
## 否则赡养流量第 1 季才出现：劳动组的生活指数在第 0→1 季无故跌约三成、受养组猛涨，
## 支持度基准（R-SUPPORT-02 锚定在第 0 季）就锚在一个不存在的状态上。
## 步骤：LOAD（JWSimState.finalize_load，仅当 q == 0）
## 前置：employed 与工资率已载入
## 后置：_disposable_prev[g] = Σ_去向 employed[g, 去向] × wage_of(skill(g))
## 不变量：INV-133（读档：q == 0 的存档与新开局同样播种；q > 0 的存档不动，读回存档值）
## 失败：无
func seed_disposable_prev(pricing: JWPricing) -> void:
	if pricing == null:
		return
	for g: int in JWUnits.GROUP:
		var wage: int = pricing.wage_of(JWIds.skill_of_group(g))
		var emp: int = 0
		for slot: int in JWUnits.S + 1:
			emp += employed[JWIds.idx_group_emp(g, slot)]
		_disposable_prev[g] = JWMath.check_amount(JWMath.mul(emp, wage))


## R-FEE-01：登记本季缴纳的公共服务收费（已由 JWTurnRunner 过账 PUBLIC_FEE）。
## 步骤：S06（个税之后、储蓄之前）
## 前置：amount >= 0，且已过账
## 后置：f_fees_paid[g] 增加（可支配收入同额减少，与 INV-086 的 Δcash 对应）
## 不变量：INV-086
## 失败：越界 / 负额 → Fault
func record_fee_paid(g: int, amount: int) -> int:
	if not _group_ok(g):
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, g, JWUnits.GROUP)
	if amount < 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, g, amount)
	f_fees_paid[g] = JWMath.check_amount(f_fees_paid[g] + amount)
	return JWResult.OK


## S05 §5.6：本季消费预算（不能花未收到的钱）。
## 步骤：S05 §5.6（买方类 0）
## 前置：S04 的工资、转移、赡养已全部落账
## 后置：out_budget[g] <= accounts.cash_of(agent_of_group(g))；按恩格尔权重拆到 4 个产品
## 不变量：INV-063（未收到的预计收入不可支配）、INV-003
## 失败：无（预算为 0 是正常结果）
func consumption_budget_into(out_budget_by_product: PackedInt64Array, accounts: JWAccount,
		params: PackedInt64Array) -> int:
	if out_budget_by_product.size() != JWUnits.GROUP_PROD_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				out_budget_by_product.size(), JWUnits.GROUP_PROD_N)
	if accounts == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, JWUnits.Phase.S05, 0)
	var mpc_ppm: int = _param_of(params, JWUnits.Param.MPC_PPM)
	var dissave_ppm: int = _param_of(params, JWUnits.Param.DISSAVE_PPM)
	# 恩格尔权重（4 个产品），docs/12 §5.6 的 split_largest_remainder 权重表
	_sc_prod_w[0] = _param_of(params, JWUnits.Param.ENGEL_WEIGHT_PPM_0)
	_sc_prod_w[1] = _param_of(params, JWUnits.Param.ENGEL_WEIGHT_PPM_1)
	_sc_prod_w[2] = _param_of(params, JWUnits.Param.ENGEL_WEIGHT_PPM_2)
	_sc_prod_w[3] = _param_of(params, JWUnits.Param.ENGEL_WEIGHT_PPM_3)
	for s: int in JWUnits.S:
		_sc_prod_tb[s] = s
	for i: int in out_budget_by_product.size():
		out_budget_by_product[i] = 0
	for g: int in JWUnits.GROUP:
		var agent: int = JWIds.agent_of_group(g)
		var deposit: int = accounts.get_balance(
				JWIds.idx_account(agent, JWIds.ACC_DEPOSIT_CLAIM))
		# docs/12 §5.6：已到手的工资 + 转移 + 赡养净额 + dissave 比例的存款
		# rounding: floor, reason=M1，存款动用比例只取整一次
		# R-CONS-01：再加上季的「财产收入 − 个税 − 收费」（可负）。财产收入在 S06 才到账，
		# 若不以滞后一季的实现值进入预算，企业利润分到户后只能经存款动用率缓慢回流，
		# 需求的系统性缺口正好是分配额；个税不扣则预算系统性高估。
		# R-CONS-01 补遗：本季租金已在开市前付出（R-HOUSING-01），是收入的既定支出，先从可用额中扣除；
		# 否则居民按毛收入的 MPC 买商品、再额外付租金，系统性超支，存款与投资池现金被持续抽干。
		var cash_avail: int = f_wage_income[g] + f_transfer_income[g] + f_support_in[g] \
				- f_support_out[g] + _nonlabor_prev[g] - f_housing_cost[g] \
				+ JWMath.mul_ppm(deposit, dissave_ppm)
		# rounding: floor, reason=M1，边际消费倾向对可用现金只取整一次
		# R-HOUSING-01：租金已在市场开市前直接付给服务部门并登记为住房支出，
		# 不再把住房额并入商品预算（那会按恩格尔权重把租金再花一次）。
		var budget: int = JWMath.mul_ppm(cash_avail, mpc_ppm)
		# INV-063 的硬保证：预算不得超过当前现金（「不能花未收到的钱」）。
		var cash: int = accounts.cash_of(agent)
		if budget > cash:
			budget = cash
		if budget < 0:
			budget = 0
		if budget == 0:
			continue
		var residual: int = JWMath.split_lr_into(budget, _sc_prod_w, _sc_prod_tb, _sc_prod_out)
		if JWMath._split_last_fault != 0:
			return JWMath._split_last_fault
		if residual != 0:
			# 恩格尔权重全 0（内容错误）：不发明分配规则，本组预算留 0。
			continue
		for s2: int in JWUnits.S:
			out_budget_by_product[JWIds.idx_group_prod(g, s2)] = _sc_prod_out[s2]
	return 0


## S05：登记一笔已成交的居民消费（由 JWInventory 在撮合后回调）。
## 步骤：S05 §5.6
## 前置：value_uu 与 qty_uqs 同时 > 0；该笔已 post(kind=HOUSEHOLD_CONSUMPTION)
## 后置：f_consumption、f_consumption_by_product_* 同步增加
## 不变量：INV-062（付款额 == floor(量×价)）、INV-064（未成交部分写 unmet_consumption）
## 失败：无
func record_consumption(g: int, product: int, value_uu: int, qty_uqs: int) -> void:
	if not _group_ok(g):
		return
	if product < 0 or product >= JWUnits.S:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, product, JWUnits.S)
		return
	if value_uu < 0 or qty_uqs < 0:
		JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, value_uu, qty_uqs)
		return
	JWMath.check_amount(value_uu)
	JWMath.check_qty(qty_uqs)
	var i: int = JWIds.idx_group_prod(g, product)
	f_consumption[g] = f_consumption[g] + value_uu
	f_consumption_by_product_uu[i] = f_consumption_by_product_uu[i] + value_uu
	f_consumption_by_product_uqs[i] = f_consumption_by_product_uqs[i] + qty_uqs


## S05：登记未成交的居民消费预算（被迫储蓄）。
## 步骤：S05 §5.6
## 前置：value_uu >= 0；对应预算未被撮合
## 后置：f_unmet_consumption[g] 增加；对应现金留在该组账户
## 不变量：INV-064
## 失败：无
func record_unmet_consumption(g: int, value_uu: int) -> void:
	if not _group_ok(g):
		return
	if value_uu < 0:
		JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, value_uu, 0)
		return
	JWMath.check_amount(value_uu)
	f_unmet_consumption[g] = f_unmet_consumption[g] + value_uu


## S05：登记本组本季的住房支出（租金腿）。
## 步骤：S05 §5.6
## 前置：value_uu >= 0；该笔已过账
## 后置：f_housing_cost[g] 增加
## 不变量：INV-062、INV-086（进可支配收入的扣减项）
## 失败：无
func record_housing_cost(g: int, value_uu: int) -> void:
	if not _group_ok(g):
		return
	if value_uu < 0:
		JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, value_uu, 0)
		return
	JWMath.check_amount(value_uu)
	f_housing_cost[g] = f_housing_cost[g] + value_uu


## S06 §6.7：企业分配与存款利息分回各组，再算可支配收入与储蓄。
## 步骤：S06 §6.7
## 前置：企业利润与利息收入已确定；equity_share_ppm 与 deposit 份额按最大余数法拆分
## 后置：Δcash[g] + Δdeposit[g] == savings[g] 逐组逐季精确成立
## 不变量：INV-086（可支配与储蓄的定义式）、INV-024（存款与投资池配平）、INV-003
## 失败：恒等式不成立 → Fault.LEDGER_IMBALANCE，detail_a = 组下标，detail_b = 残差
##
## `distributable_by_cell` 已由 JWSectorModel.compute_distributable() 按
## `param.payout_ratio_ppm` 折算过（docs/17 §5.6 第 7 行），本函数**不再乘一次**。
func settle_income_and_savings(distributable_by_cell: PackedInt64Array, interest_received_uu: int,
		ledger: JWLedger, accounts: JWAccount,
		params: PackedInt64Array) -> int:
	var rc0: int = post_property_income(distributable_by_cell, interest_received_uu, ledger, accounts)
	if rc0 != 0:
		return rc0
	return settle_savings(ledger, accounts, params)


## R-TAXBASE-01：S06 §6.7 前半——企业分配与存款利息过账到户（财产收入）。
## 步骤：S06 §6.7（先于 §6.5 个税：个税税基「已过账的 wage + property」必须含本季分配）
## 前置：distributable_by_cell 已按 payout 折算
## 后置：PROPERTY_INCOME 分录已写；f_property_income 累计
## 不变量：INV-003（拆分和恒等）、INV-086 的收入项
## 失败：拆分故障 / 过账被拒 → 返回故障码
func post_property_income(distributable_by_cell: PackedInt64Array, interest_received_uu: int,
		ledger: JWLedger, accounts: JWAccount) -> int:
	if ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, JWUnits.Phase.S06, 0)
	if distributable_by_cell.size() != JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				distributable_by_cell.size(), JWUnits.CELL)
	for g: int in JWUnits.GROUP:
		_sc_grp_tb[g] = g

	# ── 1) 企业可分配额按 equity_share_ppm 分回各组（docs/12 §6.7）
	for c: int in JWUnits.CELL:
		var amt: int = distributable_by_cell[c]
		if amt <= 0:
			continue
		JWMath.check_amount(amt)
		var cell_agent: int = JWIds.agent_of_cell(c)
		var cell_cash: int = accounts.cash_of(cell_agent)
		if amt > cell_cash:
			# 利润 ≠ 现金：分配受现金约束，缩减部分显式登记，不产生债权债务。
			ledger.log_rounding(SITE_DISTRIBUTION_CASH_CAPPED, amt, maxi(cell_cash, 0),
					amt - maxi(cell_cash, 0))
			amt = maxi(cell_cash, 0)
		if amt <= 0:
			continue
		for g2: int in JWUnits.GROUP:
			_sc_grp_w[g2] = equity_share_ppm[c * JWUnits.GROUP + g2]
		var residual: int = JWMath.split_lr_into(amt, _sc_grp_w, _sc_grp_tb, _sc_grp_out)
		if JWMath._split_last_fault != 0:
			return JWMath._split_last_fault
		if residual != 0:
			ledger.log_rounding(SITE_DISTRIBUTION_NO_EQUITY, amt, 0, residual)
			continue
		for g3: int in JWUnits.GROUP:
			var part: int = _sc_grp_out[g3]
			if part <= 0:
				continue
			var rc: int = ledger.post(JWUnits.Kind.PROPERTY_INCOME,
					JWIds.idx_account(cell_agent, JWIds.ACC_CASH),
					JWIds.idx_account(JWIds.agent_of_group(g3), JWIds.ACC_CASH),
					part, 0, -1, CAUSE_PROPERTY_DISTRIBUTION, c)
			if rc != 0:
				return rc
			f_property_income[g3] = f_property_income[g3] + part

	# ── 2) 投资池利息按各组 deposit_uu 份额分回（docs/10 §2.4，Σ 分出 == Σ 收到）
	var interest: int = interest_received_uu
	if interest < 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, interest, 0)
	if interest > 0:
		var pool_cash: int = accounts.cash_of(JWIds.AGENT_INVPOOL)
		if interest > pool_cash:
			ledger.log_rounding(SITE_INTEREST_CASH_CAPPED, interest, maxi(pool_cash, 0),
					interest - maxi(pool_cash, 0))
			interest = maxi(pool_cash, 0)
	if interest > 0:
		for g4: int in JWUnits.GROUP:
			_sc_grp_w[g4] = accounts.get_balance(
					JWIds.idx_account(JWIds.agent_of_group(g4), JWIds.ACC_DEPOSIT_CLAIM))
		var res_i: int = JWMath.split_lr_into(interest, _sc_grp_w, _sc_grp_tb, _sc_grp_out)
		if JWMath._split_last_fault != 0:
			return JWMath._split_last_fault
		if res_i != 0:
			ledger.log_rounding(SITE_INTEREST_NO_DEPOSIT, interest, 0, res_i)
		else:
			for g5: int in JWUnits.GROUP:
				var part_i: int = _sc_grp_out[g5]
				if part_i <= 0:
					continue
				var rc_i: int = ledger.post(JWUnits.Kind.PROPERTY_INCOME,
						JWIds.idx_account(JWIds.AGENT_INVPOOL, JWIds.ACC_CASH),
						JWIds.idx_account(JWIds.agent_of_group(g5), JWIds.ACC_CASH),
						part_i, 0, -1, CAUSE_DEPOSIT_INTEREST, g5)
				if rc_i != 0:
					return rc_i
				f_property_income[g5] = f_property_income[g5] + part_i
	return 0


## R-TAXBASE-01：S06 §6.8——可支配收入、储蓄与存款腿（在 §6.5 个税之后）。
## 步骤：S06 §6.8
## 前置：post_property_income 与 collect_income_tax 已完成
## 后置：f_savings 写入；存取款已过账；INV-086 逐组核对
## 不变量：INV-086（Δcash + Δdeposit == savings）、INV-024
## 失败：核对残差 != 0 → LEDGER_IMBALANCE
func settle_savings(ledger: JWLedger, accounts: JWAccount, params: PackedInt64Array) -> int:
	if ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, JWUnits.Phase.S06, 0)
	if params.size() < JWUnits.PARAM_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, params.size(), JWUnits.PARAM_N)
	# ── 3) 可支配收入与储蓄（INV-086 的定义式）
	for g6: int in JWUnits.GROUP:
		var disp: int = disposable_income(g6)
		var sav: int = disp - f_consumption[g6] - f_housing_cost[g6]
		JWMath.check_amount(sav)
		f_savings[g6] = sav
		_sc_savings[g6] = sav

	# ── 4) 储蓄的存款腿（群组 ⇄ 投资池，双边；Δcash + Δdeposit 不因本腿改变）
	for g7: int in JWUnits.GROUP:
		var sav2: int = _sc_savings[g7]
		var agent7: int = JWIds.agent_of_group(g7)
		var cash7: int = accounts.cash_of(agent7)
		var dep7: int = accounts.get_balance(JWIds.idx_account(agent7, JWIds.ACC_DEPOSIT_CLAIM))
		if sav2 > 0:
			# 正储蓄全额存入投资池：政府赤字的对手方就是这笔钱（docs/12 §6.7 的闭环）。
			var x: int = mini(sav2, maxi(cash7, 0))
			if x > 0:
				var rc_d: int = _post_deposit(ledger, agent7, x, CAUSE_DEPOSIT_PLACE, g7)
				if rc_d != 0:
					return rc_d
		elif sav2 < 0:
			# 负储蓄：从自身存款债权中取款，受债权与投资池现金双重上限约束。
			var need: int = -sav2
			var pool_cash2: int = accounts.cash_of(JWIds.AGENT_INVPOOL)
			var w: int = mini(need, mini(maxi(dep7, 0), maxi(pool_cash2, 0)))
			if w < need:
				ledger.log_rounding(SITE_DEPOSIT_WITHDRAW_CAPPED, need, maxi(w, 0), need - maxi(w, 0))
			if w > 0:
				var rc_w: int = _post_deposit(ledger, agent7, -w, CAUSE_DEPOSIT_WITHDRAW, g7)
				if rc_w != 0:
					return rc_w

	# ── 5) INV-086 的 Δ 核对与上季可支配收入的留存
	for g8: int in JWUnits.GROUP:
		var agent8: int = JWIds.agent_of_group(g8)
		var end_bal: int = accounts.cash_of(agent8) \
				+ accounts.get_balance(JWIds.idx_account(agent8, JWIds.ACC_DEPOSIT_CLAIM))
		if _balance_start_valid:
			# Δcash + Δdeposit == savings，逐组逐季精确（INV-086）。
			var resid: int = end_bal - _balance_start[g8] - f_savings[g8]
			if resid != 0:
				return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, g8, resid)
		_disposable_prev[g8] = disposable_income(g8)
		_nonlabor_prev[g8] = f_property_income[g8] - f_income_tax_paid[g8] - f_fees_paid[g8]
	# 快照只对本季有效：下季必须由 S01 重新取（未取即不做 Δ 核对，见 interface_requests）。
	_balance_start_valid = false
	return 0


## 存款腿的四腿过账（群组现金 ⇄ 投资池现金，同时动两边的存款科目）。
## delta > 0 表示存入，delta < 0 表示取款。
## 步骤：S06 §6.7
## 前置：|delta| <= 相应一侧的现金／债权余额
## 后置：Σ legs_delta == 0（负债腿以净值贡献的符号传入，docs/10 §2.5 的「负债增 −」）
## 不变量：INV-024（Σ group.deposit == invpool.deposit_liab == invpool.cash + bondhold）、INV-015
## 失败：转调 JWLedger.post_multi 的失败路径
func _post_deposit(ledger: JWLedger, agent: int, delta: int, cause: int, entity_ref: int) -> int:
	if delta == 0:
		return 0
	_sc_legs_acc[0] = JWIds.idx_account(agent, JWIds.ACC_CASH)
	_sc_legs_delta[0] = -delta
	_sc_legs_acc[1] = JWIds.idx_account(agent, JWIds.ACC_DEPOSIT_CLAIM)
	_sc_legs_delta[1] = delta
	_sc_legs_acc[2] = JWIds.idx_account(JWIds.AGENT_INVPOOL, JWIds.ACC_CASH)
	_sc_legs_delta[2] = delta
	_sc_legs_acc[3] = JWIds.idx_account(JWIds.AGENT_INVPOOL, JWIds.ACC_DEPOSIT_LIAB)
	_sc_legs_delta[3] = -delta
	# 裁定 R-DEPOSIT-01：存取款有自己的类型（三口径全 none），不得占用发债 / 还本的类型码。
	var kind: int = JWUnits.Kind.DEPOSIT_PLACE if delta > 0 else JWUnits.Kind.DEPOSIT_WITHDRAW
	return ledger.post_multi(kind, _sc_legs_acc, _sc_legs_delta, 0, -1, cause, entity_ref)


## 可支配收入（派生纯函数，S08 计算生活指数时用）。
## 步骤：S06 末、S08 §8.1
## 前置：本季 S06 已完成
## 后置：不改状态
## 不变量：INV-086
## 失败：无
func disposable_income(g: int) -> int:
	if not _group_ok(g):
		return 0
	return f_wage_income[g] + f_property_income[g] + f_transfer_income[g] \
			+ f_support_in[g] - f_support_out[g] - f_income_tax_paid[g] - f_fees_paid[g]


## S01：取本季起点的 cash + deposit_claim 快照，供 S06 的 INV-086 Δ 核对。
## 骨架里没有这个钩子，但 `Δcash + Δdeposit == savings` 必须有季初基准才能真检查，
## 已在 interface_requests 登记：JWTurnRunner 应在 S01 调用一次。
## 步骤：S01
## 前置：accounts 已 allocate()
## 后置：_balance_start 被填满，_balance_start_valid == true
## 不变量：INV-086
## 失败：accounts 为空 → Fault.PHASE_VIOLATION
func snapshot_quarter_start_balances(accounts: JWAccount) -> int:
	if accounts == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, JWUnits.Phase.S01, 0)
	for g: int in JWUnits.GROUP:
		var agent: int = JWIds.agent_of_group(g)
		_balance_start[g] = accounts.cash_of(agent) \
				+ accounts.get_balance(JWIds.idx_account(agent, JWIds.ACC_DEPOSIT_CLAIM))
	_balance_start_valid = true
	return 0


## S07 §7.5 之后：登记本季各组的迁出人数。
## §7.7 的 outflow == 死亡 + 成年出 + **迁出**，而迁出量由 JWMigration 持有；
## 骨架没有给出传递通路，已在 interface_requests 登记：
## JWTurnRunner 须在 §7.7 之前调用 `pop.record_migration_out(migration.out_by_group())`。
## 缺这一步时 check_conservation() 会以 MIGRATION_UNPAIRED 报出来，不会静默少算。
## 步骤：S07 §7.5 末
## 前置：out_by_group.size() == 36；update_demography 已在本季执行过（已清零上季登记）
## 后置：_migrate_out 被整体复制
## 不变量：INV-073, INV-080
## 失败：长度不符 → Fault.INDEX_OUT_OF_RANGE
func record_migration_out(out_by_group: PackedInt64Array) -> int:
	if out_by_group.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				out_by_group.size(), JWUnits.GROUP)
	for g: int in JWUnits.GROUP:
		var v: int = out_by_group[g]
		if v < 0:
			return JWResult.raise_fault(JWResult.Fault.MIGRATION_UNPAIRED, g, v)
		_migrate_out[g] = v
	return 0


## S07 §7.4：人口更新（死亡 → 出生 → 成年 → 退休 → 技能 → 迁移 → 核对）。
## 本函数做第 1…4 步（死亡、出生、成年、退休）；第 5 步「技能」由 update_education()
## 在结业槽位上完成——它是唯一拿得到季度号 q 的入口，而到期槽位必须按 q 定位（INV-082）；
## 迁移由 JWMigration 在其后调用，核对由 check_conservation() 完成。
## 步骤：S07 §7.4
## 前置：_population_prev 已在本步入口快照（本函数入口自取）
## 后置：每一步都是配对的转移；取整余数用 split_lr 分配到组
## 不变量：INV-071（死亡是唯一净流出、出生是唯一净流入）、INV-072（逐组来源去向齐全）、
##          INV-074（年龄有向）、INV-082（技能升档只来自结业队列且等量配对）
## 失败：Fault.POPULATION_NOT_CONSERVED
func update_demography(rng: JWRngStreams, params: PackedInt64Array) -> int:
	# rng 与 params 形参保留是为了签名稳定：docs/12 §7.4 的五步全部是确定性 ppm 换算，
	# 没有任何抽样项，也不引用参数卡。凭空加一次抽样会破坏 INV-014 的逐位可复现。
	if rng == null:
		JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, JWUnits.Phase.S07, 0)
	if params.size() < JWUnits.PARAM_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, params.size(), JWUnits.PARAM_N)
	# S07 入口快照（INV-072 的逐组来源去向基准）与上季迁出登记的清零。
	for g: int in JWUnits.GROUP:
		_population_prev[g] = population[g]
		_migrate_out[g] = 0

	# 1) 死亡：唯一允许的净流出，无去向。
	for g1: int in JWUnits.GROUP:
		# rounding: floor, reason=M1，死亡率换算只取整一次，少算优于多算
		var d: int = JWMath.mul_ppm(population[g1], death_ppm[g1])
		if d <= 0:
			continue
		if d > population[g1]:
			d = population[g1]
		population[g1] = population[g1] - d
		f_deaths[g1] = f_deaths[g1] + d

	# 2) 出生：唯一允许的净流入，去向固定为 group.<r>.minor.low。
	for r: int in JWUnits.R:
		var working_pop: int = 0
		for k: int in JWUnits.K:
			working_pop += population[JWIds.idx_group(r, JWUnits.Age.WORKING, k)]
		# rounding: floor, reason=M1，出生率按地区 working 人口换算只取整一次
		var b: int = JWMath.mul_ppm(working_pop, birth_ppm[r])
		if b <= 0:
			continue
		var g_newborn: int = JWIds.idx_group(r, JWUnits.Age.MINOR, JWUnits.Skill.LOW)
		population[g_newborn] = population[g_newborn] + b
		f_births[g_newborn] = f_births[g_newborn] + b

	# 3) 成年：minor → working，同技能档（minor 的 skill 是教育准备度，docs/10 §6）。
	var minor_rate: int = age_out_ppm[JWUnits.Age.MINOR]
	for r2: int in JWUnits.R:
		for k2: int in JWUnits.K:
			var g_min: int = JWIds.idx_group(r2, JWUnits.Age.MINOR, k2)
			# rounding: floor, reason=M1，成年率换算只取整一次
			var n: int = JWMath.mul_ppm(population[g_min], minor_rate)
			if n <= 0:
				continue
			_move_paired(g_min, JWIds.idx_group(r2, JWUnits.Age.WORKING, k2), n,
					f_age_out, f_age_in)

	# 4) 退休：working → elder，同技能档；退休者带走的就业在 §7.7 统一扣减。
	var working_rate: int = age_out_ppm[JWUnits.Age.WORKING]
	for r3: int in JWUnits.R:
		for k3: int in JWUnits.K:
			var g_wrk: int = JWIds.idx_group(r3, JWUnits.Age.WORKING, k3)
			# rounding: floor, reason=M1，退休率换算只取整一次
			var n2: int = JWMath.mul_ppm(population[g_wrk], working_rate)
			if n2 <= 0:
				continue
			_move_paired(g_wrk, JWIds.idx_group(r3, JWUnits.Age.ELDER, k3), n2,
					f_age_out, f_age_in)

	# 任何一步把人口算成负数都是最严重的一类缺陷，立即登记（不「修正」）。
	for g9: int in JWUnits.GROUP:
		if population[g9] < 0:
			return JWResult.raise_fault(JWResult.Fault.POPULATION_NOT_CONSERVED,
					g9, population[g9])
	if JWResult.pending_code() == JWResult.Fault.POPULATION_NOT_CONSERVED:
		return JWResult.Fault.POPULATION_NOT_CONSERVED
	return 0


## S07 §7.6：教育队列（P05）。拨款当季不得产生任何 skill_in。
## teachers_by_region 是 state.pubserv.teachers_persons[]（长 4，按 region），由 JWCapital 持有、
## 经 JWTurnRunner 以数组形参传入：本类与 JWCapital 同为秩 4，同秩之间不得互相引用（§3.2/§3.3）。
## 本函数同时完成 §7.4 第 5 步「技能」：到期槽位的 skill_out / skill_in 等量配对——
## 先结算到期、后放入新席位，所以本季拨款的席位在本季**不可能**产生 skill_in（INV-081）。
## 步骤：S07 §7.6
## 前置：teachers_by_region.size() == JWUnits.R；requested_seats.size() == JWUnits.GROUP；
##       max_seats = teachers_by_region[r] × student_teacher_ratio；teachers == 0 ⇒ new_seats == 0
## 后置：新席位入 education_cohort[g][q + training_lag_q]；到期队列等量配对 skill_out/skill_in
## 不变量：INV-081（席位上限与「拨款当季无 skill_in」）、INV-082（滞后 >= training_lag_q）
## 失败：申请超上限 → 截到上限并写 log.clamp；不是故障（ADV-03 的防线）
func update_education(teachers_by_region: PackedInt64Array, requested_seats: PackedInt64Array,
		q: int, params: PackedInt64Array) -> int:
	if teachers_by_region.size() != JWUnits.R:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				teachers_by_region.size(), JWUnits.R)
	if requested_seats.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				requested_seats.size(), JWUnits.GROUP)
	if q < 0:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, q, 0)
	var ratio: int = _param_of(params, JWUnits.Param.STUDENT_TEACHER_RATIO)
	var lag: int = _param_of(params, JWUnits.Param.TRAINING_LAG_Q)
	if lag < 0:
		# 负滞后没有语义（会把席位放进过去的槽位）。参数卡的 valid_range 在载入期已挡，
		# 这里只做不改账的防御性下界，并登记一次越界。
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				JWUnits.Param.TRAINING_LAG_Q, lag)
		lag = 0
	_edu_seats_clamped = 0

	# ── 第 1 步：到期槽位结业（§7.4 第 5 步）。必须在放入新席位之前，INV-081 才是结构性的。
	var slot_due: int = q - JWMath.mul(JWMath.floor_div(q, JWUnits.EDU_SLOT), JWUnits.EDU_SLOT)
	for g: int in JWUnits.GROUP:
		var idx: int = JWIds.idx_edu(g, slot_due)
		var n: int = education_cohort[idx]
		if n <= 0:
			continue
		var k: int = JWIds.SKILL_OF_GROUP[g]
		if k >= JWUnits.K - 1:
			# 最高档没有升档去向：席位作废并清零（这类席位在入队时已被拒，防御性分支）。
			education_cohort[idx] = 0
			continue
		var movable: int = mini(n, population[g])
		if movable < n:
			# 结业人数超过该组当前人口（死亡／迁出所致）：超出部分留在原槽位，不凭空造人。
			education_cohort[idx] = n - movable
		else:
			education_cohort[idx] = 0
		if movable <= 0:
			continue
		var g_to: int = JWIds.idx_group(JWIds.REGION_OF_GROUP[g], JWIds.AGE_OF_GROUP[g], k + 1)
		_move_paired(g, g_to, movable, f_skill_out, f_skill_in)

	# ── 第 2 步：新席位入队，逐地区受 teachers × ratio − 在读席位 的硬上限约束（ADV-03）。
	for r: int in JWUnits.R:
		var teachers: int = teachers_by_region[r]
		if teachers < 0:
			teachers = 0
		# 单位：人 × (学生/教师) = 席位
		var max_seats: int = JWMath.mul(teachers, maxi(ratio, 0))
		var in_study: int = 0
		var requested: int = 0
		var j: int = 0
		for a: int in JWUnits.A:
			for k2: int in JWUnits.K:
				var g2: int = JWIds.idx_group(r, a, k2)
				for s: int in JWUnits.EDU_SLOT:
					in_study += education_cohort[JWIds.idx_edu(g2, s)]
				# 只有 working 档且有升档去向的组可以申请（INV-074 / INV-082）。
				var want: int = requested_seats[g2]
				if want < 0:
					want = 0
				if a != JWUnits.Age.WORKING or k2 >= JWUnits.K - 1:
					want = 0
				# 在读 + 新席位不得超过该组现有人口（席位是人，不是额度）。
				want = mini(want, maxi(population[g2], 0))
				_sc_grp_w[j] = want
				_sc_grp_tb[j] = g2
				requested += want
				j += 1
		var room: int = maxi(max_seats - in_study, 0)
		var granted: int = mini(requested, room)
		if granted < requested:
			# 截到上限：是业务性短缺，不是故障（docs/17 §4.14 / ADV-03）。
			# log.clamp 的四条列由 JWPricing 持有，本类的签名里拿不到写入通路，
			# 因此把被截掉的席位数计入本类的可读计数器（edu_seats_clamped()）；
			# 已在 interface_requests 登记「需要一个与模块无关的 clamp 登记通路」。
			_edu_seats_clamped += requested - granted
		if granted <= 0:
			continue
		# 申请超上限时按各组申请量最大余数法分配（禁止先到先得）。
		var out_n: int = JWUnits.A * JWUnits.K
		var residual: int = 0
		if granted == requested:
			for jj: int in out_n:
				_sc_grp_out[jj] = _sc_grp_w[jj]
		else:
			residual = _split_prefix(granted, out_n)
			if JWMath._split_last_fault != 0:
				return JWMath._split_last_fault
		if residual != 0:
			continue
		var slot_new: int = q + lag
		slot_new = slot_new - JWMath.mul(
				JWMath.floor_div(slot_new, JWUnits.EDU_SLOT), JWUnits.EDU_SLOT)
		for j2: int in out_n:
			var seats: int = _sc_grp_out[j2]
			if seats <= 0:
				continue
			var idx2: int = JWIds.idx_edu(_sc_grp_tb[j2], slot_new)
			education_cohort[idx2] = education_cohort[idx2] + seats
	return 0


## 对 _sc_grp_w / _sc_grp_tb 的前 n 项做最大余数法拆分，结果写回 _sc_grp_out 的前 n 项。
## split_lr_into 要求三条数组等长，而这里的宽度（9）小于 scratch 的长度（36），
## 故把尾部权重清零后整段拆分——数学上等价（尾部权重为 0 即分不到任何一份）。
## 步骤：S07 §7.6
## 前置：0 < n <= JWUnits.GROUP；total >= 0
## 后置：Σ _sc_grp_out[0..n) == total
## 不变量：INV-003
## 失败：转调 split_lr_into 的失败路径
func _split_prefix(total: int, n: int) -> int:
	for i: int in JWUnits.GROUP:
		if i >= n:
			_sc_grp_w[i] = 0
			_sc_grp_tb[i] = JWUnits.GROUP + i
	return JWMath.split_lr_into(total, _sc_grp_w, _sc_grp_tb, _sc_grp_out)


## 最近一次 update_education() 被席位上限截掉的申请人数（诊断与 ADV-03 的断言点）。
## 步骤：S07 §7.6 之后
## 前置：update_education 已执行
## 后置：不改状态
## 不变量：INV-081
## 失败：无
func edu_seats_clamped() -> int:
	return _edu_seats_clamped


## S07 §7.8：消费指数与服务可及性（相对基准，不是国际排名）。
## 步骤：S07 §7.8
## 前置：base_real_cons 与 base_delivered_service 在 q=0 由剧本固定，之后只读
## 后置：consumption_index 与 service_access 更新；各组可不同（裁定 R-ACCESS-01）
## 不变量：INV-149（相对自身基准；文案无「国际排名」字样）
## 失败：基准为 0 → 用 max(base,1)，不除零
func update_living_indices(delivered_to_group: PackedInt64Array) -> int:
	if delivered_to_group.size() != JWUnits.GROUP_SVC_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				delivered_to_group.size(), JWUnits.GROUP_SVC_N)
	for g: int in JWUnits.GROUP:
		var real_cons: int = 0
		for s: int in JWUnits.S:
			real_cons += f_consumption_by_product_uqs[JWIds.idx_group_prod(g, s)]
		# rounding: floor, reason=docs/12 §7.8 的定义式 idiv_floor(real × 1e6, max(base,1))
		consumption_index[g] = JWMath.mul_div_floor(maxi(real_cons, 0), JWUnits.PPM,
				maxi(base_real_cons[g], 1))
		for kind: int in JWUnits.SERVICE_KIND:
			var i: int = JWIds.idx_group_svc(g, kind)
			# rounding: floor, reason=同上；服务可及率的区间是 0…1e6（裁定 R-ACCESS-01）
			var v: int = JWMath.mul_div_floor(maxi(delivered_to_group[i], 0), JWUnits.PPM,
					maxi(base_delivered_service[i], 1))
			service_access[i] = JWMath.clamp_i(v, 0, JWUnits.PPM)
	return 0


## S07：本季各组人口流出量（死亡 + 成年出 + 迁出），供 JWLaborMarket 做就业配对。
## 步骤：S07 §7.7（在 update_demography 与 JWMigration 之后）
## 前置：本季人口流动已全部完成；迁出量已由 record_migration_out() 登记
## 后置：out_flow 被填满；不改状态
## 不变量：INV-080（S07 对 employment 的减少量必须精确等于本函数的结果分摊）
## 失败：无
func outflow_persons_into(out_flow: PackedInt64Array) -> void:
	if out_flow.size() != JWUnits.GROUP:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, out_flow.size(), JWUnits.GROUP)
		return
	for g: int in JWUnits.GROUP:
		# R-P05-01：结业升档（skill_out）同样带走原技能档的在岗人数——升档者辞去原档岗位，
		# 下一季以新技能档重新进入招工。漏掉这一项时原组在岗 > 人口，S07 报 EMPLOYMENT_OVERFLOW。
		out_flow[g] = f_deaths[g] + f_age_out[g] + _migrate_out[g] + f_skill_out[g]


## S07：接收 JWLaborMarket 的就业扣减结果，回写群组侧 employed。
## 步骤：S07 §7.7
## 前置：cut[g][slot] 之和 == outflow 对应的 employed_share
## 后置：employed 减少；两侧口径仍逐（地区，技能）相等
## 不变量：INV-077, INV-080
## 失败：和不相等 → Fault.EMPLOYMENT_OVERFLOW
func apply_employment_cut(cut_by_group_slot: PackedInt64Array) -> int:
	if cut_by_group_slot.size() != JWUnits.GROUP_EMP_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				cut_by_group_slot.size(), JWUnits.GROUP_EMP_N)
	var slots: int = JWUnits.S + 1
	for g: int in JWUnits.GROUP:
		var outflow: int = f_deaths[g] + f_age_out[g] + _migrate_out[g] + f_skill_out[g]
		# docs/12 §7.7：employed_share = idiv_floor(outflow × employed_persons[g], max(pop_prev, 1))
		# rounding: floor, reason=§7.7 的定义式；分母是本步入口的人口快照
		var share: int = JWMath.mul_div_floor(outflow, employed_total(g),
				maxi(_population_prev[g], 1))
		var total_cut: int = 0
		for slot: int in slots:
			var c: int = cut_by_group_slot[JWIds.idx_group_emp(g, slot)]
			if c < 0:
				return JWResult.raise_fault(JWResult.Fault.EMPLOYMENT_OVERFLOW, g, c)
			total_cut += c
		if total_cut != share:
			return JWResult.raise_fault(JWResult.Fault.EMPLOYMENT_OVERFLOW, g, total_cut - share)
		for slot2: int in slots:
			var i: int = JWIds.idx_group_emp(g, slot2)
			var c2: int = cut_by_group_slot[i]
			if c2 > employed[i]:
				return JWResult.raise_fault(JWResult.Fault.EMPLOYMENT_OVERFLOW, i,
						c2 - employed[i])
			employed[i] = employed[i] - c2
	return 0


## S07 末：人口守恒终检。
## 步骤：S07 §7.4 第 7 步
## 前置：本季全部人口流动已完成
## 后置：不改状态
## 不变量：INV-071, INV-072, INV-073（迁移双边由 JWMigration 保证并在此复核）
## 失败：Fault.POPULATION_NOT_CONSERVED，detail_a = 组下标，detail_b = 残差
func check_conservation(migrate_in: PackedInt64Array, migrate_out: PackedInt64Array) -> int:
	if migrate_in.size() != JWUnits.GROUP or migrate_out.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				migrate_in.size(), migrate_out.size())
	var sum_in: int = 0
	var sum_out: int = 0
	for g: int in JWUnits.GROUP:
		# INV-073 的复核之一：§7.7 用的迁出量必须与 JWMigration 的账一致，
		# 否则就业扣减的分母是错的（少算即静默漏扣，不允许）。
		if migrate_out[g] != _migrate_out[g]:
			return JWResult.raise_fault(JWResult.Fault.MIGRATION_UNPAIRED, g,
					migrate_out[g] - _migrate_out[g])
		# INV-072：逐组来源去向齐全。
		var expect: int = _population_prev[g] + f_births[g] - f_deaths[g] \
				+ f_age_in[g] - f_age_out[g] + f_skill_in[g] - f_skill_out[g] \
				+ migrate_in[g] - migrate_out[g]
		if population[g] != expect:
			return JWResult.raise_fault(JWResult.Fault.POPULATION_NOT_CONSERVED, g,
					population[g] - expect)
		if population[g] < 0:
			return JWResult.raise_fault(JWResult.Fault.POPULATION_NOT_CONSERVED, g,
					population[g])
		sum_in += migrate_in[g]
		sum_out += migrate_out[g]
	# INV-073：Σ 迁入 == Σ 迁出。
	if sum_in != sum_out:
		return JWResult.raise_fault(JWResult.Fault.MIGRATION_UNPAIRED, sum_out, sum_in)
	# INV-071：全国人口只由出生流入、只由死亡流出。
	var expect_nation: int = JWMath.sum(_population_prev) + JWMath.sum(f_births) \
			- JWMath.sum(f_deaths)
	var actual_nation: int = JWMath.sum(population)
	if actual_nation != expect_nation:
		return JWResult.raise_fault(JWResult.Fault.POPULATION_NOT_CONSERVED,
				JWUnits.GROUP, actual_nation - expect_nation)
	return 0



## 载入后重建「上季基准」（内容开局与读档共用）。
## 步骤：LOAD（JWSimState.finalize_load 调用，早于 check_all_p0）
## 前置：population 与本块全部流量数组已由 set_state_array 写入；
##        migrate_in / migrate_out 是 JWMigration 已载入的同一对汇总数组
## 后置：_population_prev[g] = population[g] − 本季净流量；_migrate_out 与迁移账一致
## 不变量：INV-072 逐组来源去向在载入后按构造成立；
##          INV-071 / INV-073 仍是真检查——Σ 成年、Σ 技能、Σ 迁移的流入流出必须各自抵消，
##          反推不会替它们背书（全国恒等式的余项恰好就是这三组配对差）
## 失败：数组长度不符 → INDEX_OUT_OF_RANGE；反推出负基准 → POPULATION_NOT_CONSERVED
##
## 为什么是反推而不是存档：_population_prev 是 S07 入口的私有快照，不在状态块协议里。
## 内容开局没有「上一季」，基准只能等于开局人口（此时流量全为 0，反推即得）；
## 读档时存档带有上季全部流量，反推结果与原进程 S07 入口的快照逐位相同。
## 两条路径因此共用同一个方法，不需要改存档 schema。
func rebase_after_load(migrate_in: PackedInt64Array, migrate_out: PackedInt64Array) -> int:
	if migrate_in.size() != JWUnits.GROUP or migrate_out.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				migrate_in.size(), migrate_out.size())
	for g: int in JWUnits.GROUP:
		_migrate_out[g] = migrate_out[g]
		var prev: int = population[g] - f_births[g] + f_deaths[g] 				- f_age_in[g] + f_age_out[g] - f_skill_in[g] + f_skill_out[g] 				- migrate_in[g] + migrate_out[g]
		if prev < 0:
			return JWResult.raise_fault(JWResult.Fault.POPULATION_NOT_CONSERVED, g, prev)
		_population_prev[g] = prev
	return 0

# ── §1.6 状态块协议（子系统 SUBSYS_GROUP） ────────────────────────────────────

## LOAD 期一次性把本块各数组 resize 到 §2 的契约长度。
## 步骤：LOAD
## 前置：尚未分配；只允许 JWContentLoader / JWSaves 调用
## 后置：全部数组长度等于契约长度，内容为 0；此后不再 resize
## 不变量：INV-136（数组顺序与长度是 schema 的一部分）
## 失败：无（长度不符在载入校验处报 Load.UNIT_MISMATCH）
func allocate() -> void:
	population.resize(JWUnits.GROUP)
	participation_ppm.resize(JWUnits.GROUP)
	employed.resize(JWUnits.GROUP_EMP_N)
	education_cohort.resize(JWUnits.EDU_N)
	housing_occupied.resize(JWUnits.GROUP)
	service_access.resize(JWUnits.GROUP_SVC_N)
	consumption_index.resize(JWUnits.GROUP)
	population.fill(0)
	participation_ppm.fill(0)
	employed.fill(0)
	education_cohort.fill(0)
	housing_occupied.fill(0)
	service_access.fill(0)
	# 消费指数的初值是 1 000 000（docs/17 §4.14 成员表），不是 0。
	consumption_index.fill(JWUnits.PPM)

	f_births.resize(JWUnits.GROUP)
	f_deaths.resize(JWUnits.GROUP)
	f_age_in.resize(JWUnits.GROUP)
	f_age_out.resize(JWUnits.GROUP)
	f_skill_in.resize(JWUnits.GROUP)
	f_skill_out.resize(JWUnits.GROUP)
	f_migrate_rejected.resize(JWUnits.GROUP)
	f_wage_income.resize(JWUnits.GROUP)
	f_transfer_income.resize(JWUnits.GROUP)
	f_support_in.resize(JWUnits.GROUP)
	f_support_out.resize(JWUnits.GROUP)
	f_property_income.resize(JWUnits.GROUP)
	f_income_tax_paid.resize(JWUnits.GROUP)
	f_consumption.resize(JWUnits.GROUP)
	f_consumption_by_product_uu.resize(JWUnits.GROUP_PROD_N)
	f_consumption_by_product_uqs.resize(JWUnits.GROUP_PROD_N)
	f_housing_cost.resize(JWUnits.GROUP)
	f_unmet_consumption.resize(JWUnits.GROUP)
	f_savings.resize(JWUnits.GROUP)
	reset_flows()

	birth_ppm.resize(JWUnits.R)
	death_ppm.resize(JWUnits.GROUP)
	age_out_ppm.resize(JWUnits.A)
	support_out_weight_ppm.resize(JWUnits.GROUP)
	base_real_income.resize(JWUnits.GROUP)
	base_real_cons.resize(JWUnits.GROUP)
	base_delivered_service.resize(JWUnits.GROUP_SVC_N)
	equity_share_ppm.resize(JWUnits.CELL * JWUnits.GROUP)
	birth_ppm.fill(0)
	death_ppm.fill(0)
	age_out_ppm.fill(0)
	support_out_weight_ppm.fill(0)
	base_real_income.fill(0)
	base_real_cons.fill(0)
	base_delivered_service.fill(0)
	equity_share_ppm.fill(0)

	_population_prev.resize(JWUnits.GROUP)
	_migrate_out.resize(JWUnits.GROUP)
	_disposable_prev.resize(JWUnits.GROUP)
	_nonlabor_prev.resize(JWUnits.GROUP)
	f_fees_paid.resize(JWUnits.GROUP)
	_balance_start.resize(JWUnits.GROUP)
	_sc_savings.resize(JWUnits.GROUP)
	_population_prev.fill(0)
	_migrate_out.fill(0)
	_disposable_prev.fill(0)
	_nonlabor_prev.fill(0)
	f_fees_paid.fill(0)
	_balance_start.fill(0)
	_sc_savings.fill(0)
	_balance_start_valid = false

	_sc_dep_group.resize(DEPENDENT_PER_REGION)
	_sc_dep_w.resize(DEPENDENT_PER_REGION)
	_sc_dep_tb.resize(DEPENDENT_PER_REGION)
	_sc_dep_out.resize(DEPENDENT_PER_REGION)
	_sc_dep_group.fill(0)
	_sc_dep_w.fill(0)
	_sc_dep_tb.fill(0)
	_sc_dep_out.fill(0)

	_sc_prod_w.resize(JWUnits.S)
	_sc_prod_tb.resize(JWUnits.S)
	_sc_prod_out.resize(JWUnits.S)
	_sc_prod_w.fill(0)
	_sc_prod_tb.fill(0)
	_sc_prod_out.fill(0)

	_sc_grp_w.resize(JWUnits.GROUP)
	_sc_grp_tb.resize(JWUnits.GROUP)
	_sc_grp_out.resize(JWUnits.GROUP)
	_sc_grp_w.fill(0)
	_sc_grp_tb.fill(0)
	_sc_grp_out.fill(0)

	_sc_legs_acc.resize(4)
	_sc_legs_delta.resize(4)
	_sc_legs_acc.fill(0)
	_sc_legs_delta.fill(0)


## 只读取用某个状态数组（返回引用，调用方不得写）。
## 步骤：LOAD、哈希、存档
## 前置：0 <= i < STATE_ARRAY_IDS.size()
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回空数组
func state_array(i: int) -> PackedInt64Array:
	match i:
		0:
			return population
		1:
			return participation_ppm
		2:
			return employed
		3:
			return education_cohort
		4:
			return housing_occupied
		5:
			return service_access
		6:
			return consumption_index
		7:
			return _disposable_prev
		8:
			return _nonlabor_prev
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


## 写入某个状态数组（仅 LOAD / MIG）。
## 下标 0..8 是 STATE_ARRAY_IDS 的状态数组；9.. 是 CONTENT_ARRAY_IDS 的内容表
## （与 JWMigration 同一约定：内容表不进 state_hash，但需要一条 LOAD 期写入通路）。
## 步骤：LOAD、MIG
## 前置：调用点位于 systems/content_loader.gd 或 systems/saves.gd；长度与契约一致
## 后置：对应成员被整体替换
## 不变量：INV-136
## 失败：越界或长度不符 → 返回非 0 故障码
func set_state_array(i: int, v: PackedInt64Array) -> int:
	var n_state: int = STATE_ARRAY_IDS.size()
	if i < 0 or i >= n_state + CONTENT_ARRAY_IDS.size():
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i,
				n_state + CONTENT_ARRAY_IDS.size())
	var want: int = STATE_ARRAY_LEN[i] if i < n_state else CONTENT_ARRAY_LEN[i - n_state]
	if v.size() != want:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v.size(), want)
	match i:
		0:
			population = v
		1:
			participation_ppm = v
		2:
			employed = v
		3:
			education_cohort = v
		4:
			housing_occupied = v
		5:
			service_access = v
		6:
			consumption_index = v
		7:
			_disposable_prev = v
		8:
			_nonlabor_prev = v
		9:
			birth_ppm = v
		10:
			death_ppm = v
		11:
			age_out_ppm = v
		12:
			support_out_weight_ppm = v
		13:
			base_real_income = v
		14:
			base_real_cons = v
		15:
			base_delivered_service = v
		16:
			equity_share_ppm = v
	return 0


## 读取某个状态标量（本类无状态标量，恒返回 0）。
## 步骤：LOAD、哈希、存档
## 前置：0 <= i < STATE_SCALAR_IDS.size()
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回 0
func state_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


## 写入某个状态标量（仅 LOAD / MIG；本类无状态标量）。
## 步骤：LOAD、MIG
## 前置：调用点位于 systems/content_loader.gd 或 systems/saves.gd
## 后置：无
## 不变量：INV-136
## 失败：任意下标都越界 → 返回非 0 故障码
func set_state_scalar(i: int, v: int) -> int:
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v)


## 只读取用某个流量数组。
## 步骤：哈希、诊断
## 前置：0 <= i < FLOW_ARRAY_IDS.size()
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回空数组
func flow_array(i: int) -> PackedInt64Array:
	match i:
		0:
			return f_births
		1:
			return f_deaths
		2:
			return f_age_in
		3:
			return f_age_out
		4:
			return f_skill_in
		5:
			return f_skill_out
		6:
			return f_migrate_rejected
		7:
			return f_wage_income
		8:
			return f_transfer_income
		9:
			return f_support_in
		10:
			return f_support_out
		11:
			return f_property_income
		12:
			return f_income_tax_paid
		13:
			return f_consumption
		14:
			return f_consumption_by_product_uu
		15:
			return f_consumption_by_product_uqs
		16:
			return f_housing_cost
		17:
			return f_unmet_consumption
		18:
			return f_savings
		19:
			return f_fees_paid
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
	return PackedInt64Array()


## 读取某个流量标量（本类无流量标量，恒返回 0）。
## 步骤：哈希、诊断
## 前置：0 <= i < FLOW_SCALAR_IDS.size()
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回 0
func flow_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_SCALAR_IDS.size())
	return 0


## 仅 S01：把全部 FLOW_* 归零。
## 步骤：S01 §01.3
## 前置：调用点位于 systems/turn_runner.gd 的 _step_s01 内
## 后置：全部流量数组逐位为 0
## 不变量：INV-013（流量每季清零）
## 失败：无（清零失败由 flow_abs_sum() 在其后检出）
func reset_flows() -> void:
	f_births.fill(0)
	f_deaths.fill(0)
	f_age_in.fill(0)
	f_age_out.fill(0)
	f_skill_in.fill(0)
	f_skill_out.fill(0)
	f_migrate_rejected.fill(0)
	f_wage_income.fill(0)
	f_transfer_income.fill(0)
	f_support_in.fill(0)
	f_support_out.fill(0)
	f_property_income.fill(0)
	f_income_tax_paid.fill(0)
	f_consumption.fill(0)
	f_consumption_by_product_uu.fill(0)
	f_consumption_by_product_uqs.fill(0)
	f_housing_cost.fill(0)
	f_unmet_consumption.fill(0)
	f_savings.fill(0)
	f_fees_paid.fill(0)


## S01 清零后的自检，非 0 即 FLOW_NOT_RESET。
## 步骤：S01 §01.3 末
## 前置：reset_flows() 刚刚执行
## 后置：不改状态
## 不变量：INV-013
## 失败：返回非 0 由调用方判为 Fault.FLOW_NOT_RESET
func flow_abs_sum() -> int:
	var acc: int = 0
	for i: int in FLOW_ARRAY_IDS.size():
		acc += JWMath.sum_abs(flow_array(i))
	return acc


## §1.6 状态块协议：读档时写回流量数组（R-SAVE-01，由 tools/gen_flow_setters.py 按 flow_array 逐项对称生成）。
## 步骤：LOAD（JWSaves 经 JWSimState 调用）
## 前置：v 的长度与本块当前分配的长度一致（长度是 schema 的一部分，INV-136）
## 后置：对应成员被整体替换
## 不变量：INV-133（读档后与原进程逐位相同）
## 失败：下标越界或长度不符 → INDEX_OUT_OF_RANGE
func set_flow_array(i: int, v: PackedInt64Array) -> int:
	if i == 0:
		if v.size() != f_births.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_births = v.duplicate()
		return JWResult.OK
	if i == 1:
		if v.size() != f_deaths.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_deaths = v.duplicate()
		return JWResult.OK
	if i == 2:
		if v.size() != f_age_in.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_age_in = v.duplicate()
		return JWResult.OK
	if i == 3:
		if v.size() != f_age_out.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_age_out = v.duplicate()
		return JWResult.OK
	if i == 4:
		if v.size() != f_skill_in.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_skill_in = v.duplicate()
		return JWResult.OK
	if i == 5:
		if v.size() != f_skill_out.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_skill_out = v.duplicate()
		return JWResult.OK
	if i == 6:
		if v.size() != f_migrate_rejected.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_migrate_rejected = v.duplicate()
		return JWResult.OK
	if i == 7:
		if v.size() != f_wage_income.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_wage_income = v.duplicate()
		return JWResult.OK
	if i == 8:
		if v.size() != f_transfer_income.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_transfer_income = v.duplicate()
		return JWResult.OK
	if i == 9:
		if v.size() != f_support_in.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_support_in = v.duplicate()
		return JWResult.OK
	if i == 10:
		if v.size() != f_support_out.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_support_out = v.duplicate()
		return JWResult.OK
	if i == 11:
		if v.size() != f_property_income.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_property_income = v.duplicate()
		return JWResult.OK
	if i == 12:
		if v.size() != f_income_tax_paid.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_income_tax_paid = v.duplicate()
		return JWResult.OK
	if i == 13:
		if v.size() != f_consumption.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_consumption = v.duplicate()
		return JWResult.OK
	if i == 14:
		if v.size() != f_consumption_by_product_uu.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_consumption_by_product_uu = v.duplicate()
		return JWResult.OK
	if i == 15:
		if v.size() != f_consumption_by_product_uqs.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_consumption_by_product_uqs = v.duplicate()
		return JWResult.OK
	if i == 16:
		if v.size() != f_housing_cost.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_housing_cost = v.duplicate()
		return JWResult.OK
	if i == 17:
		if v.size() != f_unmet_consumption.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_unmet_consumption = v.duplicate()
		return JWResult.OK
	if i == 18:
		if v.size() != f_savings.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_savings = v.duplicate()
		return JWResult.OK
	if i == 19:
		if v.size() != f_fees_paid.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_fees_paid = v.duplicate()
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
