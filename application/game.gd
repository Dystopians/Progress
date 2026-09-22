## 应用层门面。**UI 只能通过它读状态、投命令**；UI 拿到的是只读的 `StateView`。
##
## 骨架依据：docs/17_api_skeleton.md §4.33（秩 A6；可引用秩 ≤10 与 A0..A5）。
class_name JWGame
extends RefCounted


## 构建标识。进 manifest 与 state.meta.build_id；不符只让重放失效，不影响读档（INV-134）。
## 它是**构建期注入**的量，在没有构建系统注入通道之前由本文件给出一个稳定串。
const BUILD_ID: String = "jingwei-simcore-1"

## 自动存档槽名（docs/11 §6.2：自动保存只追加 jsonl，不重写 state.json）。
const AUTOSAVE_SLOT: String = "autosave"

## 情景预测的季数（docs/17 §4.33：用同一个 SimCore 空命令跑 4 季）。
const PREVIEW_Q: int = 4

## 情景预测登记的指标（稳定 ID；在注册表里反查成整数码后喂 record_projection）。
## 四项都是 S02/S04/S06 的财政流量与存量，正是「未来四季会不会付不出钱」这一问的直接答案。
const PREVIEW_METRIC_IDS: PackedStringArray = [
	"state.gov.arrears_uu",
	"flow.gov.primary_paid_uu",
	"flow.gov.receipts_income_tax_uu",
	"flow.gov.new_borrowing_uu",
]

## 账本行的列数（docs/10 §2.5 的 13 列）。
const LEDGER_COLS: int = 13

## 解释项的列数（kind / entity / cause / amount / qty / constraint / q）。
const EXPLAIN_COLS: int = 7


## 只读状态快照句柄（Presentation 唯一能拿到的东西）。
## 每个数组访问器**传出前 duplicate()**，所以 UI 拿到的是副本，改它不会影响 SimCore。
## ui/** 中出现 JWLedger / JWSimState 的写方法即违规（静态检查）。
class StateView extends RefCounted:

	## 权威状态的只读引用；**本内部类不得暴露任何写接口**。
	var _st: JWSimState = null

	## 当前季序号。
	## 步骤：任意
	## 前置：无
	## 后置：不改状态
	## 不变量：INV-012（q 只在 S08 末 +1）
	## 失败：无
	func q() -> int:
		if _st == null:
			return 0
		return _st.q

	## 当前结算相位（JWUnits.Phase）。
	## 步骤：任意
	## 前置：无
	## 后置：不改状态
	## 不变量：INV-012
	## 失败：无
	## 剧本 ID（`scenario.<name>`，R-SCENARIO-01）。
	func scenario_id() -> String:
		if _st == null:
			return ""
		return _st.scenario_id

	func phase() -> int:
		if _st == null:
			return JWUnits.Phase.IDLE
		return _st.phase

	## 本局是否已终止。
	## 步骤：任意
	## 前置：无
	## 后置：不改状态
	## 不变量：INV-128（终止后任何 advance_quarter 返回 REJECT 且状态哈希不变）
	## 失败：无
	func run_terminated() -> bool:
		if _st == null or _st.politics == null:
			return false
		return _st.politics.run_terminated

	## 单个标量指标（走 JWSimState.read_metric）。
	## 步骤：任意
	## 前置：metric_code 已在加载期解析成整数码
	## 后置：不改状态
	## 不变量：INV-130；docs/11 §5.13 的 V-EV-02
	## 失败：未知 metric → Fault.METRIC_UNKNOWN 返回 0
	func scalar(metric_code: int, scope_idx: int) -> int:
		if _st == null:
			return 0
		return _st.read_metric(metric_code, scope_idx)

	## 数组副本（**duplicate() 后返回**）。
	## 步骤：任意
	## 前置：array_id_code 已登记
	## 后置：不改状态；调用方拿到的是副本
	## 不变量：计划书 §12（界面层不得直接修改 GDP、民意或库存）
	## 失败：未知 array_id_code → 返回空数组
	func array_copy(array_id_code: int) -> PackedInt64Array:
		if _st == null:
			return PackedInt64Array()
		return _st.registry_array_copy(array_id_code)

	## 稳定 ID → 条目注册表下标（`scalar` 与 `array_copy` 的码就是这个下标）。
	## 步骤：任意（冷路径，UI 初始化时查一次）
	## 前置：无
	## 后置：不改状态
	## 不变量：INV-014（注册表顺序由字节序排序定死）
	## 失败：查不到 → 返回 −1
	func code_of(stable_id: String) -> int:
		if _st == null:
			return -1
		var n: int = _st.registry_size()
		var e: int = 0
		while e < n:
			if _st.registry_id(e) == stable_id:
				return e
			e += 1
		return -1

	## 账本行区间（对账页用）。
	## 步骤：任意
	## 前置：0 <= from_row <= to_row <= log_row_count()
	## 后置：不改状态
	## 不变量：INV-011 / INV-139
	## 失败：越界 → 返回空数组
	##
	## 返回值是**行优先的扁平整数**，每行 13 列，列序即 docs/10 §2.5 的列序：
	## txn, q, step, kind, account, delta, qty, product, cause, entity, prod, exp, inc。
	func ledger_rows(from_row: int, to_row: int) -> PackedInt64Array:
		var out: PackedInt64Array = PackedInt64Array()
		if _st == null or _st.ledger == null:
			return out
		var n: int = _st.ledger.log_row_count()
		if from_row < 0 or to_row > n or from_row > to_row:
			return out
		out.resize((to_row - from_row) * JWGame.LEDGER_COLS)
		var w: int = 0
		var i: int = from_row
		while i < to_row:
			out[w] = _st.ledger.l_txn[i]
			out[w + 1] = _st.ledger.l_q[i]
			out[w + 2] = _st.ledger.l_step[i]
			out[w + 3] = _st.ledger.l_kind[i]
			out[w + 4] = _st.ledger.l_account[i]
			out[w + 5] = _st.ledger.l_delta[i]
			out[w + 6] = _st.ledger.l_qty[i]
			out[w + 7] = _st.ledger.l_product[i]
			out[w + 8] = _st.ledger.l_cause[i]
			out[w + 9] = _st.ledger.l_entity[i]
			out[w + 10] = _st.ledger.l_prod[i]
			out[w + 11] = _st.ledger.l_exp[i]
			out[w + 12] = _st.ledger.l_inc[i]
			w += JWGame.LEDGER_COLS
			i += 1
		return out

	## 本季账本行数（ledger_rows 的有效上界）。G4 界面新增的只读口，不改状态。
	## 步骤：任意
	## 前置：无
	## 后置：不改状态
	## 不变量：INV-011 / INV-139
	## 失败：账本缺失 → 0
	func ledger_row_count() -> int:
		if _st == null or _st.ledger == null:
			return 0
		return _st.ledger.log_row_count()

	## 三类分栏的解释项（ACCOUNTED / INFERRED / PROJECTED）。
	## 步骤：任意
	## 前置：kind ∈ JWUnits.ExplainKind
	## 后置：不改状态
	## 不变量：INV-140（projected 禁止回写状态）
	## 失败：kind 越界 → 返回空数组
	##
	## 返回值同样是行优先扁平整数，每行 7 列：
	## kind, entity, cause, amount_uu, qty_uqs, constraint_code, q。
	func explanations(kind: int) -> PackedInt64Array:
		var out: PackedInt64Array = PackedInt64Array()
		if _st == null or _st.diag == null:
			return out
		if kind < JWUnits.ExplainKind.ACCOUNTED or kind > JWUnits.ExplainKind.PROJECTED:
			return out
		var n: int = _st.diag.log_row_count()
		var i: int = 0
		while i < n:
			if _st.diag.e_kind[i] == kind:
				out.append(_st.diag.e_kind[i])
				out.append(_st.diag.e_entity[i])
				out.append(_st.diag.e_cause[i])
				out.append(_st.diag.e_amount[i])
				out.append(_st.diag.e_qty[i])
				out.append(_st.diag.e_constraint[i])
				out.append(_st.diag.e_q[i])
			i += 1
		return out

	## 未生效政策的原因码。
	## 步骤：任意
	## 前置：policy_idx ∈ [0, POLICY_N)
	## 后置：不改状态
	## 不变量：INV-100（玩家可见的未生效政策必须有原因码）
	## 失败：越界 → 返回 BlockedReason.NONE
	func blocked_reason(policy_idx: int) -> int:
		if _st == null or _st.policy == null:
			return JWUnits.BlockedReason.NONE
		if policy_idx < 0 or policy_idx >= JWUnits.POLICY_N:
			return JWUnits.BlockedReason.NONE
		return _st.policy.blocked_reason(policy_idx)

	## 某 cell 本季的紧约束码（JWUnits.Binding）。
	## 步骤：任意
	## 前置：cell ∈ [0, CELL)
	## 后置：不改状态
	## 不变量：INV-043..050（五项约束取 min）
	## 失败：越界 → 返回 Binding.PLAN
	func binding_code(cell: int) -> int:
		if _st == null or _st.sectors == null:
			return JWUnits.Binding.PLAN
		if cell < 0 or cell >= JWUnits.CELL:
			return JWUnits.Binding.PLAN
		return _st.sectors.binding_code(cell)


