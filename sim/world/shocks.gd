## 3 类外生冲击的抽样与传导（用 `rng.shock` 流），**抽样写日志、先查日志再抽样**。
##
## 持有 `shock_log`（与命令流分开存储，docs/11 §6.1 规则 7）。
## 依赖秩 5（docs/17 §3.2）：只允许引用 ≤4 的类。
## 子系统归属：`JWUnits.SUBSYS_WORLD`。
##
## 结构性约束：冲击只写 `world.*` 白名单（INV-108），本类不得引用任何
## `state.cell` / `state.group` / `state.gov` 字段。
class_name JWShocks
extends RefCounted

## 本块各状态数组所属子系统（与 STATE_ARRAY_IDS 等长），用于 subsystem_hash 与 WriteGuard。
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_WORLD, JWUnits.SUBSYS_WORLD, JWUnits.SUBSYS_WORLD,
	JWUnits.SUBSYS_WORLD, JWUnits.SUBSYS_WORLD,
]

## 稳定 ID 注册表：下标 == 数组序号，内容是 docs/10 的稳定 ID 字符串。
## 只在加载与哈希时被读，结算期不触碰（无 String 进入热路径）。
## 注：`duration_q` / `last_end_q` 在 docs/10 尚无稳定 ID，此处按同族命名暂定（见 interface_requests）。
const STATE_ARRAY_IDS: PackedStringArray = [
	"state.world.shock_active",
	"state.world.shock_remaining_q",
	"state.world.shock_magnitude_ppm",
	"state.world.shock_duration_q",
	"state.world.shock_last_end_q",
]
const STATE_SCALAR_IDS: PackedStringArray = []
const FLOW_ARRAY_IDS: PackedStringArray = []
const FLOW_SCALAR_IDS: PackedStringArray = []

# ── 稠密下标与内容编码（docs/11 §5.14；字符串只在加载期出现，结算期一律整数） ──

## 冲击的稠密下标 == `shock_id` 升序：shock.S01 / S02 / S03。
## docs/12 §01.6 的伪码直接用 `eff_ppm[S01]` 这样的固定下标寻址，所以这三个常量
## 就是契约的一部分，不是本文件的实现细节。
const K_EXPORT: int = 0
const K_IMPORT: int = 1
const K_CREDIT: int = 2

## `content.shock.channel` 的整数编码（docs/11 §5.14 的三个合法取值）。
const CHANNEL_EXPORT_DEMAND: int = 0
const CHANNEL_IMPORT_PRICE: int = 1
const CHANNEL_EXTERNAL_CREDIT: int = 2

## `content.shock.onset_profile` 的整数编码（docs/11 §5.14：step | ramp_2q）。
const ONSET_STEP: int = 0
const ONSET_RAMP_2Q: int = 1

## `content.shock.decay_profile` 的整数编码（docs/11 §5.14：none | linear）。
const DECAY_NONE: int = 0
const DECAY_LINEAR: int = 1

## `content.shock.target_weights_ppm` 的长度：3 个冲击 × 4 部门，行主序（k * S + s）。
const TARGET_WEIGHTS_N: int = JWUnits.SHOCK_N * JWUnits.S

## `last_end_q` 的「从未发生过」哨兵（docs/17 §4.23 成员表的初值 −999）。
## 取负数而不是 0：`q − last_end_q >= min_gap_q` 必须在 q = 0 就成立，
## 写 0 会让第 0 季起的 min_gap 判定把「从未发生」误当成「刚刚结束」。
const LAST_END_NONE: int = -999

## 本季冲击日志的列数（docs/11 §6.4 的扁平行宽度，顺序 == sl_* 的声明顺序）。
const LOG_COLS: int = 7

## `log.rng.purpose` 的取值。docs/10 §12 没有给出全局 purpose 码表（已登记为接口请求），
## 这里按「子系统号 × 1000 + 序号」取值，保证与别的子系统的 purpose 码不会撞号。
const PURPOSE_BASE: int = JWUnits.SUBSYS_WORLD * 1000
## 到达判定（hazard）的抽样
const PURPOSE_ARRIVAL: int = PURPOSE_BASE + 1
## 强度抽样
const PURPOSE_MAGNITUDE: int = PURPOSE_BASE + 2
## 持续期抽样
const PURPOSE_DURATION: int = PURPOSE_BASE + 3

## 日志扩容倍率的分子与分母（docs/10 §12 的「1.5 倍」）
const LOG_GROWTH_NUM: int = 3
const LOG_GROWTH_DEN: int = 2

## `_find_log_row` 在发现同一 (q, k) 有两行记录时的返回值。
## 不能返回 −1（那是「没有记录」的合法答案），也不能挑一行用：
## 两行同 (q, k) 意味着同一次冲击被记了两遍，复用哪一行都是在猜。
const LOG_ROW_CONFLICT: int = -2

