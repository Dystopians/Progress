## 民生：一眼看出百姓过得怎样。
##   上面四张阶层卡：画像（表情随民心变）、一句话的光景（安居乐业 / 颇有怨言……）、生活、民心、人均年入、最缺的几样；
##   中间「民心地图」：每个地区的每个阶层一张小脸，点一下去舆图；旁边是民怨最重的几处与主因；
##   下面是选中那个阶层的日子：每项需要一个图标环（满一圈 = 都买到了），收入从哪来的一条彩条。
class_name JcPageSociety
extends JcPage

const PPM_I: int = 1_000_000
const MOODS: PackedStringArray = ["content", "content", "calm", "angry", "angry"]
const MOOD_TONE: Array = ["teal.core", "teal.core", "line.strong", "ochre.core", "ochre.hot"]
const SRC_TONE: Array = ["teal.core", "ochre.core", "text.secondary", "ochre.hot"]

var _cls: String = "peasant"
var _cards: GridContainer = null


## 民心的几档：0 安居乐业 … 4 群情激愤（看支持度与民怨）。
static func mood_of(support: int, unrest: int) -> int:
	if support >= 700_000 and unrest < 100_000:
		return 0
	if support >= 550_000 and unrest < 250_000:
		return 1
	if support >= 400_000:
		return 2
	if support >= 250_000:
		return 3
	return 4


## 地区里一个阶层的脸色（只看生活与民怨）。
static func cell_mood(living: int, unrest: int) -> int:
	if unrest < 50_000 and living >= 1_050_000:
		return 0
	if unrest < 150_000:
		return 1
	if unrest < 300_000:
		return 2
	if unrest < 500_000:
		return 3
	return 4


func refresh() -> void:
	clear()
	if not session.has_game():
		return
	var g: JCGame = game()
	var v: Dictionary = views().society()
	var era: int = int(v["era"])
	content.add_child(JwUi.para(rt("jc.soc.intro", {"expect": JcFmt.times(int(v["expect"])),
			"world": JcFmt.era_name(int(v["world_era"]))}), "text.secondary"))
	# ── 四张阶层卡 ──
	var total: int = 0
	for cv0: Dictionary in v["classes"]:
		total += int(cv0["pop"])
	_cards = JcUi.grid(4, 12, 12)
	var picked: Dictionary = {}
	for cv: Dictionary in v["classes"]:
		_cards.add_child(_class_card(cv, era, total))
		if String(cv["class"]) == _cls:
			picked = cv
	content.add_child(_cards)
	_fit_cards()
	_fit_cards.call_deferred()
	# ── 民心地图与民怨最重的地方 ──
	var two: HBoxContainer = JwUi.hbox(14)
	two.add_child(_mood_map(g, v))
	two.add_child(_hot_card(g, v))
	content.add_child(two)
	# ── 选中阶层的日子 ──
	if not picked.is_empty():
		content.add_child(_detail(picked, era))


func relayout(_w: float) -> void:
	_fit_cards()


## 阶层卡一排放得下就四张一排，放不下就两张一排（不排成三加一）。
func _fit_cards() -> void:
	if _cards == null or not is_instance_valid(_cards) or _cards.get_child_count() == 0:
		return
	var avail: float = avail_width()
	if avail <= 0.0:
		return
	var need: float = 0.0
	for ch: Node in _cards.get_children():
		need = maxf(need, (ch as Control).get_combined_minimum_size().x)
	var n: int = _cards.get_child_count()
	var cols: int = n
	while cols > 1 and need * cols + 12.0 * (cols - 1) > avail:
		cols -= 1
	if cols == 3 and n == 4:
		cols = 2
	_cards.columns = cols


