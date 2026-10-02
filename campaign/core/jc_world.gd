## v2 世界与进程（docs/57 §7—§10）：研究、时代、伙伴进程、地标、事件、政令期限、限时修正、常平仓与杂项政令。
class_name JCWorld
extends RefCounted

const PPM: int = 1_000_000
const MAX_NEW_EVENTS: int = 2
const EVENT_WINDOW_Q: int = 2

var ct: JCContent
var st: JCState
var mods: JCMods
var econ: JCEconomy
var soc: JCSociety
var rng: JCRng


func setup(p_ct: JCContent, p_st: JCState, p_mods: JCMods, p_econ: JCEconomy, p_soc: JCSociety, p_rng: JCRng) -> void:
	ct = p_ct
	st = p_st
	mods = p_mods
	econ = p_econ
	soc = p_soc
	rng = p_rng


# ════════════════════════════ 研究 ════════════════════════════════════════
## 每季研究点：读书人（士绅）、商贾、识字工匠 + 书院等设施 + 学位。
func research_points() -> int:
	var C: int = ct.c_n
	var pts: int = 0
	for r: int in ct.r_n:
		pts += JCMath.muldiv(st.pop[r * C + econ.CL_G], 400, PPM)
		pts += JCMath.muldiv(st.pop[r * C + econ.CL_M], 100, PPM)
		pts += JCMath.muldiv(JCMath.mulppm(st.pop[r * C + econ.CL_A], st.literacy[r]), 100, PPM)
		@warning_ignore("integer_division")
		pts += econ.edu_seats[r] / 3000
	pts += econ.research_bld
	return JCMath.mulppm(pts, mods.mult_ppm("research_speed"))


## 伙伴 p 是否掌握科技 t（发展度越高掌握越多，按 tech_order 的顺序）。
func partner_knows(p: int, t: int) -> bool:
	var dev: int = st.p_dev[p]
	@warning_ignore("integer_division")
	var e: int = dev / PPM
	var frac: int = dev % PPM
	var te: int = ct.t_era[t]
	if te < e:
		return true
	if te > e:
		return false
	var order: PackedInt64Array = ct.tech_order.get(te, PackedInt64Array())
	var idx: int = order.find(t)
	if idx < 0:
		return false
	return idx < JCMath.muldiv(order.size(), frac, PPM)


## 国内背景加速（ppm，上限 50%）：相关建筑的在用级数。
func bg_domestic(t: int) -> int:
	var lv: int = 0
	var bg: PackedInt64Array = ct.t_bg[t]
	for i: int in st.stack_count():
		if bg.has(st.s_b[i]) and st.s_status[i] == JCState.ST_ACTIVE:
			lv += st.s_level[i]
	return mini(500_000, lv * 12_500)


## 海外背景加速（ppm，上限 100% × 修正）：与掌握该科技的伙伴的贸易占比。
func bg_foreign(t: int) -> int:
	var tot: int = 0
	var know: int = 0
	for p: int in ct.partners.size():
		if st.p_active[p] != 1:
			continue
		var v: int = st.p_exp[p] + st.p_imp[p]
		tot += v
		if partner_knows(p, t):
			know += v
	if tot <= 0:
		return 0
	var share: int = JCMath.ratio_ppm(know, tot)
	return JCMath.mulppm(mini(PPM, share * 2), mods.mult_ppm("research_foreign"))


func tech_cost(t: int) -> int:
	var c: int = ct.t_cost[t]
	var ahead: int = ct.t_era[t] - st.era
	for i: int in maxi(0, ahead):
		c = c * 3 / 2
	return c


func tech_available(t: int) -> bool:
	if st.t_done[t] == 1:
		return false
	for p: int in ct.t_prereq[t]:
		if p >= 0 and st.t_done[p] != 1:
			return false
	return ct.t_era[t] <= st.era + 1


func research() -> void:
	var pts: int = research_points()
	st.points = pts
	var t: int = st.focus
	if t < 0 or st.t_done[t] == 1 or not tech_available(t):
		st.rpool += pts
		st.focus = -1 if (t >= 0 and st.t_done[t] == 1) else st.focus
		return
	var speed: int = JCMath.mulppm(pts + st.rpool, PPM + bg_domestic(t) + bg_foreign(t))
	st.rpool = 0
	st.t_prog[t] += speed
	if st.t_prog[t] >= tech_cost(t):
		st.t_done[t] = 1
		var spill: int = st.t_prog[t] - tech_cost(t)
		st.t_prog[t] = tech_cost(t)
		st.rpool += spill
		st.focus = -1
		st.note("research", "chron.tech_done", {"tech": ct.t_id[t]})


