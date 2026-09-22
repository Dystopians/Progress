## 季度结算性能基准（docs/30_quality_gates.md §7 类别 F「性能目标」的可执行形态）。
##
## 计划书 §17：**登记参考电脑后，季度结算中位数低于 0.5 秒、95 分位低于 1 秒；未达标先剖析再优化。**
## 参考机 `REF-01` 已在 `docs/ENGINE.md` 登记。**在别的机器上测出的数字不能直接与门槛比较**——
## 必须先在那台机上重跑本脚本并登记为新的 `REF-xx`，本脚本会把 `--ref` 原样打进报告头与 CSV 文件名。
##
## ── 计时口径（docs/30 §7.2，一字不改） ──────────────────────────────────────
##
##     计时区间 = JWTurnRunner.advance_quarter() 的整个调用，含八步与全部不变量检查，
##     不含：内容加载、剧本解析、存档写盘、日志落盘、屏幕绘制。
##
## 因此本脚本**不经 `JWGame`**：`JWGame.advance_quarter()` 每季追加自动存档，那是磁盘时间，
## 由 `T-X-F-04` 单独设门（< 100 ms），不能混进这条 0.5 s 的门里。
## 内容加载单独计时并按 `T-X-F-05`（< 3 s）比对，但不计入季度样本。
##
## ── 测量协议（docs/30 §7.3） ────────────────────────────────────────────────
##
## | 项 | 规定 | 本脚本 |
## |---|---|---|
## | 样本 | 100 种子 × 120 季 | `--profile=full`；缺省 `gate` 档为 5 种子 × 120 季 |
## | 热身 | 整份基准前先跑 1 种子 × 3 季并整份丢弃 | `WARMUP_QUARTERS` |
## | 剔除首次加载 | 每个种子的 q=0 与 q=1 两季剔除 | `DROP_FIRST_Q` |
## | 重复 | 跑 3 轮，取「每轮中位数」的中位数；三轮极差 > 15% 判环境不稳 | `--rounds`，缺省 3 |
## | 统计量 | 中位数 / P95 / P99 / 最大值，全部整数微秒 | 见报告 |
## | 输出 | `tools/out/bench_<build_id>_<REF>_<日期>.csv` + 一行进 docs/ENGINE.md | 见 `--out` |
##
## **只有 `--profile=full` 跑出来的值有资格登记进 `docs/ENGINE.md` 的性能表**，
## 因为登记值的样本量是协议的一部分。缺省的 `gate` 档是日常回归用的，报告头会写明档位。
##
## ── 与压测的一处**刻意**差异：WriteGuard 抽样 ──────────────────────────────
##
## `tests/stress/many_seeds_test.gd` 按 docs/30 §6.3 断言 ④ 把 `param.write_guard_sample_q`
## 强制改成 1（逐季全开），因为压测要的是「一次越权写入都不许漏过」。
## 本脚本**不改这张卡**：性能门槛量的是玩家实际会跑的那条路径，而 §7.3 的排除项表已经写明
## 「发布构建按季抽样，不是每季必付的成本」。两边口径不同是有意的，不要「统一」它们——
## 统一到全开会让性能数字比真实体验悲观，统一到抽样会让压测出现盲区。
##
## ── 用法 ────────────────────────────────────────────────────────────────────
##
##     GODOT="…/Godot_v4.7.2-stable_win64_console.exe"
##     "$GODOT" --headless --path "C:/Users/Fiber Memory/Documents/Jingwei" \
##         --script "res://tools/bench_quarter.gd" -- [选项]
##
## 选项（全部 `--键=值`，缺省见下方常量）：
##
##     --profile=gate|full   样本档位（full == 契约的 100 种子 × 120 季）
##     --seeds=N             覆盖种子数
##     --quarters=N          覆盖每个种子的季数
##     --rounds=N            覆盖轮数
##     --ref=REF-01          参考机 ID，进报告头与 CSV 文件名
##     --out=res://…/x.csv   覆盖 CSV 输出路径（缺省按协议自动命名）
##     --no-csv              不写 CSV（只打印报告）
##     --baseline-median-us=N  上次登记的中位数，用于 T-X-F-06 回归判据
##     --baseline-p95-us=N     上次登记的 P95
##
## 退出码：0 == 全部门槛通过；1 == 有门槛未过或测量环境不稳；2 == 基准没跑成（开不了局）。
extends SceneTree

