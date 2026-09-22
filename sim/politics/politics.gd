## **票**（支持度与席位）、行政能力、留任与终局判定，以及群组的三个主观量。
##
## **INV-125 的结构性落地**：本类**不引用** `JWInterestGroups` 的任何字段，
## `seat_rule()` 也不引用 `admin_capacity_ppm`；三种权力由三个类、三个函数分别计算。
## 依赖秩 6（docs/17 §3.2）：只允许引用 ≤5 的类。
## 子系统归属：四个主观量与 keep_streak 归 `SUBSYS_GROUP`，
## `run_terminated` / `termination_reason` 归 `SUBSYS_META`，其余归 `SUBSYS_POLITICS`。
class_name JWPolitics
extends RefCounted

## 本块各状态数组所属子系统（与 STATE_ARRAY_IDS 等长），用于 subsystem_hash 与 WriteGuard。
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_GROUP, JWUnits.SUBSYS_GROUP, JWUnits.SUBSYS_GROUP,
	JWUnits.SUBSYS_GROUP, JWUnits.SUBSYS_GROUP,
	JWUnits.SUBSYS_GROUP, JWUnits.SUBSYS_GROUP, JWUnits.SUBSYS_GROUP,
	JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_POLITICS,
]

## 本块各状态标量所属子系统（与 STATE_SCALAR_IDS 等长）。
## 注：docs/17 §1.6 只定义了 STATE_ARRAY_SUBSYS；本块的标量横跨 POLITICS 与 META 两个子系统，
## 没有标量级归属表就无法给 subsystem_hash 正确分区，故此处补一张（已登记为接口变更请求）。
const STATE_SCALAR_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_POLITICS,
	JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_POLITICS,
	JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_POLITICS,
	JWUnits.SUBSYS_META, JWUnits.SUBSYS_META,
	JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_POLITICS,
	JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_POLITICS,
]

## 本块流量标量所属子系统（与 FLOW_SCALAR_IDS 等长）。
const FLOW_SCALAR_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_POLITICS,
]

## 稳定 ID 注册表：下标 == 数组序号，内容是 docs/10 的稳定 ID 字符串。
## 只在加载与哈希时被读，结算期不触碰（无 String 进入热路径）。
## 注：`keep_streak_q` 与 `_at_risk_streak_q` 在 docs/10 尚无稳定 ID，按同族命名暂定（见 interface_requests）。
const STATE_ARRAY_IDS: PackedStringArray = [
	"state.group.living_index_ppm",
	"state.group.expectation_ppm",
	"state.group.trust_ppm",
	"state.group.support_ppm",
	"state.group.keep_streak_q",
	# R-SUPPORT-02：支持度变动的基准（第 0 季结算后的模型口径指数），跨季只读，进存档与哈希。
	"state.group.base_living_index_ppm",
	"state.group.base_expectation_ppm",
	"state.group.base_trust_ppm",
	# R-EVENT-01：事件的两个跨季计数（原在 JWEventEngine 里，不进存档也不进哈希，
	# 读档后冷却与次数上限归零，「存档 → 读档 → 推进」与「直接推进」分叉）。
	"state.event.fire_count",
	"state.event.last_fire_q",
]
## 下标 11…15 是本次实现追加的跨季状态（docs/10 §8.3 尚无稳定 ID，按同族命名暂定，
## 已登记为接口变更请求）。它们**必须**进哈希与存档：预算审查的四季窗口与两条连胜／连败计数
## 都是跨季记忆，留在类 L 里会让「存档 → 读档 → 推进」与「直接推进」分叉（INV-131 / INV-133）。
const STATE_SCALAR_IDS: PackedStringArray = [
	"state.politics.seats_total",
	"state.politics.seats_gov",
	"state.politics.term_index",
	"state.politics.next_election_q",
	"state.politics.next_budget_review_q",
	"state.politics.mandate_goal",
	"state.politics.mandate_status",
	"state.politics.admin_capacity_ppm",
	"state.politics.legal_authority_mask",
	"state.meta.run_terminated",
	"state.meta.termination_reason",
	"state.politics.lost_streak_q",
	"state.politics.review_fail_streak",
	"state.politics.review_pass_streak",
	"state.politics.review_receipts_accum_uu",
	"state.politics.review_outlays_accum_uu",
]
const FLOW_ARRAY_IDS: PackedStringArray = []
const FLOW_SCALAR_IDS: PackedStringArray = [
	"flow.politics.budget_review_due",
]

# ── 事件效果落点码（docs/11 §5.13 的事件可写白名单，下标即码，顺序不得改） ──
#
# 六项的规范顺序（与 JWInterestGroups 共用同一套码；那边只认 3 与 4）：
#   0 state.group.expectation_ppm      1 state.group.trust_ppm
#   2 state.group.support_ppm          3 state.bloc.org_power_ppm
#   4 state.bloc.stance_ppm            5 state.politics.admin_capacity_ppm
# 本类只接受 0、1、2、5，其余一律 WRITE_OUT_OF_SCOPE（INV-130）。
const EVT_EXPECTATION_PPM: int = 0
const EVT_TRUST_PPM: int = 1
const EVT_SUPPORT_PPM: int = 2
const EVT_ADMIN_CAPACITY_PPM: int = 5

## 主观量的上界（docs/10 §6.3）：预期 0…2e6，信任与支持 0…1e6。
## 生活指数无契约上界；它的上界由输入本身决定（归一化收入项封顶 3e6，三权重和 1e6）。
const EXPECTATION_MAX_PPM: int = 2_000_000
const LIVING_MAX_PPM: int = 3_000_000
## 归一化人均实际收入的封顶（docs/12 §8.1）。
const REAL_INCOME_NORM_MAX_PPM: int = 3_000_000
## 每次失信记 0.25（docs/12 §8.1 的 250 000 ppm）。
const BREACH_UNIT_PPM: int = 250_000
## 重大改革授权在 legal_authority_mask 里的位序（politics_init `_note_authority_bits` 第 3 位）。
const AUTHORITY_BIT_STRUCTURAL_REFORM: int = 3

## `state.group.living_index_ppm[]`，长 36，单位 ppm，初值 1 000 000，写入者 S08。
var living_index: PackedInt64Array = PackedInt64Array()
## `state.group.expectation_ppm[]`，长 36，单位 ppm，写入者 S08。
var expectation: PackedInt64Array = PackedInt64Array()
## `state.group.trust_ppm[]`，长 36，单位 ppm，写入者 S08。
var trust: PackedInt64Array = PackedInt64Array()
## `state.group.support_ppm[]`，长 36，单位 ppm，写入者 S08。
var support: PackedInt64Array = PackedInt64Array()
## 连续留任季数，长 36，单位 季，写入者 S08。
var keep_streak_q: PackedInt64Array = PackedInt64Array()

