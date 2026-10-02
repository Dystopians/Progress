## v2 界面冒烟（docs/58）：真实开局、推进两季，逐页、逐覆盖层构建，文案不缺；
## 界面只经 JcSession / JCGame 读写局面，不碰模拟核心；数字格式平实。
## 测试运行在 SceneTree._init 中：页面与覆盖层不进场景树，直接 setup + refresh/build。
extends JWTest

const SEED: int = 11
const PAGES: Dictionary = {"overview": "JcPageOverview", "map": "JcPageMap", "industry": "JcPageIndustry",
		"modern": "JcPageModern", "tech": "JcPageTech", "policy": "JcPagePolicy", "society": "JcPageSociety",
		"trade": "JcPageTrade", "chronicle": "JcPageChronicle"}
## 可以直接用 JCGame 的模拟核心类名：界面里一律不许出现
const CORE_CLASSES: PackedStringArray = ["JCSim", "JCEconomy", "JCInvest", "JCWorld", "JCSociety", "JCCommands", "JCMods",
		"JCRng", "JCAnalyst"]
## 界面可以直接读的少数状态字段（只读、只是日历与大数）
const ST_FIELDS: PackedStringArray = ["q", "start_year", "era", "world_era", "treasury", "year", "over"]

static var _session: JcSession = null


static func _s() -> JcSession:
	if _session == null:
		_session = JcSession.new()
		if not _session.new_game(SEED):
			return null
		_session.game.autosave = false
		_session.end_turn()
		_session.end_turn()
	return _session


func _page_class(id: String) -> GDScript:
	match id:
		"overview":
			return JcPageOverview
		"map":
			return JcPageMap
		"industry":
			return JcPageIndustry
		"modern":
			return JcPageModern
		"tech":
			return JcPageTech
		"policy":
			return JcPagePolicy
		"society":
			return JcPageSociety
		"trade":
			return JcPageTrade
	return JcPageChronicle


func test_every_page_builds_with_text() -> void:
	var s: JcSession = _s()
	check(s != null and s.has_game(), "开局并推进两季")
	for id: String in PAGES.keys():
		var pg: JcPage = _page_class(id).new() as JcPage
		pg.setup(s, null, id)
		pg.refresh()
		ge_int(pg.get_child_count(), 1, "页面 " + id + " 建起来了")
		pg.free()
	var miss: PackedStringArray = JwText.missing_keys()
	var jc_miss: PackedStringArray = PackedStringArray()
	for k: String in miss:
		if k.begins_with("jc."):
			jc_miss.append(k)
	eq_int(jc_miss.size(), 0, "各页没有缺文案：" + ", ".join(jc_miss.slice(0, 8)))


func test_every_overlay_builds_with_text() -> void:
	var s: JcSession = _s()
	var specs: Array = [
		[JcNewGame, "newgame", {}], [JcStewardPanel, "steward", {}], [JcAdvisorPanel, "advisors", {}],
		[JcEventOverlay, "event", {}], [JcEraOverlay, "era", {"kind": "book"}], [JcEraOverlay, "era", {"kind": "nation", "era": 2}],
		[JcEraOverlay, "era", {"kind": "world", "era": 2}], [JcBuildDialog, "build", {}],
		[JcBuildDialog, "build", {"building": "market", "region": "zhongzhou"}], [JcReceipt, "receipt", s.game.last_receipt],
		[JcHelp, "help", {}], [JcSaves, "saves", {}], [JcGameOver, "gameover", {}],
	]
	for sp: Array in specs:
		var o: JcOverlay = (sp[0] as GDScript).new() as JcOverlay
		o.setup(s, null, String(sp[1]), sp[2])
		ge_int(o.body.get_child_count(), 1, "覆盖层 " + String(sp[1]) + " 有内容")
		o.free()
	var jc_miss: PackedStringArray = PackedStringArray()
	for k: String in JwText.missing_keys():
		if k.begins_with("jc."):
			jc_miss.append(k)
	eq_int(jc_miss.size(), 0, "各覆盖层没有缺文案：" + ", ".join(jc_miss.slice(0, 8)))


