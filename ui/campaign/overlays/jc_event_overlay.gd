## 待决事件：配图、经过、每个选项的花费、效果（持续几季）与各阶层的反应；选一个就办。
## 事件托管（代办）时不弹出；可以先关掉，截止前回来再定（过期按「听其自然」处理）。
class_name JcEventOverlay
extends JcOverlay


func build() -> void:
	width_ratio = 0.62
	var g: JCGame = game()
	var evs: Array = session.views().pending_events()
	if evs.is_empty():
		set_title(t("jc.ev.none_title"))
		body.add_child(JwUi.para(t("jc.ev.none"), "text.muted"))
		return
	set_title(rt("jc.ev.title", {"n": str(evs.size())}))
	for ev: Dictionary in evs:
		body.add_child(_event_box(g, ev))


func _event_box(g: JCGame, ev: Dictionary) -> Control:
	var box: VBoxContainer = JwUi.vbox(10)
	var art: String = String(ev["art"])
	if art != "" and not art.begins_with("res://"):
		art = "res://" + art
	var pic: Control = JcUi.art(art, Vector2(0, 220), true)
	pic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(pic)
	var h: HBoxContainer = JwUi.hbox(10)
	h.add_child(JwUi.title(String(ev["name"]), "title_block"))
	var rid: String = String(ev["region"])
	if rid != "":
		h.add_child(JcUi.chip(g.name_of("region", rid), JcUi.MUTED))
	h.add_child(JwUi.spacer())
	h.add_child(JwUi.label(rt("jc.ev.until", {"date": JcFmt.date(int(ev["until"]), g.st.start_year)}), "caption", "text.muted"))
	box.add_child(h)
	var text: String = String(ev["text"]).replace("{region}", g.name_of("region", rid) if rid != "" else t("jc.ev.somewhere"))
	box.add_child(JwUi.para(text, "text.secondary"))
	var opts: Array = ev["options"]
	for i: int in opts.size():
		box.add_child(_option(g, String(ev["event"]), i, opts[i]))
	box.add_child(JwUi.hsep())
	return box


func _option(g: JCGame, eid: String, i: int, o: Dictionary) -> Control:
	var p: PanelContainer = JwUi.panel_style(JwTheme.box_left_rule("bg.raised", "line.strong", 4, 10))
	var h: HBoxContainer = JwUi.hbox(12)
	p.add_child(h)
	var v: VBoxContainer = JwUi.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(JwUi.label(String(o["text"]), "body_bold", "text.primary", true))
	var bits: PackedStringArray = effects_text(g, o.get("effects", []), int(o.get("duration", 0)))
	for s: String in support_text(g, o.get("support", {})):
		bits.append(s)
	if not bits.is_empty():
		v.add_child(JwUi.label(t("jc.list_sep").join(bits), "caption", "text.secondary", true))
	var cost: int = int(o.get("cost", 0))
	var lab: String = t("jc.ev.choose") if cost <= 0 else rt("jc.ev.choose_cost", {"cost": JcFmt.money(cost)})
	var b: Button = JcUi.button(lab, true, func() -> void:
		session.order({"kind": "event", "event": eid, "option": i}))
	b.disabled = cost > g.st.treasury
	if b.disabled:
		b.tooltip_text = t("jc.ev.no_money")
	h.add_child(b)
	return p


## 效果列表 → 一串白话（事件、政令、地标共用）。value 是百分数（−30 = 降三成）。
static func effects_text(g: JCGame, effects: Array, duration: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for e: Variant in effects:
		if not (e is Dictionary):
			continue
		var ed: Dictionary = e
		var target: String = String(ed.get("target", ""))
		var val: float = float(ed.get("value", 0))
		var scope: String = String(ed.get("scope", ""))
		var vs: String = ("+" if val > 0 else "") + (str(int(val)) if is_equal_approx(val, roundf(val)) else str(snappedf(val, 0.1)))
		var slots: Dictionary = {"v": vs.replace("-", JcFmt.MINUS)}
		if scope != "" and g != null:
			slots["scope"] = g.name_of("class", scope) if g.is_class_id(scope) else g.name_of("region", scope)
		var key: String = "jc.eff." + target if JwText.has("jc.eff." + target) else "jc.eff.other"
		out.append(JwText.render(key, slots))
	if duration > 0 and not out.is_empty():
		out.append(JwText.render("jc.eff.for", {"n": JcFmt.quarters(duration)}))
	return out


static func support_text(g: JCGame, support: Variant) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var d: Dictionary = {}
	if support is Dictionary:
		d = support
	elif support is Array and not (support as Array).is_empty() and (support as Array)[0] is Dictionary:
		d = (support as Array)[0]
	for c: Variant in d.keys():
		var v: int = int(d[c])
		if v == 0:
			continue
		out.append(JwText.render("jc.eff.support_of", {"class": g.name_of("class", String(c)),
				"v": ("+" if v > 0 else JcFmt.MINUS) + str(absi(v))}))
	return out