## `state.world.shock_active[]`，长 3，0/1，写入者 S01。
var active: PackedInt64Array = PackedInt64Array()
## `state.world.shock_remaining_q[]`，长 3，单位 季，写入者 S01。
var remaining_q: PackedInt64Array = PackedInt64Array()
## `state.world.shock_magnitude_ppm[]`，长 3，单位 ppm，写入者 S01。
var magnitude_ppm: PackedInt64Array = PackedInt64Array()
## 衰减因子的分母，长 3，单位 季，写入者 S01。
var duration_q: PackedInt64Array = PackedInt64Array()
## min_gap 判定用的上次结束季，长 3，初值 −999，写入者 S01。
var last_end_q: PackedInt64Array = PackedInt64Array()

## `shock_log.q`，长 LOG_CAP0，写入者 S01。
var sl_q: PackedInt64Array = PackedInt64Array()
## `shock_log.kind`，长 LOG_CAP0，写入者 S01。
var sl_kind: PackedInt64Array = PackedInt64Array()
## `shock_log.magnitude_ppm`，长 LOG_CAP0，写入者 S01。
var sl_mag: PackedInt64Array = PackedInt64Array()
## `shock_log.duration_q`，长 LOG_CAP0，写入者 S01。
var sl_dur: PackedInt64Array = PackedInt64Array()
## `shock_log.draw_index`，长 LOG_CAP0，写入者 S01。
var sl_draw_index: PackedInt64Array = PackedInt64Array()
## `shock_log.raw_u64`，长 LOG_CAP0，写入者 S01。
var sl_raw: PackedInt64Array = PackedInt64Array()
## `shock_log.mapped_value`，长 LOG_CAP0，写入者 S01。
var sl_mapped: PackedInt64Array = PackedInt64Array()

## `content.shock.channel[]`，长 3，写入者 LOAD。
var channel: PackedInt64Array = PackedInt64Array()
## `content.shock.target_weights_ppm[]`，长 12（3 × 4 部门），写入者 LOAD。
var target_weights_ppm: PackedInt64Array = PackedInt64Array()
## `content.shock.hazard_ppm[]`，长 3，写入者 LOAD。
var hazard_ppm: PackedInt64Array = PackedInt64Array()
## `content.shock.earliest_q[]`，长 3，写入者 LOAD。
var earliest_q: PackedInt64Array = PackedInt64Array()
## `content.shock.min_gap_q[]`，长 3，写入者 LOAD。
var min_gap_q: PackedInt64Array = PackedInt64Array()
## `content.shock.max_active[]`，长 3，写入者 LOAD。
var max_active: PackedInt64Array = PackedInt64Array()
## `content.shock.mag_min[]`，长 3，单位 ppm，写入者 LOAD。
var mag_min: PackedInt64Array = PackedInt64Array()
## `content.shock.mag_max[]`，长 3，单位 ppm，写入者 LOAD。
var mag_max: PackedInt64Array = PackedInt64Array()
## `content.shock.dur_min[]`，长 3，单位 季，写入者 LOAD。
var dur_min: PackedInt64Array = PackedInt64Array()
## `content.shock.dur_max[]`，长 3，单位 季，写入者 LOAD。
var dur_max: PackedInt64Array = PackedInt64Array()
## `content.shock.onset_profile[]`，长 3，写入者 LOAD。
var onset_profile: PackedInt64Array = PackedInt64Array()
## `content.shock.decay_profile[]`，长 3，写入者 LOAD。
var decay_profile: PackedInt64Array = PackedInt64Array()

## 本季日志游标（已写行数），每季 S01 由 log_reset_quarter() 归零。
var _log_cursor: int = 0
## 日志当前容量（行），写满时按 1.5 倍扩容并写一条告警行。
var _log_capacity: int = 0
## shock_log 的累计行数（跨季，供 export_shock_log 与 INV-109 复用判定）。
var _log_rows_total: int = 0

## 本季各冲击的有效强度（衰减后，ppm），长 3。预分配，热路径不新建。
## 不是状态：由 apply_to_world() 每季整表重算，不进 state_hash 也不进存档
## （它是 magnitude_ppm / remaining_q / duration_q 的纯函数）。
var _eff_ppm: PackedInt64Array = PackedInt64Array()

## 日志扩容发生的次数。
##
## shock_log 不能靠「写一条告警行」来告警（docs/10 §12 的通用写法）：本通道的每一行
## 都是一条可被 INV-109 复用、被 export_shock_log 逐行写进存档的冲击记录，
## 插一行「告警」进去会让 `rows.size() % 7` 的行数校验与复用查表同时读到一条不存在的冲击。
## 改为计数器登记，与 JWRngStreams._log_grow_count 同一处理。
var _log_grow_count: int = 0