# ════════════════════════════ 时代 ════════════════════════════════════════
## 进入下一时代还差什么：{techs: [缺的科技], buildings: {类型: [已有, 需要]}, social: {key: [现值, 需要]}, ok}
func era_gap_report() -> Dictionary:
	var out: Dictionary = {"ok": false, "techs": [], "buildings": {}, "social": {}}
	if st.era >= ct.eras.size():
		return out
	var need: Dictionary = ct.eras[st.era].get("need", {})
	var ok: bool = true
	for tid: Variant in need.get("techs", []):
		var t: int = int(ct.tidx.get(String(tid), -1))
		if t >= 0 and st.t_done[t] != 1:
			out["techs"].append(String(tid))
			ok = false
	var bl: Dictionary = need.get("buildings", {})
	for bk: Variant in bl.keys():
		var b: int = int(ct.bidx.get(String(bk), -1))
		var have: int = 0
		for i: int in st.stack_count():
			if st.s_b[i] == b and st.s_status[i] != JCState.ST_NEW:
				have += st.s_level[i]
		out["buildings"][String(bk)] = [have, int(bl[bk])]
		if have < int(bl[bk]):
			ok = false
	var so: Dictionary = need.get("social", {})
	for sk: Variant in so.keys():
		var want: int = int(round(float(so[sk]) * PPM))
		var cur: int = social_value(String(sk))
		out["social"][String(sk)] = [cur, want]
		if cur < want:
			ok = false
	out["ok"] = ok
	return out


func social_value(key: String) -> int:
	var C: int = ct.c_n
	match key:
		"literacy":
			var w: int = 0
			var acc: int = 0
			for r: int in ct.r_n:
				var p: int = soc.region_pop(r) / 1000
				acc += st.literacy[r] * p
				w += p
			return acc / maxi(w, 1)
		"urban":
			var urb: int = 0
			var tot: int = 0
			for r2: int in ct.r_n:
				urb += st.pop[r2 * C + econ.CL_A] + st.pop[r2 * C + econ.CL_M]
				tot += soc.region_pop(r2)
			return JCMath.ratio_ppm(urb, maxi(tot, 1))
	return 0


func check_era() -> void:
	if st.era >= 4:
		return
	var rep: Dictionary = era_gap_report()
	if not rep["ok"]:
		return
	st.era += 1
	st.era_q[st.era] = st.q
	var leading: bool = st.world_era < st.era
	if leading:
		st.led[st.era] = 1
		st.prestige += 20
		add_timed("talent", "", 100, 20)
	st.note("era", "chron.era_enter", {"era": st.era, "leading": leading})


