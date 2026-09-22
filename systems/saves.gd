## 存档目录的读写、`manifest.json`、`state.json`、`commands.jsonl`、
## `checkpoints.jsonl`、`shock_log.jsonl`，以及版本迁移链。
##
## 骨架依据：docs/17_api_skeleton.md §4.32 与 §6.3/§6.4（秩 A4；可引用秩 ≤10、A0、A1）。
class_name JWSaves
extends RefCounted


## 状态形状版本，**单调整数**，迁移链的唯一依据。对应 docs/17 顶部的 skeleton_revision: 1。
const CURRENT_SCHEMA_VERSION: int = 2

## 大数组编码标识：`PackedInt64Array.to_byte_array()` 的 Base64（小端、每元素 8 字节）。
## **不用 `var_to_bytes()`**（其布局是引擎内部表示，跨版本不承诺，docs/17 §6.4）。
const ENC_B64LE64: String = "b64le64"

# ── 目录与文件名（docs/11 §6.2） ───────────────────────────────────────────

## 全部存档槽位的根目录。
const SAVES_ROOT: String = "user://saves/"
const FILE_MANIFEST: String = "manifest.json"
const FILE_STATE: String = "state.json"
const FILE_COMMANDS: String = "commands.jsonl"
const FILE_CHECKPOINTS: String = "checkpoints.jsonl"
const FILE_SHOCK_LOG: String = "shock_log.jsonl"

## 原子改名用的临时目录与回滚目录后缀（先写临时目录再改名，**不留半个存档**）。
const TMP_SUFFIX: String = ".tmp"
const BAK_SUFFIX: String = ".bak"

# ── manifest.json 的字段名（docs/11 §6.3，值不得改：进存档） ───────────────

const MK_SCHEMA_KIND: String = "schema_kind"
const MK_SCHEMA_VERSION: String = "schema_version"
const MK_CREATED_UTC: String = "created_utc"
const MK_BUILD_ID: String = "build_id"
const MK_SCENARIO_ID: String = "scenario_id"
const MK_SCENARIO_HASH: String = "scenario_hash"
const MK_CONTENT_HASH: String = "content_hash"
const MK_PARAM_SET_VERSION: String = "param_set_version"
const MK_ROOT_SEED: String = "root_seed"
const MK_HORIZON_Q: String = "horizon_q"
const MK_Q: String = "q"
const MK_STATE_HASH: String = "state_hash"
const MK_COMMAND_COUNT: String = "command_count"
const MK_COMMAND_LOG_HASH: String = "command_log_hash"
const MK_DRAW_COUNT: String = "draw_count"
const MK_REPLAY_MODE: String = "replay_mode"

## manifest 的 `schema_kind`（docs/11 §6.3 首行）。
const SCHEMA_KIND_MANIFEST: String = "save_manifest"

## 默认重放模式（docs/11 §6.5）。
const REPLAY_MODE_DEFAULT: String = "state+commands"

# ── checkpoints.jsonl / shock_log.jsonl 的字段名 ──────────────────────────

const CK_Q: String = "q"
const CK_STATE_HASH: String = "state_hash"
const CK_STEP_HASH: String = "step_hash"

## 一季 8 个步骤哈希（docs/12 八步结算合同）。
const STEP_HASH_N: int = 8

## shock_log 的 7 列，顺序即 `JWShocks.export_shock_log()` 的行内列序（docs/17 §4.30）。
const SL_KEYS: PackedStringArray = [
	"q", "kind", "mag", "dur", "draw_index", "raw", "mapped",
]
const SHOCK_LOG_COLS: int = 7

# ── 迁移链记录（docs/11 §6.7 M-3） ────────────────────────────────────────

## 迁移追溯键：{schema_version: 原版本, state_hash: 原哈希}。
const MIGRATED_FROM: String = "migrated_from"

## JSON 能精确表示的整数上界（2^53）。超界的整数改写十进制**字符串**，
## 两种形态读回时都认。口径与 `JWSimState.JSON_SAFE_INT_MAX` 一致。
const JSON_SAFE_INT_MAX: int = 1 << 53


## `user://saves/<slot>/`。
var slot_path: String = ""

## 逐版迁移函数链（`Dictionary → Dictionary` 的纯函数，**不允许跳版**）。
## 下标语义：`migrations[v]` 把 v 版升到 v+1 版。长度应为 `CURRENT_SCHEMA_VERSION`。
var migrations: Array[Callable] = []


func _init() -> void:
	# 下标 0 没有「0 → 1」（首版就是 1）；下标 1 是四百年重构的第一次形状变更。
	migrations = [Callable(), _mig_v1_to_v2]


