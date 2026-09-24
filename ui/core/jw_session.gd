## 界面会话：持有 JWGame、草案篮、试算、原因清单、底部固定区状态机、推进与存档。
##
## 分层（计划书 §12）：本类只经 JWGame 读视图、投命令；草案在界面侧暂存，确认推进时才逐条
## submit_command，然后投推进标记并 advance_quarter —— 命令缓冲是只追加的，提前提交的草案收不回。
## 试算（docs/20 §5.5 TH-3）：在工作线程上跑 JWGame.dry_run_exec，带请求签名，过期结果丢弃，
## 重算期间保留上次结果并标注「重算中」；无场景树时（无界面测试）走同步路径。
class_name JwSession
extends Node

signal state_changed()
signal draft_changed()
signal dryrun_changed()
signal settlement_started()
signal settlement_finished(receipt: Dictionary)
signal navigate_requested(page: String, ctx: Dictionary)
signal overlay_requested(overlay: String, ctx: Dictionary)
signal ui_event(name: String, args: Dictionary)

## 底部固定区状态（docs/20 §6.2）。
enum Dock { IDLE, DRAFT, WARN, GAP_UNBOUND, GAP_BOUND, GAP_NOEXIT, BLOCKED, SETTLING, SETTLED }

const CONTENT_ROOT: String = "res://content"
const UI_STATE_DIR: String = "user://ui_state/"
const AUTOSAVE_SLOT: String = "autosave"
const THROTTLE_MS: int = 200

## 命令码（docs/11 §6.1；与 JWCommands.Kind 同值，tests/ui 核对）。
const K_ENACT: int = 1
const K_SET_PARAMS: int = 2
const K_REPEAL: int = 3
const K_LAUNCH: int = 4
const K_CANCEL: int = 5
const K_DEFER: int = 6
const K_ISSUE_BOND: int = 8
const K_RESTRUCTURE: int = 9
const K_GOAL: int = 12
## M2 的五条命令（R-RESEARCH-01 / R-METHOD-01 / R-TRADE-01 / R-EVENTCHOICE-01）。
const K_RESEARCH: int = 13
const K_BUILD: int = 14
const K_RETROFIT: int = 15
const K_TRADE: int = 16
const K_EVENT_CHOICE: int = 17
const K_ADVANCE: int = 99

var game: JWGame = null
var model: JwReadModel = JwReadModel.new()
var catalog: JwCatalog = JwCatalog.new()
var drafts: Array[Dictionary] = []
var deferred: Array[Dictionary] = []
var gap_bindings: Dictionary = {}
## 本局已打开过定义卡的术语（docs/20 §10.4 术语首见：看过即消「新」角标）。开新局或读档时清空。
var seen_terms: Dictionary = {}
var history: Array[Dictionary] = []
var expectations: Dictionary = {}
var last_receipt: Dictionary = {}
var dry: Dictionary = {}
var seed_value: int = 0
var mandate_goal: int = -1
var settling: bool = false
var settled_flag: bool = false
var read_only: bool = false
var events: Array[Dictionary] = []
var onboarding: Dictionary = {}
var last_error: Dictionary = {}
var telemetry: bool = false
var current_slot: String = ""

var _t0_ms: int = 0
var _dry_busy: bool = false
var _dry_pending: bool = false
var _dry_due_ms: int = 0
var _task_id: int = -1
var _task_sig: String = ""
var _task_out: Dictionary = {}
var _task_meta: Dictionary = {}
var _sync_mode: bool = false
## 结算任务（docs/20 §5.5 TH-1：季度结算在工作线程一次跑完，主线程只回放）。
var _adv_task: int = -1
var _adv_box: Dictionary = {}
var _adv_ctx: Dictionary = {}
## 本季账本行按结算步计数（结算完成时在主线程缓存；结算进行中界面不读活账本）。
var step_counts: PackedInt64Array = PackedInt64Array()


func _init() -> void:
	catalog.load_all()
	JwText.ensure_loaded()
	_t0_ms = Time.get_ticks_msec()
	telemetry = JwScale.cmd_value("--ui-telemetry-local") != "" or OS.get_cmdline_user_args().has("--ui-telemetry-local")


func has_game() -> bool:
	return game != null


# ── 开局、读档、存档 ─────────────────────────────────────────────────────

## 开新局。goal ∈ {0,1,2} 时把「选择任期目标」放进第 1 季草案（命令 12 只在 q == 0 受理）。
func start_new(seed_v: int, goal: int = -1, scenario: String = "") -> Dictionary:
	if settling:
		return {"ok": false, "code": JwReadModel.RJ_PHASE_BUSY, "a": 0, "b": 0}
	_wait_dryrun()
	if scenario != "":
		use_scenario(scenario)
	var g: JWGame = JWGame.new()
	var r: RefCounted = g.new_game(_content_spec(), seed_v, catalog.horizon_q())
	var rr: Dictionary = res(r)
	if not bool(rr["ok"]):
		last_error = rr
		return rr
	game = g
	seed_value = seed_v
	mandate_goal = goal
	read_only = false
	settled_flag = false
	current_slot = ""
	model.bind(game)
	model.refresh()
	_cache_step_counts()
	drafts.clear()
	deferred.clear()
	gap_bindings.clear()
	seen_terms.clear()
	history.clear()
	expectations.clear()
	events.clear()
	last_receipt = {}
	dry = {}
	onboarding = {"enabled": true, "skipped_at_q": -1, "steps": {}}
	if goal >= 0:
		add_draft({"kind": K_GOAL, "args": _args([goal]), "p": -1, "goal": goal,
				"label": JwText.render("draft.label.goal", {"goal": JwText.t("mandate_goal.%d" % goal)})}, false)
	history.append(_snapshot(-1))
	# 自动保存只追加不建槽（JWSaves.autosave_append）：开局先建一个 autosave 槽，之后每季追加。
	var sv: Dictionary = res(game.save_game(AUTOSAVE_SLOT))
	if not bool(sv["ok"]):
		last_error = sv
	state_changed.emit()
	request_dryrun(true)
	log_event("ev.page_shown", {"page_id": "page.overview"})
	return rr


func save_slot(slot: String) -> Dictionary:
	if game == null or settling:
		return {"ok": false, "code": JwReadModel.RJ_PHASE_BUSY if settling else -1}
	_wait_dryrun()
	var rr: Dictionary = res(game.save_game(slot))
	if bool(rr["ok"]):
		current_slot = slot
		_write_side_car(slot)
	return rr


func load_slot(slot: String) -> Dictionary:
	if settling:
		return {"ok": false, "code": JwReadModel.RJ_PHASE_BUSY, "a": 0, "b": 0, "slot": slot}
	_wait_dryrun()
	var g: JWGame = game
	if g == null:
		g = JWGame.new()
		var r0: Dictionary = res(g.new_game(_content_spec(), 1, catalog.horizon_q()))
		if not bool(r0["ok"]):
			return r0
	var rr: Dictionary = res(g.load_game(slot))
	rr["slot"] = slot
	if not bool(rr["ok"]):
		last_error = rr
		return rr
	# 存档可能属于另一个剧本（JWGame.load_game 已按 manifest 换了内容包），目录跟着换。
	var sid: String = g.view().scenario_id()
	if sid.begins_with("scenario."):
		use_scenario(sid.substr(9))
	game = g
	read_only = g.read_only_mode
	current_slot = slot
	model.bind(game)
	model.refresh()
	_cache_step_counts()
	drafts.clear()
	gap_bindings.clear()
	seen_terms.clear()
	dry = {}
	_read_side_car(slot)
	state_changed.emit()
	request_dryrun(true)
	return rr