## `state.politics.seats_total`，单位 席（奇数），写入者 LOAD。
var seats_total: int = 0
## `state.politics.seats_gov`，单位 席，写入者 S08。
var seats_gov: int = 0
## `state.politics.term_index`，写入者 S08。
var term_index: int = 0
## 首次选举季（docs/17 §4.24 初值 15；INV-127 要求 q ∈ {15, 31}，q 从 0 起）。
const ELECTION_Q_FIRST: int = 15
## 第二次（也是末次）选举季（docs/17 §4.24；两次相隔 16 季）。
const ELECTION_Q_SECOND: int = 31
## 首次预算审查季（docs/17 §4.24 初值 3；INV-127 要求 `q ≡ 3 (mod 4)`）。
const BUDGET_REVIEW_Q_FIRST: int = 3
## 预算审查的周期（季）。
const BUDGET_REVIEW_PERIOD_Q: int = 4

## `state.politics.next_election_q`，单位 季 ∈ {15, 31}，写入者 S08。
## 初值 15：docs/17 §4.24 成员表与 docs/11 §5.10 politics_init 同时登记（INV-127）。
## 它必须是**声明期就成立的初值**，不能只在剧本加载路径上成立——
## 没有剧本的直接 `allocate_all()`（存档回填、单元夹具）同样要给出一个合法的选举日历，
## 否则 q = 0 会被读成「开局即选举季」。
var next_election_q: int = ELECTION_Q_FIRST
## `state.politics.next_budget_review_q`，单位 季（`q ≡ 3 (mod 4)`），写入者 S02。
## 初值 3：同上（docs/17 §4.24、docs/11 §5.10 V-POL-03）。
var next_budget_review_q: int = BUDGET_REVIEW_Q_FIRST
## `state.politics.mandate_goal`，JWUnits.MandateGoal 枚举，写入者 LOAD。
var mandate_goal: int = 0
## `state.politics.mandate_status`，JWUnits.MandateStatus 枚举，写入者 S08。
var mandate_status: int = 0
## `state.politics.admin_capacity_ppm`，单位 ppm，写入者 S07。
var admin_capacity_ppm: int = 0
## `state.politics.legal_authority_mask`，位掩码，写入者 S08。
var legal_authority_mask: int = 0
## `state.meta.run_terminated`，写入者 S08。
var run_terminated: bool = false
## `state.meta.termination_reason`，JWUnits.Termination 枚举，写入者 S08。
var termination_reason: int = 0

## `flow.politics.budget_review_due`，0/1，写入者 S02。
var f_budget_review_due: int = 0

# ── 基年基准（R-SUPPORT-01，类 C，写入者 LOAD） ─────────────────────────────
#
# 裁定 R-SUPPORT-01：`support` 必须**相对基年**计算，不得绝对加权——绝对加权在基年就给出约 87%，
# 与剧本登记的席位占比 554 455 ppm 脱节三十多个百分点，等于开局白送一个不存在的执政基础。
# 这四个数组取自剧本（population_init 的 q = 0 值），是内容常量，结算期只读。

## 基年逐组支持度，长 36，单位 ppm。
var base_support: PackedInt64Array = PackedInt64Array()
## 基年逐组生活指数，长 36，单位 ppm。
var base_living_index: PackedInt64Array = PackedInt64Array()
## 基年逐组未来预期，长 36，单位 ppm。
var base_expectation: PackedInt64Array = PackedInt64Array()
## 基年逐组程序信任，长 36，单位 ppm。
var base_trust: PackedInt64Array = PackedInt64Array()
## 四个基准各自是否已捕获的位掩码（位序 == STATE_ARRAY_IDS 的下标 0…3）。
##
## 加载器可以直接写 `base_*` 并把对应位置 1；若它还没落地这四个内容数组，
## `set_state_array()` 会在**第一次**写入某个主观量时顺带捕获基准——第一次写入必然是剧本初值，
## 之后的写入（读档回填）不会再动基准。不进哈希：它是加载路径的记账，不是模拟状态。
var base_captured_mask: int = 0

# ── 契约给了公式、但 JWUnits.Param 里没有下标的阈值（类 C，写入者 LOAD） ───
#
# 下面七个阈值都在 content/parameters/registry.json 里有正式参数卡，但 docs/17 §2.6 冻结的
# `Param` 枚举（contract_min_set 的 72 项）没有收录它们，于是运行期没有 `params[...]` 下标可取。
# 冻结的方法签名又不接受额外形参。折中取法：作为内容常量成员由 LOAD 写入，
# 默认值取同名参数卡的当前值（不是新发明的魔数，每一个都标了卡 ID）。
# 已登记为接口变更请求：正解是把它们并入 `JWUnits.Param`。

## state.event.fire_count[]：长 EVENT_N，写入者 S08（JWEventEngine.fire_events）。各事件累计触发次数。
var event_fire_count: PackedInt64Array = PackedInt64Array()
## state.event.last_fire_q[]：长 EVENT_N，初值 EVENT_NEVER_FIRED_Q，写入者 S08。各事件上次触发季。
var event_last_fire_q: PackedInt64Array = PackedInt64Array()
## 「从未触发」初值（与 JWEventEngine.NEVER_FIRED_Q 同值：任何合法冷却加上它都远小于 0）。
const EVENT_NEVER_FIRED_Q: int = -999

## `param.bloc_veto_stance_threshold_ppm`：立场低于此值且域命中才构成否决。
var veto_stance_threshold_ppm: int = -600_000
## `param.budget_review_deficit_limit_ppm`：四季赤字占四季收入的上限。
var budget_review_deficit_limit_ppm: int = 150_000
## `param.budget_review_arrears_limit_uu`：欠付存量上限。
var budget_review_arrears_limit_uu: int = 1_000_000_000
## `param.budget_review_fail_to_lost_count`：连续失败多少次直接判 lost。
var budget_review_fail_to_lost_count: int = 2
## `param.budget_review_recovery_reviews`：从 at_risk 回到 ok 需要的连续通过次数。
var budget_review_recovery_reviews: int = 2
## `param.supermajority_authority_min_seats_ppm`：留任后取得重大改革授权的席位门槛。
var supermajority_authority_min_seats_ppm: int = 666_667

