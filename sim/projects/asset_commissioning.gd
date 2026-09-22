## 完工判定、投运、未完工残值、合同赔偿。
## 它是「当季完工，下季供能」这条底座的判定端，JWCapital.commit_pending() 是执行端。
##
## 本类不持有任何状态（纯编排）。它只读写 JWProjectQueue、JWCapital、JWTreasury 的字段。
## STATE_ARRAY_IDS 与 FLOW_ARRAY_IDS 均为空数组；reset_flows() 是空实现。
## 这样做的好处：完工逻辑没有自己的「私房状态」可以藏，全部后果都落在别人可被断言的字段上。
##
## 骨架依据：docs/17_api_skeleton.md §4.20。
class_name JWAssetCommissioning
extends RefCounted

# ───────────────── §1.6 状态块协议的注册表（本类无状态，全空） ─────────────────

const STATE_ARRAY_SUBSYS: PackedInt64Array = []
const STATE_ARRAY_IDS: PackedStringArray = []
const STATE_SCALAR_IDS: PackedStringArray = []
const FLOW_ARRAY_SUBSYS: PackedInt64Array = []
const FLOW_ARRAY_IDS: PackedStringArray = []
const FLOW_SCALAR_IDS: PackedStringArray = []

# ───────────────── 本类用到的布局常量 ─────────────────

## 三条支出落点：0 进口设备 / 1 国产材料 / 2 施工服务（docs/11 §5.12，
## 与 JWProjectQueue.spend_plan / paid 的 p*3+line 布局逐字一致）。
const SPEND_LINE_N: int = 3

## 效果落点码 == JWPolicyDef.EFFECT_TARGETS 的下标（docs/11 §5.12，V-PD-10/11）。
## 这里给前 8 个取名，是为了让下面的分派表可读；数值绑死在那张白名单上，重排即破坏性变更。
const TARGET_GRID_PENDING: int = 0
const TARGET_HOUSING_PENDING: int = 1
const TARGET_IRRIGATION_PENDING: int = 2
const TARGET_PORT_PENDING: int = 3
const TARGET_CELL_CAPACITY_PENDING: int = 4
const TARGET_PUBSERV_CAPACITY_PENDING: int = 5
const TARGET_PUBSERV_TEACHERS: int = 6
const TARGET_PUBSERV_HEALTH_STAFF: int = 7

## 「目标主体人员」落在公共服务单元（pubserv.<region>）而不是某个 cell。
const OPERATOR_PUBSERV: int = -1
## 该落点不是资本项目的效果落点（参数类、政治类），项目不得指向它。
const OPERATOR_NONE: int = -2

## 效果落点码 → 投运配套条件里「目标主体」的人员落点（OQ-245）。
## 下标 == 效果落点码，长度 == JWPolicyDef.EFFECT_TARGETS.size()。
## 逐条来源（内容包 commissioning_conditions，全部指名 OQ-245）：
##   0 电网   → 该地区 energy cell 在岗人员（policy_P04 c2_operator_staffed）
##   1 住房   → 该地区 pubserv 在岗人员（policy_P06 effect_chain 第 5 步）
##   2 灌溉   → 该地区 agri cell 在岗人员（policy_P07 commission.p07.agri_staffed）
##   3 港口   → 该地区 services cell 在岗人员（policy_P08 commissioning_conditions）
##   5/6/7    → 该地区 pubserv 在岗人员（policy_P10：无人则停在完工前，不投运）
##   4        → cell 产能：该 cell 自己的在岗人员（槽位无法从项目字段解出，见 _effect_slot）
##   8..12    → 参数与政治类落点，不是资本项目的效果落点
const OPERATOR_OF_TARGET: PackedInt64Array = [
	JWUnits.Sector.ENERGY, OPERATOR_PUBSERV, JWUnits.Sector.AGRI, JWUnits.Sector.SERVICES,
	OPERATOR_NONE, OPERATOR_PUBSERV, OPERATOR_PUBSERV, OPERATOR_PUBSERV,
	OPERATOR_NONE, OPERATOR_NONE, OPERATOR_NONE, OPERATOR_NONE, OPERATOR_NONE,
]

# ───────────────────────── 方法 ─────────────────────────