## v1 → v2（R-SCENARIO-01 / R-CLOCK-01）：新增 `state.meta.mode` 与 `state.time.start_year`。
## v1 存档只可能来自单届剧本 chengwan：mode 取「单届」、start_year 取 0（不显示公历年份），
## 两者的语义就是「旧剧本」，不属于 M-5 禁止的「用 0 冒充缺失值」。
## M1 期间尚未发布 v2，M1 后续的形状变更继续并入本函数，不另起版本。
func _mig_v1_to_v2(src: Dictionary) -> Dictionary:
	var out: Dictionary = src.duplicate(true)
	var sc: Dictionary = out.get(JWSimState.SAVE_KEY_SCALARS, {})
	sc["state.meta.mode"] = JWUnits.Mode.TERM
	sc["state.time.start_year"] = 0
	# R-MONEY-01：旧剧本不发行货币（累计 0）；价格水平与目标水平取基年 1e6（旧剧本不用它们定上下限，每季 S07 重算）。
	sc["state.money.issued_total_uu"] = 0
	sc["state.money.price_level_ppm"] = JWUnits.PPM
	sc["state.money.target_level_ppm"] = JWUnits.PPM
	sc["flow.gov.money_issued_uu"] = 0
	out[JWSimState.SAVE_KEY_SCALARS] = sc
	var ar: Dictionary = out.get(JWSimState.SAVE_KEY_ARRAYS, {})
	var ring: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
	ar["state.money.real_gdp_ring_uu"] = {JWSimState.SAVE_KEY_N: ring.size(),
			JWSimState.SAVE_KEY_ENC: JWSimState.ENC_B64LE64,
			JWSimState.SAVE_KEY_DATA: Marshalls.raw_to_base64(ring.to_byte_array())}
	out[JWSimState.SAVE_KEY_ARRAYS] = ar
	return out

# ── 上一次 load() 的判定结果（INV-134 的两半，供 JWGame 决定运行模式） ─────
#
# 这两个不是状态，是**读档判定的输出**：契约要求 content_hash 不符进只读检视、
# build_id 不符置 replay_unreliable，而 JWResult 只能表达「成功/失败」一位信息。
# 若把它们塞进 JWResult 的 detail 整数槽，调用方必须靠位掩码解码，比显式布尔更易错。

## `content_hash` 或 `param_set_version` 不符 ⇒ 只读检视模式（可看不可推进，INV-134）。
var read_only_required: bool = false

## `build_id` 不符 ⇒ 禁用重放验证但**仍可继续游玩**（INV-134）。同步写入 `st.replay_unreliable`。
var replay_unreliable: bool = false

## 上一次 load() 复算出的 `state_hash`（诊断用；与 manifest 的比对已在 load 内完成）。
var last_state_hash: String = ""

## 命令流比快照多出的条数。自动保存只追加 jsonl、不重写 state.json（docs/11 §6.2），
## 因此这是**设计内的正常情形**，不是损坏。
var commands_ahead: int = 0

## 剧本哈希。`save()` 的签名里没有 JWContentLoader，由应用层在 load_all() 之后注入。
## 为空表示未注入，manifest 里照实写空串（不编造）。
var scenario_hash: String = ""

# ── 追加写游标（自动保存 O(1) 的前提，docs/11 §6.2） ──────────────────────

## commands.jsonl 已落盘的行数；-1 表示未知（需回读一次文件重建）。
var _commands_on_disk: int = -1

## shock_log.jsonl 已落盘的行数；-1 表示未知。
var _shock_rows_on_disk: int = -1

## `_read_int` 的越界/类型错误标志（冷路径，避免为每次取字段分配出参数组）。
var _field_err: bool = false