# ── 门槛（计划书 §17 / docs/30 §7.4，单位微秒） ────────────────────────────

## `T-X-F-01`：季度结算中位数门槛 0.5 s。
const THRESHOLD_MEDIAN_US: int = 500_000
## `T-X-F-02`：95 分位门槛 1 s。
const THRESHOLD_P95_US: int = 1_000_000
## `T-X-F-05`：内容包加载 + 校验 + 开账门槛 3 s。
const THRESHOLD_LOAD_US: int = 3_000_000
## `T-X-F-06`：回归容忍度，本次 ≤ 上次 × 120 / 100（整数比较，避免 float）。
const REGRESSION_NUM: int = 120
const REGRESSION_DEN: int = 100

# ── 协议常量（docs/30 §7.3） ───────────────────────────────────────────────

## 契约样本档：100 种子。
const FULL_SEEDS: int = 100
## 日常档：5 种子。跑一次 full 档是 3 轮 × 100 × 120 == 36 000 季，不是随手能跑的量。
const GATE_SEEDS: int = 5
## 每个种子的季数。
const DEFAULT_QUARTERS: int = 120
## 轮数。
const DEFAULT_ROUNDS: int = 3
## 热身：1 个种子 × 3 季，整份丢弃。
const WARMUP_SEEDS: int = 1
const WARMUP_QUARTERS: int = 3
## 每个种子头两季剔除（覆盖日志数组首次扩容、scratch 首次触碰、类缓存）。
const DROP_FIRST_Q: int = 2
## 三轮中位数极差超过这个百分比即判测量环境不稳定，结果作废。
const ROUND_SPREAD_MAX_PCT: int = 15

## 种子基数（与压测同一套，docs/30 §6.3）。
const ROOT_SEED_BASE: int = 1_000_000
## 内容包根目录。
const CONTENT_ROOT: String = "res://content"
## CSV 输出目录。
const OUT_DIR: String = "res://tools/out"
## 缺省参考机 ID。
const DEFAULT_REF: String = "REF-01"

# ── 命令行解析结果 ─────────────────────────────────────────────────────────

## 档位名（"gate" / "full" / "custom"）。
var _profile: String = "gate"
## 种子数。
var _seeds: int = GATE_SEEDS
## 每个种子的季数。
var _quarters: int = DEFAULT_QUARTERS
## 轮数。
var _rounds: int = DEFAULT_ROUNDS
## 参考机 ID。
var _ref: String = DEFAULT_REF
## CSV 输出路径（空串 == 按协议自动命名）。
var _out_path: String = ""
## 是否写 CSV。
var _write_csv: bool = true
## 上次登记的中位数（0 == 未提供，跳过回归判据）。
var _baseline_median_us: int = 0
## 上次登记的 P95。
var _baseline_p95_us: int = 0

# ── 测量结果 ───────────────────────────────────────────────────────────────

