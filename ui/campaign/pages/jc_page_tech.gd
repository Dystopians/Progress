## 科技（仿文明 6 的科技树）：上面是研究点与正在研究的；中间是可左右拖动的科技树（时代从左到右，
## 前置之间连线，节点有图标、进度、解锁的小图标）；下面是选中那项的详情：做什么用、还差多少、谁在加快、
## 解锁什么，一键定为研究方向。
class_name JcPageTech
extends JcPage

var _sel: String = ""
var _head: HBoxContainer = null
var _legend: HBoxContainer = null
var _tree_scroll: ScrollContainer = null
var _tree: JcTechTree = null
var _detail: VBoxContainer = null
var _scrolled_era: int = -1
var _list: Array = []
var _points: int = 0


func build() -> void:
	content = JwUi.vbox(10)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(content)
	_head = JwUi.hbox(14)
	content.add_child(_head)
	_legend = JwUi.hbox(14)
	content.add_child(_legend)
	var frame: PanelContainer = JwUi.panel("bg.abyss", "line.hair", 0)
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(frame)
	_tree_scroll = ScrollContainer.new()
	_tree_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_child(_tree_scroll)
	_tree = JcTechTree.new()
	_tree_scroll.add_child(_tree)
	_tree.picked.connect(func(id: String) -> void:
		_sel = id
		_tree.selected = id
		_tree.set_data(_list, _sel, int(game().st.era) if session.has_game() else 1)
		_fill_detail())
	var dp: PanelContainer = JwUi.panel("bg.panel", "line.hair", 14)
	dp.custom_minimum_size = Vector2(0, 210)
	content.add_child(dp)
	_detail = JwUi.vbox(8)
	dp.add_child(_detail)


func refresh() -> void:
	if not session.has_game():
		return
	var g: JCGame = game()
	var v: Dictionary = views().techs()
	_list = v["list"]
	_points = int(v["points"])
	# 上面：研究点、正在研究、进度
	JwUi.clear(_head)
	_head.add_child(JcUi.badge(JcUi.UI_ICON % "stat_research", 28.0, t("jc.tech.points_short"), JcUi.GOOD))
	_head.add_child(JwUi.label(rt("jc.tech.points", {"n": str(_points)}), "title_sub", "text.primary"))
	var fid: String = String(v["focus"])
	if fid != "":
		var fv: Dictionary = _find(fid)
		_head.add_child(JwUi.label(rt("jc.tech.focus", {"tech": g.name_of("tech", fid)}), "body_bold", JcUi.WARN))
		if not fv.is_empty():
			_head.add_child(JcUi.meter(JCMath.ratio_ppm(int(fv["progress"]), maxi(1, int(fv["cost"]))), JcUi.WARN, 180.0, 8.0))
			_head.add_child(JwUi.label(rt("jc.tech.eta", {"eta": JcFmt.quarters(int(fv["eta_q"]))}), "body", "text.secondary"))
	else:
		_head.add_child(JwUi.label(t("jc.tech.no_focus"), "body_bold", JcUi.BAD))
	var hint: Label = JwUi.label(t("jc.tech.hint"), "caption", "text.muted", true)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_head.add_child(hint)
	# 图例
	JwUi.clear(_legend)
	for lg: Array in [["jc.tech.lg.done", JcUi.GOOD], ["jc.tech.lg.focus", JcUi.WARN], ["jc.tech.lg.avail", "text.secondary"],
			["jc.tech.lg.locked", "line.hair"]]:
		_legend.add_child(JcUi.chip(t(String(lg[0])), String(lg[1])))
	_legend.add_child(JcUi.chip(t("jc.tech.key_short"), JcUi.WARN, true))
	_legend.add_child(JwUi.label(t("jc.tech.lg.key"), "caption", "text.muted"))
	var intro: Label = JwUi.label(t("jc.tech.intro"), "caption", "text.muted", true)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	intro.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_legend.add_child(intro)
	# 默认选中：正在研究的；没有就选下一时代要的第一项能研究的
	if _sel == "" or _find(_sel).is_empty():
		_sel = fid
		if _sel == "":
			for tv: Dictionary in _list:
				if bool(tv["available"]) and bool(tv["era_key"]):
					_sel = String(tv["id"])
					break
	_tree.set_data(_list, _sel, int(v["era"]))
	_fill_detail()
	# 第一次打开、或进了新时代：把视野挪到本国所在的时代
	if _scrolled_era != int(v["era"]):
		_scrolled_era = int(v["era"])
		var x: int = int(maxf(0.0, _tree.era_left(int(v["era"])) - 24.0))
		_tree_scroll.set_deferred("scroll_horizontal", x)


func _find(id: String) -> Dictionary:
	for tv: Dictionary in _list:
		if String(tv["id"]) == id:
			return tv
	return {}