func _class_card(cv: Dictionary, era: int, total: int) -> Control:
	var cid: String = String(cv["class"])
	var sel: bool = cid == _cls
	var sup: int = int(cv["support"])
	var unr: int = int(cv["unrest"])
	var md: int = mood_of(sup, unr)
	var tone: String = String(MOOD_TONE[md])
	var box: StyleBoxFlat = JwTheme.box4("bg.raised" if sel else "bg.panel", "ochre.core" if sel else tone, 3 if sel else 1, 12, 10, 12, 10)
	box.set_corner_radius_all(10)
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", box)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.tooltip_text = String(cv["note"])
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_cls = cid
			refresh())
	var h: HBoxContainer = JwUi.hbox(12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var portrait: Control = JcUi.badge(JcUi.CLASS_ART % [cid, clampi(era, 1, 4), MOODS[md]], 112.0, String(cv["name"]), tone)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(portrait)
	var v: VBoxContainer = JwUi.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var top: HBoxContainer = JwUi.hbox(8)
	top.add_child(JwUi.label(String(cv["name"]), "title_sub", "text.primary"))
	top.add_child(JcUi.ringed(JcUi.MOOD_ICON % md, 24.0, t("jc.soc.mood.%d" % md), tone))
	top.add_child(JwUi.label(t("jc.soc.mood.%d" % md), "body_bold", tone))
	v.add_child(top)
	var pop: int = int(cv["pop"])
	v.add_child(JwUi.label(rt("jc.soc.pop_line", {"pop": JcFmt.people(pop), "share": JcFmt.pct(JCMath.ratio_ppm(pop, maxi(1, total)), 0)}),
			"caption", "text.muted"))
	var ks: HBoxContainer = JwUi.hbox(14)
	var liv: int = int(cv["living"])
	ks.add_child(_kv(JcUi.UI_ICON % "stat_living", t("jc.soc.k.living"), JcFmt.pct(liv, 0), JcUi.tone(liv >= 950_000, liv >= 850_000)))
	ks.add_child(_kv(JcUi.UI_ICON % "stat_legitimacy", t("jc.soc.k.support"), JcFmt.pct(sup, 0), tone))
	ks.add_child(_kv(JcUi.UI_ICON % "stat_treasury", t("jc.soc.k.income"),
			rt("jc.soc.k.income_v", {"v": JcFmt.money(JCMath.muldiv(int(cv["income_pc"]), 4, 1000))}), "text.primary"))
	v.add_child(ks)
	if cid != "gentry" and int(cv["unemp"]) >= 50_000:
		v.add_child(JwUi.label(rt("jc.soc.unemp_line", {"v": JcFmt.pct(int(cv["unemp"]), 0)}), "caption", JcUi.WARN))
	# 最缺的几样（满足不到九成的，最缺的在前）
	var needs: Array = (cv["needs"] as Array).duplicate()
	needs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["sat"]) < int(b["sat"]))
	var sh: HBoxContainer = JwUi.hbox(6)
	sh.add_child(JwUi.label(t("jc.soc.short"), "caption", "text.muted"))
	var n_short: int = 0
	for nd: Dictionary in needs:
		if int(nd["sat"]) >= 900_000 or n_short >= 3:
			continue
		n_short += 1
		var it: HBoxContainer = JwUi.hbox(3)
		it.add_child(JcUi.badge(JcUi.NEED_ICON % String(nd["need"]), 22.0, String(nd["name"]), JcUi.WARN))
		it.add_child(JwUi.label(rt("jc.soc.short_item", {"name": String(nd["name"]), "v": JcFmt.pct(int(nd["sat"]), 0)}), "caption",
				JcUi.WARN if int(nd["sat"]) >= 600_000 else JcUi.BAD))
		sh.add_child(it)
	if n_short == 0:
		sh.add_child(JwUi.label(t("jc.soc.short_none"), "caption", JcUi.GOOD))
	v.add_child(sh)
	return p


func _kv(icon: String, label: String, value: String, tone: String) -> Control:
	var h: HBoxContainer = JwUi.hbox(4)
	h.add_child(JcUi.badge(icon, 20.0, label, "line.strong"))
	var vv: VBoxContainer = JwUi.vbox(0)
	vv.add_child(JwUi.label(label, "caption", "text.muted"))
	vv.add_child(JwUi.label(value, "num_bold", tone))
	h.add_child(vv)
	return h


