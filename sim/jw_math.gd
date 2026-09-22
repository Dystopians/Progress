## 整数定点算术的唯一实现。
##
## `sim/**` 与 `systems/**` 内禁止裸 `/` 与 `%`（INV-002），一切除法、缩放、拆分只能经本类。
## 命名对照见 docs/17 §1.1：docs/11 §5.2 的 IntMath.idiv_floor/idiv_ceil/split_largest_remainder
## 在本项目里的唯一实现名分别是 floor_div / ceil_div / split_lr_into（热路径）与 split_lr（冷路径）。
## 依赖秩 1：只允许引用 JWUnits 与 JWResult。
##
## 本类是全系统唯一允许出现裸 `/` 与 `%` 的地方 —— 因为它就是这两个算符的语义修正层。
## 修正的内容：GDScript 的 `/` 对负数向零截断、`%` 取被除数的符号，两者都不是契约要的语义。
class_name JWMath
extends RefCounted

## 最大余数法的拆分项数上限。覆盖首版全部拆分场景（最大是 36 群组 / 64 库存项 / 60 收款方）；
## 超长即 Fault.INDEX_OUT_OF_RANGE，不允许动态扩容（扩容会在热路径分配）。
const SPLIT_MAX_N: int = 256

## int64 下界。`-JWUnits.INT64_MAX - 1`，写成算式是因为 9223372036854775808 本身不是合法 int64 字面量。
## 它没有正的绝对值，是一切「取反 / 取绝对值」的溢出奇点，必须逐处显式挡掉。
const INT64_MIN: int = -9_223_372_036_854_775_807 - 1

# ── 成员（静态 scratch，避免热路径分配；构造期 resize 一次，此后长度不变） ──

## 最大余数法的整除部分缓冲，长度 SPLIT_MAX_N
static var _split_base: PackedInt64Array = PackedInt64Array()
## 余数缓冲，长度 SPLIT_MAX_N
static var _split_rem: PackedInt64Array = PackedInt64Array()
## 排序下标缓冲（决胜键 + 余数），长度 SPLIT_MAX_N
static var _split_order: PackedInt64Array = PackedInt64Array()

## split_lr_into 最近一次调用登记的故障码（0 == 无故障）。
## 存在的理由：split_lr_into 的返回值是「未分配残差」（W == 0 时等于 total），
## 与故障码共用一个 int 通道会歧义。调用方要区分「残差」与「故障」时读本字段，
## 或读 JWResult.has_pending()。本字段每次调用入口清零，不跨调用累积。
static var _split_last_fault: int = 0


## 静态 scratch 的一次性定长化。Godot 在脚本加载时调用一次；
## split_lr_into 入口另有 O(1) 的长度自检兜底，不依赖调用时机。
static func _static_init() -> void:
	_alloc_scratch()


## 把三条 scratch 拉到 SPLIT_MAX_N。只在加载期与自检兜底时执行，不在正常热路径上。
static func _alloc_scratch() -> void:
	_split_base.resize(SPLIT_MAX_N)
	_split_rem.resize(SPLIT_MAX_N)
	_split_order.resize(SPLIT_MAX_N)


## O(1) 长度自检：长度已对即立刻返回，不分配。
static func _ensure_scratch() -> void:
	if _split_base.size() != SPLIT_MAX_N or _split_rem.size() != SPLIT_MAX_N \
			or _split_order.size() != SPLIT_MAX_N:
		_alloc_scratch()


## 把 out 整段清零。故障路径用：宁可交回全 0 也不留下半拆的账。
static func _zero_out(out: PackedInt64Array) -> void:
	for i: int in out.size():
		out[i] = 0


## 最大余数法的全序比较：余数降序 → 决胜键升序 → 下标升序。
## 第三级（下标升序）保证同分且同决胜键时结果仍然唯一，重放逐位可复现（INV-014）。
static func _lr_before(x: int, y: int, tiebreak: PackedInt64Array) -> bool:
	var rx: int = _split_rem[x]
	var ry: int = _split_rem[y]
	if rx != ry:
		return rx > ry
	var tx: int = tiebreak[x]
	var ty: int = tiebreak[y]
	if tx != ty:
		return tx < ty
	return x < y

