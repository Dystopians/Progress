## v2 营造与投资（docs/57 §5、§10）：在建项目推进、民间投资、亏损收缩、改造操作的算账。
class_name JCInvest
extends RefCounted

const PPM: int = 1_000_000
## 民间投资：每季动用可投资闲钱的比例、年化回报门槛、每季至多新开几项
const INVEST_RATE_PPM: int = 40_000
const HURDLE_PPM: int = 100_000
const MAX_NEW: int = 4
## 连亏几季后民营作坊缩小一级
const CLOSE_AFTER: int = 6

var ct: JCContent
var st: JCState
var mods: JCMods
var econ: JCEconomy


func setup(p_ct: JCContent, p_st: JCState, p_mods: JCMods, p_econ: JCEconomy) -> void:
	ct = p_ct
	st = p_st
	mods = p_mods
	econ = p_econ


# ── 造价 ────────────────────────────────────────────────────────────────

## 以某生产方式新建一级的造价：基础造价 ×（1 + 0.4 × 方法时代高出建筑时代的档数）× 修正。
func level_cost(b: int, m: int, gov: bool) -> int:
	var extra: int = maxi(0, ct.m_era[m] - ct.b_era[b])
	var c: int = JCMath.mulppm(ct.b_cost[b], PPM + extra * 400_000)
	if gov:
		c = JCMath.mulppm(c, mods.mult_ppm("construction_cost"))
	return c


## 把某堆改成方法 m 的造价与工期。
func upgrade_cost(i: int, m: int) -> int:
	var b: int = st.s_b[i]
	var c: int = JCMath.mulppm(JCMath.mulppm(ct.b_cost[b], ct.m_upcost[m]), PPM + maxi(0, ct.m_era[m] - ct.b_era[b]) * 200_000)
	c *= maxi(1, st.s_level[i])
	if st.s_owner[i] == JCContent.OWNER_GOV:
		c = JCMath.mulppm(c, mods.mult_ppm("construction_cost"))
	return c


func method_unlocked(m: int) -> bool:
	return ct.m_tech[m] < 0 or st.t_done[ct.m_tech[m]] == 1


func building_unlocked(b: int) -> bool:
	return ct.b_tech[b] < 0 or st.t_done[ct.b_tech[b]] == 1


## 该建筑当前最好的（时代最新的）已解锁方法；同时代取列表里靠后的。
func best_method(b: int) -> int:
	var best: int = -1
	for m: int in ct.b_methods[b]:
		if not method_unlocked(m) or ct.m_era[m] > st.era + 1:
			continue
		if best < 0 or ct.m_era[m] >= ct.m_era[best]:
			best = m
	return best if best >= 0 else ct.b_methods[b][0]


## 这座建筑眼下值得新建的方法：已解锁、且没有同样产出的更新方法已解锁（农田的每种作物各算一种）。
func current_methods(b: int) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	var ms: PackedInt64Array = ct.b_methods[b]
	for m: int in ms:
		if not method_unlocked(m) or ct.m_era[m] > st.era + 1:
			continue
		var superseded: bool = false
		for m2: int in ms:
			if m2 == m or not method_unlocked(m2) or ct.m_era[m2] <= ct.m_era[m] or ct.m_era[m2] > st.era + 1:
				continue
			if _same_crop(m, m2):
				superseded = true
				break
		if not superseded:
			out.append(m)
	return out


## 某堆有没有更新的可用方法（给「改造」面板与托管用）；返回方法下标或 −1。
func newer_method(i: int) -> int:
	var b: int = st.s_b[i]
	var cur: int = st.s_m[i]
	var best: int = -1
	for m: int in ct.b_methods[b]:
		if m == cur or not method_unlocked(m):
			continue
		if ct.m_era[m] <= ct.m_era[cur]:
			continue
		# 农田只在同一作物的更新种法之间升级（名字前缀相同）
		if ct.b_cat[b] == JCContent.CAT_FARM and not _same_crop(cur, m):
			continue
		if best < 0 or ct.m_era[m] > ct.m_era[best]:
			best = m
	return best


