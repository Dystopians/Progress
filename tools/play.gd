## 无界面运行行动脚本（application/playscript.gd）：开局、逐季提交脚本命令并推进，打印年表与动作日志。
##
## 用法：godot --headless --path <根> --script res://tools/play.gd -- <脚本.json> [截止=脚本的 until] [选项...]
##   截止：同脚本里的写法，"1650"、"1650秋" 或 "q:120"
##   seed=<n>      覆盖脚本里的种子
##   every=<n>     年表每 n 季打印一行（默认 20）
##   save=<槽名>   跑完另存到该存档槽（用于生成样例存档）
##   log           打印每条动作的受理结果
## 走的是 JWGame 的正式路径（与界面相同）：命令经 S02 判定，每季自动存档追加。
extends SceneTree

const U: float = 1_000_000_000.0


func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.is_empty():
		print("用法：-- <脚本.json> [截止] [seed=n] [every=n] [save=槽名] [log]")
		quit(2)
		return
	var ps: JWPlayscript = JWPlayscript.from_file(a[0])
	if not ps.ok():
		for e: String in ps.errors:
			print("脚本错误：", e)
		quit(1)
		return
	var until_s: String = ""
	var every: int = 20
	var slot: String = ""
	var show_log: bool = false
	for i: int in range(1, a.size()):
		var s: String = a[i]
		if s.begins_with("seed="):
			ps.seed_value = int(s.substr(5))
		elif s.begins_with("every="):
			every = maxi(int(s.substr(6)), 1)
		elif s.begins_with("save="):
			slot = s.substr(5)
		elif s == "log":
			show_log = true
		else:
			until_s = s
	var g: JWGame = JWGame.new()
	g.autosave_slot = "play_tool_autosave"
	var spec: String = "res://content" if ps.scenario == "chengwan" else "res://content#" + ps.scenario
	var r: JWResult = g.new_game(spec, ps.seed_value, 0)
	if r == null or not r.ok:
		print("开局失败：", r.code if r != null else -1)
		quit(1)
		return
	if not g.playscript_bind(ps):
		for e2: String in ps.errors:
			print("脚本错误：", e2)
		quit(1)
		return
	var st: JWSimState = g._st
	var until_q: int = ps.until_q
	if until_s != "":
		until_q = JWPlayscript._parse_q(until_s, st.start_year)
	if until_q < 0:
		print("没有截止时间：脚本里写 until，或在命令行给出")
		quit(1)
		return
	print("══ 行动脚本「%s」 剧本 %s 种子 %d，推进到第 %d 季 ══" % [ps.name, ps.scenario, ps.seed_value, until_q])
	print("季    年份      实际GDP  失业%   国库    科技  建成  待执行")
	var t0: int = Time.get_ticks_msec()
	var out: Dictionary = {}
	while st.q < until_q:
		var stop: int = mini(until_q, (st.q / every + 1) * every)
		out = g.run_playscript(ps, stop)
		_row(st, ps)
		if bool(out["terminated"]) or int(out["code"]) != 0:
			break
	if bool(out.get("terminated", false)):
		print("执政结束：%s，原因 %d" % [_when(st), st.politics.termination_reason])
	elif int(out.get("code", 0)) != 0:
		print("推进失败：码 %d（%s）" % [int(out["code"]), g.last_fault_dir])
	var rejected: int = 0
	for e3: Dictionary in ps.log:
		if not bool(e3["accepted"]):
			rejected += 1
		if show_log or not bool(e3["accepted"]):
			print("  %s %s  %s%s" % [_when_q(st, int(e3["q"])), "受理" if bool(e3["accepted"]) else "被拒",
					String(e3["label"]), "" if bool(e3["accepted"]) else "（码 %d）" % int(e3["code"])])
	print("动作 %d 条，被拒 %d 条，未执行 %d 项；用时 %.1f 秒" % [ps.log.size(), rejected, ps.pending_count(),
			(Time.get_ticks_msec() - t0) / 1000.0])
	if slot != "":
		var sv: JWResult = g.save_game(slot)
		print("另存到槽「%s」：%s" % [slot, "成功" if sv != null and sv.ok else "失败"])
	quit(0)


func _row(st: JWSimState, ps: JWPlayscript) -> void:
	var techs: int = 0
	for t: int in st.research.tech_count:
		if (st.research.completed_mask >> t) & 1 == 1:
			techs += 1
	print("%-5d %-9s %8.2f %6.1f %7.2f %5d %5d %6d" % [st.q, _when(st), st.diag.gdp_real / U,
			st.diag.unemployment_ppm / 1e4, st.accounts.cash_of(JWIds.AGENT_GOV) / U, techs,
			st.buildings.count - JWUnits.CELL, ps.pending_count()])


static func _when(st: JWSimState) -> String:
	return _when_q(st, st.q)


static func _when_q(st: JWSimState, q: int) -> String:
	if st.start_year <= 0:
		return "第%d季" % q
	return "%d%s" % [st.start_year + q / 4, JWPlayscript.SEASONS[q % 4]]