# ── 方法 ───────────────────────────────────────────────────────────────────

## 带显式溢出前置检查的乘法。release 构建也执行（Godot 的 assert 会被剥离）。
## 步骤：全部（一切乘法的唯一入口）
## 前置：无
## 后置：返回 a*b；溢出时已登记 INT_OVERFLOW 并返回 0
## 不变量：INV-006（M0 规则）
## 失败：JWResult.raise_fault(Fault.INT_OVERFLOW, a, b)，返回 0；不做饱和截断
static func mul(a: int, b: int) -> int:
	if a == 0 or b == 0:
		return 0
	# INT64_MIN 没有正的绝对值，任何非 0 乘数都会溢出，先挡掉再谈裕度。
	if a == INT64_MIN or b == INT64_MIN:
		JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, a, b)
		return 0
	var aa: int = a if a >= 0 else -a
	var ab: int = b if b >= 0 else -b
	# rounding: floor, reason=aa > floor(INT64_MAX/ab) 等价于 aa*ab > INT64_MAX，是精确判据不是近似
	if aa > floor_div(JWUnits.INT64_MAX, ab):
		JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, a, b)
		return 0
	return a * b


## 向下取整除法（对负数也向 −∞）。GDScript 的 `/` 向零截断，不是我们要的语义。
## 步骤：全部
## 前置：b != 0
## 后置：返回 floor(a/b)
## 不变量：INV-002；docs/10 §0.9 铁律一（不存在四舍五入）
## 失败：b == 0 → raise_fault(Fault.DIV_ZERO) 返回 0
static func floor_div(a: int, b: int) -> int:
	if b == 0:
		JWResult.raise_fault(JWResult.Fault.DIV_ZERO, a, b)
		return 0
	# INT64_MIN / -1 的真值是 INT64_MAX + 1，int64 装不下：显式挡掉，不让它静默回卷。
	if a == INT64_MIN and b == -1:
		JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, a, b)
		return 0
	# rounding: floor, reason=契约只有 floor/ceil/最大余数法三种，此处是 floor 的定义点
	@warning_ignore("integer_division")
	var q: int = a / b
	@warning_ignore("integer_division")
	var r: int = a % b
	# 商与除法结果异号且除不尽时，向零截断比向 −∞ 大 1，补回来。
	if r != 0 and ((a < 0) != (b < 0)):
		q -= 1
	return q


## 向上取整除法。用于「投入消耗」「用工人数」等不得少算的场合。
## 步骤：S03 §3.2/§3.5、S05 §5.2/§5.4
## 前置：b != 0
## 后置：返回 ceil(a/b) == -floor_div(-a, b)
## 不变量：INV-046（ceil 反算不透支的整数引理，见 docs/12 §5.4）
## 失败：同 floor_div
static func ceil_div(a: int, b: int) -> int:
	if a == INT64_MIN:
		# -a 溢出；不做饱和截断，交给调用方走失败路径。
		JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, a, b)
		return 0
	# rounding: ceil, reason=docs/10 §0.10「产量→投入消耗 / 用工人数」绝不允许少算
	return -floor_div(-a, b)