# ════════════════════════════ 世界进程 ════════════════════════════════════
func world_year() -> void:
	if st.season() != 0:
		return
	var decade: bool = st.year() % 10 == 0
	var frontier: int = 0
	for p: int in ct.partners.size():
		if decade or st.p_noise[p] <= 0:
			st.p_noise[p] = clampi(PPM + rng.gauss_ppm(250_000), 500_000, 1_500_000)
		# 还没登场的伙伴不计进程（登场时按内容给的发展度出场）
		if st.p_active[p] != 1:
			continue
		var pd: Dictionary = ct.partners[p]
		var rate: int = int(pd.get("rate_ppm", 8000))
		@warning_ignore("integer_division")
		var pe: int = st.p_dev[p] / PPM
		rate = JCMath.mulppm(rate, PPM + (pe - 1) * 150_000)
		rate = JCMath.mulppm(rate, st.p_noise[p])
		frontier = maxi(frontier, st.p_dev[p])
		st.p_dev[p] += rate
	# 落后伙伴受前沿带动（只算已登场的）
	for p2: int in ct.partners.size():
		if st.p_active[p2] != 1:
			continue
		if frontier - st.p_dev[p2] > 500_000:
			st.p_dev[p2] += JCMath.mulppm(int(ct.partners[p2].get("rate_ppm", 8000)), 200_000)
		# 本国领先时，贸易伙伴也受益一点
		if st.era * PPM > st.p_dev[p2] and st.p_active[p2] == 1:
			st.p_dev[p2] += 1500
	var wmax: int = 1
	for p3: int in ct.partners.size():
		if st.p_active[p3] == 1 or int(ct.partners[p3].get("appear_era", 1)) <= 1:
			@warning_ignore("integer_division")
			wmax = maxi(wmax, mini(4, st.p_dev[p3] / PPM))
	while st.world_era < wmax:
		st.world_era += 1
		st.world_era_q[st.world_era] = st.q
		st.note("era", "chron.world_era", {"era": st.world_era})
		for p4: int in ct.partners.size():
			if st.p_active[p4] == 0 and int(ct.partners[p4].get("appear_era", 1)) <= st.world_era:
				st.p_active[p4] = 1
				st.note("trade", "chron.partner_appear", {"partner": String(ct.partners[p4]["id"])})
	# 关系缓慢回到基线（商约 +10，修正另加）
	for p5: int in ct.partners.size():
		var base: int = int(ct.partners[p5].get("relation", 0)) + (10 if st.p_treaty[p5] == 1 else 0)
		base += mods.sum("relation_all") / 100 + mods.scoped("relation", String(ct.partners[p5]["id"])) / 100
		base -= maxi(0, econ.partner_era(p5) - st.era) * 5
		st.p_rel[p5] = JCMath.approach(st.p_rel[p5], clampi(base, -100, 100), 300_000)
	# 国望每年自然向 0 回归 1 点（战败、条约留下的屈辱也会慢慢淡去）
	if st.prestige > 0:
		st.prestige -= 1
	elif st.prestige < 0:
		st.prestige += 1


# ════════════════════════════ 地标 ════════════════════════════════════════
## 地标能不能开工：返回原因键（空串 = 可以），full 表示按完整版建。
func landmark_check(l: int, full: bool) -> String:
	if st.l_state[l] != 0:
		return "reason.landmark_taken"
	var ld: Dictionary = ct.landmarks[l]
	var era: int = int(ld["era"])
	if String(ld.get("kind", "")) == "achievement":
		var need: Dictionary = ld.get("need", {})
		for tid: Variant in need.get("techs", []):
			var t: int = int(ct.tidx.get(String(tid), -1))
			if t >= 0 and st.t_done[t] != 1:
				return "reason.landmark_need_tech"
		if need.has("literacy") and social_value("literacy") < int(round(float(need["literacy"]) * PPM)):
			return "reason.landmark_need_literacy"
		if need.has("tech_count"):
			var n: int = 0
			for t2: int in ct.t_n:
				n += st.t_done[t2]
			if n < int(need["tech_count"]):
				return "reason.landmark_need_techs"
		var bl: Dictionary = need.get("buildings", {})
		for bk: Variant in bl.keys():
			var b: int = int(ct.bidx.get(String(bk), -1))
			var have: int = 0
			for i: int in st.stack_count():
				if st.s_b[i] == b:
					have += st.s_level[i]
			if have < int(bl[bk]):
				return "reason.landmark_need_buildings"
		return ""
	if st.era < era:
		return "reason.landmark_need_era"
	if full:
		if era >= st.led.size() or st.led[era] != 1:
			return "reason.landmark_not_leading"
		if st.lead_pick[era] >= 0 and st.lead_pick[era] != l:
			return "reason.landmark_full_used"
	return ""


