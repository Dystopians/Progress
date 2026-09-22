## JWMath 单元测试：整数定点算术的三条铁律（docs/10 §0.9）与溢出守卫（docs/10 §13）。
##
## 覆盖点：负数取整方向、除零、int64 溢出边界、ppm 单次取整、最大余数法的和恒等、
## 同分时的确定性、空权重、总额为 0、权重全 0、SPLIT_MAX_N 边界。
##
## 纪律：JWResult 的故障登记是静态的，会跨测试方法残留；每个方法前必须 clear_pending()，
## 否则「第一次故障不被覆盖」的语义会让后面的断言读到上一个测试的现场。
extends JWTest

## floor(INT64_MAX / 2)，乘 2 恰好等于 INT64_MAX - 1，是溢出守卫的临界通过点。
const HALF_MAX: int = 4_611_686_018_427_387_903


func before_each() -> void:
	JWResult.clear_pending()
	JWResult.set_step(0)


func after_each() -> void:
	JWResult.clear_pending()


# ── floor_div ──────────────────────────────────────────────────────────────

func test_floor_div_rounds_toward_negative_infinity() -> void:
	eq_int(JWMath.floor_div(7, 2), 3, "正/正 除不尽")
	eq_int(JWMath.floor_div(-7, 2), -4, "负/正 必须向 −∞，不是向零的 −3")
	eq_int(JWMath.floor_div(7, -2), -4, "正/负 必须向 −∞")
	eq_int(JWMath.floor_div(-7, -2), 3, "负/负 结果为正")
	eq_int(JWMath.floor_div(-6, 2), -3, "整除时不额外减 1")
	eq_int(JWMath.floor_div(6, -2), -3, "整除时不额外减 1（异号）")
	eq_int(JWMath.floor_div(0, 5), 0, "0 除以任意非零为 0")
	eq_int(JWMath.floor_div(-1, 2), -1, "−1/2 向 −∞ 为 −1")
	eq_int(JWMath.floor_div(1, -2), -1, "1/−2 向 −∞ 为 −1")
	eq_int(JWMath.floor_div(1, 2), 0, "1/2 为 0")


func test_floor_div_differs_from_builtin_on_negatives() -> void:
	# 这条测试的作用是把「为什么不能用裸 /」钉死：内建 / 对负数向零截断。
	@warning_ignore("integer_division")
	var builtin: int = -7 / 2
	eq_int(builtin, -3, "GDScript 内建整数除法向零截断")
	eq_int(JWMath.floor_div(-7, 2), -4, "契约要求的 floor 语义与内建不同")
	ne_int(JWMath.floor_div(-7, 2), builtin, "两者必须不同，否则说明有人把 floor_div 写成了裸除法")


func test_floor_div_by_zero_registers_fault() -> void:
	eq_int(JWMath.floor_div(5, 0), 0, "除零返回 0")
	check(JWResult.has_pending(), "除零必须登记故障，不得静默返回")
	eq_int(JWResult.pending_code(), JWResult.Fault.DIV_ZERO, "故障码为 DIV_ZERO")


func test_floor_div_int64_min_over_minus_one_is_guarded() -> void:
	# 真值 INT64_MAX + 1，int64 装不下。必须显式报溢出而不是静默回卷成 INT64_MIN。
	eq_int(JWMath.floor_div(JWMath.INT64_MIN, -1), 0, "INT64_MIN / −1 被守卫拦下")
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW, "登记 INT_OVERFLOW")


func test_floor_div_extremes() -> void:
	eq_int(JWMath.floor_div(JWUnits.INT64_MAX, 1), JWUnits.INT64_MAX, "最大值除以 1")
	eq_int(JWMath.floor_div(JWUnits.INT64_MAX, JWUnits.INT64_MAX), 1, "自除为 1")
	eq_int(JWMath.floor_div(JWMath.INT64_MIN, 1), JWMath.INT64_MIN, "最小值除以 1")
	eq_int(JWMath.floor_div(JWMath.INT64_MIN, 2), -HALF_MAX - 1, "最小值折半仍精确")
	check_false(JWResult.has_pending(), "以上都是合法运算，不应有故障")


# ── ceil_div ───────────────────────────────────────────────────────────────

func test_ceil_div_rounds_toward_positive_infinity() -> void:
	eq_int(JWMath.ceil_div(7, 2), 4, "正/正 除不尽向上")
	eq_int(JWMath.ceil_div(-7, 2), -3, "负/正 向 +∞ 为 −3")
	eq_int(JWMath.ceil_div(7, -2), -3, "正/负 向 +∞ 为 −3")
	eq_int(JWMath.ceil_div(-7, -2), 4, "负/负 向上")
	eq_int(JWMath.ceil_div(6, 2), 3, "整除时不额外加 1")
	eq_int(JWMath.ceil_div(0, 5), 0, "0 的上取整仍为 0")


func test_ceil_div_equals_negated_floor_div() -> void:
	# 后置条件：ceil_div(a,b) == -floor_div(-a,b)，逐组核对。
	var xs: PackedInt64Array = PackedInt64Array([-13, -7, -1, 0, 1, 7, 13, 1_000_001])
	var ys: PackedInt64Array = PackedInt64Array([-7, -3, -1, 1, 3, 7, 1_000_000])
	var checked: int = 0
	for i: int in xs.size():
		for j: int in ys.size():
			if JWMath.ceil_div(xs[i], ys[j]) != -JWMath.floor_div(-xs[i], ys[j]):
				fail("ceil_div(%d, %d) 与 −floor_div(−a,b) 不一致" % [xs[i], ys[j]])
			checked += 1
	eq_int(checked, xs.size() * ys.size(), "全部组合都比对过")
	check_false(JWResult.has_pending(), "合法输入不应登记故障")


