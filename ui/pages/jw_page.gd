## 主页面基类（docs/20 §7.0）：五个主页面共用的接口。
##
## refresh() 从读模型重建本页内容；页面只格式化、不运算（运算在 JwReadModel）。
## get_required_above_fold(band) 声明本页在 L/M/S 三档的首屏必备节点（附录 B），测试据此断言。
class_name JwPage
extends MarginContainer

var session: JwSession = null
var root_ui: Node = null
var page_id: String = ""
var _built_q: int = -99
var wband: int = JwScale.WBand.WIDE
var hband: int = JwScale.HBand.TALL


func setup(s: JwSession, r: Node, id: String) -> void:
	session = s
	root_ui = r
	page_id = id
	name = id.capitalize().replace(" ", "")
	add_theme_constant_override("margin_left", 16)
	add_theme_constant_override("margin_right", 16)
	add_theme_constant_override("margin_top", 12)
	add_theme_constant_override("margin_bottom", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


## 由外壳在状态变化或显示时调用。
func refresh() -> void:
	pass


func set_bands(w: int, h: int) -> void:
	var changed: bool = w != wband or h != hband
	wband = w
	hband = h
	if changed and visible:
		refresh()


func get_required_above_fold(_band: int) -> Array[StringName]:
	return []


## 找到本页里带 jw_id 的节点（测试与引导锚点用）。
func find_tagged(id: String) -> Control:
	return _find(self, id)


static func _find(n: Node, id: String) -> Control:
	if n is Control and String((n as Control).get_meta("jw_id", "")) == id:
		return n as Control
	for ch: Node in n.get_children():
		var f: Control = _find(ch, id)
		if f != null:
			return f
	return null


## 便捷：数字格子 + 统一的台账与规则入口。
func num(value_text: String, unit_text: String, cls: int, role: String, meta: Dictionary,
		paper: bool = false) -> JwNumberCell:
	var n: JwNumberCell = JwNumberCell.make(value_text, unit_text, cls, role, meta, paper)
	n.ledger_requested.connect(_on_ledger)
	n.rule_requested.connect(_on_rule)
	return n


func _on_ledger(ledger: String, row: int) -> void:
	if root_ui != null and root_ui.has_method("open_ledger"):
		root_ui.call("open_ledger", ledger, row)


func _on_rule(rule_key: String) -> void:
	if root_ui != null and root_ui.has_method("open_rule"):
		root_ui.call("open_rule", rule_key)


## 「本页术语」条（docs/20 §10.4 术语首见）：每个术语一枚可点击的签，点开是定义卡；
## 本局尚未打开过的术语旁带一次性「新」角标。换行排布，窄屏不撑破页面。
func term_strip(paper: bool = false) -> HFlowContainer:
	var h: HFlowContainer = HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 10)
	h.add_theme_constant_override("v_separation", 4)
	JwUi.tag(h, "TermStrip")
	h.add_child(JwUi.label(JwText.t("gloss.strip"), "caption", "text.ink2" if paper else "text.muted"))
	for id: String in JwGlossary.page_terms(page_id):
		var b: Button = JwUi.link(JwGlossary.term(id))
		JwUi.tag(b, "Term_" + id)
		var tid: String = id
		b.pressed.connect(func() -> void:
			open_term(tid))
		h.add_child(b)
		if session != null and not session.term_seen(id):
			var nb: Label = JwUi.label(JwText.t("gloss.new"), "caption", "ochre.core")
			JwUi.tag(nb, "TermNew_" + id)
			h.add_child(nb)
	return h


func open_term(id: String) -> void:
	if session != null:
		session.mark_term_seen(id)
	open_overlay("term", {"term": id})


func open_overlay(overlay: String, ctx: Dictionary = {}) -> void:
	if root_ui != null and root_ui.has_method("open_overlay"):
		root_ui.call("open_overlay", overlay, ctx)


func goto_page(page: String, ctx: Dictionary = {}) -> void:
	if root_ui != null and root_ui.has_method("show_page"):
		root_ui.call("show_page", page, ctx)


## 页面级 L2 展开记录（引导判据用 ev.section_expanded）。
func note_expand(node_id: String, target: String = "") -> void:
	if session != null:
		session.log_event("ev.section_expanded", {"node": node_id, "target": target})