## 解锁项的一句话（节点小图标的提示、详情列表共用）。
static func unlock_text(un: Dictionary) -> String:
	match String(un.get("kind", "")):
		"building":
			return JwText.render("jc.tech.un.building", {"name": String(un["name"])})
		"method":
			return JwText.render("jc.tech.un.method", {"building": String(un.get("building", "")), "name": String(un["name"])})
		"decree":
			if un.has("level_name"):
				return JwText.render("jc.tech.un.decree_level", {"name": String(un["name"]), "level": String(un["level_name"])})
			return JwText.render("jc.tech.un.decree", {"name": String(un["name"])})
	return String(un.get("name", ""))


func _fill_detail() -> void:
	JwUi.clear(_detail)
	var tv: Dictionary = _find(_sel)
	if tv.is_empty():
		_detail.add_child(JwUi.label(t("jc.tech.pick_hint"), "body", "text.muted"))
		return
	var g: JCGame = game()
	var h: HBoxContainer = JwUi.hbox(18)
	_detail.add_child(h)
	var done: bool = bool(tv["done"])
	var focus: bool = bool(tv["focus"])
	var avail: bool = bool(tv["available"])
	var ic: Control = JcUi.badge(JcUi.TECH_ART % String(tv["id"]), 128.0, String(tv["name"]),
			JcUi.GOOD if done else (JcUi.WARN if focus else "line.strong"))
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	# 中间：名字、时代、说明、进度、加快、前置
	var mid: VBoxContainer = JwUi.vbox(5)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(mid)
	var top: HBoxContainer = JwUi.hbox(8)
	top.add_child(JwUi.label(String(tv["name"]), "title_block", "text.primary"))
	top.add_child(JcUi.chip(JcFmt.era_name(int(tv["era"]))))
	if bool(tv["era_key"]) and not done:
		top.add_child(JcUi.chip(t("jc.tech.key"), JcUi.WARN))
	mid.add_child(top)
	mid.add_child(JwUi.label(String(tv["desc"]), "body", "text.secondary", true))
	var cost: int = int(tv["cost"])
	var prog: int = int(tv["progress"])
	if done:
		mid.add_child(JwUi.label(t("jc.tech.done"), "body_bold", JcUi.GOOD))
	else:
		var left: String = JcFmt._g3(maxi(0, cost - prog))
		mid.add_child(JwUi.label(rt("jc.tech.d.left", {"left": left, "points": str(_points), "eta": JcFmt.quarters(int(tv["eta_q"]))})
				if _points > 0 else rt("jc.tech.cost_idle", {"left": left}), "body", "text.secondary", true))
	var dom: int = int(tv["bg_domestic"])
	var fo: int = int(tv["bg_foreign"])
	if not done and (dom > 0 or fo > 0):
		mid.add_child(JwUi.label(rt("jc.tech.d.speed", {"dom": JcFmt.pct(dom, 0), "fo": JcFmt.pct(fo, 0)}), "caption",
				JcUi.GOOD, true))
	var pre: PackedStringArray = PackedStringArray()
	for p: Variant in tv["prereq"]:
		pre.append(g.name_of("tech", String(p)))
	if not pre.is_empty():
		mid.add_child(JwUi.label(rt("jc.tech.d.prereq", {"list": t("jc.name_sep").join(pre)}), "caption", "text.muted", true))
	var ab: PackedStringArray = PackedStringArray()
	for pid: Variant in tv.get("known_abroad", []):
		ab.append(g.name_of("partner", String(pid)))
	if not ab.is_empty() and not done:
		mid.add_child(JwUi.label(rt("jc.tech.d.abroad", {"list": t("jc.name_sep").join(ab)}), "caption", "text.muted", true))
	# 右边：解锁什么、按钮
	var right: VBoxContainer = JwUi.vbox(6)
	right.custom_minimum_size = Vector2(380, 0)
	h.add_child(right)
	right.add_child(JwUi.label(t("jc.tech.unlocks"), "body_bold", "text.primary"))
	var ul: Array = tv.get("unlocks", [])
	if ul.is_empty():
		right.add_child(JwUi.label(t("jc.tech.d.none_unlock"), "caption", "text.muted", true))
	var fl: HFlowContainer = JcUi.flow(10, 6)
	for un: Dictionary in ul:
		var item: HBoxContainer = JwUi.hbox(6)
		var path: String = String(un["art"])
		if String(un["kind"]) == "decree":
			path = JcUi.decree_art(String(un["id"]), int(un.get("level", -1)))
		item.add_child(JcUi.badge(path, 40.0, String(un["name"]), "line.strong"))
		item.add_child(JwUi.label(unlock_text(un), "caption", "text.secondary"))
		fl.add_child(item)
	right.add_child(fl)
	right.add_child(JwUi.spacer())
	if avail and not focus and not done:
		var id: String = String(tv["id"])
		right.add_child(JcUi.button(t("jc.tech.pick"), true, func() -> void:
			session.order({"kind": "research", "tech": id}, true)))
	elif focus:
		right.add_child(JwUi.label(t("jc.tech.researching"), "body_bold", JcUi.WARN))
