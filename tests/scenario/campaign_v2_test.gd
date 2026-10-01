## 四百年战役 v2（docs/57、docs/58）：开局预演、守恒与确定性、存读档与改内容后的重演、撤回、托管与顾问、
## 合并改造（至少两处旧的、七折、官府出钱）、切片改造、引擎文案齐全、走到终年圆满结束；
## 劳动人口比例、服务业、联产品定价、种粮优先、民间出资从积蓄出、拉民心的政令清单与顾问建议。
extends JWTest

const SEED: int = 7
const SAVE: String = "user://jc_saves/_test_v2.json"


func _new(seed_v: int = SEED) -> JCGame:
	var g: JCGame = JCGame.new()
	g.autosave = false
	check(g.new_game(seed_v), "开局")
	return g


func _state_json(g: JCGame) -> String:
	return JSON.stringify(g.st.to_dict())


func test_warm_up_opens_in_spring_with_real_numbers() -> void:
	var g: JCGame = _new()
	eq_int(g.st.year(), 1600, "开局是 1600 年")
	eq_int(g.st.season(), 0, "开局是春季")
	ge_int(int(g.st.last.get("pop", 0)), 10_000_000, "第一季就有人口统计")
	ge_int(int(g.st.last.get("gdp", 0)), 1, "第一季就有产值")
	ge_int(g.st.points, 1, "第一季就有研究点")
	eq_int(g.st.chron.size(), 1, "预演不留纪事，只记开国一条")
	eq_int(g.st.annals.size(), 1, "国史第一页是开国")
	eq_str(String(g.st.annals[0]["key"]), "chron.milestone.founding", "开国这一条")


func test_quarters_conserve_money_and_are_deterministic() -> void:
	var a: JCGame = _new()
	var b: JCGame = _new()
	for i: int in 12:
		var ra: Dictionary = a.end_turn()
		var rb: Dictionary = b.end_turn()
		check(bool(ra.get("ok", false)), "第 %d 季结算通过自检（含钱的守恒）：%s" % [i, String(ra.get("reason", ""))])
		check(bool(rb.get("ok", false)), "对照局第 %d 季" % i)
	eq_str(_state_json(a), _state_json(b), "同一种子、同样的命令，状态逐位相同")


func test_undo_save_load_and_replay_after_content_change() -> void:
	var g: JCGame = _new()
	var pend0: int = 0
	for i: int in g.st.stack_count():
		pend0 += g.st.s_pending[i]
	var r: Dictionary = g.order({"kind": "build", "building": "market", "region": "zhongzhou", "owner": "gov"})
	check(bool(r.get("ok", false)), "下令营造集市：" + String(r.get("reason", "")))
	check(g.undo_last(), "本季可以撤回")
	var pend1: int = 0
	for i2: int in g.st.stack_count():
		pend1 += g.st.s_pending[i2]
	eq_int(pend1, pend0, "撤回后在建级数回到原样")
	eq_int(g.turn_orders().size(), 0, "撤回后本季没有命令")
	check(bool(g.order({"kind": "build", "building": "market", "region": "zhongzhou", "owner": "gov"}).get("ok", false)), "再下一次")
	check(bool(g.order({"kind": "research", "tech": "bookkeeping"}).get("ok", false)), "定研究方向")
	for q: int in 4:
		g.end_turn()
	check(g.save_to(SAVE), "存档")
	var h: JCGame = JCGame.new()
	h.autosave = false
	check(h.load_from(SAVE), "读档")
	eq_str(_state_json(h), _state_json(g), "读回来的状态与存档时一样")
	# 内容改过（指纹不符）：按命令簿从种子重演，结果必须一样
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	d["state"]["content_hash"] = "changed"
	var f: FileAccess = FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var k: JCGame = JCGame.new()
	k.autosave = false
	check(k.load_from(SAVE), "内容改过的旧档也能读")
	eq_str(k.last_error, "replayed", "走的是重演")
	eq_int(k.st.q, g.st.q, "重演到同一季")
	eq_str(_state_json(k), _state_json(g), "重演结果与原局逐位相同")
	DirAccess.remove_absolute(SAVE)


