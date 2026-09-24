## 行动脚本（2026-09-23 用户要求）：把一局的玩家动作写成 JSON，按季度经**真实命令路径**提交并推进。
##
## 用途：调试与截图时快速走到指定年份；机制改了脚本照样能跑，不依赖旧存档。
## 脚本不改任何规则、不直接写状态：每条动作都是一条普通命令，照常经 S02 受理或拒绝。
##
## 格式（tools/playscripts/*.json，字段说明见 tools/playscripts/README.md）：
## {
##   "schema_kind": "playscript", "schema_version": 1,
##   "name": "重农商贸", "scenario": "campaign_1600", "seed": 7, "until": "1650",
##   "research": ["tech.survey", "tech.hydraulics"],            研究队列：完成一项自动换下一项
##   "events": {"default": 0, "event.E07": 1},                    选择型事件取第几个选项；"skip" 表示不选
##   "rules": {"build_cash_multiple": 2, "retry_quarters": 40},
##   "timeline": [ {"at": "1601", "do": [ {"build": "building.irrigation_region", "region": "region.beiyuan", "owner": "gov"} ]} ]
## }
## 时间写法："1650"（该年春）、"1650秋"、"q:120"（第 120 季，0 起）。
class_name JWPlayscript
extends RefCounted

const SEASONS: PackedStringArray = ["春", "夏", "秋", "冬"]

var name: String = ""
var scenario: String = ""
var seed_value: int = 1
## 推进到哪一季为止（不含）；−1 == 脚本没写，由调用方决定。
var until_q: int = -1
var errors: PackedStringArray = PackedStringArray()
## 每条动作的结果：{q, label, kind, accepted, code}。
var log: Array[Dictionary] = []

var _raw: Dictionary = {}
var _research: PackedInt64Array = PackedInt64Array()
var _research_i: int = 0
var _event_opt: Dictionary = {}
var _event_default: int = 0
var _build_mult: int = 2
var _retry_q: int = 40
## 待执行的动作：{q, label, kind, args, guard, tries, retrofit}（已解析成下标）。
var _pending: Array[Dictionary] = []
var _bound: bool = false
## 建造队列：按顺序一次一项。
var _queue: Array[Dictionary] = []
var _queue_i: int = 0


static func from_file(path: String) -> JWPlayscript:
	var ps: JWPlayscript = JWPlayscript.new()
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		ps.errors.append("读不到行动脚本：" + path)
		return ps
	var d: Variant = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		ps.errors.append("行动脚本不是 JSON 对象：" + path)
		return ps
	ps._load_dict(d)
	return ps


static func from_dict(d: Dictionary) -> JWPlayscript:
	var ps: JWPlayscript = JWPlayscript.new()
	ps._load_dict(d)
	return ps


func ok() -> bool:
	return errors.is_empty()


func _load_dict(d: Dictionary) -> void:
	_raw = d
	if String(d.get("schema_kind", "")) != "playscript":
		errors.append("schema_kind 必须是 playscript")
	name = String(d.get("name", ""))
	scenario = String(d.get("scenario", "campaign_1600"))
	seed_value = int(d.get("seed", 1))
	var rules: Dictionary = d.get("rules", {})
	_build_mult = int(rules.get("build_cash_multiple", 2))
	_retry_q = int(rules.get("retry_quarters", 40))


