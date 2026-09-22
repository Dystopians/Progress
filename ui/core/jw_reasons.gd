## 原因对象（docs/20 §9、docs/21 §5）：「为什么不能执行 / 为什么会有缺口」。
##
## 原因由三处构造：S02 的拒绝码（草案试算回执）、资格链镜像（政策目录）、试算结果（缺口与提示）。
## 界面只渲染：**同一原因在目录、编辑器、预算审查、确认框四处由 render_lines() 这一个函数输出**（RC-13）。
## 行 2 的数字全部由构造方算好后以已格式化字符串填进槽位，渲染时不做算术（RC-02）。
##
## 原因字典：{code, severity, quarter, subject, subject_label, line2, drivers[], exits[], links[],
##            numbers{need, avail, gap}, key}
## exits[i] = {text, action{type, …}}，每条出口都是一条可执行的界面命令（RC-08）。
class_name JwReasons
extends RefCounted


static func _q(q: int) -> String:
	return JwFormat.quarter(q)


static func make(code: String, sev: int, quarter: int, subject: String, subject_label: String,
		line2: String) -> Dictionary:
	return {
		"code": code, "severity": sev, "quarter": quarter, "subject": subject,
		"subject_label": subject_label, "line2": line2, "drivers": [], "exits": [], "links": [],
		"numbers": {}, "key": code + ":" + subject,
	}


static func add_exit(r: Dictionary, text: String, action: Dictionary) -> void:
	var ex: Array = r["exits"]
	if ex.size() >= 4:
		return
	ex.append({"text": text, "action": action})


static func add_link(r: Dictionary, ledger: String, rows: PackedInt64Array = PackedInt64Array()) -> void:
	var ls: Array = r["links"]
	ls.append({"ledger": ledger, "rows": rows})


static func add_driver(r: Dictionary, label: String, amount_text: String) -> void:
	var ds: Array = r["drivers"]
	ds.append({"label": label, "amount": amount_text})


## 五行文案（行 1 标题 / 行 2 定量 / 行 3 占用 / 行 4 出口 / 行 5 链接）。唯一渲染函数。
static func render_lines(r: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	out.append(JwText.render("reason.title", {
		"sev": JwInfo.sev_word(int(r.get("severity", JwInfo.Sev.NOTE))),
		"cat": JwText.t("reason.cat." + String(r.get("code", ""))),
		"quarter": _q(int(r.get("quarter", 0))),
		"subject": String(r.get("subject_label", "")),
	}))
	out.append(String(r.get("line2", "")))
	var drivers: Array = r.get("drivers", [])
	if not drivers.is_empty():
		var items: Array = []
		for i: int in mini(drivers.size(), 3):
			items.append(drivers[i])
		out.append(JwText.render("reason.drivers", {"items": items}))
	var exits: Array = r.get("exits", [])
	var parts: PackedStringArray = PackedStringArray()
	var marks: PackedStringArray = ["①", "②", "③", "④"]
	for i2: int in mini(exits.size(), 4):
		parts.append(marks[i2] + " " + String((exits[i2] as Dictionary).get("text", "")))
	out.append(JwText.render("reason.exits", {"list": "；".join(parts)}))
	var links: Array = r.get("links", [])
	var lp: PackedStringArray = PackedStringArray()
	for l: Variant in links:
		var ld: Dictionary = l
		lp.append("▸" + JwText.t("ledger.name." + String(ld.get("ledger", ""))))
	out.append(" ".join(lp))
	return out


static func render_text(r: Dictionary) -> String:
	return "\n".join(render_lines(r))


## 排序：BLOCK > GAP > NOTE；同级 (最早季 升序, |缺口| 降序, 码 字典序)（RC-11，稳定）。
static func sort(list: Array) -> void:
	list.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		var sx: int = int(x.get("severity", 0))
		var sy: int = int(y.get("severity", 0))
		if sx != sy:
			return sx > sy
		var qx: int = int(x.get("quarter", 0))
		var qy: int = int(y.get("quarter", 0))
		if qx != qy:
			return qx < qy
		var gx: int = absi(int((x.get("numbers", {}) as Dictionary).get("gap", 0)))
		var gy: int = absi(int((y.get("numbers", {}) as Dictionary).get("gap", 0)))
		if gx != gy:
			return gx > gy
		var kx: String = String(x.get("key", ""))
		var ky: String = String(y.get("key", ""))
		return kx < ky)


