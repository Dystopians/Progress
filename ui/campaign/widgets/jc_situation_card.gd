## 一个进行中的政局（改革、革命风潮、列强叩关、战事、经济危机）的卡片：配图、名字与去向、进度与每季走势、
## 来由，待决的关口（每个选项的后果、花费、能不能选）；推行中的改革可以放弃。
## 「政治改革」页签与待决弹窗共用。数据来自 JCViews.politics() / pending_situations()。
class_name JcSituationCard
extends RefCounted

const ART_H: float = 180.0


static func t(key: String) -> String:
	return JwText.t(key)


static func rt(key: String, slots: Dictionary) -> String:
	return JwText.render(key, slots)


## 局势的配图：改革用改革的图，其余用局势种类的图（没图时占位圆章写名字的头一个字）。
static func art_path(sv: Dictionary) -> String:
	if String(sv["k"]) == "reform":
		return JcUi.REFORM_ART % String(sv["reform"])
	return JcUi.SITUATION_ART % String(sv["k"])


## 名字：「推行『立宪运动』」「革命风潮」……
static func title_of(g: JCGame, sv: Dictionary) -> String:
	if String(sv["k"]) == "reform":
		return rt("jc.pt.s.reform", {"reform": g.name_of("reform", String(sv["reform"]))})
	return t("jc.sit.name." + String(sv["k"]))


## 阶层名单：「商贾、工匠」
static func class_list(g: JCGame, ids: Variant) -> String:
	var names: PackedStringArray = PackedStringArray()
	for c: Variant in ids:
		names.append(g.name_of("class", String(c)))
	return t("jc.name_sep").join(names) if not names.is_empty() else t("jc.pt.nobody")


## 局势说明与关口文字里的空：{reform} {regime} {pro} {con} {class}
static func slots_of(g: JCGame, sv: Dictionary) -> Dictionary:
	var agg: Array = sv.get("agg", [])
	return {"reform": g.name_of("reform", String(sv.get("reform", ""))), "regime": g.name_of("regime", String(sv.get("to", ""))),
			"pro": class_list(g, sv.get("pro", [])), "con": class_list(g, sv.get("con", [])),
			"class": class_list(g, agg), "n": JcFmt.quarters(int(sv.get("left", 0)))}


## 有符号的百分点（「+8.5%」「−3%」）。
static func signed_pct(v: int) -> String:
	return ("+" if v >= 0 else JcFmt.MINUS) + JcFmt.pct(absi(v), 1)


static func build(s: JcSession, g: JCGame, sv: Dictionary, with_art: bool, width: float = 0.0) -> Control:
	var k: String = String(sv["k"])
	var ask: Dictionary = sv.get("ask", {})
	var hot: bool = not ask.is_empty()
	var tone: String = JcUi.BAD if (hot or k in ["revolution", "war", "invasion"]) else (JcUi.WARN if k == "depression" else JcUi.GOOD)
	var box: StyleBoxFlat = JwTheme.box4("bg.raised", tone, 2, 0, 0, 0, 12)
	box.set_corner_radius_all(8)
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", box)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if width > 0.0:
		p.custom_minimum_size = Vector2(width, 0)
	var vb: VBoxContainer = JwUi.vbox(8)
	p.add_child(vb)
	var sl: Dictionary = slots_of(g, sv)
	if with_art:
		var path: String = art_path(sv)
		if JcUi.has_art(path):
			var pic: Control = JcUi.art(path, Vector2(0, ART_H), true)
			pic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			vb.add_child(pic)
	var inner: VBoxContainer = JwUi.vbox(6)
	var mc: MarginContainer = JwUi.margin(inner, 14, 4, 14, 0)
	vb.add_child(mc)
	# 名字与去向
	var h: HBoxContainer = JwUi.hbox(10)
	if not with_art or not JcUi.has_art(art_path(sv)):
		h.add_child(JcUi.badge(art_path(sv), 44.0, title_of(g, sv), tone))
	var nv: VBoxContainer = JwUi.vbox(2)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_child(JwUi.label(title_of(g, sv), "title_sub", "text.primary", true))
	var sub: String = rt("jc.pt.s.sub." + k, sl)
	if sub != "":
		nv.add_child(JwUi.label(sub, "body", "text.secondary", true))
	h.add_child(nv)
	if hot:
		h.add_child(JcUi.chip(t("jc.pt.ask.head"), JcUi.BAD, true))
	inner.add_child(h)
	inner.add_child(JwUi.label(rt("jc.sit.desc." + k, sl), "caption", "text.secondary", true))
	inner.add_child(_progress(g, sv))
	# 待决的关口
	if hot:
		inner.add_child(_ask(s, g, sv, sl))
	elif k == "reform":
		var ab: Button = JcUi.button(t("jc.pt.s.abandon"), false, func() -> void:
			s.order({"kind": "reform_abandon", "sid": int(sv["sid"]), "reform": String(sv["reform"])}))
		ab.tooltip_text = t("jc.pt.s.abandon_tip")
		var ah: HBoxContainer = JwUi.hbox(8)
		ah.add_child(JwUi.spacer())
		ah.add_child(ab)
		inner.add_child(ah)
	return p


