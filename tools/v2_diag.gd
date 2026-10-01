## v2 平衡诊断（无界面）：按行动脚本推进，然后
##   era    在给定的几个年份打印「进入下一时代还差什么」、研究方向与研究点
##   land   到某年时各地区各类地用了多少、农田级数与水利覆盖、研究与托管最近办的事（查缺粮用）
##   trace  从某年起逐季打印产值、失业、生活、在改级数、进出口、国库、威信、零售、积蓄与各部门产值，
##          最后列出纪事计数、各阶层在岗与最缺的货（查换时代时的波动用）
##   needs  从某年起每隔几季打印生活的拆分：温饱、日用、期待倍数、各阶层民心与民怨、每项日用需要满足了几成
##          （查威信慢慢往下滑是哪几项拖的）
## 用法：godot --headless --path . --script res://tools/v2_diag.gd -- <脚本.json> era 1620,1650,1680
##       godot --headless --path . --script res://tools/v2_diag.gd -- <脚本.json> trace 1905 24
##       godot --headless --path . --script res://tools/v2_diag.gd -- <脚本.json> needs 1760 20 12 seed=2
## 任意位置的 seed=N 覆盖脚本里的种子。
extends SceneTree

const U: float = 10000000.0


func _init() -> void:
	var raw: PackedStringArray = OS.get_cmdline_user_args()
	var a: PackedStringArray = PackedStringArray()
	var seed_over: int = -1
	for s: String in raw:
		if s.begins_with("seed="):
			seed_over = int(s.substr(5))
		else:
			a.append(s)
	if a.size() < 2:
		print("用法：-- <脚本.json> era <年,年,...> | trace <起年> [季数] | land <年> | needs <起年> [间隔季] [次数]")
		quit(2)
		return
	var ps: JCPlayscript = JCPlayscript.from_file(a[0])
	if seed_over >= 0:
		ps.data["seed"] = seed_over
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
		"needs":
			_needs(game, ps, a[2] if a.size() > 2 else "1700", int(a[3]) if a.size() > 3 else 20,
					int(a[4]) if a.size() > 4 else 10)
		"support":
			for ys: String in (a[2] if a.size() > 2 else "1650,1700").split(","):
				ps.step(game, JCPlayscript.parse_q(ys, game.st.start_year))
				var f: Dictionary = game.analyst.fiscal()
				print("%s 威信 %.1f%% 国库 %.0f 万 每季收入 %.0f 万 常规开支 %.0f 万" % [ys, float(game.st.legitimacy) / 1e4,
						float(game.st.treasury) / 1e7, float(f["rev"]) / 1e7, float(f["regular"]) / 1e7])
				for sd: Dictionary in game.analyst.support_decrees():
					print("    %s 威信 +%.2f%% 每季 %.1f 万" % [sd["decree"], float(sd["gain_ppm"]) / 1e4, float(sd["cost_q"]) / 1e7])
				var on: PackedStringArray = PackedStringArray()
				for d: int in game.ct.decrees.size():
					if game.st.d_level[d] > 0:
						on.append("%s=%d" % [game.ct.decrees[d]["id"], game.st.d_level[d]])
				print("    已施行：", ", ".join(on))
	quit(0)


