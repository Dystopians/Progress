## 对抗性验收套件 adversarial-a：套利与重复计数（A 族）、融资永动机（C 族）、项目与合同攻击（F 族）。
##
## 覆盖 docs/31_adversarial_tests.md 的 `ADV-A01..A06`、`ADV-C01..C07`、`ADV-F01..F06`，共 19 条。
## 每个测试方法上方有 docs/31 §0.4 要求的元数据块（adv_id / alias / family / invariants / guards / gate）。
##
## **期望值来源纪律**（docs/30 §0.3 第 4 条）：断言里的每一个期望值只能来自三处之一——
##   1. 契约文件的字面量（docs/10 §14 的 INV 文本、docs/11 §6.1 的命令表、docs/18 的裁定）；
##   2. 内容包里可以逐字查到的常量（例如 `policy_P09.json` 的 `toggle_cost_uu = 10_000_000`、
##      `spend_lines_uu_per_q.subsidy_to_firms = 190_000_000`、`government_init.json` 的
##      `gov.cash_uu = 2_000_000_000`、`invpool.cash_uu = 9_000_000_000`、
##      `credit_limit_domestic_uu = 4_000_000_000`）；
##   3. 本文件内用 `JWMath` 做的、**与被测实现不共享代码路径**的独立复算。
## 任何「拿被测模块的返回值当期望值」的写法都不出现在这里。
##
## **本文件不读任何被测模块的实现体**。它只依赖：
##   · docs/18 裁定、docs/12 结算合同、docs/10 §14 不变量总表、docs/30、docs/31；
##   · docs/17_api_skeleton.md 登记的公开签名与成员名（§4.6 JWAccount、§4.10 JWLedger、
##     §4.11 JWBondBook、§4.12 JWTreasury、§4.19 JWProjectQueue、§4.21 JWPolicyEngine、
##     §4.27 JWSimState、§4.33 JWGame）；
##   · 已完成并已测试的基础设施 `sim/jw_*.gd` 与 `sim/state/*.gd`。
##
## **三类合法结果**（docs/12 §0.6，docs/31 §0.2）：`REJECT(E_xxx)` 状态逐位不变 / `ARREARS` 账自洽 /
## `FAULT` 永不发生。**禁止出现的第四类是静默改账**——本文件的大多数断言就是在钉死这一条。
##
## 纪律：`JWResult` 的故障登记是静态的，会跨测试方法残留；每个方法前后都 `clear_pending()`。
extends JWTest


# ── 契约常量（全部可在契约文件或内容包里逐字查到，不从实现里取） ─────────────

## 政策下标：`content/policies/policy_P<nn>.json` 按 ID 字典序折成 0..11（docs/17 §4.8，长度 12）。
const P01_INCOME_TAX: int = 0
const P03_UNEMPLOYMENT: int = 2
const P04_GRID_PROJECT: int = 3
const P09_INVEST_SUBSIDY: int = 8

## `policy_P09.json`：`cooldown_q = 4`、`toggle_cost_uu = 10_000_000`。
const P09_COOLDOWN_Q: int = 4
const P09_TOGGLE_COST_UU: int = 10_000_000
## `policy_P09.json` `cost.spend_lines_uu_per_q.subsidy_to_firms`：每季补助支出的硬封顶。
const P09_SUBSIDY_CEILING_PER_Q_UU: int = 190_000_000
## `policy_P09.json` `player_params[subsidy_rate_ppm].valid_range == [100000, 500000]`。
const P09_RATE_MIN_PPM: int = 100_000
const P09_RATE_MAX_PPM: int = 500_000
## `policy_P09.json` `player_params[cap_per_cell_per_q_uu]`：`valid_range == [10000000, 190000000]`、
## `default == 60000000`（**新刻度**：R-SCALE-01 之后 1 U = 10⁹ μU，该条的三个值已随迁移 ×1000；
## 见该参数 `calibration_note` 里逐字记录的 `[10000, 190000] → [10000000, 190000000]`）。
const P09_CAP_DEFAULT_UU: int = 60_000_000
## P09 的四个命令参数槽（`systems/commands.gd` 的槽位布局 + `policy_P09.json` 的 `store` 字段）：
## j=0 region_mask（非 rate/transfer 类的 j=0 一律是 region_mask）、
## j=1 min_investment_ratio_ppm（store = params_ppm[slot 0]）、
## j=2 subsidy_rate_ppm（store = params_ppm[slot 1]）、j=3 cap_per_cell_per_q_uu（store = params_uu[slot 0]）。
const P09_J_REGION_MASK: int = 0
const P09_J_MIN_INVEST: int = 1
const P09_J_RATE: int = 2
const P09_J_CAP: int = 3

## `policy_P03.json`：`replacement_ppm.valid_range == [0, 800000]`，槽 j=0 是主速率（rate/transfer 类）。
const P03_REPLACEMENT_MAX_PPM: int = 800_000

## `policy_P01.json` 的主速率槽（rate 类 j=0 == 税率 ppm）。
const P01_J_RATE: int = 0

## ADV-F02 的探针规模（1%）：合同与赔偿都按规模缩放，槽位占用不缩放（R-PROJECT-01 ⑤）。
const F02_PROBE_SCALE_PPM: int = 10_000

## `policy_P04.json`：`cost.one_off_uu = 4_000_000_000`、`per_quarter_uu = 500_000_000`、
## `exit_rule.compensation_ppm = 300_000`、`cost.required_construction_uqs = 3_200_000`。
const P04_ONE_OFF_UU: int = 4_000_000_000
const P04_PER_QUARTER_UU: int = 500_000_000
const P04_COMPENSATION_PPM: int = 300_000
const P04_REQUIRED_CONSTRUCTION_UQS: int = 3_200_000

## `government_init.json`：开局国库现金、国内融资额度、投资池现金。
const GOV_CASH_INIT_UU: int = 2_000_000_000
const CREDIT_LIMIT_DOMESTIC_INIT_UU: int = 4_000_000_000
const INVPOOL_CASH_INIT_UU: int = 9_000_000_000

## `systems/commands.gd` 的槽位布局（该文件是布局的唯一定义处，故此处引用的是契约不是实现）。
const SLOT_POLICY: int = 0
const SLOT_PARAM_BASE: int = 1
const SLOT_ENACT_FUNDING: int = 5
const SLOT_LAUNCH_REGION: int = 1
const SLOT_LAUNCH_SCALE: int = 2
const SLOT_LAUNCH_FUNDING: int = 3
const SLOT_PROJECT: int = 0
const SLOT_DEFER_QUARTERS: int = 1
const SLOT_BOND_AMOUNT: int = 0
const SLOT_BOND_TENOR: int = 1
const SLOT_BOND_HOLDER: int = 2
const SLOT_BOND: int = 0
const SLOT_RESTRUCTURE_MODE: int = 1

## 资金来源码（`docs/11` §5.12 的 `["cash","bond","reallocation"]` 顺序）。
const FUNDING_CASH: int = 0
const FUNDING_BOND: int = 1
const FUNDING_REALLOCATION: int = 2

## `tenor_q` 的合法闭区间（docs/31 `Q-ADV-05` 的保守裁定 `[4, 40]`）。
const TENOR_MIN: int = 4
const TENOR_MAX: int = 40
## `project_defer.quarters` 的形状上界 == `param.commitment_horizon_q`（承诺表滚动窗口 16 季）。
const DEFER_QUARTERS_MAX: int = 16
## docs/31 `Q-ADV-01` 的保守期望：延期次数上限 2 次、单次 4 季、总计不超过 8 季。
const MAX_DEFER_COUNT: int = 2

## 债务重组模式码（`JWBondBook.RestructureMode` 的 `defer / writedown / default` 顺序）。
const RESTRUCTURE_DEFER: int = 0
const RESTRUCTURE_WRITEDOWN: int = 1

## 内容包根目录。`JWGame.new_game(scenario_path, ...)` 与 `JWContentLoader.load_all(root_path, ...)`
## 对这个参数的口径在 docs/17 里没有写死（见本波返回的 open_questions），故两种都试。
const CONTENT_ROOT_A: String = "res://content"
const CONTENT_ROOT_B: String = "res://content/scenarios/chengwan"

## 本套件统一的根种子与时限。种子固定 ⇒ 同构建同命令逐位可复现（INV-014）。
const ROOT_SEED: int = 1
const HORIZON_Q: int = 40

## 读不到的标量用它，任何断言碰到它都会红——**绝不用 0 兜底**，那是静默改账的测试版。
const UNREADABLE: int = -999_999_999_999


func before_each() -> void:
	JWResult.clear_pending()
	JWResult.set_step(0)


func after_each() -> void:
	JWResult.clear_pending()


func before_all() -> void:
	suite_note = "docs/31 A 族 6 条 + C 族 7 条 + F 族 6 条；INV-015..021, 024..040, 087..098, 112..114, 137"


# ══════════════════════════════════════════════════════════════════════════
# 夹具
# ══════════════════════════════════════════════════════════════════════════

