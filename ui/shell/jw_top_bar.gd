## 顶栏（docs/20 §5.1，56 lu）：国名与季度定位、国库现金、债务、三类图例入口（常驻）、
## 规则手册、存档入口与自动存档指示、结算状态。债务旁不放债务/GDP 单一比率（§07）。
class_name JwTopBar
extends PanelContainer

var session: JwSession = null
var root_ui: Node = null
var _country: Label = null
var _badges: HBoxContainer = null
var _cash_box: HBoxContainer = null
var _debt_box: HBoxContainer = null
var _save_ind: Label = null
var _settle: Label = null
var _settle_icon: JwIcon = null
var _legend: Button = null
var _rules: Button = null
var _saves: Button = null
var _h: HBoxContainer = null
var wband: int = JwScale.WBand.WIDE


func setup(s: JwSession, r: Node) -> void:
	session = s
	root_ui = r
	name = "TopBar"
	custom_minimum_size = Vector2(0, JwScale.TOPBAR_H)
	add_theme_stylebox_override("panel", JwTheme.box4("bg.abyss", "", 0, 16, 6, 12, 6))
	var h: HBoxContainer = JwUi.hbox(14)
	_h = h
	add_child(h)
	_country = JwUi.label("", "title_sub")
	_country.name = "CountryQuarter"
	h.add_child(_country)
	_badges = JwUi.hbox(6)
	h.add_child(_badges)
	h.add_child(JwUi.vspacer(0))
	h.add_child(JwUi.label(JwText.t("top.cash"), "body", "text.secondary"))
	_cash_box = JwUi.hbox(0)
	_cash_box.name = "CashReadout"
	h.add_child(_cash_box)
	h.add_child(JwUi.label(JwText.t("top.debt"), "body", "text.secondary"))
	_debt_box = JwUi.hbox(0)
	_debt_box.name = "DebtReadout"
	h.add_child(_debt_box)
	h.add_child(JwUi.spacer())
	var legend: Button = JwUi.button(JwText.t("top.legend"))
	_legend = legend
	legend.name = "ClassLegendButton"
	legend.set_meta("jw_id", "ClassLegendButton")
	legend.pressed.connect(func() -> void: _open("legend"))
	h.add_child(legend)
	var rules: Button = JwUi.button(JwText.t("top.rules"))
	_rules = rules
	rules.name = "RulesButton"
	rules.pressed.connect(func() -> void: _open("rules"))
	h.add_child(rules)
	var saves: Button = JwUi.button(JwText.t("top.saves"))
	_saves = saves
	saves.name = "SavesButton"
	saves.pressed.connect(func() -> void: _open("saves"))
	h.add_child(saves)
	_save_ind = JwUi.label("", "caption", "text.muted")
	_save_ind.name = "SaveIndicator"
	h.add_child(_save_ind)
	var st: HBoxContainer = JwUi.hbox(6)
	st.name = "SettleState"
	_settle_icon = JwIcon.make("ok", JwTheme.c("teal.core"), 14)
	st.add_child(_settle_icon)
	_settle = JwUi.label("", "body_bold", "text.primary")
	st.add_child(_settle)
	h.add_child(st)


## 宽度档（docs/20 §5.3）：W-mid 档收紧间距、用短按钮名；三类图例入口在任何档都常驻。
func set_width_band(wb: int) -> void:
	wband = wb
	var mid: bool = wb != JwScale.WBand.WIDE
	if _h != null:
		_h.add_theme_constant_override("separation", 8 if mid else 14)
	if _legend != null:
		_legend.text = JwText.t("top.legend.short") if mid else JwText.t("top.legend")
		_rules.text = JwText.t("top.rules.short") if mid else JwText.t("top.rules")
		_saves.text = JwText.t("top.saves.short") if mid else JwText.t("top.saves")
	if _save_ind != null:
		_save_ind.visible = not mid


func _open(o: String) -> void:
	if root_ui != null and root_ui.has_method("open_overlay"):
		root_ui.call("open_overlay", o, {})


