## v2 社会（docs/57 §3、§6、§17）：年成、治理与隐田、人口、阶层流动、迁移、识字、生活、民怨、民心、合法性、危机。
class_name JCSociety
extends RefCounted

const PPM: int = 1_000_000
## 危机：严重度阈值（ppm）与终局窗口（季）
const FINAL_WINDOW_Q: int = 8
## 各时代普遍的死亡率下降（ppm，下标是时代）
const ERA_DEATH_CUT: PackedInt64Array = [0, 0, 0, 0, 150_000]
const INFLUENCE: Dictionary = {"peasant": 300_000, "artisan": 150_000, "merchant": 200_000, "gentry": 350_000}

var ct: JCContent
var st: JCState
var mods: JCMods
var econ: JCEconomy
var rng: JCRng
var R: int = 0
var C: int = 0
var N: int = 0
## 本季的危机严重度（给界面）
var severity: PackedInt64Array = JCMath.zeros(3)
var admin_ratio: PackedInt64Array = PackedInt64Array()


func setup(p_ct: JCContent, p_st: JCState, p_mods: JCMods, p_econ: JCEconomy, p_rng: JCRng) -> void:
	ct = p_ct
	st = p_st
	mods = p_mods
	econ = p_econ
	rng = p_rng
	R = ct.r_n
	C = ct.c_n
	N = ct.n_n


# ── 年成（每年春季抽一次） ──────────────────────────────────────────────
func roll_weather() -> void:
	if st.season() != 0:
		return
	var cut: int = mods.sum("disaster_cut")
	for r: int in R:
		var h: int = PPM + rng.gauss_ppm(55_000)
		st.flood[r] = 0
		if rng.chance_ppm(45_000):
			h -= 160_000
		if ct.r_river[r] == 1 and rng.chance_ppm(35_000):
			st.flood[r] = 1
			h -= 120_000
		h = clampi(h, 650_000, 1_120_000)
		if h < PPM:
			var loss: int = PPM - h
			var c2: int = cut + mods.sum("disaster_cut", ct.r_id[r])
			loss = JCMath.mulppm(loss, maxi(0, PPM - c2 * 100))
			h = PPM - loss
		st.harvest[r] = h


# ── 治理、征收率、隐田 ──────────────────────────────────────────────────
func governance() -> void:
	admin_ratio = JCMath.zeros(R)
	var tot_pop: int = 0
	var weighted: int = 0
	for r: int in R:
		var pop_r: int = region_pop(r)
		tot_pop += pop_r
		admin_ratio[r] = mini(PPM, JCMath.ratio_ppm(econ.admin_cap[r], maxi(pop_r, 1)))
		weighted += admin_ratio[r] * pop_r / 1000
	var avg: int = JCMath.muldiv(weighted, 1000, maxi(tot_pop, 1))
	# 征收率：治理满额时 100%，毫无治理时 55%
	st.coll_eff = clampi(550_000 + JCMath.mulppm(450_000, avg), 300_000, PPM)
	var growth_q: int = JCMath.mulppm(_hidden_growth_base(), 250_000)
	var gmult: int = mods.mult_ppm("hidden_growth")
	for r2: int in R:
		var g: int = JCMath.mulppm(growth_q, PPM + (PPM - admin_ratio[r2]))
		var surv: int = mini(PPM, JCMath.mulppm(econ.survey_lv[r2], 500_000))
		g = JCMath.mulppm(g, PPM - surv)
		g = JCMath.mulppm(g, gmult)
		var cut: int = mods.sum("hidden_cut") * 100
		st.hidden[r2] = clampi(st.hidden[r2] + g - cut, 30_000, 600_000)


func _hidden_growth_base() -> int:
	return int(ct.scenario.get("gov", {}).get("hidden_growth_ppm", 4000))


func region_pop(r: int) -> int:
	var s: int = 0
	for c: int in C:
		s += st.pop[r * C + c]
	return s


func total_pop() -> int:
	var s: int = 0
	for k: int in st.pop.size():
		s += st.pop[k]
	return s


