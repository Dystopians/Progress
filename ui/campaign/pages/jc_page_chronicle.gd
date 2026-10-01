## 纪事：三栏——
##   国史（默认）：1600—2000 的时间轴；按年代分节，每节有「盛世 / 治世 / 平世 / 荒年 / 乱世」的评定、
##                史官曰（人口、生活、威信、时代与大事）、人口与生活的小曲线；大事做成配图卡片，小事一行一条。
##   逐季纪事：每季发生的事（可按类别筛）；托管记录：托管替你做了什么、为什么、办成没有。
class_name JcPageChronicle
extends JcPage

const KINDS: PackedStringArray = ["all", "era", "crisis", "event", "build", "invest", "research", "decree", "fiscal", "trade",
		"landmark"]
const BIG_W: float = 300.0
const BIG_H: float = 168.0
## 默认展开最近几个年代
const OPEN_DECADES: int = 6
## 三个栏目的小图标
const TAB_ICON: Dictionary = {"annals": "era", "chron": "event", "steward": "steward"}

var _tab: String = "annals"
var _kind: String = "all"
var _open: Dictionary = {}


func refresh() -> void:
	clear()
	if not session.has_game():
		return
	var g: JCGame = game()
	var tabs: HBoxContainer = JwUi.hbox(4)
	for id: String in ["annals", "chron", "steward"]:
		var b: Button = JwUi.button(t("jc.chr.tab." + id), "TabBtn")
		JcUi.set_icon(b, JcUi.CHRON_ICON % String(TAB_ICON[id]), 20)
		b.toggle_mode = true
		b.set_pressed_no_signal(_tab == id)
		b.pressed.connect(func() -> void:
			_tab = id
			refresh())
		tabs.add_child(b)
	content.add_child(tabs)
	match _tab:
		"steward":
			_steward(g)
		"chron":
			_chron(g)
		_:
			_annals(g)


# ── 国史 ────────────────────────────────────────────────────────────────
func _annals(g: JCGame) -> void:
	var v: Dictionary = views().annals()
	var list: Array = v["list"]
	var hist: Array = v["hist"]
	# 卷轴页眉：「国史」两个字压在卷轴上（墨色）
	var hd: Control = JcUi.ornament(JcUi.CHRON_DECOR % "scroll_header", t("jc.chr.tab.annals"), 76.0, "title_block", "bg.abyss")
	hd.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(hd)
	content.add_child(JwUi.para(t("jc.chr.ann.intro"), "text.muted"))
	var tl: JcTimeline = JcTimeline.new()
	tl.custom_minimum_size = Vector2(0, 78)
	tl.start_year = int(v["start_year"]) + 1
	tl.end_year = int(v["end_year"])
	tl.year_now = int(v["year"])
	var last_era: int = -1
	var last_world: int = -1
	for hv: Dictionary in hist:
		if int(hv.get("era", 1)) != last_era:
			last_era = int(hv.get("era", 1))
			tl.eras.append({"year": int(hv["year"]), "era": last_era})
		if int(hv.get("world_era", 1)) != last_world:
			if last_world > 0:
				tl.world.append({"year": int(hv["year"]), "era": int(hv.get("world_era", 1))})
			last_world = int(hv.get("world_era", 1))
	for it: Dictionary in list:
		if bool(it["big"]):
			tl.marks.append({"year": int(it["year"]), "tone": String(it["tone"])})
	tl.decade_picked.connect(func(d: int) -> void:
		_open[d] = true
		refresh())
	content.add_child(tl)
	# 按年代分节，新的在前
	var by_dec: Dictionary = {}
	for it2: Dictionary in list:
		@warning_ignore("integer_division")
		var d: int = int(it2["year"]) / 10 * 10
		if not by_dec.has(d):
			by_dec[d] = []
		(by_dec[d] as Array).append(it2)
	var hs_dec: Dictionary = {}
	for hv2: Dictionary in hist:
		@warning_ignore("integer_division")
		var d2: int = int(hv2["year"]) / 10 * 10
		if not hs_dec.has(d2):
			hs_dec[d2] = []
		(hs_dec[d2] as Array).append(hv2)
	@warning_ignore("integer_division")
	var cur: int = int(v["year"]) / 10 * 10
	var n: int = 0
	var d3: int = cur
	@warning_ignore("integer_division")
	var first_dec: int = int(v["start_year"]) / 10 * 10
	while d3 >= first_dec:
		var items: Array = by_dec.get(d3, [])
		var hs: Array = hs_dec.get(d3, [])
		if not items.is_empty() or not hs.is_empty():
			var open: bool = bool(_open.get(d3, n < OPEN_DECADES))
			if n > 0 and JcUi.has_art(JcUi.CHRON_DECOR % "divider"):
				var dv: Control = JcUi.ornament(JcUi.CHRON_DECOR % "divider", "", 26.0)
				dv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				content.add_child(dv)
			content.add_child(_decade(g, d3, items, hs, open))
			n += 1
		d3 -= 10
	if n == 0:
		content.add_child(JwUi.para(t("jc.chr.empty"), "text.muted"))


