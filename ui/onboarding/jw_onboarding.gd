## 新手前四季引导（docs/22；docs/20 §11.2）：指路，不走轨道。
##
## 只做三件事：指出一个已存在的区块（JwAnchorTip）、术语首见（首版由图例与规则卡承担）、静默复盘（判据求值）。
## 不产生命令（OB-F1）、不改任何控件属性（OB-F2）、不预填草案（OB-F4）；随时可跳过，跳过入界面存档。
## 判据是析取式，每季 ≥3 条满足路径，其中 ≥1 条不涉及提交命令（OB-F5）；结果不在界面上显示（EVAL-2）。
class_name JwOnboarding
extends Node

## 四步定义（数据）。anchor/fallback 是页面或覆盖层里带 jw_id 的节点名。
const STEPS: Array = [
	{"id": "onb.q1", "q": 0, "page": "overview", "anchor": "Mechanism", "fallback": "RegionStrip",
		"lead": "onb.lead.q1", "lead_fb": "onb.lead.q1_fb"},
	{"id": "onb.q2", "q": 1, "page": "report", "anchor": "Row0", "fallback": "HeadroomWithDraft",
		"lead": "onb.lead.q2", "lead_fb": "onb.lead.q2_fb"},
	{"id": "onb.q3", "q": 2, "page": "policy", "anchor": "GroupBreakdown", "fallback": "MatrixHeader",
		"fallback_page": "society", "lead": "onb.lead.q3", "lead_fb": "onb.lead.q3_fb"},
	{"id": "onb.q4", "q": 3, "overlay": "annual", "anchor": "AnnualReview", "fallback": "",
		"lead": "onb.lead.q4", "lead_fb": "onb.lead.q4"},
]

var session: JwSession = null
var root_ui: Node = null
var tip: JwAnchorTip = null
var _current_overlay: JwOverlay = null


func setup(s: JwSession, r: Node) -> void:
	session = s
	root_ui = r
	session.settlement_finished.connect(_on_settled)


func _state() -> Dictionary:
	if session.onboarding.is_empty():
		session.onboarding = {"enabled": true, "skipped_at_q": -1, "steps": {}}
	return session.onboarding


func enabled() -> bool:
	var st: Dictionary = _state()
	return bool(st.get("enabled", true)) and int(st.get("skipped_at_q", -1)) < 0 and session.game != null \
			and session.model.q <= 4


func _step_for_q(q: int) -> Dictionary:
	for s: Variant in STEPS:
		if int((s as Dictionary)["q"]) == q:
			return s
	return {}


func _dismissed(step_id: String) -> bool:
	var steps: Dictionary = _state().get("steps", {})
	var rec: Dictionary = steps.get(step_id, {})
	return bool(rec.get("dismissed", false))


func _mark(step_id: String, key: String, value: Variant) -> void:
	var st: Dictionary = _state()
	var steps: Dictionary = st.get("steps", {})
	var rec: Dictionary = steps.get(step_id, {})
	rec[key] = value
	steps[step_id] = rec
	st["steps"] = steps


func on_page_shown(_id: String) -> void:
	call_deferred("_try_show")


func on_refresh() -> void:
	call_deferred("_try_show")


func on_overlay_opened(id: String, o: JwOverlay) -> void:
	if id == "annual":
		_current_overlay = o
	call_deferred("_try_show")


func on_overlay_closed(id: String) -> void:
	if id == "annual" and session.game != null:
		_evaluate_q4()
		_current_overlay = null
	_clear_tip()
	call_deferred("_try_show")


func _clear_tip() -> void:
	if tip != null and is_instance_valid(tip):
		if tip.get_parent() != null:
			tip.get_parent().remove_child(tip)
		tip.queue_free()
	tip = null


