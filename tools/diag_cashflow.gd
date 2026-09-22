## 现金流拆解诊断：无命令推进 N 季，逐季按「主体类 × 交易类型」汇总现金科目的流入 / 流出。
##
## 用法：godot --headless --path <根> --script res://tools/diag_cashflow.gd -- [季数=4] [主体类=firm]
## 主体类：cell:N（单个 cell）| firm（16 个 cell）| agri / manu / energy / services（该部门 4 个 cell）| hh（36 个群组）| gov | row | invpool
## 用途：找存量—流量不一致（某类主体现金单向累积）的来源。只读，不改任何状态。
extends SceneTree

const U: float = 1_000_000_000.0
const ACC_STRIDE: int = JWUnits.ACCOUNT_CODE_N


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var n_q: int = int(args[0]) if args.size() > 0 else 4
	var who: String = args[1] if args.size() > 1 else "firm"
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: JWContentLoader = JWContentLoader.new()
	var res: JWResult = loader.load_all("res://content", st)
	if res == null or not res.ok:
		print("载入失败")
		quit(1)
		return
	st.content_hash = loader.content_hash
	st.param_set_version = loader.param_set_version
	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	var events: JWEventEngine = JWEventEngine.new()
	events.allocate()
	JWResult.clear_pending()
	var runner: JWTurnRunner = JWTurnRunner.new(st, events)
	var a0: PackedInt64Array = PackedInt64Array()
	a0.resize(JWCommands.ARG_SLOTS)
	var kind_names: Dictionary = {}
	for k: String in JWUnits.Kind.keys():
		kind_names[int(JWUnits.Kind[k])] = k
	for q: int in n_q:
		var before: int = _cash_of(st, who)
		cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, a0, q, st.policy_defs)
		var code: int = runner.advance_quarter(cmds)
		if code != JWResult.OK:
			print("第 %d 季推进返回 %d，停止" % [q, code])
			break
		var inflow: Dictionary = {}
		var outflow: Dictionary = {}
		var n: int = st.ledger.log_row_count()
		for i: int in n:
			var acc: int = st.ledger.l_account[i]
			var agent: int = int(acc / ACC_STRIDE)
			if acc - agent * ACC_STRIDE != JWIds.ACC_CASH or not _is_member(agent, who):
				continue
			var kd: int = st.ledger.l_kind[i]
			var d: int = st.ledger.l_delta[i]
			if d > 0:
				inflow[kd] = int(inflow.get(kd, 0)) + d
			else:
				outflow[kd] = int(outflow.get(kd, 0)) - d
		var after: int = _cash_of(st, who)
		print("── q%d  %s 现金 %.2f → %.2f（Δ %+.2f） ──" % [q, who, before / U, after / U, (after - before) / U])
		var tin: int = 0
		var tout: int = 0
		var keys: Array = inflow.keys() + outflow.keys()
		keys.sort()
		var seen: Dictionary = {}
		for kd2: int in keys:
			if seen.has(kd2):
				continue
			seen[kd2] = true
			var a: int = int(inflow.get(kd2, 0))
			var b: int = int(outflow.get(kd2, 0))
			tin += a
			tout += b
			print("   %-24s 入 %8.2f   出 %8.2f   净 %+8.2f" % [kind_names.get(kd2, str(kd2)), a / U, b / U, (a - b) / U])
		print("   %-24s 入 %8.2f   出 %8.2f   净 %+8.2f" % ["合计", tin / U, tout / U, (tin - tout) / U])
	quit(0)


func _is_member(agent: int, who: String) -> bool:
	if who == "firm":
		var c: int = JWIds.cell_of_agent(agent)
		return c >= 0 and c < JWUnits.CELL
	if who.begins_with("cell:"):
		return JWIds.cell_of_agent(agent) == int(who.substr(5))
	var sec: int = ["agri", "manu", "energy", "services"].find(who)
	if sec >= 0:
		var c2: int = JWIds.cell_of_agent(agent)
		return c2 >= 0 and c2 < JWUnits.CELL and JWIds.sector_of_cell(c2) == sec
	if who == "hh":
		for g: int in JWUnits.GROUP:
			if JWIds.agent_of_group(g) == agent:
				return true
		return false
	if who == "gov":
		return agent == JWIds.AGENT_GOV
	if who == "row":
		return agent == JWIds.AGENT_ROW
	if who == "invpool":
		return agent == JWIds.AGENT_INVPOOL
	return false


func _cash_of(st: JWSimState, who: String) -> int:
	var t: int = 0
	for agent: int in 256:
		if _is_member(agent, who):
			t += st.accounts.cash_of(agent)
	return t
