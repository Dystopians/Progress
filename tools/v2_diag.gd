## v2 平衡诊断（无界面）：按行动脚本推进，然后
##   era    在给定的几个年份打印「进入下一时代还差什么」、研究方向与研究点
##   land   到某年时各地区各类地用了多少、农田级数与水利覆盖、研究与托管最近办的事（查缺粮用）
##   trace  从某年起逐季打印产值、失业、生活、在改级数、进出口、国库、威信、零售、积蓄与各部门产值，
##          最后列出纪事计数、各阶层在岗与最缺的货（查换时代时的波动用）
## 用法：godot --headless --path . --script res://tools/v2_diag.gd -- <脚本.json> era 1620,1650,1680
##       godot --headless --path . --script res://tools/v2_diag.gd -- <脚本.json> trace 1905 24
extends SceneTree

const U: float = 10000000.0


func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 2:
		print("用法：-- <脚本.json> era <年,年,...> | trace <起年> [季数]")
		quit(2)
		return
	var ps: JCPlayscript = JCPlayscript.from_file(a[0])
	var game: JCGame = JCGame.new()
	game.autosave = false
	if not game.new_game(int(ps.data.get("seed", 1))) or not ps.bind(game):
		print("开局或脚本有误：", ps.errors)
		quit(1)
		return
	match a[1]:
		"era":
			_era(game, ps, a[2] if a.size() > 2 else "1620,1660,1700")
		"trace":
			_trace(game, ps, a[2] if a.size() > 2 else "1700", int(a[3]) if a.size() > 3 else 24)
		"land":
			_land(game, ps, a[2] if a.size() > 2 else "1700")
	quit(0)


func _era(game: JCGame, ps: JCPlayscript, years: String) -> void:
	for ys: String in years.split(","):
		ps.step(game, JCPlayscript.parse_q(ys, game.st.start_year))
		var rep: Dictionary = game.sim.world.era_gap_report()
		var done: int = 0
		for t: int in game.ct.t_n:
			done += game.st.t_done[t]
		print("%s 时代%d 缺：%s | 已研究 %d | 研究中 %s | 点数 %d" % [ys, game.st.era, JSON.stringify(rep), done,
			game.ct.t_id[game.st.focus] if game.st.focus >= 0 else "-", game.st.points])
		if game.st.over == 1:
			break