## 写存档（目录形态）。
## 步骤：任意（冷路径）
## 前置：phase == IDLE
## 后置：manifest.json / state.json / commands.jsonl / checkpoints.jsonl / shock_log.jsonl 齐全；
##       大数组以 `enc: "b64le64"`（PackedInt64Array.to_byte_array() 的 Base64）编码
## 不变量：INV-131（存档含全部跨季状态 + root_seed + 6 个计数器 + 完整命令流，含被拒命令）；
##          **不用 var_to_bytes()**（其布局是引擎内部表示，跨版本不承诺）
## 失败：写盘失败 → JWResult(Load.FILE_FORMAT)，**不留半个存档**（先写临时目录再原子改名）
##
## checkpoints.jsonl 是**唯一不在内存里的文件**（历史逐季一行，只追加）。
## 因此本函数把旧槽位的该文件整份搬运到临时目录，而不是重建它 ——
## 重建等于凭空编造历史哈希，正是 INV-014 二分定位要防的事。
func save(st: JWSimState, cmds: JWCommands, slot: String) -> JWResult:
	if st == null or cmds == null:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	if st.phase != JWUnits.Phase.IDLE:
		return JWResult.make_err(JWResult.Reject.PHASE_BUSY, st.phase, JWUnits.Phase.IDLE)
	if not _slot_name_ok(slot):
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 0, 0)

	var dst: String = _slot_dir(slot)
	var tmp: String = SAVES_ROOT + slot + TMP_SUFFIX + "/"
	var bak: String = SAVES_ROOT + slot + BAK_SUFFIX + "/"

	# 残留的临时目录一律先清掉：上次写盘中途崩溃留下的半个存档不得混入本次。
	_rm_recursive(tmp)
	_rm_recursive(bak)
	if DirAccess.make_dir_recursive_absolute(tmp) != OK:
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 0, 0)

	# 1) state.json —— 大数组走 ENC_B64LE64，由 JWSimState.to_dict() 保证（docs/11 §6.4）。
	var sdict: Dictionary = st.to_dict()
	if not _write_json(tmp + FILE_STATE, sdict):
		_rm_recursive(tmp)
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 1, 0)

	# 2) commands.jsonl —— 自开局起全量，含被拒命令（INV-131）。
	if not _write_text(tmp + FILE_COMMANDS, ""):
		_rm_recursive(tmp)
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 2, 0)
	var i: int = 0
	while i < cmds.count:
		var rc: JWResult = cmds.append_jsonl(tmp + FILE_COMMANDS, i)
		if rc == null or not rc.ok:
			_rm_recursive(tmp)
			return JWResult.make_err(JWResult.Load.FILE_FORMAT, 2, i)
		i += 1

	# 3) checkpoints.jsonl —— 从旧槽位整份搬运（没有旧档则是空文件）。
	var old_ck: String = ""
	if FileAccess.file_exists(dst + FILE_CHECKPOINTS):
		old_ck = FileAccess.get_file_as_string(dst + FILE_CHECKPOINTS)
	if not _write_text(tmp + FILE_CHECKPOINTS, old_ck):
		_rm_recursive(tmp)
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 3, 0)

	# 4) shock_log.jsonl —— 与命令流分开存储（docs/11 §6.1 规则 7）。
	var rows: PackedInt64Array = PackedInt64Array()
	if st.shocks != null:
		rows = st.shocks.export_shock_log()
	if rows.size() % SHOCK_LOG_COLS != 0:
		_rm_recursive(tmp)
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 4, rows.size())
	var shock_rows: int = JWMath.floor_div(rows.size(), SHOCK_LOG_COLS)
	if not _write_text(tmp + FILE_SHOCK_LOG, _shock_log_text(rows)):
		_rm_recursive(tmp)
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 4, 0)

	# 5) manifest.json —— 最后写：它是「这份存档已完整」的标记。
	if not _write_json(tmp + FILE_MANIFEST, _build_manifest(st, cmds)):
		_rm_recursive(tmp)
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 5, 0)

	# 6) 原子改名。旧档先改名成 .bak，新档就位后才删 .bak；中途失败回滚。
	var had_old: bool = DirAccess.dir_exists_absolute(dst)
	if had_old:
		if DirAccess.rename_absolute(dst, bak) != OK:
			_rm_recursive(tmp)
			return JWResult.make_err(JWResult.Load.FILE_FORMAT, 6, 0)
	if DirAccess.rename_absolute(tmp, dst) != OK:
		if had_old:
			DirAccess.rename_absolute(bak, dst)
		_rm_recursive(tmp)
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 6, 1)
	if had_old:
		_rm_recursive(bak)

	slot_path = dst
	_commands_on_disk = cmds.count
	_shock_rows_on_disk = shock_rows
	return JWResult.make_ok()


## 自动保存：追加 commands.jsonl 与 checkpoints.jsonl 尾行（O(1)，单次 < 1 KB）。
## 步骤：每季末
## 前置：本季已结算完成
## 后置：不重写 state.json
## 不变量：INV-131；docs/11 §6.2 的工程理由
## 失败：同 save
##
## checkpoints.jsonl 的尾行由 `append_checkpoint()` 单独写（它才拿得到 8 个步骤哈希）。
## 本函数负责的是**命令流与冲击记录**这两条只增不改的流：把内存里比磁盘多出来的行补上。
## 追加游标存在成员里，所以正常路径不回读文件，单次开销与新增行数成正比而与档案大小无关。
func autosave_append(st: JWSimState, cmds: JWCommands, slot: String) -> JWResult:
	if st == null or cmds == null:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	if st.phase != JWUnits.Phase.IDLE:
		return JWResult.make_err(JWResult.Reject.PHASE_BUSY, st.phase, JWUnits.Phase.IDLE)
	if not _slot_name_ok(slot):
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 0, 0)

	var dir: String = _slot_dir(slot)
	# 自动保存只追加，不创建槽位：没有 manifest 就没有可追加的存档，
	# 硬造一个只有命令流的目录就是「半个存档」。
	if not FileAccess.file_exists(dir + FILE_MANIFEST):
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 1, 0)

	if _commands_on_disk < 0:
		_commands_on_disk = _count_lines(dir + FILE_COMMANDS)
	if _shock_rows_on_disk < 0:
		_shock_rows_on_disk = _count_lines(dir + FILE_SHOCK_LOG)

	if cmds.count < _commands_on_disk:
		# 命令流只增不减；变短说明磁盘与内存不是同一局。
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, cmds.count, _commands_on_disk)
	var i: int = _commands_on_disk
	while i < cmds.count:
		var rc: JWResult = cmds.append_jsonl(dir + FILE_COMMANDS, i)
		if rc == null or not rc.ok:
			_commands_on_disk = i
			return JWResult.make_err(JWResult.Load.FILE_FORMAT, 2, i)
		i += 1
	_commands_on_disk = cmds.count

	var rows: PackedInt64Array = PackedInt64Array()
	if st.shocks != null:
		rows = st.shocks.export_shock_log()
	if rows.size() % SHOCK_LOG_COLS != 0:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 4, rows.size())
	var have: int = JWMath.floor_div(rows.size(), SHOCK_LOG_COLS)
	if have < _shock_rows_on_disk:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, have, _shock_rows_on_disk)
	if have > _shock_rows_on_disk:
		var tail: PackedStringArray = PackedStringArray()
		var r: int = _shock_rows_on_disk
		while r < have:
			tail.append(_shock_log_line(rows, r * SHOCK_LOG_COLS))
			r += 1
		if not _append_lines(dir + FILE_SHOCK_LOG, tail):
			return JWResult.make_err(JWResult.Load.FILE_FORMAT, 4, _shock_rows_on_disk)
		_shock_rows_on_disk = have

	slot_path = dir
	return JWResult.make_ok()


