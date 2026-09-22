## 项目 SoA（只增不删）、施工能力分配、进度推进、按进度付款。
## 付款不制造进度（INV-087）：construction_progress 的形参表里没有 paid_uu（静态检查）。
##
## status 的五个写入者为什么不互相放大：五处各自只做单向的状态跃迁，且跃迁图是无环的：
## planned →(S02) in_progress →(S04/S05) suspended →(S02) in_progress →(S07) completed →(S01) commissioned，
## cancelled 是 S02 的终态。set_status() 是唯一的写入函数，内部用一张 5×6 的合法跃迁表拦截非法跃迁。
##
## 已签承诺（INV-032）的三个变动点全部在本类，且都走 JWTreasury.record_commitment：
##   签约 +：start()（planned → in_progress）；履约付款 −：record_payment()；取消 −：cancel()。
## planned 表示「已批准、已占槽位、尚未签约」——它身上没有承诺，取消它也就没有冲减与赔偿。
##
## 骨架依据：docs/17_api_skeleton.md §4.19（start() 为实现期新增，见其注释）。
class_name JWProjectQueue
extends RefCounted

# ───────────────── §1.6 状态块协议的注册表 ─────────────────

## 本块各数组所属子系统（与 STATE_ARRAY_IDS 等长），用于 subsystem_hash 与 WriteGuard。
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_PROJECT, JWUnits.SUBSYS_PROJECT, JWUnits.SUBSYS_PROJECT, JWUnits.SUBSYS_PROJECT,
	JWUnits.SUBSYS_PROJECT, JWUnits.SUBSYS_PROJECT, JWUnits.SUBSYS_PROJECT, JWUnits.SUBSYS_PROJECT,
	JWUnits.SUBSYS_PROJECT, JWUnits.SUBSYS_PROJECT, JWUnits.SUBSYS_PROJECT, JWUnits.SUBSYS_PROJECT,
	JWUnits.SUBSYS_PROJECT, JWUnits.SUBSYS_PROJECT, JWUnits.SUBSYS_PROJECT, JWUnits.SUBSYS_PROJECT,
	JWUnits.SUBSYS_PROJECT, JWUnits.SUBSYS_PROJECT, JWUnits.SUBSYS_PROJECT,
	JWUnits.SUBSYS_PROJECT, JWUnits.SUBSYS_PROJECT, JWUnits.SUBSYS_PROJECT, JWUnits.SUBSYS_PROJECT,
]

## 稳定 ID 注册表：下标 == 数组序号，内容是 docs/10 的稳定 ID 字符串。
## 只在加载与哈希时被读，结算期不触碰（无 String 进入热路径）。
## 注：state.project.id[] 是 PackedStringArray，§1.6 协议没有给它访问器，
## 由 JWSimState 的 SoA ids[] 规范化编码单独处理（docs/17 §6.1），故不出现在本表。
const STATE_ARRAY_IDS: PackedStringArray = [
	"state.project.policy_idx",
	"state.project.region_idx",
	"state.project.status",
	"state.project.total_cost_uu",
	"state.project.planned_quarters",
	"state.project.spend_plan_uu",
	"state.project.paid_uu",
	"state.project.delivery_progress_ppm",
	"state.project.construction_progress_ppm",
	"state.project.required_construction_uqs",
	"state.project.required_equipment_uqs",
	"state.project.queue_slot_held",
	"state.project.capacity_effect_uqs_per_q",
	"state.project.capacity_target",
	"state.project.opex_per_q_uu",
	"state.project.commissioned_q",
	"state.project.residual_value_uu",
	"state.project.cancel_penalty_uu",
	"state.project.suspension_reason",
	# R-DEFER-01：合同延期（命令 6）的跨季记忆。
	"state.project.defer_count",
	"state.project.defer_quarters_total",
	"state.project.defer_until_q",
	"state.project.defer_fee_uu",
]
const STATE_SCALAR_IDS: PackedStringArray = [
	"state.project.count",
]

## 两个 flow.region.* 归 SUBSYS_REGION（docs/17 §4.19）。
const FLOW_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_REGION, JWUnits.SUBSYS_REGION,
]
const FLOW_ARRAY_IDS: PackedStringArray = [
	"flow.region.construction_capacity_uqs",
	"flow.region.construction_used_uqs",
]
const FLOW_SCALAR_IDS: PackedStringArray = []

# ────────── 结构常量 ──────────

## 三条支出线：0 进口设备 / 1 国产材料 / 2 施工服务（docs/11 §5.12 spend_lines_uu_per_q）
const LINE_N: int = 3
const LINE_IMPORT_EQUIPMENT: int = 0
const LINE_DOMESTIC_MATERIAL: int = 1
const LINE_CONSTRUCTION_SERVICE: int = 2

## launch() 的「未入队」返回值（成功时返回新项目下标，恒 >= 0）。
## LAUNCH_NO_SLOT 同时是各故障路径的返回值——那些路径都已登记故障，本季结算会因此中止，
## 调用方把它译成 Reject.NO_SLOT 不会掩盖任何东西。
const LAUNCH_NO_SLOT: int = -1
## 规模缩放后合同退化（合同额为 0，或每季计划施工量不足 1 μQ），调用方译成 Reject.PARAM_RANGE。
const LAUNCH_DEGENERATE_SCALE: int = -2

## 合法状态跃迁表，5 行（from，CANCELLED 是终态故无行）× 6 列（to）；1 == 合法。
## 跃迁图（docs/17 §4.19）：
##   planned →(S02) in_progress →(S04/S05) suspended →(S02) in_progress →(S07) completed
##   →(S01) commissioned；cancelled 是 S02 的终态，可从 planned / in_progress / suspended 进入。
## 恒等跃迁（to == from）不在图内，一律非法 —— 「再挂起一次」这种重复写入必须被抓住，
## 而不是被当成幂等操作放行。
const STATUS_TRANSITIONS: PackedInt64Array = [
	0, 1, 0, 0, 0, 1,
	0, 0, 1, 1, 0, 1,
	0, 1, 0, 0, 0, 1,
	0, 0, 0, 0, 1, 0,
	0, 0, 0, 0, 0, 0,
]
## STATUS_TRANSITIONS 的行数（可作为 from 的状态数）
const STATUS_FROM_N: int = 5
## STATUS_TRANSITIONS 的列数（全部状态数）
const STATUS_TO_N: int = 6

# ────────── 成员变量（SoA，容量 PROJECT_CAP0，实际长度 count） ──────────

## 运行期项目 ID（entity_seq 派生），只用于故障包／存档／报告，不进热路径。写入者 S02
var id: PackedStringArray = PackedStringArray()
## 0..11，写入者 S02
var policy_idx: PackedInt64Array = PackedInt64Array()
## 0..3，写入者 S02
var region_idx: PackedInt64Array = PackedInt64Array()
## JWUnits.ProjectStatus，写入者 S01（completed→commissioned）, S02, S04, S05, S07
var status: PackedInt64Array = PackedInt64Array()
## μU，写入者 S02
var total_cost: PackedInt64Array = PackedInt64Array()
## 季，写入者 S02
var planned_quarters: PackedInt64Array = PackedInt64Array()
## μU（按 p*3+line），写入者 S02
var spend_plan: PackedInt64Array = PackedInt64Array()
## μU（按 p*3+line），写入者 S04
var paid: PackedInt64Array = PackedInt64Array()
## ppm，写入者 S05
var delivery_progress: PackedInt64Array = PackedInt64Array()
## ppm，写入者 S05
var construction_progress: PackedInt64Array = PackedInt64Array()
## μQ_services，写入者 S02
var required_construction: PackedInt64Array = PackedInt64Array()
## μQ_manu，写入者 S02
var required_equipment: PackedInt64Array = PackedInt64Array()
## 0/1，写入者 S02, S07
var slot_held: PackedInt64Array = PackedInt64Array()
## μQ/季，写入者 S02
var capacity_effect: PackedInt64Array = PackedInt64Array()
## 效果落点码，写入者 S02
var capacity_target: PackedInt64Array = PackedInt64Array()
## μU，写入者 S02
var opex_per_q: PackedInt64Array = PackedInt64Array()
## 季，−1 未投运，写入者 S01
var commissioned_q: PackedInt64Array = PackedInt64Array()
## μU，写入者 S02, S07
var residual_value: PackedInt64Array = PackedInt64Array()
## μU，写入者 S02
var cancel_penalty: PackedInt64Array = PackedInt64Array()
## JWUnits.SuspendReason，写入者 S02, S04, S05
var suspension_reason: PackedInt64Array = PackedInt64Array()
## state.project.defer_count —— 已受理的延期次数（R-DEFER-01，上限 param.max_defer_count）
var defer_count: PackedInt64Array = PackedInt64Array()
## state.project.defer_quarters_total —— 各次延期季数之和（上限 param.max_defer_quarters）
var defer_q_total: PackedInt64Array = PackedInt64Array()
## state.project.defer_until_q —— 延期到期季：S02 在 q >= 本值时复工（未延期 == 0）
var defer_until_q: PackedInt64Array = PackedInt64Array()
## state.project.defer_fee_uu —— 累计延期赔偿（μU；已付与转欠付之和）
var defer_fee: PackedInt64Array = PackedInt64Array()

