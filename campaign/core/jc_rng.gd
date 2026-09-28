## v2 确定性随机数：xorshift32，状态存进存档。
## 只用 32 位以内的运算（左移后立即截断到 32 位），不依赖 64 位有符号溢出的行为，跨平台逐位一致。
class_name JCRng
extends RefCounted

const MASK32: int = 0xFFFFFFFF

var state: int = 0x9E3779B9


static func seeded(seed: int) -> JCRng:
	var r: JCRng = JCRng.new()
	r.reseed(seed)
	return r


func reseed(seed: int) -> void:
	# 把任意整数种子混成非零的 32 位状态（逐字节 FNV 风格混合，只用 32 位运算）。
	var h: int = 2166136261
	var s: int = seed
	for i: int in 8:
		var byte: int = s & 0xFF
		h = ((h ^ byte) * 16777619) & MASK32
		s = s >> 8
	if h == 0:
		h = 0x9E3779B9
	state = h
	for i: int in 4:
		next_u32()


func next_u32() -> int:
	var x: int = state
	x = (x ^ ((x << 13) & MASK32)) & MASK32
	x = (x ^ (x >> 17)) & MASK32
	x = (x ^ ((x << 5) & MASK32)) & MASK32
	state = x
	return x


## [0, n) 的整数。
func below(n: int) -> int:
	if n <= 1:
		return 0
	return next_u32() % n


## 以 ppm 概率返回 true。
func chance_ppm(p: int) -> bool:
	if p <= 0:
		return false
	if p >= 1_000_000:
		return true
	return below(1_000_000) < p


## 近似正态：四个均匀数之和，均值 0，标准差约 sd_ppm。返回 ppm。
func gauss_ppm(sd_ppm: int) -> int:
	var s: int = 0
	for i: int in 4:
		s += below(1_000_001) - 500_000
	# 四个 U(-0.5,0.5) 之和的标准差 ≈ 0.577
	@warning_ignore("integer_division")
	return s * sd_ppm / 577_350