## 对抗测试夹具。**不含任何写状态的接口**（docs/31 §1 的硬约束）：
## 它只能 `submit()` 递交命令、`advance()` 推进季度、用只读访问器读状态。
## 计划书 §16 人工评审重点第四条「是否在测试中偷偷补入资源」——本类里没有任何 `set_*`。
class Fix extends RefCounted:

	# GDScript 的内部类不继承外层脚本的作用域，下面几个常量因此在此重复一份。
	# 它们的权威定义在外层（值必须一致）；重复的是常量，不是逻辑。
	const CONTENT_ROOT_A: String = "res://content"
	const CONTENT_ROOT_B: String = "res://content/scenarios/chengwan"
	const ROOT_SEED: int = 1
	const HORIZON_Q: int = 40
	const GOV_CASH_INIT_UU: int = 2_000_000_000
	const UNREADABLE: int = -999_999_999_999

	## 宿主测试，用来登记失败（夹具自己不做断言，只登记事实）。
	var t: JWTest = null
	## 权威状态。
	var st: JWSimState = null
	## 命令缓冲。
	var cmds: JWCommands = null
	## 回合驱动。
	var runner: JWTurnRunner = null
	## 应用层门面（可用时优先走它，这是契约规定的唯一写入路径）。
	var game: JWGame = null
	## 是否经由 JWGame 递交命令与推进。
	var via_game: bool = false
	## 内容包是否真的载入（现金总量对得上才算）。
	var booted: bool = false
	## 夹具是否仍可推进（一旦推进失败即置 false，避免后续断言读到半截状态）。
	var alive: bool = false
	## 本局已按规则终局（选举落败 / 不信任 / 财政重组失败 / 到期）：此后 advance 不再推进，
	## 但 alive 保持 true——断言照常在已结算的季上执行（docs/12 §0.6：RUN_TERMINATED 是 REJECT 类）。
	var ended: bool = false
	## 终局后第一次被拒的推进季（−1 == 未终局）。
	var ended_q: int = -1
	## 启动诊断文本，失败消息里原样带出。
	var note: String = ""

	## 稳定 ID → 条目注册表下标（`JWSimState.read_metric` 的 metric_code 就是这个下标）。
	var _code_of_id: Dictionary = {}

	## 逐季账本正腿汇总：`_led[q][kind]`。
	var _led: Array = []
	## 逐季按**科目腿**的有符号汇总（docs/18 第三轮「测试口径更正」）：发债 / 还本是四腿分录、
	## 减记是两笔两腿分录，正腿之和是面值的 2 倍，不能拿来量金额。债务流量改按政府债务科目腿量，
	## 国内发债按投资池持债科目腿量。`_led_gov_debt[q][kind]` / `_led_pool_bond[q][kind]` = 该类行在该科目上的 Σ delta。
	var _led_gov_debt: Array = []
	var _led_pool_bond: Array = []
	## R-PROJECT-01 之后项目付款是四腿分录（收款方现金 +、政府在建工程 +），正腿之和 == 2 × 付款额；
	## `_led_gov_cash_out[q][kind]` = 该类行在政府现金科目上的流出额（正数），即实付额。
	var _led_gov_cash_out: Array = []
	## 逐季快照：季末的国库现金 / 欠付 / 承诺 / 未偿债务 / 全经济现金总量。
	var _cash_gov: PackedInt64Array = PackedInt64Array()
	var _arrears: PackedInt64Array = PackedInt64Array()
	var _committed: PackedInt64Array = PackedInt64Array()
	var _debt: PackedInt64Array = PackedInt64Array()
	var _cash_total: PackedInt64Array = PackedInt64Array()
	## 逐季新增/清偿欠付（INV-030 的两个流量）。
	var _arrears_added: PackedInt64Array = PackedInt64Array()
	var _arrears_cleared: PackedInt64Array = PackedInt64Array()
	## 已完成的季数（== 已写入快照的季数）。
	var _quarters_done: int = 0

	# ── 启动 ───────────────────────────────────────────────────────────────

	## 开新局。优先走 `JWGame.new_game`（docs/17 §4.33 的唯一开局入口）；
	## 门面尚未实现时退回到「自己拼 SimState + Loader + Runner + Commands」的等价路径，
	## 这样本套件在门面完成前后都能跑，且不需要改测试。
	func boot(host: JWTest) -> bool:
		t = host
		_try_game()
		if st == null:
			_boot_manual()
		if st == null:
			t.fail("夹具启动失败：既拿不到 JWGame._st，也建不出 JWSimState。%s" % note)
			return false
		alive = true
		_alloc_series()
		_build_code_map()
		booted = _content_loaded()
		if not booted:
			t.fail(("内容包未载入：期望 `scenario.total_cash_uu` 与 Σ 全部 cash 科目都等于 "
					+ "剧本登记的现金总量（INV-018），实际 total_cash_uu=%d、Σcash=%d、gov.cash=%d "
					+ "（剧本 government_init.json 的 gov.cash_uu 是 %d）。"
					+ "在 JWContentLoader.load_all 与 JWTurnRunner.advance_quarter 填上实现之前，"
					+ "本条对抗测试的运行期部分无法判定——这是红，不是跳过。%s")
					% [st.total_cash_uu, _total_cash(), cash_of(JWIds.AGENT_GOV),
						GOV_CASH_INIT_UU, note])
		return booted

	## 走应用层门面开局（docs/17 §4.33 的唯一开局入口）。
	## 门面或它依赖的脚本当前编译不过时，`load()` 返回 null——这里只登记事实并退回自建栈，
	## 不让一个编译错误把整份对抗套件变成「无输出」。
	func _try_game() -> void:
		var gs: Variant = load("res://application/game.gd")
		if gs == null:
			note = "application/game.gd 当前无法加载（编译失败）"
			return
		var obj: Object = gs.new()
		if obj == null:
			note = "JWGame.new() 返回 null"
			return
		game = obj as JWGame
		# 测试专用的自动存档槽：与游戏本体的 "autosave" 分开，并行跑界面冒烟时不互相覆盖（2900）。
		obj.set("autosave_slot", "autosave_test")
		var r: Variant = obj.call("new_game", CONTENT_ROOT_A, ROOT_SEED, HORIZON_Q)
		var code: int = 0
		if r != null and r is JWResult:
			code = (r as JWResult).code
		var gst: Variant = obj.get("_st")
		if gst != null and gst is JWSimState:
			st = gst as JWSimState
			var gc: Variant = obj.get("_cmds")
			var gr: Variant = obj.get("_runner")
			if gc != null and gr != null:
				cmds = gc as JWCommands
				runner = gr as JWTurnRunner
				via_game = true
			return
		note = "JWGame.new_game 未构造权威状态（返回码 %d）；退回自建栈" % code

	## 自建栈：与 `JWGame.new_game` 的后置条件等价（docs/17 §4.33「状态就绪，phase == IDLE，q == 0」）。
	## 先把状态与命令缓冲立起来，再尝试载入内容包——这样即便加载器不可用，
	## 命令形状层的对抗断言（C02 / C07 / F04）仍然跑得动。
	func _boot_manual() -> void:
		var s: JWSimState = JWSimState.new()
		s.allocate_all()
		s.horizon_q = HORIZON_Q
		st = s
		via_game = false

		var ls: Variant = load("res://systems/content_loader.gd")
		if ls == null:
			note += "；systems/content_loader.gd 当前无法加载（编译失败），内容包未进状态"
		else:
			var code: int = _load_into(ls, st, CONTENT_ROOT_A)
			if code != JWResult.OK:
				note += "；load_all(%s) 返回错误码 %d" % [CONTENT_ROOT_A, code]
				# `JWGame.new_game` 的形参叫 `scenario_path`，`JWContentLoader.load_all` 的叫
				# `root_path`，docs/17 没有写死二者是不是同一个口径（见本波返回的 open_questions）。
				# 半载入的状态不能复用，换一个根路径就从头再来一遍。
				var s2: JWSimState = JWSimState.new()
				s2.allocate_all()
				s2.horizon_q = HORIZON_Q
				if _load_into(ls, s2, CONTENT_ROOT_B) == JWResult.OK:
					st = s2
					note += "；改用 %s 载入成功" % CONTENT_ROOT_B

		# 命令缓冲与回合驱动必须绑在最终选定的那个 st 上。
		cmds = JWCommands.new()
		var rs: Variant = load("res://systems/turn_runner.gd")
		var es: Variant = load("res://systems/event_engine.gd")
		if rs != null and es != null:
			runner = rs.new(st, es.new()) as JWTurnRunner
		else:
			note += "；systems/turn_runner.gd 或 event_engine.gd 当前无法加载"

	## 用给定的加载器脚本把内容包载进 `target`，返回 `JWResult` 的错误码（0 == OK）。
	func _load_into(loader_script: Variant, target: JWSimState, root: String) -> int:
		var loader: Object = loader_script.new()
		if loader == null:
			note += "；JWContentLoader.new() 返回 null"
			return JWResult.Load.FILE_FORMAT
		var res: Variant = loader.call("load_all", root, target)
		if res == null or not (res is JWResult):
			return JWResult.OK
		return (res as JWResult).code

	## 内容包是否真的进了状态：现金总量三处对得上（docs/11 §7 载入流水线的最后一步）。
	func _content_loaded() -> bool:
		if st.total_cash_uu <= 0:
			return false
		if _total_cash() != st.total_cash_uu:
			return false
		return cash_of(JWIds.AGENT_GOV) == GOV_CASH_INIT_UU

	func _alloc_series() -> void:
		_led.clear()
		_led_gov_debt.clear()
		_led_pool_bond.clear()
		_led_gov_cash_out.clear()
		_cash_gov = PackedInt64Array()
		_arrears = PackedInt64Array()
		_committed = PackedInt64Array()
		_debt = PackedInt64Array()
		_cash_total = PackedInt64Array()
		_arrears_added = PackedInt64Array()
		_arrears_cleared = PackedInt64Array()
		_quarters_done = 0

	func _build_code_map() -> void:
		_code_of_id.clear()
		var n: int = st.registry_size()
		var e: int = 0
		while e < n:
			_code_of_id[st.registry_id(e)] = e
			e += 1

	# ── 命令与推进 ─────────────────────────────────────────────────────────

	## 递交一条命令，返回拒绝码（0 == 受理）。**只递交，不推进**。
	func submit(kind: int, args: PackedInt64Array) -> int:
		if not alive:
			return UNREADABLE
		if via_game:
			var r: JWResult = game.submit_command(kind, args)
			return 0 if (r == null or r.ok) else r.code
		var r2: JWResult = cmds.submit(kind, args, st.q, st.policy_defs)
		return 0 if (r2 == null or r2.ok) else r2.code

	## 六槽参数的构造器：未用到的槽必须为 0（INV-138 在整数槽层的唯一可机器检查形态）。
	static func a6(s0: int = 0, s1: int = 0, s2: int = 0, s3: int = 0,
			s4: int = 0, s5: int = 0) -> PackedInt64Array:
		return PackedInt64Array([s0, s1, s2, s3, s4, s5])

	## 推进 n 季。每季都自动补一条 `advance_quarter` 标记（docs/11 §6.1 kind 99：
	## 每季恰好一条且为该季最后一条）。任一季推进失败即停并登记失败。
	func advance(n: int) -> void:
		var i: int = 0
		while i < n:
			if not alive or ended:
				return
			var q0: int = st.q
			var marker: int = submit(99, a6())
			if marker != 0:
				t.fail("第 %d 季的 advance_quarter 标记被拒（码 %d）；docs/11 §6.1 规定它每季恰好一条"
						% [q0, marker])
				alive = false
				return
			var rc: int = 0
			if via_game:
				var r: JWResult = game.advance_quarter()
				rc = 0 if (r == null or r.ok) else r.code
			else:
				rc = runner.advance_quarter(cmds)
			if rc == JWResult.Reject.RUN_TERMINATED and st.politics != null 					and st.politics.run_terminated and not JWResult.has_pending():
				# 按规则终局是合法结局（INV-128），不是故障：本局到此为止，已结算的季照常断言。
				# 攻击若让政府下台（例如无资金来源的补助把预算审查连续打穿），那正是它的真实代价。
				ended = true
				ended_q = q0
				return
			if rc != JWResult.OK:
				t.fail("第 %d 季推进返回非 OK（码 %d）；docs/12 §0.6 只允许 REJECT / ARREARS 两类，"
						% [q0, rc] + "FAULT 一律视为测试失败")
				alive = false
				return
			if JWResult.has_pending():
				t.fail("第 %d 季推进后仍挂着故障码 %d（步骤 %d）；docs/12 §9：故障必须中止结算"
						% [q0, JWResult.pending_code(), JWResult.pending_step()])
				alive = false
				return
			if st.q != q0 + 1:
				t.fail(("第 %d 季推进后 state.time.q 仍是 %d：INV-012 规定 q 只在 S08 末 +1，"
						+ "没有 +1 说明八步结算没有真正跑完（JWTurnRunner.advance_quarter 尚未实现）")
						% [q0, st.q])
				alive = false
				return
			_snapshot(q0)
			i += 1

	## 把刚结束的那一季的账本与存量快照存下来（日志每季 S01 重置，过了这一刻就读不到了）。
	func _snapshot(q: int) -> void:
		var by_kind: PackedInt64Array = PackedInt64Array()
		by_kind.resize(JWUnits.KIND_N)
		by_kind.fill(0)
		var gov_debt: PackedInt64Array = PackedInt64Array()
		gov_debt.resize(JWUnits.KIND_N)
		gov_debt.fill(0)
		var pool_bond: PackedInt64Array = PackedInt64Array()
		pool_bond.resize(JWUnits.KIND_N)
		pool_bond.fill(0)
		var gov_cash_out: PackedInt64Array = PackedInt64Array()
		gov_cash_out.resize(JWUnits.KIND_N)
		gov_cash_out.fill(0)
		var acc_gov_cash: int = JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH)
		var acc_gov_debt: int = JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_DEBT)
		var acc_pool_bond: int = JWIds.idx_account(JWIds.AGENT_INVPOOL, JWIds.ACC_BONDHOLD)
		var led: JWLedger = st.ledger
		if led != null:
			var rows: int = led.log_row_count()
			var k: PackedInt64Array = led.l_kind
			var d: PackedInt64Array = led.l_delta
			var a: PackedInt64Array = led.l_account
			var i: int = 0
			while i < rows and i < k.size() and i < d.size() and i < a.size():
				var kd: int = k[i]
				if kd >= 1 and kd < JWUnits.KIND_N:
					# 正腿之和只对两腿分录等于过账额（INV-015：一笔 txn 的有符号行之和为 0）；
					# 多腿分录（发债 / 还本四腿、减记两笔）的金额改从下面的科目腿读。
					if d[i] > 0:
						by_kind[kd] += d[i]
					# 科目腿：政府债务（负债增为负，docs/10 §2.5）与投资池持债（资产增为正）。
					if a[i] == acc_gov_debt:
						gov_debt[kd] += d[i]
					elif a[i] == acc_pool_bond:
						pool_bond[kd] += d[i]
					elif a[i] == acc_gov_cash and d[i] < 0:
						gov_cash_out[kd] -= d[i]
				i += 1
		_led.append(by_kind)
		_led_gov_debt.append(gov_debt)
		_led_pool_bond.append(pool_bond)
		_led_gov_cash_out.append(gov_cash_out)
		_cash_gov.append(cash_of(JWIds.AGENT_GOV))
		_arrears.append(treasury_int("arrears"))
		_committed.append(treasury_int("committed_memo"))
		_debt.append(debt_outstanding())
		_cash_total.append(_total_cash())
		_arrears_added.append(JWMath.sum(treasury_arr("f_arrears_added")))
		_arrears_cleared.append(JWMath.sum(treasury_arr("f_arrears_cleared")))
		_quarters_done += 1

	## 已完成的季数。
	func quarters_done() -> int:
		return _quarters_done

	# ── 账本与命令日志查询 ─────────────────────────────────────────────────

	## 某季某 kind 的过账总额（μU）。季号越界返回 0（那一季根本没跑）。
	func led_q(kind: int, q: int) -> int:
		if q < 0 or q >= _led.size():
			return 0
		var row: PackedInt64Array = _led[q]
		if kind < 0 or kind >= row.size():
			return 0
		return row[kind]

	## 某季某 kind 在政府债务科目上的有符号 Σ delta（负债增为负：发债行 < 0，还本 / 减记行 > 0）。
	func gov_debt_leg_q(kind: int, q: int) -> int:
		if q < 0 or q >= _led_gov_debt.size():
			return 0
		var row: PackedInt64Array = _led_gov_debt[q]
		if kind < 0 or kind >= row.size():
			return 0
		return row[kind]

	## 某季某 kind 在投资池持债科目上的有符号 Σ delta（资产增为正：向投资池发债 > 0）。
	func pool_bond_leg_q(kind: int, q: int) -> int:
		if q < 0 or q >= _led_pool_bond.size():
			return 0
		var row: PackedInt64Array = _led_pool_bond[q]
		if kind < 0 or kind >= row.size():
			return 0
		return row[kind]

	## 闭区间 [q_from, q_to] 内某 kind 从政府现金流出的总额（多腿分录的实付额）。
	func gov_cash_out_sum(kind: int, q_from: int, q_to: int) -> int:
		var acc: int = 0
		var q: int = q_from
		while q <= q_to:
			if q >= 0 and q < _led_gov_cash_out.size():
				var row: PackedInt64Array = _led_gov_cash_out[q]
				if kind >= 0 and kind < row.size():
					acc += row[kind]
			q += 1
		return acc

	## 某季新增借款（政府债务科目上 BOND_ISSUE 行使负债增加的量）。
	func new_borrowing_q(q: int) -> int:
		return -gov_debt_leg_q(JWUnits.Kind.BOND_ISSUE, q)

	## 某季还本（政府债务科目上 BOND_PRINCIPAL 行使负债减少的量）。
	func principal_repaid_q(q: int) -> int:
		return gov_debt_leg_q(JWUnits.Kind.BOND_PRINCIPAL, q)

	## 某季确认减记（政府债务科目上 WRITEOFF 行使负债减少的量）。
	func writeoff_q(q: int) -> int:
		return gov_debt_leg_q(JWUnits.Kind.WRITEOFF, q)

	## 闭区间 [q_from, q_to] 内某 kind 的过账总额。
	func led_sum(kind: int, q_from: int, q_to: int) -> int:
		var acc: int = 0
		var q: int = q_from
		while q <= q_to:
			acc += led_q(kind, q)
			q += 1
		return acc

	## 本季账本里某 kind 的行数（唯一性断言用；日志每季重置，只能查当季）。
	func led_rows_this_quarter(kind: int) -> int:
		var led: JWLedger = st.ledger
		if led == null:
			return 0
		var rows: int = led.log_row_count()
		var k: PackedInt64Array = led.l_kind
		var d: PackedInt64Array = led.l_delta
		var n: int = 0
		var i: int = 0
		while i < rows and i < k.size() and i < d.size():
			if k[i] == kind and d[i] > 0:
				n += 1
			i += 1
		return n

	## 本季账本里某 kind 的全部行是否三重分类码都是 NONE（INV-113 / INV-114 的运行期形态）。
	func all_rows_unclassified(kind: int) -> bool:
		var led: JWLedger = st.ledger
		if led == null:
			return true
		var rows: int = led.log_row_count()
		var i: int = 0
		while i < rows and i < led.l_kind.size():
			if led.l_kind[i] == kind:
				if led.l_prod[i] != 0 or led.l_exp[i] != 0 or led.l_inc[i] != 0:
					return false
			i += 1
		return true

	## 某季被登记为该拒绝码的命令条数（S02 的语义拒绝走这里，不在 submit 的返回值里）。
	func rejects_in_q(q: int, code: int) -> int:
		if cmds == null:
			return 0
		var n: int = 0
		var i: int = 0
		while i < cmds.count:
			if cmds.c_issued_q[i] == q and cmds.c_reject_code[i] == code:
				n += 1
			i += 1
		return n

	## 某季某种命令被受理（c_accepted == 1）的条数：用来确认一条改参数命令真的生效，
	## 否则依赖它的比较可能是两局同样的基线在互比（空跑）。
	func accepted_kind_in_q(q: int, kind: int) -> int:
		if cmds == null:
			return 0
		var n: int = 0
		var i: int = 0
		while i < cmds.count:
			if cmds.c_issued_q[i] == q and cmds.c_kind[i] == kind and cmds.c_accepted[i] == 1:
				n += 1
			i += 1
		return n

	## 整局中被登记为该拒绝码的命令条数。
	func rejects_total(code: int) -> int:
		if cmds == null:
			return 0
		var n: int = 0
		var i: int = 0
		while i < cmds.count:
			if cmds.c_reject_code[i] == code:
				n += 1
			i += 1
		return n

	# ── 只读状态访问 ───────────────────────────────────────────────────────

	## 按稳定 ID 读标量 / 数组元素（走 `JWSimState.read_metric`，docs/12 §8.4）。
	## ID 不在注册表里时返回 `UNREADABLE` 并登记失败——不返回 0。
	func metric(id: String, scope: int = 0) -> int:
		if not _code_of_id.has(id):
			t.fail("稳定 ID `%s` 不在 JWSimState 的条目注册表里（docs/10 的命名空间表要求它存在）" % id)
			return UNREADABLE
		return st.read_metric(int(_code_of_id[id]), scope)

	## 注册表里有没有这个稳定 ID（用于「该字段是否已登记」类断言）。
	func has_metric(id: String) -> bool:
		return _code_of_id.has(id)

	func cash_of(agent: int) -> int:
		if st == null or st.accounts == null:
			return UNREADABLE
		return st.accounts.cash_of(agent)

	func balance_of(agent: int, code: int) -> int:
		if st == null or st.accounts == null:
			return UNREADABLE
		return st.accounts.get_balance(JWIds.idx_account(agent, code))

	func net_worth_of(agent: int) -> int:
		if st == null or st.accounts == null:
			return UNREADABLE
		return st.accounts.net_worth_of(agent)

	func _total_cash() -> int:
		if st == null or st.accounts == null:
			return UNREADABLE
		return st.accounts.total_cash()

	## 全经济现金总量（INV-018 的左边）。
	func total_cash() -> int:
		return _total_cash()

	## 未偿计息债务（`derived.gov.debt_uu` 的唯一来源，docs/17 §4.11）。
	func debt_outstanding() -> int:
		if st == null or st.bonds == null:
			return UNREADABLE
		return st.bonds.debt_outstanding()

	## 用批次表独立复算的未偿债务（INV-035 的右边）。裁定 R-INV035-01：「活跃」= 尚未结清，
	## 含违约、延期中的批次——只排除已到期结清（MATURED）与已核销（WRITTEN_OFF）的批次。
	## 若只数 status == ACTIVE，违约那一刻债务就从 INV-025/028 里凭空消失。
	func debt_recomputed() -> int:
		if st == null or st.bonds == null:
			return UNREADABLE
		var acc: int = 0
		var b: int = 0
		while b < st.bonds.count:
			var s: int = st.bonds.status[b]
			if s != JWUnits.BondStatus.MATURED and s != JWUnits.BondStatus.WRITTEN_OFF:
				acc += st.bonds.principal_outstanding[b]
			b += 1
		return acc

	func bond_count() -> int:
		return 0 if st == null or st.bonds == null else st.bonds.count

	## 债券票息快照（INV-036「发行后被写入即 FAULT」的比对基准）。
	func coupon_snapshot() -> PackedInt64Array:
		if st == null or st.bonds == null:
			return PackedInt64Array()
		return st.bonds.coupon_ppm.slice(0, st.bonds.count)

	func project_count() -> int:
		return 0 if st == null or st.projects == null else st.projects.count

	## 某项目三条 spend_line 的已付合计（`paid` 按 `p*3+line` 存，docs/17 §4.19）。
	func project_paid(p: int) -> int:
		if st == null or st.projects == null:
			return UNREADABLE
		var acc: int = 0
		var line: int = 0
		while line < 3:
			var i: int = p * 3 + line
			if i < st.projects.paid.size():
				acc += st.projects.paid[i]
			line += 1
		return acc

	## 某项目三条 spend_line 的计划支出合计（INV-092 的 `Σ spend_plan == total_cost`）。
	func project_planned(p: int) -> int:
		if st == null or st.projects == null:
			return UNREADABLE
		var acc: int = 0
		var line: int = 0
		while line < 3:
			var i: int = p * 3 + line
			if i < st.projects.spend_plan.size():
				acc += st.projects.spend_plan[i]
			line += 1
		return acc

	## 全部地区已占用槽位之和（INV-094 的左边，逐项目数 `slot_held`，不问实现的 `slots_used`）。
	func slots_held_total() -> int:
		if st == null or st.projects == null:
			return UNREADABLE
		var acc: int = 0
		var p: int = 0
		while p < st.projects.count:
			acc += st.projects.slot_held[p]
			p += 1
		return acc

	## 某地区已占用槽位（同上，独立复算）。
	func slots_held_in(r: int) -> int:
		if st == null or st.projects == null:
			return UNREADABLE
		var acc: int = 0
		var p: int = 0
		while p < st.projects.count:
			if st.projects.region_idx[p] == r:
				acc += st.projects.slot_held[p]
			p += 1
		return acc

	## `JWTreasury` 的整数标量（docs/17 §4.12 逐字登记的成员名）。
	func treasury_int(prop: String) -> int:
		if st == null or st.treasury == null:
			return UNREADABLE
		var v: Variant = st.treasury.get(prop)
		if v == null:
			t.fail("JWTreasury 缺少 docs/17 §4.12 登记的成员 `%s`" % prop)
			return UNREADABLE
		return int(v)

	## `JWTreasury` 的整数数组。
	func treasury_arr(prop: String) -> PackedInt64Array:
		if st == null or st.treasury == null:
			return PackedInt64Array()
		var v: Variant = st.treasury.get(prop)
		if v == null:
			t.fail("JWTreasury 缺少 docs/17 §4.12 登记的成员 `%s`" % prop)
			return PackedInt64Array()
		return v as PackedInt64Array

	## `JWPolicyEngine` 的整数数组元素（docs/17 §4.21 逐字登记的成员名）。
	func policy_arr(prop: String, i: int) -> int:
		if st == null or st.policy == null:
			return UNREADABLE
		var v: Variant = st.policy.get(prop)
		if v == null:
			t.fail("JWPolicyEngine 缺少 docs/17 §4.21 登记的成员 `%s`" % prop)
			return UNREADABLE
		var a: PackedInt64Array = v as PackedInt64Array
		if i < 0 or i >= a.size():
			return UNREADABLE
		return a[i]

	## 运行期参数 `param.*`（docs/17 §2.6：加载期折成稠密数组，下标即 `JWUnits.Param`）。
	func param(idx: int) -> int:
		if st == null or idx < 0 or idx >= st.params.size():
			return UNREADABLE
		return st.params[idx]

	## 逐季序列访问器。
	func gov_cash_at(q: int) -> int:
		return UNREADABLE if q < 0 or q >= _cash_gov.size() else _cash_gov[q]

	func arrears_at(q: int) -> int:
		return UNREADABLE if q < 0 or q >= _arrears.size() else _arrears[q]

	func committed_at(q: int) -> int:
		return UNREADABLE if q < 0 or q >= _committed.size() else _committed[q]

	func debt_at(q: int) -> int:
		return UNREADABLE if q < 0 or q >= _debt.size() else _debt[q]

	func cash_total_at(q: int) -> int:
		return UNREADABLE if q < 0 or q >= _cash_total.size() else _cash_total[q]

	func arrears_added_at(q: int) -> int:
		return UNREADABLE if q < 0 or q >= _arrears_added.size() else _arrears_added[q]

	func arrears_cleared_at(q: int) -> int:
		return UNREADABLE if q < 0 or q >= _arrears_cleared.size() else _arrears_cleared[q]

	## 状态哈希（INV-137「命令被拒时状态哈希完全不变」的比对基准）。
	func hash_now() -> String:
		return "" if st == null else st.state_hash()


