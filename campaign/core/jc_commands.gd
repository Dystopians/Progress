## v2 命令（docs/57 §11）：玩家与托管发出的每个动作都是一条命令，先查后办，被拒给出原因键。
## 命令格式：{"kind": 种类, ...参数, "source": "player" 或 "steward:<领域>"}
##   build        {building, region, owner: gov|private, method?, levels?}   新建（官府出资；private 表示招商、建成归民间）
##   upgrade      {uid, method, levels?}                                   改造一堆（官府出资；给 levels 就只切出这几级去改）
##   upgrade_all  {building, region: 地区或 "", owner?}                     同类过时建筑一起改造
##   consolidate  {building, region, owner?}                               合并同地区同类建筑并改造，打七折
##   mothball     {uid} / reopen {uid} / demolish {uid, levels}            官办建筑的封存、重开、拆除
##   research     {tech}                                                   研究方向
##   decree       {decree, level}                                          政令开关、档位或发起运动
##   tax          {tax: land|salt|commerce|customs, value}                 税率（ppm；盐课为厘/担）
##   budget       {line: 0—6, level}                                       拨款比例（ppm）
##   loan         {amount} / repay {amount}                                向商贾借款、还款（厘）
##   treaty       {partner}                                                签商约
##   event        {event, option}                                          回应待决事件
##   landmark     {landmark, region, full}                                 开建地标
class_name JCCommands
extends RefCounted

const PPM: int = 1_000_000
const TAX_BOUNDS: Dictionary = {
	"land": [30_000, 200_000], "salt": [0, 1_500], "commerce": [0, 100_000], "customs": [0, 300_000],
}

var ct: JCContent
var st: JCState
var mods: JCMods
var inv: JCInvest
var world: JCWorld


func setup(p_ct: JCContent, p_st: JCState, p_mods: JCMods, p_inv: JCInvest, p_world: JCWorld) -> void:
	ct = p_ct
	st = p_st
	mods = p_mods
	inv = p_inv
	world = p_world


func apply_all(cmds: Array) -> Array:
	var out: Array = []
	for c: Variant in cmds:
		if typeof(c) != TYPE_DICTIONARY:
			out.append({"ok": false, "reason": "reason.bad_command"})
			continue
		var r: Dictionary = apply(c)
		r["kind"] = String(c.get("kind", ""))
		r["source"] = String(c.get("source", "player"))
		out.append(r)
	return out


## 只检查不执行（给界面的按钮与托管用）。
func check(c: Dictionary) -> Dictionary:
	return _run(c, false)


func apply(c: Dictionary) -> Dictionary:
	return _run(c, true)


func _ok(extra: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"ok": true, "reason": ""}
	d.merge(extra)
	return d


func _no(reason: String, extra: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"ok": false, "reason": reason}
	d.merge(extra)
	return d


func _run(c: Dictionary, doit: bool) -> Dictionary:
	if st.over == 1:
		return _no("reason.game_over")
	match String(c.get("kind", "")):
		"build":
			return _build(c, doit)
		"upgrade":
			return _upgrade(c, doit)
		"upgrade_all":
			return _upgrade_all(c, doit)
		"consolidate":
			return _consolidate(c, doit)
		"mothball":
			return _mothball(c, doit)
		"reopen":
			return _reopen(c, doit)
		"demolish":
			return _demolish(c, doit)
		"research":
			return _research(c, doit)
		"decree":
			return _decree(c, doit)
		"tax":
			return _tax(c, doit)
		"budget":
			return _budget(c, doit)
		"loan":
			return _loan(c, doit)
		"repay":
			return _repay(c, doit)
		"treaty":
			return _treaty(c, doit)
		"event":
			return _event(c, doit)
		"landmark":
			return _landmark(c, doit)
	return _no("reason.bad_command")