func _needs(game: JCGame, ps: JCPlayscript, from: String, every: int, n: int) -> void:
	var st: JCState = game.st
	var ct: JCContent = game.ct
	var econ: JCEconomy = game.sim.econ
	var C: int = ct.c_n
	var N: int = ct.n_n
	ps.step(game, JCPlayscript.parse_q(from, st.start_year))
	for i: int in n:
		if i > 0:
			ps.step(game, st.q + every)
		var em: int = econ.expect_mult()
		var ref_avg: int = 0
		var pw: int = 0
		var liv: int = 0
		var com: int = 0
		var un: PackedInt64Array = JCMath.zeros(C)
		var cpw: PackedInt64Array = JCMath.zeros(C)
		var nsum: PackedInt64Array = JCMath.zeros(N)
		var npw: PackedInt64Array = JCMath.zeros(N)
		# 商贾与士绅单算（他们的民心最容易掉）
		var usum: PackedInt64Array = JCMath.zeros(N)
		var upw: PackedInt64Array = JCMath.zeros(N)
		var cliv: PackedInt64Array = JCMath.zeros(C)
		var ccom: PackedInt64Array = JCMath.zeros(C)
		for k: int in st.pop.size():
			var w: int = st.pop[k] / 1000
			if w <= 0:
				continue
			var c: int = k % C
			var upper: bool = ct.c_id[c] == "merchant" or ct.c_id[c] == "gentry"
			pw += w
			liv += st.living[k] * w
			com += st.comfort[k] * w
			un[c] += st.unrest[k] * w
			cliv[c] += st.living[k] * w
			ccom[c] += st.comfort[k] * w
			cpw[c] += w
			ref_avg += st.basket[k] * w
			var ref_b: int = JCMath.mulppm(econ.basket0[k], em)
			for nn: int in N:
				if not ct.need_active(nn, st.era):
					continue
				var idx: int = k * N + nn
				var v: int = st.sat[idx]
				if ct.n_ess[nn] != 1:
					var full: int = JCMath.mulppm(st.pop[k] * ct.n_qty[nn * C + c], econ.need_mult(nn, ref_b))
					if full <= 0:
						continue
					v = mini(2 * JCMath.PPM, JCMath.ratio_ppm(JCMath.mulppm(econ.need_ref[idx], st.sat[idx]), full))
				nsum[nn] += v * w
				npw[nn] += w
				if upper:
					usum[nn] += v * w
					upw[nn] += w
		pw = maxi(pw, 1)
		var line: String = "%d%s 时代%d/%d 期待%.2f 篮子%.2f 生活%.1f 日用%.1f 威信%.1f 民心" % [st.year(),
				["春", "夏", "秋", "冬"][st.season()], st.era, st.world_era, float(em) / 1e6, float(ref_avg / pw) / 1e6,
				float(liv / pw) / 1e4, float(com / pw) / 1e4, float(st.legitimacy) / 1e4]
		for c2: int in C:
			var cw: int = maxi(1, cpw[c2])
			line += " %s 心%.0f 怨%.0f 活%.0f 日%.0f" % [ct.c_id[c2].substr(0, 2), float(st.support[c2]) / 1e4,
					float(un[c2] / cw) / 1e4, float(cliv[c2] / cw) / 1e4, float(ccom[c2] / cw) / 1e4]
		line += " 商税%.1f%% 田赋%.1f%%" % [float(st.tax_commerce_ppm) / 1e4, float(st.tax_land_ppm) / 1e4]
		print(line)
		# 各阶层：人口（万）、人均收入（两/年）、篮子（相对开局）、在岗率
		var cl: String = "    阶层"
		for c3: int in C:
			var p3: int = 0
			var inc3: int = 0
			var bsk: int = 0
			var b0: int = 0
			var sup3: int = 0
			var emp3: int = 0
			for r3: int in ct.r_n:
				var k3: int = r3 * C + c3
				p3 += st.pop[k3]
				inc3 += st.income[k3]
				bsk += st.basket[k3] * (st.pop[k3] / 1000)
				b0 += econ.basket0[k3] * (st.pop[k3] / 1000)
				var s3: int = JCMath.mulppm(st.pop[k3], econ.work_ppm(c3))
				sup3 += s3
				emp3 += mini(st.employed[k3], s3)
			cl += " %s %.0f万 人均%.2f两 篮%.2f 岗%.0f%%" % [ct.c_id[c3].substr(0, 2), float(p3) / 1e4,
					float(inc3) * 4.0 / maxf(1.0, float(p3)) / 1000.0, float(bsk) / maxf(1.0, float(b0)),
					float(emp3) * 100.0 / maxf(1.0, float(sup3))]
			# 商贾、士绅：人均收入按来源拆（工钱/利润/官府/亏损与出资），以及人均积蓄
			if ct.c_id[c3] == "merchant" or ct.c_id[c3] == "gentry":
				var src: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
				var sv3: float = 0.0
				for r4: int in ct.r_n:
					var k4: int = r4 * C + c3
					sv3 += float(st.savings[k4])
					for si: int in JCEconomy.SRC_N:
						src[si] += float(econ.inc_src[k4 * JCEconomy.SRC_N + si])
				var pp: float = maxf(1.0, float(p3)) * 1000.0 / 4.0
				cl += "（工%.1f 利%.1f 官%.1f 出%.1f 蓄%.0f）" % [src[0] / pp, src[1] / pp, src[2] / pp, src[3] / pp,
						sv3 / maxf(1.0, float(p3)) / 1000.0]
		print(cl)
		var parts: PackedStringArray = PackedStringArray()
		var uparts: PackedStringArray = PackedStringArray()
		for nn2: int in N:
			if npw[nn2] > 0:
				parts.append("%s%.0f" % [ct.n_id[nn2], float(nsum[nn2] / npw[nn2]) / 1e4])
			if upw[nn2] > 0:
				uparts.append("%s%.0f" % [ct.n_id[nn2], float(usum[nn2] / upw[nn2]) / 1e4])
		print("    全体 ", " ".join(parts))
		print("    商绅 ", " ".join(uparts))
		# 日用货：供不上（到货不足九成）或贵过三成的
		var gparts: PackedStringArray = PackedStringArray()
		var seen: Dictionary = {}
		for nn3: int in N:
			if ct.n_ess[nn3] == 1 or not ct.need_active(nn3, st.era):
				continue
			for g: int in ct.n_goods[nn3]:
				if seen.has(g) or ct.g_era[g] > st.era:
					continue
				seen[g] = true
				var d: int = econ.prev_demand[g] if econ.prev_demand.size() > g else 0
				var s2: int = econ.prev_supply[g] if econ.prev_supply.size() > g else 0
				var fill: int = JCMath.PPM if d <= 0 else JCMath.ratio_ppm(s2, d)
				var pr: int = game.analyst.price_ppm(g)
				if fill < 900_000 or pr > 1_300_000:
					gparts.append("%s 到%.0f%% 价%.0f%%" % [ct.g_id[g], float(fill) / 1e4, float(pr) / 1e4])
		print("    缺货 ", "，".join(gparts))
		if st.over == 1:
			print("终局：", st.over_reason)
			break


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
		var irr: int = game.sim.econ.irrig_cov[r] if game.sim.econ.irrig_cov.size() > r else 0
		print("%s 地：%s ｜ 农田 %d 级 ｜ 灌溉覆盖 %.0f%% ｜ 水力 %d 级" % [ct.r_id[r], ", ".join(parts), farm,
				float(irr) / maxf(1.0, float(farm) * 1e6) * 100.0,
				game.sim.econ.water_cov[r] / 1_000_000 if game.sim.econ.water_cov.size() > r else 0])
		# 各种做法的农田级数（看口粮与经济作物的比例、改没改新做法）
		var by_m: Dictionary = {}
		for i: int in st.stack_count():
			if st.s_region[i] == r and ct.b_cat[st.s_b[i]] == JCContent.CAT_FARM and st.s_level[i] > 0:
				var mk: String = ct.m_id[st.s_m[i]] + ("(官)" if st.s_owner[i] == JCContent.OWNER_GOV else "")
				by_m[mk] = int(by_m.get(mk, 0)) + st.s_level[i]
		var mparts: PackedStringArray = PackedStringArray()
		for mk2: Variant in by_m.keys():
			mparts.append("%s %d" % [mk2, by_m[mk2]])
		print("    ", "，".join(mparts))
		# 农户劳力：可出工、在岗；农田里卡在人手上的级数、平均开工
		var C2: int = ct.c_n
		var P: int = int(ct.cidx.get("peasant", 0))
		var kp: int = r * C2 + P
		var supp: int = JCMath.mulppm(st.pop[kp], game.sim.econ.work_ppm(P))
		var lab_lv: int = 0
		var all_lv: int = 0
		var u_acc: int = 0
		for i2: int in st.stack_count():
			if st.s_region[i2] == r and ct.b_cat[st.s_b[i2]] == JCContent.CAT_FARM and st.s_level[i2] > 0:
				all_lv += st.s_level[i2]
				u_acc += st.s_u[i2] * st.s_level[i2]
				if st.s_bind[i2] == JCEconomy.B_LABOR:
					lab_lv += st.s_level[i2]
		print("    农户可出工 %.0f 万 在岗 %.0f 万 ｜ 农田卡人手 %d/%d 级 平均开工 %.0f%%" % [float(supp) / 1e4,
				float(st.employed[kp]) / 1e4, lab_lv, all_lv, float(u_acc) / maxf(1.0, float(all_lv)) / 1e4])
	var done: PackedStringArray = PackedStringArray()
	for t: int in ct.t_n:
		if st.t_done[t] == 1:
			done.append(ct.t_id[t])
	print("已研究：", ", ".join(done), " ｜ 研究中：", ct.t_id[st.focus] if st.focus >= 0 else "-")
	for rec: Dictionary in game.steward.records.slice(maxi(0, game.steward.records.size() - 24)):
		print("  %d %s %s %s %s" % [int(rec["q"]), rec["domain"], rec["reason"], "成" if bool(rec["ok"]) else "未成：" + String(rec["why"]),
				JSON.stringify(rec["slots"])])
