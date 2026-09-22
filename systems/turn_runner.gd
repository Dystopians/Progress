## 八步固定顺序结算的**唯一编排者**，WriteGuard，步骤哈希，故障处置。
## **它是全系统唯一持有全部 scratch 数组的地方**（热路径不分配）。
##
## 骨架依据：docs/17_api_skeleton.md §4.29 与 §5（八步调用序列，秩 A3；可引用秩 ≤10、A0、A2）。
class_name JWTurnRunner
extends RefCounted


## 支付拆分 scratch 的长度（收款方 == AGENT_N）。
const SC_PAYEE_N: int = 60

## 最大余数法 scratch 的长度（== JWMath.SPLIT_MAX_N）。
const SC_SPLIT_N: int = 256

## 项目付款清单的行数上界（每个项目最多 LINE_N 行）。
const SC_PROJECT_ROW_N: int = JWUnits.PROJECT_CAP0 * JWProjectQueue.LINE_N

## 「季末全量检查」在 _check_invariants 里的步号。
const STEP_QUARTER_END: int = 0

## 失信计数的四类来源（docs/12 §8.1 的闭集合），值只用于自检不进状态。
const BREACH_TRANSFER: int = 1
const BREACH_OPEX: int = 2
const BREACH_PROJECT_CANCEL: int = 4
const BREACH_BOND_DEFAULT: int = 8

## 账本行的账户下标反解（account == agent * ACCOUNT_CODE_N + code）。
const ACC_STRIDE: int = JWUnits.ACCOUNT_CODE_N

## `log.rounding.site_code` / `log.ledger.cause` 的本文件号段。
## 中央注册表尚不存在（见 open_questions），本文件占用 1900..1909，与已知的
## JWPopulation（1401..1419）、JWPricing（100..699）、JWLaborMarket（3001..3004）不重叠。
const CAUSE_RUNNER: int = 1900

## 故障包目录前缀。
const FAULT_DIR: String = "user://faults/"

## 季号在故障包目录名里的补零宽度（q<NNN>）。
const FAULT_Q_PAD: int = 3


# ── 成员变量 ────────────────────────────────────────────────────────────

## 权威状态（构造注入）。
var _st: JWSimState = null

## 事件引擎（构造注入）。
var _events: JWEventEngine = null

## 本季 8 个步骤哈希（写 `checkpoints.jsonl`）。
var _step_hash: PackedStringArray = PackedStringArray()

## 进入某步前对不可写子系统取的哈希，长 SUBSYS_N。
var _guard_hash: PackedStringArray = PackedStringArray()

## 支付拆分 scratch ×3，长 SC_PAYEE_N。
var _sc_payee: PackedInt64Array = PackedInt64Array()
var _sc_due: PackedInt64Array = PackedInt64Array()
var _sc_paid: PackedInt64Array = PackedInt64Array()

## 最大余数法 scratch ×3，长 SC_SPLIT_N。
var _sc_weights: PackedInt64Array = PackedInt64Array()
var _sc_tiebreak: PackedInt64Array = PackedInt64Array()
var _sc_out: PackedInt64Array = PackedInt64Array()

## cell 级中间量，长 CELL。
var _sc_cell: PackedInt64Array = PackedInt64Array()

## 群组级中间量，长 GROUP。
var _sc_group: PackedInt64Array = PackedInt64Array()

## 群组×岗位中间量，长 GROUP_EMP_N。
var _sc_group_slot: PackedInt64Array = PackedInt64Array()

## 市场需求／成交 scratch，长 MARKET_N。
var _sc_market: PackedInt64Array = PackedInt64Array()

## 项目付款 scratch，长 PROJECT_CAP0 * 4。
var _sc_project: PackedInt64Array = PackedInt64Array()

## 本季失信计数（S08 输入），长 GROUP。
var _sc_breach: PackedInt64Array = PackedInt64Array()

## 应税利润（S06 中转），长 CELL。
var _sc_taxable: PackedInt64Array = PackedInt64Array()

## 可分配利润（S06 中转），长 CELL。
var _sc_distributable: PackedInt64Array = PackedInt64Array()

# ── 骨架之外新增的 scratch（全部在 _init 一次性 resize，结算期不分配） ──────
#
# 新增理由逐条写在声明处。它们都是**跨步骤但不跨季**的中间量，没有任何一个块能持有：
# 持有它们的块要么在 S01 §01.3 被整表清零（流量），要么就得新增状态字段（改 schema）。

## 上季成交量 / 上季未满足需求，长 CELL。
## S03 §3.1 的 `D_prev = 成交 + 未满足` 取自**上季**流量，而 JWInventory 的
## f_sold / f_unmet_demand 在 S01 §01.3 被整表清零且该块没有留快照
## （JWSectorModel 自己留了 _prev_output_actual 三项，库存侧没有对应物）。
## 因此必须在 reset_all_flows() 之前由本类抓一份。
var _sc_sold_prev: PackedInt64Array = PackedInt64Array()
var _sc_unmet_prev: PackedInt64Array = PackedInt64Array()

## 上季实际投资额，长 CELL。docs/12 §4.3 的补助前置是「上季 flow.cell.investment_uu > 0」，
## 同样在 S01 被清零，同样没有块留快照。
var _sc_invest_prev: PackedInt64Array = PackedInt64Array()

## 运行费应付清单（收款方 / 应付额），长 OPEX_N（JWTreasury._check_line_arity 对该档钉死长度）。
var _sc_opex_payee: PackedInt64Array = PackedInt64Array()
var _sc_opex_due: PackedInt64Array = PackedInt64Array()

## 转移支付应付清单（收款方 / 应付额），长 GROUP（同上，该档长度被钉死）。
var _sc_tr_payee: PackedInt64Array = PackedInt64Array()
var _sc_tr_due: PackedInt64Array = PackedInt64Array()

## 项目付款清单四列，长 SC_PROJECT_ROW_N。
## JWProjectQueue.payment_due_into 要求四个等长数组，且 `_sc_project`（256）装不下四列。
var _sc_pj_project: PackedInt64Array = PackedInt64Array()
var _sc_pj_line: PackedInt64Array = PackedInt64Array()
var _sc_pj_payee: PackedInt64Array = PackedInt64Array()
var _sc_pj_due: PackedInt64Array = PackedInt64Array()

## 补助应付清单（收款方 / 应付额），长 CELL（该档长度被钉死）。
var _sc_sub_payee: PackedInt64Array = PackedInt64Array()
var _sc_sub_due: PackedInt64Array = PackedInt64Array()

## GDP 三口径分类汇总缓冲。
var _sc_class_prod: PackedInt64Array = PackedInt64Array()
var _sc_class_exp: PackedInt64Array = PackedInt64Array()
var _sc_class_inc: PackedInt64Array = PackedInt64Array()

## R-PROCURE-01：采购档的应付额缓冲（长 1，_finance_before_pay 的入参）。
var _sc_proc_due: PackedInt64Array = PackedInt64Array([0])
## 逐组公共服务交付量，长 GROUP_SVC_N（S07 §7.8 的 update_living_indices 入参）。
var _sc_group_svc: PackedInt64Array = PackedInt64Array()

## 本季失信来源位掩码，长 GROUP（_collect_breach_counts 的中间量）。
var _sc_breach_mask: PackedInt64Array = PackedInt64Array()

## 地区级中间量，长 R（update_environment 的人口入参）。
var _sc_region: PackedInt64Array = PackedInt64Array()

## 支付优先级重排缓冲，长 PAY_LINE_N（set_state_array 对该数组的长度有硬要求）。
var _sc_pay_order: PackedInt64Array = PackedInt64Array()

## 本季已受理命令的**行号**缓冲，长 JWCommands.CMD_CAP。
## 不能复用 _sc_out（长 SC_SPLIT_N == 256）：命令缓冲的出厂容量就是 CMD_CAP == 4096，
## 而 accepted_this_quarter_into 在 out 装不下时是**整体失败**（不截断），
## 一季递交超过 256 条命令就会在 S02 第 1 条登记 Fault.INDEX_OUT_OF_RANGE。
## ADV-C05 一季递交 `param.bond_batch_cap + 64 == 576` 条发行命令，正好踩在这上面。
## 两者共用同一块缓冲本身也是隐患：S02 的循环体一边读行号，被调链一边可能拿 _sc_out 做拆分。
var _sc_cmd_rows: PackedInt64Array = PackedInt64Array()
## R-AUTHORITY-01：每条政策的域否决集团位掩码（S02 前重算并注入政策引擎；长度 POLICY_N）。
var _veto_view: PackedInt64Array = PackedInt64Array()

## 本季被取消项目所在地区的位掩码（S02 记，S08 §8.1 读）。
var _cancel_region_mask: int = 0

## 本季债券违约标记（S02 记，S08 §8.1 读）。
var _bond_default_flag: int = 0

## 本季 pay_debt_service 返回的财政重组失败信号（S02 记，S08 §8.5 读）。
var _fiscal_signal: int = 0

## 步骤哈希的拼接缓冲（避免每步新建 PackedByteArray）。
var _hash_buf: PackedByteArray = PackedByteArray()

## 最近一次 _enter_fault 写出的故障包目录（供 JWGame 报给玩家）。
var last_fault_dir: String = ""


## 构造注入权威状态与事件引擎，并一次性 resize 全部 scratch。
## 步骤：LOAD
## 前置：st 与 events 已 allocate()
## 后置：全部 scratch 数组长度固定；此后结算期不再分配
## 不变量：docs/17 §1.4（热路径不 new 对象、不建 Dictionary）
## 失败：无
func _init(st: JWSimState, events: JWEventEngine) -> void:
	_st = st
	_events = events

	_step_hash.resize(JWUnits.Phase.S08)
	var h: int = 0
	while h < _step_hash.size():
		_step_hash[h] = ""
		h += 1
	_guard_hash.resize(JWUnits.SUBSYS_N)
	var g: int = 0
	while g < _guard_hash.size():
		_guard_hash[g] = ""
		g += 1

	_alloc(_sc_payee, SC_PAYEE_N)
	_alloc(_sc_due, SC_PAYEE_N)
	_alloc(_sc_paid, SC_PAYEE_N)
	_alloc(_sc_weights, SC_SPLIT_N)
	_alloc(_sc_tiebreak, SC_SPLIT_N)
	_alloc(_sc_out, SC_SPLIT_N)
	_alloc(_sc_cell, JWUnits.CELL)
	_alloc(_sc_group, JWUnits.GROUP)
	_alloc(_sc_group_slot, JWUnits.GROUP_EMP_N)
	_alloc(_sc_market, JWUnits.MARKET_N)
	_alloc(_sc_project, JWUnits.PROJECT_CAP0 * 4)
	_alloc(_sc_breach, JWUnits.GROUP)
	_alloc(_sc_taxable, JWUnits.CELL)
	_alloc(_sc_distributable, JWUnits.CELL)

	_alloc(_sc_sold_prev, JWUnits.CELL)
	_alloc(_sc_unmet_prev, JWUnits.CELL)
	_alloc(_sc_invest_prev, JWUnits.CELL)
	_alloc(_sc_opex_payee, JWUnits.OPEX_N)
	_alloc(_sc_opex_due, JWUnits.OPEX_N)
	_alloc(_sc_tr_payee, JWUnits.GROUP)
	_alloc(_sc_tr_due, JWUnits.GROUP)
	_alloc(_sc_pj_project, SC_PROJECT_ROW_N)
	_alloc(_sc_pj_line, SC_PROJECT_ROW_N)
	_alloc(_sc_pj_payee, SC_PROJECT_ROW_N)
	_alloc(_sc_pj_due, SC_PROJECT_ROW_N)
	_alloc(_sc_sub_payee, JWUnits.CELL)
	_alloc(_sc_sub_due, JWUnits.CELL)
	_alloc(_sc_class_prod, JWLedger.PROD_CLASS_N)
	_alloc(_sc_class_exp, JWLedger.EXP_CLASS_N)
	_alloc(_sc_class_inc, JWLedger.INC_CLASS_N)
	_alloc(_sc_group_svc, JWUnits.GROUP_SVC_N)
	_alloc(_sc_breach_mask, JWUnits.GROUP)
	_alloc(_sc_region, JWUnits.R)
	_alloc(_sc_pay_order, JWUnits.PAY_LINE_N)
	_alloc(_sc_cmd_rows, JWCommands.CMD_CAP)

	# 决胜键恒为「下标升序」（docs/12 §0.3 的遍历确定性）：写一次，此后不再改。
	var i: int = 0
	while i < SC_SPLIT_N:
		_sc_tiebreak[i] = i
		i += 1


## 一次性分配一个 scratch 并清零。
## 步骤：LOAD
## 前置：n >= 0
## 后置：a.size() == n 且全 0
## 不变量：docs/10 §0.6（加载期一次性 resize）
## 失败：无
func _alloc(a: PackedInt64Array, n: int) -> void:
	a.resize(n)
	a.fill(0)


## 推进一个季度：八步顺序固定、不可重入、不可回退。
## 步骤：S01..S08 全程
## 前置：!run_terminated；phase == IDLE；本季命令已提交且含恰好一条 advance_quarter
## 后置：成功 → phase 回到 IDLE 且 q 已 +1；失败 → 停在故障步，状态保留现场
## 不变量：INV-012（严格单向推进）、INV-013（每步只写可写子集）、INV-014（逐季哈希可复现）
## 失败：run_terminated → Reject.RUN_TERMINATED（**状态哈希不变**，INV-128）；
##       phase != IDLE → Reject.PHASE_BUSY；任一 Fault → 停止推进、导出故障包、
##       **不回滚到「看起来正常」的状态**
## T-X-F-03（docs/30 §7）：本季 S01..S08 各步耗时（μs，下标 0..7；含该步的写入守卫与不变量检查）。
## 纯诊断读口：不进状态、不进哈希、不参与任何结算判断，只供性能基准做八步分解。
var step_us: PackedInt64Array = PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])


func advance_quarter(cmds: JWCommands) -> int:
	if _st == null or _events == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, 0)
	if _st.politics != null and _st.politics.run_terminated:
		# INV-128：终局后的推进是 REJECT，不是 FAULT —— 状态一位不改，哈希逐位相同。
		return JWResult.Reject.RUN_TERMINATED
	if _st.phase != JWUnits.Phase.IDLE:
		return JWResult.Reject.PHASE_BUSY
	if JWResult.has_pending():
		# 上一季留下的未处理故障：docs/12 §9 要求故障包导出后才清登记，
		# 带着挂起的故障继续推进等于把第一现场埋掉。
		return JWResult.pending_code()

	var fault: int = 0
	var step: int = JWUnits.Phase.S01
	step_us.fill(0)
	while step <= JWUnits.Phase.S08:
		var t_step: int = Time.get_ticks_usec()
		_st.phase = step
		JWResult.set_step(step)
		if _st.ledger != null:
			_st.ledger.set_context(_st.q, step)
		_guard_begin(step)
		fault = _run_step(step, cmds)
		if step == JWUnits.Phase.S01 and fault >= JWResult.Reject.RUN_TERMINATED:
			# REJECT 语义（docs/12 §0.6）：状态完全不变。**只有 S01** 能走这条路：
			# 它的命令前置检查排在 S01 的任何写入之前，所以把相位放回 IDLE 之后状态逐位如初。
			# 限定 `step == S01` 不是保险起见 —— 后面的步骤已经改过账，把它们的 Reject
			# 当成「状态完全不变」交回去，就是在对调用方谎报现场。
			_st.phase = JWUnits.Phase.IDLE
			JWResult.set_step(0)
			return fault
		var guard: int = _guard_end(step)
		if fault == JWResult.OK:
			fault = guard
		if fault == JWResult.OK:
			fault = _check_invariants(step)
		_record_step_hash(step)
		step_us[step - JWUnits.Phase.S01] = Time.get_ticks_usec() - t_step
		if fault != JWResult.OK:
			return _enter_fault(step, fault)
		step += 1

	fault = _check_invariants(STEP_QUARTER_END)
	if fault != JWResult.OK:
		return _enter_fault(JWUnits.Phase.S08, fault)
	_st.phase = JWUnits.Phase.IDLE
	JWResult.set_step(0)
	return JWResult.OK


## 步骤分派（只有一个 match，没有任何逻辑；存在的意义是让 §5 的主循环保持 8 行可读）。
## 步骤：S01..S08
## 前置：step ∈ [1, 8]
## 后置：转调对应的 _step_sNN
## 不变量：INV-012（不回退不跳步）
## 失败：step 越界 → Fault.PHASE_VIOLATION
func _run_step(step: int, cmds: JWCommands) -> int:
	match step:
		JWUnits.Phase.S01:
			return _step_s01(cmds)
		JWUnits.Phase.S02:
			return _step_s02(cmds)
		JWUnits.Phase.S03:
			return _step_s03()
		JWUnits.Phase.S04:
			return _step_s04()
		JWUnits.Phase.S05:
			return _step_s05()
		JWUnits.Phase.S06:
			return _step_s06()
		JWUnits.Phase.S07:
			return _step_s07()
		JWUnits.Phase.S08:
			return _step_s08()
	return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, step, JWUnits.Phase.S08)