func test_steward_acts_with_reasons_that_have_text() -> void:
	var g: JCGame = _new()
	for d: String in JCSteward.DOMAINS:
		check(g.set_steward(d, JCSteward.AUTO), "托管 " + d + " 设为代办")
	for q: int in 8:
		check(bool(g.end_turn().get("ok", false)), "托管代办的季度照常结算")
	ge_int(g.steward.records.size(), 1, "八季里托管至少办了一件事")
	var bad: PackedStringArray = PackedStringArray()
	for rec: Dictionary in g.steward.records:
		var key: String = "jc." + String(rec["reason"])
		if not JwText.has(key):
			bad.append(key)
			continue
		if JcFmt.r(String(rec["reason"]), JcFmt.slots(g, rec.get("slots", {}))) == "":
			bad.append(key + "（槽位不全）")
	eq_int(bad.size(), 0, "每条托管记录的理由都能说成一句话：" + ", ".join(bad.slice(0, 5)))


func test_advisors_speak_plainly_and_their_orders_work() -> void:
	var g: JCGame = _new()
	g.end_turn()
	g.end_turn()
	var items: Array = g.advisors.items
	ge_int(items.size(), 1, "顾问有话说")
	for it: Dictionary in items:
		var sl: Dictionary = JcFmt.slots(g, it.get("slots", {}))
		check(JcFmt.r(String(it["title"]), sl) != "", "建议标题能渲染：" + String(it["title"]))
		check(JcFmt.r(String(it["body"]), sl) != "", "建议正文能渲染：" + String(it["body"]))
	for it2: Dictionary in items:
		if (it2.get("cmds", []) as Array).is_empty():
			continue
		var r: Dictionary = g.accept_advice(String(it2["id"]))
		if not bool(r.get("ok", false)):
			for x: Dictionary in r.get("results", []):
				check(JwText.has("jc." + String(x.get("reason", ""))), "被拒的原因有文案")
		else:
			check(g.advisors.find(String(it2["id"])).is_empty(), "办过的建议不再显示")
		break


## 活字印刷让印坊有了同时代的新做法：造出同地区两处旧印坊，检验合并改造。
func _printing_setup() -> Dictionary:
	var g: JCGame = _new()
	var t: int = int(g.ct.tidx.get("movable_type", -1))
	check(t >= 0, "有活字印刷这项科技")
	g.st.t_done[t] = 1
	var b: int = int(g.ct.bidx.get("printing", -1))
	var target: int = g.sim.inv.best_method(b)
	for i: int in g.st.stack_count():
		if g.st.s_b[i] == b and g.st.s_level[i] >= 4 and g.st.s_status[i] == JCState.ST_ACTIVE and g.st.s_m[i] != target:
			return {"g": g, "b": b, "i": i, "r": g.st.s_region[i], "owner": g.st.s_owner[i], "target": target}
	fail("找不到够大的旧印坊")
	return {}


func test_merge_needs_two_old_sites_and_charges_seventy_percent() -> void:
	var s: Dictionary = _printing_setup()
	if s.is_empty():
		return
	var g: JCGame = s["g"]
	var inv: JCInvest = g.sim.inv
	var b: int = s["b"]
	var r: int = s["r"]
	var owner: int = s["owner"]
	var own_s: String = "gov" if owner == JCContent.OWNER_GOV else "private"
	# 只有一处旧的：不能合并（否则等于七折单改）
	var solo: int = 0
	for i: int in g.st.stack_count():
		if g.st.s_b[i] == b and g.st.s_region[i] == r and g.st.s_owner[i] == owner and g.st.s_m[i] != int(s["target"]):
			solo += 1
	if solo == 1:
		eq_int(inv.consolidate_cost(b, r, owner), 0, "只有一处旧印坊时没有合并价")
	# 切出一处，凑成两处
	var row: int = inv.split_off(int(s["i"]), 2)
	check(row >= 0, "切出两级另成一处")
	var full: int = 0
	for i2: int in g.st.stack_count():
		if g.st.s_b[i2] == b and g.st.s_region[i2] == r and g.st.s_owner[i2] == owner and g.st.s_level[i2] > 0 \
				and g.st.s_m[i2] != int(s["target"]):
			full += inv.upgrade_cost(i2, int(s["target"]))
	var cost: int = inv.consolidate_cost(b, r, owner)
	in_range_int(cost, JCMath.mulppm(full, 700_000) - 2, JCMath.mulppm(full, 700_000) + 2, "合并改造按七折计价")
	var res: Dictionary = g.order({"kind": "consolidate", "building": "printing", "region": g.ct.r_id[r], "owner": own_s})
	check(bool(res.get("ok", false)), "合并改造受理：" + String(res.get("reason", "")))
	var keep: int = -1
	for i3: int in g.st.stack_count():
		if g.st.s_b[i3] == b and g.st.s_region[i3] == r and g.st.s_status[i3] == JCState.ST_UPGRADE:
			keep = i3
	check(keep >= 0, "合成的一处正在改造")
	eq_int(g.st.s_fund[keep], JCInvest.FUND_MERGE, "合并改造由官府出钱、记为七折")
	in_range_int(inv.job_total(keep), cost - 4, cost + 4, "实际要付的就是报的合并价")


