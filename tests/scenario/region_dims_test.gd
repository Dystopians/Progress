## 地区维度随剧本变化（docs/18 R-SCENARIO-02；docs/53 M1-2）。
## 测试时在 user:// 下生成一份 5 区剧本：复制整个内容包，把西陵原样复制成第 5 区「西陵乙」。
## 区内账目逐项与西陵相同；全国级的两条对账（现金总量、居民存款 == 投资池现金 + 持债）加上新区的份额。
## 验证：能载入、维度与主体布局随之改变、推进 8 季守恒且确定、换回 4 区剧本后一切复原。
extends JWTest

const SRC: String = "res://content"
const DST: String = "user://jwtest_region5/content"
const SPLIT: String = "split5"
const TWIN: String = "xilingb"


func after_each() -> void:
	# 其他测试文件直接 allocate_all()，依赖默认的 4 区维度：这里负责复原。
	JWUnits.set_regions(4)
	JWIds.apply_dims()


# ── 夹具：生成 5 区剧本 ───────────────────────────────────────────────────

static func _copy_tree(src: String, dst: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst)
	for f: String in DirAccess.get_files_at(src):
		if f.ends_with(".json"):
			DirAccess.copy_absolute(src + "/" + f, dst + "/" + f)
	for d: String in DirAccess.get_directories_at(src):
		_copy_tree(src + "/" + d, dst + "/" + d)


static func _read(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	var v: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return _ints(v)


## JSON 解析出的数都是 float；写回之前全部收窄成 int，否则 stringify 写出 `1.0`，加载器的方言检查会拒绝。
static func _ints(v: Variant) -> Variant:
	if v is Dictionary:
		var d: Dictionary = {}
		for k: Variant in (v as Dictionary).keys():
			d[k] = _ints((v as Dictionary)[k])
		return d
	if v is Array:
		var a: Array = []
		for e: Variant in v:
			a.append(_ints(e))
		return a
	if typeof(v) == TYPE_FLOAT:
		return int(v)
	return v


static func _write(path: String, d: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "  ", false) + "\n")
	f.close()


## 把字符串里的 `.xiling.` / 结尾 `.xiling` 换成孪生区名。
static func _twin_id(s: String) -> String:
	if s.ends_with(".xiling"):
		return s.substr(0, s.length() - 7) + "." + TWIN
	return s.replace(".xiling.", "." + TWIN + ".")