# ════════════════════════════ 事件 ════════════════════════════════════════
func metric(name: String, arg: String, r: int) -> float:
	var C: int = ct.c_n
	match name:
		"harvest":
			return float(st.harvest[r]) / PPM
		"flood":
			return float(st.flood[r])
		"relation":
			if arg == "any":
				var lo: int = 100
				for p: int in ct.partners.size():
					if st.p_active[p] == 1:
						lo = mini(lo, st.p_rel[p])
				return float(lo)
			var pi: int = int(ct.pidx.get(arg, -1))
			return float(st.p_rel[pi]) if pi >= 0 else 0.0
		"unemployment":
			var c: int = int(ct.cidx.get(arg, 0))
			var k: int = r * C + c
			var sup: int = JCMath.mulppm(st.pop[k], econ.work_ppm(c))
			return 0.0 if sup <= 0 else float(maxi(0, sup - st.employed[k])) / sup
		"literacy":
			return float(st.literacy[r]) / PPM
		"staple_sat":
			var n: int = int(ct.nidx.get("staple", 0))
			var acc: int = 0
			var w: int = 0
			for c2: int in C:
				var k2: int = r * C + c2
				acc += st.sat[k2 * ct.n_n + n] * (st.pop[k2] / 1000)
				w += st.pop[k2] / 1000
			return float(acc) / maxi(w, 1) / PPM
		"sanitation":
			return float(mini(PPM, JCMath.ratio_ppm(econ.sanit_cov[r], maxi(soc.region_pop(r), 1)))) / PPM
		"region":
			return 1.0 if ct.r_id[r] == arg else 0.0
		"unrest":
			if arg != "" and arg != "all" and ct.cidx.has(arg):
				return float(st.unrest[r * C + int(ct.cidx[arg])]) / PPM
			var acc2: int = 0
			var w2: int = 0
			for c3: int in C:
				var k3: int = r * C + c3
				acc2 += st.unrest[k3] * (st.pop[k3] / 1000)
				w2 += st.pop[k3] / 1000
			return float(acc2) / maxi(w2, 1) / PPM
		"silver_flow":
			return float(st.last.get("silver_flow", 0))
		"defense":
			return float(JCMath.mulppm(st.budget[JCState.BUD_ARMY], st.gov_fund)) / PPM
		"building":
			var parts: PackedStringArray = arg.split(":")
			var b: int = int(ct.bidx.get(parts[0], -1))
			var n2: int = 0
			for i: int in st.stack_count():
				if st.s_b[i] == b and st.s_status[i] != JCState.ST_NEW:
					if parts.size() > 1 and ct.m_id[st.s_m[i]].find(parts[1]) < 0:
						continue
					n2 += st.s_level[i]
			return float(n2)
		"tech":
			var t: int = int(ct.tidx.get(arg, -1))
			return float(st.t_done[t]) if t >= 0 else 0.0
		"price_ratio":
			var g: int = int(ct.gidx.get(arg, -1))
			return float(st.price[g]) / maxi(ct.g_base[g], 1) if g >= 0 else 1.0
		"debt_ratio":
			var rv: int = 0
			for x: int in st.rev:
				rv += x
			return float(st.debt) / maxi(rv * 4, 1)
		"year":
			return float(st.year())
	return 0.0


func _cond_ok(cond: Array, r: int) -> bool:
	var name: String = String(cond[0])
	var op: String = String(cond[1])
	var arg: String = String(cond[3]) if cond.size() > 3 else ""
	if name == "region":
		arg = String(cond[2])
		return metric("region", arg, r) > 0.5
	var v: float = metric(name, arg, r)
	var x: float = float(cond[2])
	match op:
		"<":
			return v < x
		">":
			return v > x
		"=":
			return absf(v - x) < 0.0001
	return false


func events() -> void:
	# 过期未决：按最后一个选项（通常是「听其自然」）处理
	var keep: Array = []
	for pe: Dictionary in st.pend:
		if st.q > int(pe["until"]):
			var e: int = int(pe["e"])
			var opts: Array = ct.events[e].get("options", [])
			apply_event_option(e, int(pe["r"]), opts.size() - 1, true)
		else:
			keep.append(pe)
	st.pend = keep
	var fired: int = 0
	for e2: int in ct.events.size():
		if fired >= MAX_NEW_EVENTS:
			break
		var ed: Dictionary = ct.events[e2]
		if st.era < int(ed["era"]) or st.era > int(ed["era_end"]) or st.q < st.e_cool[e2]:
			continue
		if _pending_has(e2):
			continue
		var when: Array = ed.get("when", [])
		var cand: PackedInt64Array = PackedInt64Array()
		if String(ed.get("region", "none")) == "pick":
			for r: int in ct.r_n:
				var ok: bool = true
				for c: Variant in when:
					if not _cond_ok(c, r):
						ok = false
						break
				if ok:
					cand.append(r)
		else:
			var ok2: bool = true
			for c2: Variant in when:
				if not _cond_ok(c2, int(ct.ridx.get("zhongzhou", 0))):
					ok2 = false
					break
			if ok2:
				cand.append(-1)
		if cand.is_empty():
			continue
		if not rng.chance_ppm(int(ed.get("chance_ppm", 50000))):
			continue
		var rr: int = cand[rng.below(cand.size())]
		st.pend.append({"e": e2, "r": rr, "until": st.q + EVENT_WINDOW_Q})
		st.e_cool[e2] = st.q + int(ed.get("cooldown", 16))
		st.note("event", "chron.event_fired", {"event": String(ed["id"]), "region": ct.r_id[rr] if rr >= 0 else ""})
		fired += 1