func _same_crop(a: int, b: int) -> bool:
	var ga: PackedInt64Array = ct.m_out_g[a]
	var gb: PackedInt64Array = ct.m_out_g[b]
	return not ga.is_empty() and not gb.is_empty() and ga[0] == gb[0]


# ── 可建性（软约束 + 硬上限），返回原因键；空串表示可以 ─────────────────
func check_site(b: int, r: int, levels: int) -> String:
	if not building_unlocked(b):
		return "reason.tech_missing"
	if ct.b_era[b] > st.era + 1:
		return "reason.era_too_early"
	var lt: int = ct.b_land[b]
	if lt >= 0:
		var cap: int = st.land[r * JCContent.LT_N + lt]
		var used: int = land_in_use(r, lt)
		if used + levels > cap:
			return "reason.no_land"
	var dep: String = ct.b_deposit[b]
	if dep != "":
		var dcap: int = int(ct.r_deposit[r].get(dep, 0))
		if deposit_in_use(r, b) + levels > dcap:
			return "reason.no_deposit"
	if ct.b_coast[b] == 1 and ct.r_coast[r] != 1:
		return "reason.no_coast"
	var id: String = ct.b_id[b]
	if (id == "canal" or id == "watermill") and ct.r_river[r] != 1:
		return "reason.no_river"
	return ""


func land_in_use(r: int, lt: int) -> int:
	var used: int = 0
	for i: int in st.stack_count():
		if st.s_region[i] == r and ct.b_land[st.s_b[i]] == lt:
			used += st.s_level[i] + st.s_pending[i]
	return used


func deposit_in_use(r: int, b: int) -> int:
	var dep: String = ct.b_deposit[b]
	var used: int = 0
	for i: int in st.stack_count():
		if st.s_region[i] == r and ct.b_deposit[st.s_b[i]] == dep:
			used += st.s_level[i] + st.s_pending[i]
	return used


# ── 开工与改造 ──────────────────────────────────────────────────────────

## 新建 levels 级（同地区、同类型、同所有者、同方法的堆就加级），返回堆行号。
func start_build(b: int, r: int, owner: int, m: int, levels: int) -> int:
	var i: int = _find(r, b, m, owner)
	if i >= 0:
		st.s_pending[i] += levels
		if st.s_needq[i] <= 0:
			st.s_needq[i] = ct.b_build_q[b]
			st.s_prog[i] = 0
		st.s_fund[i] = 0 if owner == JCContent.OWNER_GOV else 1
		return i
	var row: int = st.add_stack(r, b, m, owner, 0, JCState.ST_NEW, levels, ct.b_build_q[b])
	st.s_fund[row] = 0 if owner == JCContent.OWNER_GOV else 1
	return row


func _find(r: int, b: int, m: int, owner: int) -> int:
	for i: int in st.stack_count():
		if st.s_region[i] == r and st.s_b[i] == b and st.s_m[i] == m and st.s_owner[i] == owner \
				and st.s_status[i] != JCState.ST_UPGRADE:
			return i
	return -1


func start_upgrade(i: int, m: int) -> void:
	st.s_status[i] = JCState.ST_UPGRADE
	st.s_target[i] = m
	st.s_needq[i] = maxi(1, ct.m_upq[m])
	st.s_prog[i] = 0
	st.s_fund[i] = 0 if st.s_owner[i] == JCContent.OWNER_GOV else 1


