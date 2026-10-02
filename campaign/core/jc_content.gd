## v2 内容：读 content_v2/*.json，建下标数组与 ID 索引（docs/57）。
## 内容只读；不进存档（存档只记内容指纹，读档时核对）。
class_name JCContent
extends RefCounted

const ROOT: String = "res://content_v2/"
const LAND_TYPES: PackedStringArray = ["paddy", "dry", "slope", "forest", "pasture", "coast"]
const LT_N: int = 6
const SECTORS: PackedStringArray = ["agri", "manu", "energy", "serv"]
const CATS: PackedStringArray = ["farm", "mine", "workshop", "infra", "public"]
const CAT_FARM: int = 0
const CAT_MINE: int = 1
const CAT_WORKSHOP: int = 2
const CAT_INFRA: int = 3
const CAT_PUBLIC: int = 4
const OWNER_PRIVATE: int = 0
const OWNER_GOV: int = 1

var content_hash: String = ""
var errors: PackedStringArray = PackedStringArray()

# ── 商品 ──
var g_n: int = 0
var g_id: PackedStringArray = PackedStringArray()
var g_name: PackedStringArray = PackedStringArray()
var g_unit: PackedStringArray = PackedStringArray()
var g_art: PackedStringArray = PackedStringArray()
var g_note: PackedStringArray = PackedStringArray()
var g_sector: PackedInt64Array = PackedInt64Array()
var g_tier: PackedInt64Array = PackedInt64Array()
var g_era: PackedInt64Array = PackedInt64Array()
var g_era_end: PackedInt64Array = PackedInt64Array()
var g_perish: PackedInt64Array = PackedInt64Array()
var g_base: PackedInt64Array = PackedInt64Array()
var g_durable: PackedInt64Array = PackedInt64Array()
var gidx: Dictionary = {}

# ── 阶层 ──
var c_n: int = 0
var c_id: PackedStringArray = PackedStringArray()
var c_name: PackedStringArray = PackedStringArray()
var c_note: PackedStringArray = PackedStringArray()
var c_wage: PackedInt64Array = PackedInt64Array()
var c_work: PackedInt64Array = PackedInt64Array()
var c_save: PackedInt64Array = PackedInt64Array()
## 想留在手上的积蓄（几个季度的开销，ppm）
var c_buffer: PackedInt64Array = PackedInt64Array()
var c_invest: PackedInt64Array = PackedInt64Array()
var cidx: Dictionary = {}

# ── 需要 ──
var n_n: int = 0
var n_id: PackedStringArray = PackedStringArray()
var n_name: PackedStringArray = PackedStringArray()
var n_ess: PackedInt64Array = PackedInt64Array()
var n_weight: PackedInt64Array = PackedInt64Array()
## 随日用水平的弹性（500000 / 1000000 / 1500000）
var n_el: PackedInt64Array = PackedInt64Array()
## 农户自产自食（不付零售加价）
var n_own: PackedInt64Array = PackedInt64Array()
## 商品是否属于某项「自产自食」的需要（农户买它不付加价）
var g_own: PackedInt64Array = PackedInt64Array()
var n_era: PackedInt64Array = PackedInt64Array()
var n_era_end: PackedInt64Array = PackedInt64Array()
var n_goods: Array[PackedInt64Array] = []
var n_conv: Array[PackedInt64Array] = []
## n * c_n + c：每人每季需要量（千分单位的「需要单位」）
var n_qty: PackedInt64Array = PackedInt64Array()
## 每项需要：长 r_n 的数组，每个元素是 {商品下标: 份额 ppm}；空字典表示用全国统一份额
var n_taste: Array = []
var nidx: Dictionary = {}

# ── 地区 ──
var r_n: int = 0
var r_id: PackedStringArray = PackedStringArray()
var r_name: PackedStringArray = PackedStringArray()
var r_desc: PackedStringArray = PackedStringArray()
var r_river: PackedInt64Array = PackedInt64Array()
var r_coast: PackedInt64Array = PackedInt64Array()
var r_capital: PackedInt64Array = PackedInt64Array()
var r_logistics: PackedInt64Array = PackedInt64Array()
## 各地区地租率（农田利润里归士绅的份额，ppm）
var r_rent: PackedInt64Array = PackedInt64Array()
## r * LT_N + lt
var r_land: PackedInt64Array = PackedInt64Array()
var r_deposit: Array[Dictionary] = []
## r * c_n + c
var r_pop: PackedInt64Array = PackedInt64Array()
var ridx: Dictionary = {}