## flow.region.construction_capacity_uqs：μQ_services，写入者 S05
var f_construction_capacity: PackedInt64Array = PackedInt64Array()
## flow.region.construction_used_uqs：μQ_services，写入者 S05
var f_construction_used: PackedInt64Array = PackedInt64Array()

## 项目数（SoA 实际长度），写入者 S02
var count: int = 0

# ── 预分配 scratch（热路径不新建对象，§1.4） ──

## 本季计划施工量，长度 PROJECT_CAP0；非本区域／非在建的项目位恒为 0
var _need: PackedInt64Array = PackedInt64Array()
## split_lr_into 的产出缓冲，长度 PROJECT_CAP0
var _grant: PackedInt64Array = PackedInt64Array()
## 最大余数法的决胜键 == 项目下标（「按 project 下标升序」），长度 PROJECT_CAP0
var _tiebreak: PackedInt64Array = PackedInt64Array()
## 三条支出线的权重缓冲
var _line_w: PackedInt64Array = PackedInt64Array()
## 三条支出线的决胜键（0/1/2）
var _line_tb: PackedInt64Array = PackedInt64Array()
## 三条支出线的拆分产出
var _line_out: PackedInt64Array = PackedInt64Array()

# ───────────────────────── 方法 ─────────────────────────

## S02 §2.7：新建项目，占用施工槽位，展开分季支出计划。
## 步骤：S02 §2.7
## 前置：region 有空槽（derived.slots_used < slots_total）；Σ spend_plan == total_cost（精确）
## 后置：新项目入 SoA，slot_held = 1，status = PLANNED；ID 来自 entity_seq
## 不变量：INV-092（Σ spend_plan == total_cost）、INV-094（Σ slot_held <= slots_total）、INV-010
## 失败：无空槽 → 返回 LAUNCH_NO_SLOT(-1)，调用方置 blocked_reason = QUEUE 并 REJECT(Reject.NO_SLOT)；
##       规模小到合同退化 → 返回 LAUNCH_DEGENERATE_SCALE(-2)，调用方 REJECT(Reject.PARAM_RANGE)
##
## 注：形参 policy_idx 与同名成员数组重名（签名冻结，不改名）。函数体内写成员数组时
## 一律用 self.policy_idx[...]，读形参时用裸名，二者不会混。
##
## scale_ppm（docs/18 R-PROJECT-01 ⑤；policy_P04.json player_params.scale_ppm 的缩放口径）：
## 合同总额、所需施工量、所需设备量、完工新增产能、每季运行费一律 mul_ppm 同倍缩放（floor），
## 支出计划再用最大余数法把缩放后的总额拆成三条支出线（Σ 精确等于缩放后的总额，INV-003/092）；
## planned_quarters 不随规模变化。缺省 PPM 即满规模，与签名冻结前的行为逐位相同。
## 「退化」指缩放后合同额为 0，或所需施工量不足以让每季计划施工量（floor(需求 / 工期)）至少为 1——
## 那样的项目永远推进不了，却会一直占着槽位与承诺。
func launch(entity_seq: int, policy_idx: int, region: int, defs: JWPolicyDef,
		capital: JWCapital, q: int, scale_ppm: int = JWUnits.PPM) -> int:
	if policy_idx < 0 or policy_idx >= JWUnits.POLICY_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, policy_idx, JWUnits.POLICY_N)
		return -1
	if region < 0 or region >= JWUnits.R:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, region, JWUnits.R)
		return -1
	if q < 0 or entity_seq < 0:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, q, entity_seq)
		return -1
	if defs == null or capital == null:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, 0)
		return -1
	# SoA 只增不删，容量是编译期常量：满了就是满了，不在热路径扩容（§1.4）。
	if count < 0 or count >= JWUnits.PROJECT_CAP0:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, count, JWUnits.PROJECT_CAP0)
		return -1
	if status.size() < JWUnits.PROJECT_CAP0 or spend_plan.size() < JWUnits.PROJECT_CAP0 * LINE_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, status.size(),
				JWUnits.PROJECT_CAP0)
		return -1

	# INV-094：槽位是硬上限，满则不入队（调用方置 blocked_reason = QUEUE 并 REJECT(NO_SLOT)）。
	if slots_used(region) >= capital.slots_total(region):
		return -1

	var pol: int = policy_idx
	# defs 的每张表都必须覆盖到 pol：内容包没装满时宁可拒绝入队，也不能越界读到别的政策的数。
	if defs.cost_one_off_uu.size() <= pol or defs.planned_quarters.size() <= pol \
			or defs.required_construction_uqs.size() <= pol \
			or defs.required_equipment_uqs.size() <= pol \
			or defs.effect_magnitude.size() <= pol or defs.effect_target.size() <= pol \
			or defs.opex_per_q_uu.size() <= pol:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, pol,
				defs.cost_one_off_uu.size())
		return -1
	# V-PD-03：one_off_uu == per_quarter_uu × planned_quarters，合同总额取 one_off_uu。
	var cost_full: int = defs.cost_one_off_uu[pol]
	var quarters: int = defs.planned_quarters[pol]
	if cost_full <= 0 or quarters <= 0:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cost_full, quarters)
		return -1
	var req_con_full: int = defs.required_construction_uqs[pol]
	var req_eqp_full: int = defs.required_equipment_uqs[pol]
	# docs/10 §8.1：required_construction_uqs > 0（加载期 V-PD 保证）。这里再拦一次，
	# 否则 S05 的 Δ进度 除法会在结算期炸成 DIV_ZERO —— 入队时挡住比结算时崩掉便宜。
	if req_con_full <= 0 or req_eqp_full < 0:
		JWResult.raise_fault(JWResult.Fault.DIV_ZERO, req_con_full, req_eqp_full)
		return -1
	# scale_ppm 的值域由提交期（JWCommands._validate_row 的 [0, PPM]）挡住；负值走到这里是调用方缺陷。
	if scale_ppm < 0:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, scale_ppm, JWUnits.PPM)
		return -1
	# 同倍缩放。满规模（scale_ppm == PPM）时 mul_ppm 是恒等变换，逐位不变。
	# rounding: floor, reason=M1（mul_ppm），缩放后的合同额少记不多记，差额不进任何人的账
	var cost: int = JWMath.mul_ppm(cost_full, scale_ppm)
	# rounding: floor, reason=M1，所需施工量随规模缩放
	var req_con: int = JWMath.mul_ppm(req_con_full, scale_ppm)
	# rounding: floor, reason=M1，所需设备量随规模缩放（缩到 0 即「无设备需求」，交付腿天然满足）
	var req_eqp: int = JWMath.mul_ppm(req_eqp_full, scale_ppm)
	# 退化的合同不入队：合同额为 0 的项目没有可签的承诺；每季计划施工量
	# floor(req_con / quarters) 为 0 的项目在 advance_progress 里永远推进不了，却会一直占着槽位。
	# rounding: floor, reason=与 advance_progress ① 的 per_q 同一口径
	if cost <= 0 or JWMath.floor_div(req_con, quarters) <= 0:
		return LAUNCH_DEGENERATE_SCALE
	# INV-007：合同总额不得越过金额上限，否则后续的 ppm 折算会顶到 int64 天花板。
	if cost > JWUnits.AMOUNT_MAX:
		JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, cost, JWUnits.AMOUNT_MAX)
		return -1

	# 分项支出计划：按三条支出线的季度额做权重，用最大余数法把合同总额拆成三份，
	# Σ 精确等于 total_cost（INV-092）。不用「季度额 × 季数」直接相乘：
	# V-PD-03 虽然保证了两者相等，但一旦内容包有误差，相乘会把误差留在账上而不报错。
	if _line_w.size() != LINE_N or _line_tb.size() != LINE_N or _line_out.size() != LINE_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, _line_w.size(), LINE_N)
		return -1
	for line: int in LINE_N:
		_line_w[line] = defs.spend_line(pol, line)
		_line_tb[line] = line
	var split_rc: int = JWMath.split_lr_into(cost, _line_w, _line_tb, _line_out)
	if split_rc != JWResult.OK:
		# split_rc != 0 有两种：故障码，或「权重全 0 时交回的残差 == cost」。
		# 两种都意味着 Σ spend_plan != total_cost，都不允许入队（INV-092）。
		JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, cost, split_rc)
		return -1

	var p: int = count
	id[p] = "project.q%03d_%d" % [q, entity_seq]
	self.policy_idx[p] = pol
	region_idx[p] = region
	status[p] = JWUnits.ProjectStatus.PLANNED
	total_cost[p] = cost
	planned_quarters[p] = quarters
	for line: int in LINE_N:
		spend_plan[p * LINE_N + line] = _line_out[line]
		paid[p * LINE_N + line] = 0
	delivery_progress[p] = 0
	construction_progress[p] = 0
	required_construction[p] = req_con
	required_equipment[p] = req_eqp
	slot_held[p] = 1
	# rounding: floor, reason=M1，完工新增产能与合同同倍缩放（P04 player_params.scale_ppm）
	capacity_effect[p] = JWMath.mul_ppm(defs.effect_magnitude[pol], scale_ppm)
	capacity_target[p] = defs.effect_target[pol]
	# rounding: floor, reason=M1，投运后每季运行费与合同同倍缩放
	opex_per_q[p] = JWMath.mul_ppm(defs.opex_per_q_uu[pol], scale_ppm)
	commissioned_q[p] = -1
	residual_value[p] = 0
	cancel_penalty[p] = 0
	suspension_reason[p] = JWUnits.SuspendReason.NONE
	defer_count[p] = 0
	defer_q_total[p] = 0
	defer_until_q[p] = 0
	defer_fee[p] = 0
	count = p + 1
	return p