func _pending_has(e: int) -> bool:
	for pe: Dictionary in st.pend:
		if int(pe["e"]) == e:
			return true
	return false


## 回应事件：花钱、加限时修正、改民心。auto 表示过期由系统代选。
func apply_event_option(e: int, r: int, opt: int, auto: bool) -> void:
	var ed: Dictionary = ct.events[e]
	var opts: Array = ed.get("options", [])
	if opt < 0 or opt >= opts.size():
		return
	var o: Dictionary = opts[opt]
	var cost: int = int(o.get("cost_li", 0))
	if cost > 0:
		st.treasury -= cost
		st.exp[JCState.EXP_EVENT] += cost
		# 花出去的钱：灾区农户六成、工匠四成
		var rr: int = r if r >= 0 else int(ct.ridx.get("zhongzhou", 0))
		var C: int = ct.c_n
		var a: int = JCMath.mulppm(cost, 600_000)
		st.savings[rr * C + econ.CL_P] += a
		st.savings[rr * C + econ.CL_A] += cost - a
	var dur: int = int(o.get("duration", 8))
	var regional: PackedStringArray = ["farm_yield", "unrest", "mortality", "disaster_cut", "land_tax_eff"]
	for m: Dictionary in o.get("effects", []):
		var target: String = String(m.get("target", ""))
		var scope: String = String(m.get("scope", ""))
		if scope == "" and r >= 0 and regional.has(target):
			scope = ct.r_id[r]
		add_timed(target, scope, int(round(float(m.get("value", 0)) * 100.0)), dur)
	var sup: Dictionary = o.get("support", {})
	for ck: Variant in sup.keys():
		add_timed("support", String(ck), int(sup[ck]) * 100, 8)
	st.note("event", "chron.event_answered", {"event": String(ed["id"]), "option": opt, "auto": auto,
			"region": ct.r_id[r] if r >= 0 else ""})


func add_timed(target: String, scope: String, value_hundredths: int, quarters: int) -> void:
	st.tm_target.append(target)
	st.tm_scope.append(scope)
	st.tm_value.append(value_hundredths)
	st.tm_until.append(st.q + quarters)


func expire_timed() -> void:
	var t: PackedStringArray = PackedStringArray()
	var s: PackedStringArray = PackedStringArray()
	var v: PackedInt64Array = PackedInt64Array()
	var u: PackedInt64Array = PackedInt64Array()
	for i: int in st.tm_target.size():
		if st.tm_until[i] > st.q:
			t.append(st.tm_target[i])
			s.append(st.tm_scope[i])
			v.append(st.tm_value[i])
			u.append(st.tm_until[i])
	st.tm_target = t
	st.tm_scope = s
	st.tm_value = v
	st.tm_until = u


# ════════════════════════════ 政令期限与杂项效果 ══════════════════════════
func decree_timers() -> void:
	for d: int in ct.decrees.size():
		var dd: Dictionary = ct.decrees[d]
		if String(dd.get("kind", "")) == "campaign" and st.d_level[d] > 0 and st.q >= st.d_until[d]:
			st.d_level[d] = 0
			st.d_cool[d] = st.q + int(dd.get("cooldown", 8))
			st.note("decree", "chron.campaign_end", {"decree": String(dd["id"])})


