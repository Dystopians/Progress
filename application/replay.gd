## 命令流 + 冲击流重放。**同构建、同种子、同命令流 ⇒ 逐位相同的状态。**
## 它**不引用 `JWGame`**（避免环）：自己构造一份独立的 `JWSimState` 与 `JWTurnRunner`。
##
## 骨架依据：docs/17_api_skeleton.md §4.34（秩 A5；可引用秩 ≤10 与 A0..A4）。
class_name JWReplay
extends RefCounted


## 重放模式：**权威重放**（CI 用），只喂命令流，不读 state.json。
const COMMANDS_ONLY: int = 0

## 重放模式：正常读档（状态 + 命令流）。
const STATE_AND_COMMANDS: int = 1


## 当前模式（COMMANDS_ONLY / STATE_AND_COMMANDS）。
var mode: int = COMMANDS_ONLY

## 第一个哈希不匹配的季，−1 表示无分歧。
var divergence_q: int = -1

## 该季 8 个步骤哈希中第一个不匹配的步，−1 表示步骤内一致。
var divergence_step: int = -1

## 上一次 `run_to` / `verify` 跑出来的终态（调用方自行断言；签名只能返回 JWResult）。
var last_state: JWSimState = null

## 上一次重放实际跑到的季号（诊断用）。
var last_q: int = 0

## `diff_quarter` 复算 `log.rng` 时对不上的第一行，−1 表示全部对得上。
var rng_mismatch_row: int = -1


## 从 q=0 用 commands_only 重跑到存档的 q，逐季比对 checkpoints.jsonl 的 state_hash。
## 步骤：冷路径（CI 与调试）
## 前置：build_id 一致（不一致时 replay_unreliable 为 true，本函数直接返回「不承诺」）
## 后置：divergence_q / divergence_step 写好
## 不变量：INV-014、INV-133（save → load → advance 与 advance 的 state_hash 逐位相同，
##          `log.rng` 完全一致）
## 失败：不修改任何状态，只报告分歧季与分歧步骤；
##       8 个步骤哈希都一致而季末不一致 ⇒ 存在步骤之外的写入 ⇒ **直接报架构缺陷**
func verify(slot: String, loader: JWContentLoader) -> JWResult:
	divergence_q = -1
	divergence_step = -1
	rng_mismatch_row = -1
	last_state = null
	last_q = 0
	mode = COMMANDS_ONLY

	var dir: String = JWSaves.SAVES_ROOT + slot + "/"
	var man: Dictionary = {}
	var rc_man: JWResult = _read_json(dir + JWSaves.FILE_MANIFEST, man)
	if not rc_man.ok:
		return rc_man

	var ck_q: PackedInt64Array = PackedInt64Array()
	var ck_hash: PackedStringArray = PackedStringArray()
	var ck_steps: Array[PackedStringArray] = []
	var rc_ck: JWResult = _read_checkpoints(dir + JWSaves.FILE_CHECKPOINTS, ck_q, ck_hash,
			ck_steps)
	if not rc_ck.ok:
		return rc_ck
	if ck_q.is_empty():
		# 还没走完第一季的存档没有检查点：没有可比对的东西，不算分歧，也不算错。
		return JWResult.make_ok()

	var target_q: int = _int_of(man, JWSaves.MK_Q)
	var st: JWSimState = null
	var runner: JWTurnRunner = null
	var cmds: JWCommands = null
	var rc_boot: JWResult = _boot(dir, man, loader)
	if not rc_boot.ok:
		return rc_boot
	st = last_state
	runner = _last_runner
	cmds = _last_cmds

	var line: int = 0
	var q: int = 0
	while q < target_q:
		var code: int = runner.advance_quarter(cmds)
		last_q = q
		if code != JWResult.OK:
			# 重放跑不动本身就是分歧：报出季号与故障码，**不修改任何状态**。
			divergence_q = q
			return JWResult.make_err(code, q, JWResult.pending_step())
		while line < ck_q.size() and ck_q[line] < q:
			line += 1
		if line < ck_q.size() and ck_q[line] == q:
			if st.state_hash() != ck_hash[line]:
				divergence_q = q
				divergence_step = _first_step_mismatch(runner.step_hashes(), ck_steps[line])
				if divergence_step < 0:
					# 8 个步骤哈希全一致而季末哈希不一致 ⇒ 有人在八步之外写了状态。
					# 这不是数据分歧，是架构缺陷，必须与普通分歧区分开报。
					return JWResult.make_err(JWResult.Fault.WRITE_OUT_OF_SCOPE, q, -1)
				return JWResult.make_err(JWResult.Fault.PHASE_VIOLATION, q, divergence_step)
			line += 1
		q += 1
	last_q = target_q
	# R-REPLAY-01：重抽出的冲击日志必须与存档记录逐位相同（只比存档季之前的行）。
	var got: PackedInt64Array = st.shocks.export_shock_log()
	var cols: int = JWSaves.SHOCK_LOG_COLS
	var n_saved: int = JWMath.floor_div(_saved_shock_rows.size(), cols)
	var n_got: int = JWMath.floor_div(got.size(), cols)
	if n_saved != n_got:
		return JWResult.make_err(JWResult.Fault.RNG_LOG_MISMATCH, n_saved, n_got)
	var i2: int = 0
	while i2 < _saved_shock_rows.size():
		if _saved_shock_rows[i2] != got[i2]:
			divergence_q = int(got[i2 - (i2 % cols)])
			return JWResult.make_err(JWResult.Fault.RNG_LOG_MISMATCH, divergence_q, i2 % cols)
		i2 += 1
	return JWResult.make_ok()


