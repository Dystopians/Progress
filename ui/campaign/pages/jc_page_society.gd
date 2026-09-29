## 民生：四个阶层各自的人口、收入（从哪来）、生活与体面、民怨、支持，以及每项需要满足了几成；
## 最上面列出民怨最重的几处与主因，点地区名跳到舆图。
class_name JcPageSociety
extends JcPage

const PPM_I: int = 1_000_000


func refresh() -> void:
	clear()
	if not session.has_game():
		return
	var g: JCGame = game()
	var v: Dictionary = views().society()
	content.add_child(JwUi.para(rt("jc.soc.intro", {"expect": JcFmt.times(int(v["expect"])),
			"world": JcFmt.era_name(int(v["world_era"]))}), "text.secondary"))
	# ── 民怨最重的地方 ──
	var hc: Dictionary = JcUi.card(t("jc.soc.hot"), t("jc.soc.hot_sub"))
	var hb: VBoxContainer = hc["body"]
	var any_hot: bool = false
	for h: Dictionary in v["hotspots"]:
		var unr: int = int(h["unrest"])
		if unr < 250_000:
			continue
		any_hot = true
		var row: HBoxContainer = JwUi.hbox(10)
		var rid: String = String(h["region"])
		row.add_child(JcUi.link(g.name_of("region", rid), func() -> void:
			session.selected_region = rid
			goto_page("map")))
		row.add_child(JwUi.label(g.name_of("class", String(h["class"])), "body", "text.secondary"))
		var m: JcMeter = JcUi.meter(unr, JcUi.tone(false, unr < 450_000), 120.0)
		row.add_child(m)
		row.add_child(JwUi.label(rt("jc.soc.hot_row", {"unrest": JcFmt.pct(unr, 0), "living": JcFmt.pct(int(h["living"]), 0),
				"cause": JcFmt.k(String(h["cause"]))}), "body", "text.secondary", true))
		hb.add_child(row)
	if not any_hot:
		hb.add_child(JwUi.para(t("jc.soc.calm"), JcUi.GOOD))
	content.add_child(hc["root"])
	# ── 各阶层 ──
	var gr: GridContainer = JcUi.grid(2, 14, 14)
	for cv: Dictionary in v["classes"]:
		gr.add_child(_class_card(cv))
	content.add_child(gr)


func _class_card(cv: Dictionary) -> PanelContainer:
	var c: Dictionary = JcUi.card(String(cv["name"]), JcFmt.people(int(cv["pop"])))
	var body: VBoxContainer = c["body"]
	body.add_child(JwUi.label(String(cv["note"]), "caption", "text.muted", true))
	var liv: int = int(cv["living"])
	var com: int = int(cv["comfort"])
	var unr: int = int(cv["unrest"])
	var sup: int = int(cv["support"])
	body.add_child(JcUi.row(t("jc.soc.living"), JcFmt.pct(liv, 0), "text.primary", clampi(liv, 0, PPM_I),
			JcUi.tone(liv >= 950_000, liv >= 850_000)))
	body.add_child(JcUi.row(t("jc.soc.comfort"), JcFmt.pct(com, 0), "text.primary", clampi(com, 0, PPM_I),
			JcUi.tone(com >= 900_000, com >= 700_000)))
	body.add_child(JcUi.row(t("jc.soc.unrest"), JcFmt.pct(unr, 0), "text.primary", clampi(unr, 0, PPM_I),
			JcUi.tone(unr < 250_000, unr < 450_000)))
	body.add_child(JcUi.row(t("jc.soc.support"), JcFmt.pct(sup, 0), "text.primary", clampi(sup, 0, PPM_I),
			JcUi.tone(sup >= 500_000, sup >= 350_000)))
	if String(cv["class"]) != "gentry":
		body.add_child(JcUi.row(t("jc.soc.unemp"), JcFmt.pct(int(cv["unemp"])), "text.primary"))
	# 收入
	var src: Array = cv["src"]
	var total_in: int = 0
	for x: Variant in src:
		total_in += maxi(0, int(x))
	var parts: PackedStringArray = PackedStringArray()
	for s: int in src.size():
		var a: int = int(src[s])
		if a != 0:
			parts.append(rt("jc.soc.src.%d" % s, {"v": JcFmt.pct(JCMath.ratio_ppm(absi(a), maxi(1, total_in)), 0)}))
	body.add_child(JwUi.label(rt("jc.soc.income", {"v": JcFmt.money(JCMath.muldiv(int(cv["income_pc"]), 4, 1000))}), "body_bold", "text.primary"))
	if not parts.is_empty():
		body.add_child(JwUi.label(t("jc.list_sep").join(parts), "caption", "text.muted", true))
	# 各项需要
	var nf: GridContainer = JcUi.grid(2, 12, 4)
	for nd: Dictionary in cv["needs"]:
		var sat: int = int(nd["sat"])
		var h: HBoxContainer = JwUi.hbox(6)
		var l: Label = JwUi.label(String(nd["name"]) + (t("jc.soc.ess_mark") if bool(nd["essential"]) else ""), "caption",
				"text.secondary")
		l.custom_minimum_size = Vector2(72, 0)
		h.add_child(l)
		var m: JcMeter = JcUi.meter(sat, JcUi.tone(sat >= 900_000, sat >= 600_000), 90.0, 6.0)
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(m)
		h.add_child(JwUi.label(JcFmt.pct(sat, 0), "caption", "text.muted"))
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nf.add_child(h)
	body.add_child(JwUi.label(t("jc.soc.needs"), "caption", "text.muted"))
	body.add_child(nf)
	return c["root"]