# ── 建造与改造 ──────────────────────────────────────────────────────────
func _build(c: Dictionary, doit: bool) -> Dictionary:
	var b: int = int(ct.bidx.get(String(c.get("building", "")), -1))
	var r: int = int(ct.ridx.get(String(c.get("region", "")), -1))
	if b < 0 or r < 0:
		return _no("reason.bad_command")
	var owner: int = JCContent.OWNER_GOV if String(c.get("owner", "gov")) == "gov" else JCContent.OWNER_PRIVATE
	var mask: int = ct.b_owners[b]
	if owner == JCContent.OWNER_GOV and (mask & 2) == 0:
		return _no("reason.owner_not_allowed")
	if owner == JCContent.OWNER_PRIVATE and (mask & 1) == 0:
		return _no("reason.owner_not_allowed")
	var m: int = inv.best_method(b)
	if c.has("method") and String(c["method"]) != "":
		m = int(ct.midx.get(String(c["method"]), -1))
		if m < 0 or ct.m_b[m] != b:
			return _no("reason.bad_method")
		if not inv.method_unlocked(m):
			return _no("reason.tech_missing")
	var levels: int = clampi(int(c.get("levels", 1)), 1, 20)
	var why: String = inv.check_site(b, r, levels)
	if why != "":
		return _no(why)
	var cost: int = inv.level_cost(b, m, true) * levels
	if doit:
		var i: int = inv.start_build(b, r, owner, m, levels)
		st.s_fund[i] = 0
		st.note("build", "chron.build_order", {"building": ct.b_id[b], "region": ct.r_id[r], "levels": levels,
				"owner": owner, "source": String(c.get("source", "player"))})
	return _ok({"cost": cost, "quarters": ct.b_build_q[b]})


func _upgrade(c: Dictionary, doit: bool) -> Dictionary:
	var i: int = st.stack_of_uid(int(c.get("uid", -1)))
	if i < 0:
		return _no("reason.bad_command")
	if st.s_status[i] != JCState.ST_ACTIVE or st.s_pending[i] > 0:
		return _no("reason.busy")
	var m: int = int(ct.midx.get(String(c.get("method", "")), -1))
	if m < 0 or ct.m_b[m] != st.s_b[i] or m == st.s_m[i]:
		return _no("reason.bad_method")
	if not inv.method_unlocked(m):
		return _no("reason.tech_missing")
	var lv: int = int(c.get("levels", 0))
	var cost: int = inv.upgrade_cost(i, m)
	if lv > 0 and lv < st.s_level[i]:
		cost = JCMath.muldiv(cost, lv, st.s_level[i])
	if doit:
		if lv > 0 and lv < st.s_level[i]:
			var row: int = inv.split_off(i, lv)
			if row >= 0:
				i = row
		inv.start_upgrade(i, m)
		st.s_fund[i] = 0
		st.note("build", "chron.upgrade_order", {"building": ct.b_id[st.s_b[i]], "region": ct.r_id[st.s_region[i]],
				"method": ct.m_id[m], "source": String(c.get("source", "player"))})
	return _ok({"cost": cost, "quarters": ct.m_upq[m]})


func _upgrade_all(c: Dictionary, doit: bool) -> Dictionary:
	var b: int = int(ct.bidx.get(String(c.get("building", "")), -1))
	if b < 0:
		return _no("reason.bad_command")
	var r: int = int(ct.ridx.get(String(c.get("region", "")), -1))
	var owner: int = JCContent.OWNER_GOV if String(c.get("owner", "gov")) == "gov" else JCContent.OWNER_PRIVATE
	var n: int = 0
	var cost: int = 0
	for i: int in st.stack_count():
		if st.s_b[i] != b or st.s_owner[i] != owner or (r >= 0 and st.s_region[i] != r):
			continue
		if st.s_status[i] != JCState.ST_ACTIVE or st.s_pending[i] > 0:
			continue
		var m: int = inv.newer_method(i)
		if m < 0:
			continue
		cost += inv.upgrade_cost(i, m)
		n += 1
		if doit:
			inv.start_upgrade(i, m)
			st.s_fund[i] = 0
	if n == 0:
		return _no("reason.nothing_to_upgrade")
	if doit:
		st.note("build", "chron.upgrade_all", {"building": ct.b_id[b], "count": n,
				"source": String(c.get("source", "player"))})
	return _ok({"cost": cost, "count": n})


