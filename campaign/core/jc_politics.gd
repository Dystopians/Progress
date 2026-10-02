## v2 政治局势（docs/61）：
##   改革局势：玩家在「政治改革」里推行，几年推完；拥护与反对的阶层的民心决定推得快慢，三成五、七成各有一个关口。
##   革命风潮：第三时代起，威信低、某阶层怨气大、政体落后于时代时，革命压力累积，满了就爆发；可镇压、让步、收买、坐视。
##   列强叩关：世界进入第三时代起，本国落后、兵弱、闭关时，列强压力累积，满了就兵临城下；可抵抗（转成战事）、议和（不平等条约）、变法图强。
##   经济危机：第三时代起，偶尔爆发（经济过热时更容易），居民日用开支与民间投资大减，几季后复苏；可放任、以工代赈、保护关税。
## 政体是「政体」政令的档位，只在这里改（改革成功、让步、革命、战败、割据、收回主权）。
## 待决的关口两季内不选，按默认选项办（托管的事件领域代办时由 JCSteward 先选）。
class_name JCPolitics
extends RefCounted

const PPM: int = 1_000_000
## 局势的种类（sit_cool 的下标）；战事算在列强叩关里
const KINDS: PackedStringArray = ["reform", "revolution", "invasion", "depression"]
const ASK_Q: int = 2
const REFORM_COOL_Q: int = 8
const REV_COOL_Q: int = 24
const FOR_COOL_Q: int = 40
const WAR_MAX_Q: int = 12
const TREATY_Q: int = 80
const TREATY_CUSTOMS_PPM: int = 20_000
const SUPPORT_Q: int = 12

var ct: JCContent
var st: JCState
var mods: JCMods
var econ: JCEconomy
var soc: JCSociety
var world: JCWorld
var rng: JCRng


func setup(p_ct: JCContent, p_st: JCState, p_mods: JCMods, p_econ: JCEconomy, p_soc: JCSociety, p_world: JCWorld,
		p_rng: JCRng) -> void:
	ct = p_ct
	st = p_st
	mods = p_mods
	econ = p_econ
	soc = p_soc
	world = p_world
	rng = p_rng


# ════════════════════════════ 查询 ════════════════════════════════════════
func regime() -> int:
	var d: int = int(ct.didx.get("regime", -1))
	return st.d_level[d] if d >= 0 else 0


func regime_id(idx: int = -1) -> String:
	var r: int = regime() if idx < 0 else idx
	return String(ct.regimes[r]["id"]) if r >= 0 and r < ct.regimes.size() else "empire"


func find(sid: int) -> int:
	for i: int in st.sit.size():
		if int((st.sit[i] as Dictionary).get("sid", -1)) == sid:
			return i
	return -1


func active(kind: String) -> Dictionary:
	for s: Variant in st.sit:
		var sd: Dictionary = s
		var k: String = String(sd.get("k", ""))
		if k == kind or (kind == "invasion" and k == "war"):
			return sd
	return {}


## 改革的目标政体（按时代、或回到受制之前）。找不到返回 -1。
func reform_target(rf: Dictionary) -> int:
	var to: Dictionary = rf.get("to", {})
	var id: String = ""
	if to.has("any"):
		id = String(to["any"])
	else:
		id = String(to.get(str(clampi(st.era, 1, 4)), to.get("3", "")))
	if id == "_prev":
		return clampi(st.reg_prev, 0, ct.regimes.size() - 1)
	return int(ct.regidx.get(id, -1))


## 某项改革眼下能不能推：返回原因键（空串 = 可以）。
func reform_check(id: String) -> String:
	var rf_i: int = int(ct.refidx.get(id, -1))
	if rf_i < 0:
		return "reason.bad_command"
	var rf: Dictionary = ct.reforms[rf_i]
	if not (rf.get("frm", []) as Array).has(regime_id()):
		return "reason.reform_wrong_regime"
	if st.era < int(rf.get("era", 1)):
		return "reason.era_too_early"
	var tech: String = String(rf.get("tech", ""))
	if tech != "" and st.t_done[int(ct.tidx.get(tech, 0))] != 1:
		return "reason.tech_missing"
	if not active("reform").is_empty():
		return "reason.reform_busy"
	if st.q < cool_until("reform"):
		return "reason.cooling"
	var to: int = reform_target(rf)
	if to < 0 or to == regime():
		return "reason.no_change"
	if st.treasury < int(rf.get("cost_start_li", 0)):
		return "reason.no_money"
	return ""