## 无溢出的 floor(a * b / c)（c > 0）。
## 步骤：全部需要「先乘后除」的换算（ppm 缩放、价格×数量、按份额折算）
## 前置：c > 0
## 后置：精确等于 floor(a * b / c) 的数学真值，中间量不溢出
## 不变量：INV-005（换算余数写 log.rounding）
## 失败：真值本身超出 int64 → mul 的失败路径
##
## 原理：设 a = q*c + r 且 0 <= r < c（floor_div 语义保证）。
## 则 a*b/c = q*b + r*b/c，floor 后 = q*b + floor(r*b/c)，因为 q*b 已是整数。
## 这样中间量最大只到 max(|q*b|, |r*b|)，而不是 |a*b|——正是 1 U = 1e9 μU 刻度下
## 让 AMOUNT_MAX(4e15) × PPM(1e6) 不再溢出的关键（裁定 R-SCALE-01）。
static func mul_div_floor(a: int, b: int, c: int) -> int:
	if c <= 0:
		JWResult.raise_fault(JWResult.Fault.DIV_ZERO, a, c)
		return 0
	# rounding: floor, reason=R-SCALE-01，先拆商与余数，避免 a*b 的中间溢出
	var q: int = floor_div(a, c)
	var r: int = a - mul(q, c)
	var hi: int = mul(q, b)
	var lo: int = 0
	if r != 0 and b != 0:
		if b != INT64_MIN and absi(b) <= floor_div(JWUnits.INT64_MAX, r):
			# 快路径：r·|b| 装得下 int64（ppm、价格×数量等常见情形都走这里）
			lo = floor_div(mul(r, b), c)
		else:
			# 慢路径：c 与 b 同为金额量级（如按金额权重拆分）时 r·b 可达 1e26，
			# 用逐位长乘除求精确的 floor(r·b/c)，中间量恒 < 2c，永不溢出。
			lo = _mul_div_floor_slow(r, b, c)
	if lo > 0 and hi > JWUnits.INT64_MAX - lo:
		JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, hi, lo)
		return 0
	if lo < 0 and hi < INT64_MIN - lo:
		JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, hi, lo)
		return 0
	return hi + lo


## 长乘除核的除数上界：2^62 − 1。保证核内的 2·rr 与 rr + x 都 < 2^63。
const MDR_MAX_DIVISOR: int = 4_611_686_018_427_387_903

## 长乘除核的两个输出（静态暂存，热路径不分配对象）。
static var _mdr_q: int = 0
static var _mdr_r: int = 0


## 精确长乘除核：对 0 <= x < m、y >= 0，求 floor(x·y/m) 与 (x·y) mod m，写入 _mdr_q / _mdr_r。
## 步骤：mul_div_floor 与 split_lr_into 的慢路径
## 前置：0 <= x < m；y >= 0；0 < m <= MDR_MAX_DIVISOR
## 后置：_mdr_q·m + _mdr_r == x·y（数学真值），0 <= _mdr_r < m
## 不变量：INV-003（拆分的和恒等由精确余数保证）、INV-006（任何中间量不溢出）
## 失败：前置破裂 → INT_OVERFLOW / SPLIT_MISMATCH，返回故障码；成功返回 0
##
## 原理：从 y 的最高位向低位扫，维持「已扫前缀 p：x·p == qq·m + rr，0 <= rr < m」。
## 每步先整体加倍（p ← 2p），再按当前位加 x（p ← p + 1）；每次加法后至多减一次 m 即回到 [0, m)。
## 因为 rr < m 且 x < m，所有中间量都 < 2m <= 2^63 − 2；qq <= p <= y，同样不溢出。
static func _mul_div_rem(x: int, y: int, m: int) -> int:
	if m <= 0 or m > MDR_MAX_DIVISOR:
		return JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, m, MDR_MAX_DIVISOR)
	if x < 0 or x >= m or y < 0:
		return JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, x, y)
	var qq: int = 0
	var rr: int = 0
	var bit: int = 62
	while bit >= 0 and ((y >> bit) & 1) == 0:
		bit -= 1
	while bit >= 0:
		qq += qq
		rr += rr
		if rr >= m:
			rr -= m
			qq += 1
		if ((y >> bit) & 1) == 1:
			rr += x
			if rr >= m:
				rr -= m
				qq += 1
		bit -= 1
	_mdr_q = qq
	_mdr_r = rr
	return 0


## mul_div_floor 的慢路径：0 <= r < c，b 任意符号，返回 floor(r·b/c)。
static func _mul_div_floor_slow(r: int, b: int, c: int) -> int:
	if b == INT64_MIN:
		return JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, r, b)
	var rc: int = _mul_div_rem(r, absi(b), c)
	if rc != 0:
		return 0
	if b >= 0:
		return _mdr_q
	# rounding: floor, reason=负乘数时 floor(−v) == −ceil(v)，有余数就再退一格
	return -_mdr_q - (1 if _mdr_r > 0 else 0)