## 切换内容目录到另一个剧本（R-SCENARIO-01）。同名不重载。
func use_scenario(name: String) -> void:
	if name == "" or name == catalog.scenario_name:
		return
	var c: JwCatalog = JwCatalog.new()
	c.scenario_name = name
	c.load_all()
	catalog = c


## 交给 JWGame 的内容根：旧剧本不带后缀，其他剧本带 `#<name>`。
func _content_spec() -> String:
	return CONTENT_ROOT if catalog.scenario_name == "chengwan" else CONTENT_ROOT + "#" + catalog.scenario_name


func list_saves() -> Array[Dictionary]:
	if game == null:
		var g: JWGame = JWGame.new()
		return g.list_save_slots()
	return game.list_save_slots()


func _write_side_car(slot: String) -> void:
	DirAccess.make_dir_recursive_absolute(UI_STATE_DIR)
	var d: Dictionary = {"schema_version": 1, "history": history, "expectations": expectations,
			"deferred": deferred, "onboarding": onboarding, "mandate_goal": mandate_goal,
			"seed": seed_value}
	var f: FileAccess = FileAccess.open(UI_STATE_DIR + slot + ".json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_jsonable(d)))
		f.close()


func _read_side_car(slot: String) -> void:
	history.clear()
	expectations.clear()
	deferred.clear()
	var path: String = UI_STATE_DIR + slot + ".json"
	if not FileAccess.file_exists(path):
		history.append(_snapshot(-1))
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or int((parsed as Dictionary).get("schema_version", 0)) != 1:
		history.append(_snapshot(-1))
		return
	var d: Dictionary = parsed
	for h: Variant in d.get("history", []):
		history.append(_ints(h))
	var ex: Dictionary = d.get("expectations", {})
	for k: Variant in ex.keys():
		expectations[str(k)] = _ints(ex[k])
	for df: Variant in d.get("deferred", []):
		deferred.append(_ints(df))
	onboarding = d.get("onboarding", onboarding)
	mandate_goal = int(d.get("mandate_goal", -1))
	seed_value = int(d.get("seed", 0))


# ── 草案篮 ─────────────────────────────────────────────────────────────

## 草案：{kind, args(6 槽), p, region, scale, amount, label, cost_hint}
func add_draft(d: Dictionary, recalc: bool = true) -> void:
	if not d.has("args"):
		d["args"] = _args([])
	drafts.append(d)
	log_event("ev.draft_added", {"kind": int(d.get("kind", 0)), "p": int(d.get("p", -1))})
	draft_changed.emit()
	if recalc:
		request_dryrun()


func remove_draft(i: int) -> void:
	if i < 0 or i >= drafts.size():
		return
	drafts.remove_at(i)
	draft_changed.emit()
	request_dryrun()


func replace_draft(i: int, d: Dictionary) -> void:
	if i < 0 or i >= drafts.size():
		return
	drafts[i] = d
	draft_changed.emit()
	request_dryrun()


func clear_drafts() -> void:
	drafts.clear()
	gap_bindings.clear()
	draft_changed.emit()
	request_dryrun()


## 改期：把草案移入「下季待办」（草案层的改期，不提交任何命令；项目合同延期是命令 6，见 draft_project_defer）。
func defer_draft(i: int, to_q: int) -> void:
	if i < 0 or i >= drafts.size():
		return
	var d: Dictionary = drafts[i]
	d["deferred_to_q"] = to_q
	deferred.append(d)
	drafts.remove_at(i)
	log_event("ev.draft_deferred", {"to_q": to_q})
	draft_changed.emit()
	request_dryrun()


func restore_deferred(i: int) -> void:
	if i < 0 or i >= deferred.size():
		return
	var d: Dictionary = deferred[i]
	d.erase("deferred_to_q")
	deferred.remove_at(i)
	add_draft(d)


static func _args(vals: Array) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(6)
	a.fill(0)
	for i: int in mini(vals.size(), 6):
		a[i] = int(vals[i])
	return a


## 草案构造器（参数槽布局见 systems/commands.gd 顶部注释）。
func draft_enact(p: int, params: PackedInt64Array, funding: int) -> Dictionary:
	var pd: Dictionary = catalog.policy(p)
	return {"kind": K_ENACT, "args": _args([p, params[0], params[1], params[2], params[3], funding]),
			"p": p, "label": JwText.render("draft.label.enact", {"policy": String(pd.get("label", ""))}),
			"cost_hint": int(pd.get("one_off_uu", 0))}


func draft_set_params(p: int, params: PackedInt64Array) -> Dictionary:
	var pd: Dictionary = catalog.policy(p)
	return {"kind": K_SET_PARAMS, "args": _args([p, params[0], params[1], params[2], params[3]]),
			"p": p, "label": JwText.render("draft.label.set_params", {"policy": String(pd.get("label", ""))})}


func draft_repeal(p: int) -> Dictionary:
	var pd: Dictionary = catalog.policy(p)
	return {"kind": K_REPEAL, "args": _args([p]), "p": p,
			"label": JwText.render("draft.label.repeal", {"policy": String(pd.get("label", ""))})}


func draft_launch(p: int, region: int, scale_ppm: int, funding: int) -> Dictionary:
	var pd: Dictionary = catalog.policy(p)
	@warning_ignore("integer_division")
	var total: int = int(pd.get("one_off_uu", 0)) * scale_ppm / JwReadModel.PPM
	return {"kind": K_LAUNCH, "args": _args([p, region, scale_ppm, funding]), "p": p,
			"region": region, "scale": scale_ppm,
			"label": JwText.render("draft.label.launch", {"policy": String(pd.get("label", "")),
				"region": catalog.region_label(region), "scale": JwFormat.pct(scale_ppm)}),
			"cost_hint": total}


## R-CAP-01：命令参数是项目的稳定实体号；草案另记本季行号 project，只用于界面内的行匹配。
## M2：设定研究方向（命令 13）。
func draft_research(tech: int, label_text: String) -> Dictionary:
	return {"kind": K_RESEARCH, "args": _args([tech]), "p": -1, "tech": tech,
			"label": JwText.render("draft.label.research", {"tech": label_text})}


## M2：新建建筑（命令 14）。cost_hint 让确认框的四季现金预测把它算进去。
func draft_build(building_type: int, region: int, owner: int, method: int, label_text: String,
		cost_uu: int) -> Dictionary:
	return {"kind": K_BUILD, "args": _args([building_type, region, owner, method]), "p": -1,
			"building": building_type, "region": region, "owner": owner, "method": method,
			"cost_hint": cost_uu,
			"label": JwText.render("draft.label.build", {"building": label_text,
				"region": catalog.region_label(region),
				"owner": JwText.t("ind.owner.%d" % owner)})}


## M2：改造建筑堆的生产方式（命令 15）。
func draft_retrofit(stack_entity: int, method: int, label_text: String, method_text: String,
		cost_uu: int) -> Dictionary:
	return {"kind": K_RETROFIT, "args": _args([stack_entity, method]), "p": -1,
			"stack": stack_entity, "method": method, "cost_hint": cost_uu,
			"label": JwText.render("draft.label.retrofit", {"building": label_text,
				"method": method_text})}


## M2：贸易安排（命令 16）。
func draft_trade(partner: int, mode: int, up: int, label_text: String) -> Dictionary:
	return {"kind": K_TRADE, "args": _args([partner, mode, up]), "p": -1, "partner": partner,
			"label": JwText.render("draft.label.trade", {"partner": label_text,
				"mode": JwText.t("ind.trade.mode.%d" % mode),
				"dir": JwText.t("ind.trade.up.%d" % up)})}


## M2：记下对某条选择型事件的选择（命令 17；本身没有经济效果）。
func draft_event_choice(event: int, option: int, label_text: String) -> Dictionary:
	return {"kind": K_EVENT_CHOICE, "args": _args([event, option]), "p": -1, "event": event,
			"option": option,
			"label": JwText.render("draft.label.event_choice", {"option": label_text})}


## R-EVENTCHOICE-01 / M2 审阅 G1：本季草案篮里是否已经为事件 e 选过选项（返回选项下标，−1 == 没有）。
func event_choice_drafted(e: int) -> int:
	for d: Dictionary in drafts:
		if int(d.get("kind", -1)) == K_EVENT_CHOICE and int(d.get("event", -1)) == e:
			return int(d.get("option", -1))
	return -1


## 选一个事件选项：把选项预填的普通命令（kind == 0 表示「不发命令，现状照旧」）连同命令 17 放进草案篮。
## 同一事件同一季只能选一次；要改就先从草案篮里撤掉。
func choose_event_option(e: int, option: int) -> void:
	if event_choice_drafted(e) >= 0:
		return
	var choices: Array = catalog.event_choices.get(e, [])
	if option < 0 or option >= choices.size():
		return
	var c: Dictionary = choices[option]
	var label_text: String = String(c.get("label_zh", ""))
	var dc: Dictionary = c.get("draft_command", {})
	var k: int = int(dc.get("kind", 0))
	if k > 0:
		var args: Array = dc.get("args", [])
		add_draft({"kind": k, "args": _args(args), "p": -1, "event": -1,
				"label": JwText.render("draft.label.event_command", {"option": label_text})}, false)
	add_draft(draft_event_choice(e, option, label_text))


func draft_cancel(project: int, label_text: String) -> Dictionary:
	return {"kind": K_CANCEL, "args": _args([model.project_entity(project)]), "p": -1, "project": project,
			"label": JwText.render("draft.label.cancel", {"project": label_text})}


## 项目延期（命令 6，docs/18 R-DEFER-01）：quarters 季内不付款、不推进，槽位照占；赔偿当季付清。
func draft_project_defer(project: int, quarters: int, label_text: String) -> Dictionary:
	return {"kind": K_DEFER, "args": _args([model.project_entity(project), quarters]), "p": -1, "project": project,
			"quarters": quarters, "label": JwText.render("draft.label.project_defer",
				{"project": label_text, "quarters": JwFormat.quarters(quarters)})}


func draft_bond(amount: int, tenor_q: int, holder: int) -> Dictionary:
	return {"kind": K_ISSUE_BOND, "args": _args([amount, tenor_q, holder]), "p": -1,
			"amount": amount, "tenor": tenor_q, "holder": holder,
			"label": JwText.render("draft.label.bond", {"amount": JwFormat.u(amount),
				"tenor": JwFormat.quarters(tenor_q), "holder": JwText.t("holder.%d" % holder)}),
			"cost_hint": 0}


# ── 试算 ───────────────────────────────────────────────────────────────

func draft_signature() -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append(str(model.q))
	for d: Dictionary in drafts:
		parts.append(str(int(d.get("kind", 0))) + ":" + str(d.get("args", PackedInt64Array())))
	return "|".join(parts)


func dry_is_current() -> bool:
	return not dry.is_empty() and String(dry.get("sig", "")) == draft_signature()


func dry_busy() -> bool:
	return _dry_busy or _dry_pending


## 请求重算（节流 200 ms；now = true 立即开始）。无场景树时同步执行。
func request_dryrun(now: bool = false) -> void:
	if game == null or model.terminated or settling:
		return
	if not is_inside_tree() or _sync_mode:
		compute_dryrun_sync()
		return
	_dry_pending = true
	_dry_due_ms = Time.get_ticks_msec() + (0 if now else THROTTLE_MS)
	dryrun_changed.emit()


func set_sync_mode(v: bool) -> void:
	_sync_mode = v


func _runs_plan() -> Array[Dictionary]:
	var base: Dictionary = catalog.scenario_def("base")
	var adv: Dictionary = catalog.scenario_def("adverse")
	var plan: Array[Dictionary] = []
	var has_draft: bool = not drafts.is_empty()
	plan.append({"id": "nodraft_lo", "draft": false, "shock": base.get("shock_lo", [0, 0, 0])})
	plan.append({"id": "nodraft_hi", "draft": false, "shock": base.get("shock_hi", [0, 0, 0])})
	if has_draft:
		plan.append({"id": "draft_lo", "draft": true, "shock": base.get("shock_lo", [0, 0, 0])})
		plan.append({"id": "draft_hi", "draft": true, "shock": base.get("shock_hi", [0, 0, 0])})
	plan.append({"id": "adv_lo", "draft": has_draft, "shock": adv.get("shock_lo", [0, 0, 0])})
	plan.append({"id": "adv_hi", "draft": has_draft, "shock": adv.get("shock_hi", [0, 0, 0])})
	return plan


func _draft_kinds() -> PackedInt64Array:
	var k: PackedInt64Array = PackedInt64Array()
	for d: Dictionary in drafts:
		k.append(int(d.get("kind", 0)))
	return k


func _draft_args() -> Array:
	var out: Array = []
	for d: Dictionary in drafts:
		out.append(d.get("args", _args([])))
	return out


static func _shock_arr(v: Variant) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	if v is Array:
		for x: Variant in v as Array:
			out.append(int(x))
	return out


## 同步试算（测试与无场景树时用）。
func compute_dryrun_sync() -> Dictionary:
	if game == null or settling:
		return dry
	_wait_dryrun()
	var snap: Dictionary = game.dry_run_snapshot()
	var out: Dictionary = {}
	var kinds: PackedInt64Array = _draft_kinds()
	var args: Array = _draft_args()
	var n_q: int = int(catalog.cfg("preview_quarters", 4))
	var t0: int = Time.get_ticks_msec()
	for run: Dictionary in _runs_plan():
		var use: bool = bool(run["draft"])
		out[String(run["id"])] = game.dry_run_exec(snap, kinds if use else PackedInt64Array(),
				args if use else [], n_q, _shock_arr(run["shock"]))
	_finish_dryrun(draft_signature(), out, Time.get_ticks_msec() - t0)
	return dry


func _start_dryrun() -> void:
	_dry_pending = false
	if game == null or settling:
		return
	var kinds: PackedInt64Array = _draft_kinds()
	var args: Array = _draft_args()
	var plan: Array[Dictionary] = _runs_plan()
	var n_q: int = int(catalog.cfg("preview_quarters", 4))
	_task_sig = draft_signature()
	_task_out = {}
	_task_meta = {"t0": Time.get_ticks_msec()}
	_dry_busy = true
	var g: JWGame = game
	var out_ref: Dictionary = _task_out
	# 真实状态的快照也在工作线程里取（只读；试算进行中主线程不写真实状态，推进与读档都先等本任务结束）。
	_task_id = WorkerThreadPool.add_task(func() -> void:
		var snap: Dictionary = g.dry_run_snapshot()
		for run: Dictionary in plan:
			var use: bool = bool(run["draft"])
			out_ref[String(run["id"])] = g.dry_run_exec(snap, kinds if use else PackedInt64Array(),
					args if use else [], n_q, JwSession._shock_arr(run["shock"])), false,
			"jw_dryrun")
	dryrun_changed.emit()


func _wait_dryrun() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		_dry_busy = false
		_finish_dryrun(_task_sig, _task_out, Time.get_ticks_msec() - int(_task_meta.get("t0", 0)))


## 退出场景树（关窗、换场景）前等工作线程上的试算与结算收尾，避免引擎拆除时线程仍在跑。
func _exit_tree() -> void:
	if _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		_dry_busy = false
	if _adv_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_adv_task)
		_adv_task = -1


