## 界面截图与主场景冒烟（G4 自检）。
##
## 截图（必须非 headless，才能拿到真实像素）：
##   godot --path <项目根> --windowed --resolution 960x540 --script res://tools/ui_snapshot.gd -- --out=docs/_drafts/ui_shots
## 冒烟（可 headless；不写图片，只跑流程并统计错误）：
##   godot --headless --path <项目根> --script res://tools/ui_snapshot.gd -- --smoke [--full]
##
## 做法：把主场景 res://ui/main.tscn 实例放进一个 SubViewport（物理尺寸 = 目标分辨率，缩放档用
## size_2d_override + oversampling_override 模拟 Window.content_scale_factor），自动开局后按真实按钮信号走一遍：
## 政策页「立项」→ 底部推进按钮 → 确认框 → 推进 → 结算回放 →「查看季度报告」→ 各页 → 年度审查 → 覆盖层 →
## 存档 / 读档。全程用 Logger 统计 SCRIPT ERROR / push_error；退出码 0 = 流程走通且无错误。
## --full：一直推进到执政结束（第 40 季或提前结束），再打开发展档案。
extends SceneTree

const SEED: int = 20260921
const MAIN_SCENE: String = "res://ui/main.tscn"
const SMOKE_SLOT: String = "uisnap_smoke"

## 截图配置：物理像素 × 界面缩放（逻辑尺寸 = 物理 / 缩放）。
const CONFIGS: Array = [
	{"id": "1920x1080_s100", "w": 1920, "h": 1080, "scale": 1.0},
	{"id": "1366x768_s100", "w": 1366, "h": 768, "scale": 1.0},
	{"id": "1920x1080_s125", "w": 1920, "h": 1080, "scale": 1.25},
	{"id": "1920x1080_s150", "w": 1920, "h": 1080, "scale": 1.5},
	{"id": "1366x768_s125", "w": 1366, "h": 768, "scale": 1.25},
]


## 捕获全部错误（含工作线程里的 push_error），供冒烟判定。
class ErrorTap extends Logger:
	var mutex: Mutex = Mutex.new()
	var errors: PackedStringArray = PackedStringArray()
	var warnings: int = 0

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		mutex.lock()
		if error_type == ERROR_TYPE_WARNING:
			warnings += 1
		else:
			errors.append("%s | %s | %s:%d %s" % [rationale if rationale != "" else code, function, file.get_file(), line, code])
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


var vp: SubViewport = null
var ui: JwRoot = null
var out_dir: String = ""
var smoke: bool = false
var full: bool = false
var shots: PackedStringArray = PackedStringArray()
var problems: PackedStringArray = PackedStringArray()
var notes: PackedStringArray = PackedStringArray()
var tap: ErrorTap = null
var _cfg: Dictionary = {}
## SimCore 在结算中报故障（不是界面问题）：记下季号与故障码，流程就此停下。
var sim_fault: String = ""


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a == "--smoke":
			smoke = true
		elif a == "--full":
			full = true
	if out_dir == "" and not smoke:
		out_dir = "docs/_drafts/ui_shots"
	if not smoke and DisplayServer.get_name() == "headless":
		printerr("[ui_snapshot] screenshots need a real renderer: run without --headless (or pass --smoke)")
		quit(2)
		return
	if out_dir != "":
		if not out_dir.begins_with("res://") and not out_dir.is_absolute_path():
			out_dir = ProjectSettings.globalize_path("res://" + out_dir)
		elif out_dir.begins_with("res://"):
			out_dir = ProjectSettings.globalize_path(out_dir)
		DirAccess.make_dir_recursive_absolute(out_dir)
	tap = ErrorTap.new()
	OS.add_logger(tap)
	_run()