## ppm 缩放（单次取整）。
## 步骤：全部
## 前置：|x| <= AMOUNT_MAX 或 QTY_MAX（由调用方保证并断言）
## 后置：返回 floor_div(mul(x, p), PPM)
## 不变量：INV-005（换算余数写 log.rounding，不产生债权债务）；M1
## 失败：溢出转 mul 的失败路径
static func mul_ppm(x: int, p: int) -> int:
	# rounding: floor, reason=M1，换算只取整一次，少给优于凭空多给
	return mul_div_floor(x, p, JWUnits.PPM)


## 两个 ppm 先合并再缩放，只取整一次。禁止 mul_ppm(mul_ppm(x,p1),p2)。
## 步骤：S03 §3.6、S07 §7.9 等
## 前置：同 mul_ppm
## 后置：返回 floor_div(mul(x, floor_div(mul(p1,p2), PPM)), PPM)
## 不变量：M2（禁止连乘两个 ppm）
## 失败：同 mul
static func mul_ppm_2(x: int, p1: int, p2: int) -> int:
	# rounding: floor, reason=M2，先把两个系数合成一个 ppm，对 x 只取整一次
	var p: int = floor_div(mul(p1, p2), JWUnits.PPM)
	# rounding: floor, reason=M1，合成系数对 x 的唯一一次取整
	return mul_div_floor(x, p, JWUnits.PPM)