## S02 §2.2 / §2.7：签约开工 —— 把合同总额计入已签承诺，并执行 planned → in_progress。
## 步骤：S02 §2.7（紧随 launch() 之后，由 JWTurnRunner 在同一条立项命令里调用）
## 前置：status == PLANNED（launch() 刚建出、尚未签约的项目）
## 后置：committed_memo += total_cost（INV-032「新签合同 +」）；status == IN_PROGRESS
## 不变量：INV-032、INV-092（Σ spend_plan == total_cost，故签入的正是之后逐季履约冲减的那笔）
## 失败：非 PLANNED → Reject.PRECONDITION（状态不变）；承诺登记的故障原样返回（此时不跃迁）
##
## 为什么独立成一步而不塞进 launch()：launch() 的冻结签名里没有 treasury，
## 而「签约即占用未来预算承诺」（计划书 §07、docs/30 T-U-D-08）必须落在 committed_memo 上。
## PLANNED 因此只表示「已批准、占了槽位、尚未签约」；未签约的项目没有承诺、没有合同，
## 取消它既不冲减承诺也不产生赔偿（见 cancel()）。签约与跃迁同在本函数内完成，
## 「status 已离开 PLANNED ⇔ 合同额已计入 committed_memo」由此按构造成立，cancel() 据此判断该冲减多少。
func start(p: int, treasury: JWTreasury) -> int:
	if p < 0 or p >= count:
		return JWResult.Reject.NOT_FOUND
	if treasury == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, 0)
	if status[p] != JWUnits.ProjectStatus.PLANNED:
		return JWResult.Reject.PRECONDITION
	var cost: int = total_cost[p]
	if cost <= 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, p, cost)
	# 先登记承诺、后跃迁：承诺登记失败时项目仍是未签约的 PLANNED，两者不会半成立。
	var rc: int = treasury.record_commitment(cost)
	if rc != JWResult.OK:
		return rc
	return set_status(p, JWUnits.ProjectStatus.IN_PROGRESS, JWUnits.SuspendReason.NONE)


## S02：挂起项目复工（docs/18 R-PROJECT-01 ⑤：「S02 须有 SUSPENDED → IN_PROGRESS 的恢复路径」）。
## 步骤：S02（命令受理之前，由 JWTurnRunner._step_s02 调用）
## 前置：无
## 后置：本季开始时处于 SUSPENDED 的项目全部回到 IN_PROGRESS，suspension_reason 清为 NONE
## 不变量：INV-087（只改状态，不写 paid 与任何进度字段）、INV-094（挂起期间一直占着槽位，复工不新占）、
##          INV-032（承诺不因挂起／复工变动）
## 失败：状态跃迁表拒绝 → 原样返回 set_status 的故障码（SUSPENDED → IN_PROGRESS 在表内，走不到）
##
## 为什么无条件复工：两种挂起原因都由之后的步骤按**本季**的实况重判——
##   FINANCING：S04 §4.4 照常开出本季应付（支付前融资 R-FINANCE-01 之后仍付不足，record_payment 再挂起）；
##   CONGESTION：S05 §5.5 按本季实际施工能力重新配额（仍分不到能力，advance_progress 再挂起）。
## 这两个条件在 S02 这一刻都无从复核：施工能力是 S05 才折出的本季流量，现金要过了 S03/S04 才定。
## 「条件满足才复工」只能拿上季的旧数判，而项目一旦挂起就再也不会被 S04/S05 看到——
## 原实现正是如此：跃迁表里有 SUSPENDED → IN_PROGRESS 这条边，却没有任何调用者，挂起即永久停工。
## 复工只让项目重新进入本季的付款与配额，不给它任何东西：付款仍按分期表（_installment_due），
## 进度仍只由实投施工量与实际到货量决定（INV-087/089）。
## 例外（R-DEFER-01）：玩家延期（DEFERRED）不是本季实况能重判的挂起，到 defer_until_q 才复工。
func resume_suspended(q: int) -> int:
	var rc: int = JWResult.OK
	for p: int in count:
		if status[p] != JWUnits.ProjectStatus.SUSPENDED:
			continue
		if suspension_reason[p] == JWUnits.SuspendReason.DEFERRED and q < defer_until_q[p]:
			continue
		var ts: int = set_status(p, JWUnits.ProjectStatus.IN_PROGRESS, JWUnits.SuspendReason.NONE)
		if ts != JWResult.OK and rc == JWResult.OK:
			rc = ts
	return rc