## 上一季的财政收入（给「花掉几成收入」的选项定价）。
func revenue_q() -> int:
	return maxi(1, int(st.last.get("gov_rev", 0)))


## 兵力（ppm）：军饷拨款 × 国家开支到位率，最多 1.5。
func army() -> int:
	return clampi(JCMath.mulppm(st.budget[JCState.BUD_ARMY], st.gov_fund), 0, 1_500_000)


# ════════════════════════════ 命令 ════════════════════════════════════════
func start_reform(id: String, doit: bool, source: String = "player") -> Dictionary:
	var why: String = reform_check(id)
	if why != "":
		return {"ok": false, "reason": why}
	var rf: Dictionary = ct.reforms[int(ct.refidx[id])]
	var cost: int = int(rf.get("cost_start_li", 0))
	if doit:
		_spend(cost)
		var s: Dictionary = _new_sit("reform")
		s["id"] = id
		s["to"] = reform_target(rf)
		s["p"] = 0
		s["stage"] = 0
		st.sit.append(s)
		st.note("politics", "chron.reform_start", {"reform": id, "regime": regime_id(int(s["to"])), "source": source})
	return {"ok": true, "reason": "", "cost": cost}


func abandon(sid: int, doit: bool) -> Dictionary:
	var i: int = find(sid)
	if i < 0 or String((st.sit[i] as Dictionary).get("k", "")) != "reform":
		return {"ok": false, "reason": "reason.bad_command"}
	if doit:
		var s: Dictionary = st.sit[i]
		var rf: Dictionary = ct.reforms[int(ct.refidx.get(String(s["id"]), 0))]
		for c: Variant in rf.get("pro", []):
			_timed_support(String(c), -5)
		st.sit.remove_at(i)
		_set_cool("reform", REFORM_COOL_Q)
		st.note("politics", "chron.reform_abandoned", {"reform": String(s["id"])})
	return {"ok": true, "reason": ""}


## 回应某个局势的待决关口。
func answer(sid: int, opt: String, doit: bool, auto: bool = false, source: String = "player") -> Dictionary:
	var i: int = find(sid)
	if i < 0:
		return {"ok": false, "reason": "reason.bad_command"}
	var s: Dictionary = st.sit[i]
	var ask: Dictionary = s.get("ask", {})
	if ask.is_empty():
		return {"ok": false, "reason": "reason.nothing_to_answer"}
	var o: Dictionary = option_def(String(ask.get("set", "")), opt)
	if o.is_empty():
		return {"ok": false, "reason": "reason.bad_command"}
	var cost: int = option_cost(o)
	if not auto and cost > st.treasury:
		return {"ok": false, "reason": "reason.no_money", "cost": cost}
	if doit:
		_spend(cost)
		s["ask"] = {}
		st.note("politics", "chron.situation_answer", {"sit": String(s.get("k", "")), "set": String(ask.get("set", "")),
				"opt": opt, "auto": auto, "source": source, "reform": String(s.get("id", ""))})
		_apply(i, String(ask.get("set", "")), opt, o)
	return {"ok": true, "reason": "", "cost": cost}


## 关口的选项集合：「stage:<关口 id>」或局势种类名。
func option_set(set_id: String) -> Array:
	if set_id.begins_with("stage:"):
		var sid: String = set_id.substr(6)
		for sg: Variant in ct.reform_stages:
			if String((sg as Dictionary)["id"]) == sid:
				return (sg as Dictionary).get("options", [])
		return []
	return (ct.crises.get(set_id, {}) as Dictionary).get("options", [])


func option_def(set_id: String, opt: String) -> Dictionary:
	for o: Variant in option_set(set_id):
		if String((o as Dictionary)["id"]) == opt:
			return o
	return {}


func option_default(set_id: String) -> String:
	if set_id.begins_with("stage:"):
		var sid: String = set_id.substr(6)
		for sg: Variant in ct.reform_stages:
			if String((sg as Dictionary)["id"]) == sid:
				return String((sg as Dictionary).get("default", ""))
		return ""
	return String((ct.crises.get(set_id, {}) as Dictionary).get("default", ""))


