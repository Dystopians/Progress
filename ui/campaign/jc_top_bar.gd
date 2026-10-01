## v2 顶栏：年月、本国与世界的时代、国库（每季收支）、民心（合法性）、生活、三条危机、
## 托管 / 存档 / 帮助，快进与「结束本季」。
class_name JcTopBar
extends PanelContainer

var session: JcSession = null
var root_ui: Node = null
var _date: Label = null
var _era: Label = null
var _treasury: Label = null
var _balance: Label = null
var _legit: Label = null
var _living: Label = null
var _crisis: HBoxContainer = null
var _steward_btn: Button = null
var _end_btn: Button = null
var _ff: MenuButton = null
var _row: HBoxContainer = null
var _sep: VSeparator = null
var _compact: bool = false
var _props: int = 0


func setup(s: JcSession, r: Node) -> void:
	session = s
	root_ui = r
	name = "TopBar"
	add_theme_stylebox_override("panel", JwTheme.box4("bg.abyss", "", 0, 16, 8, 16, 8))
	custom_minimum_size = Vector2(0, 64)
	var h: HBoxContainer = JwUi.hbox(20)
	_row = h
	add_child(h)
	var dv: VBoxContainer = JwUi.vbox(0)
	dv.alignment = BoxContainer.ALIGNMENT_CENTER
	_date = JwUi.label("", "title_block", "text.primary")
	dv.add_child(_date)
	h.add_child(dv)
	# 本国与世界的时代那一行由外壳摆到页签行右端（界面放大后顶栏挤不下）
	_era = JwUi.label("", "body", "text.secondary")
	_sep = VSeparator.new()
	h.add_child(_sep)
	var tv: VBoxContainer = JwUi.vbox(0)
	tv.add_child(JwUi.label(JwText.t("jc.top.treasury"), "caption", "text.muted"))
	var tr: HBoxContainer = JwUi.hbox(8)
	_treasury = JwUi.label("", "num_bold", "text.primary")
	_balance = JwUi.label("", "caption", "text.muted")
	_balance.size_flags_vertical = Control.SIZE_SHRINK_END
	tr.add_child(_treasury)
	tr.add_child(_balance)
	tv.add_child(tr)
	h.add_child(tv)
	var lv: VBoxContainer = JwUi.vbox(0)
	lv.add_child(JwUi.label(JwText.t("jc.top.legitimacy"), "caption", "text.muted"))
	_legit = JwUi.label("", "num_bold", "text.primary")
	lv.add_child(_legit)
	lv.tooltip_text = JwText.t("jc.top.legitimacy_tip")
	lv.mouse_filter = Control.MOUSE_FILTER_STOP
	h.add_child(lv)
	var liv: VBoxContainer = JwUi.vbox(0)
	liv.add_child(JwUi.label(JwText.t("jc.top.living"), "caption", "text.muted"))
	_living = JwUi.label("", "num_bold", "text.primary")
	liv.add_child(_living)
	liv.tooltip_text = JwText.t("jc.top.living_tip")
	liv.mouse_filter = Control.MOUSE_FILTER_STOP
	h.add_child(liv)
	var cv: VBoxContainer = JwUi.vbox(2)
	cv.add_child(JwUi.label(JwText.t("jc.top.crisis"), "caption", "text.muted"))
	_crisis = JwUi.hbox(10)
	cv.add_child(_crisis)
	h.add_child(cv)
	h.add_child(JwUi.spacer())
	_steward_btn = JwUi.button(JwText.t("jc.top.steward"))
	_steward_btn.pressed.connect(func() -> void: root_ui.call("open_overlay", "steward", {}))
	h.add_child(_steward_btn)
	var sv: Button = JwUi.button(JwText.t("jc.top.saves"))
	sv.pressed.connect(func() -> void: root_ui.call("open_overlay", "saves", {}))
	h.add_child(sv)
	var hp: Button = JwUi.button(JwText.t("jc.top.help"))
	hp.pressed.connect(func() -> void: root_ui.call("open_overlay", "help", {}))
	h.add_child(hp)
	_ff = MenuButton.new()
	_ff.text = JwText.t("jc.top.ff")
	_ff.flat = false
	var pm: PopupMenu = _ff.get_popup()
	pm.add_item(JwText.t("jc.top.ff_year"), 4)
	pm.add_item(JwText.t("jc.top.ff_5y"), 20)
	pm.add_item(JwText.t("jc.top.ff_20y"), 80)
	pm.id_pressed.connect(func(n: int) -> void: session.fast_forward(n))
	h.add_child(_ff)
	_end_btn = JwUi.button(JwText.t("jc.top.end_turn"), "PrimaryButton")
	_end_btn.name = "EndTurn"
	_end_btn.custom_minimum_size = Vector2(150, 44)
	_end_btn.tooltip_text = JwText.t("jc.top.end_turn_tip")
	_end_btn.pressed.connect(func() -> void: session.end_turn())
	h.add_child(_end_btn)


func refresh() -> void:
	if not session.has_game():
		return
	var g: JCGame = session.game
	var s: Dictionary = g.status()
	_date.text = JcFmt.date(int(s["q"]), g.st.start_year)
	_era.text = JwText.render("jc.top.era", {"era": JcFmt.era_name(int(s["era"])), "world": JcFmt.era_name(int(s["world_era"]))})
	_treasury.text = JcFmt.money(int(s["treasury"]))
	var bal: int = int(s["balance"])
	_balance.text = JwText.render("jc.top.per_q", {"v": JcFmt.money_signed(bal)})
	_balance.add_theme_color_override("font_color", JwTheme.c(JcUi.GOOD if bal >= 0 else JcUi.BAD))
	var leg: int = int(s["legitimacy"])
	_legit.text = JcFmt.pct(leg, 0)
	_legit.add_theme_color_override("font_color", JwTheme.c(JcUi.GOOD if leg >= 450_000 else (JcUi.WARN if leg >= 300_000 else JcUi.BAD)))
	var liv: int = int(s["living"])
	_living.text = JcFmt.pct(liv, 0)
	_living.add_theme_color_override("font_color", JwTheme.c(JcUi.GOOD if liv >= 950_000 else (JcUi.WARN if liv >= 850_000 else JcUi.BAD)))
	JwUi.clear(_crisis)
	var cr: Array = s["crisis"]
	for tr: int in 3:
		var stg: int = int(cr[tr])
		var chip: PanelContainer = JcUi.chip(JwText.t("jc.crisis.short.%d" % tr) + " " + JwText.t("jc.stage.%d" % stg),
				JcUi.GOOD if stg == 0 else (JcUi.WARN if stg == 1 else JcUi.BAD))
		chip.tooltip_text = JwText.t("jc.crisis.tip.%d" % tr)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		_crisis.add_child(chip)
	_props = int(s["proposals"])
	_steward_text()
	_end_btn.disabled = bool(s["over"])


## 「本国：… 世界：…」那一行（外壳取走，放在页签行）。
func era_label() -> Label:
	return _era


## 窄窗口（逻辑宽度不到 1500，比如 1920 宽屏开 150%、2560 宽屏开 200%）：收紧间距、去掉竖线、待批只写个数。
func set_compact(on: bool) -> void:
	_compact = on
	_row.add_theme_constant_override("separation", 10 if on else 20)
	_sep.visible = not on
	_steward_text()


func _steward_text() -> void:
	var tail: String = ""
	if _props > 0:
		tail = " · " + (str(_props) if _compact else JwText.render("jc.top.proposals", {"n": str(_props)}))
	_steward_btn.text = JwText.t("jc.top.steward") + tail