## 进度条与每季走势；战事是一条两头的刻度（左败右胜）。
static func _progress(g: JCGame, sv: Dictionary) -> Control:
	var k: String = String(sv["k"])
	var v: VBoxContainer = JwUi.vbox(4)
	var pr: int = int(sv["p"])
	var rate: int = int(sv.get("rate", 0))
	match k:
		"reform", "revolution":
			var row: HBoxContainer = JwUi.hbox(10)
			row.add_child(JwUi.label(t("jc.pt.s.bar." + k), "caption", "text.muted"))
			var marks: Array = sv.get("marks", [])
			var stage: int = int(sv.get("stage", 0))
			var m: JcMeter = JcUi.meter(pr, JcUi.GOOD if k == "reform" else JcUi.BAD, 260.0, 10.0,
					int(marks[stage]) if stage < marks.size() else -1)
			m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(m)
			row.add_child(JwUi.label(JcFmt.pct(clampi(pr, 0, 1_000_000), 0), "num_bold", "text.primary"))
			v.add_child(row)
			var bits: PackedStringArray = PackedStringArray()
			bits.append(rt("jc.pt.s.rate", {"v": signed_pct(rate)}))
			if rate > 0 and pr < 1_000_000:
				@warning_ignore("integer_division")
				bits.append(rt("jc.pt.s.eta." + k, {"n": JcFmt.quarters((1_000_000 - pr + rate - 1) / rate)}))
			if k == "reform":
				bits.append(rt("jc.pt.s.sides", {"pro": class_list(g, sv.get("pro", [])), "con": class_list(g, sv.get("con", []))}))
				if int(sv.get("cost_q", 0)) > 0:
					bits.append(rt("jc.pt.s.cost_q", {"v": JcFmt.money(int(sv["cost_q"]))}))
			v.add_child(JwUi.label(t("jc.list_sep").join(bits), "caption", "text.muted", true))
		"war":
			var row2: HBoxContainer = JwUi.hbox(10)
			row2.add_child(JwUi.label(t("jc.pt.s.lose"), "caption", JcUi.BAD))
			var ax: JcAxis = JcAxis.new()
			@warning_ignore("integer_division")
			ax.value = clampi(pr / 10_000, -100, 100)
			ax.left_tone = JcUi.BAD
			ax.right_tone = JcUi.GOOD
			ax.custom_minimum_size = Vector2(260, 20)
			ax.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row2.add_child(ax)
			row2.add_child(JwUi.label(t("jc.pt.s.win"), "caption", JcUi.GOOD))
			v.add_child(row2)
			v.add_child(JwUi.label(rt("jc.pt.s.war", {"ours": JcFmt.pct(int(sv.get("ours", 0)), 0),
					"enemy": JcFmt.pct(int(sv.get("enemy", 0)), 0), "v": signed_pct(rate),
					"n": JcFmt.quarters(int(sv.get("left_q", 0)))}), "caption", "text.muted", true))
		"invasion":
			v.add_child(JwUi.label(rt("jc.pt.s.odds", {"ours": JcFmt.pct(int(sv.get("ours", 0)), 0),
					"enemy": JcFmt.pct(int(sv.get("enemy", 0)), 0)}), "caption", "text.muted", true))
		"depression":
			var bits2: PackedStringArray = PackedStringArray()
			var opt: String = String(sv.get("opt", ""))
			if opt != "":
				bits2.append(rt("jc.pt.s.dep_opt", {"opt": t("jc.sit.opt.depression." + opt)}))
				bits2.append(rt("jc.pt.s.dep_left", {"n": JcFmt.quarters(int(sv.get("left", 0)))}))
				if opt == "works":
					bits2.append(rt("jc.pt.s.works_q", {"v": JcFmt.money(int(sv.get("works_q", 0)))}))
			if not bits2.is_empty():
				v.add_child(JwUi.label(t("jc.list_sep").join(bits2), "caption", "text.muted", true))
	return v