# ── 人口：生、死、流动、迁移 ────────────────────────────────────────────
func demography() -> void:
	var staple: int = int(ct.nidx.get("staple", 0))
	var mort_mult: int = mods.mult_ppm("mortality")
	for r: int in R:
		var pop_r: int = maxi(region_pop(r), 1)
		var h: int = mini(PPM, JCMath.ratio_ppm(econ.health_cov[r], pop_r))
		var s: int = mini(PPM, JCMath.ratio_ppm(econ.sanit_cov[r], pop_r))
		for c: int in C:
			var k: int = r * C + c
			var p: int = st.pop[k]
			if p <= 0:
				continue
			var f: int = st.sat[k * N + staple]
			var birth: int = 9_300
			# 第三时代起识字率高的地方少生（人口转型：先是死亡率降，后是出生率降）
			if st.era >= 3:
				birth = JCMath.mulppm(birth, PPM - JCMath.mulppm(st.literacy[r], 350_000 if st.era >= 4 else 120_000))
			birth = JCMath.mulppm(birth, clampi(f, 600_000, PPM))
			# 生计紧：没活干、日子紧的人家晚婚少育（失业三成时少生一成五；日用只有期待一半时再少一成）
			var sup_b: int = JCMath.mulppm(p, econ.work_ppm(c))
			var idle_b: int = 0 if sup_b <= 0 else JCMath.ratio_ppm(maxi(0, sup_b - st.employed[k]), sup_b)
			birth = JCMath.mulppm(birth, PPM - JCMath.mulppm(mini(idle_b, 400_000), 250_000))
			birth = JCMath.mulppm(birth, 900_000 + JCMath.mulppm(mini(st.comfort[k], PPM), 100_000))
			var death: int = 8_600
			# 时代本身带来的普遍改善（吃得更好、常识与防疫）：不靠设施，第四时代才有
			death = JCMath.mulppm(death, PPM - ERA_DEATH_CUT[clampi(st.era, 1, 4)])
			# 医药与卫生降死亡率：前现代效果有限（第一时代至多一成），到第四时代才显著
			death = JCMath.mulppm(death, PPM - JCMath.mulppm(h, 50_000 + (st.era - 1) * 70_000) - JCMath.mulppm(s, 40_000 + (st.era - 1) * 30_000))
			if f < 950_000:
				death = JCMath.mulppm(death, PPM + 4 * (950_000 - f))
			death = JCMath.mulppm(death, mort_mult)
			var b_n: int = JCMath.mulppm(p, birth)
			var d_n: int = JCMath.mulppm(p, death)
			st.pop[k] = maxi(0, p + b_n - d_n)
	_mobility()
	_migration()


func _mobility() -> void:
	var up: int = mods.mult_ppm("skill_up")
	var P: int = econ.CL_P
	var A: int = econ.CL_A
	var M: int = econ.CL_M
	var Gc: int = econ.CL_G
	for r: int in R:
		var kP: int = r * C + P
		var kA: int = r * C + A
		var kM: int = r * C + M
		var kG: int = r * C + Gc
		# 作坊缺人、村里有闲人：农户进城做工
		var vacA: int = maxi(0, st.jobs[kA] - JCMath.mulppm(st.pop[kA], econ.work_ppm(A)))
		var idleP: int = maxi(0, JCMath.mulppm(st.pop[kP], econ.work_ppm(P)) - st.employed[kP])
		var move_w: int = mini(mini(vacA, idleP), JCMath.mulppm(st.pop[kP], 20_000))
		move_w = JCMath.mulppm(move_w, up)
		_move(kP, kA, JCMath.ratio_ppm(move_w, econ.work_ppm(P), 0) * 1)
		# 工匠闲人多、农活缺人：回乡
		var idleA: int = maxi(0, JCMath.mulppm(st.pop[kA], econ.work_ppm(A)) - st.employed[kA])
		var vacP: int = maxi(0, st.jobs[kP] - JCMath.mulppm(st.pop[kP], econ.work_ppm(P)))
		if idleA > JCMath.mulppm(st.pop[kA], 60_000):
			_move(kA, kP, JCMath.muldiv(mini(idleA, vacP + JCMath.mulppm(idleA, 100_000)), PPM, econ.work_ppm(A)) / 10)
		# 商贾缺人：工匠转行
		var vacM: int = maxi(0, st.jobs[kM] - JCMath.mulppm(st.pop[kM], econ.work_ppm(M)))
		_move(kA, kM, JCMath.mulppm(mini(JCMath.muldiv(vacM, PPM, econ.work_ppm(M)), JCMath.mulppm(st.pop[kA], 10_000)), up))
		# 商贾闲人多：转回工匠
		var idleM: int = maxi(0, JCMath.mulppm(st.pop[kM], econ.work_ppm(M)) - st.employed[kM])
		if idleM > JCMath.mulppm(st.pop[kM], 100_000):
			_move(kM, kA, JCMath.muldiv(idleM, PPM, econ.work_ppm(M)) / 20)
		# 士绅：识字的人随读书机会增长，下限为人口的 2.5%
		var pop_r: int = region_pop(r)
		var vacG: int = maxi(0, st.jobs[kG] - JCMath.mulppm(st.pop[kG], econ.work_ppm(Gc)))
		var want_g: int = maxi(JCMath.mulppm(pop_r, 25_000), JCMath.mulppm(pop_r, JCMath.mulppm(st.literacy[r], 150_000)))
		# 读书人愿不愿意「入士」要看士绅的日子：人均收入不到工匠的两倍半就不去挤了；
		# 士绅人均收入跌到工匠的一倍半以下，一部分士绅改行做工商（保底人口的 2.5%）
		var pc_g: int = st.income[kG] / maxi(1, st.pop[kG] / 1000)
		var pc_a: int = st.income[kA] / maxi(1, st.pop[kA] / 1000)
		var attractive: bool = pc_g * 2 >= pc_a * 5
		if pc_g * 2 < pc_a * 3 and st.pop[kG] > JCMath.mulppm(pop_r, 25_000):
			_move(kG, kA, mini(JCMath.mulppm(st.pop[kG], 5_000), st.pop[kG] - JCMath.mulppm(pop_r, 25_000)))
		if (st.pop[kG] < want_g and attractive) or vacG > 0:
			var mv: int = mini(JCMath.mulppm(st.pop[kM] + st.pop[kA], 3_000), maxi(want_g - st.pop[kG], JCMath.muldiv(vacG, PPM, econ.work_ppm(Gc))))
			mv = JCMath.mulppm(mv, up)
			# 读书出身的士人多来自工匠与殷实农户，少数来自商贾
			@warning_ignore("integer_division")
			var from_m: int = mv / 5
			@warning_ignore("integer_division")
			var from_a: int = mv / 2
			_move(kM, kG, from_m)
			_move(kA, kG, from_a)
			_move(kP, kG, mv - from_m - from_a)


