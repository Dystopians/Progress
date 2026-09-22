## 40 季重放用例（suite = replay）。
##
## 覆盖矩阵 ID（docs/30 §6.2「确定性与重放」）：
##   T-R-E-01 test_r_replay_40      —— 同种子同命令流两遍逐季 state_hash / step_hash 逐位相同
##   T-R-E-02 test_r_save_roundtrip —— 中途存档 → 读档 → 继续，与不存档直跑逐位相同
## 另承担计划书 §15 的 G1 出场门槛（「无来源资金或物资」三条）：
##   全程账本残差恒为 0、库存恒等式恒成立、人口守恒恒成立。
##
## 依据（只依据契约，不依据实现）：
##   - docs/18_rulings.md   R-SCALE-01（1 U = 10⁹ μU）
##   - docs/12_simulation_contract.md §0.6（OK / REJECT / FAULT 三种语义）、§10（不变量时点表）
##   - docs/11_data_contract.md §6.1（命令流协议与 kind 99 的位置约束）、§6.4/§6.6（存档与读档）
##   - docs/10_variable_dictionary.md §14：INV-012, INV-014, INV-015..021, INV-047, INV-059,
##     INV-071..073, INV-128, INV-131, INV-133
##   - docs/17_api_skeleton.md §4.29 JWTurnRunner、§4.34 JWReplay、§4.32 JWSaves、§5 八步调用序列
##   - docs/30_quality_gates.md §6.1（整数世界里「无 NaN」的改写）、§6.2
##
## 期望值来源（docs/30 §0.3 第 4 条）：本文件不从实现里取任何期望值。
##   · 确定性断言比对的是**同一段代码的两次独立运行**，期望值是「逐位相同」这一契约本身；
##   · 守恒断言全部由本文件用上一季末的自取快照**独立复算**，
##     不调用 `check_stock_identity` / `check_conservation` / `check_cash_closure` —— 那三个函数
##     正是被测对象，拿它们的返回值当期望值等于没有检查。
##
## 纪律：JWResult 的故障登记是静态的且会跨测试方法残留；每个方法前后都 clear_pending()。
##   跑批结果按 (种子, 路线) 缓存在 static var 里 —— 一次 40 季跑批要载一次内容包，
##   每个测试方法各跑一遍既慢又不会给出额外信息。
extends JWTest

# ── 夹具常量 ────────────────────────────────────────────────────────────────

## 出厂内容包根目录（docs/30 的 FX-BASE）。
const CONTENT_ROOT: String = "res://content"

## 跑批季数。剧本 `horizon_q == 40`，第 40 季（q == 39）季末由 JWPolitics 置终局。
const TARGET_Q: int = 40

## 存档 → 读档 → 继续的切分点（docs/30 T-R-E-02 用的 q = 17）。
const SPLIT_Q: int = 17

## 基准种子（docs/30 §6.2 登记的 `root_seed = 1_000_000`）。
const SEED_A: int = 1_000_000

## 对照种子：只改种子，命令流与内容包完全不变。
const SEED_B: int = 1_000_001

## 本用例专用的存档槽位（跑完即删）。
const SAVE_SLOT: String = "jw_forty_quarters_test"

## 每季步骤哈希条数（docs/11 §6.5 的 checkpoints 行形状）。
const STEP_N: int = 8

## 随机流条数（JWUnits.RNG_STREAM_N；此处写死是为了让断言里的 6 有出处可查）。
const STREAM_N: int = 6

## `log.rng` 每行摊平后的列数：stream / draw_index / raw / mapped。
const RNG_COLS: int = 4

# ── 路线脚本（route_a 的整数形态；本文件是它的唯一定义处） ──────────────────
#
# 七条命令全部只用**取值范围可在 docs/11 §6.1 与 systems/commands.gd 的槽位表上逐条核对**
# 的字面量，不读任何运行期状态 —— 否则两次运行提交的字节就不再逐位相同，
# 「同命令流」这个前提本身就塌了。
# 被 S02 按业务规则拒掉是允许的（INV-137：被拒命令照样进命令流并复现），
# 拒绝本身也是确定性的一部分。

## 命令生效季。
const ROUTE_Q: PackedInt64Array = [0, 5, 9, 14, 20, 27, 33]

## 命令码（JWCommands.Kind 的数值，docs/11 §6.1 规定值不得改）。
## 12 select_mandate_goal / 10 set_payment_priority / 8 issue_bond /
## 11 set_standing_rule / 8 / 7 budget_reallocate / 10
const ROUTE_KIND: PackedInt64Array = [12, 10, 8, 11, 8, 7, 10]

## 七条命令的参数，每条固定占 6 个槽（JWCommands.ARG_SLOTS），行优先摊平。
##   行 0  q=0   goal = 0（industry）
##   行 1  q=5   packed = Σ i·8ⁱ（i = 0..7）= 16_434_824，恒等排列，8 档齐全
##   行 2  q=9   发行 1 U、期限 8 季、持有方 invpool(0)
##   行 3  q=14  常设指令 0（运行费自动拨付）置 1
##   行 4  q=20  发行 2 U、期限 12 季、持有方 invpool(0)
##   行 5  q=27  预算从第 7 档划 0.1 U 到第 4 档
##   行 6  q=33  packed = Σ (7−i)·8ⁱ = 342_391，逆序排列，8 档同样齐全
const ROUTE_ARGS: PackedInt64Array = [
	0, 0, 0, 0, 0, 0,
	16_434_824, 0, 0, 0, 0, 0,
	1_000_000_000, 8, 0, 0, 0, 0,
	0, 1, 0, 0, 0, 0,
	2_000_000_000, 12, 0, 0, 0, 0,
	7, 4, 100_000_000, 0, 0, 0,
	342_391, 0, 0, 0, 0, 0,
]

# ── 跑批结果缓存（同一份结果供多个测试方法共用） ────────────────────────────

## 基准种子第一遍。
static var _trace_a1: Trace = null
## 基准种子第二遍（与第一遍逐位可比）。
static var _trace_a2: Trace = null
## 对照种子。
static var _trace_b: Trace = null
## 存档 → 读档 → 继续。
static var _trace_split: Trace = null
## 空业务命令流（只有推进标记）的本地跑批，用来与 JWReplay.run_to 对照。
static var _trace_plain: Trace = null
## JWReplay.run_to 的终态哈希（空业务命令流，权威重放口径）。
static var _replay_hash: String = ""
## JWReplay.run_to 的返回码与实际跑到的季号。
static var _replay_code: int = -1
static var _replay_q: int = -1
## 载入失败时的错误位置（与 Trace.boot_where 同口径）。
static var _replay_where: String = ""


func before_all() -> void:
	suite_note = "T-R-E-01 / T-R-E-02；INV-012/014/015..021/047/059/071..073/131/133"


func before_each() -> void:
	JWResult.clear_pending()
	JWResult.set_step(0)


func after_each() -> void:
	JWResult.clear_pending()


# ══════════════════════════════════════════════════════════════════════════
# A 组 跑得通：连续 40 季不崩溃、不进故障、不提前终局
# ══════════════════════════════════════════════════════════════════════════