## 二分定位：给定分歧季，重算该季任意一次抽样并对齐 log.rng。
## 步骤：冷路径
## 前置：verify 已定位到分歧季
## 后置：输出该季逐步骤哈希与 rng 抽样对照
## 不变量：INV-009（流隔离）、INV-010（可从任意季直接重算任意一次抽样）、INV-011
## 失败：无
func diff_quarter(slot: String, q: int, loader: JWContentLoader) -> JWResult:
	divergence_step = -1
	rng_mismatch_row = -1
	if q < 0:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, q, 0)

	var dir: String = JWSaves.SAVES_ROOT + slot + "/"
	var man: Dictionary = {}
	var rc_man: JWResult = _read_json(dir + JWSaves.FILE_MANIFEST, man)
	if not rc_man.ok:
		return rc_man

	var ck_q: PackedInt64Array = PackedInt64Array()
	var ck_hash: PackedStringArray = PackedStringArray()
	var ck_steps: Array[PackedStringArray] = []
	var rc_ck: JWResult = _read_checkpoints(dir + JWSaves.FILE_CHECKPOINTS, ck_q, ck_hash,
			ck_steps)
	if not rc_ck.ok:
		return rc_ck

	var rc_boot: JWResult = _boot(dir, man, loader)
	if not rc_boot.ok:
		return rc_boot
	var st: JWSimState = last_state
	var runner: JWTurnRunner = _last_runner
	var cmds: JWCommands = _last_cmds

	# 重跑到分歧季的前一季。
	var t: int = 0
	while t < q:
		var code: int = runner.advance_quarter(cmds)
		if code != JWResult.OK:
			return JWResult.make_err(code, t, JWResult.pending_step())
		t += 1

	var code_q: int = runner.advance_quarter(cmds)
	last_q = q
	if code_q != JWResult.OK:
		return JWResult.make_err(code_q, q, JWResult.pending_step())

	# 逐步骤哈希对照。
	var row: int = -1
	var i: int = 0
	while i < ck_q.size():
		if ck_q[i] == q:
			row = i
			break
		i += 1
	if row >= 0:
		divergence_step = _first_step_mismatch(runner.step_hashes(), ck_steps[row])

	# INV-010：从任意季直接重算任意一次抽样，与 log.rng 逐行对齐。
	# draw_raw 是纯函数（root_seed + salt + q + index），不推进计数器，因此复算不改状态。
	var rng: JWRngStreams = st.rng
	var rows: int = rng.log_row_count()
	var j: int = 0
	while j < rows:
		var stream: int = rng.log_stream[j]
		var index: int = rng.log_draw_index[j]
		if rng.draw_raw(stream, q, index) != rng.log_raw[j]:
			rng_mismatch_row = j
			return JWResult.make_err(JWResult.Fault.RNG_LOG_MISMATCH, q, j)
		j += 1

	if divergence_step >= 0:
		return JWResult.make_err(JWResult.Fault.PHASE_VIOLATION, q, divergence_step)
	return JWResult.make_ok()