func test_ceil_div_never_underdraws() -> void:
	# INV-046：产量 → 投入消耗用 ceil，反算回去绝不能少于原值（不透支引理）。
	var need: PackedInt64Array = PackedInt64Array([1, 2, 999_999, 1_000_000, 1_000_001, 7_000_003])
	var per: PackedInt64Array = PackedInt64Array([1, 3, 7, 1_000_000])
	for i: int in need.size():
		for j: int in per.size():
			var units: int = JWMath.ceil_div(need[i], per[j])
			ge_int(units * per[j], need[i], "ceil 反算不得透支")


func test_ceil_div_by_zero_registers_fault() -> void:
	eq_int(JWMath.ceil_div(5, 0), 0, "除零返回 0")
	eq_int(JWResult.pending_code(), JWResult.Fault.DIV_ZERO, "与 floor_div 同码")


func test_ceil_div_int64_min_is_guarded() -> void:
	eq_int(JWMath.ceil_div(JWMath.INT64_MIN, 2), 0, "取反会溢出，必须拦下")
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW, "登记 INT_OVERFLOW")


# ── mul 溢出守卫（M0 / INV-006） ────────────────────────────────────────────

func test_mul_basic() -> void:
	eq_int(JWMath.mul(3, 4), 12, "正×正")
	eq_int(JWMath.mul(-3, 4), -12, "负×正")
	eq_int(JWMath.mul(3, -4), -12, "正×负")
	eq_int(JWMath.mul(-3, -4), 12, "负×负")
	eq_int(JWMath.mul(0, JWUnits.INT64_MAX), 0, "0 × 极大值短路为 0")
	eq_int(JWMath.mul(JWUnits.INT64_MAX, 0), 0, "极大值 × 0 短路为 0")
	eq_int(JWMath.mul(JWUnits.INT64_MAX, 1), JWUnits.INT64_MAX, "× 1 不动")
	check_false(JWResult.has_pending(), "以上都在裕度内")


func test_mul_overflow_boundary() -> void:
	# 恰好落在上界内：HALF_MAX × 2 == INT64_MAX − 1。
	eq_int(JWMath.mul(HALF_MAX, 2), JWUnits.INT64_MAX - 1, "临界内正常相乘")
	check_false(JWResult.has_pending(), "临界内不应报溢出")
	# 再多 1 就越界。
	eq_int(JWMath.mul(HALF_MAX + 1, 2), 0, "越界返回 0，不做饱和截断")
	check(JWResult.has_pending(), "越界必须登记故障")
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW, "故障码为 INT_OVERFLOW")


func test_mul_overflow_is_symmetric_in_sign() -> void:
	eq_int(JWMath.mul(-(HALF_MAX + 1), 2), 0, "负方向越界同样拦下（不靠积的符号判断）")
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW, "登记 INT_OVERFLOW")


func test_mul_int64_min_operand_is_guarded() -> void:
	# INT64_MIN 没有正的绝对值，按 |a| > INT64_MAX/|b| 判定会读到错误的绝对值，必须先挡掉。
	eq_int(JWMath.mul(JWMath.INT64_MIN, 1), 0, "INT64_MIN 作乘数一律保守拒绝")
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW, "登记 INT_OVERFLOW")


func test_mul_at_contract_ceilings() -> void:
	# 裁定 R-SCALE-01 之后（1 U = 1e9 μU），docs/10 §13 的最紧处分成两类：
	# 仍能裸乘的，和必须走 mul_div_floor 的。这条测试把两类都钉死。
	# 仍在裸乘裕度内：qty(1e12) × ppm(1e6) == 1e18 < 9.22e18
	eq_int(JWMath.mul(JWUnits.QTY_MAX, JWUnits.PPM), 1_000_000_000_000_000_000,
			"qty × 1e6 == 1e18，裸乘仍安全")
	check_false(JWResult.has_pending(), "该处不应报溢出")


func test_scaled_ceilings_require_mul_div_floor() -> void:
	# R-SCALE-01 的核心后果：金额刻度细化 1000 倍后，AMOUNT_MAX × PPM 与
	# QTY_MAX × PRICE_MAX 的**中间量**都超出 int64，必须先拆商再乘。
	# 这也是 mul_div_floor 存在的唯一理由——先证明裸乘真的会炸。
	eq_int(JWMath.mul(JWUnits.AMOUNT_MAX, JWUnits.PPM), 0,
			"裸乘 amount×ppm 在新刻度下溢出，按契约返回 0")
	check(JWResult.has_pending(), "溢出必须登记故障，不得静默回卷")
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW, "故障码必须是 INT_OVERFLOW")
	JWResult.clear_pending()

	eq_int(JWMath.mul(JWUnits.QTY_MAX, JWUnits.PRICE_MAX), 0,
			"裸乘 qty×price_max 同样溢出")
	check(JWResult.has_pending(), "溢出必须登记故障")
	JWResult.clear_pending()

	# mul_div_floor 在同样的输入上必须给出精确真值且不报故障。
	# floor(AMOUNT_MAX × PPM / PPM) == AMOUNT_MAX
	eq_int(JWMath.mul_div_floor(JWUnits.AMOUNT_MAX, JWUnits.PPM, JWUnits.PPM),
			JWUnits.AMOUNT_MAX, "mul_div_floor 在金额上界处恒等")
	# floor(QTY_MAX × PRICE_MAX / Q_SCALE) == 1e12 × 2.5e9 / 1e6 == 2.5e15
	eq_int(JWMath.mul_div_floor(JWUnits.QTY_MAX, JWUnits.PRICE_MAX, JWUnits.Q_SCALE),
			2_500_000_000_000_000, "数量×价格折算金额，中间量不溢出")
	# 余数不得丢失：floor(7 × 1e6 / 3) == 2333333
	eq_int(JWMath.mul_div_floor(7, JWUnits.PPM, 3), 2_333_333, "余数按 floor 处理")
	# 负数走 floor 而非向零
	eq_int(JWMath.mul_div_floor(-7, JWUnits.PPM, 3), -2_333_334, "负数向 −∞ 取整")
	check_false(JWResult.has_pending(), "mul_div_floor 在契约上界内不应报故障")