func option_cost(o: Dictionary) -> int:
	return JCMath.mulppm(revenue_q(), int(o.get("cost_rev", 0)))


## 以工代赈每季花多少（上季财政收入的几成）。
func works_per_q() -> int:
	return JCMath.mulppm(revenue_q(), int(option_def("depression", "works").get("works_rev", 0)))


# ════════════════════════════ 每季 ════════════════════════════════════════
func step() -> void:
	_expire_asks()
	var i: int = 0
	while i < st.sit.size():
		if _advance(i):
			i += 1
	_pressures()
	_triggers()


## 两季内没选的关口，按默认选项办。
func _expire_asks() -> void:
	for s: Variant in st.sit.duplicate():
		var sd: Dictionary = s
		var ask: Dictionary = sd.get("ask", {})
		if ask.is_empty() or st.q < int(ask.get("until", 0)):
			continue
		var set_id: String = String(ask.get("set", ""))
		answer(int(sd["sid"]), option_default(set_id), true, true)


## 推进第 i 个局势；局势结束（已移除）时返回 false。
func _advance(i: int) -> bool:
	var s: Dictionary = st.sit[i]
	match String(s.get("k", "")):
		"reform":
			return _advance_reform(i, s)
		"revolution":
			return _advance_revolution(i, s)
		"war":
			return _advance_war(i, s)
		"depression":
			return _advance_depression(i, s)
	return true


func _advance_reform(i: int, s: Dictionary) -> bool:
	var rf: Dictionary = ct.reforms[int(ct.refidx.get(String(s["id"]), 0))]
	if not (s.get("ask", {}) as Dictionary).is_empty():
		return true
	_spend(int(rf.get("cost_q_li", 0)))
	s["p"] = int(s["p"]) + reform_rate(rf)
	var stage: int = int(s.get("stage", 0))
	if stage < ct.reform_stages.size() and int(s["p"]) >= int((ct.reform_stages[stage] as Dictionary)["at"]):
		s["stage"] = stage + 1
		s["ask"] = {"set": "stage:" + String((ct.reform_stages[stage] as Dictionary)["id"]), "until": st.q + ASK_Q}
		st.note("politics", "chron.reform_stage", {"reform": String(s["id"]), "rstage": String((ct.reform_stages[stage] as Dictionary)["id"])})
		return true
	if int(s["p"]) >= PPM:
		st.sit.remove_at(i)
		_set_cool("reform", REFORM_COOL_Q)
		st.note("politics", "chron.reform_done", {"reform": String(s["id"])})
		_set_regime(int(s["to"]), "reform")
		for c: Variant in rf.get("pro", []):
			_timed_support(String(c), 6)
		for c2: Variant in rf.get("con", []):
			_timed_support(String(c2), -4)
		return false
	if int(s["p"]) <= 0 or st.legitimacy < 200_000:
		# 推不下去了：改革失败，反对的人得意，拥护的人失望
		st.sit.remove_at(i)
		_set_cool("reform", REFORM_COOL_Q * 2)
		st.note("politics", "chron.reform_failed", {"reform": String(s["id"])})
		for c3: Variant in rf.get("pro", []):
			_timed_support(String(c3), -6)
		for c4: Variant in rf.get("con", []):
			_timed_support(String(c4), 4)
		return false
	return true


func _advance_revolution(i: int, s: Dictionary) -> bool:
	if not (s.get("ask", {}) as Dictionary).is_empty():
		pass
	elif st.q >= int(s.get("next_ask", 0)):
		s["ask"] = {"set": "revolution", "until": st.q + ASK_Q}
		s["next_ask"] = st.q + int((ct.crises.get("revolution", {}) as Dictionary).get("every", 3))
	s["p"] = int(s["p"]) + revolution_rate()
	if int(s["p"]) >= PPM:
		st.sit.remove_at(i)
		_revolution_wins(s)
		return false
	if int(s["p"]) <= 0:
		st.sit.remove_at(i)
		st.pres[0] = JCMath.mulppm(st.pres[0], 400_000)
		_set_cool("revolution", REV_COOL_Q)
		st.note("politics", "chron.revolution_crushed", {"regime": regime_id(int(s["to"]))})
		return false
	return true