## 最大余数法拆分（热路径版本，写入调用方提供的 out）。
## 步骤：全部拆分场景（工资到组、支出到收款方、配给、年度拆季、等额本金、加权汇总）
## 前置：total >= 0；∀w >= 0；weights.size() == tiebreak.size() == out.size() <= SPLIT_MAX_N
## 后置：Σ out == total 精确成立；W == 0 时 out 全 0 并返回 residual = total 给调用方登记
## 不变量：INV-003（后置断言），INV-060（配给），INV-124（加权）
## 失败：长度越界 → INDEX_OUT_OF_RANGE；后置断言不成立 → SPLIT_MISMATCH（最严重的一类缺陷，立即停）
##
## 返回值是「未分配残差」：正常拆分为 0，W == 0 时为 total（调用方必须登记，不得丢弃）。
## 故障路径返回故障码并把 out 清零；调用方要区分残差与故障时读 _split_last_fault
## 或 JWResult.has_pending()，二者都由本函数在同一次调用内写好。
static func split_lr_into(total: int, weights: PackedInt64Array,
		tiebreak: PackedInt64Array, out: PackedInt64Array) -> int:
	_split_last_fault = 0
	var n: int = weights.size()
	if n != tiebreak.size() or n != out.size() or n > SPLIT_MAX_N:
		_zero_out(out)
		_split_last_fault = JWResult.raise_fault(
				JWResult.Fault.INDEX_OUT_OF_RANGE, n, SPLIT_MAX_N)
		return _split_last_fault
	if total < 0:
		# 前置条件破裂。负额拆分会让「余数最大者多得 1」变成「多扣 1」，语义完全相反，
		# 不允许用取绝对值之类的办法糊过去。
		_zero_out(out)
		_split_last_fault = JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, total, 0)
		return _split_last_fault
	_ensure_scratch()

	var w_sum: int = 0
	var w_max: int = 0
	for i: int in n:
		var w: int = weights[i]
		if w < 0:
			_zero_out(out)
			_split_last_fault = JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, i, w)
			return _split_last_fault
		if w_sum > JWUnits.INT64_MAX - w:
			_zero_out(out)
			_split_last_fault = JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, w_sum, w)
			return _split_last_fault
		w_sum += w
		if w > w_max:
			w_max = w
	_zero_out(out)

	if w_sum == 0:
		# 权重全 0（含空权重表）。不存在「按 0 分配」的合理取法，也不许平均分 ——
		# 那等于替调用方发明一条经济规则。原额交回，由调用方登记进余数账。
		return total

	# 入口溢出断言（docs/10 §13.5 的裁定）：函数内实际执行的乘法只有 `mul(total, w_i)`，
	# 它不溢出的**充要条件**是 `|total| · max_i|w_i| <= INT64_MAX`。
	# 旧写法用 `Σw` 当乘数（`max_i w_i <= Σ w_i`，是充分不必要条件），在新刻度下开始误杀：
	# §13.5 逐字算过基年 S06 的票息分配——total = 317 500 000、Σw = 43 000 000 000，
	# 旧上界 214 497 024 会拒绝它，而真正的乘积 317 500 000 × 7 726 328 000 = 2.453e18
	# 还有 3.76× 裕度。docs/10 §13.5 与 §16.5 第 1 条把本处列为「必须同步的跨文件遗留」，
	# 并明令不得用删断言或降级成告警绕过。这里换的是乘数，不是护栏的强度。
	# 第二段的 `rem_i = total·w_i − base·Σw` 中 `base·Σw <= total·w_i`，同样被本条件覆盖；
	# 每次 mul() 内部仍有 M0 的逐次精确检查兜底。
	# rounding: floor, reason=floor(INT64_MAX/w_max) 是 total 的精确上界
	var fast: bool = w_max == 0 or total <= floor_div(JWUnits.INT64_MAX, w_max)
	if not fast and w_sum > MDR_MAX_DIVISOR:
		_zero_out(out)
		_split_last_fault = JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, total, w_sum)
		return _split_last_fault
	# 慢路径的分解：total = tq·Σw + tr（0 <= tr < Σw），则
	#   floor(total·w_i / Σw) = tq·w_i + floor(tr·w_i / Σw)，余数 = (tr·w_i) mod Σw。
	# tq·w_i <= total，不溢出；后一项交给长乘除核。与快路径逐位相同（同一个数学真值）。
	var tq: int = 0 if fast else floor_div(total, w_sum)
	var tr: int = 0 if fast else total - mul(tq, w_sum)

	var assigned: int = 0
	for i: int in n:
		var base: int = 0
		if fast:
			var num: int = mul(total, weights[i])
			# rounding: lr, reason=最大余数法第一段，整除部分先落地，余数留给第二段
			base = floor_div(num, w_sum)
			_split_rem[i] = num - mul(base, w_sum)
		else:
			var rc_md: int = _mul_div_rem(tr, weights[i], w_sum)
			if rc_md != 0:
				_zero_out(out)
				_split_last_fault = rc_md
				return _split_last_fault
			base = mul(tq, weights[i]) + _mdr_q
			_split_rem[i] = _mdr_r
		_split_base[i] = base
		assigned += base
	var r: int = total - assigned
	if r < 0 or r >= n:
		# 数学上 0 <= r <= n-1（因为每个 rem_i < w_sum，故 Σrem_i < n·w_sum）；
		# 越界说明上面的整除或余数算错了，属于最严重的一类缺陷。
		_zero_out(out)
		_split_last_fault = JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, total, r)
		return _split_last_fault

	var i2: int = 0
	while i2 < n:
		_split_order[i2] = i2
		out[i2] = _split_base[i2]
		i2 += 1
	# 插入排序，n <= 256 且典型 n 为 36 / 60；不新建任何对象，排序键全在 scratch 里。
	var s: int = 1
	while s < n:
		var key: int = _split_order[s]
		var j: int = s - 1
		while j >= 0 and _lr_before(key, _split_order[j], tiebreak):
			_split_order[j + 1] = _split_order[j]
			j -= 1
		_split_order[j + 1] = key
		s += 1

	var t: int = 0
	while t < r:
		var idx: int = _split_order[t]
		out[idx] = out[idx] + 1
		t += 1

	# 后置断言（INV-003）：不是「一般成立」，是每次都要算的硬检查。
	var back: int = 0
	for i: int in n:
		back += out[i]
	if back != total:
		_zero_out(out)
		_split_last_fault = JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, total, back)
		return _split_last_fault
	return 0


## 冷路径包装：返回一个新数组。禁止出现在结算路径（静态检查）。
## 步骤：加载期、测试
## 前置：同 split_lr_into
## 后置：同 split_lr_into
## 不变量：INV-003
## 失败：同 split_lr_into；失败时返回空数组
##
## W == 0 时返回的是与 weights 等长的全 0 数组（不是空数组）——「没有故障，但一分未拆」。
## 调用方据 total − Σ 结果 得到残差并登记。故障与该情形的区分同 split_lr_into。
static func split_lr(total: int, weights: PackedInt64Array,
		tiebreak: PackedInt64Array) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(weights.size())
	split_lr_into(total, weights, tiebreak, out)
	if _split_last_fault != 0:
		return PackedInt64Array()
	return out