## 合并：同地区同类型、同所有者的几堆过时建筑合成一堆新式的，造价打七折。返回新堆行号或 −1。
func consolidate(b: int, r: int, owner: int) -> int:
	var rows: PackedInt64Array = PackedInt64Array()
	var total: int = 0
	var target: int = best_method(b)
	for i: int in st.stack_count():
		if st.s_region[i] == r and st.s_b[i] == b and st.s_owner[i] == owner and st.s_status[i] != JCState.ST_NEW \
				and st.s_pending[i] == 0 and st.s_status[i] != JCState.ST_UPGRADE:
			if ct.b_cat[b] == JCContent.CAT_FARM and not _same_crop(st.s_m[i], target):
				continue
			rows.append(i)
			total += st.s_level[i]
	if rows.size() < 1 or total <= 0:
		return -1
	var keep: int = rows[0]
	for k: int in range(1, rows.size()):
		st.s_level[rows[k]] = 0
	st.s_level[keep] = total
	st.s_status[keep] = JCState.ST_ACTIVE
	if target != st.s_m[keep]:
		start_upgrade(keep, target)
	return keep


func consolidate_cost(b: int, r: int, owner: int) -> int:
	var target: int = best_method(b)
	var cost: int = 0
	for i: int in st.stack_count():
		if st.s_region[i] == r and st.s_b[i] == b and st.s_owner[i] == owner and st.s_m[i] != target \
				and st.s_status[i] == JCState.ST_ACTIVE:
			if ct.b_cat[b] == JCContent.CAT_FARM and not _same_crop(st.s_m[i], target):
				continue
			cost += upgrade_cost(i, target)
	return JCMath.mulppm(cost, 700_000)


func demolish(i: int, levels: int) -> int:
	var lv: int = mini(levels, st.s_level[i])
	var salvage: int = JCMath.mulppm(ct.b_cost[st.s_b[i]] * lv, 100_000)
	st.s_level[i] -= lv
	return salvage


# ── 每季：营造项目登记（在经济结算之前） ────────────────────────────────
func plan_jobs() -> void:
	econ.clear_jobs()
	var gov_left: int = maxi(0, st.treasury)
	var priv_left: int = _private_funds()
	for i: int in st.stack_count():
		var building: bool = st.s_pending[i] > 0
		var upgrading: bool = st.s_status[i] == JCState.ST_UPGRADE
		if not building and not upgrading:
			continue
		var b: int = st.s_b[i]
		var total: int
		if upgrading:
			total = upgrade_cost(i, st.s_target[i])
		else:
			total = level_cost(b, st.s_m[i], st.s_owner[i] == JCContent.OWNER_GOV) * st.s_pending[i]
		var needq: int = maxi(1, st.s_needq[i])
		@warning_ignore("integer_division")
		var per_q: int = total / needq
		var gov: bool = st.s_fund[i] == 0
		var cap: int = gov_left if gov else priv_left
		var v: int = mini(per_q, cap)
		if gov:
			gov_left -= v
		else:
			priv_left -= v
		if v > 0:
			econ.add_job(i, -1, st.s_region[i], v, 0 if gov else 1)
		else:
			st.s_bind[i] = JCEconomy.B_FUNDS
	# 地标
	for l: int in ct.landmarks.size():
		if st.l_state[l] != 1:
			continue
		var ld: Dictionary = ct.landmarks[l]
		var full: bool = st.lead_pick.size() > int(ld["era"]) and st.lead_pick[int(ld["era"])] == l
		var cost: int = int(ld["cost_li"])
		if not full and String(ld.get("kind", "")) == "leading":
			@warning_ignore("integer_division")
			cost = cost * 6 / 10
		@warning_ignore("integer_division")
		var per: int = cost / maxi(1, int(ld["build_q"]))
		var v2: int = mini(per, gov_left)
		gov_left -= v2
		if v2 > 0:
			econ.add_job(-1, l, st.l_region[l], v2, 0)


func _private_funds() -> int:
	var tot: int = 0
	var C: int = ct.c_n
	for r: int in ct.r_n:
		for c: int in C:
			if ct.c_invest[c] == 1:
				var k: int = r * C + c
				tot += maxi(0, st.savings[k] - JCMath.mulppm(st.spend[k], ct.c_buffer[c]))
	return tot


