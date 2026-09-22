## 主压力测试（`T-X-E-11` / `test_x_100seeds_120q` 的可执行形态）：多种子 × 120 季，
## 检查无崩溃、无整数溢出、无未处理越界、终局可正常记录。
##
## 依据：
##   - docs/30_quality_gates.md §6 类别 E「稳定与重放」：§6.1 把计划书的「无 NaN」改写成
##     整数世界里三类可检查的事实（无 float 进状态 / 无整数溢出 / 无除零）+ 无未检查下标 + 无崩溃；
##     §6.3 主压力测试 `T-X-E-11` 的六条断言；`T-X-E-13` 合法命令 fuzz；`T-X-E-14` 长局账本。
##   - docs/12_simulation_contract.md §0.6 三种失败语义（REJECT / ARREARS / FAULT，没有第四种）、
##     §9 故障登记（第一现场不覆盖、不自动修正）。
##   - docs/10_variable_dictionary.md INV-011、INV-012（q 只在 S08 末 +1）、INV-018、
##     INV-128（终局后任何 advance_quarter 返回 REJECT 且状态哈希逐位不变）。
##   - docs/18_rulings.md R-SCALE-01（1 U = 10⁹ μU；AMOUNT_MAX = 4×10¹⁵、PRICE ∈ [4×10⁸, 2.5×10⁹]）。
##
## ── 规模与如何跑完整 100 种子 ────────────────────────────────────────────────
##
## 契约规模是 **100 种子 × 120 季**（`SEEDS_FULL` × `QUARTERS_FULL`）。
## 那是夜间跑的规模（docs/30 §6.3 明确「不进每次提交的门」），而 `tools/test.sh` 会把
## stress 套件一起跑掉，因此**日常闸门默认只跑 `SEEDS_DEFAULT`（5）个种子**。
## 默认值是 5，不是 100 —— 本文件任何一处都不会声称跑了 100 个。
##
## 跑完整 100 种子（同一份代码，只改环境变量，不改常量）：
##
##     JW_STRESS_SEEDS=100 bash tools/test.sh --suite=stress
##
## 也可单独缩放季数（调试用；缩了就不再是「120 季长局」，报告里的季数会如实打印）：
##
##     JW_STRESS_SEEDS=100 JW_STRESS_QUARTERS=120 bash tools/test.sh --suite=stress
##
## 实际跑了多少个种子由 `test_x_stress_scale_is_reported` 打印并断言，**读报告即可核实**。
##
## 闸门耗时：缺省档是 2 档 × 5 种子 × 120 季 == 1 200 季。按性能门槛的上界（中位数 0.5 s）算，
## 那是 10 分钟——所以缺省档能不能留在每次提交的门里，取决于 `tools/bench_quarter.gd` 实测出来的
## 季度耗时。实测值一旦登记进 `docs/ENGINE.md`，就按它来定：
## 每季 ≲ 30 ms 时缺省档约半分钟，可以留；显著更慢就把日常闸门降到 `JW_STRESS_SEEDS=1`，
## 100 种子那一档仍然照跑，只是挪到夜间。**不要靠减少断言来换速度。**
##
## ── 为什么直接驱动 JWTurnRunner 而不经 JWGame ───────────────────────────────
##
## `JWGame.advance_quarter()` 每季都会追加自动存档（docs/11 §6.2）。压测要量的是 SimCore
## 的稳定性，不是磁盘；600 季就是 600 次写盘，会把「引擎有没有崩」和「磁盘有没有满」搅在一起。
## 自动存档另有 `T-X-F-04` 单独把关。本文件因此走 Loader → SimState → TurnRunner 这条等价路径
## （与 docs/30 §7.2 给 `tools/bench_quarter.gd` 规定的计时口径同一条）。
extends JWTest

# ── 规模常量 ───────────────────────────────────────────────────────────────

## 契约规模的种子数（docs/30 §6.3：`root_seed = 1_000_000 + i`，`i ∈ [0, 100)`）。
const SEEDS_FULL: int = 100
## 日常闸门的种子数。压测进不了每次提交的门，但也不该完全不跑。
const SEEDS_DEFAULT: int = 5
## 契约规模的季数（长局 120 季）。
const QUARTERS_FULL: int = 120
## 种子基数（docs/30 §6.3）。
const ROOT_SEED_BASE: int = 1_000_000

## 覆盖种子数的环境变量名。
const ENV_SEEDS: String = "JW_STRESS_SEEDS"
## 覆盖季数的环境变量名。
const ENV_QUARTERS: String = "JW_STRESS_QUARTERS"

## 内容包根目录（`JWContentLoader.load_all` 的 root_path 口径）。
const CONTENT_ROOT: String = "res://content"

## 命令流档位（docs/30 §6.3「三档命令流」）。第 ② 档「脚本化路线」要 `route_a/b/c.jsonl`，
## 那三份路线脚本本波尚不存在（见返回的 open_questions），因此这里只实现能真跑的两档。
const TIER_EMPTY: int = 0
const TIER_FUZZ: int = 1
const TIER_N: int = 2
const TIER_NAMES: PackedStringArray = ["空命令", "合法随机命令 fuzz"]