func test_upgrade_can_take_a_slice() -> void:
	var s: Dictionary = _printing_setup()
	if s.is_empty():
		return
	var g: JCGame = s["g"]
	var i: int = s["i"]
	var lv0: int = g.st.s_level[i]
	var uid: int = g.st.s_uid[i]
	var res: Dictionary = g.order({"kind": "upgrade", "uid": uid, "method": g.ct.m_id[int(s["target"])], "levels": 1})
	check(bool(res.get("ok", false)), "只改一级：" + String(res.get("reason", "")))
	var j: int = g.st.stack_of_uid(uid)
	eq_int(g.st.s_level[j], lv0 - 1, "原处少了一级")
	eq_int(g.st.s_status[j], JCState.ST_ACTIVE, "原处照常开工")
	var upgrading: int = 0
	for k: int in g.st.stack_count():
		if g.st.s_status[k] == JCState.ST_UPGRADE:
			upgrading += g.st.s_level[k]
	eq_int(upgrading, 1, "只有切出的那一级在改")
	eq_int(JCInvest.upgrade_slice(1), 1, "一级整改")
	eq_int(JCInvest.upgrade_slice(4), 4, "四级整改")
	eq_int(JCInvest.upgrade_slice(5), 2, "五级先改两级")
	eq_int(JCInvest.upgrade_slice(40), 10, "四十级先改十级")
	check(JCInvest.upgrade_room({"3:1": [0, 40]}, 3, 1), "没有在改的：可以改")
	check_false(JCInvest.upgrade_room({"3:1": [10, 40]}, 3, 1), "已有四分之一在改：先等")


func test_engine_text_keys_all_exist() -> void:
	var rx: RegEx = RegEx.create_from_string("\"((?:reason|chron|stw|adv|warn|cause|need)\\.[a-z0-9_.]+)\"")
	var missing: PackedStringArray = PackedStringArray()
	var n: int = 0
	for dir: String in ["res://campaign/core", "res://campaign/app"]:
		var da: DirAccess = DirAccess.open(dir)
		for f: String in da.get_files():
			if not f.ends_with(".gd"):
				continue
			var src: String = FileAccess.get_file_as_string(dir + "/" + f)
			for m: RegExMatch in rx.search_all(src):
				var k: String = m.get_string(1)
				n += 1
				if k.begins_with("need."):
					for suf: String in [".t", ".b"]:
						if not JwText.has("jc." + k + suf):
							missing.append("jc." + k + suf)
				elif not JwText.has("jc." + k):
					missing.append("jc." + k)
	ge_int(n, 100, "扫到的引擎文案键")
	eq_int(missing.size(), 0, "引擎与应用层的每个键都有文案：" + ", ".join(missing.slice(0, 8)))


func test_game_completes_at_end_year() -> void:
	var g: JCGame = _new()
	g.st.q = (2000 - g.st.start_year) * 4 - 1
	var r: Dictionary = g.end_turn()
	check(bool(r.get("over", false)), "走到 2000 年春，这一局结束")
	eq_str(g.st.over_reason, "complete", "结束原因是四百年走完")
	check(JwText.has("jc.over.complete") and JwText.has("jc.go.explain.complete"), "终局有文案")