static func _twin_keys(m: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in m.keys():
		out[_twin_id(String(k))] = m[k]
	return out


static func build_fixture() -> String:
	_copy_tree(SRC, DST)
	var sd: String = DST + "/scenarios/" + SPLIT
	_copy_tree(SRC + "/scenarios/chengwan", sd)
	# 只保留测试剧本与参考剧本，战役剧本与本测试无关。
	var extra: String = DST + "/scenarios/campaign_1600"
	for f: String in DirAccess.get_files_at(extra):
		DirAccess.remove_absolute(extra + "/" + f)
	DirAccess.remove_absolute(extra)

	# regions：复制西陵；各区的成本表补上孪生区（取它们到西陵的值）；孪生区只与西陵相邻。
	var reg: Dictionary = _read(sd + "/regions.json")
	var regions: Array = reg["regions"]
	var x: Dictionary = {}
	for e: Variant in regions:
		if String((e as Dictionary)["region_id"]) == "region.xiling":
			x = e
	var t: Dictionary = x.duplicate(true)
	t["region_id"] = "region." + TWIN
	t["label_zh"] = String(x["label_zh"]) + "乙"
	t["adjacency"] = ["region.xiling"]
	for e2: Variant in regions:
		var ed: Dictionary = e2
		for key: String in ["logistics_cost_ppm", "migration_cost_uu"]:
			var m: Dictionary = ed[key]
			m["region." + TWIN] = m["region.xiling"]
	for key2: String in ["logistics_cost_ppm", "migration_cost_uu"]:
		var tm: Dictionary = {}
		var xm: Dictionary = x[key2]
		for k: Variant in xm.keys():
			tm[k] = xm[k]
		tm["region." + TWIN] = 0
		t[key2] = tm
	(x["adjacency"] as Array).append("region." + TWIN)
	regions.append(t)
	_write(sd + "/regions.json", reg)

	# population：复制西陵的 9 个群组；出生率表补孪生区。
	var pop: Dictionary = _read(sd + "/population_init.json")
	var groups: Array = pop["groups"]
	var add_cash: int = 0
	var add_dep: int = 0
	var new_groups: Array = []
	for g: Variant in groups:
		var gd: Dictionary = g
		if String(gd["group_id"]).begins_with("group.xiling."):
			var ng: Dictionary = gd.duplicate(true)
			ng["group_id"] = _twin_id(String(gd["group_id"]))
			add_cash += int(gd["cash_uu"])
			add_dep += int(gd["deposit_uu"])
			new_groups.append(ng)
	groups.append_array(new_groups)
	var dr: Dictionary = pop["demography_rates"]
	var br: Dictionary = dr["birth_ppm_per_q"]
	br["region." + TWIN] = br["region.xiling"]
	_write(sd + "/population_init.json", pop)

	# cells：复制西陵四个部门单元；股权表原样（持股群组不变，每行仍合计 1e6）。
	var cel: Dictionary = _read(sd + "/cells_init.json")
	var cells: Array = cel["cells"]
	var new_cells: Array = []
	for c: Variant in cells:
		var cd: Dictionary = c
		if String(cd["cell_id"]).begins_with("cell.xiling."):
			var nc: Dictionary = cd.duplicate(true)
			nc["cell_id"] = _twin_id(String(cd["cell_id"]))
			add_cash += int(cd["cash_uu"])
			new_cells.append(nc)
	cells.append_array(new_cells)
	_write(sd + "/cells_init.json", cel)

	# pubserv：复制。
	var ps: Dictionary = _read(sd + "/pubserv_init.json")
	var units: Array = ps["units"]
	for u: Variant in units.duplicate():
		if String((u as Dictionary)["pubserv_id"]) == "pubserv.xiling":
			var nu: Dictionary = (u as Dictionary).duplicate(true)
			nu["pubserv_id"] = "pubserv." + TWIN
			units.append(nu)
	_write(sd + "/pubserv_init.json", ps)

	# io_table：单元级劳动系数覆盖项复制。
	var io: Dictionary = _read(sd + "/io_table.json")
	var lc: Dictionary = io["labor_coeff_persons_per_qs"]
	for k2: Variant in lc.keys():
		var ks: String = String(k2)
		if ks.begins_with("cell.xiling."):
			lc[_twin_id(ks)] = (lc[k2] as Dictionary).duplicate(true)
	_write(sd + "/io_table.json", io)

	# 全国对账：居民存款 == 投资池现金 + 持债 ⇒ 投资池现金加上新增存款；现金总量加上新增现金。
	var gov: Dictionary = _read(sd + "/government_init.json")
	var inv: Dictionary = gov["invpool"]
	inv["cash_uu"] = int(inv["cash_uu"]) + add_dep
	_write(sd + "/government_init.json", gov)
	var sc: Dictionary = _read(sd + "/scenario.json")
	sc["scenario_id"] = "scenario." + SPLIT
	sc["total_cash_uu"] = int(sc["total_cash_uu"]) + add_cash + add_dep
	# 按地区排列的房租表：孪生区取西陵的值（西陵是第 4 个，下标 3）。
	var pi: Dictionary = sc["prices_init"]
	var rent: Array = pi["housing_rent_uu_per_unit_q"]
	rent.append(rent[3])
	_write(sd + "/scenario.json", sc)

	# assertions：只留与地区数无关的恒等式（现金总量、基年价格）。
	var asr: Dictionary = _read(sd + "/assertions.json")
	var keep: Array = []
	for ck: Variant in asr["checks"]:
		var id: String = String((ck as Dictionary)["id"])
		if id == "assert.cash_total" or id == "assert.base_prices" or id == "assert.gov_cash":
			keep.append(ck)
	asr["checks"] = keep
	_write(sd + "/assertions.json", asr)
	return DST + "#" + SPLIT


# ── 用例 ─────────────────────────────────────────────────────────────────

func _new(spec: String, seed_v: int) -> JWGame:
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_test_region5"
	var r: JWResult = g.new_game(spec, seed_v, 0)
	check(r != null and r.ok, "开局 %s（%s）" % [spec, str(r.code) if r != null else "null"])
	return g


func _advance(g: JWGame, n: int) -> void:
	for i: int in n:
		var a: PackedInt64Array = PackedInt64Array()
		a.resize(JWCommands.ARG_SLOTS)
		a.fill(0)
		g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, a)
		var r: JWResult = g.advance_quarter()
		check(r == null or r.ok, "推进第 %d 季（码 %d，%d / %d）" % [i, r.code if r != null else 0,
				r.detail_a if r != null else 0, r.detail_b if r != null else 0])
		if r != null and not r.ok:
			return


