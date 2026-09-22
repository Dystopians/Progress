## 两条产业路线的对照局（docs/53 M2-8）：同一个 1600 剧本、同一个种子，只有玩法不同。
##
## 路线甲「重农商贸」：先土地清丈 → 水利营造 → 轮作，再复式记账 → 港务营造；
##                     建地区水利与基本灌溉（农业），市集商行与港务扩建（服务）。
## 路线乙「早期工场」：先复式记账 → 行会工场 → 木炭冶炼，再土地清丈 → 水力机械；
##                     建手工工场与木炭冶炼（制造），辅以基本灌溉保口粮。
##
## 两条都只用**真实命令**（13 设定研究方向、14 新建建筑），不直接改状态，不放宽任何规则。
## 建造的判据也写死成一条简单规则：国库现金 > 造价 × 2 才下令，钱不够就等——
## 这不是「最优打法」，是「一个普通玩家会做的事」。对照的意义在于两条路线都得跑得通。
##
## 用法：godot --headless --path <根> --script res://tools/route_compare.gd -- [季数=200] [种子=1] [步=20]
extends SceneTree

const U: float = 1_000_000_000.0

## 路线表：[科技顺序], [[建筑类型, 地区, 所有者], ...]
## 建筑类型下标按 content/buildings 文件名升序 + 1：
## 1 基本灌溉、2 地区水利、3 手工工场、4 木炭冶炼、5 市集商行、6 港务扩建。
## 所有者：0 企业、1 政府。
const ROUTE_A_TECH: PackedInt64Array = [0, 1, 2, 3, 7]
const ROUTE_A_BUILD: Array = [[2, 0, 1], [1, 1, 0], [5, 1, 0], [2, 2, 1], [6, 2, 0], [1, 3, 0]]
const ROUTE_B_TECH: PackedInt64Array = [3, 4, 6, 0, 5]
const ROUTE_B_BUILD: Array = [[3, 1, 0], [5, 1, 0], [3, 0, 0], [4, 2, 0], [1, 3, 0], [3, 2, 0]]


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var n_q: int = int(args[0]) if args.size() > 0 else 200
	var seed_v: int = int(args[1]) if args.size() > 1 else 1
	var step: int = int(args[2]) if args.size() > 2 else 20
	_run("甲 重农商贸", ROUTE_A_TECH, ROUTE_A_BUILD, n_q, seed_v, step)
	_run("乙 早期工场", ROUTE_B_TECH, ROUTE_B_BUILD, n_q, seed_v, step)
	quit(0)


func _run(name: String, techs: PackedInt64Array, builds: Array, n_q: int, seed_v: int,
		step: int) -> void:
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_route_%d" % seed_v
	var r: JWResult = g.new_game("res://content#campaign_1600", seed_v, 0)
	if r == null or not r.ok:
		print("【%s】开局失败" % name)
		return
	var st: JWSimState = g.get("_st") as JWSimState
	st.crisis.final_window_q = 1 << 40
	print("\n══ 路线%s（种子 %d，%d 季 == %d 年）══" % [name, seed_v, n_q, n_q / 4])
	print("年份   实际GDP  失业%   资本存量  价格水平  已完成科技  建成设施  国库")
	var next_tech: int = 0
	var next_build: int = 0
	var built: int = 0
	for q: int in n_q:
		# ① 研究：当前方向完成了就换下一项。
		if next_tech < techs.size():
			var t: int = techs[next_tech]
			if (st.research.completed_mask >> t) & 1 == 1:
				next_tech += 1
			elif st.research.focus != t and st.research.is_available(t):
				g.submit_command(JWCommands.Kind.SET_RESEARCH_FOCUS, _args([t]))
		# ② 建造：清单里的下一项解锁了、国库又付得起两倍造价，就下令。
		if next_build < builds.size():
			var spec: Array = builds[next_build]
			var bt: int = int(spec[0])
			if (st.research.unlocked_building_mask() >> bt) & 1 == 1:
				var cost: int = st.buildings.t_cost[bt]
				var payer: int = JWIds.AGENT_GOV if int(spec[2]) == 1 \
						else JWIds.agent_of_cell(JWIds.idx_cell(int(spec[1]),
								st.buildings.t_sector[bt]))
				if st.accounts.cash_of(payer) > cost * 2:
					var rb: JWResult = g.submit_command(JWCommands.Kind.BUILD_BUILDING,
							_args([bt, int(spec[1]), int(spec[2]), 0]))
					if rb != null and rb.ok:
						next_build += 1
						built += 1
					elif q % 20 == 0:
						print("   [第 %d 季] 建 %d 于地区 %d 被拒：码 %d" % [q, bt, int(spec[1]),
								rb.code if rb else -1])
		g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, _args([]))
		var cmds: JWCommands = g.get("_cmds") as JWCommands
		var ra: JWResult = g.advance_quarter()
		# 建造命令是不是在 S02 被拒了：只有逐条看回执才知道，submit_command 只校验形状。
		if cmds != null:
			for i: int in cmds.count:
				if cmds.c_kind[i] == JWCommands.Kind.BUILD_BUILDING and cmds.c_accepted[i] == 0:
					print("   [第 %d 季] 建造被拒：码 %d" % [q, cmds.c_reject_code[i]])
		if ra == null or not ra.ok:
			print("第 %d 季推进失败（码 %d）" % [q, ra.code if ra else -1])
			if st.politics.run_terminated:
				st.politics.run_terminated = false
				JWResult.clear_pending()
				continue
			break
		if q % step == step - 1 or q == n_q - 1:
			var done: int = 0
			for t2: int in st.research.tech_count:
				if (st.research.completed_mask >> t2) & 1 == 1:
					done += 1
			var stacks: int = 0
			for b: int in st.buildings.count:
				if st.buildings.type[b] > 0:
					stacks += 1
			var proj: int = 0
			for pr: int in st.projects.count:
				if st.projects.building_type[pr] > 0 and st.projects.status[pr] < JWUnits.ProjectStatus.COMMISSIONED:
					proj += 1
			print(("%4d %9.2f %6.1f %9.1f %9.3f %9d %10d %7.1f  在建%d" % [
					1600 + q / 4, st.diag.gdp_real / U, st.diag.unemployment_ppm / 1e4,
					JWMath.sum(st.capital.cell_capital_value) / U,
					st.money.price_level_ppm / 1e6, done, stacks,
					st.accounts.cash_of(JWIds.AGENT_GOV) / U, proj]) + "  " + _mix(st))
	print("下令建造 %d 次；研究推进到清单第 %d 项。" % [built, next_tech])


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
	var pol: String = " 政策"
	for pi: int in 3:
		pol += "%d" % (1 if st.policy.is_effective(pi, st.q) else 0)
	var gov: String = pol
	for c3: int in JWUnits.CELL:
		var sh: int = st.buildings.gov_share_ppm(c3)
		if sh > 0:
			gov += " 单元%d政府份额%.1f%%" % [c3, sh / 1e4]
	return "%s ｜企业现金 %.1f 贷款 %.1f%s" % [" ".join(parts), firm_cash / 1e9,
			(st.credit.principal_total() + st.credit.wc_total()) / 1e9, gov]


func _args(v: Array) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(JWCommands.ARG_SLOTS)
	a.fill(0)
	for i: int in v.size():
		a[i] = int(v[i])
	return a