## S01 §01.4 末：把上季完工的项目标记为已投运。
## 步骤：S01 §01.4
## 前置：JWCapital.commit_pending() 已执行（能力已转 active）
## 后置：status: COMPLETED → COMMISSIONED；commissioned_q = 当前 q（== 完工季 + 1）
## 不变量：INV-091（commissioned_q == 完工季 + 1）；验收测试 T-S-COMMISSION-LAG
## 失败：非法跃迁 → Fault.PHASE_VIOLATION
func promote_completed(pq: JWProjectQueue, q: int) -> int:
	if pq == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, 0)
	# q 是 S01 的当季；完工发生在上一季的 S07，故这里写下去的 commissioned_q 恒等于
	# 「完工季 + 1」——这是 INV-091 的数据流保证，不是一个可调参数。
	if q < 0:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, q, 0)
	var n: int = _row_count(pq)
	if n < 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, pq.count, pq.status.size())
	var first_err: int = 0
	for p: int in n:
		if pq.status[p] != JWUnits.ProjectStatus.COMPLETED:
			continue
		# 跃迁只走唯一写入函数：非法跃迁由它拦截并登记 PHASE_VIOLATION，本函数不自行改 status。
		var code: int = pq.set_status(p, JWUnits.ProjectStatus.COMMISSIONED,
				JWUnits.SuspendReason.NONE)
		if code != 0:
			if first_err == 0:
				first_err = code
			continue
		pq.commissioned_q[p] = q
	return first_err


## S07 §7.1：完工判定（充要条件三项齐全才算完工）。
## 步骤：S07 §7.1
## 前置：delivery == 1e6 且 construction == 1e6 且配套条件满足
##       （OQ-245：运行费已纳入下季预算承诺，且目标主体人员不为零）
## 后置：status = COMPLETED；只写 *_pending_*（JWCapital.add_pending）；
##       wip 转 capital；gov.service_opex_committed += opex_per_q；释放槽位
## 不变量：INV-090（任一未满足不得投运）、INV-091（只写 pending）、INV-054、INV-092、INV-102
## 失败：配套条件不满足 → 停在进度 100% 但不完工，写 blocked_reason（业务结果，不是故障）；
##       若本函数写到任何 *_active_* → Fault.WRITE_OUT_OF_SCOPE
func commission_ready(pq: JWProjectQueue, capital: JWCapital, treasury: JWTreasury,
		labor: JWLaborMarket, ledger: JWLedger, accounts: JWAccount, q: int) -> int:
	if pq == null or capital == null or treasury == null or labor == null \
			or ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, 0)
	if q < 0:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, q, 0)
	var n: int = _row_count(pq)
	if n < 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, pq.count, pq.status.size())
	var first_err: int = 0
	# 项目下标升序遍历（docs/12 §7.1 的 sorted(projects)）：遍历序进结果，禁止用字典序或随机序。
	for p: int in n:
		if pq.status[p] != JWUnits.ProjectStatus.IN_PROGRESS:
			continue
		# 条件一：进度双满。progress_ready 是必要条件，不是充分条件（INV-090）。
		if not pq.progress_ready(p):
			continue
		var opex: int = pq.opex_per_q[p]
		# 条件二：运行费已纳入下季预算承诺。OQ-245 未闭合，取内容包 policy_P04
		# commissioning_conditions.c1_opex_affordable 给出的最保守可机器求值形式：
		# 投运当季政府可用现金（已扣本季预留）足以承担一季运行费。
		var available_uu: int = accounts.cash_of(JWIds.AGENT_GOV) - treasury.reserved_memo
		if available_uu < opex:
			# 业务结果，不是故障：进度停在 100%，status 不变，本季不投运。
			continue
		var r: int = pq.region_idx[p]
		var target: int = pq.capacity_target[p]
		# R-METHOD-01：建筑项目的产能落到指定的建筑堆，不走地区级落点表。
		var is_building: bool = p < pq.building_type.size() and pq.building_type[p] > 0
		# 条件三：目标主体人员不为零（OQ-245）。人员落点随效果落点变（见 OPERATOR_OF_TARGET）；
		# 建筑项目的运营方就是它自己所在部门的生产单元（落点表对「单元产能」这一项登记的是「无」）。
		if is_building:
			var sec_b: int = capital.buildings.t_sector[pq.building_type[p]]
			var staffed: int = 0
			for k: int in JWUnits.K:
				staffed += labor.employment(JWIds.idx_cell(r, sec_b), k)
			if staffed <= 0:
				continue
		elif not _operator_staffed(target, r, labor):
			continue
		var slot: int = _effect_slot(target, r) if not is_building else 0
		if slot < 0:
			# 落点无法解成一个稠密槽位：不猜、不投运，登记越权写入。
			var bad: int = JWResult.raise_fault(JWResult.Fault.WRITE_OUT_OF_SCOPE, target, p)
			if first_err == 0:
				first_err = bad
			continue
		# 先过账、后写能力：资金腿失败时能力不得已经落地。
		# 已付款项在 S04 全部计入 gov.wip_uu（INV-092；R-PROJECT-01 四腿付款的第三腿），
		# 故归属本项目的 wip 就是 Σ_line paid。
		var wip_part: int = _paid_total(pq, p)
		if wip_part > 0:
			# 公共资本项目的资产落在政府名下（docs/10 §3.1：state.gov.capital_uu 的写入者含 S07）；
			# wip → capital 由 JWCapital 过一笔 ASSET_RECLASS 两腿分录（R-ASSET-01：政府 wip −V、
			# 政府资本 +V，净值不变，三口径全 none）。分录行的实体引用是项目下标。
			var code_cap: int = capital.capitalize_wip(JWIds.AGENT_GOV, wip_part, ledger, accounts, p)
			if code_cap != 0:
				if first_err == 0:
					first_err = code_cap
				continue
		# **只写 pending**（INV-091）：本季完工的产能对本季生产毫无影响（INV-054）。
		# 本函数不持有任何 *_active_* 的写入通道——这是结构保证，不是自觉。
		var code_pend: int = 0
		if is_building and pq.retrofit_stack[p] >= 0:
			# R-METHOD-01：改造完工——整堆切到新方式，解冻产能，不新增产能。
			code_pend = capital.switch_stack_method(pq.retrofit_stack[p], pq.building_method[p])
		elif is_building:
			var sec: int = capital.buildings.t_sector[pq.building_type[p]]
			code_pend = capital.add_building_pending(JWIds.idx_cell(r, sec), pq.building_type[p],
					pq.building_owner[p], pq.building_method[p], pq.capacity_effect[p], q,
					pq.entity[p])
		else:
			code_pend = capital.add_pending(target, slot, pq.capacity_effect[p])
		if code_pend != 0:
			if first_err == 0:
				first_err = code_pend
			continue
		# 投运即背上每季运行费义务（docs/12 §7.1；欠拨的后果在 §7.2，只降可用率不减资产 INV-102）。
		var committed: int = treasury.service_opex_committed + opex
		JWMath.check_amount(committed)
		treasury.service_opex_committed = committed
		# 释放施工槽位（INV-094）：完工的项目不再占用并发名额。
		pq.slot_held[p] = 0
		var code_st: int = pq.set_status(p, JWUnits.ProjectStatus.COMPLETED,
				JWUnits.SuspendReason.NONE)
		if code_st != 0 and first_err == 0:
			first_err = code_st
	return first_err


