## v2 游戏门面（docs/57 §15）：界面、工具与测试只经这里读局面、下命令、推进。
##
## 一回合 = 一季：
##   玩家下令（order）→ 立即生效、记进本局命令簿；本季内可以撤回（undo）
##   结束本季（end_turn）→ 托管代办 → 结算一季 → 刷新顾问、托管拟办、分析
## 命令簿（journal）记下每条命令发生在第几季：同一种子 + 同一命令簿可以逐位复现整局（replay）。
## 存档是 JSON：状态 + 托管设置 + 顾问记忆 + 命令簿；读档时核对内容指纹。
class_name JCGame
extends RefCounted

const PPM: int = 1_000_000
const SAVE_DIR: String = "user://jc_saves"
const SAVE_SCHEMA: String = "jc.save"
const SAVE_VERSION: int = 1

var ct: JCContent = null
var st: JCState = null
var sim: JCSim = null
var analyst: JCAnalyst = JCAnalyst.new()
var steward: JCSteward = JCSteward.new()
var advisors: JCAdvisors = JCAdvisors.new()
## [{q, cmd}]
var journal: Array = []
## 托管拟办（ASK 模式）：[{domain, cmd, reason, slots}]
var proposals: Array = []
## 本季开始时的快照（撤回用）
var _snap: JCState = null
var _snap_journal: int = 0
var last_error: String = ""
## 上一回合结算的回执：{q_from, q_to, notes: [...], steward: [...], over}
var last_receipt: Dictionary = {}
var autosave: bool = true


# ════════════════════════════ 开局、读档、存档 ════════════════════════════
static func load_content() -> JCContent:
	return JCContent.load_default()


func new_game(seed: int, content: JCContent = null) -> bool:
	ct = content if content != null else load_content()
	if ct == null or not ct.ok():
		last_error = "content"
		return false
	st = JCSim.new_state(ct, maxi(1, seed))
	sim = JCSim.new(ct, st)
	sim.warm_up()
	steward = JCSteward.new()
	advisors = JCAdvisors.new()
	journal = []
	proposals = []
	last_receipt = {}
	_begin_turn()
	return true


func is_ready() -> bool:
	return sim != null and st != null


func save_to(path: String) -> bool:
	if not is_ready():
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var d: Dictionary = {"schema": SAVE_SCHEMA, "version": SAVE_VERSION, "content_hash": ct.content_hash,
			"seed": st.seed, "year": st.year(), "season": st.season(), "era": st.era,
			"saved_at": Time.get_datetime_string_from_system(), "state": st.to_dict(),
			"steward": steward.to_dict(), "advisors": advisors.to_dict(), "journal": journal}
	var tmp: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "save_open"
		return false
	f.store_string(JSON.stringify(d))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var err: int = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		last_error = "save_rename"
		return false
	return true


func load_from(path: String, content: JCContent = null) -> bool:
	if not FileAccess.file_exists(path):
		last_error = "no_file"
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or String((parsed as Dictionary).get("schema", "")) != SAVE_SCHEMA:
		last_error = "bad_file"
		return false
	var d: Dictionary = parsed
	var c: JCContent = content if content != null else load_content()
	if c == null or not c.ok():
		last_error = "content"
		return false
	var s: JCState = JCState.from_dict(d["state"])
	ct = c
	st = s
	if st.content_hash != ct.content_hash:
		# 内容改过：按命令簿从种子重放（机制改变也不坏档，docs/57 §15）
		var jr: Array = JCState._ints_deep(d.get("journal", []))
		var target_q: int = st.q
		if not new_game(int(d.get("seed", st.seed)), c):
			return false
		steward.from_dict(d.get("steward", {}))
		advisors.from_dict(d.get("advisors", {}))
		replay(jr, target_q)
		last_error = "replayed"
		return true
	sim = JCSim.new(ct, st)
	sim.rebind(st)
	steward = JCSteward.new()
	steward.from_dict(JCState._ints_deep(d.get("steward", {})))
	advisors = JCAdvisors.new()
	advisors.from_dict(JCState._ints_deep(d.get("advisors", {})))
	journal = JCState._ints_deep(d.get("journal", []))
	proposals = []
	_begin_turn()
	return true


static func save_path(slot: String) -> String:
	return SAVE_DIR + "/" + slot + ".json"