## fuzz 档每季递交的命令条数。
const FUZZ_CMDS_PER_Q: int = 3

## 终局之后连续尝试推进的次数（INV-128：每次都必须是 REJECT 且哈希不变）。
const POST_END_TRIES: int = 3

## 六个整数槽（== `JWCommands.ARG_SLOTS`）。
const ARG_SLOTS: int = 6

## 支付优先级打包位宽（== `JWCommands.PRIORITY_BITS`）。
const PRIORITY_BITS: int = 3
## 支付优先级档数（== `JWUnits.PAY_LINE_N`）。
const PAY_LINE_N: int = 8

## 明细最多展开几条（展开全部报告没法看，展开 0 条等于没报告）。
const MAX_DETAIL_LINES: int = 8


func before_all() -> void:
	suite_note = ("docs/30 §6.3 T-X-E-11 / T-X-E-13 / T-X-E-14；默认 %d 种子 × %d 季，"
			+ "完整规模 %d 种子（%s=100）") % [SEEDS_DEFAULT, QUARTERS_FULL, SEEDS_FULL, ENV_SEEDS]


func before_each() -> void:
	JWResult.clear_pending()
	JWResult.set_step(0)


func after_each() -> void:
	JWResult.clear_pending()


# ══════════════════════════════════════════════════════════════════════════
# 测试方法（矩阵只跑一遍，六个断言各看一个侧面）
# ══════════════════════════════════════════════════════════════════════════

## 规模自报：实际跑了几个种子、几季。
## **这条断言的意义是防止「默认 5 个种子」被误读成「跑过 100 个」**，
## 顺带把规模旋钮本身钉死：环境变量给了什么，矩阵就必须跑什么。
func test_x_stress_scale_is_reported() -> void:
	var s: Summary = _summary()
	eq_int(s.seeds, _env_int(ENV_SEEDS, SEEDS_DEFAULT),
			"实际种子数必须等于 %s 指定的值（未指定时为缺省 %d，**不是** 契约规模 %d）"
			% [ENV_SEEDS, SEEDS_DEFAULT, SEEDS_FULL])
	eq_int(s.quarters, _env_int(ENV_QUARTERS, QUARTERS_FULL),
			"实际季数必须等于 %s 指定的值（未指定时为 %d）" % [ENV_QUARTERS, QUARTERS_FULL])
	print("[压测] 档位 %d ｜ 种子 %d（完整规模 %d，用 %s=%d 打开）｜ 季数 %d ｜ 计划季数 %d ｜ 墙钟 %d ms"
			% [TIER_N, s.seeds, SEEDS_FULL, ENV_SEEDS, SEEDS_FULL, s.quarters,
				s.seeds * s.quarters * TIER_N, s.elapsed_ms])
	if not s.booted:
		print("[压测] 未能开局：%s" % s.boot_note)
	else:
		print("[压测] 成功结算 %d 季 ｜ 终局 %d/%d ｜ 账本扩容 %d 次 ｜ fuzz 递交 %d 条"
				% [s.settled_q, s.terminated_runs, s.runs_total, s.log_grow_total,
					s.fuzz_submitted])
		print("[压测] 终局可读性：注册表 %d 条，其中按契约不可整数读的 %d 条（SoA 字符串 ID 列）"
				% [s.registry_entries, s.non_integer_entries.size()])


## 开局必须成功。开不了局，后面五条断言全部无从判定——这是红，不是跳过。
func test_x_content_boots_for_stress() -> void:
	var s: Summary = _summary()
	check(s.booted, ("压测无法开局：%s。docs/30 §6.3 的前置状态 FX-STRESS120 要求内容包能载入；"
			+ "载不进来时本套件的运行期断言一条也判定不了") % s.boot_note)


## 断言 ①②：每一季都成功结算、无 Fault，且 q 每季恰好 +1（INV-012）。
## 提前终局是合法结局（docs/12 §0.6），但**必须有终局登记**：少跑的季数只能由终局解释。
func test_x_all_quarters_settle_without_fault() -> void:
	var s: Summary = _summary()
	check(s.booted, "前置：压测必须先能开局（%s）" % s.boot_note)
	eq_int(s.faults.size(), 0, ("docs/30 §6.3 断言 ②：压测全程 Fault 计数必须为 0"
			+ "（INT_OVERFLOW / DIV_ZERO / INDEX_OUT_OF_RANGE / FLOAT_IN_STATE / NEGATIVE_CASH /"
			+ " NEGATIVE_INVENTORY / POPULATION_NOT_CONSERVED / LEDGER_IMBALANCE 逐个为 0）。"
			+ "实测故障 %d 条：%s") % [s.faults.size(), _head(s.faults)])
	eq_int(s.q_not_advanced.size(), 0, ("INV-012：q 只在 S08 末 +1。返回 OK 却没有 +1 说明八步没跑完。"
			+ "实测 %d 处：%s") % [s.q_not_advanced.size(), _head(s.q_not_advanced)])
	eq_int(s.unexplained_short_runs.size(), 0,
			("成功结算的季数少于计划，却没有终局登记——docs/12 §0.6 只有 REJECT / ARREARS / FAULT 三种"
			+ "失败语义，「静悄悄地少跑几季」不在其中。实测 %d 处：%s")
			% [s.unexplained_short_runs.size(), _head(s.unexplained_short_runs)])
	if s.early_terminated_runs == 0:
		eq_int(s.settled_q, s.seeds * s.quarters * TIER_N,
				"docs/30 §6.3 断言 ①：无提前终局时，成功结算的季数必须精确等于 种子 × 季 × 档位")
	else:
		eq_int(s.settled_q + s.shortfall_q, s.seeds * s.quarters * TIER_N,
				"成功结算季数 + 因终局少跑的季数必须精确等于计划季数（差额只能由终局解释）")