## S01 冻结起点。可写：META | TIME | CELL | PUBSERV | REGION | PROJECT | WORLD | RNG + 全部 flow.*
## 步骤：S01（docs/12 §01.1–§01.7）
## 前置：phase == S01
## 后置：state_hash_prev 已记；全部 flow.* 为 0；本季命令已判定；冲击已决并作用于 world
## 不变量：INV-011, INV-012, INV-054, INV-091, INV-109, INV-134
## 失败：content_hash 不符 → 拒绝推进；流量清零后非零 → FLOW_NOT_RESET；
##       shock_log 与计数器矛盾 → RNG_LOG_MISMATCH
##
## 与 docs/17 §5.1 清单的**唯一顺序差异**：第 2 条（版本校验）与第 8 条（命令判定）提到全部
## 状态写入之前。理由是 docs/12 §0.6 的 REJECT 语义要求「状态完全不变」，而这两条都是纯判定：
## `_verify_versions` 只读 meta，`validate_batch` / `check_advance_marker` 只读命令缓冲与 q，
## 都不读 §01.1–§01.7 写过的任何字段，提前执行不改变任何结果。
func _step_s01(cmds: JWCommands) -> int:
	# ── 第 2 条：版本校验（INV-134）──────────────────────────────────────
	var rc: int = _verify_versions()
	if rc != JWResult.OK:
		return rc

	# ── 第 8 条：命令判定（只判定不执行；被拒命令仍入档，INV-137）─────────
	if cmds == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, JWUnits.Phase.S01, 0)
	cmds.validate_batch(_st.q, _st.policy_defs)
	var rc_mark: int = cmds.check_advance_marker(_st.q)
	if rc_mark != JWResult.OK:
		# 本季没有推进标记（或标记不在末尾）：这是命令流不合法，按 REJECT 交回，
		# 状态一位不改。docs/17 §4.29 的前置条件就写着「本季命令流以一条 advance_quarter 结尾」。
		return rc_mark

	# ── 第 1 条：记上季末哈希 ────────────────────────────────────────────
	_st.state_hash_prev = _st.state_hash()

	# ── 第 3 条前的快照：三项「上季已实现的量」────────────────────────────
	# reset_all_flows() 之后它们就再也读不到了（见成员声明处的理由）。
	# R-EXPECT-01：第 0 季没有「上季」，也就没有可用于更新预期的观测；
	# 此时令 D_prev := E_prev（预期保持剧本给定的基年水平），而不是拿开局为 0 的流量把预期砍掉。
	var no_prev_obs: bool = _st.q == 0
	var cell: int = 0
	while cell < JWUnits.CELL:
		if no_prev_obs:
			_sc_sold_prev[cell] = _st.sectors.demand_expect[cell]
			_sc_unmet_prev[cell] = 0
		else:
			# 市场成交 + 直接售出（住房服务交租，R-HOUSING-01）都是上季实现的需求。
			_sc_sold_prev[cell] = _st.inventory.f_sold[cell] + _st.inventory.f_sold_direct[cell]
			_sc_unmet_prev[cell] = _st.inventory.f_unmet_demand[cell]
			# 能源 cell 的主要需求走电网配给（R-POWER-01），不在市场成交里。D_prev 必须加上
			# 上季本地区电网总需求（含各 cell 生产用电、能源自用与生命线；配给 + 未满足）——
			# 否则能源的需求预期只看得见居民与出口，被系统性低估，计划产量逐季下滑。
			# R-GRID-01 补遗：跨区输电之后，能源 cell 的已实现需求是它**自己**经电网的实际交付
			# （自用 + 本地 + 跨区输出），未满足部分取本地区电网在输电之后仍缺的生产用电。
			if JWIds.sector_of_cell(cell) == JWUnits.Sector.ENERGY:
				_sc_sold_prev[cell] += _st.sectors.f_elec_delivered[cell]
				_sc_unmet_prev[cell] += _st.sectors.f_elec_unmet[JWIds.region_of_cell(cell)]
		_sc_invest_prev[cell] = _st.capital.f_cell_investment[cell]
		cell += 1

	# ── 第 3 条：流量整表清零（全局唯一允许处）───────────────────────────
	rc = _st.reset_all_flows()
	if rc != JWResult.OK:
		return rc

	# ── 第 4 条：日志通道重置 + 随机流开季 ───────────────────────────────
	_st.ledger.log_reset_quarter()
	_st.rng.begin_quarter(_st.q)
	_st.pricing.log_reset_quarter()
	_st.treasury.log_reset_quarter()
	_st.shocks.log_reset_quarter()
	_st.diag.log_reset_quarter()
	cmds.log_reset_quarter()

	# 本季的跨步标记归零（它们不是状态，只是本类的步间中转）。
	_cancel_region_mask = 0
	_bond_default_flag = 0
	_fiscal_signal = 0
	_sc_breach.fill(0)
	_sc_breach_mask.fill(0)

	# ── 第 5 条：国库记季初现金（INV-027 的基准）─────────────────────────
	_st.treasury.begin_quarter(_st.accounts)
	# INV-086 的季初基准：缺它时 settle_income_and_savings 只做定义式自检，不做 Δ 核对。
	rc = _st.pop.snapshot_quarter_start_balances(_st.accounts)
	if rc != JWResult.OK:
		return rc

	# ── 第 6 条：产能转入（capacity_active 的唯一增量写入点，INV-054/091）──
	rc = _st.capital.commit_pending()
	if rc != JWResult.OK:
		return rc

	# ── 第 7 条：completed → commissioned ───────────────────────────────
	rc = _st.commissioning.promote_completed(_st.projects, _st.q)
	if rc != JWResult.OK:
		return rc

	# ── 第 9 条：冲击先查后抽（INV-109）──────────────────────────────────
	rc = _st.shocks.resolve_quarter(_st.rng, _st.world, _st.q, _st.params)
	if rc != JWResult.OK:
		return rc

	# ── 第 10 条：冲击作用于 world 白名单（INV-108）──────────────────────
	rc = _st.shocks.apply_to_world(_st.world, _st.q, _st.params)
	if rc != JWResult.OK:
		return rc

	# INV-011：本季日志行数与抽样计数必须对得上。
	if _st.rng.log_row_count() != _st.rng.draws_this_quarter():
		return JWResult.raise_fault(JWResult.Fault.RNG_LOG_MISMATCH,
				_st.rng.log_row_count(), _st.rng.draws_this_quarter())
	return JWResult.OK


## S02 审核与融资。可写：POLICY | PROJECT | GOV | BOND | WORLD | POLITICS | META
## 步骤：S02（docs/12 §2.1–§2.8）
## 前置：phase == S02；S01 已完成
## 后置：本季每条已受理命令恰好被处理一次；利息与本金已排程并按优先级付讫或登记欠付
## 不变量：INV-016, 028, 030, 032..041, 092..095, 098, 127
## 失败：现金不足且无法融资 → 推迟并生成 arrears（不静默改账）；批次超上限 → REJECT 新发行；
##       gov.cash 将为负 → NEGATIVE_CASH；debt != Σ outstanding → BOND_MISMATCH
func _step_s02(cmds: JWCommands) -> int:
	# 第 1 条：本季已受理命令，按 (issued_q, command_id) 升序。
	# 命令缓冲按 1.5 倍自增长（JWCommands._ensure_cmd_capacity），行号缓冲必须跟得上它的
	# **容量**而不是 count：accepted_this_quarter_into 装不下就整体失败，少执行几条命令会让
	# 重放分歧。比较是 O(1)；resize 只在命令缓冲真的涨过之后发生（一局至多几次），
	# 不是逐季分配，因此不破坏「热路径不分配」（docs/17 §1.4）。
	if _sc_cmd_rows.size() < cmds.c_kind.size():
		_sc_cmd_rows.resize(cmds.c_kind.size())
	var rows: int = cmds.accepted_this_quarter_into(_sc_cmd_rows, _st.q)
	if JWResult.has_pending():
		return JWResult.pending_code()

	# 集团立场的只读视图：try_enact 的冻结签名里没有 JWInterestGroups，
	# 而 §2.1 第 1 项资格检查（集团否决）必须读立场（JWPolicyEngine 的注释点名要求注入）。
	_st.policy.set_bloc_stance_view(_st.blocs.stance_array())
	# R-AUTHORITY-01：按改革域持有否决资格的集团（工商业联盟 → 财税法域）。
	if _veto_view.size() != JWUnits.POLICY_N:
		_veto_view.resize(JWUnits.POLICY_N)
	var rc_vv: int = _st.blocs.veto_masks_into(_veto_view)
	if rc_vv != JWResult.OK:
		return rc_vv
	_st.policy.set_bloc_veto_view(_veto_view)

	# 第 9 条（R-WINDOW-01 前移到命令受理之前）：预算审议标记（q ≡ 3 (mod 4)，INV-127）。
	# 立法窗口是命令资格链的输入（JWPolicyEngine.try_enact 读 f_budget_review_due）；
	# 原先排在命令执行之后置位，审查季提交的命令读到的永远是 0，requires_budget_review 的政策永远开不了。
	var rc_rv: int = _st.politics.mark_budget_review(_st.q)
	if rc_rv != JWResult.OK:
		return rc_rv

	# R-PARAMS-01：到期的排期参数先落地（本季起生效），再受理本季命令。
	_st.policy.commit_due_params(_st.q, _st.policy_defs)

	# R-PROJECT-01 ⑤：挂起项目复工（SUSPENDED → IN_PROGRESS）。挂起原因由 S04（财务）与 S05（施工能力）
	# 逐季重判，仍不满足就当季再挂起；排在命令之前，本季的取消命令看到的是复工后的状态（取消对二者一视同仁）。
	var rc_rs: int = _st.projects.resume_suspended(_st.q)
	if rc_rs != JWResult.OK:
		return rc_rs

	# 第 2/3 条：逐条执行。任一条的业务性拒绝都写回命令行的 reject_code，不中断本步。
	var i: int = 0
	while i < rows:
		var rc_cmd: int = _apply_command(cmds, _sc_cmd_rows[i])
		if rc_cmd != JWResult.OK and rc_cmd < JWResult.Reject.RUN_TERMINATED:
			# 非 Reject 即 Fault：立刻交回主循环（docs/12 §0.6 的三种失败语义）。
			return rc_cmd
		i += 1

	# 第 4 条：资金来源预留（JWPolicyEngine.try_enact 内部已按 §2.2 调 treasury.reserve，
	# 见该函数「开关成本过账排在预留之前」的说明）。本步不再重复预留，重复预留会让
	# INV-033 的 `reserved_memo <= cash` 在同一笔上被扣两次。

	# 第 5 条：逐批次计息（INV-036/004）。
	var rc: int = _st.bonds.accrue_interest(_st.q)
	if rc != JWResult.OK:
		return rc

	# 第 6 条：排本金（分期表 Σ == 面值，INV-037）。
	rc = _st.bonds.schedule_principal(_st.q)
	if rc != JWResult.OK:
		return rc

	# R-FINANCE-01：到期本息先再融资、后付款。这是再融资而不是展期——到期批次照常按原条款结清，
	# 新批次按当季利率另行发行（固定利率旧债不重定价，INV-038）。融不到的部分才在下面显露为违约。
	var ds_due: int = 0
	var b_i: int = 0
	while b_i < _st.bonds.count:
		ds_due += _st.bonds.interest_due[b_i] + _st.bonds.principal_due[b_i]
		b_i += 1
	# R-ROLLOVER-01：还本只动用「一季营运现金」之上的余额（营运现金 = 年化经常性收入 ÷ 4，
	# S04 的工资、转移、采购要靠它）；其余到期本金由原持有人按本季价格续发承接——再融资，不是展期。
	# 票息已触上限（市场不再按价出清）时不续发，缺口照常在下面预融资、再显露为违约。
	var float_uu: int = JWMath.floor_div(_st.treasury.state_scalar(8), 4)
	var spare: int = maxi(0, _st.accounts.cash_of(JWIds.AGENT_GOV) - float_uu)
	if ds_due > spare:
		var n_before2: int = _st.bonds.count
		var rc_roll: int = _st.treasury.rollover_principal(ds_due - spare, _st.bonds, _st.world,
				_st.accounts, _st.q, _st.entity_seq + 1, _st.params)
		_st.entity_seq += _st.bonds.count - n_before2
		if rc_roll != JWResult.OK and rc_roll < JWResult.Reject.RUN_TERMINATED:
			return rc_roll
		ds_due = 0
		b_i = 0
		while b_i < _st.bonds.count:
			ds_due += _st.bonds.interest_due[b_i] + _st.bonds.principal_due[b_i]
			b_i += 1
	var ds_gap: int = ds_due - _st.accounts.cash_of(JWIds.AGENT_GOV)
	if ds_gap > 0:
		var n_before: int = _st.bonds.count
		var rc_pre: int = _st.treasury.issue_debt_up_to(ds_gap, _st.bonds, _st.world,
				_st.ledger, _st.accounts, _st.q, _st.entity_seq + 1, _st.params)
		_st.entity_seq += _st.bonds.count - n_before
		if rc_pre != JWResult.OK and rc_pre < JWResult.Reject.RUN_TERMINATED:
			return rc_pre

	# 第 7 条：付本息（短缺先显露，不自动展期）。
	var arrears_before: int = _st.treasury.arrears
	rc = _st.treasury.pay_debt_service(_st.bonds, _st.ledger, _st.accounts, _st.q, _st.params)
	if rc == JWTreasury.SIGNAL_FISCAL_RESTRUCTURING_FAILED:
		# 连续 default_grace_q 季付不出第 1 档：这是给 S08 的信号，不是故障（INV-040）。
		_fiscal_signal = rc
		rc = JWResult.OK
	if rc != JWResult.OK and rc < JWResult.Reject.RUN_TERMINATED:
		return rc

	# docs/12 §2.5：债务违约时置 mandate_status = at_risk。
	# treasury 不持有 politics（签名冻结），由本类按 deferral_flag 落实。
	if _st.treasury.deferral_flag[JWUnits.PayLine.DEBT_SERVICE] == 1:
		_bond_default_flag = 1
		if _st.politics.mandate_status == JWUnits.MandateStatus.OK:
			_st.politics.mandate_status = JWUnits.MandateStatus.AT_RISK

	# 第 8 条：必要时融资。触发条件是**本季本息的实际短缺**（arrears 的增量），
	# 不是预测值：docs/12 §2.5 要求短缺先显露，§2.6 才补融资。
	var shortfall: int = _st.treasury.arrears - arrears_before
	if shortfall > 0:
		var before_n: int = _st.bonds.count
		var rc_issue: int = _st.treasury.issue_debt_up_to(shortfall, _st.bonds, _st.world,
				_st.ledger, _st.accounts, _st.q, _st.entity_seq + 1, _st.params)
		# 一次 issue_debt 最多产生两个批次（国内 + 外部），必须按**实际批次数**推进 entity_seq，
		# 否则下一次发行会撞 ID（INV-010）。
		_st.entity_seq += _st.bonds.count - before_n
		if rc_issue != JWResult.OK and rc_issue < JWResult.Reject.RUN_TERMINATED:
			return rc_issue

	# 第 9 条已按 R-WINDOW-01 前移到命令受理之前（见本函数开头）。

	# 第 10 条：blocked_reason 重算（INV-100）。
	rc = _st.policy.refresh_blocked_reasons(_st.policy_defs, _st.politics, _st.treasury,
			_st.projects, _st.capital, _st.accounts, _st.q, _st.params)
	if rc != JWResult.OK:
		return rc
	return JWResult.OK


## 执行一条已受理命令（docs/11 §6.1 的 12 种 + 推进标记）。
## 步骤：S02 §2.1
## 前置：row ∈ [0, cmds.count)；该行 c_accepted == 1
## 后置：命令生效或被拒；被拒时写回 c_accepted / c_reject_code（INV-137：被拒命令仍入档）
## 不变量：INV-095, 098, 137, 138
## 失败：Fault 直接上抛；Reject 写回命令行后返回该 Reject 码
func _apply_command(cmds: JWCommands, row: int) -> int:
	var kind: int = cmds.c_kind[row]
	var rc: int = JWResult.OK
	match kind:
		JWCommands.Kind.POLICY_ENACT:
			rc = _cmd_policy_enact(cmds, row)
		JWCommands.Kind.POLICY_SET_PARAMS:
			rc = _cmd_policy_params(cmds, row)
		JWCommands.Kind.POLICY_REPEAL:
			rc = _st.policy.try_repeal(cmds.arg_at(row, JWCommands.SLOT_POLICY),
					_st.policy_defs, _st.treasury, _st.ledger, _st.accounts, _st.q)
		JWCommands.Kind.PROJECT_LAUNCH:
			rc = _cmd_project_launch(cmds, row)
		JWCommands.Kind.PROJECT_CANCEL:
			rc = _cmd_project_cancel(cmds.arg_at(row, JWCommands.SLOT_PROJECT))
		JWCommands.Kind.ISSUE_BOND:
			rc = _cmd_issue_bond(cmds.arg_at(row, JWCommands.SLOT_BOND_AMOUNT),
					cmds.arg_at(row, JWCommands.SLOT_BOND_TENOR),
					cmds.arg_at(row, JWCommands.SLOT_BOND_HOLDER))
		JWCommands.Kind.DEBT_RESTRUCTURE:
			rc = _cmd_restructure(cmds.arg_at(row, JWCommands.SLOT_BOND),
					cmds.arg_at(row, JWCommands.SLOT_RESTRUCTURE_MODE))
		JWCommands.Kind.SET_PAYMENT_PRIORITY:
			rc = _cmd_payment_priority(cmds.arg_at(row, JWCommands.SLOT_PRIORITY_PACKED))
		JWCommands.Kind.SELECT_MANDATE_GOAL:
			rc = _cmd_mandate_goal(cmds.arg_at(row, JWCommands.SLOT_GOAL))
		JWCommands.Kind.PROJECT_DEFER:
			rc = _st.projects.defer(cmds.arg_at(row, JWCommands.SLOT_PROJECT),
					cmds.arg_at(row, JWCommands.SLOT_DEFER_QUARTERS), _st.q, _st.params,
					_st.treasury, _st.ledger, _st.accounts)
		JWCommands.Kind.BUDGET_REALLOCATE, JWCommands.Kind.SET_STANDING_RULE:
			# 这两种命令在 SimCore 里没有落点：JWTreasury 没有档间调剂入口（各支出档由规则决定，
			# 没有可调剂的分档拨款），常设指令没有承载它的状态字段。
			# 显式拒绝并写回原因码，不假装执行（见返回值 open_questions）。
			rc = JWResult.Reject.PRECONDITION
		_:
			rc = JWResult.Reject.NOT_FOUND
	if rc != JWResult.OK and rc >= JWResult.Reject.RUN_TERMINATED:
		# 业务性拒绝：命令仍在档，只是标记为未受理（INV-137）。
		cmds.c_accepted[row] = 0
		cmds.c_reject_code[row] = rc
	return rc