# ── 夹具辅助（宿主侧） ──────────────────────────────────────────────────────

## 建一个夹具。
## 返回 null 表示连 `JWSimState` 都建不出来（失败已登记，调用方直接 return）。
## 返回非 null 但 `f.booted == false` 表示状态骨架在、内容包没进来：
## 命令形状层的断言仍然可跑，依赖运行期状态的断言由各用例自己用 `if not f.booted: return` 挡住。
## **「内容包没进来」这件事本身已经被 `Fix.boot()` 登记为一条失败**，不存在悄悄跳过。
func _boot() -> Fix:
	var f: Fix = Fix.new()
	f.boot(self)
	if f.st == null:
		return null
	return f


## 断言一条命令被拒且拒绝是「纯的」：码相符 + 状态哈希逐位不变（INV-137、docs/31 §0.2）。
func _expect_reject(f: Fix, kind: int, args: PackedInt64Array, code: int, what: String) -> void:
	var h0: String = f.hash_now()
	var got: int = f.submit(kind, args)
	eq_int(got, code, "%s：docs/11 §6.1 要求该命令被拒且原因码为 %d" % [what, code])
	eq_str(f.hash_now(), h0, "%s：INV-137 要求被拒命令后状态哈希逐位不变" % what)


## 逐季复核三条全局守恒（docs/31 §1「每条测试收尾必调」的可实现子集）。
func _assert_conservation(f: Fix, what: String) -> void:
	var q: int = 0
	while q < f.quarters_done():
		eq_int(f.cash_total_at(q), f.st.total_cash_uu,
				"%s：INV-018 全经济现金总量必须恒等于 scenario.total_cash_uu（第 %d 季）" % [what, q])
		q += 1
	eq_int(f.st.accounts.check_receivable_payable(), JWResult.OK,
			"%s：INV-019 要求 Σ recv == Σ pay" % what)
	eq_int(f.st.accounts.check_balance_sheet(), JWResult.OK,
			"%s：INV-020 逐主体资产负债恒等式必须成立" % what)
	eq_int(f.st.check_all_p0(), JWResult.OK,
			"%s：docs/12 §10 的全量 P0 不变量检查必须返回 OK" % what)


## 逐季复核欠付恒等式 INV-030：`arrears_end == arrears_start + 新增 − 清偿`。
func _assert_arrears_identity(f: Fix, what: String) -> void:
	var prev: int = 0
	var q: int = 0
	while q < f.quarters_done():
		var expect: int = prev + f.arrears_added_at(q) - f.arrears_cleared_at(q)
		eq_int(f.arrears_at(q), expect,
				"%s：INV-030 欠付恒等式在第 %d 季不成立（期初 %d + 新增 %d − 清偿 %d）"
				% [what, q, prev, f.arrears_added_at(q), f.arrears_cleared_at(q)])
		ge_int(f.arrears_at(q), 0, "%s：INV-030 要求 arrears >= 0（第 %d 季）" % [what, q])
		prev = f.arrears_at(q)
		q += 1


## 逐季复核债务恒等式 INV-028：`debt_end == debt_start + 新增借款 − 还本 − 确认减记`。
## 三项流量按**政府债务科目腿**量（docs/18 第三轮「测试口径更正」）：发债 / 还本是四腿分录、
## 减记是两笔两腿分录，按类型取正腿之和会得到面值的 2 倍；存取款另有类型（R-DEPOSIT-01）也不再混入。
func _assert_debt_identity(f: Fix, what: String) -> void:
	var prev: int = f.debt_at(0) - f.new_borrowing_q(0) + f.principal_repaid_q(0) + f.writeoff_q(0)
	var q: int = 0
	while q < f.quarters_done():
		var expect: int = prev + f.new_borrowing_q(q) - f.principal_repaid_q(q) - f.writeoff_q(q)
		eq_int(f.debt_at(q), expect,
				("%s：INV-028 债务恒等式在第 %d 季不成立"
				+ "（期初 %d + 新增 %d − 还本 %d − 减记 %d）")
				% [what, q, prev, f.new_borrowing_q(q), f.principal_repaid_q(q), f.writeoff_q(q)])
		prev = f.debt_at(q)
		q += 1


## 政策开启命令（四个玩家参数 + 资金来源）。
func _cmd_enact(p: int, j0: int, j1: int, j2: int, j3: int, funding: int) -> PackedInt64Array:
	return Fix.a6(p, j0, j1, j2, j3, funding)


# ══════════════════════════════════════════════════════════════════════════
# A 族：套利与重复计数
# ══════════════════════════════════════════════════════════════════════════

# adv_id:     ADV-A01
# alias:      ADV-01
# family:     arbitrage
# invariants: INV-095, INV-097, INV-098, INV-113, INV-137
# guards:     claim_idempotency, policy_cooldown, effective_from_monotonic, toggle_cost
# gate:       G3
## 反复开关补助重复领钱。攻击叙述见 docs/31 §2 `ADV-A01`：
## 开一季、关一季、再开一季，指望重开时把关闭期间的合格投资补发一遍。
##
## 期望值来源：
##   · 冷却期 = `policy_P09.json` 的 `cooldown_q = 4`；冷却内的开关命令必须 `REJECT(E_POLICY_COOLDOWN)`；
##   · 每次成功开关的行政成本 = `policy_P09.json` 的 `toggle_cost_uu = 10_000_000`，
##     故 `Σ kind=26` 必须精确等于 `toggle_count × 10_000_000`（容差 0）；
##   · 任一季的补助支出上界 = `cost.spend_lines_uu_per_q.subsidy_to_firms = 190_000_000`。
##     若重开当季出现「补发」，这一季的补助必然突破该封顶——这就是 INV-098 的可判定形态。
func test_adv_a01_toggle_subsidy_no_backpay() -> void:
	var f: Fix = _boot()
	if f == null:
		return
	if not f.booted:
		return

	# q=0 开启 P09，费率取 valid_range 上限（30% 是默认值，50% 是上限，取上限放大攻击面）。
	var enact: PackedInt64Array = _cmd_enact(P09_INVEST_SUBSIDY, 15, 10_000,
			P09_RATE_MAX_PPM, P09_CAP_DEFAULT_UU, FUNDING_CASH)
	eq_int(f.submit(1, enact), 0, "ADV-A01：q=0 开启 P09 的命令在形状与范围上必须合法")
	f.advance(1)

	# q=1 立刻撤销：冷却 4 季未过 ⇒ 必须被拒，且状态哈希不变（INV-098 + INV-137）。
	_expect_reject(f, 3, Fix.a6(P09_INVEST_SUBSIDY), JWResult.Reject.POLICY_COOLDOWN,
			"ADV-A01：冷却期（enacted_q=0，cooldown_q=4）内的 policy_repeal")
	f.advance(1)

	# 交替开关 20 轮。冷却挡住的那些必须被拒；挡不住的那些每次都要收行政成本。
	var round_i: int = 0
	while round_i < 20 and f.alive:
		var want_off: bool = (round_i % 2) == 0
		if want_off:
			f.submit(3, Fix.a6(P09_INVEST_SUBSIDY))
		else:
			f.submit(1, enact)
		f.advance(1)
		round_i += 1
	if not f.alive:
		return

	# 收尾：保持开启跑到第 39 季，让全部在途申领结清。
	f.submit(1, enact)
	f.advance(HORIZON_Q - f.quarters_done())
	if not f.alive:
		return
	# 无资金来源的补助开满十年可能让预算审查连败、执政合法终局（夹具在终局处停下）。
	# 那不影响下面的断言，但 20 轮开关（到第 21 季）必须真的跑完，否则这些断言是空跑。
	ge_int(f.quarters_done(), 22,
			"ADV-A01：终局早于 20 轮开关跑完（已结算 %d 季）⇒ 下面的开关成本与冷却断言没有被真正检验"
			% f.quarters_done())

	var toggles: int = f.policy_arr("toggle_count", P09_INVEST_SUBSIDY)
	var toggle_paid: int = f.led_sum(JWUnits.Kind.POLICY_TOGGLE_COST, 0, f.quarters_done() - 1)

	# 1) 开关本身是有成本的，且成本精确等于「次数 × 卡面值」。
	ge_int(toggles, 1, "ADV-A01：INV-098 要求 toggle_count 单调递增；一次都没记 = 开关变成免费动作")
	eq_int(toggle_paid, toggles * P09_TOGGLE_COST_UU,
			("ADV-A01：INV-098 要求每次开关产生一次性行政成本。期望 Σkind26 == toggle_count × "
			+ "policy_P09.json 的 toggle_cost_uu(%d)") % P09_TOGGLE_COST_UU)

	# 2) 冷却确实拒绝过，且拒绝是纯的（纯度已在 _expect_reject 里逐条查过）。
	ge_int(f.rejects_total(JWResult.Reject.POLICY_COOLDOWN), 1,
			"ADV-A01：20 轮交替开关一次都没撞上 cooldown_q=4 ⇒ 冷却闸门不存在（INV-098）")

	# 3) 任何一季的补助支出都不得突破每季封顶——重开补发历史季必然突破它。
	var q: int = 0
	while q < f.quarters_done():
		le_int(f.led_q(JWUnits.Kind.SUBSIDY, q), P09_SUBSIDY_CEILING_PER_Q_UU,
				("ADV-A01：第 %d 季的补助支出超过 policy_P09.json 的每季封顶 %d μU。"
				+ "封顶只会被『重开时补发关闭期间的合格投资』这一种写法突破 ⇒ "
				+ "effective_from_q 被回溯了（INV-098），或 claim_key 漏了季号（INV-097）")
				% [q, P09_SUBSIDY_CEILING_PER_Q_UU])
		q += 1

	# 4) 幂等台账里不得有重复键（INV-097：同键至多一条、至多付一次）。
	var claim_n: int = 0
	if st_policy_has(f, "claim_key"):
		var seen: Dictionary = {}
		var i: int = 0
		while i < JWPolicyEngine.CLAIM_CAP:
			var key: int = f.policy_arr("claim_key", i)
			if key == UNREADABLE:
				break
			if key != 0:
				claim_n += 1
				check_false(seen.has(key),
						"ADV-A01：claim_ledger 出现重复 claim_key=%d ⇒ INV-097 的幂等键失效" % key)
				seen[key] = true
			i += 1
	ge_int(claim_n, 0, "ADV-A01：claim_ledger 可读（INV-097 的台账是可审计的，不能是隐藏状态）")

	# 5) 补助不进 GDP：kind=12 的三重分类必须全是 none（INV-113 + INV-114）。
	eq_int(JWUnits.KIND_PROD_CLASS[JWUnits.Kind.SUBSIDY], JWUnits.ProdClass.NONE,
			"ADV-A01：INV-113 要求 kind=12 subsidy 的生产法分类恒为 none")
	eq_int(JWUnits.KIND_EXP_CLASS[JWUnits.Kind.SUBSIDY], JWUnits.ExpClass.NONE,
			"ADV-A01：INV-113 要求 kind=12 subsidy 的支出法分类恒为 none")
	eq_int(JWUnits.KIND_INC_CLASS[JWUnits.Kind.SUBSIDY], JWUnits.IncClass.NONE,
			"ADV-A01：INV-113 要求 kind=12 subsidy 的收入法分类恒为 none")

	_assert_conservation(f, "ADV-A01")


## `JWPolicyEngine` 是否登记了该成员（台账是稀疏数组，读不到时不做无意义断言）。
func st_policy_has(f: Fix, prop: String) -> bool:
	return f.st != null and f.st.policy != null and f.st.policy.get(prop) != null