## 断言 ④⑤：每季末全部 P0 不变量残差为 0；金额、数量、价格、现金、库存五类越界计数为 0。
## `param.write_guard_sample_q` 在压测中强制为 1（docs/30 §6.3 断言 ④「抽样策略强制全开」）。
func test_x_no_out_of_range_writes() -> void:
	var s: Summary = _summary()
	check(s.booted, "前置：压测必须先能开局（%s）" % s.boot_note)
	eq_int(s.p0_failures.size(), 0, ("docs/30 §6.3 断言 ④：每季全部 P0 不变量残差必须为 0。"
			+ "实测 %d 处：%s") % [s.p0_failures.size(), _head(s.p0_failures)])
	eq_int(s.bound_violations.size(), 0, ("docs/30 §6.3 断言 ⑤：越界写入尝试计数必须为 0"
			+ "（|金额| ≤ %d、|数量| ≤ %d、price ∈ [%d, %d]，取自 R-SCALE-01 的新刻度）。"
			+ "实测 %d 处：%s") % [JWUnits.AMOUNT_MAX, JWUnits.QTY_MAX,
				JWUnits.PRICE_MIN, JWUnits.PRICE_MAX,
				s.bound_violations.size(), _head(s.bound_violations)])
	eq_int(s.guard_off_runs, 0,
			"docs/30 §6.3 断言 ④：压测中 param.write_guard_sample_q 必须被强制为 1（逐季全开）")


## 断言 ⑥：终局可正常记录——`run_terminated == true`、终止原因在枚举内且非 NONE、
## 终局状态的每个注册表条目都读得出来（发展档案的数据来源就是它们）；
## 其后任一 advance_quarter 返回 REJECT(E_RUN_TERMINATED) 且 state_hash 逐位不变（INV-128）。
func test_x_terminal_record_and_reject_after_end() -> void:
	var s: Summary = _summary()
	check(s.booted, "前置：压测必须先能开局（%s）" % s.boot_note)
	eq_int(s.terminated_runs, s.runs_total,
			"docs/30 §6.3 断言 ⑥：每个种子跑到头之后都必须 run_terminated == true（%d / %d）"
			% [s.terminated_runs, s.runs_total])
	eq_int(s.bad_termination_reasons.size(), 0,
			("终止原因必须落在 JWUnits.Termination 内且不是 NONE——终局了却说不出为什么，"
			+ "发展档案就没法写。实测 %d 处：%s")
			% [s.bad_termination_reasons.size(), _head(s.bad_termination_reasons)])
	eq_int(s.unreadable_entries.size(), 0,
			("终局状态必须整份可读：注册表 %d 个条目逐条读出时不得登记故障"
			+ "（读不出来的字段进不了发展档案，「字段缺失数 == 0」就无从谈起）。实测 %d 处：%s")
			% [s.registry_entries, s.unreadable_entries.size(), _head(s.unreadable_entries)])
	eq_int(s.empty_entries.size(), 0,
			("终局状态里不得有长度为 0 的数组条目——那是一个读不出任何元素的维度。"
			+ "`content.*` 条目出现这种情况通常说明内容包没有真正载进来。实测 %d 处：%s")
			% [s.empty_entries.size(), _head(s.empty_entries)])
	# 「按契约不能当整数读」的条目只能是 SoA 的字符串 ID 列。放宽到别的条目上，
	# 这条豁免就会变成一个永远不会失败的检查（docs/18 收尾三缺口里点名的那种静默漏洞）。
	var stray: Array[String] = []
	for id: String in s.non_integer_entries:
		if not id.ends_with(".id"):
			stray.append(id)
	eq_int(stray.size(), 0,
			("登记 METRIC_UNKNOWN 的条目只允许是 SoA 的字符串 ID 列（名字以 `.id` 结尾，"
			+ "docs/10 §11 排除清单）。实测 %d 个不是：%s") % [stray.size(), _head(stray)])
	eq_int(s.post_end_bad_code.size(), 0,
			("INV-128：终局后连续 %d 次 advance_quarter 必须全部返回 REJECT(E_RUN_TERMINATED = %d)。"
			+ "实测 %d 处不符：%s") % [POST_END_TRIES, JWResult.Reject.RUN_TERMINATED,
				s.post_end_bad_code.size(), _head(s.post_end_bad_code)])
	eq_int(s.post_end_hash_changed.size(), 0,
			"INV-128：被拒的推进必须状态一位不改（state_hash 逐位相同）。实测 %d 处：%s"
			% [s.post_end_hash_changed.size(), _head(s.post_end_hash_changed)])