## 一个年代：评定、史官曰、小曲线；展开时列出大事卡片与小事。
func _decade(g: JCGame, d: int, items: Array, hs: Array, open: bool) -> Control:
	var card: PanelContainer = JwUi.panel("bg.panel", "line.hair", 14)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v: VBoxContainer = JwUi.vbox(10)
	card.add_child(v)
	var head: HBoxContainer = JwUi.hbox(12)
	# 年代题签框里写「1720 年代」
	head.add_child(JcUi.ornament(JcUi.CHRON_DECOR % "decade_frame", rt("jc.chr.ann.decade", {"d": str(d)}), 60.0, "title_sub",
			"text.primary"))
	var age: String = _age(hs, items)
	var age_tone: String = JcUi.GOOD if age == "golden" or age == "peace" else (JcUi.BAD if age == "chaos" or age == "peril"
			else (JcUi.WARN if age == "lean" else "text.secondary"))
	head.add_child(JcUi.chip(t("jc.chr.ann.age." + age), age_tone, age == "golden"))
	head.add_child(JwUi.spacer())
	if hs.size() >= 2:
		var pops: Array = []
		var livs: Array = []
		for hv: Dictionary in hs:
			pops.append(int(hv.get("pop", 0)))
			livs.append(int(hv.get("living", 0)))
		head.add_child(JwUi.label(t("jc.chr.ann.spark_pop"), "caption", "text.muted"))
		head.add_child(JcUi.spark(pops, JcUi.GOOD, Vector2(120, 34)))
		head.add_child(JwUi.label(t("jc.chr.ann.spark_living"), "caption", "text.muted"))
		head.add_child(JcUi.spark(livs, JcUi.WARN, Vector2(120, 34)))
	var dd: int = d
	head.add_child(JcUi.link(t("jc.chr.ann.collapse") if open else t("jc.chr.ann.expand"), func() -> void:
		_open[dd] = not open
		refresh()))
	v.add_child(head)
	var says: HBoxContainer = JwUi.hbox(10)
	says.add_child(JcUi.badge("res://assets/ui/chronicle/seal.png", 34.0, t("jc.chr.ann.seal"), JcUi.BAD))
	var sl: Label = JwUi.label(_says(g, hs, items), "body", "text.secondary", true)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	says.add_child(sl)
	v.add_child(says)
	if not open:
		return card
	var bigs: HFlowContainer = JcUi.flow(12, 12)
	var smalls: VBoxContainer = JwUi.vbox(4)
	for it: Dictionary in items:
		if bool(it["big"]):
			bigs.add_child(_big_card(g, it))
		else:
			smalls.add_child(_small_row(g, it))
	if bigs.get_child_count() > 0:
		v.add_child(bigs)
	if smalls.get_child_count() > 0:
		v.add_child(smalls)
	if items.is_empty():
		v.add_child(JwUi.label(t("jc.chr.ann.empty"), "caption", "text.muted"))
	return card


## 年代的评定：危亡之秋、乱世、荒年、盛世、治世、平世。
func _age(hs: Array, items: Array) -> String:
	for it: Dictionary in items:
		var key: String = String(it["key"])
		var a: Dictionary = it["args"]
		if key == "chron.game_over" and String(a.get("reason", "")) != "complete":
			return "peril"
		if key == "chron.crisis_up" and int(a.get("stage", 0)) >= 3:
			return "peril"
	if hs.is_empty():
		return "plain"
	var liv: int = 0
	var leg: int = 0
	var lo: int = 9_999_999
	for hv: Dictionary in hs:
		liv += int(hv.get("living", 0))
		leg += int(hv.get("legitimacy", 0))
		lo = mini(lo, int(hv.get("living", 0)))
	@warning_ignore("integer_division")
	liv = liv / hs.size()
	@warning_ignore("integer_division")
	leg = leg / hs.size()
	if leg < 350_000:
		return "chaos"
	if lo < 850_000:
		return "lean"
	if liv >= 1_050_000 and leg >= 550_000:
		return "golden"
	if liv >= 980_000 and leg >= 450_000:
		return "peace"
	return "plain"