## 支持度的三项贡献分解，长 108（36 × 3），单位 ppm，类 L（不进 state_hash），写入者 S08。
var _support_decomp: PackedInt64Array = PackedInt64Array()
## 本季事件对 support 的增量，长 36，单位 ppm，类 L（不进 state_hash），写入者 S08 §8.4。
## 与 `_support_decomp` 一起构成 INV-123 的完整来源记录：三项贡献 + 事件增量。
var _support_event_delta: PackedInt64Array = PackedInt64Array()
## 连续 `mandate_status == LOST` 的季数，单位 季，写入者 S08。
## （成员名沿用骨架；计数口径按 docs/12 §8.5 与 politics_init `_note_termination_triggers` 取 lost。）
var _at_risk_streak_q: int = 0
## 连续预算审查失败次数，写入者 S08。
var _review_fail_streak: int = 0
## 连续预算审查通过次数，写入者 S08。
var _review_pass_streak: int = 0
## 自上次预算审查以来累计的政府收入（μU），写入者 S08。
var _review_receipts_accum_uu: int = 0
## 自上次预算审查以来累计的政府基本支出 + 利息（μU），写入者 S08。
var _review_outlays_accum_uu: int = 0

## 消费价格指数的产品权重缓冲，长 S，类 L（热路径预分配，不在结算期新建对象）。
var _cons_weight_uqs: PackedInt64Array = PackedInt64Array()
## 人口加权的权重缓冲，长 36，类 L。
var _w_buf: PackedInt64Array = PackedInt64Array()
## 最大余数法的决胜键缓冲（恒为下标），长 36，类 L。
var _tiebreak_buf: PackedInt64Array = PackedInt64Array()
## 最大余数法拆出的份额缓冲，长 36，单位 ppm，类 L。
var _share_buf: PackedInt64Array = PackedInt64Array()


## S02 §2.8：预算审查标记（判定在 S08）。
## 步骤：S02 §2.8
## 前置：q == next_budget_review_q
## 后置：f_budget_review_due = 1；next_budget_review_q += 4
## 不变量：INV-127（预算审查在 q ≡ 3 (mod 4)）
## 失败：无
func mark_budget_review(q: int) -> int:
	if q != next_budget_review_q:
		return JWResult.OK
	# INV-127：审查只能落在 q ≡ 3 (mod 4)。落不上说明 next_budget_review_q 被写坏了，
	# 这时置位等于把一次不该发生的审查写进历史，宁可显式失败。
	if JWMath.floor_div(q, 4) * 4 + 3 != q:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, q, 3)
	f_budget_review_due = 1
	next_budget_review_q = q + 4
	return JWResult.OK


## S02：政策资格链里的「权限 / 席位 / 集团否决」判定（只读，不改状态）。
## 注意：**集团立场作为形参传入**（`bloc_stance_ppm` 数组），本类不引用 JWInterestGroups（INV-125）。
## 步骤：S02 §2.1
## 前置：authority_bit 与 min_seats_ppm 来自 JWPolicyDef
## 后置：不改状态
## 不变量：INV-099、INV-125
## 失败：返回 Reject.AUTHORITY / SEATS_SHORT / BLOC_VETO
func check_authority(authority_bit: int, min_seats_ppm: int, veto_bloc_mask: int,
		bloc_stance_ppm: PackedInt64Array, policy_idx: int) -> int:
	if policy_idx < 0 or policy_idx >= JWUnits.POLICY_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, policy_idx, JWUnits.POLICY_N)
		return JWResult.Reject.AUTHORITY
	# 1 法定权限：位没拿到就是拿不到，和席位多少无关（INV-099）。
	if authority_bit < 0 or authority_bit >= 63:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, authority_bit, 63)
		return JWResult.Reject.AUTHORITY
	if (legal_authority_mask >> authority_bit) & 1 != 1:
		return JWResult.Reject.AUTHORITY
	# 2 席位门槛：seats_gov * 1e6 / seats_total >= min_seats_ppm，
	#   交叉相乘判定，不做除法也就没有余数与它的取整方向问题。
	if seats_total <= 0:
		JWResult.raise_fault(JWResult.Fault.DIV_ZERO, seats_total, 0)
		return JWResult.Reject.SEATS_SHORT
	if JWMath.mul(seats_gov, JWUnits.PPM) < JWMath.mul(min_seats_ppm, seats_total):
		return JWResult.Reject.SEATS_SHORT
	# 3 集团否决：域命中（veto_bloc_mask 由调用方查 JWInterestGroups.has_veto 得出）
	#   **且** 该集团对该政策的立场低于阈值，两个条件同时成立才是否决。
	if veto_bloc_mask != 0:
		if bloc_stance_ppm.size() != JWUnits.STANCE_N:
			JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
					bloc_stance_ppm.size(), JWUnits.STANCE_N)
			return JWResult.Reject.BLOC_VETO
		var b: int = 0
		while b < JWUnits.BLOC_N:
			if (veto_bloc_mask >> b) & 1 == 1:
				if bloc_stance_ppm[JWIds.idx_stance(b, policy_idx)] < veto_stance_threshold_ppm:
					return JWResult.Reject.BLOC_VETO
			b += 1
	return JWResult.Reject.NONE


## S07：行政执行能力更新（只被 P11 类政策与事件影响）。
## 步骤：S07（政策效果落点）
## 前置：delta 来自白名单落点
## 后置：admin_capacity_ppm ∈ [0, 1_000_000]
## 不变量：INV-125（**实施速度函数只引用 admin_capacity_ppm**；它不进 support 公式）
## 失败：无
func set_admin_capacity(value_ppm: int) -> int:
	admin_capacity_ppm = JWMath.clamp_i(value_ppm, 0, JWUnits.PPM)
	return JWResult.OK