static func counts(list: Array) -> Dictionary:
	var c: Dictionary = {"block": 0, "gap": 0, "note": 0}
	for r: Variant in list:
		match int((r as Dictionary).get("severity", 0)):
			JwInfo.Sev.BLOCK:
				c["block"] = int(c["block"]) + 1
			JwInfo.Sev.GAP:
				c["gap"] = int(c["gap"]) + 1
			_:
				c["note"] = int(c["note"]) + 1
	return c


# ── 由资格链镜像或 S02 拒绝码构造 BLOCK ─────────────────────────────────────

## ctx: {kind（命令码）, p, region, scale, amount, draft（草案序号，-1 表示目录）, subject, subject_label}
static func from_code(rc: int, ctx: Dictionary, m: JwReadModel, cat: JwCatalog) -> Dictionary:
	var q: int = m.q
	var p: int = int(ctx.get("p", -1))
	var subj: String = String(ctx.get("subject", "P%02d" % (p + 1)))
	var label: String = String(ctx.get("subject_label", ""))
	var draft: int = int(ctx.get("draft", -1))
	var r: Dictionary = {}
	match rc:
		JwReadModel.RJ_AUTHORITY:
			var el: Dictionary = m.eligibility(p, false)
			var bit: int = int(el.get("authority_bit", m.at("content.policy.authority_bit", p)))
			var mask: int = int(el.get("authority_mask", m.sc("state.politics.legal_authority_mask")))
			var held: PackedStringArray = PackedStringArray()
			for b: int in 8:
				if (mask >> b) & 1 == 1:
					held.append(JwText.t("authority.bit.%d" % b))
			var ne: int = m.next_election_q()
			r = make("blk.authority", JwInfo.Sev.BLOCK, q, subj, label, JwText.render("reason.l2.blk.authority", {
				"auth_name": JwText.t("authority.bit.%d" % bit), "bit": str(bit),
				"held": "、".join(held) if not held.is_empty() else JwText.t("common.none"),
				"path": JwText.t("authority.path.%d" % bit),
				"path_q": _q(ne) if ne >= 0 else JwText.t("common.na"),
			}))
			if ne >= 0:
				add_exit(r, JwText.render("reason.exit.wait", {"q": _q(ne), "window": JwText.t("reason.window.election"),
						"remaining": JwFormat.quarters(ne - q), "residual": JwText.t("reason.residual.recompute")}),
						{"type": "defer_draft", "draft": draft, "to_q": ne})
			_add_other_tool_exit(r, p, cat)
			add_link(r, "politics")
		JwReadModel.RJ_SEATS_SHORT:
			var seats: int = m.sc("state.politics.seats_gov")
			var total: int = maxi(m.sc("state.politics.seats_total"), 1)
			var min_ppm: int = m.at("content.policy.min_seats_ppm", p)
			@warning_ignore("integer_division")
			var need_seats: int = (min_ppm * total + JwReadModel.PPM - 1) / JwReadModel.PPM
			@warning_ignore("integer_division")
			var have_ppm: int = seats * JwReadModel.PPM / total
			r = make("blk.seats", JwInfo.Sev.BLOCK, q, subj, label, JwText.render("reason.l2.blk.seats", {
				"need_pct": JwFormat.pct(min_ppm), "seats": str(seats), "total": str(total),
				"have_pct": JwFormat.pct(have_ppm), "gap_seats": str(maxi(need_seats - seats, 0)),
			}))
			r["numbers"] = {"need": need_seats, "avail": seats, "gap": maxi(need_seats - seats, 0)}
			var ne2: int = m.next_election_q()
			if ne2 >= 0:
				add_exit(r, JwText.render("reason.exit.wait", {"q": _q(ne2), "window": JwText.t("reason.window.election"),
						"remaining": JwFormat.quarters(ne2 - q), "residual": JwText.t("reason.residual.recompute")}),
						{"type": "defer_draft", "draft": draft, "to_q": ne2})
			_add_other_tool_exit(r, p, cat)
			add_link(r, "politics")
		JwReadModel.RJ_BLOC_VETO:
			var el2: Dictionary = m.eligibility(p, false)
			var b2: int = int(el2.get("bloc", 0))
			var st: int = int(el2.get("stance_ppm", 0))
			var thr: int = int(el2.get("threshold_ppm", m.rule("politics.veto_stance_threshold_ppm", -300000)))
			r = make("blk.bloc_veto", JwInfo.Sev.BLOCK, q, subj, label, JwText.render("reason.l2.blk.bloc_veto", {
				"bloc": cat.bloc_label(b2), "stance": JwFormat.pct(st), "thr": JwFormat.pct(thr),
				"gap": JwFormat.ppt(thr - st),
			}))
			r["numbers"] = {"need": thr, "avail": st, "gap": thr - st}
			_add_other_tool_exit(r, p, cat)
			add_exit(r, JwText.render("reason.exit.remove", {"residual": JwFormat.u(0)}),
					{"type": "remove_draft", "draft": draft})
			add_link(r, "politics")
		JwReadModel.RJ_POLICY_COOLDOWN:
			var until: int = m.at("state.policy.cooldown_until_q", p)
			r = make("blk.cooldown", JwInfo.Sev.BLOCK, q, subj, label, JwText.render("reason.l2.blk.cooldown", {
				"until_q": _q(until), "remaining": JwFormat.quarters(maxi(until - q, 0)),
				"toggle": JwFormat.u(m.at("content.policy.toggle_cost_uu", p)),
			}))
			r["numbers"] = {"need": until, "avail": q, "gap": maxi(until - q, 0)}
			add_exit(r, JwText.render("reason.exit.wait", {"q": _q(until), "window": "",
					"remaining": JwFormat.quarters(maxi(until - q, 0)), "residual": JwFormat.u(0)}),
					{"type": "defer_draft", "draft": draft, "to_q": until})
			add_link(r, "command")
		JwReadModel.RJ_NO_SLOT:
			var reg: int = int(ctx.get("region", -1))
			var used: int = m.slots_used(reg) if reg >= 0 else 0
			var tot: int = m.slots_total(reg) if reg >= 0 else 0
			var rel: Dictionary = _earliest_slot_release(reg, m, cat)
			r = make("blk.queue", JwInfo.Sev.BLOCK, q, subj, label, JwText.render("reason.l2.blk.queue", {
				"region": cat.region_label(reg), "used": str(used), "total": str(tot),
				"release_q": _q(int(rel.get("q", q))), "holder": String(rel.get("holder", JwText.t("common.none"))),
			}))
			r["numbers"] = {"need": 1, "avail": maxi(tot - used, 0), "gap": 1}
			add_exit(r, JwText.render("reason.exit.defer", {"q": _q(int(rel.get("q", q))),
					"n": JwFormat.quarters(maxi(int(rel.get("q", q)) - q, 0)), "residual": JwFormat.u(0)}),
					{"type": "defer_draft", "draft": draft, "to_q": int(rel.get("q", q))})
			add_exit(r, JwText.render("reason.exit.change_region", {"residual": JwText.t("reason.residual.recompute")}),
					{"type": "goto_policy", "p": p})
			add_link(r, "project")
		JwReadModel.RJ_BUDGET_INSUFFICIENT, JwReadModel.RJ_NO_FUNDING:
			var scale: int = int(ctx.get("scale", JwReadModel.PPM))
			var el3: Dictionary = m.eligibility(p, false, -1, scale)
			var need: int = int(el3.get("need", 0))
			var avail: int = int(el3.get("avail", 0))
			var gap: int = maxi(need - avail, 0)
			@warning_ignore("integer_division")
			var per_q: int = m.at("content.policy.cost_per_quarter_uu", p) * scale / JwReadModel.PPM
			r = make("blk.budget", JwInfo.Sev.BLOCK, q, subj, label, JwText.render("reason.l2.blk.budget", {
				"need": JwFormat.u(need), "per_q": JwFormat.u(per_q),
				"toggle": JwFormat.u(m.at("content.policy.toggle_cost_uu", p)),
				"avail": JwFormat.u(avail), "cash": JwFormat.u(m.gov_cash()),
				"reserved": JwFormat.u(m.sc("state.gov.reserved_memo_uu")), "gap": JwFormat.u(gap),
			}))
			r["numbers"] = {"need": need, "avail": avail, "gap": gap}
			add_driver(r, JwText.t("reason.driver.reserved"), JwFormat.u(m.sc("state.gov.reserved_memo_uu")))
			add_exit(r, JwText.render("reason.exit.borrow", {"amount": JwFormat.u(gap),
					"tenor": JwFormat.quarters(int(cat.cfg("bond_default_tenor_q", 8))),
					"residual": JwText.t("reason.residual.recompute")}),
					{"type": "add_bond", "amount": gap})
			add_exit(r, JwText.render("reason.exit.defer", {"q": _q(q + 1), "n": JwFormat.quarters(1),
					"residual": JwText.t("reason.residual.recompute")}),
					{"type": "defer_draft", "draft": draft, "to_q": q + 1})
			add_link(r, "cash")
		JwReadModel.RJ_CREDIT_LIMIT:
			var amt: int = int(ctx.get("amount", 0))
			r = make("blk.credit", JwInfo.Sev.BLOCK, q, subj, label, JwText.render("reason.l2.blk.credit", {
				"need": JwFormat.u(amt), "pool": JwFormat.u(m.invpool_cash()),
				"ext": JwFormat.u(m.credit_left()),
			}))
			r["numbers"] = {"need": amt, "avail": m.invpool_cash(), "gap": maxi(amt - m.invpool_cash(), 0)}
			add_exit(r, JwText.render("reason.exit.scale_bond", {"amount": JwFormat.u(amt / 2),
					"residual": JwText.t("reason.residual.recompute")}),
					{"type": "scale_bond", "draft": draft, "amount": amt / 2})
			add_exit(r, JwText.render("reason.exit.switch_holder", {"residual": JwText.t("reason.residual.recompute")}),
					{"type": "switch_holder", "draft": draft})
			add_link(r, "debt")
			add_link(r, "external")
		JwReadModel.RJ_ALREADY_ENACTED:
			var since: int = m.at("state.policy.enacted_q", p)
			r = make("blk.duplicate", JwInfo.Sev.BLOCK, q, subj, label, JwText.render("reason.l2.blk.duplicate", {
				"subject": label, "since_q": _q(maxi(since, -1)) if since > -1000 else JwText.t("reason.since_start"),
			}))
			add_exit(r, JwText.render("reason.exit.adjust", {"residual": JwFormat.u(0)}),
					{"type": "goto_policy", "p": p})
			add_link(r, "command")
		JwReadModel.RJ_NOT_FOUND:
			r = make("blk.not_found", JwInfo.Sev.BLOCK, q, subj, label, JwText.render("reason.l2.blk.not_found", {
				"subject": label,
			}))
			add_exit(r, JwText.render("reason.exit.remove", {"residual": JwFormat.u(0)}),
					{"type": "remove_draft", "draft": draft})
			add_link(r, "command")
		JwReadModel.RJ_PARAM_RANGE:
			r = make("blk.param_range", JwInfo.Sev.BLOCK, q, subj, label, JwText.render("reason.l2.blk.param_range", {
				"detail": String(ctx.get("range_text", JwText.t("reason.range_generic"))),
			}))
			add_exit(r, JwText.render("reason.exit.adjust", {"residual": JwFormat.u(0)}),
					{"type": "goto_policy", "p": p})
			add_link(r, "rule")
		JwReadModel.RJ_RUN_TERMINATED:
			r = make("blk.terminated", JwInfo.Sev.BLOCK, q, subj, label, JwText.render("reason.l2.blk.terminated", {
				"q": _q(maxi(q - 1, 0)),
			}))
			add_exit(r, JwText.t("reason.exit.archive"), {"type": "open_archive"})
			add_link(r, "politics")
		JwReadModel.RJ_PHASE_BUSY:
			r = make("blk.readonly", JwInfo.Sev.BLOCK, q, subj, label, JwText.t("reason.l2.blk.readonly"))
			add_exit(r, JwText.t("reason.exit.new_game"), {"type": "open_saves"})
			add_link(r, "command")
		_:
			# PRECONDITION：先判是否立法窗口，再判首版未实现的命令，其余给出条件原文。
			var kind: int = int(ctx.get("kind", 0))
			if kind == 6:
				# R-DEFER-01：延期的前置条件逐条写出（在建、不在延期中、次数与累计季数），不再是「未实现」。
				var pj: int = int(ctx.get("project", -1))
				var used: String = ""
				for row: Dictionary in m.project_rows():
					if int(row["p"]) == pj:
						used = JwText.render("reason.defer.used", {"count": str(int(row["defer_count"])),
								"quarters": JwFormat.quarters(int(row["defer_q_total"])),
								"status": JwText.t("project_status.%d" % int(row["status"]))})
				r = make("blk.defer", JwInfo.Sev.BLOCK, q, subj, label, JwText.render("reason.l2.blk.defer", {
					"count": str(m.rule("param.max_defer_count", 0)),
					"quarters": JwFormat.quarters(m.rule("param.max_defer_quarters", 0)),
					"used": used,
				}))
				add_exit(r, JwText.render("reason.exit.remove", {"residual": JwFormat.u(0)}),
						{"type": "remove_draft", "draft": draft})
				add_link(r, "rule")
			elif kind == 7 or kind == 11:
				r = make("blk.unsupported", JwInfo.Sev.BLOCK, q, subj, label, JwText.render("reason.l2.blk.unsupported", {
					"cmd": JwText.t("cmd.kind.%d" % kind),
				}))
				add_exit(r, JwText.render("reason.exit.remove", {"residual": JwFormat.u(0)}),
						{"type": "remove_draft", "draft": draft})
				add_link(r, "command")
			elif p >= 0 and m.at("content.policy.requires_budget_review", p) == 1 and not m.review_window_open() \
					and not cat.is_project(p):
				var wq: int = m.next_review_q()
				r = make("blk.window", JwInfo.Sev.BLOCK, q, subj, label, JwText.render("reason.l2.blk.window", {
					"window_q": _q(wq), "remaining": JwFormat.quarters(maxi(wq - q, 0)),
				}))
				r["numbers"] = {"need": wq, "avail": q, "gap": maxi(wq - q, 0)}
				add_exit(r, JwText.render("reason.exit.wait", {"q": _q(wq), "window": JwText.t("reason.window.review"),
						"remaining": JwFormat.quarters(maxi(wq - q, 0)), "residual": JwFormat.u(0)}),
						{"type": "defer_draft", "draft": draft, "to_q": wq})
				_add_other_tool_exit(r, p, cat)
				add_link(r, "rule")
			else:
				var cond: String = String(ctx.get("cond_text", ""))
				if cond == "":
					cond = JwText.render("reason.precond.generic", {"subject": label})
				r = make("blk.precond", JwInfo.Sev.BLOCK, q, subj, label, cond)
				add_exit(r, JwText.render("reason.exit.remove", {"residual": JwFormat.u(0)}),
						{"type": "remove_draft", "draft": draft})
				_add_other_tool_exit(r, p, cat)
				add_link(r, "rule")
	r["reject_code"] = rc
	return r