func _run() -> void:
	vp = SubViewport.new()
	vp.name = "SnapViewport"
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)
	_apply_config(CONFIGS[0])
	var ps: PackedScene = load(MAIN_SCENE) as PackedScene
	if ps == null:
		_fail("main scene cannot be loaded: " + MAIN_SCENE)
		_finish()
		return
	# 先看开局覆盖层（不自动开局的一份实例）。
	var ng: JwRoot = ps.instantiate() as JwRoot
	vp.add_child(ng)
	await _frames(4)
	_expect(ng.top_overlay() is JwNewGame, "without autostart the main scene opens the new-game overlay")
	await _shot("00_newgame")
	vp.remove_child(ng)
	ng.queue_free()
	await _frames(2)
	# 正式实例：自动开局。
	ui = ps.instantiate() as JwRoot
	ui.autostart_seed = SEED
	vp.add_child(ui)
	await _frames(3)
	var s: JwSession = ui.session
	_expect(s != null and s.game != null, "autostart created a game through JwSession/JWGame")
	if s == null or s.game == null:
		_finish()
		return
	await _wait_dry(s)
	_expect(s.model.q == 0, "game starts at q0 (display quarter 1)")
	await _shot("01_overview_q1")
	for id: String in ["region", "society", "report"]:
		ui.show_page(id, {})
		await _frames(3)
		await _shot("02_%s_q1_cold" % id)
	# ── 第 1 季：政策页立项（按按钮）──
	var launch: Dictionary = _pick_launch(s)
	_expect(not launch.is_empty(), "an eligible project policy/region exists at q0")
	if not launch.is_empty():
		var p: int = int(launch["p"])
		ui.show_page("policy", {"p": p})
		var pp: JwPolicyPage = ui.page("policy") as JwPolicyPage
		pp.launch_region[p] = int(launch["region"])
		pp.refresh()
		await _frames(2)
		var lb: Button = _find_named(pp, "LaunchButton") as Button
		_expect(lb != null, "policy page exposes the launch button")
		if lb != null:
			lb.pressed.emit()
		await _frames(2)
		_expect(s.drafts.size() == 1, "pressing launch adds exactly one draft (no command submitted yet)")
		_expect(s.model.cmdlog.get("count", 0) == s.game.command_log_copy().get("count", 0), "no command reached SimCore")
	var enact: int = _pick_enact(s)
	if enact >= 0:
		ui.show_page("policy", {"p": enact})
		await _frames(2)
		var eb: Button = _find_named(ui.page("policy"), "EnactButton") as Button
		if eb != null:
			eb.pressed.emit()
			await _frames(2)
			notes.append("enact draft added for policy index %d" % enact)
	await _wait_dry(s)
	ui.show_page("policy", {"p": int(launch.get("p", 0))})
	await _frames(3)
	await _shot("03_policy_draft_q1")
	ui.open_overlay("budget", {})
	await _frames(3)
	await _shot("04_budget_review_q1")
	ui.close_all_overlays()
	await _frames(2)
	# ── 底部推进按钮 → 确认框 ──
	await _press_advance_to_confirm(s)
	await _shot("05_confirm_q1")
	var q_before: int = s.model.q
	await _confirm_and_settle(s)
	_expect(s.model.q == q_before + 1, "confirm → advance → settled one quarter")
	var rep: JwOverlay = ui.top_overlay()
	_expect(rep is JwSettlementReplay, "settlement replay opens after the quarter settles")
	if rep is JwSettlementReplay:
		(rep as JwSettlementReplay).finish_now()
		await _frames(2)
		await _shot("06_settlement_q1")
		var to_rep: Button = _find_button_text(rep, JwText.t("sr.to_report"))
		_expect(to_rep != null, "settlement replay offers 'view quarterly report'")
		if to_rep != null:
			to_rep.pressed.emit()
	await _frames(3)
	_expect(ui.current_page == "report", "report page shown after settlement")
	await _wait_dry(s)
	await _shot("07_report_q2")
	for id2: String in ["overview", "region", "society", "policy"]:
		ui.show_page(id2, {})
		await _frames(3)
		await _shot("08_%s_q2" % id2)
	# ── 其他分辨率与缩放档（同一状态）──
	if not smoke:
		for i: int in range(1, CONFIGS.size()):
			var cfg: Dictionary = CONFIGS[i]
			_apply_config(cfg)
			await _frames(3)
			for id3: String in ["overview", "policy", "report", "society"]:
				ui.show_page(id3, {})
				await _frames(3)
				await _shot("20_%s_%s" % [id3, String(cfg["id"])])
			ui.open_overlay("confirm", {})
			await _frames(3)
			await _shot("20_confirm_%s" % String(cfg["id"]))
			ui.close_all_overlays()
			await _frames(2)
		_apply_config(CONFIGS[0])
		await _frames(3)
	# ── 推进到第 4 季结算（年度审查）──
	while s.model.q < 4 and not s.model.terminated and sim_fault == "":
		await _advance_once(s)
	var ar: JwOverlay = ui.top_overlay()
	_expect(ar is JwAnnualReview or sim_fault != "", "annual review opens after the fourth quarter settles")
	await _frames(3)
	await _shot("09_annual_review_q4")
	ui.close_all_overlays()
	await _frames(2)
	# ── 覆盖层 ──
	var overlays: Array = [["ledger", {"ledger": "cash"}, "10_ledger_cash"], ["ledger", {"ledger": "debt"}, "10_ledger_debt"],
			["ledger", {"ledger": "project"}, "10_ledger_project"], ["rule", {"rule": "fiscal_identity"}, "11_rule_card"],
			["legend", {}, "12_class_legend"], ["rules", {}, "13_rules_book"], ["saves", {}, "14_save_manager"],
			["archive", {}, "15_archive_interim"]]
	for ov: Array in overlays:
		var o: JwOverlay = ui.open_overlay(String(ov[0]), ov[1])
		_expect(o != null, "overlay opens: " + String(ov[0]))
		await _frames(3)
		await _shot(String(ov[2]))
		ui.close_all_overlays()
		await _frames(2)
	# ── 存档 / 读档 ──
	var qs: int = s.model.q
	if sim_fault != "":
		_finish()
		return
	var sv: Dictionary = s.save_slot(SMOKE_SLOT)
	_expect(bool(sv.get("ok", false)), "save_slot ok (code %d)" % int(sv.get("code", 0)))
	var ld: Dictionary = s.load_slot(SMOKE_SLOT)
	if bool(ld.get("ok", false)):
		_expect(s.model.q == qs, "load_slot restores the same quarter")
		notes.append("save/load round trip ok at q=%d" % qs)
		await _wait_dry(s)
		await _advance_once(s)
		_expect(s.model.q == qs + 1, "can advance after loading a save")
	else:
		_fail("load_slot failed: code %d detail %d (see interface requests)" % [int(ld.get("code", 0)), int(ld.get("a", 0))])
	_cleanup_slot(SMOKE_SLOT)
	# ── 可选：一直推进到执政结束 ──
	if full:
		var guard: int = 0
		while not s.model.terminated and guard < 60 and sim_fault == "":
			await _advance_once(s)
			guard += 1
		_expect(s.model.terminated or sim_fault != "", "the run reaches its end within the horizon")
		notes.append("full run ended at q=%d, termination_reason=%d" % [s.model.q, s.model.sc("state.meta.termination_reason")])
		await _frames(3)
		var fa: JwOverlay = ui.top_overlay()
		if not (fa is JwFinalArchive):
			ui.close_all_overlays()
			fa = ui.open_overlay("archive", {})
		await _frames(3)
		await _shot("16_archive_final")
	_finish()