## S08 §8.1：三个主观量**分开更新**（生活 / 预期 / 信任）。
## 步骤：S08 §8.1
## 前置：breach_count 由 JWTurnRunner 从欠付、欠拨、项目取消、债券违约四个闭集合事件汇总；
##       consumer_index 来自 JWPricing
## 后置：三者各自 clamp 到自己的区间；keep_streak 更新
## 不变量：INV-121（三者分开存储、分开更新，禁止合成单一满意度）、
##          INV-122（**trust 的更新式里结构上不存在 transfer_income 通道**；
##          且 param.trust_recover_ppm < param.trust_drop_ppm，加载期校验）
## 失败：主观量越界 → clamp 并写 log.clamp
func update_subjective(pop: JWPopulation, pricing: JWPricing,
		breach_count_by_group: PackedInt64Array, params: PackedInt64Array) -> int:
	if living_index.size() != JWUnits.GROUP or breach_count_by_group.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				breach_count_by_group.size(), JWUnits.GROUP)
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)

	var w_house_ppm: int = params[JWUnits.Param.LIVING_WEIGHT_HOUSE_PPM]
	var w_service_ppm: int = params[JWUnits.Param.LIVING_WEIGHT_SERVICE_PPM]
	# docs/12 §8.1：收入权重是残差 1e6 − 住房 − 服务（原实现误取支持度权重 0，两者只是碰巧同值）。
	var w_income_ppm: int = maxi(0, JWUnits.PPM - w_house_ppm - w_service_ppm)
	var inertia_ppm: int = params[JWUnits.Param.EXPECTATION_INERTIA_PPM]
	var trust_drop_ppm: int = params[JWUnits.Param.TRUST_DROP_PPM]
	var trust_recover_ppm: int = params[JWUnits.Param.TRUST_RECOVER_PPM]
	var streak_cap_q: int = params[JWUnits.Param.TRUST_STREAK_CAP_Q]
	if streak_cap_q < 1:
		streak_cap_q = 1

	# 消费价格指数：把逐组逐产品的消费量汇成全国产品权重（预分配缓冲，不新建对象）。
	var s: int = 0
	while s < JWUnits.S:
		_cons_weight_uqs[s] = 0
		s += 1
	var gi: int = 0
	while gi < JWUnits.GROUP:
		var s2: int = 0
		while s2 < JWUnits.S:
			_cons_weight_uqs[s2] += pop.f_consumption_by_product_uqs[JWIds.idx_group_prod(gi, s2)]
			s2 += 1
		gi += 1
	var consumer_index_ppm: int = pricing.consumer_index_ppm(_cons_weight_uqs)
	if consumer_index_ppm < 1:
		consumer_index_ppm = 1

	var g: int = 0
	while g < JWUnits.GROUP:
		var persons_den: int = pop.population[g]
		if persons_den < 1:
			persons_den = 1

		# ── 当期生活（docs/12 §8.1） ──
		var disposable_uu: int = pop.disposable_income(g)
		var real_income_uu: int = JWMath.mul_div_floor(disposable_uu,
				JWUnits.PPM, consumer_index_ppm)
		# R-PERIOD-01：基准 base_real_income 是**年**人均，当期收入是季度流量；先年化再比，
		# 否则基年的当期生活指数恒约为 25%，开局即判执政 at_risk。年化放在除法之前以保精度。
		var per_capita_uu: int = JWMath.floor_div(JWMath.mul(real_income_uu, 4), persons_den)
		var base_pc_uu: int = pop.base_real_income[g]
		if base_pc_uu < 1:
			base_pc_uu = 1
		var real_income_norm_ppm: int = JWMath.clamp_i(
				JWMath.mul_div_floor(per_capita_uu, JWUnits.PPM, base_pc_uu),
				0, REAL_INCOME_NORM_MAX_PPM)

		# 住房负担率：本季住房支出占可支配收入的比重，封顶 1e6（收入为 0 时视为满负担）。
		# docs/10 §6.3 把 derived.group.housing_burden_ppm 列为派生量却没给公式；
		# 这里取「住房支出 / 可支配收入」，与 §8.1 里 `1e6 − housing_burden` 的用法一致。
		var housing_burden_ppm: int = JWUnits.PPM
		if disposable_uu > 0:
			housing_burden_ppm = JWMath.clamp_i(
					JWMath.mul_div_floor(pop.f_housing_cost[g], JWUnits.PPM, disposable_uu),
					0, JWUnits.PPM)
		elif pop.f_housing_cost[g] <= 0:
			housing_burden_ppm = 0

		# 服务可及性：三类服务的等权平均（医疗／教育／公用）。
		var svc_sum: int = 0
		var kind: int = 0
		while kind < JWUnits.SERVICE_KIND:
			svc_sum += pop.service_access[JWIds.idx_group_svc(g, kind)]
			kind += 1
		var service_avg_ppm: int = JWMath.floor_div(svc_sum, JWUnits.SERVICE_KIND)

		living_index[g] = JWMath.clamp_i(
				JWMath.mul_ppm(real_income_norm_ppm, w_income_ppm)
				+ JWMath.mul_ppm(JWUnits.PPM - housing_burden_ppm, w_house_ppm)
				+ JWMath.mul_ppm(service_avg_ppm, w_service_ppm),
				0, LIVING_MAX_PPM)

		# ── 未来预期：对生活指数的滞后平滑（惯性） ──
		expectation[g] = JWMath.clamp_i(
				JWMath.mul_ppm(expectation[g], inertia_ppm)
				+ JWMath.mul_ppm(living_index[g], JWUnits.PPM - inertia_ppm),
				0, EXPECTATION_MAX_PPM)

		# ── 程序信任：只受「承诺兑现与否」驱动 ──
		# 这条更新式里**结构上不存在 transfer_income 通道**（INV-122）：
		# 不是把某个系数取零，而是根本没有这条路——短期补贴修不了长期失信。
		var breach_count: int = breach_count_by_group[g]
		if breach_count < 0:
			breach_count = 0
		if breach_count == 0:
			keep_streak_q[g] = keep_streak_q[g] + 1
			if keep_streak_q[g] > streak_cap_q:
				keep_streak_q[g] = streak_cap_q
		else:
			keep_streak_q[g] = 0
		var breach_ppm: int = JWMath.clamp_i(JWMath.mul(breach_count, BREACH_UNIT_PPM),
				0, JWUnits.PPM)
		var keep_ppm: int = JWMath.clamp_i(
				JWMath.mul_div_floor(keep_streak_q[g], JWUnits.PPM, streak_cap_q),
				0, JWUnits.PPM)
		trust[g] = JWMath.clamp_i(
				trust[g]
				- JWMath.mul_ppm(trust_drop_ppm, breach_ppm)
				+ JWMath.mul_ppm(trust_recover_ppm, keep_ppm),
				0, JWUnits.PPM)
		g += 1
	return JWResult.OK