func _process(_delta: float) -> void:
	if _adv_task >= 0 and WorkerThreadPool.is_task_completed(_adv_task):
		WorkerThreadPool.wait_for_task_completion(_adv_task)
		_adv_task = -1
		_finish_advance(_adv_box.get("r", {"ok": false, "code": -1, "a": 0, "b": 0}))
	if _task_id >= 0 and WorkerThreadPool.is_task_completed(_task_id):
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		_dry_busy = false
		_finish_dryrun(_task_sig, _task_out, Time.get_ticks_msec() - int(_task_meta.get("t0", 0)))
	if _dry_pending and _task_id < 0 and Time.get_ticks_msec() >= _dry_due_ms:
		_start_dryrun()


func _finish_dryrun(sig: String, runs: Dictionary, ms: int) -> void:
	if sig != draft_signature():
		# 过期结果：丢弃，但若当前没有任何结果，仍保留它作「上次结果」显示（标注重算中）。
		if dry.is_empty():
			dry = {"sig": sig, "runs": runs, "ms": ms, "q": model.q, "stale": true}
		if not _dry_pending and _task_id < 0 and is_inside_tree():
			request_dryrun(true)
		dryrun_changed.emit()
		return
	dry = {"sig": sig, "runs": runs, "ms": ms, "q": model.q, "stale": false}
	dryrun_changed.emit()