## docs/12 §0.6 + INV-012：40 次 `advance_quarter` 必须全部返回 OK，季号严格 +1。
## docs/30 §6.1 把「无崩溃 / 无 NaN」改写成「无 Fault 登记」，这里逐季核对返回码。
func test_r_forty_quarters_run_without_fault() -> void:
	var t: Trace = _trace(SEED_A, 1)
	if not _startable(t, "40 季跑批"):
		return
	eq_int(t.boot_code, JWResult.OK, "载入出厂内容包必须成功（docs/30 的 FX-BASE 必须可载入）")
	eq_int(t.fault_code, JWResult.OK,
			"INV-012：40 季推进中不得出现任何 Fault（第 %d 季返回码 %d）" % [t.fault_q, t.fault_code])
	eq_int(t.q_done, TARGET_Q,
			"必须连续跑满 40 季（docs/30 T-R-E-01 的前置：route_a × 40 季）")
	eq_int(t.final_q, TARGET_Q, "INV-012：40 次推进之后 state.time.q 必须恰好等于 40")
	eq_int(t.state_hash.size(), TARGET_Q, "逐季 state_hash 必须一季一条，共 40 条")
	eq_int(t.step_hash.size(), TARGET_Q * STEP_N,
			"INV-014：逐季 8 个步骤哈希必须齐备，共 320 条")
	eq_int(t.empty_step_hash, 0,
			"INV-014：步骤哈希不得为空串（空串意味着该步没有被哈希，重放二分就有盲区）")
	eq_int(t.pending_after, JWResult.OK,
			"跑批结束时不得留下挂起的故障登记（docs/12 §9：带着挂起故障继续推进等于埋掉第一现场）")


## INV-128：跑满 horizon 之后必须进终局，且终局后的推进是 REJECT 而不是 FAULT，状态一位不改。
func test_r_run_terminates_at_horizon_and_rejects_further_advance() -> void:
	var t: Trace = _trace(SEED_A, 1)
	if not _startable(t, "终局判定"):
		return
	check(t.terminated, "剧本 horizon_q == 40，第 40 季季末必须置 run_terminated（docs/12 §8）")
	eq_int(t.extra_code, JWResult.Reject.RUN_TERMINATED,
			"INV-128：终局后的 advance_quarter 必须返回 REJECT(E_RUN_TERMINATED) == 1000")
	eq_str(t.hash_after_extra, t.state_hash[t.state_hash.size() - 1],
			"INV-128：被拒的推进不得改动状态，state_hash 必须逐位不变")


# ══════════════════════════════════════════════════════════════════════════
# B 组 确定性：同种子同命令流两遍逐位相同；换种子必须不同
# ══════════════════════════════════════════════════════════════════════════

## T-R-E-01 / INV-014：两遍独立跑批的逐季 state_hash（40 次）与逐季 8 个 step_hash（320 次）
## 必须字符串精确相等。`log.rng` 的条数与逐条取值同样必须完全相同。
func test_r_replay_40() -> void:
	var a: Trace = _trace(SEED_A, 1)
	var b: Trace = _trace(SEED_A, 2)
	if not _startable(a, "重放第一遍") or not _startable(b, "重放第二遍"):
		return
	eq_int(b.q_done, a.q_done, "两遍必须跑到同一季（跑批长度不同就没有逐位可比性）")

	var q_diff: int = _first_str_diff(a.state_hash, b.state_hash)
	eq_int(q_diff, -1,
			"T-R-E-01 / INV-014：同构建 + 同内容 + 同种子 + 同命令流，逐季 state_hash 必须逐位相同"
			+ "（第一处分歧在 q = %d）" % q_diff)

	var s_diff: int = _first_str_diff(a.step_hash, b.step_hash)
	eq_int(s_diff, -1,
			"INV-014：逐季 8 个步骤哈希必须逐位相同（第一处分歧在 q = %d 的第 %d 步）"
			% [JWMath.floor_div(maxi(s_diff, 0), STEP_N), maxi(s_diff, 0) % STEP_N + 1])

	eq_int_array(b.rng_rows, a.rng_rows,
			"INV-011：两遍每季的 log.rng 行数必须逐季相同")
	eq_int(a.rng_log.size(), JWMath.sum(a.rng_rows) * RNG_COLS,
			"log.rng 的摊平长度必须等于 Σ 逐季行数 × %d 列（对不上说明采集本身漏了行）"
			% RNG_COLS)
	eq_int_array(b.rng_log, a.rng_log,
			"INV-011 / INV-014：两遍 log.rng 的 (stream, draw_index, raw, mapped) 必须逐行逐列相同")
	eq_int_array(b.draw_count, a.draw_count,
			"INV-131：两遍每季末的 6 个 draw_count 必须逐个精确相等")
	eq_int_array(b.cmd_code, a.cmd_code,
			"INV-137：两遍同一条命令的受理/拒绝判定必须完全相同（拒绝也要逐位复现）")


## 换种子必须换结果：否则随机流没有真的参与结算，前一条的「逐位相同」就退化成恒真式。
## 这条是 test_r_replay_40 的负对照 —— 缺了它，把 state_hash 写成常量也能让上一条变绿。
func test_r_different_seed_diverges() -> void:
	var a: Trace = _trace(SEED_A, 1)
	var b: Trace = _trace(SEED_B, 1)
	if not _startable(a, "基准种子") or not _startable(b, "对照种子"):
		return
	eq_int(b.q_done, TARGET_Q, "对照种子同样必须跑满 40 季（跑不动就证明不了差异来自种子）")
	ne_int(b.root_seed, a.root_seed, "对照组的 root_seed 必须与基准组不同，否则本条无意义")

	var q_diff: int = _first_str_diff(a.state_hash, b.state_hash)
	ge_int(q_diff, 0,
			"换种子之后 40 季里必须至少有一季的 state_hash 不同"
			+ "（全程相同 ⇒ 随机流没有进入结算，INV-009/014 的确定性检查是空的）")
	check(a.state_hash[a.state_hash.size() - 1] != b.state_hash[b.state_hash.size() - 1],
			"换种子之后第 40 季末的 state_hash 必须不同")


# ══════════════════════════════════════════════════════════════════════════
# C 组 存档：中途存档 → 读档 → 继续，与不存档直跑逐位相同
# ══════════════════════════════════════════════════════════════════════════

## T-R-E-02 / INV-131 / INV-133：在 q = 17 存档，换一套全新的状态栈读回来再跑到第 40 季，
## 逐季 state_hash 与 step_hash 必须与直跑分支逐位相同；6 个 draw_count 同样逐个相等。
func test_r_save_roundtrip() -> void:
	var a: Trace = _trace(SEED_A, 1)
	var s: Trace = _split_trace()
	if not _startable(a, "直跑分支"):
		return
	eq_int(s.boot_code, JWResult.OK, "存档分支的内容包载入必须成功")
	eq_int(s.save_code, JWResult.OK,
			"docs/11 §6.4：q = %d 的存档必须写出成功（码 %d）" % [SPLIT_Q, s.save_code])
	eq_int(s.load_code, JWResult.OK,
			"docs/11 §6.6 / INV-132：刚写出的存档必须能原样读回（码 %d）" % s.load_code)
	check_false(s.read_only_required,
			"INV-134：同一份内容包读回自己的存档，不得被判成只读检视")
	check_false(s.replay_unreliable,
			"INV-134：同一构建读回自己的存档，不得被判成重放不可靠")
	eq_int(s.fault_code, JWResult.OK,
			"读档之后必须能继续推进到第 40 季（第 %d 季返回码 %d）" % [s.fault_q, s.fault_code])
	eq_int(s.q_done, TARGET_Q, "存档分支同样必须跑满 40 季")

	var q_diff: int = _first_str_diff(a.state_hash, s.state_hash)
	eq_int(q_diff, -1,
			"T-R-E-02 / INV-133：save → load → advance 与直接 advance 的逐季 state_hash 必须逐位相同"
			+ "（第一处分歧在 q = %d；q < %d 是存档前的共同前缀，分歧只可能来自存档漏装状态）"
			% [q_diff, SPLIT_Q])
	var s_diff: int = _first_str_diff(a.step_hash, s.step_hash)
	eq_int(s_diff, -1, "INV-133：两分支逐季 8 个步骤哈希必须逐位相同")
	eq_int_array(s.draw_count, a.draw_count,
			"INV-131：两分支每季末的 6 个 draw_count 必须逐个精确相等（读档不得重抽）")
	eq_int_array(s.rng_log, a.rng_log,
			"ADV-06 / INV-109：两分支的 log.rng 必须逐行相同 —— 读档重抽即 save-scum 成立")