func _advance_war(i: int, s: Dictionary) -> bool:
	if (s.get("ask", {}) as Dictionary).is_empty() and st.q >= int(s.get("next_ask", 0)):
		s["ask"] = {"set": "war", "until": st.q + ASK_Q}
		s["next_ask"] = st.q + int((ct.crises.get("war", {}) as Dictionary).get("every", 4))
	# 打仗额外花一半军饷
	_spend(JCMath.mulppm(st.exp[JCState.EXP_ARMY], 500_000))
	s["p"] = int(s["p"]) + war_drift(s) + rng.gauss_ppm(100_000)
	if int(s["p"]) >= PPM:
		st.sit.remove_at(i)
		_war_won()
		return false
	if int(s["p"]) <= -PPM:
		st.sit.remove_at(i)
		_war_lost(true)
		return false
	if st.q - int(s["q0"]) >= WAR_MAX_Q:
		st.sit.remove_at(i)
		_treaty(PPM, false)
		st.note("politics", "chron.war_armistice", {})
		_end_foreign()
		return false
	return true


func _advance_depression(i: int, s: Dictionary) -> bool:
	if not (s.get("ask", {}) as Dictionary).is_empty():
		return true
	s["left"] = int(s.get("left", 0)) - 1
	if int(s["left"]) <= 0:
		st.sit.remove_at(i)
		_set_cool("depression", int(ct.pressure.get("dep_cool_q", 40)))
		st.note("politics", "chron.depression_end", {})
		return false
	return true


## 改革每季推进多少（ppm）：势头 = 1 + 拥护阶层的民心均值 − 反对阶层的（0.25—1.75）；威信不到三成五时再打六折。
func reform_rate(rf: Dictionary) -> int:
	var mom: int = PPM + _avg_support(rf.get("pro", [])) - _avg_support(rf.get("con", []))
	mom = clampi(mom, 250_000, 1_750_000)
	if st.legitimacy < 350_000:
		mom = JCMath.mulppm(mom, 600_000)
	@warning_ignore("integer_division")
	return JCMath.mulppm(PPM / maxi(1, int(rf.get("quarters", 12))), mom)


## 革命每季推进多少：威信越低越快（每季六到十四个百分点）。
func revolution_rate() -> int:
	return 60_000 + JCMath.mulppm(80_000, JCMath.ratio_ppm(maxi(0, 450_000 - st.legitimacy), 450_000))


## 本国战力（ppm）：兵力（0.3—1.5）× 技术（0.7 + 0.3 × 本国时代 / 世界时代）。
func war_strength() -> int:
	@warning_ignore("integer_division")
	return JCMath.mulppm(clampi(army(), 300_000, 1_500_000), 700_000 + 300_000 * st.era / maxi(1, st.world_era))


## 战局每季的走势（不含运气）：本国战力减敌方战力，乘四分之一。
func war_drift(s: Dictionary) -> int:
	return JCMath.mulppm(war_strength() - int(s.get("enemy", PPM)), 250_000)


## 以工代赈：本季公共工程按各地区闲人分到各地（工钱与料钱由国库出，记在营造开支里）。[[地区, 两]]
func public_works() -> Array:
	var s: Dictionary = active("depression")
	if s.is_empty() or String(s.get("opt", "")) != "works" or not (s.get("ask", {}) as Dictionary).is_empty():
		return []
	var total: int = works_per_q()
	var w: PackedInt64Array = JCMath.zeros(ct.r_n)
	for r: int in ct.r_n:
		for c: int in ct.c_n:
			if c == econ.CL_G:
				continue
			var k: int = r * ct.c_n + c
			w[r] += maxi(0, JCMath.mulppm(st.pop[k], econ.work_ppm(c)) - st.employed[k])
	var parts: PackedInt64Array = JCMath.split(total, w)
	var out: Array = []
	for r2: int in ct.r_n:
		if parts[r2] > 0:
			out.append([r2, parts[r2]])
	return out