# ── mul_ppm / mul_ppm_2 ────────────────────────────────────────────────────

func test_mul_ppm_single_rounding() -> void:
	eq_int(JWMath.mul_ppm(1_000_000, 500_000), 500_000, "一半")
	eq_int(JWMath.mul_ppm(1_000_000, JWUnits.PPM), 1_000_000, "系数 1.0 恒等")
	eq_int(JWMath.mul_ppm(7, 500_000), 3, "3.5 向下取整为 3")
	eq_int(JWMath.mul_ppm(-7, 500_000), -4, "−3.5 向 −∞ 取整为 −4，不是 −3")
	eq_int(JWMath.mul_ppm(123, 0), 0, "系数 0")
	eq_int(JWMath.mul_ppm(JWUnits.BASE_YEAR_GDP_UU, JWUnits.PPM), JWUnits.BASE_YEAR_GDP_UU,
			"基年 GDP 乘 1.0 不变")


func test_mul_ppm_2_rounds_only_once() -> void:
	# M2：先合成系数再缩放。与「连乘两次 mul_ppm」的结果必须不同，否则说明双重取整没被消除。
	var once: int = JWMath.mul_ppm_2(1000, 333_333, 333_333)
	var twice: int = JWMath.mul_ppm(JWMath.mul_ppm(1000, 333_333), 333_333)
	eq_int(once, 111, "合成系数 111110 ppm，1000 × 0.111110 == 111")
	eq_int(twice, 110, "双重取整会掉到 110")
	ne_int(once, twice, "两者必须不同，这就是禁止连乘两个 ppm 的原因")


func test_mul_ppm_2_identity_coefficients() -> void:
	eq_int(JWMath.mul_ppm_2(12_345, JWUnits.PPM, JWUnits.PPM), 12_345, "两个 1.0 系数恒等")
	eq_int(JWMath.mul_ppm_2(12_345, JWUnits.PPM, 0), 0, "任一系数为 0 则结果为 0")
	check_false(JWResult.has_pending(), "合法输入不登记故障")


# ── split_lr_into：和恒等（INV-003） ───────────────────────────────────────

func test_split_sum_identity_across_cases() -> void:
	var totals: PackedInt64Array = PackedInt64Array([0, 1, 2, 7, 10, 99, 100, 1_000_003])
	var weights: PackedInt64Array = PackedInt64Array([1, 2, 3, 5, 7])
	var tiebreak: PackedInt64Array = PackedInt64Array([0, 1, 2, 3, 4])
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(weights.size())
	for i: int in totals.size():
		var residual: int = JWMath.split_lr_into(totals[i], weights, tiebreak, out)
		eq_int(residual, 0, "权重和非零时残差必须为 0")
		eq_int(JWMath.sum(out), totals[i], "Σ 分项 == 总额（INV-003）")
	check_false(JWResult.has_pending(), "正常拆分不登记故障")


func test_split_every_item_nonnegative_and_bounded() -> void:
	var weights: PackedInt64Array = PackedInt64Array([10, 1, 1, 1])
	var tiebreak: PackedInt64Array = PackedInt64Array([0, 1, 2, 3])
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(4)
	eq_int(JWMath.split_lr_into(1_000, weights, tiebreak, out), 0, "正常拆分")
	for i: int in out.size():
		ge_int(out[i], 0, "非负总额拆分不得产生负分项")
	eq_int(JWMath.sum(out), 1_000, "和恒等")
	# 精确份额 10/13 × 1000 ≈ 769.23，1/13 × 1000 ≈ 76.92：
	# 整除部分 [769, 76, 76, 76] 余 3 个单位，余数 [3, 12, 12, 12] 里后三项并列且最大，
	# 按决胜键升序各得 1。每一项与精确份额的差不超过 1 —— 最大余数法的定义性质。
	eq_int(out[0], 769, "大权重项拿整除部分 769，不因为权重大就多分")
	eq_int_array(out, PackedInt64Array([769, 77, 77, 77]), "逐位固定，防止实现漂移")