# ══════════════════════════════════════════════════════════════════════════
# D 组 权威重放：JWReplay.run_to 与本地逐季驱动必须给出同一个终态
# ══════════════════════════════════════════════════════════════════════════

## INV-133：`JWReplay.run_to`（application 层的权威重放口径，自带每季推进标记）
## 与本文件按 docs/17 §5 逐季驱动 JWTurnRunner 得到的终态必须逐位相同。
## 两条路径各自独立装配状态栈，因此这条同时钉死「重放栈没有走私任何额外初始化」。
func test_r_replay_run_to_matches_local_driver() -> void:
	var p: Trace = _plain_trace()
	_ensure_replay_run()
	if not _startable(p, "空命令流本地跑批"):
		return
	# 测试口径更正（docs/18 第五轮）：本条检验的是 INV-133「权威重放与逐季驱动逐位相同」，不是「这一局必须活满 40 季」。
	# 空命令流带冲击的一局可以因预算审查连败而按规则终局（INV-128，合法结局）；此时权威重放必须在**同一季**、
	# 以**同一个码**停下，终态逐位相同。其余任何码仍按故障判红。
	var expect_code: int = JWResult.OK
	var expect_q: int = TARGET_Q
	if p.fault_code == JWResult.Reject.RUN_TERMINATED:
		expect_code = JWResult.Reject.RUN_TERMINATED
		expect_q = p.q_done
	eq_int(_replay_code, expect_code,
			"JWReplay.run_to 必须与逐季驱动同样跑到终点（逐季驱动停在第 %d 季、码 %d；重放实际码 %d）。%s"
			% [p.q_done, p.fault_code, _replay_code, _replay_where])
	eq_int(_replay_q, expect_q, "JWReplay.run_to 之后 last_q 必须等于逐季驱动的结算季数")
	check(_replay_hash != "", "JWReplay.run_to 必须留下可比对的终态（last_state 不得为空）")
	eq_str(_replay_hash, p.state_hash[p.state_hash.size() - 1],
			"INV-133：权威重放与逐季驱动的第 40 季末 state_hash 必须逐位相同")


## INV-014 / INV-133：`JWReplay.verify` 是重放的权威入口 —— 它**不读 state.json**，
## 只按 commands.jsonl 从 q = 0 重跑，逐季与 checkpoints.jsonl 的 state_hash 比对。
## 它必须报「无分歧」：divergence_q == −1 且 divergence_step == −1。
## 这条与 test_r_save_roundtrip 互补：后者证明「读档能接着跑」，
## 本条证明「只凭命令流也能从头长出同一条轨迹」——存档漏装状态时前者红，
## 结算读了命令流之外的东西时本条红。
func test_r_authoritative_replay_verify_finds_no_divergence() -> void:
	var s: Trace = _split_trace()
	if s.boot_code != JWResult.OK:
		check(false, "权威重放无法起跑：出厂内容包未能载入（code=%d）。%s"
				% [s.boot_code, s.boot_where])
		return
	eq_int(s.checkpoint_code, JWResult.OK,
			"docs/11 §6.5：逐季 append_checkpoint 必须全部写出成功（首个错误码 %d）"
			% s.checkpoint_code)
	eq_int(s.checkpoint_rows, SPLIT_Q,
			"存档前的每一季都必须留下一行检查点，共 %d 行" % SPLIT_Q)
	eq_int(s.verify_code, JWResult.OK,
			"INV-014：权威重放必须逐季命中 checkpoints.jsonl 的 state_hash（返回码 %d）"
			% s.verify_code)
	eq_int(s.verify_divergence_q, -1,
			"JWReplay.verify 必须报告「无分歧季」（实际 divergence_q = %d）" % s.verify_divergence_q)
	eq_int(s.verify_divergence_step, -1,
			"JWReplay.verify 必须报告「无分歧步」（实际 divergence_step = %d）"
			% s.verify_divergence_step)


# ══════════════════════════════════════════════════════════════════════════
# E 组 无来源资金（计划书 §15 的 G1 出场门槛之一）
#   全部由本文件独立复算：账本行、56 个 cash 科目、60 个主体的资产负债残差。
# ══════════════════════════════════════════════════════════════════════════

## INV-015 / INV-016：本季账本里每一笔 txn 的有符号行之和必须为 0。
## 复算方式：按 `log.ledger.txn_id` 分组求和，与实现的任何自检函数无关。
func test_r_ledger_every_txn_balances() -> void:
	var t: Trace = _trace(SEED_A, 1)
	if not _startable(t, "账本双边入账"):
		return
	ge_int(t.txn_total, 1, "40 季里必须真的记过账（一笔都没有的话本条是空检查）")
	eq_int(t.txn_unbalanced, 0,
			"INV-015：每一笔 txn 的行之和必须精确为 0（不平的笔数 %d，第一例：%s）"
			% [t.txn_unbalanced, t.first_money])
	ge_int(t.ledger_row_total, t.txn_total * 2,
			"INV-015：每笔 txn 至少两条过账行（两端账户必须不同）；"
			+ "40 季共 %d 行 / %d 笔，行数少于两倍笔数说明存在单腿分录"
			% [t.ledger_row_total, t.txn_total])


## INV-017 / INV-018：全经济现金总量恒等于剧本登记的 `scenario.total_cash_uu`。
## 复算方式：本文件自己对 56 个 cash 科目求和（AGENT_N 减去 4 个无现金的 pubserv），
## 不调 `JWAccount.total_cash()`，也不调 `check_cash_closure`。
func test_r_no_money_created_or_destroyed() -> void:
	var t: Trace = _trace(SEED_A, 1)
	if not _startable(t, "现金闭合"):
		return
	eq_int(t.cash_violations, 0,
			"INV-018：40 季里每一季末 Σ cash 都必须精确等于 state.total_cash_uu"
			+ "（违例 %d 次，第一例：%s）" % [t.cash_violations, t.first_money])
	eq_int(t.total_cash_moved, 0,
			"INV-018：`state.total_cash_uu` 本身是常量，40 季内不得被改写"
			+ "（它一旦跟着余额走，现金闭合就变成恒真式）")
	ge_int(t.cash_total_first, 1,
			"开局的全经济现金总量必须为正（为 0 说明开账根本没跑，后面的闭合断言无意义）")


