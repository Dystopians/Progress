## 界面文案的唯一入口（docs/21 §1：玩家可见中文只在文案资源里，代码只持 key 与槽位）。
##
## 资源：`res://ui/text/zh_cn/*.json`，每个文件是 `{"schema_version": 1, "t": {key: 文本}}`，
## 全部文件合并成一张表，key 全局唯一（重复即加载期报错，TP-01）。
## 占位符语法（docs/21 §1.3）：
##   {slot}                          命名槽位（禁止位置占位）
##   [[?slot]]……[[/]]                槽位存在且非空时渲染
##   [[*slot sep="、"]]……{.field}……[[/]]   列表段：slot 是 Array[Dictionary]
##   {{ 与 }}                        转义为 { 与 }
## 必填槽位缺失 → 整条不渲染（返回空串）并 push_error（PH-05：禁止渲染半句）。
## 槽位的值由调用方算好传入；本类不对槽位做任何算术（PH-07）。
class_name JwText
extends RefCounted

const TEXT_DIR: String = "res://ui/text/zh_cn"

static var _t: Dictionary = {}
static var _loaded: bool = false
static var _dup_keys: PackedStringArray = PackedStringArray()
static var _missing: Dictionary = {}


## 载入全部文案文件（幂等）。
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_t.clear()
	_dup_keys.clear()
	var dir: DirAccess = DirAccess.open(TEXT_DIR)
	if dir == null:
		push_error("JwText: text dir missing " + TEXT_DIR)
		return
	var files: PackedStringArray = PackedStringArray()
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".json"):
			files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	files.sort()
	for f: String in files:
		var path: String = TEXT_DIR + "/" + f
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary):
			push_error("JwText: cannot parse " + path)
			continue
		var doc: Dictionary = parsed
		var table: Variant = doc.get("t", {})
		if not (table is Dictionary):
			push_error("JwText: missing t table in " + path)
			continue
		for k: Variant in (table as Dictionary).keys():
			var key: String = String(k)
			if _t.has(key):
				_dup_keys.append(key)
				push_error("JwText: duplicate key " + key + " in " + path)
			_t[key] = String((table as Dictionary)[k])


## 强制重新载入（测试用）。
static func reload() -> void:
	_loaded = false
	ensure_loaded()


## 取一条文案（不带槽位）。缺失 → 空串 + push_error（界面不显示内部 key）。
static func t(key: String) -> String:
	ensure_loaded()
	if _t.has(key):
		return String(_t[key])
	_note_missing(key)
	return ""


## 取一条文案；key 不存在时取 fallback_key（码表类文案用：未登记的码不报缺失，显示「未登记」）。
static func t_or(key: String, fallback_key: String) -> String:
	ensure_loaded()
	if _t.has(key):
		return String(_t[key])
	return t(fallback_key)


static func has(key: String) -> bool:
	ensure_loaded()
	return _t.has(key)


## 全部 key（lint 与测试用）。
static func keys() -> PackedStringArray:
	ensure_loaded()
	var out: PackedStringArray = PackedStringArray()
	for k: Variant in _t.keys():
		out.append(String(k))
	out.sort()
	return out


static func duplicate_keys() -> PackedStringArray:
	ensure_loaded()
	return _dup_keys.duplicate()


static func missing_keys() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k: Variant in _missing.keys():
		out.append(String(k))
	return out


## 渲染一条模板。slots 的值是已格式化的字符串（或列表段用的 Array[Dictionary]）。
static func render(key: String, slots: Dictionary = {}) -> String:
	ensure_loaded()
	if not _t.has(key):
		_note_missing(key)
		return ""
	var tpl: String = String(_t[key])
	var ok: Array[bool] = [true]
	var out: String = _render_str(tpl, slots, ok, key)
	if not ok[0]:
		return ""
	return out


## 渲染模板正文（不查表）；供测试与内部嵌套使用。
static func render_raw(tpl: String, slots: Dictionary) -> String:
	var ok: Array[bool] = [true]
	var out: String = _render_str(tpl, slots, ok, "<raw>")
	if not ok[0]:
		return ""
	return out