func test_split_tie_uses_tiebreak_then_index() -> void:
	var weights: PackedInt64Array = PackedInt64Array([1, 1, 1])
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(3)
	# 余数全部并列：决胜键升序决定谁多拿 1。
	eq_int(JWMath.split_lr_into(10, weights, PackedInt64Array([0, 1, 2]), out), 0, "拆分成功")
	eq_int_array(out, PackedInt64Array([4, 3, 3]), "决胜键 0 最小，下标 0 多拿 1")
	eq_int(JWMath.split_lr_into(10, weights, PackedInt64Array([2, 1, 0]), out), 0, "拆分成功")
	eq_int_array(out, PackedInt64Array([3, 3, 4]), "决胜键反序则下标 2 多拿 1")
	# 决胜键也并列：退到下标升序，结果必须唯一确定（重放逐位可复现）。
	eq_int(JWMath.split_lr_into(10, weights, PackedInt64Array([5, 5, 5]), out), 0, "拆分成功")
	eq_int_array(out, PackedInt64Array([4, 3, 3]), "同分同键时按下标升序")
	eq_int(JWMath.split_lr_into(11, weights, PackedInt64Array([5, 5, 5]), out), 0, "拆分成功")
	eq_int_array(out, PackedInt64Array([4, 4, 3]), "余 2 时给下标最小的两个")


func test_split_is_deterministic_on_repeat() -> void:
	var weights: PackedInt64Array = PackedInt64Array([3, 3, 3, 3, 3, 3, 3])
	var tiebreak: PackedInt64Array = PackedInt64Array([1, 1, 1, 1, 1, 1, 1])
	var a: PackedInt64Array = PackedInt64Array()
	var b: PackedInt64Array = PackedInt64Array()
	a.resize(7)
	b.resize(7)
	eq_int(JWMath.split_lr_into(100, weights, tiebreak, a), 0, "第一次")
	eq_int(JWMath.split_lr_into(100, weights, tiebreak, b), 0, "第二次")
	eq_int_array(a, b, "同输入必须逐位相同（INV-014 的前提）")
	eq_int(JWMath.sum(a), 100, "和恒等")


func test_split_mirrors_when_weights_reversed() -> void:
	var out_a: PackedInt64Array = PackedInt64Array()
	var out_b: PackedInt64Array = PackedInt64Array()
	out_a.resize(3)
	out_b.resize(3)
	var tiebreak: PackedInt64Array = PackedInt64Array([0, 1, 2])
	eq_int(JWMath.split_lr_into(10, PackedInt64Array([1, 2, 3]), tiebreak, out_a), 0, "正序")
	eq_int(JWMath.split_lr_into(10, PackedInt64Array([3, 2, 1]), tiebreak, out_b), 0, "逆序")
	eq_int_array(out_a, PackedInt64Array([2, 3, 5]), "正序分配")
	eq_int_array(out_b, PackedInt64Array([5, 3, 2]), "逆序分配恰为镜像")
	eq_int(JWMath.sum(out_a), 10, "和恒等（正序）")
	eq_int(JWMath.sum(out_b), 10, "和恒等（逆序）")


func test_split_zero_total() -> void:
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(3)
	out[0] = 999
	eq_int(JWMath.split_lr_into(0, PackedInt64Array([3, 5, 2]),
			PackedInt64Array([0, 1, 2]), out), 0, "总额 0 不是故障")
	eq_int_array(out, PackedInt64Array([0, 0, 0]), "out 必须被整段清零，不得留下旧值")
	check_false(JWResult.has_pending(), "总额 0 不登记故障")


func test_split_all_zero_weights_returns_residual() -> void:
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(3)
	out[1] = 12_345
	var residual: int = JWMath.split_lr_into(100, PackedInt64Array([0, 0, 0]),
			PackedInt64Array([0, 1, 2]), out)
	eq_int(residual, 100, "权重全 0 时原额交回调用方登记，绝不静默吞掉")
	eq_int_array(out, PackedInt64Array([0, 0, 0]), "out 全 0")
	check_false(JWResult.has_pending(), "权重全 0 是业务情形，不是故障")
	eq_int(JWMath._split_last_fault, 0, "故障通道为空，返回值应按残差解读")


func test_split_empty_weights_returns_residual() -> void:
	var out: PackedInt64Array = PackedInt64Array()
	eq_int(JWMath.split_lr_into(77, PackedInt64Array(), PackedInt64Array(), out), 77,
			"空权重表等同权重全 0：残差就是总额")
	eq_int(out.size(), 0, "空 out 保持为空")
	eq_int(JWMath.split_lr_into(0, PackedInt64Array(), PackedInt64Array(), out), 0,
			"空权重 + 总额 0 的残差为 0")
	check_false(JWResult.has_pending(), "不登记故障")


func test_split_length_mismatch_is_fault() -> void:
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(3)
	eq_int(JWMath.split_lr_into(10, PackedInt64Array([1, 1, 1]),
			PackedInt64Array([0, 1]), out), JWResult.Fault.INDEX_OUT_OF_RANGE,
			"tiebreak 长度不符即故障")
	eq_int(JWResult.pending_code(), JWResult.Fault.INDEX_OUT_OF_RANGE, "登记 INDEX_OUT_OF_RANGE")
	eq_int_array(out, PackedInt64Array([0, 0, 0]), "故障路径不得留下半拆的账")


func test_split_out_length_mismatch_is_fault() -> void:
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(2)
	eq_int(JWMath.split_lr_into(10, PackedInt64Array([1, 1, 1]),
			PackedInt64Array([0, 1, 2]), out), JWResult.Fault.INDEX_OUT_OF_RANGE,
			"out 长度不符即故障")
	eq_int(JWMath._split_last_fault, JWResult.Fault.INDEX_OUT_OF_RANGE, "故障通道被写")


