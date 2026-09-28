## v2 行动脚本：把一局的打法写成 JSON，按季经 JCGame 的正常命令路径执行（调试、截图、平衡试跑用）。
##
## {
##   "schema_kind": "jc_playscript", "schema_version": 1, "name": "托管均衡",
##   "seed": 1, "until": "1750秋",
##   "steward": {"research": ["auto", "era"], "build": ["ask", "balanced"], ...},   // 模式 off / ask / auto
##   "approve": true,          // 拟办（ask）一律批准
##   "advice": "follow",       // follow：每季照办排第一的顾问建议；ignore（缺省）：不理会
##   "events": "first",        // 待决事件：first 选第一项；last 选最后一项；缺省按托管或到期自动
##   "timeline": [{"at": "1601春", "do": [{"kind": "build", "building": "school", "region": "zhongzhou"}]}]
## }
## 时间写法：「1650」= 1650 年春；「1650秋」；「q:37」= 第 37 季。
class_name JCPlayscript
extends RefCounted

const SEASONS: PackedStringArray = ["春", "夏", "秋", "冬"]

var data: Dictionary = {}
var errors: PackedStringArray = PackedStringArray()
## 脚本命令的执行记录：{q, cmd, ok, reason}
var entries: Array = []
var _tl: Dictionary = {}
var _bound: bool = false


static func from_file(path: String) -> JCPlayscript:
	var p: JCPlayscript = JCPlayscript.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		p.errors.append("not_json:" + path)
		return p
	p.data = parsed
	return p


static func from_dict(d: Dictionary) -> JCPlayscript:
	var p: JCPlayscript = JCPlayscript.new()
	p.data = d
	return p


## 「1650秋」→ 季下标；认不出返回 −1。
static func parse_q(s: String, start_year: int) -> int:
	var t: String = s.strip_edges()
	if t.begins_with("q:"):
		var n: String = t.substr(2)
		return int(n) if n.is_valid_int() else -1
	var season: int = 0
	for i: int in SEASONS.size():
		if t.ends_with(SEASONS[i]):
			season = i
			t = t.substr(0, t.length() - 1)
			break
	if not t.is_valid_int():
		return -1
	return (int(t) - start_year) * 4 + season


## 开局（若还没开）、设托管、解析时间线。
func bind(game: JCGame) -> bool:
	if not game.is_ready():
		if not game.new_game(int(data.get("seed", 1))):
			errors.append("new_game")
			return false
	game.autosave = false
	var start: int = game.st.start_year
	var sw: Dictionary = data.get("steward", {})
	var keys: Array = sw.keys()
	keys.sort()
	for dom: Variant in keys:
		var spec: Array = sw[dom] if sw[dom] is Array else [sw[dom]]
		var mode: int = int({"off": JCSteward.OFF, "ask": JCSteward.ASK, "auto": JCSteward.AUTO}.get(String(spec[0]), JCSteward.OFF))
		var stance: String = String(spec[1]) if spec.size() > 1 else ""
		if not game.set_steward(String(dom), mode, stance):
			errors.append("bad_steward:" + String(dom))
	_tl = {}
	for e: Variant in data.get("timeline", []):
		var ed: Dictionary = e
		var q: int = parse_q(String(ed.get("at", "")), start)
		if q < 0:
			errors.append("bad_time:" + String(ed.get("at", "")))
			continue
		if not _tl.has(q):
			_tl[q] = []
		(_tl[q] as Array).append_array(ed.get("do", []))
	_bound = true
	return errors.is_empty()


func until_q(game: JCGame) -> int:
	var start: int = game.st.start_year
	var q: int = parse_q(String(data.get("until", str(start + 400))), start)
	return q if q >= 0 else 1600


## 推进到第 target 季（不超过 max_turns 回合）；返回 {ok, turns, stop}。
func step(game: JCGame, target: int, max_turns: int = 1600) -> Dictionary:
	if not _bound and not bind(game):
		return {"ok": false, "turns": 0, "stop": "bind", "errors": errors}
	var approve_all: bool = bool(data.get("approve", false))
	var advice: String = String(data.get("advice", "ignore"))
	var ev: String = String(data.get("events", ""))
	var turns: int = 0
	var stop: String = ""
	while game.st.q < target and turns < max_turns:
		var q2: int = game.st.q
		for c: Variant in _tl.get(q2, []):
			var r: Dictionary = game.order(c)
			entries.append({"q": q2, "cmd": c, "ok": bool(r.get("ok", false)), "reason": String(r.get("reason", ""))})
		if approve_all:
			game.approve_all()
		if advice == "follow":
			var top: Array = game.advisors.top(1)
			if not top.is_empty() and not (top[0]["cmds"] as Array).is_empty():
				game.accept_advice(String(top[0]["id"]))
		if ev == "first" or ev == "last":
			for pe: Dictionary in game.st.pend.duplicate():
				var ed2: Dictionary = game.ct.events[int(pe["e"])]
				var n: int = (ed2.get("options", []) as Array).size()
				game.order({"kind": "event", "event": String(ed2["id"]), "option": 0 if ev == "first" else n - 1})
		var res: Dictionary = game.end_turn()
		turns += 1
		if not bool(res.get("ok", false)):
			stop = "error:" + String(res.get("reason", ""))
			break
		if game.st.over == 1:
			stop = "over:" + game.st.over_reason
			break
	return {"ok": not stop.begins_with("error"), "turns": turns, "stop": stop, "errors": errors}


func run(game: JCGame, max_turns: int = 1600) -> Dictionary:
	if not bind(game):
		return {"ok": false, "turns": 0, "stop": "bind", "errors": errors}
	return step(game, until_q(game), max_turns)