## 按本局载入的内容把文字 ID 与时间解析成下标。开局之后、第一次 plan() 之前调用一次。
func bind(loader: JWContentLoader, start_year: int) -> bool:
	_bound = true
	_pending.clear()
	_research = PackedInt64Array()
	_research_i = 0
	var until_v: Variant = _raw.get("until", null)
	if until_v != null:
		until_q = _parse_q(until_v, start_year)
	for t: Variant in _raw.get("research", []):
		var ti: int = loader.lookup_id(String(t))
		if ti < 0:
			errors.append("研究队列里的科技不存在：" + String(t))
		else:
			_research.append(ti)
	var ev: Dictionary = _raw.get("events", {})
	for k: String in ev.keys():
		var v: Variant = ev[k]
		var opt: int = -1 if typeof(v) == TYPE_STRING and str(v) == "skip" else int(v)
		if k == "default":
			_event_default = opt
			continue
		var e: int = loader.lookup_id(k)
		if e < 0:
			errors.append("事件不存在：" + k)
		else:
			_event_opt[e] = opt
	_event_cmds = loader.event_choice_commands
	_queue.clear()
	_queue_i = 0
	for a: Variant in _raw.get("build_queue", []):
		var qa: Dictionary = _resolve(a as Dictionary, loader)
		if qa.is_empty():
			continue
		qa["queue"] = true
		qa["tries"] = 0
		_queue.append(qa)
	var tl: Array = _raw.get("timeline", [])
	for i: int in tl.size():
		var entry: Dictionary = tl[i]
		var q: int = _parse_q(entry.get("at", "q:0"), start_year)
		if q < 0:
			errors.append("时间写法不对：" + str(entry.get("at", "")))
			continue
		for a: Variant in entry.get("do", []):
			var act: Dictionary = _resolve(a as Dictionary, loader)
			if act.is_empty():
				continue
			act["q"] = q
			act["tries"] = 0
			_pending.append(act)
	return ok()


var _event_cmds: Dictionary = {}


## "1650" / "1650秋" / "q:120" / 整数季 → 季下标；解析失败返回 −1。
static func _parse_q(v: Variant, start_year: int) -> int:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return int(v)
	var s: String = String(v).strip_edges()
	if s.begins_with("q:"):
		return int(s.substr(2)) if s.substr(2).is_valid_int() else -1
	var season: int = 0
	for i: int in SEASONS.size():
		if s.ends_with(SEASONS[i]):
			season = i
			s = s.substr(0, s.length() - 1)
	if not s.is_valid_int() or start_year <= 0:
		return -1
	return maxi((int(s) - start_year) * 4 + season, 0)