func _move(from_k: int, to_k: int, persons: int) -> void:
	var p: int = mini(maxi(persons, 0), st.pop[from_k])
	if p <= 0:
		return
	# 储蓄跟着人走（按人均）
	var sv: int = JCMath.muldiv(maxi(st.savings[from_k], 0), p, maxi(st.pop[from_k], 1))
	st.pop[from_k] -= p
	st.pop[to_k] += p
	st.savings[from_k] -= sv
	st.savings[to_k] += sv


## 地区之间：同一阶层从生活差、闲人多的地区迁往生活好、缺人的地区（每季至多 0.4%）。
func _migration() -> void:
	var mig: int = mods.mult_ppm("migration")
	for c: int in C:
		var attract: PackedInt64Array = JCMath.zeros(R)
		for r: int in R:
			var k: int = r * C + c
			var sup: int = JCMath.mulppm(st.pop[k], econ.work_ppm(c))
			var emp: int = PPM if sup <= 0 else mini(PPM, JCMath.ratio_ppm(st.employed[k], sup))
			attract[r] = JCMath.mulppm(st.living[k], emp)
		for r2: int in R:
			var best: int = -1
			for r3: int in R:
				if r3 != r2 and (best < 0 or attract[r3] > attract[best]):
					best = r3
			if best < 0:
				continue
			var diff: int = attract[best] - attract[r2]
			if diff <= 50_000:
				continue
			var rate: int = mini(4_000, JCMath.mulppm(diff, 20_000))
			rate = JCMath.mulppm(rate, mig)
			_move(r2 * C + c, best * C + c, JCMath.mulppm(st.pop[r2 * C + c], rate))


# ── 识字 ────────────────────────────────────────────────────────────────
func literacy() -> void:
	var lr: int = mods.mult_ppm("literacy_rate")
	for r: int in R:
		var pop_r: int = maxi(region_pop(r), 1)
		var cover: int = mini(PPM, JCMath.ratio_ppm(econ.edu_seats[r], JCMath.mulppm(pop_r, 30_000)))
		var span: int = 200_000 + (st.era - 1) * 250_000
		var target: int = 30_000 + JCMath.mulppm(cover, span) + econ.literacy_bld[r]
		target = JCMath.mulppm(target, lr)
		target = mini(target, 950_000)
		var rate: int = JCMath.mulppm(15_000, lr)
		st.literacy[r] = JCMath.approach(st.literacy[r], target, rate)