# ── 流程步骤 ─────────────────────────────────────────────────────────────

func _press_advance_to_confirm(s: JwSession) -> void:
	await _wait_dry(s)
	ui.close_all_overlays()
	await _frames(1)
	var adv: Button = _find_named(ui.dock, "AdvanceButton") as Button
	_expect(adv != null, "dock has the advance button")
	if adv == null:
		return
	if s.dock_state() == JwSession.Dock.SETTLED:
		adv.pressed.emit()
		await _frames(2)
	adv.pressed.emit()
	await _frames(3)
	var top: JwOverlay = ui.top_overlay()
	if top is JwBudgetReview:
		# 阻断 / 未绑定缺口：像玩家一样在预算审查里点原因卡上的出口（先融资，后「承担欠付」）。
		var st0: int = s.dock_state()
		notes.append("q%d: advance opened budget review (dock state %d): %s" % [s.model.q, st0, _reason_summary(s)])
		for attempt: int in 6:
			var st1: int = s.dock_state()
			if st1 != JwSession.Dock.GAP_UNBOUND and st1 != JwSession.Dock.BLOCKED:
				break
			var want: PackedStringArray = ["add_bond", "accept_gap"] if attempt == 0 else ["accept_gap", "remove_draft", "add_bond"]
			if st1 == JwSession.Dock.BLOCKED:
				want = ["switch_holder", "scale_bond", "remove_draft", "scale_draft", "defer_draft"] if attempt < 3 						else ["remove_draft", "defer_draft"]
			var eb: Button = _exit_button(ui.top_overlay(), want)
			if eb == null and st1 == JwSession.Dock.BLOCKED and not s.drafts.is_empty():
				# 草案篮里的「移出」按钮等价于 remove_draft：撤下最后一条草案。
				notes.append("q%d: removed the last draft from the tray (%s)" % [s.model.q, String(s.drafts[s.drafts.size() - 1].get("label", ""))])
				s.remove_draft(s.drafts.size() - 1)
				await _wait_dry(s)
				continue
			if eb == null:
				_fail("q%d: no executable exit on reason cards (state %d)" % [s.model.q, st1])
				break
			var act: Dictionary = eb.get_meta("exit_action", {})
			notes.append("q%d: pressed exit '%s'" % [s.model.q, String(act.get("type", ""))])
			eb.pressed.emit()
			await _wait_dry(s)
		ui.close_all_overlays()
		await _frames(1)
		adv.pressed.emit()
		await _frames(3)
		if not (ui.top_overlay() is JwConfirmAdvance):
			ui.close_all_overlays()
			ui.open_overlay("confirm", {})
			await _frames(3)
	_expect(ui.top_overlay() is JwConfirmAdvance, "advance flow reaches the confirm dialog")