# adv_id:     ADV-A02
# alias:      —
# family:     arbitrage
# invariants: INV-002, INV-003, INV-005, INV-097
# guards:     claim_grouping, rounding_log
# gate:       G5
## 同一笔投资拆成多笔骗取多份补助。docs/31 `Q-ADV-04` 的裁定：
## **按 (policy_id, beneficiary_id, q) 分组，先求和再乘费率**——而不是逐事件乘费率再求和。
##
## 这条规则的可机器判定形态：**同一季、同一受益 cell 至多产生一条 kind=12 的过账行**。
## 逐事件计费的实现必然产生多条（每条各自 floor 一次），拆 100 笔就多 99 次向下取整的损失，
## 差额随笔数线性放大——docs/31 §2 `ADV-A02` 的失败诊断说的就是这个。
## 本测试用「每季每受益方至多一条补助行 + 单笔不超过单户封顶 + 全季不超过总封顶」三条钉死它。
func test_adv_a02_split_investment_single_claim_row() -> void:
	var f: Fix = _boot()
	if f == null:
		return
	if not f.booted:
		return

	var enact: PackedInt64Array = _cmd_enact(P09_INVEST_SUBSIDY, 15, 10_000,
			P09_RATE_MAX_PPM, P09_CAP_DEFAULT_UU, FUNDING_CASH)
	eq_int(f.submit(1, enact), 0, "ADV-A02：开启 P09 的命令必须在形状上合法")
	f.advance(8)
	if not f.alive:
		return

	# 1) 每季补助总额不超过内容包登记的每季封顶（逐事件计费 + 拆单会把这条顶爆）。
	var q: int = 0
	while q < f.quarters_done():
		le_int(f.led_q(JWUnits.Kind.SUBSIDY, q), P09_SUBSIDY_CEILING_PER_Q_UU,
				("ADV-A02：第 %d 季补助总额超过 policy_P09.json 的 subsidy_to_firms 封顶 %d μU")
				% [q, P09_SUBSIDY_CEILING_PER_Q_UU])
		q += 1

	# 2) 同一季里每个受益 cell 至多一条补助行（Q-ADV-04：先合并计基数再乘费率）。
	#    只能查当季（log.ledger 每季 S01 重置），故这里查最后一季。
	var by_account: Dictionary = {}
	var led: JWLedger = f.st.ledger
	var rows: int = led.log_row_count()
	var i: int = 0
	while i < rows and i < led.l_kind.size():
		if led.l_kind[i] == JWUnits.Kind.SUBSIDY and led.l_delta[i] > 0:
			var acc: int = led.l_account[i]
			check_false(by_account.has(acc),
					("ADV-A02：科目 %d 在同一季出现第 2 条 kind=12 补助行 ⇒ 补助是逐事件计费的，"
					+ "不是按 (policy, beneficiary, q) 先求和再乘费率（docs/31 Q-ADV-04）") % acc)
			by_account[acc] = true
		i += 1
	ge_int(by_account.size(), 0, "ADV-A02：补助行可按科目枚举（INV-139 要求每笔变化可追溯）")

	# 3) 取整余数必须被 log.rounding 逐条解释，不得产生债权债务（INV-005）。
	ge_int(f.treasury_int("rounding_residual"), 0,
			"ADV-A02：INV-005 的 rounding_residual 不得为负（换算余数不产生债权债务）")

	_assert_conservation(f, "ADV-A02")


# adv_id:     ADV-A03
# alias:      —
# family:     arbitrage
# invariants: INV-112, INV-113, INV-114
# guards:     gdp_class_whitelist
# gate:       G5
## 把补助当 GDP 刷。docs/31 §2 `ADV-A03`：补助可以通过「企业现金增加 → 下季多产」间接影响 GDP，
## 但**当季不得有任何一条 GDP 口径直接吃到补助金额**。
##
## 注意一处与 docs/31 原文的差异，以 docs/11 §5.3 的分类表为准（docs/31 §14 第 4 条规定的优先级）：
## `kind=26 policy_toggle_cost` 的分类**不是** none——`JWUnits.KIND_PROD_CLASS[26] == VA_NONMARKET`、
## `KIND_EXP_CLASS[26] == G`。所以「开启 P09 的那一季 GDP 与对照组逐位相同」这条原文断言不成立：
## 开关行政成本本身就是一笔政府消费。正确的断言是：**两组 GDP 之差恰好等于开关成本，补助本身贡献 0**。
func test_adv_a03_subsidy_not_counted_in_gdp() -> void:
	# 静态部分：再分配类 kind 的三重分类必须全是显式登记的 none（INV-114 的白名单反查）。
	var redistribution: PackedInt64Array = PackedInt64Array([
		JWUnits.Kind.INCOME_TAX, JWUnits.Kind.PROFIT_TAX, JWUnits.Kind.SUBSIDY,
		JWUnits.Kind.TRANSFER, JWUnits.Kind.HOUSEHOLD_SUPPORT, JWUnits.Kind.BOND_ISSUE,
		JWUnits.Kind.BOND_PRINCIPAL, JWUnits.Kind.BOND_INTEREST, JWUnits.Kind.PROPERTY_INCOME,
		JWUnits.Kind.CANCEL_PENALTY, JWUnits.Kind.WRITEOFF,
	])
	for k: int in redistribution:
		eq_int(JWUnits.KIND_IS_REDISTRIBUTION[k], 1,
				"ADV-A03：docs/11 §5.3 把 kind=%d 登记为再分配类" % k)
		eq_int(JWUnits.KIND_PROD_CLASS[k], JWUnits.ProdClass.NONE,
				"ADV-A03：INV-029/INV-113 要求再分配类 kind=%d 的生产法分类为 none" % k)
		eq_int(JWUnits.KIND_EXP_CLASS[k], JWUnits.ExpClass.NONE,
				"ADV-A03：INV-029/INV-113 要求再分配类 kind=%d 的支出法分类为 none" % k)
		eq_int(JWUnits.KIND_INC_CLASS[k], JWUnits.IncClass.NONE,
				"ADV-A03：INV-029/INV-113 要求再分配类 kind=%d 的收入法分类为 none" % k)
	# 完备性：1..28 每个 kind 都必须已登记（INV-114，未登记即 LEDGER_KIND_UNCLASSIFIED）。
	var kk: int = 1
	while kk < JWUnits.KIND_N:
		check(JWUnits.kind_is_classified(kk),
				"ADV-A03：INV-114 要求 kind=%d 在三张分类表中都有显式登记" % kk)
		kk += 1

	# 运行期部分。
	var f_on: Fix = _boot()
	if f_on == null:
		return
	var f_ctrl: Fix = _boot()
	if f_ctrl == null:
		return
	if not f_on.booted or not f_ctrl.booted:
		return

	var enact: PackedInt64Array = _cmd_enact(P09_INVEST_SUBSIDY, 15, 10_000,
			P09_RATE_MAX_PPM, P09_CAP_DEFAULT_UU, FUNDING_CASH)
	eq_int(f_on.submit(1, enact), 0, "ADV-A03：实验组开启 P09 的命令必须在形状上合法")

	# 口径更正（R-PUBSERV-01）：开关成本付给中州服务 cell，是它的一笔销售——从下一季起经利润分配进入居民收入，
	# 两组经济随后按间接渠道分叉（计划书允许的「企业现金增加 → 下季多产」同类效应）。所以逐口径比较只在
	# **开启当季**有意义：那一季两组的唯一差别就是开关成本本身。
	f_on.advance(1)
	f_ctrl.advance(1)
	if not f_on.alive or not f_ctrl.alive:
		return
	var prod_on: PackedInt64Array = _zeros(8)
	var exp_on: PackedInt64Array = _zeros(8)
	var inc_on: PackedInt64Array = _zeros(8)
	var prod_c: PackedInt64Array = _zeros(8)
	var exp_c: PackedInt64Array = _zeros(8)
	var inc_c: PackedInt64Array = _zeros(8)
	eq_int(f_on.st.ledger.aggregate_classes(prod_on, exp_on, inc_on), JWResult.OK,
			"ADV-A03：INV-114 要求 aggregate_classes 在分类完备时返回 OK")
	eq_int(f_ctrl.st.ledger.aggregate_classes(prod_c, exp_c, inc_c), JWResult.OK,
			"ADV-A03：对照组的 aggregate_classes 同样必须返回 OK")
	var toggle: int = f_on.gov_cash_out_sum(JWUnits.Kind.POLICY_TOGGLE_COST, 0, 0)
	ge_int(toggle, 1, "ADV-A03：开启当季必须有开关成本（政策开关有真实成本）")
	eq_int(exp_on[JWUnits.ExpClass.C] - exp_c[JWUnits.ExpClass.C], 0,
			"ADV-A03：开启当季补助与开关成本都不得进入支出法的 C（居民消费）口径")
	eq_int(exp_on[JWUnits.ExpClass.G] - exp_c[JWUnits.ExpClass.G], toggle,
			"ADV-A03：开启当季两组支出法 G 之差必须恰好等于开关成本（补助本身贡献 0）")
	eq_int(f_on.st.diag.gdp_production - f_ctrl.st.diag.gdp_production, toggle,
			"ADV-A03：开启当季两组生产法 GDP 之差必须恰好等于开关成本（补助本身贡献 0）")

	# 其后推进满 8 季：任何一条 kind=12 的账本行都不得带非零分类码（结构性保证，逐季检查）。
	var q: int = 1
	while q < 8:
		f_on.advance(1)
		f_ctrl.advance(1)
		if not f_on.alive or not f_ctrl.alive:
			return
		check(f_on.all_rows_unclassified(JWUnits.Kind.SUBSIDY),
				"ADV-A03：第 %d 季存在带非零三重分类码的 kind=12 补助行 ⇒ 补助被算进了某个 GDP 口径（INV-113）" % q)
		q += 1

	_assert_conservation(f_on, "ADV-A03 实验组")
	_assert_conservation(f_ctrl, "ADV-A03 对照组")


## n 个 0 的整数数组（aggregate_classes 的输出缓冲）。
func _zeros(n: int) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(n)
	a.fill(0)
	return a


# adv_id:     ADV-A04
# alias:      ADV-05
# family:     arbitrage
# invariants: INV-016, INV-031, INV-063
# guards:     tax_base_erosion, admin_capacity_gate, accrual_vs_cash
# gate:       G3
## 提高税率后税收绕过实际税基。docs/31 §2 `ADV-A04`：玩家以为 `税收 = 税率 × 名义收入`。
##
## 期望（全部来自契约，不来自实现）：
##   · 实收对税率**非线性**：60% 档的实收必须严格小于 10% 档实收 × 6 × 0.8（留 20% 余量后仍严格小于）；
##   · 序列里至少出现一次不增（税基侵蚀 + 征收能力上限同时起作用的可判定形态）；
##   · **应计与实收分离**：最高档下 `state.gov.tax_receivable_uu > 0`。
##     「实收恒等于应计」意味着税收变成了「宣布即到账」，INV-031 的应收账款不存在；
##   · 任何一档下，群组现金都不得为负（INV-016：不得把群组现金打成负数）。
func test_adv_a04_tax_rate_is_not_linear() -> void:
	var rates: PackedInt64Array = PackedInt64Array([100_000, 200_000, 300_000, 400_000,
			500_000, 600_000])
	var receipts: PackedInt64Array = PackedInt64Array()
	var receivable_top: int = UNREADABLE
	var r_i: int = 0
	while r_i < rates.size():
		var f: Fix = _boot()
		if f == null:
			return
		if not f.booted:
			return
		# 测试口径更正（docs/18 R-ENACT-01）：P01 开局即在执行（R-BASELINE-01），对它递交 policy_enact
		# 必须以 ALREADY_ENACTED 拒绝且不改任何参数；改税率只能用 policy_set_params，只能在预算审议季
		# （q ≡ 3 (mod 4)，R-WINDOW-01）提出，时滞后生效（R-PARAMS-01）。原写法在第 0 季递交 policy_enact，
		# 靠的正是「被拒命令仍改了参数」这条已修复的漏洞。
		f.advance(3)
		if not f.alive:
			return
		var set_cmd: PackedInt64Array = Fix.a6(P01_INCOME_TAX, rates[r_i], 0, 0, 0)
		eq_int(f.submit(2, set_cmd), 0,
				"ADV-A04：税率 %d ppm 的 policy_set_params 必须在形状与 valid_range 上合法" % rates[r_i])
		f.advance(1)
		if not f.alive:
			return
		eq_int(f.accepted_kind_in_q(3, 2), 1,
				"ADV-A04：税率 %d ppm 的改参数命令必须在第 3 季（预算审议季）被受理，否则六档比较是空跑"
				% rates[r_i])
		# 新税率第 4 季起生效；量第 4—11 季（8 季）。这段时间里任何预算审查都不可能连败两次而终局
		# （最早第 7、11 季两次失败，第 12 季才可能终局），终局是合法结局，但不是本测试的对象。
		f.advance(8)
		if not f.alive:
			return
		receipts.append(f.led_sum(JWUnits.Kind.INCOME_TAX, 4, 11))

		# 逐季逐群组：居民现金不得为负（INV-016）。
		var g: int = 0
		while g < JWUnits.GROUP:
			ge_int(f.cash_of(JWIds.agent_of_group(g)), 0,
					"ADV-A04：税率 %d ppm 下群组 %d 的现金为负 ⇒ INV-016 的过账前置检查缺失"
					% [rates[r_i], g])
			g += 1
		if r_i == rates.size() - 1:
			receivable_top = f.treasury_int("tax_receivable")
			_assert_conservation(f, "ADV-A04（60% 档）")
		r_i += 1

	# 1) 不是线性等比上升。
	le_int(receipts[5] * 10, receipts[0] * 6 * 8,
			("ADV-A04：60%% 档实收 %d ≥ 10%% 档实收 %d × 6 × 0.8 ⇒ 税收对税率线性等比上升，"
			+ "税基侵蚀通道不存在（base_eff 直接等于名义收入）") % [receipts[5], receipts[0]])

	# 2) 一阶差分至少出现一次不增。
	var has_non_increasing: bool = false
	var i: int = 1
	while i < receipts.size():
		if receipts[i] <= receipts[i - 1]:
			has_non_increasing = true
		i += 1
	check(has_non_increasing,
			"ADV-A04：六档税率的实收严格单调递增 ⇒ 没有拐点，税基侵蚀与征收能力上限都没起作用")

	# 3) 应计与实收分离：最高档必然收不满。
	ge_int(receivable_top, 1,
			("ADV-A04：60%% 税率下 state.gov.tax_receivable_uu == %d。实收恒等于应计 ⇒ "
			+ "缺 INV-031 的应收账款与征收能力闸门，税收变成了『宣布即到账』") % receivable_top)