## `T-X-E-13`：fuzz 档递交的必须**真的是合法命令**（形状与范围层零拒绝）；
## 语义层的拒绝（S02 的权限 / 资金 / 冷却）是正常结果，不在此断言。
## `T-X-E-14`：长局账本——行数任何时刻都不得越过容量，扩容次数记录在案（不作为失败判据）。
func test_x_fuzz_commands_are_legal_and_ledger_holds() -> void:
	var s: Summary = _summary()
	check(s.booted, "前置：压测必须先能开局（%s）" % s.boot_note)
	ge_int(s.fuzz_submitted, 1, "fuzz 档必须真的递交过命令，否则这一档等于没跑")
	eq_int(s.fuzz_shape_rejects.size(), 0,
			("T-X-E-13：fuzz 档生成的是**合法**命令，形状与范围层必须零拒绝"
			+ "（被拒说明生成器越界，那就不是在压合法路径）。实测 %d 处：%s")
			% [s.fuzz_shape_rejects.size(), _head(s.fuzz_shape_rejects)])
	eq_int(s.log_overflow.size(), 0,
			"T-X-E-14 / INV-011：账本行数任何时刻都不得超过容量。实测 %d 处：%s"
			% [s.log_overflow.size(), _head(s.log_overflow)])


# ══════════════════════════════════════════════════════════════════════════
# 汇总对象
# ══════════════════════════════════════════════════════════════════════════

## 一次压测矩阵的全部事实。**只登记事实，不做断言**——断言在上面的测试方法里。
##
## 明细列表一律用 `Array[String]` 而不是 `PackedStringArray`：Packed 系是值类型，
## 传进 `note()` 会被复制，追加就丢在副本里了（这类静默丢失正是本套件要抓的东西）。
class Summary extends RefCounted:

	## 每类明细的登记上限。
	const NOTE_CAP: int = 64

	## 是否成功开局。
	var booted: bool = false
	## 开局诊断（失败时原样带进失败消息）。
	var boot_note: String = "（未尝试）"
	## 本次实际使用的种子数。
	var seeds: int = 0
	## 本次实际使用的季数。
	var quarters: int = 0
	## 跑过的「种子 × 档位」次数。
	var runs_total: int = 0
	## 成功结算的季数合计。
	var settled_q: int = 0
	## 因终局而少跑的季数合计。
	var shortfall_q: int = 0
	## 未跑满计划季数的次数。
	var early_terminated_runs: int = 0
	## 结束时 run_terminated == true 的次数。
	var terminated_runs: int = 0
	## 注册表条目数（终局可读性检查的分母）。
	var registry_entries: int = 0
	## fuzz 档实际递交的命令条数。
	var fuzz_submitted: int = 0
	## 账本扩容次数合计（docs/30 §6.3 断言 ⑦：记录在案，不作为失败判据）。
	var log_grow_total: int = 0
	## WriteGuard 未能强制全开的次数。
	var guard_off_runs: int = 0
	## 整个矩阵的墙钟耗时（毫秒；仅供人读，性能门在 tools/bench_quarter.gd）。
	var elapsed_ms: int = 0

	## 故障明细。
	var faults: Array[String] = []
	## 返回 OK 但 q 没有 +1 的明细。
	var q_not_advanced: Array[String] = []
	## 少跑了季却没有终局登记的明细。
	var unexplained_short_runs: Array[String] = []
	## P0 不变量失败明细。
	var p0_failures: Array[String] = []
	## 越界明细（金额 / 数量 / 价格 / 现金为负 / 库存为负）。
	var bound_violations: Array[String] = []
	## 终止原因不合法的明细。
	var bad_termination_reasons: Array[String] = []
	## 终局状态读不出来的条目明细（长度 > 0 却仍登记故障——真缺陷）。
	var unreadable_entries: Array[String] = []
	## 终局状态里长度为 0 的数组条目明细（一个读不出任何元素的维度）。
	var empty_entries: Array[String] = []
	## 按契约就不能当整数读的条目（SoA 的 `ids[]` 是字符串列，`read_metric` 登记 METRIC_UNKNOWN）。
	## 它们不是缺陷，但也不能悄悄放过：条目名必须以 `.id` 结尾，否则就是真的未知指标。
	var non_integer_entries: Array[String] = []
	## 终局后推进返回码不对的明细。
	var post_end_bad_code: Array[String] = []
	## 终局后状态哈希变了的明细。
	var post_end_hash_changed: Array[String] = []
	## fuzz 命令被形状层拒绝的明细。
	var fuzz_shape_rejects: Array[String] = []
	## 账本行数越过容量的明细。
	var log_overflow: Array[String] = []

	## 追加一条明细；到上限后只在末尾留一条「还有更多」的记号，不再增长。
	func note(list: Array[String], line: String) -> void:
		if list.size() < NOTE_CAP:
			list.append(line)
		elif list.size() == NOTE_CAP:
			list.append("（同类明细已达 %d 条上限，后续不再展开）" % NOTE_CAP)