## 只读 manifest 里的剧本 ID（R-SCENARIO-01：读档前先按它装配对应剧本的内容包）。
## 读不到返回空串，由后续 load() 报具体错误。
func peek_scenario_id(slot: String) -> String:
	if not _slot_name_ok(slot):
		return ""
	var man: Dictionary = {}
	var rm: JWResult = _read_json_dict(_slot_dir(slot) + FILE_MANIFEST, man)
	if not rm.ok:
		return ""
	return String(man.get(MK_SCENARIO_ID, ""))


## 读档（顺序固定，docs/11 §6.6）。
## 步骤：LOAD
## 前置：目录存在
## 后置：解析 manifest → schema_version 检查 → 迁移链 → 解析各文件 →
##       **重算 state_hash 并比对** → content_hash / param_set_version 比对 →
##       build_id 比对 → 立即跑一遍全部 P0 不变量
## 不变量：INV-132（不符即 E_SAVE_CORRUPT，**拒绝加载，不做尽力修复**）、
##          INV-134（content_hash 不符 ⇒ 只读检视模式；build_id 不符 ⇒ replay_unreliable 但可继续玩）、
##          INV-135（schema_version 高于上限 ⇒ 拒绝，不猜测）
## 失败：Load.SAVE_CORRUPT / SAVE_VERSION_TOO_NEW / MIGRATION_MISSING
##
## 五个文件**全部先解析成 Variant，一个都不落地**，然后才开始写状态。
## 这样「任一步不符即拒绝加载」才真的能做到不留半截状态：
## 解析阶段失败时 `st` 还没被碰过。
func load(slot: String, st: JWSimState, cmds: JWCommands, loader: JWContentLoader) -> JWResult:
	read_only_required = false
	replay_unreliable = false
	last_state_hash = ""
	commands_ahead = 0
	_commands_on_disk = -1
	_shock_rows_on_disk = -1

	if st == null or cmds == null:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	if not _slot_name_ok(slot):
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 0, 0)
	var dir: String = _slot_dir(slot)
	if not DirAccess.dir_exists_absolute(dir):
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 1, 0)

	# ── 1 解析 manifest ────────────────────────────────────────────────
	var man: Dictionary = {}
	var rm: JWResult = _read_json_dict(dir + FILE_MANIFEST, man)
	if not rm.ok:
		return rm
	if String(man.get(MK_SCHEMA_KIND, "")) != SCHEMA_KIND_MANIFEST:
		return JWResult.make_err(JWResult.Load.SCHEMA_HEADER, 0, 0)

	# ── 2 schema_version 检查（高于上限即拒绝，不猜测，INV-135） ────────
	var sv: int = _read_int(man, MK_SCHEMA_VERSION)
	if _field_err:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	if sv > CURRENT_SCHEMA_VERSION:
		return JWResult.make_err(JWResult.Load.SAVE_VERSION_TOO_NEW, sv, CURRENT_SCHEMA_VERSION)
	if sv < 0:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, sv, 0)

	# ── 3 解析 state.json / commands / checkpoints / shock_log ──────────
	var sdict: Dictionary = {}
	var rs: JWResult = _read_json_dict(dir + FILE_STATE, sdict)
	if not rs.ok:
		return rs
	var shock_rows: PackedInt64Array = PackedInt64Array()
	var rsl: JWResult = _parse_shock_log(dir + FILE_SHOCK_LOG, shock_rows)
	if not rsl.ok:
		return rsl
	var ck_lines: int = 0
	var rck: JWResult = _verify_checkpoints(dir + FILE_CHECKPOINTS)
	if not rck.ok:
		return rck
	ck_lines = rck.detail_a

	# ── 4 迁移链（逐版递增，不跳版；必须在写状态之前） ───────────────────
	var migrated: bool = sv < CURRENT_SCHEMA_VERSION
	if migrated:
		var rmg: JWResult = migrate(sdict, sv)
		if not rmg.ok:
			return rmg
		# M-3：保留原哈希便于追溯。migrate() 拿不到 manifest，这一半在这里补齐。
		var mf: Dictionary = sdict.get(MIGRATED_FROM, {})
		mf[MK_STATE_HASH] = String(man.get(MK_STATE_HASH, ""))
		sdict[MIGRATED_FROM] = mf

	# 落地之前先记下**正在运行的这一份**的身份，from_dict 会用档内值覆盖它们。
	var live_build: String = st.build_id
	var live_content: String = st.content_hash
	var live_param: int = st.param_set_version
	if loader != null:
		if loader.content_hash != "":
			live_content = loader.content_hash
		if loader.param_set_version != 0:
			live_param = loader.param_set_version

	# ── 5 写入状态 ──────────────────────────────────────────────────────
	var rf: JWResult = st.from_dict(sdict)
	if not rf.ok:
		return rf

	# ── 6 重算 state_hash 并比对（不符即拒绝，不做尽力修复，INV-132） ────
	var got: String = st.state_hash()
	last_state_hash = got
	if migrated:
		# 迁移改了状态形状，档内哈希描述的是**旧形状**，无法与新哈希比较。
		# 契约对此的处置是 M-3「迁移后重算 state_hash 写回 + 保留 migrated_from」，
		# 而不是拿新旧哈希硬比 —— 硬比必然误判为损坏。
		pass
	elif got != String(man.get(MK_STATE_HASH, "")):
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)

	# ── 7 随机流的 7 个数：manifest 与 state.json 必须一致（docs/17 §6.2）──
	var rr: JWResult = _verify_rng(man, st)
	if not rr.ok:
		return rr

	# ── 8 命令流与冲击记录落地 ──────────────────────────────────────────
	var rc: JWResult = cmds.load_jsonl(dir + FILE_COMMANDS, null)
	if rc == null or not rc.ok:
		return rc if rc != null else JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	var want_cmds: int = _read_int(man, MK_COMMAND_COUNT)
	if _field_err:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	if cmds.count < want_cmds:
		# 命令流比快照还短 ⇒ 丢了命令，重放不可能复现（INV-131）。
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, cmds.count, want_cmds)
	commands_ahead = cmds.count - want_cmds
	if commands_ahead == 0:
		# 只有在条数一致时，全量命令流哈希才与 manifest 登记的是同一个对象。
		var want_hash: String = String(man.get(MK_COMMAND_LOG_HASH, ""))
		if want_hash != "" and cmds.command_log_hash() != want_hash:
			return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, cmds.count, want_cmds)
	if st.shocks != null:
		var rsh: JWResult = st.shocks.load_shock_log(shock_rows)
		if rsh == null or not rsh.ok:
			return rsh if rsh != null else JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)

	# ── 9 content_hash / param_set_version 比对（不符 ⇒ 只读检视，INV-134）─
	var arc_content: String = String(man.get(MK_CONTENT_HASH, ""))
	var arc_param: int = _read_int(man, MK_PARAM_SET_VERSION)
	if _field_err:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	if live_content == "":
		# 当前会话算不出 content_hash 就无从证明内容包没漂移。
		# 无法证明时按不符处理（只读检视），而不是假定相符 —— 后者是静默放行。
		read_only_required = arc_content != ""
	elif arc_content != live_content:
		read_only_required = true
	if arc_param != live_param:
		read_only_required = true
	# state.meta.content_hash / param_set_version 描述的是**内存里这一份内容包**，
	# 不是档内那一份；档内值已经在 read_only_required 里表达了。
	st.content_hash = live_content
	st.param_set_version = live_param

	# ── 10 build_id 比对（不符 ⇒ replay_unreliable，但仍可继续游玩，INV-134）─
	var arc_build: String = String(man.get(MK_BUILD_ID, ""))
	replay_unreliable = arc_build != live_build
	st.build_id = live_build
	st.replay_unreliable = replay_unreliable

	# ── 11 立即跑一遍全部 P0 不变量（坏档当场发现，不等到第 30 季） ───────
	#    先由存档里的上季流量反推私有基准（与原进程 S07 入口快照逐位相同）。
	var fl: int = st.finalize_load()
	if fl != JWResult.OK:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, fl, ck_lines)
	var p0: int = st.check_all_p0()
	if p0 != JWResult.OK:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, p0, ck_lines)

	slot_path = dir
	_commands_on_disk = cmds.count
	_shock_rows_on_disk = JWMath.floor_div(shock_rows.size(), SHOCK_LOG_COLS)
	return JWResult.make_ok()