## 同域的替代工具出口（按 docs/21 §2.4 的机制域候选集；只给名称与代价，不给推荐）。
static func _add_other_tool_exit(r: Dictionary, p: int, cat: JwCatalog) -> void:
	var alt: int = int((cat.cfg("alt_tools", {}) as Dictionary).get("P%02d" % (p + 1), -1)) \
			if cat.cfg("alt_tools", {}) is Dictionary else -1
	if alt < 0:
		return
	var pd: Dictionary = cat.policy(alt)
	add_exit(r, JwText.render("reason.exit.other_tool", {"tool": String(pd.get("label", "")),
			"cost": JwFormat.u(int(pd.get("one_off_uu", 0))), "residual": JwText.t("reason.residual.recompute")}),
			{"type": "goto_policy", "p": alt})


## 某地区最早释放的施工槽位：在建项目按计划季数匀速完工的最早季与占用者名。
static func _earliest_slot_release(reg: int, m: JwReadModel, cat: JwCatalog) -> Dictionary:
	var best_q: int = m.q + 99
	var holder: String = ""
	for row: Dictionary in m.project_rows():
		if int(row["region"]) != reg or int(row["slot_held"]) != 1:
			continue
		var cq: int = m.earliest_commission_q(row)
		if cq < best_q:
			best_q = cq
			holder = String(cat.policy(int(row["policy"])).get("label", ""))
	if holder == "":
		best_q = m.q + 1
	return {"q": best_q, "holder": holder}