## S02/S07：未完工残值登记（取消或长期中断时）。
## 步骤：S02 §2.7（取消）、S07（长期中断复核）
## 前置：项目未完工
## 后置：residual_value = 已形成的可回收部分；wip 中超出残值的部分确认为损失（政府净值减少）
## 不变量：INV-093（残值与赔偿均入账）、INV-020、INV-021
## 失败：残值 > 已付 → Fault.LEDGER_IMBALANCE；已完工／已投运 → Fault.PHASE_VIOLATION；
##       未取消的项目 → Reject.PRECONDITION（状态不变，见下）
##
## 取消路径上的残值登记与损失确认由 JWProjectQueue.cancel() 在同一步一次完成——它是取消结算的
## 唯一执行点（本类秩 8 可以调它，它秩 6 调不回本类，所以只能是它做、这里核）。docs/17 §5.2 第 3 条
## 紧随 cancel() 之后再调本函数时项目已是 CANCELLED：这里只核对 INV-093（残值 <= 已付），**不再过账**。
## 原实现在这里按另一条公式重算残值并再减记一次 wip：同一笔损失记两遍，wip 不够时直接撞
## LEDGER_IMBALANCE —— ADV-F01/F02/F06 的码 22 有一路来自这里。
## 未取消项目的「长期中断复核」首版不落账：减值之后项目若复工完工，commission_ready 按 Σpaid 资本化，
## 会越过已被减掉的 wip；在有逐项目减值台账之前，任何减记都会让完工路径失衡，故显式拒绝而不是半做。
func register_residual(pq: JWProjectQueue, p: int, capital: JWCapital,
		ledger: JWLedger, accounts: JWAccount) -> int:
	if pq == null or capital == null or ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, p, 0)
	var n: int = _row_count(pq)
	if n < 0 or p < 0 or p >= n:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, n)
	var st: int = pq.status[p]
	# 前置：项目未完工。已完工／已投运的资产走折旧与退出规则，不在残值口径内。
	if st == JWUnits.ProjectStatus.COMPLETED or st == JWUnits.ProjectStatus.COMMISSIONED:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, p, st)
	if st != JWUnits.ProjectStatus.CANCELLED:
		return JWResult.Reject.PRECONDITION
	# 核对 cancel() 登记的残值：不为负、不超过实际已付（INV-093；残值若引用 total_cost 会在这里露馅）。
	var paid_total: int = _paid_total(pq, p)
	var residual: int = pq.residual_value[p]
	if residual < 0 or residual > paid_total:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, residual, paid_total)
	return JWResult.OK