## 迁移链（逐版递增，不跳版；每个迁移是纯函数，不碰磁盘）。
## 步骤：LOAD
## 前置：from_version < CURRENT_SCHEMA_VERSION
## 后置：升到当前版本；重算 state_hash 写回；保留 migrated_from（原版本 + 原哈希）
## 不变量：INV-136（有序纯函数链；**缺失字段禁止用 0 填充**除非语义就是「无」；
##          部门／地区／群组集合变化 ⇒ 明确拒绝）
## 失败：缺少某一版的迁移函数 → Load.MIGRATION_MISSING
##
## 结果写回 `src` 本身（GDScript 的 Dictionary 是引用类型），因为签名只能返回 JWResult。
## 迁移函数自己拿到的是一份深拷贝，改坏了也污染不到调用方的原始字典 —— 纯函数的实际保障。
## M-7（部门／地区／群组集合变化）的落地点在 `JWSimState.from_dict()`：
## 它对每个数组写入后立刻读回比对，长度对不上即 SAVE_CORRUPT，不会被静默截断。
func migrate(src: Dictionary, from_version: int) -> JWResult:
	if from_version > CURRENT_SCHEMA_VERSION:
		return JWResult.make_err(JWResult.Load.SAVE_VERSION_TOO_NEW,
				from_version, CURRENT_SCHEMA_VERSION)
	if from_version < 0:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, from_version, 0)
	if from_version == CURRENT_SCHEMA_VERSION:
		return JWResult.make_ok()

	var cur: Dictionary = src.duplicate(true)
	var v: int = from_version
	while v < CURRENT_SCHEMA_VERSION:
		if v >= migrations.size():
			return JWResult.make_err(JWResult.Load.MIGRATION_MISSING, v, v + 1)
		var fn: Callable = migrations[v]
		if not fn.is_valid():
			return JWResult.make_err(JWResult.Load.MIGRATION_MISSING, v, v + 1)
		var out: Variant = fn.call(cur)
		if typeof(out) != TYPE_DICTIONARY:
			return JWResult.make_err(JWResult.Load.MIGRATION_MISSING, v, v + 1)
		cur = out
		v += 1
		# 迁移函数漏写版本号不算它的错，但版本号必须单调升一级：链的全序由这里保证。
		cur[JWSimState.SAVE_KEY_SCHEMA] = v

	var mf: Dictionary = {}
	mf[MK_SCHEMA_VERSION] = from_version
	mf[MK_STATE_HASH] = ""
	cur[MIGRATED_FROM] = mf

	src.clear()
	src.merge(cur, true)
	return JWResult.make_ok()


