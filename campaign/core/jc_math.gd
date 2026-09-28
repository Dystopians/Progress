## v2 模拟核心的整数工具（docs/57 §2）。模拟里不出现浮点。
class_name JCMath
extends RefCounted

const PPM: int = 1_000_000
## 数量的内部刻度：1 单位 = 1000。
const QS: int = 1000
## 钱：1 两 = 1000 厘。
const LI: int = 1000
const BIG: int = 3_000_000_000


## floor(a * b / c)，c > 0；a、b 可正可负（结果向零截断）。全程精确：放不进 64 位的乘积改用逐位除法。
static func muldiv(a: int, b: int, c: int) -> int:
	if c <= 0:
		push_error("JCMath.muldiv: c <= 0")
		return 0
	if a == 0 or b == 0:
		return 0
	var neg: bool = (a < 0) != (b < 0)
	var aa: int = absi(a)
	var bb: int = absi(b)
	var r: int
	if aa < BIG and bb < BIG:
		@warning_ignore("integer_division")
		r = (aa * bb) / c
	else:
		r = _muldiv_exact(aa, bb, c)
	return -r if neg else r


## 精确的 floor(a*b/c)，a、b ≥ 0、0 < c < 2^62：按 b 的二进制位逐位累加商与余数，余数始终小于 c，不会溢出。
static func _muldiv_exact(a: int, b: int, c: int) -> int:
	@warning_ignore("integer_division")
	var qa: int = a / c
	var ra: int = a % c
	var q: int = 0
	var r: int = 0
	var bit: int = 62
	while bit >= 0:
		q = q * 2
		r = r * 2
		if r >= c:
			r -= c
			q += 1
		if (b >> bit) & 1 == 1:
			q += qa
			r += ra
			if r >= c:
				r -= c
				q += 1
		bit -= 1
	return q


static func mulppm(x: int, p: int) -> int:
	return muldiv(x, p, PPM)


## 整数平方根 floor(√n)，n ≥ 0（牛顿法，全程整数）。
static func isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var x: int = n
	@warning_ignore("integer_division")
	var y: int = (x + 1) / 2
	while y < x:
		x = y
		@warning_ignore("integer_division")
		y = (x + n / x) / 2
	return x


## 数量（千分单位）× 价格（厘 / 单位）→ 金额（厘）
static func value(qty_milli: int, price_li: int) -> int:
	return muldiv(qty_milli, price_li, QS)


## 金额（厘）÷ 价格（厘 / 单位）→ 数量（千分单位）
static func qty_of(value_li: int, price_li: int) -> int:
	if price_li <= 0:
		return 0
	return muldiv(value_li, QS, price_li)


## a / b 的 ppm；b <= 0 时返回 dflt。
static func ratio_ppm(a: int, b: int, dflt: int = PPM) -> int:
	if b <= 0:
		return dflt
	return muldiv(a, PPM, b)


static func clampi2(v: int, lo: int, hi: int) -> int:
	return lo if v < lo else (hi if v > hi else v)


## 从 cur 向 target 移动 rate_ppm 的比例（向零截断，保证最终能到达）。
static func approach(cur: int, target: int, rate_ppm: int) -> int:
	var d: int = target - cur
	if d == 0:
		return cur
	var step: int = muldiv(absi(d), rate_ppm, PPM)
	if step == 0:
		step = 1
	return cur + (step if d > 0 else -step)


## 把 total 按权重拆开（最大余数法），返回与 weights 等长的数组，和恒等于 total。
static func split(total: int, weights: PackedInt64Array) -> PackedInt64Array:
	var n: int = weights.size()
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(n)
	out.fill(0)
	if n == 0 or total == 0:
		return out
	var wsum: int = 0
	for w: int in weights:
		wsum += maxi(w, 0)
	if wsum <= 0:
		return out
	var given: int = 0
	var rems: Array = []
	for i: int in n:
		var w: int = maxi(weights[i], 0)
		var a: int = muldiv(total, w, wsum)
		out[i] = a
		given += a
		@warning_ignore("integer_division")
		var rem: int = (absi(total) % wsum) * w % wsum if total >= 0 else 0
		rems.append([rem, i])
	var left: int = total - given
	if left != 0:
		rems.sort_custom(func(x: Array, y: Array) -> bool:
			return x[0] > y[0] or (x[0] == y[0] and x[1] < y[1]))
		var k: int = 0
		var step: int = 1 if left > 0 else -1
		while left != 0 and k < rems.size() * 4:
			var i2: int = rems[k % rems.size()][1]
			if maxi(weights[i2], 0) > 0:
				out[i2] += step
				left -= step
			k += 1
	return out


static func sum(a: PackedInt64Array) -> int:
	var s: int = 0
	for x: int in a:
		s += x
	return s


static func zeros(n: int) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(n)
	a.fill(0)
	return a


static func filled(n: int, v: int) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(n)
	a.fill(v)
	return a