## 测试局部的 fuzz 随机流。**与 SimCore 的六条流完全独立**（docs/30 §6.3 第 ③ 档的硬要求）：
## 它不碰 `state.rng`、不写 `log.rng`，因此开不开 fuzz 都不改变模拟本身的抽样序列。
## 这里用 64 位 LCG 而不是 splitmix64：它只负责挑命令，取模偏置对「压合法路径」没有影响；
## SimCore 的抽样另有拒绝采样与黄金向量（`T-U-E-10`）把关，两者不共用一行代码。
class FuzzStream extends RefCounted:

	## LCG 乘数（Knuth MMIX）。
	const MUL: int = 6_364_136_223_846_793_005
	## LCG 增量（Knuth MMIX）。
	const INC: int = 1_442_695_040_888_963_407
	## 取高位用的掩码（62 位，保证非负）。
	const MASK62: int = (1 << 62) - 1

	## 内部状态。
	var _s: int = 0

	func _init(seed_v: int) -> void:
		_s = seed_v

	## 下一个非负整数。
	func next() -> int:
		_s = _s * MUL + INC
		return (_s >> 2) & MASK62

	## `[0, n)` 内的下一个整数（n ≤ 1 时恒为 0）。
	func below(n: int) -> int:
		if n <= 1:
			return 0
		return next() % n


# ══════════════════════════════════════════════════════════════════════════
# 矩阵运行（静态缓存：矩阵只跑一遍，六个测试方法共用同一份结果）
# ══════════════════════════════════════════════════════════════════════════

## 矩阵结果的静态缓存（运行器为每个测试方法新建实例，静态成员是共享结果的唯一通路）。
static var _cached: Summary = null


## 取汇总（第一次调用时真跑矩阵）。
static func _summary() -> Summary:
	if _cached == null:
		_cached = _run_matrix()
	return _cached


## 从环境变量取正整数；未设、非法或非正时用 fallback。
static func _env_int(name: String, fallback: int) -> int:
	var raw: String = OS.get_environment(name)
	if raw == "" or not raw.is_valid_int():
		return fallback
	var v: int = raw.to_int()
	return v if v > 0 else fallback


## 跑完整个压测矩阵（档位 × 种子），把事实写进 Summary。
static func _run_matrix() -> Summary:
	var s: Summary = Summary.new()
	s.seeds = _env_int(ENV_SEEDS, SEEDS_DEFAULT)
	s.quarters = _env_int(ENV_QUARTERS, QUARTERS_FULL)

	var t0: int = Time.get_ticks_msec()
	# 先用第一个种子探一次路：开不了局就别把同一条错误重复 seeds × TIER_N 遍。
	var probe: JWSimState = _boot(ROOT_SEED_BASE, s.quarters, s)
	if probe == null:
		s.elapsed_ms = Time.get_ticks_msec() - t0
		return s
	s.booted = true
	s.boot_note = "开局成功"
	s.registry_entries = probe.registry_size()

	var tier: int = 0
	while tier < TIER_N:
		var i: int = 0
		while i < s.seeds:
			_run_one(tier, ROOT_SEED_BASE + i, s)
			i += 1
		tier += 1
	s.elapsed_ms = Time.get_ticks_msec() - t0
	return s


## 按 docs/17 §4.33 `new_game` 的后置条件装配一份可推进的状态（不含自动存档）。
## 失败时把加载器的第一条错误与位置写进 `s.boot_note` 并返回 null。
static func _boot(seed_v: int, quarters: int, s: Summary) -> JWSimState:
	JWResult.clear_pending()
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	st.horizon_q = quarters

	var loader: JWContentLoader = JWContentLoader.new()
	var res: JWResult = loader.load_all(CONTENT_ROOT, st)
	if res == null:
		s.boot_note = "JWContentLoader.load_all 返回 null"
		return null
	if not res.ok:
		var where: String = "（无位置）"
		if loader.errors.size() > 0:
			where = loader.error_where(0)
		s.boot_note = ("载入 %s 失败：首个错误码 %d 于 %s；加载器共报 %d 条错误"
				% [CONTENT_ROOT, res.code, where, loader.errors.size()])
		return null

	st.build_id = JWGame.BUILD_ID
	st.content_hash = loader.content_hash
	st.param_set_version = loader.param_set_version
	var rc: int = st.rng.set_state_scalar(0, seed_v)
	if rc != JWResult.OK:
		s.boot_note = "注入 root_seed %d 失败，码 %d" % [seed_v, rc]
		return null

	# docs/30 §6.3 断言 ④：压测中 WriteGuard「强制全开」。`param.*` 是内容数据（docs/11 §5.15），
	# 压测夹具按契约把这一张卡改成 1，而不是去改 JWTurnRunner 的抽样逻辑。
	# 先取出再写回：Packed 系是值类型，`st.params[i] = 1` 这种写法容易只改到副本。
	if st.params.size() == JWUnits.PARAM_N:
		var p: PackedInt64Array = st.params
		p[JWUnits.Param.WRITE_GUARD_SAMPLE_Q] = 1
		st.params = p
		if st.params[JWUnits.Param.WRITE_GUARD_SAMPLE_Q] != 1:
			s.guard_off_runs += 1
	else:
		s.guard_off_runs += 1

	JWResult.clear_pending()
	var p0: int = st.check_all_p0()
	if p0 != JWResult.OK:
		s.boot_note = "载入后 P0 不变量即不成立，码 %d" % p0
		JWResult.clear_pending()
		return null
	return st