## checkpoints.jsonl：每季一行 {q, state_hash, step_hash[8]}。
## 步骤：每季末
## 前置：本季 8 个步骤哈希已记录
## 后置：追加一行
## 不变量：INV-014；docs/11 §6.5 的重放分歧二分定位
## 失败：无
##
## 「失败：无」指没有业务失败；写盘失败与行格式不合规仍然如实返回错误码 ——
## 一行残缺的检查点会让重放二分定位指向错误的季，比不写更坏。
func append_checkpoint(q: int, state_hash: String, step_hash: PackedStringArray,
		slot: String) -> JWResult:
	if not _slot_name_ok(slot):
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 0, 0)
	if q < 0 or state_hash == "":
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, q, 0)
	if step_hash.size() != STEP_HASH_N:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, step_hash.size(), STEP_HASH_N)

	var dir: String = _slot_dir(slot)
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 1, 0)

	var steps: Array = []
	var i: int = 0
	while i < step_hash.size():
		steps.append(step_hash[i])
		i += 1
	var rec: Dictionary = {}
	rec[CK_Q] = q
	rec[CK_STATE_HASH] = state_hash
	rec[CK_STEP_HASH] = steps

	var one: PackedStringArray = PackedStringArray()
	one.append(JSON.stringify(rec, "", true))
	if not _append_lines(dir + FILE_CHECKPOINTS, one):
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 2, q)
	slot_path = dir
	return JWResult.make_ok()


# ── 内部：manifest 组装与校验 ─────────────────────────────────────────────

## 按 docs/11 §6.3 逐字段组装 manifest。
## 全部取值都来自权威状态与命令缓冲，**没有一个字段是推测出来的**：
## 取不到的（scenario_hash 未注入）写空串，由读档端按「无法证明」处置。
func _build_manifest(st: JWSimState, cmds: JWCommands) -> Dictionary:
	var d: Dictionary = {}
	d[MK_SCHEMA_KIND] = SCHEMA_KIND_MANIFEST
	d[MK_SCHEMA_VERSION] = CURRENT_SCHEMA_VERSION
	d[MK_CREATED_UTC] = Time.get_datetime_string_from_system(true) + "Z"
	d[MK_BUILD_ID] = st.build_id
	d[MK_SCENARIO_ID] = st.scenario_id
	d[MK_SCENARIO_HASH] = scenario_hash
	d[MK_CONTENT_HASH] = st.content_hash
	d[MK_PARAM_SET_VERSION] = st.param_set_version
	d[MK_HORIZON_Q] = st.horizon_q
	d[MK_Q] = st.q
	d[MK_STATE_HASH] = st.state_hash()
	d[MK_COMMAND_COUNT] = cmds.count
	d[MK_COMMAND_LOG_HASH] = cmds.command_log_hash()
	d[MK_REPLAY_MODE] = REPLAY_MODE_DEFAULT

	var seed_v: int = 0
	var draws: Array = []
	if st.rng != null:
		seed_v = st.rng.root_seed
		var i: int = 0
		while i < st.rng.draw_count.size():
			draws.append(_json_int(st.rng.draw_count[i]))
			i += 1
	d[MK_ROOT_SEED] = _json_int(seed_v)
	d[MK_DRAW_COUNT] = draws
	return d


## docs/17 §6.2：`root_seed` + `draw_count[6]` 就是完整的随机流状态，
## 而它同时出现在 manifest 与 state.json 两处；两处不一致即 E_SAVE_CORRUPT。
func _verify_rng(man: Dictionary, st: JWSimState) -> JWResult:
	if st.rng == null:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	var want_seed: int = _read_int(man, MK_ROOT_SEED)
	if _field_err:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	if want_seed != st.rng.root_seed:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	if typeof(man.get(MK_DRAW_COUNT, null)) != TYPE_ARRAY:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	var arr: Array = man[MK_DRAW_COUNT]
	if arr.size() != JWUnits.RNG_STREAM_N or st.rng.draw_count.size() != JWUnits.RNG_STREAM_N:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, arr.size(), JWUnits.RNG_STREAM_N)
	var i: int = 0
	while i < arr.size():
		var v: int = _variant_int(arr[i])
		if _field_err or v != st.rng.draw_count[i]:
			return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, i, v)
		i += 1
	return JWResult.make_ok()