func run(id: String) -> Dictionary:
	var runs: Dictionary = dry.get("runs", {})
	if runs.has(id):
		return runs[id]
	if id == "draft_lo":
		return runs.get("nodraft_lo", {})
	if id == "draft_hi":
		return runs.get("nodraft_hi", {})
	return {}


## 某序列在两次试算下的逐季区间：[{lo, hi}] × n_q。
func band(run_lo: String, run_hi: String, key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var a: PackedInt64Array = JwReasons._series(run(run_lo), key)
	var b: PackedInt64Array = JwReasons._series(run(run_hi), key)
	var n: int = maxi(a.size(), b.size())
	for t: int in n:
		var x: int = a[t] if t < a.size() else (b[t] if t < b.size() else 0)
		var y: int = b[t] if t < b.size() else x
		out.append({"lo": mini(x, y), "hi": maxi(x, y)})
	return out


## 四季最窄余量（含本季草案，情景预测）：基线情景两次试算的逐季期末现金，取下界最低的一季。
func headroom_with_draft() -> Dictionary:
	if dry.is_empty():
		return {}
	var b: Array[Dictionary] = band("draft_lo", "draft_hi", "cash_end")
	if b.is_empty():
		return {}
	var worst: int = 0
	for t: int in b.size():
		if int(b[t]["lo"]) < int(b[worst]["lo"]):
			worst = t
	return {"lo": int(b[worst]["lo"]), "hi": int(b[worst]["hi"]), "q": model.q + worst}


## 本草案新增长期承诺（预算审查 B 表，docs/20 §8.3）：逐条目的承诺行与三项合计。
## 金额按内容包定义 × 规模（规则推断）；债券票息取草案试算里新批次的规则定价，试算未就绪时取主权利率。
## 返回 {rows[], first_q, four_q, steady, irreversible, cumulative, irreversible_items[]}。
func draft_commitments() -> Dictionary:
	var m: JwReadModel = model
	var q: int = m.q
	var rows: Array[Dictionary] = []
	var irrev_items: Array[Dictionary] = []
	var first_q: int = 0
	var four_q: int = 0
	var steady: int = 0
	var irrev: int = 0
	var cumulative: int = 0
	var new_bonds: Array = []
	if dry_is_current():
		new_bonds = run("draft_lo").get("new_bonds", [])
	var bond_i: int = 0
	for i: int in drafts.size():
		var d: Dictionary = drafts[i]
		var kind: int = int(d.get("kind", 0))
		var p: int = int(d.get("p", -1))
		var label: String = String(d.get("label", ""))
		if kind == K_LAUNCH and p >= 0:
			var scale: int = int(d.get("scale", JwReadModel.PPM))
			@warning_ignore("integer_division")
			var total: int = m.at("content.policy.cost_one_off_uu", p) * scale / JwReadModel.PPM
			var pq: int = maxi(m.at("content.policy.planned_quarters", p), 1)
			@warning_ignore("integer_division")
			var per: int = total / pq
			@warning_ignore("integer_division")
			var opex: int = m.at("content.policy.opex_per_q_uu", p) * scale / JwReadModel.PPM
			var comp: int = m.at("content.policy.exit_compensation_ppm", p)
			var delay: int = maxi(m.at("content.policy.commission_delay_q", p), 1)
			rows.append({"label": label, "type": "contract", "counterparty": "contractor", "start_q": q,
					"end_q": q + pq - 1, "per_q": per, "cum": total, "perpetual": false,
					"cancel": JwText.render("b.cancel.contract", {"pct": JwFormat.pct(comp)}), "source": "commit"})
			rows.append({"label": label, "type": "opex", "counterparty": "pubserv", "start_q": q + pq + delay - 1,
					"end_q": -1, "per_q": opex, "cum": -1, "perpetual": true,
					"cancel": JwText.t("b.cancel.opex"), "source": "opex"})
			first_q += per
			four_q += per * mini(4, pq)
			steady += opex
			irrev += per
			cumulative += total
			irrev_items.append({"label": label, "text": JwText.render("irrev.first_installment",
					{"amount": JwFormat.u(per)}), "amount": per})
		elif kind == K_ENACT and p >= 0:
			var per2: int = m.at("content.policy.cost_per_quarter_uu", p)
			var one: int = m.at("content.policy.cost_one_off_uu", p)
			var pq2: int = maxi(m.at("content.policy.planned_quarters", p), 1)
			var opex2: int = m.at("content.policy.opex_per_q_uu", p)
			var tog: int = m.at("content.policy.toggle_cost_uu", p)
			var comp2: int = m.at("content.policy.exit_compensation_ppm", p)
			rows.append({"label": label, "type": "policy", "counterparty": "program", "start_q": q,
					"end_q": q + pq2 - 1, "per_q": per2, "cum": one, "perpetual": false,
					"cancel": JwText.render("b.cancel.contract", {"pct": JwFormat.pct(comp2)}), "source": "commit"})
			if opex2 > 0:
				rows.append({"label": label, "type": "opex", "counterparty": "pubserv", "start_q": q + 1,
						"end_q": -1, "per_q": opex2, "cum": -1, "perpetual": true,
						"cancel": JwText.t("b.cancel.opex_policy"), "source": "opex"})
			rows.append({"label": label, "type": "toggle", "counterparty": "gov", "start_q": q, "end_q": q,
					"per_q": tog, "cum": tog, "perpetual": false, "cancel": JwText.t("b.cancel.irrevocable"),
					"source": "cash"})
			first_q += per2 + tog
			four_q += per2 * mini(4, pq2) + tog
			steady += opex2
			irrev += tog
			cumulative += one + tog
			irrev_items.append({"label": label, "text": JwText.render("irrev.toggle", {"amount": JwFormat.u(tog)}),
					"amount": tog})
		elif kind == K_REPEAL and p >= 0:
			var tog2: int = m.at("content.policy.toggle_cost_uu", p)
			var remaining: int = maxi(m.at("state.policy.budget_committed_uu", p) - m.at("state.policy.budget_spent_uu", p), 0)
			@warning_ignore("integer_division")
			var pen: int = remaining * m.at("content.policy.exit_compensation_ppm", p) / JwReadModel.PPM
			rows.append({"label": label, "type": "exit", "counterparty": "program", "start_q": q, "end_q": q,
					"per_q": tog2 + pen, "cum": tog2 + pen, "perpetual": false,
					"cancel": JwText.t("b.cancel.irrevocable"), "source": "cash"})
			first_q += tog2 + pen
			four_q += tog2 + pen
			irrev += tog2 + pen
			cumulative += tog2 + pen
			irrev_items.append({"label": label, "text": JwText.render("irrev.repeal",
					{"toggle": JwFormat.u(tog2), "penalty": JwFormat.u(pen)}), "amount": tog2 + pen})
		elif kind == K_CANCEL:
			var pj: int = int(d.get("project", -1))
			for row: Dictionary in m.project_rows():
				if int(row["p"]) == pj:
					var wc: Dictionary = m.withdraw_cost(row)
					rows.append({"label": label, "type": "exit", "counterparty": "contractor", "start_q": q,
							"end_q": q, "per_q": int(wc["penalty"]), "cum": int(wc["penalty"]), "perpetual": false,
							"cancel": JwText.t("b.cancel.irrevocable"), "source": "project"})
					first_q += int(wc["penalty"])
					four_q += int(wc["penalty"])
					irrev += int(wc["penalty"]) + int(wc["sunk"])
					irrev_items.append({"label": label, "text": JwText.render("irrev.cancel",
							{"sunk": JwFormat.u(int(wc["sunk"])), "penalty": JwFormat.u(int(wc["penalty"]))}),
							"amount": int(wc["penalty"])})
		elif kind == K_DEFER:
			var pj2: int = int(d.get("project", -1))
			for row2: Dictionary in m.project_rows():
				if int(row2["p"]) == pj2:
					var dc: Dictionary = m.defer_cost(row2, int(d.get("quarters", 1)))
					var fee: int = int(dc["fee"])
					rows.append({"label": label, "type": "exit", "counterparty": "contractor", "start_q": q,
							"end_q": q, "per_q": fee, "cum": fee, "perpetual": false,
							"cancel": JwText.t("b.cancel.irrevocable"), "source": "project"})
					first_q += fee
					four_q += fee
					irrev += fee
					irrev_items.append({"label": label, "text": JwText.render("irrev.defer",
							{"penalty": JwFormat.u(fee), "resume": JwFormat.quarter(int(dc["resume_q"]))}),
							"amount": fee})
		elif kind == K_ISSUE_BOND:
			var amount: int = int(d.get("amount", 0))
			var tenor: int = maxi(int(d.get("tenor", 8)), 1)
			var coupon_ppm: int = m.sc("state.world.sovereign_rate_ppm_per_q")
			if bond_i < new_bonds.size():
				coupon_ppm = int((new_bonds[bond_i] as Dictionary).get("coupon_ppm_per_q", coupon_ppm))
			bond_i += 1
			@warning_ignore("integer_division")
			var coupon_q: int = amount * coupon_ppm / JwReadModel.PPM
			var interest_total: int = coupon_q * tenor
			rows.append({"label": label, "type": "bond", "counterparty": "holder.%d" % int(d.get("holder", 0)),
					"start_q": q, "end_q": q + tenor, "per_q": coupon_q, "cum": amount + interest_total,
					"perpetual": false, "cancel": JwText.t("b.cancel.irrevocable"), "source": "debt",
					"coupon_ppm": coupon_ppm})
			steady += coupon_q
			four_q += coupon_q * 4
			cumulative += amount + interest_total
			irrev_items.append({"label": label, "text": JwText.render("irrev.bond",
					{"amount": JwFormat.u(amount), "q": JwFormat.quarter(q + tenor)}), "amount": amount})
	return {"rows": rows, "first_q": first_q, "four_q": four_q, "steady": steady, "irreversible": irrev,
			"cumulative": cumulative, "irreversible_items": irrev_items}


## 分配后果（情景预测）：含草案与不含草案两次基线试算期末的逐组生活指数差，按区间中点排序，
## 取受益前 3 与受损前 3（docs/20 §7.3.4：受益与受损并列，不给净额与平均）。
func group_impact() -> Dictionary:
	var out: Dictionary = {"gainers": [], "losers": [], "ready": false}
	if drafts.is_empty() or not dry_is_current():
		return out
	var a_lo: PackedInt64Array = run("draft_lo").get("living_index_end", PackedInt64Array())
	var a_hi: PackedInt64Array = run("draft_hi").get("living_index_end", PackedInt64Array())
	var b_lo: PackedInt64Array = run("nodraft_lo").get("living_index_end", PackedInt64Array())
	var b_hi: PackedInt64Array = run("nodraft_hi").get("living_index_end", PackedInt64Array())
	var pop: PackedInt64Array = run("draft_lo").get("population_end", PackedInt64Array())
	if a_lo.size() != JwReadModel.GROUP or b_lo.size() != JwReadModel.GROUP:
		return out
	var rows: Array[Dictionary] = []
	for g: int in JwReadModel.GROUP:
		if g < pop.size() and pop[g] <= 0:
			continue
		var d1: int = a_lo[g] - b_lo[g]
		var d2: int = (a_hi[g] if g < a_hi.size() else a_lo[g]) - (b_hi[g] if g < b_hi.size() else b_lo[g])
		rows.append({"g": g, "lo": mini(d1, d2), "hi": maxi(d1, d2), "mid": d1 + d2})
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if int(x["mid"]) != int(y["mid"]):
			return int(x["mid"]) > int(y["mid"])
		return int(x["g"]) < int(y["g"]))
	var gainers: Array = []
	var losers: Array = []
	for r: Dictionary in rows:
		if int(r["mid"]) > 0 and gainers.size() < 3:
			gainers.append(r)
	for i: int in range(rows.size() - 1, -1, -1):
		if int(rows[i]["mid"]) < 0 and losers.size() < 3:
			losers.append(rows[i])
	out["gainers"] = gainers
	out["losers"] = losers
	out["ready"] = true
	out["horizon_q"] = model.q + int(catalog.cfg("preview_quarters", 4)) - 1
	return out


