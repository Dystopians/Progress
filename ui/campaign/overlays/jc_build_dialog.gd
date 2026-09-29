## 营造：左边目录（按类别，已解锁的在前）；右边选做法、经营方式（招商 / 官办）、级数，
## 下面每个地区一行：能不能建、造价、工期、按现价每季利润与一年回报、要注意的地方；推荐地区标星。
## ctx 可带 building / method / region（从产业链、舆图、顾问跳来时预选）。
class_name JcBuildDialog
extends JcOverlay

const CAT_ORDER: PackedStringArray = ["all", "farm", "mine", "workshop", "infra", "public"]

var _cat: String = "all"
var _building: String = ""
var _method: String = ""
var _owner: String = ""
var _levels: int = 1
var _region: String = ""


func build() -> void:
	width_ratio = 0.9
	height_ratio = 0.9
	if _building == "":
		_building = String(ctx.get("building", ""))
		_method = String(ctx.get("method", ""))
		_region = String(ctx.get("region", ""))
	set_title(t("jc.bld.title") if _region == "" else rt("jc.bld.title_in", {"region": game().name_of("region", _region)}))
	var cat: Array = session.views().catalog()
	if _building == "" and not cat.is_empty():
		for cv: Dictionary in cat:
			if bool(cv["unlocked"]):
				_building = String(cv["building"])
				break
	var h: HBoxContainer = JwUi.hbox(14)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(h)
	h.add_child(_catalog(cat))
	var right: VBoxContainer = JwUi.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	for cv2: Dictionary in cat:
		if String(cv2["building"]) == _building:
			_detail(right, cv2)


func _rebuild() -> void:
	on_changed()


func _catalog(cat: Array) -> Control:
	var p: PanelContainer = JwUi.panel("bg.panel", "line.hair", 8)
	p.custom_minimum_size = Vector2(300, 0)
	var v: VBoxContainer = JwUi.vbox(4)
	p.add_child(v)
	var fl: HFlowContainer = JcUi.flow(4, 4)
	for c: String in CAT_ORDER:
		var b: Button = JwUi.button(t("jc.bld.cat." + c), "TabBtn")
		b.toggle_mode = true
		b.set_pressed_no_signal(_cat == c)
		b.pressed.connect(func() -> void:
			_cat = c
			_rebuild())
		fl.add_child(b)
	v.add_child(fl)
	var last_cat: String = ""
	for cv2: Dictionary in _sorted(cat):
		if _cat != "all" and String(cv2["cat"]) != _cat:
			continue
		if _cat == "all" and String(cv2["cat"]) != last_cat:
			last_cat = String(cv2["cat"])
			v.add_child(JwUi.label(t("jc.bld.cat." + last_cat), "caption", "text.muted"))
		var id: String = String(cv2["building"])
		var sel: bool = id == _building
		var unlocked: bool = bool(cv2["unlocked"])
		var bt: Button = JwUi.button(("▸ " if sel else "") + String(cv2["name"]), "LinkBtn")
		bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bt.add_theme_color_override("font_color", JwTheme.c("text.primary" if unlocked else "text.muted"))
		if not unlocked:
			bt.tooltip_text = rt("jc.bld.needs_tech", {"tech": game().name_of("tech", String(cv2["tech"]))})
		bt.pressed.connect(func() -> void:
			_building = id
			_method = ""
			_owner = ""
			_rebuild())
		v.add_child(bt)
	return p


## 目录排序：类别（农田、矿场、作坊、设施、公共）→ 已解锁在前 → 时代 → 原顺序。
static func _sorted(cat: Array) -> Array:
	var idx: Array = []
	for i: int in cat.size():
		idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool:
		var ca: Dictionary = cat[a]
		var cb: Dictionary = cat[b]
		var ka: int = CAT_ORDER.find(String(ca["cat"]))
		var kb: int = CAT_ORDER.find(String(cb["cat"]))
		if ka != kb:
			return ka < kb
		if bool(ca["unlocked"]) != bool(cb["unlocked"]):
			return bool(ca["unlocked"])
		return a < b)
	var out: Array = []
	for i2: int in idx:
		out.append(cat[i2])
	return out