# ════════════════════════════ 选项的效果 ══════════════════════════════════
func _apply(i: int, set_id: String, opt: String, o: Dictionary) -> void:
	var s: Dictionary = st.sit[i]
	if set_id.begins_with("stage:"):
		var rf: Dictionary = ct.reforms[int(ct.refidx.get(String(s["id"]), 0))]
		s["p"] = int(s["p"]) + int(o.get("progress", 0))
		for c: Variant in rf.get("pro", []):
			_timed_support(String(c), int(o.get("pro", 0)))
		for c2: Variant in rf.get("con", []):
			_timed_support(String(c2), int(o.get("con", 0)))
		if int(o.get("unrest", 0)) != 0:
			world.add_timed("unrest", "", int(o["unrest"]) * 100, 8)
		return
	match set_id:
		"revolution":
			var agg: Array = s.get("agg", [])
			match opt:
				"repress":
					s["p"] = int(s["p"]) - (200_000 + JCMath.mulppm(300_000, army()))
					world.add_timed("unrest", "", 2000, SUPPORT_Q)
					for c3: Variant in agg:
						_timed_support(String(c3), -8)
				"concede":
					st.sit.remove_at(i)
					st.pres[0] = JCMath.mulppm(st.pres[0], 500_000)
					_set_cool("revolution", REV_COOL_Q)
					st.note("politics", "chron.revolution_conceded", {"regime": regime_id(int(s["to"]))})
					_set_regime(int(s["to"]), "concession")
					for c4: Variant in agg:
						_timed_support(String(c4), 6)
				"appease":
					s["p"] = int(s["p"]) - 350_000
					for c5: Variant in agg:
						_timed_support(String(c5), 10)
		"invasion":
			match opt:
				"resist":
					s["k"] = "war"
					s["p"] = 0
					s["q0"] = st.q
					s["next_ask"] = st.q + int((ct.crises.get("war", {}) as Dictionary).get("every", 4))
					st.note("politics", "chron.war_start", {})
				"negotiate":
					st.sit.remove_at(i)
					_treaty(1_500_000, true)
					_end_foreign()
				"selfstrength":
					st.sit.remove_at(i)
					st.pres[1] = JCMath.mulppm(st.pres[1], 400_000)
					world.add_timed("research_speed", "", 1000, 16)
					world.add_timed("admin_eff", "", 500, 16)
					_set_cool("invasion", FOR_COOL_Q / 2)
					st.note("politics", "chron.selfstrength", {})
		"war":
			if opt == "sue":
				st.sit.remove_at(i)
				var mild: bool = int(s["p"]) > 0
				_treaty(PPM if mild else 1_800_000, not mild)
				st.note("politics", "chron.war_sued", {})
				_end_foreign()
		"depression":
			s["opt"] = opt
			s["left"] = int(o.get("quarters", 8))


# ════════════════════════════ 结局 ════════════════════════════════════════
func _revolution_wins(s: Dictionary) -> void:
	var to: int = int(s["to"])
	# 威信已经垮到两成以下：革命成了，天下却散了——军阀割据（第三时代起）
	if st.legitimacy < 200_000 and st.era >= 3:
		to = int(ct.regidx.get("warlords", to))
	_spend(JCMath.mulppm(maxi(0, st.treasury), 200_000))
	st.pres[0] = 0
	_set_cool("revolution", REV_COOL_Q)
	st.note("politics", "chron.revolution_won", {"regime": regime_id(to)})
	_set_regime(to, "revolution")
	for c: int in ct.c_n:
		var cid: String = ct.c_id[c]
		_timed_support(cid, 10 if (s.get("agg", []) as Array).has(cid) else -8)
	_prestige(-5)


func _war_won() -> void:
	_prestige(15)
	for c: int in ct.c_n:
		_timed_support(ct.c_id[c], 5)
	st.note("politics", "chron.war_won", {})
	_end_foreign()


func _war_lost(heavy: bool) -> void:
	_treaty(2_500_000, true)
	st.note("politics", "chron.war_lost", {})
	# 第三时代起，威信又低：国家被列强控制，成了保护国
	if heavy and st.era >= 3 and st.legitimacy < 400_000:
		var pr: int = int(ct.regidx.get("protectorate", -1))
		if pr >= 0 and regime() != pr:
			st.reg_prev = regime()
			_set_regime(pr, "defeat")
	_end_foreign()