## R-SUPPORT-02：把「生活指数、未来预期、程序信任」三个基准锚定为当前值（模型口径）。
## 步骤：S08（仅第 0 季，update_subjective 之后、update_support 之前，由 JWTurnRunner 调用）
## 前置：本季三项指数已更新
## 后置：base_living_index / base_expectation / base_trust == 当前值；base_support 不变（仍为剧本值）
## 不变量：R-SUPPORT-01（相对基年）——基年 = 第 0 季结算后，剧本初值只作开局展示
## 失败：无
##
## 理由：剧本逐组登记生活指数 1 000 000，而 §8.1 的公式在住房负担为正时不可能在基年给出 1 000 000；
## 以剧本值为基准，第 0 季就有一截与玩家无关的支持度跳变（实测足以决定第 15 季选举）。
func anchor_base_to_current() -> void:
	base_living_index = living_index.duplicate()
	base_expectation = expectation.duplicate()
	base_trust = trust.duplicate()
	base_captured_mask = base_captured_mask | 0b0111


## S08 §8.2：支持度（三项加权）与来源分解。
## 步骤：S08 §8.2
## 前置：三项权重之和 == 1 000 000（加载期校验）
## 后置：support ∈ [0, 1e6]；**逐组 support 必须保留**（禁止只保留全国值）；
##       每次变动写 log.explanations 的三项贡献
## 不变量：INV-123（变动有来源分解）、INV-124（全国值只由逐组按人口最大余数法加权）、INV-125
## 失败：无来源记录 → Fault.SUPPORT_UNEXPLAINED
func update_support(pop: JWPopulation, params: PackedInt64Array) -> int:
	if support.size() != JWUnits.GROUP or base_support.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				base_support.size(), JWUnits.GROUP)
	if base_living_index.size() != JWUnits.GROUP or base_expectation.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				base_living_index.size(), JWUnits.GROUP)
	if base_trust.size() != JWUnits.GROUP or params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				base_trust.size(), JWUnits.GROUP)

	var w0: int = params[JWUnits.Param.SUPPORT_WEIGHT_PPM_0]
	var w1: int = params[JWUnits.Param.SUPPORT_WEIGHT_PPM_1]
	var w2: int = params[JWUnits.Param.SUPPORT_WEIGHT_PPM_2]

	var g: int = 0
	while g < JWUnits.GROUP:
		# 裁定 R-SUPPORT-01：相对基年映射，不是绝对加权。
		# 基年三个指数各自等于自己的基准 ⇒ 增量恒为 0 ⇒ support 恒等于剧本登记值；
		# 此后只由**变化量**驱动，政策的受益与受损仍然逐组可追溯。
		var d_living: int = living_index[g] - base_living_index[g]
		var d_expect: int = expectation[g] - base_expectation[g]
		var d_trust: int = trust[g] - base_trust[g]
		# 前缀和分解：三项贡献之和**精确等于**总增量，不是三次独立取整后再凑。
		var n0: int = JWMath.mul(w0, d_living)
		var n01: int = n0 + JWMath.mul(w1, d_expect)
		var n012: int = n01 + JWMath.mul(w2, d_trust)
		var f0: int = JWMath.floor_div(n0, JWUnits.PPM)
		var f01: int = JWMath.floor_div(n01, JWUnits.PPM)
		var f012: int = JWMath.floor_div(n012, JWUnits.PPM)
		var c0: int = f0
		var c1: int = f01 - f0
		var c2: int = f012 - f01

		var base: int = g * 3
		_support_decomp[base] = c0
		_support_decomp[base + 1] = c1
		_support_decomp[base + 2] = c2
		# 事件增量是逐季效果：support 每季由基准与三个指数重算，
		# 事件对 support 的一次性冲击只在它发生的那一季存在（持久通道是 expectation 与 trust）。
		_support_event_delta[g] = 0

		var raw: int = base_support[g] + c0 + c1 + c2
		support[g] = JWMath.clamp_i(raw, 0, JWUnits.PPM)

		# INV-123 的自检：**从来源记录里读回来**重建，必须逐位等于写下的值。
		# 读回来而不是把上面的表达式再写一遍，才能抓住「算对了但记错了」的下标错误——
		# 一个没被正确登记的来源，和没有来源是一回事。
		var rebuilt: int = JWMath.clamp_i(
				base_support[g] + _support_decomp[base] + _support_decomp[base + 1]
				+ _support_decomp[base + 2], 0, JWUnits.PPM)
		if support[g] != rebuilt:
			return JWResult.raise_fault(JWResult.Fault.SUPPORT_UNEXPLAINED, g, support[g])
		g += 1
	return JWResult.OK


## 全国支持度：逐组 support 按人口最大余数法加权（**不是独立字段**）。
## 步骤：S08 §8.2、S08 §8.5、报告
## 前置：update_support 已完成
## 后置：不改状态
## 不变量：INV-124（全国值只由逐组按人口最大余数法加权）
## 失败：无
func support_national_ppm(pop: JWPopulation) -> int:
	# 分母不含未成年人口（politics_init `_note_resident_support`：选民口径）。
	var g: int = 0
	while g < JWUnits.GROUP:
		_tiebreak_buf[g] = g
		if JWIds.age_of_group(g) == JWUnits.Age.MINOR:
			_w_buf[g] = 0
		else:
			_w_buf[g] = pop.population[g]
		g += 1
	return _weighted_support_ppm()


## 分区支持度：该区各组 support 按人口最大余数法加权。
## 步骤：S08 §8.2、报告
## 前置：update_support 已完成；r ∈ [0, JWUnits.R)
## 后置：不改状态
## 不变量：INV-124
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回 0
func support_region_ppm(pop: JWPopulation, r: int) -> int:
	if r < 0 or r >= JWUnits.R:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, r, JWUnits.R)
		return 0
	var g: int = 0
	while g < JWUnits.GROUP:
		_tiebreak_buf[g] = g
		if JWIds.region_of_group(g) != r or JWIds.age_of_group(g) == JWUnits.Age.MINOR:
			_w_buf[g] = 0
		else:
			_w_buf[g] = pop.population[g]
		g += 1
	return _weighted_support_ppm()


## 用 _w_buf 里的人口权重把逐组 support 加权成一个 ppm（最大余数法）。
## 步骤：S08 §8.2
## 前置：_w_buf / _tiebreak_buf 已填好
## 后置：不改状态（只动类 L 缓冲）
## 不变量：INV-124（份额精确加总到 1e6，全程整数）
## 失败：拆分失败 → 返回 0
func _weighted_support_ppm() -> int:
	# 先把人口权重用最大余数法拆成精确加总为 1e6 的份额，再用份额做一次加权求和：
	# 全流程只有最后一次取整，份额之和恒为 1e6，所以结果恒在 [0, 1e6]。
	# 返回值非 0 有两种含义：权重全 0 时是「一分未拆」的残差，否则是故障码。
	# 两种情形下 _share_buf 都已被清零，加权和自然是 0，所以统一返回 0 即可。
	if JWMath.split_lr_into(JWUnits.PPM, _w_buf, _tiebreak_buf, _share_buf) != 0:
		return 0
	var num: int = 0
	var g: int = 0
	while g < JWUnits.GROUP:
		num += JWMath.mul(support[g], _share_buf[g])
		g += 1
	return JWMath.clamp_i(JWMath.floor_div(num, JWUnits.PPM), 0, JWUnits.PPM)


