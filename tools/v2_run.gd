## v2 无界面试跑：开新局、推进若干季、每年打印一行摘要（docs/57）。
## 用法：godot --headless --path . --script res://tools/v2_run.gd -- [季数=80] [种子=1] [every=4] [goods] [stacks] [chron]
extends SceneTree

const U: float = 10000000.0   # 万两 = 1e7 厘


func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var n_q: int = int(a[0]) if a.size() > 0 and a[0].is_valid_int() else 80
	var seed: int = int(a[1]) if a.size() > 1 and a[1].is_valid_int() else 1
	var every: int = 4
	for s: String in a:
		if s.begins_with("every="):
			every = maxi(1, int(s.substr(6)))
	var ct: JCContent = JCContent.load_default()
	if not ct.ok():
		for e: String in ct.errors:
			print("内容错误：", e)
		quit(1)
		return
	var st: JCState = JCSim.new_state(ct, seed)
	var sim: JCSim = JCSim.new(ct, st)
	sim.warm_up()
	var t0: int = Time.get_ticks_msec()
	print("年份    人口万  产值万两 失业%  生活%  国库万  债务万  收入万  支出万  时代 世界 合法% 危机  稻米 麦粟 布匹 盐")
	for q: int in n_q:
		var res: Dictionary = sim.advance([])
		if not bool(res["ok"]):
			print("第 %d 季自检失败：%s" % [st.q - 1, res["reason"]])
			break
		if (st.q - 1) % every == 0 or st.over == 1:
			_row(ct, st)
		if st.over == 1:
			print("终局：%s（%d 年）" % [st.over_reason, st.year()])
			break
	print("用时 %.1f 秒，平均 %.1f 毫秒/季" % [(Time.get_ticks_msec() - t0) / 1000.0,
			float(Time.get_ticks_msec() - t0) / maxi(1, st.q)])
	if a.has("goods"):
		_goods(ct, st)
	if a.has("stacks"):
		_stacks(ct, st)
	if a.has("chron"):
		for c: Dictionary in st.chron.slice(maxi(0, st.chron.size() - 60)):
			print("  %d  %s  %s  %s" % [c["q"], c["kind"], c["key"], JSON.stringify(c["args"])])
	quit(0)


func _p(ct: JCContent, st: JCState, id: String) -> String:
	var g: int = int(ct.gidx.get(id, -1))
	return "%.2f" % (float(st.price[g]) / float(ct.g_base[g])) if g >= 0 else "-"


func _row(ct: JCContent, st: JCState) -> void:
	var l: Dictionary = st.last
	var stages: String = "%d%d%d" % [st.cr_stage[0], st.cr_stage[1], st.cr_stage[2]]
	print("%d%s %7.0f %8.0f %5.1f %6.1f %7.0f %7.0f %7.0f %7.0f  %d    %d  %5.1f  %s  %s %s %s %s" % [
		st.year() if st.season() > 0 else st.year() - 1, ["春", "夏", "秋", "冬"][(st.q - 1) % 4],
		float(l.get("pop", 0)) / 10000.0, float(l.get("gdp", 0)) / U,
		float(l.get("unemp_ppm", 0)) / 10000.0, float(l.get("living", 0)) / 10000.0,
		float(st.treasury) / U, float(st.debt) / U, float(l.get("gov_rev", 0)) / U, float(l.get("gov_exp", 0)) / U,
		st.era, st.world_era, float(st.legitimacy) / 10000.0, stages,
		_p(ct, st, "rice"), _p(ct, st, "grain"), _p(ct, st, "fabric"), _p(ct, st, "salt")])


func _goods(ct: JCContent, st: JCState) -> void:
	print("\n商品：价格/基准  产量  居民  投入  出口  进口  缺口  库存（单位）")
	for g: int in ct.g_n:
		if st.f_prod[g] == 0 and st.f_hh[g] == 0 and st.f_use[g] == 0 and st.f_imp[g] == 0:
			continue
		print("  %-6s %5.2f %10.0f %10.0f %10.0f %8.0f %8.0f %8.0f %10.0f" % [ct.g_name[g],
			float(st.price[g]) / ct.g_base[g], st.f_prod[g] / 1000.0, st.f_hh[g] / 1000.0, st.f_use[g] / 1000.0,
			st.f_exp[g] / 1000.0, st.f_imp[g] / 1000.0, st.f_unmet[g] / 1000.0, st.stock[g] / 1000.0])


func _stacks(ct: JCContent, st: JCState) -> void:
	print("\n建筑堆：地区 建筑 方法 所有者 级 开工% 卡在 利润（两/季）")
	for i: int in st.stack_count():
		print("  %s %s %s %s %d %3.0f%% %d %.0f" % [ct.r_name[st.s_region[i]], ct.b_name[st.s_b[i]],
			ct.m_name[st.s_m[i]], "官" if st.s_owner[i] == 1 else "民", st.s_level[i], st.s_u[i] / 10000.0,
			st.s_bind[i], st.s_profit[i] / 1000.0])