## S01 §01.6：本季冲击的到达、衰减与复用。
## **先查 shock_log：已有本 q 的记录则复用且不推进 rng.shock 的计数器**（堵住「存档重载重抽」）。
## 步骤：S01 §01.6
## 前置：按 shock_id 升序遍历（确定性）；rng.begin_quarter(q) 已调用
## 后置：active / magnitude / remaining_q 更新；新抽样追加 shock_log（含 draw_index、raw_u64、mapped_value）
## 不变量：INV-109（先查后抽）、INV-009（与 rng.event 结构性独立）、INV-010、INV-011
## 失败：shock_log 与计数器矛盾 → Fault.RNG_LOG_MISMATCH，终止并保留现场
func resolve_quarter(rng: JWRngStreams, world: JWWorldMarket, q: int,
		params: PackedInt64Array) -> int:
	if rng == null or world == null:
		# 01.6 与 01.7 是一对：缺任何一半都必须在动 rng 之前失败，
		# 否则会留下「抽过样但没落地」的半截状态，而抽样是不可回退的。
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, 1)
	if params.size() != JWUnits.PARAM_N:
		# 参数表在 01.7 才被读，但在这里就挡住：01.6 一旦抽样就推进了计数器，
		# 到 01.7 才发现参数表不对就只能带着已抽的样中止。
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	if q < 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, q, 0)
	var fault: int = _check_dims()
	if fault != JWResult.OK:
		return fault

	# docs/12 §01.6：按 shock_id 升序遍历，遍历顺序即 rng.shock 的 draw_index 顺序（INV-008）。
	for k: int in JWUnits.SHOCK_N:
		# (a) 先查 shock_log：已有本 q 的记录则直接复用，rng.shock 不推进（INV-109）
		var row: int = _find_log_row(q, k)
		if row == LOG_ROW_CONFLICT:
			return JWResult.raise_fault(JWResult.Fault.RNG_LOG_MISMATCH, q, k)
		if row >= 0:
			# 复用**不比对** draw_index 与 draw_count：docs/12 §01.6 (a) 的伪码只有
			# 「has(q, k) → apply_record → continue」，没有任何计数器前置条件，而这条
			# 前置条件在正规存档里恰好不成立——ADV-06 的存档点在冲击季**之前**，
			# 此时 draw_count 正停在该行 draw_index 上（相等），若要求
			# `draw_index < draw_count` 就把唯一合法的读档路径判成坏档，
			# 冲击被丢弃、强度归零，反而是 save-scum 的另一种成立方式。
			# 存档点在冲击季之后时 draw_index < draw_count，两个方向都合法，
			# 单凭这两个数无法判定矛盾。§1.3 的「shock_log 与计数器矛盾」由
			# _find_log_row 的同 (q, k) 双行与 load_shock_log 的行格式校验承担。
			fault = _apply_record(k, sl_mag[row], sl_dur[row])
			if fault != JWResult.OK:
				return fault
			continue

		# (b) 衰减既有冲击
		if remaining_q[k] > 0:
			remaining_q[k] -= 1
			if remaining_q[k] == 0:
				active[k] = 0
				magnitude_ppm[k] = 0
				duration_q[k] = 0
				# 结束季登记在这里，min_gap_q 从本季起算（成员表：last_end_q 是
				# 「上次结束季」）。不登记就等于 min_gap 永远从 −999 起算，等于没有间隔约束。
				last_end_q[k] = q
			continue

		# (c) 到达抽样
		if q < earliest_q[k]:
			continue
		if q - last_end_q[k] < min_gap_q[k]:
			continue
		# max_active 在首版是「每类冲击同时生效的实例数上限」，而每类只有一个槽位，
		# 于是它退化成开关：<= 0 即该类冲击本局不到达。这是内容层能关掉单个冲击的唯一手段。
		if active[k] >= max_active[k]:
			continue
		if dur_min[k] < 1:
			# docs/12 §01.7 的前置：duration_q >= 1 由 dur_min[k] >= 1 保证；为 0 即 DIV_ZERO。
			# 在抽样之前挡住，而不是等到 01.7 除零时才报——那时样已经抽了。
			return JWResult.raise_fault(JWResult.Fault.DIV_ZERO, dur_min[k], 0)

		var draw_index: int = rng.draw_count_of(JWUnits.RngStream.SHOCK)
		var hazard: int = rng.draw_ppm(JWUnits.RngStream.SHOCK, PURPOSE_ARRIVAL)
		if JWResult.has_pending():
			return JWResult.pending_code()
		# 被拒绝采样丢弃的那次也写了 log.rng，所以真正被采纳的那次的 draw_index
		# 要从 rng 的日志末行读，而不是用抽样前的 draw_count（两者只在无重抽时相等）。
		var rng_row: int = _rng_last_log_row(rng)
		if rng_row < 0:
			return JWResult.Fault.RNG_LOG_MISMATCH
		draw_index = rng.log_draw_index[rng_row]
		var raw: int = rng.log_raw[rng_row]
		if hazard >= hazard_ppm[k]:
			continue

		var m: int = rng.draw_range(JWUnits.RngStream.SHOCK, mag_min[k], mag_max[k],
				PURPOSE_MAGNITUDE)
		if JWResult.has_pending():
			return JWResult.pending_code()
		var d: int = rng.draw_range(JWUnits.RngStream.SHOCK, dur_min[k], dur_max[k],
				PURPOSE_DURATION)
		if JWResult.has_pending():
			return JWResult.pending_code()

		fault = _apply_record(k, m, d)
		if fault != JWResult.OK:
			return fault
		# 到达当季就写一行（含 draw_index / raw_u64 / mapped_value，V-SH-05）。
		# mapped_value 记的是**到达判定**那一次的映射值：它是「这季有没有冲击」的唯一决定量，
		# 强度与持续期的两次抽样已经逐位记在 log.rng 里，不必在本通道重复一遍。
		_log_write(q, k, m, d, draw_index, raw, hazard)

	return JWResult.OK