## 民心地图：行是地区，列是阶层，每格一张小脸。
func _mood_map(g: JCGame, v: Dictionary) -> Control:
	var c: Dictionary = JcUi.card(t("jc.soc.map"), t("jc.soc.map_sub"))
	c["root"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body: VBoxContainer = c["body"]
	var classes: Array = []
	for cv: Dictionary in v["classes"]:
		classes.append(String(cv["class"]))
	var grid: GridContainer = JcUi.grid(classes.size() + 1, 18, 10)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.add_child(JwUi.label("", "caption", "text.muted"))
	for cid: String in classes:
		var hl: Label = JwUi.label(g.name_of("class", cid), "caption", "text.secondary")
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(hl)
	var cells: Dictionary = {}
	for ce: Dictionary in v["cells"]:
		cells[String(ce["region"]) + ":" + String(ce["class"])] = ce
	for rv: Dictionary in v["regions"]:
		var rid: String = String(rv["region"]) if rv.has("region") else String(rv.get("id", ""))
		var rh: HBoxContainer = JwUi.hbox(4)
		rh.add_child(JcUi.icon(JcUi.UI_ICON % ("region_" + rid), 22.0))
		rh.add_child(JcUi.link(g.name_of("region", rid), func() -> void:
			session.selected_region = rid
			goto_page("map")))
		grid.add_child(rh)
		for cid2: String in classes:
			var ce2: Dictionary = cells.get(rid + ":" + cid2, {})
			if ce2.is_empty():
				grid.add_child(JwUi.label("—", "caption", "text.muted"))
				continue
			var md: int = cell_mood(int(ce2["living"]), int(ce2["unrest"]))
			var cell: VBoxContainer = JwUi.vbox(0)
			cell.alignment = BoxContainer.ALIGNMENT_CENTER
			cell.mouse_filter = Control.MOUSE_FILTER_STOP
			cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			cell.tooltip_text = rt("jc.soc.cell_tip", {"region": g.name_of("region", rid), "class": g.name_of("class", cid2),
					"living": JcFmt.pct(int(ce2["living"]), 0), "unrest": JcFmt.pct(int(ce2["unrest"]), 0),
					"cause": JcFmt.k(String(ce2["cause"]))})
			var face: Control = JcUi.ringed(JcUi.MOOD_ICON % md, 34.0, t("jc.soc.mood.%d" % md), String(MOOD_TONE[md]))
			face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			cell.add_child(face)
			var lv: Label = JwUi.label(JcFmt.pct(int(ce2["living"]), 0), "caption", String(MOOD_TONE[md]))
			lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.add_child(lv)
			var r2: String = rid
			cell.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
					session.selected_region = r2
					goto_page("map"))
			grid.add_child(cell)
	body.add_child(grid)
	var lg: HBoxContainer = JwUi.hbox(10)
	for md2: int in 5:
		var it: HBoxContainer = JwUi.hbox(4)
		it.add_child(JcUi.ringed(JcUi.MOOD_ICON % md2, 18.0, t("jc.soc.mood.%d" % md2), String(MOOD_TONE[md2])))
		it.add_child(JwUi.label(t("jc.soc.mood.%d" % md2), "caption", "text.muted"))
		lg.add_child(it)
	body.add_child(lg)
	return c["root"]


