## 诊断：按 run_tests.gd 的方式先跑若干测试文件（复现跨用例的静态状态），再跑指定用例，
## 全程打开 JWResult.trace_faults，故障登记时打印调用栈。
## 用法：godot --headless --path <根> --script res://tools/diag_suite_trace.gd -- <前置文件,...> <目标文件> <目标方法>
## 例：-- res://tests/scenario/adversarial_meta_test.gd res://tests/scenario/adversarial_money_test.gd test_adv_a01_toggle_subsidy_no_backpay
extends SceneTree


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		print("用法：<前置文件,...> <目标文件> <目标方法>")
		quit(2)
		return
	JWResult.trace_faults = true
	for pre: String in args[0].split(","):
		if pre == "" or pre == "-":
			continue
		_run_all(pre)
	var gds: GDScript = load(args[1]) as GDScript
	var tc: JWTest = gds.new() as JWTest
	tc.current_test = args[2]
	tc.before_each()
	tc.call(args[2])
	tc.after_each()
	print("目标 %s：断言 %d，失败 %d" % [args[2], tc.assertion_count, tc.failures.size()])
	for f: String in tc.failures:
		print("  ✗ " + f)
	quit(0)


func _run_all(path: String) -> void:
	var gds: GDScript = load(path) as GDScript
	var probe: Object = gds.new()
	var names: PackedStringArray = PackedStringArray()
	for m: Dictionary in probe.get_method_list():
		var n: String = String(m.get("name", ""))
		if n.begins_with("test_") and not names.has(n):
			names.append(n)
	names.sort()
	var shared: JWTest = gds.new() as JWTest
	shared.before_all()
	shared.after_all()
	for n2: String in names:
		var tc: JWTest = gds.new() as JWTest
		tc.current_test = n2
		tc.before_each()
		tc.call(n2)
		tc.after_each()
	print("前置 %s：%d 个用例已跑完" % [path, names.size()])