func _try_show() -> void:
	_clear_tip()
	if root_ui == null or not enabled():
		return
	var q: int = session.model.q
	var step: Dictionary = _step_for_q(q if q < 3 else 3)
	if q == 4:
		step = _step_for_q(3)
	if step.is_empty() or _dismissed(String(step["id"])):
		return
	var anchor: Control = null
	var lead_key: String = String(step["lead"])
	if step.has("overlay"):
		if _current_overlay == null or not is_instance_valid(_current_overlay):
			return
		anchor = JwPage._find(_current_overlay, String(step["anchor"]))
	else:
		var cur: String = String(root_ui.get("current_page"))
		if root_ui.call("top_overlay") != null:
			return
		if cur == String(step["page"]):
			var pg: JwPage = root_ui.call("page", cur)
			anchor = pg.find_tagged(String(step["anchor"])) if pg != null else null
		if (anchor == null or not anchor.is_visible_in_tree()) and String(step.get("fallback", "")) != "":
			var fb_page: String = String(step.get("fallback_page", cur))
			if fb_page == cur:
				var pg2: JwPage = root_ui.call("page", cur)
				anchor = pg2.find_tagged(String(step["fallback"])) if pg2 != null else null
				if anchor == null:
					anchor = JwPage._find(root_ui, String(step["fallback"]))
				lead_key = String(step["lead_fb"])
	if anchor == null or not anchor.is_visible_in_tree():
		return
	tip = JwAnchorTip.make(JwText.t(lead_key), String(step["id"]))
	tip.anchor = anchor
	if JwText.has(lead_key + ".off"):
		tip.lead_off = JwText.t(lead_key + ".off")
	tip.prefer_above = step.has("overlay")
	# 可放置区域 = 顶栏与页签以下的整块（含底部固定区；锚点可能在底部固定区里）。
	var body_node: Variant = root_ui.get("body")
	if body_node is Control and root_ui is Control:
		var br: Rect2 = (body_node as Control).get_global_rect()
		var rr: Rect2 = (root_ui as Control).get_global_rect()
		tip.bounds = rr if step.has("overlay") else Rect2(br.position, Vector2(br.size.x, rr.end.y - br.position.y))
		tip.body_rect = rr if step.has("overlay") else br
	tip.dismissed.connect(_on_dismiss)
	root_ui.add_child(tip)
	tip.call_deferred("place")
	if not _state().get("steps", {}).has(String(step["id"])) or not ((_state()["steps"] as Dictionary)[String(step["id"])] as Dictionary).has("shown_q"):
		_mark(String(step["id"]), "shown_q", q)
	session.log_event("ev.onb_step", {"step_id": String(step["id"]), "state": "shown"})


func _on_dismiss(forever: bool) -> void:
	if tip == null:
		return
	var id: String = tip.step_id
	_mark(id, "dismissed", true)
	if forever:
		_state()["skipped_at_q"] = session.model.q
		session.log_event("ev.onb_step", {"step_id": id, "state": "skipped"})
	else:
		session.log_event("ev.onb_step", {"step_id": id, "state": "dismissed"})
	_clear_tip()


## 推进被接受后立即求值一次（EVAL-1）；纯函数于 (本季命令回执, 本季事件)。
func _on_settled(receipt: Dictionary) -> void:
	_clear_tip()
	var q0: int = int(receipt.get("q", -1))
	if q0 < 0 or q0 > 2:
		return
	var res: Dictionary = evaluate(q0, receipt.get("commands", []), session.events_of_quarter(q0), session)
	var id: String = String(_step_for_q(q0).get("id", ""))
	_mark(id, "met", bool(res["met"]))
	_mark(id, "met_by", String(res["met_by"]))
	_mark(id, "na", bool(res["na"]))
	session.log_event("ev.onb_step", {"step_id": id, "state": "na" if bool(res["na"]) else ("met" if bool(res["met"]) else "not_met")})


func _evaluate_q4() -> void:
	var evs: Array[Dictionary] = session.events_of_quarter(session.model.q)
	var res: Dictionary = evaluate(3, [], evs, session)
	_mark("onb.q4", "met", bool(res["met"]))
	_mark("onb.q4", "met_by", String(res["met_by"]))
	_mark("onb.q4", "na", bool(res["na"]))