## INV-019 / INV-020：逐主体资产负债恒等式残差为 0，且 Σ 应收 == Σ 应付。
## 复算方式：按 docs/10 §2.2 的科目方向约定逐科目加减，nw 取负。
func test_r_balance_sheet_and_receivable_payable_close() -> void:
	var t: Trace = _trace(SEED_A, 1)
	if not _startable(t, "资产负债闭合"):
		return
	eq_int(t.balance_violations, 0,
			"INV-020：每季末 60 个主体的资产负债残差都必须为 0"
			+ "（违例 %d 次，第一例：%s）" % [t.balance_violations, t.first_money])
	eq_int(t.recv_pay_violations, 0,
			"INV-019：每季末 Σ recv 必须精确等于 Σ pay（违例 %d 次）" % t.recv_pay_violations)


# ══════════════════════════════════════════════════════════════════════════
# F 组 无来源物资（计划书 §15 的 G1 出场门槛之二）
# ══════════════════════════════════════════════════════════════════════════

## INV-047：逐 cell 的成品与投入库存恒等式。
## 复算方式：用**上一季末本文件自取的快照**作期初值，
##   可库存部门 `期末 == 期初 + 实际产出 − 售出 − 损耗`；
##   不可库存部门（io.storable == 0）期末库存恒为 0（docs/10 §4.5）。
## 投入侧 `期末 == 期初 + 采购 − 消耗 − 损耗`，逐 (cell, 品种) 64 条。
func test_r_inventory_identity_holds_every_quarter() -> void:
	var t: Trace = _trace(SEED_A, 1)
	if not _startable(t, "库存恒等式"):
		return
	eq_int(t.inv_out_violations, 0,
			"INV-047：成品库存恒等式必须逐季逐 cell 成立"
			+ "（违例 %d 次，第一例：%s）" % [t.inv_out_violations, t.first_goods])
	eq_int(t.inv_in_violations, 0,
			"INV-047：投入库存恒等式必须逐季逐 (cell, 品种) 成立（违例 %d 次）"
			% t.inv_in_violations)
	eq_int(t.inv_negative, 0,
			"INV-048：库存不得为负（出现负库存即凭空消灭物资，违例 %d 次）" % t.inv_negative)
	eq_int(t.nonstorable_stock, 0,
			"INV-049：energy 与 services 这类不可库存部门的成品库存必须恒为 0（违例 %d 次）"
			% t.nonstorable_stock)


## INV-059：卖方库存减少量与市场成交量逐部门相等；成交 + 未满足 == 需求。
## 这条把「物资从哪来」与「物资到哪去」两侧各锁一次 —— 只锁一侧的话，
## 两侧同时多算同一笔就查不出来。
func test_r_market_clearing_matches_physical_flows() -> void:
	var t: Trace = _trace(SEED_A, 1)
	if not _startable(t, "市场出清对账"):
		return
	eq_int(t.sold_traded_violations, 0,
			"INV-059：Σ 卖方售出量必须逐部门精确等于 Σ 市场成交量（违例 %d 次，第一例：%s）"
			% [t.sold_traded_violations, t.first_goods])
	eq_int(t.demand_split_violations, 0,
			"INV-059：成交量 + 未满足量必须逐部门精确等于需求量（违例 %d 次）"
			% t.demand_split_violations)


# ══════════════════════════════════════════════════════════════════════════
# G 组 人口守恒（计划书 §15 的 G1 出场门槛之三）
# ══════════════════════════════════════════════════════════════════════════

## INV-071 / INV-072 / INV-073：逐组来源去向齐全、Σ 迁入 == Σ 迁出、
## 全国人口只由出生流入、只由死亡流出。
## 复算方式：期初值取**上一季末本文件自取的 36 个数**，不读 `JWPopulation._population_prev`。
func test_r_population_conserved_every_quarter() -> void:
	var t: Trace = _trace(SEED_A, 1)
	if not _startable(t, "人口守恒"):
		return
	eq_int(t.pop_group_violations, 0,
			"INV-072：逐组 期末 == 期初 + 出生 − 死亡 + 年龄迁入 − 年龄迁出 + 技能迁入 − 技能迁出"
			+ " + 迁入 − 迁出（违例 %d 次，第一例：%s）" % [t.pop_group_violations, t.first_pop])
	eq_int(t.pop_nation_violations, 0,
			"INV-071：全国人口变化必须恰好等于 Σ 出生 − Σ 死亡（违例 %d 次）"
			% t.pop_nation_violations)
	eq_int(t.migration_unpaired, 0,
			"INV-073：Σ 迁入必须精确等于 Σ 迁出（违例 %d 次）" % t.migration_unpaired)
	eq_int(t.pop_negative, 0,
			"INV-072：任何群组的人口都不得为负（违例 %d 次）" % t.pop_negative)
	ge_int(t.pop_total_first, 1,
			"开局全国人口必须为正（为 0 则上面四条全是空检查）")


# ══════════════════════════════════════════════════════════════════════════
# H 组 夹具自检：路线脚本本身必须是一条合法命令流
#   缺了这一条，整条路线被形状层拒掉时上面的确定性断言**仍然全绿** ——
#   「两遍都被拒」同样是逐位相同。这条把「命令流真的进了结算」钉死，
#   而且它不依赖内容包，因此内容层出问题时它照样能给出信号。
# ══════════════════════════════════════════════════════════════════════════

## docs/11 §6.1 规则 1（(issued_q, command_id) 全序）+ kind 99 的位置约束：
## 路线脚本按季提交之后，七条业务命令必须全部通过形状与取值校验，
## 且每一季都恰好有一条位于末尾的推进标记。
func test_r_route_script_is_a_legal_command_stream() -> void:
	eq_int(ROUTE_KIND.size(), ROUTE_Q.size(), "路线表的季号列与命令码列必须等长")
	eq_int(ROUTE_ARGS.size(), ROUTE_Q.size() * JWCommands.ARG_SLOTS,
			"路线表的参数列必须是「条数 × %d 槽」" % JWCommands.ARG_SLOTS)

	var order_bad: int = 0
	var range_bad: int = 0
	var prev: int = -1
	var r: int = 0
	while r < ROUTE_Q.size():
		if ROUTE_Q[r] <= prev:
			order_bad += 1
		if ROUTE_Q[r] < 0 or ROUTE_Q[r] >= TARGET_Q:
			range_bad += 1
		prev = ROUTE_Q[r]
		r += 1
	eq_int(order_bad, 0, "路线命令的季号必须严格递增（否则提交期就会被判 COMMAND_ORDER）")
	eq_int(range_bad, 0, "路线命令的季号必须落在 [0, %d) 之内" % TARGET_Q)

	# 用一个一次性的命令缓冲复演整条提交序列。此处 defs 传 null：
	# 路线只用 kind 7/8/10/11/12，它们的取值校验都不读 JWPolicyDef。
	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	var args: PackedInt64Array = PackedInt64Array()
	args.resize(JWCommands.ARG_SLOTS)
	var submitted: int = 0
	var rejected: int = 0
	var first_reject: String = "无"
	var marker_bad: int = 0
	var q: int = 0
	while q < TARGET_Q:
		var i: int = 0
		while i < ROUTE_Q.size():
			if ROUTE_Q[i] == q:
				var base: int = i * JWCommands.ARG_SLOTS
				var s: int = 0
				while s < JWCommands.ARG_SLOTS:
					args[s] = ROUTE_ARGS[base + s]
					s += 1
				var rc: JWResult = cmds.submit(ROUTE_KIND[i], args, q, null)
				submitted += 1
				if rc == null or not rc.ok:
					rejected += 1
					if first_reject == "无":
						first_reject = "q=%d kind=%d 码=%d" % [q, ROUTE_KIND[i], _code_of(rc)]
			i += 1
		args.fill(0)
		cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, args, q, null)
		if cmds.check_advance_marker(q) != JWResult.OK:
			marker_bad += 1
		q += 1

	eq_int(submitted, ROUTE_Q.size(),
			"路线表里的每一条命令都必须在它登记的季被提交（漏提交等于路线名存实亡）")
	eq_int(rejected, 0,
			"路线脚本必须整条通过提交期校验（被拒 %d 条，第一例：%s）；"
			% [rejected, first_reject]
			+ "形状层就被拒的命令进不了 S02，确定性断言会退化成「两遍都没跑」")
	eq_int(marker_bad, 0,
			"docs/11 §6.1 kind 99：每季必须恰好一条推进标记且位于该季末尾（违例 %d 季）"
			% marker_bad)
	eq_int(cmds.count, TARGET_Q + ROUTE_Q.size(),
			"命令缓冲总条数必须等于 40 条推进标记 + %d 条业务命令（不跳号、不丢条）"
			% ROUTE_Q.size())


