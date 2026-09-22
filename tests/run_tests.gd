## 经纬无界面测试运行器。
##
## 用法：
##   godot --headless --path <项目根> --script res://tests/run_tests.gd -- [--suite=unit] [--filter=ledger] [--verbose]
##
## 退出码：0 全部通过；1 存在失败；2 运行器自身出错（找不到用例目录等）。
extends SceneTree

const SUITES: Array[String] = ["unit", "replay", "scenario", "stress", "ui"]
const TESTS_ROOT: String = "res://tests"

var _suite_filter: String = ""
var _name_filter: String = ""
var _verbose: bool = false

var _total_files: int = 0
var _total_tests: int = 0
var _total_assertions: int = 0
var _failed_tests: int = 0
var _failure_lines: PackedStringArray = PackedStringArray()
var _slowest: Array = []
var _errors: ErrorCounter = ErrorCounter.new()


## 运行错误计数（Godot 4.5+ 的 Logger）。GDScript 的运行错误只中止出错的那个函数，调用方照常往下走：
## 测试函数可能因此提前退出、没有任何失败断言却记为通过（2026-09-21：四个配给用例的辅助数组
## 比买方类少一格，就这样空跑了）。运行器逐用例取计数：脚本运行错误、以及在脚本执行中触发的
## 引擎错误（格式化失败、push_error 等）都判该用例失败；故意触发的条数由用例的
## `expected_engine_errors` 声明。警告不计。
class ErrorCounter extends Logger:
	var count: int = 0
	var first: String = ""
	var _m: Mutex = Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING or error_type == ERROR_TYPE_SHADER:
			return
		if error_type != ERROR_TYPE_SCRIPT and script_backtraces.is_empty():
			return
		var where: String = "%s:%d %s" % [file, line, function]
		for bt: ScriptBacktrace in script_backtraces:
			if bt != null and bt.get_frame_count() > 0:
				where = "%s:%d %s" % [bt.get_frame_file(0), bt.get_frame_line(0), bt.get_frame_function(0)]
				break
		_m.lock()
		count += 1
		if first == "":
			first = "%s（%s）" % [rationale if rationale != "" else code, where]
		_m.unlock()

	## 取出并清零：[条数, 第一条的说明]。
	func take() -> Array:
		_m.lock()
		var r: Array = [count, first]
		count = 0
		first = ""
		_m.unlock()
		return r


func _init() -> void:
	_parse_args()
	var files: PackedStringArray = _collect_test_files()
	if files.is_empty():
		print("[经纬测试] 未找到任何 *_test.gd 用例（suite 过滤=\"%s\"）" % _suite_filter)
		quit(0)
		return

	OS.add_logger(_errors)
	var started_us: int = Time.get_ticks_usec()
	for path: String in files:
		_run_file(path)
	var elapsed_ms: int = int((Time.get_ticks_usec() - started_us) / 1000)
	OS.remove_logger(_errors)

	_report(elapsed_ms)
	quit(1 if _failed_tests > 0 else 0)


func _parse_args() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--suite="):
			_suite_filter = a.substr(8)
		elif a.begins_with("--filter="):
			_name_filter = a.substr(9)
		elif a == "--verbose":
			_verbose = true


func _collect_test_files() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for suite: String in SUITES:
		if _suite_filter != "" and suite != _suite_filter:
			continue
		_walk("%s/%s" % [TESTS_ROOT, suite], out)
	out.sort()
	return out


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
		elif entry.ends_with("_test.gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _run_file(path: String) -> void:
	var script: Resource = load(path)
	if script == null or not (script is GDScript):
		_failed_tests += 1
		_failure_lines.append("！无法加载测试脚本：%s" % path)
		return
	var gds: GDScript = script as GDScript
	var probe: Object = gds.new()
	if probe == null:
		_failed_tests += 1
		_failure_lines.append("！无法实例化测试脚本（是否继承 JWTest？）：%s" % path)
		return
	if not (probe is JWTest):
		_failed_tests += 1
		_failure_lines.append("！测试脚本未继承 JWTest：%s" % path)
		return

	var method_names: PackedStringArray = PackedStringArray()
	for m: Dictionary in probe.get_method_list():
		var mname: String = String(m.get("name", ""))
		if mname.begins_with("test_") and not method_names.has(mname):
			if _name_filter == "" or mname.findn(_name_filter) >= 0 or path.findn(_name_filter) >= 0:
				method_names.append(mname)
	method_names.sort()
	if method_names.is_empty():
		return

	_total_files += 1
	var display: String = path.replace(TESTS_ROOT + "/", "")

	var shared: JWTest = gds.new() as JWTest
	shared.before_all()
	shared.after_all()

	for mname: String in method_names:
		var tc: JWTest = gds.new() as JWTest
		tc.current_test = mname
		_total_tests += 1
		var t0: int = Time.get_ticks_usec()
		_errors.take()
		tc.before_each()
		tc.call(mname)
		tc.after_each()
		var err: Array = _errors.take()
		var dt_us: int = Time.get_ticks_usec() - t0
		_slowest.append({"name": "%s::%s" % [display, mname], "us": dt_us})
		_total_assertions += tc.assertion_count
		if int(err[0]) > tc.expected_engine_errors:
			tc.failures.append("执行期间出现 %d 条运行错误（声明预期 %d 条），首条：%s"
					% [int(err[0]), tc.expected_engine_errors, String(err[1])])

		if tc.failures.size() > 0:
			_failed_tests += 1
			for f: String in tc.failures:
				_failure_lines.append("  ✗ %s::%s\n      %s" % [display, mname, f])
		elif tc.assertion_count == 0:
			_failed_tests += 1
			_failure_lines.append("  ✗ %s::%s\n      该测试没有执行任何断言（空测试视为失败）" % [display, mname])
		elif _verbose:
			print("  ✓ %s::%s（%d 断言，%.1f ms）" % [display, mname, tc.assertion_count, dt_us / 1000.0])


func _report(elapsed_ms: int) -> void:
	print("")
	print("──────────── 经纬测试报告 ────────────")
	print("用例文件 %d ｜ 测试 %d ｜ 断言 %d ｜ 耗时 %d ms" % [_total_files, _total_tests, _total_assertions, elapsed_ms])
	if _failure_lines.size() > 0:
		print("")
		print("失败明细：")
		for line: String in _failure_lines:
			print(line)
	if _verbose and _slowest.size() > 0:
		_slowest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["us"]) > int(b["us"]))
		print("")
		print("最慢 5 项：")
		for i: int in mini(5, _slowest.size()):
			var e: Dictionary = _slowest[i]
			print("  %.1f ms  %s" % [int(e["us"]) / 1000.0, String(e["name"])])
	print("")
	if _failed_tests > 0:
		print("结果：失败 %d / %d" % [_failed_tests, _total_tests])
	else:
		print("结果：全部通过 ✓（%d 项）" % _total_tests)
	print("──────────────────────────────────────")