## S02：合同延期（命令 6；docs/18 R-DEFER-01，docs/31 ADV-F04 / Q-ADV-01）。
## 步骤：S02（命令受理；resume_suspended 之后，故到期的延期已先复工）
## 前置：项目存在且 status == IN_PROGRESS（已签约、未完工、不在延期中）
## 后置：status = SUSPENDED(DEFERRED)，defer_until_q = q + quarters：期间 S04 不开应付、S05 不配施工能力；
##       槽位照占（INV-094，否则延期成了免费保留队列位置）；承诺不变（INV-032）；
##       延期赔偿 = floor(剩余合同额 × 每季赔偿率 × quarters)，当季按三条线的剩余额拆给承包方，
##       现金不足转欠付——与取消赔偿同一条过账路径（kind 27 合同赔偿，三口径全 none）
## 不变量：INV-032、INV-087（不写任何进度字段）、INV-094、INV-016
## 失败：项目不存在 → Reject.NOT_FOUND；非 IN_PROGRESS、次数或累计季数超限 → Reject.PRECONDITION（状态不变）
##
## 为什么赔偿当季一次付清而不逐季摊：延期的代价必须在做决定的那一季就看得见（ADV-G02「藏账」：
## 把难看的账推过选举季）。逐季摊付会让延期在当季显得免费。
func defer(p: int, quarters: int, q: int, params: PackedInt64Array, treasury: JWTreasury,
		ledger: JWLedger, accounts: JWAccount) -> int:
	if p < 0 or p >= count:
		return JWResult.Reject.NOT_FOUND
	if treasury == null or ledger == null or accounts == null or params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, params.size())
	if quarters < 1:
		return JWResult.Reject.PARAM_RANGE
	if status[p] != JWUnits.ProjectStatus.IN_PROGRESS:
		# 未签约（PLANNED）没有合同可延；已完工、已投运、已取消不是延期对象；
		# 已在延期中的项目要等复工之后才能再延（那算一次新的延期）。
		return JWResult.Reject.PRECONDITION
	if defer_count[p] >= params[JWUnits.Param.MAX_DEFER_COUNT]:
		return JWResult.Reject.PRECONDITION
	if defer_q_total[p] + quarters > params[JWUnits.Param.MAX_DEFER_QUARTERS]:
		return JWResult.Reject.PRECONDITION
	var remaining: int = committed_remaining(p)
	var rate: int = JWMath.clamp_i(params[JWUnits.Param.DEFER_FEE_PPM_PER_Q] * quarters, 0, JWUnits.PPM)
	# rounding: floor, reason=赔偿按合同比例折算，少付 1 μU 优于凭空多付
	var fee: int = JWMath.mul_ppm(remaining, rate)
	var rc: int = set_status(p, JWUnits.ProjectStatus.SUSPENDED, JWUnits.SuspendReason.DEFERRED)
	if rc != JWResult.OK:
		return rc
	defer_count[p] += 1
	defer_q_total[p] += quarters
	defer_until_q[p] = q + quarters
	if fee > 0:
		defer_fee[p] += fee
		rc = _pay_cancel_penalty_lines(p, fee, treasury, ledger, accounts)
	return rc


## S02 §2.7：取消项目。已付不退、现金不增加。
## 步骤：S02 §2.7
## 前置：项目存在且未完工
## 后置：committed_memo 减去剩余合同额；penalty 与 residual_value 均入账；释放槽位；
##       status = CANCELLED
## 不变量：INV-093（paid_uu 不回退）、INV-032（取消不退还已付的钱）、INV-094、
##          INV-016（赔偿先看现金再过账，不足转欠付）、INV-027（赔偿计入基本支出实付）
## 失败：项目不存在 → Reject.NOT_FOUND；已完工／已投运／已取消 → Reject.PRECONDITION
##
## 本函数是取消结算的**唯一执行点**：承诺冲减、赔偿、残值与损失、释放槽位、落终态一次做完。
## docs/17 §5.2 第 3 条紧随其后调用的 JWAssetCommissioning.pay_cancel_penalty /
## register_residual 对已取消的项目只做核对、不再过账——三处各做一遍，赔偿就会被付两次、
## 在建工程就会被减记两次（后者在 wip 不足时直接撞 LEDGER_IMBALANCE，ADV-F01/F02/F06 的码 22）。
func cancel(p: int, defs: JWPolicyDef, treasury: JWTreasury, ledger: JWLedger,
		accounts: JWAccount, capital: JWCapital) -> int:
	if p < 0 or p >= count:
		return JWResult.Reject.NOT_FOUND
	if defs == null or treasury == null or ledger == null or accounts == null or capital == null:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, 0)
		return JWResult.Reject.NOT_FOUND
	var st: int = status[p]
	if st == JWUnits.ProjectStatus.COMPLETED or st == JWUnits.ProjectStatus.COMMISSIONED \
			or st == JWUnits.ProjectStatus.CANCELLED:
		# 已完工／已投运／已取消都不是「取消」的合法对象；不是故障，是被拒绝的命令。
		return JWResult.Reject.PRECONDITION

	var rc: int = JWResult.OK
	if st == JWUnits.ProjectStatus.PLANNED:
		# 未签约（尚未经 start() 开工）：没有计入 committed_memo 的承诺可冲减，没有合同就没有赔偿，
		# 也不可能有已付款（S04 只付 IN_PROGRESS 的项目）。只释放槽位、落终态。
		cancel_penalty[p] = 0
		residual_value[p] = 0
	else:
		rc = _settle_signed_cancel(p, defs, treasury, ledger, accounts)

	# 释放槽位并落终态（INV-094）。
	slot_held[p] = 0
	var ts: int = set_status(p, JWUnits.ProjectStatus.CANCELLED, JWUnits.SuspendReason.NONE)
	if ts != JWResult.OK and rc == JWResult.OK:
		rc = ts
	return rc


## S04 §4.4：项目履约付款的应付清单（三条 spend_line 各有收款方）。
## 本步不写任何进度字段。
## 步骤：S04 §4.4
## 前置：status == IN_PROGRESS
## 后置：out_payee 与 out_due 填好（进口设备 → agent.row，国产材料 → cell.manu，
##       施工服务 → cell.services）
## 不变量：INV-087（付款与进度无数据依赖）、INV-092
## 失败：无
func payment_due_into(out_project: PackedInt64Array, out_line: PackedInt64Array,
		out_payee_agent: PackedInt64Array, out_due: PackedInt64Array, q: int) -> int:
	var cap: int = out_project.size()
	if out_line.size() != cap or out_payee_agent.size() != cap or out_due.size() != cap:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cap, out_line.size())
		return 0
	if q < 0:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, q, 0)
		return 0
	var n: int = 0
	for p: int in count:
		if status[p] != JWUnits.ProjectStatus.IN_PROGRESS:
			continue
		var quarters: int = planned_quarters[p]
		if quarters <= 0:
			JWResult.raise_fault(JWResult.Fault.DIV_ZERO, p, quarters)
			continue
		for line: int in LINE_N:
			var due: int = _installment_due(p, line)
			if due <= 0:
				continue
			if n >= cap:
				# 缓冲不够是调用方给错了尺寸，显式登记，不静默截断清单。
				JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, n, cap)
				return n
			out_project[n] = p
			out_line[n] = line
			out_payee_agent[n] = _payee_agent(region_idx[p], line)
			out_due[n] = due
			n += 1
	return n


## S04 §4.4：回写实付，增 wip，资金不足转 suspended(financing)。
## 步骤：S04 §4.4
## 前置：paid <= 该分项剩余合同额
## 后置：paid_uu 增加；flow.gov.pay_project_uu[p] 增加；committed_memo 减去实付（INV-032「履约付款 −」）；
##       不足 → status = SUSPENDED, reason = FINANCING，已付不退
## 不变量：INV-087, INV-092（Σ paid <= Σ spend_plan）、INV-032
## 失败：超付 → 拒绝该笔并记 Reject.OVERPAY 诊断（不是 Fault），项目转 SUSPENDED；
##       承诺不足以冲减实付 → Fault.LEDGER_IMBALANCE（签约时没有登记承诺，上游违反 INV-032）
func record_payment(p: int, line: int, paid_uu: int, treasury: JWTreasury) -> int:
	if p < 0 or p >= count or line < 0 or line >= LINE_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, line)
	if treasury == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, 0)
	if paid_uu < 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, p, paid_uu)
	var i: int = p * LINE_N + line
	var remaining: int = spend_plan[i] - paid[i]
	if remaining < 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, i, remaining)
	if paid_uu > remaining:
		# 超付：拒绝整笔（不截到剩余额），项目转 suspended。这是诊断不是故障（docs/12 §4.3）。
		_suspend_if_running(p, JWUnits.SuspendReason.FINANCING)
		return JWResult.Reject.OVERPAY

	var due: int = _installment_due(p, line)
	paid[i] += paid_uu
	var rc: int = JWResult.OK
	if paid_uu > 0:
		# flow.gov.pay_project_uu[p]（docs/10 §3.2，写入者 S04，按项目登记）走 treasury 的登记入口，
		# 不直接写别人的字段；该入口只做分项归集，不动 primary_paid（这笔钱在 pay_line 里已计过）。
		rc = treasury.record_line_attribution(JWUnits.PayLine.PROJECT_CONTRACTS, p, paid_uu)
		# INV-032「履约付款 −」：付掉的部分不再是未来承诺（docs/30 T-U-D-08：签 4 → 付 0.5 → 3.5）。
		# 承诺在签约时由 start() 计入；memo 装不下实付即签约登记缺失，record_commitment 登记故障且不改 memo。
		var rc_c: int = treasury.record_commitment(-paid_uu)
		if rc == JWResult.OK:
			rc = rc_c
	# gov.wip_uu 的增加只能经 JWLedger 的分录发生（INV-022：余额唯一写入口在 ledger）。
	# 本函数拿不到 ledger/accounts（签名冻结），wip 腿由 S04 项目档的付款过账一并写出：
	# JWTreasury.pay_line 对 PROJECT_PAYMENT 过四腿分录（docs/18 R-PROJECT-01 ①，docs/12 §4.4
	# 「gov.wip_uu += pay_uu」），故这里的 paid 增量与 gov 在建工程的增量逐 μU 相等。
	# 本函数只回写 paid、流量、承诺与状态，不碰任何进度字段（INV-087）。
	if paid_uu < due:
		# 欠付：已付部分不退，项目挂起等资金（docs/12 §4.4）。
		_suspend_if_running(p, JWUnits.SuspendReason.FINANCING)
	return rc