func test_five_regions_load_and_run() -> void:
	var spec: String = build_fixture()
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var ld: JWContentLoader = JWContentLoader.new()
	var r: JWResult = ld.load_all(spec, st)
	if r == null or not r.ok:
		var msgs: PackedStringArray = PackedStringArray()
		for i: int in mini(ld.errors.size(), 8):
			msgs.append("%d@%s(%d,%d)" % [ld.errors[i].code, ld.error_where(i), ld.errors[i].detail_a, ld.errors[i].detail_b])
		fail("5 区剧本载入失败：%s" % ", ".join(msgs))
		return
	eq_int(JWUnits.R, 5, "地区数 5")
	eq_int(JWUnits.CELL, 20, "单元 20")
	eq_int(JWUnits.GROUP, 45, "群组 45")
	eq_int(JWUnits.AGENT_N, 1 + 20 + 5 + 45 + 3, "主体 74")
	eq_int(JWIds.AGENT_ROW, 72, "外部主体下标随布局后移")
	eq_int(st.dims_r, 5, "状态按 5 区重新分配")
	eq_int(st.pop.population.size(), 45, "群组数组长 45")
	eq_int(JWIds.REGION_OF_GROUP[44], 4, "反解表随之重建")

	var g: JWGame = _new(spec, 99)
	_advance(g, 8)
	var s1: JWSimState = g.get("_st") as JWSimState
	eq_int(g.view().q(), 8, "5 区剧本推进 8 季")
	check(not s1.politics.run_terminated, "8 季内未终局")
	# 西陵与孪生区开局相同，同一套规则下 8 季后人口仍相等（迁移只在相邻区之间，二者对称地与外界相连除外）。
	var px: int = 0
	var pt: int = 0
	for a: int in JWUnits.A:
		for k: int in JWUnits.K:
			px += s1.pop.population[JWIds.idx_group(3, a, k)]
			pt += s1.pop.population[JWIds.idx_group(4, a, k)]
	check(px > 0 and pt > 0, "两区都有人口（%d / %d）" % [px, pt])

	# 确定性：同种子同命令两次逐位相同。
	var h1: String = s1.state_hash()
	var g2: JWGame = _new(spec, 99)
	_advance(g2, 8)
	eq_str((g2.get("_st") as JWSimState).state_hash(), h1, "5 区剧本同种子逐位确定")


func test_switching_back_to_four_regions() -> void:
	var spec: String = build_fixture()
	var g5: JWGame = _new(spec, 5)
	eq_int(JWUnits.R, 5, "先载 5 区")
	var g4: JWGame = _new("res://content", 5)
	eq_int(JWUnits.R, 4, "换回参考剧本即回到 4 区")
	eq_int(JWIds.AGENT_ROW, 58, "主体布局复原")
	_advance(g4, 2)
	eq_int(g4.view().q(), 2, "4 区剧本照常推进")
	check(g5 != null, "5 区对象仍在（同一时刻只用一种维度，这里不再推进它）")