## 每轮的中位数。
var _round_median: PackedInt64Array = PackedInt64Array()
## 全部轮次的样本拼在一起（算 P95 / P99 / 最大值用）。
var _all_samples: PackedInt64Array = PackedInt64Array()
## 每次开局的内容加载耗时（微秒）。
var _load_us: PackedInt64Array = PackedInt64Array()
## CSV 明细行：round, seed, q, dt_us。
var _csv_rows: PackedStringArray = PackedStringArray()
## 跑成功的季数（含被剔除的头两季）。
var _quarters_run: int = 0
## T-X-F-03：八步各自的累计耗时（μs，只计保留下来的样本季）。
var _step_total_us: PackedInt64Array = PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0])
## 提前终局的次数（终局是合法结局，但它会让有效样本数少于协议值，必须报出来）。
var _early_end_runs: int = 0
## 结算返回非 OK 的次数（性能数字只在引擎跑得通时才有意义）。
var _failed_quarters: int = 0
## 开局失败的诊断（非空即整份基准作废）。
var _boot_note: String = ""


func _init() -> void:
	_parse_args()
	_print_header()

	# 热身：整份丢弃（docs/30 §7.3）。它同时把脚本类缓存、scratch 分配、首次 load() 全部吃掉。
	var warm: Bench = _run_seed(ROOT_SEED_BASE - 1, WARMUP_QUARTERS, -1, false)
	if warm == null:
		print("")
		print("！基准未能开始：%s" % _boot_note)
		print("！这不是「性能不达标」，而是**测不了**——引擎在这台机上开不了局。")
		print("！docs/30 §7.1 要求报告写明机器 ID 与 build_id；无样本时不得登记任何数字。")
		_print_footer_no_data()
		quit(2)
		return
	print("热身完成：1 种子 × %d 季，整份丢弃（内容加载 %d μs）" % [WARMUP_QUARTERS, warm.load_us])

	var r: int = 0
	while r < _rounds:
		var samples: PackedInt64Array = PackedInt64Array()
		var i: int = 0
		while i < _seeds:
			var b: Bench = _run_seed(ROOT_SEED_BASE + i, _quarters, r, true)
			if b == null:
				print("！第 %d 轮种子 %d 开局失败：%s" % [r + 1, ROOT_SEED_BASE + i, _boot_note])
				_print_footer_no_data()
				quit(2)
				return
			_load_us.append(b.load_us)
			samples.append_array(b.kept)
			i += 1
		samples.sort()
		_round_median.append(_median(samples))
		_all_samples.append_array(samples)
		print("第 %d / %d 轮：有效样本 %d，中位数 %d μs" % [r + 1, _rounds, samples.size(),
				_median(samples)])
		r += 1

	_all_samples.sort()
	var code: int = _report()
	quit(code)


# ══════════════════════════════════════════════════════════════════════════
# 命令行
# ══════════════════════════════════════════════════════════════════════════

func _parse_args() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--profile="):
			_profile = a.substr(10)
			if _profile == "full":
				_seeds = FULL_SEEDS
			elif _profile == "gate":
				_seeds = GATE_SEEDS
		elif a.begins_with("--seeds="):
			_seeds = maxi(1, _int_arg(a, 8))
			_profile = "custom"
		elif a.begins_with("--quarters="):
			_quarters = maxi(DROP_FIRST_Q + 1, _int_arg(a, 11))
			_profile = "custom"
		elif a.begins_with("--rounds="):
			_rounds = maxi(1, _int_arg(a, 9))
		elif a.begins_with("--ref="):
			_ref = a.substr(6)
		elif a.begins_with("--out="):
			_out_path = a.substr(6)
		elif a == "--no-csv":
			_write_csv = false
		elif a.begins_with("--baseline-median-us="):
			_baseline_median_us = _int_arg(a, 21)
		elif a.begins_with("--baseline-p95-us="):
			_baseline_p95_us = _int_arg(a, 18)


## 本次运行是否**完全符合** docs/30 §7.3 的测量协议。
## 只有协议样本跑出来的数字才有资格登记进 `docs/ENGINE.md`——样本量与轮数是登记值的一部分，
## 少一轮、少几个种子都会改变分位数的含义，把它当登记值就是在报一个自己不认识的数。
func _is_protocol_run() -> bool:
	return _seeds == FULL_SEEDS and _quarters == DEFAULT_QUARTERS and _rounds == DEFAULT_ROUNDS