# ── 建筑 ──
var b_n: int = 0
var b_id: PackedStringArray = PackedStringArray()
var b_name: PackedStringArray = PackedStringArray()
var b_note: PackedStringArray = PackedStringArray()
var b_cat: PackedInt64Array = PackedInt64Array()
var b_sector: PackedInt64Array = PackedInt64Array()
## 位 0：民营可建；位 1：官办可建
var b_owners: PackedInt64Array = PackedInt64Array()
var b_land: PackedInt64Array = PackedInt64Array()
var b_deposit: PackedStringArray = PackedStringArray()
var b_coast: PackedInt64Array = PackedInt64Array()
var b_cost: PackedInt64Array = PackedInt64Array()
var b_maint: PackedInt64Array = PackedInt64Array()
var b_build_q: PackedInt64Array = PackedInt64Array()
var b_era: PackedInt64Array = PackedInt64Array()
var b_tech: PackedInt64Array = PackedInt64Array()
var b_effects: Array[Dictionary] = []
var b_art: Array[Dictionary] = []
var b_methods: Array[PackedInt64Array] = []
var bidx: Dictionary = {}

# ── 生产方式 ──
var m_n: int = 0
var m_id: PackedStringArray = PackedStringArray()
var m_name: PackedStringArray = PackedStringArray()
var m_b: PackedInt64Array = PackedInt64Array()
var m_era: PackedInt64Array = PackedInt64Array()
var m_era_end: PackedInt64Array = PackedInt64Array()
var m_tech: PackedInt64Array = PackedInt64Array()
var m_water: PackedInt64Array = PackedInt64Array()
var m_upcost: PackedInt64Array = PackedInt64Array()
var m_upq: PackedInt64Array = PackedInt64Array()
var m_eff: PackedInt64Array = PackedInt64Array()
var m_out_g: Array[PackedInt64Array] = []
var m_out_q: Array[PackedInt64Array] = []
var m_in_g: Array[PackedInt64Array] = []
var m_in_q: Array[PackedInt64Array] = []
## m * c_n + c
var m_labor: PackedInt64Array = PackedInt64Array()
## 各投入占投入总值的份额（按基准价，ppm）：份额小于四分之一的算「辅料」，缺了只按份额减产
var m_in_share: Array[PackedInt64Array] = []
## 生产层级：产出商品的最高层级（同季按层级从低到高生产）
var m_tier: PackedInt64Array = PackedInt64Array()
var midx: Dictionary = {}
## 维护与营造用料（按本国时代 1..4）：商品下标与价值份额 ppm
var maint_g_era: Array = []
var maint_ppm_era: Array = []
var build_g_era: Array = []
var build_ppm_era: Array = []

# ── 科技 ──
var t_n: int = 0
var t_id: PackedStringArray = PackedStringArray()
var t_name: PackedStringArray = PackedStringArray()
var t_desc: PackedStringArray = PackedStringArray()
var t_era: PackedInt64Array = PackedInt64Array()
var t_cost: PackedInt64Array = PackedInt64Array()
var t_key: PackedInt64Array = PackedInt64Array()
var t_prereq: Array[PackedInt64Array] = []
var t_bg: Array[PackedInt64Array] = []
var t_effects: Array = []
var tidx: Dictionary = {}
## 伙伴掌握科技的顺序：时代 → 科技下标数组
var tech_order: Dictionary = {}

# ── 其余（保留原始字典，按需取用） ──
var eras: Array = []
var obsolescence: Dictionary = {}
var decrees: Array = []
var didx: Dictionary = {}
var partners: Array = []
var pidx: Dictionary = {}
var landmarks: Array = []
var lidx: Dictionary = {}
var events: Array = []
var eidx: Dictionary = {}
## 政治：政体（下标 = 「政体」政令的档位）、改革局势、改革关口、外部局势、压力参数
var regimes: Array = []
var regidx: Dictionary = {}
var reforms: Array = []
var refidx: Dictionary = {}
var reform_stages: Array = []
var crises: Dictionary = {}
var pressure: Dictionary = {}
var scenario: Dictionary = {}


static func load_default() -> JCContent:
	var c: JCContent = JCContent.new()
	c.load_from(ROOT)
	return c


func ok() -> bool:
	return errors.is_empty()