func _hot_card(g: JCGame, v: Dictionary) -> Control:
	var hc: Dictionary = JcUi.card(t("jc.soc.hot"), t("jc.soc.hot_sub"))
	hc["root"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb: VBoxContainer = hc["body"]
	var any_hot: bool = false
	for h: Dictionary in v["hotspots"]:
		var unr: int = int(h["unrest"])
		if unr < 250_000:
			continue
		any_hot = true
		var row: HBoxContainer = JwUi.hbox(10)
		var rid: String = String(h["region"])
		var md: int = cell_mood(int(h["living"]), unr)
		row.add_child(JcUi.ringed(JcUi.MOOD_ICON % md, 28.0, t("jc.soc.mood.%d" % md), String(MOOD_TONE[md])))
		row.add_child(JcUi.link(g.name_of("region", rid), func() -> void:
			session.selected_region = rid
			goto_page("map")))
		row.add_child(JwUi.label(g.name_of("class", String(h["class"])), "body", "text.secondary"))
		row.add_child(JwUi.label(rt("jc.soc.hot_row", {"unrest": JcFmt.pct(unr, 0), "living": JcFmt.pct(int(h["living"]), 0),
				"cause": JcFmt.k(String(h["cause"]))}), "body", "text.secondary", true))
		hb.add_child(row)
	if not any_hot:
		hb.add_child(JwUi.para(t("jc.soc.calm"), JcUi.GOOD))
	return hc["root"]


## 选中阶层的日子：生活场景、每项需要的图标环、收入从哪来。
func _detail(cv: Dictionary, era: int) -> Control:
	var cid: String = String(cv["class"])
	var c: Dictionary = JcUi.card(rt("jc.soc.detail", {"class": String(cv["name"])}), t("jc.soc.detail_sub"))
	var body: VBoxContainer = c["body"]
	var life: String = JcUi.LIFE_ART % [cid, clampi(era, 1, 4)]
	if JcUi.has_art(life):
		body.add_child(JcUi.art(life, Vector2(0, 150)))
	for grp: String in ["ess", "daily", "fine", "new"]:
		var items: Array = []
		for nd: Dictionary in cv["needs"]:
			if String(nd.get("group", "")) == grp:
				items.append(nd)
		if items.is_empty():
			continue
		body.add_child(JwUi.label(t("jc.soc.grp." + grp), "body_bold", "text.secondary"))
		var fl: HFlowContainer = JcUi.flow(14, 10)
		for nd2: Dictionary in items:
			var sat: int = int(nd2["sat"])
			var tile: VBoxContainer = JwUi.vbox(2)
			tile.custom_minimum_size = Vector2(84, 0)
			var ring: JcRing = JcRing.new()
			ring.value = sat
			ring.tone = JcUi.tone(sat >= 900_000, sat >= 600_000)
			ring.icon_path = JcUi.NEED_ICON % String(nd2["need"])
			ring.text = String(nd2["name"]).substr(0, 1)
			ring.custom_minimum_size = Vector2(60, 60)
			ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			ring.tooltip_text = rt("jc.soc.need_tip", {"name": String(nd2["name"]), "v": JcFmt.pct(sat, 0)})
			tile.add_child(ring)
			var nl: Label = JwUi.label(String(nd2["name"]) + (t("jc.soc.ess_mark") if bool(nd2["essential"]) else ""), "caption",
					"text.secondary")
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tile.add_child(nl)
			var pl: Label = JwUi.label(JcFmt.pct(sat, 0), "caption", ring.tone)
			pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tile.add_child(pl)
			fl.add_child(tile)
		body.add_child(fl)
	# 收入从哪来：一条按份额分段的彩条
	var src: Array = cv["src"]
	var total_in: int = 0
	for x: Variant in src:
		total_in += absi(int(x))
	if total_in > 0:
		body.add_child(JwUi.label(rt("jc.soc.src_head", {"v": JcFmt.money(JCMath.muldiv(int(cv["income_pc"]), 4, 1000))}),
				"body_bold", "text.secondary"))
		var bar: HBoxContainer = JwUi.hbox(0)
		bar.custom_minimum_size = Vector2(0, 16)
		var legend: HBoxContainer = JwUi.hbox(14)
		for s: int in src.size():
			var a: int = absi(int(src[s]))
			if a <= 0:
				continue
			var share: int = JCMath.ratio_ppm(a, total_in)
			var seg: ColorRect = ColorRect.new()
			seg.color = JwTheme.c(String(SRC_TONE[mini(s, SRC_TONE.size() - 1)]))
			seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			seg.size_flags_stretch_ratio = maxf(0.02, float(share) / 1_000_000.0)
			seg.tooltip_text = rt("jc.soc.src.%d" % s, {"v": JcFmt.pct(share, 0)})
			bar.add_child(seg)
			var li: HBoxContainer = JwUi.hbox(4)
			var sw: ColorRect = ColorRect.new()
			sw.color = seg.color
			sw.custom_minimum_size = Vector2(12, 12)
			sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			li.add_child(sw)
			li.add_child(JwUi.label(rt("jc.soc.src.%d" % s, {"v": JcFmt.pct(share, 0)}), "caption", "text.muted"))
			legend.add_child(li)
		body.add_child(bar)
		body.add_child(legend)
	return c["root"]