## 席位转换规则（**纯函数**，OQ-221 的首版取法：按支持度比例 + 最大余数法）。
## 步骤：S08 §8.5
## 前置：support_national_ppm ∈ [0, 1e6]；seats_total > 0 且为奇数
## 后置：0 <= seats_gov <= seats_total；整数、最大余数法
## 不变量：INV-126（纯函数）、INV-125（**静态检查：本函数不引用 org_power_ppm 与 admin_capacity_ppm**）
## 失败：无
static func seat_rule(support_national_ppm: int, seats_total: int) -> int:
	if seats_total <= 0:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, seats_total, 0)
		return 0
	var sup: int = JWMath.clamp_i(support_national_ppm, 0, JWUnits.PPM)
	# 等价于 split_largest_remainder(seats_total, [1e6 − sup, sup], [0, 1])[1]：
	# 权重表把反对方放在下标 0、执政方放在下标 1，于是余数并列时那 1 席归**反对方**。
	# 这是 politics_init `_note_separation_of_three` 的裁定：支持度恰好 50% 要判为失去执政资格。
	var num_gov: int = JWMath.mul(seats_total, sup)
	var num_opp: int = JWMath.mul(seats_total, JWUnits.PPM - sup)
	var base_gov: int = JWMath.floor_div(num_gov, JWUnits.PPM)
	var base_opp: int = JWMath.floor_div(num_opp, JWUnits.PPM)
	var rem_gov: int = num_gov - base_gov * JWUnits.PPM
	var rem_opp: int = num_opp - base_opp * JWUnits.PPM
	var seats: int = base_gov
	if base_gov + base_opp < seats_total and rem_gov > rem_opp:
		seats += 1
	return JWMath.clamp_i(seats, 0, seats_total)


## S08 §8.5：预算审查、选举、留任与终局。
## 步骤：S08 §8.5
## 前置：选举只在 q ∈ {15, 31}；审查在 f_budget_review_due == 1 的季
## 后置：seats_gov 更新；`seats_gov * 2 <= seats_total` ⇒ 终止（刚好过半算失去）；
##       连续 no_confidence_q 季 mandate_status == LOST ⇒ 终止；
##       连续 default_grace_q 季付不出第 1 档 ⇒ 终止；q == horizon_q − 1 ⇒ 终止
## 不变量：INV-127（选举与审查季度）、INV-128（**终局判定式中不含任何 GDP 项**，静态检查；
##          终止后任何 advance_quarter 返回 REJECT 且状态哈希不变）
## 失败：无（终止是正常结果，不是故障）
func review_and_terminate(treasury: JWTreasury, pop: JWPopulation, q: int, horizon_q: int,
		default_streak_q: int, params: PackedInt64Array) -> int:
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	if run_terminated:
		# 已经终止的这一局不再改任何政治状态：状态哈希必须逐位不变（INV-128）。
		return JWResult.OK

	# ── 四季窗口的滚动累计（docs/18 R-SEASON-01 的同一口径：借款不是收入，还本不是支出） ──
	_review_receipts_accum_uu += treasury.f_receipts_income_tax
	_review_receipts_accum_uu += treasury.f_receipts_profit_tax
	_review_receipts_accum_uu += treasury.f_receipts_other
	_review_outlays_accum_uu += treasury.f_primary_paid
	_review_outlays_accum_uu += treasury.f_interest_paid

	# ── 预算审查（judgment 在 S08，置位在 S02） ──
	if f_budget_review_due == 1:
		var receipts: int = _review_receipts_accum_uu
		var outlays: int = _review_outlays_accum_uu
		var deficit: int = outlays - receipts
		var failed: bool = false
		# docs/12 §8.5 的判据是「**连续赤字超限**或欠付超限」——超限才是失败依据，
		# 「本季做了一次审查」本身不是。所以这里只在真有赤字时才去比阈值：
		# deficit <= 0（盈余，或四季窗口内收支皆为 0）一律不构成超限。
		if deficit > 0:
			if receipts <= 0:
				# 有赤字而零收入：赤字／收入无上界，必然超过任何有限的 limit_ppm。
				# 单独成支，既表达了判据也避开了除零。
				failed = true
			else:
				# R-SCALE-01：先乘后除一律走 mul_div_floor。
				# 交叉相乘 deficit * PPM 在新刻度下会真的溢出 int64，而 JWMath.mul 溢出时
				# 登记 INT_OVERFLOW 并返回 0——那会把一次超限的审查悄悄判成通过。
				var deficit_ratio_ppm: int = JWMath.mul_div_floor(deficit, JWUnits.PPM, receipts)
				if deficit_ratio_ppm > budget_review_deficit_limit_ppm:
					failed = true
		if treasury.arrears > budget_review_arrears_limit_uu:
			failed = true

		if failed:
			_review_fail_streak += 1
			_review_pass_streak = 0
			if _review_fail_streak == 1 and mandate_status == JWUnits.MandateStatus.OK:
				mandate_status = JWUnits.MandateStatus.AT_RISK
			if _review_fail_streak >= budget_review_fail_to_lost_count:
				mandate_status = JWUnits.MandateStatus.LOST
			# 审查失败即失去重大改革授权（politics_init `_note_budget_review`）。
			legal_authority_mask = legal_authority_mask \
					& ~(1 << AUTHORITY_BIT_STRUCTURAL_REFORM)
		else:
			_review_fail_streak = 0
			_review_pass_streak += 1
			# 恢复慢于恶化：一次失败即 at_risk，回到 ok 需要连续通过；lost 不因通过恢复。
			if mandate_status == JWUnits.MandateStatus.AT_RISK \
					and _review_pass_streak >= budget_review_recovery_reviews:
				mandate_status = JWUnits.MandateStatus.OK
		_review_receipts_accum_uu = 0
		_review_outlays_accum_uu = 0

	# ── 选举（INV-127：只在第 16、32 季，q 从 0 起） ──
	if q == ELECTION_Q_FIRST or q == ELECTION_Q_SECOND:
		seats_gov = seat_rule(support_national_ppm(pop), seats_total)
		term_index += 1
		if JWMath.mul(seats_gov, 2) > seats_total:
			# 留任：席位达到超级多数门槛才拿到重大改革授权，否则明确收回。
			var held: int = JWMath.mul(seats_gov, JWUnits.PPM)
			var need: int = JWMath.mul(supermajority_authority_min_seats_ppm, seats_total)
			if held >= need:
				legal_authority_mask = legal_authority_mask \
						| (1 << AUTHORITY_BIT_STRUCTURAL_REFORM)
			else:
				legal_authority_mask = legal_authority_mask \
						& ~(1 << AUTHORITY_BIT_STRUCTURAL_REFORM)
		else:
			run_terminated = true
			termination_reason = JWUnits.Termination.LOST_ELECTION
		if q == ELECTION_Q_FIRST:
			next_election_q = ELECTION_Q_SECOND
		# 选举留任不清除 at_risk：财政问题不会因为赢得选举而消失。

	# ── 不信任：连续 param.no_confidence_q 季 mandate_status == lost ──
	if mandate_status == JWUnits.MandateStatus.LOST:
		_at_risk_streak_q += 1
	else:
		_at_risk_streak_q = 0
	var no_confidence_q: int = params[JWUnits.Param.NO_CONFIDENCE_Q]
	if not run_terminated and no_confidence_q > 0 and _at_risk_streak_q >= no_confidence_q:
		run_terminated = true
		termination_reason = JWUnits.Termination.LOST_CONFIDENCE

	# ── 财政重组失败：连续 param.default_grace_q 季付不出支付优先级第 1 档 ──
	var grace_q: int = params[JWUnits.Param.DEFAULT_GRACE_Q]
	if not run_terminated and grace_q > 0 and default_streak_q >= grace_q:
		run_terminated = true
		termination_reason = JWUnits.Termination.FISCAL_RESTRUCTURING_FAILED

	# ── 到期：正常结束，不是失败 ──
	if not run_terminated and q == horizon_q - 1:
		run_terminated = true
		termination_reason = JWUnits.Termination.HORIZON

	# 以上四条判定式中没有出现任何 GDP、增加值或产出项：经济下滑本身不是失败（INV-128）。
	return JWResult.OK