## S05 §5.5：从服务 cell 的实际产量折出本地区施工能力（不是由付款折出）。
## 步骤：S05 §5.5
## 前置：svc_output_uqs 由 JWTurnRunner 从 JWSectorModel 取来（数组形参，避免反向依赖）
## 后置：f_construction_capacity[r] = mul_ppm(svc_out, construction_share_cap_ppm)；
##       该份额从服务的市场可售量中扣除（由 JWInventory 在算 supply 时读本字段）
## 不变量：INV-088、INV-058（施工受能力与槽位双重约束）
## 失败：无
func compute_construction_capacity(svc_output_uqs: PackedInt64Array,
		params: PackedInt64Array) -> int:
	if svc_output_uqs.size() < JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				svc_output_uqs.size(), JWUnits.CELL)
	if params.size() < JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	if f_construction_capacity.size() != JWUnits.R:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				f_construction_capacity.size(), JWUnits.R)
	var share: int = params[JWUnits.Param.CONSTRUCTION_SHARE_CAP_PPM]
	if share < 0 or share > JWUnits.PPM:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, share, JWUnits.PPM)
	for r: int in JWUnits.R:
		var svc_out: int = svc_output_uqs[JWIds.idx_cell(r, JWUnits.Sector.SERVICES)]
		if svc_out < 0:
			return JWResult.raise_fault(JWResult.Fault.NEGATIVE_INVENTORY, r, svc_out)
		f_construction_capacity[r] = JWMath.mul_ppm(svc_out, share)
	return JWResult.OK


## S05 §5.5：推进施工进度与交付进度。形参表中没有 paid_uu（INV-087 的静态防线）。
## 步骤：S05 §5.5
## 前置：compute_construction_capacity 已完成；设备到货量受 world.delivery_capacity 约束
## 后置：Δconstruction = floor(grant × 1e6 / required_construction)；
##       Δdelivery = floor(delivered × 1e6 / required_equipment)；两者都 clamp 到 [0, 1e6]；
##       grant == 0 且 need > 0 → status = SUSPENDED, reason = CONGESTION
## 不变量：INV-087, INV-088, INV-089（交付只由实际到货量决定）
## 失败：required_* == 0 → Fault.DIV_ZERO（加载期 V-PD 已保证 > 0，此处是兜底）
func advance_progress(world: JWWorldMarket, ledger: JWLedger, accounts: JWAccount) -> int:
	if world == null or ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, count, 0)
	if _need.size() != JWUnits.PROJECT_CAP0 or _grant.size() != JWUnits.PROJECT_CAP0 \
			or _tiebreak.size() != JWUnits.PROJECT_CAP0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				_need.size(), JWUnits.PROJECT_CAP0)
	if f_construction_capacity.size() != JWUnits.R or f_construction_used.size() != JWUnits.R:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				f_construction_used.size(), JWUnits.R)
	if count <= 0:
		return JWResult.OK

	var rc: int = JWResult.OK
	# INV-104：全部项目设备到货共用本季剩余的外部交付额度，逐项扣减，不许各算各的。
	var deliver_budget: int = world.delivery_remaining(JWUnits.Sector.MANU)
	if deliver_budget < 0:
		deliver_budget = 0
	var delivered_total: int = 0

	for r: int in JWUnits.R:
		for i: int in JWUnits.PROJECT_CAP0:
			_need[i] = 0
		# ① 本季计划施工量（只由工期与剩余工程量决定，与 paid_uu 无任何数据依赖，INV-087）
		var need_sum: int = 0
		for p: int in count:
			if region_idx[p] != r or status[p] != JWUnits.ProjectStatus.IN_PROGRESS:
				continue
			var quarters: int = planned_quarters[p]
			var req_con: int = required_construction[p]
			if quarters <= 0 or req_con <= 0:
				rc = JWResult.raise_fault(JWResult.Fault.DIV_ZERO, p, req_con)
				continue
			var done: int = JWMath.mul_div_floor(req_con, construction_progress[p], JWUnits.PPM)
			var left: int = req_con - done
			if left < 0:
				left = 0
			var per_q: int = JWMath.floor_div(req_con, quarters)
			var nd: int = per_q
			if left < nd:
				nd = left
			_need[p] = nd
			need_sum += nd
		if need_sum <= 0:
			continue

		# ② 按能力配额（最大余数法，决胜键 == 项目下标升序），Σ grant 精确等于可分配量
		var cap_r: int = f_construction_capacity[r]
		if cap_r < 0:
			cap_r = 0
		var alloc: int = cap_r
		if need_sum < alloc:
			alloc = need_sum
		var srp: int = JWMath.split_lr_into(alloc, _need, _tiebreak, _grant)
		if srp != JWResult.OK:
			rc = JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, alloc, srp)
			continue

		# ③ 逐项目推进两条进度并登记占用
		var used: int = 0
		for p: int in count:
			if region_idx[p] != r or status[p] != JWUnits.ProjectStatus.IN_PROGRESS:
				continue
			var req_con2: int = required_construction[p]
			if req_con2 <= 0:
				continue
			var g: int = _grant[p]
			used += g
			if g > 0:
				var d_con: int = JWMath.mul_div_floor(g, JWUnits.PPM, req_con2)
				construction_progress[p] = JWMath.clamp_i(
						construction_progress[p] + d_con, 0, JWUnits.PPM)

			# 交付进度：只由实际到货设备量决定（INV-089），到货量受本季外部交付额度约束。
			var req_eqp: int = required_equipment[p]
			if req_eqp <= 0:
				# 无设备需求的项目，交付这条腿天然满足；否则永远到不了完工充要条件。
				delivery_progress[p] = JWUnits.PPM
			elif deliver_budget > 0:
				var done_e: int = JWMath.mul_div_floor(req_eqp, delivery_progress[p], JWUnits.PPM)
				var left_e: int = req_eqp - done_e
				if left_e < 0:
					left_e = 0
				# docs/12 §5.5：delivered_uqs = min(**本季已订设备量**, 本季剩余交付额度)。
				# 「已订」不是工期表上的应订量：设备订单由 S04 §4.4 的进口设备付款腿产生
				# （「import_equipment -> agent.row，同时增 flow.world.imports_*」），
				# 没下单就没有货在路上，外部交付额度再富余也交付不出东西来。
				# 用累计口径（已订总量 − 已到货总量）而不是「本季新订量」：
				# 一季的港口拥堵若让当季订单作废，required_equipment 就再也交不齐，
				# 项目会被一次瞬时冲击永久钉死在 delivery_progress < 1e6 上（违反 §7.1 的可完工性）。
				# 注意这不触碰 INV-087：那条只约束 construction_progress 与 paid_uu 的函数依赖，
				# 交付腿由 §5.5 明文挂在「已订量」上，而进度增量仍只由**实际到货量** deliv 折出（INV-089）。
				var plan_e: int = spend_plan[p * LINE_N + LINE_IMPORT_EQUIPMENT]
				var ordered_e: int = req_eqp
				if plan_e > 0:
					# 设备线合同额 → 已订实物量，按该线已付比例折算（先乘后除走 mul_div_floor）。
					ordered_e = JWMath.mul_div_floor(req_eqp,
							paid[p * LINE_N + LINE_IMPORT_EQUIPMENT], plan_e)
					if ordered_e > req_eqp:
						ordered_e = req_eqp
				# plan_e == 0（设备线无合同额）时订购闸是空的：没有可付的款，也就没有可卡的订单，
				# 全部需求都算已订 —— 否则这类项目的交付腿会被一个恒为 0 的闸永久卡死。
				var want: int = ordered_e - done_e
				if want < 0:
					want = 0
				if left_e < want:
					want = left_e
				var deliv: int = want
				if deliver_budget < deliv:
					deliv = deliver_budget
				if deliv > 0:
					deliver_budget -= deliv
					delivered_total += deliv
					var d_del: int = JWMath.mul_div_floor(deliv, JWUnits.PPM, req_eqp)
					delivery_progress[p] = JWMath.clamp_i(
							delivery_progress[p] + d_del, 0, JWUnits.PPM)
					ledger.log_physical(JWIds.AGENT_ROW, -1, JWUnits.Sector.MANU,
							deliv, JWUnits.Kind.IMPORT)

			# 拥堵：有活干却一点能力也没分到（docs/12 §5.5 与 §5.9 的失败行为表）
			if g == 0 and _need[p] > 0:
				var ts: int = set_status(p, JWUnits.ProjectStatus.SUSPENDED,
						JWUnits.SuspendReason.CONGESTION)
				if ts != JWResult.OK:
					rc = ts
		f_construction_used[r] += used

	# 到货设备占用的外部交付额度一次性回写（金额腿在 S04 §4.4 的进口设备付款处登记，
	# 此处只登记实物量，避免同一笔进口的额度被扣两次）。见返回值 interface_requests。
	if delivered_total > 0:
		var ri: int = world.record_import(JWUnits.Sector.MANU, delivered_total, 0)
		if ri != JWResult.OK:
			rc = ri
	return rc