func test_work_share_falls_with_schooling_and_pensions() -> void:
	var g: JCGame = _new()
	var e: JCEconomy = g.sim.econ
	eq_int(e.participation_ppm(), 1_000_000, "第一时代出来干活的比例不打折")
	# 进入第三时代满 25 年：按 WORK_CUT_ERA3（眼下为 0，种地还靠人手）
	g.st.era = 3
	g.st.era_q[2] = 0
	g.st.era_q[3] = 0
	g.st.q = JCEconomy.ADOPT_Q + 10
	eq_int(e.participation_ppm(), 1_000_000 - JCEconomy.WORK_CUT_ERA3, "第三时代按设定的折扣（眼下不降）")
	# 第四时代满 25 年：再少 WORK_CUT_ERA4
	g.st.era = 4
	g.st.era_q[4] = 0
	g.st.q += 1
	eq_int(e.participation_ppm(), 1_000_000 - JCEconomy.WORK_CUT_ERA3 - JCEconomy.WORK_CUT_ERA4, "第四时代普及后再降一截")
	var c: int = int(g.ct.cidx.get("artisan", 1))
	eq_int(e.work_ppm(c), JCMath.mulppm(g.ct.c_work[c], e.participation_ppm()), "各阶层按同一折扣")


func test_service_trade_is_wired() -> void:
	var g: JCGame = _new()
	var gi: int = int(g.ct.gidx.get("services", -1))
	var b: int = int(g.ct.bidx.get("servicehall", -1))
	var n: int = int(g.ct.nidx.get("leisure", -1))
	check(gi >= 0 and b >= 0 and n >= 0, "服务、服务行、游乐与服务都在内容里")
	if gi < 0 or b < 0 or n < 0:
		return
	check(g.ct.n_goods[n].has(gi), "游乐与服务这项需要买的是服务")
	var makes: bool = false
	for m: int in g.ct.b_methods[b]:
		if g.ct.m_out_g[m].has(gi):
			makes = true
	check(makes, "服务行产出服务")
	eq_int(g.ct.n_era[n], 3, "第三时代起才有这项需要（开局的校准不受影响）")


## 一个做法出两样货、另一样已经由别的做法定了价（皂烛兼营的蜡烛按手工蜡烛定价）：按常价算，兼营不比老做法差。
## 原来肥皂只分到兼营 5% 的成本，兼营在常价下必亏，全国没人做肥皂，「皂」这项需要几百年都是 0%。
func test_joint_methods_pay_at_base_prices() -> void:
	var g: JCGame = _new()
	var ct: JCContent = g.ct
	var b: int = int(ct.bidx.get("chandlery", -1))
	var m0: int = int(ct.midx.get("candle_hand", -1))
	var m1: int = int(ct.midx.get("candle_soap", -1))
	check(b >= 0 and m0 >= 0 and m1 >= 0, "有皂烛坊的手工蜡烛与皂烛兼营两种做法")
	if b < 0 or m0 < 0 or m1 < 0:
		return
	for gid: String in ["candles", "soap", "cooking_oil"]:
		var gi: int = int(ct.gidx.get(gid, -1))
		if gi >= 0:
			g.st.price[gi] = ct.g_base[gi]
	for r: int in ct.r_n:
		ge_int(g.sim.inv.level_profit(b, m1, r), g.sim.inv.level_profit(b, m0, r),
				"%s：按常价，皂烛兼营每级的利润不低于手工蜡烛" % ct.r_id[r])


func test_staple_farms_get_peasants_first() -> void:
	var g: JCGame = _new()
	var e: JCEconomy = g.sim.econ
	var ct: JCContent = g.ct
	var paddy: int = int(ct.midx.get("paddy_rice", -1))
	var cotton: int = int(ct.midx.get("dry_cotton", -1))
	check(paddy >= 0 and cotton >= 0, "有水田种稻、旱地种棉两种做法")
	if paddy < 0 or cotton < 0:
		return
	check(e._staple_farm(paddy), "种稻是口粮田")
	check(not e._staple_farm(cotton), "种棉不是口粮田")
	# 各地农户只剩三成：口粮田的人手到位率不低于别的营生
	var P: int = int(ct.cidx.get("peasant", 0))
	for r: int in ct.r_n:
		g.st.pop[r * ct.c_n + P] = g.st.pop[r * ct.c_n + P] * 3 / 10
	check(bool(g.end_turn().get("ok", false)), "人手大缺的一季照常结算")
	var short_any: bool = false
	for r2: int in ct.r_n:
		ge_int(e.food_fill[r2], e.lab_fill[r2 * ct.c_n + P], "口粮田先补人手（%s）" % ct.r_id[r2])
		if e.lab_fill[r2 * ct.c_n + P] < 1_000_000:
			short_any = true
	check(short_any, "农户确实不够用（别的营生缺人）")