## S01 §01.7：把本季冲击强度按衰减因子折成对 world.* 的增量。
## 步骤：S01 §01.7
## 前置：resolve_quarter 已完成
## 后置：只调 JWWorldMarket 的五个 setter（**不碰任何国内字段**）
## 不变量：INV-108（不得直接写国内账户、产能、库存或人口）、INV-105
## 失败：本函数若引用任何 state.cell / state.group / state.gov 字段 → 静态检查失败
func apply_to_world(world: JWWorldMarket, q: int, params: PackedInt64Array) -> int:
	if world == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, 1)
	if q < 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, q, 0)
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	var fault: int = _check_dims()
	if fault != JWResult.OK:
		return fault
	if world.base_export_ppm.size() != JWUnits.S or world.base_import_ppm.size() != JWUnits.S:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				world.base_export_ppm.size(), JWUnits.S)
	# 稠密下标与 channel 必须对得上：docs/12 §01.7 是按固定下标（S01/S02/S03）寻址的，
	# 内容包一旦把 channel 排错位，「出口冲击」就会写到进口价格上，而且全程没有任何报错。
	if channel[K_EXPORT] != CHANNEL_EXPORT_DEMAND:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				channel[K_EXPORT], CHANNEL_EXPORT_DEMAND)
	if channel[K_IMPORT] != CHANNEL_IMPORT_PRICE:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				channel[K_IMPORT], CHANNEL_IMPORT_PRICE)
	if channel[K_CREDIT] != CHANNEL_EXTERNAL_CREDIT:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				channel[K_CREDIT], CHANNEL_EXTERNAL_CREDIT)

	# 衰减因子与有效强度（docs/12 §01.7）
	for k: int in JWUnits.SHOCK_N:
		_eff_ppm[k] = 0
		if active[k] == 0:
			continue
		var decay_ppm: int = JWUnits.PPM
		if decay_profile[k] == DECAY_LINEAR:
			if duration_q[k] < 1:
				# docs/12 §01.7 的前置写死了：duration_q 为 0 即 Fault.DIV_ZERO。
				return JWResult.raise_fault(JWResult.Fault.DIV_ZERO, duration_q[k], 0)
			# rounding: floor, reason=docs/12 §01.7，衰减因子 = 剩余季数 / 总季数，
			# 先乘后除一律走 mul_div_floor（裁定 R-SCALE-01 的连带要求 1）。
			decay_ppm = JWMath.mul_div_floor(remaining_q[k], JWUnits.PPM, duration_q[k])
		# rounding: floor, reason=M1，eff = magnitude × decay，只取整一次；
		# magnitude 可为负（mag_min 是负数），mul_ppm 走 floor_div，对负数也向 −∞。
		_eff_ppm[k] = JWMath.mul_ppm(magnitude_ppm[k], decay_ppm)

	# S01 出口需求：逐部门按 target_weights_ppm 分摊
	for s: int in JWUnits.S:
		var w: int = target_weights_ppm[K_EXPORT * JWUnits.S + s]
		var v: int = world.base_export_ppm[s] + JWMath.mul_ppm(_eff_ppm[K_EXPORT], w)
		fault = world.set_export_demand(s, JWMath.clamp_i(v,
				JWWorldMarket.EXPORT_DEMAND_MIN_PPM, JWWorldMarket.EXPORT_DEMAND_MAX_PPM))
		if fault != JWResult.OK:
			return fault

	# S02 进口价格：逐部门按 target_weights_ppm 分摊
	for s: int in JWUnits.S:
		var w: int = target_weights_ppm[K_IMPORT * JWUnits.S + s]
		var v: int = world.base_import_ppm[s] + JWMath.mul_ppm(_eff_ppm[K_IMPORT], w)
		fault = world.set_import_price(s, JWMath.clamp_i(v,
				JWWorldMarket.IMPORT_PRICE_MIN_PPM, JWWorldMarket.IMPORT_PRICE_MAX_PPM))
		if fault != JWResult.OK:
			return fault

	# S03 外部融资：额度与利率**共用同一次抽样**（docs/16 §shock_binding 明文禁止分别抽样）。
	var rate: int = params[JWUnits.Param.MARKET_RATE_BASE_PPM] \
			+ JWMath.mul_ppm(_eff_ppm[K_CREDIT], params[JWUnits.Param.RATE_SENSITIVITY_PPM])
	fault = world.set_sovereign_rate(JWMath.clamp_i(rate,
			JWWorldMarket.SOVEREIGN_RATE_MIN_PPM, JWWorldMarket.SOVEREIGN_RATE_MAX_PPM))
	if fault != JWResult.OK:
		return fault
	# rounding: floor, reason=M1，额度按 (1e6 − eff) 缩放，只取整一次；
	# eff 为负（外部宽松）时 1e6 − eff > 1e6，被 clamp 压回 1e6：docs/16 规定收紧只压上限，
	# 宽松不得把额度抬到剧本基准之上（那等于凭空发一笔新授信）。
	var limit: int = JWMath.mul_ppm(world.base_credit_limit,
			JWMath.clamp_i(JWUnits.PPM - _eff_ppm[K_CREDIT], 0, JWUnits.PPM))
	fault = world.set_credit_limit(limit)
	if fault != JWResult.OK:
		return fault

	# state.world.delivery_capacity_uqs 不在本步写：docs/12 §01.7 的四条赋值里没有它，
	# 三个冲击的 channel 也都不指向它。缺一条公式就不许自造一条（已登记为 open_question）。
	return JWResult.OK