## 状态跃迁的唯一写入函数（内部查合法跃迁表）。
## 步骤：S01, S02, S04, S05, S07
## 前置：(from, to) 在合法跃迁表内
## 后置：status[p] == to；不合法则不改并返回错误
## 不变量：INV-090（完工充要条件由 JWAssetCommissioning 判定，本函数只执行跃迁）
## 失败：非法跃迁 → Fault.PHASE_VIOLATION
func set_status(p: int, to: int, reason: int) -> int:
	if p < 0 or p >= count:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, count)
	if to < 0 or to >= STATUS_TO_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, to, STATUS_TO_N)
	if reason < 0 or reason > JWUnits.SuspendReason.DEFERRED:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, reason,
				JWUnits.SuspendReason.DEFERRED)
	var from: int = status[p]
	if from < 0 or from >= STATUS_FROM_N:
		# CANCELLED（== STATUS_FROM_N）是终态，没有出边；越界同理。
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, from, to)
	if STATUS_TRANSITIONS[from * STATUS_TO_N + to] != 1:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, from, to)
	status[p] = to
	suspension_reason[p] = reason
	return JWResult.OK


## 某区域已占用的施工槽位数。
## 步骤：全部
## 前置：r ∈ [0,4)
## 后置：不改状态
## 不变量：INV-094（Σ slot_held <= slots_total）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func slots_used(r: int) -> int:
	if r < 0 or r >= JWUnits.R:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, r, JWUnits.R)
		return 0
	var n: int = 0
	for i: int in count:
		if region_idx[i] == r and slot_held[i] == 1:
			n += 1
	return n


## 进度是否双满（delivery == 1e6 且 construction == 1e6）。完工的必要条件，不是充分条件。
## 步骤：S07 §7.1
## 前置：p ∈ [0, count)
## 后置：不改状态
## 不变量：INV-090（充要条件三项齐全由 JWAssetCommissioning 判定）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 false
func progress_ready(p: int) -> bool:
	if p < 0 or p >= count:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, count)
		return false
	return delivery_progress[p] == JWUnits.PPM and construction_progress[p] == JWUnits.PPM


## 读取项目状态码。
## 步骤：全部
## 前置：p ∈ [0, count)
## 后置：不改状态
## 不变量：INV-090
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func status_of(p: int) -> int:
	if p < 0 or p >= count:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, count)
		return 0
	return status[p]


## 读取项目所在地区下标。
## 步骤：全部
## 前置：p ∈ [0, count)
## 后置：不改状态
## 不变量：INV-094
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func region_of(p: int) -> int:
	if p < 0 or p >= count:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, count)
		return 0
	return region_idx[p]


## 剩余合同额（Σ spend_plan − Σ paid），取消时用来冲减 committed_memo。
## 步骤：S02 §2.7、S04 §4.4
## 前置：p ∈ [0, count)
## 后置：不改状态
## 不变量：INV-092（Σ paid <= Σ spend_plan，故返回值 >= 0）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func committed_remaining(p: int) -> int:
	if p < 0 or p >= count:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, count)
		return 0
	var rem: int = 0
	for line: int in LINE_N:
		rem += spend_plan[p * LINE_N + line] - paid[p * LINE_N + line]
	if rem < 0:
		# INV-092 破裂：付出去的比签下的还多。显式登记，返回 0 而不是负的「负承诺」。
		JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, p, rem)
		return 0
	return rem


# ───────────────── 内部辅助（不进契约，仅本文件使用） ─────────────────

## 已签约项目的取消结算（cancel() 的主体）：承诺冲减 → 赔偿 → 残值与损失。
## 返回第一个非 OK 的码。登记了故障之后仍把其余几笔结完：故障会让本季中止并导出现场，
## 而取消命令已经落地的部分必须与状态一致（docs/12 §9「不回滚到看起来正常的状态」）。
## 三处「上游漏记」都**只登记、不截断**：截断 memo 或损失就是替上游把账抹平（docs/31 §0.2 的第四类）。
func _settle_signed_cancel(p: int, defs: JWPolicyDef, treasury: JWTreasury, ledger: JWLedger,
		accounts: JWAccount) -> int:
	var rc: int = JWResult.OK
	var pol: int = policy_idx[p]
	var remaining: int = committed_remaining(p)

	# ① 剩余合同额从已签承诺里冲掉（docs/12 §2.7；INV-032「取消 −」）。走 treasury 的唯一入口：
	#    memo 装不下本项目的剩余合同额 ⇒ 签约或履约的登记漏了一笔，record_commitment 登记
	#    LEDGER_IMBALANCE 且不改 memo。
	if remaining > 0:
		var rc_c: int = treasury.record_commitment(-remaining)
		if rc_c != JWResult.OK:
			rc = rc_c

	# ② 赔偿 = 剩余合同额 × exit_rule.compensation_ppm，按三条线的剩余额拆给各自的承包方。
	var comp_ppm: int = 0
	if pol >= 0 and pol < defs.exit_compensation_ppm.size():
		comp_ppm = defs.exit_compensation_ppm[pol]
	var penalty: int = 0
	if comp_ppm < 0 or comp_ppm > JWUnits.PPM:
		# V-PD 在加载期已保证 [0, 1e6]；越界是装填缺陷。登记故障，不夹逼后照付。
		var rc_r: int = JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, comp_ppm, JWUnits.PPM)
		if rc == JWResult.OK:
			rc = rc_r
	else:
		# rounding: floor, reason=赔偿按合同比例折算，少付 1 μU 优于凭空多付
		penalty = JWMath.mul_ppm(remaining, comp_ppm)
	cancel_penalty[p] = penalty
	if penalty > 0:
		var rc_p: int = _pay_cancel_penalty_lines(p, penalty, treasury, ledger, accounts)
		if rc_p != JWResult.OK and rc == JWResult.OK:
			rc = rc_p

	# ③ 残值与损失：已付的钱不退（INV-093 / INV-032）。「已形成的可回收部分」留在在建工程里作残值，
	#    超出残值的部分确认为损失（政府净值减少，docs/12 §2.7）。
	#    逐支出线按各自对应的实物进度折算：设备线看交付进度，材料与施工线看施工进度。
	#    契约没有给残值公式，此处取「每条线的可回收部分 <= 该线已付额」的保守口径：
	#    mul_ppm(已付, 进度 <= 1e6) <= 已付，故 residual <= Σpaid 按构造成立（INV-093）。
	var paid_total: int = 0
	var residual: int = 0
	for line: int in LINE_N:
		var pl: int = paid[p * LINE_N + line]
		paid_total += pl
		var prog: int = construction_progress[p]
		if line == LINE_IMPORT_EQUIPMENT:
			prog = delivery_progress[p]
		# rounding: floor, reason=残值宁可少估，不得凭空多出可回收资产
		residual += JWMath.mul_ppm(pl, JWMath.clamp_i(prog, 0, JWUnits.PPM))
	if residual < 0 or residual > paid_total:
		var rc_v: int = JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, residual, paid_total)
		if rc == JWResult.OK:
			rc = rc_v
		return rc
	residual_value[p] = residual
	var loss: int = paid_total - residual
	if loss > 0:
		# 已付款项按 INV-092 全部计入 gov.wip_uu，本项目的在建工程至少有 paid_total 在账上。
		# wip 装不下本项目的损失 ⇒ 付款时的 wip 腿没记（上游违反 INV-092）：显式登记，不截断损失。
		var wip: int = accounts.get_balance(JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_WIP))
		if wip < loss:
			var rc_w: int = JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, wip, loss)
			if rc == JWResult.OK:
				rc = rc_w
		else:
			var wo: int = ledger.post_noncash(JWUnits.Kind.WRITEOFF, JWIds.AGENT_GOV,
					JWIds.ACC_WIP, -loss, JWUnits.Kind.WRITEOFF, p)
			if wo != JWResult.OK and rc == JWResult.OK:
				rc = wo
	return rc