## 群组显示名：地区·年龄·技能。
func group_label(g: int) -> String:
	return JwText.render("group.label", {"region": catalog.region_label(JwReadModel.region_of_group(g)),
			"age": JwText.t("age.%d" % JwReadModel.age_of_group(g)),
			"skill": JwText.t("skill.%d" % JwReadModel.skill_of_group(g))})


# ── 原因清单与底部固定区 ─────────────────────────────────────────────────

## 草案每条的 S02 回执（试算有效时取试算结果，否则用资格链镜像）。
func draft_verdicts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var run_lo: Dictionary = run("draft_lo")
	var have: bool = dry_is_current() and not drafts.is_empty() and bool(run_lo.get("ok", false))
	var s02: PackedInt64Array = run_lo.get("s02_codes", PackedInt64Array()) if have else PackedInt64Array()
	var sub: PackedInt64Array = run_lo.get("submit_codes", PackedInt64Array()) if have else PackedInt64Array()
	for i: int in drafts.size():
		var d: Dictionary = drafts[i]
		var code: int = 0
		var source: String = "dryrun"
		if have and i < sub.size() and sub[i] != 0:
			code = sub[i]
		elif have and i < s02.size():
			code = s02[i]
		else:
			source = "mirror"
			var kind: int = int(d.get("kind", 0))
			if kind == K_ENACT:
				code = int(model.eligibility(int(d.get("p", -1)), false, -1, JwReadModel.PPM).get("code", 0))
			elif kind == K_LAUNCH:
				code = int(model.eligibility(int(d.get("p", -1)), true, int(d.get("region", -1))).get("code", 0))
			elif kind == K_DEFER:
				code = JwReadModel.RJ_PRECONDITION
				for row: Dictionary in model.project_rows():
					if int(row["p"]) == int(d.get("project", -1)) \
							and bool(model.defer_cost(row, int(d.get("quarters", 1)))["allowed"]):
						code = 0
		out.append({"code": code, "source": source})
	return out