# ══════════════════════════════════════════════════════════════════════════
# 跑批装置（不含任何断言）
# ══════════════════════════════════════════════════════════════════════════

## 一次跑批采集到的全部可比对量。字段全是整数或字符串序列，逐位可比。
class Trace:
	extends RefCounted

	## 内容包载入码（0 == OK）。
	var boot_code: int = -1
	## 载入失败时前几条错误的精确位置（`<相对路径>#<JSON 指针>` + 错误码），
	## 直接写进失败信息 —— 「载不进去」这条报告不带位置就无法行动。
	var boot_where: String = ""
	## 本次跑批的根种子。
	var root_seed: int = 0
	## 实际完成的季数。
	var q_done: int = 0
	## 跑批结束时的 state.time.q。
	var final_q: int = 0
	## 第一个非 OK 的推进返回码与它所在的季（无故障时 0 / −1）。
	var fault_code: int = 0
	var fault_q: int = -1
	## 跑批结束时 JWResult 的挂起故障码。
	var pending_after: int = 0
	## 终局标记与终局后再推一次的返回码、以及那之后的 state_hash。
	var terminated: bool = false
	var extra_code: int = 0
	var hash_after_extra: String = ""

	## 逐季 state_hash（长 q_done）与逐季 8 个步骤哈希（长 q_done × 8）。
	var state_hash: PackedStringArray = PackedStringArray()
	var step_hash: PackedStringArray = PackedStringArray()
	## 空串步骤哈希的条数。
	var empty_step_hash: int = 0

	## 逐季 log.rng 行数，以及摊平的 (stream, draw_index, raw, mapped)。
	var rng_rows: PackedInt64Array = PackedInt64Array()
	var rng_log: PackedInt64Array = PackedInt64Array()
	## 逐季末 6 条流的 draw_count（长 q_done × 6）。
	var draw_count: PackedInt64Array = PackedInt64Array()
	## 路线命令逐条的提交返回码（0 == 受理）。
	var cmd_code: PackedInt64Array = PackedInt64Array()

	## 存档分支专用。
	var save_code: int = -1
	var load_code: int = -1
	var read_only_required: bool = false
	var replay_unreliable: bool = false
	## 逐季 append_checkpoint 的第一个非 OK 返回码，与实际写出的检查点行数。
	var checkpoint_code: int = 0
	var checkpoint_rows: int = 0
	## JWReplay.verify 的返回码与它报出的分歧季 / 分歧步。
	var verify_code: int = -1
	var verify_divergence_q: int = -2
	var verify_divergence_step: int = -2

	## ── 守恒统计（全部是独立复算出来的违例计数） ──
	var txn_total: int = 0
	var txn_unbalanced: int = 0
	var ledger_row_total: int = 0
	var cash_violations: int = 0
	var cash_total_first: int = 0
	var total_cash_moved: int = 0
	var balance_violations: int = 0
	var recv_pay_violations: int = 0
	var inv_out_violations: int = 0
	var inv_in_violations: int = 0
	var inv_negative: int = 0
	var nonstorable_stock: int = 0
	var sold_traded_violations: int = 0
	var demand_split_violations: int = 0
	var pop_group_violations: int = 0
	var pop_nation_violations: int = 0
	var migration_unpaired: int = 0
	var pop_negative: int = 0
	var pop_total_first: int = 0

	## 三类守恒各自的第一例现场（季号 + 下标 + 残差），失败信息里直接可读。
	var first_money: String = "无"
	var first_goods: String = "无"
	var first_pop: String = "无"

	## 上一季末的自取快照（期初值的唯一来源）。
	var prev_pop: PackedInt64Array = PackedInt64Array()
	var prev_inv_out: PackedInt64Array = PackedInt64Array()
	var prev_inv_in: PackedInt64Array = PackedInt64Array()
	var total_cash_ref: int = 0


## 一套独立装配好的模拟栈。
class Sim:
	extends RefCounted
	var st: JWSimState = null
	var cmds: JWCommands = null
	var events: JWEventEngine = null
	var runner: JWTurnRunner = null
	var loader: JWContentLoader = null
	var code: int = -1
	## 载入失败时的前几条错误位置（见 Trace.boot_where）。
	var where: String = ""


## 装配一份全新的模拟栈（与 JWGame.new_game 同一套顺序，docs/17 §4.33）。
## 步骤：LOAD
## 前置：无
## 后置：st / cmds / events / runner 就位，q == 0；失败时 code != 0
## 不变量：INV-131（root_seed 写进状态）
## 失败：内容包载入失败 → code 取加载器的错误码
func _boot(root_seed: int) -> Sim:
	var sim: Sim = Sim.new()
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: JWContentLoader = JWContentLoader.new()
	var res: JWResult = loader.load_all(CONTENT_ROOT, st)
	if res == null:
		sim.code = JWResult.Load.FILE_FORMAT
		return sim
	if not res.ok:
		sim.code = res.code
		sim.where = _errors_of(loader)
		return sim
	st.content_hash = loader.content_hash
	st.param_set_version = loader.param_set_version
	var rc_seed: int = st.rng.set_state_scalar(0, root_seed)
	if rc_seed != JWResult.OK:
		sim.code = rc_seed
		return sim
	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	var events: JWEventEngine = JWEventEngine.new()
	events.allocate()
	# R-EVENT-01：与 JWGame / JWReplay 同一套事件卡，否则逐季驱动与权威重放在事件触发处分叉。
	var rev: JWResult = loader.load_events_into(events, st)
	if rev == null or not rev.ok:
		sim.code = JWResult.Load.EVENT_COUNT if rev == null else rev.code
		return sim
	JWResult.clear_pending()
	sim.st = st
	sim.cmds = cmds
	sim.events = events
	sim.loader = loader
	sim.runner = JWTurnRunner.new(st, events)
	sim.code = JWResult.OK
	return sim