## 经济结算之后：按到位率推进，完工的转为在用。
func after_economy() -> void:
	for j: int in econ.job_value.size():
		var fill: int = econ.job_fill[j]
		var v: int = econ.job_value[j]
		var i: int = econ.job_stack[j]
		if i >= 0:
			var b: int = st.s_b[i]
			var total: int
			if st.s_status[i] == JCState.ST_UPGRADE:
				total = upgrade_cost(i, st.s_target[i])
			else:
				total = level_cost(b, st.s_m[i], st.s_owner[i] == JCContent.OWNER_GOV) * maxi(1, st.s_pending[i])
			var needq: int = maxi(1, st.s_needq[i])
			# 进度（ppm·季）：本季实付 ÷ 每季应付
			@warning_ignore("integer_division")
			var per_q: int = maxi(1, total / needq)
			var step: int = JCMath.muldiv(JCMath.mulppm(v, fill), PPM, per_q)
			st.s_prog[i] += mini(step, PPM)
			if st.s_prog[i] >= needq * PPM:
				_complete(i)
		else:
			var l: int = econ.job_landmark[j]
			if l < 0:
				continue
			var ld: Dictionary = ct.landmarks[l]
			var cost: int = int(ld["cost_li"])
			@warning_ignore("integer_division")
			var per: int = maxi(1, cost / maxi(1, int(ld["build_q"])))
			st.l_prog[l] += mini(PPM, JCMath.muldiv(JCMath.mulppm(v, fill), PPM, per))
			if st.l_prog[l] >= int(ld["build_q"]) * PPM:
				var full: bool = st.lead_pick.size() > int(ld["era"]) and st.lead_pick[int(ld["era"])] == l
				if String(ld.get("kind", "")) == "achievement":
					full = true
				st.l_state[l] = 2 if full else 3
				st.note("landmark", "chron.landmark_done", {"landmark": String(ld["id"]), "full": full})


func _complete(i: int) -> void:
	var b: int = st.s_b[i]
	if st.s_status[i] == JCState.ST_UPGRADE:
		var old: int = st.s_m[i]
		st.s_m[i] = st.s_target[i]
		st.s_target[i] = -1
		st.s_status[i] = JCState.ST_ACTIVE
		st.s_prog[i] = 0
		st.s_needq[i] = 0
		# 同地区同类型同方法同所有者的堆合并成一行
		_merge_into_existing(i)
		st.note("build", "chron.upgrade_done", {"building": ct.b_id[b], "region": ct.r_id[st.s_region[i]],
				"method": ct.m_id[st.s_m[i]], "from": ct.m_id[old], "owner": st.s_owner[i]})
		return
	var add: int = st.s_pending[i]
	st.s_level[i] += add
	st.s_pending[i] = 0
	st.s_prog[i] = 0
	st.s_needq[i] = 0
	if st.s_status[i] == JCState.ST_NEW:
		st.s_status[i] = JCState.ST_ACTIVE
		st.s_u[i] = PPM
	st.note("build", "chron.build_done", {"building": ct.b_id[b], "region": ct.r_id[st.s_region[i]],
			"levels": add, "owner": st.s_owner[i]})


func _merge_into_existing(i: int) -> void:
	for k: int in st.stack_count():
		if k == i:
			continue
		if st.s_region[k] == st.s_region[i] and st.s_b[k] == st.s_b[i] and st.s_m[k] == st.s_m[i] \
				and st.s_owner[k] == st.s_owner[i] and st.s_status[k] == JCState.ST_ACTIVE and st.s_pending[k] == 0:
			st.s_level[k] += st.s_level[i]
			st.s_level[i] = 0
			return


