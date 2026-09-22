## 经纬测试基类。
##
## 所有测试文件继承本类，文件名以 `_test.gd` 结尾，测试方法以 `test_` 开头。
## 断言全部面向整数与确定性断言——SimCore 内禁止 float，测试里也不做浮点近似比较。
class_name JWTest
extends RefCounted

## 本次测试方法收集到的失败信息。
var failures: PackedStringArray = PackedStringArray()
## 本次测试方法执行的断言次数（断言数为 0 的测试会被判为可疑）。
var assertion_count: int = 0
## 当前正在执行的测试方法名，由运行器写入。
var current_test: String = ""
## 整套测试文件的可选说明，显示在报告里。
var suite_note: String = ""
## 本用例**故意**触发的引擎错误条数（例如校验「缺失即 push_error」）。运行器把用例执行期间
## 由脚本触发的运行错误与引擎错误逐条计数，超出本数即判该用例失败（见 run_tests.gd 的 ErrorCounter）。
var expected_engine_errors: int = 0


## 每个测试方法执行前调用。
func before_each() -> void:
	pass


## 每个测试方法执行后调用。
func after_each() -> void:
	pass


## 整个测试文件执行前调用一次。
func before_all() -> void:
	pass


## 整个测试文件执行后调用一次。
func after_all() -> void:
	pass


## 直接记一条失败。
func fail(message: String) -> void:
	failures.append(message)


## 布尔断言。
func check(condition: bool, message: String) -> void:
	assertion_count += 1
	if not condition:
		fail("%s —— 条件不成立" % message)


## 布尔断言（期望为假）。
func check_false(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		fail("%s —— 期望为假，实际为真" % message)


## 整数相等断言。SimCore 的一切数值比较都应走这里。
func eq_int(actual: int, expected: int, message: String) -> void:
	assertion_count += 1
	if actual != expected:
		fail("%s —— 期望 %d，实际 %d，差 %d" % [message, expected, actual, actual - expected])


## 整数不等断言。
func ne_int(actual: int, forbidden: int, message: String) -> void:
	assertion_count += 1
	if actual == forbidden:
		fail("%s —— 值不应等于 %d" % [message, forbidden])


## 整数区间断言（闭区间）。
func in_range_int(actual: int, low: int, high: int, message: String) -> void:
	assertion_count += 1
	if actual < low or actual > high:
		fail("%s —— 期望落在 [%d, %d]，实际 %d" % [message, low, high, actual])


## 整数不小于断言。
func ge_int(actual: int, floor_value: int, message: String) -> void:
	assertion_count += 1
	if actual < floor_value:
		fail("%s —— 期望 ≥ %d，实际 %d" % [message, floor_value, actual])


## 整数不大于断言。
func le_int(actual: int, ceil_value: int, message: String) -> void:
	assertion_count += 1
	if actual > ceil_value:
		fail("%s —— 期望 ≤ %d，实际 %d" % [message, ceil_value, actual])


## 字符串相等断言。
func eq_str(actual: String, expected: String, message: String) -> void:
	assertion_count += 1
	if actual != expected:
		fail("%s —— 期望 \"%s\"，实际 \"%s\"" % [message, expected, actual])


## 通用相等断言（用于 Dictionary / Array 等结构，走 Variant 深比较）。
func eq_var(actual: Variant, expected: Variant, message: String) -> void:
	assertion_count += 1
	if actual != expected:
		fail("%s —— 期望 %s，实际 %s" % [message, str(expected), str(actual)])


## 断言两个整数数组逐位相同（重放确定性检查的主力）。
func eq_int_array(actual: PackedInt64Array, expected: PackedInt64Array, message: String) -> void:
	assertion_count += 1
	if actual.size() != expected.size():
		fail("%s —— 长度不同：期望 %d，实际 %d" % [message, expected.size(), actual.size()])
		return
	for i: int in actual.size():
		if actual[i] != expected[i]:
			fail("%s —— 第 %d 位不同：期望 %d，实际 %d" % [message, i, expected[i], actual[i]])
			return


## 断言字典包含某个键。
func has_key(dict: Dictionary, key: Variant, message: String) -> void:
	assertion_count += 1
	if not dict.has(key):
		fail("%s —— 缺少键 %s" % [message, str(key)])


## 断言某个 Callable 会推入错误（Godot 无异常，约定被测代码返回错误码或写入 errors 列表时使用 check 即可）。
## 保留此方法是为了让「必须被拒绝的命令」类测试有统一写法。
func rejects(result_code: int, ok_code: int, message: String) -> void:
	assertion_count += 1
	if result_code == ok_code:
		fail("%s —— 期望该操作被拒绝，实际被接受" % message)