## 政策目录的一句原因（折叠态即带原因，docs/20 §7.3.2）。可提交或已生效时返回 {}。
static func for_catalog(p: int, m: JwReadModel, cat: JwCatalog) -> Dictionary:
	var ctx: Dictionary = {"p": p, "draft": -1, "subject": "P%02d" % (p + 1),
			"subject_label": String(cat.policy(p).get("label", ""))}
	if cat.is_project(p):
		# 项目类走 project_launch：S02 只判施工槽位（全部地区都满才算阻断）。
		var any_free: bool = false
		var full_region: int = -1
		for reg: int in JwReadModel.R:
			if m.slots_used(reg) < m.slots_total(reg):
				any_free = true
			else:
				full_region = reg
		if m.terminated:
			return from_code(JwReadModel.RJ_RUN_TERMINATED, ctx, m, cat)
		if not any_free:
			ctx["region"] = full_region
			return from_code(JwReadModel.RJ_NO_SLOT, ctx, m, cat)
		return {}
	var el: Dictionary = m.eligibility(p, false)
	var rc: int = int(el.get("code", 0))
	if rc == 0 or rc == JwReadModel.RJ_ALREADY_ENACTED:
		return {}
	return from_code(rc, ctx, m, cat)


# ── 由试算结果构造 GAP 与 NOTE ───────────────────────────────────────────