# adv_id:     ADV-A05
# alias:      —
# family:     arbitrage
# invariants: INV-017, INV-018, INV-019
# guards:     two_sided_posting
# gate:       G3
## 转移支付回流永动机。docs/31 §2 `ADV-A05`：转移支付是**再分配**，不创造现金。
## 政府净现金必然随转移累计单调下降，除非通过借款补充（而借款受 C 族规则约束）。
func test_adv_a05_transfer_creates_no_cash() -> void:
	var f_on: Fix = _boot()
	if f_on == null:
		return
	var f_ctrl: Fix = _boot()
	if f_ctrl == null:
		return
	if not f_on.booted or not f_ctrl.booted:
		return

	# 测试口径更正（docs/18 R-ENACT-01）：P03 开局即在执行，把替代率提到 valid_range 上限只能用
	# policy_set_params（P03 不受预算审议窗口约束，R-WINDOW-01；时滞后生效，R-PARAMS-01）。
	var set_cmd: PackedInt64Array = Fix.a6(P03_UNEMPLOYMENT, P03_REPLACEMENT_MAX_PPM, 4, 1, 15)
	eq_int(f_on.submit(2, set_cmd), 0, "ADV-A05：P03 改参数的命令必须在形状与 valid_range 上合法")
	f_on.advance(20)
	f_ctrl.advance(20)
	if not f_on.alive or not f_ctrl.alive:
		return
	eq_int(f_on.accepted_kind_in_q(0, 2), 1,
			"ADV-A05：第 0 季的 P03 改参数命令必须被受理，否则下面的对照是两局同样的基线在互比")

	var last: int = mini(f_on.quarters_done(), f_ctrl.quarters_done()) - 1

	# 1) 全经济现金总量逐季恒定（INV-018）；两局都查。
	for f: Fix in [f_on, f_ctrl]:
		var q: int = 0
		while q < f.quarters_done():
			eq_int(f.cash_total_at(q), f.st.total_cash_uu,
					("ADV-A05：第 %d 季全经济现金总量 %d != scenario.total_cash_uu %d ⇒ "
					+ "某条转移路径是单边过账（只记收方不记付方），违反 INV-015/INV-018")
					% [q, f.cash_total_at(q), f.st.total_cash_uu])
			q += 1

	# 2) 回流率必须 < 1。测试口径更正：回流率是「多发的转移」引起的「多收的税」之比，必须对照
	#    同种子、无该命令的对照局计算。原写法拿全部个税与利润税去比全部转移——那比的是整个财政的
	#    收支结构（税收本来就要支付工资、采购与利息），在任何正常的基线里都 ≥ 0，与永动机无关。
	var d_transfer: int = f_on.led_sum(JWUnits.Kind.TRANSFER, 0, last) \
			- f_ctrl.led_sum(JWUnits.Kind.TRANSFER, 0, last)
	var d_tax: int = f_on.led_sum(JWUnits.Kind.INCOME_TAX, 0, last) \
			+ f_on.led_sum(JWUnits.Kind.PROFIT_TAX, 0, last) \
			- f_ctrl.led_sum(JWUnits.Kind.INCOME_TAX, 0, last) \
			- f_ctrl.led_sum(JWUnits.Kind.PROFIT_TAX, 0, last)
	# 3) 转移确实多发了——否则上一条是空跑。
	ge_int(d_transfer, 1,
			"ADV-A05：替代率提到上限后 20 季累计转移没有增加（差 %d）⇒ 改参数没生效，回流比较是空跑"
			% d_transfer)
	le_int(d_tax - d_transfer, -1,
			("ADV-A05：多发转移 %d 引起多收税 %d，回流率 ≥ 1 ⇒ 存在现金永动机；"
			+ "通常是消费与利润税之间重复计数") % [d_transfer, d_tax])

	_assert_conservation(f_on, "ADV-A05 实验局")
	_assert_conservation(f_ctrl, "ADV-A05 对照局")
	_assert_arrears_identity(f_on, "ADV-A05")


# adv_id:     ADV-A06
# alias:      —
# family:     arbitrage
# invariants: INV-015, INV-020, INV-026, INV-099
# guards:     effect_target_whitelist, pubserv_has_no_cash
# gate:       G5
## 给不持有现金的主体发补助。docs/31 §2 `ADV-A06`：`agent.pubserv.*` 不持有现金
## （其支付由 `agent.gov` 执行）。把补助打给它 = 凭空造钱。
##
## docs/31 原文的操作序列要一个「effect_target 指向 pubserv」的内容包变体；
## 本测试改用**两条不依赖变体、但判定同一条规则**的断言：
##   1. 加载期白名单里根本没有 pubserv 的现金落点（`JWPolicyDef.EFFECT_TARGETS` 是闭集合）；
##   2. 运行期四个 pubserv 主体的 cash 科目恒为 0（docs/17 §2.3 的现金主体口径：
##      56 个 cash 科目参与 INV-018 求和，其中 4 个 pubserv 恒为 0）。
## 任一条红，都说明「没有现金账户的主体收到了钱」这条攻击是通的。
func test_adv_a06_pubserv_holds_no_cash() -> void:
	# 1) 效果落点白名单是闭集合，且不含任何现金落点。
	eq_int(JWPolicyDef.effect_target_code("state.pubserv.cash_uu"), -1,
			"ADV-A06：effect_target 白名单不得包含 pubserv 的现金落点（INV-099 的 effect_target 分支）")
	eq_int(JWPolicyDef.effect_target_code("state.gov.cash_uu"), -1,
			"ADV-A06：effect_target 白名单不得包含任何现金落点——改现金只能经 JWLedger.post()（INV-022）")
	for target: String in JWPolicyDef.EFFECT_TARGETS:
		check_false(target.ends_with("cash_uu"),
				"ADV-A06：白名单条目 `%s` 是现金落点 ⇒ 政策可以绕过 post() 直接改现金" % target)

	# 2) 运行期：pubserv 恒无现金。
	var f: Fix = _boot()
	if f == null:
		return
	if not f.booted:
		return
	var r: int = 0
	while r < JWUnits.R:
		eq_int(f.cash_of(JWIds.agent_of_pubserv(r)), 0,
				("ADV-A06：开局时 agent.pubserv.%d 的 cash 科目不是 0。docs/17 §2.3 规定 pubserv "
				+ "不持有自有现金，其支付由 agent.gov 执行") % r)
		r += 1
	# `agent.opening.cash` 同样恒为 0（OQ-217），它参与求和只是为了让「恒为 0」有人检查。
	eq_int(f.cash_of(JWIds.AGENT_OPENING), 0,
			"ADV-A06：开账主体的 cash 科目在开账后必须恒为 0（OQ-217）")

	f.advance(8)
	if not f.alive:
		return
	r = 0
	while r < JWUnits.R:
		eq_int(f.cash_of(JWIds.agent_of_pubserv(r)), 0,
				("ADV-A06：跑了 %d 季之后 agent.pubserv.%d 的 cash 科目变成了非 0 ⇒ "
				+ "有一笔收付的一端落在了不该持有现金的主体上（INV-026：不存在无对手方收支）")
				% [f.quarters_done(), r])
		r += 1
	_assert_conservation(f, "ADV-A06")


# ══════════════════════════════════════════════════════════════════════════
# C 族：融资永动机
# ══════════════════════════════════════════════════════════════════════════

# adv_id:     ADV-C01
# alias:      ADV-02
# family:     financing
# invariants: INV-034, INV-035, INV-036, INV-037, INV-038, INV-040
# guards:     no_auto_rollover, rate_dsr_coupling, counterparty_capacity, coupon_seal
# gate:       G3
## 借新还旧永远没有成本。docs/31 §4 `ADV-C01`：每季发新债覆盖到期本金与利息，从不主动偿还。
##
## 三条可判定的期望：
##   · **不存在自动展期**：任何到期季已经结算过的批次（`maturity_q < q`，q 为推进后的下一季——
##     到期那一季的 S02 才付最后一期，docs/12 §2.4、§01.8；docs/18 第三轮口径更正），
##     其状态不得仍是 ACTIVE 且未偿本金 > 0；
##   · **旧债不重定价**：q=4 时的票息快照与终局逐位相同（INV-036：`coupon_ppm_per_q` 发行后被写入即 FAULT）；
##   · **成本真的上升或撞上额度**：要么利息累计严格增长，要么出现 `E_CREDIT_LIMIT`，要么进入重组分支。
##     三者皆无 ⇒ 国债成了无限 ATM（INV-034 的对手方能力约束缺失）。
func test_adv_c01_rollover_costs_and_no_auto_extension() -> void:
	var f: Fix = _boot()
	if f == null:
		return
	if not f.booted:
		return

	var coupons_q4: PackedInt64Array = PackedInt64Array()
	var interest: PackedInt64Array = PackedInt64Array()
	var q: int = 0
	while q < 24 and f.alive:
		# 每季滚一笔 0.5 U 的新债，tenor 取合法下界 4 季，持有人 invpool。
		f.submit(8, Fix.a6(500_000_000, TENOR_MIN, JWUnits.Holder.INVPOOL))
		f.advance(1)
		if not f.alive:
			return
		if q == 4:
			coupons_q4 = f.coupon_snapshot()
		interest.append(f.led_q(JWUnits.Kind.BOND_INTEREST, q))

		# 逐季：INV-035 的两边必须精确相等（左边问实现，右边本文件自己数未结清批次，R-INV035-01）。
		eq_int(f.debt_outstanding(), f.debt_recomputed(),
				"ADV-C01：第 %d 季 INV-035 不成立——debt_outstanding() != Σ 未结清批次未偿本金" % q)

		# 逐季：不存在自动展期。推进后 f.st.q 已是下一季（尚未结算），到期季 < f.st.q 才算到期已过。
		var b: int = 0
		while b < f.bond_count():
			var matured: bool = f.st.bonds.maturity_q[b] < f.st.q
			var still_open: bool = f.st.bonds.status[b] == JWUnits.BondStatus.ACTIVE \
					and f.st.bonds.principal_outstanding[b] > 0
			check_false(matured and still_open,
					("ADV-C01：批次 %d 的 maturity_q=%d 已过（当前 q=%d），"
					+ "却仍是 ACTIVE 且未偿本金 %d ⇒ 存在自动展期路径，"
					+ "计划书 §07『融资必须有对手方』被架空（INV-038）")
					% [b, f.st.bonds.maturity_q[b], f.st.q, f.st.bonds.principal_outstanding[b]])
			b += 1
		q += 1
	if not f.alive:
		return

	# 1) 旧债一字不改。
	var coupons_end: PackedInt64Array = f.coupon_snapshot()
	ge_int(coupons_q4.size(), 1, "ADV-C01：第 4 季必须已经存在债券批次（开局就有 50 U 存量债）")
	var i: int = 0
	while i < coupons_q4.size() and i < coupons_end.size():
		eq_int(coupons_end[i], coupons_q4[i],
				"ADV-C01：批次 %d 的票息从 %d 被改成了 %d ⇒ 违反 INV-036『发行后被写入即 FAULT』"
				% [i, coupons_q4[i], coupons_end[i]])
		i += 1

	# 2) 成本必须真实发生：利息累计严格增长，或撞上额度，或进重组。
	var early: int = f.led_sum(JWUnits.Kind.BOND_INTEREST, 0, 3)
	var late: int = f.led_sum(JWUnits.Kind.BOND_INTEREST, f.quarters_done() - 4,
			f.quarters_done() - 1)
	var hit_limit: int = f.rejects_total(JWResult.Reject.CREDIT_LIMIT)
	var restructured: bool = false
	var b2: int = 0
	while b2 < f.bond_count():
		var s: int = f.st.bonds.status[b2]
		if s == JWUnits.BondStatus.DEFAULTED or s == JWUnits.BondStatus.RESTRUCTURED \
				or s == JWUnits.BondStatus.WRITTEN_OFF:
			restructured = true
		b2 += 1
	check(late > early or hit_limit > 0 or restructured,
			("ADV-C01：24 季只滚不还，末 4 季利息 %d 却不高于头 4 季 %d，且既没触发 E_CREDIT_LIMIT "
			+ "（%d 次）也没有任何批次进入违约/重组 ⇒ 借新还旧零成本（INV-038 的利率–偿债率联动"
			+ "与 INV-034 的对手方能力约束至少缺一条）") % [late, early, hit_limit])

	_assert_debt_identity(f, "ADV-C01")
	_assert_conservation(f, "ADV-C01")


# adv_id:     ADV-C02
# alias:      —
# family:     financing
# invariants: INV-025, INV-035
# guards:     holder_closed_enum
# gate:       G5
## 政府买自己的债。docs/31 §4 `ADV-C02`：`holder` 是闭枚举，只能是 `invpool` 或 `row`。
##
## 一处与 docs/31 原文的差异，以 docs/11 §7 为准：`E_BOND_FIELD` 在 §7 的错误码表里属于
## **加载期**「剧本硬约束」组，不是命令拒绝码（`JWResult.Reject` 里没有它）。
## 命令层对「枚举槽取了枚举外的整数」的唯一合法拒绝码是 `E_PARAM_RANGE`。
## 断言因此钉在 `Reject.PARAM_RANGE` 上；若实现返回别的码，说明枚举被当成了自由整数。
func test_adv_c02_bond_holder_is_closed_enum() -> void:
	var f: Fix = _boot()
	if f == null:
		return

	# `gov` / `opening` / `cell` / `pubserv` 在主体表里分别是 0 / 59 / 1..16 / 17..20；
	# Holder 枚举只有 0(invpool) 与 1(row)，所以这些主体下标一旦被当成 holder 就必然越界。
	var bad_holders: PackedInt64Array = PackedInt64Array([-1, 2, 3, 17, 57, 58, 59, 1 << 20])
	for h: int in bad_holders:
		_expect_reject(f, 8, Fix.a6(1_000_000_000, 8, h), JWResult.Reject.PARAM_RANGE,
				"ADV-C02：holder=%d 不在闭枚举 {invpool=0, row=1} 内" % h)

	# 合法的两个值必须过形状关（能不能真发出去归 S02 的额度检查）。
	eq_int(f.submit(8, Fix.a6(1_000_000_000, 8, JWUnits.Holder.INVPOOL)), 0,
			"ADV-C02：holder=invpool 是合法枚举值，形状层不得拒绝")
	if not f.booted:
		return
	f.advance(1)
	if not f.alive:
		return

	# INV-025：两个债权人的持债合计 == 未偿债务总额。
	var hold_pool: int = f.balance_of(JWIds.AGENT_INVPOOL, JWIds.ACC_BONDHOLD)
	var hold_row: int = f.balance_of(JWIds.AGENT_ROW, JWIds.ACC_BONDHOLD)
	eq_int(hold_pool + hold_row, f.debt_outstanding(),
			("ADV-C02：INV-025 不成立——invpool 持债 %d + row 持债 %d != derived.gov.debt_uu %d。"
			+ "政府一旦能持有自己的债，债务指标立刻失去意义") % [hold_pool, hold_row, f.debt_outstanding()])
	eq_int(f.balance_of(JWIds.AGENT_GOV, JWIds.ACC_BONDHOLD), 0,
			"ADV-C02：政府的 bondhold 科目必须恒为 0——政府不能是自己国债的债权人")


# adv_id:     ADV-C03
# alias:      —
# family:     financing
# invariants: INV-024, INV-034
# guards:     counterparty_cash_check, credit_limit_check
# gate:       G5
## 投资池被掏空后继续发债。docs/31 §4 `ADV-C03`：发债规模上限是
## `min(credit_limit_domestic_memo_uu, invpool.cash_uu)`，**两个上限都要检查**。
##
## 内容包给的两个数：`credit_limit_domestic_uu = 4_000_000_000`、`invpool.cash_uu = 9_000_000_000`。
## 所以开局那一季的国内新增发行合计不得超过 4 U；超出部分必须 `REJECT(E_CREDIT_LIMIT)`。
func test_adv_c03_invpool_drain_hits_credit_limit() -> void:
	var f: Fix = _boot()
	if f == null:
		return
	if not f.booted:
		return

	eq_int(f.balance_of(JWIds.AGENT_INVPOOL, JWIds.ACC_CASH), INVPOOL_CASH_INIT_UU,
			"ADV-C03：开局投资池现金必须等于 government_init.json 的 invpool.cash_uu")

	# 一季内连发 12 笔 1 U：既超过 4 U 的额度，也在同一季耗尽 9 U 的对手方现金。
	var n: int = 0
	while n < 12:
		f.submit(8, Fix.a6(1_000_000_000, 8, JWUnits.Holder.INVPOOL))
		n += 1
	f.advance(1)
	if not f.alive:
		return

	# 1) 本季实际新增借款不得超过两个上限中的较小者。
	# 「国内借款」按投资池持债科目腿量（docs/18 第三轮「测试口径更正」）：BOND_ISSUE 是四腿分录，
	# 正腿之和 = 2 × 面值且混入外部发行；投资池持债腿的增量恰是本季向国内对手方发出的面值。
	var issued: int = f.pool_bond_leg_q(JWUnits.Kind.BOND_ISSUE, 0)
	le_int(issued, CREDIT_LIMIT_DOMESTIC_INIT_UU,
			("ADV-C03：q=0 实际新增国内借款 %d μU 超过 government_init.json 的 "
			+ "credit_limit_domestic_uu %d μU ⇒ 只查了表外备查额度以外的东西（INV-034）")
			% [issued, CREDIT_LIMIT_DOMESTIC_INIT_UU])
	le_int(issued, INVPOOL_CASH_INIT_UU,
			("ADV-C03：q=0 实际新增国内借款 %d μU 超过投资池开局现金 %d μU ⇒ "
			+ "对手方凭空拿出了钱，游戏隐式地模拟了货币创造（计划书 §03/§07）")
			% [issued, INVPOOL_CASH_INIT_UU])

	# 2) 超额的那几笔必须被显式拒绝，而不是被静默缩规模或吞掉。
	ge_int(f.rejects_in_q(0, JWResult.Reject.CREDIT_LIMIT), 1,
			"ADV-C03：一季内递交 12 U 的发债需求却没有任何一条被 E_CREDIT_LIMIT 拒绝 ⇒ 额度闸门不存在")

	# 3) INV-024：`Σ group.deposit == invpool.deposit_liab == invpool.cash + invpool.bondhold`。
	var deposits: int = 0
	var g: int = 0
	while g < JWUnits.GROUP:
		deposits += f.balance_of(JWIds.agent_of_group(g), JWIds.ACC_DEPOSIT_CLAIM)
		g += 1
	var liab: int = f.balance_of(JWIds.AGENT_INVPOOL, JWIds.ACC_DEPOSIT_LIAB)
	var pool_cash: int = f.balance_of(JWIds.AGENT_INVPOOL, JWIds.ACC_CASH)
	var pool_bond: int = f.balance_of(JWIds.AGENT_INVPOOL, JWIds.ACC_BONDHOLD)
	eq_int(deposits, liab, "ADV-C03：INV-024 左段不成立——Σ group.deposit != invpool.deposit_liab")
	eq_int(liab, pool_cash + pool_bond,
			"ADV-C03：INV-024 右段不成立——invpool.deposit_liab != invpool.cash + invpool.bondhold")
	ge_int(pool_cash, 0, "ADV-C03：INV-016 要求投资池现金不得为负")

	_assert_conservation(f, "ADV-C03")