## S02：合同赔偿（取消时按剩余合同额的 compensation_ppm）。
## 步骤：S02 §2.7
## 前置：defs.exit_compensation_ppm 已加载；项目已由 JWProjectQueue.cancel() 取消
## 后置：post(kind=CANCEL_PENALTY, gov → 承包方)；committed_memo 减少
## 不变量：INV-032、INV-093
## 失败：现金不足 → 登记 arrears（业务性短缺），不是故障；未取消的项目 → Reject.PRECONDITION；
##       已登记的赔偿额与合同口径不符 → Fault.LEDGER_IMBALANCE
##
## 赔偿的过账、欠付与流量登记、以及 committed_memo 的冲减，都由 JWProjectQueue.cancel() 在同一步
## 一次完成（取消结算的唯一执行点，见 register_residual 的同类说明）。docs/17 §5.2 第 3 条紧随
## cancel() 之后再调本函数时，这里只核对「已登记的赔偿 == mul_ppm(剩余合同额, compensation_ppm)」，
## **不再付第二次**——原实现在 cancel() 已付过之后又按同一公式付一遍，承包方收两份赔偿。
## 未签约就取消的项目没有合同，赔偿为 0，同样满足下面的核对式。
func pay_cancel_penalty(pq: JWProjectQueue, p: int, defs: JWPolicyDef, treasury: JWTreasury,
		ledger: JWLedger, accounts: JWAccount) -> int:
	if pq == null or defs == null or treasury == null or ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, p, 0)
	var n: int = _row_count(pq)
	if n < 0 or p < 0 or p >= n:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, n)
	var pol: int = pq.policy_idx[p]
	# R-METHOD-01：建筑项目没有政策卡（policy_idx == −1），退出赔偿为 0，核对式自然成立。
	if pol < 0 and p < pq.building_type.size() and pq.building_type[p] > 0:
		return JWResult.OK
	if pol < 0 or pol >= defs.exit_compensation_ppm.size():
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, pol,
				defs.exit_compensation_ppm.size())
	if pq.status[p] != JWUnits.ProjectStatus.CANCELLED:
		# 没有取消就没有赔偿；赔偿也不能先于取消单独结算（那会让随后的 cancel() 再付一遍）。
		return JWResult.Reject.PRECONDITION
	# 剩余合同额 = Σ_line (spend_plan − paid)；取消不改 paid（INV-093），故此刻读到的就是取消时的口径。
	var remaining: int = pq.committed_remaining(p)
	if remaining < 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, remaining, 0)
	# 新刻度下 remaining 可达 AMOUNT_MAX 量级，裸乘 PPM 必溢出：一律走 mul_ppm → mul_div_floor（R-SCALE-01）。
	# rounding: floor, reason=与 cancel() 的赔偿折算同一口径
	var expect: int = JWMath.mul_ppm(remaining, defs.exit_compensation_ppm[pol])
	var got: int = pq.cancel_penalty[p]
	if got != 0 and got != expect:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, got, expect)
	return JWResult.OK


# ───────────────── 私有工具（无状态，纯函数式） ─────────────────

