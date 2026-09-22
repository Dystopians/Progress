## 内容目录（只读静态数据）：政策、地区、集团、冲击的显示名与定义，外加界面配置。
##
## 数据来自 content/ 下的内容包 JSON（与 SimCore 载入的是同一份文件），只取展示需要的字段；
## 数值口径（成本、参数区间）以注册表里的 content.policy.* 为准，这里的副本只用于标签与说明。
## 界面配置 res://ui/config/ui_config.json 登记了剧本尚未提供、由界面暂定的量（地区主题短语、
## 情景定义、诊断阈值），每一项都带 `pending_owner` 注明应由谁接管（写进报告的接口请求）。
class_name JwCatalog
extends RefCounted

const CONTENT_ROOT: String = "res://content"
const CONFIG_PATH: String = "res://ui/config/ui_config.json"
const POLICY_N: int = 12
const REGION_N: int = 4
const SECTOR_N: int = 4
const BLOC_N: int = 3
const SHOCK_N: int = 3

## 政策种类码（与 JWPolicyDef.POLICY_KIND_* 同值；界面不引用 sim 脚本，故在此登记名字）。
const KIND_NAMES: PackedStringArray = ["rate", "transfer", "subsidy", "project", "capacity", "admin"]
const KIND_PROJECT: int = 3
const EVENT_N: int = 12
const SECTOR_IDS: PackedStringArray = ["agri", "manu", "energy", "services"]
const AGE_IDS: PackedStringArray = ["child", "working", "elder"]
const SKILL_IDS: PackedStringArray = ["low", "mid", "high"]

## 当前剧本目录名（R-SCENARIO-01；`content/scenarios/<name>/`）。
var scenario_name: String = "chengwan"

## M2 内容卡（只取展示需要的字段；数值口径以注册表里的 content.* 为准）。
var technologies: Array[Dictionary] = []
var building_types: Array[Dictionary] = []
var methods: Array[Dictionary] = []
var partners: Array[Dictionary] = []
var event_choices: Dictionary = {}

var policies: Array[Dictionary] = []
var regions: Array[Dictionary] = []
var blocs: Array[Dictionary] = []
var shocks: Array[Dictionary] = []
## 12 个事件模板的公开触发条件（docs/20 §10.4 第 9 条；R-EVENT-01）。
var events: Array[Dictionary] = []
var scenario: Dictionary = {}
var config: Dictionary = {}
var base_plan: Dictionary = {}
var loaded: bool = false


func load_all() -> void:
	if loaded:
		return
	loaded = true
	config = _json(CONFIG_PATH)
	var sdir: String = CONTENT_ROOT + "/scenarios/" + scenario_name
	scenario = _json(sdir + "/scenario.json")
	base_plan = _json(sdir + "/government_init.json").get("annual_plan", {})
	var reg: Dictionary = _json(sdir + "/regions.json")
	var themes: Array = config.get("region_themes", [])
	var i: int = 0
	for r: Variant in reg.get("regions", []):
		var rd: Dictionary = r
		regions.append({
			"idx": i,
			"id": String(rd.get("region_id", "")),
			"adjacency": rd.get("adjacency", []),
			"logistics": rd.get("logistics_cost_ppm", {}),
			"label": String(rd.get("label_zh", "")),
			"theme": String(themes[i]) if i < themes.size() else "",
		})
		i += 1
	# M2：科技卡、建筑卡、方式卡按文件名升序（与 SimCore 的下标一致）；建筑与方式的下标从 1 起。
	technologies = _load_dir(CONTENT_ROOT + "/technologies", "tech_")
	building_types = _load_dir(CONTENT_ROOT + "/buildings", "building_")
	methods = _load_dir(CONTENT_ROOT + "/methods", "method_")
	var trade_rule: Dictionary = scenario.get("trade_rule", {})
	for pd: Variant in trade_rule.get("partners", []):
		partners.append(pd)
	for e: int in EVENT_N:
		var ed: Dictionary = _json(CONTENT_ROOT + "/events/event_E%02d.json" % (e + 1))
		if ed.has("choices"):
			event_choices[e] = ed["choices"]
	var pol: Dictionary = _json(sdir + "/politics_init.json")
	for b: Variant in pol.get("blocs", []):
		var bd: Dictionary = b
		blocs.append({
			"id": String(bd.get("bloc_id", "")),
			"label": String(bd.get("label_zh", "")),
			"veto_domains": bd.get("veto_domains", []),
		})
	for k: int in SHOCK_N:
		var sd: Dictionary = _json(CONTENT_ROOT + "/shocks/shock_S%02d.json" % (k + 1))
		var mag: Dictionary = sd.get("magnitude_ppm", {})
		var dur: Dictionary = sd.get("duration_q", {})
		var arr: Dictionary = sd.get("arrival", {})
		shocks.append({
			"id": String(sd.get("shock_id", "")),
			"label": String(sd.get("label_zh", "")),
			"channel": String(sd.get("channel", "")),
			"mag_min": int(mag.get("min", 0)), "mag_max": int(mag.get("max", 0)),
			"dur_min": int(dur.get("min", 0)), "dur_max": int(dur.get("max", 0)),
			"hazard_ppm": int(arr.get("hazard_ppm_per_q", 0)),
			"earliest_q": int(arr.get("earliest_q", 0)),
			"weights": sd.get("target_weights_ppm", []),
		})
	for e: int in EVENT_N:
		var ed: Dictionary = _json(CONTENT_ROOT + "/events/event_E%02d.json" % (e + 1))
		var tr: Dictionary = ed.get("trigger", {})
		var conds: Array[Dictionary] = []
		for c: Variant in tr.get("all_of", []):
			var cd: Dictionary = c
			conds.append({"metric": String(cd.get("metric", "")), "scope": String(cd.get("scope", "")),
					"op": String(cd.get("op", "")), "value": int(cd.get("value", 0))})
		events.append({
			"code": "E%02d" % (e + 1),
			"label": String(ed.get("label_zh", "")),
			"p_ppm": int(tr.get("probability_ppm", 0)),
			"cooldown_q": int(tr.get("cooldown_q", 0)),
			"max": int(tr.get("max_occurrences", 0)),
			"conds": conds,
		})
	for p: int in POLICY_N:
		policies.append(_load_policy(p))