## 整数夹逼。每个调用点必须由调用方自己写 log.clamp（本函数不写日志，因为它不知道字段码）。
## 只允许出现在 docs/10 §0.8 登记为「有界平滑」的位置。
## 步骤：S03 摩擦、S05 进度、S07 价格与人口、S08 主观量
## 前置：lo <= hi
## 后置：返回 min(max(v, lo), hi)
## 不变量：INV-069（夹逼必须计数并写日志——由调用方负责）
## 失败：lo > hi → INDEX_OUT_OF_RANGE 返回 lo
static func clamp_i(v: int, lo: int, hi: int) -> int:
	if lo > hi:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, lo, hi)
		return lo
	if v < lo:
		return lo
	if v > hi:
		return hi
	return v


## 整数绝对值。
## 步骤：全部
## 前置：无
## 后置：返回 |a|
## 不变量：INV-007
## 失败：越界 → raise_fault(Fault.INT_OVERFLOW)，返回原值以便调用方继续走失败路径
static func absi(a: int) -> int:
	if a == INT64_MIN:
		JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, a, 0)
		return a
	return a if a >= 0 else -a


## 数组求和（带溢出守卫）。
## 步骤：全部（恒等式对账）
## 前置：无
## 后置：返回 Σ a[i]
## 不变量：INV-007
## 失败：越界 → raise_fault(Fault.INT_OVERFLOW)
static func sum(a: PackedInt64Array) -> int:
	var acc: int = 0
	for i: int in a.size():
		var v: int = a[i]
		if v > 0 and acc > JWUnits.INT64_MAX - v:
			JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, acc, v)
			return 0
		if v < 0 and acc < INT64_MIN - v:
			JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, acc, v)
			return 0
		acc += v
	return acc


## 数组绝对值求和（流量清零自检用）。
## 步骤：S01 §01.3
## 前置：无
## 后置：返回 Σ |a[i]|
## 不变量：INV-007, INV-013
## 失败：越界 → raise_fault(Fault.INT_OVERFLOW)
static func sum_abs(a: PackedInt64Array) -> int:
	var acc: int = 0
	for i: int in a.size():
		var v: int = a[i]
		if v == INT64_MIN:
			JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, v, 0)
			return 0
		var av: int = v if v >= 0 else -v
		if acc > JWUnits.INT64_MAX - av:
			JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, acc, av)
			return 0
		acc += av
	return acc


## 金额上下界检查（写入前的护栏）。
## 步骤：全部
## 前置：无
## 后置：越界时已登记故障
## 不变量：INV-007
## 失败：|x| > JWUnits.AMOUNT_MAX → raise_fault(Fault.INT_OVERFLOW)，返回原值
static func check_amount(x: int) -> int:
	if x > JWUnits.AMOUNT_MAX or x < -JWUnits.AMOUNT_MAX:
		JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, x, JWUnits.AMOUNT_MAX)
	return x


## 数量上下界检查（写入前的护栏）。
## 步骤：全部
## 前置：无
## 后置：越界时已登记故障
## 不变量：INV-007
## 失败：|x| > JWUnits.QTY_MAX → raise_fault(Fault.INT_OVERFLOW)，返回原值
static func check_qty(x: int) -> int:
	if x > JWUnits.QTY_MAX or x < -JWUnits.QTY_MAX:
		JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, x, JWUnits.QTY_MAX)
	return x


## 价格上下界检查（写入前的护栏）。
## 步骤：S07 价格更新、加载期
## 前置：无
## 后置：越界时已登记故障
## 不变量：INV-007, INV-066
## 失败：p 超出 [JWUnits.PRICE_MIN, JWUnits.PRICE_MAX] → raise_fault(Fault.INT_OVERFLOW)，返回原值
static func check_price(p: int) -> int:
	if p < JWUnits.PRICE_MIN or p > JWUnits.PRICE_MAX:
		JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, p, JWUnits.PRICE_MAX)
	return p