## 按路线脚本提交本季的业务命令，再补上本季唯一的推进标记。
## 步骤：CMD（S01 之前）
## 前置：cmds 已 allocate；q 单调不减
## 后置：本季命令流以一条 advance_quarter 结尾（docs/11 §6.1 kind 99）
## 不变量：INV-137（被拒命令照样入档）
## 失败：无（提交码写进 trace，由测试方法比对两遍是否一致）
func _submit_quarter(sim: Sim, q: int, t: Trace, pass_route: bool) -> void:
	var args: PackedInt64Array = PackedInt64Array()
	args.resize(JWCommands.ARG_SLOTS)
	if pass_route:
		var r: int = 0
		while r < ROUTE_Q.size():
			if ROUTE_Q[r] == q:
				var base: int = r * JWCommands.ARG_SLOTS
				var s: int = 0
				while s < JWCommands.ARG_SLOTS:
					args[s] = ROUTE_ARGS[base + s]
					s += 1
				var rc: JWResult = sim.cmds.submit(ROUTE_KIND[r], args, q, sim.st.policy_defs)
				t.cmd_code.append(JWResult.OK if (rc != null and rc.ok) else _code_of(rc))
			r += 1
	args.fill(0)
	sim.cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, args, q, sim.st.policy_defs)


## 取 JWResult 的错误码（null 按「格式错误」处理，绝不当成成功）。
func _code_of(r: JWResult) -> int:
	if r == null:
		return JWResult.Load.FILE_FORMAT
	return r.code


## 载入器前几条错误的「码 @ 位置」串（docs/11 §7 要求报出精确位置）。
## 只取前 6 条：内容层一处漂移常常连锁出几十条，全部拼进失败信息反而读不出根因。
func _errors_of(loader: JWContentLoader) -> String:
	var out: String = ""
	var n: int = mini(6, loader.errors.size())
	var i: int = 0
	while i < n:
		if i > 0:
			out += "；"
		out += "code=%d @ %s" % [loader.errors[i].code, loader.error_where(i)]
		i += 1
	if loader.errors.size() > n:
		out += "；…共 %d 条" % loader.errors.size()
	return out


## 跑批主循环：逐季提交命令 → 推进 → 采集哈希 → 独立复算三类守恒。
## 步骤：S01..S08 × until_q
## 前置：sim 已装配；t 的快照已由 _snapshot_open 初始化
## 后置：t 被填满；出现非 OK 返回码即停在该季并记录
## 不变量：INV-012（不回退不跳步）
## 失败：不修改任何状态，只记录故障码与季号
func _drive(sim: Sim, t: Trace, from_q: int, until_q: int, pass_route: bool,
		saves: JWSaves = null, slot: String = "") -> void:
	var q: int = from_q
	while q < until_q:
		_submit_quarter(sim, q, t, pass_route)
		var code: int = sim.runner.advance_quarter(sim.cmds)
		if code != JWResult.OK:
			t.fault_code = code
			t.fault_q = q
			t.pending_after = JWResult.pending_code() if JWResult.has_pending() else JWResult.OK
			JWResult.clear_pending()
			return
		t.q_done += 1
		t.final_q = sim.st.q
		if saves != null:
			# 与 JWGame.advance_quarter 同一时点：本季结算完成后追加一行检查点。
			var rck: JWResult = saves.append_checkpoint(q, sim.st.state_hash(),
					sim.runner.step_hashes(), slot)
			if rck == null or not rck.ok:
				if t.checkpoint_code == JWResult.OK:
					t.checkpoint_code = _code_of(rck)
			else:
				t.checkpoint_rows += 1
		_collect(sim, t)
		_check_money(sim, t, q)
		_check_goods(sim, t, q)
		_check_population(sim, t, q)
		q += 1
	t.pending_after = JWResult.pending_code() if JWResult.has_pending() else JWResult.OK


## 采集本季的哈希、随机流与抽样计数。
func _collect(sim: Sim, t: Trace) -> void:
	t.state_hash.append(sim.st.state_hash())
	var steps: PackedStringArray = sim.runner.step_hashes()
	var i: int = 0
	while i < STEP_N:
		var h: String = steps[i] if i < steps.size() else ""
		if h == "":
			t.empty_step_hash += 1
		t.step_hash.append(h)
		i += 1

	var rng: JWRngStreams = sim.st.rng
	var rows: int = rng.log_row_count()
	t.rng_rows.append(rows)
	var j: int = 0
	while j < rows:
		t.rng_log.append(rng.log_stream[j])
		t.rng_log.append(rng.log_draw_index[j])
		t.rng_log.append(rng.log_raw[j])
		t.rng_log.append(rng.log_mapped[j])
		j += 1
	var s: int = 0
	while s < STREAM_N:
		t.draw_count.append(rng.draw_count_of(s))
		s += 1


## 期初快照：开账之后、第一次推进之前取一次，此后每季末刷新。
## 这是本文件全部守恒复算的期初值来源 —— 不读被测模块的任何 `_*_prev` 私有成员。
func _snapshot_open(sim: Sim, t: Trace) -> void:
	t.prev_pop = sim.st.pop.population.duplicate()
	t.prev_inv_out = sim.st.inventory.inv_output.duplicate()
	t.prev_inv_in = sim.st.inventory.inv_input.duplicate()
	t.total_cash_ref = sim.st.total_cash_uu
	t.cash_total_first = _cash_total(sim.st)
	t.pop_total_first = JWMath.sum(sim.st.pop.population)


## 无来源资金：账本逐笔行和、56 个 cash 科目求和、60 个主体的资产负债残差、应收应付配对。
func _check_money(sim: Sim, t: Trace, q: int) -> void:
	var st: JWSimState = sim.st
	var led: JWLedger = st.ledger

	# ① INV-015：按 txn_id 分组求和。行是按 txn 连续写入的，一遍扫描即可分组。
	var n: int = led.log_row_count()
	t.ledger_row_total += n
	var i: int = 0
	while i < n:
		var txn: int = led.l_txn[i]
		var acc: int = 0
		var j: int = i
		while j < n and led.l_txn[j] == txn:
			acc += led.l_delta[j]
			j += 1
		t.txn_total += 1
		if acc != 0:
			t.txn_unbalanced += 1
			if t.first_money == "无":
				t.first_money = "q=%d txn=%d 行和=%d" % [q, txn, acc]
		i = j

	# ② INV-018：Σ cash（56 个科目）恒等于 state.total_cash_uu。
	var cash: int = _cash_total(st)
	if cash != st.total_cash_uu:
		t.cash_violations += 1
		if t.first_money == "无":
			t.first_money = "q=%d Σcash=%d 应为 %d 差 %d" % [q, cash, st.total_cash_uu,
					cash - st.total_cash_uu]
	if st.total_cash_uu != t.total_cash_ref:
		t.total_cash_moved += 1

	# ③ INV-020：逐主体资产负债残差；④ INV-019：Σ recv == Σ pay。
	var recv: int = 0
	var pay: int = 0
	var a: int = 0
	while a < JWUnits.AGENT_N:
		var res: int = _balance_residual(st, a)
		if res != 0:
			t.balance_violations += 1
			if t.first_money == "无":
				t.first_money = "q=%d agent=%d 资产负债残差=%d" % [q, a, res]
		recv += st.accounts.get_balance(JWIds.idx_account(a, JWIds.ACC_RECV))
		pay += st.accounts.get_balance(JWIds.idx_account(a, JWIds.ACC_PAY))
		a += 1
	if recv != pay:
		t.recv_pay_violations += 1
		if t.first_money == "无":
			t.first_money = "q=%d Σrecv=%d Σpay=%d 差 %d" % [q, recv, pay, recv - pay]