func _consolidate(c: Dictionary, doit: bool) -> Dictionary:
	var b: int = int(ct.bidx.get(String(c.get("building", "")), -1))
	var r: int = int(ct.ridx.get(String(c.get("region", "")), -1))
	if b < 0 or r < 0:
		return _no("reason.bad_command")
	var owner: int = JCContent.OWNER_GOV if String(c.get("owner", "gov")) == "gov" else JCContent.OWNER_PRIVATE
	var cost: int = inv.consolidate_cost(b, r, owner)
	if cost <= 0:
		return _no("reason.nothing_to_merge")
	if doit:
		var keep: int = inv.consolidate(b, r, owner)
		if keep < 0:
			return _no("reason.nothing_to_merge")
		st.note("build", "chron.consolidate", {"building": ct.b_id[b], "region": ct.r_id[r],
				"source": String(c.get("source", "player"))})
	return _ok({"cost": cost})


func _gov_stack(c: Dictionary) -> int:
	var i: int = st.stack_of_uid(int(c.get("uid", -1)))
	if i < 0 or st.s_owner[i] != JCContent.OWNER_GOV:
		return -1
	return i


func _mothball(c: Dictionary, doit: bool) -> Dictionary:
	var i: int = _gov_stack(c)
	if i < 0:
		return _no("reason.not_gov_owned")
	if st.s_status[i] != JCState.ST_ACTIVE:
		return _no("reason.busy")
	if doit:
		st.s_status[i] = JCState.ST_MOTHBALL
		st.note("build", "chron.mothball", {"building": ct.b_id[st.s_b[i]], "region": ct.r_id[st.s_region[i]]})
	return _ok()


func _reopen(c: Dictionary, doit: bool) -> Dictionary:
	var i: int = _gov_stack(c)
	if i < 0:
		return _no("reason.not_gov_owned")
	if st.s_status[i] != JCState.ST_MOTHBALL:
		return _no("reason.busy")
	var cost: int = JCMath.mulppm(ct.b_cost[st.s_b[i]] * st.s_level[i], 100_000)
	if st.treasury < cost:
		return _no("reason.no_money", {"cost": cost})
	if doit:
		st.treasury -= cost
		st.exp[JCState.EXP_BUILD] += cost
		_spread_artisans(st.s_region[i], cost)
		st.s_status[i] = JCState.ST_ACTIVE
		st.note("build", "chron.reopen", {"building": ct.b_id[st.s_b[i]], "region": ct.r_id[st.s_region[i]]})
	return _ok({"cost": cost})


func _demolish(c: Dictionary, doit: bool) -> Dictionary:
	var i: int = _gov_stack(c)
	if i < 0:
		return _no("reason.not_gov_owned")
	var lv: int = clampi(int(c.get("levels", st.s_level[i])), 1, maxi(1, st.s_level[i]))
	if doit:
		var salvage: int = inv.demolish(i, lv)
		# 残值：本地区工匠拆下的料卖了钱，归国库
		var r: int = st.s_region[i]
		var k: int = r * ct.c_n + int(ct.cidx.get("merchant", 2))
		var pay: int = mini(salvage, maxi(0, st.savings[k]))
		st.savings[k] -= pay
		st.treasury += pay
		st.rev[JCState.REV_OTHER] += pay
		st.note("build", "chron.demolish", {"building": ct.b_id[st.s_b[i]], "region": ct.r_id[r], "levels": lv})
	return _ok()


func _spread_artisans(r: int, amount: int) -> void:
	var k: int = r * ct.c_n + int(ct.cidx.get("artisan", 1))
	st.savings[k] += amount


# ── 研究、政令、税、拨款 ────────────────────────────────────────────────
func _research(c: Dictionary, doit: bool) -> Dictionary:
	var t: int = int(ct.tidx.get(String(c.get("tech", "")), -1))
	if t < 0:
		return _no("reason.bad_command")
	if st.t_done[t] == 1:
		return _no("reason.tech_done")
	if not world.tech_available(t):
		return _no("reason.tech_prereq")
	if doit:
		st.focus = t
	return _ok({"cost": world.tech_cost(t) - st.t_prog[t]})