## 跑一个「档位 × 种子」。
static func _run_one(tier: int, seed_v: int, s: Summary) -> void:
	var st: JWSimState = _boot(seed_v, s.quarters, s)
	if st == null:
		s.note(s.faults, "档 %s 种子 %d：开局失败（%s）" % [TIER_NAMES[tier], seed_v, s.boot_note])
		return
	s.runs_total += 1

	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	var events: JWEventEngine = JWEventEngine.new()
	events.allocate()
	var runner: JWTurnRunner = JWTurnRunner.new(st, events)
	# fuzz 流的种子与模拟种子分开，免得「换一个 root_seed」同时改动两件事。
	var fz: FuzzStream = FuzzStream.new(seed_v * 2 + 1)

	var done: int = 0
	var aborted: bool = false
	while done < s.quarters:
		if st.politics != null and st.politics.run_terminated:
			break
		var q0: int = st.q
		if tier == TIER_FUZZ:
			_submit_fuzz(cmds, st, fz, s, seed_v)
		var rm: JWResult = cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, _zeros6(), st.q,
				st.policy_defs)
		if rm != null and not rm.ok:
			s.note(s.faults, "档 %s 种子 %d 第 %d 季：advance_quarter 标记被拒，码 %d"
					% [TIER_NAMES[tier], seed_v, q0, rm.code])
			aborted = true
			break

		var rc: int = runner.advance_quarter(cmds)
		if rc != JWResult.OK:
			s.note(s.faults, "档 %s 种子 %d 第 %d 季：advance_quarter 返回 %d（步骤 %d）"
					% [TIER_NAMES[tier], seed_v, q0, rc, JWResult.pending_step()])
			JWResult.clear_pending()
			aborted = true
			break
		if JWResult.has_pending():
			s.note(s.faults, "档 %s 种子 %d 第 %d 季：返回 OK 但仍挂着故障 %d（步骤 %d）"
					% [TIER_NAMES[tier], seed_v, q0, JWResult.pending_code(),
						JWResult.pending_step()])
			JWResult.clear_pending()
			aborted = true
			break
		if st.q != q0 + 1:
			s.note(s.q_not_advanced, "档 %s 种子 %d：第 %d 季后 q 仍是 %d"
					% [TIER_NAMES[tier], seed_v, q0, st.q])
			aborted = true
			break

		done += 1
		s.settled_q += 1
		_check_bounds(tier, seed_v, q0, st, s)
		_check_p0(tier, seed_v, q0, st, s)

	if st.ledger != null:
		s.log_grow_total += st.ledger.log_grow_count()
	if done < s.quarters:
		s.shortfall_q += s.quarters - done
		s.early_terminated_runs += 1
		if not aborted and (st.politics == null or not st.politics.run_terminated):
			s.note(s.unexplained_short_runs, "档 %s 种子 %d：只结算了 %d / %d 季且没有终局登记"
					% [TIER_NAMES[tier], seed_v, done, s.quarters])
	_check_terminal(tier, seed_v, done, aborted, st, runner, s)


## fuzz 档：递交若干条**形状与范围都合法**的命令。
## 只用四种命令码——它们的合法取值集合在 `JWCommands` 里是封闭的、不依赖剧本内容：
## 发债（额度 / 期限 / 持有人）、支付优先级全排列、撤销政策、开局唯一一次的施政目标。
static func _submit_fuzz(cmds: JWCommands, st: JWSimState, fz: FuzzStream, s: Summary,
		seed_v: int) -> void:
	var n: int = 0
	while n < FUZZ_CMDS_PER_Q:
		var args: PackedInt64Array = _zeros6()
		var kind: int = JWCommands.Kind.ISSUE_BOND
		if st.q == 0 and n == 0:
			# 施政目标只有 q == 0 合法（docs/11 §6.1 命令 12），因此不进随机池，开局定一次。
			kind = JWCommands.Kind.SELECT_MANDATE_GOAL
			args[JWCommands.SLOT_GOAL] = fz.below(3)
		else:
			var pick: int = fz.below(3)
			if pick == 0:
				# 发债：amount ∈ [1, AMOUNT_MAX]（这里取 0.1 U … 10 U 一档），
				# tenor ∈ [TENOR_MIN, TENOR_MAX]，holder ∈ {INVPOOL, ROW}。
				kind = JWCommands.Kind.ISSUE_BOND
				args[JWCommands.SLOT_BOND_AMOUNT] = 100_000_000 + fz.below(100) * 100_000_000
				args[JWCommands.SLOT_BOND_TENOR] = JWCommands.TENOR_MIN + fz.below(
						JWCommands.TENOR_MAX - JWCommands.TENOR_MIN + 1)
				args[JWCommands.SLOT_BOND_HOLDER] = fz.below(2)
			elif pick == 1:
				# 支付优先级：8 档全排列打包（少一档就是 E_PRIORITY_INCOMPLETE，那不叫合法命令）。
				kind = JWCommands.Kind.SET_PAYMENT_PRIORITY
				args[JWCommands.SLOT_PRIORITY_PACKED] = _packed_permutation(fz)
			else:
				# 撤销政策：下标在 [0, POLICY_N) 内即形状合法；没开启过的由 S02 语义层拒。
				kind = JWCommands.Kind.POLICY_REPEAL
				args[JWCommands.SLOT_POLICY] = fz.below(JWUnits.POLICY_N)

		var r: JWResult = cmds.submit(kind, args, st.q, st.policy_defs)
		s.fuzz_submitted += 1
		if r != null and not r.ok:
			s.note(s.fuzz_shape_rejects, "种子 %d 第 %d 季：命令码 %d 被形状层拒绝，码 %d"
					% [seed_v, st.q, kind, r.code])
		n += 1