## 无来源物资：成品与投入两条库存恒等式 + 市场出清两侧对账。
func _check_goods(sim: Sim, t: Trace, q: int) -> void:
	var st: JWSimState = sim.st
	var inv: JWInventory = st.inventory
	var out_actual: PackedInt64Array = st.sectors.f_output_actual

	for cell: int in JWUnits.CELL:
		var storable: bool = st.io.is_storable(JWIds.sector_of_cell(cell))
		if storable:
			var want: int = t.prev_inv_out[cell] + out_actual[cell] - inv.f_sold[cell] \
					- inv.f_spoilage_out[cell]
			if inv.inv_output[cell] != want:
				t.inv_out_violations += 1
				if t.first_goods == "无":
					t.first_goods = "q=%d cell=%d 期末=%d 复算=%d 差 %d" % [q, cell,
							inv.inv_output[cell], want, inv.inv_output[cell] - want]
		elif inv.inv_output[cell] != 0:
			t.nonstorable_stock += 1
			if t.first_goods == "无":
				t.first_goods = "q=%d cell=%d 不可库存部门期末库存=%d" % [q, cell,
						inv.inv_output[cell]]
		if inv.inv_output[cell] < 0:
			t.inv_negative += 1
		for j: int in JWUnits.S:
			var idx: int = JWIds.idx_inv(cell, j)
			var want_in: int = t.prev_inv_in[idx] + inv.f_purchased[idx] - inv.f_consumed[idx] \
					- inv.f_spoilage_in[idx]
			if inv.inv_input[idx] != want_in:
				t.inv_in_violations += 1
				if t.first_goods == "无":
					t.first_goods = "q=%d inv=%d 期末=%d 复算=%d 差 %d" % [q, idx,
							inv.inv_input[idx], want_in, inv.inv_input[idx] - want_in]
			if inv.inv_input[idx] < 0:
				t.inv_negative += 1

	# INV-059：卖方减少量 == 市场成交量；成交 + 未满足 == 需求。
	for s2: int in JWUnits.S:
		var sold: int = 0
		for r: int in JWUnits.R:
			sold += inv.f_sold[JWIds.idx_cell(r, s2)]
		var traded: int = 0
		var demand: int = 0
		var unmet: int = 0
		for b: int in JWUnits.BUYER_CLASS_N:
			var m: int = JWIds.idx_market(s2, b)
			traded += inv.m_traded[m]
			# R-IMPORT-01：成交里由外部供货的部分不经国内卖方。
			sold += inv.m_imported[m]
			demand += inv.m_demand[m]
			unmet += inv.m_unmet[m]
		if sold != traded:
			t.sold_traded_violations += 1
			if t.first_goods == "无":
				t.first_goods = "q=%d sector=%d 售出=%d 成交=%d 差 %d" % [q, s2, sold, traded,
						sold - traded]
		if traded + unmet != demand:
			t.demand_split_violations += 1
			if t.first_goods == "无":
				t.first_goods = "q=%d sector=%d 成交+未满足=%d 需求=%d" % [q, s2,
						traded + unmet, demand]

	t.prev_inv_out = inv.inv_output.duplicate()
	t.prev_inv_in = inv.inv_input.duplicate()


## 人口守恒：逐组来源去向、Σ 迁入 == Σ 迁出、全国口径。
func _check_population(sim: Sim, t: Trace, q: int) -> void:
	var pop: JWPopulation = sim.st.pop
	var mig_in: PackedInt64Array = sim.st.migration.in_by_group()
	var mig_out: PackedInt64Array = sim.st.migration.out_by_group()

	var sum_in: int = 0
	var sum_out: int = 0
	var births: int = 0
	var deaths: int = 0
	var g: int = 0
	while g < JWUnits.GROUP:
		var want: int = t.prev_pop[g] + pop.f_births[g] - pop.f_deaths[g] \
				+ pop.f_age_in[g] - pop.f_age_out[g] \
				+ pop.f_skill_in[g] - pop.f_skill_out[g] \
				+ mig_in[g] - mig_out[g]
		if pop.population[g] != want:
			t.pop_group_violations += 1
			if t.first_pop == "无":
				t.first_pop = "q=%d group=%d 期末=%d 复算=%d 差 %d" % [q, g,
						pop.population[g], want, pop.population[g] - want]
		if pop.population[g] < 0:
			t.pop_negative += 1
		sum_in += mig_in[g]
		sum_out += mig_out[g]
		births += pop.f_births[g]
		deaths += pop.f_deaths[g]
		g += 1

	if sum_in != sum_out:
		t.migration_unpaired += 1
		if t.first_pop == "无":
			t.first_pop = "q=%d Σ迁入=%d Σ迁出=%d" % [q, sum_in, sum_out]
	var nation_prev: int = JWMath.sum(t.prev_pop)
	var nation_now: int = JWMath.sum(pop.population)
	if nation_now != nation_prev + births - deaths:
		t.pop_nation_violations += 1
		if t.first_pop == "无":
			t.first_pop = "q=%d 全国 期末=%d 期初=%d 出生=%d 死亡=%d" % [q, nation_now,
					nation_prev, births, deaths]
	t.prev_pop = pop.population.duplicate()


## 56 个 cash 科目求和（docs/10 §2.1：4 个 pubserv 不持有现金）。
## 本函数是 INV-018 的独立复算入口，**不调 JWAccount.total_cash()**。
func _cash_total(st: JWSimState) -> int:
	var acc: int = 0
	var a: int = 0
	while a < JWUnits.AGENT_N:
		if a < JWIds.AGENT_PUBSERV_BASE or a >= JWIds.AGENT_GROUP_BASE:
			acc += st.accounts.get_balance(JWIds.idx_account(a, JWIds.ACC_CASH))
		a += 1
	return acc


## 逐主体资产负债残差（docs/10 §2.2 的方向约定，INV-020 的原文形态）。
func _balance_residual(st: JWSimState, agent: int) -> int:
	var acc: int = st.accounts.get_balance(JWIds.idx_account(agent, JWIds.ACC_CASH))
	for s: int in JWUnits.S:
		acc += st.accounts.get_balance(JWIds.idx_account(agent, JWIds.ACC_INV_BASE + s))
	acc += st.accounts.get_balance(JWIds.idx_account(agent, JWIds.ACC_WIP))
	acc += st.accounts.get_balance(JWIds.idx_account(agent, JWIds.ACC_CAPITAL))
	acc += st.accounts.get_balance(JWIds.idx_account(agent, JWIds.ACC_HOUSING))
	acc += st.accounts.get_balance(JWIds.idx_account(agent, JWIds.ACC_RECV))
	acc += st.accounts.get_balance(JWIds.idx_account(agent, JWIds.ACC_BONDHOLD))
	acc += st.accounts.get_balance(JWIds.idx_account(agent, JWIds.ACC_DEPOSIT_CLAIM))
	acc -= st.accounts.get_balance(JWIds.idx_account(agent, JWIds.ACC_PAY))
	acc -= st.accounts.get_balance(JWIds.idx_account(agent, JWIds.ACC_DEBT))
	acc -= st.accounts.get_balance(JWIds.idx_account(agent, JWIds.ACC_DEPOSIT_LIAB))
	acc -= st.accounts.get_balance(JWIds.idx_account(agent, JWIds.ACC_NW))
	return acc


# ── 跑批入口（带缓存） ──────────────────────────────────────────────────────

## 取（种子, 遍次）对应的跑批结果；没跑过就现跑一遍并缓存。
func _trace(root_seed: int, pass_index: int) -> Trace:
	if root_seed == SEED_A and pass_index == 1:
		if _trace_a1 == null:
			_trace_a1 = _run_full(SEED_A)
		return _trace_a1
	if root_seed == SEED_A and pass_index == 2:
		if _trace_a2 == null:
			_trace_a2 = _run_full(SEED_A)
		return _trace_a2
	if _trace_b == null:
		_trace_b = _run_full(SEED_B)
	return _trace_b


