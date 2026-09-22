## 解析闸门：加载项目内每一个 .gd 脚本，报告无法解析的文件。
##
## 用法：godot --headless --path <项目根> --script res://tools/parse_check.gd
## 退出码：0 全部可解析；1 存在解析失败。
extends SceneTree

const SELF_PATH: String = "res://tools/parse_check.gd"
const SCAN_DIRS: Array[String] = ["res://sim", "res://systems", "res://application", "res://ui", "res://tests", "res://tools"]

var _ok: int = 0
var _bad: PackedStringArray = PackedStringArray()


func _init() -> void:
	var files: PackedStringArray = PackedStringArray()
	for d: String in SCAN_DIRS:
		_walk(d, files)
	files.sort()
	for f: String in files:
		if f == SELF_PATH:
			continue
		var res: Resource = load(f)
		# load() 对有解析错误的脚本仍会返回一个 GDScript 对象（只是编译失败），
		# 只判「非空且是 GDScript」会把坏文件记成可解析；can_instantiate() 在编译失败时为 false。
		if res == null or not (res is GDScript) or not (res as GDScript).can_instantiate():
			_bad.append(f)
		else:
			_ok += 1
	print("")
	print("──────────── 解析闸门 ────────────")
	print("可解析 %d ｜ 失败 %d ｜ 总计 %d" % [_ok, _bad.size(), files.size() - 1])
	if _bad.size() > 0:
		print("失败文件（详细错误见上方 SCRIPT ERROR 行）：")
		for f: String in _bad:
			print("  ✗ %s" % f)
	print("──────────────────────────────────")
	quit(1 if _bad.size() > 0 else 0)


func _walk(dir_path: String, out: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full: String = "%s/%s" % [dir_path, entry]
		if dir.current_is_dir():
			_walk(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