func _decree(c: Dictionary, doit: bool) -> Dictionary:
	var d: int = int(ct.didx.get(String(c.get("decree", "")), -1))
	if d < 0:
		return _no("reason.bad_command")
	var dd: Dictionary = ct.decrees[d]
	var lvl: int = int(c.get("level", 1))
	var kind: String = String(dd.get("kind", "toggle"))
	if st.era < int(dd.get("era", 1)):
		return _no("reason.era_too_early")
	var tech: String = String(dd.get("tech", ""))
	if tech != "" and st.t_done[int(ct.tidx.get(tech, 0))] != 1:
		return _no("reason.tech_missing")
	var maxl: int = 1
	if kind == "level":
		maxl = maxi(0, dd.get("levels", []).size() - 1)
	if lvl < 0 or lvl > maxl:
		return _no("reason.bad_command")
	if lvl == st.d_level[d]:
		return _no("reason.no_change")
	if st.q < st.d_cool[d] and lvl > 0:
		return _no("reason.cooling", {"until": st.d_cool[d]})
	var once: int = int(dd.get("cost_once_li", 0))
	if lvl > 0 and once > 0 and st.treasury < once:
		return _no("reason.no_money", {"cost": once})
	if doit:
		if lvl > 0 and once > 0:
			st.treasury -= once
			st.exp[JCState.EXP_DECREE] += once
			var k: int = int(ct.ridx.get("zhongzhou", 0)) * ct.c_n + int(ct.cidx.get("gentry", 3))
			st.savings[k] += once
		st.d_level[d] = lvl
		st.d_since[d] = st.q
		if kind == "campaign" and lvl > 0:
			st.d_until[d] = st.q + int(dd.get("duration", 4))
		elif kind != "campaign":
			st.d_cool[d] = st.q + 4
		st.note("decree", "chron.decree", {"decree": String(dd["id"]), "level": lvl,
				"source": String(c.get("source", "player"))})
	return _ok({"cost_once": once, "cost_q": int(dd.get("cost_q_li", 0))})


func _tax(c: Dictionary, doit: bool) -> Dictionary:
	var kind: String = String(c.get("tax", ""))
	if not TAX_BOUNDS.has(kind):
		return _no("reason.bad_command")
	var v: int = int(c.get("value", 0))
	var bnd: Array = TAX_BOUNDS[kind]
	if v < int(bnd[0]) or v > int(bnd[1]):
		return _no("reason.out_of_range", {"lo": bnd[0], "hi": bnd[1]})
	if doit:
		match kind:
			"land":
				st.tax_land_ppm = v
			"salt":
				st.tax_salt_li = v
			"commerce":
				st.tax_commerce_ppm = v
			"customs":
				st.tax_customs_ppm = v
		st.note("fiscal", "chron.tax", {"tax": kind, "value": v, "source": String(c.get("source", "player"))})
	return _ok()


func _budget(c: Dictionary, doit: bool) -> Dictionary:
	var line: int = int(c.get("line", -1))
	var v: int = int(c.get("level", PPM))
	if line < 0 or line >= JCState.BUD_N or v < 0 or v > 1_500_000:
		return _no("reason.out_of_range", {"lo": 0, "hi": 1_500_000})
	if doit:
		st.budget[line] = v
		st.note("fiscal", "chron.budget", {"line": line, "value": v, "source": String(c.get("source", "player"))})
	return _ok()


# ── 借贷、商约 ──────────────────────────────────────────────────────────
func loan_limit() -> int:
	var tot: int = 0
	var M: int = int(ct.cidx.get("merchant", 2))
	for r: int in ct.r_n:
		tot += maxi(0, st.savings[r * ct.c_n + M])
	return JCMath.mulppm(tot, 300_000)


func _loan(c: Dictionary, doit: bool) -> Dictionary:
	var amt: int = int(c.get("amount", 0))
	if amt <= 0:
		return _no("reason.bad_command")
	var lim: int = loan_limit()
	if amt > lim:
		return _no("reason.loan_limit", {"limit": lim})
	if doit:
		var M: int = int(ct.cidx.get("merchant", 2))
		var w: PackedInt64Array = JCMath.zeros(ct.r_n)
		for r: int in ct.r_n:
			w[r] = maxi(0, st.savings[r * ct.c_n + M])
		var parts: PackedInt64Array = JCMath.split(amt, w)
		for r2: int in ct.r_n:
			st.savings[r2 * ct.c_n + M] -= parts[r2]
		st.treasury += amt
		st.debt += amt
		st.note("fiscal", "chron.loan", {"amount": amt, "source": String(c.get("source", "player"))})
	return _ok({"rate": JCMath.mulppm(st.debt_rate_ppm, mods.mult_ppm("interest_rate"))})