func reasons() -> Array:
	var out: Array = []
	if game == null:
		return out
	if read_only:
		out.append(JwReasons.from_code(JwReadModel.RJ_PHASE_BUSY, {"p": -1, "subject": "game",
				"subject_label": JwText.t("reason.subject.game")}, model, catalog))
	if model.terminated:
		out.append(JwReasons.from_code(JwReadModel.RJ_RUN_TERMINATED, {"p": -1, "subject": "game",
				"subject_label": JwText.t("reason.subject.game")}, model, catalog))
		return out
	var verdicts: Array[Dictionary] = draft_verdicts()
	for i: int in drafts.size():
		var v: int = int(verdicts[i]["code"])
		if v == 0:
			continue
		var d: Dictionary = drafts[i]
		var ctx: Dictionary = {"kind": int(d.get("kind", 0)), "p": int(d.get("p", -1)),
				"region": int(d.get("region", -1)), "scale": int(d.get("scale", JwReadModel.PPM)),
				"amount": int(d.get("amount", 0)), "draft": i, "subject": "draft%d" % i,
				"project": int(d.get("project", -1)),
				"subject_label": String(d.get("label", ""))}
		var r: Dictionary = JwReasons.from_code(v, ctx, model, catalog)
		r["draft"] = i
		r["verdict_source"] = String(verdicts[i]["source"])
		out.append(r)
	if dry_is_current():
		out.append_array(JwReasons.from_dryrun(dry, drafts, model, catalog))
	out.append_array(JwReasons.draft_notes(drafts, model, catalog))
	for r2: Variant in out:
		var rd: Dictionary = r2
		rd["bound"] = gap_bindings.has(String(rd.get("key", "")))
		rd["bound_path"] = String(gap_bindings.get(String(rd.get("key", "")), ""))
	JwReasons.sort(out)
	return out


func term_seen(id: String) -> bool:
	return seen_terms.has(id)


func mark_term_seen(id: String) -> void:
	if seen_terms.has(id):
		return
	seen_terms[id] = true
	log_event("ev.term_opened", {"term": id})


func bind_gap(key: String, path: String) -> void:
	gap_bindings[key] = path
	log_event("ev.gap_bound", {"code": key, "path": path})
	draft_changed.emit()


func dock_state() -> int:
	if settling:
		return Dock.SETTLING
	if settled_flag and drafts.is_empty():
		return Dock.SETTLED
	var rs: Array = reasons()
	var c: Dictionary = JwReasons.counts(rs)
	if int(c["block"]) > 0:
		return Dock.BLOCKED
	var unbound: int = 0
	var noexit: int = 0
	for r: Variant in rs:
		var rd: Dictionary = r
		if int(rd.get("severity", 0)) == JwInfo.Sev.GAP and not bool(rd.get("bound", false)):
			unbound += 1
			if (rd.get("exits", []) as Array).is_empty():
				noexit += 1
	if unbound > 0:
		return Dock.GAP_NOEXIT if noexit == unbound else Dock.GAP_UNBOUND
	if int(c["gap"]) > 0:
		return Dock.GAP_BOUND
	if int(c["note"]) > 0:
		return Dock.WARN
	if not drafts.is_empty():
		return Dock.DRAFT
	return Dock.IDLE


## 执行一条原因出口（RC-08：每条出口都是可执行的界面命令）。
func apply_exit(action: Dictionary) -> void:
	var t: String = String(action.get("type", ""))
	log_event("ev.reason_exit_opened", {"type": t})
	match t:
		"remove_draft":
			remove_draft(int(action.get("draft", -1)))
		"defer_draft":
			var i: int = int(action.get("draft", -1))
			if i >= 0:
				defer_draft(i, int(action.get("to_q", model.q + 1)))
		"scale_draft":
			var j: int = int(action.get("draft", -1))
			if j >= 0 and j < drafts.size():
				var d: Dictionary = drafts[j]
				if int(d.get("kind", 0)) == K_LAUNCH:
					var nd: Dictionary = draft_launch(int(d["p"]), int(d.get("region", 0)),
							int(action.get("scale", 500000)), int((d["args"] as PackedInt64Array)[3]))
					replace_draft(j, nd)
		"add_bond":
			var amt: int = maxi(int(action.get("amount", 0)), 100_000_000)
			@warning_ignore("integer_division")
			var rounded: int = ((amt + 99_999_999) / 100_000_000) * 100_000_000
			add_draft(draft_bond(rounded, int(catalog.cfg("bond_default_tenor_q", 8)), 0))
		"scale_bond":
			var k: int = int(action.get("draft", -1))
			if k >= 0 and k < drafts.size():
				var db: Dictionary = drafts[k]
				replace_draft(k, draft_bond(maxi(int(action.get("amount", 0)), 1), int(db.get("tenor", 8)),
						int(db.get("holder", 0))))
		"switch_holder":
			var h: int = int(action.get("draft", -1))
			if h >= 0 and h < drafts.size():
				var dh: Dictionary = drafts[h]
				replace_draft(h, draft_bond(int(dh.get("amount", 0)), int(dh.get("tenor", 8)),
						1 - int(dh.get("holder", 0))))
		"accept_gap":
			bind_gap(String(action.get("key", "")), "accept")
		"add_project_defer":
			add_draft(draft_project_defer(int(action.get("project", -1)), maxi(int(action.get("quarters", 1)), 1),
					String(action.get("name", ""))))
		"goto_policy":
			navigate_requested.emit("policy", {"p": int(action.get("p", -1))})
		"open_ledger":
			overlay_requested.emit("ledger", {"ledger": String(action.get("ledger", ""))})
		"open_archive":
			overlay_requested.emit("archive", {})
		"open_saves":
			overlay_requested.emit("saves", {})
		"recompute":
			request_dryrun(true)
		_:
			pass


# ── 推进 ───────────────────────────────────────────────────────────────