## 结构性校验 checkpoints.jsonl；成功时 `detail_a` 是行数。
##
## 只校验**结构与单调性**，不校验「哪一行的哈希该等于 manifest 的 state_hash」：
## 自动保存会让 checkpoints 跑在 state.json 快照前面（docs/11 §6.2），
## 两者的 q 对应关系不是恒等的，硬断言就是在猜。
func _verify_checkpoints(path: String) -> JWResult:
	if not FileAccess.file_exists(path):
		# 尚未走完第一季的存档没有检查点，这是合法的空文件/缺文件。
		return JWResult.make_ok()
	var text: String = FileAccess.get_file_as_string(path)
	var lines: PackedStringArray = text.split("\n", false)
	var prev_q: int = -1
	var n: int = 0
	var i: int = 0
	while i < lines.size():
		var line: String = lines[i].strip_edges()
		i += 1
		if line == "":
			continue
		var v: Variant = JSON.parse_string(line)
		if typeof(v) != TYPE_DICTIONARY:
			return JWResult.make_err(JWResult.Load.FILE_FORMAT, n, 0)
		var rec: Dictionary = v
		if not rec.has(CK_Q) or not rec.has(CK_STATE_HASH) or not rec.has(CK_STEP_HASH):
			return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, n, 0)
		var q: int = _variant_int(rec[CK_Q])
		if _field_err or q <= prev_q:
			# 季号必须严格递增：重排或重复会让二分定位失去意义。
			return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, n, q)
		prev_q = q
		if typeof(rec[CK_STEP_HASH]) != TYPE_ARRAY:
			return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, n, 0)
		var steps: Array = rec[CK_STEP_HASH]
		if steps.size() != STEP_HASH_N:
			return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, n, steps.size())
		if String(rec[CK_STATE_HASH]) == "":
			return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, n, 0)
		n += 1
	var r: JWResult = JWResult.make_ok()
	r.detail_a = n
	return r


# ── 内部：shock_log.jsonl ─────────────────────────────────────────────────

## 把扁平行渲染成 JSON Lines（列序即 SL_KEYS）。
func _shock_log_text(rows: PackedInt64Array) -> String:
	var out: String = ""
	var r: int = 0
	var n: int = JWMath.floor_div(rows.size(), SHOCK_LOG_COLS)
	while r < n:
		out += _shock_log_line(rows, r * SHOCK_LOG_COLS) + "\n"
		r += 1
	return out


## 单行渲染。`raw` 是 u64 位型，可能超过 2^53，走 `_json_int` 的字符串形态。
func _shock_log_line(rows: PackedInt64Array, base: int) -> String:
	var rec: Dictionary = {}
	var c: int = 0
	while c < SHOCK_LOG_COLS:
		rec[SL_KEYS[c]] = _json_int(rows[base + c])
		c += 1
	return JSON.stringify(rec, "", true)


## 逐行解析 shock_log.jsonl 成扁平整数行（stride = 7）。
## 与命令流不同，冲击记录**单行损坏不能只丢一条**：丢一条就等于改写了已决抽样，
## 读档后 S01「先查后抽」会重抽，INV-109 与 INV-133 同时失效。所以一律拒绝加载。
func _parse_shock_log(path: String, out_rows: PackedInt64Array) -> JWResult:
	out_rows.clear()
	if not FileAccess.file_exists(path):
		return JWResult.make_ok()
	var text: String = FileAccess.get_file_as_string(path)
	var lines: PackedStringArray = text.split("\n", false)
	var i: int = 0
	while i < lines.size():
		var line: String = lines[i].strip_edges()
		i += 1
		if line == "":
			continue
		var v: Variant = JSON.parse_string(line)
		if typeof(v) != TYPE_DICTIONARY:
			return JWResult.make_err(JWResult.Load.FILE_FORMAT, i, 0)
		var rec: Dictionary = v
		var c: int = 0
		while c < SHOCK_LOG_COLS:
			if not rec.has(SL_KEYS[c]):
				return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, i, c)
			var x: int = _variant_int(rec[SL_KEYS[c]])
			if _field_err:
				return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, i, c)
			out_rows.append(x)
			c += 1
	return JWResult.make_ok()


# ── 内部：文件与目录 ──────────────────────────────────────────────────────

## 槽位名必须是单段安全名：不得为空、不得含路径分隔符或 `..`。
## 否则 `user://saves/<slot>/` 可以被撬出存档根目录。
func _slot_name_ok(slot: String) -> bool:
	if slot == "" or slot.length() > 64:
		return false
	if slot.contains("/") or slot.contains("\\") or slot.contains(":"):
		return false
	if slot == "." or slot == ".." or slot.contains(".."):
		return false
	return true


func _slot_dir(slot: String) -> String:
	return SAVES_ROOT + slot + "/"


## 写一个 JSON 文件（键升序、无缩进；哈希不看它，人读时靠 sort_keys 稳定定位）。
func _write_json(path: String, d: Dictionary) -> bool:
	return _write_text(path, JSON.stringify(d, "\t", true) + "\n")