## 一条动作 → {label, kind, args, guard}；出错记入 errors 并返回空字典。
func _resolve(a: Dictionary, loader: JWContentLoader) -> Dictionary:
	if a.has("build"):
		var bt: int = loader.lookup_id(String(a["build"]))
		var r: int = loader.lookup_id(String(a.get("region", "")))
		var own: int = 1 if String(a.get("owner", "firm")) == "gov" else 0
		var m: int = 0
		if a.has("method"):
			m = loader.lookup_id(String(a["method"]))
		if bt < 0 or r < 0 or m < 0:
			errors.append("建造动作的 ID 不对：" + JSON.stringify(a))
			return {}
		return {"label": "建造 %s @ %s" % [a["build"], a.get("region", "")], "kind": JWCommands.Kind.BUILD_BUILDING,
				"args": [bt, r, own, m], "guard": "build", "bt": bt}
	if a.has("research"):
		var t: int = loader.lookup_id(String(a["research"]))
		if t < 0:
			errors.append("科技不存在：" + String(a["research"]))
			return {}
		return {"label": "研究 " + String(a["research"]), "kind": JWCommands.Kind.SET_RESEARCH_FOCUS, "args": [t],
				"guard": "research", "tech": t}
	if a.has("enact") or a.has("set_params"):
		var key: String = "enact" if a.has("enact") else "set_params"
		var p: int = loader.lookup_id(String(a[key]))
		var prm: Array = a.get("params", [0, 0, 0, 0])
		if p < 0 or prm.size() != 4:
			errors.append("政策动作不对：" + JSON.stringify(a))
			return {}
		var args: Array = [p, prm[0], prm[1], prm[2], prm[3]]
		if key == "enact":
			args.append(int(a.get("funding", 0)))
		return {"label": "%s %s" % ["颁布" if key == "enact" else "调参", a[key]],
				"kind": JWCommands.Kind.POLICY_ENACT if key == "enact" else JWCommands.Kind.POLICY_SET_PARAMS, "args": args}
	if a.has("repeal"):
		var p2: int = loader.lookup_id(String(a["repeal"]))
		if p2 < 0:
			errors.append("政策不存在：" + String(a["repeal"]))
			return {}
		return {"label": "撤销 " + String(a["repeal"]), "kind": JWCommands.Kind.POLICY_REPEAL, "args": [p2]}
	if a.has("launch"):
		var p3: int = loader.lookup_id(String(a["launch"]))
		var r3: int = loader.lookup_id(String(a.get("region", "")))
		if p3 < 0 or r3 < 0:
			errors.append("项目动作不对：" + JSON.stringify(a))
			return {}
		return {"label": "启动项目 %s @ %s" % [a["launch"], a.get("region", "")], "kind": JWCommands.Kind.PROJECT_LAUNCH,
				"args": [p3, r3, int(a.get("scale_ppm", 1_000_000)), int(a.get("funding", 0))]}
	if a.has("bond_u"):
		# 金额按 U 写（可带小数），在这里换成 μU 整数；模拟核心只见整数。
		var uu: int = int(round(float(a["bond_u"]) * 1_000_000_000.0))
		return {"label": "发债 %s U" % str(a["bond_u"]), "kind": JWCommands.Kind.ISSUE_BOND,
				"args": [uu, int(a.get("tenor_q", 8)), 1 if String(a.get("holder", "domestic")) == "foreign" else 0]}
	if a.has("trade"):
		var pn: int = loader.lookup_id(String(a["trade"]))
		var mode: int = ["export", "import", "treaty"].find(String(a.get("mode", "export")))
		var up: int = 0 if String(a.get("dir", "up")) == "down" else 1
		if pn < 0 or mode < 0:
			errors.append("贸易动作不对：" + JSON.stringify(a))
			return {}
		return {"label": "贸易 %s %s" % [a["trade"], a.get("mode", "export")], "kind": JWCommands.Kind.TRADE_ARRANGE,
				"args": [pn, mode, up]}
	if a.has("retrofit"):
		var bt2: int = 0 if String(a["retrofit"]) == "legacy" else loader.lookup_id(String(a["retrofit"]))
		var r4: int = loader.lookup_id(String(a.get("region", "")))
		var m4: int = loader.lookup_id(String(a.get("method", "")))
		var sec: int = ["agri", "manu", "energy", "services"].find(String(a.get("sector", "")))
		if bt2 < 0 or r4 < 0 or m4 < 0:
			errors.append("改造动作不对：" + JSON.stringify(a))
			return {}
		return {"label": "改造 %s @ %s → %s" % [a["retrofit"], a.get("region", ""), a.get("method", "")],
				"kind": JWCommands.Kind.RETROFIT_STACK, "args": [0, m4], "guard": "retrofit",
				"retrofit": [bt2, r4, sec]}
	if a.has("raw_kind"):
		return {"label": "原始命令 %d" % int(a["raw_kind"]), "kind": int(a["raw_kind"]),
				"args": a.get("args", [])}
	errors.append("认不出的动作：" + JSON.stringify(a))
	return {}