func _detail(right: VBoxContainer, cv: Dictionary) -> void:
	var g: JCGame = game()
	var head: HBoxContainer = JwUi.hbox(12)
	var art: String = String(cv["art"])
	head.add_child(JcUi.art(art, Vector2(160, 110), true))
	var hv: VBoxContainer = JwUi.vbox(4)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(JwUi.title(String(cv["name"]), "title_block"))
	hv.add_child(JwUi.label(String(cv["note"]), "body", "text.secondary", true))
	hv.add_child(JwUi.label(t("jc.bld.cat_note." + String(cv["cat"])), "caption", "text.muted", true))
	head.add_child(hv)
	right.add_child(head)
	if not bool(cv["unlocked"]):
		right.add_child(JwUi.para(rt("jc.bld.needs_tech", {"tech": g.name_of("tech", String(cv["tech"]))}), JcUi.WARN))
		return
	# 做法
	var mh: HFlowContainer = JcUi.flow(6, 6)
	mh.add_child(JwUi.label(t("jc.bld.method"), "body_bold", "text.primary"))
	var methods: Array = cv["methods"]
	var sites: Dictionary = session.views().sites(String(cv["building"]), _method)
	if sites.is_empty():
		return
	var cur_m: String = String(sites["method"])
	var rec_m: String = String(sites["recommended"])
	var locked: PackedStringArray = PackedStringArray()
	for mv: Dictionary in methods:
		if int(mv["era"]) > g.st.era + 1:
			continue
		var mid: String = String(mv["method"])
		if not bool(mv["unlocked"]):
			locked.append(rt("jc.bld.locked_item", {"method": String(mv["name"]), "tech": g.name_of("tech", String(mv["tech"]))}))
			continue
		if not bool(mv["current"]) and mid != cur_m:
			continue
		var b: Button = JwUi.button((t("jc.bld.star") if mid == rec_m else "") + String(mv["name"]), "TabBtn")
		b.toggle_mode = true
		b.set_pressed_no_signal(mid == cur_m)
		b.tooltip_text = t("jc.bld.method_rec") if mid == rec_m else ""
		b.pressed.connect(func() -> void:
			_method = mid
			_rebuild())
		mh.add_child(b)
	right.add_child(mh)
	if not locked.is_empty():
		right.add_child(JwUi.label(rt("jc.bld.locked", {"list": t("jc.name_sep").join(locked)}), "caption", "text.muted", true))
	# 经营方式与级数
	var oh: HBoxContainer = JwUi.hbox(8)
	var priv_ok: bool = bool(sites["private_ok"])
	var gov_ok: bool = bool(sites["gov_ok"])
	var default_owner: String = "private" if priv_ok and String(sites["cat"]) in ["farm", "mine", "workshop"] else "gov"
	if _owner == "" or (_owner == "private" and not priv_ok) or (_owner == "gov" and not gov_ok):
		_owner = default_owner
	oh.add_child(JwUi.label(t("jc.bld.owner"), "body_bold", "text.primary"))
	for o: String in ["private", "gov"]:
		if (o == "private" and not priv_ok) or (o == "gov" and not gov_ok):
			continue
		var ob: Button = JwUi.button(t("jc.bld.owner." + o), "TabBtn")
		ob.toggle_mode = true
		ob.set_pressed_no_signal(_owner == o)
		ob.tooltip_text = t("jc.bld.owner_tip." + o)
		ob.pressed.connect(func() -> void:
			_owner = o
			_rebuild())
		oh.add_child(ob)
	oh.add_child(JwUi.spacer())
	oh.add_child(JwUi.label(t("jc.bld.levels"), "body_bold", "text.primary"))
	var bd: Button = JcUi.button(t("jc.pol.less"), false, func() -> void:
		_levels = maxi(1, _levels - 1)
		_rebuild())
	bd.disabled = _levels <= 1
	oh.add_child(bd)
	oh.add_child(JwUi.label(str(_levels), "num_bold", "text.primary"))
	var bi: Button = JcUi.button(t("jc.pol.more"), false, func() -> void:
		_levels = mini(5, _levels + 1)
		_rebuild())
	bi.disabled = _levels >= 5
	oh.add_child(bi)
	right.add_child(oh)
	right.add_child(JwUi.label(t("jc.bld.owner_note." + _owner), "caption", "text.muted", true))
	# 各地区
	right.add_child(JwUi.label(t("jc.bld.where"), "title_sub", "text.primary"))
	var best: String = String(sites["best"])
	var list: Array = (sites["list"] as Array).duplicate()
	list.sort_custom(func(a: Dictionary, b2: Dictionary) -> bool:
		var ka: int = _site_rank(a, best)
		var kb: int = _site_rank(b2, best)
		return ka > kb)
	for rep: Dictionary in list:
		right.add_child(_site_row(g, rep, best, int(sites["treasury"])))