## 付合同赔偿（取消赔偿与 R-DEFER-01 的延期赔偿共用）：按三条线的剩余合同额拆分，
## 逐笔「先看现金、再过账、再登记流量」，不足转欠付。
## 为什么先看现金：post() 在现金不足时登记 NEGATIVE_CASH 故障（INV-016 的第一现场），
## 而这里的现金不足是业务性短缺（docs/12 §0.6 的 ARREARS），只能转欠付，不能先撞故障再补救。
## 为什么要登记流量：S02/S06 的 INV-027 现金恒等式只认 primary_paid 解释的流出，
## 赔偿不计入就是一笔账上找不到来源的现金减少。
func _pay_cancel_penalty_lines(p: int, penalty: int, treasury: JWTreasury, ledger: JWLedger,
		accounts: JWAccount) -> int:
	for line: int in LINE_N:
		var rem_line: int = spend_plan[p * LINE_N + line] - paid[p * LINE_N + line]
		_line_w[line] = rem_line if rem_line > 0 else 0
		_line_tb[line] = line
	# penalty > 0 ⇒ 剩余合同额 > 0 ⇒ 至少一条线的权重 > 0，「权重全 0 交回残差」的分支走不到。
	var srp: int = JWMath.split_lr_into(penalty, _line_w, _line_tb, _line_out)
	if srp != JWResult.OK:
		return JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, penalty, srp)
	var r: int = region_idx[p]
	var gov_cash: int = JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH)
	for line: int in LINE_N:
		var due: int = _line_out[line]
		if due <= 0:
			continue
		var payee: int = _payee_agent(r, line)
		# 逐笔重读余额：上一笔已经把现金花掉了。
		var pay: int = accounts.cash_of(JWIds.AGENT_GOV)
		if pay > due:
			pay = due
		if pay > 0:
			var prc: int = ledger.post(JWUnits.Kind.CANCEL_PENALTY, gov_cash,
					JWIds.idx_account(payee, JWIds.ACC_CASH), pay, 0, -1,
					JWUnits.Kind.CANCEL_PENALTY, p)
			if prc != JWResult.OK:
				# 现金已先判过，post 仍失败只能是结构性故障（已由 post 登记），原样上抛。
				return prc
			var frc: int = treasury.record_line_payment(JWUnits.PayLine.PROJECT_CONTRACTS, p, pay)
			if frc != JWResult.OK:
				return frc
		var short: int = due - pay
		if short > 0:
			# 业务性短缺：按收款方显式登记欠付，赔偿不因没钱而消失（docs/12 §0.6）。
			treasury.add_arrears(payee, short, JWUnits.PayLine.PROJECT_CONTRACTS)
	return JWResult.OK


## 支出线 → 收款方主体下标（docs/12 §4.4）：
## 0 进口设备 → agent.row；1 国产材料 → cell.<r>.manu；2 施工服务 → cell.<r>.services。
func _payee_agent(r: int, line: int) -> int:
	if line == LINE_IMPORT_EQUIPMENT:
		return JWIds.AGENT_ROW
	if line == LINE_DOMESTIC_MATERIAL:
		return JWIds.agent_of_cell(JWIds.idx_cell(r, JWUnits.Sector.MANU))
	return JWIds.agent_of_cell(JWIds.idx_cell(r, JWUnits.Sector.SERVICES))


## 未来 n 季（含 q）逐季的已签项目分期款（承诺时间轴用，docs/20 D-02）。
## 规则推断，假设按期足额付款：每条支出线每季 ceil(该线合同额 / 计划工期)，以剩余额封顶（与 _installment_due 同口径）；
## 延期中的项目从 defer_until_q 起付；已完工、已投运、已取消与未签约的项目不计。
## 步骤：冷路径（界面读）
## 前置：输出数组长度 >= n
## 后置：不改状态
## 失败：输出数组过短 → 返回 INDEX_OUT_OF_RANGE（不登记故障）
func installment_schedule_into(q: int, n: int, out: PackedInt64Array) -> int:
	if n < 0 or out.size() < n:
		return JWResult.Fault.INDEX_OUT_OF_RANGE
	for t0: int in n:
		out[t0] = 0
	for p: int in count:
		var stp: int = status[p]
		if stp != JWUnits.ProjectStatus.IN_PROGRESS and stp != JWUnits.ProjectStatus.SUSPENDED:
			continue
		var quarters: int = planned_quarters[p]
		if quarters <= 0:
			continue
		var start_q: int = q
		if stp == JWUnits.ProjectStatus.SUSPENDED and suspension_reason[p] == JWUnits.SuspendReason.DEFERRED:
			start_q = maxi(q, defer_until_q[p])
		for line: int in LINE_N:
			var i: int = p * LINE_N + line
			var left: int = spend_plan[i] - paid[i]
			var inst: int = JWMath.ceil_div(spend_plan[i], quarters)
			var t: int = start_q - q
			while left > 0 and t < n:
				var pay: int = mini(inst, left)
				out[t] += pay
				left -= pay
				t += 1
	return JWResult.OK


## 某项目某支出线的本季应付额（μU）。
##
## 口径：等额分期 = ceil(该线合同额 / 计划工期)，再以「该线剩余合同额」封顶。
## 用 ceil 而不是 floor：floor 会让每期都差一点，合同款在计划工期内永远付不完，
## 项目被自己的取整挂在 financing 上。ceil 则保证正常推进时最后一期自动缩成余数，
## Σ 各期 == 合同额精确成立（INV-092）。
## 本函数只读 spend_plan / paid / planned_quarters，与任何进度字段无关（INV-087）。
func _installment_due(p: int, line: int) -> int:
	var quarters: int = planned_quarters[p]
	if quarters <= 0:
		JWResult.raise_fault(JWResult.Fault.DIV_ZERO, p, quarters)
		return 0
	var i: int = p * LINE_N + line
	var left: int = spend_plan[i] - paid[i]
	if left <= 0:
		return 0
	var inst: int = JWMath.ceil_div(spend_plan[i], quarters)
	if left < inst:
		return left
	return inst


## 只在项目仍处于 IN_PROGRESS 时挂起。
## 存在的理由：S04 一季会对同一项目调三次 record_payment，第一条线欠付挂起后，
## 后两条线若再挂一次就是 SUSPENDED → SUSPENDED 的恒等跃迁，会撞出 PHASE_VIOLATION。
## 状态跃迁表保持严格，重复挂起在这里被吸收，而不是靠放宽跃迁表。
func _suspend_if_running(p: int, reason: int) -> void:
	if status[p] != JWUnits.ProjectStatus.IN_PROGRESS:
		return
	set_status(p, JWUnits.ProjectStatus.SUSPENDED, reason)