func load_from(root: String) -> bool:
	errors = PackedStringArray()
	var meta: Dictionary = _read(root + "meta.json")
	content_hash = String(meta.get("content_hash", ""))
	var goods: Dictionary = _read(root + "goods.json")
	var society: Dictionary = _read(root + "society.json")
	var buildings: Dictionary = _read(root + "buildings.json")
	var progress: Dictionary = _read(root + "progress.json")
	scenario = _read(root + "scenario.json")
	if not errors.is_empty():
		return false
	_load_goods(goods.get("goods", []))
	_load_classes(society.get("classes", []))
	_load_regions(scenario.get("regions", []))
	_load_needs(society.get("needs", []))
	_load_techs(progress.get("techs", []))
	_load_buildings(buildings.get("buildings", []))
	_load_mixes(buildings.get("maint_mix", {}), maint_g_era, maint_ppm_era)
	_load_mixes(buildings.get("build_mix", {}), build_g_era, build_ppm_era)
	eras = progress.get("eras", [])
	obsolescence = progress.get("obsolescence", {})
	decrees = progress.get("decrees", [])
	for i: int in decrees.size():
		didx[String(decrees[i]["id"])] = i
	partners = progress.get("partners", [])
	for i: int in partners.size():
		pidx[String(partners[i]["id"])] = i
	landmarks = progress.get("landmarks", [])
	for i: int in landmarks.size():
		lidx[String(landmarks[i]["id"])] = i
	events = progress.get("events", [])
	for i: int in events.size():
		eidx[String(events[i]["id"])] = i
	regimes = progress.get("regimes", [])
	for i: int in regimes.size():
		regidx[String(regimes[i]["id"])] = i
	reforms = progress.get("reforms", [])
	for i: int in reforms.size():
		refidx[String(reforms[i]["id"])] = i
	reform_stages = progress.get("reform_stages", [])
	crises = progress.get("crises", {})
	pressure = progress.get("pressure", {})
	var to: Dictionary = progress.get("tech_order", {})
	for k: Variant in to.keys():
		var arr: PackedInt64Array = PackedInt64Array()
		for tid: Variant in to[k]:
			arr.append(int(tidx.get(String(tid), -1)))
		tech_order[int(String(k))] = arr
	_compute_ranks()
	_check_refs()
	return errors.is_empty()


## 生产次序：一个生产方式的「秩」= 1 + 它的非耐用投入商品的秩的最大值；商品的秩 = 它的生产方式的秩的最大值。
## 耐用投入（农具、役畜、船只、机械、电动机）不参与排序——它们取季初库存，由此打破产业链里的环。
var m_rank: PackedInt64Array = PackedInt64Array()
var g_rank: PackedInt64Array = PackedInt64Array()
## 按秩从低到高排好的生产方式下标（同秩按下标）
var m_order: PackedInt64Array = PackedInt64Array()


func _compute_ranks() -> void:
	m_rank = JCMath.zeros(m_n)
	g_rank = JCMath.zeros(g_n)
	for it: int in 24:
		var changed: bool = false
		for m: int in m_n:
			var r: int = 0
			var ig: PackedInt64Array = m_in_g[m]
			for k: int in ig.size():
				var g: int = ig[k]
				if g_durable[g] == 1:
					continue
				r = maxi(r, g_rank[g] + 1)
			if r != m_rank[m]:
				m_rank[m] = r
				changed = true
		for m2: int in m_n:
			var og: PackedInt64Array = m_out_g[m2]
			for k2: int in og.size():
				var g2: int = og[k2]
				if m_rank[m2] > g_rank[g2]:
					g_rank[g2] = m_rank[m2]
					changed = true
		if not changed:
			break
	var idx: Array = []
	for m3: int in m_n:
		idx.append(m3)
	idx.sort_custom(func(a: int, b: int) -> bool:
		return m_rank[a] < m_rank[b] or (m_rank[a] == m_rank[b] and a < b))
	for m4: Variant in idx:
		m_order.append(int(m4))