func _trace(game: JCGame, ps: JCPlayscript, from: String, n: int) -> void:
	ps.step(game, JCPlayscript.parse_q(from, game.st.start_year))
	var st: JCState = game.st
	var ct: JCContent = game.ct
	var q0: int = st.q
	print("季      时代 人口万 产值万  失业%  生活%  在改级 总级  新建级  进口万  出口万  国库万  威信  零售万  积蓄万   农/工/能/服")
	for i: int in n:
		ps.step(game, st.q + 1)
		var up: int = 0
		var tot: int = 0
		var pend: int = 0
		for k: int in st.stack_count():
			tot += st.s_level[k]
			pend += st.s_pending[k]
			if st.s_status[k] == JCState.ST_UPGRADE:
				up += st.s_level[k]
		var l: Dictionary = st.last
		var sv: Array = l.get("sector_va", [0, 0, 0, 0])
		print("%d%s  %d  %6.0f %7.0f %5.1f %6.1f %6d %6d %6d %7.0f %7.0f %7.0f %5.1f %7.0f %8.0f  %.0f/%.0f/%.0f/%.0f" % [st.year(),
				["春", "夏", "秋", "冬"][st.season()], st.era, float(l.get("pop", 0)) / 10000.0, float(l.get("gdp", 0)) / U,
				float(l.get("unemp_ppm", 0)) / 10000.0, float(l.get("living", 0)) / 10000.0, up, tot, pend,
				float(l.get("imports", 0)) / U, float(l.get("exports", 0)) / U, float(st.treasury) / U,
				float(st.legitimacy) / 10000.0, float(l.get("retail", 0)) / U, float(JCMath.sum(st.savings)) / U,
				float(sv[0]) / U, float(sv[1]) / U, float(sv[2]) / U, float(sv[3]) / U])
		if st.over == 1:
			print("终局：", st.over_reason)
			break
	var cnt: Dictionary = {}
	for e: Dictionary in st.chron:
		if int(e["q"]) >= q0:
			cnt[String(e["key"])] = int(cnt.get(String(e["key"]), 0)) + 1
	print("纪事计数：", JSON.stringify(cnt))
	var C: int = ct.c_n
	for c: int in C:
		var sup: int = 0
		var emp: int = 0
		for r: int in ct.r_n:
			var kk: int = r * C + c
			var s0: int = JCMath.mulppm(st.pop[kk], ct.c_work[c])
			sup += s0
			emp += mini(st.employed[kk], s0)
		print("  %s 劳力 %.0f 万 在岗 %.0f 万" % [ct.c_id[c], float(sup) / 10000.0, float(emp) / 10000.0])
	# 口粮：各地区各阶层的满足度（最低的几组）与医药、卫生覆盖
	var staple: int = int(ct.nidx.get("staple", 0))
	var rows: Array = []
	for r2: int in ct.r_n:
		for c2: int in C:
			var k2: int = r2 * C + c2
			if st.pop[k2] > 0:
				rows.append([st.sat[k2 * ct.n_n + staple], ct.r_id[r2], ct.c_id[c2], st.pop[k2]])
	rows.sort_custom(func(a1: Array, b1: Array) -> bool: return int(a1[0]) < int(b1[0]))
	for rw: Array in rows.slice(0, 5):
		print("  口粮 %s %s %.0f%%（%.0f 万人）" % [rw[1], rw[2], float(rw[0]) / 10000.0, float(rw[3]) / 10000.0])
	for r3: int in ct.r_n:
		var pop_r: int = maxi(1, game.sim.soc.region_pop(r3))
		print("  %s 医药覆盖 %.0f%% 卫生覆盖 %.0f%%" % [ct.r_id[r3],
				float(JCMath.ratio_ppm(game.sim.econ.health_cov[r3], pop_r)) / 10000.0,
				float(JCMath.ratio_ppm(game.sim.econ.sanit_cov[r3], pop_r)) / 10000.0])
	for x: Dictionary in game.analyst.shortages(10):
		print("  缺 %s 缺口 %.0f%% 价 %.0f%%" % [ct.g_id[int(x["g"])], float(x["gap_ppm"]) / 10000.0, float(x["price_ppm"]) / 10000.0])


func _land(game: JCGame, ps: JCPlayscript, at: String) -> void:
	ps.step(game, JCPlayscript.parse_q(at, game.st.start_year))
	var st: JCState = game.st
	var ct: JCContent = game.ct
	for r: int in ct.r_n:
		var parts: PackedStringArray = PackedStringArray()
		for lt: int in JCContent.LT_N:
			var cap: int = st.land[r * JCContent.LT_N + lt]
			if cap > 0:
				parts.append("%s %d/%d" % [JCContent.LAND_TYPES[lt], game.sim.inv.land_in_use(r, lt), cap])
		var farm: int = game.sim.econ.farm_lv[r] if game.sim.econ.farm_lv.size() > r else 0
		print("%s 地：%s ｜ 农田 %d 级 ｜ 水利覆盖 %d 级" % [ct.r_id[r], ", ".join(parts), farm,
				game.sim.econ.water_cov[r] / 1_000_000 if game.sim.econ.water_cov.size() > r else 0])
	var done: PackedStringArray = PackedStringArray()
	for t: int in ct.t_n:
		if st.t_done[t] == 1:
			done.append(ct.t_id[t])
	print("已研究：", ", ".join(done), " ｜ 研究中：", ct.t_id[st.focus] if st.focus >= 0 else "-")
	for rec: Dictionary in game.steward.records.slice(maxi(0, game.steward.records.size() - 24)):
		print("  %d %s %s %s %s" % [int(rec["q"]), rec["domain"], rec["reason"], "成" if bool(rec["ok"]) else "未成：" + String(rec["why"]),
				JSON.stringify(rec["slots"])])