## 生成 8 档支付优先级的一个全排列并按 3 位／档打包（Fisher–Yates，纯整数洗牌）。
static func _packed_permutation(fz: FuzzStream) -> int:
	var order: PackedInt64Array = PackedInt64Array()
	order.resize(PAY_LINE_N)
	var i: int = 0
	while i < PAY_LINE_N:
		order[i] = i
		i += 1
	var j: int = PAY_LINE_N - 1
	while j > 0:
		var k: int = fz.below(j + 1)
		var tmp: int = order[j]
		order[j] = order[k]
		order[k] = tmp
		j -= 1
	var packed: int = 0
	var m: int = 0
	while m < PAY_LINE_N:
		packed |= order[m] << (PRIORITY_BITS * m)
		m += 1
	return packed


## 六个零槽（未用到的槽必须为 0，INV-138 在整数槽层的唯一可机器检查形态）。
static func _zeros6() -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(ARG_SLOTS)
	a.fill(0)
	return a


## 断言 ⑤ 的逐季检查：价格、账本金额与数量、现金、库存五类越界。
static func _check_bounds(tier: int, seed_v: int, q: int, st: JWSimState, s: Summary) -> void:
	# 价格（R-SCALE-01 新刻度：PRICE ∈ [4×10⁸, 2.5×10⁹]）。
	if st.pricing != null:
		var price: PackedInt64Array = st.pricing.price
		var sec: int = 0
		while sec < JWUnits.S and sec < price.size():
			if price[sec] < JWUnits.PRICE_MIN or price[sec] > JWUnits.PRICE_MAX:
				s.note(s.bound_violations, "档 %s 种子 %d 第 %d 季：部门 %d 价格 %d 越界"
						% [TIER_NAMES[tier], seed_v, q, sec, price[sec]])
			sec += 1

	# 本季账本行的金额与数量（`log_reset_quarter` 每季 S01 清一次，行数即本季的量）。
	if st.ledger != null:
		var cap: int = st.ledger.log_capacity()
		var rows: int = st.ledger.log_row_count()
		if rows > cap:
			s.note(s.log_overflow, "档 %s 种子 %d 第 %d 季：账本行数 %d > 容量 %d"
					% [TIER_NAMES[tier], seed_v, q, rows, cap])
			rows = cap
		var deltas: PackedInt64Array = st.ledger.l_delta
		var qtys: PackedInt64Array = st.ledger.l_qty
		var i: int = 0
		while i < rows and i < deltas.size() and i < qtys.size():
			if JWMath.absi(deltas[i]) > JWUnits.AMOUNT_MAX:
				s.note(s.bound_violations, "档 %s 种子 %d 第 %d 季：账本第 %d 行金额 %d 越过 AMOUNT_MAX"
						% [TIER_NAMES[tier], seed_v, q, i, deltas[i]])
			if JWMath.absi(qtys[i]) > JWUnits.QTY_MAX:
				s.note(s.bound_violations, "档 %s 种子 %d 第 %d 季：账本第 %d 行数量 %d 越过 QTY_MAX"
						% [TIER_NAMES[tier], seed_v, q, i, qtys[i]])
			i += 1

	# 现金为负（Fault.NEGATIVE_CASH 的同一件事，从状态侧再看一遍）。pubserv（17..20）无自有现金。
	if st.accounts != null:
		var a: int = 0
		while a <= JWIds.AGENT_OPENING:
			if a < JWIds.AGENT_PUBSERV_BASE or a >= JWIds.AGENT_GROUP_BASE:
				var c: int = st.accounts.cash_of(a)
				if c < 0:
					s.note(s.bound_violations, "档 %s 种子 %d 第 %d 季：主体 %d 现金为负（%d）"
							% [TIER_NAMES[tier], seed_v, q, a, c])
			a += 1

	# 库存为负（Fault.NEGATIVE_INVENTORY 的同一件事）。
	if st.inventory != null:
		var out_inv: PackedInt64Array = st.inventory.inv_output
		var k: int = 0
		while k < out_inv.size():
			if out_inv[k] < 0:
				s.note(s.bound_violations, "档 %s 种子 %d 第 %d 季：inv_output[%d] 为负（%d）"
						% [TIER_NAMES[tier], seed_v, q, k, out_inv[k]])
			k += 1