## 纯重放一段命令流到指定季（压力测试与黄金存档回归用）。
## 步骤：冷路径
## 前置：内容包与参数包版本一致（否则同样进只读检视，M-9）
## 后置：返回终态的 JWSimState（调用方自行断言）
## 不变量：INV-133、INV-136（黄金存档跑「v1 → 当前」全链）
## 失败：任一季 Fault → 停在该季并返回故障码
##
## 「推进到第 N 季」本身就蕴含 N 条 `advance_quarter` 标记，因此本函数**按季自动补一条**
## （写进传入的 `cmds`，与 UI 每季点一次推进等价）；调用方只需提供业务命令。
func run_to(root_seed: int, cmds: JWCommands, target_q: int,
		loader: JWContentLoader) -> JWResult:
	divergence_q = -1
	divergence_step = -1
	last_state = null
	last_q = 0
	if cmds == null or loader == null or target_q < 0:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, target_q, 0)

	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var res: JWResult = loader.load_all(loader.root_path(), st)
	if res == null or not res.ok:
		return res if res != null else JWResult.make_err(JWResult.Load.FILE_FORMAT, 0, 0)
	# build_id 不写：本类是秩 A5，**不得引用 JWGame（A6）**（否则 A5↔A6 成环，见文件头）。
	# 它也不进 state_hash（docs/17 §6.1 的排除清单），因此留空不影响 INV-133 的逐位比对；
	# 需要它的调用方在拿到 last_state 之后自行填。
	st.content_hash = loader.content_hash
	st.param_set_version = loader.param_set_version
	var rc_seed: int = st.rng.set_state_scalar(0, root_seed)
	if rc_seed != JWResult.OK:
		return JWResult.make_err(rc_seed, root_seed, 0)

	var events: JWEventEngine = JWEventEngine.new()
	events.allocate()
	# R-EVENT-01：与开局同一套事件卡，否则重放与原局在第一次事件触发处分叉。
	var rev: JWResult = loader.load_events_into(events, st)
	if rev == null or not rev.ok:
		return rev if rev != null else JWResult.make_err(JWResult.Load.EVENT_COUNT, 0, 0)
	var runner: JWTurnRunner = JWTurnRunner.new(st, events)
	last_state = st
	_last_runner = runner
	_last_cmds = cmds

	var marker: PackedInt64Array = PackedInt64Array()
	marker.resize(JWCommands.ARG_SLOTS)
	marker.fill(0)
	var q: int = 0
	while q < target_q:
		if cmds.check_advance_marker(st.q) != JWResult.OK:
			var rs: JWResult = cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, marker, st.q,
					st.policy_defs)
			if rs == null or not rs.ok:
				return rs if rs != null else JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
		var code: int = runner.advance_quarter(cmds)
		last_q = st.q
		if code != JWResult.OK:
			divergence_q = q
			return JWResult.make_err(code, q, JWResult.pending_step())
		q += 1
	last_q = st.q
	return JWResult.make_ok()


# ── 内部实现（全部冷路径；本类不进状态、不进哈希） ─────────────────────────

## R-REPLAY-01：存档里的冲击记录（扁平 7 列），重放结束后与重抽出的记录逐行比对。
var _saved_shock_rows: PackedInt64Array = PackedInt64Array()

## 上一次装配出来的回合驱动与命令缓冲（verify / diff_quarter 共用 _boot）。
var _last_runner: JWTurnRunner = null
var _last_cmds: JWCommands = null