# ── 民间投资 ────────────────────────────────────────────────────────────
## 每级每季的理论利润（按现价、现工钱、本地区物流费；过时方法计入落后减产）。
func level_profit(b: int, m: int, r: int) -> int:
	var C: int = ct.c_n
	var og: PackedInt64Array = ct.m_out_g[m]
	var oq: PackedInt64Array = ct.m_out_q[m]
	var rev: int = 0
	var mult: int = PPM
	if ct.b_cat[b] == JCContent.CAT_FARM:
		mult = mods.mult_ppm("farm_yield", ct.r_id[r])
	var pen: int = econ.obsolete_penalty(b, m, int(ct.obsolescence.get("per_year", 3)) * 10_000,
			int(ct.obsolescence.get("cap", 30)) * 10_000) if econ.st != null else 0
	mult = JCMath.mulppm(mult, PPM - pen)
	for k: int in og.size():
		rev += JCMath.value(JCMath.mulppm(oq[k], mult), st.price[og[k]])
	rev -= JCMath.mulppm(rev, st.logistics[r] if st.logistics.size() > r else ct.r_logistics[r])
	var cost: int = ct.b_maint[b]
	var ig: PackedInt64Array = ct.m_in_g[m]
	var iq: PackedInt64Array = ct.m_in_q[m]
	for k2: int in ig.size():
		cost += JCMath.value(iq[k2], st.price[ig[k2]])
	for c: int in C:
		cost += ct.m_labor[m * C + c] * st.wage[r * C + c]
	var cat: int = ct.b_cat[b]
	if cat == JCContent.CAT_FARM and ct.b_land[b] >= 0 and ct.b_land[b] <= 2:
		cost += JCMath.mulppm(JCMath.mulppm(rev, st.tax_land_ppm), PPM - st.hidden[r])
	elif cat == JCContent.CAT_WORKSHOP or cat == JCContent.CAT_MINE:
		cost += JCMath.mulppm(rev, st.tax_commerce_ppm)
	return rev - cost


## 已有同类堆的实际利润（每级每季，平均）；没有返回 null 标记 −2^62。
func realized_profit(b: int, m: int, r: int) -> int:
	var sum: int = 0
	var lv: int = 0
	for i: int in st.stack_count():
		if st.s_b[i] == b and st.s_m[i] == m and st.s_status[i] == JCState.ST_ACTIVE and st.s_level[i] > 0:
			if r >= 0 and st.s_region[i] != r:
				continue
			sum += st.s_profit[i]
			lv += st.s_level[i]
	if lv <= 0:
		return -(1 << 62)
	@warning_ignore("integer_division")
	return sum / lv


## 该商品本季还能再卖多少（缺口 + 进口替代 + 伙伴还想要的量），给民间投资估销路。
func market_room(g: int) -> int:
	var room: int = st.f_unmet[g] + st.f_imp[g] - _pending_output(g)
	for p: int in ct.partners.size():
		if st.p_active[p] != 1:
			continue
		var wants: Dictionary = ct.partners[p].get("wants", {})
		if wants.has(ct.g_id[g]):
			room += maxi(0, int(wants[ct.g_id[g]][1]) / 2 - st.f_exp[g] / maxi(1, _wanters(g)))
	if st.premium[g] > 100_000:
		room += JCMath.mulppm(st.f_demand[g], st.premium[g] / 4)
	# 库存积压则减
	room -= maxi(0, st.stock[g] - st.f_demand[g])
	return room


## 在建（和改造中）的产能：每季还会多出多少该商品。
func _pending_output(g: int) -> int:
	var q: int = 0
	for i: int in st.stack_count():
		var m: int = st.s_target[i] if st.s_status[i] == JCState.ST_UPGRADE and st.s_target[i] >= 0 else st.s_m[i]
		var lv: int = st.s_pending[i]
		if lv <= 0:
			continue
		var og: PackedInt64Array = ct.m_out_g[m]
		for k: int in og.size():
			if og[k] == g:
				q += ct.m_out_q[m][k] * lv
	return q