## SoA 的有效行数；count 与数组长度矛盾时返回 -1 让调用方登记越界。
func _row_count(pq: JWProjectQueue) -> int:
	var n: int = pq.count
	if n < 0 or n > pq.status.size() or n > pq.region_idx.size() \
			or n > pq.capacity_target.size() or n > pq.capacity_effect.size() \
			or n > pq.opex_per_q.size() or n > pq.slot_held.size() \
			or n > pq.commissioned_q.size() or n > pq.residual_value.size() \
			or n > pq.cancel_penalty.size() or n > pq.policy_idx.size() \
			or n > pq.construction_progress.size():
		return -1
	if n * SPEND_LINE_N > pq.paid.size() or n * SPEND_LINE_N > pq.spend_plan.size():
		return -1
	return n


## 归属某项目的已付总额（= 该项目在 gov.wip_uu 中的份额，INV-092）。
func _paid_total(pq: JWProjectQueue, p: int) -> int:
	var base: int = p * SPEND_LINE_N
	if base < 0 or base + SPEND_LINE_N > pq.paid.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, base, pq.paid.size())
		return 0
	var total: int = 0
	for line: int in SPEND_LINE_N:
		total += pq.paid[base + line]
	return total


## 效果落点码 + 地区 → JWCapital 的稠密槽位下标；无法解出时返回 -1。
func _effect_slot(target: int, r: int) -> int:
	if r < 0 or r >= JWUnits.R:
		return -1
	match target:
		TARGET_GRID_PENDING, TARGET_HOUSING_PENDING, TARGET_IRRIGATION_PENDING, \
				TARGET_PORT_PENDING:
			# 四个地区级设施数组的下标就是地区下标。
			return r
		TARGET_PUBSERV_CAPACITY_PENDING, TARGET_PUBSERV_TEACHERS, \
				TARGET_PUBSERV_HEALTH_STAFF:
			# PUBSERV == R，公共服务单元逐地区一个。
			return r
		_:
			# state.cell.capacity_pending 需要 idx_cell(r, s)，而 state.project.* 里没有部门字段；
			# 首版内容包无任何 project 指向该落点。缺字段就不猜——返回 -1 让调用方登记越权写入。
			return -1


## OQ-245 的「目标主体人员不为零」：人员落点随效果落点变（见 OPERATOR_OF_TARGET）。
func _operator_staffed(target: int, r: int, labor: JWLaborMarket) -> bool:
	if r < 0 or r >= JWUnits.R:
		return false
	if target < 0 or target >= OPERATOR_OF_TARGET.size():
		return false
	var operator_code: int = OPERATOR_OF_TARGET[target]
	if operator_code == OPERATOR_NONE:
		return false
	var persons: int = 0
	if operator_code == OPERATOR_PUBSERV:
		for k: int in JWUnits.K:
			persons += labor.pubserv_employment(r, k)
	else:
		var cell: int = JWIds.idx_cell(r, operator_code)
		for k: int in JWUnits.K:
			persons += labor.employment(cell, k)
	return persons > 0


# ───────────── §1.6 状态块协议：全部方法返回空 / 空实现（本类无状态） ─────────────

## 本类无状态，空实现。
## 步骤：LOAD
## 前置：无
## 后置：不改状态
## 不变量：docs/17 §4.20（完工逻辑不得有私房状态）
## 失败：无
func allocate() -> void:
	# 无状态可分配（取消赔偿的拆分已并入 JWProjectQueue.cancel()，本类不再持有拆分缓冲）。
	pass


## 本类无状态，返回空数组。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：docs/17 §4.20
## 失败：无
func state_array(i: int) -> PackedInt64Array:
	return PackedInt64Array()


## 本类无状态，空实现。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：docs/17 §4.20
## 失败：无
func set_state_array(i: int, v: PackedInt64Array) -> int:
	return 0


## 本类无状态，恒 0。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：docs/17 §4.20
## 失败：无
func state_scalar(i: int) -> int:
	return 0


## 本类无状态，空实现。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：docs/17 §4.20
## 失败：无
func set_state_scalar(i: int, v: int) -> int:
	return 0


## 本类无流量，返回空数组。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：docs/12 §01.3
## 失败：无
func flow_array(i: int) -> PackedInt64Array:
	return PackedInt64Array()


## 本类无流量，恒 0。
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
	pass


## 本类无流量，恒 0。
## 步骤：S01 §01.3
## 前置：无
## 后置：不改状态
## 不变量：docs/12 §01.3
## 失败：无
func flow_abs_sum() -> int:
	return 0