# ── 成员变量 ────────────────────────────────────────────────────────────

## 权威状态。
var _st: JWSimState = null

## 命令缓冲。
var _cmds: JWCommands = null

## 回合驱动。
var _runner: JWTurnRunner = null

## 存档。
var _saves: JWSaves = null

## 内容加载。
var _loader: JWContentLoader = null

## 重放校验。
var _replay: JWReplay = null

## 事件引擎（JWTurnRunner 的构造依赖；不在 JWSimState 的状态块里）。
var _events: JWEventEngine = null

## `content_hash` 不符时为 true（可看不可推进）。
var read_only_mode: bool = false

## 复用的只读视图实例（docs/17 §4.33：每次 view() 返回同一个实例）。
var _view: StateView = null

## 最近一次自动存档的返回码（0 == 成功）。自动存档失败不改变「这一季确实推进了」这一事实，
## 因此不把它混进 advance_quarter 的返回值，但也**不静默**：这里留痕，并 push_error 一条。
var last_autosave_code: int = 0
## 自动存档槽名（开局前可改；默认 "autosave"）。并行跑的测试 / 工具进程各用各的槽，避免互相覆盖（界面子代理的接口请求 1）。
var autosave_slot: String = AUTOSAVE_SLOT

## 最近一次 advance_quarter 的故障包目录（无故障时为空串）。
var last_fault_dir: String = ""


## 开新局：加载内容、建初始账本、注入 root_seed。
## 步骤：LOAD
## 前置：scenario 路径有效；root_seed == 0 表示运行时注入
## 后置：状态就绪，phase == IDLE，q == 0；已跑一遍 P0 不变量
## 不变量：INV-023、INV-141..152
## 失败：返回加载器的 JWResult；**不进入半初始化状态**
func new_game(scenario_path: String, root_seed: int, horizon_q: int) -> JWResult:
	# 全部装配都先落在局部变量上：任一步失败就整体丢弃，本对象的成员一位不改
	# （docs/17 §4.33 的「不进入半初始化状态」只能靠这个顺序保证）。
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	if horizon_q > 0:
		st.horizon_q = horizon_q

	var loader: JWContentLoader = JWContentLoader.new()
	var res: JWResult = loader.load_all(scenario_path, st)
	if res == null:
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 0, 0)
	if not res.ok:
		return res

	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()

	var events: JWEventEngine = JWEventEngine.new()
	events.allocate()
	# R-EVENT-01：装载 12 张事件卡（此前引擎一直是空的，事件从不发生）。
	var rev: JWResult = loader.load_events_into(events, st)
	if rev == null or not rev.ok:
		return rev if rev != null else JWResult.make_err(JWResult.Load.EVENT_COUNT, 0, 0)

	st.build_id = BUILD_ID
	st.content_hash = loader.content_hash
	st.param_set_version = loader.param_set_version
	# root_seed == 0 == 「运行时注入」：取一个与本次运行绑定的非零种子并**写进状态**，
	# 于是它照常进存档与 manifest，重放仍然逐位可复现（INV-131/133）。
	var seed_v: int = root_seed
	if seed_v == 0:
		# get_ticks_usec() 返回 int（get_unix_time_from_system() 是 float，整数契约里不许用）。
		# 末位置 1 保证非零：0 是「请注入」的哨兵，不能同时是一个合法种子。
		seed_v = Time.get_ticks_usec() | 1
	var rc_seed: int = st.rng.set_state_scalar(0, seed_v)
	if rc_seed != JWResult.OK:
		return JWResult.make_err(rc_seed, seed_v, 0)

	# 载入流水线的最后一步：立即跑一遍全部 P0 不变量（docs/11 §7）。
	JWResult.clear_pending()
	var p0: int = st.check_all_p0()
	if p0 != JWResult.OK:
		return JWResult.make_err(p0, st.q, 0)

	var saves: JWSaves = JWSaves.new()
	saves.scenario_hash = loader.scenario_hash

	# 全部就绪，一次性接管。
	_st = st
	_cmds = cmds
	_loader = loader
	_events = events
	_runner = JWTurnRunner.new(_st, _events)
	_saves = saves
	_replay = JWReplay.new()
	_view = null
	read_only_mode = false
	last_autosave_code = 0
	last_fault_dir = ""
	# 自动存档只追加、不建槽（JWSaves.autosave_append）：开局先把本局写成一个完整槽位，
	# 否则槽位不存在时每季追加都失败，槽位残留上一局时又以 SAVE_CORRUPT（2900）失败。
	_reset_autosave()
	return JWResult.make_ok()


## 把当前局面写成自动存档槽的新起点（开局与读档之后各一次）。失败只登记 last_autosave_code，不影响开局。
## fresh ⇒ 新局，检查点从空开始；否则以 source 槽（刚读的存档）的检查点为起点。
func _reset_autosave(fresh: bool = true, source: String = "") -> void:
	if _saves == null or _st == null or _cmds == null:
		return
	_saves.checkpoint_fresh = fresh
	_saves.checkpoint_source_slot = source
	var r: JWResult = _saves.save(_st, _cmds, autosave_slot)
	_saves.checkpoint_fresh = false
	_saves.checkpoint_source_slot = ""
	if r != null and not r.ok:
		last_autosave_code = r.code


