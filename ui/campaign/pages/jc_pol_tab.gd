## 政令页的「政治改革」页签（docs/61）：当今国家（评语、徽记、取向）、眼下的局势（改革进度、革命、列强、战事、
## 经济危机，待决的关口在这里拿主意）、可以推行的改革、两种压力及来由、各种政体、政体更替史。
## 政体不能直接下令换：只能推行改革，或在革命、战败等外部局势里改变。
class_name JcPolTab
extends RefCounted

const REFORM_W: float = 330.0
const REGIME_W: float = 150.0

var page: JcPage = null
var g: JCGame = null
var v: Dictionary = {}


func _init(p_page: JcPage, p_game: JCGame) -> void:
	page = p_page
	g = p_game


func t(key: String) -> String:
	return JwText.t(key)


func rt(key: String, slots: Dictionary) -> String:
	return JwText.render(key, slots)


func build(content: VBoxContainer) -> void:
	v = page.views().politics()
	content.add_child(regime_card(g, v["regime"]))
	content.add_child(_situations())
	content.add_child(_reforms())
	content.add_child(_pressures())
	content.add_child(_ladder())
	content.add_child(_history())


# ── 当今国家 ─────────────────────────────────────────────────────────────
## 徽记没到时圆章里写的字：每种政体一个（「军政府」「军阀割据」不至于都写「军」）。
static func glyph(gm: JCGame, id: String) -> String:
	return JwText.t("jc.regime.glyph." + id) if JwText.has("jc.regime.glyph." + id) else gm.name_of("regime", id)


## 评语：按 title_keys 取第一个有文案的（局面 × 政体 × 风格……），用政体的称呼填 {noun}。
static func title_text(rp: Dictionary) -> String:
	for k: Variant in rp.get("title_keys", []):
		if JwText.has(String(k)):
			return JwText.render(String(k), {"noun": String(rp.get("noun", ""))})
	return JwText.t(String(rp["title"]))