## `--键=整数` 的取值；非整数时返回 0。
func _int_arg(arg: String, prefix_len: int) -> int:
	var v: String = arg.substr(prefix_len)
	if not v.is_valid_int():
		return 0
	return v.to_int()


# ══════════════════════════════════════════════════════════════════════════
# 单个种子的测量
# ══════════════════════════════════════════════════════════════════════════

## 一个种子跑下来的测量结果。
class Bench extends RefCounted:
	## 保留下来的季度样本（已剔除头 DROP_FIRST_Q 季），微秒。
	var kept: PackedInt64Array = PackedInt64Array()
	## 本次开局的内容加载耗时（微秒）。
	var load_us: int = 0
	## 是否提前终局（或被故障打断）。
	var early_end: bool = false


## 跑一个种子。`round_idx < 0` 表示热身（不写 CSV、不计入任何统计）。
func _run_seed(seed_v: int, quarters: int, round_idx: int, record: bool) -> Bench:
	var b: Bench = Bench.new()

	# ── 排除项：内容加载单独计时，不进季度样本（docs/30 §7.2 的明确排除项） ──
	var l0: int = Time.get_ticks_usec()
	JWResult.clear_pending()
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	st.horizon_q = quarters
	var loader: JWContentLoader = JWContentLoader.new()
	var res: JWResult = loader.load_all(CONTENT_ROOT, st)
	if res == null or not res.ok:
		var where: String = "（无位置）"
		if loader.errors.size() > 0:
			where = loader.error_where(0)
		var code: int = res.code if res != null else -1
		_boot_note = ("载入 %s 失败：首个错误码 %d 于 %s；加载器共报 %d 条错误"
				% [CONTENT_ROOT, code, where, loader.errors.size()])
		return null
	st.build_id = JWGame.BUILD_ID
	st.content_hash = loader.content_hash
	st.param_set_version = loader.param_set_version
	if st.rng.set_state_scalar(0, seed_v) != JWResult.OK:
		_boot_note = "注入 root_seed %d 失败" % seed_v
		return null
	b.load_us = Time.get_ticks_usec() - l0

	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	var events: JWEventEngine = JWEventEngine.new()
	events.allocate()
	var runner: JWTurnRunner = JWTurnRunner.new(st, events)
	var marker: PackedInt64Array = PackedInt64Array()
	marker.resize(JWCommands.ARG_SLOTS)
	marker.fill(0)

	var q: int = 0
	while q < quarters:
		if st.politics != null and st.politics.run_terminated:
			b.early_end = true
			break
		var rm: JWResult = cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, marker, st.q,
				st.policy_defs)
		if rm != null and not rm.ok:
			_boot_note = "第 %d 季的 advance_quarter 标记被拒，码 %d" % [q, rm.code]
			return null

		# ── 被测区间（docs/30 §7.2，一行不多一行不少） ──────────────────
		var t0: int = Time.get_ticks_usec()
		var fault: int = runner.advance_quarter(cmds)
		var dt_us: int = Time.get_ticks_usec() - t0
		# ── 被测区间结束 ────────────────────────────────────────────────

		if fault != JWResult.OK:
			if record:
				_failed_quarters += 1
			print("！种子 %d 第 %d 季结算返回 %d（步骤 %d）——性能数字只在引擎跑得通时才有意义"
					% [seed_v, q, fault, JWResult.pending_step()])
			JWResult.clear_pending()
			b.early_end = true
			break
		if record:
			_quarters_run += 1
			if q >= DROP_FIRST_Q:
				b.kept.append(dt_us)
				for k: int in 8:
					_step_total_us[k] += runner.step_us[k]
				if _write_csv:
					_csv_rows.append("%d,%d,%d,%d" % [round_idx + 1, seed_v, q, dt_us])
		q += 1

	if record and b.early_end:
		_early_end_runs += 1
	return b