func test_split_exceeds_max_n_is_fault() -> void:
	var n: int = JWMath.SPLIT_MAX_N + 1
	var w: PackedInt64Array = PackedInt64Array()
	var tb: PackedInt64Array = PackedInt64Array()
	var out: PackedInt64Array = PackedInt64Array()
	w.resize(n)
	tb.resize(n)
	out.resize(n)
	for i: int in n:
		w[i] = 1
		tb[i] = i
	eq_int(JWMath.split_lr_into(1_000, w, tb, out), JWResult.Fault.INDEX_OUT_OF_RANGE,
			"超过 SPLIT_MAX_N 即故障，不得动态扩容")
	eq_int(JWResult.pending_code(), JWResult.Fault.INDEX_OUT_OF_RANGE, "登记 INDEX_OUT_OF_RANGE")


func test_split_at_max_n_works() -> void:
	var n: int = JWMath.SPLIT_MAX_N
	var w: PackedInt64Array = PackedInt64Array()
	var tb: PackedInt64Array = PackedInt64Array()
	var out: PackedInt64Array = PackedInt64Array()
	w.resize(n)
	tb.resize(n)
	out.resize(n)
	for i: int in n:
		w[i] = 1
		tb[i] = i
	eq_int(JWMath.split_lr_into(1_000, w, tb, out), 0, "恰好 256 项可拆")
	eq_int(JWMath.sum(out), 1_000, "和恒等")
	eq_int(out[0], 4, "前 232 项各 4")
	eq_int(out[231], 4, "第 232 项仍为 4")
	eq_int(out[232], 3, "其余各 3")
	check_false(JWResult.has_pending(), "边界内不登记故障")


func test_split_rejects_negative_total_and_weight() -> void:
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(2)
	eq_int(JWMath.split_lr_into(-5, PackedInt64Array([1, 1]),
			PackedInt64Array([0, 1]), out), JWResult.Fault.SPLIT_MISMATCH, "负总额即故障")
	eq_int(JWResult.pending_code(), JWResult.Fault.SPLIT_MISMATCH, "登记 SPLIT_MISMATCH")
	JWResult.clear_pending()
	eq_int(JWMath.split_lr_into(5, PackedInt64Array([1, -1]),
			PackedInt64Array([0, 1]), out), JWResult.Fault.SPLIT_MISMATCH, "负权重即故障")
	eq_int(JWResult.pending_code(), JWResult.Fault.SPLIT_MISMATCH, "登记 SPLIT_MISMATCH")


func test_split_overflow_guard() -> void:
	# docs/10 §13.5 裁定：入口断言的乘数是 max_i |w_i| 而**不是** Σw。
	# 被保护的对象是 INV-006，而函数内实际执行的乘法只有 mul(total, w_i)，
	# 其不溢出的充要条件就是 |total| · max_i |w_i| ≤ INT64_MAX。
	# 本测试按该充要条件钉三点：临界内放行、临界外拦下、以及被旧 Σw 版误杀的真实用例。
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(2)

	# 临界内：total × max_w == INT64_MAX − 1，恰好不越界，必须放行且和恒等。
	eq_int(JWMath.split_lr_into(HALF_MAX, PackedInt64Array([2, 1]),
			PackedInt64Array([0, 1]), out), 0, "total × max_i w_i 恰在界内必须放行")
	eq_int(JWMath.sum(out), HALF_MAX, "临界内拆分仍满足 Σout == total")
	check_false(JWResult.has_pending(), "临界内不得登记故障")

	# 临界外：total 再多 1 就使快路径的 mul(total, 2) 越界。
	# 旧实现在这里拒绝；但数学真值完全装得下 int64，拒绝只是算法局限，不是契约要求——
	# INV-006 要的是「不许静默溢出」。现在由长乘除核走慢路径，必须给出精确结果。
	# 期望值由 Python 大整数独立算出。
	eq_int(JWMath.split_lr_into(HALF_MAX + 1, PackedInt64Array([2, 1]),
			PackedInt64Array([0, 1]), out), 0, "快路径越界时改走慢路径，仍须成功")
	eq_int_array(out, PackedInt64Array([3_074_457_345_618_258_603, 1_537_228_672_809_129_301]),
			"慢路径与数学真值逐位相同")
	eq_int(JWMath.sum(out), HALF_MAX + 1, "慢路径同样满足 Σout == total")
	check_false(JWResult.has_pending(), "慢路径在可表示范围内不得登记故障")

	# 真正处理不了的输入必须**显式**拒绝：快路径越界且权重和超过长乘除核上界 2^62 − 1。
	eq_int(JWMath.split_lr_into(3, PackedInt64Array([JWMath.MDR_MAX_DIVISOR, 2]),
			PackedInt64Array([0, 1]), out), JWResult.Fault.INT_OVERFLOW,
			"权重和超出长乘除核上界必须在入口拦下")
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW, "登记 INT_OVERFLOW")
	eq_int_array(out, PackedInt64Array([0, 0]), "故障路径不得留下半拆的账")
	JWResult.clear_pending()