## 投一条命令（UI 的唯一写入路径）。
## 步骤：CMD
## 前置：!read_only_mode
## 后置：命令入缓冲；**绝不直接改账**；一切生效发生在 S02
## 不变量：INV-138（命令只写 pending_params 与命令日志）、INV-137
## 失败：转发 JWCommands.submit 的 JWResult；只读模式 → Reject.PHASE_BUSY
func submit_command(kind: int, args: PackedInt64Array) -> JWResult:
	if _cmds == null or _st == null:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	if read_only_mode:
		# INV-134：content_hash 不符只允许只读检视，命令一条都不收。
		return JWResult.make_err(JWResult.Reject.PHASE_BUSY, kind, 0)
	return _cmds.submit(kind, args, _st.q, _st.policy_defs)


# ── R-CLOCK-01 第二部分：批量推进与暂停原因 ───────────────────────────────

## 批量推进的暂停原因（界面按它显示「为什么停下」）。
enum Pause { NONE = 0, TERMINATED = 1, CRISIS = 2, GOV_CHANGE = 3, ELECTION = 4, ARREARS = 5,
		FAILED = 6, EVENT_CHOICE = 7 }


## 推进前的探针：危机各轨级别、政府更替次数、届次、欠付。
func pause_probe() -> Dictionary:
	if _st == null:
		return {}
	return {"stages": _st.crisis.stage.duplicate(), "gov_changes": _st.crisis.gov_changes,
			"term_index": _st.politics.term_index, "arrears": _st.treasury.arrears}


## 一季推进之后是否该停（按优先级：终局 > 危机升级 > 政府更替 > 选举 > 新增欠付）。
func pause_reason(before: Dictionary, advance_ok: bool) -> int:
	if not advance_ok:
		return Pause.FAILED
	if _st == null or before.is_empty():
		return Pause.NONE
	if _st.politics.run_terminated:
		return Pause.TERMINATED
	var st0: PackedInt64Array = before["stages"]
	for t: int in mini(st0.size(), _st.crisis.stage.size()):
		if _st.crisis.stage[t] > st0[t]:
			return Pause.CRISIS
	if _st.crisis.gov_changes > int(before["gov_changes"]):
		return Pause.GOV_CHANGE
	if _st.politics.term_index > int(before["term_index"]):
		return Pause.ELECTION
	if _st.politics.has_pending_choice():
		return Pause.EVENT_CHOICE
	if _st.treasury.arrears > int(before["arrears"]):
		return Pause.ARREARS
	return Pause.NONE


## 批量推进 n 季（R-CLOCK-01）：调用方先提交本季业务命令（不含推进标记）；本函数逐季补推进标记并结算，
## 遇到暂停原因即停。结果与逐季调用 advance_quarter 逐位相同——它就是逐季调用。
## 返回 {advanced, reason, code}。
func advance_batch(n: int) -> Dictionary:
	var done: int = 0
	var reason: int = Pause.NONE
	var code: int = 0
	var empty: PackedInt64Array = PackedInt64Array()
	empty.resize(JWCommands.ARG_SLOTS)
	empty.fill(0)
	while done < n:
		var before: Dictionary = pause_probe()
		submit_command(JWCommands.Kind.ADVANCE_QUARTER, empty)
		var r: JWResult = advance_quarter()
		var ok: bool = r == null or r.ok
		if not ok:
			code = r.code
		else:
			done += 1
		reason = pause_reason(before, ok)
		if reason != Pause.NONE:
			break
	return {"advanced": done, "reason": reason, "code": code}


## 推进一个季度。
## 步骤：S01..S08
## 前置：!read_only_mode；!run_terminated；本季命令流以一条 advance_quarter 结尾
## 后置：成功则 q += 1 并自动追加存档
## 不变量：INV-012、INV-128（终止后任何 advance_quarter 返回 REJECT 且状态哈希不变）
## 失败：返回 JWResult 包住 runner 的 Fault 码；故障时附故障包路径
func advance_quarter() -> JWResult:
	if _runner == null or _st == null or _cmds == null:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	if read_only_mode:
		# INV-134 的「拒绝推进」就落在这里：runner 拿不到 content_hash 的外部基准，
		# 这一道闸只有应用层能设。
		return JWResult.make_err(JWResult.Reject.PHASE_BUSY, _st.q, 0)
	last_fault_dir = ""
	var code: int = _runner.advance_quarter(_cmds)
	if code != JWResult.OK:
		last_fault_dir = _runner.last_fault_dir
		return JWResult.make_err(code, _st.q, JWResult.pending_step())

	# 自动存档：追加命令流与检查点（docs/11 §6.2 的 O(1) 追加写）。
	last_autosave_code = JWResult.OK
	if _saves != null:
		var r1: JWResult = _saves.autosave_append(_st, _cmds, autosave_slot)
		if r1 != null and not r1.ok:
			last_autosave_code = r1.code
		var r2: JWResult = _saves.append_checkpoint(_st.q - 1, _st.state_hash(),
				_runner.step_hashes(), autosave_slot)
		if r2 != null and not r2.ok and last_autosave_code == JWResult.OK:
			last_autosave_code = r2.code
		if last_autosave_code != JWResult.OK:
			push_error("JWGame: 自动存档失败，码 " + str(last_autosave_code)
					+ "（本季已推进，状态不受影响）")
	return JWResult.make_ok()


## 取只读视图（每次调用返回同一个 StateView 实例，内部数据按需 duplicate）。
## 步骤：任意
## 前置：无
## 后置：UI 拿不到任何写接口
## 不变量：计划书 §12（界面层不得直接修改 GDP、民意或库存）
## 失败：无
func view() -> StateView:
	if _view == null:
		_view = StateView.new()
	_view._st = _st
	return _view