## bundle 是 JwSession 的试算包：{runs{id → result}, drafts[], scen{…}}。
static func from_dryrun(bundle: Dictionary, drafts: Array, m: JwReadModel, cat: JwCatalog) -> Array:
	var out: Array = []
	var runs: Dictionary = bundle.get("runs", {})
	if runs.is_empty():
		return out
	var q: int = m.q
	var nod_lo: Dictionary = runs.get("nodraft_lo", {})
	var dr_lo: Dictionary = runs.get("draft_lo", nod_lo)
	var dr_hi: Dictionary = runs.get("draft_hi", runs.get("nodraft_hi", {}))
	var adv_lo: Dictionary = runs.get("adv_lo", {})
	var base_name: String = JwText.t("scen.base")
	var adv_name: String = JwText.t("scen.adverse")
	# 1 欠付（支付优先级挤出）：不利情景下界的逐季欠付高于不含草案的基线 → GAP。
	var probe: Array = [[adv_lo, adv_name], [dr_lo, base_name]]
	for pr: Array in probe:
		var run: Dictionary = pr[0]
		if run.is_empty() or not bool(run.get("ok", false)):
			continue
		var arr: PackedInt64Array = _series(run, "arrears")
		var base_arr: PackedInt64Array = _series(nod_lo, "arrears")
		var worst_gap: int = 0
		var trig: int = -1
		for t: int in arr.size():
			var b0: int = base_arr[t] if t < base_arr.size() else 0
			var d: int = arr[t] - b0 if not drafts.is_empty() else arr[t]
			if d > worst_gap:
				worst_gap = d
				if trig < 0:
					trig = q + t
		if worst_gap > 0:
			var need: int = _series_sum(run, "primary_paid") + worst_gap
			var r: Dictionary = make("gap.arrears", JwInfo.Sev.GAP, trig, "cash", JwText.t("reason.subject.cash_path"),
					JwText.render("reason.l2.gap.arrears", {"scenario": String(pr[1]), "trigger_q": _q(trig),
						"need": JwFormat.u(need), "avail": JwFormat.u(need - worst_gap), "gap": JwFormat.u(worst_gap)}))
			r["numbers"] = {"need": need, "avail": need - worst_gap, "gap": worst_gap}
			r["key"] = "gap.arrears:" + String(pr[1])
			add_exit(r, JwText.render("reason.exit.borrow", {"amount": JwFormat.u(worst_gap),
					"tenor": JwFormat.quarters(int(cat.cfg("bond_default_tenor_q", 8))),
					"residual": JwText.t("reason.residual.recompute")}), {"type": "add_bond", "amount": worst_gap})
			var big: int = _largest_draft(drafts)
			if big >= 0:
				add_exit(r, JwText.render("reason.exit.scale_down", {"scale": JwFormat.pct(500000),
						"residual": JwText.t("reason.residual.recompute")}), {"type": "scale_draft", "draft": big, "scale": 500000})
				add_exit(r, JwText.render("reason.exit.defer", {"q": _q(q + 1), "n": JwFormat.quarters(1),
						"residual": JwText.t("reason.residual.recompute")}), {"type": "defer_draft", "draft": big, "to_q": q + 1})
			# gap.defer 的合同付款一半（docs/20 §8.5；R-DEFER-01）：把分期款最大的在建项目延后一季。
			var pdf: Dictionary = _deferrable_project(m, cat)
			if not pdf.is_empty():
				add_exit(r, JwText.render("reason.exit.project_defer", {"project": String(pdf["name"]),
						"saved": JwFormat.u(int(pdf["installment"])), "fee": JwFormat.u(int(pdf["fee"])),
						"residual": JwText.t("reason.residual.recompute")}),
						{"type": "add_project_defer", "project": int(pdf["p"]), "quarters": 1, "name": String(pdf["name"])})
			add_exit(r, JwText.render("reason.exit.accept_arrears", {"gap": JwFormat.u(worst_gap), "residual": JwFormat.u(worst_gap)}),
					{"type": "accept_gap", "key": String(r["key"])})
			add_link(r, "cash")
			add_link(r, "debt")
			out.append(r)
			break
	# 2 执政结束判据：试算期内触发（只允许写规则 ID 与判据，docs/20 §7.1.5）。
	for pr2: Array in [[dr_lo, base_name], [adv_lo, adv_name]]:
		var run2: Dictionary = pr2[0]
		if run2.is_empty():
			continue
		var tq: int = int(run2.get("terminated_at", -1))
		var reason_code: int = int(run2.get("termination_reason", 0))
		if tq >= 0 and reason_code != 1:
			var r2: Dictionary = make("gap.terminal", JwInfo.Sev.GAP, tq, "politics", JwText.t("reason.subject.terminal"),
					JwText.render("reason.l2.gap.terminal", {"scenario": String(pr2[1]), "term_q": _q(tq),
						"reason_name": JwText.t("termination.%d" % reason_code),
						"rule": JwText.t("rule.termination.%d" % reason_code)}))
			r2["numbers"] = {"need": 0, "avail": 0, "gap": 0}
			r2["key"] = "gap.terminal:" + String(pr2[1])
			add_exit(r2, JwText.render("reason.exit.borrow", {"amount": JwFormat.u(_series_max(run2, "arrears")),
					"tenor": JwFormat.quarters(int(cat.cfg("bond_default_tenor_q", 8))),
					"residual": JwText.t("reason.residual.recompute")}), {"type": "add_bond", "amount": _series_max(run2, "arrears")})
			add_exit(r2, JwText.render("reason.exit.accept_arrears", {"gap": JwFormat.u(0), "residual": JwText.t("reason.residual.recompute")}),
					{"type": "accept_gap", "key": String(r2["key"])})
			add_link(r2, "politics")
			add_link(r2, "cash")
			out.append(r2)
			break
	# 3 新增借款（NOTE）：含草案与不含草案两次基线试算的四季借款差。
	if not drafts.is_empty() and not dr_lo.is_empty() and not nod_lo.is_empty():
		var d_lo: int = _series_sum(dr_lo, "new_borrowing") - _series_sum(nod_lo, "new_borrowing")
		var nod_hi: Dictionary = runs.get("nodraft_hi", nod_lo)
		var d_hi: int = _series_sum(dr_hi, "new_borrowing") - _series_sum(nod_hi, "new_borrowing")
		var d_max: int = maxi(d_lo, d_hi)
		if d_max > 0:
			var r3: Dictionary = make("note.borrow", JwInfo.Sev.NOTE, q, "debt", JwText.t("reason.subject.borrow"),
					JwText.render("reason.l2.note.borrow", {"delta": JwFormat.u(d_max), "scenario": base_name,
						"range": JwFormat.range_u(mini(d_lo, d_hi), d_max), "horizon_q": _q(q + 3)}))
			r3["numbers"] = {"need": d_max, "avail": 0, "gap": d_max}
			add_exit(r3, JwText.t("reason.exit.view_debt"), {"type": "open_ledger", "ledger": "debt"})
			add_link(r3, "debt")
			out.append(r3)
	return out