# ══════════════════════════════════════════════════════════════════════════
# 统计（全部整数微秒；不用 float，也就没有「看起来精确的假小数」）
# ══════════════════════════════════════════════════════════════════════════

## 已排序数组的中位数。偶数个取中间两个的整数平均（向下取整），奇数个取正中。
static func _median(sorted_v: PackedInt64Array) -> int:
	var n: int = sorted_v.size()
	if n == 0:
		return 0
	var lo: int = sorted_v[JWMath.floor_div(n - 1, 2)]
	var hi: int = sorted_v[JWMath.floor_div(n, 2)]
	return JWMath.floor_div(lo + hi, 2)


## 已排序数组的第 pct 百分位（最近秩法：秩 = ceil(pct × n / 100)，下标 = 秩 − 1）。
static func _percentile(sorted_v: PackedInt64Array, pct: int) -> int:
	var n: int = sorted_v.size()
	if n == 0:
		return 0
	var rank: int = JWMath.ceil_div(pct * n, 100)
	var idx: int = JWMath.clamp_i(rank - 1, 0, n - 1)
	return sorted_v[idx]


## 整数「微秒 → 毫秒（保留 3 位）」的展示串，不引入 float。
static func _ms(us: int) -> String:
	var whole: int = JWMath.floor_div(us, 1000)
	var frac: int = us - whole * 1000
	return "%d.%03d ms" % [whole, frac]


# ══════════════════════════════════════════════════════════════════════════
# 报告
# ══════════════════════════════════════════════════════════════════════════

func _print_header() -> void:
	print("")
	print("════════════ 经纬 · 季度结算性能基准 ════════════")
	print("参考机      ： %s（性能门槛只对登记过的参考机成立；换机器必须重跑并登记新的 REF-xx）" % _ref)
	print("build_id    ： %s" % JWGame.BUILD_ID)
	print("引擎        ： %s" % Engine.get_version_info().get("string", "未知"))
	print("日期        ： %s" % Time.get_datetime_string_from_system(false, true))
	var tail: String = ""
	if not _is_protocol_run():
		tail = "　← 不合 docs/30 §7.3 的协议样本（%d 种子 × %d 季 × %d 轮），不得登记进 docs/ENGINE.md" \
				% [FULL_SEEDS, DEFAULT_QUARTERS, DEFAULT_ROUNDS]
	print("档位        ： %s（%d 种子 × %d 季 × %d 轮）%s"
			% [_profile, _seeds, _quarters, _rounds, tail])
	print("计时口径    ： JWTurnRunner.advance_quarter() 整个调用（docs/30 §7.2）；")
	print("              不含内容加载、剧本解析、存档写盘、日志落盘、屏幕绘制")
	print("剔除规则    ： 热身 1 种子 × %d 季整份丢弃；每个种子的 q=0、q=1 两季剔除" % WARMUP_QUARTERS)
	print("环境要求    ： 插电、电源模式「高性能」、无其他前台负载（docs/30 §7.3；由操作者保证）")
	print("──────────────────────────────────────────────")


func _print_footer_no_data() -> void:
	print("──────────────────────────────────────────────")
	print("有效样本 0 —— 本次**没有产生任何可登记的性能数字**。")
	print("按 docs/30 §7.4，没有样本就既不能宣告通过，也不能宣告不通过：它是「测量未能进行」。")
	print("════════════════════════════════════════════════")


