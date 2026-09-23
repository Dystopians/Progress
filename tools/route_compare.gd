## 两条产业路线的对照局（docs/53 M2-8）：同一个 1600 剧本、同样的种子，只有玩法不同。
##
## 路线甲「重农商贸」：土地清丈 → 水利营造 → 轮作 → 复式记账 → 港务营造；
##                     建地区水利、基本灌溉（农业），市集商行，港务扩建（服务）。
## 路线乙「早期工场」：复式记账 → 行会工场 → 木炭冶炼 → 土地清丈 → 水利营造 → 水力机械；
##                     建手工工场与木炭冶炼（制造），市集商行，基本灌溉保口粮。
##
## 两条都只用**真实命令**（13 设定研究方向、14 新建建筑），不直接改状态，不放宽任何规则。
## 建造判据写死成一条简单规则：国库现金 > 造价 × 2 才下令（R-OWNER-01：两种所有者都由国库出资），
## 被 S02 拒绝就下季再试，不跳过。这不是最优打法，是「一个普通玩家会做的事」。
##
## 用法：godot --headless --path <根> --script res://tools/route_compare.gd -- [季数=200] [种子=1,2,3,4] [步=0] [nofinal]
##   步 == 0：只打印跨种子汇总表；步 > 0：逐步打印明细。
##   nofinal：关掉最后补救窗口（只用于研究经济路径；验收时必须开着）。
extends SceneTree

const U: float = 1_000_000_000.0

## 路线表：[科技顺序], [[建筑类型, 地区, 所有者], ...]
## 建筑类型下标按 content/buildings 文件名升序 + 1：
## 1 基本灌溉、2 地区水利、3 手工工场、4 木炭冶炼、5 市集商行、6 港务扩建、7 水力动力坊。
## 所有者：0 企业（政府出资、完工移交）、1 政府。
const ROUTE_A_TECH: PackedInt64Array = [0, 1, 2, 3, 7]
const ROUTE_A_BUILD: Array = [[2, 0, 1], [7, 3, 0], [1, 1, 0], [5, 1, 0], [2, 2, 0], [6, 2, 0], [1, 3, 0]]
const ROUTE_B_TECH: PackedInt64Array = [3, 4, 6, 0, 1, 5]
const ROUTE_B_BUILD: Array = [[3, 1, 0], [5, 1, 0], [3, 0, 0], [4, 2, 0], [7, 3, 0], [1, 3, 0], [3, 2, 0]]

var _nofinal: bool = false


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var n_q: int = int(args[0]) if args.size() > 0 else 200
	var seeds: PackedInt64Array = PackedInt64Array()
	for tok: String in (args[1] if args.size() > 1 else "1,2,3,4").split(",", false):
		seeds.append(int(tok))
	var step: int = int(args[2]) if args.size() > 2 else 0
	_nofinal = args.has("nofinal")
	var rows: Array = []
	for s: int in seeds:
		rows.append(_run("甲 重农商贸", ROUTE_A_TECH, ROUTE_A_BUILD, n_q, s, step))
		rows.append(_run("乙 早期工场", ROUTE_B_TECH, ROUTE_B_BUILD, n_q, s, step))
	print("\n══ 汇总（%d 季，补救窗口%s）══" % [n_q, "关闭" if _nofinal else "开启"])
	print("路线         种子  尾季实际GDP  失业%   建成  科技  终局")
	for r: Dictionary in rows:
		print("%-10s %4d %11.2f %7.1f %5d %5d  %s" % [r["name"], r["seed"], r["gdp"], r["unemp"],
				r["built"], r["techs"], r["end"]])