## 史官曰：人口、生活、威信，再加这十年的时代更替、危机与几件大事。
func _says(g: JCGame, hs: Array, items: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if hs.size() >= 2:
		var p0: int = int(hs[0].get("pop", 0))
		var p1: int = int(hs[hs.size() - 1].get("pop", 0))
		var dp: int = JCMath.ratio_ppm(p1 - p0, maxi(1, p0))
		if dp >= 10_000:
			parts.append(rt("jc.chr.ann.pop_up", {"v": JcFmt.pct(dp, 0)}))
		elif dp <= -10_000:
			parts.append(rt("jc.chr.ann.pop_down", {"v": JcFmt.pct(-dp, 0)}))
		else:
			parts.append(t("jc.chr.ann.pop_flat"))
	if not hs.is_empty():
		var liv: int = 0
		var leg: int = 0
		for hv: Dictionary in hs:
			liv += int(hv.get("living", 0))
			leg += int(hv.get("legitimacy", 0))
		@warning_ignore("integer_division")
		var liv_avg: int = liv / hs.size()
		@warning_ignore("integer_division")
		var leg_avg: int = leg / hs.size()
		parts.append(rt("jc.chr.ann.living", {"v": JcFmt.pct(liv_avg, 0)}))
		parts.append(rt("jc.chr.ann.legit", {"v": JcFmt.pct(leg_avg, 0)}))
	var named: PackedStringArray = PackedStringArray()
	for it: Dictionary in items:
		var key: String = String(it["key"])
		var a: Dictionary = it["args"]
		if key == "chron.era_enter":
			parts.append(rt("jc.chr.ann.era", {"era": JcFmt.era_name(int(a.get("era", 1)))}))
		elif key == "chron.crisis_up":
			parts.append(rt("jc.chr.ann.crisis", {"track": t("jc.crisis.%d" % int(a.get("track", 0)))}))
		elif String(it["kind"]) == "milestone" and named.size() < 2:
			named.append(JcFmt.chron(g, it))
	if not named.is_empty():
		parts.append(t("jc.list_sep").join(named))
	return rt("jc.chr.ann.says", {"text": t("jc.chr.ann.sep").join(parts)})


## 没有图时圆章里写的那个字：里程碑各有一个字（第一家钱庄写「钱」），科技、政令写名字的头一个字，
## 其余取这条记载的头一个字。
func _glyph_of(g: JCGame, it: Dictionary) -> String:
	var aid: String = String(it["art_id"])
	match String(it["art_type"]):
		"milestone":
			if JwText.has("jc.chr.glyph." + aid):
				return t("jc.chr.glyph." + aid)
		"tech":
			return g.name_of("tech", aid)
		"decree":
			return g.name_of("decree", aid)
	return JcFmt.chron(g, it)


func _art_of(it: Dictionary) -> String:
	if String(it["art_path"]) != "":
		return JcUi.res(String(it["art_path"]))
	var id: String = String(it["art_id"])
	match String(it["art_type"]):
		"milestone":
			return JcUi.MILESTONE_ART % id
		"tech":
			return JcUi.TECH_ART % id
		"decree":
			# 分档的政令按定下的那一档配图
			return JcUi.decree_art(id, int((it.get("args", {}) as Dictionary).get("level", -1)))
	return ""


func _big_card(g: JCGame, it: Dictionary) -> Control:
	var tone: String = String(it["tone"])
	var box: StyleBoxFlat = JwTheme.box4("bg.raised", tone, 2, 0, 0, 0, 10)
	box.set_corner_radius_all(8)
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", box)
	p.custom_minimum_size = Vector2(BIG_W, 0)
	var v: VBoxContainer = JwUi.vbox(6)
	p.add_child(v)
	var path: String = _art_of(it)
	if JcUi.has_art(path):
		v.add_child(JcUi.art(path, Vector2(BIG_W, BIG_H)))
	else:
		var ph: PanelContainer = JwUi.panel("bg.abyss", "", 0)
		ph.custom_minimum_size = Vector2(BIG_W, BIG_H)
		var cc: CenterContainer = CenterContainer.new()
		cc.add_child(JcUi.badge(JcUi.CHRON_ICON % _kind_of(it), 64.0, _glyph_of(g, it), tone))
		ph.add_child(cc)
		v.add_child(ph)
	var mc: MarginContainer = MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 12)
	mc.add_theme_constant_override("margin_right", 12)
	var iv: VBoxContainer = JwUi.vbox(2)
	mc.add_child(iv)
	iv.add_child(JwUi.label(rt("jc.chr.ann.date", {"year": str(int(it["year"])), "season": t("jc.u.season.%d" % int(it["season"]))}),
			"caption", "text.muted"))
	var tx: Label = JwUi.label(JcFmt.chron(g, it), "body_bold", tone if tone != "text.secondary" else "text.primary", true)
	tx.custom_minimum_size = Vector2(BIG_W - 24.0, 0)
	iv.add_child(tx)
	v.add_child(mc)
	return p