## 从存档目录装配一份**独立的**权威重放栈（不读 state.json，INV-133 的权威口径）。
## 步骤：冷路径
## 前置：manifest 已解析
## 后置：last_state / _last_runner / _last_cmds 就位，q == 0
## 不变量：INV-109（先查 shock_log 再抽样，读档不重抽）、INV-131
## 失败：内容包载入失败 → 转发加载器的 JWResult
func _boot(dir: String, man: Dictionary, loader: JWContentLoader) -> JWResult:
	if loader == null:
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 0, 0)
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var horizon: int = _int_of(man, JWSaves.MK_HORIZON_Q)
	if horizon > 0:
		st.horizon_q = horizon
	var res: JWResult = loader.load_all(loader.root_path(), st)
	if res == null or not res.ok:
		return res if res != null else JWResult.make_err(JWResult.Load.FILE_FORMAT, 0, 0)
	st.build_id = String(man.get(JWSaves.MK_BUILD_ID, ""))
	st.content_hash = loader.content_hash
	st.param_set_version = loader.param_set_version
	var rc_seed: int = st.rng.set_state_scalar(0, _int_of(man, JWSaves.MK_ROOT_SEED))
	if rc_seed != JWResult.OK:
		return JWResult.make_err(rc_seed, 0, 0)

	# 冲击流（R-REPLAY-01）：权威重放从 q = 0 起跑，**不**把存档里的冲击记录预先灌回去，
	# 而是让 S01 用同一根种子重新抽——rng.shock 按 (种子, 季, 序号) 取值、与其它流隔离（INV-009），
	# 重抽结果逐位相同。预灌会让「先查后抽」在冲击季复用记录、rng.shock 少推进到达 + 强度 + 持续期
	# 那几次，计数器与原局不同，冲击季的 S01 哈希必然分歧（实测第 14 季）。
	# 存档记录改作对照：重放结束后逐行比对重抽出的冲击日志（见 verify）。
	_saved_shock_rows = PackedInt64Array()
	var rc_sl: JWResult = _read_shock_log(dir + JWSaves.FILE_SHOCK_LOG, _saved_shock_rows)
	if not rc_sl.ok:
		return rc_sl

	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	var rc_cmd: JWResult = cmds.load_jsonl(dir + JWSaves.FILE_COMMANDS, loader.ids())
	if rc_cmd != null and not rc_cmd.ok:
		return rc_cmd

	var events: JWEventEngine = JWEventEngine.new()
	events.allocate()
	var rev2: JWResult = loader.load_events_into(events, st)
	if rev2 == null or not rev2.ok:
		return rev2 if rev2 != null else JWResult.make_err(JWResult.Load.EVENT_COUNT, 0, 0)
	JWResult.clear_pending()
	last_state = st
	_last_runner = JWTurnRunner.new(st, events)
	_last_cmds = cmds
	return JWResult.make_ok()


## 逐步骤哈希对照，返回第一个不等的步号（1..8），全等返回 −1。
## 步骤：冷路径
## 前置：两侧都是 8 个哈希（缺项按不等处理）
## 后置：不改状态
## 不变量：INV-014
## 失败：无
func _first_step_mismatch(got: PackedStringArray, want: PackedStringArray) -> int:
	var n: int = JWSaves.STEP_HASH_N
	var i: int = 0
	while i < n:
		var a: String = got[i] if i < got.size() else ""
		var b: String = want[i] if i < want.size() else ""
		if a != b:
			return i + 1
		i += 1
	return -1


## 读一个 JSON 对象文件。
## 步骤：冷路径
## 前置：无
## 后置：out_d 被填满；不改任何状态
## 不变量：docs/11 §6.3
## 失败：Load.FILE_FORMAT
func _read_json(path: String, out_d: Dictionary) -> JWResult:
	if not FileAccess.file_exists(path):
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 0, 0)
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, parser.get_error_line(), 0)
	if typeof(parser.data) != TYPE_DICTIONARY:
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, typeof(parser.data), 0)
	var d: Dictionary = parser.data
	for k: Variant in d.keys():
		out_d[k] = d[k]
	return JWResult.make_ok()