## 事件效果落点（只允许白名单内的 ppm 增量）。
## 步骤：S08 §8.4
## 前置：target ∈ {expectation_ppm, trust_ppm, support_ppm, admin_capacity_ppm}
## 后置：对应字段加 delta 后 clamp
## 不变量：INV-130（事件不得直接写现金、库存、产能、人口；首版事件无任何账本效应）
## 失败：target 不在白名单 → Fault.WRITE_OUT_OF_SCOPE
func apply_event_delta(target_code: int, scope_idx: int, delta_ppm: int) -> int:
	if target_code == EVT_ADMIN_CAPACITY_PPM:
		admin_capacity_ppm = JWMath.clamp_i(admin_capacity_ppm + delta_ppm, 0, JWUnits.PPM)
		return JWResult.OK
	if target_code != EVT_EXPECTATION_PPM and target_code != EVT_TRUST_PPM \
			and target_code != EVT_SUPPORT_PPM:
		# 现金、库存、产能、人口都在这里被挡住：首版事件没有任何账本效应。
		return JWResult.raise_fault(JWResult.Fault.WRITE_OUT_OF_SCOPE, target_code, scope_idx)
	if scope_idx < 0 or scope_idx >= JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, scope_idx, JWUnits.GROUP)
	if target_code == EVT_EXPECTATION_PPM:
		expectation[scope_idx] = JWMath.clamp_i(expectation[scope_idx] + delta_ppm,
				0, EXPECTATION_MAX_PPM)
		return JWResult.OK
	if target_code == EVT_TRUST_PPM:
		trust[scope_idx] = JWMath.clamp_i(trust[scope_idx] + delta_ppm, 0, JWUnits.PPM)
		return JWResult.OK
	var before: int = support[scope_idx]
	support[scope_idx] = JWMath.clamp_i(before + delta_ppm, 0, JWUnits.PPM)
	# 记下事件这一路的实际增量（夹逼后），与 _support_decomp 的三项一起构成完整来源（INV-123）。
	_support_event_delta[scope_idx] += support[scope_idx] - before
	return JWResult.OK


## §1.6 状态块协议：LOAD 期一次性 resize 到 §2 的契约长度。
## 步骤：LOAD
## 前置：维度常量已确定
## 后置：五个状态数组长 JWUnits.GROUP；_support_decomp 长 GROUP * 3；
##       政治日历两个标量回到 docs/17 §4.24 的契约初值（15 / 3）
## 不变量：docs/10 §0.6（加载期一次性 resize）
## 失败：无
func allocate() -> void:
	living_index.resize(JWUnits.GROUP)
	living_index.fill(0)
	expectation.resize(JWUnits.GROUP)
	expectation.fill(0)
	trust.resize(JWUnits.GROUP)
	trust.fill(0)
	support.resize(JWUnits.GROUP)
	support.fill(0)
	keep_streak_q.resize(JWUnits.GROUP)
	keep_streak_q.fill(0)

	base_support.resize(JWUnits.GROUP)
	base_support.fill(0)
	base_living_index.resize(JWUnits.GROUP)
	base_living_index.fill(0)
	base_expectation.resize(JWUnits.GROUP)
	base_expectation.fill(0)
	base_trust.resize(JWUnits.GROUP)
	base_trust.fill(0)
	event_fire_count.resize(JWUnits.EVENT_N)
	event_fire_count.fill(0)
	event_last_fire_q.resize(JWUnits.EVENT_N)
	event_last_fire_q.fill(EVENT_NEVER_FIRED_Q)

	_support_decomp.resize(JWUnits.GROUP * 3)
	_support_decomp.fill(0)
	_support_event_delta.resize(JWUnits.GROUP)
	_support_event_delta.fill(0)
	_cons_weight_uqs.resize(JWUnits.S)
	_cons_weight_uqs.fill(0)
	_w_buf.resize(JWUnits.GROUP)
	_w_buf.fill(0)
	_tiebreak_buf.resize(JWUnits.GROUP)
	_tiebreak_buf.fill(0)
	_share_buf.resize(JWUnits.GROUP)
	_share_buf.fill(0)

	# 政治日历的两个契约初值（docs/17 §4.24 成员表、docs/11 §5.10）：
	# 重新 allocate 必须把它们放回合法值，否则「先 allocate 再读档失败」会留下 q = 0 的日历。
	# 剧本加载器随后按 politics_init 覆写它们（systems/content_loader.gd 的 slot 3 / 4）。
	next_election_q = ELECTION_Q_FIRST
	next_budget_review_q = BUDGET_REVIEW_Q_FIRST