func _load_policy(p: int) -> Dictionary:
	var d: Dictionary = _json(CONTENT_ROOT + "/policies/policy_P%02d.json" % (p + 1))
	var la: Dictionary = d.get("legal_authority", {})
	var cost: Dictionary = d.get("cost", {})
	var lag: Dictionary = d.get("lag", {})
	var ex: Dictionary = d.get("exit_rule", {})
	var params: Array[Dictionary] = []
	var funding: Dictionary = {}
	for pp: Variant in d.get("player_params", []):
		var e: Dictionary = pp
		var key: String = String(e.get("key", ""))
		var rec: Dictionary = {
			"key": key,
			"label": String(e.get("label_zh", "")),
			"type": String(e.get("type", "")),
			"unit": String(e.get("unit", "")),
			"step": int(e.get("step", 0)) if e.has("step") else 0,
			"values": e.get("values", []),
			"range": e.get("valid_range", []),
			"popcount_max": int(e.get("popcount_max", 0)),
		}
		if key == "funding_source":
			funding = rec
		else:
			params.append(rec)
	var fails: PackedStringArray = PackedStringArray()
	for f: Variant in d.get("failure_paths", []):
		fails.append(String((f as Dictionary).get("code", "")))
	var pre: PackedStringArray = PackedStringArray()
	for c: Variant in d.get("preconditions", []):
		pre.append(String((c as Dictionary).get("kind", "")))
	var react: Dictionary = {}
	var pr: Dictionary = d.get("political_reaction", {})
	for bk: Variant in pr.keys():
		var bs: String = String(bk)
		if bs.begins_with("_"):
			continue
		var v: Variant = pr[bk]
		if v is float or v is int:
			react[bs] = int(v)
	var kind_s: String = String(d.get("kind", ""))
	return {
		"idx": p,
		"code": "P%02d" % (p + 1),
		"id": String(d.get("policy_id", "")),
		"label": String(d.get("label_zh", "")),
		"kind": kind_s,
		"kind_code": KIND_NAMES.find(kind_s),
		"authority_bit": int(la.get("authority_bit", 0)),
		"requires_budget_review": bool(la.get("requires_budget_review", false)),
		"requires_bloc_support": la.get("requires_bloc_support", []),
		"min_seats_ppm": int(la.get("min_seats_ppm", 0)),
		"params": params,
		"funding": funding,
		"one_off_uu": int(cost.get("one_off_uu", 0)),
		"per_quarter_uu": int(cost.get("per_quarter_uu", 0)),
		"planned_quarters": int(cost.get("planned_quarters", 0)),
		"opex_per_q_uu": int(cost.get("opex_per_q_uu", 0)),
		"lag_enact": int(lag.get("enact_to_effect_q", 1)),
		"lag_min": int(lag.get("min_feedback_q", 0)),
		"lag_max": int(lag.get("max_feedback_q", 0)),
		"commission_delay": int(lag.get("commission_delay_q", 1)),
		"exit_assets": String(ex.get("delivered_assets", "")),
		"exit_unfinished": String(ex.get("unfinished_work", "")),
		"exit_comp_rule": String(ex.get("compensation_rule", "")),
		"exit_comp_ppm": int(ex.get("compensation_ppm", 0)),
		"reaction": react,
		"failure_paths": fails,
		"preconditions": pre,
		"cooldown_q": int(d.get("cooldown_q", 0)),
		"toggle_cost_uu": int(d.get("toggle_cost_uu", 0)),
	}