static func regime_card(gm: JCGame, rp: Dictionary) -> PanelContainer:
	var card: PanelContainer = JwUi.panel("bg.panel", "line.hair", 16)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h: HBoxContainer = JwUi.hbox(20)
	card.add_child(h)
	var tone: String = String(rp["tone"])
	var tone_tok: String = JcUi.GOOD if tone == "benevolent" else (JcUi.BAD if tone == "harsh" else "line.strong")
	var title: String = title_text(rp)
	var em: Control = JcUi.badge(JcUi.regime_art(String(rp["regime"]), tone), 150.0, glyph(gm, String(rp["regime"])), tone_tok)
	em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(em)
	var vb: VBoxContainer = JwUi.vbox(6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(vb)
	vb.add_child(JwUi.label(JwText.t("jc.regime.head"), "caption", "text.muted"))
	vb.add_child(JwUi.label(title, "title_page", tone_tok if tone != "steady" else "text.primary", true))
	vb.add_child(JwUi.label(JwText.render("jc.regime.sub", {"regime": String(rp["regime_name"]), "era": JcFmt.era_name(gm.st.era)}),
			"body", "text.secondary"))
	var lines: PackedStringArray = PackedStringArray()
	var good: Array = rp["good"]
	var harsh: Array = rp["harsh"]
	var gov: String = JwText.t(String(rp.get("gov", "jc.regime.gov.court")))
	if not good.is_empty():
		lines.append(JwText.render("jc.regime.s.good", {"list": JwText.t("jc.name_sep").join(PackedStringArray(good)), "gov": gov}))
	if not harsh.is_empty():
		lines.append(JwText.render("jc.regime.s.harsh", {"list": JwText.t("jc.name_sep").join(PackedStringArray(harsh))}))
	for n: Dictionary in rp["notes"]:
		var sl: Dictionary = (n["slots"] as Dictionary).duplicate()
		sl["gov"] = gov
		if sl.has("v"):
			sl["v"] = JcFmt._dec(absi(int(sl["v"])), 10_000, 1)
		lines.append(JwText.render(String(n["key"]), sl))
	if good.is_empty() and harsh.is_empty() and (rp["notes"] as Array).is_empty():
		lines.append(JwText.t("jc.regime.s.none"))
	lines.append(JwText.render("jc.regime.s.econ", {"v": JwText.t("jc.regime.econ." + String(rp["economy"]))}))
	if String(rp.get("flavor", "")) != "":
		lines.append(JwText.t("jc.regime.fl." + String(rp["flavor"])))
	vb.add_child(JwUi.label("".join(lines), "body", "text.secondary", true))
	# 四个取向：左边是负的一头，右边是正的一头
	var axes: Dictionary = rp["axes"]
	var gr: GridContainer = JcUi.grid(4, 10, 6)
	gr.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for ax: Array in [["benevolent", "harsh", "benevolent", JcUi.BAD, JcUi.GOOD], ["central", "laissez", "central", JcUi.WARN, JcUi.WARN],
			["open", "closed", "open", JcUi.WARN, JcUi.GOOD], ["reform", "traditional", "reform", JcUi.WARN, JcUi.GOOD]]:
		var neg: String = String(ax[1])
		var pos: String = String(ax[2])
		var lh: HBoxContainer = JwUi.hbox(6)
		lh.add_child(JcUi.badge(JcUi.POLICY_ICON % ("axis_" + neg), 24.0, JwText.t("jc.regime.ax." + neg), "line.strong"))
		var ll: Label = JwUi.label(JwText.t("jc.regime.ax." + neg), "caption", "text.secondary")
		ll.custom_minimum_size = Vector2(44, 0)
		lh.add_child(ll)
		gr.add_child(lh)
		var am: JcAxis = JcAxis.new()
		am.value = int(axes[String(ax[0])])
		am.left_tone = String(ax[3])
		am.right_tone = String(ax[4])
		am.custom_minimum_size = Vector2(260, 20)
		gr.add_child(am)
		var rh: HBoxContainer = JwUi.hbox(6)
		var rl: Label = JwUi.label(JwText.t("jc.regime.ax." + pos), "caption", "text.secondary")
		rl.custom_minimum_size = Vector2(44, 0)
		rh.add_child(rl)
		rh.add_child(JcUi.badge(JcUi.POLICY_ICON % ("axis_" + pos), 24.0, JwText.t("jc.regime.ax." + pos), "line.strong"))
		gr.add_child(rh)
		gr.add_child(JwUi.spacer())
	vb.add_child(gr)
	var ec: HBoxContainer = JwUi.hbox(8)
	ec.add_child(JwUi.label(JwText.t("jc.regime.ec_head"), "caption", "text.muted"))
	var econ: Dictionary = rp["econ"]
	for k: String in ["agrarian", "mercantile", "industrial"]:
		var on: bool = String(rp["economy"]) == k
		var item: HBoxContainer = JwUi.hbox(4)
		item.add_child(JcUi.badge(JcUi.POLICY_ICON % ("axis_" + k), 22.0, JwText.t("jc.regime.ec." + k), JcUi.GOOD if on else "line.hair"))
		item.add_child(JwUi.label(JwText.render("jc.regime.ec_item", {"name": JwText.t("jc.regime.ec." + k), "v": str(int(econ[k]))}),
				"caption", JcUi.GOOD if on else "text.muted"))
		ec.add_child(item)
	vb.add_child(ec)
	return card


# ── 眼下的局势 ───────────────────────────────────────────────────────────
func _situations() -> PanelContainer:
	var c: Dictionary = JcUi.card(t("jc.pt.sits"), t("jc.pt.sits_sub"))
	var body: VBoxContainer = c["body"]
	var sits: Array = v["situations"]
	if sits.is_empty():
		body.add_child(JwUi.para(t("jc.pt.sits_none"), "text.muted"))
	for sv: Dictionary in sits:
		body.add_child(JcSituationCard.build(page.session, g, sv, false))
	if int(v["treaty_until"]) > int(v["q"]):
		body.add_child(JwUi.para(rt("jc.pt.treaty", {"date": JcFmt.date(int(v["treaty_until"]), g.st.start_year)}), JcUi.WARN))
	return c["root"]


# ── 可以推行的改革 ───────────────────────────────────────────────────────
func _reforms() -> PanelContainer:
	var c: Dictionary = JcUi.card(t("jc.pt.reforms"), t("jc.pt.reforms_sub"))
	var body: VBoxContainer = c["body"]
	var fl: HFlowContainer = JcUi.flow(12, 12)
	var n: int = 0
	for rf: Dictionary in v["reforms"]:
		if not bool(rf["here"]):
			continue
		fl.add_child(_reform_box(rf))
		n += 1
	if n == 0:
		body.add_child(JwUi.para(t("jc.pt.reforms_none"), "text.muted"))
	else:
		body.add_child(fl)
	if int(v["reform_cool"]) > int(v["q"]):
		body.add_child(JwUi.label(rt("jc.pt.reform_cool", {"date": JcFmt.date(int(v["reform_cool"]), g.st.start_year)}),
				"caption", "text.muted"))
	return c["root"]


func _reform_box(rf: Dictionary) -> PanelContainer:
	var ok: bool = bool(rf["ok"])
	var box: StyleBoxFlat = JwTheme.box4("bg.raised" if ok else "bg.panel", "line.strong" if ok else "line.hair", 1, 0, 0, 0, 10)
	box.set_corner_radius_all(8)
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", box)
	p.custom_minimum_size = Vector2(REFORM_W, 0)
	var vb: VBoxContainer = JwUi.vbox(6)
	p.add_child(vb)
	var path: String = JcUi.REFORM_ART % String(rf["id"])
	if JcUi.has_art(path):
		vb.add_child(JcUi.art(path, Vector2(REFORM_W, 140.0)))
	var inner: VBoxContainer = JwUi.vbox(5)
	vb.add_child(JwUi.margin(inner, 12, 4, 12, 0))
	var h: HBoxContainer = JwUi.hbox(8)
	if not JcUi.has_art(path):
		h.add_child(JcUi.badge(path, 36.0, String(rf["name"]), "line.strong"))
	h.add_child(JwUi.label(String(rf["name"]), "body_bold", "text.primary"))
	inner.add_child(h)
	var to: String = String(rf["to"])
	var path_row: HBoxContainer = JwUi.hbox(6)
	path_row.add_child(JcUi.badge(JcUi.regime_art(String(v["regime_id"]), "steady"), 26.0, glyph(g, String(v["regime_id"])), "line.hair"))
	path_row.add_child(JwUi.label(rt("jc.pt.rf.path", {"from": g.name_of("regime", String(v["regime_id"])),
			"to": g.name_of("regime", to)}), "body", "text.secondary"))
	path_row.add_child(JcUi.badge(JcUi.regime_art(to, "steady"), 26.0, glyph(g, to), JcUi.GOOD))
	inner.add_child(path_row)
	var desc: Label = JwUi.label(String(rf["desc"]), "caption", "text.secondary", true)
	desc.custom_minimum_size = Vector2(REFORM_W - 24.0, 0)
	inner.add_child(desc)
	var sides: HFlowContainer = JcUi.flow(6, 4)
	if not (rf["pro"] as Array).is_empty():
		sides.add_child(JwUi.label(t("jc.pt.rf.pro"), "caption", "text.muted"))
		for cp: Variant in rf["pro"]:
			sides.add_child(JcUi.chip(g.name_of("class", String(cp)), JcUi.GOOD))
	if not (rf["con"] as Array).is_empty():
		sides.add_child(JwUi.label(t("jc.pt.rf.con"), "caption", "text.muted"))
		for cc: Variant in rf["con"]:
			sides.add_child(JcUi.chip(g.name_of("class", String(cc)), JcUi.BAD))
	inner.add_child(sides)
	var rate: int = maxi(1, int(rf["rate"]))
	@warning_ignore("integer_division")
	var eta: int = (1_000_000 + rate - 1) / rate
	inner.add_child(JwUi.label(rt("jc.pt.rf.cost", {"start": JcFmt.money(int(rf["cost_start"])), "q": JcFmt.money(int(rf["cost_q"]))}),
			"caption", "text.muted", true))
	inner.add_child(JwUi.label(rt("jc.pt.rf.time", {"n": JcFmt.quarters(int(rf["quarters"])), "eta": JcFmt.quarters(eta)}),
			"caption", "text.muted", true))
	var act: HBoxContainer = JwUi.hbox(8)
	var id: String = String(rf["id"])
	var b: Button = JcUi.button(t("jc.pt.rf.go"), true, func() -> void:
		page.session.order({"kind": "reform", "reform": id}))
	b.disabled = not ok
	act.add_child(b)
	if not ok:
		var why: String = String(rf["reason"])
		var txt: String = ""
		if why == "reason.era_too_early":
			txt = rt("jc.pt.rf.need_era", {"era": JcFmt.era_name(int(rf["era"]))})
		elif why == "reason.tech_missing":
			txt = rt("jc.pt.rf.need_tech", {"tech": g.name_of("tech", String(rf["tech"]))})
		else:
			txt = JcFmt.reason(g, {"reason": why, "cost": int(rf["cost_start"])})
		var wl: Label = JwUi.label(txt, "caption", JcUi.WARN, true)
		wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		act.add_child(wl)
	inner.add_child(act)
	return p


# ── 压力 ────────────────────────────────────────────────────────────────
func _pressures() -> PanelContainer:
	var c: Dictionary = JcUi.card(t("jc.pt.pres"), t("jc.pt.pres_sub"))
	var body: VBoxContainer = c["body"]
	for pv: Dictionary in v["pressures"]:
		var kind: String = String(pv["kind"])
		var val: int = int(pv["v"])
		var h: HBoxContainer = JwUi.hbox(10)
		h.add_child(JcUi.badge(JcUi.UI_ICON % ("pres_" + kind), 32.0, t("jc.pt.p." + kind), JcUi.BAD if val >= 500_000 else "line.strong"))
		var nl: Label = JwUi.label(t("jc.pt.p." + kind), "body_bold", "text.primary")
		nl.custom_minimum_size = Vector2(96, 0)
		h.add_child(nl)
		var m: JcMeter = JcUi.meter(val, JcUi.BAD if val >= 700_000 else (JcUi.WARN if val >= 400_000 else JcUi.GOOD), 300.0, 12.0)
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(m)
		h.add_child(JwUi.label(JcFmt.pct(val, 0), "num_bold", "text.primary"))
		body.add_child(h)
		if not bool(pv["on"]):
			body.add_child(JwUi.label(t("jc.pt.p.off." + kind), "caption", "text.muted"))
			continue
		var tot: int = 0
		var fl: HFlowContainer = JcUi.flow(6, 4)
		for f: Variant in pv["factors"]:
			var fa: Array = f
			var fv: int = int(fa[1])
			tot += fv
			fl.add_child(JcUi.chip(rt("jc.pt.p.factor", {"name": factor_name(g, String(fa[0])), "v": JcSituationCard.signed_pct(fv)}),
					JcUi.BAD if fv > 0 else JcUi.GOOD))
		var line: PackedStringArray = PackedStringArray()
		line.append(rt("jc.pt.p.rate", {"v": JcSituationCard.signed_pct(tot)}))
		line.append(t("jc.pt.p.full." + kind))
		if int(pv["cool"]) > int(v["q"]):
			line.append(rt("jc.pt.p.cool", {"date": JcFmt.date(int(pv["cool"]), g.st.start_year)}))
		body.add_child(JwUi.label(t("jc.list_sep").join(line), "caption", "text.secondary", true))
		body.add_child(fl)
	body.add_child(JwUi.label(rt("jc.pt.unemp", {"v": JcFmt.pct(int(v["urban_unemp"]), 1)}), "caption", "text.muted", true))
	return c["root"]


## 压力来由的名字：「威信低」「工匠民心低落」……
static func factor_name(gm: JCGame, key: String) -> String:
	if key.begins_with("class:"):
		return JwText.render("jc.pol.factor.class", {"class": gm.name_of("class", key.substr(6))})
	return JwText.t("jc.pol.factor." + key)


# ── 各种政体 ─────────────────────────────────────────────────────────────
func _ladder() -> PanelContainer:
	var c: Dictionary = JcUi.card(t("jc.pt.ladder"), t("jc.pt.ladder_sub"))
	var body: VBoxContainer = c["body"]
	var fl: HFlowContainer = JcUi.flow(10, 10)
	for rd: Dictionary in v["regimes"]:
		var cur: bool = bool(rd["current"])
		var box: StyleBoxFlat = JwTheme.box4("bg.raised" if cur else "bg.panel", JcUi.GOOD if cur else "line.hair", 2 if cur else 1, 0, 0, 0, 8)
		box.set_corner_radius_all(8)
		var p: PanelContainer = PanelContainer.new()
		p.add_theme_stylebox_override("panel", box)
		p.custom_minimum_size = Vector2(REGIME_W, 0)
		if not cur and not bool(rd["seen"]):
			p.modulate = Color(1, 1, 1, 0.72)
		var vb: VBoxContainer = JwUi.vbox(4)
		p.add_child(vb)
		var em: Control = JcUi.badge(JcUi.regime_art(String(rd["id"]), "steady"), 72.0, glyph(g, String(rd["id"])), JcUi.GOOD if cur else "line.strong")
		em.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(em)
		var nl: Label = JwUi.label(String(rd["name"]), "body_bold", "text.primary" if cur else "text.secondary")
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(nl)
		var sl: Label = JwUi.label(t("jc.pt.r.now") if cur else rt("jc.pt.r.era", {"era": JcFmt.era_name(int(rd["era"]))}),
				"caption", JcUi.GOOD if cur else "text.muted")
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(sl)
		var tip: PackedStringArray = PackedStringArray([String(rd["desc"])])
		var eff: PackedStringArray = JcEventOverlay.effects_text(g, rd["effects"], 0)
		if not eff.is_empty():
			tip.append(t("jc.list_sep").join(eff))
		var sup: PackedStringArray = JcEventOverlay.support_text(g, rd["support"])
		if not sup.is_empty():
			tip.append(rt("jc.pt.r.tip_sup", {"list": t("jc.list_sep").join(sup)}))
		p.tooltip_text = "\n".join(tip)
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		fl.add_child(p)
	body.add_child(fl)
	return c["root"]


# ── 政体更替 ─────────────────────────────────────────────────────────────
func _history() -> PanelContainer:
	var c: Dictionary = JcUi.card(t("jc.pt.hist"), "")
	var body: VBoxContainer = c["body"]
	var hist: Array = v["history"]
	if hist.is_empty():
		body.add_child(JwUi.para(t("jc.pt.hist_none"), "text.muted"))
	for i: int in range(hist.size() - 1, -1, -1):
		var hd: Dictionary = hist[i]
		var h: HBoxContainer = JwUi.hbox(8)
		h.add_child(JwUi.label(JcFmt.date(int(hd["q"]), g.st.start_year), "caption", "text.muted"))
		h.add_child(JcUi.badge(JcUi.regime_art(String(hd["to"]), "steady"), 24.0, glyph(g, String(hd["to"])), "line.strong"))
		h.add_child(JwUi.label(rt("jc.pt.h.row", {"from": g.name_of("regime", String(hd["from"])), "to": g.name_of("regime", String(hd["to"])),
				"how": t("jc.pol.how." + String(hd["how"]))}), "body", "text.secondary", true))
		body.add_child(h)
	return c["root"]