func test_private_investment_comes_out_of_savings() -> void:
	var g: JCGame = _new()
	var e: JCEconomy = g.sim.econ
	var C: int = g.ct.c_n
	var sav0: int = 0
	var inc0: int = 0
	var out0: int = 0
	for r: int in g.ct.r_n:
		for c: int in [e.CL_M, e.CL_G]:
			sav0 += g.st.savings[r * C + c]
			inc0 += e.inc[r * C + c]
			out0 += e.invest_out[r * C + c]
	e._private_pay(1_000_000)
	var sav1: int = 0
	var inc1: int = 0
	var out1: int = 0
	for r2: int in g.ct.r_n:
		for c2: int in [e.CL_M, e.CL_G]:
			sav1 += g.st.savings[r2 * C + c2]
			inc1 += e.inc[r2 * C + c2]
			out1 += e.invest_out[r2 * C + c2]
	eq_int(sav0 - sav1, 1_000_000, "民间出资从商贾、士绅的积蓄里扣")
	eq_int(inc1, inc0, "不算成当季收入的减项（不压日常开支）")
	eq_int(out1 - out0, 1_000_000, "出资额另有记录")


func test_support_decrees_are_ranked_and_offered() -> void:
	var g: JCGame = _new()
	var list: Array = g.analyst.support_decrees()
	ge_int(list.size(), 1, "开局就有能拉民心的政令可选")
	var seen_paid: bool = false
	for sd: Dictionary in list:
		check(int(sd["gain_ppm"]) > 0, "清单里的政令威信净涨：" + String(sd["decree"]))
		check(String(sd["decree"]) != "famine_relief", "赈济不在清单里（按有没有人挨饿开关）")
		check(bool(g.sim.cmd.check(sd["cmd"]).get("ok", false)), "清单里的政令眼下能施行：" + String(sd["decree"]))
		if int(sd["cost_q"]) > 0:
			seen_paid = true
		else:
			check(not seen_paid, "不花钱的排在花钱的前面")
	# 威信跌破五成：民政顾问推荐清单里的第一道，建议能渲染、能照办
	g.st.legitimacy = 400_000
	g.advisors.refresh(g.sim, g.analyst)
	var found: bool = false
	for it: Dictionary in g.advisors.items:
		if not String(it["id"]).begins_with("minzheng.support."):
			continue
		found = true
		var sl: Dictionary = JcFmt.slots(g, it.get("slots", {}))
		check(JcFmt.r(String(it["title"]), sl) != "" and JcFmt.r(String(it["body"]), sl) != "", "建议能渲染")
		ge_int((it.get("cmds", []) as Array).size(), 1, "建议带着能办的命令")
	check(found, "威信不到五成时，民政顾问推荐拉民心的政令")


## 国家形态的评语：用户举的两个例子——善政加君主集权是「宽容仁厚的帝国」，社会主义却严禁罢工是「堕落的工人国家」。
func test_regime_titles_follow_decrees() -> void:
	var g: JCGame = _new()
	var ct: JCContent = g.ct
	eq_str(String(g.analyst.regime_profile()["regime"]), "empire", "开局是君主集权")
	for id: String in ["ever_normal_granary", "promote_schools", "tax_remission"]:
		g.st.d_level[int(ct.didx[id])] = 1
		g.st.d_until[int(ct.didx[id])] = g.st.q + 8
	var rp: Dictionary = g.analyst.regime_profile()
	eq_str(String(rp["title"]), "jc.regime.title.empire.benevolent", "善政 + 君主集权")
	eq_str(JwText.t(String(rp["title"])), "宽容仁厚的帝国", "评语文字")
	g.st.era = 4
	g.st.d_level[int(ct.didx["regime"])] = 4
	g.st.d_level[int(ct.didx["labor_policy"])] = 0
	rp = g.analyst.regime_profile()
	eq_str(String(rp["regime"]), "socialist", "改成社会主义")
	eq_str(JwText.t(String(rp["title"])), "堕落的工人国家", "社会主义却严禁罢工")
	eq_str(String(rp["tone"]), "harsh", "徽记与颜色跟着评语按严苛算")
	g.st.d_level[int(ct.didx["labor_policy"])] = 2
	rp = g.analyst.regime_profile()
	check(String(rp["title"]) != "jc.regime.title.socialist.harsh", "工会合法就不是「堕落」")