## 通过一项政策（命令 1）。
## 步骤：S02 §2.1
## 前置：row ∈ [0, cmds.count)
## 后置：受理 ⇒ 参数落定且政策通过；拒绝 ⇒ 该政策的参数槽与命令之前逐位相同（INV-137）
## 不变量：INV-095, 098, 137
## 失败：已在执行 → Reject.ALREADY_ENACTED（R-ENACT-01）；其余转发资格链的 Reject
##
## R-ENACT-01：原先先写参数、后判资格——对开局即在执行的 P01—P03 递交「通过」命令，
## try_enact 虽以 ALREADY_ENACTED 拒绝，参数却已按 R-PARAMS-01 排期，被拒的命令改了税制，
## 还绕开了预算审议窗口（R-WINDOW-01 只拦 POLICY_SET_PARAMS）。改执行中政策的参数只能走命令 2。
func _cmd_policy_enact(cmds: JWCommands, row: int) -> int:
	var p: int = cmds.arg_at(row, JWCommands.SLOT_POLICY)
	if p < 0 or p >= JWUnits.POLICY_N:
		return JWResult.Reject.UNKNOWN_POLICY
	if _st.policy.enabled[p] == 1:
		return JWResult.Reject.ALREADY_ENACTED
	_st.policy.snapshot_params(p)
	var rc: int = _cmd_policy_params(cmds, row)
	if rc == JWResult.OK:
		rc = _st.policy.try_enact(p, _st.policy_defs, _st.politics, _st.treasury, _st.projects,
				_st.capital, _st.ledger, _st.accounts, _st.q, _st.params)
	if rc != JWResult.OK and rc >= JWResult.Reject.RUN_TERMINATED:
		# 业务性拒绝：参数槽回到命令之前（故障不回滚——故障本身就中止结算）。
		_st.policy.restore_params(p)
	return rc


## 把命令的 4 个玩家参数槽写进 pending_params 并落定（INV-138 允许的唯一状态写入）。
## 步骤：S02 §2.1
## 前置：槽 1..4 是 player_params 的 j = 0..3
## 后置：pending_params 写入后立即 apply_pending_params
## 不变量：INV-098（冷却期内不许改参数由 apply_pending_params 自己拦）
## 失败：转发 apply_pending_params 的 Reject
func _cmd_policy_params(cmds: JWCommands, row: int) -> int:
	var p: int = cmds.arg_at(row, JWCommands.SLOT_POLICY)
	if p < 0 or p >= JWUnits.POLICY_N:
		return JWResult.Reject.UNKNOWN_POLICY
	# R-WINDOW-01 / R-PARAMS-01：修改**执行中**的税制与法定支出（requires_budget_review 的四项）
	# 同样只能在预算审议季提出；新通过的政策由 try_enact 自己判窗口。
	if cmds.c_kind[row] == JWCommands.Kind.POLICY_SET_PARAMS and _st.policy.enabled[p] == 1 \
			and _st.policy_defs.requires_budget_review[p] == 1 \
			and _st.politics.f_budget_review_due != 1:
		return JWResult.Reject.PRECONDITION
	var j: int = 0
	while j < JWIds.POLICY_PARAM_STRIDE:
		_st.policy.pending_params[JWIds.idx_policy_param(p, j)] = \
				cmds.arg_at(row, JWCommands.SLOT_PARAM_BASE + j)
		j += 1
	return _st.policy.apply_pending_params(p, _st.policy_defs, _st.q)


## 立项（命令 4）：把 JWProjectQueue.launch 的**项目下标**翻译成错误码。
## 步骤：S02 §2.7
## 前置：row ∈ [0, cmds.count)
## 后置：成功 ⇒ 新项目入队且 entity_seq 恰好 +1；失败 ⇒ 状态不变、entity_seq 不动
## 不变量：INV-010（ID 单调且不跳号）、INV-094（Σ slot_held <= slots_total）
## 失败：无空槽 → Reject.NO_SLOT（S02 第 10 条的 refresh_blocked_reasons 据此把
##       blocked_reason 置成 QUEUE）；launch 已登记的故障原样上抛
##
## `launch` 的返回值是**新项目的下标**（docs/17 §4.19：「无空槽 → 返回 -1」），不是错误码。
## 直接把它当 rc 用，第 2 个立项返回的下标 1 会被 `_apply_command` 判成「非 Reject 即 Fault」
## 并作为故障码 1 交回主循环——而 1 == Fault.RUN_ENDED，于是第 0 季就被报成「已终局」，
## 且 JWResult 里没有任何登记（因为根本没人 raise_fault）。ADV-C04 / ADV-F02 红在这里。
## entity_seq 的推进也因此改成「成功才 +1」：`next_entity_seq()` 在入队失败时也会把计数器
## 推走，与 `_cmd_issue_bond` 的「按实际新增批次数推进」不是同一口径。
func _cmd_project_launch(cmds: JWCommands, row: int) -> int:
	# R-LAUNCH-01：先过政策资格链的权限 / 否决 / 窗口两档，被拒即状态不变（INV-137）。
	var pol: int = cmds.arg_at(row, JWCommands.SLOT_POLICY)
	if pol < 0 or pol >= JWUnits.POLICY_N:
		return JWResult.Reject.UNKNOWN_POLICY
	var rc_el: int = _st.policy.check_launch_eligibility(pol, _st.policy_defs, _st.politics)
	if rc_el != JWResult.OK:
		return rc_el
	# R-PROJECT-01 ⑤：立项命令的 scale_ppm（槽 2，提交期已校验 [0, PPM]）传入 launch()，
	# 合同额、工程量、设备量、产能效果与运行费同倍缩放。原先这一槽没有落点，任何规模都按满规模立项。
	var p: int = _st.projects.launch(_st.entity_seq + 1,
			cmds.arg_at(row, JWCommands.SLOT_POLICY),
			cmds.arg_at(row, JWCommands.SLOT_LAUNCH_REGION),
			_st.policy_defs, _st.capital, _st.q,
			cmds.arg_at(row, JWCommands.SLOT_LAUNCH_SCALE))
	if p >= 0:
		_st.entity_seq += 1
		# 立项即签约开工：合同总额计入承诺（INV-032），状态 planned → in_progress。
		# 原先只调 launch()，项目永远停在 planned，取消时承诺冲减必然失衡。
		return _st.projects.start(p, _st.treasury)
	# launch 的失败分三类：参数／容量类已经 raise_fault 过（必须原样上抛，不许降级成
	# 业务拒绝）；规模缩放后合同退化（合同额为 0 或每季施工量不足 1）是参数越界；
	# 纯粹的「本地区没有空槽」没有登记任何故障，那才是 Reject.NO_SLOT。
	if JWResult.has_pending():
		return JWResult.pending_code()
	if p == JWProjectQueue.LAUNCH_DEGENERATE_SCALE:
		return JWResult.Reject.PARAM_RANGE
	return JWResult.Reject.NO_SLOT


## 取消一个项目：取消 → 赔偿金 → 残值登记（docs/12 §2.7）。
## 步骤：S02 §2.1 第 3 条
## 前置：p ∈ [0, projects.count)
## 后置：项目转 cancelled，槽位释放，已付不退（INV-093）；本季取消地区记入失信位掩码
## 不变量：INV-093, INV-094
## 失败：转发各调用的错误码
func _cmd_project_cancel(p: int) -> int:
	if p < 0 or p >= _st.projects.count:
		return JWResult.Reject.NOT_FOUND
	var r: int = _st.projects.region_of(p)
	var rc: int = _st.projects.cancel(p, _st.policy_defs, _st.treasury, _st.ledger,
			_st.accounts, _st.capital)
	if rc != JWResult.OK:
		return rc
	rc = _st.commissioning.pay_cancel_penalty(_st.projects, p, _st.policy_defs,
			_st.treasury, _st.ledger, _st.accounts)
	if rc != JWResult.OK and rc < JWResult.Reject.RUN_TERMINATED:
		return rc
	rc = _st.commissioning.register_residual(_st.projects, p, _st.capital,
			_st.ledger, _st.accounts)
	if rc != JWResult.OK and rc < JWResult.Reject.RUN_TERMINATED:
		return rc
	if r >= 0 and r < JWUnits.R:
		_cancel_region_mask = _cancel_region_mask | (1 << r)
	return JWResult.OK


## 玩家主动发债（命令 8）。
## 步骤：S02 §2.6
## 前置：amount_uu > 0
## 后置：新批次入 SoA；entity_seq 按**实际批次数**推进（INV-010）
## 不变量：INV-034, INV-029
## 失败：额度不足 → Reject.CREDIT_LIMIT
##
## `tenor_q` 槽拿不到落点：JWTreasury.issue_debt 的冻结签名里没有期限形参，期限由它内部
## 按 §2.6 推出。命令层的 [4, 40] 区间校验仍然生效（JWCommands.TENOR_MIN/MAX），
## 但玩家选的期限目前进不了 bond_book —— 见返回值 interface_requests。
func _cmd_issue_bond(amount_uu: int, tenor_q: int, holder: int) -> int:
	if amount_uu <= 0:
		return JWResult.Reject.PARAM_RANGE
	# 玩家命令：按玩家指定的债权人与期限发一个批次，全有全无，**不转投另一债权人**
	# （指定国内却悄悄变外债，就是绕过国内额度闸门，ADV-C03）。
	var before_n: int = _st.bonds.count
	var rc: int = _st.treasury.issue_bond_to(amount_uu, tenor_q, holder, _st.bonds, _st.world,
			_st.ledger, _st.accounts, _st.q, _st.entity_seq + 1, _st.params)
	_st.entity_seq += _st.bonds.count - before_n
	return rc


## 债务重组（命令 9）：bond_book 改账，本类补 WRITEOFF 分录、flow.gov.recognized_writeoffs 与欠付核销。
## 步骤：S02 §2.5
## 前置：b ∈ [0, bonds.count)；mode ∈ JWBondBook.RestructureMode
## 后置：确认减记的本金（bonds.last_writeoff_uu）经 post(kind=WRITEOFF) 落账并计入
##       flow.gov.recognized_writeoffs_uu；该批次移出的已计未付（bonds.last_writeoff_arrears_uu：
##       减记/违约了结的未付本息，延期顺延回分期表的逾期本金）经 treasury.write_off_arrears
##       从 gov.arrears 注销并计入 flow.gov.arrears_written_off_uu（第三轮裁定：重组核销欠付）
## 不变量：INV-028（debt_end == debt_start + 新增借款 − 还本 − 确认减记）、
##          INV-030（arrears_end == start + 新增 − 清偿 − 核销）、INV-025（Σ bondhold == debt）
## 失败：转发 bonds.restructure / write_off_arrears 的错误码
##
## JWTreasury 没有 restructure 入口（签名冻结），减记的后续动作（过账、流量登记、欠付核销）
## 因此落在本类：bonds.last_writeoff_uu / last_writeoff_arrears_uu 是 bond_book 的公开输出口，每次调用前清零。
func _cmd_restructure(b: int, mode: int) -> int:
	if b < 0 or b >= _st.bonds.count:
		return JWResult.Reject.NOT_FOUND
	if mode < 0 or mode >= JWCommands.RESTRUCTURE_MODE_N:
		return JWResult.Reject.PARAM_RANGE
	var rc: int = _st.bonds.restructure(b, mode, _st.q)
	if rc != JWResult.OK:
		return rc
	var holder_agent: int = JWIds.AGENT_INVPOOL
	if _st.bonds.holder[b] == JWUnits.Holder.ROW:
		holder_agent = JWIds.AGENT_ROW
	var writeoff: int = _st.bonds.last_writeoff_uu
	if writeoff > 0:
		# 债权人的持债资产减记：资产腿 −，净值腿由 _settle_nw 自动补（Δnw 就是损失本身）。
		rc = _st.ledger.post_noncash(JWUnits.Kind.WRITEOFF, holder_agent,
				JWIds.ACC_BONDHOLD, -writeoff, CAUSE_RUNNER, b)
		if rc != JWResult.OK:
			return rc
		# 债务人的负债减记，同样两腿。
		rc = _st.ledger.post_noncash(JWUnits.Kind.WRITEOFF, JWIds.AGENT_GOV,
				JWIds.ACC_DEBT, writeoff, CAUSE_RUNNER, b)
		if rc != JWResult.OK:
			return rc
		_st.treasury.f_writeoffs = JWMath.check_amount(_st.treasury.f_writeoffs + writeoff)
	# 该批次移出的已计未付：违约时它与 gov.arrears 同额登记（pay_debt_service），这里同额核销，
	# 否则同一笔要么在欠付里与减记重复（减记 / 违约），要么下季到期时再挂一遍（延期）。
	var released: int = _st.bonds.last_writeoff_arrears_uu
	if released > 0:
		rc = _st.treasury.write_off_arrears(holder_agent, released)
		if rc != JWResult.OK:
			return rc
	_bond_default_flag = 1
	return JWResult.OK


## 支付优先级重排（命令 10）。
## 步骤：S02 §2.2
## 前置：packed 是 8 档的一个全排列
## 后置：state.gov.payment_priority 被整体替换
## 不变量：INV-039
## 失败：非全排列 → Reject.PRIORITY_INCOMPLETE
func _cmd_payment_priority(packed: int) -> int:
	var rc: int = JWCommands.unpack_payment_priority_into(_sc_pay_order, packed)
	if rc != JWResult.OK:
		return rc
	return _st.treasury.set_state_array(1, _sc_pay_order)


## 施政目标选择（命令 12）。
## 步骤：S02 §2.1
## 前置：goal ∈ JWUnits.MandateGoal
## 后置：politics.mandate_goal 被替换
## 不变量：INV-128（终局式只看 mandate_goal 对应的指标，不看 GDP）
## 失败：越界 → Reject.PARAM_RANGE
func _cmd_mandate_goal(goal: int) -> int:
	if goal < JWUnits.MandateGoal.INDUSTRY or goal > JWUnits.MandateGoal.FISCAL:
		return JWResult.Reject.PARAM_RANGE
	_st.politics.mandate_goal = goal
	return JWResult.OK


## S03 计划与就业。可写：CELL | PUBSERV | GROUP | REGION | MARKET | RNG
## 步骤：S03（docs/12 §3.1–§3.6）
## 前置：phase == S03；S02 已完成
## 后置：产出计划、用工、失业率（反算）、投入订单与投资意愿就位
## 不变量：INV-074..080
## 失败：Σ employed > pool → EMPLOYMENT_OVERFLOW；现金不足付期望工资 → 缩减并写 log.clamp
func _step_s03() -> int:
	var rc: int = _st.sectors.plan_output(_sc_sold_prev, _sc_unmet_prev,
			_st.inventory, _st.io, _st.params)
	if rc != JWResult.OK:
		return rc
	rc = _st.labor.hire_and_fire(_st.sectors.f_output_plan, _st.io, _st.pricing,
			_st.pop, _st.accounts, _st.params)
	if rc != JWResult.OK:
		return rc
	rc = _st.labor.compute_unemployment(_st.pop)
	if rc != JWResult.OK:
		return rc
	rc = _st.labor.check_employment_views(_st.pop)
	if rc != JWResult.OK:
		return rc
	rc = _st.sectors.order_inputs(_st.io, _st.pop, _st.params)
	if rc != JWResult.OK:
		return rc
	return _st.sectors.compute_invest_intent(_st.capital, _st.params, _st.io)