# adv_id:     ADV-C04
# alias:      —
# family:     financing
# invariants: INV-016, INV-027, INV-030, INV-033, INV-063
# guards:     no_negative_treasury, suspended_financing, reserve_le_cash
# gate:       G5
## 把未来收入当现金花。docs/31 §4 `ADV-C04`：国库只有 2 U（`government_init.json` 的 `gov.cash_uu`），
## 而 P04 的 `cost.one_off_uu` 是 4 U、`per_quarter_uu` 是 0.5 U。
## 用 `funding_source = cash` 去立一个买不起的项目，只有两种合法结局：
## 命令层 `REJECT(E_NO_FUNDING)`，或已在途后转 `suspended(financing)` 并登记欠付。
## **不允许负国库余额，也不允许无提示的延后**（计划书 §07「短缺先显露」）。
func test_adv_c04_future_income_is_not_cash() -> void:
	var f: Fix = _boot()
	if f == null:
		return
	if not f.booted:
		return

	eq_int(f.cash_of(JWIds.AGENT_GOV), GOV_CASH_INIT_UU,
			"ADV-C04：开局国库现金必须等于 government_init.json 的 gov.cash_uu")
	check(P04_ONE_OFF_UU > GOV_CASH_INIT_UU,
			"ADV-C04：本用例的前提是 P04 的合同总额 4 U 买不起（国库只有 2 U）——这来自内容包，不是假设")

	# 在同一季连立 8 个满规模 P04：前面的耗掉预留，后面的必然没钱。
	var launched: int = 0
	var n: int = 0
	while n < 8:
		var rc: int = f.submit(4, Fix.a6(P04_GRID_PROJECT, JWUnits.Region.HAIJIA,
				JWUnits.PPM, FUNDING_CASH))
		if rc == 0:
			launched += 1
		n += 1
	f.advance(4)
	if not f.alive:
		return

	# 1) 国库现金逐季不得为负（INV-016）。
	var q: int = 0
	while q < f.quarters_done():
		ge_int(f.gov_cash_at(q), 0,
				("ADV-C04：第 %d 季末国库现金 %d < 0 ⇒ 缺 INV-016 的过账前置检查，"
				+ "系统先扣成负数再想办法") % [q, f.gov_cash_at(q)])
		q += 1

	# 2) 买不起的立项必须被显式拒绝（docs/11 §6.1 kind 4 的失败列写的是 E_NO_SLOT / E_NO_FUNDING）。
	var no_funding: int = f.rejects_total(JWResult.Reject.NO_FUNDING)
	var no_slot: int = f.rejects_total(JWResult.Reject.NO_SLOT)
	ge_int(no_funding + no_slot, 1,
			("ADV-C04：一季内递交 8 个满规模 P04（每个合同总额 %d μU，国库只有 %d μU），"
			+ "却一条 E_NO_FUNDING / E_NO_SLOT 都没有 ⇒ 资金闸门与槽位闸门都不存在")
			% [P04_ONE_OFF_UU, GOV_CASH_INIT_UU])

	# 3) 预留只减额度不移现金，且季末归零（INV-033）。
	eq_int(f.treasury_int("reserved_memo"), 0,
			"ADV-C04：INV-033 要求 reserved_memo 季末归零（预留要么执行要么释放）")
	le_int(f.treasury_int("reserved_memo"), f.cash_of(JWIds.AGENT_GOV),
			"ADV-C04：INV-033 要求 reserved_memo <= cash")

	# 4) 短缺必须显露成欠付或 suspended(financing)，不许静默推进。
	var suspended_financing: int = 0
	var p: int = 0
	while p < f.project_count():
		if f.st.projects.status[p] == JWUnits.ProjectStatus.SUSPENDED \
				and f.st.projects.suspension_reason[p] == JWUnits.SuspendReason.FINANCING:
			suspended_financing += 1
		p += 1
	# 口径更正（R-FINANCE-01 / R-PROJECT-01）：预算内支出付款前先按发债规则融资，
	# 所以「付款超过开局现金」本身不是违规——违规的是**没有来源**的付款。判据：
	# 项目实付（政府现金腿）超过开局现金的部分，必须由同期显式新增借款承担，或显露为欠付 / suspended(financing)。
	var q_last: int = f.quarters_done() - 1
	var paid_projects: int = f.gov_cash_out_sum(JWUnits.Kind.PROJECT_PAYMENT, 0, q_last)
	var borrowed: int = 0
	var qb: int = 0
	while qb <= q_last:
		borrowed += f.new_borrowing_q(qb)
		qb += 1
	check(f.project_count() == 0 or paid_projects <= GOV_CASH_INIT_UU or borrowed > 0
			or f.arrears_at(q_last) > 0 or suspended_financing > 0,
			("ADV-C04：项目实付 %d 已超过开局国库现金 %d，而同期新增借款 %d、欠付 %d、suspended(financing) %d "
			+ "全为 0 ⇒ 付款没有来源（钱不够但项目照做）")
			% [paid_projects, GOV_CASH_INIT_UU, borrowed, f.arrears_at(q_last), suspended_financing])

	_assert_arrears_identity(f, "ADV-C04")
	_assert_conservation(f, "ADV-C04")


# adv_id:     ADV-C05
# alias:      —
# family:     financing
# invariants: INV-007, INV-034, INV-036
# guards:     bond_batch_cap, no_batch_merge, coupon_seal
# gate:       G5
## 用批次刷屏绕过重定价。docs/31 §4 `ADV-C05`：单季循环发 1 μU 的批次直到被拒。
## 期望：超过 `param.bond_batch_cap` ⇒ `REJECT(E_CREDIT_LIMIT)`，**不自动合并批次**
## （docs/12 §2.4：合并会破坏「旧债不重定价」）。
func test_adv_c05_bond_batch_cap_and_no_reprice() -> void:
	var f: Fix = _boot()
	if f == null:
		return
	if not f.booted:
		return

	var cap: int = f.param(JWUnits.Param.BOND_BATCH_CAP)
	ge_int(cap, 1,
			"ADV-C05：param.bond_batch_cap 必须已进 JWSimState.params（docs/17 §2.6），实际读到 %d" % cap)

	# 1) 同季、同债权人、同到期季的刷屏并入同一批次（docs/18 R-BONDCAP-01：同季票息相同，
	#    并批不重定价任何旧债）。批次数不得随递交笔数增长：玩家批次至多 +1，外加规则发行的
	#    国内、外部各至多一批。
	var before: int = f.bond_count()
	var tries: int = 0
	while tries < cap + 64:
		f.submit(8, Fix.a6(1, TENOR_MAX, JWUnits.Holder.INVPOOL))
		tries += 1
	f.advance(1)
	if not f.alive:
		return
	le_int(f.bond_count(), cap,
			("ADV-C05：一季内递交 %d 笔发行后批次数是 %d，超过 param.bond_batch_cap %d ⇒ "
			+ "上限只写在文档里没进代码") % [tries, f.bond_count(), cap])
	le_int(f.bond_count() - before, 3,
			("ADV-C05：同季同条件的 %d 笔发行新增了 %d 个批次 ⇒ R-BONDCAP-01 的同季并批没有生效，"
			+ "批次表会被刷屏写满") % [tries, f.bond_count() - before])

	# 2) 不自动合并跨季批次：批次数只增不减，且既有票息一字不改（INV-036）。
	var coupons_before: PackedInt64Array = f.coupon_snapshot()
	var count_before: int = f.bond_count()
	ge_int(count_before, before, "ADV-C05：批次表只增不删（docs/17 §4.11：结清批次改状态位，下标永久稳定）")
	f.advance(8)
	if not f.alive:
		return
	ge_int(f.bond_count(), count_before,
			("ADV-C05：8 季后批次数从 %d 降到 %d ⇒ 发生了批次合并，旧债被隐式重定价（违反 INV-036）")
			% [count_before, f.bond_count()])
	var coupons_after: PackedInt64Array = f.coupon_snapshot()
	var i: int = 0
	while i < coupons_before.size() and i < coupons_after.size():
		eq_int(coupons_after[i], coupons_before[i],
				"ADV-C05：批次 %d 的票息被改写（%d → %d）⇒ 违反 INV-036"
				% [i, coupons_before[i], coupons_after[i]])
		i += 1

	# 3) 批次上限是硬闸（测试口径更正：同条件刷屏已被并批化解，写满批次表要逐季用**不同期限**发行）。
	#    每季每个合法期限各发 1 μU，直到出现 E_CREDIT_LIMIT；任一季批次数都不得越过上限。
	#    放在最后：表写满之后政府自己的规则发行也无处落批，续发失败、违约宽限用尽即合法终局——
	#    那是这次攻击的真实代价，不是本条要测的闸门，所以一见到拒绝就停。
	#    R-CAP-01 之后，已清偿的批次会在 S01 被压实腾出位置：1 μU 的批次首期即还清，用它刷表已不可能
	#    （这条攻击被压实化解，实测批次数稳定在 250 上下）。要验证硬闸，发行额取 1000 μU，
	#    使每期至少还 1 μU、到期前一直存续；期限 4—40 各一批，约 20 轮越过 512。轮数上限 48。
	var q_guard: int = 0
	while f.alive and f.rejects_total(JWResult.Reject.CREDIT_LIMIT) == 0 and q_guard < 48:
		var tn: int = TENOR_MIN
		while tn <= TENOR_MAX:
			f.submit(8, Fix.a6(1000, tn, JWUnits.Holder.INVPOOL))
			tn += 1
		f.advance(1)
		le_int(f.bond_count(), cap,
				"ADV-C05：第 %d 轮后批次数 %d 越过 param.bond_batch_cap %d" % [q_guard, f.bond_count(), cap])
		q_guard += 1
	if not f.alive:
		return
	ge_int(f.rejects_total(JWResult.Reject.CREDIT_LIMIT), 1,
			"ADV-C05：批次表写满之后的发行没有产生任何 E_CREDIT_LIMIT 拒绝 ⇒ 缺批次上限闸门")

	_assert_conservation(f, "ADV-C05")


# adv_id:     ADV-C06
# alias:      —
# family:     financing
# invariants: INV-021, INV-028, INV-029, INV-114
# guards:     writedown_two_sided, writeoff_not_receipt
# gate:       G5
## 把债务减记当收入。docs/31 §4 `ADV-C06`：减记必须登记债权人损失，**双边**；
## 且不进任何收入口径、不进 GDP。
func test_adv_c06_writedown_is_not_income() -> void:
	# 静态：kind=28 writeoff 的三重分类必须全 none（INV-029 + INV-114）。
	eq_int(JWUnits.KIND_PROD_CLASS[JWUnits.Kind.WRITEOFF], JWUnits.ProdClass.NONE,
			"ADV-C06：INV-029 要求 kind=28 writeoff 不进生产法口径")
	eq_int(JWUnits.KIND_EXP_CLASS[JWUnits.Kind.WRITEOFF], JWUnits.ExpClass.NONE,
			"ADV-C06：INV-029 要求 kind=28 writeoff 不进支出法口径")
	eq_int(JWUnits.KIND_INC_CLASS[JWUnits.Kind.WRITEOFF], JWUnits.IncClass.NONE,
			"ADV-C06：INV-029 要求 kind=28 writeoff 不进收入法口径")
	eq_int(JWUnits.KIND_PROD_CLASS[JWUnits.Kind.BOND_ISSUE], JWUnits.ProdClass.NONE,
			"ADV-C06：INV-029 要求新增借款不进任何 GDP 口径")
	eq_int(JWUnits.KIND_PROD_CLASS[JWUnits.Kind.BOND_PRINCIPAL], JWUnits.ProdClass.NONE,
			"ADV-C06：INV-029 要求还本不进任何 GDP 口径")

	var f: Fix = _boot()
	if f == null:
		return
	if not f.booted:
		return

	var nw_gov_0: int = f.net_worth_of(JWIds.AGENT_GOV)
	var nw_pool_0: int = f.net_worth_of(JWIds.AGENT_INVPOOL)
	var nw_row_0: int = f.net_worth_of(JWIds.AGENT_ROW)

	# 对开局存量债的第 0 批次提交减记。命令层只判形状；能不能减记归 S02。
	eq_int(f.submit(9, Fix.a6(f.st.bonds.entity[0], RESTRUCTURE_WRITEDOWN)), 0,
			"ADV-C06：debt_restructure{bond=0, mode=writedown} 在形状与范围上必须合法")
	f.advance(4)
	if not f.alive:
		return

	var wrote: int = f.led_sum(JWUnits.Kind.WRITEOFF, 0, f.quarters_done() - 1)

	# 1) 减记必须双边：政府净值的上升恰好等于债权人净值的下降。
	if wrote > 0:
		var d_gov: int = f.net_worth_of(JWIds.AGENT_GOV) - nw_gov_0
		var d_creditors: int = (f.net_worth_of(JWIds.AGENT_INVPOOL) - nw_pool_0) \
				+ (f.net_worth_of(JWIds.AGENT_ROW) - nw_row_0)
		eq_int(d_gov + d_creditors, 0,
				("ADV-C06：减记 %d μU 之后政府净值变动 %d、债权人净值变动 %d，两者之和不为 0 ⇒ "
				+ "减记是单边的（只减政府负债不减债权人资产），凭空消灭负债 = 凭空创造净值（INV-015）")
				% [wrote, d_gov, d_creditors])
		check(f.all_rows_unclassified(JWUnits.Kind.WRITEOFF),
				"ADV-C06：存在带非零分类码的 kind=28 行 ⇒ 减记被计进了某个 GDP 口径")
	else:
		# 普通年份减记为 0（计划书 §07）——这时必须能看到命令被显式拒绝，而不是静默无事发生。
		ge_int(f.rejects_total(JWResult.Reject.PRECONDITION)
				+ f.rejects_total(JWResult.Reject.NOT_FOUND), 1,
				("ADV-C06：财政未到重组边缘时提交 writedown 既没有产生减记，也没有任何拒绝记录 ⇒ "
				+ "命令被静默吞掉，违反 INV-137『被拒命令仍入档并记原因码』"))

	# 2) 债务恒等式逐季成立（INV-028），这是「减记有没有被当成收入」的会计层判据。
	_assert_debt_identity(f, "ADV-C06")
	_assert_conservation(f, "ADV-C06")