## 断言 ④ 的逐季检查：季末全部 P0 不变量。
static func _check_p0(tier: int, seed_v: int, q: int, st: JWSimState, s: Summary) -> void:
	JWResult.clear_pending()
	var rc: int = st.check_all_p0()
	if rc != JWResult.OK:
		s.note(s.p0_failures, "档 %s 种子 %d 第 %d 季：check_all_p0 返回 %d"
				% [TIER_NAMES[tier], seed_v, q, rc])
	JWResult.clear_pending()


## 断言 ⑥：终局登记、终局状态可读、终局之后的 REJECT 与哈希不变。
## `aborted == true`（本局被故障打断）时不再追问终局：那一局的第一现场已经登记在 faults 里，
## 再报一条「没有终局」只会把因果颠倒过来。
static func _check_terminal(tier: int, seed_v: int, done: int, aborted: bool, st: JWSimState,
		runner: JWTurnRunner, s: Summary) -> void:
	if aborted:
		return
	if st.politics == null:
		s.note(s.bad_termination_reasons, "档 %s 种子 %d：politics 块为空，无从判定终局"
				% [TIER_NAMES[tier], seed_v])
		return
	if not st.politics.run_terminated:
		s.note(s.bad_termination_reasons, "档 %s 种子 %d：结算 %d 季后 run_terminated 仍为 false"
				% [TIER_NAMES[tier], seed_v, done])
		return
	s.terminated_runs += 1
	var reason: int = st.politics.termination_reason
	if reason <= JWUnits.Termination.NONE \
			or reason > JWUnits.Termination.FISCAL_RESTRUCTURING_FAILED:
		s.note(s.bad_termination_reasons, "档 %s 种子 %d：termination_reason = %d 不在枚举内或为 NONE"
				% [TIER_NAMES[tier], seed_v, reason])

	# 终局状态整份可读：发展档案的每一项都从注册表条目取数，读不出来就写不出档案。
	# 三种结果分开登记，因为它们指向完全不同的东西：
	#   · METRIC_UNKNOWN + 长度 0 —— SoA 的 `ids[]` 是字符串列，按 docs/10 §11 的排除清单
	#     本来就没有可比较的整数取值。不是缺陷，但条目名必须以 `.id` 结尾（下面另有断言）。
	#   · INDEX_OUT_OF_RANGE + 长度 0 —— 这个维度在终局状态里根本没有数据
	#     （`content.*` 条目出现这种情况，通常说明内容包没有真正载进来）。
	#   · 其余 —— 读口本身有问题。
	var n: int = st.registry_size()
	var e: int = 0
	while e < n:
		JWResult.clear_pending()
		var arr: PackedInt64Array = st.registry_array_copy(e)
		st.read_metric(e, 0)
		if arr.size() > 1:
			st.read_metric(e, arr.size() - 1)
		if JWResult.has_pending():
			var code: int = JWResult.pending_code()
			var id: String = st.registry_id(e)
			if arr.size() == 0 and code == JWResult.Fault.METRIC_UNKNOWN:
				s.note(s.non_integer_entries, id)
			elif arr.size() == 0 and code == JWResult.Fault.INDEX_OUT_OF_RANGE:
				s.note(s.empty_entries, "档 %s 种子 %d：数组条目 %s 长度为 0"
						% [TIER_NAMES[tier], seed_v, id])
			else:
				s.note(s.unreadable_entries, "档 %s 种子 %d：条目 %s（长度 %d）读出时登记故障 %d"
						% [TIER_NAMES[tier], seed_v, id, arr.size(), code])
		JWResult.clear_pending()
		e += 1

	# INV-128：终局后连续推进必须 REJECT，且状态一位不改。
	var before: String = st.state_hash()
	var tries: int = 0
	while tries < POST_END_TRIES:
		JWResult.clear_pending()
		var rc: int = runner.advance_quarter(null)
		if rc != JWResult.Reject.RUN_TERMINATED:
			s.note(s.post_end_bad_code, "档 %s 种子 %d：终局后第 %d 次推进返回 %d（期望 %d）"
					% [TIER_NAMES[tier], seed_v, tries + 1, rc, JWResult.Reject.RUN_TERMINATED])
		if st.state_hash() != before:
			s.note(s.post_end_hash_changed, "档 %s 种子 %d：终局后第 %d 次推进改变了 state_hash"
					% [TIER_NAMES[tier], seed_v, tries + 1])
		JWResult.clear_pending()
		tries += 1


## 明细列表的前几条（展开全部报告没法看）。
func _head(list: Array[String]) -> String:
	if list.is_empty():
		return "（无）"
	var out: String = ""
	var i: int = 0
	while i < list.size() and i < MAX_DETAIL_LINES:
		out += "\n      · " + list[i]
		i += 1
	if list.size() > MAX_DETAIL_LINES:
		out += "\n      · …… 其余 %d 条省略" % (list.size() - MAX_DETAIL_LINES)
	return out