## 重放与读档：把存档里的 shock_log 灌回来。
## 步骤：LOAD
## 前置：行数与 manifest 一致
## 后置：后续 resolve_quarter 在同 q 会复用记录
## 不变量：INV-109、INV-131、INV-133（save→load→advance 与 advance 逐位相同）
## 失败：格式不符 → Load.SAVE_CORRUPT
func load_shock_log(rows: PackedInt64Array) -> JWResult:
	var n_flat: int = rows.size()
	# rounding: floor, reason=行宽固定 7 列，除不尽即行被截断，属坏档
	var n_rows: int = JWMath.floor_div(n_flat, LOG_COLS)
	if JWMath.mul(n_rows, LOG_COLS) != n_flat:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, n_flat, LOG_COLS)

	# 先整体校验再落地：半截灌进去的日志会让 INV-109 拿着一部分记录去复用，
	# 比干脆拒绝加载更难排查（docs/11 §6.6：坏档必须当场发现，不做尽力修复）。
	var i: int = 0
	while i < n_rows:
		var base: int = JWMath.mul(i, LOG_COLS)
		if rows[base] < 0:
			return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, i, rows[base])
		if rows[base + 1] < 0 or rows[base + 1] >= JWUnits.SHOCK_N:
			return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, i, rows[base + 1])
		if rows[base + 3] < 1:
			# duration_q < 1 会让 01.7 的线性衰减除零，坏档在这里就要被挡住。
			return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, i, rows[base + 3])
		if rows[base + 4] < 0:
			return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, i, rows[base + 4])
		i += 1

	while _log_capacity < n_rows:
		_log_grow()

	i = 0
	while i < n_rows:
		var base: int = JWMath.mul(i, LOG_COLS)
		sl_q[i] = rows[base]
		sl_kind[i] = rows[base + 1]
		sl_mag[i] = rows[base + 2]
		sl_dur[i] = rows[base + 3]
		sl_draw_index[i] = rows[base + 4]
		sl_raw[i] = rows[base + 5]
		sl_mapped[i] = rows[base + 6]
		i += 1
	_log_rows_total = n_rows
	# 本季游标归零：载入不属于任何一季的结算，行数对账从下一次 S01 重新起算。
	_log_cursor = 0
	return JWResult.make_ok()


## 重放与存档：把 shock_log 导出成扁平整数行。
## 步骤：存档 / 故障包导出
## 前置：无
## 后置：不改状态
## 不变量：INV-109、INV-131
## 失败：无
func export_shock_log() -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(JWMath.mul(_log_rows_total, LOG_COLS))
	var i: int = 0
	while i < _log_rows_total:
		var base: int = JWMath.mul(i, LOG_COLS)
		out[base] = sl_q[i]
		out[base + 1] = sl_kind[i]
		out[base + 2] = sl_mag[i]
		out[base + 3] = sl_dur[i]
		out[base + 4] = sl_draw_index[i]
		out[base + 5] = sl_raw[i]
		out[base + 6] = sl_mapped[i]
		i += 1
	return out


## 只读（报告与诊断）：该类冲击本季是否生效。
## 步骤：全部
## 前置：k ∈ [0,3)
## 后置：不改状态
## 不变量：INV-109
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func is_active(k: int) -> bool:
	if k < 0 or k >= JWUnits.SHOCK_N or active.size() != JWUnits.SHOCK_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, k, JWUnits.SHOCK_N)
		return false
	return active[k] != 0


## 只读（报告与诊断）：该类冲击本季强度。
## 步骤：全部
## 前置：k ∈ [0,3)
## 后置：不改状态
## 不变量：INV-109
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func magnitude(k: int) -> int:
	if k < 0 or k >= JWUnits.SHOCK_N or magnitude_ppm.size() != JWUnits.SHOCK_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, k, JWUnits.SHOCK_N)
		return 0
	return magnitude_ppm[k]