func test_split_guard_admits_base_year_coupon_allocation() -> void:
	# docs/10 §13.5 的回归钉：基年 S06 按各组 deposit_uu 份额分回票息。
	# total = 317 500 000 μU，Σw = 43 000 000 000 μU，max_w = 7 726 328 000 μU。
	# 旧 Σw 版上界 floor(INT64_MAX / 43e9) == 214 497 024 < 317 500 000 —— 会误杀这笔合法分配；
	# 而真正执行的乘法 317 500 000 × 7 726 328 000 == 2.453e18，尚有 3.76× 裕度。
	# 这条一旦变红，说明有人把入口断言的乘数换回了 Σw。
	var w: PackedInt64Array = PackedInt64Array([
		7_726_328_000, 7_726_328_000, 7_726_328_000,
		7_726_328_000, 7_726_328_000, 4_368_360_000])
	var tb: PackedInt64Array = PackedInt64Array([0, 1, 2, 3, 4, 5])
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(w.size())
	eq_int(JWMath.sum(w), 43_000_000_000, "权重和与 §13.5 的算例一致")
	ge_int(317_500_000, JWMath.floor_div(JWUnits.INT64_MAX, JWMath.sum(w)) + 1,
			"该用例确实越过旧 Σw 版上界，否则这条回归钉不住任何东西")
	eq_int(JWMath.split_lr_into(317_500_000, w, tb, out), 0,
			"基年票息分配必须放行（§13.5 裁定：乘数是 max_i w_i）")
	eq_int(JWMath.sum(out), 317_500_000, "Σout == total 精确成立")
	check_false(JWResult.has_pending(), "合法分配不得登记 INT_OVERFLOW")


func test_split_at_amount_max() -> void:
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(3)
	eq_int(JWMath.split_lr_into(JWUnits.AMOUNT_MAX, PackedInt64Array([1, 1, 1]),
			PackedInt64Array([0, 1, 2]), out), 0, "契约金额上界可拆")
	eq_int(JWMath.sum(out), JWUnits.AMOUNT_MAX, "和恒等于 AMOUNT_MAX")
	eq_int_array(out, PackedInt64Array([1_333_333_333_333_334, 1_333_333_333_333_333, 1_333_333_333_333_333]),
			"余 1 给下标最小者（AMOUNT_MAX = 4e15，裁定 R-SCALE-01）")


func test_split_lr_cold_path_wrapper() -> void:
	var got: PackedInt64Array = JWMath.split_lr(10, PackedInt64Array([1, 2, 3]),
			PackedInt64Array([0, 1, 2]))
	eq_int_array(got, PackedInt64Array([2, 3, 5]), "冷路径包装与热路径结果一致")
	var zero_w: PackedInt64Array = JWMath.split_lr(10, PackedInt64Array([0, 0]),
			PackedInt64Array([0, 1]))
	eq_int_array(zero_w, PackedInt64Array([0, 0]), "权重全 0 返回等长全 0 数组而非空数组")
	var bad: PackedInt64Array = JWMath.split_lr(10, PackedInt64Array([1, 1]),
			PackedInt64Array([0]))
	eq_int(bad.size(), 0, "故障时返回空数组")
	eq_int(JWResult.pending_code(), JWResult.Fault.INDEX_OUT_OF_RANGE, "故障已登记")


# ── clamp / absi / sum / 上下界护栏 ────────────────────────────────────────

func test_clamp_i() -> void:
	eq_int(JWMath.clamp_i(5, 0, 10), 5, "区间内不动")
	eq_int(JWMath.clamp_i(-5, 0, 10), 0, "低于下界夹到下界")
	eq_int(JWMath.clamp_i(15, 0, 10), 10, "高于上界夹到上界")
	eq_int(JWMath.clamp_i(0, 0, 0), 0, "退化区间")
	eq_int(JWMath.clamp_i(-7, -10, -1), -7, "全负区间")
	check_false(JWResult.has_pending(), "合法夹逼不登记故障")


func test_clamp_i_inverted_bounds_is_fault() -> void:
	eq_int(JWMath.clamp_i(5, 10, 0), 10, "lo > hi 返回 lo")
	eq_int(JWResult.pending_code(), JWResult.Fault.INDEX_OUT_OF_RANGE, "登记 INDEX_OUT_OF_RANGE")


func test_absi() -> void:
	eq_int(JWMath.absi(5), 5, "正数")
	eq_int(JWMath.absi(-5), 5, "负数")
	eq_int(JWMath.absi(0), 0, "零")
	eq_int(JWMath.absi(JWUnits.INT64_MAX), JWUnits.INT64_MAX, "最大值")
	check_false(JWResult.has_pending(), "以上不登记故障")
	eq_int(JWMath.absi(JWMath.INT64_MIN), JWMath.INT64_MIN, "INT64_MIN 无正绝对值，原值返回")
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW, "并登记 INT_OVERFLOW")


func test_sum_and_sum_abs() -> void:
	var a: PackedInt64Array = PackedInt64Array([1, -2, 3, -4])
	eq_int(JWMath.sum(a), -2, "有符号求和")
	eq_int(JWMath.sum_abs(a), 10, "绝对值求和")
	eq_int(JWMath.sum(PackedInt64Array()), 0, "空数组求和为 0")
	eq_int(JWMath.sum_abs(PackedInt64Array()), 0, "空数组绝对值求和为 0")
	check_false(JWResult.has_pending(), "合法求和不登记故障")


func test_sum_overflow_guard() -> void:
	var a: PackedInt64Array = PackedInt64Array([JWUnits.INT64_MAX, 1])
	eq_int(JWMath.sum(a), 0, "正向累加越界返回 0")
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW, "登记 INT_OVERFLOW")
	JWResult.clear_pending()
	var b: PackedInt64Array = PackedInt64Array([JWMath.INT64_MIN, -1])
	eq_int(JWMath.sum(b), 0, "负向累加越界返回 0")
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW, "登记 INT_OVERFLOW")