func _read(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("读不到内容文件：" + path)
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		errors.append("内容文件不是 JSON 对象：" + path)
		return {}
	return d


func _load_goods(lst: Array) -> void:
	g_n = lst.size()
	for i: int in g_n:
		var g: Dictionary = lst[i]
		var id: String = String(g["id"])
		gidx[id] = i
		g_id.append(id)
		g_name.append(String(g["name"]))
		g_unit.append(String(g["unit"]))
		g_art.append(String(g.get("art", "")))
		g_note.append(String(g.get("note", "")))
		g_sector.append(maxi(SECTORS.find(String(g["sector"])), 0))
		g_tier.append(int(g["tier"]))
		g_era.append(int(g["era"]))
		g_era_end.append(int(g["era_end"]))
		g_perish.append(int(g["perish_ppm"]))
		g_base.append(int(g["base_price_li"]))
		g_durable.append(1 if bool(g.get("durable", false)) else 0)


func _load_classes(lst: Array) -> void:
	c_n = lst.size()
	for i: int in c_n:
		var c: Dictionary = lst[i]
		var id: String = String(c["id"])
		cidx[id] = i
		c_id.append(id)
		c_name.append(String(c["name"]))
		c_note.append(String(c.get("note", "")))
		c_wage.append(int(c["base_wage_li"]))
		c_work.append(int(c["work_ppm"]))
		c_save.append(int(c["save_ppm"]))
		c_buffer.append(int(c.get("buffer_ppm", 2_000_000)))
		c_invest.append(1 if bool(c.get("invest", false)) else 0)


func _load_regions(lst: Array) -> void:
	r_n = lst.size()
	r_land = JCMath.zeros(r_n * LT_N)
	r_pop = JCMath.zeros(r_n * c_n)
	for i: int in r_n:
		var r: Dictionary = lst[i]
		var id: String = String(r["id"])
		ridx[id] = i
		r_id.append(id)
		r_name.append(String(r["name"]))
		r_desc.append(String(r.get("desc", "")))
		r_river.append(1 if bool(r.get("river", false)) else 0)
		r_coast.append(1 if bool(r.get("coast", false)) else 0)
		r_capital.append(1 if bool(r.get("capital", false)) else 0)
		r_logistics.append(int(r["logistics_ppm"]))
		r_rent.append(int(r.get("rent_ppm", 420000)))
		var land: Dictionary = r.get("land", {})
		for lt: int in LT_N:
			r_land[i * LT_N + lt] = int(land.get(LAND_TYPES[lt], 0))
		var dep: Dictionary = {}
		var d0: Dictionary = r.get("deposit", {})
		for k: Variant in d0.keys():
			dep[String(k)] = int(d0[k])
		r_deposit.append(dep)
		var pop: Dictionary = r.get("pop", {})
		for c: int in c_n:
			r_pop[i * c_n + c] = int(pop.get(c_id[c], 0))


func _load_needs(lst: Array) -> void:
	n_n = lst.size()
	n_qty = JCMath.zeros(n_n * c_n)
	g_own = JCMath.zeros(g_n)
	for i: int in n_n:
		var n: Dictionary = lst[i]
		var id: String = String(n["id"])
		nidx[id] = i
		n_id.append(id)
		n_name.append(String(n["name"]))
		n_ess.append(1 if bool(n.get("essential", false)) else 0)
		n_weight.append(int(n["weight"]))
		n_el.append(int(n.get("el_ppm", 1_000_000)))
		n_own.append(1 if bool(n.get("own_food", false)) else 0)
		n_era.append(int(n["era"]))
		n_era_end.append(int(n.get("era_end", 4)))
		var gs: PackedInt64Array = PackedInt64Array()
		var cv: PackedInt64Array = PackedInt64Array()
		var goods: Dictionary = n.get("goods", {})
		for gk: Variant in goods.keys():
			var gi: int = int(gidx.get(String(gk), -1))
			if gi < 0:
				errors.append("需要 %s 引用了未知商品 %s" % [id, gk])
				continue
			gs.append(gi)
			cv.append(int(goods[gk]))
		n_goods.append(gs)
		n_conv.append(cv)
		if n_own[i] == 1:
			for gi3: int in gs:
				g_own[gi3] = 1
		var qty: Dictionary = n.get("qty", {})
		for c: int in c_n:
			n_qty[i * c_n + c] = int(qty.get(c_id[c], 0))
		var tastes: Array = []
		var t0: Dictionary = n.get("taste", {})
		for r: int in r_n:
			var d: Dictionary = {}
			var t1: Variant = t0.get(r_id[r], null)
			if typeof(t1) == TYPE_DICTIONARY:
				for gk2: Variant in (t1 as Dictionary).keys():
					var gi2: int = int(gidx.get(String(gk2), -1))
					if gi2 >= 0:
						d[gi2] = int(t1[gk2])
			tastes.append(d)
		n_taste.append(tastes)


func _load_techs(lst: Array) -> void:
	t_n = lst.size()
	for i: int in t_n:
		tidx[String(lst[i]["id"])] = i
	for i: int in t_n:
		var t: Dictionary = lst[i]
		t_id.append(String(t["id"]))
		t_name.append(String(t["name"]))
		t_desc.append(String(t.get("desc", "")))
		t_era.append(int(t["era"]))
		t_cost.append(int(t["cost"]))
		t_key.append(1 if bool(t.get("key", false)) else 0)
		var pre: PackedInt64Array = PackedInt64Array()
		for p: Variant in t.get("prereq", []):
			pre.append(int(tidx.get(String(p), -1)))
		t_prereq.append(pre)
		t_effects.append(t.get("effects", []))
	# 国内背景要等建筑读完再解析
	for i: int in t_n:
		t_bg.append(PackedInt64Array())


func _load_buildings(lst: Array) -> void:
	b_n = lst.size()
	for i: int in b_n:
		bidx[String(lst[i]["id"])] = i
	for i: int in b_n:
		var b: Dictionary = lst[i]
		var id: String = String(b["id"])
		b_id.append(id)
		b_name.append(String(b["name"]))
		b_note.append(String(b.get("note", "")))
		b_cat.append(maxi(CATS.find(String(b["category"])), 0))
		b_sector.append(maxi(SECTORS.find(String(b["sector"])), 0))
		var mask: int = 0
		for o: Variant in b.get("owners", []):
			if String(o) == "private":
				mask |= 1
			elif String(o) == "gov":
				mask |= 2
		b_owners.append(mask)
		b_land.append(LAND_TYPES.find(String(b.get("land", ""))))
		b_deposit.append(String(b.get("deposit", "")))
		b_coast.append(1 if bool(b.get("coast", false)) else 0)
		b_cost.append(int(b["cost_li"]))
		b_maint.append(int(b["maint_li"]))
		b_build_q.append(int(b["build_q"]))
		b_era.append(int(b["era"]))
		b_tech.append(int(tidx.get(String(b.get("tech", "")), -1)))
		var eff: Dictionary = {}
		var e0: Dictionary = b.get("effects", {})
		for k: Variant in e0.keys():
			eff[String(k)] = int(e0[k])
		b_effects.append(eff)
		var art: Dictionary = {}
		var a0: Dictionary = b.get("art", {})
		for k2: Variant in a0.keys():
			art[int(String(k2))] = String(a0[k2])
		b_art.append(art)
		var ms: PackedInt64Array = PackedInt64Array()
		for m: Dictionary in b.get("methods", []):
			ms.append(_add_method(m, i))
		b_methods.append(ms)
	# 科技的国内背景
	var raw: Array = []
	var prog: Dictionary = _read(ROOT + "progress.json")
	raw = prog.get("techs", [])
	for i: int in mini(raw.size(), t_n):
		var bg: PackedInt64Array = PackedInt64Array()
		for x: Variant in raw[i].get("bg", []):
			var bi: int = int(bidx.get(String(x), -1))
			if bi >= 0:
				bg.append(bi)
		t_bg[i] = bg


func _add_method(m: Dictionary, b: int) -> int:
	var i: int = m_n
	m_n += 1
	var id: String = String(m["id"])
	midx[id] = i
	m_id.append(id)
	m_name.append(String(m["name"]))
	m_b.append(b)
	m_era.append(int(m["era"]))
	m_era_end.append(int(m.get("era_end", 4)))
	m_tech.append(int(tidx.get(String(m.get("tech", "")), -1)))
	m_water.append(1 if bool(m.get("water", false)) else 0)
	m_upcost.append(int(m.get("upgrade_cost_ppm", 350000)))
	m_upq.append(int(m.get("upgrade_q", 2)))
	m_eff.append(int(m.get("eff_ppm", 1000000)))
	var og: PackedInt64Array = PackedInt64Array()
	var oq: PackedInt64Array = PackedInt64Array()
	var tier: int = 0
	var out: Dictionary = m.get("out", {})
	for gk: Variant in out.keys():
		var gi: int = int(gidx.get(String(gk), -1))
		if gi < 0:
			errors.append("生产方式 %s 引用了未知商品 %s" % [id, gk])
			continue
		og.append(gi)
		oq.append(int(out[gk]))
		tier = maxi(tier, g_tier[gi])
	m_out_g.append(og)
	m_out_q.append(oq)
	m_tier.append(tier)
	var ig: PackedInt64Array = PackedInt64Array()
	var iq: PackedInt64Array = PackedInt64Array()
	var inp: Dictionary = m.get("inp", {})
	for gk2: Variant in inp.keys():
		var gi2: int = int(gidx.get(String(gk2), -1))
		if gi2 < 0:
			errors.append("生产方式 %s 引用了未知商品 %s" % [id, gk2])
			continue
		ig.append(gi2)
		iq.append(int(inp[gk2]))
	m_in_g.append(ig)
	m_in_q.append(iq)
	var lab: Dictionary = m.get("labor", {})
	var lab_v: int = 0
	for c: int in c_n:
		m_labor.append(int(lab.get(c_id[c], 0)))
		lab_v += int(lab.get(c_id[c], 0)) * c_wage[c]
	# 投入占「投入 + 工钱」（按基准价与基准工钱）的份额：份额大的是主料，缺多少减多少；
	# 份额小的是辅料（农田的役畜与农具、船坞的铜钉……），缺了只减一部分
	var tot_v: int = lab_v
	for kk: int in ig.size():
		tot_v += JCMath.value(iq[kk], g_base[ig[kk]])
	var shares: PackedInt64Array = PackedInt64Array()
	for kk2: int in ig.size():
		shares.append(JCMath.ratio_ppm(JCMath.value(iq[kk2], g_base[ig[kk2]]), maxi(1, tot_v)))
	m_in_share.append(shares)
	return i


func _check_refs() -> void:
	for i: int in t_n:
		for p: int in t_prereq[i]:
			if p < 0:
				errors.append("科技 %s 的前置不存在" % t_id[i])
	for s: Dictionary in scenario.get("stacks", []):
		if not bidx.has(String(s["building"])) or not midx.has(String(s["method"])) \
				or not ridx.has(String(s["region"])):
			errors.append("开局建筑引用不存在：" + JSON.stringify(s))


# ── 查询 ────────────────────────────────────────────────────────────────

func method_of(b: int, k: int) -> int:
	return b_methods[b][k]


## 某建筑在给定时代应显示的配图路径。
func building_art(b: int, era: int) -> String:
	var d: Dictionary = b_art[b]
	for e: int in range(era, 0, -1):
		if d.has(e):
			return String(d[e])
	return String(d.get(1, ""))


func labor(m: int, c: int) -> int:
	return m_labor[m * c_n + c]


func labor_total(m: int) -> int:
	var s: int = 0
	for c: int in c_n:
		s += m_labor[m * c_n + c]
	return s


## 某时代活跃的需要（era <= 时代 <= era_end）。
## 用料表：era 1..4 → 商品下标数组、份额数组（缺的时代沿用前一个）。
func _load_mixes(d: Dictionary, gs_out: Array, ppm_out: Array) -> void:
	gs_out.clear()
	ppm_out.clear()
	gs_out.append(PackedInt64Array())
	ppm_out.append(PackedInt64Array())
	for era: int in range(1, 5):
		var mix: Variant = d.get(str(era), null)
		if typeof(mix) != TYPE_DICTIONARY:
			gs_out.append(gs_out[era - 1])
			ppm_out.append(ppm_out[era - 1])
			continue
		var gs: PackedInt64Array = PackedInt64Array()
		var ps: PackedInt64Array = PackedInt64Array()
		var keys: Array = (mix as Dictionary).keys()
		keys.sort()
		for gk: Variant in keys:
			var gi: int = int(gidx.get(String(gk), -1))
			if gi < 0:
				errors.append("用料表引用了未知商品 %s" % gk)
				continue
			gs.append(gi)
			ps.append(int(mix[gk]))
		gs_out.append(gs)
		ppm_out.append(ps)


func maint_g(era: int) -> PackedInt64Array:
	return maint_g_era[clampi(era, 1, 4)]


func maint_ppm(era: int) -> PackedInt64Array:
	return maint_ppm_era[clampi(era, 1, 4)]


func build_g(era: int) -> PackedInt64Array:
	return build_g_era[clampi(era, 1, 4)]


func build_ppm(era: int) -> PackedInt64Array:
	return build_ppm_era[clampi(era, 1, 4)]


func need_active(n: int, era: int) -> bool:
	return n_era[n] <= era and era <= n_era_end[n]


func good_active(g: int, era: int) -> bool:
	return g_era[g] <= era and era <= g_era_end[g] + 1
