## 部门现金流量表（docs/53 M2-8 标定）：按「主体类 × 交易类型」把现金科目的流入 / 流出
## 在一个窗口内累加，每个窗口打印一张表。用来回答「谁的钱漏到哪去了」。
##
## 用法：godot --headless --path <根> --script res://tools/diag_flows.gd -- [剧本=campaign_1600] [季数=120] [窗口=20] [主体类=firm] [种子=1] [nofinal]
## 主体类：firm（16 个生产单元）| agri / manu / energy / services（该部门 4 个单元）| cell:N（单个生产单元）| hh | gov | row | invpool
## 只读诊断，不改规则。
extends SceneTree

const U: float = 1_000_000_000.0
const STRIDE: int = JWUnits.ACCOUNT_CODE_N


func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var scen: String = a[0] if a.size() > 0 else "campaign_1600"
	var n_q: int = int(a[1]) if a.size() > 1 else 120
	var win: int = int(a[2]) if a.size() > 2 else 20
	var who: String = a[3] if a.size() > 3 else "firm"
	var seed_v: int = int(a[4]) if a.size() > 4 else 1
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: JWContentLoader = JWContentLoader.new()
	var spec: String = "res://content" if scen == "chengwan" else "res://content#" + scen
	var res: JWResult = loader.load_all(spec, st)
	if res == null or not res.ok:
		print("载入失败")
		quit(1)
		return
	st.content_hash = loader.content_hash
	st.rng.set_state_scalar(0, seed_v)
	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	var events: JWEventEngine = JWEventEngine.new()
	events.allocate()
	loader.load_events_into(events, st)
	JWResult.clear_pending()
	var runner: JWTurnRunner = JWTurnRunner.new(st, events)
	if a.has("nofinal"):
		st.crisis.final_window_q = 1 << 40
	var a0: PackedInt64Array = PackedInt64Array()
	a0.resize(JWCommands.ARG_SLOTS)
	var names: Dictionary = {}
	for k: String in JWUnits.Kind.keys():
		names[int(JWUnits.Kind[k])] = k
	var inflow: Dictionary = {}
	var outflow: Dictionary = {}
	var cash0: int = _cash(st, who)
	for q: int in n_q:
		cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, a0, q, st.policy_defs)
		var code: int = runner.advance_quarter(cmds)
		if code != 0:
			print("第 %d 季推进失败：码 %d" % [q, code])
			break
		for i: int in st.ledger.log_row_count():
			var acc: int = st.ledger.l_account[i]
			var ag: int = int(acc / STRIDE)
			if acc - ag * STRIDE != JWIds.ACC_CASH or not _member(ag, who):
				continue
			var kd: int = st.ledger.l_kind[i]
			var d: int = st.ledger.l_delta[i]
			if d > 0:
				inflow[kd] = int(inflow.get(kd, 0)) + d
			else:
				outflow[kd] = int(outflow.get(kd, 0)) - d
		if q % win == win - 1:
			var cash1: int = _cash(st, who)
			print("── 第 %d—%d 季  %s 现金 %.1f → %.1f（每季平均，U）  实际GDP %.1f 失业 %.0f%% ──" % [
					q - win + 2, q + 1, who, cash0 / U, cash1 / U, st.diag.gdp_real / U,
					st.diag.unemployment_ppm / 1e4])
			var keys: Array = inflow.keys() + outflow.keys()
			keys.sort()
			var seen: Dictionary = {}
			var tin: int = 0
			var tout: int = 0
			for kd2: int in keys:
				if seen.has(kd2):
					continue
				seen[kd2] = true
				var x: int = int(inflow.get(kd2, 0))
				var y: int = int(outflow.get(kd2, 0))
				tin += x
				tout += y
				if absi(x - y) * 100 < win * 1_000_000_000 and x + y < win * 1_000_000_000:
					continue
				print("   %-24s 入 %7.3f  出 %7.3f  净 %+7.3f" % [names.get(kd2, str(kd2)),
						x / U / win, y / U / win, (x - y) / U / win])
			print("   %-24s 入 %7.3f  出 %7.3f  净 %+7.3f" % ["合计", tin / U / win, tout / U / win,
					(tin - tout) / U / win])
			inflow.clear()
			outflow.clear()
			cash0 = cash1
	quit(0)


func _member(agent: int, who: String) -> bool:
	if who.begins_with("cell:"):
		return JWIds.cell_of_agent(agent) == int(who.substr(5))
	match who:
		"firm":
			var c: int = JWIds.cell_of_agent(agent)
			return c >= 0 and c < JWUnits.CELL
		"agri", "manu", "energy", "services":
			var c2: int = JWIds.cell_of_agent(agent)
			if c2 < 0 or c2 >= JWUnits.CELL:
				return false
			return JWIds.sector_of_cell(c2) == ["agri", "manu", "energy", "services"].find(who)
		"hh":
			return agent >= JWIds.AGENT_GROUP_BASE and agent < JWIds.AGENT_INVPOOL
		"gov":
			return agent == JWIds.AGENT_GOV
		"row":
			return agent == JWIds.AGENT_ROW
		"invpool":
			return agent == JWIds.AGENT_INVPOOL
	return false


func _cash(st: JWSimState, who: String) -> int:
	var t: int = 0
	for ag: int in JWUnits.AGENT_N:
		if _member(ag, who):
			t += st.accounts.cash_of(ag)
	return t