## 情景预测：对状态做只读副本，用**同一个 SimCore** 空命令跑 4 季（不另写近似模型）。
## 步骤：S08 之后或 UI 请求时
## 前置：phase == IDLE
## 后置：把结果喂给 JWDiagnostics.record_projection()；**不写任何真实状态**
## 不变量：INV-140（projected 禁止回写状态）；docs/12 §8.6、OQ-230（延迟风险）
## 失败：副本推进失败 → 丢弃预测并返回告警，不影响主线
##
## 副本用一份**全新分配的** JWEventEngine：事件模板不在 JWSimState 的状态块里，
## duplicate_state() 复制不到它。因此预测是「无事件情景」，这一点必须写进 UI 文案
## （见返回值 open_questions：加载器目前也没有把事件模板喂给引擎的通路）。
func preview_four_quarters() -> JWResult:
	if _st == null or _st.diag == null:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	if _st.phase != JWUnits.Phase.IDLE:
		return JWResult.make_err(JWResult.Reject.PHASE_BUSY, _st.phase, JWUnits.Phase.IDLE)

	var codes: PackedInt64Array = PackedInt64Array()
	codes.resize(PREVIEW_METRIC_IDS.size())
	var v: StateView = view()
	var m: int = 0
	while m < PREVIEW_METRIC_IDS.size():
		codes[m] = v.code_of(PREVIEW_METRIC_IDS[m])
		m += 1

	# duplicate_state() 只复制注册表条目，冲击通道、世界基准、按键解析的政策槽位等内容级字段不在其中，
	# 副本在 S01 即登记 INDEX_OUT_OF_RANGE（界面子代理实测）。改用与读档同一条路：装过内容包的新状态 +
	# 存档字典整体覆盖——副本与真状态在注册表口径上逐位相同，内容级字段来自同一个内容包。
	if _loader == null:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	var copy: JWSimState = JWSimState.new()
	copy.allocate_all()
	var ldr: JWContentLoader = JWContentLoader.new()
	var lres: JWResult = ldr.load_all(_loader.root_path(), copy)
	if lres == null or not lres.ok:
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 0, 0)
	var zeroed: PackedStringArray = PackedStringArray()
	var rrs: int = _ui_dry_restore(copy, _st.to_dict(), zeroed)
	if rrs != JWResult.OK:
		return JWResult.make_err(rrs, 0, 0)
	var ev: JWEventEngine = JWEventEngine.new()
	ev.allocate()
	var runner: JWTurnRunner = JWTurnRunner.new(copy, ev)
	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	var marker: PackedInt64Array = PackedInt64Array()
	marker.resize(JWCommands.ARG_SLOTS)
	marker.fill(0)

	# 故障登记是静态的：预测跑坏了不能污染主线的第一现场，所以先存后复。
	var saved_code: int = JWResult.pending_code()
	var saved_step: int = JWResult.pending_step()
	var saved_a: int = JWResult._pending_a
	var saved_b: int = JWResult._pending_b
	JWResult.clear_pending()

	var ok: bool = true
	var t: int = 0
	while t < PREVIEW_Q:
		var rs: JWResult = cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, marker, copy.q,
				copy.policy_defs)
		if rs == null or not rs.ok:
			ok = false
			break
		if runner.advance_quarter(cmds) != JWResult.OK:
			ok = false
			break
		var mm: int = 0
		while mm < codes.size():
			if codes[mm] >= 0:
				_st.diag.record_projection(t, codes[mm], copy.read_metric(codes[mm], 0))
			mm += 1
		t += 1

	JWResult.clear_pending()
	if saved_code != JWResult.OK:
		JWResult.set_step(saved_step)
		JWResult.raise_fault(saved_code, saved_a, saved_b)
	if not ok:
		return JWResult.make_err(JWResult.Fault.PHASE_VIOLATION, copy.q, t)
	return JWResult.make_ok()


## 最近一次结算触发的事件（R-EVENT-01；界面报告用，只读）。
## 引擎的本季缓冲在下一次 S08 入口才重置，所以结算完成后读到的就是刚结算那一季的触发。
func fired_events_last() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _events == null or _loader == null:
		return out
	for e: int in JWUnits.EVENT_N:
		if _events.fired_this_quarter(e):
			out.append({"id": "event.E%02d" % (e + 1), "label": _loader.event_label(e)})
	return out


## 存档门面转发。
## 步骤：冷路径
## 前置：phase == IDLE
## 后置：见 JWSaves.save
## 不变量：INV-131
## 失败：转发 JWSaves.save 的 JWResult
func save_game(slot: String) -> JWResult:
	if _saves == null or _st == null or _cmds == null:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	# 新建的手动存档从自动存档槽搬运本局的逐季检查点，重放校验才有东西可比（不再空过）。
	_saves.checkpoint_source_slot = autosave_slot if slot != autosave_slot else ""
	return _saves.save(_st, _cmds, slot)


## 读档门面转发。
## 步骤：冷路径
## 前置：phase == IDLE
## 后置：见 JWSaves.load；content_hash 不符时置 read_only_mode
## 不变量：INV-132..136
## 失败：转发 JWSaves.load 的 JWResult
func load_game(slot: String) -> JWResult:
	if _saves == null or _st == null or _cmds == null:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	# R-SCENARIO-01：存档属于另一个剧本 ⇒ 先按该剧本重新装配内容包，再读档。
	var sid: String = _saves.peek_scenario_id(slot)
	if sid.begins_with("scenario.") and sid != _st.scenario_id:
		var root: String = JWContentLoader.split_root_spec(_loader.root_path())[0]
		var rn: JWResult = new_game(root + "#" + sid.substr(9), 1, 0)
		if rn == null or not rn.ok:
			return rn if rn != null else JWResult.make_err(JWResult.Load.FILE_FORMAT, 0, 0)
	var res: JWResult = _saves.load(slot, _st, _cmds, _loader)
	if res == null:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	if res.ok:
		# INV-134 的两半：content_hash / param_set_version 不符 ⇒ 只读检视；
		# build_id 不符 ⇒ 禁用重放验证但仍可继续玩。
		read_only_mode = _saves.read_only_required
		# 读回的是另一局（或另一槽）：自动存档从读回的局面重新起头，否则此后每季追加都对不上。
		if not read_only_mode and slot != autosave_slot:
			_reset_autosave(false, slot)
	return res


## 重放校验门面转发。
## 步骤：冷路径
## 前置：phase == IDLE；build_id 一致
## 后置：见 JWReplay.verify
## 不变量：INV-014、INV-133
## 失败：转发 JWReplay.verify 的 JWResult
func verify_replay(slot: String) -> JWResult:
	if _replay == null:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	if _st != null and _st.replay_unreliable:
		# build_id 不符时重放不承诺逐位相同，直接说「不承诺」，不跑一遍再报一个假分歧。
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	return _replay.verify(slot, _loader)


# ── G4 界面：新增的只读查询（docs/20 §17「对 Application 层的接口要求」）────────
#
# 以下方法**只读** `_st` / `_cmds`，或在一份**影子状态**上试算；任何一个都不写权威状态、
# 不改命令缓冲、不改上面任何既有方法的行为。界面层经它们拿到「应用层已经算好的量」。
#
# 为什么草案试算不复用 `preview_four_quarters()` 的 `duplicate_state()`：
# 副本只复制注册表条目，而冲击通道、世界基准等内容级字段不在注册表里，
# 副本在 S01 的 `JWShocks.apply_to_world` 登记 INDEX_OUT_OF_RANGE（实测，已写入接口请求）。
# 这里改用「装过内容包的影子状态 + 存档字典整体覆盖」，与读档走同一条路（docs/11 §6.6），
# 因此影子与真状态在注册表口径上逐位相同，内容级字段来自同一个内容包。

## derived.* 稳定 ID → JWDiagnostics 成员名（读时取，不进注册表，docs/10 §9.3）。
const UI_DERIVED_FIELDS: Dictionary = {
	"derived.gdp.production_uu": "gdp_production",
	"derived.gdp.expenditure_uu": "gdp_expenditure",
	"derived.gdp.income_uu": "gdp_income",
	"derived.gdp.real_uu": "gdp_real",
	"derived.gdp.annual_nominal_uu": "gdp_annual_nominal",
	"derived.labor.unemployment_ppm": "unemployment_ppm",
	"derived.fiscal.debt_to_gdp_ppm": "debt_to_gdp_ppm",
	"derived.fiscal.debt_service_ratio_ppm": "debt_service_ratio_ppm",
	"derived.fiscal.next4q_debt_service_uu": "next4q_debt_service",
	"derived.living.consumption_index_ppm": "living_consumption_index",
	"derived.living.public_service_index_ppm": "living_service_index",
	"derived.income_quantile_uu": "income_quantile",
	"derived.region.population_persons": "region_population",
	"derived.group.labor_force_persons": "labor_force",
	"derived.region.electricity_availability_ppm": "electricity_availability",
	"derived.region.housing_occupied_units": "housing_occupied",
	"derived.region.construction_slots_used": "slots_used",
}

