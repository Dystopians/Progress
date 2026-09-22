## 界面冒烟测试（G4）：用真实 JWGame.new_game 开局、推进 1–2 季，逐页、逐覆盖层实例化，
## 断言关键数字与 StateView 一致、阻断原因文本非空且带具体数字、三类信息的视觉编码不混用、
## 界面与试算不改动真实状态、文案 key 完整、界面代码不含中文字面量、镜像常量与 SimCore 一致。
##
## 测试运行在 SceneTree._init 中（无帧循环），因此：会话用同步试算（set_sync_mode）；
## 页面与覆盖层不进场景树，直接 setup + refresh/build 后检查节点。
extends JWTest

const SEED: int = 20260921
const PAGE_IDS: PackedStringArray = ["overview", "region", "policy", "industry", "society", "report"]
const OVERLAY_IDS: PackedStringArray = ["newgame", "budget", "confirm", "settlement", "annual", "archive", "saves",
		"ledger", "rule", "legend", "rules", "term"]

## 按推进季数缓存的会话（每个测试方法是新实例，静态变量跨实例共享）。
static var _sessions: Dictionary = {}
static var _launch_info: Dictionary = {}


# ── 夹具 ─────────────────────────────────────────────────────────────────

## q0：新开局；q1 / q2：第 1 季起草一个可立项的项目并推进。
static func _session(n_adv: int) -> JwSession:
	if _sessions.has(n_adv):
		return _sessions[n_adv]
	var s: JwSession = JwSession.new()
	s.set_sync_mode(true)
	var r: Dictionary = s.start_new(SEED, -1)
	if not bool(r.get("ok", false)):
		return null
	if n_adv > 0:
		var launched: bool = false
		for p: int in JwReadModel.POLICY_N:
			if launched or not s.catalog.is_project(p):
				continue
			for reg: int in JwReadModel.R:
				var el: Dictionary = s.model.eligibility(p, true, reg)
				if int(el.get("code", -1)) == 0:
					s.add_draft(s.draft_launch(p, reg, JwReadModel.PPM, 0))
					_launch_info = {"p": p, "region": reg}
					launched = true
					break
		for i: int in n_adv:
			s.advance()
	_sessions[n_adv] = s
	return s


static func _page_classes() -> Array:
	return [JwOverviewPage, JwRegionPage, JwPolicyPage, JwIndustryPage, JwSocietyPage, JwReportPage]


static func _walk(n: Node, out: Array[Node]) -> void:
	out.append(n)
	for ch: Node in n.get_children():
		_walk(ch, out)