func _run(name: String, techs: PackedInt64Array, builds: Array, n_q: int, seed_v: int,
		step: int) -> Dictionary:
	var out: Dictionary = {"name": name, "seed": seed_v, "gdp": 0.0, "unemp": 0.0, "built": 0,
			"techs": 0, "end": "—"}
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_route_%d" % seed_v
	var r: JWResult = g.new_game("res://content#campaign_1600", seed_v, 0)
	if r == null or not r.ok:
		out["end"] = "开局失败"
		return out
	var st: JWSimState = g.get("_st") as JWSimState
	# 诊断工具不需要逐季自动存档与状态哈希（它们占了九成耗时）；规则与结算不受影响。
	g.set("_saves", null)
	if _nofinal:
		st.crisis.final_window_q = 1 << 40
	if step > 0:
		print("\n══ 路线%s（种子 %d）══" % [name, seed_v])
		print("年份   实际GDP  失业%   资本存量  价格水平  科技  建成  国库   瓶颈")
	var next_tech: int = 0
	var next_build: int = 0
	for q: int in n_q:
		# ① 研究：当前方向完成了就换下一项。
		while next_tech < techs.size() and (st.research.completed_mask >> techs[next_tech]) & 1 == 1:
			next_tech += 1
		if next_tech < techs.size():
			var t: int = techs[next_tech]
			if st.research.focus != t and st.research.is_available(t):
				g.submit_command(JWCommands.Kind.SET_RESEARCH_FOCUS, _args([t]))
		# ② 建造：清单里的下一项解锁了、国库付得起两倍造价，就下令；S02 接受了才推进清单。
		var ordered: int = -1
		if next_build < builds.size():
			var spec: Array = builds[next_build]
			var bt: int = int(spec[0])
			if (st.research.unlocked_building_mask() >> bt) & 1 == 1 \
					and st.accounts.cash_of(JWIds.AGENT_GOV) > st.buildings.t_cost[bt] * 2:
				var rb: JWResult = g.submit_command(JWCommands.Kind.BUILD_BUILDING,
						_args([bt, int(spec[1]), int(spec[2]), 0]))
				if rb != null and rb.ok:
					ordered = bt
		g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, _args([]))
		var cmds: JWCommands = g.get("_cmds") as JWCommands
		var n_before: int = cmds.count if cmds != null else 0
		var ra: JWResult = g.advance_quarter()
		if ordered > 0 and cmds != null and _accepted_build(cmds, n_before):
			next_build += 1
			out["built"] = int(out["built"]) + 1
		if ra == null or not ra.ok:
			if st.politics.run_terminated:
				out["end"] = "%d 年（原因 %d）" % [1600 + q / 4, st.politics.termination_reason]
			else:
				out["end"] = "故障 %d" % (ra.code if ra else -1)
			break
		if step > 0 and (q % step == step - 1 or q == n_q - 1):
			print("%4d %9.2f %6.1f %9.1f %9.3f %5d %5d %6.1f   %s" % [1600 + q / 4,
					st.diag.gdp_real / U, st.diag.unemployment_ppm / 1e4,
					JWMath.sum(st.capital.cell_capital_value) / U, st.money.price_level_ppm / 1e6,
					_techs_done(st), int(out["built"]), st.accounts.cash_of(JWIds.AGENT_GOV) / U,
					_mix(st)])
	out["gdp"] = st.diag.gdp_real / U
	out["unemp"] = st.diag.unemployment_ppm / 1e4
	out["techs"] = _techs_done(st)
	return out


## 本季提交的建造命令在 S02 有没有被接受（命令流里本季新增的行）。
static func _accepted_build(cmds: JWCommands, from_row: int) -> bool:
	var i: int = maxi(0, from_row - 2)
	while i < cmds.count:
		if cmds.c_kind[i] == JWCommands.Kind.BUILD_BUILDING and cmds.c_accepted[i] == 1:
			return true
		i += 1
	return false


static func _techs_done(st: JWSimState) -> int:
	var n: int = 0
	for t: int in st.research.tech_count:
		if (st.research.completed_mask >> t) & 1 == 1:
			n += 1
	return n


## 十六个生产单元本季各自被什么卡住，加上企业现金与贷款余额。
static func _mix(st: JWSimState) -> String:
	var names: PackedStringArray = ["计划", "产能", "劳动", "电力", "投入"]
	var cnt: PackedInt64Array = PackedInt64Array()
	cnt.resize(names.size())
	cnt.fill(0)
	for c: int in JWUnits.CELL:
		var b: int = st.sectors.f_binding_code[c]
		if b >= 0 and b < names.size():
			cnt[b] += 1
	var parts: PackedStringArray = PackedStringArray()
	for i: int in names.size():
		if cnt[i] > 0:
			parts.append("%s%d" % [names[i], cnt[i]])
	var firm_cash: int = 0
	for c2: int in JWUnits.CELL:
		firm_cash += st.accounts.cash_of(JWIds.agent_of_cell(c2))
	return "%s ｜企业现金 %.1f 贷款 %.1f" % [" ".join(parts), firm_cash / U,
			(st.credit.principal_total() + st.credit.wc_total()) / U]


func _args(v: Array) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(JWCommands.ARG_SLOTS)
	a.fill(0)
	for i: int in v.size():
		a[i] = int(v[i])
	return a