## 规则卡与原因文案要显示的政治规则阈值（JWPolitics 的加载期常量，不进注册表）。
const UI_POLITICS_RULE_FIELDS: PackedStringArray = [
	"veto_stance_threshold_ppm",
	"budget_review_deficit_limit_ppm",
	"budget_review_arrears_limit_uu",
	"budget_review_fail_to_lost_count",
	"budget_review_recovery_reviews",
	"supermajority_authority_min_seats_ppm",
]

## 影子状态（草案试算专用）。内容包只装一次；每次试算前用当前状态的存档字典整体覆盖。
var _dry_st: JWSimState = null
## 影子状态装载时的内容根路径（换内容根即重建）。
var _dry_root: String = ""
## 稳定 ID → 注册表下标的缓存。真状态与影子状态的注册表同构（INV-014），码值相同。
var _ui_code_cache: Dictionary = {}


## derived.* 的权威值快照（取自 JWDiagnostics，最近一次 S06/S07/S08 的结果）。
## 步骤：任意（冷路径）
## 前置：无
## 后置：不改状态；数组一律 duplicate()
## 不变量：计划书 §12（界面层不得自行计算数值，docs/20 B-02）
## 失败：诊断块缺失或字段缺失 → 该键不出现（调用方显示「尚未结算」而不是 0）
func derived_snapshot() -> Dictionary:
	var out: Dictionary = {}
	if _st == null or _st.diag == null:
		return out
	var d: Object = _st.diag
	for key: String in UI_DERIVED_FIELDS.keys():
		var v: Variant = d.get(String(UI_DERIVED_FIELDS[key]))
		if v is int:
			out[key] = v
		elif v is PackedInt64Array:
			out[key] = (v as PackedInt64Array).duplicate()
	return out


## 未来 n 季（含当前季）的已签承诺四泳道（docs/20 D-02 的承诺时间轴，T1 先做 12 季静态视窗）：
## 到期本金、利息（逐批次合同现金流）、项目分期款（假设按期足额付款）、设施运行费与政策项目期应付。
## 全部由 SimCore 同口径函数给出（界面不运算，docs/20 B-02）；不含未提交的草案，也不含未来新发的债。
## 步骤：冷路径
## 前置：已开局
## 后置：不改状态
## 失败：未开局 → 空字典
func commitment_schedule(n: int) -> Dictionary:
	if _st == null or n <= 0:
		return {}
	var q0: int = _st.q
	var pr: PackedInt64Array = PackedInt64Array()
	var it: PackedInt64Array = PackedInt64Array()
	var pj: PackedInt64Array = PackedInt64Array()
	var ox: PackedInt64Array = PackedInt64Array()
	pr.resize(n)
	it.resize(n)
	pj.resize(n)
	ox.resize(n)
	_st.bonds.debt_service_schedule_into(q0, n, pr, it)
	_st.projects.installment_schedule_into(q0, n, pj)
	# 运行费：已并入长期义务的每季额（常数）+ 能力 / 行政类政策项目期的每季应付（按剩余承诺逐季扣减）。
	var room: PackedInt64Array = PackedInt64Array()
	room.resize(JWUnits.POLICY_N)
	for p: int in JWUnits.POLICY_N:
		room[p] = maxi(_st.policy.budget_committed[p] - _st.policy.budget_spent[p], 0)
	for t: int in n:
		var qq: int = q0 + t
		var o: int = _st.treasury.service_opex_committed
		for p2: int in JWUnits.POLICY_N:
			if not _st.policy.in_program(p2, _st.policy_defs, qq):
				continue
			var k: int = _st.policy_defs.kind[p2]
			if k != JWPolicyDef.POLICY_KIND_CAPACITY and k != JWPolicyDef.POLICY_KIND_ADMIN:
				continue
			var due: int = mini(_st.policy_defs.cost_per_quarter(p2), room[p2])
			if due > 0:
				o += due
				room[p2] -= due
		ox[t] = o
	return {"q0": q0, "principal": pr, "interest": it, "projects": pj, "opex": ox}


## E17：上一季采购透明通道的 8 个中间量（实记，来自 log.explanations）：{policy, coverage, audit, progress, ramp,
## avail, load, gain, delta}（ppm）。本季没有这条通道的记录时返回空字典。
## 步骤：冷路径
## 前置：无
## 后置：不改状态
## 失败：未开局 → 空字典
func transparency_explained() -> Dictionary:
	var out: Dictionary = {}
	if _st == null or _st.diag == null:
		return out
	var base: int = JWPolicyEngine.EXPLAIN_P12_BASE
	for i: int in _st.diag.log_row_count():
		var c: int = _st.diag.e_cause[i]
		if _st.diag.e_kind[i] != JWUnits.ExplainKind.ACCOUNTED or c < base \
				or c >= base + JWPolicyEngine.EXPLAIN_P12_KEYS.size():
			continue
		out[JWPolicyEngine.EXPLAIN_P12_KEYS[c - base]] = _st.diag.e_amount[i]
		out["policy"] = _st.diag.e_entity[i]
	return out


## 命令流的只读副本（命令日志台账与季度回执用）。
## 步骤：任意（冷路径）
## 前置：无
## 后置：不改状态；返回的数组都是切片副本
## 不变量：INV-137（被拒命令也在档，界面据此给出「为什么没有执行」）
## 失败：命令缓冲缺失 → 空字典
func command_log_copy() -> Dictionary:
	var out: Dictionary = {}
	if _cmds == null:
		return out
	var n: int = _cmds.count
	out["count"] = n
	out["arg_slots"] = JWCommands.ARG_SLOTS
	out["command_id"] = _ui_packed_slice(_cmds, "c_command_id", n)
	out["issued_q"] = _ui_packed_slice(_cmds, "c_issued_q", n)
	out["kind"] = _ui_packed_slice(_cmds, "c_kind", n)
	out["args"] = _ui_packed_slice(_cmds, "c_arg", n * JWCommands.ARG_SLOTS)
	out["accepted"] = _ui_packed_slice(_cmds, "c_accepted", n)
	out["reject_code"] = _ui_packed_slice(_cmds, "c_reject_code", n)
	return out


## 规则参数的只读副本：全部 param.*（按 JWUnits.Param 名取值）+ 政治规则阈值。
## 步骤：任意（冷路径）
## 前置：无
## 后置：不改状态
## 不变量：计划书 §04「不隐藏当前规则」；界面不硬编码阈值（docs/20 §17）
## 失败：缺字段 → 该键不出现
func rule_params() -> Dictionary:
	var out: Dictionary = {}
	if _st == null:
		return out
	var names: Array = JWUnits.Param.keys()
	var i: int = 0
	while i < names.size() and i < _st.params.size():
		out["param." + String(names[i]).to_lower()] = _st.params[i]
		i += 1
	if _st.politics != null:
		for f: String in UI_POLITICS_RULE_FIELDS:
			var v: Variant = _st.politics.get(f)
			if v is int:
				out["politics." + f] = v
	out["meta.content_hash"] = _st.content_hash
	out["meta.build_id"] = _st.build_id
	out["meta.horizon_q"] = _st.horizon_q
	return out