func _small_row(g: JCGame, it: Dictionary) -> Control:
	var h: HBoxContainer = JwUi.hbox(10)
	var path: String = _art_of(it)
	h.add_child(JcUi.badge(path if path != "" else JcUi.CHRON_ICON % _kind_of(it), 28.0, _glyph_of(g, it), "line.strong"))
	var d: Label = JwUi.label(rt("jc.chr.ann.date", {"year": str(int(it["year"])), "season": t("jc.u.season.%d" % int(it["season"]))}),
			"caption", "text.muted")
	d.custom_minimum_size = Vector2(110, 0)
	h.add_child(d)
	h.add_child(JwUi.label(JcFmt.chron(g, it), "body", String(it["tone"]), true))
	return h


## 纪事分类（配分类图标）：milestone 归到时代一类。
func _kind_of(it: Dictionary) -> String:
	var k: String = String(it["kind"])
	return "era" if k == "milestone" else k


# ── 逐季纪事 ─────────────────────────────────────────────────────────────
func _chron(g: JCGame) -> void:
	var fl: HFlowContainer = JcUi.flow(4, 4)
	for k: String in KINDS:
		var b2: Button = JwUi.button(t("jc.chr.kind." + k))
		b2.toggle_mode = true
		b2.set_pressed_no_signal(_kind == k)
		b2.pressed.connect(func() -> void:
			_kind = k
			refresh())
		fl.add_child(b2)
	content.add_child(fl)
	var box: VBoxContainer = JwUi.vbox(2)
	var last_year: int = -1
	var n: int = 0
	for e: Dictionary in views().chronicle(400):
		var kind: String = String(e.get("kind", ""))
		if kind == "steward" or kind == "advisor":
			continue
		if _kind != "all" and kind != _kind:
			continue
		var q: int = int(e["q"])
		@warning_ignore("integer_division")
		var y: int = g.st.start_year + q / 4
		if y != last_year:
			last_year = y
			box.add_child(JwUi.label(rt("jc.chr.year", {"year": str(y)}), "title_sub", "text.primary"))
		var h: HBoxContainer = JwUi.hbox(10)
		var d: Label = JwUi.label(t("jc.u.season.%d" % (q % 4)), "caption", "text.muted")
		d.custom_minimum_size = Vector2(28, 0)
		h.add_child(d)
		h.add_child(JcUi.badge(JcUi.CHRON_ICON % (kind if kind != "milestone" else "era"), 22.0, t("jc.chr.kind." + kind)
				if kind in KINDS else "", "line.hair"))
		var tok: String = "text.secondary"
		if kind == "era" or kind == "landmark" or kind == "milestone":
			tok = JcUi.GOOD
		elif kind == "crisis":
			tok = JcUi.BAD
		elif kind == "event":
			tok = JcUi.WARN
		h.add_child(JwUi.label(JcFmt.chron(g, e), "body", tok, true))
		box.add_child(h)
		n += 1
		if n >= 240:
			break
	if n == 0:
		box.add_child(JwUi.para(t("jc.chr.empty"), "text.muted"))
	content.add_child(box)


func _steward(g: JCGame) -> void:
	content.add_child(JwUi.para(t("jc.chr.steward_intro"), "text.muted"))
	var box: VBoxContainer = JwUi.vbox(4)
	var recs: Array = views().steward_log(200)
	if recs.is_empty():
		box.add_child(JwUi.para(t("jc.chr.steward_empty"), "text.muted"))
	for rec: Dictionary in recs:
		var h: HBoxContainer = JwUi.hbox(10)
		var d: Label = JwUi.label(JcFmt.date(int(rec["q"]), g.st.start_year), "caption", "text.muted")
		d.custom_minimum_size = Vector2(90, 0)
		h.add_child(d)
		h.add_child(JcUi.icon(String(JcUi.STEWARD_ART.get(String(rec["domain"]), "")), 24.0))
		h.add_child(JcUi.chip(t("jc.stw.domain." + String(rec["domain"])), JcUi.MUTED))
		var ok: bool = bool(rec.get("ok", false))
		var txt: String = JcFmt.r(String(rec["reason"]), JcFmt.slots(g, rec.get("slots", {})))
		if not ok:
			txt += rt("jc.chr.failed", {"why": JcFmt.reason(g, {"reason": String(rec.get("why", ""))})})
		h.add_child(JwUi.label(txt, "body", "text.secondary" if ok else JcUi.WARN, true))
		box.add_child(h)
	content.add_child(box)
