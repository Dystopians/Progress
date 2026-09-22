## 长局基准（docs/53 M1-9）：战役剧本推进 N 季（缺省 1600），报告
## ① 逐年推进耗时（中位数 / P95 / 最大）；② 结束时的存档大小；③ 全程重放耗时与逐位一致性；
## ④ 数值尺度：金额、数量、价格的峰值相对上限的余量，项目 / 债券 / 建筑堆表的峰值行数。
##
## 用法：godot --headless --path . --script res://tools/bench_long.gd -- [季数=1600] [种子=1] [nofinal]
## nofinal：把危机的最后补救窗口设为无穷长（只改本进程），让无人操作的占位经济也能跑满全程。
## M1 的战役剧本是现代经济的副本，无人操作时会退化（见 docs/18 R-CLOSURE-01）；
## 这里的数值尺度只说明「骨架在退化经济里也不溢出」，不代表 1600 年经济的真实量级。
extends SceneTree

const SLOT: String = "bench_long"


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var n_q: int = int(args[0]) if args.size() > 0 and args[0].is_valid_int() else 1600
	var seed_v: int = int(args[1]) if args.size() > 1 and args[1].is_valid_int() else 1
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_bench_long"
	var r0: JWResult = g.new_game("res://content#campaign_1600", seed_v, 0)
	if r0 == null or not r0.ok:
		print("开局失败")
		quit(1)
		return
	var st: JWSimState = g.get("_st") as JWSimState
	if args.has("nofinal"):
		st.crisis.final_window_q = 1 << 40

	var year_us: PackedInt64Array = PackedInt64Array()
	var peak_amount: int = 0
	var peak_amount_what: String = ""
	var peak_qty: int = 0
	var peak_price_ppm: int = 0
	var peak_projects: int = 0
	var peak_bonds: int = 0
	var peak_buildings: int = 0
	var done: int = 0
	var stopped: String = ""
	var t_all: int = Time.get_ticks_usec()
	while done < n_q:
		var n_year: int = mini(4, n_q - done)
		var t0: int = Time.get_ticks_usec()
		var res: Dictionary = g.advance_batch(n_year)
		year_us.append(Time.get_ticks_usec() - t0)
		done += int(res["advanced"])
		# 峰值：全部账户余额的绝对值、在用产能、价格。
		var bal: PackedInt64Array = st.accounts.balance
		for i: int in bal.size():
			var v: int = absi(bal[i])
			if v > peak_amount:
				peak_amount = v
				peak_amount_what = "account[%d]" % i
		for c: int in JWUnits.CELL:
			peak_qty = maxi(peak_qty, st.capital.cell_capacity_active[c])
		for s: int in JWUnits.S:
			peak_price_ppm = maxi(peak_price_ppm, JWMath.mul_div_floor(st.pricing.price[s], JWUnits.PPM,
					st.pricing.base_price[s]))
		peak_projects = maxi(peak_projects, st.projects.count)
		peak_bonds = maxi(peak_bonds, st.bonds.count)
		peak_buildings = maxi(peak_buildings, st.buildings.count)
		if int(res["advanced"]) < n_year:
			var reason: int = int(res["reason"])
			if reason == JWGame.Pause.TERMINATED or reason == JWGame.Pause.FAILED:
				stopped = "第 %d 季停下：原因 %d，终局码 %d，结算码 %d" % [done, reason,
						st.politics.termination_reason, int(res["code"])]
				break
	var total_ms: int = (Time.get_ticks_usec() - t_all) / 1000

	var sorted: PackedInt64Array = year_us.duplicate()
	sorted.sort()
	var med: int = sorted[sorted.size() / 2] if sorted.size() > 0 else 0
	var p95: int = sorted[mini(sorted.size() - 1, (sorted.size() * 95) / 100)] if sorted.size() > 0 else 0
	var mx: int = sorted[sorted.size() - 1] if sorted.size() > 0 else 0

	var t_save: int = Time.get_ticks_msec()
	var rs: JWResult = g.save_game(SLOT)
	var save_ms: int = Time.get_ticks_msec() - t_save
	var save_bytes: int = _dir_bytes("user://saves/" + SLOT)
	var t_rep: int = Time.get_ticks_msec()
	var rv: JWResult = g.verify_replay(SLOT)
	var replay_ms: int = Time.get_ticks_msec() - t_rep

	print("════════ 长局基准（战役剧本，种子 %d） ════════" % seed_v)
	print("推进季数        ： %d / %d %s" % [done, n_q, stopped])
	print("总耗时          ： %d ms（每季平均 %.1f ms）" % [total_ms, float(total_ms) / maxf(1.0, done)])
	print("推进一年        ： 中位数 %.0f ms，P95 %.0f ms，最大 %.0f ms（%d 个样本）" % [med / 1000.0,
			p95 / 1000.0, mx / 1000.0, year_us.size()])
	print("存档            ： %s，%.1f KB，写入 %d ms" % ["成功" if rs != null and rs.ok else "失败",
			save_bytes / 1024.0, save_ms])
	print("全程重放        ： %s，%d ms" % ["逐位一致" if rv != null and rv.ok else "不一致或失败", replay_ms])
	print("金额峰值        ： %s μU（%s），上限 %s，余量 %.0f 倍" % [String.num_scientific(float(peak_amount)),
			peak_amount_what, String.num_scientific(float(JWUnits.AMOUNT_MAX)),
			float(JWUnits.AMOUNT_MAX) / maxf(1.0, peak_amount)])
	print("单元产能峰值    ： %s μQ，上限 %s，余量 %.0f 倍" % [String.num_scientific(float(peak_qty)),
			String.num_scientific(float(JWUnits.QTY_MAX)), float(JWUnits.QTY_MAX) / maxf(1.0, peak_qty)])
	print("价格峰值        ： %.2f 倍基年价（绝对护栏 %.0f 倍）" % [peak_price_ppm / 1e6, st.money.abs_ceil_ppm / 1e6])
	print("表行峰值        ： 项目 %d / %d，债券 %d / %d，建筑堆 %d / %d" % [peak_projects, JWUnits.PROJECT_CAP0,
			peak_bonds, JWUnits.BOND_CAP0, peak_buildings, JWBuildings.CAP0])
	print("累计货币发行    ： %.2f U；政府更替 %d 次；危机级别 %s" % [st.money.issued_total / 1e9,
			st.crisis.gov_changes, str(st.crisis.stage)])
	quit()


static func _dir_bytes(path: String) -> int:
	var total: int = 0
	var d: DirAccess = DirAccess.open(path)
	if d == null:
		return 0
	for f: String in d.get_files():
		var fa: FileAccess = FileAccess.open(path + "/" + f, FileAccess.READ)
		if fa != null:
			total += fa.get_length()
			fa.close()
	return total