# ── 生活、民怨、民心、合法性 ────────────────────────────────────────────
func living_and_unrest() -> void:
	var gap: int = maxi(0, st.world_era - st.era)
	# 生活水平 = 六成温饱（口粮、盐的满足度）+ 四成日用（相对当世期待，最多算到 125%）；
	# 期待随世界时代上涨（jc_economy._comfort），所以国家原地不动时，日子会显得越来越紧。
	var expect: int = 950_000
	var sc: Dictionary = ct.scenario.get("gov", {})
	var base_land: int = int(sc.get("land_tax_ppm", 90000))
	var base_salt: int = int(sc.get("salt_tax_li", 600))
	var base_com: int = int(sc.get("commerce_tax_ppm", 20000))
	for r: int in R:
		var pop_r: int = maxi(region_pop(r), 1)
		var amen: int = mini(PPM, JCMath.ratio_ppm(econ.amen_cov[r], pop_r))
		for c: int in C:
			var k: int = r * C + c
			var wsum: int = 0
			var acc: int = 0
			for n: int in N:
				if ct.n_ess[n] != 1 or not ct.need_active(n, st.era):
					continue
				var w: int = ct.n_weight[n]
				wsum += w
				acc += w * st.sat[k * N + n]
			@warning_ignore("integer_division")
			var ess: int = PPM if wsum <= 0 else acc / wsum
			# 吃不饱的时候，日用再好也不算过得好：温饱不到九成五，日用那四成最多按温饱算
			var com: int = mini(1_250_000, st.comfort[k])
			if ess < 950_000:
				com = mini(com, ess)
			st.living[k] = JCMath.mulppm(ess, 600_000) + JCMath.mulppm(com, 400_000)
			var t: int = 3 * maxi(0, expect - st.living[k])
			var cid: String = ct.c_id[c]
			# 税负：高于开局水平的部分，按阶层加怨
			if cid == "peasant":
				t += maxi(0, st.tax_land_ppm - base_land) * 3
				t += maxi(0, JCMath.ratio_ppm(st.tax_salt_li - base_salt, maxi(base_salt, 1), 0)) / 4
			elif cid == "merchant":
				t += maxi(0, st.tax_commerce_ppm - base_com) * 4
			elif cid == "gentry":
				t += maxi(0, st.tax_land_ppm - base_land) * 2
			# 欠饷欠俸
			if st.arrears > 0 and (cid == "peasant" or cid == "gentry"):
				t += 150_000
			# 失业
			var sup: int = JCMath.mulppm(st.pop[k], econ.work_ppm(c))
			if sup > 0 and cid != "gentry":
				var idle: int = maxi(0, sup - st.employed[k])
				# 农户的闲人多半在自家田里帮工（分的是一家的收成），民怨比城里没活干的人轻
				var w_idle: int = 500_000 if cid == "peasant" else 1_500_000
				t += JCMath.mulppm(JCMath.ratio_ppm(idle, sup), w_idle) - 60_000
			t = maxi(0, t)
			t = JCMath.mulppm(t, PPM - JCMath.mulppm(amen, 100_000))
			t = JCMath.mulppm(t, mods.mult_ppm("unrest", cid))
			t = JCMath.mulppm(t, PPM + mods.delta_ppm("unrest", ct.r_id[r]) - mods.delta_ppm("unrest"))
			t = clampi(t, 0, PPM)
			st.unrest[k] = JCMath.approach(st.unrest[k], t, 200_000)
	# 各阶层民心（全国）
	for c2: int in C:
		var cid2: String = ct.c_id[c2]
		var tgt: int = 600_000
		for d: int in ct.decrees.size():
			var lvl: int = st.d_level[d]
			var sup_list: Array = ct.decrees[d].get("support", [])
			var kind: String = String(ct.decrees[d].get("kind", "toggle"))
			var pick: int = lvl if kind == "level" else (0 if lvl > 0 else -1)
			if pick >= 0 and pick < sup_list.size():
				tgt += int(sup_list[pick].get(cid2, 0)) * 10_000
		tgt += (mods.scoped("support", cid2) + mods.scoped("support", "all") + mods.scoped("support", "")) * 100
		# 民怨拉低民心
		var un: int = 0
		var pw: int = 0
		for r2: int in R:
			var k2: int = r2 * C + c2
			un += st.unrest[k2] * (st.pop[k2] / 1000)
			pw += st.pop[k2] / 1000
		un = un / maxi(pw, 1)
		tgt -= JCMath.mulppm(un, 600_000)
		tgt += st.prestige * 1_000
		tgt = clampi(tgt, 0, PPM)
		st.support[c2] = JCMath.approach(st.support[c2], tgt, 150_000)
	var leg: int = 0
	for c3: int in C:
		leg += JCMath.mulppm(st.support[c3], int(INFLUENCE.get(ct.c_id[c3], 250_000)))
	leg -= mini(st.arrears_streak, 10) * 20_000
	leg -= gap * 30_000
	leg += st.prestige * 1_000
	st.legitimacy = clampi(leg, 0, PPM)