## 确认推进（由确认框调用）。有场景树时结算在工作线程上跑（TH-1），完成后在主线程收尾并回放；
## 无场景树（测试）或同步模式下当场跑完。
func advance() -> Dictionary:
	var out: Dictionary = {"ok": false}
	if game == null or read_only or model.terminated or settling:
		out["code"] = JwReadModel.RJ_PHASE_BUSY if (read_only or settling) else JwReadModel.RJ_RUN_TERMINATED
		return out
	_wait_dryrun()
	_dry_pending = false
	settling = true
	settlement_started.emit()
	var q0: int = model.q
	_record_expectations(q0)
	var submitted: Array[Dictionary] = []
	for d: Dictionary in drafts:
		var rr: Dictionary = res(game.submit_command(int(d.get("kind", 0)), d.get("args", _args([]))))
		submitted.append({"label": String(d.get("label", "")), "kind": int(d.get("kind", 0)),
				"p": int(d.get("p", -1)), "submit_ok": bool(rr["ok"]), "submit_code": int(rr["code"])})
	var rm: Dictionary = res(game.submit_command(K_ADVANCE, _args([])))
	_adv_ctx = {"q0": q0, "submitted": submitted, "rm": rm, "arrears0": model.sc("state.gov.arrears_uu")}
	if _sync_mode or not is_inside_tree():
		return _finish_advance(res(game.advance_quarter()))
	# TH-1：在工作线程跑完整季结算；主线程保持响应，结算期间界面只读、不读活状态。
	var g: JWGame = game
	var box: Dictionary = {}
	_adv_box = box
	_adv_task = WorkerThreadPool.add_task(func() -> void:
		box["r"] = JwSession.res(g.advance_quarter()), false, "jw_settle")
	return {"ok": true, "pending": true, "q": q0}


## 批量推进（R-CLOCK-01，战役模式的「推进一年 / 五年」）：主线程逐季结算，每季照常写历史快照与回执；
## 遇到暂停原因（终局、危机升级、政府更替、选举、新增欠付）即停；只在最后一季发 settlement_finished。
## 草案只进第一季。
## scripted == true 时（行动脚本快进）：每季先提交本局所挂脚本的命令，只在终局或推进失败时停。
func advance_batch(n: int, scripted: bool = false) -> Dictionary:
	var out: Dictionary = {"ok": false}
	if game == null or read_only or model.terminated or settling or n < 1:
		out["code"] = JwReadModel.RJ_PHASE_BUSY if (read_only or settling) else JwReadModel.RJ_RUN_TERMINATED
		return out
	_wait_dryrun()
	_dry_pending = false
	settling = true
	settlement_started.emit()
	var done: int = 0
	var reason: int = 0
	var last: Dictionary = {}
	while done < n:
		var q0: int = model.q
		var submitted: Array[Dictionary] = []
		if done == 0:
			_record_expectations(q0)
			for d: Dictionary in drafts:
				var rr: Dictionary = res(game.submit_command(int(d.get("kind", 0)), d.get("args", _args([]))))
				submitted.append({"label": String(d.get("label", "")), "kind": int(d.get("kind", 0)),
						"p": int(d.get("p", -1)), "submit_ok": bool(rr["ok"]), "submit_code": int(rr["code"])})
		var planned: Array[Dictionary] = []
		if scripted:
			planned = game.playscript_submit_active()
			for p: Dictionary in planned:
				submitted.append({"label": String(p["label"]), "kind": int(p["kind"]), "p": -1,
						"submit_ok": true, "submit_code": 0})
		var before: Dictionary = game.pause_probe()
		var rm: Dictionary = res(game.submit_command(K_ADVANCE, _args([])))
		_adv_ctx = {"q0": q0, "submitted": submitted, "rm": rm, "arrears0": model.sc("state.gov.arrears_uu")}
		settling = true
		var ra: Dictionary = res(game.advance_quarter())
		if scripted:
			game.playscript_settle_active(planned, q0)
		last = _finish_advance(ra, false)
		reason = game.pause_reason(before, bool(ra.get("ok", false)))
		if bool(ra.get("ok", false)):
			done += 1
		if scripted and reason != JWGame.Pause.TERMINATED and reason != JWGame.Pause.FAILED:
			reason = 0
		if reason != 0:
			break
	last["batch"] = {"requested": n, "done": done, "reason": reason}
	last_receipt = last
	settlement_finished.emit(last)
	request_dryrun(true)
	return last


## 行动脚本快进：按脚本的剧本与种子开新局，再逐季提交脚本命令推进到 until（可覆盖；写法同脚本）。
## 返回 {ok, errors, status, batch}；脚本解析失败时不开局。
func play_script(path: String, until_override: String = "") -> Dictionary:
	var peek: Dictionary = JWGame.playscript_peek(path)
	if not bool(peek.get("ok", false)):
		return {"ok": false, "errors": peek.get("errors", PackedStringArray())}
	var r: Dictionary = start_new(int(peek["seed"]), -1, String(peek["scenario"]))
	if not bool(r.get("ok", false)):
		return {"ok": false, "errors": PackedStringArray(["start_new failed"]), "start": r}
	var at: Dictionary = game.playscript_attach(path)
	if not bool(at.get("ok", false)):
		return {"ok": false, "errors": at.get("errors", PackedStringArray())}
	var until_q: int = int(at.get("until_q", -1))
	if until_override != "":
		until_q = game.playscript_parse_q(until_override)
	var out: Dictionary = {"ok": true, "errors": PackedStringArray()}
	if until_q > model.q:
		out["batch"] = advance_batch(until_q - model.q, true).get("batch", {})
	out["status"] = game.playscript_status()
	return out


## 结算完成（主线程）：刷新读模型、写历史快照与回执、发 settlement_finished。
## final == false 时（批量推进的中间季）不发信号、不请求试算，由 advance_batch 在最后一季统一收尾。
func _finish_advance(ra: Dictionary, final: bool = true) -> Dictionary:
	var q0: int = int(_adv_ctx.get("q0", model.q))
	var submitted: Array = _adv_ctx.get("submitted", [])
	var rm: Dictionary = _adv_ctx.get("rm", {"ok": false})
	var arrears0: int = int(_adv_ctx.get("arrears0", 0))
	model.refresh()
	_cache_step_counts()
	var cmds: Array[Dictionary] = model.commands_of_quarter(q0)
	var j: int = 0
	for row: Dictionary in cmds:
		if j < submitted.size():
			(submitted[j] as Dictionary)["accepted"] = int(row.get("accepted", 0))
			(submitted[j] as Dictionary)["reject_code"] = int(row.get("reject_code", 0))
		j += 1
	var out: Dictionary = {
		"ok": bool(ra.get("ok", false)), "code": int(ra.get("code", -1)), "marker_ok": bool(rm.get("ok", false)),
		"q": q0, "commands": submitted,
		"arrears_delta": model.sc("state.gov.arrears_uu") - arrears0,
		"terminated": model.terminated,
		"termination_reason": model.sc("state.meta.termination_reason"),
		"autosave_code": game.last_autosave_code,
		"fault_dir": game.last_fault_dir,
		"review_quarter": q0 % 4 == 3,
		"election_quarter": JwReadModel.ELECTION_QS.has(q0),
	}
	if bool(ra.get("ok", false)):
		history.append(_snapshot(q0))
		drafts.clear()
		gap_bindings.clear()
		settled_flag = true
		# 自动存档槽的界面侧车（历史快照、存档的预期区间等），读 autosave 时报告与年度审查不丢历史。
		if int(game.last_autosave_code) == 0:
			_write_side_car(AUTOSAVE_SLOT)
	last_receipt = out
	settling = false
	_adv_ctx = {}
	log_event("ev.advance_confirmed", {"q": q0})
	dry = {}
	if not final:
		return out
	# 不另发 state_changed：外壳在 settlement_finished 里先开回放、下一帧再整体刷新（收尾分两帧，TH-4）。
	settlement_finished.emit(out)
	request_dryrun(true)
	return out