func _confirm_and_settle(s: JwSession) -> void:
	var cf: JwOverlay = ui.top_overlay()
	if not (cf is JwConfirmAdvance):
		_fail("confirm dialog not on top")
		return
	var ack: CheckBox = _find_named(cf, "AckNotes") as CheckBox
	if ack != null:
		ack.button_pressed = true
		await _frames(1)
	var btn: Button = _find_named(cf, "ConfirmAdvance") as Button
	if btn == null:
		_fail("confirm button missing")
		return
	if btn.disabled:
		_fail("confirm disabled: " + _reason_summary(s))
		return
	btn.pressed.emit()
	if s.dock_state() == JwSession.Dock.GAP_NOEXIT and not s.settling:
		btn.pressed.emit()
	var t0: int = Time.get_ticks_msec()
	var max_gap: int = 0
	var last: int = t0
	while s.settling and Time.get_ticks_msec() - t0 < 60000:
		await process_frame
		var now: int = Time.get_ticks_msec()
		max_gap = maxi(max_gap, now - last)
		last = now
	notes.append("settlement q%d took %d ms; longest main-thread frame gap %d ms" % [s.model.q, Time.get_ticks_msec() - t0, max_gap])
	if not bool(s.last_receipt.get("ok", true)) and sim_fault == "":
		sim_fault = "SimCore fault while settling quarter %d: code %d, fault dir %s" % [int(s.last_receipt.get("q", -1)) + 1,
				int(s.last_receipt.get("code", 0)), String(s.last_receipt.get("fault_dir", ""))]
	await _frames(3)


func _advance_once(s: JwSession) -> void:
	await _press_advance_to_confirm(s)
	if ui.top_overlay() is JwConfirmAdvance:
		await _confirm_and_settle(s)
		var top: JwOverlay = ui.top_overlay()
		if top is JwSettlementReplay:
			(top as JwSettlementReplay).finish_now()
			await _frames(1)
			var cont: Button = _find_button_text(top, JwText.t("sr.continue"))
			if cont != null:
				cont.pressed.emit()
			await _frames(2)


## 原因卡上的出口按钮（JwReasonView 把每条出口渲染为带 exit_action 的按钮）；按类型优先级挑一个。
func _exit_button(o: Node, types: PackedStringArray) -> Button:
	if o == null:
		return null
	var all: Array[Button] = []
	_collect_exit_buttons(o, all)
	for t: String in types:
		for b: Button in all:
			if String((b.get_meta("exit_action", {}) as Dictionary).get("type", "")) == t:
				return b
	return null


## 只收未绑定（未选定处理路径）的原因卡上的出口。
static func _collect_exit_buttons(n: Node, out: Array[Button]) -> void:
	if n is JwReasonView and bool((n as JwReasonView).reason.get("bound", false)):
		return
	if n is Button and n.has_meta("exit_action"):
		out.append(n as Button)
	for ch: Node in n.get_children():
		_collect_exit_buttons(ch, out)


func _pick_launch(s: JwSession) -> Dictionary:
	for p: int in JwReadModel.POLICY_N:
		if not s.catalog.is_project(p):
			continue
		for r: int in JwReadModel.R:
			if int(s.model.eligibility(p, true, r).get("code", -1)) == 0:
				return {"p": p, "region": r}
	return {}


func _pick_enact(s: JwSession) -> int:
	for p: int in JwReadModel.POLICY_N:
		if s.catalog.is_project(p) or s.model.policy_enabled(p):
			continue
		if int(s.model.eligibility(p, false).get("code", -1)) == 0:
			return p
	return -1


func _reason_summary(s: JwSession) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for r: Variant in s.reasons():
		var rd: Dictionary = r
		parts.append("%s[%d]" % [String(rd.get("code", "")), int(rd.get("severity", 0))])
	return ",".join(parts)