## S04 工资与投入。可写：全部 cash、GROUP | CELL | PUBSERV | GOV | PROJECT | POLICY
## 步骤：S04（docs/12 §4.1–§4.5）
## 前置：phase == S04；S03 已完成
## 后置：工资先于消费付讫；8 档支付优先级按序执行；预留季末归零
## 不变量：INV-003, 015, 016, 030, 039, 079, 085, 087, 092, 096, 097
## 失败：企业现金不足付工资 → WAGE_UNFUNDED；政府现金不足 → 部分支付 + 欠付；
##       项目超付 → 拒付并转 suspended；拆分和不等 → SPLIT_MISMATCH
func _step_s04() -> int:
	# 第 1 条：企业付工资（**工资先于消费**）。
	var rc: int = _st.labor.pay_wages(_st.pricing, _st.pop, _st.ledger, _st.accounts)
	if rc != JWResult.OK:
		return rc

	# 第 2 条：按 payment_priority 遍历 8 档（INV-039：实际顺序必须与优先级一致）。
	var t: int = 0
	while t < JWUnits.PAY_LINE_N:
		var line: int = _st.treasury.payment_priority[t]
		rc = _pay_one_line(line)
		if rc != JWResult.OK and rc < JWResult.Reject.RUN_TERMINATED:
			return rc
		t += 1

	# 第 3 条：组间赡养转移（Σ support_in == Σ support_out，INV-085）。
	rc = _st.pop.pay_household_support(_st.ledger, _st.accounts, _st.params)
	if rc != JWResult.OK:
		return rc

	# 第 4 条：预留季末归零（INV-033）。
	return _st.treasury.release_reservations()


## 支付一档（docs/12 §04.2 的 2a–2h）。
## 步骤：S04 §4.2
## 前置：line ∈ JWUnits.PayLine
## 后置：该档已付讫或已登记欠付；分项流量已归集
## 不变量：INV-030, INV-039, INV-092, INV-097, INV-102
## 失败：转发各调用的错误码
func _pay_one_line(line: int) -> int:
	match line:
		JWUnits.PayLine.DEBT_SERVICE:
			# 2a：第 1 档在 S02 §2.5 已处理，本步跳过（重复支付会让 INV-027 与 INV-028 同时错）。
			return JWResult.OK
		JWUnits.PayLine.PUBLIC_WAGES:
			return _pay_public_wages()
		JWUnits.PayLine.STATUTORY_TRANSFERS:
			return _pay_transfers()
		JWUnits.PayLine.SERVICE_OPEX:
			return _pay_service_opex()
		JWUnits.PayLine.PROJECT_CONTRACTS:
			return _pay_projects()
		JWUnits.PayLine.PROCUREMENT:
			# 2f：采购档只预留额度，实际成交在 S05 §5.6（买方类 2）。
			return _reserve_procurement()
		JWUnits.PayLine.SUBSIDIES:
			return _pay_subsidies()
		JWUnits.PayLine.DISCRETIONARY:
			# 2h：机动档没有应付清单来源（年计划的 discretionary 档在 SimCore 里没有落点），
			# 本季不产生任何支付。见返回值 open_questions。
			return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, line, JWUnits.PAY_LINE_N)


## 2b 公共部门工资：取清单 → pay_line → 回写实付（同秩不互调，由本文件中转）。
## 步骤：S04 §4.2
## 前置：labor 与 pricing 已就位
## 后置：flow.pubserv.wage_bill_uu 与 flow.group.wage_income_uu 同步写入
## 不变量：INV-079, INV-101, INV-030
## 失败：转发 pay_line / record_public_wage_paid 的错误码
func _pay_public_wages() -> int:
	_sc_payee.fill(0)
	_sc_due.fill(0)
	var rows: int = _st.labor.public_wage_due_into(_sc_payee, _sc_due, _st.pricing, _st.pop)
	if JWResult.has_pending():
		return JWResult.pending_code()
	if rows <= 0:
		return JWResult.OK
	var rc_fin: int = _finance_before_pay(_sc_due)
	if rc_fin != JWResult.OK:
		return rc_fin
	var rc: int = _st.treasury.pay_line(JWUnits.PayLine.PUBLIC_WAGES, _sc_payee, _sc_due,
			JWUnits.Kind.PUBLIC_WAGE_PAYMENT, _st.ledger, _st.accounts)
	if rc != JWResult.OK:
		return rc
	# 实付额按群组下标对齐后回写（record_public_wage_paid 接受 GROUP 长度的形态）。
	_sc_group.fill(0)
	var i: int = 0
	while i < rows:
		var g: int = JWIds.group_of_agent(_sc_payee[i])
		if g >= 0 and g < JWUnits.GROUP:
			_sc_group[g] = _st.treasury.last_paid_of(i)
		i += 1
	return _st.labor.record_public_wage_paid(_sc_group, _st.pop)


## 2c 法定转移：现金不足 → 部分支付 + 欠付，**不得少算人数**。
## 步骤：S04 §4.2
## 前置：policy 已就位
## 后置：逐组实付与欠付登记完成；欠付的组记入本季失信位掩码（docs/12 §8.1）
## 不变量：INV-030, INV-121
## 失败：转发各调用的错误码
func _pay_transfers() -> int:
	var rc: int = _st.policy.transfer_due_into(_sc_tr_payee, _sc_tr_due, _st.pop,
			_st.labor, _st.policy_defs, _st.q, _st.params)
	if rc != JWResult.OK:
		return rc
	# R-PENSION-01：基本养老金是法定转移的常设部分（按老年人口 × 每人每季定额），与 P03 失业救济同档支付。
	var pension: int = _st.params[JWUnits.Param.PENSION_UU_PER_ELDER_Q]
	if pension > 0:
		var g0: int = 0
		while g0 < JWUnits.GROUP:
			if JWIds.age_of_group(g0) == JWUnits.Age.ELDER:
				_sc_tr_due[g0] = JWMath.check_amount(_sc_tr_due[g0]
						+ JWMath.mul(_st.pop.population[g0], pension))
			g0 += 1
	rc = _finance_before_pay(_sc_tr_due)
	if rc != JWResult.OK:
		return rc
	rc = _st.treasury.pay_line(JWUnits.PayLine.STATUTORY_TRANSFERS, _sc_tr_payee, _sc_tr_due,
			JWUnits.Kind.TRANSFER, _st.ledger, _st.accounts)
	if rc != JWResult.OK:
		return rc
	var g: int = 0
	while g < JWUnits.GROUP:
		var paid_g: int = _st.treasury.last_paid_of(g)
		# 实付额才是居民收入；欠付部分不计（INV-086）。
		if paid_g > 0:
			rc = _st.pop.record_transfer_paid(g, paid_g)
			if rc != JWResult.OK:
				return rc
		if _sc_tr_due[g] > paid_g:
			_sc_breach_mask[g] = _sc_breach_mask[g] | BREACH_TRANSFER
		g += 1
	return JWResult.OK


## 2d 公共服务运行费：本季可拨付额度决定 flow.pubserv.funding_ratio_ppm（INV-102）。
## 步骤：S04 §4.2
## 前置：state.gov.service_opex_committed_uu 是本季承诺的运行费总额
## 后置：逐地区 funding_ratio 写入；flow.gov.pay_opex_uu[] == 本季拨付额度（S05 公共服务买方类的预算）；
##       欠拨的地区记入失信位掩码，本档 deferral_flag 置位；**本步不过账、不动任何现金**
## 不变量：INV-102（欠拨只降可用率，不减资产）、INV-027（钱在 S05 成交时才流出，由那里登记基本支出）
## 失败：转发 split / set_funding_ratio / record_line_attribution 的错误码
##
## 承诺额是全国口径的一个标量（JWTreasury.service_opex_committed），而应付清单的契约长度是
## OPEX_N == R × SERVICE_KIND。拆分规则：先按各地区公共服务产能用最大余数法拆到地区，
## 再在地区内按服务种类下标升序等分（同样走最大余数法）。两级都完全确定，可重放。
##
## docs/18 R-PUBSERV-01：pubserv 不持现金（docs/10 §2.1），运行费是政府为公共服务购买的中间投入。
## 实际支出只发生在 S05 市场的公共服务买方类（JWInventory 以 f_pay_opex 为预算、由 gov 付 GOV_PROCUREMENT、
## 货进 f_pub_intermediate，S05 末按 gov 现金的 GOV_PROCUREMENT 净流出登记基本支出）。
## 原实现在这里再把同一笔钱 pay_line 进 pubserv 的现金户：钱付了两遍（S04 进 pubserv、S05 买投入），
## 且 pubserv 现金非零，现金闭合检查必报 22。本步因此只算「可拨付额度」——
## 与 pay_line 同一口径：先按 R-FINANCE-01 支付前融资，额度 = min(应拨, 政府现金)，
## 按各地区应拨额最大余数拆分——并把额度写进 f_pay_opex（record_line_attribution：只归集分项流量、
## 不计基本支出），funding_ratio、失信位由额度与应拨之差决定，逻辑与原先逐位相同。
## 欠拨**不**登记为对 pubserv 的欠付：欠付是日后要以现金清偿的债务，而 pubserv 不持现金；
## 裁定原文「欠拨仍只降低服务可用率」。本档的推迟只以 deferral_flag 与 funding_ratio 显露。
func _pay_service_opex() -> int:
	var committed: int = _st.treasury.service_opex_committed
	_sc_opex_due.fill(0)
	var r: int = 0
	if committed > 0:
		_sc_weights.fill(0)
		r = 0
		while r < JWUnits.R:
			_sc_weights[r] = _st.capital.pubserv_capacity(r)
			r += 1
		var res: int = JWMath.split_lr_into(committed, _sc_weights, _sc_tiebreak, _sc_out)
		if JWMath._split_last_fault != JWResult.OK:
			return JWMath._split_last_fault
		if res != 0:
			# 四地区产能全 0：拆不下去，整额留在承诺里不发，登记取整残差供对账（INV-005）。
			_st.ledger.log_rounding(CAUSE_RUNNER, committed, 0, res)
		else:
			r = 0
			while r < JWUnits.R:
				var due_r: int = _sc_out[r]
				var k2: int = 0
				while k2 < JWUnits.SERVICE_KIND:
					# rounding: lr, reason=地区内按服务种类等分，下标升序决胜（docs/12 §0.3）
					var share: int = JWMath.floor_div(due_r, JWUnits.SERVICE_KIND)
					if k2 < due_r - share * JWUnits.SERVICE_KIND:
						share += 1
					_sc_opex_due[JWIds.idx_opex(r, k2)] = share
					k2 += 1
				r += 1
	# R-POLSPEND-01：能力类与行政类政策（P05/P10/P11/P12）的项目期支出。原先只在 S02 预留、从不付款，
	# 效果却照常落地——这四项政策除开关成本外是免费的。现按作用地区（region_mask，0 == 全国）等权拆到地区、
	# 地区内按服务种类等分，并入本档应拨额：同一次融资、同一个可拨付比例，S05 由公共服务买方类花出。
	_prog_amt.fill(0)
	var prog_total: int = 0
	for pp: int in JWUnits.POLICY_N:
		var amt: int = _st.policy.program_due(pp, _st.policy_defs, _st.q)
		if amt <= 0:
			continue
		_prog_amt[pp] = amt
		prog_total += amt
		var pmask: int = _st.policy.region_mask[pp] & JWPolicyEngine.REGION_MASK_ALL
		if pmask == 0:
			pmask = JWPolicyEngine.REGION_MASK_ALL
		_sc_weights.fill(0)
		for r5: int in JWUnits.R:
			_sc_weights[r5] = 1 if ((pmask >> r5) & 1) == 1 else 0
		var res_p: int = JWMath.split_lr_into(amt, _sc_weights, _sc_tiebreak, _sc_out)
		if JWMath._split_last_fault != JWResult.OK:
			return JWMath._split_last_fault
		if res_p != 0:
			return JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, amt, res_p)
		for r6: int in JWUnits.R:
			var add_r: int = _sc_out[r6]
			var k6: int = 0
			while k6 < JWUnits.SERVICE_KIND:
				# rounding: lr, reason=地区内按服务种类等分，下标升序决胜（与运行费同一拆法）
				var sh: int = JWMath.floor_div(add_r, JWUnits.SERVICE_KIND)
				if k6 < add_r - sh * JWUnits.SERVICE_KIND:
					sh += 1
				_sc_opex_due[JWIds.idx_opex(r6, k6)] += sh
				k6 += 1

	var rc_fin: int = _finance_before_pay(_sc_opex_due)
	if rc_fin != JWResult.OK:
		return rc_fin

	# 可拨付额度 = min(应拨, 政府现金)（docs/12 §4.2 的 pay = min(due, gov.cash)，与 pay_line 同一口径）。
	var due_total: int = JWMath.sum(_sc_opex_due)
	var grant_total: int = due_total
	var cash: int = _st.accounts.cash_of(JWIds.AGENT_GOV)
	if grant_total > cash:
		grant_total = cash
	if grant_total < 0:
		grant_total = 0
	# 逐地区额度：足额时就是应拨额；不足时按各地区应拨额做最大余数拆分（地区下标升序决胜），
	# Σ 精确等于 grant_total（INV-003），且每地区额度 <= 该地区应拨额。
	_sc_weights.fill(0)
	_sc_out.fill(0)
	r = 0
	while r < JWUnits.R:
		var due_r0: int = 0
		var k0: int = 0
		while k0 < JWUnits.SERVICE_KIND:
			due_r0 += _sc_opex_due[JWIds.idx_opex(r, k0)]
			k0 += 1
		_sc_weights[r] = due_r0
		_sc_out[r] = due_r0
		r += 1
	if grant_total < due_total:
		var res_g: int = JWMath.split_lr_into(grant_total, _sc_weights, _sc_tiebreak, _sc_out)
		if JWMath._split_last_fault != JWResult.OK:
			return JWMath._split_last_fault
		if res_g != 0:
			# due_total > grant_total >= 0 ⇒ 权重和 > 0，「残差 == total」的分支走不到。
			return JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, grant_total, res_g)
		_st.treasury.deferral_flag[JWUnits.PayLine.SERVICE_OPEX] = 1

	# R-P10-01：带「每季拨款」旋钮的政策（P10 grant_per_q_uu），其投运后并入本档的运行费只在拨款额内拨付；
	# 退出后拨款为 0。欠拨差额在该政策作用地区间按各地区本档应拨额加权拆分（运行费义务按地区公共服务
	# 产能摊到各地区，欠拨跟着义务走；作用地区应拨额全为 0 时等权），从各地区实拨额里扣下（不超过实拨额）；
	# 应拨额不变，funding_ratio 随之低于 1 ⇒ S07 可用率按断供规则衰减（policy_P10.json effect_chain 3—4）。
	for pg: int in JWUnits.POLICY_N:
		var short: int = _st.policy.grant_shortfall(pg, _st.policy_defs)
		if short <= 0:
			continue
		var gmask: int = _st.policy.region_mask[pg] & JWPolicyEngine.REGION_MASK_ALL
		if gmask == 0:
			gmask = JWPolicyEngine.REGION_MASK_ALL
		var wsum: int = 0
		for rg: int in JWUnits.R:
			_grant_w[rg] = _sc_weights[rg] if ((gmask >> rg) & 1) == 1 else 0
			wsum += _grant_w[rg]
		if wsum == 0:
			for rg1: int in JWUnits.R:
				_grant_w[rg1] = 1 if ((gmask >> rg1) & 1) == 1 else 0
		var res_gr: int = JWMath.split_lr_into(short, _grant_w, _grant_tb, _grant_out)
		if JWMath._split_last_fault != JWResult.OK:
			return JWMath._split_last_fault
		if res_gr != 0:
			return JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, short, res_gr)
		for rg2: int in JWUnits.R:
			var cut: int = mini(_grant_out[rg2], _sc_out[rg2])
			if cut > 0:
				# 只扣运行费的实拨额；项目期支出（下方 budget_spent）按现金可拨付比例另计，不受拨款旋钮影响。
				_sc_out[rg2] -= cut
				_st.treasury.deferral_flag[JWUnits.PayLine.SERVICE_OPEX] = 1

	# R-POLSPEND-01：项目期实付按本档可拨付比例折算后记入各政策的 budget_spent（INV-096）。
	if prog_total > 0:
		for pq: int in JWUnits.POLICY_N:
			if _prog_amt[pq] <= 0:
				continue
			var paid_p: int = _prog_amt[pq]
			if grant_total < due_total:
				# rounding: floor, reason=少记实付优于多记（不足额时承诺余额留到下一季）
				paid_p = JWMath.mul_div_floor(_prog_amt[pq], grant_total, maxi(1, due_total))
			var rc_ps: int = _st.policy.record_program_spend(pq, paid_p)
			if rc_ps != JWResult.OK:
				return rc_ps

	var rc: int = JWResult.OK
	r = 0
	while r < JWUnits.R:
		var due: int = _sc_weights[r]
		var grant_r: int = _sc_out[r]
		var k3: int = 0
		while k3 < JWUnits.SERVICE_KIND:
			# rounding: lr, reason=地区额度在服务种类间等分，下标升序决胜（与应拨额同一拆法）
			var share: int = JWMath.floor_div(grant_r, JWUnits.SERVICE_KIND)
			if k3 < grant_r - share * JWUnits.SERVICE_KIND:
				share += 1
			if share > 0:
				# 只归集分项流量（S05 公共服务买方类的预算），不计基本支出：钱在 S05 成交时才流出。
				rc = _st.treasury.record_line_attribution(JWUnits.PayLine.SERVICE_OPEX,
						JWIds.idx_opex(r, k3), share)
				if rc != JWResult.OK:
					return rc
			k3 += 1
		rc = _st.capital.set_funding_ratio(r, grant_r, due)
		if rc != JWResult.OK:
			return rc
		if grant_r < due:
			var g: int = 0
			while g < JWUnits.GROUP:
				if JWIds.region_of_group(g) == r:
					_sc_breach_mask[g] = _sc_breach_mask[g] | BREACH_OPEX
				g += 1
		r += 1
	return JWResult.OK