## 只读（报告与诊断）：该类冲击剩余季数。
## 步骤：全部
## 前置：k ∈ [0,3)
## 后置：不改状态
## 不变量：INV-109
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func remaining(k: int) -> int:
	if k < 0 or k >= JWUnits.SHOCK_N or remaining_q.size() != JWUnits.SHOCK_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, k, JWUnits.SHOCK_N)
		return 0
	return remaining_q[k]


## §1.6 状态块协议：LOAD 期一次性 resize 到 §2 的契约长度。
## 步骤：LOAD
## 前置：维度常量已确定
## 后置：五个状态数组长 JWUnits.SHOCK_N；七条日志长 JWUnits.LOG_CAP0
## 不变量：docs/10 §0.6（加载期一次性 resize）
## 失败：无
func allocate() -> void:
	active.resize(JWUnits.SHOCK_N)
	active.fill(0)
	remaining_q.resize(JWUnits.SHOCK_N)
	remaining_q.fill(0)
	magnitude_ppm.resize(JWUnits.SHOCK_N)
	magnitude_ppm.fill(0)
	duration_q.resize(JWUnits.SHOCK_N)
	duration_q.fill(0)
	last_end_q.resize(JWUnits.SHOCK_N)
	last_end_q.fill(LAST_END_NONE)

	channel.resize(JWUnits.SHOCK_N)
	channel.fill(0)
	target_weights_ppm.resize(TARGET_WEIGHTS_N)
	target_weights_ppm.fill(0)
	hazard_ppm.resize(JWUnits.SHOCK_N)
	hazard_ppm.fill(0)
	earliest_q.resize(JWUnits.SHOCK_N)
	earliest_q.fill(0)
	min_gap_q.resize(JWUnits.SHOCK_N)
	min_gap_q.fill(0)
	max_active.resize(JWUnits.SHOCK_N)
	max_active.fill(0)
	mag_min.resize(JWUnits.SHOCK_N)
	mag_min.fill(0)
	mag_max.resize(JWUnits.SHOCK_N)
	mag_max.fill(0)
	dur_min.resize(JWUnits.SHOCK_N)
	dur_min.fill(0)
	dur_max.resize(JWUnits.SHOCK_N)
	dur_max.fill(0)
	onset_profile.resize(JWUnits.SHOCK_N)
	onset_profile.fill(ONSET_STEP)
	decay_profile.resize(JWUnits.SHOCK_N)
	decay_profile.fill(DECAY_NONE)

	sl_q.resize(JWUnits.LOG_CAP0)
	sl_kind.resize(JWUnits.LOG_CAP0)
	sl_mag.resize(JWUnits.LOG_CAP0)
	sl_dur.resize(JWUnits.LOG_CAP0)
	sl_draw_index.resize(JWUnits.LOG_CAP0)
	sl_raw.resize(JWUnits.LOG_CAP0)
	sl_mapped.resize(JWUnits.LOG_CAP0)
	_log_capacity = JWUnits.LOG_CAP0
	_log_cursor = 0
	_log_rows_total = 0
	_log_grow_count = 0

	_eff_ppm.resize(JWUnits.SHOCK_N)
	_eff_ppm.fill(0)


## §1.6 状态块协议：按下标只读取用状态数组（返回引用，调用方不得写）。
## 步骤：加载、哈希、存档
## 前置：i ∈ [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136（下标顺序是 schema 的一部分）
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回空数组
func state_array(i: int) -> PackedInt64Array:
	if i == 0:
		return active
	if i == 1:
		return remaining_q
	if i == 2:
		return magnitude_ppm
	if i == 3:
		return duration_q
	if i == 4:
		return last_end_q
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


## §1.6 状态块协议：写入状态数组，**仅 LOAD / MIG**。
## 步骤：LOAD / MIG
## 前置：调用点位于 systems/content_loader.gd 或 systems/saves.gd（静态检查）
## 后置：对应成员被整体替换，长度必须与契约一致
## 不变量：INV-136
## 失败：越界或长度不符 → 返回对应 Fault / Load 码
func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i < 0 or i >= STATE_ARRAY_IDS.size():
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	if v.size() != JWUnits.SHOCK_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v.size(), JWUnits.SHOCK_N)
	# duplicate()：Packed*Array 传参是引用语义，直接赋值会让权威状态与调用方的临时数组
	# 共用一块内存，此后调用方改一位就等于偷改了状态（与 JWRngStreams 同一处理）。
	if i == 0:
		active = v.duplicate()
	elif i == 1:
		remaining_q = v.duplicate()
	elif i == 2:
		magnitude_ppm = v.duplicate()
	elif i == 3:
		duration_q = v.duplicate()
	else:
		last_end_q = v.duplicate()
	return JWResult.OK


## §1.6 状态块协议：按下标读取状态标量（本块无状态标量）。
## 步骤：加载、哈希、存档
## 前置：i ∈ [0, STATE_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回 0
func state_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