## 关口：说明、各选项（后果、花费）、按钮；过期按哪项办。
static func _ask(s: JcSession, g: JCGame, sv: Dictionary, sl: Dictionary) -> Control:
	var ask: Dictionary = sv["ask"]
	var set_id: String = String(ask["set"])
	var v: VBoxContainer = JwUi.vbox(8)
	v.add_child(JwUi.hsep())
	v.add_child(JwUi.label(rt("jc.sit.ask." + set_id, sl), "body", "text.primary", true))
	for o: Dictionary in ask["options"]:
		v.add_child(_option(s, g, sv, set_id, o, sl))
	var dflt: String = String(ask.get("default", ""))
	if dflt != "":
		v.add_child(JwUi.label(rt("jc.pt.ask.until", {"date": JcFmt.date(int(ask["until"]), g.st.start_year),
				"opt": t("jc.sit.opt.%s.%s" % [set_id, dflt])}), "caption", "text.muted", true))
	return v


static func _option(s: JcSession, g: JCGame, sv: Dictionary, set_id: String, o: Dictionary, sl: Dictionary) -> Control:
	var oid: String = String(o["id"])
	var ok: bool = bool(o["ok"])
	var p: PanelContainer = JwUi.panel_style(JwTheme.box_left_rule("bg.panel", "line.strong" if ok else "line.hair", 4, 10))
	var h: HBoxContainer = JwUi.hbox(12)
	p.add_child(h)
	var tv: VBoxContainer = JwUi.vbox(3)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	tv.add_child(JwUi.label(t("jc.sit.opt.%s.%s" % [set_id, oid]), "body_bold", "text.primary" if ok else "text.muted", true))
	tv.add_child(JwUi.label(rt("jc.sit.optd.%s.%s" % [set_id, oid], sl), "caption", "text.secondary", true))
	if int(o.get("works_q", 0)) > 0:
		tv.add_child(JwUi.label(rt("jc.pt.s.works_q", {"v": JcFmt.money(int(o["works_q"]))}), "caption", "text.muted"))
	var cost: int = int(o.get("cost", 0))
	var lab: String = t("jc.pt.ask.choose") if cost <= 0 else rt("jc.pt.ask.choose_cost", {"cost": JcFmt.money(cost)})
	var sid: int = int(sv["sid"])
	var kind: String = String(sv["k"])
	var b: Button = JcUi.button(lab, true, func() -> void:
		s.order({"kind": "situation", "sid": sid, "option": oid, "sit": kind, "set": set_id}))
	b.disabled = not ok
	if not ok:
		b.tooltip_text = JcFmt.reason(g, {"reason": String(o.get("reason", "")), "cost": cost})
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	return p