## 本季可延期、且每季分期款最大的在建项目（缺口处理器 gap.defer 的合同付款路径，R-DEFER-01）。
## 分期款按结算器口径 ceil(合同额 / 计划季数)、以剩余合同额封顶；没有可延期的项目返回空字典。
static func _deferrable_project(m: JwReadModel, cat: JwCatalog) -> Dictionary:
	var best: Dictionary = {}
	for row: Dictionary in m.project_rows():
		var dc: Dictionary = m.defer_cost(row, 1)
		if not bool(dc["allowed"]):
			continue
		var pq: int = maxi(int(row["planned_quarters"]), 1)
		@warning_ignore("integer_division")
		var inst: int = mini(int(row["remaining"]), (int(row["total"]) + pq - 1) / pq)
		if inst > 0 and (best.is_empty() or inst > int(best["installment"])):
			best = {"p": int(row["p"]), "installment": inst, "fee": int(dc["fee"]),
					"name": JwText.render("project.name", {"policy": String(cat.policy(int(row["policy"])).get("label", "")),
						"region": cat.region_label(int(row["region"])), "n": str(int(row["p"]) + 1)})}
	return best


## 草案本身的提示：不可逆支出、反馈晚于选举、主要集团反对（NOTE 不阻断）。
static func draft_notes(drafts: Array, m: JwReadModel, cat: JwCatalog) -> Array:
	var out: Array = []
	var q: int = m.q
	var irrev: int = 0
	var n_irrev: int = 0
	for i: int in drafts.size():
		var d: Dictionary = drafts[i]
		var kind: int = int(d.get("kind", 0))
		var p: int = int(d.get("p", -1))
		if kind == 1 and p >= 0:
			irrev += m.at("content.policy.toggle_cost_uu", p)
			n_irrev += 1
		elif kind == 3 and p >= 0:
			irrev += m.at("content.policy.toggle_cost_uu", p)
			n_irrev += 1
		elif kind == 4 and p >= 0:
			@warning_ignore("integer_division")
			var first: int = m.at("content.policy.cost_per_quarter_uu", p) * int(d.get("scale", JwReadModel.PPM)) / JwReadModel.PPM
			irrev += first
			n_irrev += 1
		if p >= 0 and (kind == 1 or kind == 4):
			var pd: Dictionary = cat.policy(p)
			var fb: int = q + int(pd.get("lag_max", 0))
			var ne: int = m.next_election_q()
			if ne >= 0 and fb > ne:
				var rf: Dictionary = make("note.feedback_late", JwInfo.Sev.NOTE, q, "P%02d" % (p + 1), String(pd.get("label", "")),
						JwText.render("reason.l2.note.feedback_late", {"policy": String(pd.get("label", "")),
							"lo_q": _q(q + int(pd.get("lag_min", 0))), "hi_q": _q(fb), "election_q": _q(ne),
							"gap": JwFormat.quarters(fb - ne)}))
				rf["numbers"] = {"need": fb, "avail": ne, "gap": fb - ne}
				rf["key"] = "note.feedback_late:%d" % i
				add_exit(rf, JwText.t("reason.exit.keep"), {"type": "noop"})
				add_link(rf, "rule")
				out.append(rf)
			var worst_b: int = -1
			var worst_v: int = 0
			var react: Dictionary = pd.get("reaction", {})
			for bk: Variant in react.keys():
				var v: int = int(react[bk])
				if v < worst_v:
					worst_v = v
					worst_b = cat.bloc_index(String(bk))
			if worst_b >= 0 and worst_v <= -100000:
				var ro: Dictionary = make("note.opposition", JwInfo.Sev.NOTE, q, "P%02d" % (p + 1), String(pd.get("label", "")),
						JwText.render("reason.l2.note.opposition", {"bloc": cat.bloc_label(worst_b),
							"policy": String(pd.get("label", "")), "react": JwFormat.ppt(worst_v),
							"org": JwFormat.pct(m.at("state.bloc.org_power_ppm", worst_b)),
							"stance": JwFormat.pct(m.at("state.bloc.stance_ppm", worst_b * 12 + p))}))
				ro["numbers"] = {"need": 0, "avail": 0, "gap": absi(worst_v)}
				ro["key"] = "note.opposition:%d" % i
				add_exit(ro, JwText.t("reason.exit.keep"), {"type": "noop"})
				add_exit(ro, JwText.render("reason.exit.remove", {"residual": JwFormat.u(0)}), {"type": "remove_draft", "draft": i})
				add_link(ro, "politics")
				out.append(ro)
	if n_irrev > 0 and irrev > 0:
		var r: Dictionary = make("note.irreversible", JwInfo.Sev.NOTE, q, "draft", JwText.t("reason.subject.draft"),
				JwText.render("reason.l2.note.irreversible", {"irrev": JwFormat.u(irrev), "n": str(n_irrev)}))
		r["numbers"] = {"need": irrev, "avail": 0, "gap": irrev}
		add_exit(r, JwText.t("reason.exit.keep"), {"type": "noop"})
		add_link(r, "commit")
		out.append(r)
	return out


static func _series(run: Dictionary, key: String) -> PackedInt64Array:
	var s: Dictionary = run.get("series", {})
	var v: Variant = s.get(key, PackedInt64Array())
	if v is PackedInt64Array:
		return v
	return PackedInt64Array()


static func _series_sum(run: Dictionary, key: String) -> int:
	var t: int = 0
	for x: int in _series(run, key):
		t += x
	return t


static func _series_max(run: Dictionary, key: String) -> int:
	var t: int = 0
	for x: int in _series(run, key):
		t = maxi(t, x)
	return t


static func _largest_draft(drafts: Array) -> int:
	var best: int = -1
	var best_v: int = 0
	for i: int in drafts.size():
		var d: Dictionary = drafts[i]
		var v: int = int(d.get("cost_hint", 0))
		if int(d.get("kind", 0)) == 4 and v > best_v:
			best_v = v
			best = i
	return best