## §1.6 状态块协议：写入状态标量，**仅 LOAD / MIG**（本块无状态标量）。
## 步骤：LOAD / MIG
## 前置：调用点位于 systems/content_loader.gd 或 systems/saves.gd（静态检查）
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → 返回 Fault.INDEX_OUT_OF_RANGE
func set_state_scalar(i: int, v: int) -> int:
	# v 无处可写：本块的 STATE_SCALAR_IDS 是空表，任何下标都越界。
	# 签名由 §1.6 固定，不能因为没有标量就改成别的形状。
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v)


## §1.6 状态块协议：按下标只读取用流量数组（本块无流量）。
## 步骤：报告、哈希对账
## 前置：i ∈ [0, FLOW_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-013
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回空数组
func flow_array(i: int) -> PackedInt64Array:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
	return PackedInt64Array()


## §1.6 状态块协议：按下标读取流量标量（本块无流量）。
## 步骤：报告、哈希对账
## 前置：i ∈ [0, FLOW_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-013
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回 0
func flow_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_SCALAR_IDS.size())
	return 0


## §1.6 状态块协议：全部 FLOW_* 归零，**仅 S01**（本块无流量，是空实现）。
## 步骤：S01 §01.3
## 前置：调用点位于 systems/turn_runner.gd 的 _step_s01（静态检查）
## 后置：不改状态
## 不变量：INV-013
## 失败：无
func reset_flows() -> void:
	# 冲击只改 state.world.*（存量），不产生任何 flow.*：出口与进口的流量由 JWWorldMarket
	# 在 S05 成交时登记。这里保持空实现，不是漏写。
	pass


## §1.6 状态块协议：S01 清零后的自检，非 0 即 FLOW_NOT_RESET（本块恒 0）。
## 步骤：S01 §01.3 末
## 前置：reset_flows() 刚被调用
## 后置：不改状态
## 不变量：INV-013
## 失败：无
func flow_abs_sum() -> int:
	return 0


## §1.7 日志通道协议：每季 S01 重置本季游标（日志不进 state_hash）。
## 步骤：S01 §01.1
## 前置：phase == S01
## 后置：_log_cursor == 0
## 不变量：INV-011 / INV-139（行数对账）
## 失败：无
func log_reset_quarter() -> void:
	# 只归零本季游标，**不动 _log_rows_total 与已写的行**：INV-109 的「先查后抽」
	# 查的正是往季留下的记录，清掉它就等于每次读档都重抽一遍已确定的冲击。
	_log_cursor = 0


## §1.7 日志通道协议：本季已写行数，供 INV-011 / INV-139 对账。
## 步骤：每季末
## 前置：无
## 后置：不改状态
## 不变量：INV-011、INV-139
## 失败：无
func log_row_count() -> int:
	return _log_cursor


## §1.7 日志通道协议：当前容量；写满时按 1.5 倍扩容并写一条告警行。
## 步骤：每季末
## 前置：无
## 后置：不改状态
## 不变量：INV-139
## 失败：无
func log_capacity() -> int:
	return _log_capacity


## 本局日志扩容发生的次数（本通道以计数器代替告警行，理由见 _log_grow_count 的说明）。
## 步骤：每季末 / 诊断
## 前置：无
## 后置：不改状态
## 不变量：INV-139
## 失败：无
func log_grow_count() -> int:
	return _log_grow_count


## shock_log 的累计行数（跨季），供存档与 INV-109 对账。
## 步骤：存档 / 诊断
## 前置：无
## 后置：不改状态
## 不变量：INV-109、INV-131
## 失败：无
func log_rows_total() -> int:
	return _log_rows_total

# ── 内部实现 ───────────────────────────────────────────────────────────────

## 维度自检：allocate() 没跑过就结算，会让下标寻址读到空数组。
## 步骤：S01 §01.6 / §01.7 入口
## 前置：无
## 后置：不改状态
## 不变量：docs/10 §0.6（加载期一次性 resize，此后长度恒定）
## 失败：长度不符 → Fault.INDEX_OUT_OF_RANGE
func _check_dims() -> int:
	if active.size() != JWUnits.SHOCK_N or remaining_q.size() != JWUnits.SHOCK_N \
			or magnitude_ppm.size() != JWUnits.SHOCK_N or duration_q.size() != JWUnits.SHOCK_N \
			or last_end_q.size() != JWUnits.SHOCK_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				active.size(), JWUnits.SHOCK_N)
	if channel.size() != JWUnits.SHOCK_N or hazard_ppm.size() != JWUnits.SHOCK_N \
			or earliest_q.size() != JWUnits.SHOCK_N or min_gap_q.size() != JWUnits.SHOCK_N \
			or max_active.size() != JWUnits.SHOCK_N or mag_min.size() != JWUnits.SHOCK_N \
			or mag_max.size() != JWUnits.SHOCK_N or dur_min.size() != JWUnits.SHOCK_N \
			or dur_max.size() != JWUnits.SHOCK_N or onset_profile.size() != JWUnits.SHOCK_N \
			or decay_profile.size() != JWUnits.SHOCK_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				channel.size(), JWUnits.SHOCK_N)
	if target_weights_ppm.size() != TARGET_WEIGHTS_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				target_weights_ppm.size(), TARGET_WEIGHTS_N)
	if _eff_ppm.size() != JWUnits.SHOCK_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				_eff_ppm.size(), JWUnits.SHOCK_N)
	return JWResult.OK