# ───────────────── §1.6 状态块协议全部方法 ─────────────────

## LOAD 期一次性 resize 到 PROJECT_CAP0 的契约容量。
## 步骤：LOAD
## 前置：尚未开始任何季度结算
## 后置：全部 SoA 数组长度 == PROJECT_CAP0（spend_plan / paid 为 PROJECT_CAP0*3），count == 0
## 不变量：INV-136（下标顺序是 schema 的一部分）；§1.4（热路径不再分配）
## 失败：无
func allocate() -> void:
	var n: int = JWUnits.PROJECT_CAP0
	var n3: int = n * LINE_N
	id.resize(n)
	id.fill("")
	policy_idx.resize(n)
	policy_idx.fill(0)
	region_idx.resize(n)
	region_idx.fill(0)
	status.resize(n)
	status.fill(0)
	total_cost.resize(n)
	total_cost.fill(0)
	planned_quarters.resize(n)
	planned_quarters.fill(0)
	spend_plan.resize(n3)
	spend_plan.fill(0)
	paid.resize(n3)
	paid.fill(0)
	delivery_progress.resize(n)
	delivery_progress.fill(0)
	construction_progress.resize(n)
	construction_progress.fill(0)
	required_construction.resize(n)
	required_construction.fill(0)
	required_equipment.resize(n)
	required_equipment.fill(0)
	slot_held.resize(n)
	slot_held.fill(0)
	capacity_effect.resize(n)
	capacity_effect.fill(0)
	capacity_target.resize(n)
	capacity_target.fill(0)
	opex_per_q.resize(n)
	opex_per_q.fill(0)
	commissioned_q.resize(n)
	# −1 == 未投运（docs/10 §8.1）。0 是合法的季号，不能拿来当哨兵。
	commissioned_q.fill(-1)
	residual_value.resize(n)
	residual_value.fill(0)
	cancel_penalty.resize(n)
	cancel_penalty.fill(0)
	suspension_reason.resize(n)
	suspension_reason.fill(0)
	defer_count.resize(n)
	defer_count.fill(0)
	defer_q_total.resize(n)
	defer_q_total.fill(0)
	defer_until_q.resize(n)
	defer_until_q.fill(0)
	defer_fee.resize(n)
	defer_fee.fill(0)

	f_construction_capacity.resize(JWUnits.R)
	f_construction_capacity.fill(0)
	f_construction_used.resize(JWUnits.R)
	f_construction_used.fill(0)

	_need.resize(n)
	_need.fill(0)
	_grant.resize(n)
	_grant.fill(0)
	_tiebreak.resize(n)
	for i: int in n:
		_tiebreak[i] = i
	_line_w.resize(LINE_N)
	_line_w.fill(0)
	_line_tb.resize(LINE_N)
	_line_tb.fill(0)
	_line_out.resize(LINE_N)
	_line_out.fill(0)

	count = 0


## 只读取用（返回引用，调用方不得写）。
## 步骤：存档 / 哈希
## 前置：i ∈ [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func state_array(i: int) -> PackedInt64Array:
	match i:
		0:
			return policy_idx
		1:
			return region_idx
		2:
			return status
		3:
			return total_cost
		4:
			return planned_quarters
		5:
			return spend_plan
		6:
			return paid
		7:
			return delivery_progress
		8:
			return construction_progress
		9:
			return required_construction
		10:
			return required_equipment
		11:
			return slot_held
		12:
			return capacity_effect
		13:
			return capacity_target
		14:
			return opex_per_q
		15:
			return commissioned_q
		16:
			return residual_value
		17:
			return cancel_penalty
		18:
			return suspension_reason
		19:
			return defer_count
		20:
			return defer_q_total
		21:
			return defer_until_q
		22:
			return defer_fee
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


## 仅 LOAD / MIG。
## 步骤：LOAD / MIG
## 前置：i 合法；v 长度符合契约
## 后置：对应成员数组 == v
## 不变量：INV-136
## 失败：长度或下标不符 → 返回非 0 错误码
func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i < 0 or i >= STATE_ARRAY_IDS.size():
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i,
				STATE_ARRAY_IDS.size())
	# 5 == spend_plan、6 == paid 是 p*3+line 布局，其余都是每项目一格。
	var want: int = JWUnits.PROJECT_CAP0
	if i == 5 or i == 6:
		want = JWUnits.PROJECT_CAP0 * LINE_N
	if v.size() != want:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v.size(), want)
	# duplicate()：Packed*Array 传参是引用语义，直接赋值会让权威状态与调用方的临时数组共用
	# 同一块内存，此后调用方改一位就等于偷改了权威状态。
	var d: PackedInt64Array = v.duplicate()
	match i:
		0:
			policy_idx = d
		1:
			region_idx = d
		2:
			status = d
		3:
			total_cost = d
		4:
			planned_quarters = d
		5:
			spend_plan = d
		6:
			paid = d
		7:
			delivery_progress = d
		8:
			construction_progress = d
		9:
			required_construction = d
		10:
			required_equipment = d
		11:
			slot_held = d
		12:
			capacity_effect = d
		13:
			capacity_target = d
		14:
			opex_per_q = d
		15:
			commissioned_q = d
		16:
			residual_value = d
		17:
			cancel_penalty = d
		18:
			suspension_reason = d
		19:
			defer_count = d
		20:
			defer_q_total = d
		21:
			defer_until_q = d
		22:
			defer_fee = d
	return JWResult.OK


## 读取标量状态（0 == state.project.count）。
## 步骤：存档 / 哈希
## 前置：i ∈ [0, STATE_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func state_scalar(i: int) -> int:
	if i == 0:
		return count
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


## 仅 LOAD / MIG。
## 步骤：LOAD / MIG
## 前置：i 合法；v >= 0 且 <= PROJECT_CAP0
## 后置：count == v
## 不变量：INV-136
## 失败：越界 → 返回非 0 错误码
func set_state_scalar(i: int, v: int) -> int:
	if i != 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i,
				STATE_SCALAR_IDS.size())
	if v < 0 or v > JWUnits.PROJECT_CAP0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v,
				JWUnits.PROJECT_CAP0)
	count = v
	return JWResult.OK


## 读取流量数组（0 施工能力 / 1 施工已用）。
## 步骤：S05 之后、季末对账
## 前置：i ∈ [0, FLOW_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-088
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func flow_array(i: int) -> PackedInt64Array:
	if i == 0:
		return f_construction_capacity
	if i == 1:
		return f_construction_used
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
	return PackedInt64Array()


## 本类无标量流量。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：docs/12 §01.3
## 失败：无
func flow_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_SCALAR_IDS.size())
	return 0


## 仅 S01；全部 FLOW_* 归零。
## 步骤：S01 §01.3
## 前置：上季已结算完毕
## 后置：f_construction_capacity 与 f_construction_used 全 0
## 不变量：docs/12 §01.3（流量注册表整表清零）
## 失败：无
func reset_flows() -> void:
	f_construction_capacity.fill(0)
	f_construction_used.fill(0)


## S01 清零后的自检，非 0 即 FLOW_NOT_RESET。
## 步骤：S01 §01.3
## 前置：reset_flows() 已执行
## 后置：不改状态
## 不变量：docs/12 §01.3
## 失败：无
func flow_abs_sum() -> int:
	return JWMath.sum_abs(f_construction_capacity) + JWMath.sum_abs(f_construction_used)


## §1.6 状态块协议：读档时写回流量数组（R-SAVE-01，由 tools/gen_flow_setters.py 按 flow_array 逐项对称生成）。
## 步骤：LOAD（JWSaves 经 JWSimState 调用）
## 前置：v 的长度与本块当前分配的长度一致（长度是 schema 的一部分，INV-136）
## 后置：对应成员被整体替换
## 不变量：INV-133（读档后与原进程逐位相同）
## 失败：下标越界或长度不符 → INDEX_OUT_OF_RANGE
func set_flow_array(i: int, v: PackedInt64Array) -> int:
	if i == 0:
		if v.size() != f_construction_capacity.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_construction_capacity = v.duplicate()
		return JWResult.OK
	if i == 1:
		if v.size() != f_construction_used.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_construction_used = v.duplicate()
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