func refresh() -> void:
	if session == null or session.game == null:
		_country.text = session.catalog.country_label() if session != null else ""
		JwUi.clear(_cash_box)
		JwUi.clear(_debt_box)
		_cash_box.add_child(JwUi.label(JwText.t("common.none"), "num_bold", "text.muted"))
		_debt_box.add_child(JwUi.label(JwText.t("common.none"), "num_bold", "text.muted"))
		_save_ind.text = ""
		_settle.text = JwText.t("top.settle.no_game")
		_settle_icon.set_kind("note", JwTheme.c("text.muted"))
		return
	var m: JwReadModel = session.model
	var q: int = m.q
	# 执政结束后不再有「本季」：季号停在最后一个已结算季（NN ∈ [1, 40]，§5.1）。
	var qd: int = maxi(q - 1, 0) if m.terminated else q
	_country.text = JwText.render("top.country_quarter", {"country": session.catalog.country_label(),
			"nn": JwFormat.q2(qd), "y": str(JwFormat.year_of(qd)), "m": str(JwFormat.quarter_in_year(qd))})
	JwUi.clear(_badges)
	if q % 4 == 3 and not m.terminated:
		_badges.add_child(_chip(JwText.t("top.badge.review")))
	if JwReadModel.ELECTION_QS.has(q) and not m.terminated:
		_badges.add_child(_chip(JwText.t("top.badge.election")))
	if session.read_only:
		_badges.add_child(_chip(JwText.t("top.badge.readonly")))
	if m.terminated:
		_badges.add_child(_chip(JwText.t("top.badge.ended")))
	JwUi.clear(_cash_box)
	var cash: JwNumberCell = JwNumberCell.make(JwFormat.u_num(m.gov_cash()), "U", JwInfo.Cls.ACTUAL, "num_bold",
			{"measure": JwText.t("measure.stock"), "period": JwText.t("period.q_end"),
			"price_base": JwText.t("price.nominal"), "ledger": "cash", "rule_key": "fiscal_identity",
			"citation": JwFormat.citation(JwText.t("ledger.alias.cash"), maxi(q - 1, -1), 1),
			"raw": JwFormat.uu_raw(m.gov_cash())})
	cash.ledger_requested.connect(_on_ledger)
	cash.rule_requested.connect(_on_rule)
	_cash_box.add_child(cash)
	JwUi.clear(_debt_box)
	var debt: JwNumberCell = JwNumberCell.make(JwFormat.u_num(m.debt_total()), "U", JwInfo.Cls.ACTUAL, "num_bold",
			{"measure": JwText.t("measure.stock"), "period": JwText.t("period.q_end"),
			"price_base": JwText.t("price.nominal"), "ledger": "debt", "rule_key": "bond_rules",
			"raw": JwFormat.uu_raw(m.debt_total())})
	debt.ledger_requested.connect(_on_ledger)
	debt.rule_requested.connect(_on_rule)
	_debt_box.add_child(debt)
	var ac: int = session.game.last_autosave_code
	if session.history.size() <= 1:
		_save_ind.text = JwText.t("top.autosave.none")
	elif ac == 0:
		_save_ind.text = JwText.render("top.autosave.ok", {"q": JwFormat.quarter(maxi(q - 1, 0))})
	else:
		_save_ind.text = JwText.render("top.autosave.fail", {"code": str(ac)})
	if session.settling:
		_settle.text = JwText.t("top.settle.running")
		_settle_icon.set_kind("settling", JwTheme.c("warm.text"))
	elif q >= 1:
		_settle.text = JwText.render("top.settle.done", {"q": JwFormat.quarter(q - 1)})
		_settle_icon.set_kind("ok", JwTheme.c("teal.core"))
	else:
		_settle.text = JwText.t("top.settle.none")
		_settle_icon.set_kind("note", JwTheme.c("text.muted"))


func _chip(t: String) -> PanelContainer:
	var p: PanelContainer = JwUi.panel_style(JwTheme.box4("bg.raised", "line.strong", 1, 8, 2, 8, 2))
	p.add_child(JwUi.label(t, "body_bold", "text.primary"))
	return p


func _on_ledger(l: String, r: int) -> void:
	if root_ui != null and root_ui.has_method("open_ledger"):
		root_ui.call("open_ledger", l, r)


func _on_rule(k: String) -> void:
	if root_ui != null and root_ui.has_method("open_rule"):
		root_ui.call("open_rule", k)