## 2e 项目款：取清单 → pay_line → 回写实付（**本步不写任何进度字段**，INV-087）。
## 步骤：S04 §4.4
## 前置：projects 已就位
## 后置：state.project.paid_uu 增加；超付的项目转 suspended
## 不变量：INV-087, INV-092
## 失败：转发 pay_line / record_payment 的错误码
##
## 分项归集**只调 record_payment**：JWProjectQueue.record_payment 内部已写
## flow.gov.pay_project_uu[p]，再调 treasury.record_line_attribution 会把同一笔记两次。
func _pay_projects() -> int:
	_sc_pj_project.fill(0)
	_sc_pj_line.fill(0)
	_sc_pj_payee.fill(0)
	_sc_pj_due.fill(0)
	var rows: int = _st.projects.payment_due_into(_sc_pj_project, _sc_pj_line,
			_sc_pj_payee, _sc_pj_due, _st.q)
	if JWResult.has_pending():
		return JWResult.pending_code()
	if rows <= 0:
		return JWResult.OK
	var rc_fin: int = _finance_before_pay(_sc_pj_due)
	if rc_fin != JWResult.OK:
		return rc_fin
	var rc: int = _st.treasury.pay_line(JWUnits.PayLine.PROJECT_CONTRACTS, _sc_pj_payee,
			_sc_pj_due, JWUnits.Kind.PROJECT_PAYMENT, _st.ledger, _st.accounts)
	if rc != JWResult.OK:
		return rc
	var i: int = 0
	while i < rows:
		var paid: int = _st.treasury.last_paid_of(i)
		var rc_p: int = _st.projects.record_payment(_sc_pj_project[i], _sc_pj_line[i],
				paid, _st.treasury)
		if rc_p != JWResult.OK and rc_p < JWResult.Reject.RUN_TERMINATED:
			return rc_p
		i += 1
	return JWResult.OK


## 2f 采购档：只预留额度，实际采购在 S05 §5.6 成交。
## 步骤：S04 §4.2
## 前置：无
## 后置：reserved_memo 增加；不产生任何现金移动（INV-033）
## 不变量：INV-033
## 失败：额度不足 → Reject.BUDGET_INSUFFICIENT（业务性拒绝，不中断本步）
##
## 预留额 = 本季政府采购的年计划四季份额。SimCore 里没有块持有年计划的支出分档
## （docs/12 §2 02.0 的 flow.gov.primary_budget_q_uu 在 JWTreasury 的注册表里不存在），
## 因此这里按**已预留之外的可用现金**给出上限为 0 的预留：不预留即不采购。
## 这不是「先记 0 再想办法」，是把缺口显式留在 open_questions 里，不凭空发明一个采购额度。
func _reserve_procurement() -> int:
	# R-PROCURE-01：年度计划的采购档（每季 = 年额 ÷ 4）按支付优先级在这里先融资（R-FINANCE-01），
	# 再把「可用现金内的额度」核定为本季采购预算；实际付款在 S05 市场的买方类 2 成交时发生。
	var budget: int = _st.treasury.procurement_budget_q_uu
	if budget <= 0:
		return _st.treasury.authorize_procurement(0)
	_sc_proc_due[0] = budget
	var rc: int = _finance_before_pay(_sc_proc_due)
	if rc != JWResult.OK:
		return rc
	var cash: int = _st.accounts.cash_of(JWIds.AGENT_GOV)
	return _st.treasury.authorize_procurement(maxi(0, mini(budget, cash)))


## R-P05-01：培训申请拆分的 scratch（长 GROUP）。
var _edu_w: PackedInt64Array = PackedInt64Array()
var _edu_tb: PackedInt64Array = PackedInt64Array()
var _edu_out: PackedInt64Array = PackedInt64Array()


## R-P05-01：把项目期内的培训政策（effect 落点 == education_cohort）换成逐组申请席位，写入 _sc_group。
## 步骤：S07 §7.6 之前
## 前置：_sc_group 已清零
## 后置：_sc_group[g] += 本季该组申请席位；Σ == 各政策 seats_per_q_units 之和（组权重全 0 的政策除外）
## 不变量：INV-003（拆分精确）、INV-095（未生效零申请）
## 失败：拆分失败 → 其错误码
func _fill_education_requests() -> int:
	if _edu_w.size() != JWUnits.GROUP:
		_edu_w.resize(JWUnits.GROUP)
		_edu_tb.resize(JWUnits.GROUP)
		_edu_out.resize(JWUnits.GROUP)
	var defs: JWPolicyDef = _st.policy_defs
	for p: int in JWUnits.POLICY_N:
		if defs.effect_target_of(p) != JWPolicyDef.TARGET_GROUP_EDUCATION_COHORT:
			continue
		if defs.qty_slot[p] < 0 or not _st.policy.in_program(p, defs, _st.q):
			continue
		var seats: int = _st.policy.params_ppm[JWIds.idx_policy_param(p, defs.qty_slot[p])]
		if seats <= 0:
			continue
		var track: int = 2
		if defs.track_slot[p] >= 0:
			track = _st.policy.params_ppm[JWIds.idx_policy_param(p, defs.track_slot[p])]
		var mask: int = _st.policy.region_mask[p] & JWPolicyEngine.REGION_MASK_ALL
		if mask == 0:
			mask = JWPolicyEngine.REGION_MASK_ALL
		var wsum: int = 0
		for g: int in JWUnits.GROUP:
			_edu_tb[g] = g
			_edu_w[g] = 0
			if JWIds.age_of_group(g) != JWUnits.Age.WORKING:
				continue
			if ((mask >> JWIds.region_of_group(g)) & 1) == 0:
				continue
			var k: int = JWIds.SKILL_OF_GROUP[g]
			var ok: bool = (track == 0 and k == 0) or (track == 1 and k == 1) \
					or (track == 2 and k < JWUnits.K - 1)
			if not ok:
				continue
			_edu_w[g] = maxi(0, _st.pop.population[g])
			wsum += _edu_w[g]
		if wsum <= 0:
			continue
		var rc: int = JWMath.split_lr_into(seats, _edu_w, _edu_tb, _edu_out)
		if rc != JWResult.OK:
			return rc
		for g2: int in JWUnits.GROUP:
			_sc_group[g2] += _edu_out[g2]
	return JWResult.OK


## R-POLSPEND-01：本季各政策的项目期应付额（长 POLICY_N）。
var _prog_amt: PackedInt64Array = PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
## R-P10-01：拨款欠额在地区间拆分的 scratch（长 R）。
var _grant_w: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
var _grant_tb: PackedInt64Array = PackedInt64Array([0, 1, 2, 3])
var _grant_out: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])


## R-SUBSIDY-01：补助配给的 scratch（长 CELL）。
var _sub_want: PackedInt64Array = PackedInt64Array()
var _sub_tb: PackedInt64Array = PackedInt64Array()
var _sub_out: PackedInt64Array = PackedInt64Array()


## 2g 补助：逐个合格 cell 调 pay_subsidy（幂等键 + 已发生的实际投资前置，INV-097）。
##
## R-SUBSIDY-01（policy_P09.json 的 effect_chain 第 1 环与 at == payment 的前置条件）：
##   合格 cell = 作用地区（region_mask）∩ 合格部门（param.p09_eligible_sector_mask）∩ 上季实际投资 > 0
##             ∩ 上季投资 ≥ 期初资本 × min_investment_ratio ∩ 上季（合格投资季）≥ 生效季；
##   应得额 = min(上季投资 × 补助率, cap_per_cell_per_q)；Σ 超过每季封顶（支出线 subsidy_to_firms）时
##   按最大余数法在封顶内配给，不形成欠付、不结转。
## 原实现把 slot 0（P09 的 region_mask == 15）当补助率，实付约为投资的 0.0015%，其余三个旋钮全被忽略。
## 步骤：S04 §4.3
## 前置：_sc_invest_prev 是上季 flow.cell.investment_uu 的快照
## 后置：合格 cell 收到补助；重复申领被拦；实付计入 flow.gov.pay_subsidies 与 primary_paid
## 不变量：INV-096, INV-097, INV-113
## 失败：转发 pay_subsidy 的错误码（Reject 不中断本步）
func _pay_subsidies() -> int:
	var p: int = 0
	while p < JWUnits.POLICY_N:
		if _st.policy_defs.kind[p] != JWPolicyDef.POLICY_KIND_SUBSIDY:
			p += 1
			continue
		if not _st.policy.is_effective(p, _st.q):
			p += 1
			continue
		var defs: JWPolicyDef = _st.policy_defs
		if defs.rate_slot[p] < 0:
			p += 1
			continue
		var rate_ppm: int = _st.policy.effective_param_ppm(p, defs.rate_slot[p], _st.q)
		if rate_ppm <= 0:
			p += 1
			continue
		# 合格投资季（上季）不得早于生效季：政策生效前发生的投资与政策无因果关系（p09.pre.investment_after_effective）。
		if _st.q - 1 < _st.policy.effective_from_q[p]:
			p += 1
			continue
		var cap_cell: int = JWUnits.AMOUNT_MAX
		if defs.cap_slot[p] >= 0:
			cap_cell = _st.policy.params_uu[JWIds.idx_policy_param(p, defs.cap_slot[p])]
		var min_ratio: int = 0
		if defs.min_ratio_slot[p] >= 0:
			min_ratio = _st.policy.params_ppm[JWIds.idx_policy_param(p, defs.min_ratio_slot[p])]
		var rmask: int = _st.policy.region_mask[p] & JWPolicyEngine.REGION_MASK_ALL
		if rmask == 0:
			rmask = JWPolicyEngine.REGION_MASK_ALL
		var smask: int = _st.params[JWUnits.Param.P09_ELIGIBLE_SECTOR_MASK]
		var ceiling: int = defs.spend_line(p, 0)
		if _sub_want.size() != JWUnits.CELL:
			_sub_want.resize(JWUnits.CELL)
			_sub_tb.resize(JWUnits.CELL)
			_sub_out.resize(JWUnits.CELL)
		var want_total: int = 0
		var c0: int = 0
		while c0 < JWUnits.CELL:
			_sub_tb[c0] = c0
			_sub_want[c0] = 0
			var inv0: int = _sc_invest_prev[c0]
			var ok: bool = inv0 > 0 \
					and ((rmask >> JWIds.REGION_OF_CELL[c0]) & 1) == 1 \
					and ((smask >> JWIds.SECTOR_OF_CELL[c0]) & 1) == 1 \
					and inv0 >= JWMath.mul_ppm(_st.capital.cell_capital_value[c0], min_ratio)
			if ok:
				_sub_want[c0] = mini(JWMath.mul_ppm(inv0, rate_ppm), cap_cell)
				want_total += _sub_want[c0]
			c0 += 1
		if ceiling > 0 and want_total > ceiling:
			var rc_s: int = JWMath.split_lr_into(ceiling, _sub_want, _sub_tb, _sub_out)
			if rc_s != JWResult.OK:
				return rc_s
			for c1: int in JWUnits.CELL:
				_sub_want[c1] = mini(_sub_out[c1], _sub_want[c1])
		# R-FINANCE-01 的逐线融资：补助档先融资。采购预算已在第 6 档核定、要到 S05 开市才花，
		# 这里若只按补助额融资，补助会先花掉那笔已核定给采购的现金，S05 的采购被 min(预算, 现金)
		# 截短同样的数额（实测补助每发 0.19 U，政府采购恰好少 0.19 U）。所以融资目标 = 补助 + 待花的采购预算。
		var pay_total: int = JWMath.sum(_sub_want)
		if pay_total > 0:
			_sc_proc_due[0] = pay_total + _st.treasury.f_procure_budget
			var rc_f: int = _finance_before_pay(_sc_proc_due)
			if rc_f != JWResult.OK:
				return rc_f
		var cell: int = 0
		while cell < JWUnits.CELL:
			var invest: int = _sc_invest_prev[cell]
			if invest > 0 and _sub_want[cell] > 0:
				var requested: int = _sub_want[cell]
				if requested > 0:
					var cash_before: int = _st.accounts.cash_of(JWIds.agent_of_cell(cell))
					# qualifying_event_id 取上季季号：claim_key 已含本季 q，用「补的是哪一季的
					# 投资」做事件 ID 才能让同一季的两笔投资各自成键（docs/12 §4.3）。
					var rc: int = _st.policy.pay_subsidy(p, cell, requested, _st.q - 1,
							invest, _st.policy_defs, _st.treasury, _st.ledger,
							_st.accounts, _st.q)
					if rc != JWResult.OK and rc < JWResult.Reject.RUN_TERMINATED:
						return rc
					if rc == JWResult.OK:
						var paid: int = _st.accounts.cash_of(JWIds.agent_of_cell(cell)) \
								- cash_before
						if paid > 0:
							# pay_subsidy 自己 post，流量登记必须由调用方补（INV-027）。
							var rc2: int = _st.treasury.record_line_payment(
									JWUnits.PayLine.SUBSIDIES, cell, paid)
							if rc2 != JWResult.OK:
								return rc2
			cell += 1
		p += 1
	return JWResult.OK


## S05 生产与交易。可写：CELL | GROUP | PUBSERV | REGION | MARKET | GOV | WORLD | PROJECT | RNG
## 步骤：S05（docs/12 §5.1–§5.8）
## 前置：phase == S05；S04 已完成
## 后置：严格按 docs/12 §5.1 的八个次序完成能源、生产、施工、公共服务、撮合、损耗与存量恒等
## 不变量：INV-015, 016, 043..053, 059..064, 087..089, 094, 103, 104
## 失败：use > avail → NEGATIVE_INVENTORY；施工能力为 0 → suspended(congestion)；
##       买方现金不足 → 成交缩减并记未满足需求
func _step_s05() -> int:
	# 第 1 条：快照期初库存，重置本季交付额度。
	_st.inventory.begin_production()
	_st.world.begin_quarter_delivery()
	if JWResult.has_pending():
		return JWResult.pending_code()

	# 第 2 条：能源 cell 先产（自用 ceil 净出；电力不入库存，INV-051/052）。
	var rc: int = _st.sectors.settle_energy(_st.capital, _st.inventory, _st.io,
			_st.labor, _st.params, _st.ledger, _st.accounts, _st.pricing, _st.world)
	if rc != JWResult.OK:
		return rc

	# 第 3 条：其余 12 个 cell 生产（五项约束取 min，INV-043..050）。
	rc = _st.sectors.settle_production(_st.capital, _st.labor, _st.inventory, _st.io)
	if rc != JWResult.OK:
		return rc

	# 第 4 条：施工能力由**实际**服务产量折出（不是由付款折出，INV-088）。
	rc = _st.projects.compute_construction_capacity(_st.sectors.output_actual_array(),
			_st.params)
	if rc != JWResult.OK:
		return rc

	# 第 5 条：项目进度（形参表里没有 paid_uu，INV-087/089）。
	rc = _st.projects.advance_progress(_st.world, _st.ledger, _st.accounts)
	if rc != JWResult.OK:
		return rc

	# 第 6 条：公共服务交付（delivered <= capacity × availability，INV-102/103）。
	rc = _st.inventory.deliver_public_services(_st.capital, _st.pop)
	if rc != JWResult.OK:
		return rc

	# R-HOUSING-01：市场开市前先交租（住房服务按存量提供，不占当季服务产出的可售量）。
	rc = _pay_rents()
	if rc != JWResult.OK:
		return rc

	# 第 7 条：先算全部需求再统一配给，最后成交（INV-059..064）。
	rc = _st.inventory.collect_demand(_st.pop, _st.capital, _st.treasury, _st.world,
			_st.pricing, _st.accounts, _st.params)
	if rc != JWResult.OK:
		return rc
	# R-INVEST-01：企业资本品需求（S03 的投资意愿按内容给定的资本品构成拆到产品）。
	rc = _st.inventory.add_capital_demand(_st.sectors.f_invest_intent,
			_st.io.capital_goods_split_ppm, _st.pricing)
	if rc != JWResult.OK:
		return rc
	rc = _st.inventory.ration(JWInventory.RATION_MODE_PRIORITY, _st.rng)
	if rc != JWResult.OK:
		return rc
	rc = _st.inventory.execute_trades(_st.pop, _st.capital, _st.treasury, _st.world,
			_st.pricing, _st.ledger, _st.accounts)
	if rc != JWResult.OK:
		return rc
	# R-INVEST-01：成交的资本品计入资本存量；新增产能进 pending，下季才可用（INV-091）。
	var cap_cell: int = 0
	while cap_cell < JWUnits.CELL:
		rc = _st.capital.add_purchased_capital(cap_cell, _st.inventory.f_capital_bought[cap_cell], _st.io)
		if rc != JWResult.OK:
			return rc
		cap_cell += 1
	# 采购档的钱是在这里才真的流出去的（买方类 2 的成交），而 JWInventory 不该去写
	# JWTreasury 的流量。不登记的后果不是少一个数字：INV-027 的「基本支出」会系统性少计
	# 这一笔，季末恒等式必然失衡。金额取本季账本里 gov 现金因 GOV_PROCUREMENT 的净流出。
	rc = _st.treasury.record_line_payment(JWUnits.PayLine.PROCUREMENT, 0,
			_ledger_sum(JWUnits.Kind.GOV_PROCUREMENT, JWIds.AGENT_GOV, false))
	if rc != JWResult.OK:
		return rc

	# 第 8 条：排放与损耗（损耗显式登记并计入中间消耗，INV-053）。
	rc = _st.capital.accumulate_emissions(_st.sectors.output_actual_array(), _st.io)
	if rc != JWResult.OK:
		return rc
	rc = _st.inventory.apply_spoilage(_st.io)
	if rc != JWResult.OK:
		return rc

	# 第 9 条：逐 cell 逐品种的存量恒等（INV-047）。
	return _st.inventory.check_stock_identity(_st.sectors.output_actual_array())