## §1.6 状态块协议：按下标只读取用状态数组（返回引用，调用方不得写）。
## 步骤：加载、哈希、存档
## 前置：i ∈ [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136（下标顺序是 schema 的一部分）
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回空数组
func state_array(i: int) -> PackedInt64Array:
	if i == 8:
		return event_fire_count
	if i == 9:
		return event_last_fire_q
	if i == 0:
		return living_index
	if i == 1:
		return expectation
	if i == 2:
		return trust
	if i == 3:
		return support
	if i == 4:
		return keep_streak_q
	if i == 5:
		return base_living_index
	if i == 6:
		return base_expectation
	if i == 7:
		return base_trust
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
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				i, STATE_ARRAY_IDS.size())
	if i == 8 or i == 9:
		# R-EVENT-01：事件计数按事件下标（长 EVENT_N），不按群组。
		if v.size() != JWUnits.EVENT_N:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v.size(), JWUnits.EVENT_N)
		if i == 8:
			event_fire_count = v.duplicate()
		else:
			event_last_fire_q = v.duplicate()
		return JWResult.OK
	if v.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v.size(), JWUnits.GROUP)
	if i == 0:
		living_index = v
	elif i == 1:
		expectation = v
	elif i == 2:
		trust = v
	elif i == 3:
		support = v
	elif i == 4:
		keep_streak_q = v
	else:
		# R-SUPPORT-02：读档回填第 0 季锚定的基准（不走下面的「首次写入即捕获」）。
		if i == 5:
			base_living_index = v.duplicate()
		elif i == 6:
			base_expectation = v.duplicate()
		else:
			base_trust = v.duplicate()
		base_captured_mask = base_captured_mask | (1 << (i - 5))
		return JWResult.OK
	# R-SUPPORT-01 的基年基准：**第一次**写入必然是剧本初值，就地捕获；
	# 之后的写入（读档回填状态）不再改基准，否则读档会把基准挪到存档那一季。
	if i <= 3 and (base_captured_mask >> i) & 1 == 0:
		if i == 0:
			base_living_index = v.duplicate()
		elif i == 1:
			base_expectation = v.duplicate()
		elif i == 2:
			base_trust = v.duplicate()
		else:
			base_support = v.duplicate()
		base_captured_mask = base_captured_mask | (1 << i)
	return JWResult.OK


## §1.6 状态块协议：按下标读取状态标量（`run_terminated` 以 0/1 编码）。
## 步骤：加载、哈希、存档
## 前置：i ∈ [0, STATE_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回 0
func state_scalar(i: int) -> int:
	if i == 0:
		return seats_total
	if i == 1:
		return seats_gov
	if i == 2:
		return term_index
	if i == 3:
		return next_election_q
	if i == 4:
		return next_budget_review_q
	if i == 5:
		return mandate_goal
	if i == 6:
		return mandate_status
	if i == 7:
		return admin_capacity_ppm
	if i == 8:
		return legal_authority_mask
	if i == 9:
		return 1 if run_terminated else 0
	if i == 10:
		return termination_reason
	if i == 11:
		return _at_risk_streak_q
	if i == 12:
		return _review_fail_streak
	if i == 13:
		return _review_pass_streak
	if i == 14:
		return _review_receipts_accum_uu
	if i == 15:
		return _review_outlays_accum_uu
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


## §1.6 状态块协议：写入状态标量，**仅 LOAD / MIG**（`run_terminated` 以 0/1 解码）。
## 步骤：LOAD / MIG
## 前置：调用点位于 systems/content_loader.gd 或 systems/saves.gd（静态检查）
## 后置：对应成员被写
## 不变量：INV-136
## 失败：越界 → 返回 Fault.INDEX_OUT_OF_RANGE
func set_state_scalar(i: int, v: int) -> int:
	if i == 0:
		seats_total = v
	elif i == 1:
		seats_gov = v
	elif i == 2:
		term_index = v
	elif i == 3:
		next_election_q = v
	elif i == 4:
		next_budget_review_q = v
	elif i == 5:
		mandate_goal = v
	elif i == 6:
		mandate_status = v
	elif i == 7:
		admin_capacity_ppm = v
	elif i == 8:
		legal_authority_mask = v
	elif i == 9:
		run_terminated = v != 0
	elif i == 10:
		termination_reason = v
	elif i == 11:
		_at_risk_streak_q = v
	elif i == 12:
		_review_fail_streak = v
	elif i == 13:
		_review_pass_streak = v
	elif i == 14:
		_review_receipts_accum_uu = v
	elif i == 15:
		_review_outlays_accum_uu = v
	else:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				i, STATE_SCALAR_IDS.size())
	return JWResult.OK


## §1.6 状态块协议：按下标只读取用流量数组（本块无流量数组）。
## 步骤：报告、哈希对账
## 前置：i ∈ [0, FLOW_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-013
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回空数组
func flow_array(i: int) -> PackedInt64Array:
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
		return f_budget_review_due
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_SCALAR_IDS.size())
	return 0


## §1.6 状态块协议：全部 FLOW_* 归零，**仅 S01**。
## 步骤：S01 §01.3
## 前置：调用点位于 systems/turn_runner.gd 的 _step_s01（静态检查）
## 后置：f_budget_review_due == 0
## 不变量：INV-013
## 失败：无
func reset_flows() -> void:
	f_budget_review_due = 0


## §1.6 状态块协议：S01 清零后的自检，非 0 即 FLOW_NOT_RESET。
## 步骤：S01 §01.3 末
## 前置：reset_flows() 刚被调用
## 后置：不改状态
## 不变量：INV-013
## 失败：无
func flow_abs_sum() -> int:
	return JWMath.absi(f_budget_review_due)


## §1.6 状态块协议：读档时写回流量标量（R-SAVE-01，由 tools/gen_flow_setters.py 按 flow_scalar 逐项对称生成）。
## 步骤：LOAD
## 前置：无
## 后置：对应成员被赋值
## 不变量：INV-133
## 失败：下标越界 → INDEX_OUT_OF_RANGE
func set_flow_scalar(i: int, v: int) -> int:
	if i == 0:
		f_budget_review_due = v
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_SCALAR_IDS.size())