## 存档列表：[{slot, path, year, season, era, saved_at}]，新的在前。
static func list_saves() -> Array:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var e: String = dir.get_next()
	while e != "":
		if not dir.current_is_dir() and e.ends_with(".json"):
			var p: String = SAVE_DIR + "/" + e
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
			if parsed is Dictionary and String((parsed as Dictionary).get("schema", "")) == SAVE_SCHEMA:
				var d: Dictionary = parsed
				out.append({"slot": e.get_basename(), "path": p, "year": int(d.get("year", 0)),
						"season": int(d.get("season", 0)), "era": int(d.get("era", 1)),
						"saved_at": String(d.get("saved_at", ""))})
		e = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["saved_at"]) > String(b["saved_at"]))
	return out


# ════════════════════════════ 下令与撤回 ══════════════════════════════════
## 只检查、不执行（按钮是否可点、托管与顾问用）。
func check(cmd: Dictionary) -> Dictionary:
	if not is_ready():
		return {"ok": false, "reason": "reason.no_game"}
	return sim.cmd.check(cmd)


## 下一条命令：立即生效并记进命令簿。
func order(cmd: Dictionary) -> Dictionary:
	if not is_ready():
		return {"ok": false, "reason": "reason.no_game"}
	var c: Dictionary = cmd.duplicate(true)
	if not c.has("source"):
		c["source"] = "player"
	var r: Dictionary = sim.cmd.apply(c)
	if bool(r.get("ok", false)):
		journal.append({"q": st.q, "cmd": c})
		_after_order()
	return r


## 本季下过的命令（可撤回的）。
func turn_orders() -> Array:
	return journal.slice(_snap_journal)


## 撤回本季最后一条命令（回到季初快照，再把其余命令重下一遍）。
func undo_last() -> bool:
	if journal.size() <= _snap_journal or _snap == null:
		return false
	var keep: Array = journal.slice(_snap_journal, journal.size() - 1)
	journal.resize(_snap_journal)
	st = _snap.duplicate_state()
	sim.rebind(st)
	for e: Dictionary in keep:
		var r: Dictionary = sim.cmd.apply(e["cmd"])
		if bool(r.get("ok", false)):
			journal.append(e)
	_after_order()
	return true


func _after_order() -> void:
	analyst.setup(sim)
	advisors.refresh(sim, analyst)


# ════════════════════════════ 托管与顾问 ══════════════════════════════════
func set_steward(domain: String, mode: int, stance: String = "") -> bool:
	var ok: bool = steward.set_mode(domain, mode)
	if ok and stance != "":
		ok = steward.set_stance(domain, stance)
	if ok:
		st.note("steward", "chron.steward_mode", {"domain": domain, "mode": mode, "stance": String(steward.stance[domain])})
		_refresh_proposals()
	return ok


## 批准一条拟办（下标）；批准后从拟办里移除。
func approve(idx: int) -> Dictionary:
	if idx < 0 or idx >= proposals.size():
		return {"ok": false, "reason": "reason.bad_command"}
	var p: Dictionary = proposals[idx]
	proposals.remove_at(idx)
	var r: Dictionary = order(p["cmd"])
	steward.record(sim, p, r)
	_refresh_proposals()
	return r


func approve_all() -> int:
	var n: int = 0
	while not proposals.is_empty():
		if bool(approve(0).get("ok", false)):
			n += 1
	return n


func reject(idx: int) -> void:
	if idx < 0 or idx >= proposals.size():
		return
	var p: Dictionary = proposals[idx]
	proposals.remove_at(idx)
	var key: String = String(p.get("slots", {}).get("_cool", ""))
	if key != "":
		steward.cool[key] = st.q + 8


## 「照此办理」：执行一条顾问建议的全部命令。
func accept_advice(id: String) -> Dictionary:
	var it: Dictionary = advisors.find(id)
	if it.is_empty():
		return {"ok": false, "reason": "reason.no_such_advice"}
	var results: Array = []
	var any: bool = false
	for c: Variant in it.get("cmds", []):
		var r: Dictionary = order(c)
		results.append(r)
		any = any or bool(r.get("ok", false))
	if any:
		advisors.dismiss(id, st.q, 2)
		st.note("advisor", "chron.advice_taken", {"ministry": it["ministry"], "advice": id})
		advisors.refresh(sim, analyst)
	return {"ok": any, "results": results}