## 本季账本行按结算步计数（log.ledger 的 step 列；只在主线程、非结算期读取）。
func _cache_step_counts() -> void:
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(9)
	out.fill(0)
	if game == null:
		step_counts = out
		return
	var v: JWGame.StateView = game.view()
	var rows: PackedInt64Array = v.ledger_rows(0, v.ledger_row_count())
	var i: int = 0
	while i + 12 < rows.size():
		var st: int = rows[i + 2]
		if st >= 0 and st < 9:
			out[st] += 1
		i += 13
	step_counts = out


func clear_settled_flag() -> void:
	settled_flag = false


## VT-1：推进前把本季的情景区间写入只读档（事后不可改）。
func _record_expectations(q0: int) -> void:
	if expectations.has(str(q0)) or not dry_is_current():
		return
	var e: Dictionary = {}
	for key: String in ["cash_end", "new_borrowing", "arrears", "unemployment_ppm", "receipts"]:
		var b: Array[Dictionary] = band("draft_lo", "draft_hi", key)
		if not b.is_empty():
			e[key] = [int(b[0]["lo"]), int(b[0]["hi"])]
	e["scenario"] = "base"
	expectations[str(q0)] = e


# ── 历史快照（报告、偏差表、年度审查与档案用） ───────────────────────────

func _snapshot(q_settled: int) -> Dictionary:
	var m: JwReadModel = model
	var un: Dictionary = m.unemployment()
	var h: Dictionary = {
		"q": q_settled,
		"cash": m.gov_cash(), "debt": m.debt_total(), "arrears": m.sc("state.gov.arrears_uu"),
		"receipts": m.receipts_total(), "receipts_income": m.sc("flow.gov.receipts_income_tax_uu"),
		"receipts_profit": m.sc("flow.gov.receipts_profit_tax_uu"),
		"receipts_other": m.sc("flow.gov.receipts_other_uu"),
		"primary": m.sc("flow.gov.primary_paid_uu"), "interest": m.sc("flow.gov.interest_paid_uu"),
		"principal": m.sc("flow.gov.principal_paid_uu"), "borrowing": m.sc("flow.gov.new_borrowing_uu"),
		"opex_paid": _sum(m.ar("flow.gov.pay_opex_uu")),
		"public_wages": m.sc("flow.gov.pay_public_wages_uu"), "procurement": m.sc("flow.gov.pay_procurement_uu"),
		"rollover": m.sc("flow.gov.rollover_uu"),
		"project_paid": _sum(m.ar("flow.gov.pay_project_uu")),
		"gdp_real": m.dv("derived.gdp.real_uu"), "gdp_nominal": m.dv("derived.gdp.production_uu"),
		"gdp_annual": m.dv("derived.gdp.annual_nominal_uu"),
		"unemployment_ppm": int(un["rate_ppm"]), "labor_force": int(un["labor_force"]),
		"living": m.living_national(), "expectation": m.expectation_national(),
		"trust": m.trust_national(), "support": m.support_national(),
		"tax_capacity": m.sc("state.gov.tax_capacity_ppm"),
		"opex_committed": m.sc("state.gov.service_opex_committed_uu"),
		"committed": m.sc("state.gov.committed_memo_uu"),
		"credit_left": m.credit_left(),
		"binding": m.ar("flow.cell.binding_code"),
		"cell_output": m.ar("flow.cell.output_actual_uqs"),
		"cell_va_real": m.ar("flow.cell.value_added_real_uu"),
		"pop": m.national_population(),
	}
	var ur: Array = []
	var sr: Array = []
	var br: Array = []
	var va: Array = []
	for r: int in JwReadModel.R:
		ur.append(int(m.region_unemployment(r)["rate_ppm"]))
		sr.append(m.support_region(r))
		br.append(int(m.region_burden(r)["ppm"]))
	for sec: int in JwReadModel.S:
		va.append(m.sector_va_real(sec))
	h["unemp_region"] = ur
	h["support_region"] = sr
	h["burden_region"] = br
	h["va_sector"] = va
	var gd: Array = []
	var gl: Array = []
	for g: int in JwReadModel.GROUP:
		gd.append(m.group_disposable_pc(g))
		gl.append(m.at("state.group.living_index_ppm", g))
	h["group_disp_pc"] = gd
	h["group_living"] = gl
	var bo: Array = []
	for b: int in JwReadModel.BLOC_N:
		bo.append(m.at("state.bloc.org_power_ppm", b))
	h["bloc_org"] = bo
	h["shocks"] = m.ar("state.world.shock_active")
	return h


func history_entry(q_settled: int) -> Dictionary:
	for h: Dictionary in history:
		if int(h.get("q", -99)) == q_settled:
			return h
	return {}


func last_settled() -> Dictionary:
	if history.size() >= 1:
		return history[history.size() - 1]
	return {}


static func _sum(a: PackedInt64Array) -> int:
	var t: int = 0
	for x: int in a:
		t += x
	return t


# ── 界面事件（docs/22 §3：不进命令流、不进哈希，只写本地） ─────────────────

func log_event(name: String, args: Dictionary = {}) -> void:
	var e: Dictionary = {"t_ms": Time.get_ticks_msec() - _t0_ms, "q": model.q if game != null else 0,
			"name": name, "args": args}
	events.append(e)
	if events.size() > 5000:
		events.remove_at(0)
	ui_event.emit(name, args)
	if telemetry:
		var f: FileAccess = FileAccess.open("user://ui_events.jsonl", FileAccess.READ_WRITE)
		if f == null:
			f = FileAccess.open("user://ui_events.jsonl", FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_line(JSON.stringify(_jsonable(e)))
			f.close()


func events_of_quarter(qq: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in events:
		if int(e.get("q", -1)) == qq:
			out.append(e)
	return out


# ── 工具 ───────────────────────────────────────────────────────────────

## JWResult → {ok, code, a, b}（界面不引用 SimCore 的类型）。
static func res(r: Object) -> Dictionary:
	if r == null:
		return {"ok": false, "code": -1, "a": 0, "b": 0}
	return {"ok": bool(r.get("ok")), "code": int(r.get("code")), "a": int(r.get("detail_a")),
			"b": int(r.get("detail_b"))}


static func _jsonable(v: Variant) -> Variant:
	if v is PackedInt64Array:
		var arr: Array = []
		for x: int in v as PackedInt64Array:
			arr.append(x)
		return arr
	if v is Dictionary:
		var d: Dictionary = {}
		for k: Variant in (v as Dictionary).keys():
			d[str(k)] = _jsonable((v as Dictionary)[k])
		return d
	if v is Array:
		var a: Array = []
		for x2: Variant in v as Array:
			a.append(_jsonable(x2))
		return a
	return v


## JSON 读回后把浮点数还原为整数（JSON 把全部数字解析成 float）。
static func _ints(v: Variant) -> Variant:
	if v is float:
		return int(v)
	if v is Dictionary:
		var d: Dictionary = {}
		for k: Variant in (v as Dictionary).keys():
			d[str(k)] = _ints((v as Dictionary)[k])
		return d
	if v is Array:
		var a: Array = []
		for x: Variant in v as Array:
			a.append(_ints(x))
		return a
	return v