func _site_rank(rep: Dictionary, best: String) -> int:
	if String(rep["region"]) == _region:
		return 1 << 40
	if String(rep["region"]) == best:
		return 1 << 39
	if String(rep["block"]) != "":
		return -(1 << 39)
	return int(rep["roi_ppm"]) - (rep["warnings"] as Array).size() * 50_000


func _site_row(g: JCGame, rep: Dictionary, best: String, treasury: int) -> PanelContainer:
	var rid: String = String(rep["region"])
	var blocked: String = String(rep["block"])
	var is_best: bool = rid == best and blocked == ""
	var p: PanelContainer = JwUi.panel_style(JwTheme.box_left_rule("bg.raised" if blocked == "" else "bg.panel",
			JcUi.GOOD if is_best else ("line.hair" if blocked != "" else "line.strong"), 4, 10))
	var h: HBoxContainer = JwUi.hbox(12)
	p.add_child(h)
	var nv: VBoxContainer = JwUi.vbox(2)
	nv.custom_minimum_size = Vector2(110, 0)
	nv.add_child(JwUi.label(String(rep["region_name"]), "body_bold", "text.primary" if blocked == "" else "text.muted"))
	if is_best:
		nv.add_child(JwUi.label(t("jc.bld.best"), "caption", JcUi.GOOD))
	h.add_child(nv)
	var mid: VBoxContainer = JwUi.vbox(3)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(mid)
	if blocked != "":
		mid.add_child(JwUi.label(JcFmt.reason(g, {"reason": blocked}), "body", "text.muted", true))
		return p
	var cost: int = int(rep["cost"]) * _levels
	var profit: int = int(rep["profit_q"]) * _levels
	var line: String = rt("jc.bld.site_line", {"cost": JcFmt.money(cost), "time": JcFmt.quarters(int(rep["quarters"]))})
	if String(rep["building"]) != "" and profit != 0:
		line += rt("jc.bld.site_profit", {"profit": JcFmt.money_signed(profit), "roi": JcFmt.pct(int(rep["roi_ppm"]), 0)})
	mid.add_child(JwUi.label(line, "body", "text.primary", true))
	var warns: PackedStringArray = PackedStringArray()
	for w: Dictionary in rep["warnings"]:
		warns.append(warn_text(g, w))
	if not warns.is_empty():
		mid.add_child(JwUi.label(t("jc.list_sep").join(warns), "caption", JcUi.WARN, true))
	else:
		mid.add_child(JwUi.label(t("jc.bld.no_warn"), "caption", JcUi.GOOD))
	var cmd: Dictionary = (rep["cmd"] as Dictionary).duplicate()
	cmd["owner"] = _owner
	cmd["levels"] = _levels
	var b: Button = JcUi.button(t("jc.bld.build_here"), is_best, func() -> void:
		var r: Dictionary = session.order(cmd)
		if bool(r.get("ok", false)):
			close())
	if cost > treasury:
		b.tooltip_text = t("jc.bld.cost_over")
	h.add_child(b)
	return p


## 一条软提醒 → 一句话（营造、地区面板共用）。
static func warn_text(g: JCGame, w: Dictionary) -> String:
	var s: Dictionary = {}
	for k: Variant in w.keys():
		var ks: String = String(k)
		if ks == "key":
			continue
		match ks:
			"good":
				s["good"] = g.name_of("good", String(w[k]))
			"pct":
				s["pct"] = JcFmt.pct(int(w[k]), 0)
			_:
				s[ks] = str(w[k])
	return JcFmt.r(String(w["key"]), s)