## 判据（docs/22 §2）：返回 {met, met_by, na}。
static func evaluate(q0: int, cmds: Array, evs: Array, s: JwSession) -> Dictionary:
	var out: Dictionary = {"met": false, "met_by": "", "na": false}
	match q0:
		0:
			var launched: bool = false
			var rejected: bool = false
			for c: Variant in cmds:
				var cd: Dictionary = c
				var k: int = int(cd.get("kind", 0))
				if k == JwSession.K_LAUNCH or k == JwSession.K_ENACT:
					if int(cd.get("accepted", 0)) == 1:
						launched = true
					else:
						rejected = true
			if launched:
				return {"met": true, "met_by": "P1.A", "na": false}
			if rejected and _has(evs, "ev.reason_exit_opened", {}):
				return {"met": true, "met_by": "P1.B", "na": false}
			if _has_prefix(evs, "ev.section_expanded", "node", "DiagCard") and _has(evs, "ev.page_shown", {"page_id": "page.region"}) \
					and _has_any(evs, "ev.ledger_opened", "ledger", ["constraint", "project", "cash", "debt"]):
				return {"met": true, "met_by": "P1.C", "na": false}
		1:
			var pre: bool = s.model.sc("state.gov.committed_memo_uu") > 0
			for row: Dictionary in s.model.project_rows():
				if int(row["paid"]) > 0:
					pre = true
			if not pre:
				return {"met": false, "met_by": "", "na": true}
			if _has(evs, "ev.rule_card_opened", {"rule_id": "commission"}):
				return {"met": true, "met_by": "P2.A", "na": false}
			if _has_prefix(evs, "ev.section_expanded", "node", "Report/LagBlock/Row"):
				return {"met": true, "met_by": "P2.B", "na": false}
			if _has(evs, "ev.cost_card_rendered", {}):
				return {"met": true, "met_by": "P2.C", "na": false}
			if _has_any(evs, "ev.ledger_opened", "ledger", ["project", "commit"]):
				return {"met": true, "met_by": "P2.D", "na": false}
		2:
			if _has_prefix(evs, "ev.section_expanded", "node", "PolicyEditor/ImpactPreview/GroupBreakdown"):
				return {"met": true, "met_by": "P3.A", "na": false}
			if _has(evs, "ev.impact_source_changed", {"source": "current_draft"}):
				return {"met": true, "met_by": "P3.B", "na": false}
			if _has_any(evs, "ev.matrix_field_changed", "field", ["burden", "access", "edu"]) and _has(evs, "ev.group_focused", {}):
				return {"met": true, "met_by": "P3.C", "na": false}
		3:
			if s.model.terminated and s.model.q < 4:
				return {"met": false, "met_by": "", "na": true}
			var opened: bool = _has(evs, "ev.overlay_opened", {"overlay": "overlay.annual_review"})
			if opened and _has_prefix(evs, "ev.section_expanded", "node", "AnnualReview/Right/NextYearOpex"):
				return {"met": true, "met_by": "P4.AB", "na": false}
			if opened and _has(evs, "ev.rule_card_opened", {}):
				return {"met": true, "met_by": "P4.AC", "na": false}
			if opened and _has_any(evs, "ev.ledger_opened", "ledger", ["opex", "service", "tax"]):
				return {"met": true, "met_by": "P4.AD", "na": false}
	return out


static func _has(evs: Array, name: String, args: Dictionary) -> bool:
	for e: Variant in evs:
		var ed: Dictionary = e
		if String(ed.get("name", "")) != name:
			continue
		var a: Dictionary = ed.get("args", {})
		var ok: bool = true
		for k: Variant in args.keys():
			if str(a.get(k, "")) != str(args[k]):
				ok = false
		if ok:
			return true
	return false


static func _has_prefix(evs: Array, name: String, key: String, prefix: String) -> bool:
	for e: Variant in evs:
		var ed: Dictionary = e
		if String(ed.get("name", "")) == name and String((ed.get("args", {}) as Dictionary).get(key, "")).begins_with(prefix):
			return true
	return false


static func _has_any(evs: Array, name: String, key: String, values: Array) -> bool:
	for e: Variant in evs:
		var ed: Dictionary = e
		if String(ed.get("name", "")) == name and values.has(String((ed.get("args", {}) as Dictionary).get(key, ""))):
			return true
	return false