## 某地区某类设施：在用级数与在建级数。
func _levels_of(b: int, r: int) -> Vector2i:
	var lv: int = 0
	var pend: int = 0
	for i: int in st.stack_count():
		if st.s_b[i] == b and st.s_region[i] == r:
			lv += st.s_level[i]
			pend += st.s_pending[i]
	return Vector2i(lv, pend)


func _wanters(g: int) -> int:
	var n: int = 0
	for p: int in ct.partners.size():
		if st.p_active[p] == 1 and ct.partners[p].get("wants", {}).has(ct.g_id[g]):
			n += 1
	return n


func private_invest() -> void:
	var funds: int = JCMath.mulppm(_private_funds(), JCMath.mulppm(INVEST_RATE_PPM, mods.mult_ppm("invest_prop")))
	# 已在建的民间项目先占用
	for i: int in st.stack_count():
		if st.s_fund[i] == 1 and (st.s_pending[i] > 0 or st.s_status[i] == JCState.ST_UPGRADE):
			funds -= level_cost(st.s_b[i], st.s_m[i], false) / 4
	if funds <= 0:
		return
	var cands: Array = []
	var room_used: Dictionary = {}
	for b: int in ct.b_n:
		if (ct.b_owners[b] & 1) == 0 or not building_unlocked(b):
			continue
		var cat: int = ct.b_cat[b]
		if cat == JCContent.CAT_PUBLIC:
			continue
		for m: int in current_methods(b):
			for r: int in ct.r_n:
				if check_site(b, r, 1) != "":
					continue
				var roi: int = _roi(b, m, r)
				if roi > HURDLE_PPM:
					cands.append([roi, b, m, r, 0])
	# 升级候选
	for i2: int in st.stack_count():
		if st.s_owner[i2] != JCContent.OWNER_PRIVATE or st.s_status[i2] != JCState.ST_ACTIVE or st.s_pending[i2] > 0:
			continue
		var nm: int = newer_method(i2)
		if nm < 0:
			continue
		var gain: int = level_profit(st.s_b[i2], nm, st.s_region[i2]) - level_profit(st.s_b[i2], st.s_m[i2], st.s_region[i2])
		if gain <= 0:
			continue
		var cost: int = upgrade_cost(i2, nm)
		var roi2: int = JCMath.ratio_ppm(gain * 4 * st.s_level[i2], maxi(cost, 1), 0)
		if roi2 > HURDLE_PPM:
			cands.append([roi2, st.s_b[i2], nm, st.s_region[i2], i2 + 1])
	cands.sort_custom(func(a: Array, b2: Array) -> bool:
		return a[0] > b2[0] or (a[0] == b2[0] and (a[1] < b2[1] or (a[1] == b2[1] and a[3] < b2[3]))))
	var started: int = 0
	for c: Array in cands:
		if started >= MAX_NEW or funds <= 0:
			break
		var b3: int = c[1]
		var m3: int = c[2]
		var r3: int = c[3]
		var up: int = c[4]
		if up > 0:
			var i3: int = up - 1
			var cost3: int = upgrade_cost(i3, m3)
			start_upgrade(i3, m3)
			funds -= cost3
			started += 1
			st.note("invest", "chron.private_upgrade", {"building": ct.b_id[b3], "region": ct.r_id[r3],
					"method": ct.m_id[m3]})
			continue
		# 同一商品本季已有人投，销路按已投的量扣减
		var og: PackedInt64Array = ct.m_out_g[m3]
		if not og.is_empty():
			var g: int = og[0]
			var room: int = market_room(g) - int(room_used.get(g, 0))
			if room <= JCMath.mulppm(ct.m_out_q[m3][0], 300_000) and ct.b_cat[b3] != JCContent.CAT_INFRA:
				continue
			room_used[g] = int(room_used.get(g, 0)) + ct.m_out_q[m3][0]
		elif room_used.has(-b3 - 1):
			continue
		room_used[-b3 - 1] = 1
		var lc: int = level_cost(b3, m3, false)
		start_build(b3, r3, JCContent.OWNER_PRIVATE, m3, 1)
		funds -= lc
		started += 1
		st.note("invest", "chron.private_build", {"building": ct.b_id[b3], "region": ct.r_id[r3],
				"method": ct.m_id[m3]})