## 读 checkpoints.jsonl（每季一行 {q, state_hash, step_hash[8]}）。
## 步骤：冷路径
## 前置：无
## 后置：三个出参等长且按文件行序；不改任何状态
## 不变量：INV-014
## 失败：格式不符 → Load.SAVE_CORRUPT
func _read_checkpoints(path: String, out_q: PackedInt64Array, out_hash: PackedStringArray,
		out_steps: Array[PackedStringArray]) -> JWResult:
	out_q.clear()
	out_hash.clear()
	out_steps.clear()
	if not FileAccess.file_exists(path):
		return JWResult.make_ok()
	var text: String = FileAccess.get_file_as_string(path)
	var lines: PackedStringArray = text.split("\n", false)
	var i: int = 0
	while i < lines.size():
		var s: String = lines[i].strip_edges()
		if s == "":
			i += 1
			continue
		var parser: JSON = JSON.new()
		if parser.parse(s) != OK or typeof(parser.data) != TYPE_DICTIONARY:
			return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, i, 0)
		var d: Dictionary = parser.data
		out_q.append(_int_of(d, JWSaves.CK_Q))
		out_hash.append(String(d.get(JWSaves.CK_STATE_HASH, "")))
		var steps: PackedStringArray = PackedStringArray()
		var raw: Variant = d.get(JWSaves.CK_STEP_HASH, [])
		if typeof(raw) == TYPE_ARRAY:
			var arr: Array = raw
			var j: int = 0
			while j < arr.size():
				steps.append(String(arr[j]))
				j += 1
		out_steps.append(steps)
		i += 1
	return JWResult.make_ok()


## 读 shock_log.jsonl，摊平成 JWShocks.load_shock_log 要的 7 列整数行。
## 步骤：冷路径
## 前置：无
## 后置：out_rows 长度是 7 的整数倍；不改任何状态
## 不变量：INV-109
## 失败：格式不符 → Load.SHOCK_LOG
func _read_shock_log(path: String, out_rows: PackedInt64Array) -> JWResult:
	out_rows.clear()
	if not FileAccess.file_exists(path):
		return JWResult.make_ok()
	var text: String = FileAccess.get_file_as_string(path)
	var lines: PackedStringArray = text.split("\n", false)
	var i: int = 0
	while i < lines.size():
		var s: String = lines[i].strip_edges()
		if s == "":
			i += 1
			continue
		var parser: JSON = JSON.new()
		if parser.parse(s) != OK or typeof(parser.data) != TYPE_DICTIONARY:
			return JWResult.make_err(JWResult.Load.SHOCK_LOG, i, 0)
		var d: Dictionary = parser.data
		var c: int = 0
		while c < JWSaves.SHOCK_LOG_COLS:
			out_rows.append(_int_of(d, JWSaves.SL_KEYS[c]))
			c += 1
		i += 1
	return JWResult.make_ok()


## 从字典取一个整数（int 与十进制字符串两种形态都认，与 JWSimState._variant_to_int 同口径）。
## 步骤：冷路径
## 前置：无
## 后置：不改状态
## 不变量：INV-001（不让 float 混进整数状态）
## 失败：取不到 → 返回 0
func _int_of(d: Dictionary, key: String) -> int:
	if not d.has(key):
		return 0
	var v: Variant = d[key]
	var t: int = typeof(v)
	if t == TYPE_INT:
		return int(v)
	if t == TYPE_STRING or t == TYPE_STRING_NAME:
		return String(v).to_int()
	if t == TYPE_FLOAT:
		# Godot 的 JSON 解析把**所有**数字都读成 double（包括写盘时的整数）。
		# 与 JWSaves._float_to_int 同一口径：整值且在 JSON 安全整数范围内（|n| ≤ 2^53 − 1）即精确还原；
		# 超出范围或带小数才是真正的丢精度——登记故障、返回 0，不四舍五入。
		# （原实现对一切 double 都返回 0：manifest 的目标季读成 0，verify 从不比对任何检查点，
		# 冲击记录的 duration 读成 0 即被判坏档。）
		var f: float = v
		var n: int = int(f)
		if float(n) == f and n <= JWSaves.JSON_SAFE_INT_MAX and n >= -JWSaves.JSON_SAFE_INT_MAX:
			return n
		JWResult.raise_fault(JWResult.Fault.FLOAT_IN_STATE, 0, 0)
		return 0
	return 0