## 本季要提交的命令（不含推进标记）。只读 st；返回 [{kind, args, label, ref}]，ref 指回待执行动作。
## 提交顺序：研究（队列或时间线）→ 时间线其余动作 → 建造队列的下一项 → 事件回应。
func plan(st: JWSimState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var q: int = st.q
	var due: Array[Dictionary] = []
	var timeline_research: bool = false
	for act: Dictionary in _pending:
		if int(act["q"]) > q:
			continue
		var args: Variant = _ready_args(st, act)
		if args == null:
			continue
		if String(act.get("guard", "")) == "research":
			timeline_research = true
		due.append({"kind": int(act["kind"]), "args": args, "label": String(act["label"]), "ref": act})
	# 研究队列：时间线里本季没指定方向时，当前方向完成了就换下一项。
	if not timeline_research:
		while _research_i < _research.size() and (st.research.completed_mask >> _research[_research_i]) & 1 == 1:
			_research_i += 1
		if _research_i < _research.size():
			var t2: int = _research[_research_i]
			if st.research.focus != t2 and st.research.is_available(t2):
				out.append({"kind": JWCommands.Kind.SET_RESEARCH_FOCUS, "args": [t2],
						"label": "研究队列 T%d" % t2, "ref": {}})
	out.append_array(due)
	# 建造队列：一次只下一项，受理了才轮到下一项（被拒就下季再试，不跳过）。
	if _queue_i < _queue.size():
		var qa: Dictionary = _queue[_queue_i]
		var qargs: Variant = _ready_args(st, qa)
		if qargs != null:
			out.append({"kind": int(qa["kind"]), "args": qargs, "label": String(qa["label"]), "ref": qa})
	# 选择型事件：窗口开着、还没选的，按脚本给的选项回应。
	var pend: PackedInt64Array = st.politics.event_pending_until_q
	for e: int in pend.size():
		if pend[e] < 0 or q > pend[e]:
			continue
		var opt: int = int(_event_opt.get(e, _event_default))
		var opts: Array = _event_cmds.get(e, [])
		if opt < 0 or opt >= opts.size():
			continue
		var c: Dictionary = opts[opt]
		if int(c["kind"]) > 0:
			out.append({"kind": int(c["kind"]), "args": Array(c["args"]),
					"label": "事件 E%02d 选项 %d 的命令" % [e + 1, opt], "ref": {}})
		out.append({"kind": JWCommands.Kind.EVENT_CHOICE, "args": [e, opt],
				"label": "事件 E%02d 选项 %d" % [e + 1, opt], "ref": {}})
	return out


## 动作本季能不能下：能就返回参数表，不能（未解锁、钱不够、已完成、找不到建筑堆）返回 null。
func _ready_args(st: JWSimState, act: Dictionary) -> Variant:
	var g: String = String(act.get("guard", ""))
	var args: Array = (act["args"] as Array).duplicate()
	if g == "build":
		var bt: int = int(act["bt"])
		if (st.research.unlocked_building_mask() >> bt) & 1 == 0:
			return null
		if st.accounts.cash_of(JWIds.AGENT_GOV) <= st.buildings.t_cost[bt] * _build_mult:
			return null
	elif g == "research":
		var t: int = int(act["tech"])
		if (st.research.completed_mask >> t) & 1 == 1:
			act["done"] = true
			return null
		if not st.research.is_available(t) or st.research.focus == t:
			return null
	elif g == "retrofit":
		var ent: int = _find_stack(st, act["retrofit"] as Array)
		if ent < 0:
			return null
		args[0] = ent
	return args


## 结算之后登记结果：受理的动作出队；被拒的留着下季重试，超过重试期就放弃。
func settle(q: int, planned: Array[Dictionary], accepted: PackedInt64Array, codes: PackedInt64Array) -> void:
	for i: int in planned.size():
		var p: Dictionary = planned[i]
		var ok_i: bool = i < accepted.size() and accepted[i] == 1
		log.append({"q": q, "label": String(p["label"]), "kind": int(p["kind"]), "accepted": ok_i,
				"code": codes[i] if i < codes.size() else -1})
		var ref: Dictionary = p["ref"]
		if ref.is_empty():
			continue
		if bool(ref.get("queue", false)):
			if ok_i:
				_queue_i += 1
			continue
		if ok_i:
			ref["done"] = true
		else:
			ref["tries"] = int(ref["tries"]) + 1
			if int(ref["tries"]) > _retry_q:
				ref["done"] = true
				ref["gave_up"] = true
	var keep: Array[Dictionary] = []
	for act: Dictionary in _pending:
		if not bool(act.get("done", false)):
			keep.append(act)
		elif bool(act.get("gave_up", false)):
			log.append({"q": q, "label": String(act["label"]) + "（多次被拒，放弃）", "kind": int(act["kind"]),
					"accepted": false, "code": -1})
	_pending = keep


## 还没执行的动作数（含等待解锁与等钱的）。
func pending_count() -> int:
	return _pending.size() + _queue.size() - _queue_i


static func _find_stack(st: JWSimState, spec: Array) -> int:
	var bt: int = int(spec[0])
	var r: int = int(spec[1])
	var sec: int = int(spec[2])
	for b: int in st.buildings.count:
		if st.buildings.type[b] != bt:
			continue
		var c: int = st.buildings.cell[b]
		if sec >= 0:
			if c != JWIds.idx_cell(r, sec):
				continue
		else:
			var hit: bool = false
			for s: int in 4:
				if c == JWIds.idx_cell(r, s):
					hit = true
			if not hit:
				continue
		return st.buildings.entity[b]
	return -1