func dismiss_advice(id: String) -> void:
	advisors.dismiss(id, st.q, 8)
	advisors.refresh(sim, analyst)


func _refresh_proposals() -> void:
	if not is_ready() or st.over == 1:
		proposals = []
		return
	proposals = steward.plan(sim, analyst, JCSteward.ASK)


# ════════════════════════════ 推进 ════════════════════════════════════════
## 结束本季：托管代办 → 结算。返回回执 {ok, q_from, q_to, notes, steward, over, reason}。
func end_turn() -> Dictionary:
	if not is_ready():
		return {"ok": false, "reason": "reason.no_game"}
	if st.over == 1:
		return {"ok": false, "reason": "reason.game_over"}
	var q0: int = st.q
	var done: Array = []
	# 托管代办（先刷新分析，看到玩家本季下的命令之后的局面）
	analyst.setup(sim)
	for p: Dictionary in steward.plan(sim, analyst, JCSteward.AUTO):
		var r: Dictionary = order(p["cmd"])
		steward.record(sim, p, r)
		if bool(r.get("ok", false)):
			done.append(p)
	var res: Dictionary = sim.advance([])
	if not bool(res.get("ok", false)):
		last_error = String(res.get("reason", ""))
	var notes: Array = []
	for e: Dictionary in st.chron:
		if int(e["q"]) >= q0:
			notes.append(e)
	last_receipt = {"ok": bool(res.get("ok", false)), "q_from": q0, "q_to": st.q, "notes": notes, "steward": done,
			"over": st.over == 1, "reason": String(res.get("reason", ""))}
	_begin_turn()
	if autosave and st.season() == 0 and st.q > 0:
		save_to(save_path("autosave"))
	return last_receipt


## 快进至多 n 季；遇到待决事件（事件未托管时）、危机升级、终局就停。返回 {turns, stop}。
func fast_forward(n: int) -> Dictionary:
	var turns: int = 0
	var stop: String = ""
	var q0: int = st.q
	var done: Array = []
	for i: int in n:
		var cr0: int = _crisis_sum()
		var r: Dictionary = end_turn()
		done.append_array(r.get("steward", []))
		turns += 1
		if not bool(r.get("ok", false)) or st.over == 1:
			stop = "over"
			break
		if not st.pend.is_empty() and int(steward.mode["events"]) != JCSteward.AUTO:
			stop = "event"
			break
		if _crisis_sum() > cr0:
			stop = "crisis"
			break
		if _era_changed(r):
			stop = "era"
			break
	# 快进的回执：把这几季的纪事与托管代办合在一起
	var notes: Array = []
	for e: Dictionary in st.chron:
		if int(e["q"]) >= q0:
			notes.append(e)
	last_receipt = {"ok": st.over == 0, "q_from": q0, "q_to": st.q, "notes": notes, "steward": done,
			"over": st.over == 1, "reason": String(last_receipt.get("reason", "")), "stop": stop, "turns": turns}
	return {"turns": turns, "stop": stop}


func _crisis_sum() -> int:
	var s: int = 0
	for x: int in st.cr_stage:
		s += x
	return s


func _era_changed(r: Dictionary) -> bool:
	for e: Dictionary in r.get("notes", []):
		if String(e["kind"]) == "era":
			return true
	return false


func _begin_turn() -> void:
	analyst.setup(sim)
	advisors.refresh(sim, analyst)
	_refresh_proposals()
	_snap = st.duplicate_state()
	_snap_journal = journal.size()


## 从当前（刚开局的）状态按命令簿重放到第 target_q 季。
func replay(jr: Array, target_q: int) -> bool:
	var i: int = 0
	while st.q < target_q and st.over == 0:
		while i < jr.size() and int(jr[i]["q"]) == st.q:
			var r: Dictionary = sim.cmd.apply(jr[i]["cmd"])
			if bool(r.get("ok", false)):
				journal.append(jr[i])
			i += 1
		while i < jr.size() and int(jr[i]["q"]) < st.q:
			i += 1
		var res: Dictionary = sim.advance([])
		if not bool(res.get("ok", false)):
			last_error = String(res.get("reason", ""))
			_begin_turn()
			return false
	# 目标季里、结算之前下的命令
	while i < jr.size() and int(jr[i]["q"]) == st.q:
		var r2: Dictionary = sim.cmd.apply(jr[i]["cmd"])
		if bool(r2.get("ok", false)):
			journal.append(jr[i])
		i += 1
	_begin_turn()
	_snap_journal = journal.size()
	return true