## 签约：赔款（上季收入的几倍）、关税封顶、开放口岸、国望与士绅民心下降。
func _treaty(indemnity_x: int, unequal: bool) -> void:
	_spend(JCMath.mulppm(revenue_q(), indemnity_x), true)
	if unequal:
		st.treaty_until = maxi(st.treaty_until, st.q + TREATY_Q)
		st.tax_customs_ppm = mini(st.tax_customs_ppm, TREATY_CUSTOMS_PPM)
		var sp: int = int(ct.didx.get("sea_policy", -1))
		if sp >= 0 and st.d_level[sp] == 0:
			st.d_level[sp] = 2
		_prestige(-15)
		_timed_support("gentry", -6)
		_timed_support("merchant", 2)
		st.note("politics", "chron.treaty_unequal", {"x": indemnity_x, "amount": JCMath.mulppm(revenue_q(), indemnity_x)})
	else:
		_prestige(-5)
		st.note("politics", "chron.treaty_peace", {"x": indemnity_x, "amount": JCMath.mulppm(revenue_q(), indemnity_x)})


func _end_foreign() -> void:
	st.pres[1] = 0
	_set_cool("invasion", FOR_COOL_Q)


func _set_regime(to: int, how: String) -> void:
	var d: int = int(ct.didx.get("regime", -1))
	if d < 0 or to < 0 or to >= ct.regimes.size():
		return
	var from: int = st.d_level[d]
	if from == to:
		return
	st.d_level[d] = to
	st.d_since[d] = st.q
	st.reg_hist.append({"q": st.q, "from": from, "to": to, "how": how})
	st.note("politics", "chron.regime_change", {"regime_from": regime_id(from), "regime": regime_id(to), "how": how})


# ════════════════════════════ 压力与触发 ══════════════════════════════════
## 革命压力每季的增减，分项（给界面解释）：[[键, ppm], ...]
func revolution_factors() -> Array:
	var p: Dictionary = ct.pressure
	var out: Array = []
	if st.era < 3:
		return out
	var leg_part: int = JCMath.mulppm(maxi(0, 450_000 - st.legitimacy), int(p.get("rev_legit_k", 120000)))
	if leg_part > 0:
		out.append(["legit", leg_part])
	var floor_c: int = int(p.get("rev_class_floor", 300000))
	var ck: Dictionary = p.get("rev_class_k", {})
	for c: int in ct.c_n:
		var cid: String = ct.c_id[c]
		var part: int = JCMath.mulppm(maxi(0, floor_c - st.support[c]), int(ck.get(cid, 50000)))
		if part > 0:
			out.append(["class:" + cid, part])
	var ue: int = urban_unemployment()
	var ue_part: int = JCMath.mulppm(maxi(0, ue - int(p.get("rev_unemp_floor", 80000))), int(p.get("rev_unemp_k", 150000)))
	if ue_part > 0:
		out.append(["unemp", ue_part])
	var od: Array = (p.get("rev_outdated", {}) as Dictionary).get(regime_id(), [0, 0])
	var od_part: int = int(od[1] if st.era >= 4 else od[0]) if od.size() >= 2 else 0
	if od_part > 0:
		out.append(["outdated", od_part])
	if _harsh():
		out.append(["harsh", int(p.get("rev_harsh", 3000))])
	if not active("depression").is_empty():
		out.append(["depression", int(p.get("rev_depression", 8000))])
	var dec: int = int(p.get("rev_decay", 8000)) + JCMath.mulppm(maxi(0, st.legitimacy - int(p.get("rev_legit_hi", 550000))), int(p.get("rev_legit_hi_k", 100000)))
	out.append(["decay", -dec])
	return out


## 列强压力每季的增减，分项。
func foreign_factors() -> Array:
	var p: Dictionary = ct.pressure
	var out: Array = []
	if st.world_era < 3:
		return out
	var gap: int = maxi(0, st.world_era - st.era)
	if gap > 0:
		out.append(["gap", gap * int(p.get("for_gap_k", 10000))])
	var weak: int = JCMath.mulppm(int(p.get("for_weak_k", 10000)), maxi(0, PPM - army()))
	if weak > 0:
		out.append(["weak", weak])
	var sp: int = int(ct.didx.get("sea_policy", -1))
	if sp >= 0 and st.d_level[sp] == 0:
		out.append(["closed", int(p.get("for_closed", 6000))])
	var pf: int = int(p.get("for_prestige_floor", 30))
	if st.prestige < pf:
		out.append(["prestige", (pf - st.prestige) * int(p.get("for_prestige_k", 150))])
	var lead: int = maxi(0, st.era - st.world_era) * int(p.get("for_lead_k", 10000))
	out.append(["decay", -(int(p.get("for_decay", 6000)) + lead)])
	return out