## S06 财税结算。可写：GOV | CELL | PUBSERV | GROUP | REGION | WORLD | BOND
## 步骤：S06（docs/12 §6.1–§6.9）
## 前置：phase == S06；S05 已完成
## 后置：折旧、增加值两轨、非市场产出、利润、两税、可分配、居民储蓄、对外经常项目、三口径 GDP 完成
## 不变量：INV-017..021, 027, 028, 035, 101, 106, 107, 110..119
## 失败：任一恒等式不成立 → LEDGER_IMBALANCE 并导出故障包，**不得自动修正**；
##       GDP 覆盖性检验失败 → GDP_CLASS_MISSING / GDP_CLASS_DUPLICATE
func _step_s06() -> int:
	# 第 1 条：折旧（非现金分录，两轨同率，INV-055/056）。
	var rc: int = _st.capital.depreciate(_st.io, _st.ledger, _st.accounts)
	if rc != JWResult.OK:
		return rc

	# §6.2 的销售额入口：JWInventory.execute_trades 的冻结签名里没有 JWSectorModel，
	# 回调不到 record_sale。改由本类从**本季账本行**按卖方主体归集——
	# kind ∈ {3,4,5,8} 只在 _trade_one 里出现，卖方那一腿恒是「现金科目 + 正 delta」，
	# 因此这个口径与逐笔回调逐位相同（见返回值 interface_requests）。
	rc = _collect_sales_from_ledger()
	if rc != JWResult.OK:
		return rc

	# 第 2 条：增加值两轨（**禁止名义除以价格指数**，INV-111/117）。
	rc = _st.sectors.compute_value_added(_st.inventory, _st.io)
	if rc != JWResult.OK:
		return rc

	# 第 3 条：公共非市场产出（按成本计价，INV-101）。
	rc = _st.capital.compute_nonmarket_output(_st.labor.f_pub_wage_bill,
			_st.inventory.f_pub_intermediate)
	if rc != JWResult.OK:
		return rc

	# 第 4 条：利润（营业盈余按残差定义，价差进经营结果）。
	rc = _st.sectors.compute_profit(_st.labor, _st.capital, _st.inventory,
			_sc_taxable, _st.params)
	if rc != JWResult.OK:
		return rc

	# 第 6 条：企业利润税（利润 ≠ 现金，差额进应收，INV-031）。
	if _st.policy.is_effective(JWTreasury.POLICY_PROFIT_TAX, _st.q):
		rc = _st.treasury.collect_profit_tax(_sc_taxable, _st.policy.params_ppm_array(),
				_st.ledger, _st.accounts, _st.params)
		if rc != JWResult.OK:
			return rc
	rc = _record_profit_tax_by_cell()
	if rc != JWResult.OK:
		return rc

	# 第 7 条：可分配利润（已按 payout_ratio 折算，调用方不再乘一次）。
	rc = _st.sectors.compute_distributable(_sc_distributable, _st.params)
	if rc != JWResult.OK:
		return rc
	# R-PAYOUT-02：分配以「下季付得起足额工资」为前提（S04 发薪只能动用期初现金的 wage_cash_share）；
	# 亏损季耗掉的营运现金由其后的利润先补回，而不是被全额分走、一路耗到付不起工资。
	_retain_working_capital()

	# 第 8 条（前半，R-TAXBASE-01）：企业分配与存款利息先过账到户——§6.5 个税的税基是
	# 「已过账的 wage + property」，分配排在个税之后等于本季财产收入永远不进税基。
	rc = _st.pop.post_property_income(_sc_distributable,
			_ledger_sum(JWUnits.Kind.BOND_INTEREST, JWIds.AGENT_INVPOOL, true),
			_st.ledger, _st.accounts)
	if rc != JWResult.OK:
		return rc

	# 第 5 条：个人所得税（税基只来自已过账收入）。
	# INV-095：税种本身是政策（P01/P02），读其参数前必须先过 is_effective 闸门；
	# 被废止或尚未生效的税种一分不征，而不是拿残留在参数槽里的旧税率继续征。
	if _st.policy.is_effective(JWTreasury.POLICY_INCOME_TAX, _st.q):
		rc = _st.treasury.collect_income_tax(_st.pop, _st.policy.params_ppm_array(),
				_st.ledger, _st.accounts, _st.params)
		if rc != JWResult.OK:
			return rc

	# R-FEE-01：公共服务收费（非税收入）。按本季实际交付到各组的公共服务量征收，受群组现金约束。
	rc = _collect_service_fees()
	if rc != JWResult.OK:
		return rc
	# R-DSR-01：全部经常性收入入账后再年化，供下一季偿债率定价。
	rc = _st.treasury.annualize_receipts()
	if rc != JWResult.OK:
		return rc

	# 第 8 条（后半）：可支配收入与储蓄（Δcash + Δdeposit == savings 逐组精确，INV-086/024）。
	rc = _st.pop.settle_savings(_st.ledger, _st.accounts, _st.params)
	if rc != JWResult.OK:
		return rc

	# 第 9 条：对外经常项目（外债经整数形参传入，秩 4 同秩不得互引）。
	var ext_interest: int = _ledger_sum(JWUnits.Kind.BOND_INTEREST, JWIds.AGENT_ROW, true)
	var ext_borrow: int = _ledger_sum(JWUnits.Kind.BOND_ISSUE, JWIds.AGENT_ROW, false) \
			- _ledger_sum(JWUnits.Kind.BOND_PRINCIPAL, JWIds.AGENT_ROW, true)
	rc = _st.world.settle_current_account(ext_interest, ext_borrow,
			_st.bonds.debt_outstanding_of_holder(JWUnits.Holder.ROW), _st.accounts)
	if rc != JWResult.OK:
		return rc

	# 第 10 条：三口径 + 覆盖性检验（INV-112..119）。
	rc = _st.ledger.aggregate_classes(_sc_class_prod, _sc_class_exp, _sc_class_inc)
	if rc != JWResult.OK:
		return rc
	rc = _st.diag.compute_gdp(_st.sectors, _st.capital, _st.inventory, _st.world,
			_st.treasury, _st.ledger)
	if rc != JWResult.OK:
		return rc
	rc = _st.diag.compute_fiscal(_st.bonds, _st.treasury, _st.q)
	if rc != JWResult.OK:
		return rc

	# 第 11 条：本季唯一的终检点（INV-017..021, 027, 028, 035, 115）。
	rc = _st.treasury.check_fiscal_identities(_st.bonds, _st.accounts)
	if rc != JWResult.OK:
		return rc
	rc = _st.accounts.check_cash_closure(_st.total_cash_uu, _st.total_cash_uu)
	if rc != JWResult.OK:
		return rc
	rc = _st.accounts.check_receivable_payable()
	if rc != JWResult.OK:
		return rc
	return _st.accounts.check_balance_sheet()


## S07 跨期变化。可写：PRICE | CELL | PUBSERV | REGION | GROUP | PROJECT | GOV | POLITICS | RNG
## 步骤：S07（docs/12 §7.1–§7.9）
## 前置：phase == S07；S06 已完成
## 后置：投产只写 *_pending_*；价格与工资只写 pending；人口守恒成立
## 不变量：INV-054, 055, 056, 065..073, 081..084, 091, 102, 149
## 失败：人口守恒不成立 → POPULATION_NOT_CONSERVED；迁移不配对 → MIGRATION_UNPAIRED；
##       住房容量被突破 → HOUSING_OVERFLOW
func _step_s07() -> int:
	# 第 1 条：完工投运（只写 *_pending_*，INV-090/091）。
	var rc: int = _st.commissioning.commission_ready(_st.projects, _st.capital, _st.treasury,
			_st.labor, _st.ledger, _st.accounts, _st.q)
	if rc != JWResult.OK:
		return rc

	# 第 2 条：政策效应（落点白名单；未生效返回零效应，INV-095）。
	rc = _st.policy.apply_effects(_st.policy_defs, _st.capital, _st.treasury,
			_st.politics, _st.pop, _st.q, _st.params, _st.diag)
	if rc != JWResult.OK:
		return rc

	# 第 2′ 条（R-P11-02 / R-P12-02）：已投运行政类效果的断供与退出衰减（读本季 S04 的到位率）。
	rc = _st.policy.upkeep_effects(_st.policy_defs, _st.capital, _st.treasury, _st.politics, _st.q, _st.params)
	if rc != JWResult.OK:
		return rc

	# 第 3 条：维护欠账与可用率（欠拨只降可用率，INV-102）。
	rc = _st.capital.update_maintenance_and_availability(_st.params)
	if rc != JWResult.OK:
		return rc

	# 第 4 条：价格 / 工资 / 租金（**只写 pending**，INV-065..070）。
	rc = _st.pricing.update_prices(_st.inventory.m_supply, _st.inventory.m_demand,
			_st.inventory.inv_output, _st.inventory.m_inv_target, _st.io.storable, _st.params)
	if rc != JWResult.OK:
		return rc
	rc = _st.pricing.update_wages(_st.labor.vacancies_persons(),
			_st.labor.unemployed_persons(), _labor_force_total(), _st.params)
	if rc != JWResult.OK:
		return rc
	# 住房租金是**地区**口径（JWPricing 的两个形参都长 R），而 state.group.housing_units_occupied
	# 是 36 个组的列；这里先按地区汇总再传入。
	var rr: int = 0
	while rr < JWUnits.R:
		_sc_region[rr] = 0
		rr += 1
	var gg: int = 0
	while gg < JWUnits.GROUP:
		var reg: int = JWIds.region_of_group(gg)
		_sc_region[reg] += _st.pop.housing_occupied[gg]
		gg += 1
	rc = _st.pricing.update_housing_rent(_sc_region, _st.capital.housing_capacity, _st.params)
	if rc != JWResult.OK:
		return rc

	# 第 5 条：人口（死亡是唯一净流出，出生是唯一净流入，INV-071/072/074）。
	rc = _st.pop.update_demography(_st.rng, _st.params)
	if rc != JWResult.OK:
		return rc

	# 第 6 条：迁移（三道硬闸；被挡回显式登记，INV-073/083/084）。
	rc = _st.migration.run(_st.pop, _st.labor, _st.capital, _st.pricing, _st.ledger,
			_st.accounts, _st.rng, _st.params)
	if rc != JWResult.OK:
		return rc
	# §7.7 的 outflow = 死亡 + 成年出 + **迁出**，而迁出量在 JWMigration 手里：
	# 缺这一步 check_conservation 会以 Fault.MIGRATION_UNPAIRED 报出来。
	rc = _st.pop.record_migration_out(_st.migration.out_by_group())
	if rc != JWResult.OK:
		return rc

	# 第 7 条：教育（无教师即无席位；拨款当季无 skill_in，INV-081/082）。
	# R-P05-01：申请席位 = 项目期内每季 seats_per_q_units，按作用地区内劳动年龄组的人口拆分，
	# 技能档由 track 决定（0 只收低技能、1 只收中技能、2 两档兼顾；最高档没有升档去向）。
	# 原先申请量恒为 0、另一条直接入队的路径又因效果量为 0 从不触发：P05 从未培训过一个人。
	_sc_group.fill(0)
	rc = _fill_education_requests()
	if rc != JWResult.OK:
		return rc
	rc = _st.pop.update_education(_st.capital.pub_teachers, _sc_group, _st.q, _st.params)
	if rc != JWResult.OK:
		return rc
	# §7.6 的席位截断按契约要写 log.clamp，而 JWPopulation 的签名里拿不到 JWPricing：
	# 由本类按它暴露的计数器代写（INV-069 要求每个夹逼调用点都计数并写日志）。
	var clamped: int = _st.pop.edu_seats_clamped()
	if clamped > 0:
		_st.pricing.log_clamp(CAUSE_RUNNER, clamped, 0, 0)

	# 第 8 条：人口流出的就业配对（S07 对 employment 的写只在这一条链上，INV-080）。
	_st.pop.outflow_persons_into(_sc_group)
	if JWResult.has_pending():
		return JWResult.pending_code()
	rc = _st.labor.release_for_outflow(_sc_group, _st.pop, _sc_group_slot)
	if rc != JWResult.OK:
		return rc
	rc = _st.pop.apply_employment_cut(_sc_group_slot)
	if rc != JWResult.OK:
		return rc

	# 第 9 条：人口守恒（INV-071/072/073）。
	rc = _st.pop.check_conservation(_st.migration.in_by_group(), _st.migration.out_by_group())
	if rc != JWResult.OK:
		return rc

	# 第 10 条：生活与服务指数（相对基准，不冒充国际排名，INV-149）。
	rc = _build_delivered_to_group()
	if rc != JWResult.OK:
		return rc
	rc = _st.pop.update_living_indices(_sc_group_svc)
	if rc != JWResult.OK:
		return rc

	# 第 11 条：排放与环境（排放不反馈到生产约束，INV-057）。
	var r: int = 0
	while r < JWUnits.R:
		_sc_region[r] = _st.pop.region_population(r)
		r += 1
	return _st.capital.update_environment(_sc_region, _st.params)


## S08 社会与报告。可写：GROUP（四个主观量）| POLITICS | META | PRICE（swap）| TIME | RNG
## 步骤：S08（docs/12 §8.1–§8.7）
## 前置：phase == S08；S07 已完成
## 后置：主观量、支持度、集团、事件、任期审查、报告完成；价格 swap 与 q += 1 各自唯一时点
## 不变量：INV-011, 012, 014, 121..130, 140
## 失败：事件引用不存在的字段 → METRIC_UNKNOWN；support_ppm 变动无来源 → SUPPORT_UNEXPLAINED
func _step_s08() -> int:
	# 第 1 条：汇总本季失信计数（闭集合，逐季计数）。
	var rc: int = _collect_breach_counts(_sc_breach)
	if rc != JWResult.OK:
		return rc

	# 第 2 条：三个主观量分开更新（trust 的更新式里没有 transfer_income 通道，INV-121/122）。
	rc = _st.politics.update_subjective(_st.pop, _st.pricing, _sc_breach, _st.params)
	if rc != JWResult.OK:
		return rc
	# R-SUPPORT-02：第 0 季结算后的三项指数即支持度变动的基准（模型口径）。
	if _st.q == 0:
		_st.politics.anchor_base_to_current()

	# 第 3 条：支持度（逐组保留，全国值只由加权得出，INV-123/124/125）。
	rc = _st.politics.update_support(_st.pop, _st.params)
	if rc != JWResult.OK:
		return rc

	# 第 4 条：集团（与 support 互不引用，INV-125/129）。
	rc = _st.blocs.update_blocs(_st.sectors, _st.labor, _st.capital, _st.pop,
			_newly_effective_mask(), _st.policy_defs, _st.params)
	if rc != JWResult.OK:
		return rc

	# 第 5 条：事件（用 rng.event；rng.shock 取值不受影响，INV-009/130）。
	rc = _events.fire_events(_st, _st.q)
	if rc != JWResult.OK:
		return rc

	# 第 6 条：任期审查与终局（选举只在 q ∈ {15, 31}；终局式中无任何 GDP 项）。
	rc = _st.politics.review_and_terminate(_st.treasury, _st.pop, _st.q, _st.horizon_q,
			_default_streak_q(), _st.params)
	if rc != JWResult.OK:
		return rc

	# 第 7 条：诊断分栏（projected 禁止回写状态，INV-140）。
	rc = _st.diag.compute_income_quantiles(_st.pop)
	if rc != JWResult.OK:
		return rc

	# 第 8 条：价格与工资切换的**唯一时点**（INV-065/070）。
	rc = _st.pricing.swap_pending()
	if rc != JWResult.OK:
		return rc

	# 第 9 条：state.time.q 的**唯一写入点**（INV-012）。
	rc = _st.advance_quarter_index()
	if rc != JWResult.OK:
		return rc

	# 第 10 条：派生一致性快照（逐个传域类，不传 _st，INV-014）。
	# 传 `_st.q - 1` 而不是 docs/17 §5.8 写的 `_st.q`：第 9 条刚把 q 加过 1，而本函数内部要
	# **重算** compute_fiscal 并与 §6.4 在本季写下的值逐项比对；compute_fiscal 依赖 q
	# （debt_service_next4q(q)）。传加过 1 的 q 会让重算值与已写值必然不等，
	# 报出一个与病因无关的 LEDGER_IMBALANCE。这里传的正是「刚结算完的那一季」。
	return _st.diag.snapshot_and_verify(_st.sectors, _st.capital, _st.inventory, _st.world,
			_st.treasury, _st.ledger, _st.bonds, _st.pop, _st.q - 1)