## 政治改革页签与政局弹窗（docs/61）：有改革、革命、经济危机、待决关口时都建得起来，文案不缺。
func test_politics_tab_and_situation_overlay_build_with_text() -> void:
	var s: JcSession = JcSession.new()
	check(s.new_game(13), "另开一局")
	s.game.autosave = false
	s.end_turn()
	var g: JCGame = s.game
	g.st.era = 3
	g.st.world_era = 3
	g.st.legitimacy = 200_000
	g.st.pres[0] = 1_000_000
	g.sim.politics.step()
	g.sim.politics._start_depression()
	check(g.situation_asks() >= 2, "革命与经济危机都在等着拿主意")
	JcPagePolicy.want_tab = "politics"
	var pg: JcPage = JcPagePolicy.new()
	pg.setup(s, null, "policy")
	pg.refresh()
	ge_int(pg.content.get_child_count(), 4, "政治改革页签建起来了")
	pg.free()
	var o: JcOverlay = JcSituationOverlay.new()
	o.setup(s, null, "situation", {})
	ge_int(o.body.get_child_count(), 2, "政局弹窗列出待决的关口")
	o.free()
	var jc_miss: PackedStringArray = PackedStringArray()
	for k: String in JwText.missing_keys():
		if k.begins_with("jc."):
			jc_miss.append(k)
	eq_int(jc_miss.size(), 0, "政治改革没有缺文案：" + ", ".join(jc_miss.slice(0, 8)))


func test_v2_ui_only_goes_through_the_facade() -> void:
	var files: PackedStringArray = PackedStringArray()
	_gd_files("res://ui/campaign", files)
	ge_int(files.size(), 20, "扫到 v2 界面脚本")
	var rx_st: RegEx = RegEx.create_from_string("\\.st\\.([a-z_]+)")
	var bad: PackedStringArray = PackedStringArray()
	for f: String in files:
		var src: String = FileAccess.get_file_as_string(f)
		for line: String in src.split("\n"):
			var code: String = line.split("#")[0] if not line.strip_edges().begins_with("##") else ""
			for cls: String in CORE_CLASSES:
				if code.contains(cls):
					bad.append(f.get_file() + ": " + cls)
			for tok: String in [".sim.", ".sim)", ".ct.", ".analyst."]:
				if code.contains(tok):
					bad.append(f.get_file() + ": " + tok)
			for m: RegExMatch in rx_st.search_all(code):
				if not ST_FIELDS.has(m.get_string(1)):
					bad.append(f.get_file() + ": st." + m.get_string(1))
	eq_int(bad.size(), 0, "v2 界面只经 JcSession / JCGame 与视图：" + ", ".join(bad.slice(0, 8)))


## 字面量里的键：jc.* 必须存在（以「.」或「_」结尾的是拼接用的前缀，不算）；
## 引擎键（reason. / chron. / stw. / adv. / warn. / cause. / need.）要有加了 jc. 前缀的文案。
func test_literal_keys_in_v2_ui_exist() -> void:
	var files: PackedStringArray = PackedStringArray()
	_gd_files("res://ui/campaign", files)
	var rx: RegEx = RegEx.create_from_string("\"((?:jc|reason|chron|stw|adv|warn|cause)\\.[a-z0-9_.]*)\"")
	var missing: PackedStringArray = PackedStringArray()
	var n: int = 0
	for f: String in files:
		var src: String = FileAccess.get_file_as_string(f)
		for line: String in src.split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			for m: RegExMatch in rx.search_all(line):
				var k: String = m.get_string(1)
				if k.ends_with(".") or k.ends_with("_"):
					continue
				n += 1
				var key: String = k if k.begins_with("jc.") else "jc." + k
				if not JwText.has(key):
					missing.append(key + " @" + f.get_file())
	ge_int(n, 300, "扫到的 v2 字面量键")
	eq_int(missing.size(), 0, "v2 界面的字面量键都有文案：" + ", ".join(missing.slice(0, 8)))


func test_numbers_read_plainly() -> void:
	eq_str(JcFmt.money(12_345_000), "1.2 " + JwText.t("jc.u.wan_liang"), "一万两以上按万两")
	eq_str(JcFmt.money(3_456_000), "3,456 " + JwText.t("jc.u.liang"), "一万两以下按两")
	eq_str(JcFmt.money(125_000_000_000), "1.25 " + JwText.t("jc.u.yi_liang"), "一亿两以上按亿两")
	eq_str(JcFmt.people(23_000_000), "2,300 " + JwText.t("jc.u.wan_ren"), "人口按万人")
	eq_str(JcFmt.pct(125_000), "12.5%", "比例按百分数")
	eq_str(JcFmt.quarters(6), JwText.render("jc.u.years_q", {"n": "1", "q": "2"}), "六季说成一年两季")
	eq_str(JcFmt.date(4, 1599), JwText.render("jc.u.date", {"year": "1600", "season": JwText.t("jc.u.season.0")}), "日期")


static func _gd_files(dir_path: String, out: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var e: String = dir.get_next()
	while e != "":
		if not e.begins_with("."):
			var full: String = dir_path + "/" + e
			if dir.current_is_dir():
				_gd_files(full, out)
			elif e.ends_with(".gd"):
				out.append(full)
		e = dir.get_next()
	dir.list_dir_end()