## 存档槽列表（只读各槽的 manifest.json）。
## 步骤：冷路径
## 前置：无
## 后置：不改状态、不改任何文件
## 不变量：INV-134（content_hash / schema_version 是否匹配由此行给出，界面据此标注整行）
## 失败：目录不存在 → 空数组；单个 manifest 坏 → 该行带 manifest_ok = false
func list_save_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir: DirAccess = DirAccess.open(JWSaves.SAVES_ROOT)
	if dir == null:
		return out
	var names: PackedStringArray = PackedStringArray()
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with(".") \
				and not entry.ends_with(JWSaves.TMP_SUFFIX) and not entry.ends_with(JWSaves.BAK_SUFFIX):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for slot: String in names:
		var row: Dictionary = {"slot": slot, "manifest_ok": false}
		var path: String = JWSaves.SAVES_ROOT + slot + "/" + JWSaves.FILE_MANIFEST
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				var m: Dictionary = parsed
				row["manifest_ok"] = true
				row["schema_version"] = _ui_int(m.get(JWSaves.MK_SCHEMA_VERSION, -1))
				row["q"] = _ui_int(m.get(JWSaves.MK_Q, -1))
				row["root_seed"] = _ui_int(m.get(JWSaves.MK_ROOT_SEED, 0))
				row["content_hash"] = String(m.get(JWSaves.MK_CONTENT_HASH, ""))
				row["build_id"] = String(m.get(JWSaves.MK_BUILD_ID, ""))
				row["created_utc"] = str(m.get(JWSaves.MK_CREATED_UTC, ""))
				row["command_count"] = _ui_int(m.get(JWSaves.MK_COMMAND_COUNT, 0))
				var sv: int = int(row["schema_version"])
				row["schema_ok"] = sv >= 0 and sv <= JWSaves.CURRENT_SCHEMA_VERSION
				row["content_match"] = _st != null and String(row["content_hash"]) == _st.content_hash
		out.append(row)
	return out


## 草案试算第一段：在调用线程（主线程）上取当前状态的存档字典。
## 步骤：phase == IDLE 时的冷路径
## 前置：已开局
## 后置：不改状态；返回的字典与真状态不共享任何数组
## 不变量：INV-140（projected 禁止回写状态）
## 失败：未开局 → 空字典
func dry_run_snapshot() -> Dictionary:
	if _st == null or _loader == null:
		return {}
	var snap: Dictionary = {}
	snap["state"] = _st.to_dict()
	snap["shock_log"] = _st.shocks.export_shock_log() if _st.shocks != null else PackedInt64Array()
	snap["root"] = _loader.root_path()
	snap["content_hash"] = _st.content_hash
	snap["param_ver"] = _st.param_set_version
	snap["q"] = _st.q
	snap["terminated"] = _st.politics != null and _st.politics.run_terminated
	return snap


## 草案试算第二段：影子状态上「提交草案 + 推进 n_q 季」，只写影子（可在工作线程调用，
## 但同一 JWGame 同时只能有一次在跑；调用方负责串行）。
## 步骤：冷路径
## 前置：snap 来自 dry_run_snapshot()；draft_args[i] 是 6 槽整数参数
## 后置：真状态、命令缓冲与存档一概不变；故障登记（静态）先存后复
## 不变量：INV-140；计划书 §04「可以隐藏未来冲击」—— 影子里不抽本局真实的冲击到达，
##          只按调用方给的情景强度（shock_ppm[3]）设定三类冲击，已生效的冲击按当前强度延续
## 失败：返回字典的 ok == false，code 为故障码或 Reject 码
func dry_run_exec(snap: Dictionary, draft_kinds: PackedInt64Array, draft_args: Array,
		n_q: int, shock_ppm: PackedInt64Array) -> Dictionary:
	var out: Dictionary = {"ok": false, "code": 0, "quarters": 0, "terminated_at": -1,
			"termination_reason": 0, "scenario_applied": false}
	if snap.is_empty() or not snap.has("state"):
		out["code"] = JWResult.Load.SAVE_CORRUPT
		return out
	var saved_code: int = JWResult.pending_code()
	var saved_step: int = JWResult.pending_step()
	var saved_a: int = JWResult._pending_a
	var saved_b: int = JWResult._pending_b
	JWResult.clear_pending()

	var sh: JWSimState = _ui_dry_shadow(String(snap.get("root", "")))
	var fault: int = 0
	if sh == null:
		fault = JWResult.Load.FILE_FORMAT
	var zeroed: PackedStringArray = PackedStringArray()
	if fault == 0:
		fault = _ui_dry_restore(sh, snap["state"], zeroed)
	out["flow_entries_zeroed"] = zeroed
	if fault == 0 and sh.shocks != null:
		var rows: PackedInt64Array = snap.get("shock_log", PackedInt64Array())
		var rs: JWResult = sh.shocks.load_shock_log(rows)
		if rs == null or not rs.ok:
			fault = rs.code if rs != null else JWResult.Load.SAVE_CORRUPT
	if fault == 0:
		sh.content_hash = String(snap.get("content_hash", ""))
		sh.param_set_version = int(snap.get("param_ver", 0))
		sh.build_id = BUILD_ID
		fault = sh.finalize_load()
	if fault == 0:
		out["scenario_applied"] = _ui_dry_apply_scenario(sh, shock_ppm, n_q)

	var series: Dictionary = {}
	var s02: PackedInt64Array = PackedInt64Array()
	var submit_codes: PackedInt64Array = PackedInt64Array()
	if fault == 0:
		var ev: JWEventEngine = JWEventEngine.new()
		ev.allocate()
		var runner: JWTurnRunner = JWTurnRunner.new(sh, ev)
		var cmds: JWCommands = JWCommands.new()
		cmds.allocate()
		var rows_of: PackedInt64Array = PackedInt64Array()
		var i: int = 0
		while i < draft_kinds.size():
			var a: PackedInt64Array = draft_args[i] if i < draft_args.size() else PackedInt64Array()
			var r: JWResult = cmds.submit(draft_kinds[i], a, sh.q, sh.policy_defs)
			submit_codes.append(0 if (r != null and r.ok) else (r.code if r != null else -1))
			rows_of.append(cmds.count - 1)
			i += 1
		var marker: PackedInt64Array = PackedInt64Array()
		marker.resize(JWCommands.ARG_SLOTS)
		marker.fill(0)
		var bonds_before: int = _ui_reg_scalar(sh, "state.bond.count")
		var projects_before: int = _ui_reg_scalar(sh, "state.project.count")
		var t: int = 0
		while t < n_q:
			var rm: JWResult = cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, marker, sh.q,
					sh.policy_defs)
			if rm == null or not rm.ok:
				fault = rm.code if rm != null else JWResult.Reject.COMMAND_ORDER
				break
			var rc: int = runner.advance_quarter(cmds)
			if rc == JWResult.Reject.RUN_TERMINATED:
				break
			if rc != JWResult.OK:
				fault = rc
				out["fault_step"] = JWResult.pending_step()
				break
			if t == 0:
				var acc: PackedInt64Array = _ui_packed_slice(cmds, "c_accepted", cmds.count)
				var rej: PackedInt64Array = _ui_packed_slice(cmds, "c_reject_code", cmds.count)
				for row: int in rows_of:
					if row >= 0 and row < acc.size() and acc[row] == 0:
						s02.append(rej[row] if rej[row] != 0 else JWResult.Reject.PRECONDITION)
					else:
						s02.append(0)
				out["cell_output_q0"] = _ui_reg_array(sh, "flow.cell.output_actual_uqs")
				out["new_bonds"] = _ui_new_rows(sh, "bond", bonds_before)
				out["new_projects"] = _ui_new_rows(sh, "project", projects_before)
			_ui_dry_collect(sh, series)
			t += 1
			if sh.politics != null and sh.politics.run_terminated:
				out["terminated_at"] = sh.q - 1
				out["termination_reason"] = sh.politics.termination_reason
				break
		out["quarters"] = t
		out["living_index_end"] = _ui_reg_array(sh, "state.group.living_index_ppm")
		out["population_end"] = _ui_reg_array(sh, "state.group.population_persons")
		out["disposable_end"] = _ui_group_disposable(sh)

	JWResult.clear_pending()
	if saved_code != JWResult.OK:
		JWResult.set_step(saved_step)
		JWResult.raise_fault(saved_code, saved_a, saved_b)
	out["ok"] = fault == 0
	out["code"] = fault
	out["series"] = series
	out["s02_codes"] = s02
	out["submit_codes"] = submit_codes
	out["q0"] = int(snap.get("q", 0))
	return out