# ════════════════════════════ 名字与状态 ══════════════════════════════════
## 内容 ID → 显示名（kind：building / region / good / tech / partner / decree / event / method / class / landmark / need）。
func name_of(kind: String, id: String) -> String:
	if ct == null:
		return id
	match kind:
		"building":
			var b: int = int(ct.bidx.get(id, -1))
			return ct.b_name[b] if b >= 0 else id
		"region":
			var r: int = int(ct.ridx.get(id, -1))
			return ct.r_name[r] if r >= 0 else id
		"good":
			var g: int = int(ct.gidx.get(id, -1))
			return ct.g_name[g] if g >= 0 else id
		"tech":
			var t: int = int(ct.tidx.get(id, -1))
			return ct.t_name[t] if t >= 0 else id
		"method":
			var m: int = int(ct.midx.get(id, -1))
			return ct.m_name[m] if m >= 0 else id
		"class":
			var c: int = int(ct.cidx.get(id, -1))
			return ct.c_name[c] if c >= 0 else id
		"need":
			var n: int = int(ct.nidx.get(id, -1))
			return ct.n_name[n] if n >= 0 else id
		"partner":
			var p: int = int(ct.pidx.get(id, -1))
			return String(ct.partners[p]["name"]) if p >= 0 else id
		"decree":
			var d: int = int(ct.didx.get(id, -1))
			return String(ct.decrees[d]["name"]) if d >= 0 else id
		"event":
			var e: int = int(ct.eidx.get(id, -1))
			return String(ct.events[e]["name"]) if e >= 0 else id
		"landmark":
			var l: int = int(ct.lidx.get(id, -1))
			return String(ct.landmarks[l]["name"]) if l >= 0 else id
	return id


## 政令某一档的名字（分档政令）；开关与运动类返回空串。
func decree_level_name(id: String, lvl: int) -> String:
	if ct == null:
		return ""
	var d: int = int(ct.didx.get(id, -1))
	if d < 0 or String(ct.decrees[d].get("kind", "toggle")) != "level":
		return ""
	var lv: Array = ct.decrees[d].get("levels", [])
	return String(lv[lvl]) if lvl >= 0 and lvl < lv.size() else ""


## 事件某个选项的文字（纪事、命令簿里写「选了哪一条」）；找不到返回空串。
func event_option(id: String, idx: int) -> String:
	if ct == null:
		return ""
	var e: int = int(ct.eidx.get(id, -1))
	if e < 0:
		return ""
	var opts: Array = ct.events[e].get("options", [])
	return String((opts[idx] as Dictionary).get("text", "")) if idx >= 0 and idx < opts.size() else ""


## 某一堆建筑（按编号）是什么、在哪：{building, region}；找不到返回空字典。
func stack_info(uid: int) -> Dictionary:
	if not is_ready():
		return {}
	var i: int = st.stack_of_uid(uid)
	if i < 0:
		return {}
	return {"building": ct.b_id[st.s_b[i]], "region": ct.r_id[st.s_region[i]]}


func is_class_id(id: String) -> bool:
	return ct != null and ct.cidx.has(id)


## 顶栏用的概况。
func status() -> Dictionary:
	if not is_ready():
		return {}
	var f: Dictionary = analyst.fiscal()
	return {"q": st.q, "year": st.year(), "season": st.season(), "era": st.era, "world_era": st.world_era,
			"treasury": st.treasury, "balance": int(f["balance"]), "debt": st.debt, "legitimacy": st.legitimacy,
			"crisis": Array(st.cr_stage), "events": st.pend.size(), "advice": advisors.items.size(),
			"proposals": proposals.size(), "over": st.over == 1, "over_reason": st.over_reason,
			"pop": int(st.last.get("pop", 0)), "gdp": int(st.last.get("gdp", 0)), "living": int(st.last.get("living", 0)),
			"unemp": int(st.last.get("unemp_ppm", 0)), "prestige": st.prestige, "orders": turn_orders().size()}


## 界面视图（懒建）。
var _views: JCViews = null


func views() -> JCViews:
	if _views == null:
		_views = JCViews.new(self)
	return _views