## 把一条（新抽的或从日志复用的）冲击记录落到状态上。
## 步骤：S01 §01.6 (a) 与 (c) 共用
## 前置：k ∈ [0,3)；d >= 1
## 后置：active[k] == 1；magnitude_ppm[k] == m；remaining_q[k] == duration_q[k] == d
## 不变量：INV-109（复用与新抽走同一条落地路径，二者逐位相同）
## 失败：d < 1 → Fault.DIV_ZERO（01.7 的线性衰减会以 d 为分母）
##
## 到达当季 remaining == duration，所以 01.7 的线性衰减因子在到达季恰为 1e6：
## 「到达当季满强度，此后按剩余季数线性退坡」，与 docs/12 §01.7 的注释一致。
func _apply_record(k: int, m: int, d: int) -> int:
	if d < 1:
		return JWResult.raise_fault(JWResult.Fault.DIV_ZERO, d, 0)
	active[k] = 1
	magnitude_ppm[k] = m
	remaining_q[k] = d
	duration_q[k] = d
	return JWResult.OK


## 查 shock_log 里是否已有 (q, k) 的记录（INV-109 的「先查后抽」）。
## 步骤：S01 §01.6 (a)
## 前置：无
## 后置：不改状态
## 不变量：INV-109
## 失败：同一 (q, k) 有两行 → 返回 LOG_ROW_CONFLICT，由调用方转 Fault.RNG_LOG_MISMATCH
##
## 线性扫描而不是建索引字典：40 季 × 3 类冲击的到达行数以十计，
## 而热路径禁止新建字典（docs/17 §1.4）。
func _find_log_row(qq: int, k: int) -> int:
	var found: int = -1
	var i: int = 0
	while i < _log_rows_total:
		if sl_q[i] == qq and sl_kind[i] == k:
			if found >= 0:
				return LOG_ROW_CONFLICT
			found = i
		i += 1
	return found


## 取 rng 刚写下的那一行 log.rng 的行号（被采纳的那次抽样）。
## 步骤：S01 §01.6 (c)
## 前置：刚调用过一次 rng 的抽样方法
## 后置：不改状态
## 不变量：INV-011（每次抽样恰好一行 log.rng）
## 失败：行号不可用 → 登记 Fault.RNG_LOG_MISMATCH 并返回 −1
##
## 不用「抽样前的 draw_count」当 draw_index：拒绝采样会多推进若干次计数器，
## 被采纳的那次的 index 只有 rng 自己的日志末行知道。
func _rng_last_log_row(rng: JWRngStreams) -> int:
	var row: int = rng.log_row_count() - 1
	if row < 0 or row >= rng.log_raw.size() or row >= rng.log_draw_index.size():
		JWResult.raise_fault(JWResult.Fault.RNG_LOG_MISMATCH, row, rng.log_raw.size())
		return -1
	return row


## 写一行 shock_log。每次**到达**恰好一行（衰减季不写行，它不消耗抽样）。
## 步骤：S01 §01.6 (c)
## 前置：无
## 后置：_log_rows_total += 1；_log_cursor += 1；必要时先扩容
## 不变量：INV-109、INV-139
## 失败：无（容量不足时先扩容再写）
func _log_write(qq: int, k: int, m: int, d: int, draw_index: int, raw: int, mapped: int) -> void:
	if _log_rows_total >= _log_capacity:
		_log_grow()
	sl_q[_log_rows_total] = qq
	sl_kind[_log_rows_total] = k
	sl_mag[_log_rows_total] = m
	sl_dur[_log_rows_total] = d
	sl_draw_index[_log_rows_total] = draw_index
	sl_raw[_log_rows_total] = raw
	sl_mapped[_log_rows_total] = mapped
	_log_rows_total += 1
	_log_cursor += 1


## 七张 log 数组按 1.5 倍同步扩容（docs/10 §12）。
## 步骤：写日志时容量耗尽
## 前置：无
## 后置：七张数组等长且 > 原长
## 不变量：INV-139
## 失败：无
func _log_grow() -> void:
	var cap: int = _log_capacity
	var next_cap: int = JWUnits.LOG_CAP0
	if cap > 0:
		# rounding: ceil, reason=1.5 倍扩容宁可多要一行也不能因取整停在原容量上
		next_cap = JWMath.ceil_div(JWMath.mul(cap, LOG_GROWTH_NUM), LOG_GROWTH_DEN)
	if next_cap <= cap:
		next_cap = cap + 1
	sl_q.resize(next_cap)
	sl_kind.resize(next_cap)
	sl_mag.resize(next_cap)
	sl_dur.resize(next_cap)
	sl_draw_index.resize(next_cap)
	sl_raw.resize(next_cap)
	sl_mapped.resize(next_cap)
	_log_capacity = next_cap
	_log_grow_count += 1