## 汇总本季失信计数（转移欠付、运行费欠拨、项目取消、债券违约四类闭集合事件）。
## 步骤：S08 §8.1 第 1 条
## 前置：S07 已完成；out 长度 == GROUP
## 后置：out 写满本季逐组失信计数，供 update_subjective 使用
## 不变量：INV-121（失信是闭集合，逐季计数）
## 失败：长度不符 → Fault.INDEX_OUT_OF_RANGE
func _collect_breach_counts(out: PackedInt64Array) -> int:
	if out.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				out.size(), JWUnits.GROUP)
	var g: int = 0
	while g < JWUnits.GROUP:
		var mask: int = _sc_breach_mask[g]
		# 项目取消：本季该组所在地区有项目被取消（S02 记下的地区位掩码）。
		if ((_cancel_region_mask >> JWIds.region_of_group(g)) & 1) == 1:
			mask = mask | BREACH_PROJECT_CANCEL
		# 债券违约：全国一致。
		if _bond_default_flag == 1:
			mask = mask | BREACH_BOND_DEFAULT
		var n: int = 0
		if (mask & BREACH_TRANSFER) != 0:
			n += 1
		if (mask & BREACH_OPEX) != 0:
			n += 1
		if (mask & BREACH_PROJECT_CANCEL) != 0:
			n += 1
		if (mask & BREACH_BOND_DEFAULT) != 0:
			n += 1
		out[g] = n
		g += 1
	return JWResult.OK


## 版本校验：比对 build_id / content_hash / param_set_version。
## 步骤：S01 §01.2
## 前置：LOAD 已完成
## 后置：不改状态
## 不变量：INV-134（content_hash 不符 ⇒ 只读检视、**拒绝推进**）
## 失败：content_hash 不符 → 拒绝推进；build_id 不符 → replay_unreliable 但可继续
##
## 本函数只能校验**状态里自带**的三项：schema_version 与代码常量是否同版、参数数组是否齐备、
## 参数包版本是否为负。`content_hash` 的「符不符」需要一个外部基准（内容目录的重算值），
## 而冻结的 _init(st, events) 签名里没有 JWContentLoader —— 这道闸在 JWSaves.load 与
## JWGame.read_only_mode 上（load 判不符即置只读，JWGame.advance_quarter 据此拒绝推进）。
func _verify_versions() -> int:
	if _st.schema_version != JWSimState.SCHEMA_VERSION:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION,
				_st.schema_version, JWSimState.SCHEMA_VERSION)
	if _st.params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				_st.params.size(), JWUnits.PARAM_N)
	if _st.param_set_version < 0:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, _st.param_set_version, 0)
	return JWResult.OK


## WriteGuard：进入前对**不属于该步可写子集**的子系统取哈希，退出时比对。
## 步骤：每步进入
## 前置：`JWUnits.WRITABLE_SUBSYS[step]` 已定义
## 后置：不改状态；调试构建全开，发布构建按 params[WRITE_GUARD_SAMPLE_Q] 抽季开启
## 不变量：INV-013（越界写入即 WRITE_OUT_OF_SCOPE）；分级策略写进参数卡并在存档留痕（OQ-231）
## 失败：本函数只取样，不判失败
func _guard_begin(step: int) -> void:
	# 抽样判定在进入时做一次并记住：S08 会把 q 加 1，若出口重新判定，
	# 就会拿着没有更新过的基线去比对，把「没有写入」误报成越权写入。
	_guard_on = _guard_active()
	if not _guard_on:
		return
	var mask: int = JWUnits.WRITABLE_SUBSYS[step]
	var s: int = 0
	while s < JWUnits.SUBSYS_N:
		if ((mask >> s) & 1) == 0:
			_guard_hash[s] = _st.subsystem_hash(s)
		else:
			_guard_hash[s] = ""
		s += 1
	# 诊断模式（JWResult.trace_faults，默认关闭）：逐条目留底，越权时能报出具体字段。
	if JWResult.trace_faults:
		_guard_dbg.clear()
		for e: int in _st.registry_size():
			_guard_dbg.append(_st.registry_array_copy(e))


## 本步 WriteGuard 是否启用（_guard_begin 判定一次，_guard_end 沿用，不随步内的 q 变化）。
var _guard_on: bool = false

## 诊断模式下的逐条目快照（只在 trace_faults 打开时写，不进状态、不进哈希）。
var _guard_dbg: Array = []


## WriteGuard：退出时比对进入前的哈希。
## 步骤：每步退出
## 前置：_guard_begin(step) 已执行
## 后置：不改状态
## 不变量：INV-013
## 失败：哈希不等 → Fault.WRITE_OUT_OF_SCOPE，detail_a = 步，detail_b = 子系统
func _guard_end(step: int) -> int:
	if not _guard_on:
		return JWResult.OK
	var mask: int = JWUnits.WRITABLE_SUBSYS[step]
	var s: int = 0
	while s < JWUnits.SUBSYS_N:
		if ((mask >> s) & 1) == 0:
			if _st.subsystem_hash(s) != _guard_hash[s]:
				if JWResult.trace_faults and _guard_dbg.size() == _st.registry_size():
					for e: int in _st.registry_size():
						if _st.registry_subsys(e) == s and _st.registry_array_copy(e) != _guard_dbg[e]:
							print("[guard] 步骤 %d 越权改写：%s" % [step, _st.registry_id(e)])
				return JWResult.raise_fault(JWResult.Fault.WRITE_OUT_OF_SCOPE, step, s)
		s += 1
	return JWResult.OK


## 本季是否开启 WriteGuard（docs/12 §9 的分级策略，OQ-231）。
## 步骤：每步进入／退出
## 前置：无
## 后置：不改状态
## 不变量：INV-013；分级本身写进参数卡并在存档留痕
## 失败：无
func _guard_active() -> bool:
	if _st.params.size() != JWUnits.PARAM_N:
		return true
	var period: int = _st.params[JWUnits.Param.WRITE_GUARD_SAMPLE_Q]
	if period <= 1:
		# 0 == 参数未填（内容包尚未提供该卡），1 == 逐季全开。两者都取「全开」：
		# 少查一季的代价是一条越权写入被放过，比多查一季的代价大得多。
		return true
	return _st.q - JWMath.floor_div(_st.q, period) * period == 0


## 步末不变量批量检查（清单见 docs/12 §10 的时点表）。
## 步骤：每步末（step == 0 表示「季末全量」）
## 前置：该步已完成
## 后置：不改状态
## 不变量：按步查表
## 失败：返回第一个失败的 Fault 码
func _check_invariants(step: int) -> int:
	# 任何一步里由被调方登记过的故障都在这里被拦下：raise_fault 只记第一现场，
	# 而被调方可能因为「业务性短缺」返回了 OK（docs/12 §0.6 的三种语义要靠这一道分开）。
	if JWResult.has_pending():
		return JWResult.pending_code()
	match step:
		JWUnits.Phase.S01:
			# 流量全 0 已由 reset_all_flows 自检；这里补 INV-011 的日志行数对账。
			if _st.ledger.log_row_count() > _st.ledger.log_capacity():
				return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
						_st.ledger.log_row_count(), _st.ledger.log_capacity())
			return JWResult.OK
		JWUnits.Phase.S02:
			# INV-028 / INV-035 / INV-030：财政恒等式与欠付口径。
			return _st.treasury.check_fiscal_identities(_st.bonds, _st.accounts)
		JWUnits.Phase.S03:
			# INV-077：两侧就业口径逐（地区, 技能）相等。
			return _st.labor.check_employment_views(_st.pop)
		JWUnits.Phase.S04:
			# INV-017/018：现金闭合；INV-019：应收 == 应付。
			var rc: int = _st.accounts.check_cash_closure(_st.total_cash_uu, _st.total_cash_uu)
			if rc != JWResult.OK:
				return rc
			return _st.accounts.check_receivable_payable()
		JWUnits.Phase.S05:
			# INV-047：逐 cell 逐品种的存量恒等（S05 第 9 条已查一次，这里是步末的定点）。
			return _st.inventory.check_stock_identity(_st.sectors.output_actual_array())
		JWUnits.Phase.S06:
			# §6.9 的终检点已在 _step_s06 第 11 条逐条执行；步末补一次资产负债表。
			return _st.accounts.check_balance_sheet()
		JWUnits.Phase.S07:
			var rc2: int = _st.pop.check_conservation(_st.migration.in_by_group(),
					_st.migration.out_by_group())
			if rc2 != JWResult.OK:
				return rc2
			# 不在这里做产能轨／价值轨的全存量一致性检查（OQ-206）：
			# 折旧对两轨各自 floor，第一季起就合法地漂移；投运增量取自项目规格的 capacity_effect，
			# 本来就不由「价值 × 系数」派生。V-CELL-03 只在载入期由 JWContentLoader 执行，
			# 运行期漂移由 JWCapital.capacity_value_drift_ppm 诊断，超阈值只报警不改数。
			return JWResult.OK
		JWUnits.Phase.S08:
			# INV-121..130 由各自的 update_* 在内部自检；这里只确认没有挂起故障（已在开头查）。
			return JWResult.OK
		STEP_QUARTER_END:
			return _st.check_all_p0()
	return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, step, JWUnits.Phase.S08)


## 记录该步的子系统哈希（只哈希**该步允许写的子集**，不是全状态）。
## 步骤：每步末
## 前置：无
## 后置：_step_hash[step-1] 写入
## 不变量：INV-014；docs/11 §6.5 的重放二分定位依赖它
## 失败：无
func _record_step_hash(step: int) -> void:
	if step < JWUnits.Phase.S01 or step > JWUnits.Phase.S08:
		return
	var mask: int = JWUnits.WRITABLE_SUBSYS[step]
	_hash_buf.resize(0)
	var s: int = 0
	while s < JWUnits.SUBSYS_N:
		if ((mask >> s) & 1) == 1:
			_hash_buf.append_array(_st.subsystem_hash(s).to_utf8_buffer())
		s += 1
	if _hash_buf.is_empty():
		# 空可写集合（不会发生：八步的掩码都非空）。空缓冲喂给 HashingContext 是引擎错误，
		# 写一个可识别的常量占位，不让它变成一条引擎级 ERROR 日志。
		_hash_buf.append(step)
	_step_hash[step - 1] = JWSimState.sha256_hex(_hash_buf)


## 故障处置：导出故障包并中止。
## 步骤：任意步
## 前置：JWResult.has_pending()
## 后置：写 user://faults/q<NNN>_<code>/ 下的 state_after.json、ledger_q.csv、
##       physical_q.csv、step_hashes.json、fault.json
## 不变量：docs/12 §9「不修改状态、不尝试修复」
## 失败：写盘失败也不修改状态，只追加一条控制台错误
##
## `state_before.json` 不在导出清单里：它需要每季一份完整状态副本，而 docs/12 §14 把
## 「每季 duplicate 整份状态」列为**被结构性排除的风险**。故障包改记 `state_hash_prev`
## （S01 §01.1 记下的上季末哈希），由重放从存档复原上季末状态——见 open_questions。
func _enter_fault(step: int, code: int) -> int:
	var dir: String = FAULT_DIR + "q" + _pad_q(_st.q) + "_" + str(code) + "/"
	last_fault_dir = dir
	if DirAccess.make_dir_recursive_absolute(dir) == OK:
		_write_text(dir + "state_after.json", JSON.stringify(_st.to_dict(), "\t", true))
		_write_text(dir + "step_hashes.json", JSON.stringify(_step_hashes_dict(), "\t", true))
		_write_text(dir + "ledger_q.csv", _ledger_csv())
		_write_text(dir + "physical_q.csv", _physical_csv())
		_write_text(dir + "fault.json", JSON.stringify(_fault_dict(step, code), "\t", true))
	else:
		push_error("JWTurnRunner: 故障包目录写不出来：" + dir)
	# **不回滚、不修正**：状态保留现场，相位停在故障步（docs/12 §9）。
	return code


## 本季 8 个步骤哈希（供 checkpoints.jsonl 与重放二分）。
## 步骤：季末
## 前置：本季已完成
## 后置：不改状态
## 不变量：INV-014
## 失败：无
func step_hashes() -> PackedStringArray:
	return _step_hash


# ── 内部工具（全部只读或只写本类的 scratch） ───────────────────────────────

## R-HOUSING-01：居民按占用住房交租（docs/18 第三轮后补）。
## 步骤：S05（市场开市之前）
## 前置：pop.housing_occupied 与 pricing.housing_rent 已就位
## 后置：每组付 min(占用套数 × 本地区租金, 现金)，付给本地区服务部门 cell（计划书 §06：服务含住房），
##       kind = HOUSEHOLD_CONSUMPTION（计入 C）；实付额经 record_housing_cost 登记为住房支出
## 不变量：INV-086（储蓄 = 可支配收入 − 市场消费 − 住房支出；住房不经 record_consumption，避免双计）、
##          INV-062（付款额 == floor(量×价)：数量按当季服务价折算）
## 失败：透传 ledger.post 的故障；付不起的部分不透支、不记债（住房负担的后果由负担率与迁移体现）
##
## 原状：record_housing_cost 在全项目从未被调用——租金价格与住房占用都在，却没有人交租，
## 基年约 2.8 U/季的住房服务消费凭空消失。
func _pay_rents() -> int:
	var services_price: int = _st.pricing.price_of(JWUnits.Sector.SERVICES)
	var g: int = 0
	while g < JWUnits.GROUP:
		var units: int = _st.pop.housing_occupied[g]
		if units > 0:
			var r: int = JWIds.region_of_group(g)
			var due: int = JWMath.mul(units, _st.pricing.housing_rent[r])
			var agent: int = JWIds.agent_of_group(g)
			var paid: int = mini(due, _st.accounts.cash_of(agent))
			# 住房服务由服务部门的当季产出提供（io_table：服务含住房），交租即从本地区服务 cell 取货；
			# 可售量不足时按可售量折算的金额封顶——不能为没有生产出来的住房服务付款。
			var svc_cell: int = JWIds.idx_cell(r, JWUnits.Sector.SERVICES)
			if services_price > 0:
				var cap_uu: int = JWMath.mul_div_floor(_st.inventory.avail_for_direct_sale(svc_cell),
						services_price, JWUnits.Q_SCALE)
				if paid > cap_uu:
					paid = cap_uu
			if paid > 0:
				var qty: int = 0
				if services_price > 0:
					# rounding: floor, reason=M1，折算数量只取整一次
					qty = JWMath.mul_div_floor(paid, JWUnits.Q_SCALE, services_price)
				var seller: int = JWIds.agent_of_cell(svc_cell)
				var rc: int = _st.ledger.post(JWUnits.Kind.HOUSEHOLD_CONSUMPTION,
						JWIds.idx_account(agent, JWIds.ACC_CASH),
						JWIds.idx_account(seller, JWIds.ACC_CASH),
						paid, qty, JWUnits.Sector.SERVICES, 0, g)
				if rc != JWResult.OK:
					return rc
				rc = _st.inventory.sell_direct(svc_cell, qty)
				if rc != JWResult.OK:
					return rc
				_st.pop.record_housing_cost(g, paid)
		g += 1
	if JWResult.has_pending():
		return JWResult.pending_code()
	return JWResult.OK


## R-FINANCE-01：预算内支出的常设融资授权（docs/18）。
## 步骤：S04 §4.2（每条支付线付款之前）
## 前置：due 是本支付线本季的逐项应付额
## 后置：若国库现金不足以付清本线，按 JWTreasury.issue_debt 的既有规则（居民投资池 + 外部额度，
##       各有上限）融资补足；融不到的部分交给 pay_line 照常记欠付——短缺仍然显露，只是出现在融资失败之后
## 不变量：INV-010（按实际批次数推进 entity_seq）、INV-035（债务余额 == Σ ACTIVE 批次）
## 失败：透传 issue_debt 的故障码；业务性拒绝（额度用尽等）不是故障，交由 pay_line 记欠付
##
## 计划书 §07 原文是「**无法融资时**进入支出排序、延期与重组选择」——先融资、后显露。
## 原结算合同只在付不出本息时才发债（§2.6），使基年预算本身不自洽：开局国库 2 U，
## 每季约 5.5 U 的支出在 S04 付出、税收要到 S06 才到账，政府天然需要借钱周转。
func _finance_before_pay(due: PackedInt64Array) -> int:
	var total_due: int = JWMath.sum(due)
	if total_due <= 0:
		return JWResult.OK
	var cash: int = _st.accounts.cash_of(JWIds.AGENT_GOV)
	var gap: int = total_due - cash
	if gap <= 0:
		return JWResult.OK
	var before_n: int = _st.bonds.count
	var rc: int = _st.treasury.issue_debt_up_to(gap, _st.bonds, _st.world, _st.ledger, _st.accounts,
			_st.q, _st.entity_seq + 1, _st.params)
	_st.entity_seq += _st.bonds.count - before_n
	if rc != JWResult.OK and rc < JWResult.Reject.RUN_TERMINATED:
		return rc
	return JWResult.OK