# ── 危机三轨 ────────────────────────────────────────────────────────────
func crisis() -> void:
	# 财政：本季有欠付、或债务超过三年收入
	var rev_year: int = 0
	for i: int in st.rev.size():
		rev_year += st.rev[i]
	rev_year *= 4
	var fiscal_bad: bool = st.arrears > 0 or (rev_year > 0 and st.debt > rev_year * 3)
	if fiscal_bad:
		st.arrears_streak += 1
		st.cr_bad[JCState.CR_FISCAL] += 1
	else:
		st.arrears_streak = maxi(0, st.arrears_streak - 1)
		st.cr_bad[JCState.CR_FISCAL] = maxi(0, st.cr_bad[JCState.CR_FISCAL] - 2)
	var fb: int = st.cr_bad[JCState.CR_FISCAL]
	severity[JCState.CR_FISCAL] = mini(PPM, fb * 70_000)
	_set_stage(JCState.CR_FISCAL, 3 if fb >= 12 else (2 if fb >= 6 else (1 if fb >= 1 else 0)))
	# 民生：最乱地区的民怨与最饿地区的口粮
	var staple: int = int(ct.nidx.get("staple", 0))
	var worst_unrest: int = 0
	var worst_food: int = PPM
	for r: int in R:
		var un: int = 0
		var fd: int = 0
		var pw: int = 0
		for c: int in C:
			var k: int = r * C + c
			var w: int = st.pop[k] / 1000
			un += st.unrest[k] * w
			fd += st.sat[k * N + staple] * w
			pw += w
		if pw > 0:
			worst_unrest = maxi(worst_unrest, un / pw)
			worst_food = mini(worst_food, fd / pw)
	var hunger: int = 3 * maxi(0, 900_000 - worst_food)
	var sev: int = maxi(worst_unrest, hunger)
	severity[JCState.CR_LIVELIHOOD] = mini(PPM, sev)
	# 纪事里记下民生危机主要是因为挨饿还是民怨（国史配「大饥荒」还是「民变四起」）
	_set_stage(JCState.CR_LIVELIHOOD, 3 if sev >= 700_000 else (2 if sev >= 500_000 else (1 if sev >= 300_000 else 0)),
			{"why": "hunger" if hunger >= worst_unrest else "unrest"})
	# 合法性
	var leg: int = st.legitimacy
	severity[JCState.CR_LEGITIMACY] = clampi(JCMath.mulppm(PPM - leg, 1_600_000) - 400_000, 0, PPM)
	_set_stage(JCState.CR_LEGITIMACY, 3 if leg < 250_000 else (2 if leg < 350_000 else (1 if leg < 450_000 else 0)))
	# 终局：任一轨停在第三级满 8 季
	var reasons: PackedStringArray = ["fiscal", "revolt", "mandate"]
	for t: int in 3:
		if st.cr_stage[t] >= 3 and st.q - st.cr_since[t] >= FINAL_WINDOW_Q and st.over == 0:
			st.over = 1
			st.over_reason = reasons[t]
			st.over_q = st.q
			st.note("crisis", "chron.game_over", {"reason": reasons[t]})


func _set_stage(t: int, stage: int, extra: Dictionary = {}) -> void:
	if stage != st.cr_stage[t]:
		var args: Dictionary = {"track": t, "stage": stage}
		args.merge(extra)
		if stage > st.cr_stage[t]:
			st.note("crisis", "chron.crisis_up", args)
		elif st.cr_stage[t] >= 2 and stage < st.cr_stage[t]:
			st.note("crisis", "chron.crisis_down", args)
		st.cr_stage[t] = stage
		st.cr_since[t] = st.q