## 经济结算之前：常平仓开仓、垦荒。
func pre_economy() -> void:
	var ri: int = int(ct.gidx.get("rice", -1))
	var gr: int = int(ct.gidx.get("grain", -1))
	if mods.flag("granary_ops") and st.gstore > 0 and ri >= 0 and gr >= 0:
		var hi: bool = st.price[ri] > JCMath.mulppm(ct.g_base[ri], 1_150_000) or st.price[gr] > JCMath.mulppm(ct.g_base[gr], 1_150_000)
		if hi:
			var rel: int = mini(st.gstore, JCMath.mulppm(st.gstore, 400_000))
			@warning_ignore("integer_division")
			st.stock[ri] += rel / 2
			st.stock[gr] += rel - rel / 2
			st.gstore -= rel
			st.note("decree", "chron.granary_release", {"qty": rel})
	if mods.flag("reclaim"):
		var dry: int = JCContent.LAND_TYPES.find("dry")
		var forest: int = JCContent.LAND_TYPES.find("forest")
		for r: int in ct.r_n:
			var fk: int = r * JCContent.LT_N + forest
			# 刚读档、经济还没结算过一季时，用地表是空的：按各建筑的级数现算
			var used: int = econ.land_used[fk] if econ.land_used.size() > fk else _land_used_now(r, forest)
			if st.land[fk] > used + 1:
				st.land[fk] -= 1
				st.land[r * JCContent.LT_N + dry] += 1


## 某地区某类地眼下用了几级（与经济结算里的算法相同：所有在册的级数，不论开工与否）。
func _land_used_now(r: int, lt: int) -> int:
	var n: int = 0
	for i: int in st.stack_count():
		if st.s_region[i] == r and ct.b_land[st.s_b[i]] == lt and st.s_level[i] > 0:
			n += st.s_level[i]
	return n


## 经济结算之后：常平仓收储、捐纳、所得税。
func post_economy() -> void:
	var C: int = ct.c_n
	var ri: int = int(ct.gidx.get("rice", -1))
	var gr: int = int(ct.gidx.get("grain", -1))
	if mods.flag("granary_ops") and ri >= 0 and gr >= 0 and econ.grain_cap > st.gstore:
		var lo: bool = st.price[ri] < JCMath.mulppm(ct.g_base[ri], 950_000) and st.price[gr] < JCMath.mulppm(ct.g_base[gr], 950_000)
		if lo:
			var room: int = econ.grain_cap - st.gstore
			var buy: int = mini(room, JCMath.mulppm(st.stock[ri] + st.stock[gr], 300_000))
			@warning_ignore("integer_division")
			var br: int = mini(st.stock[ri], buy / 2)
			var bg: int = mini(st.stock[gr], buy - br)
			var cost: int = JCMath.value(br, st.price[ri]) + JCMath.value(bg, st.price[gr])
			if cost > 0 and st.treasury > cost:
				st.stock[ri] -= br
				st.stock[gr] -= bg
				st.gstore += br + bg
				st.treasury -= cost
				st.exp[JCState.EXP_RELIEF] += cost
				# 买粮的钱归各地农户（按人口）
				var w: PackedInt64Array = JCMath.zeros(ct.r_n)
				for r: int in ct.r_n:
					w[r] = st.pop[r * C + econ.CL_P]
				var parts: PackedInt64Array = JCMath.split(cost, w)
				for r2: int in ct.r_n:
					st.savings[r2 * C + econ.CL_P] += parts[r2]
	if mods.flag("title_sales"):
		var take: int = 0
		for r3: int in ct.r_n:
			for c: int in [econ.CL_M, econ.CL_G]:
				var k: int = r3 * C + c
				var t: int = JCMath.mulppm(maxi(0, st.savings[k]), 20_000)
				st.savings[k] -= t
				take += t
		st.treasury += take
		st.rev[JCState.REV_OTHER] += take
	if mods.flag("income_tax"):
		var tax: int = 0
		for r4: int in ct.r_n:
			for c2: int in [econ.CL_M, econ.CL_G]:
				var k2: int = r4 * C + c2
				var t2: int = JCMath.mulppm(JCMath.mulppm(maxi(0, st.income[k2]), 100_000), st.coll_eff)
				t2 = mini(t2, maxi(0, st.savings[k2]))
				st.savings[k2] -= t2
				tax += t2
		st.treasury += tax
		st.rev[JCState.REV_INCOME] += tax
	# 人才流入（引领之后二十季）：每季迁入少量士绅与工匠
	if mods.flag("talent"):
		for r5: int in ct.r_n:
			st.pop[r5 * C + econ.CL_G] += JCMath.mulppm(st.pop[r5 * C + econ.CL_G], 1_500)
			st.pop[r5 * C + econ.CL_A] += JCMath.mulppm(st.pop[r5 * C + econ.CL_A], 1_000)
