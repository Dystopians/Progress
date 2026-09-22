## 测试框架自检：确认运行器能发现用例、执行断言、区分通过与失败。
extends JWTest

var _setup_marker: int = 0


func before_each() -> void:
	_setup_marker = 42


func test_before_each_runs() -> void:
	eq_int(_setup_marker, 42, "before_each 应已执行")


func test_integer_assertions() -> void:
	eq_int(2 + 2, 4, "整数加法")
	ne_int(3, 4, "整数不等")
	in_range_int(5, 1, 10, "区间断言")
	ge_int(7, 7, "不小于")
	le_int(7, 7, "不大于")


func test_packed_int64_equality() -> void:
	var a: PackedInt64Array = PackedInt64Array([1, 2, 3])
	var b: PackedInt64Array = PackedInt64Array([1, 2, 3])
	eq_int_array(a, b, "重放状态逐位比较")


func test_floor_division_convention() -> void:
	# 契约规定：整数除法一律向下取整；GDScript 的 int 除法对负数是向零取整，
	# 因此 SimCore 必须使用自己的 floor_div，本测试固定该差异的存在，防止误用内建运算符。
	eq_int(-7 / 2, -3, "GDScript 内建整数除法对负数向零取整")
	var floor_div: int = int(floor(-7.0 / 2.0))
	eq_int(floor_div, -4, "向下取整的期望结果")