func _report() -> int:
	var expected: int = _seeds * (_quarters - DROP_FIRST_Q) * _rounds
	var n: int = _all_samples.size()
	var med: int = _median(_all_samples)
	var p95: int = _percentile(_all_samples, 95)
	var p99: int = _percentile(_all_samples, 99)
	var worst: int = _all_samples[n - 1] if n > 0 else 0

	# 登记值 = 「每轮中位数」的中位数（docs/30 §7.3）。
	var rm: PackedInt64Array = _round_median.duplicate()
	rm.sort()
	var registered: int = _median(rm)
	var spread: int = 0
	if rm.size() > 0:
		spread = rm[rm.size() - 1] - rm[0]
	var unstable: bool = registered > 0 and spread * 100 > registered * ROUND_SPREAD_MAX_PCT

	var load_sorted: PackedInt64Array = _load_us.duplicate()
	load_sorted.sort()
	var load_med: int = _median(load_sorted)

	# docs/30 §7.3 点名要求打印「每轮有效样本数」（协议档下 == 100 × 118 == 11 800）。
	var per_round: int = _seeds * (_quarters - DROP_FIRST_Q)
	print("")
	print("──────────── 样本 ────────────")
	print("每轮有效样本： %d（== 种子 %d × (季 %d − 剔除 %d)）" % [per_round, _seeds, _quarters,
			DROP_FIRST_Q])
	print("合计有效样本： %d（协议值 = 每轮 %d × 轮 %d = %d）" % [n, per_round, _rounds, expected])
	if n != expected:
		print("！有效样本数与协议值不符：提前终局 %d 次、结算失败 %d 次。"
				% [_early_end_runs, _failed_quarters])
		print("！样本量是登记值的一部分，对不上就不能把这组数字当成协议样本（docs/30 §7.3）。")
	print("结算成功季数： %d ｜ 结算失败季数： %d ｜ 提前终局： %d 次"
			% [_quarters_run, _failed_quarters, _early_end_runs])

	print("")
	print("──────────── 季度结算耗时（整数微秒） ────────────")
	print("中位数      ： %9d μs（%s）" % [med, _ms(med)])
	print("P95         ： %9d μs（%s）" % [p95, _ms(p95)])
	print("P99         ： %9d μs（%s）" % [p99, _ms(p99)])
	print("最大值      ： %9d μs（%s）" % [worst, _ms(worst)])
	var i: int = 0
	while i < _round_median.size():
		print("第 %d 轮中位数： %9d μs（%s）" % [i + 1, _round_median[i], _ms(_round_median[i])])
		i += 1
	print("登记值（每轮中位数的中位数）： %d μs（%s）" % [registered, _ms(registered)])
	print("三轮中位数极差： %d μs（上限 %d%% == %d μs）"
			% [spread, ROUND_SPREAD_MAX_PCT,
				JWMath.floor_div(registered * ROUND_SPREAD_MAX_PCT, 100)])

	print("")
	print("──────────── 判据（docs/30 §7.4） ────────────")
	var ok: bool = true
	ok = _judge("T-X-F-01 中位数", registered, THRESHOLD_MEDIAN_US) and ok
	ok = _judge("T-X-F-02 P95   ", p95, THRESHOLD_P95_US) and ok
	ok = _judge("T-X-F-05 内容加载", load_med, THRESHOLD_LOAD_US) and ok
	if _baseline_median_us > 0:
		var lim: int = JWMath.floor_div(_baseline_median_us * REGRESSION_NUM, REGRESSION_DEN)
		ok = _judge("T-X-F-06 中位数回归（上次 %d）" % _baseline_median_us, registered, lim + 1) and ok
	if _baseline_p95_us > 0:
		var lim95: int = JWMath.floor_div(_baseline_p95_us * REGRESSION_NUM, REGRESSION_DEN)
		ok = _judge("T-X-F-06 P95 回归（上次 %d）" % _baseline_p95_us, p95, lim95 + 1) and ok
	if unstable:
		print("  ✗ 三轮中位数极差 %d μs 超过登记值的 %d%%：测量环境不稳定，本次结果作废，须重测"
				% [spread, ROUND_SPREAD_MAX_PCT])
		ok = false
	if n != expected:
		print("  ✗ 样本量与协议不符，本次结果不得登记")
		ok = false
	if not _is_protocol_run():
		print("  · 本次不是协议样本（协议 = %d 种子 × %d 季 × %d 轮，本次 %d × %d × %d）："
				% [FULL_SEEDS, DEFAULT_QUARTERS, DEFAULT_ROUNDS, _seeds, _quarters, _rounds])
		print("    结果只作回归信号，**不得**写进 docs/ENGINE.md 的性能登记表")

	print("")
	print("──────────── 未覆盖项（不假装测过） ────────────")
	print("T-X-F-04 自动保存耗时：归 JWSaves，本脚本刻意不触发自动存档（它在计时口径的排除项里）。")
	_report_steps()

	if _write_csv:
		_dump_csv(n, med, p95, p99, worst, registered, load_med)

	print("")
	if ok:
		print("结果：性能门槛全部通过 ✓")
	else:
		print("结果：存在未通过项 ✗（docs/30 §7.4：未达标先剖析再优化，不得先改代码）")
	print("════════════════════════════════════════════════")
	return 0 if ok else 1