## 完整 40 季跑批（路线命令流），跑完再多推一次以验证 INV-128。
func _run_full(root_seed: int) -> Trace:
	var t: Trace = Trace.new()
	t.root_seed = root_seed
	var sim: Sim = _boot(root_seed)
	t.boot_code = sim.code
	t.boot_where = sim.where
	if sim.code != JWResult.OK:
		return t
	_snapshot_open(sim, t)
	_drive(sim, t, 0, TARGET_Q, true)
	if t.fault_code == JWResult.OK and t.q_done == TARGET_Q:
		t.terminated = sim.st.politics.run_terminated
		_submit_quarter(sim, sim.st.q, t, false)
		t.extra_code = sim.runner.advance_quarter(sim.cmds)
		t.hash_after_extra = sim.st.state_hash()
		# 终局拒绝不得留下挂起故障；留了就是把 REJECT 当成了 FAULT。
		if JWResult.has_pending():
			t.pending_after = JWResult.pending_code()
			JWResult.clear_pending()
	return t


## 空业务命令流（只有推进标记）的本地跑批，用于与 JWReplay.run_to 对照。
func _plain_trace() -> Trace:
	if _trace_plain != null:
		return _trace_plain
	var t: Trace = Trace.new()
	t.root_seed = SEED_A
	var sim: Sim = _boot(SEED_A)
	t.boot_code = sim.code
	t.boot_where = sim.where
	if sim.code != JWResult.OK:
		_trace_plain = t
		return t
	_snapshot_open(sim, t)
	_drive(sim, t, 0, TARGET_Q, false)
	_trace_plain = t
	return t


## 存档 → 读档 → 继续：前 SPLIT_Q 季在原栈上跑，其余季在**读回来的新栈**上跑。
func _split_trace() -> Trace:
	if _trace_split != null:
		return _trace_split
	var t: Trace = Trace.new()
	t.root_seed = SEED_A
	var sim: Sim = _boot(SEED_A)
	t.boot_code = sim.code
	t.boot_where = sim.where
	if sim.code != JWResult.OK:
		_trace_split = t
		return t
	_snapshot_open(sim, t)
	# 先清干净槽位：checkpoints.jsonl 只追加不重写，上一次运行的残留会让 verify 对错季。
	_remove_slot(SAVE_SLOT)
	var saves: JWSaves = JWSaves.new()
	saves.scenario_hash = sim.loader.scenario_hash
	_drive(sim, t, 0, SPLIT_Q, true, saves, SAVE_SLOT)
	if t.fault_code != JWResult.OK:
		_trace_split = t
		return t

	var rs: JWResult = saves.save(sim.st, sim.cmds, SAVE_SLOT)
	t.save_code = _code_of(rs) if (rs == null or not rs.ok) else JWResult.OK
	if t.save_code != JWResult.OK:
		_trace_split = t
		return t

	# 换一套全新的状态栈读回来：沿用原栈就证明不了「存档装全了跨季状态」。
	var sim2: Sim = _boot(SEED_A)
	if sim2.code != JWResult.OK:
		t.load_code = sim2.code
		_trace_split = t
		return t
	var saves2: JWSaves = JWSaves.new()
	var rl: JWResult = saves2.load(SAVE_SLOT, sim2.st, sim2.cmds, sim2.loader)
	t.load_code = _code_of(rl) if (rl == null or not rl.ok) else JWResult.OK
	t.read_only_required = saves2.read_only_required
	t.replay_unreliable = saves2.replay_unreliable
	if t.load_code != JWResult.OK:
		_trace_split = t
		return t
	# 读档后 JWTurnRunner 必须重新构造：它持有的是状态对象引用。
	sim2.runner = JWTurnRunner.new(sim2.st, sim2.events)
	JWResult.clear_pending()
	_drive(sim2, t, SPLIT_Q, TARGET_Q, true)

	# 权威重放（COMMANDS_ONLY）：不读 state.json，只喂 commands.jsonl 从 q = 0 重跑，
	# 逐季与 checkpoints.jsonl 比对。用 sim.loader —— 它的 root_path() 已就位，
	# 而 sim 这一支到此已经不再使用（verify 内部会重置这个加载器）。
	JWResult.clear_pending()
	var replay: JWReplay = JWReplay.new()
	var rv: JWResult = replay.verify(SAVE_SLOT, sim.loader)
	t.verify_code = JWResult.OK if (rv != null and rv.ok) else _code_of(rv)
	t.verify_divergence_q = replay.divergence_q
	t.verify_divergence_step = replay.divergence_step
	JWResult.clear_pending()

	_remove_slot(SAVE_SLOT)
	_trace_split = t
	return t


## 跑一遍 JWReplay.run_to（权威重放口径：空业务命令流，推进标记由它自己补）。
func _ensure_replay_run() -> void:
	if _replay_code >= 0:
		return
	var probe: JWSimState = JWSimState.new()
	probe.allocate_all()
	var loader: JWContentLoader = JWContentLoader.new()
	var res: JWResult = loader.load_all(CONTENT_ROOT, probe)
	if res == null or not res.ok:
		_replay_code = _code_of(res)
		_replay_where = _errors_of(loader)
		_replay_q = -1
		return
	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	JWResult.clear_pending()
	var replay: JWReplay = JWReplay.new()
	var rc: JWResult = replay.run_to(SEED_A, cmds, TARGET_Q, loader)
	_replay_code = JWResult.OK if (rc != null and rc.ok) else _code_of(rc)
	_replay_q = replay.last_q
	_replay_hash = replay.last_state.state_hash() if replay.last_state != null else ""
	JWResult.clear_pending()


# ── 小工具 ────────────────────────────────────────────────────────────────

## 跑批起跑失败时记一条**可读**的失败并返回 false，
## 不让下游断言把同一个根因重复报成十条。
func _startable(t: Trace, what: String) -> bool:
	if t.boot_code != JWResult.OK:
		check(false, "%s 无法起跑：出厂内容包未能载入（code=%d）。%s" % [what, t.boot_code,
				t.boot_where])
		return false
	if t.state_hash.is_empty():
		check(false, "%s 无法起跑：一季都没有推进成功（第 %d 季返回码 %d）"
				% [what, t.fault_q, t.fault_code])
		return false
	return true


## 两个字符串序列的第一处不等下标；长度不同时返回较短者的长度；全等返回 −1。
func _first_str_diff(a: PackedStringArray, b: PackedStringArray) -> int:
	var n: int = mini(a.size(), b.size())
	var i: int = 0
	while i < n:
		if a[i] != b[i]:
			return i
		i += 1
	if a.size() != b.size():
		return n
	return -1


## 删掉本用例写出的存档槽位（含 .tmp / .bak 残留）。
func _remove_slot(slot: String) -> void:
	_remove_tree(JWSaves.SAVES_ROOT + slot + "/")
	_remove_tree(JWSaves.SAVES_ROOT + slot + JWSaves.TMP_SUFFIX + "/")
	_remove_tree(JWSaves.SAVES_ROOT + slot + JWSaves.BAK_SUFFIX + "/")


## 递归删目录（只用于 user:// 下本用例自己写出的临时目录）。
func _remove_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full: String = path + entry
			if dir.current_is_dir():
				_remove_tree(full + "/")
			else:
				DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