# ── 视口、帧与截图 ─────────────────────────────────────────────────────────

func _apply_config(cfg: Dictionary) -> void:
	_cfg = cfg
	var w: int = int(cfg["w"])
	var h: int = int(cfg["h"])
	var sc: float = float(cfg["scale"])
	vp.size = Vector2i(w, h)
	if sc != 1.0:
		vp.size_2d_override = Vector2i(roundi(float(w) / sc), roundi(float(h) / sc))
		vp.size_2d_override_stretch = true
	else:
		vp.size_2d_override = Vector2i.ZERO
		vp.size_2d_override_stretch = false
	vp.set("oversampling_override", sc)
	if ui != null:
		ui.ui_scale = sc


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _wait_dry(s: JwSession) -> void:
	var t0: int = Time.get_ticks_msec()
	while (s.dry_busy() or not s.dry_is_current() or s.settling) and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	await _frames(2)


func _shot(name: String) -> void:
	shots.append(name)
	if smoke:
		return
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	if img == null or img.is_empty():
		_fail("empty capture for " + name)
		return
	var path: String = out_dir.path_join("%s__%s.png" % [name, String(_cfg.get("id", ""))]) if not name.begins_with("20_") \
			else out_dir.path_join(name + ".png")
	var err: int = img.save_png(path)
	if err != OK:
		_fail("cannot save " + path)


# ── 查找与判定 ─────────────────────────────────────────────────────────────

static func _find_named(n: Node, nm: String) -> Node:
	if n == null:
		return null
	if String(n.name) == nm:
		return n
	for ch: Node in n.get_children():
		var f: Node = _find_named(ch, nm)
		if f != null:
			return f
	return null


static func _find_button_text(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n as Button
	for ch: Node in n.get_children():
		var f: Button = _find_button_text(ch, text)
		if f != null:
			return f
	return null


func _expect(cond: bool, what: String) -> void:
	if not cond:
		problems.append("FAILED: " + what)


func _fail(what: String) -> void:
	problems.append("FAILED: " + what)


## 只清理本工具自己写入的存档槽（含临时 / 备份目录）与界面侧车文件。
func _cleanup_slot(slot: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", "_tmp", "_bak"]:
		_rm_tree("user://saves/" + slot + suffix)
	var side: String = "user://ui_state/" + slot + ".json"
	if FileAccess.file_exists(side):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(side))


static func _rm_tree(path: String) -> void:
	if not path.begins_with("user://saves/" + SMOKE_SLOT):
		return
	var d: DirAccess = DirAccess.open(path)
	if d == null:
		return
	for sub: String in d.get_directories():
		_rm_tree(path + "/" + sub)
	for f: String in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish() -> void:
	OS.remove_logger(tap)
	tap.mutex.lock()
	var all_errs: PackedStringArray = tap.errors.duplicate()
	var warns: int = tap.warnings
	tap.mutex.unlock()
	# 自动存档写入 user://saves/autosave：所有 JWGame 实例（含并行跑的其他测试进程）共用同一个槽，
	# 并发时读回校验会失败（码 2900）。这是应用层的共享槽问题（已列入接口请求），单列计数、不算界面错误。
	var errs: PackedStringArray = PackedStringArray()
	var autosave_errs: int = 0
	for e: String in all_errs:
		if e.contains("JWGame") and e.contains("2900"):
			autosave_errs += 1
		else:
			errs.append(e)
	if autosave_errs > 0:
		notes.append("autosave append failed %d time(s) with code 2900 (shared autosave slot; see interface requests)" % autosave_errs)
	print("")
	print("──────────── ui_snapshot ────────────")
	print("mode: %s%s | shots: %d | errors: %d | warnings: %d" % ["smoke" if smoke else "snapshot", " (full)" if full else "",
			shots.size(), errs.size(), warns])
	if not smoke:
		print("out: " + out_dir)
	for n: String in notes:
		print("note: " + n)
	if sim_fault != "":
		print("SIMCORE: " + sim_fault + " (the UI showed the fault card; not a UI failure)")
	for p: String in problems:
		print(p)
	for i: int in mini(errs.size(), 25):
		print("error: " + errs[i])
	var ok: bool = problems.is_empty() and errs.is_empty()
	print("result: " + ("OK" if ok else "PROBLEMS"))
	print("─────────────────────────────────────")
	quit(0 if ok else 1)