## 单条判据：`value < limit` 即通过。
func _judge(name: String, value: int, limit: int) -> bool:
	if value < limit:
		print("  ✓ %s： %d μs < %d μs" % [name, value, limit])
		return true
	print("  ✗ %s： %d μs ≥ %d μs" % [name, value, limit])
	return false


## 写 CSV（docs/30 §7.3 的输出项）。逐样本明细 + 一段汇总注释。
func _dump_csv(n: int, med: int, p95: int, p99: int, worst: int, registered: int,
		load_med: int) -> void:
	var path: String = _out_path
	if path == "":
		var date: String = Time.get_date_string_from_system(false)
		path = "%s/bench_%s_%s_%s.csv" % [OUT_DIR, JWGame.BUILD_ID, _ref, date]
	if not DirAccess.dir_exists_absolute(OUT_DIR):
		DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("！CSV 写入失败（%s）：%d。报告仍然有效，只是没有落盘明细。"
				% [path, FileAccess.get_open_error()])
		return
	f.store_line("# 经纬季度结算基准 · 明细")
	f.store_line("# ref=%s build_id=%s profile=%s seeds=%d quarters=%d rounds=%d"
			% [_ref, JWGame.BUILD_ID, _profile, _seeds, _quarters, _rounds])
	f.store_line("# date=%s engine=%s"
			% [Time.get_datetime_string_from_system(false, true),
				Engine.get_version_info().get("string", "未知")])
	f.store_line("# samples=%d median_us=%d p95_us=%d p99_us=%d max_us=%d registered_us=%d load_median_us=%d"
			% [n, med, p95, p99, worst, registered, load_med])
	f.store_line("round,root_seed,q,dt_us")
	for line: String in _csv_rows:
		f.store_line(line)
	f.close()
	print("")
	print("CSV 明细已写入： %s（%d 行）" % [path, _csv_rows.size()])


## T-X-F-03：八步耗时分解（JWTurnRunner.step_us 的累计；每步含其写入守卫与不变量检查）与占比最高的两步。
func _report_steps() -> void:
	var total: int = 0
	for k: int in 8:
		total += _step_total_us[k]
	print("")
	print("──────────── T-X-F-03 八步耗时分解 ────────────")
	if total <= 0:
		print("  无样本（没有跑出保留季）。")
		return
	var order: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
	order.sort_custom(func(a: int, b: int) -> bool: return _step_total_us[a] > _step_total_us[b])
	for k: int in 8:
		# rounding: 千分比取整只用于显示
		@warning_ignore("integer_division")
		print("  S%02d  %5d‰  累计 %d μs" % [k + 1, _step_total_us[k] * 1000 / total, _step_total_us[k]])
	print("  占比最高的两步：S%02d、S%02d（docs/30 §7.4「先剖析再优化」的剖析对象）" % [order[0] + 1, order[1] + 1])