func _roi(b: int, m: int, r: int) -> int:
	var cost: int = level_cost(b, m, false)
	if cost <= 0:
		return 0
	var theo: int = level_profit(b, m, r)
	var real: int = realized_profit(b, m, r)
	var prof: int = theo
	if real > -(1 << 61):
		prof = (theo + real) / 2
	var cat: int = ct.b_cat[b]
	if cat == JCContent.CAT_INFRA:
		# 服务设施：看本地区同类设施的实际利润（在建的也要分一份）；没有的话看全国的
		prof = realized_profit(b, m, r)
		if prof <= -(1 << 61):
			prof = realized_profit(b, m, -1)
			if prof <= -(1 << 61):
				return 0
			prof = JCMath.mulppm(prof, 800_000)
		var lp: Vector2i = _levels_of(b, r)
		if lp.x > 0:
			prof = JCMath.muldiv(prof, lp.x, lp.x + lp.y + 1)
	# 人手：本地区相关阶层的闲人够不够
	var C: int = ct.c_n
	var util: int = PPM
	for c: int in C:
		var need: int = ct.m_labor[m * C + c]
		if need <= 0:
			continue
		var k: int = r * C + c
		var idle: int = maxi(0, JCMath.mulppm(st.pop[k], ct.c_work[c]) - st.employed[k])
		util = mini(util, maxi(300_000, JCMath.ratio_ppm(idle, need)))
	# 原料：本季这些投入作为生产投入实际到了几成（主料缺多少算多少；辅料按份额）
	var ig: PackedInt64Array = ct.m_in_g[m]
	var sh: PackedInt64Array = ct.m_in_share[m]
	for k2: int in ig.size():
		var g: int = ig[k2]
		var f: int = econ.in_fill[g] if econ.in_fill.size() > g else PPM
		if sh[k2] < JCEconomy.MAIN_INPUT_PPM:
			f = PPM - JCMath.mulppm(sh[k2], PPM - f)
		util = mini(util, f)
	prof = JCMath.mulppm(prof, util)
	var roi: int = JCMath.ratio_ppm(prof * 4, cost, 0)
	if cat == JCContent.CAT_WORKSHOP:
		roi = JCMath.mulppm(roi, mods.mult_ppm("invest_workshop"))
	return roi


## 连亏的民营建筑缩小一级；规模为 0 的在季末清掉。
func closures() -> void:
	# 各商品还在开工的级数：某商品还有人要、而这里是最后一级产能时不关（亏损由东家扛着，等价钱回来）
	var live: PackedInt64Array = JCMath.zeros(ct.g_n)
	for i0: int in st.stack_count():
		if st.s_status[i0] != JCState.ST_ACTIVE:
			continue
		for g0: int in ct.m_out_g[st.s_m[i0]]:
			live[g0] += st.s_level[i0]
	for i: int in st.stack_count():
		if st.s_owner[i] != JCContent.OWNER_PRIVATE or st.s_status[i] != JCState.ST_ACTIVE:
			continue
		var last: bool = false
		for g1: int in ct.m_out_g[st.s_m[i]]:
			if live[g1] <= 1 and st.f_demand[g1] > 0:
				last = true
		if last:
			continue
		if st.s_loss[i] >= CLOSE_AFTER and st.s_level[i] > 0:
			for g2: int in ct.m_out_g[st.s_m[i]]:
				live[g2] -= 1
			st.s_level[i] -= 1
			st.s_loss[i] = CLOSE_AFTER / 2
			st.note("invest", "chron.private_close", {"building": ct.b_id[st.s_b[i]],
					"region": ct.r_id[st.s_region[i]], "left": st.s_level[i]})