func _repay(c: Dictionary, doit: bool) -> Dictionary:
	var amt: int = mini(int(c.get("amount", 0)), st.debt)
	if amt <= 0:
		return _no("reason.no_debt")
	if st.treasury < amt:
		return _no("reason.no_money", {"cost": amt})
	if doit:
		var M: int = int(ct.cidx.get("merchant", 2))
		var w: PackedInt64Array = JCMath.zeros(ct.r_n)
		for r: int in ct.r_n:
			w[r] = maxi(1, st.pop[r * ct.c_n + M])
		var parts: PackedInt64Array = JCMath.split(amt, w)
		for r2: int in ct.r_n:
			st.savings[r2 * ct.c_n + M] += parts[r2]
		st.treasury -= amt
		st.debt -= amt
		st.note("fiscal", "chron.repay", {"amount": amt, "source": String(c.get("source", "player"))})
	return _ok()


func treaty_cost(p: int) -> int:
	return 200_000_000 * st.era


func _treaty(c: Dictionary, doit: bool) -> Dictionary:
	var p: int = int(ct.pidx.get(String(c.get("partner", "")), -1))
	if p < 0 or st.p_active[p] != 1:
		return _no("reason.bad_command")
	if st.p_treaty[p] == 1:
		return _no("reason.no_change")
	if st.p_rel[p] < 0:
		return _no("reason.relation_low")
	var cost: int = treaty_cost(p)
	if st.treasury < cost:
		return _no("reason.no_money", {"cost": cost})
	if doit:
		st.treasury -= cost
		st.exp[JCState.EXP_DECREE] += cost
		st.silver -= cost
		st.p_treaty[p] = 1
		st.p_rel[p] = mini(100, st.p_rel[p] + 10)
		st.note("trade", "chron.treaty", {"partner": String(ct.partners[p]["id"]),
				"source": String(c.get("source", "player"))})
	return _ok({"cost": cost})


# ── 事件、地标 ──────────────────────────────────────────────────────────
func _event(c: Dictionary, doit: bool) -> Dictionary:
	var e: int = int(ct.eidx.get(String(c.get("event", "")), -1))
	var opt: int = int(c.get("option", -1))
	var idx: int = -1
	for k: int in st.pend.size():
		if int(st.pend[k]["e"]) == e:
			idx = k
			break
	if e < 0 or idx < 0:
		return _no("reason.no_such_event")
	var opts: Array = ct.events[e].get("options", [])
	if opt < 0 or opt >= opts.size():
		return _no("reason.bad_command")
	var cost: int = int(opts[opt].get("cost_li", 0))
	if cost > 0 and st.treasury < cost:
		return _no("reason.no_money", {"cost": cost})
	if doit:
		var r: int = int(st.pend[idx]["r"])
		st.pend.remove_at(idx)
		world.apply_event_option(e, r, opt, false)
	return _ok({"cost": cost})


func _landmark(c: Dictionary, doit: bool) -> Dictionary:
	var l: int = int(ct.lidx.get(String(c.get("landmark", "")), -1))
	var r: int = int(ct.ridx.get(String(c.get("region", "")), -1))
	if l < 0 or r < 0:
		return _no("reason.bad_command")
	var full: bool = bool(c.get("full", false))
	var why: String = world.landmark_check(l, full)
	if why != "":
		return _no(why)
	var ld: Dictionary = ct.landmarks[l]
	var cost: int = int(ld["cost_li"])
	if not full and String(ld.get("kind", "")) == "leading":
		@warning_ignore("integer_division")
		cost = cost * 6 / 10
	if doit:
		st.l_state[l] = 1
		st.l_region[l] = r
		st.l_prog[l] = 0
		st.l_needq[l] = int(ld["build_q"])
		if full:
			st.lead_pick[int(ld["era"])] = l
		st.note("landmark", "chron.landmark_start", {"landmark": String(ld["id"]), "region": ct.r_id[r], "full": full})
	return _ok({"cost": cost})