## 从本季账本行按卖方归集销售额与销售量，回写 JWSectorModel。
## 步骤：S06 §6.2 之前
## 前置：S05 的成交已全部过账
## 后置：sectors._sales_rev / _sold_qty 写满
## 不变量：INV-112（只是增加值公式的一个输入项，不是 GDP 本身）
## 失败：无
func _collect_sales_from_ledger() -> int:
	var n: int = _st.ledger.log_row_count()
	var i: int = 0
	while i < n:
		var kind: int = _st.ledger.l_kind[i]
		if kind == JWUnits.Kind.HOUSEHOLD_CONSUMPTION or kind == JWUnits.Kind.GOV_PROCUREMENT \
				or kind == JWUnits.Kind.INTERMEDIATE_PURCHASE or kind == JWUnits.Kind.EXPORT \
				or kind == JWUnits.Kind.CAPITAL_PURCHASE:
			var delta: int = _st.ledger.l_delta[i]
			if delta > 0:
				var account: int = _st.ledger.l_account[i]
				var agent: int = JWMath.floor_div(account, ACC_STRIDE)
				if account - agent * ACC_STRIDE == JWIds.ACC_CASH:
					var cell: int = JWIds.cell_of_agent(agent)
					if cell >= 0 and cell < JWUnits.CELL:
						_st.sectors.record_sale(cell, delta, _st.ledger.l_qty[i])
		elif kind == JWUnits.Kind.PROJECT_PAYMENT or kind == JWUnits.Kind.POLICY_TOGGLE_COST:
			# 只看收款方现金腿（正腿）。项目付款是四腿分录（R-PROJECT-01 ①）：另一条正腿是政府
			# 在建工程，不是现金科目，不会被误当成销售；收款方净值腿为负，同样不进来。
			var delta2: int = _st.ledger.l_delta[i]
			if delta2 > 0:
				var account2: int = _st.ledger.l_account[i]
				var agent2: int = JWMath.floor_div(account2, ACC_STRIDE)
				if account2 - agent2 * ACC_STRIDE == JWIds.ACC_CASH:
					if agent2 == JWIds.AGENT_ROW:
						if kind == JWUnits.Kind.PROJECT_PAYMENT:
							# R-PROJECT-01 ③：设备线付给外部即进口（M）——docs/12 §4.4「同时增
							# flow.world.imports_uu」。只登记金额（数量 0，不占交付额度）：实物到货量由
							# S05 advance_progress 按实际到货另行登记（金额 0），两腿互不重复。
							# 支出法 I 与 M 同增同额，GDP 净影响为零。
							var rc_m: int = _st.world.record_import(JWUnits.Sector.MANU, 0, delta2)
							if rc_m != JWResult.OK:
								return rc_m
					else:
						var cell2: int = JWIds.cell_of_agent(agent2)
						if cell2 >= 0 and cell2 < JWUnits.CELL:
							# R-PROJECT-01 ②：国内承包方（材料 → 制造 cell，施工 → 服务 cell）的收款计为销售；
							# R-PUBSERV-01：开关成本的收款（中州服务 cell）同样是销售。数量 0：
							# 这两类是按合同额结算的服务，不从成品库存出货。
							_st.sectors.record_sale(cell2, delta2, 0)
							if kind == JWUnits.Kind.POLICY_TOGGLE_COST:
								# R-PUBSERV-01：开关成本是政府为公共服务购买的中间投入，计入卖方所在地区
								# pubserv 的中间消耗，从而进入以成本计的 G（compute_nonmarket_output 在本函数
								# 之后读它）。生产法：卖方增加值 +V；支出法：G +V；pubserv 自身增加值不变。
								var r2: int = JWIds.region_of_cell(cell2)
								_st.inventory.f_pub_intermediate[r2] = JWMath.check_amount(
										_st.inventory.f_pub_intermediate[r2] + delta2)
		i += 1
	if JWResult.has_pending():
		return JWResult.pending_code()
	return JWResult.OK


## 本季某 kind 在某主体现金科目上的过账合计。
## 步骤：S06 §6.7/§6.8
## 前置：本季分录已写入
## 后置：不改状态
## 不变量：INV-024（利息分配链）、INV-026（对外必有 agent.row 对手方）
## 失败：无
##
## `inflow == true` 取正腿（该主体收到的钱），否则取负腿的绝对值（该主体付出的钱）。
func _ledger_sum(kind: int, agent: int, inflow: bool) -> int:
	var want: int = JWIds.idx_account(agent, JWIds.ACC_CASH)
	var acc: int = 0
	var n: int = _st.ledger.log_row_count()
	var i: int = 0
	while i < n:
		if _st.ledger.l_kind[i] == kind and _st.ledger.l_account[i] == want:
			var d: int = _st.ledger.l_delta[i]
			if inflow and d > 0:
				acc += d
			elif not inflow and d < 0:
				acc -= d
		i += 1
	return acc


## 把本季逐 cell 的实缴利润税转交给 flow.cell.tax_profit_paid_uu。
## 步骤：S06 §6.6
## 前置：collect_profit_tax 已完成
## 后置：sectors.f_tax_profit_paid 逐位等于 treasury 的实缴额，
##       Σ == flow.gov.receipts_profit_tax_uu 的本季增量
## 不变量：INV-031（利润 ≠ 现金；差额在 tax_receivable，不在本数组）
## 失败：合计对不上 → Fault.LEDGER_IMBALANCE
##
## 该数组归 cell 侧所有，JWTreasury（秩 5）拿不到 JWSectorModel（秩 7）的引用（§3.2），
## 故由本类逐项转交。**不做任何摊分**：实缴额是逐 cell 按各自现金上限截过的，
## 按应税额事后摊回既不精确，又会在 split_lr_into 的入口守卫处溢出（实测 1.37e19 > int64）。
func _record_profit_tax_by_cell() -> int:
	var cell: int = 0
	while cell < JWUnits.CELL:
		var paid: int = _st.treasury.profit_tax_paid_of(cell)
		if paid < 0:
			return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, cell, paid)
		_st.sectors.f_tax_profit_paid[cell] = paid
		cell += 1
	return JWResult.OK


## 全国劳动力人数（update_wages 的分母）。
## 步骤：S07 §7.3
## 前置：无
## 后置：不改状态
## 不变量：INV-075
## 失败：无
func _labor_force_total() -> int:
	var acc: int = 0
	var g: int = 0
	while g < JWUnits.GROUP:
		acc += _st.pop.labor_force(g)
		g += 1
	return acc


## R-PAYOUT-02：可分配额按营运现金封顶。目标 = 下季足额发薪所需的现金 = 本季工资现金流出 ÷
## param.wage_cash_share_ppm（S04 发薪只能动用期初现金的这一比例）；可分配额 = min(原额, max(0, 现金 − 目标))。
## 投入品在 S05 与销售同季循环（企业投入类在居民、公服、政采之后成交），不进目标。
## 步骤：S06 §6.7（compute_distributable 之后、post_property_income 之前）
## 前置：本季全部成交已过账
## 后置：_sc_distributable 逐 cell 不增；sectors.f_distributed 同步
## 不变量：INV-086（分配额即财产收入）
## 失败：无
func _retain_working_capital() -> void:
	var share: int = maxi(1, _st.params[JWUnits.Param.WAGE_CASH_SHARE_PPM])
	var c: int = 0
	while c < JWUnits.CELL:
		var d: int = _sc_distributable[c]
		if d > 0:
			var agent: int = JWIds.agent_of_cell(c)
			# rounding: floor, reason=目标只取整一次
			var target: int = JWMath.mul_div_floor(
					_ledger_sum(JWUnits.Kind.WAGE_PAYMENT, agent, false), JWUnits.PPM, share)
			var room: int = maxi(0, _st.accounts.cash_of(agent) - target)
			if d > room:
				_sc_distributable[c] = room
				_st.sectors.f_distributed[c] = room
		c += 1


## R-FEE-01：公共服务收费。每组 fee = floor(Σ_k 本季交付量 × 基价 × fee_ppm / 1e6 / Q_SCALE)，
## 以群组现金为上限（付不出的部分豁免，不挂应收）；群组现金 → 政府现金，kind PUBLIC_FEE（三口径全 none）。
## 步骤：S06（个税之后、储蓄之前）
## 前置：S05 §5.7 交付已完成
## 后置：f_receipts_other 与各组 f_fees_paid 同额增加
## 不变量：INV-027、INV-086
## 失败：转发过账与登记的故障码
func _collect_service_fees() -> int:
	var fee_ppm: int = _st.params[JWUnits.Param.PUBSERV_FEE_PPM]
	if fee_ppm <= 0:
		return JWResult.OK
	var rc: int = _build_delivered_to_group()
	if rc != JWResult.OK:
		return rc
	# rounding: floor, reason=单价 = 基价 × 费率，只取整一次
	var unit_fee: int = JWMath.mul_ppm(JWUnits.BASE_PRICE, fee_ppm)
	var gov_cash: int = JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH)
	var g: int = 0
	while g < JWUnits.GROUP:
		var qty: int = 0
		var k: int = 0
		while k < JWUnits.SERVICE_KIND:
			qty += _sc_group_svc[JWIds.idx_group_svc(g, k)]
			k += 1
		if qty > 0:
			# rounding: floor, reason=收费少收优于多收
			var fee: int = JWMath.mul_div_floor(qty, unit_fee, JWUnits.Q_SCALE)
			var agent: int = JWIds.agent_of_group(g)
			fee = mini(fee, maxi(0, _st.accounts.cash_of(agent)))
			if fee > 0:
				rc = _st.ledger.post(JWUnits.Kind.PUBLIC_FEE,
						JWIds.idx_account(agent, JWIds.ACC_CASH), gov_cash, fee, 0, -1, 0, g)
				if rc != JWResult.OK:
					return rc
				rc = _st.pop.record_fee_paid(g, fee)
				if rc != JWResult.OK:
					return rc
				rc = _st.treasury.record_other_receipt(fee)
				if rc != JWResult.OK:
					return rc
		g += 1
	return JWResult.OK


## 由 flow.pubserv.delivered_uqs 逐组摊出 delivered_to_group（长 GROUP_SVC_N）。
## 步骤：S07 §7.8
## 前置：S05 §5.7 的交付已完成
## 后置：_sc_group_svc 写满；Σ 逐组 == Σ 逐地区交付量
## 不变量：INV-149
## 失败：拆分和不等 → SPLIT_MISMATCH
##
## 两级都与 JWInventory.deliver_public_services 内部用的是同一套权重与决胜键
## （种类级：各种类的基准需求量；组级：该组该种类的基准需求量），因此结果可重放。
func _build_delivered_to_group() -> int:
	_sc_group_svc.fill(0)
	var r: int = 0
	while r < JWUnits.R:
		var delivered: int = _st.inventory.f_pub_delivered[r]
		if delivered <= 0:
			r += 1
			continue
		# 一级：按服务种类的基准需求量拆。
		_sc_weights.fill(0)
		var k: int = 0
		while k < JWUnits.SERVICE_KIND:
			var need_k: int = 0
			var a: int = 0
			while a < JWUnits.A:
				var sk: int = 0
				while sk < JWUnits.K:
					need_k += _st.pop.base_delivered_service[
							JWIds.idx_group_svc(JWIds.idx_group(r, a, sk), k)]
					sk += 1
				a += 1
			_sc_weights[k] = need_k
			k += 1
		var res: int = JWMath.split_lr_into(delivered, _sc_weights, _sc_tiebreak, _sc_out)
		if JWMath._split_last_fault != JWResult.OK:
			return JWMath._split_last_fault
		if res != 0:
			# 本地区基准需求全 0：无从摊分，登记残差（INV-005），不平均分。
			_st.ledger.log_rounding(CAUSE_RUNNER + 2, delivered, 0, res)
			r += 1
			continue
		# 一级结果先取到局部（只有 3 个数），二级要重用同一个 out 缓冲。
		var got0: int = _sc_out[0]
		var got1: int = _sc_out[1]
		var got2: int = _sc_out[2]
		# 二级：每个种类内按各组的基准需求量拆。
		k = 0
		while k < JWUnits.SERVICE_KIND:
			var got_k: int = got0
			if k == 1:
				got_k = got1
			elif k == 2:
				got_k = got2
			_sc_weights.fill(0)
			var slot: int = 0
			var a2: int = 0
			while a2 < JWUnits.A:
				var sk2: int = 0
				while sk2 < JWUnits.K:
					_sc_weights[slot] = _st.pop.base_delivered_service[
							JWIds.idx_group_svc(JWIds.idx_group(r, a2, sk2), k)]
					slot += 1
					sk2 += 1
				a2 += 1
			# 三个形参必须等长（split_lr_into 的前置），所以二级也走 _sc_out —— 一级结果
			# 已经取进 got0/1/2，这时重用它是安全的。
			var res2: int = JWMath.split_lr_into(got_k, _sc_weights, _sc_tiebreak, _sc_out)
			if JWMath._split_last_fault != JWResult.OK:
				return JWMath._split_last_fault
			if res2 == 0:
				slot = 0
				var a3: int = 0
				while a3 < JWUnits.A:
					var sk3: int = 0
					while sk3 < JWUnits.K:
						_sc_group_svc[JWIds.idx_group_svc(JWIds.idx_group(r, a3, sk3), k)] = \
								_sc_out[slot]
						slot += 1
						sk3 += 1
					a3 += 1
			else:
				_st.ledger.log_rounding(CAUSE_RUNNER + 3, got_k, 0, res2)
			k += 1
		r += 1
	return JWResult.OK


## 本季新生效政策的位掩码（update_blocs 的输入）。
## 步骤：S08 §8.3
## 前置：无
## 后置：不改状态
## 不变量：INV-129
## 失败：无
func _newly_effective_mask() -> int:
	var mask: int = 0
	var p: int = 0
	while p < JWUnits.POLICY_N:
		if _st.policy.effective_from_q[p] == _st.q and _st.policy.enabled[p] == 1:
			mask = mask | (1 << p)
		p += 1
	return mask


## 连续违约季数（review_and_terminate 的输入，INV-040）。
## 步骤：S08 §8.5
## 前置：S02 已完成
## 后置：不改状态
## 不变量：INV-040、INV-128
## 失败：无
##
## JWTreasury 的连续计数器是私有的，它把「连续 default_grace_q 季付不出第 1 档」压缩成
## 一个信号码返回。本类据此给出 0 或 params[DEFAULT_GRACE_Q]，两者足以让终局判据成立。
func _default_streak_q() -> int:
	if _fiscal_signal == JWTreasury.SIGNAL_FISCAL_RESTRUCTURING_FAILED:
		return _st.params[JWUnits.Param.DEFAULT_GRACE_Q]
	if _bond_default_flag == 1:
		return 1
	return 0


## 季号补零成三位（故障包目录名 q<NNN>）。
## 步骤：故障处置
## 前置：q >= 0
## 后置：不改状态
## 不变量：docs/12 §9
## 失败：无
func _pad_q(q: int) -> String:
	var s: String = str(q)
	while s.length() < FAULT_Q_PAD:
		s = "0" + s
	return s


## 写一个文本文件（故障包用；写不出来只登记控制台错误，不改状态）。
## 步骤：故障处置
## 前置：无
## 后置：不改状态
## 不变量：docs/12 §9
## 失败：无
func _write_text(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("JWTurnRunner: 故障包文件写不出来：" + path)
		return
	f.store_string(text)
	f.close()


## 步骤哈希的字典形态（step_hashes.json）。
## 步骤：故障处置
## 前置：无
## 后置：不改状态
## 不变量：INV-014
## 失败：无
func _step_hashes_dict() -> Dictionary:
	var d: Dictionary = {}
	d["q"] = _st.q
	d["state_hash_prev"] = _st.state_hash_prev
	var arr: Array = []
	var i: int = 0
	while i < _step_hash.size():
		arr.append(_step_hash[i])
		i += 1
	d["step_hash"] = arr
	return d


## 故障现场的字典形态（fault.json）。
## 步骤：故障处置
## 前置：无
## 后置：不改状态
## 不变量：docs/12 §9（失败的不变量编号与实测残差）
## 失败：无
func _fault_dict(step: int, code: int) -> Dictionary:
	var d: Dictionary = {}
	d["q"] = _st.q
	d["step"] = step
	d["code"] = code
	d["pending_code"] = JWResult.pending_code()
	d["pending_step"] = JWResult.pending_step()
	d["detail_a"] = JWResult._pending_a
	d["detail_b"] = JWResult._pending_b
	d["state_hash_prev"] = _st.state_hash_prev
	d["state_hash_now"] = _st.state_hash()
	return d


## 本季账本行的 CSV（docs/10 §2.5 的 13 列）。
## 步骤：故障处置
## 前置：无
## 后置：不改状态
## 不变量：INV-011
## 失败：无
func _ledger_csv() -> String:
	var out: String = "txn,q,step,kind,account,delta,qty,product,cause,entity,prod,exp,inc\n"
	var n: int = _st.ledger.log_row_count()
	var i: int = 0
	while i < n:
		out += str(_st.ledger.l_txn[i]) + "," + str(_st.ledger.l_q[i]) + ","
		out += str(_st.ledger.l_step[i]) + "," + str(_st.ledger.l_kind[i]) + ","
		out += str(_st.ledger.l_account[i]) + "," + str(_st.ledger.l_delta[i]) + ","
		out += str(_st.ledger.l_qty[i]) + "," + str(_st.ledger.l_product[i]) + ","
		out += str(_st.ledger.l_cause[i]) + "," + str(_st.ledger.l_entity[i]) + ","
		out += str(_st.ledger.l_prod[i]) + "," + str(_st.ledger.l_exp[i]) + ","
		out += str(_st.ledger.l_inc[i]) + "\n"
		i += 1
	return out


## 本季实物流水的 CSV（docs/10 §2.5 的 physical 通道）。
## 步骤：故障处置
## 前置：无
## 后置：不改状态
## 不变量：INV-011
## 失败：无
func _physical_csv() -> String:
	var out: String = "from,to,product,qty,cause,step\n"
	var n: int = _st.ledger.physical_row_count()
	var i: int = 0
	while i < n:
		out += str(_st.ledger.p_from[i]) + "," + str(_st.ledger.p_to[i]) + ","
		out += str(_st.ledger.p_product[i]) + "," + str(_st.ledger.p_qty[i]) + ","
		out += str(_st.ledger.p_cause[i]) + "," + str(_st.ledger.p_step[i]) + "\n"
		i += 1
	return out