## 影子状态：装一次内容包（换内容根即重建）。
func _ui_dry_shadow(root: String) -> JWSimState:
	if root == "":
		return null
	if _dry_st != null and _dry_root == root:
		return _dry_st
	var sh: JWSimState = JWSimState.new()
	sh.allocate_all()
	var ld: JWContentLoader = JWContentLoader.new()
	var res: JWResult = ld.load_all(root, sh)
	if res == null or not res.ok:
		return null
	_dry_st = sh
	_dry_root = root
	return sh


## 影子覆盖：先清零影子的全部流量，再用存档字典整体覆盖。
## 个别流量条目在 SimCore 里没有写入口（实测：JWBondBook 只有 flow_array、没有 set_flow_array，
## 于是 flow.bond.interest_due_uu / principal_due_uu 在 from_dict 的逐位读回比对中必然失败）。
## 遇到这种 flow.* 条目时，在字典里把它置零后重试：流量在下一季 S01 整表清零后重算，
## 置零不改变试算结果；被置零的条目逐条记入返回值，不静默。
func _ui_dry_restore(sh: JWSimState, state_dict: Dictionary, zeroed: PackedStringArray) -> int:
	sh.reset_all_flows()
	JWResult.clear_pending()
	var tries: int = 0
	while tries < 32:
		var rf: JWResult = sh.from_dict(state_dict)
		if rf != null and rf.ok:
			# from_dict 把 SoA 的 ids[] 换成存档里的实长列表（开局为空），而 JWProjectQueue.launch
			# 按容量下标写 id[p] —— 不补回容量，影子里第一次立项就越界（实测，已写入接口请求）。
			_ui_restore_soa_capacity(sh.projects, JWUnits.PROJECT_CAP0)
			_ui_restore_soa_capacity(sh.bonds, JWUnits.BOND_CAP0)
			return JWResult.OK
		if rf == null:
			return JWResult.Load.SAVE_CORRUPT
		if rf.code != JWResult.Load.SAVE_CORRUPT:
			return rf.code
		var e: int = rf.detail_a
		if e < 0 or e >= sh.registry_size():
			return rf.code
		var id: String = sh.registry_id(e)
		if not id.begins_with("flow.") or not _ui_zero_dict_entry(state_dict, id):
			return rf.code
		zeroed.append(id)
		tries += 1
	return JWResult.Load.SAVE_CORRUPT


## SoA 的 ids[] 补回容量（只用于影子）。
static func _ui_restore_soa_capacity(block: Object, cap: int) -> void:
	if block == null:
		return
	var v: Variant = block.get("id")
	if v is PackedStringArray:
		var ids: PackedStringArray = v
		if ids.size() < cap:
			ids.resize(cap)
			block.set("id", ids)


## 把存档字典里的一个条目置零（数组保持长度与编码）。只用于影子覆盖，不碰真状态。
static func _ui_zero_dict_entry(state_dict: Dictionary, id: String) -> bool:
	var arrays: Dictionary = state_dict.get(JWSimState.SAVE_KEY_ARRAYS, {})
	if arrays.has(id):
		var rec: Dictionary = (arrays[id] as Dictionary).duplicate()
		var n: int = int(rec.get(JWSimState.SAVE_KEY_N, 0))
		var z: PackedInt64Array = PackedInt64Array()
		z.resize(n)
		z.fill(0)
		rec[JWSimState.SAVE_KEY_DATA] = Marshalls.raw_to_base64(z.to_byte_array())
		arrays[id] = rec
		return true
	var scalars: Dictionary = state_dict.get(JWSimState.SAVE_KEY_SCALARS, {})
	if scalars.has(id):
		scalars[id] = 0
		return true
	return false


## 试算情景：三类冲击按给定强度设定；未给强度的通道若已有冲击则按当前强度延续到试算期末；
## 试算期内不抽新的到达（真实到达属「本局未披露」）。返回是否设定成功。
func _ui_dry_apply_scenario(sh: JWSimState, shock_ppm: PackedInt64Array, n_q: int) -> bool:
	if sh.shocks == null:
		return false
	var shk: Object = sh.shocks
	var act_v: Variant = shk.get("active")
	var rem_v: Variant = shk.get("remaining_q")
	var mag_v: Variant = shk.get("magnitude_ppm")
	var dur_v: Variant = shk.get("duration_q")
	var mx_v: Variant = shk.get("max_active")
	if not (act_v is PackedInt64Array and rem_v is PackedInt64Array and mag_v is PackedInt64Array
			and dur_v is PackedInt64Array and mx_v is PackedInt64Array):
		return false
	var act: PackedInt64Array = act_v
	var rem: PackedInt64Array = rem_v
	var mag: PackedInt64Array = mag_v
	var dur: PackedInt64Array = dur_v
	var mx: PackedInt64Array = mx_v
	var hold: int = n_q + 1
	var k: int = 0
	while k < act.size():
		var ov: int = shock_ppm[k] if k < shock_ppm.size() else 0
		if ov != 0:
			if act[k] == 1:
				# 情景强度与已生效冲击取更不利的一侧（负向取小、正向取大）。
				mag[k] = mini(mag[k], ov) if ov < 0 else maxi(mag[k], ov)
			else:
				mag[k] = ov
			act[k] = 1
			dur[k] = hold
			rem[k] = hold
		elif act[k] == 1:
			dur[k] = hold
			rem[k] = hold
		mx[k] = 0
		k += 1
	shk.set("active", act)
	shk.set("remaining_q", rem)
	shk.set("magnitude_ppm", mag)
	shk.set("duration_q", dur)
	shk.set("max_active", mx)
	return true