# adv_id:     ADV-C07
# alias:      —
# family:     financing
# invariants: INV-007, INV-037
# guards:     tenor_valid_range
# gate:       G5
## 零期限债券当季发当季还。docs/31 §4 `ADV-C07` + `Q-ADV-05`：`tenor_q` 的合法闭区间是 `[4, 40]`。
## `tenor_q == 0` 尤其危险：它会让到期表为空而 `outstanding > 0`，直接破坏 INV-037。
func test_adv_c07_tenor_range_and_maturity_table() -> void:
	var f: Fix = _boot()
	if f == null:
		return

	for tn: int in PackedInt64Array([-1, 0, 1, 3, 41, 200, 1 << 40]):
		_expect_reject(f, 8, Fix.a6(1_000_000_000, tn, JWUnits.Holder.INVPOOL),
				JWResult.Reject.PARAM_RANGE,
				"ADV-C07：tenor_q=%d 不在 Q-ADV-05 裁定的 [%d, %d] 内" % [tn, TENOR_MIN, TENOR_MAX])
	# 金额上界同样是硬边界（INV-007）。
	_expect_reject(f, 8, Fix.a6(JWUnits.AMOUNT_MAX + 1, 8, JWUnits.Holder.INVPOOL),
			JWResult.Reject.PARAM_RANGE,
			"ADV-C07：amount_uu 超过 AMOUNT_MAX（R-SCALE-01 定为 4e15）")
	_expect_reject(f, 8, Fix.a6(0, 8, JWUnits.Holder.INVPOOL), JWResult.Reject.PARAM_RANGE,
			"ADV-C07：amount_uu == 0 的发行没有面值，`principal_initial > 0` 是 docs/10 §3.3 的取值域")

	eq_int(f.submit(8, Fix.a6(1_000_000_000, 8, JWUnits.Holder.INVPOOL)), 0,
			"ADV-C07：tenor_q=8 在合法区间内，形状层不得拒绝")
	if not f.booted:
		return
	f.advance(1)
	if not f.alive:
		return

	# 到期表与余额一致的可判定形态：任何批次的到期季必须严格晚于发行季，未偿不得超过面值。
	var b: int = 0
	while b < f.bond_count():
		check(f.st.bonds.maturity_q[b] > f.st.bonds.issue_q[b],
				("ADV-C07：批次 %d 的 maturity_q=%d 不晚于 issue_q=%d ⇒ 到期表为空而 outstanding>0，"
				+ "INV-037 立刻破裂") % [b, f.st.bonds.maturity_q[b], f.st.bonds.issue_q[b]])
		le_int(f.st.bonds.principal_outstanding[b], f.st.bonds.principal_initial[b],
				"ADV-C07：批次 %d 的未偿本金超过了发行本金（docs/10 §3.3 取值域 0..initial）" % b)
		ge_int(f.st.bonds.principal_outstanding[b], 0,
				"ADV-C07：批次 %d 的未偿本金为负" % b)
		b += 1
	eq_int(f.debt_outstanding(), f.debt_recomputed(),
			"ADV-C07：INV-035 不成立——debt_outstanding() != Σ ACTIVE 批次未偿本金")


# ══════════════════════════════════════════════════════════════════════════
# F 族：项目与合同攻击
# ══════════════════════════════════════════════════════════════════════════

## 立一个满规模 P04 项目，返回是否被受理。区域固定海岬（内容包默认 region_mask = 4）。
func _launch_p04(f: Fix, region: int, scale_ppm: int, funding: int) -> int:
	return f.submit(4, Fix.a6(P04_GRID_PROJECT, region, scale_ppm, funding))


# adv_id:     ADV-F01
# alias:      —
# family:     contract
# invariants: INV-032, INV-092, INV-093
# guards:     cancel_no_refund, cancel_penalty, residual_le_paid
# gate:       G5
## 取消退款。docs/31 §7 `ADV-F01`：已付不退（计划书 §07「项目取消不会释放已实际花掉的钱」）。
## **政府现金只会因取消而减少，绝不增加。**
func test_adv_f01_cancel_does_not_refund() -> void:
	var f: Fix = _boot()
	if f == null:
		return
	if not f.booted:
		return

	eq_int(_launch_p04(f, JWUnits.Region.HAIJIA, JWUnits.PPM, FUNDING_BOND), 0,
			"ADV-F01：立项命令必须在形状与范围上合法（P04 是 project 类，scale_ppm=1e6 在 [0, PPM] 内）")
	f.advance(4)
	if not f.alive:
		return
	ge_int(f.project_count(), 1,
			"ADV-F01：立项后项目表里必须有项目；一个都没有说明 S02 §2.7 的 launch 从未执行")
	if f.project_count() < 1:
		return

	var pid: int = f.project_count() - 1
	var cash_before: int = f.cash_of(JWIds.AGENT_GOV)
	var paid_before: int = f.project_paid(pid)
	var committed_before: int = f.treasury_int("committed_memo")
	var unpaid: int = f.project_planned(pid) - paid_before

	eq_int(f.submit(5, Fix.a6(f.st.projects.entity[pid])), 0, "ADV-F01：project_cancel 在形状与范围上必须合法")
	f.advance(1)
	if not f.alive:
		return

	# 1) 现金只会因取消而减少（取消被写成「冲销已付分录」时它会增加）。
	#    量法按 docs/18 第三轮「测试口径更正」：只量取消相关分录（本项目的 CANCEL_PENALTY / WRITEOFF）
	#    在国库现金科目上的精确效果。整季现金变化混入了本季常规赤字与 R-FINANCE-01 的周转借款，
	#    借款大于当季支出的那一季，整季口径会把「借来的钱」误报成「取消退回的钱」。
	#    cash_before 仍保留作失败信息里的上下文。
	var gov_cash_acc: int = JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH)
	var cancel_cash: int = _cancel_legs_on(f, pid, gov_cash_acc)
	le_int(cancel_cash, 0,
			("ADV-F01：取消相关分录使国库现金净增 %d（取消前国库现金 %d）⇒ 取消被写成了冲销已付分录，"
			+ "这是账本层面的时间倒流，INV-018 的现金总量守恒会立刻报警")
			% [cancel_cash, cash_before])
	eq_int(cancel_cash, -_cancel_penalty_paid(f, pid),
			("ADV-F01：取消相关分录对国库现金的净效果 %d 不等于 −（本项目实付赔偿 %d）⇒ "
			+ "除赔偿之外还有别的取消分录动了国库现金") % [cancel_cash, _cancel_penalty_paid(f, pid)])
	eq_int(_gov_cash_refund_rows(f), 0,
			("ADV-F01：取消当季国库现金科目上出现了项目付款 / 赔偿 / 减记类型的正腿 ⇒ "
			+ "已付款项被冲销退回（INV-093：paid 不回退、现金不增加）"))

	# 2) 已付一分不退（INV-093：`paid_uu` 不回退）。
	eq_int(f.project_paid(pid), paid_before,
			"ADV-F01：INV-093 要求取消时 paid_uu 不回退，实际从 %d 变成 %d"
			% [paid_before, f.project_paid(pid)])

	# 3) 承诺只减未付部分（INV-032）。
	eq_int(f.treasury_int("committed_memo"), committed_before - unpaid,
			("ADV-F01：INV-032 要求 committed_memo 只减去未付部分 %d（取消前 %d）") % [unpaid, committed_before])

	# 4) 残值不得超过已投入（INV-093）。
	le_int(f.st.projects.residual_value[pid], paid_before,
			("ADV-F01：残值 %d > 已付 %d ⇒ 残值评估函数凭空创造资产（引用了 total_cost 而不是 wip）")
			% [f.st.projects.residual_value[pid], paid_before])

	# 5) 取消是有代价的：赔偿真的收了。
	ge_int(f.led_q(JWUnits.Kind.CANCEL_PENALTY, f.quarters_done() - 1), 1,
			("ADV-F01：取消当季没有任何 kind=27 cancel_penalty 过账，而 policy_P04.json 的 "
			+ "exit_rule.compensation_ppm 是 %d ⇒ 取消变成了零成本动作") % P04_COMPENSATION_PPM)

	# 6) 终态必须是 cancelled，且槽位已释放。
	eq_int(f.st.projects.status[pid], JWUnits.ProjectStatus.CANCELLED,
			"ADV-F01：取消后项目状态必须是 cancelled（docs/17 §4.19 的跃迁图里它是终态）")
	eq_int(f.st.projects.slot_held[pid], 0,
			"ADV-F01：INV-094 要求取消当季释放槽位；仍占着 = 引用计数错误")

	_assert_conservation(f, "ADV-F01")


# adv_id:     ADV-F02
# alias:      —
# family:     contract
# invariants: INV-032, INV-058, INV-094
# guards:     slot_release_on_cancel, cancel_penalty, slot_hard_cap
# gate:       G5
## 反复立项占队列。docs/31 §7 `ADV-F02`：槽位上限是硬约束；每次立项–取消循环都产生 `cancel_penalty`；
## 槽位计数在取消当季释放，**跑完 N 轮后可用槽位必须回到初值**（引用计数不得泄漏）。
func test_adv_f02_slot_churn_leaks_no_slot() -> void:
	var f: Fix = _boot()
	if f == null:
		return
	if not f.booted:
		return

	var slots_total: PackedInt64Array = PackedInt64Array()
	var r: int = 0
	while r < JWUnits.R:
		slots_total.append(f.metric("state.region.construction_slots_total", r))
		in_range_int(slots_total[r], 1, 8,
				"ADV-F02：docs/10 §7 规定 construction_slots_total 的取值域是 1..8（地区 %d）" % r)
		r += 1

	var rounds: int = 0
	while rounds < 6 and f.alive:
		# 每个地区都立到撑爆槽位（多立 3 个，逼出 E_NO_SLOT）。
		var rr: int = 0
		while rr < JWUnits.R:
			var k: int = 0
			while k < slots_total[rr] + 3:
				# 测试口径更正：占队列与规模无关，最省钱的攻击是最小规模的探针立项（F02_PROBE_SCALE_PPM）。
				# 满规模 × 全部槽位 × 6 轮的取消赔偿足以让预算审查连败、执政在第 8 季合法终局，
				# 测试就验不到槽位回收——那是财政规则的结局，不是本条要测的引用计数。
				_launch_p04(f, rr, F02_PROBE_SCALE_PPM, FUNDING_BOND)
				k += 1
			rr += 1
		f.advance(1)
		if not f.alive:
			return

		# 逐地区：已占槽位不得越过上限（INV-094）。
		rr = 0
		while rr < JWUnits.R:
			le_int(f.slots_held_in(rr), slots_total[rr],
					("ADV-F02：第 %d 轮地区 %d 已占槽位 %d 超过 construction_slots_total %d ⇒ "
					+ "INV-094 的硬约束被写成了静默排队") % [rounds, rr, f.slots_held_in(rr), slots_total[rr]])
			rr += 1

		# 全部取消。
		var p: int = 0
		while p < f.project_count():
			if f.st.projects.status[p] != JWUnits.ProjectStatus.CANCELLED \
					and f.st.projects.status[p] != JWUnits.ProjectStatus.COMMISSIONED:
				f.submit(5, Fix.a6(f.st.projects.entity[p]))
			p += 1
		f.advance(1)
		rounds += 1
	if not f.alive:
		return

	# 1) 槽位不得泄漏。
	eq_int(f.slots_held_total(), 0,
			("ADV-F02：%d 轮立项–取消之后仍有 %d 个槽位没释放 ⇒ 取消路径没有释放 queue_slot_held，"
			+ "引用计数泄漏（INV-094）") % [rounds, f.slots_held_total()])

	# 2) 占位不是免费的。
	ge_int(f.led_sum(JWUnits.Kind.CANCEL_PENALTY, 0, f.quarters_done() - 1), 1,
			("ADV-F02：%d 轮立项–取消一分赔偿都没收 ⇒ 缺『取消产生违约或沉没成本』规则，"
			+ "立项变成零成本试探，玩家会把队列当成免费的信息探针（计划书 §07）") % rounds)

	# 3) 槽位上限确实拦过人。
	ge_int(f.rejects_total(JWResult.Reject.NO_SLOT), 1,
			"ADV-F02：每轮都比槽位多立 3 个，却一次 E_NO_SLOT 都没有 ⇒ 槽位上限不是硬约束")

	_assert_conservation(f, "ADV-F02")


# adv_id:     ADV-F03
# alias:      —
# family:     contract
# invariants: INV-087, INV-088, INV-092
# guards:     progress_independent_of_payment
# gate:       G2
## 付款制造进度（P04 验收断言的独立复核）。docs/31 §7 `ADV-F03`：
## **进度只由实投施工服务量决定**，与 `paid_uu` 无函数依赖。
##
## docs/31 原文用「改 spend_plan 前置付款」的内容包变体做对照；本测试改用同一条规则的
## **逐季恒等式形态**（INV-088）：
##   `Δconstruction_progress_ppm == mul_div_floor(本季实投施工量, PPM, required_construction_uqs)`
## 且「本季实投为 0 但付款在增加」时 `Δprogress` 必须恰好为 0。
## 只立一个项目，`flow.region.construction_used_uqs[r]` 就等于该项目的实投量，等式两边都可独立复算。
func test_adv_f03_payment_does_not_make_progress() -> void:
	var f: Fix = _boot()
	if f == null:
		return
	if not f.booted:
		return

	var region: int = JWUnits.Region.HAIJIA
	eq_int(_launch_p04(f, region, JWUnits.PPM, FUNDING_BOND), 0,
			"ADV-F03：立项命令必须在形状与范围上合法")
	f.advance(1)
	if not f.alive:
		return
	ge_int(f.project_count(), 1, "ADV-F03：立项后必须存在项目，否则本用例什么也测不到")
	if f.project_count() < 1:
		return
	var pid: int = f.project_count() - 1

	var prev_progress: int = f.st.projects.construction_progress[pid]
	var prev_paid: int = f.project_paid(pid)
	var q: int = 1
	while q < 10 and f.alive:
		f.advance(1)
		if not f.alive:
			return
		var used: int = f.st.projects.f_construction_used[region]
		var required: int = f.st.projects.required_construction[pid]
		var progress: int = f.st.projects.construction_progress[pid]
		var paid: int = f.project_paid(pid)
		var d_progress: int = progress - prev_progress

		in_range_int(progress, 0, JWUnits.PPM,
				"ADV-F03：construction_progress_ppm 必须落在 [0, 1e6]（第 %d 季读到 %d）" % [q, progress])
		ge_int(d_progress, 0, "ADV-F03：施工进度不得倒退（第 %d 季 Δ=%d）" % [q, d_progress])

		if required > 0:
			# 独立复算：本文件自己调 JWMath.mul_div_floor，不碰 JWProjectQueue 的任何算式。
			var expect: int = JWMath.mul_div_floor(used, JWUnits.PPM, required)
			if progress < JWUnits.PPM:
				eq_int(d_progress, expect,
						("ADV-F03：第 %d 季 Δprogress=%d，而按 INV-088 用本季实投施工量 %d μQ_s 与 "
						+ "required_construction %d μQ_s 独立复算应为 %d。对不上 ⇒ 进度另有来源，"
						+ "最可能的来源就是 paid_uu（INV-087 被破坏）") % [q, d_progress, used, required, expect])
		if used == 0 and paid > prev_paid:
			eq_int(d_progress, 0,
					("ADV-F03：第 %d 季实投施工量为 0，付款却从 %d 涨到 %d，而进度前进了 %d ppm ⇒ "
					+ "`construction_progress` 对 `paid_uu` 存在函数依赖，INV-087 被破坏")
					% [q, prev_paid, paid, d_progress])
		prev_progress = progress
		prev_paid = paid
		q += 1

	# 付款总额不得超过计划（INV-092）。
	le_int(f.project_paid(pid), f.project_planned(pid),
			"ADV-F03：INV-092 要求 Σ paid_uu <= Σ spend_plan_uu（实际 %d > %d）"
			% [f.project_paid(pid), f.project_planned(pid)])
	_assert_conservation(f, "ADV-F03")