func _write_text(path: String, text: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	var err: int = f.get_error()
	f.close()
	return err == OK


## 追加若干行（一次开闭，不重写已有内容）。
func _append_lines(path: String, lines: PackedStringArray) -> bool:
	if lines.is_empty():
		return true
	var f: FileAccess = null
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		if f == null:
			return false
		f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return false
	var i: int = 0
	while i < lines.size():
		f.store_string(lines[i] + "\n")
		i += 1
	f.close()
	return true


## 数非空行数（只在追加游标未知时走一次）。
func _count_lines(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var text: String = FileAccess.get_file_as_string(path)
	var lines: PackedStringArray = text.split("\n", false)
	var n: int = 0
	var i: int = 0
	while i < lines.size():
		if lines[i].strip_edges() != "":
			n += 1
		i += 1
	return n


## 读一个 JSON 文件并要求根是 Dictionary。
func _read_json_dict(path: String, out_d: Dictionary) -> JWResult:
	if not FileAccess.file_exists(path):
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 0, 0)
	var text: String = FileAccess.get_file_as_string(path)
	var v: Variant = JSON.parse_string(text)
	if typeof(v) != TYPE_DICTIONARY:
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, 0, 0)
	if not _normalize_ints(v):
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	var d: Dictionary = v
	out_d.clear()
	out_d.merge(d, true)
	return JWResult.make_ok()


## 把 JSON 解析器吐出的 double **还原**成精确 int64（递归，就地改写）。
##
## 引擎的 JSON 解析器把一切数字都读成 double（4.7 实测），而存档里一个浮点都没有：
## 写出时 `_json_int` 保证 |v| ≤ 2^53 的整数写成裸整数、超界的写成十进制字符串。
## 因此凡是读回来的 double 都必然是「本来是整数、被解析器降级了」的那一类，
## 还原是无损的。**这不是给浮点开口子**：带小数部分、或绝对值超过 2^53 的 double
## 一律判存档损坏 —— 那种值不可能由本模块写出，只能是档案被改坏。
## 还原必须发生在 `JWSimState.from_dict()` 之前：它对 TYPE_FLOAT 直接登记
## `Fault.FLOAT_IN_STATE` 并返回 0（INV-001），拿到 double 会把整份状态读成 0。
func _normalize_ints(v: Variant) -> bool:
	var t: int = typeof(v)
	if t == TYPE_DICTIONARY:
		var d: Dictionary = v
		var keys: Array = d.keys()
		var i: int = 0
		while i < keys.size():
			var child: Variant = d[keys[i]]
			var ct: int = typeof(child)
			if ct == TYPE_FLOAT:
				var n: int = _float_to_int(child)
				if _field_err:
					return false
				d[keys[i]] = n
			elif ct == TYPE_DICTIONARY or ct == TYPE_ARRAY:
				if not _normalize_ints(child):
					return false
			i += 1
		return true
	if t == TYPE_ARRAY:
		var a: Array = v
		var j: int = 0
		while j < a.size():
			var e: Variant = a[j]
			var et: int = typeof(e)
			if et == TYPE_FLOAT:
				var m: int = _float_to_int(e)
				if _field_err:
					return false
				a[j] = m
			elif et == TYPE_DICTIONARY or et == TYPE_ARRAY:
				if not _normalize_ints(e):
					return false
			j += 1
		return true
	return true


## 单个 double → int64；带小数部分或超出 2^53 即置 `_field_err`。
func _float_to_int(x: Variant) -> int:
	_field_err = false
	var n: int = int(x)
	if n > JSON_SAFE_INT_MAX or n < -JSON_SAFE_INT_MAX:
		_field_err = true
		return 0
	if x != n:
		_field_err = true
		return 0
	return n


## 递归删除一个目录（写盘失败时清理半成品；不存在即成功）。
func _rm_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	dir.include_navigational = false
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			if dir.current_is_dir():
				_rm_recursive(path + entry + "/")
			else:
				DirAccess.remove_absolute(path + entry)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


# ── 内部：整数的 JSON 形态（docs/11 §3 无浮点） ───────────────────────────

## 超过 2^53 的整数经任何标准 JSON 解析器都会掉成 double 并丢低位，
## 而 `root_seed` 与 shock_log 的 `raw` 天然是 u64 位型。超界即改写十进制字符串。
func _json_int(v: int) -> Variant:
	if v > JSON_SAFE_INT_MAX or v < -JSON_SAFE_INT_MAX:
		return str(v)
	return v


## 读一个整数字段；缺失或类型不对时置 `_field_err`。
## **浮点一律判错**：docs/11 §3 的方言限制里没有浮点，出现即存档已被改坏。
func _read_int(d: Dictionary, key: String) -> int:
	if not d.has(key):
		_field_err = true
		return 0
	return _variant_int(d[key])


func _variant_int(x: Variant) -> int:
	_field_err = false
	var t: int = typeof(x)
	if t == TYPE_INT:
		return int(x)
	if t == TYPE_STRING or t == TYPE_STRING_NAME:
		var s: String = String(x)
		if s.is_valid_int():
			return s.to_int()
	if t == TYPE_FLOAT:
		# JSON 解析器把裸整数读成 double（见 _normalize_ints 的说明）。
		return _float_to_int(x)
	_field_err = true
	return 0


# 存档安全边界（docs/17 §4.32 末）：**不加密、不签名**。
# 哈希只用于检测损坏与内容漂移，不用于防作弊 —— 玩家改自己的存档不在威胁模型内（docs/11 §6.8）。