static func _nodes(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	_walk(n, out)
	return out


static func _find(n: Node, id: String) -> Control:
	return JwPage._find(n, id)


static func _page(s: JwSession, i: int) -> JwPage:
	var pg: JwPage = (_page_classes()[i] as GDScript).new() as JwPage
	pg.setup(s, null, PAGE_IDS[i])
	pg.refresh()
	return pg


static func _overlay(s: JwSession, id: String, ctx: Dictionary) -> JwOverlay:
	var o: JwOverlay = null
	match id:
		"newgame":
			o = JwNewGame.new()
		"budget":
			o = JwBudgetReview.new()
		"confirm":
			o = JwConfirmAdvance.new()
		"settlement":
			o = JwSettlementReplay.new()
		"annual":
			o = JwAnnualReview.new()
		"archive":
			o = JwFinalArchive.new()
		"saves":
			o = JwSaveManager.new()
		"ledger":
			o = JwLedgerDrawer.new()
		"rule":
			o = JwRuleCard.new()
		"legend":
			o = JwClassLegend.new()
		"rules":
			o = JwRulesBook.new()
		"term":
			o = JwTermCard.new()
	o.setup(s, null, id, ctx)
	return o


## 真实模拟状态的指纹（测试可越层读取；界面代码不可）。
static func _fingerprint(s: JwSession) -> String:
	var st: Object = s.game.get("_st")
	var parts: PackedStringArray = PackedStringArray()
	if st != null and st.has_method("state_hash"):
		parts.append(str(st.call("state_hash")))
	var v: JWGame.StateView = s.game.view()
	parts.append(str(v.q()))
	parts.append(str(v.ledger_row_count()))
	for id: String in JwReadModel.SCALAR_IDS:
		var c: int = v.code_of(id)
		if c >= 0:
			parts.append(str(v.scalar(c, 0)))
	for id2: String in JwReadModel.ARRAY_IDS:
		var c2: int = v.code_of(id2)
		if c2 >= 0:
			parts.append(str(str(v.array_copy(c2)).hash()))
	var cl: Dictionary = s.game.command_log_copy()
	parts.append(str(int(cl.get("count", 0))))
	return ",".join(parts)


static func _has_digit(t: String) -> bool:
	for i: int in t.length():
		var c: int = t.unicode_at(i)
		if c >= 48 and c <= 57:
			return true
	return false


static func _texts_with_class(root: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n: Node in _nodes(root):
		if not n.has_meta("info_class"):
			continue
		var c: int = int(n.get_meta("info_class"))
		var t: String = ""
		if n is JwNumberCell:
			t = (n as JwNumberCell).value_text
		elif n.has_meta("line_text"):
			t = String(n.get_meta("line_text"))
		elif n.has_meta("cell_text"):
			t = String(n.get_meta("cell_text"))
		else:
			continue
		if t != "":
			out.append({"cls": c, "text": t, "node": String(n.name)})
	return out


# ── 基础：开局与读模型 ──────────────────────────────────────────────────

func test_new_game_and_read_model_match_state_view() -> void:
	var s: JwSession = _session(0)
	check(s != null and s.game != null, "real JWGame.new_game must succeed")
	if s == null:
		return
	var v: JWGame.StateView = s.game.view()
	eq_int(s.model.q, v.q(), "model.q equals StateView.q")
	eq_int(s.model.q, 0, "fresh game starts at q0")
	var bal: PackedInt64Array = v.array_copy(v.code_of("account.balance"))
	eq_int(s.model.gov_cash(), bal[0], "gov cash equals account.balance[gov,cash]")
	var n_b: int = v.scalar(v.code_of("state.bond.count"), 0)
	var outst: PackedInt64Array = v.array_copy(v.code_of("state.bond.principal_outstanding_uu"))
	var t: int = 0
	for b: int in n_b:
		t += outst[b]
	eq_int(s.model.debt_total(), t, "debt equals sum of outstanding bond principal")
	check(not s.dry.is_empty(), "dry-run bundle computed at q0 (sync mode)")


func test_advance_two_quarters_updates_model() -> void:
	var s: JwSession = _session(2)
	check(s != null, "session q2")
	if s == null:
		return
	eq_int(s.model.q, 2, "two advances reach q2")
	eq_int(s.model.q, s.game.view().q(), "model follows StateView after advance")
	ge_int(s.history.size(), 3, "history holds open + 2 settled snapshots")
	check(not _launch_info.is_empty(), "an eligible project was launched in q0")


# ── 关键数字与 StateView 一致 ────────────────────────────────────────────

func test_top_bar_numbers_match_state_view() -> void:
	for n_adv: int in [0, 1]:
		var s: JwSession = _session(n_adv)
		var tb: JwTopBar = JwTopBar.new()
		tb.setup(s, null)
		tb.refresh()
		var v: JWGame.StateView = s.game.view()
		var cash_uu: int = v.array_copy(v.code_of("account.balance"))[0]
		var cells: Array[JwNumberCell] = []
		for n: Node in _nodes(tb):
			if n is JwNumberCell:
				cells.append(n as JwNumberCell)
		eq_int(cells.size(), 2, "top bar has cash and debt cells")
		if cells.size() == 2:
			eq_str(cells[0].value_text, JwFormat.u_num(cash_uu), "top bar cash equals StateView (q%d)" % n_adv)
			eq_str(cells[1].value_text, JwFormat.u_num(s.model.debt_total()), "top bar debt equals bond sum (q%d)" % n_adv)
		tb.free()


func test_overview_key_numbers_match_state_view() -> void:
	var s: JwSession = _session(1)
	var pg: JwPage = _page(s, 0)
	var v: JWGame.StateView = s.game.view()
	var cash: JwNumberCell = _find(pg, "CashEnd") as JwNumberCell
	check(cash != null, "overview has CashEnd cell")
	if cash != null:
		eq_str(cash.value_text, JwFormat.u_num(v.array_copy(v.code_of("account.balance"))[0]), "overview cash equals StateView")
		eq_int(cash.cls, JwInfo.Cls.ACTUAL, "settled cash is ACTUAL")
	var un: JwNumberCell = _find(pg, "Unemployment") as JwNumberCell
	check(un != null, "overview has Unemployment cell")
	if un != null:
		eq_str(un.value_text, JwFormat.pct_num(int(s.model.unemployment()["rate_ppm"])), "unemployment equals read model")
	pg.free()


func test_region_and_society_numbers() -> void:
	var s: JwSession = _session(1)
	var rg: JwPage = _page(s, 1)
	var ladder: Control = _find(rg, "ConstraintLadder")
	check(ladder != null, "region page has constraint ladder")
	var texts: Array[Dictionary] = _texts_with_class(rg)
	var found_actual: bool = false
	for t: Dictionary in texts:
		if String(t["text"]).begins_with(JwText.t("cls.prefix.derived")) and String(t["text"]).contains("min") == false:
			found_actual = true
	check(found_actual, "region ladder renders derived lines")
	rg.free()
	var so: JwPage = _page(s, 4)
	var mx: Control = _find(so, "GroupMatrix")
	check(mx != null, "society page has group matrix")
	if mx != null:
		eq_int(int(mx.get_meta("cell_count", 0)), 36, "group matrix renders 36 cells (4 regions x 3 ages x 3 skills)")
	for id: String in ["MoodLiving", "MoodExpectation", "MoodTrust", "DistributionBar", "PrecisionNote"]:
		check(_find(so, id) != null, "society page has " + id)
	for n: Node in _nodes(so):
		if n is Label:
			var lt: String = (n as Label).text
			check_false(lt.contains("基尼") or lt.to_lower().contains("gini"), "society page outputs no Gini score")
	so.free()


# ── 阻断原因：非空且带具体数字 ────────────────────────────────────────────

func test_policy_block_reasons_are_specific() -> void:
	var s: JwSession = _session(0)
	var pg: JwPage = _page(s, 2)
	var n_reason: int = 0
	for n: Node in _nodes(pg):
		if n is Label and n.has_meta("reason_text"):
			n_reason += 1
			var rt: String = String(n.get_meta("reason_text"))
			check(rt.strip_edges() != "", "block reason text is non-empty")
			check(_has_digit(rt), "block reason carries a concrete number: " + rt.substr(0, 60))
	ge_int(n_reason, 1, "at least one policy is blocked at q0 (review window / authority)")
	for p: int in JwReadModel.POLICY_N:
		var r: Dictionary = JwReasons.for_catalog(p, s.model, s.catalog)
		if r.is_empty():
			continue
		var lines: PackedStringArray = JwReasons.render_lines(r)
		ge_int(lines.size(), 2, "reason renders title + quantitative line")
		check(_has_digit(String(r.get("line2", ""))), "reason line 2 quantifies the gap (policy %d)" % p)
		check(String(r.get("line2", "")).contains(JwText.t("fmt.quarter").split("{")[0].strip_edges()) or _has_digit(String(r["line2"])),
				"reason line 2 names a quarter or number")
	pg.free()


func test_reject_codes_render_reason_cards() -> void:
	var s: JwSession = _session(0)
	for rc: int in range(JwReadModel.RJ_RUN_TERMINATED, JwReadModel.RJ_COMMAND_ORDER + 1):
		var r: Dictionary = JwReasons.from_code(rc, {"kind": JwSession.K_ENACT, "p": 0, "draft": -1, "subject": "cmd",
				"subject_label": "P01"}, s.model, s.catalog)
		check(not r.is_empty(), "reject code %d maps to a reason card" % rc)
		if r.is_empty():
			continue
		var txt: String = JwReasons.render_text(r)
		check(txt.strip_edges() != "", "reason card text for %d is non-empty" % rc)
		check(JwText.has("reason.cat." + String(r.get("code", ""))), "reason %d has a category name" % rc)


# ── 三类信息：视觉编码不混用 ──────────────────────────────────────────────

func _check_classes(root: Node, where: String) -> int:
	var n_checked: int = 0
	var pa: String = JwText.t("cls.prefix.actual")
	var pd: String = JwText.t("cls.prefix.derived")
	var pp: String = JwText.t("cls.prefix.projected")
	for t: Dictionary in _texts_with_class(root):
		var c: int = int(t["cls"])
		var tx: String = String(t["text"])
		n_checked += 1
		if c == JwInfo.Cls.PROJECTED:
			check(tx.contains(JwFormat.RANGE_OPEN) or tx == JwText.t("common.recalc"),
					"%s: PROJECTED value must be an interval: %s" % [where, tx.substr(0, 50)])
			check_false(tx.begins_with(pa) or tx.begins_with(pd), "%s: PROJECTED line with wrong prefix" % where)
		elif c == JwInfo.Cls.ACTUAL or c == JwInfo.Cls.DERIVED:
			check_false(tx.contains(JwFormat.RANGE_OPEN), "%s: %s value must not be an interval: %s" % [where,
					"ACTUAL" if c == JwInfo.Cls.ACTUAL else "DERIVED", tx.substr(0, 50)])
			check_false(tx.begins_with(pp), "%s: non-projected line uses the projected prefix" % where)
			if c == JwInfo.Cls.ACTUAL:
				check_false(tx.begins_with(pd), "%s: ACTUAL line uses the derived prefix: %s" % [where, tx.substr(0, 40)])
			else:
				check_false(tx.begins_with(pa), "%s: DERIVED line uses the actual prefix: %s" % [where, tx.substr(0, 40)])
	return n_checked


func test_three_info_classes_not_mixed_on_pages() -> void:
	for n_adv: int in [0, 2]:
		var s: JwSession = _session(n_adv)
		var total: int = 0
		for i: int in _page_classes().size():
			var pg: JwPage = _page(s, i)
			total += _check_classes(pg, "q%d/%s" % [n_adv, PAGE_IDS[i]])
			pg.free()
		ge_int(total, 20, "class-coded values were found and checked (q%d)" % n_adv)


func test_three_info_classes_not_mixed_in_overlays() -> void:
	var s: JwSession = _session(1)
	for id: String in ["budget", "confirm", "annual", "archive"]:
		var o: JwOverlay = _overlay(s, id, {})
		_check_classes(o, "overlay/" + id)
		o.free()
	check(true, "overlays checked")


func test_class_channels_are_distinct() -> void:
	var badges: Dictionary = {}
	var prefixes: Dictionary = {}
	var icons: Dictionary = {}
	for c: int in [JwInfo.Cls.ACTUAL, JwInfo.Cls.DERIVED, JwInfo.Cls.PROJECTED]:
		badges[JwInfo.badge(c)] = true
		prefixes[JwInfo.prefix(c)] = true
		icons[JwInfo.icon_kind(c)] = true
	eq_int(badges.size(), 3, "three distinct badge characters")
	eq_int(prefixes.size(), 3, "three distinct word prefixes")
	eq_int(icons.size(), 3, "three distinct icon kinds")
	check(JwFormat.range_u(1_000_000_000, 2_000_000_000).begins_with(JwFormat.RANGE_OPEN), "only intervals use 〔〕")
	check_false(JwFormat.u(1_000_000_000).contains(JwFormat.RANGE_OPEN), "point values never use 〔〕")


# ── 界面不改状态；试算不污染真实状态 ─────────────────────────────────────

func test_ui_and_dry_run_do_not_mutate_state() -> void:
	var s: JwSession = _session(1)
	var before: String = _fingerprint(s)
	for i: int in _page_classes().size():
		var pg: JwPage = _page(s, i)
		pg.free()
	for id: String in OVERLAY_IDS:
		var ctx: Dictionary = {}
		if id == "ledger":
			ctx = {"ledger": "transaction"}
		elif id == "rule":
			ctx = {"rule": "fiscal_identity"}
		elif id == "settlement":
			ctx = s.last_receipt
		var o: JwOverlay = _overlay(s, id, ctx)
		o.free()
	s.compute_dryrun_sync()
	eq_str(_fingerprint(s), before, "rendering every page/overlay and re-running the dry-run leaves SimState untouched")


# ── 草案、预算审查、确认框（§8.3 / §8.4） ───────────────────────────────

func test_confirm_dialog_renders_all_blocks() -> void:
	var s: JwSession = _session(0)
	var o: JwOverlay = _overlay(s, "confirm", {})
	for id: String in ["CashProjectionTable", "ScenarioTable", "CommitmentTable", "CommandList", "IrreversibleList",
			"ReasonList", "ConfirmFooter"]:
		check(_find(o, id) != null, "confirm dialog renders " + id)
	var table: Control = _find(o, "CashProjectionTable")
	var n_q: int = 0
	if table != null:
		for n: Node in _nodes(table):
			if n is Label and (n as Label).text.begins_with(JwText.t("fmt.quarter").split("{")[0].strip_edges()):
				n_q += 1
	ge_int(n_q, 4, "A1 header shows four quarter columns including the current quarter")
	var btn: Button = _find(o, "ConfirmAdvance") as Button
	if btn == null:
		for n2: Node in _nodes(o):
			if n2 is Button and String(n2.name) == "ConfirmAdvance":
				btn = n2 as Button
	check(btn != null, "confirm button exists")
	o.free()


func test_draft_commitments_have_three_totals_and_perpetual_rows() -> void:
	var s: JwSession = JwSession.new()
	s.set_sync_mode(true)
	s.start_new(SEED + 1, -1)
	var done: bool = false
	for p: int in JwReadModel.POLICY_N:
		if done or not s.catalog.is_project(p):
			continue
		for reg: int in JwReadModel.R:
			if int(s.model.eligibility(p, true, reg).get("code", -1)) == 0:
				s.add_draft(s.draft_launch(p, reg, JwReadModel.PPM, 0))
				done = true
				break
	check(done, "a project draft could be added")
	var com: Dictionary = s.draft_commitments()
	for k: String in ["four_q", "steady", "irreversible"]:
		check(com.has(k), "commitment totals include " + k)
	ge_int((com["rows"] as Array).size(), 1, "commitment rows exist for the draft")
	var o: JwOverlay = _overlay(s, "confirm", {})
	var totals: Control = _find(o, "CommitTotals")
	check(totals != null and (totals as Label).text != "", "three-part totals line renders")
	var hr: Dictionary = s.headroom_with_draft()
	check(not hr.is_empty(), "headroom with draft computed")
	if not hr.is_empty():
		le_int(int(hr["lo"]), int(hr["hi"]), "headroom interval lo <= hi")
	o.free()
	s.free()


## R-DEFER-01：延期草案 → 预算审查列出赔偿 → 试算放行 → 推进后项目为「合同延期」，赔偿与界面推算一致。
func test_project_defer_flow() -> void:
	var s: JwSession = JwSession.new()
	s.set_sync_mode(true)
	s.start_new(SEED + 2, -1)
	var done: bool = false
	for p: int in JwReadModel.POLICY_N:
		if done or not s.catalog.is_project(p):
			continue
		for reg: int in JwReadModel.R:
			if int(s.model.eligibility(p, true, reg).get("code", -1)) == 0:
				s.add_draft(s.draft_launch(p, reg, JwReadModel.PPM, 0))
				done = true
				break
	check(done, "a project draft could be added")
	s.advance()
	var rows: Array[Dictionary] = s.model.project_rows()
	ge_int(rows.size(), 1, "project exists after launch")
	if rows.is_empty():
		s.free()
		return
	var pj: int = int(rows[rows.size() - 1]["p"])
	var dc: Dictionary = s.model.defer_cost(rows[rows.size() - 1], 2)
	check(bool(dc["allowed"]), "a running project can be deferred")
	check(int(dc["fee"]) > 0, "deferral has a fee")
	check(not bool(s.model.defer_cost(rows[rows.size() - 1], 99)["allowed"]), "deferral beyond the quarter cap is refused")
	# 缺口处理器 gap.defer 的合同付款出口：挑出可延期的项目，赔偿与界面推算一致；执行出口即加入延期草案。
	var pdf: Dictionary = JwReasons._deferrable_project(s.model, s.catalog)
	check(not pdf.is_empty(), "gap resolver finds a deferrable project")
	if not pdf.is_empty():
		check(int(pdf["installment"]) > 0, "deferring saves an installment")
		eq_int(int(pdf["fee"]), int(s.model.defer_cost(rows[rows.size() - 1], 1)["fee"]), "exit fee equals the 1-quarter estimate")
		s.apply_exit({"type": "add_project_defer", "project": int(pdf["p"]), "quarters": 1, "name": String(pdf["name"])})
		eq_int(s.drafts.size(), 1, "the exit adds one draft")
		if s.drafts.size() == 1:
			eq_int(int((s.drafts[0] as Dictionary)["kind"]), JwSession.K_DEFER, "the exit adds a project_defer draft")
		s.clear_drafts()
	s.add_draft(s.draft_project_defer(pj, 2, "project"))
	var found: bool = false
	for r: Dictionary in s.draft_commitments()["rows"]:
		if int(r.get("per_q", -1)) == int(dc["fee"]):
			found = true
	check(found, "budget review lists the deferral fee")
	var verdicts: Array[Dictionary] = s.draft_verdicts()
	eq_int(int(verdicts[verdicts.size() - 1]["code"]), 0, "deferral draft passes the dry run")
	s.advance()
	var after: Dictionary = {}
	for r2: Dictionary in s.model.project_rows():
		if int(r2["p"]) == pj:
			after = r2
	check(not after.is_empty(), "project row still present")
	if not after.is_empty():
		eq_int(int(after["suspension"]), JwReadModel.SUSPEND_DEFERRED, "project is deferred after advancing")
		eq_int(int(after["defer_fee"]), int(dc["fee"]), "settled fee equals the UI estimate")
		check(JwText.t("suspend.%d" % int(after["suspension"])) != "", "suspension reason has text")
		check(not bool(s.model.defer_cost(after, 1)["allowed"]), "a deferred project cannot be deferred again")
	s.free()


## AC-34（docs/20 §10.4 术语首见）：五页的「本页术语」签，每个都在术语表里有术语、一句定义、本局实例与规则锚点；
## 术语表每条至少出现在一页上。未看过的术语带「新」角标，打开定义卡即视为看过，页面刷新后角标消失。
func test_glossary_terms_complete_and_first_seen() -> void:
	var s: JwSession = _session(2)
	var on_pages: Dictionary = {}
	for k: int in PAGE_IDS.size():
		var pg: JwPage = _page(s, k)
		check(_find(pg, "TermStrip") != null, "page %s has a term strip" % PAGE_IDS[k])
		for n: Node in _nodes(pg):
			if not (n is Control):
				continue
			var jid: String = String((n as Control).get_meta("jw_id", ""))
			if not jid.begins_with("Term_"):
				continue
			var id: String = jid.substr(5)
			on_pages[id] = true
			check(JwGlossary.has(id), "term %s is in the glossary" % id)
			check(JwGlossary.term(id) != "", "term %s has a name" % id)
			check(JwGlossary.definition(id) != "", "term %s has a one-line definition" % id)
			check(JwGlossary.instance(id, s) != "", "term %s has an in-game instance" % id)
			var a: int = JwGlossary.anchor(id)
			check(a >= 1 and a <= 14 and JwText.has("rb.s%d" % a), "term %s links to a rules-book anchor" % id)
		pg.free()
	for gid: String in JwGlossary.ids():
		check(on_pages.has(gid), "glossary term %s appears on at least one page" % gid)
	s.seen_terms.clear()
	var pg2: JwPage = _page(s, 0)
	check(_find(pg2, "TermNew_gov_cash") != null, "an unseen term shows the new badge")
	var o: JwOverlay = _overlay(s, "term", {"term": "gov_cash"})
	check(_find(o, "TermDefinition") != null, "term card shows the definition")
	check(_find(o, "TermInstance") != null, "term card shows the in-game instance")
	check(_find(o, "TermRuleLink") != null, "term card links to the rules book")
	o.free()
	s.mark_term_seen("gov_cash")
	pg2.refresh()
	check(_find(pg2, "TermNew_gov_cash") == null, "the badge disappears once the card was opened")
	check(_find(pg2, "TermNew_arrears") != null, "other unseen terms keep their badge")
	pg2.free()
	s.seen_terms.clear()


## docs/20 §10.4 第 9 条：规则手册逐条列出 12 个事件模板的公开触发条件（指标、范围、阈值、概率、冷却、次数上限），
## 每个条件的指标都有中文名，不出现未登记的比较符；不披露本局是否触发。
func test_rules_book_lists_event_triggers() -> void:
	var s: JwSession = _session(0)
	eq_int(s.catalog.events.size(), 12, "catalog loads 12 event templates")
	for ev: Dictionary in s.catalog.events:
		for c: Dictionary in ev["conds"]:
			var metric: String = String(c["metric"])
			if metric == "state.time.q" or metric == "state.policy.enabled" or metric == "flow.politics.budget_review_due":
				continue
			check(JwText.has("ev.metric." + metric), "event metric %s has a display name" % metric)
			check(JwText.has("ev.op." + String(c["op"])), "event op %s has a symbol" % String(c["op"]))
			if String(c["scope"]) != "":
				check(s.catalog.scope_label(String(c["scope"])) != "", "event scope %s has a label" % String(c["scope"]))
	var o: JwOverlay = _overlay(s, "rules", {"anchor": 9})
	for k: int in 12:
		var l: Control = _find(o, "RuleEvent_E%02d" % (k + 1))
		check(l != null, "rules book lists event E%02d" % (k + 1))
		if l != null:
			var txt: String = (l as Label).text
			check(txt.find(String(s.catalog.events[k]["label"])) >= 0, "event line names the event")
			check(txt.find(JwFormat.pct(int(s.catalog.events[k]["p_ppm"]))) >= 0, "event line shows the probability")
	o.free()


## AC-16（docs/20 §4.4）：图表四标注——总览「走势」的每张图都带时间范围 / 单位 / 价格基期 / 分母，渲染在图框之内；
## 任一标注为空即 push_error 并出现红底占位（本用例故意构造一次，声明预期的 1 条引擎错误）。
func test_chart_frames_carry_four_annotations() -> void:
	var s: JwSession = _session(2)
	var pg: JwPage = _page(s, 0)
	var tc: Control = _find(pg, "TrendCharts")
	check(tc != null, "overview has trend charts")
	var frames: int = 0
	for n: Node in _nodes(tc if tc != null else pg):
		if n is JwChartFrame:
			frames += 1
			var f: JwChartFrame = n as JwChartFrame
			check(f.get_chart_meta() != null and f.get_chart_meta().missing().is_empty(),
					"chart %s has all four annotations" % f.chart_title)
			var ml: Control = _find(f, "ChartMeta")
			check(ml != null and (ml as Label).text != "", "chart %s renders its annotation line inside the frame" % f.chart_title)
			check(_find(f, "ChartMetaMissing") == null, "chart %s shows no missing-meta placeholder" % f.chart_title)
	eq_int(frames, 6, "overview renders six trend charts")
	pg.free()
	expected_engine_errors = 1
	var bad: JwLineChart = JwLineChart.make("probe", JwChartMeta.make("t", "", "p", "d"), [] as Array[Dictionary],
			PackedInt64Array(), "u")
	check(_find(bad, "ChartMetaMissing") != null, "an empty annotation renders the red placeholder")
	eq_int(JwChartMeta.make("t", "", "p", "").missing().size(), 2, "missing() lists every empty field")
	bad.free()


## docs/20 D-02 承诺时间轴：四泳道 × 12 季；前四季的本金 + 利息与 SimCore 的 derived.fiscal.next4q_debt_service_uu 逐位一致；
## 总览页与季度报告各有一条，四标注齐全。
func test_commitment_timeline_matches_simcore() -> void:
	var s: JwSession = _session(2)
	var sched: Dictionary = s.game.commitment_schedule(12)
	check(not sched.is_empty(), "commitment schedule available")
	for lane: String in JwCommitTimeline.LANES:
		eq_int((sched[lane] as PackedInt64Array).size(), 12, "lane %s has 12 quarters" % lane)
	var st: Object = s.game.get("_st")
	var bonds: Object = st.get("bonds")
	var ds4: int = int(bonds.call("debt_service_next4q", int(sched["q0"])))
	var sum4: int = 0
	for t: int in 4:
		sum4 += int((sched["principal"] as PackedInt64Array)[t]) + int((sched["interest"] as PackedInt64Array)[t])
	eq_int(sum4, ds4, "first four quarters of principal + interest equal SimCore next4q debt service")
	var opex: PackedInt64Array = sched["opex"]
	ge_int(int(opex[0]), int(st.get("treasury").get("service_opex_committed")), "opex lane includes the landed obligation")
	var pg: JwPage = _page(s, 0)
	var ct: Control = _find(pg, "CommitTimeline")
	check(ct != null and ct is JwChartFrame and (ct as JwChartFrame).get_chart_meta().missing().is_empty(),
			"overview shows the commitment timeline with four annotations")
	pg.free()
	var rp: JwPage = _page(s, 5)
	check(_find(rp, "CommitTimeline") != null, "quarterly report shows the commitment timeline")
	rp.free()


## AC-18 / AC-20（docs/20 §7.2.5）：地区图的四个标签都在右侧标签栏里，引出线端点（锚点）落在各自多边形内；
## 图上的邻接边与成本系数逐条来自剧本 regions.json（界面不定义拓扑）；默认图层四区同色时按规格只报构建期警告。
func test_region_map_labels_edges_and_topology() -> void:
	var s: JwSession = _session(1)
	var pg: JwPage = _page(s, 0)
	var mp: JwRegionMap = _find(pg, "RegionMap") as JwRegionMap
	check(mp != null, "overview renders the region map in the wide band")
	if mp == null:
		pg.free()
		return
	var bar: Control = _find(mp, "MapLabelBar")
	check(bar != null, "map has a label bar")
	var tokens: Dictionary = {}
	for r: int in JwReadModel.R:
		var lab: Control = _find(mp, "MapLabel%d" % r)
		check(lab != null and lab.get_parent() == bar, "label %d sits in the label bar" % r)
		check(Geometry2D.is_point_in_polygon(mp.anchor_of(r), mp.regions[r]["poly"]), "leader-line anchor %d lies inside its polygon" % r)
		tokens[String(mp.regions[r]["token"])] = true
	# AC-20b 在规格里是「否则构建期警告」：四区同一约束类别（例如都被计划量约束）是模型实况，不是界面缺陷。
	if tokens.size() < 2:
		print("[AC-20b 警告] 本季默认图层四区同色（各区最紧约束同类），新手简报仍需靠诊断卡指向瓶颈。")
	# 拓扑逐条来自剧本：重新从 regions.json 数无向邻接对与成本。
	var reg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/scenarios/chengwan/regions.json"))
	var ids: Array = []
	for rd: Variant in reg["regions"]:
		ids.append(String((rd as Dictionary)["region_id"]))
	var want: Dictionary = {}
	for a_i: int in ids.size():
		var rd2: Dictionary = reg["regions"][a_i]
		for bid: Variant in rd2["adjacency"]:
			var b_i: int = ids.find(String(bid))
			if b_i > a_i:
				want["%d-%d" % [a_i, b_i]] = int((rd2["logistics_cost_ppm"] as Dictionary)[String(bid)])
	eq_int(mp.edges.size(), want.size(), "every adjacency declared by the scenario is drawn as an edge")
	for e: Variant in mp.edges:
		var ed: Array = e
		var key: String = "%d-%d" % [int(ed[0]), int(ed[1])]
		check(want.has(key), "edge %s is declared by the scenario" % key)
		if want.has(key):
			eq_int(int(ed[2]), int(want[key]), "edge %s shows the scenario logistics cost" % key)
	pg.free()


func test_dock_never_disables_without_reason() -> void:
	var s: JwSession = _session(0)
	var dock: JwActionDock = JwActionDock.new()
	dock.setup(s, null)
	dock.refresh()
	var adv: Button = null
	var status: Label = null
	for n: Node in _nodes(dock):
		if n is Button and String(n.name) == "AdvanceButton":
			adv = n as Button
		if n is Label and String(n.name) == "DockStatus":
			status = n as Label
	check(adv != null, "dock has advance button")
	if adv != null:
		check(adv.text != "", "advance button has a label")
		if adv.disabled:
			check(status != null and status.text != "", "disabled advance button shows a reason")
	dock.free()


# ── 季度报告（docs/20 §7.5；AC-18b） ──────────────────────────────────────

func test_report_q2_shows_paid_but_zero_new_capacity() -> void:
	var s: JwSession = _session(2)
	var pg: JwPage = _page(s, 5)
	var lag: Control = _find(pg, "LagBlock")
	check(lag != null, "report has LagBlock")
	var ok_row: bool = false
	for n: Node in _nodes(pg):
		if n.has_meta("paid") and n.has_meta("new_capacity"):
			if int(n.get_meta("paid")) > 0 and int(n.get_meta("new_capacity")) == 0:
				ok_row = true
	check(ok_row, "q2 report renders a project row with paid > 0 and new capacity = 0")
	for id: String in ["ReportHeader", "VarianceTable", "SettlementReceipt", "BindingFactors", "Scenarios", "Todo"]:
		check(_find(pg, id) != null, "report section present: " + id)
	for k: int in 8:
		check(_find(pg, "Step%d" % (k + 1)) != null, "settlement step %d receipt present" % (k + 1))
	pg.free()


func test_variance_table_compares_with_stored_intervals() -> void:
	var s: JwSession = _session(1)
	check(s.expectations.has("0"), "q0 expectations were stored before advancing (VT-1)")
	var pg: JwPage = _page(s, 5)
	var vt: Control = _find(pg, "VarianceTable")
	check(vt != null, "variance table present")
	var n_proj: int = 0
	var n_act: int = 0
	if vt != null:
		for t: Dictionary in _texts_with_class(vt):
			if int(t["cls"]) == JwInfo.Cls.PROJECTED:
				n_proj += 1
			elif int(t["cls"]) == JwInfo.Cls.ACTUAL:
				n_act += 1
	ge_int(n_proj, 1, "variance table has interval cells")
	ge_int(n_act, 1, "variance table has actual cells")
	pg.free()


# ── 覆盖层与文案完整性 ────────────────────────────────────────────────────

func test_all_overlays_build_without_missing_text() -> void:
	var s: JwSession = _session(1)
	for id: String in OVERLAY_IDS:
		var ctx: Dictionary = {}
		if id == "ledger":
			ctx = {"ledger": "cash"}
		elif id == "rule":
			ctx = {"rule": "bond_rules"}
		elif id == "settlement":
			ctx = s.last_receipt
		var o: JwOverlay = _overlay(s, id, ctx)
		check(o.title_label != null and o.title_label.text != "", "overlay %s has a title" % id)
		if o is JwSettlementReplay:
			(o as JwSettlementReplay).finish_now()
		o.free()
	for lg: String in ["cash", "transaction", "debt", "commit", "project", "constraint", "command", "labor", "household",
			"service", "tax", "external", "value_added", "rule"]:
		var d: JwOverlay = _overlay(s, "ledger", {"ledger": lg})
		d.free()
	for rk: String in ["fiscal_identity", "bond_rules", "real_gdp", "unemployment", "household_burden", "population",
			"subjective", "commission", "unknown_rule"]:
		var rc: JwOverlay = _overlay(s, "rule", {"rule": rk})
		rc.free()
	for i: int in _page_classes().size():
		var pg: JwPage = _page(s, i)
		pg.free()
	# 政策工作台逐项选中 12 项政策（参数行、枚举、资金来源、项目控件各走一遍）。
	var pp: JwPolicyPage = _page(s, 2) as JwPolicyPage
	for p: int in JwReadModel.POLICY_N:
		pp.selected = p
		pp.refresh()
	pp.free()
	var missing: PackedStringArray = JwText.missing_keys()
	eq_int(missing.size(), 0, "no text key was missing at runtime: " + ", ".join(missing.slice(0, 8)))
	eq_int(JwText.duplicate_keys().size(), 0, "no duplicate text keys across files")


func test_literal_text_keys_exist() -> void:
	var files: PackedStringArray = PackedStringArray()
	_gd_files("res://ui", files)
	var rx_lit: RegEx = RegEx.create_from_string("\"([a-z][a-z0-9_]*(?:\\.[a-z0-9_]+)+)\"")
	var skip_prefix: PackedStringArray = ["state.", "flow.", "derived.", "param.", "politics.", "meta.", "ev.", "overlay.",
			"page.", "content.", "account.", "blk.", "det.", "gap.", "note.", "series.", "debug.", "res.", "user.", "onb.q"]
	var palette: Dictionary = {}
	for k: String in JwTheme.palette_tokens():
		palette[k] = true
	var n_keys: int = 0
	var missing: PackedStringArray = PackedStringArray()
	for f: String in files:
		var src: String = FileAccess.get_file_as_string(f)
		for line: String in src.split("\n"):
			var code: String = _strip_comment(line)
			for m: RegExMatch in rx_lit.search_all(code):
				var k: String = m.get_string(1)
				var skip: bool = palette.has(k)
				for sp: String in skip_prefix:
					if k.begins_with(sp):
						skip = true
				if skip:
					continue
				n_keys += 1
				if not JwText.has(k):
					missing.append(k + " @" + f.get_file())
	ge_int(n_keys, 300, "scanned literal text keys")
	eq_int(missing.size(), 0, "every literal text key exists: " + ", ".join(missing.slice(0, 10)))


func test_template_slots_render() -> void:
	eq_str(JwText.render_raw("a{x}b", {"x": "1"}), "a1b", "named slot renders")
	eq_str(JwText.render_raw("[[?x]]X={x}[[/]]", {"x": ""}), "", "conditional segment hidden when empty")
	eq_str(JwText.render_raw("[[*items sep=\"、\"]]{.n}[[/]]", {"items": [{"n": "a"}, {"n": "b"}]}), "a、b", "list segment")
	eq_str(JwText.render_raw("{{x}}", {}), "{x}", "brace escape")


# ── 静态：界面代码无中文字面量；只经 JWGame 与 SimCore 交互 ──────────────

func test_no_cjk_string_literals_in_ui_code() -> void:
	var files: PackedStringArray = PackedStringArray()
	_gd_files("res://ui", files)
	var bad: PackedStringArray = PackedStringArray()
	for f: String in files:
		var src: String = FileAccess.get_file_as_string(f)
		var ln: int = 0
		for line: String in src.split("\n"):
			ln += 1
			var code: String = _strip_comment(line)
			var in_str: bool = false
			for i: int in code.length():
				var ch: String = code[i]
				if ch == "\"":
					in_str = not in_str
				elif in_str and code.unicode_at(i) >= 0x4E00 and code.unicode_at(i) <= 0x9FFF:
					bad.append("%s:%d" % [f.get_file(), ln])
					break
	ge_int(files.size(), 30, "scanned ui scripts")
	eq_int(bad.size(), 0, "no CJK string literals in ui/*.gd (all copy lives in ui/text): " + ", ".join(bad.slice(0, 8)))


func test_ui_code_only_touches_sim_through_jwgame() -> void:
	var files: PackedStringArray = PackedStringArray()
	_gd_files("res://ui", files)
	var rx: RegEx = RegEx.create_from_string("\\bJW[A-Z][A-Za-z]+\\b")
	var bad: PackedStringArray = PackedStringArray()
	for f: String in files:
		var src: String = FileAccess.get_file_as_string(f)
		for line: String in src.split("\n"):
			var code: String = _strip_comment(line)
			if code.contains("res://sim/") or code.contains("res://systems/"):
				bad.append(f.get_file() + ": preload of sim/systems")
			if code.contains("._st") or code.contains(".ledger.post") or code.contains("_runner"):
				bad.append(f.get_file() + ": private state access")
			for m: RegExMatch in rx.search_all(code):
				if m.get_string() != "JWGame":
					bad.append(f.get_file() + ": " + m.get_string())
	eq_int(bad.size(), 0, "ui/ references SimCore only via JWGame: " + ", ".join(bad.slice(0, 8)))


func test_mirrored_constants_match_simcore() -> void:
	eq_int(JwSession.K_ENACT, JWCommands.Kind.POLICY_ENACT, "K_ENACT")
	eq_int(JwSession.K_SET_PARAMS, JWCommands.Kind.POLICY_SET_PARAMS, "K_SET_PARAMS")
	eq_int(JwSession.K_REPEAL, JWCommands.Kind.POLICY_REPEAL, "K_REPEAL")
	eq_int(JwSession.K_LAUNCH, JWCommands.Kind.PROJECT_LAUNCH, "K_LAUNCH")
	eq_int(JwSession.K_CANCEL, JWCommands.Kind.PROJECT_CANCEL, "K_CANCEL")
	eq_int(JwSession.K_DEFER, JWCommands.Kind.PROJECT_DEFER, "K_DEFER")
	eq_int(JwReadModel.SUSPEND_DEFERRED, JWUnits.SuspendReason.DEFERRED, "SUSPEND_DEFERRED")
	eq_int(JwSession.K_ISSUE_BOND, JWCommands.Kind.ISSUE_BOND, "K_ISSUE_BOND")
	eq_int(JwReadModel.RJ_RUN_TERMINATED, JWResult.Reject.RUN_TERMINATED, "RJ_RUN_TERMINATED")
	eq_int(JwReadModel.RJ_AUTHORITY, JWResult.Reject.AUTHORITY, "RJ_AUTHORITY")
	eq_int(JwReadModel.RJ_SEATS_SHORT, JWResult.Reject.SEATS_SHORT, "RJ_SEATS_SHORT")
	eq_int(JwReadModel.RJ_BLOC_VETO, JWResult.Reject.BLOC_VETO, "RJ_BLOC_VETO")
	eq_int(JwReadModel.RJ_BUDGET_INSUFFICIENT, JWResult.Reject.BUDGET_INSUFFICIENT, "RJ_BUDGET_INSUFFICIENT")
	eq_int(JwReadModel.RJ_NO_SLOT, JWResult.Reject.NO_SLOT, "RJ_NO_SLOT")
	eq_int(JwReadModel.RJ_PRECONDITION, JWResult.Reject.PRECONDITION, "RJ_PRECONDITION")
	eq_int(JwReadModel.RJ_PARAM_RANGE, JWResult.Reject.PARAM_RANGE, "RJ_PARAM_RANGE")
	eq_int(JwReadModel.RJ_COMMAND_ORDER, JWResult.Reject.COMMAND_ORDER, "RJ_COMMAND_ORDER")
	eq_int(JwReadModel.U, 1_000_000_000, "1 U = 1 000 000 000 μU")


# ── 格式化与字体 ──────────────────────────────────────────────────────────

func test_integer_formatters() -> void:
	eq_str(JwFormat.u(1_234_567_890_000), "1,234.57 U", "amount two decimals with grouping")
	eq_str(JwFormat.u(5_000_000), "0.01 U", "half rounds away from zero")
	eq_str(JwFormat.u(-5_000_000), JwFormat.MINUS + "0.01 U", "negative half rounds away from zero, true minus sign")
	eq_str(JwFormat.u(1), JwText.t("fmt.lt_u"), "non-zero tiny amount never shows as zero")
	eq_str(JwFormat.pct(80_000), "8.0 %", "ppm to percent")
	eq_str(JwFormat.persons(9_000_000), "900.0 " + JwText.t("unit.wan_persons"), "9,000,000 persons = 900.0 wan")
	eq_str(JwFormat.persons(934_161), "934,161 " + JwText.t("unit.persons"), "below one million: integer persons")
	eq_str(JwFormat.wan_num(11_677_000), "1,167.7", "wan number with one decimal")
	eq_str(JwFormat.quarter(0), JwText.render("fmt.quarter", {"n": "1"}), "display quarter = q + 1")
	check(JwFormat.range_u(1_800_000_000, 2_600_000_000).begins_with(JwFormat.RANGE_OPEN), "interval uses 〔〕")


func test_body_text_at_least_16_lu_and_digits_tabular() -> void:
	ge_int(JwTheme.size("body"), 16, "body text >= 16 lu")
	ge_int(JwTheme.size("dense"), 16, "table text >= 16 lu")
	ge_int(JwTheme.size("num"), 16, "table numbers >= 16 lu")
	var f: Font = JwTheme.font("num")
	var w0: float = f.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var same: bool = true
	for d: String in ["1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		if absf(f.get_string_size(d, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x - w0) > 0.01:
			same = false
	check(same, "number font digits share one advance width (tnum)")


func test_sans_font_uses_mandated_cjk_list() -> void:
	var f: Font = JwTheme.font("body")
	check(f is SystemFont, "body font is a SystemFont (no bundled font files)")
	if f is SystemFont:
		var names: PackedStringArray = (f as SystemFont).font_names
		eq_str(names[0], "Microsoft YaHei UI", "first CJK font")
		eq_str(names[1], "Microsoft YaHei", "second CJK font")
		eq_str(names[2], "PingFang SC", "third CJK font")
		eq_str(names[3], "Noto Sans CJK SC", "fourth CJK font")
		eq_str(names[4], "SimHei", "fifth CJK font")
	var t: Font = JwTheme.font("title_page")
	check(t is SystemFont and (t as SystemFont).font_names[0] == "Microsoft YaHei UI", "titles use the same CJK list")


# ── 引导（docs/22） ─────────────────────────────────────────────────────

func test_onboarding_criteria_are_disjunctive() -> void:
	var s: JwSession = _session(0)
	var ev_c: Array = [
		{"name": "ev.section_expanded", "args": {"node": "DiagCard0/Mechanism"}},
		{"name": "ev.page_shown", "args": {"page_id": "page.region"}},
		{"name": "ev.ledger_opened", "args": {"ledger": "constraint"}},
	]
	var r1: Dictionary = JwOnboarding.evaluate(0, [], ev_c, s)
	check(bool(r1["met"]), "Q1 can be met without submitting a command (P1.C)")
	eq_str(String(r1["met_by"]), "P1.C", "met_by records the path")
	var r2: Dictionary = JwOnboarding.evaluate(0, [{"kind": JwSession.K_LAUNCH, "accepted": 1}], [], s)
	eq_str(String(r2["met_by"]), "P1.A", "accepted launch meets Q1 via P1.A")
	var r3: Dictionary = JwOnboarding.evaluate(2, [], [{"name": "ev.impact_source_changed", "args": {"source": "current_draft"}}], s)
	check(bool(r3["met"]), "Q3 met by switching the impact source to the current draft")
	var r4: Dictionary = JwOnboarding.evaluate(0, [], [], s)
	check_false(bool(r4["met"]), "no activity does not meet Q1")


# ── 工具 ─────────────────────────────────────────────────────────────────

static func _gd_files(dir_path: String, out: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var e: String = dir.get_next()
	while e != "":
		if not e.begins_with("."):
			var full: String = dir_path + "/" + e
			if dir.current_is_dir():
				_gd_files(full, out)
			elif e.ends_with(".gd"):
				out.append(full)
		e = dir.get_next()
	dir.list_dir_end()


## 去掉行内注释（不在字符串里的 #）。
static func _strip_comment(line: String) -> String:
	var in_str: bool = false
	for i: int in line.length():
		var ch: String = line[i]
		if ch == "\"":
			in_str = not in_str
		elif ch == "#" and not in_str:
			return line.substr(0, i)
	return line


## R-SCENARIO-01 / R-CLOCK-01：开局覆盖层列出两个剧本；战役剧本按公历显示季度，切回旧剧本恢复「第 N 季」。
func test_campaign_scenario_calendar() -> void:
	var list: Array[Dictionary] = JwCatalog.list_scenarios()
	var names: PackedStringArray = PackedStringArray()
	for d: Dictionary in list:
		names.append(String(d["name"]))
	check(names.has("chengwan") and names.has("campaign_1600"), "剧本清单含旧剧本与战役剧本：%s" % str(names))
	var s: JwSession = JwSession.new()
	s.set_sync_mode(true)
	var r: Dictionary = s.start_new(SEED, -1, "campaign_1600")
	check(bool(r.get("ok", false)), "战役剧本开局（%s）" % str(r))
	eq_int(s.catalog.scenario_mode(), 1, "目录切到战役剧本")
	eq_str(JwFormat.quarter(0), "1600 年春", "第 0 季显示为 1600 年春")
	eq_str(JwFormat.quarter(7), "1601 年冬", "第 7 季显示为 1601 年冬")
	var ng: JwNewGame = JwNewGame.new()
	ng.setup(s, null, "newgame", {})
	ng.build()
	check(ng.find_child("ScenarioOption", true, false) != null, "开局覆盖层有剧本选择")
	ng.free()
	var s2: JwSession = JwSession.new()
	s2.set_sync_mode(true)
	check(bool(s2.start_new(SEED, -1, "chengwan").get("ok", false)), "切回旧剧本开局")
	eq_str(JwFormat.quarter(0), JwText.render("fmt.quarter", {"n": "1"}), "旧剧本仍显示「第 1 季」")


## R-CLOCK-01：战役剧本的确认框有「推进一年 / 五年」；会话批量推进逐季写历史快照。
func test_campaign_batch_advance() -> void:
	var s: JwSession = JwSession.new()
	s.set_sync_mode(true)
	check(bool(s.start_new(SEED, -1, "campaign_1600").get("ok", false)), "战役开局")
	var ca: JwConfirmAdvance = JwConfirmAdvance.new()
	ca.setup(s, null, "confirm", {})
	ca.build()
	check(ca.find_child("ConfirmAdvanceYears1", true, false) != null, "有「推进一年」")
	check(ca.find_child("ConfirmAdvanceYears5", true, false) != null, "有「推进五年」")
	ca.free()
	var h0: int = s.history.size()
	var r: Dictionary = s.advance_batch(4)
	check(r.has("batch"), "回执带批量汇总")
	var done: int = int((r["batch"] as Dictionary)["done"])
	ge_int(done, 1, "至少推进一季")
	eq_int(s.model.q, done, "读模型季号 == 推进季数")
	eq_int(s.history.size() - h0, done, "每季一条历史快照")
	var s2: JwSession = JwSession.new()
	s2.set_sync_mode(true)
	check(bool(s2.start_new(SEED, -1, "chengwan").get("ok", false)), "切回旧剧本（复原公历显示）")