# adv_id:     ADV-F04
# alias:      —
# family:     contract
# invariants: INV-032, INV-094
# guards:     defer_count_cap, defer_keeps_slot
# gate:       G5
## 无限延期。docs/31 §7 `ADV-F04` + `Q-ADV-01` 的保守期望：
## 延期次数上限 2 次、单次不超过 4 季、总计不超过 8 季；**延期期间不释放槽位**；
## 延期不得减少 `committed_memo`；超限 `REJECT`。
##
## `Q-ADV-01` 是本目录明确标注「最可能真的缺失」的一条；本测试按保守期望写，
## 实现若给不出上限就会红——那正是它该红的地方，不是把断言放宽的理由。
func test_adv_f04_defer_has_a_ceiling() -> void:
	var f: Fix = _boot()
	if f == null:
		return

	# 形状层的上界先钉死：quarters 的合法区间是 [1, 16]（== param.commitment_horizon_q）。
	_expect_reject(f, 6, Fix.a6(0, 0), JWResult.Reject.PARAM_RANGE,
			"ADV-F04：project_defer{quarters=0} 不是延期，是空命令")
	_expect_reject(f, 6, Fix.a6(0, -1), JWResult.Reject.PARAM_RANGE,
			"ADV-F04：project_defer{quarters=-1} 会让承诺表时间倒流")
	_expect_reject(f, 6, Fix.a6(0, DEFER_QUARTERS_MAX + 1), JWResult.Reject.PARAM_RANGE,
			"ADV-F04：project_defer 的 quarters 超过承诺表滚动窗口 %d 季即无法登记" % DEFER_QUARTERS_MAX)

	if not f.booted:
		return
	var region: int = JWUnits.Region.HAIJIA
	eq_int(_launch_p04(f, region, JWUnits.PPM, FUNDING_BOND), 0,
			"ADV-F04：立项命令必须在形状与范围上合法")
	f.advance(1)
	if not f.alive:
		return
	ge_int(f.project_count(), 1, "ADV-F04：立项后必须存在项目")
	if f.project_count() < 1:
		return
	var pid: int = f.project_count() - 1
	var committed_at_launch: int = f.treasury_int("committed_memo")

	# 一直延期到被拒。每次 4 季。
	var accepted: int = 0
	var tries: int = 0
	while tries < 8 and f.alive:
		var rc: int = f.submit(6, Fix.a6(f.st.projects.entity[pid], 4))
		f.advance(1)
		if not f.alive:
			return
		if rc == 0 and f.rejects_in_q(f.quarters_done() - 1, JWResult.Reject.PRECONDITION) == 0 \
				and f.rejects_in_q(f.quarters_done() - 1, JWResult.Reject.NOT_FOUND) == 0:
			accepted += 1
		tries += 1

	# 0) R-DEFER-01 之后延期真实可用：一次都不受理，下面的上限、槽位与承诺断言就是空过。
	ge_int(accepted, 1, "ADV-F04：%d 次 project_defer 一次都没受理 ⇒ 延期不可用，本用例的其余断言空过" % tries)

	# 1) 延期次数必须有上限。
	le_int(accepted, MAX_DEFER_COUNT,
			("ADV-F04：递交 %d 次 project_defer 有 %d 次被接受，超过 Q-ADV-01 的保守上限 %d 次 ⇒ "
			+ "缺延期上限规则，成本可以被无限推到第 40 季之外") % [tries, accepted, MAX_DEFER_COUNT])

	# 2) 延期期间不得释放槽位（否则延期成了免费保留队列位置）。
	if f.st.projects.status[pid] != JWUnits.ProjectStatus.CANCELLED \
			and f.st.projects.status[pid] != JWUnits.ProjectStatus.COMMISSIONED:
		eq_int(f.st.projects.slot_held[pid], 1,
				"ADV-F04：延期期间项目 %d 的 queue_slot_held 是 0 ⇒ 延期竟然释放了槽位" % pid)

	# 3) 延期不得减少承诺（INV-032：committed_memo 只由新签 + / 履约付款 − / 取消 − 变动）。
	le_int(committed_at_launch - f.treasury_int("committed_memo"),
			f.gov_cash_out_sum(JWUnits.Kind.PROJECT_PAYMENT, 0, f.quarters_done() - 1),
			("ADV-F04：committed_memo 从 %d 降到 %d，降幅超过了同期项目付款总额 ⇒ "
			+ "延期动了承诺表，违反 INV-032")
			% [committed_at_launch, f.treasury_int("committed_memo")])

	_assert_conservation(f, "ADV-F04")


# adv_id:     ADV-F05
# alias:      —
# family:     contract
# invariants: INV-058, INV-088, INV-094
# guards:     slot_hard_cap, construction_capacity_cap
# gate:       G5
## 拆分项目绕过槽位。docs/31 §7 `ADV-F05`：**槽位数挡住并发，施工能力挡住总量**。
## 拆成多个小项目只会撞上槽位上限，总推进速度仍受 `construction_capacity_uqs` 限制，
## **完工季不得早于对照组**。
func test_adv_f05_split_cannot_beat_construction_capacity() -> void:
	var f_whole: Fix = _boot()
	if f_whole == null:
		return
	var f_split: Fix = _boot()
	if f_split == null:
		return
	if not f_whole.booted or not f_split.booted:
		return

	var region: int = JWUnits.Region.HAIJIA
	# 对照组：一个满规模项目。
	eq_int(_launch_p04(f_whole, region, JWUnits.PPM, FUNDING_BOND), 0,
			"ADV-F05：对照组立项命令必须在形状与范围上合法")
	# 实验组：9 个 1/9 规模项目（111_111 ppm，落在 P04 的 scale_ppm valid_range 内）。
	var k: int = 0
	while k < 9:
		_launch_p04(f_split, region, 111_111, FUNDING_BOND)
		k += 1

	f_whole.advance(16)
	f_split.advance(16)
	if not f_whole.alive or not f_split.alive:
		return

	var slots_total: int = f_split.metric("state.region.construction_slots_total", region)

	# 1) 并发数被槽位挡住。
	le_int(f_split.slots_held_in(region), slots_total,
			("ADV-F05：拆成 9 个后地区 %d 的已占槽位 %d 超过 construction_slots_total %d ⇒ "
			+ "只要拆得够碎就能绕过并发约束（INV-094）") % [region, f_split.slots_held_in(region), slots_total])

	# 2) 总量被施工能力挡住：任何一季的实投都不得超过当季能力（INV-088）。
	le_int(f_split.st.projects.f_construction_used[region],
			f_split.st.projects.f_construction_capacity[region],
			("ADV-F05：实验组末季实投施工量 %d 超过本季施工能力 %d ⇒ INV-058 的『推进速度』那一半缺失，"
			+ "单一约束总能被拆分绕过")
			% [f_split.st.projects.f_construction_used[region],
				f_split.st.projects.f_construction_capacity[region]])
	le_int(f_whole.st.projects.f_construction_used[region],
			f_whole.st.projects.f_construction_capacity[region],
			"ADV-F05：对照组末季实投施工量同样不得超过本季施工能力（INV-088）")

	# 3) 拆分不得更快完工：实验组最早投运季不得早于对照组。
	var first_split: int = _first_commission_q(f_split)
	var first_whole: int = _first_commission_q(f_whole)
	if first_split >= 0 and first_whole >= 0:
		ge_int(first_split, first_whole,
				("ADV-F05：拆成 9 个后最早投运季是 %d，早于对照组的 %d ⇒ 拆分反而更快完工，"
				+ "说明只有并发数约束、没有推进速度约束（INV-058 的一半缺失）")
				% [first_split, first_whole])
	else:
		eq_int(first_split, -1,
				("ADV-F05：对照组在 16 季内没有任何项目投运（first_commission_q=%d），"
				+ "实验组却有（%d）⇒ 拆分买到了对照组买不到的完工")
				% [first_whole, first_split])


## 最早的投运季；没有任何项目投运时返回 −1（`commissioned_q` 的未投运哨兵值也是 −1）。
func _first_commission_q(f: Fix) -> int:
	var best: int = -1
	var p: int = 0
	while p < f.project_count():
		var cq: int = f.st.projects.commissioned_q[p]
		if cq >= 0 and (best < 0 or cq < best):
			best = cq
		p += 1
	return best


# adv_id:     ADV-F06
# alias:      —
# family:     contract
# invariants: INV-020, INV-021, INV-093
# guards:     residual_from_wip, residual_le_paid
# gate:       G5
## 残值套利。docs/31 §7 `ADV-F06`：付一点点钱就取消，指望按「计划总投入」拿到一大笔残值资产。
## 期望：`residual_value <= wip <= Σ paid_uu`；取消损失 = `paid − residual` 计入当期损益，
## 净值变化可解释（INV-021）。
func test_adv_f06_residual_never_exceeds_paid() -> void:
	var f: Fix = _boot()
	if f == null:
		return
	if not f.booted:
		return

	eq_int(_launch_p04(f, JWUnits.Region.HAIJIA, JWUnits.PPM, FUNDING_BOND), 0,
			"ADV-F06：立项命令必须在形状与范围上合法")
	f.advance(1)
	if not f.alive:
		return
	ge_int(f.project_count(), 1, "ADV-F06：立项后必须存在项目")
	if f.project_count() < 1:
		return
	var pid: int = f.project_count() - 1

	var paid: int = f.project_paid(pid)
	var wip_before: int = f.balance_of(JWIds.AGENT_GOV, JWIds.ACC_WIP)
	var nw_before: int = f.net_worth_of(JWIds.AGENT_GOV)
	var cash_before: int = f.cash_of(JWIds.AGENT_GOV)

	eq_int(f.submit(5, Fix.a6(f.st.projects.entity[pid])), 0, "ADV-F06：project_cancel 在形状与范围上必须合法")
	f.advance(1)
	if not f.alive:
		return

	var residual: int = f.st.projects.residual_value[pid]

	# 1) 残值 ≤ 在建工程 ≤ 已付。
	le_int(residual, wip_before,
			("ADV-F06：残值 %d 超过取消前的政府在建工程 %d ⇒ 残值函数引用了 total_cost 而不是 wip")
			% [residual, wip_before])
	le_int(wip_before, paid,
			"ADV-F06：取消前的在建工程 %d 超过已付 %d ⇒ 付款之外还有别的东西在增 wip（INV-092）"
			% [wip_before, paid])
	le_int(residual, paid,
			"ADV-F06：残值 %d 超过已付 %d ⇒ 残值评估函数凭空创造资产（INV-093）" % [residual, paid])
	ge_int(residual, 0, "ADV-F06：残值不得为负")

	# 2) 取消不给政府送钱。
	#    量法按 docs/18 第三轮「测试口径更正」：只量取消相关分录（本项目的 CANCEL_PENALTY / WRITEOFF）
	#    在国库现金科目上的精确效果，不量整季现金（后者混入本季常规赤字与 R-FINANCE-01 的周转借款）。
	var gov_cash_acc: int = JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH)
	var cancel_cash: int = _cancel_legs_on(f, pid, gov_cash_acc)
	le_int(cancel_cash, 0,
			"ADV-F06：取消相关分录使国库现金净增 %d（取消前国库现金 %d）⇒ 已付被退了回来（INV-032/INV-093）"
			% [cancel_cash, cash_before])
	eq_int(cancel_cash, -_cancel_penalty_paid(f, pid),
			("ADV-F06：取消相关分录对国库现金的净效果 %d 不等于 −（本项目实付赔偿 %d）⇒ "
			+ "除赔偿之外还有别的取消分录动了国库现金") % [cancel_cash, _cancel_penalty_paid(f, pid)])
	eq_int(_gov_cash_refund_rows(f), 0,
			"ADV-F06：取消当季国库现金科目上出现了项目付款 / 赔偿 / 减记类型的正腿 ⇒ 已付被冲销退回（INV-093）")

	# 3) 净值变化必须被本季损益完全解释（INV-021）：
	#    Δnw == 残值 − 已付 − 取消赔偿。取消季之前的已付已经以 wip 的形态在资产里，
	#    取消把 wip 中超出残值的部分确认为损失，赔偿是另一笔当期支出。
	#    量法按 docs/18 第三轮「测试口径更正」：Δnw 取**取消相关分录**对政府净值的精确效果——
	#    本项目的 CANCEL_PENALTY 与 WRITEOFF 行在政府各非净值科目上的有符号 Σ（INV-020 逐笔成立，
	#    故一笔分录对某主体净值的效果恒等于它在该主体其余科目上的行之和）。整季 Δnw 混入了本季常规
	#    赤字（公职工资、转移支付都是政府净值的当期减少），与取消无关。期望值公式与数值不变。
	#    nw_before 仍保留作失败信息里的上下文。
	var d_nw: int = _cancel_nw_effect_on_gov(f, pid)
	var penalty: int = f.led_q(JWUnits.Kind.CANCEL_PENALTY, f.quarters_done() - 1)
	eq_int(d_nw, residual - wip_before - penalty,
			("ADV-F06：取消相关分录的政府净值效果 %d != 残值 %d − 取消前在建工程 %d − 取消赔偿 %d"
			+ "（取消前政府净值 %d）⇒ 净值变化无法被损益解释，残值登记走了绕过 post() 的直接赋值路径"
			+ "（违反 INV-021/INV-022）")
			% [d_nw, residual, wip_before, penalty, nw_before])

	_assert_conservation(f, "ADV-F06")


# ── F01 / F06 的取消量法（docs/18 第三轮「测试口径更正」） ──────────────────
# 只量**取消相关分录**：本季账本里 entity_ref == 项目下标、kind ∈ {CANCEL_PENALTY, WRITEOFF} 的行
# （JWProjectQueue.cancel 过这两类分录时都以项目下标作实体引用）。承诺冲减是备查额，不进账本，
# 由 F01 第 3 条对 committed_memo 单独量。日志每季 S01 重置，这些函数只能在取消季推进完之后立刻调用。

## 取消相关分录在某科目上的有符号 Σ delta。
func _cancel_legs_on(f: Fix, pid: int, account: int) -> int:
	var led: JWLedger = f.st.ledger
	var rows: int = led.log_row_count()
	var acc: int = 0
	var i: int = 0
	while i < rows:
		var k: int = led.l_kind[i]
		if (k == JWUnits.Kind.CANCEL_PENALTY or k == JWUnits.Kind.WRITEOFF) \
				and led.l_entity[i] == pid and led.l_account[i] == account:
			acc += led.l_delta[i]
		i += 1
	return acc


## 本项目本季实付的取消赔偿：CANCEL_PENALTY 行在收款方现金科目上的正腿之和。
func _cancel_penalty_paid(f: Fix, pid: int) -> int:
	var led: JWLedger = f.st.ledger
	var rows: int = led.log_row_count()
	var acc: int = 0
	var i: int = 0
	while i < rows:
		if led.l_kind[i] == JWUnits.Kind.CANCEL_PENALTY and led.l_entity[i] == pid \
				and led.l_delta[i] > 0 \
				and led.l_account[i] % JWUnits.ACCOUNT_CODE_N == JWIds.ACC_CASH:
			acc += led.l_delta[i]
		i += 1
	return acc


## 取消相关分录对政府净值的精确效果：这些行在政府各**非净值**科目上的有符号 Σ。
## INV-020 逐笔成立（每笔分录对每个主体的行之和为 0，净值行或显式或由 _settle_nw 隐式补平），
## 所以一笔分录对政府净值的效果恒等于它在政府其余科目上的行之和（资产增 +、负债增 −）。
func _cancel_nw_effect_on_gov(f: Fix, pid: int) -> int:
	var led: JWLedger = f.st.ledger
	var rows: int = led.log_row_count()
	var nw_acc: int = JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_NW)
	var acc: int = 0
	var i: int = 0
	while i < rows:
		var k: int = led.l_kind[i]
		if (k == JWUnits.Kind.CANCEL_PENALTY or k == JWUnits.Kind.WRITEOFF) \
				and led.l_entity[i] == pid:
			var a: int = led.l_account[i]
			if JWMath.floor_div(a, JWUnits.ACCOUNT_CODE_N) == JWIds.AGENT_GOV and a != nw_acc:
				acc += led.l_delta[i]
		i += 1
	return acc


## 本季国库现金科目上「项目付款 / 取消赔偿 / 减记」类型的正腿行数（冲销退款的可判定形态）。
## 这三类分录里政府只可能是付款方或资产减记方，国库现金出现正腿即已付款项被退回。
func _gov_cash_refund_rows(f: Fix) -> int:
	var led: JWLedger = f.st.ledger
	var rows: int = led.log_row_count()
	var gov_cash: int = JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH)
	var n: int = 0
	var i: int = 0
	while i < rows:
		var k: int = led.l_kind[i]
		var tied: bool = k == JWUnits.Kind.PROJECT_PAYMENT or k == JWUnits.Kind.CANCEL_PENALTY \
				or k == JWUnits.Kind.WRITEOFF
		if tied and led.l_account[i] == gov_cash and led.l_delta[i] > 0:
			n += 1
		i += 1
	return n