## 每季末采集的财政与民生序列（键名是界面侧的序列名，值逐季追加）。
func _ui_dry_collect(sh: JWSimState, series: Dictionary) -> void:
	var cash_arr: PackedInt64Array = _ui_reg_array(sh, "account.balance")
	_ui_push(series, "cash_end", cash_arr[0] if cash_arr.size() > 0 else 0)
	var r_inc: int = _ui_reg_scalar(sh, "flow.gov.receipts_income_tax_uu")
	var r_pro: int = _ui_reg_scalar(sh, "flow.gov.receipts_profit_tax_uu")
	var r_oth: int = _ui_reg_scalar(sh, "flow.gov.receipts_other_uu")
	_ui_push(series, "receipts", r_inc + r_pro + r_oth)
	_ui_push(series, "receipts_income_tax", r_inc)
	_ui_push(series, "receipts_profit_tax", r_pro)
	_ui_push(series, "receipts_other", r_oth)
	_ui_push(series, "primary_paid", _ui_reg_scalar(sh, "flow.gov.primary_paid_uu"))
	_ui_push(series, "interest_paid", _ui_reg_scalar(sh, "flow.gov.interest_paid_uu"))
	_ui_push(series, "principal_paid", _ui_reg_scalar(sh, "flow.gov.principal_paid_uu"))
	_ui_push(series, "new_borrowing", _ui_reg_scalar(sh, "flow.gov.new_borrowing_uu"))
	_ui_push(series, "project_paid", _ui_sum(_ui_reg_array(sh, "flow.gov.pay_project_uu")))
	_ui_push(series, "opex_paid", _ui_sum(_ui_reg_array(sh, "flow.gov.pay_opex_uu")))
	_ui_push(series, "arrears", _ui_reg_scalar(sh, "state.gov.arrears_uu"))
	_ui_push(series, "committed", _ui_reg_scalar(sh, "state.gov.committed_memo_uu"))
	_ui_push(series, "opex_committed", _ui_reg_scalar(sh, "state.gov.service_opex_committed_uu"))
	var n_b: int = _ui_reg_scalar(sh, "state.bond.count")
	var out_b: PackedInt64Array = _ui_reg_array(sh, "state.bond.principal_outstanding_uu")
	var debt: int = 0
	var b: int = 0
	while b < n_b and b < out_b.size():
		debt += out_b[b]
		b += 1
	_ui_push(series, "debt", debt)
	var un: Variant = sh.diag.get("unemployment_ppm") if sh.diag != null else null
	_ui_push(series, "unemployment_ppm", int(un) if un is int else 0)
	var gr: Variant = sh.diag.get("gdp_real") if sh.diag != null else null
	_ui_push(series, "gdp_real", int(gr) if gr is int else 0)
	_ui_push(series, "q_settled", sh.q - 1)


## 逐组可支配收入（本季流量），与 JWPopulation.disposable_income 同口径：
## 工资 + 财产 + 转移 + 互助转入 − 互助转出 − 个税 − 公共服务收费。
func _ui_group_disposable(sh: JWSimState) -> PackedInt64Array:
	var plus: Array = [_ui_reg_array(sh, "flow.group.wage_income_uu"), _ui_reg_array(sh, "flow.group.property_income_uu"),
			_ui_reg_array(sh, "flow.group.transfer_income_uu"), _ui_reg_array(sh, "flow.group.support_in_uu")]
	var minus: Array = [_ui_reg_array(sh, "flow.group.support_out_uu"), _ui_reg_array(sh, "flow.group.income_tax_paid_uu"),
			_ui_reg_array(sh, "flow.group.fees_paid_uu")]
	var n: int = (plus[0] as PackedInt64Array).size()
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(n)
	var g: int = 0
	while g < n:
		var v: int = 0
		for a: Variant in plus:
			var pa: PackedInt64Array = a
			if g < pa.size():
				v += pa[g]
		for b: Variant in minus:
			var mb: PackedInt64Array = b
			if g < mb.size():
				v -= mb[g]
		out[g] = v
		g += 1
	return out


## 试算期内新增的债券批次或项目（第一季末读，逐行给出界面需要的列）。
func _ui_new_rows(sh: JWSimState, which: String, before: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if which == "bond":
		var n: int = _ui_reg_scalar(sh, "state.bond.count")
		var pi: PackedInt64Array = _ui_reg_array(sh, "state.bond.principal_initial_uu")
		var cp: PackedInt64Array = _ui_reg_array(sh, "state.bond.coupon_ppm_per_q")
		var mt: PackedInt64Array = _ui_reg_array(sh, "state.bond.maturity_q")
		var hd: PackedInt64Array = _ui_reg_array(sh, "state.bond.holder")
		var iq: PackedInt64Array = _ui_reg_array(sh, "state.bond.issue_q")
		var b: int = maxi(before, 0)
		while b < n and b < pi.size():
			rows.append({"principal_uu": pi[b], "coupon_ppm_per_q": cp[b], "maturity_q": mt[b],
					"holder": hd[b], "issue_q": iq[b]})
			b += 1
	elif which == "project":
		var m: int = _ui_reg_scalar(sh, "state.project.count")
		var pol: PackedInt64Array = _ui_reg_array(sh, "state.project.policy_idx")
		var reg: PackedInt64Array = _ui_reg_array(sh, "state.project.region_idx")
		var tot: PackedInt64Array = _ui_reg_array(sh, "state.project.total_cost_uu")
		var pq: PackedInt64Array = _ui_reg_array(sh, "state.project.planned_quarters")
		var opx: PackedInt64Array = _ui_reg_array(sh, "state.project.opex_per_q_uu")
		var cap: PackedInt64Array = _ui_reg_array(sh, "state.project.capacity_effect_uqs_per_q")
		var st: PackedInt64Array = _ui_reg_array(sh, "state.project.status")
		var p: int = maxi(before, 0)
		while p < m and p < pol.size():
			rows.append({"policy": pol[p], "region": reg[p], "total_cost_uu": tot[p],
					"planned_quarters": pq[p], "opex_per_q_uu": opx[p], "capacity_effect": cap[p],
					"status": st[p]})
			p += 1
	return rows


func _ui_code(st: JWSimState, id: String) -> int:
	if _ui_code_cache.has(id):
		return int(_ui_code_cache[id])
	var n: int = st.registry_size()
	var e: int = 0
	while e < n:
		if st.registry_id(e) == id:
			_ui_code_cache[id] = e
			return e
		e += 1
	_ui_code_cache[id] = -1
	return -1


func _ui_reg_scalar(st: JWSimState, id: String) -> int:
	var c: int = _ui_code(st, id)
	if c < 0:
		return 0
	return st.read_metric(c, 0)


func _ui_reg_array(st: JWSimState, id: String) -> PackedInt64Array:
	var c: int = _ui_code(st, id)
	if c < 0:
		return PackedInt64Array()
	return st.registry_array_copy(c)


static func _ui_packed_slice(obj: Object, field: String, n: int) -> PackedInt64Array:
	if obj == null:
		return PackedInt64Array()
	var v: Variant = obj.get(field)
	if not (v is PackedInt64Array):
		return PackedInt64Array()
	var a: PackedInt64Array = v
	return a.slice(0, mini(n, a.size()))


static func _ui_sum(a: PackedInt64Array) -> int:
	var s: int = 0
	for x: int in a:
		s += x
	return s


static func _ui_push(series: Dictionary, key: String, v: int) -> void:
	if not series.has(key):
		series[key] = PackedInt64Array()
	var a: PackedInt64Array = series[key]
	a.append(v)
	series[key] = a


static func _ui_int(v: Variant) -> int:
	if v is int:
		return v
	if v is float:
		return int(v)
	if v is String and (v as String).is_valid_int():
		return (v as String).to_int()
	return 0