func policy(p: int) -> Dictionary:
	if p < 0 or p >= policies.size():
		return {}
	return policies[p]


func is_project(p: int) -> bool:
	return int(policy(p).get("kind_code", -1)) == KIND_PROJECT


## 事件条件里的范围 ID → 显示名（region / cell / group / sector / policy / pubserv / bloc）。
func scope_label(scope: String) -> String:
	var parts: PackedStringArray = scope.split(".")
	if parts.size() < 2:
		return ""
	match parts[0]:
		"region", "pubserv":
			var rl: String = region_label(_region_index(parts[1]))
			return JwText.render("ev.scope.pubserv", {"region": rl}) if parts[0] == "pubserv" else rl
		"cell":
			if parts.size() >= 3:
				return JwText.render("ev.scope.cell", {"region": region_label(_region_index(parts[1])),
						"sector": JwText.t("sector.%d" % maxi(SECTOR_IDS.find(parts[2]), 0))})
		"group":
			if parts.size() >= 4:
				return JwText.render("ev.scope.group", {"region": region_label(_region_index(parts[1])),
						"age": JwText.t("age.%d" % maxi(AGE_IDS.find(parts[2]), 0)),
						"skill": JwText.t("skill.%d" % maxi(SKILL_IDS.find(parts[3]), 0))})
		"sector":
			return JwText.t("sector.%d" % maxi(SECTOR_IDS.find(parts[1]), 0))
		"policy":
			var pn: int = int(parts[1].substr(1)) - 1
			if pn >= 0 and pn < policies.size():
				return String(policies[pn].get("label", ""))
		"bloc":
			return bloc_label(bloc_index(scope))
	return ""


func _region_index(rid: String) -> int:
	for rd: Dictionary in regions:
		if String(rd["id"]) == "region." + rid:
			return int(rd["idx"])
	return -1