static func _render_str(tpl: String, slots: Dictionary, ok: Array[bool], key: String) -> String:
	var out: String = ""
	var i: int = 0
	var n: int = tpl.length()
	while i < n:
		if tpl.substr(i, 2) == "{{":
			out += "{"
			i += 2
			continue
		if tpl.substr(i, 2) == "}}":
			out += "}"
			i += 2
			continue
		if tpl.substr(i, 3) == "[[?":
			var close: int = tpl.find("]]", i)
			var end_tag: int = tpl.find("[[/]]", close)
			if close < 0 or end_tag < 0:
				push_error("JwText: unclosed conditional in " + key)
				ok[0] = false
				return ""
			var slot: String = tpl.substr(i + 3, close - i - 3).strip_edges()
			var body: String = tpl.substr(close + 2, end_tag - close - 2)
			if slots.has(slot) and str(slots[slot]) != "":
				out += _render_str(body, slots, ok, key)
			i = end_tag + 5
			continue
		if tpl.substr(i, 3) == "[[*":
			var close2: int = tpl.find("]]", i)
			var end2: int = tpl.find("[[/]]", close2)
			if close2 < 0 or end2 < 0:
				push_error("JwText: unclosed list in " + key)
				ok[0] = false
				return ""
			var head: String = tpl.substr(i + 3, close2 - i - 3).strip_edges()
			var sep: String = ""
			var slot2: String = head
			var sp: int = head.find(" ")
			if sp > 0:
				slot2 = head.substr(0, sp)
				var rest: String = head.substr(sp + 1)
				var q1: int = rest.find("\"")
				var q2: int = rest.rfind("\"")
				if q1 >= 0 and q2 > q1:
					sep = rest.substr(q1 + 1, q2 - q1 - 1)
			var body2: String = tpl.substr(close2 + 2, end2 - close2 - 2)
			if not slots.has(slot2):
				push_error("JwText: missing list slot " + slot2 + " in " + key)
				ok[0] = false
				return ""
			var items: Variant = slots[slot2]
			if items is Array:
				var parts: PackedStringArray = PackedStringArray()
				for it: Variant in items as Array:
					var d: Dictionary = it if it is Dictionary else {"value": str(it)}
					parts.append(_render_item(body2, d, slots, ok, key))
				out += sep.join(parts)
			i = end2 + 5
			continue
		if tpl[i] == "{":
			var close3: int = tpl.find("}", i)
			if close3 < 0:
				push_error("JwText: unclosed slot in " + key)
				ok[0] = false
				return ""
			var name: String = tpl.substr(i + 1, close3 - i - 1)
			if not slots.has(name):
				push_error("JwText: missing required slot {" + name + "} in " + key)
				ok[0] = false
				return ""
			out += str(slots[name])
			i = close3 + 1
			continue
		out += tpl[i]
		i += 1
	return out


static func _render_item(body: String, item: Dictionary, slots: Dictionary, ok: Array[bool],
		key: String) -> String:
	var out: String = ""
	var i: int = 0
	var n: int = body.length()
	while i < n:
		if body.substr(i, 2) == "{.":
			var close: int = body.find("}", i)
			if close < 0:
				ok[0] = false
				return ""
			var field: String = body.substr(i + 2, close - i - 2)
			if not item.has(field):
				push_error("JwText: missing list field {." + field + "} in " + key)
				ok[0] = false
				return ""
			out += str(item[field])
			i = close + 1
			continue
		if body[i] == "{" and body.substr(i, 2) != "{{":
			var close2: int = body.find("}", i)
			if close2 < 0:
				ok[0] = false
				return ""
			var name: String = body.substr(i + 1, close2 - i - 1)
			if not slots.has(name):
				ok[0] = false
				return ""
			out += str(slots[name])
			i = close2 + 1
			continue
		out += body[i]
		i += 1
	return out


static func _note_missing(key: String) -> void:
	if not _missing.has(key):
		_missing[key] = true
		push_error("JwText: missing text key " + key)