func _pressures() -> void:
	if st.pres.size() < 2:
		st.pres = JCMath.zeros(2)
	var rv: int = 0
	for f: Variant in revolution_factors():
		rv += int((f as Array)[1])
	st.pres[0] = clampi(st.pres[0] + rv, 0, PPM) if st.era >= 3 else 0
	var fv: int = 0
	for f2: Variant in foreign_factors():
		fv += int((f2 as Array)[1])
	st.pres[1] = clampi(st.pres[1] + fv, 0, PPM) if st.world_era >= 3 else 0


func _triggers() -> void:
	if st.era >= 3 and st.pres[0] >= PPM and active("revolution").is_empty() and st.q >= cool_until("revolution"):
		_start_revolution()
	if st.world_era >= 3 and st.pres[1] >= PPM and active("invasion").is_empty() and st.q >= cool_until("invasion"):
		_start_invasion()
	if st.era >= 3 and active("depression").is_empty() and st.q >= cool_until("depression"):
		var chance: int = int(ct.pressure.get("dep_base", 6000))
		if _boom():
			chance += int(ct.pressure.get("dep_boom", 8000))
		if rng.chance_ppm(chance):
			_start_depression()


func _start_revolution() -> void:
	var agg: Array = []
	var order: Array = []
	for c: int in ct.c_n:
		order.append([st.support[c], ct.c_id[c]])
	order.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and String(a[1]) < String(b[1])))
	for e: Variant in order:
		if int((e as Array)[0]) < 350_000:
			agg.append(String((e as Array)[1]))
	if agg.is_empty():
		agg.append(String((order[0] as Array)[1]))
	var s: Dictionary = _new_sit("revolution")
	s["to"] = _revolution_target(agg)
	s["agg"] = agg
	s["p"] = 200_000
	s["ask"] = {"set": "revolution", "until": st.q + ASK_Q}
	s["next_ask"] = st.q + int((ct.crises.get("revolution", {}) as Dictionary).get("every", 3))
	st.sit.append(s)
	st.pres[0] = 300_000
	st.note("politics", "chron.revolution_start", {"regime": regime_id(int(s["to"])), "class": String(agg[0])})


## 革命要建立什么（docs/61 §3.1）：欠饷连续两季、或军饷拨款不到七成时是兵变（军政府）；否则看当今政体与最不满的阶层——
##   君主国（集权、开明）：士绅要立宪，其余要共和；第四时代工匠、农户要社会主义；
##   君主立宪、共和、商人共和：第四时代工匠、农户要社会主义；士绅、商贾（或第三时代的工匠、农户）闹起来，是军人出来收拾局面；
##   社会主义、一党：商贾、士绅要共和；工匠、农户在社会主义国家里要一党「纠偏」，在一党国家里要社会主义；
##   军政府、割据、保护国：第三时代要共和；第四时代工匠、农户要社会主义，其余要一党。
func _revolution_target(agg: Array) -> int:
	var cur: String = regime_id()
	var first: String = String(agg[0])
	var workers: bool = first == "artisan" or first == "peasant"
	var modern: bool = st.era >= 4
	var want: String = "republic"
	if st.arrears_streak >= 2 or st.budget[JCState.BUD_ARMY] < 700_000:
		want = "junta"
	else:
		match cur:
			"empire", "enlightened":
				want = "socialist" if (modern and workers) else ("constitutional" if first == "gentry" else "republic")
			"constitutional", "republic", "merchant_republic":
				want = "socialist" if (modern and workers) else "junta"
			"socialist":
				want = "one_party" if workers else "republic"
			"one_party":
				want = "socialist" if workers else "republic"
			_:
				want = ("socialist" if workers else "one_party") if modern else "republic"
	if want == cur:
		want = "junta" if cur != "junta" else "republic"
	return int(ct.regidx.get(want, 0))