func test_sum_abs_overflow_guard() -> void:
	var a: PackedInt64Array = PackedInt64Array([JWMath.INT64_MIN])
	eq_int(JWMath.sum_abs(a), 0, "INT64_MIN 取绝对值越界")
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW, "登记 INT_OVERFLOW")


func test_check_amount_bounds() -> void:
	eq_int(JWMath.check_amount(JWUnits.AMOUNT_MAX), JWUnits.AMOUNT_MAX, "上界内返回原值")
	eq_int(JWMath.check_amount(-JWUnits.AMOUNT_MAX), -JWUnits.AMOUNT_MAX, "下界内返回原值")
	check_false(JWResult.has_pending(), "边界上不报错")
	eq_int(JWMath.check_amount(JWUnits.AMOUNT_MAX + 1), JWUnits.AMOUNT_MAX + 1,
			"越界仍返回原值，以便调用方继续走失败路径")
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW, "登记 INT_OVERFLOW")


func test_check_qty_bounds() -> void:
	eq_int(JWMath.check_qty(JWUnits.QTY_MAX), JWUnits.QTY_MAX, "上界内")
	check_false(JWResult.has_pending(), "边界上不报错")
	eq_int(JWMath.check_qty(-JWUnits.QTY_MAX - 1), -JWUnits.QTY_MAX - 1, "越界返回原值")
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW, "登记 INT_OVERFLOW")


func test_check_price_bounds() -> void:
	eq_int(JWMath.check_price(JWUnits.PRICE_MIN), JWUnits.PRICE_MIN, "价格下界合法")
	eq_int(JWMath.check_price(JWUnits.PRICE_MAX), JWUnits.PRICE_MAX, "价格上界合法")
	eq_int(JWMath.check_price(JWUnits.BASE_PRICE), JWUnits.BASE_PRICE, "基年价合法")
	check_false(JWResult.has_pending(), "区间内不报错")
	eq_int(JWMath.check_price(JWUnits.PRICE_MIN - 1), JWUnits.PRICE_MIN - 1, "低于下界返回原值")
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW, "登记 INT_OVERFLOW")


# ── JWResult 的故障登记语义 ────────────────────────────────────────────────

func test_first_fault_wins() -> void:
	JWResult.set_step(JWUnits.Phase.S03)
	eq_int(JWResult.raise_fault(JWResult.Fault.DIV_ZERO, 11, 22), JWResult.Fault.DIV_ZERO,
			"raise_fault 原样返回故障码")
	eq_int(JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, 33, 44),
			JWResult.Fault.SPLIT_MISMATCH, "返回值仍是本次的码")
	eq_int(JWResult.pending_code(), JWResult.Fault.DIV_ZERO, "登记的仍是第一次故障")
	eq_int(JWResult.pending_step(), JWUnits.Phase.S03, "步骤取第一次故障时的当前步")
	check(JWResult.has_pending(), "有未处理故障")
	JWResult.clear_pending()
	check_false(JWResult.has_pending(), "clear_pending 后归零")
	eq_int(JWResult.pending_code(), 0, "码归零")
	eq_int(JWResult.pending_step(), 0, "步骤归零")


func test_raise_fault_ignores_ok_code() -> void:
	eq_int(JWResult.raise_fault(0, 1, 2), 0, "code == 0 直接放行")
	check_false(JWResult.has_pending(), "OK 不得被登记成故障")


func test_result_cold_path_constructors() -> void:
	var ok: JWResult = JWResult.make_ok()
	check(ok.ok, "make_ok 的 ok 为真")
	eq_int(ok.code, 0, "make_ok 的码为 0")
	var err: JWResult = JWResult.make_err(JWResult.Load.DUP_ID, 7, 8, 9)
	check_false(err.ok, "make_err 的 ok 为假")
	eq_int(err.code, JWResult.Load.DUP_ID, "码原样带上")
	eq_int(err.detail_a, 7, "detail_a")
	eq_int(err.detail_b, 8, "detail_b")
	eq_int(err.detail_key, 9, "detail_key")
	check_false(JWResult.has_pending(), "冷路径构造器不写静态故障登记")


# ── JWUnits 的静态表自检 ──────────────────────────────────────────────────

func test_kind_classification_tables() -> void:
	eq_int(JWUnits.KIND_PROD_CLASS.size(), JWUnits.KIND_N, "生产法分类表长度")
	eq_int(JWUnits.KIND_EXP_CLASS.size(), JWUnits.KIND_N, "支出法分类表长度")
	eq_int(JWUnits.KIND_INC_CLASS.size(), JWUnits.KIND_N, "收入法分类表长度")
	eq_int(JWUnits.KIND_IS_REDISTRIBUTION.size(), JWUnits.KIND_N, "再分配标记表长度")
	check_false(JWUnits.kind_is_classified(0), "0 号是占位，不算已登记")
	check_false(JWUnits.kind_is_classified(JWUnits.KIND_N), "越界不算已登记")
	check_false(JWUnits.kind_is_classified(-1), "负值不算已登记")
	for k: int in range(1, JWUnits.KIND_N):
		if not JWUnits.kind_is_classified(k):
			fail("kind %d 应已登记（INV-114）" % k)
	check(JWUnits.kind_is_classified(JWUnits.Kind.WAGE_PAYMENT), "工资支付已登记")
	check(JWUnits.kind_is_classified(JWUnits.Kind.WRITEOFF), "减记已登记")