## 地区轮廓（ui_config.json 登记的抽象多边形，坐标空间见 map_coord_space）；缺失返回空数组。
func region_polygon(r: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if r < 0 or r >= regions.size():
		return out
	var rp: Dictionary = config.get("region_polygons", {})
	var polys: Dictionary = rp.get("polygons", {})
	for pt: Variant in polys.get(String(regions[r]["id"]), []):
		var a: Array = pt
		if a.size() >= 2:
			out.append(Vector2(float(a[0]), float(a[1])))
	return out


func map_coord_space() -> Vector2:
	var cs: Array = (config.get("region_polygons", {}) as Dictionary).get("coord_space", [1000, 700])
	return Vector2(float(cs[0]), float(cs[1])) if cs.size() >= 2 else Vector2(1000, 700)


## 剧本邻接边（无向、去重，a < b）：[[a, b, 物流成本 ppm], …]。拓扑只从 regions.json 读（docs/20 §7.2.5，AC-20）。
func adjacency_edges() -> Array:
	var out: Array = []
	for a: int in regions.size():
		var adj: Array = regions[a].get("adjacency", [])
		for bid: Variant in adj:
			var b: int = _region_index(String(bid).trim_prefix("region."))
			if b > a:
				var lc: Dictionary = regions[a].get("logistics", {})
				out.append([a, b, int(lc.get(String(bid), 0))])
	return out


func region_label(r: int) -> String:
	if r < 0 or r >= regions.size():
		return ""
	return String(regions[r]["label"])


func region_theme(r: int) -> String:
	if r < 0 or r >= regions.size():
		return ""
	return String(regions[r]["theme"])


func bloc_label(b: int) -> String:
	if b < 0 or b >= blocs.size():
		return ""
	return String(blocs[b]["label"])


func bloc_index(bloc_id: String) -> int:
	for i: int in blocs.size():
		if String(blocs[i]["id"]) == bloc_id:
			return i
	return -1


func cfg(key: String, default_value: Variant = null) -> Variant:
	return config.get(key, default_value)


## 情景定义：{id, shock_lo[3], shock_hi[3]}（界面暂定，见 ui_config.json 的 pending_owner）。
func scenario_def(id: String) -> Dictionary:
	var all: Dictionary = config.get("scenarios", {})
	return all.get(id, {})


## 情景假设的槽位（已格式化）：base/adverse 两情景三通道（出口、进口价格、信贷利差）的取值范围。
func scenario_slots() -> Dictionary:
	var out: Dictionary = {}
	for pair: Array in [["b", "base"], ["a", "adverse"]]:
		var d: Dictionary = scenario_def(String(pair[1]))
		var lo: Array = d.get("shock_lo", [0, 0, 0])
		var hi: Array = d.get("shock_hi", [0, 0, 0])
		var names: Array = ["exp", "imp", "cr"]
		for i: int in 3:
			var x: int = int(lo[i]) if i < lo.size() else 0
			var y: int = int(hi[i]) if i < hi.size() else 0
			var a: int = mini(x, y)
			var b: int = maxi(x, y)
			var key: String = String(pair[0]) + "_" + String(names[i])
			if a == b:
				out[key] = JwFormat.pct_signed(a)
			else:
				out[key] = JwText.render("fmt.span", {"lo": JwFormat.pct_signed(a), "hi": JwFormat.pct_signed(b)})
	return out


func country_label() -> String:
	return String(scenario.get("label_zh", ""))


func horizon_q() -> int:
	return int(scenario.get("horizon_q", 40))


## 剧本模式：0 单届 1 战役（R-SCENARIO-01；旧剧本不写 mode 即单届）。
func scenario_mode() -> int:
	return 1 if String(scenario.get("mode", "term")) == "campaign" else 0


## 第 0 季所在公历年（0 = 不显示年份）。
func start_year() -> int:
	return int(scenario.get("start_year", 0))


## 按前缀读一个内容目录（文件名升序）。
static func _load_dir(dir: String, prefix: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var names: PackedStringArray = DirAccess.get_files_at(dir)
	names.sort()
	for f: String in names:
		if f.begins_with(prefix) and f.ends_with(".json"):
			var fa: FileAccess = FileAccess.open(dir + "/" + f, FileAccess.READ)
			if fa == null:
				continue
			var v: Variant = JSON.parse_string(fa.get_as_text())
			fa.close()
			if v is Dictionary:
				out.append(v)
	return out


## M2：科技 / 建筑 / 方式的显示名（下标越界时给出可诊断的占位串，不静默留空）。
func tech_label(t: int) -> String:
	if t < 0 or t >= technologies.size():
		return "tech#%d" % t
	return String(technologies[t].get("label_zh", "tech#%d" % t))


func tech_desc(t: int) -> String:
	if t < 0 or t >= technologies.size():
		return ""
	return String(technologies[t].get("desc_zh", ""))


func building_label(bt: int) -> String:
	# 下标 0 是「既有设施」，不在卡片里。
	if bt <= 0 or bt - 1 >= building_types.size():
		return JwText.t("ind.legacy_building")
	return String(building_types[bt - 1].get("label_zh", "building#%d" % bt))


func building_family(bt: int) -> String:
	if bt <= 0 or bt - 1 >= building_types.size():
		return ""
	return String(building_types[bt - 1].get("family", ""))


func building_desc(bt: int) -> String:
	if bt <= 0 or bt - 1 >= building_types.size():
		return ""
	return String(building_types[bt - 1].get("desc_zh", ""))


func method_label(m: int) -> String:
	if m <= 0 or m - 1 >= methods.size():
		return JwText.t("ind.legacy_method")
	return String(methods[m - 1].get("label_zh", "method#%d" % m))


func method_desc(m: int) -> String:
	if m <= 0 or m - 1 >= methods.size():
		return ""
	return String(methods[m - 1].get("desc_zh", ""))


func partner_label(p: int) -> String:
	if p < 0 or p >= partners.size():
		return "partner#%d" % p
	return String(partners[p].get("label_zh", "partner#%d" % p))


## M2-7：建筑家族 → 图片路径模板（界面配置，不写进内容卡；资源仍待用户初审，未通过前返回空串）。
func building_art(bt: int, era_hint: int) -> String:
	var fam: String = building_family(bt)
	if fam == "":
		return ""
	var map: Dictionary = config.get("building_art", {})
	if not map.has(fam):
		return ""
	var tier: String = "early"
	if era_hint >= 5:
		tier = "modern"
	elif era_hint >= 3:
		tier = "industrial"
	var path: String = String(map[fam]).replace("{era}", tier)
	return path if ResourceLoader.exists(path) else ""


## 内容包里的全部剧本（按目录名升序）：[{name, label, mode, horizon_q, start_year}]。
static func list_scenarios() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dirs: PackedStringArray = DirAccess.get_directories_at(CONTENT_ROOT + "/scenarios")
	dirs.sort()
	for d: String in dirs:
		var f: FileAccess = FileAccess.open(CONTENT_ROOT + "/scenarios/" + d + "/scenario.json", FileAccess.READ)
		if f == null:
			continue
		var v: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if not (v is Dictionary):
			continue
		var sd: Dictionary = v
		out.append({"name": d, "label": String(sd.get("label_zh", d)),
				"mode": 1 if String(sd.get("mode", "term")) == "campaign" else 0,
				"horizon_q": int(sd.get("horizon_q", 40)), "start_year": int(sd.get("start_year", 0))})
	return out


static func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("JwCatalog: missing " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("JwCatalog: cannot parse " + path)
	return {}