func _start_invasion() -> void:
	var s: Dictionary = _new_sit("invasion")
	var gap: int = maxi(0, st.world_era - st.era)
	s["enemy"] = 700_000 + gap * 250_000 + maxi(0, st.world_era - 2) * 100_000
	s["p"] = 0
	s["ask"] = {"set": "invasion", "until": st.q + ASK_Q}
	st.sit.append(s)
	st.pres[1] = 200_000
	st.note("politics", "chron.invasion_start", {})


func _start_depression() -> void:
	var s: Dictionary = _new_sit("depression")
	s["opt"] = ""
	s["left"] = 8
	s["ask"] = {"set": "depression", "until": st.q + ASK_Q}
	st.sit.append(s)
	st.note("politics", "chron.depression_start", {})


## 经济过热：近五年产值涨了两成以上。
func _boom() -> bool:
	var n: int = st.hist.size()
	if n < 6:
		return false
	var now: int = int((st.hist[n - 1] as Dictionary).get("gdp", 0))
	var before: int = int((st.hist[n - 6] as Dictionary).get("gdp", 0))
	return before > 0 and now * 10 > before * 12


## 严苛：欠饷、田赋比开局重三个百分点以上、或严禁罢工（第三时代起）。
func _harsh() -> bool:
	if st.arrears > 0:
		return true
	var base_land: int = int(ct.scenario.get("gov", {}).get("land_tax_ppm", 90000))
	if st.tax_land_ppm - base_land >= 30_000:
		return true
	var lp: int = int(ct.didx.get("labor_policy", -1))
	return st.era >= 3 and lp >= 0 and st.d_level[lp] == 0


## 城镇失业（工匠、商贾里找不到活的）：农户闲着多半在自家田里帮工，不算进来。取本季经济结算的摘要
## （读档后还没结算时取上季记录）。
func urban_unemployment() -> int:
	return int(econ.summary.get("unemp_town_ppm", st.last.get("unemp_town_ppm", 0)))


# ════════════════════════════ 小工具 ══════════════════════════════════════
func _new_sit(kind: String) -> Dictionary:
	st.sit_seq += 1
	return {"sid": st.sit_seq, "k": kind, "q0": st.q, "p": 0, "ask": {}}


func _avg_support(classes: Variant) -> int:
	var arr: Array = classes
	if arr.is_empty():
		return 500_000
	var s: int = 0
	for c: Variant in arr:
		var ci: int = int(ct.cidx.get(String(c), -1))
		if ci >= 0:
			s += st.support[ci]
	@warning_ignore("integer_division")
	return s / arr.size()


func _prestige(d: int) -> void:
	st.prestige = clampi(st.prestige + d, -60, 100)


func _timed_support(cid: String, points: int) -> void:
	if points != 0:
		world.add_timed("support", cid, points * 100, SUPPORT_Q)


## 国库出钱（记在事件开支里）。abroad 为真时钱流出国境（赔款），否则流向民间：工匠六成、商贾四成（货币守恒）。
## 国库不够时当场向民间借（econ.cover_treasury，记为国债、摊到工匠农户的算欠饷），国库不会在季中变负。
func _spend(v: int, abroad: bool = false) -> void:
	if v <= 0:
		return
	st.treasury -= v
	st.exp[JCState.EXP_EVENT] += v
	if abroad:
		st.silver -= v
	else:
		var C: int = ct.c_n
		var k: int = int(ct.ridx.get("zhongzhou", 0)) * C
		var a: int = JCMath.mulppm(v, 600_000)
		st.savings[k + econ.CL_A] += a
		st.savings[k + econ.CL_M] += v - a
	if st.treasury < 0:
		econ.cover_treasury()


func cool_until(kind: String) -> int:
	var i: int = KINDS.find(kind)
	return st.sit_cool[i] if i >= 0 and i < st.sit_cool.size() else 0


func _set_cool(kind: String, quarters: int) -> void:
	var i: int = KINDS.find(kind)
	if st.sit_cool.size() < KINDS.size():
		st.sit_cool = JCMath.zeros(KINDS.size())
	if i >= 0:
		st.sit_cool[i] = maxi(st.sit_cool[i], st.q + quarters)