func test_redistribution_kinds_have_no_gdp_class() -> void:
	# INV-029 / INV-113：再分配类三口径必须全为 NONE，否则会被重复计入 GDP。
	for k: int in range(1, JWUnits.KIND_N):
		if JWUnits.KIND_IS_REDISTRIBUTION[k] == 1:
			if JWUnits.KIND_PROD_CLASS[k] != JWUnits.ProdClass.NONE \
					or JWUnits.KIND_EXP_CLASS[k] != JWUnits.ExpClass.NONE \
					or JWUnits.KIND_INC_CLASS[k] != JWUnits.IncClass.NONE:
				fail("再分配类 kind %d 的三口径不全为 NONE" % k)
	eq_int(JWUnits.KIND_IS_REDISTRIBUTION[JWUnits.Kind.INCOME_TAX], 1, "个税是再分配类")
	eq_int(JWUnits.KIND_IS_REDISTRIBUTION[JWUnits.Kind.WAGE_PAYMENT], 0, "工资支付不是再分配类")


func test_writable_subsys_table() -> void:
	eq_int(JWUnits.WRITABLE_SUBSYS.size(), JWUnits.Phase.S08 + 1, "每个 Phase 一条位掩码")
	eq_int(JWUnits.WRITABLE_SUBSYS[JWUnits.Phase.IDLE], 0, "IDLE 无写权")
	check(JWUnits.WRITABLE_SUBSYS[JWUnits.Phase.S08] & (1 << JWUnits.SUBSYS_TIME) != 0,
			"只有 S08 能写 TIME（INV-012）")
	for p: int in range(JWUnits.Phase.S01, JWUnits.Phase.S08):
		if JWUnits.WRITABLE_SUBSYS[p] & (1 << JWUnits.SUBSYS_TIME) != 0:
			fail("步骤 %d 不得可写 TIME 子系统" % p)


# ── 长乘除核（R-SCALE-01 之后金额级权重的拆分） ───────────────────────────────
# 期望值全部由 Python 任意精度整数独立算出，不依赖被测实现。

# INV-006：c 与 b 同为金额量级时，r·b 可达 1e26；慢路径必须给出精确 floor。
func test_mul_div_floor_slow_path_exact() -> void:
	eq_int(JWMath.mul_div_floor(1_000_000_000_000_007, 3_000_000_000_000, 7_000_000_000_001),
			428_571_428_571_370, "正数，中间量约 3e27")
	eq_int(JWMath.mul_div_floor(-1_000_000_000_000_007, 3_000_000_000_000, 7_000_000_000_001),
			-428_571_428_571_371, "负被乘数向 −∞ 取整")
	eq_int(JWMath.mul_div_floor(1_000_000_000_000_007, -3_000_000_000_000, 7_000_000_000_001),
			-428_571_428_571_371, "负乘数向 −∞ 取整（慢路径的 ceil 退格）")
	eq_int(JWMath.mul_div_floor(4_000_000_000_000_000, 999_999_999_999, 1_000_000_000_000),
			3_999_999_999_996_000, "AMOUNT_MAX 量级")
	eq_int(JWMath.mul_div_floor(123_456_789_012_345, 98_765_432_109_876, 55_555_555_555_555),
			219_478_736_046_639, "三个数都在 1e14 量级")
	check_false(JWResult.has_pending(), "慢路径在合法输入上不应登记故障")


# INV-003 / INV-006：第 1 季 S04 公共工资拆分的真实崩溃现场（total 1.41e9、Σw 1.78e13）。
# 修复前：入口护栏判 total·w_max 溢出而拒绝，整季中止。修复后必须精确拆分且和恒等。
func test_split_with_money_scale_weights() -> void:
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(4)
	var w: PackedInt64Array = PackedInt64Array([2_831_649_999_997, 5_000_000_000_001,
			5_000_000_000_001, 5_000_000_000_001])
	eq_int(JWMath.split_lr_into(1_413_450_000, w, PackedInt64Array([0, 1, 2, 3]), out), 0,
			"金额级权重必须可拆")
	eq_int_array(out, PackedInt64Array([224_454_590, 396_331_804, 396_331_803, 396_331_803]),
			"与 Python 大整数的最大余数法逐位相同")
	eq_int(JWMath.sum(out), 1_413_450_000, "和恒等于总额")

	var w2: PackedInt64Array = PackedInt64Array([4_457_912_500_003, 4_457_912_499_999,
			4_457_912_500_001, 4_457_912_499_997])
	eq_int(JWMath.split_lr_into(1_413_450_000, w2, PackedInt64Array([0, 1, 2, 3]), out), 0,
			"近似等权")
	eq_int_array(out, PackedInt64Array([353_362_500, 353_362_500, 353_362_500, 353_362_500]),
			"近似等权的精确结果")

	var out3: PackedInt64Array = PackedInt64Array()
	out3.resize(3)
	var w3: PackedInt64Array = PackedInt64Array([7, 13_000_000_000_000, 4_831_649_999_993])
	eq_int(JWMath.split_lr_into(4_000_000_000_000_000, w3, PackedInt64Array([0, 1, 2]), out3), 0,
			"总额取 AMOUNT_MAX 量级")
	eq_int_array(out3, PackedInt64Array([1_570, 2_916_163_114_462_206, 1_083_836_885_536_224]),
			"极小权重与极大权重并存")
	eq_int(JWMath.sum(out3), 4_000_000_000_000_000, "和恒等于总额")
	check_false(JWResult.has_pending(), "合法拆分不应登记故障")
