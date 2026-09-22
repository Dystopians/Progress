## 投入产出与技术系数（docs/10 §4.5）。内容包只读，LOAD 后永不改写。
##
## 骨架依据：docs/17_api_skeleton.md §4.7。依赖秩 2，只允许引用秩 0/1（JWUnits / JWResult / JWMath / JWIds）。
## 全部读取器都是纯查表：系数为 0 表示「该约束不适用」，由调用方 continue，本类不做除零也不做 max(c,1)（INV-044）。
class_name JWIoTable
extends RefCounted

## §1.6 状态块协议：本块各数组所属子系统（与 STATE_ARRAY_IDS 等长）。
## 本类全部数组都是 content.*，不进 state_hash（进 content_hash，由 JWContentLoader 负责），
## 故一律登记为 SUBSYS_META；WriteGuard 对 META 子系统只做「加载后不得再写」的检查。
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_META, JWUnits.SUBSYS_META, JWUnits.SUBSYS_META, JWUnits.SUBSYS_META,
	JWUnits.SUBSYS_META, JWUnits.SUBSYS_META, JWUnits.SUBSYS_META, JWUnits.SUBSYS_META,
]

## 稳定 ID 注册表：下标 == 数组序号，内容是 docs/10 的稳定 ID 字符串。
## 只在加载与哈希时被读，结算期不触碰（无 String 进入热路径）。顺序是 schema 的一部分（INV-136）。
const STATE_ARRAY_IDS: PackedStringArray = [
	"content.io.io_coeff_uqs_per_qs",
	"content.io.labor_coeff_persons_per_qs",
	"content.io.energy_coeff_uqs_per_qs",
	"content.io.spoilage_ppm",
	"content.io.depreciation_ppm_per_q",
	"content.io.capacity_per_capital_uu_ppm",
	"content.io.emission_ppm",
	"content.storable",
]
const STATE_SCALAR_IDS: PackedStringArray = []
const FLOW_ARRAY_IDS: PackedStringArray = []
const FLOW_SCALAR_IDS: PackedStringArray = []

## 各 state 数组的契约长度，下标与 STATE_ARRAY_IDS 对齐（docs/17 §2.1）。
## 长度本身是 schema 的一部分（INV-136）：allocate() 与 set_state_array() 都以它为唯一依据，
## 不在两处各写一份字面量，避免二者漂移后谁也发现不了。
## R-SCENARIO-02：含随地区数变化的维度，因此是函数而不是常量。
static func state_array_len() -> PackedInt64Array:
	return PackedInt64Array([
		JWUnits.IO_N, JWUnits.EMP_N, JWUnits.CELL, JWUnits.S,
		JWUnits.S, JWUnits.S, JWUnits.S, JWUnits.S,
	])

## V-IO-05 的整数迭代轮数（docs/11 §5.5）。
const LEONTIEF_ROUNDS: int = 30

## content.io.io_coeff_uqs_per_qs[] —— 长度 16（按 idx_io），单位 μQ_from / Q_to。类 C，写入者 LOAD。
var io_coeff: PackedInt64Array = PackedInt64Array()
## content.io.labor_coeff_persons_per_qs[] —— 长度 48（按 idx_emp(cell,k)），单位 人 / Q_s。类 C，写入者 LOAD。
var labor_coeff: PackedInt64Array = PackedInt64Array()
## content.io.energy_coeff_uqs_per_qs[] —— 长度 16（按 cell），单位 μQ_energy / Q_s。
## IO 表能源行的冗余副本，加载期必须与 io_coeff 交叉一致（V-IO-08）。类 C，写入者 LOAD。
var energy_coeff: PackedInt64Array = PackedInt64Array()
## content.io.spoilage_ppm[] —— 长度 4，单位 ppm/季。类 C，写入者 LOAD。
var spoilage_ppm: PackedInt64Array = PackedInt64Array()
## content.io.depreciation_ppm_per_q[] —— 长度 4，单位 ppm/季（产能轨与价值轨同率，INV-056）。类 C，写入者 LOAD。
var depreciation_ppm: PackedInt64Array = PackedInt64Array()
## content.io.capacity_per_capital_uu_ppm[] —— 长度 4，单位 μQ_s/季 每 μU，只在投运时用一次。类 C，写入者 LOAD。
var capacity_per_capital_ppm: PackedInt64Array = PackedInt64Array()
## content.io.emission_ppm[] —— 长度 4，单位 ppm。类 C，写入者 LOAD。
var emission_ppm: PackedInt64Array = PackedInt64Array()
## content.storable[] —— 长度 4，0/1；energy 与 services 必须为 0（INV-049/INV-150）。类 C，写入者 LOAD。
var storable: PackedInt64Array = PackedInt64Array()
## R-INVEST-01：企业资本品购买按产品的构成（ppm，Σ == 1e6）。内容常量，由加载器直接写入，
## 不进状态块协议（与 JWWorldMarket.base_export_uqs 同一先例）；读档时随内容包重新载入。
var capital_goods_split_ppm: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])


## 读取 s_from → s_to 的投入产出系数。系数为 0 表示「该约束不适用」，调用方必须 continue，
## 禁止除零，也禁止用 max(c,1) 代替（INV-044）。
## 步骤：S03 §3.2/§3.5、S05 §5.3/§5.4、S06 §6.1
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-044
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func io(s_from: int, s_to: int) -> int:
	if s_from < 0 or s_from >= JWUnits.S or s_to < 0 or s_to >= JWUnits.S:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, s_from, s_to)
		return 0
	var i: int = JWIds.idx_io(s_from, s_to)
	# 未 allocate 时数组为空：同样是越界，显式登记而不是返回一个看起来正常的 0。
	if i >= io_coeff.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, io_coeff.size())
		return 0
	return io_coeff[i]


## 读取 cell 对技能 k 的劳动系数（人 / Q_s）。系数为 0 表示该约束不适用（INV-044）。
## 步骤：S03 §3.2、S05 §5.3
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-044
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func labor(cell: int, k: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL or k < 0 or k >= JWUnits.K:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, k)
		return 0
	var i: int = JWIds.idx_emp(cell, k)
	if i >= labor_coeff.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, labor_coeff.size())
		return 0
	return labor_coeff[i]


## 读取 cell 的能源系数（μQ_energy / Q_s）。系数为 0 表示该约束不适用（INV-044）。
## 步骤：S03 §3.5、S05 §5.3
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-044
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func energy(cell: int) -> int:
	# 本数组是 io_coeff 能源行的冗余副本（按 cell 展开），V-IO-08 在加载期把二者钉死；
	# 运行期的权威值仍是 io(ENERGY, sector_of_cell)，见 docs/12 §3.5。
	if cell < 0 or cell >= energy_coeff.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, energy_coeff.size())
		return 0
	return energy_coeff[cell]


## 读取部门 s 的季度损耗率（ppm/季）。
## 步骤：S05 §5.8
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-044、INV-053（损耗显式登记，不得用盘点差异吸收）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func spoilage(s: int) -> int:
	if s < 0 or s >= spoilage_ppm.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, s, spoilage_ppm.size())
		return 0
	return spoilage_ppm[s]


## 读取部门 s 的季度折旧率（ppm/季），产能轨与价值轨同率。
## 步骤：S06 §6.1
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-056（同一折旧率）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func depreciation(s: int) -> int:
	if s < 0 or s >= depreciation_ppm.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, s, depreciation_ppm.size())
		return 0
	return depreciation_ppm[s]


## 读取部门 s 的「每 μU 资本对应产能」系数（μQ_s/季 每 μU），只在投运时用一次。
## 步骤：LOAD、S07 §7.1 投运瞬间
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-056（|capacity − capital × coeff / 1e6| <= 1 μQ_s）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func capacity_per_capital(s: int) -> int:
	# 分母是 μU，方向与金额系数相反（裁定 R-SCALE-01 第 2 条）：μU 变细 1000 倍，
	# 本系数已整体 ÷1000（现值 [200, 180, 55, 160]）。这里只做查表，换算由调用方走
	# JWMath.mul_div_floor(capital_uu, coeff, PPM)，不得在此处替调用方乘除。
	if s < 0 or s >= capacity_per_capital_ppm.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, s, capacity_per_capital_ppm.size())
		return 0
	return capacity_per_capital_ppm[s]


## 读取部门 s 的排放系数（ppm）。
## 步骤：S05 §5.8
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-057（排放只累积，首版不反馈到生产约束）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func emission(s: int) -> int:
	if s < 0 or s >= emission_ppm.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, s, emission_ppm.size())
		return 0
	return emission_ppm[s]


## 部门 s 是否可库存。energy 与 services 恒为不可库存（INV-049/INV-150）。
## 步骤：S03 §3.1、S05 §5.4/§5.8
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-049、INV-150
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 false
func is_storable(s: int) -> bool:
	if s < 0 or s >= storable.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, s, storable.size())
		return false
	return storable[s] != 0


## 加载期校验（V-IO-01..08 的落点）。
## 步骤：LOAD
## 前置：全部数组已填充
## 后置：不改状态
## 不变量：INV-150（每列和 < 1e6、storable[energy]==0、storable[services]==0、a(energy→energy)<1e6）、
##          INV-052（能源自用收敛）、V-IO-08（energy_coeff 与 io_coeff 的冗余一致）
## 失败：Load.IO_COLSUM / IO_STORABLE / IO_ENERGY_SELF / IO_NEGATIVE / IO_ENERGY_COEFF / IO_LABOR
func validate() -> JWResult:
	# 顺序不是随意的：docs/31 §能源自用 要求 a(energy,energy) >= 1e6 报 E_IO_ENERGY_SELF
	# 而不是 E_IO_COLSUM——该情形两条都成立，故自用检查必须排在列和之前。

	# 长度先行：数组没按契约长度填满时，后面的逐项检查全是无意义的越界读。
	for i: int in range(STATE_ARRAY_IDS.size()):
		var want: int = state_array_len()[i]
		var got: int = _array_size(i)
		if got != want:
			return JWResult.make_err(JWResult.Load.SCHEMA_HEADER, i, got)

	# V-IO-04：全部系数 >= 0。`== 0` 是合法值（表示跳过该约束），不是错误。
	for i: int in range(JWUnits.IO_N):
		if io_coeff[i] < 0:
			return JWResult.make_err(JWResult.Load.IO_NEGATIVE, i, io_coeff[i])
	for i: int in range(JWUnits.EMP_N):
		if labor_coeff[i] < 0:
			return JWResult.make_err(JWResult.Load.IO_NEGATIVE, i, labor_coeff[i])
	for i: int in range(JWUnits.CELL):
		if energy_coeff[i] < 0:
			return JWResult.make_err(JWResult.Load.IO_NEGATIVE, i, energy_coeff[i])
	for s: int in range(JWUnits.S):
		if spoilage_ppm[s] < 0:
			return JWResult.make_err(JWResult.Load.IO_NEGATIVE, s, spoilage_ppm[s])
		if depreciation_ppm[s] < 0:
			return JWResult.make_err(JWResult.Load.IO_NEGATIVE, s, depreciation_ppm[s])
		if capacity_per_capital_ppm[s] < 0:
			return JWResult.make_err(JWResult.Load.IO_NEGATIVE, s, capacity_per_capital_ppm[s])
		if emission_ppm[s] < 0:
			return JWResult.make_err(JWResult.Load.IO_NEGATIVE, s, emission_ppm[s])

	# V-IO-02：storable 只能取 0/1，且 energy 与 services 必须为 0（计划书 §06，INV-049/INV-150）。
	for s: int in range(JWUnits.S):
		if storable[s] != 0 and storable[s] != 1:
			return JWResult.make_err(JWResult.Load.IO_STORABLE, s, storable[s])
	if storable[JWUnits.Sector.ENERGY] != 0:
		return JWResult.make_err(JWResult.Load.IO_STORABLE,
				JWUnits.Sector.ENERGY, storable[JWUnits.Sector.ENERGY])
	if storable[JWUnits.Sector.SERVICES] != 0:
		return JWResult.make_err(JWResult.Load.IO_STORABLE,
				JWUnits.Sector.SERVICES, storable[JWUnits.Sector.SERVICES])

	# V-IO-03：能源自用系数 < 1e6，否则能源部门吃掉自身全部产出（docs/12 §3.5，INV-052）。
	var self_use: int = io_coeff[JWIds.idx_io(JWUnits.Sector.ENERGY, JWUnits.Sector.ENERGY)]
	if self_use >= JWUnits.PPM:
		return JWResult.make_err(JWResult.Load.IO_ENERGY_SELF, self_use, JWUnits.PPM)

	# V-IO-01：每「列」（消耗方 s_to）的中间投入合计 < 1e6，否则增加值必为负（INV-150）。
	for s_to: int in range(JWUnits.S):
		var col_sum: int = 0
		for s_from: int in range(JWUnits.S):
			col_sum += io_coeff[JWIds.idx_io(s_from, s_to)]
		if col_sum >= JWUnits.PPM:
			return JWResult.make_err(JWResult.Load.IO_COLSUM, s_to, col_sum)

	# V-IO-08：energy_coeff 是 IO 表能源行按 cell 展开的冗余副本，逐格交叉校验（docs/12 §3.5）。
	for cell: int in range(JWUnits.CELL):
		var s: int = JWIds.SECTOR_OF_CELL[cell]
		var row: int = io_coeff[JWIds.idx_io(JWUnits.Sector.ENERGY, s)]
		if energy_coeff[cell] != row:
			return JWResult.make_err(JWResult.Load.IO_ENERGY_COEFF, cell, energy_coeff[cell])

	# V-IO-06：展开后的 labor_coeff 每格至少一档 > 0（负值已由 V-IO-04 拦下，
	# 故「要么 == 0 要么 >= 1」在整数下已自动成立，此处只剩「至少一档 > 0」）。
	for cell: int in range(JWUnits.CELL):
		var any_positive: bool = false
		for k: int in range(JWUnits.K):
			if labor_coeff[JWIds.idx_emp(cell, k)] > 0:
				any_positive = true
				break
		if not any_positive:
			return JWResult.make_err(JWResult.Load.IO_LABOR, cell, 0)

	# V-IO-07：capacity_per_capital_uu_ppm[s] > 0（0 会让投运时的产能恒为 0）。
	for s: int in range(JWUnits.S):
		if capacity_per_capital_ppm[s] <= 0:
			return JWResult.make_err(JWResult.Load.IO_CAPACITY_COEFF, s, capacity_per_capital_ppm[s])

	# V-IO-05：Leontief 可行性的整数近似。以「每部门 1 Q_s 最终需求」为第 0 层，
	# 逐层展开间接投入；每层的实物量为 layer[to] × a(from,to) / Q_SCALE（先乘后除走 mul_div_floor）。
	# 列和 < 1e6 使层总量严格递减，30 轮后增量必须 < 1 μQ（整数下即 == 0），否则判不收敛。
	# 诚实声明：这是幂和近似，不是特征值计算，只拦「投入比产出还多」这类明显错配（docs/11 §5.5）。
	var layer: PackedInt64Array = PackedInt64Array()
	layer.resize(JWUnits.S)
	layer.fill(JWUnits.Q_SCALE)
	var next_layer: PackedInt64Array = PackedInt64Array()
	next_layer.resize(JWUnits.S)
	var increment: int = 0
	for _round: int in range(LEONTIEF_ROUNDS):
		next_layer.fill(0)
		increment = 0
		for s_to: int in range(JWUnits.S):
			var q_to: int = layer[s_to]
			if q_to == 0:
				continue
			for s_from: int in range(JWUnits.S):
				var a: int = io_coeff[JWIds.idx_io(s_from, s_to)]
				# 系数为 0 ⇒ 该投入不适用，跳过（INV-044），不做除零也不折算。
				if a == 0:
					continue
				# rounding: floor, reason=V-IO-05 是可行性近似，少算优于多算；
				# 多算会把收敛的表误判成发散，从而拒绝合法内容包。
				var need: int = JWMath.mul_div_floor(q_to, a, JWUnits.Q_SCALE)
				next_layer[s_from] += need
				increment += need
		for s: int in range(JWUnits.S):
			layer[s] = next_layer[s]
		if increment == 0:
			break
	if increment != 0:
		return JWResult.make_err(JWResult.Load.IO_NOT_CONVERGENT, LEONTIEF_ROUNDS, increment)

	return JWResult.make_ok()


## §1.6 状态块协议：LOAD 期一次性 resize 到 §2 的契约长度。
## 步骤：LOAD
## 前置：尚未 allocate
## 后置：八个数组长度分别为 IO_N / EMP_N / CELL / S / S / S / S / S，且全部为 0
## 不变量：INV-136（数组顺序与长度是 schema 的一部分）
## 失败：无
func allocate() -> void:
	io_coeff.resize(JWUnits.IO_N)
	io_coeff.fill(0)
	labor_coeff.resize(JWUnits.EMP_N)
	labor_coeff.fill(0)
	energy_coeff.resize(JWUnits.CELL)
	energy_coeff.fill(0)
	spoilage_ppm.resize(JWUnits.S)
	spoilage_ppm.fill(0)
	depreciation_ppm.resize(JWUnits.S)
	depreciation_ppm.fill(0)
	capacity_per_capital_ppm.resize(JWUnits.S)
	capacity_per_capital_ppm.fill(0)
	emission_ppm.resize(JWUnits.S)
	emission_ppm.fill(0)
	storable.resize(JWUnits.S)
	storable.fill(0)


## §1.6 状态块协议：只读取用（返回引用，调用方不得写）。
## 步骤：LOAD / 哈希 / 存档
## 前置：i ∈ [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func state_array(i: int) -> PackedInt64Array:
	match i:
		0:
			return io_coeff
		1:
			return labor_coeff
		2:
			return energy_coeff
		3:
			return spoilage_ppm
		4:
			return depreciation_ppm
		5:
			return capacity_per_capital_ppm
		6:
			return emission_ppm
		7:
			return storable
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


## §1.6 状态块协议：仅 LOAD / MIG 可调（静态检查：调用点必须在 systems/content_loader.gd 或 systems/saves.gd）。
## 步骤：LOAD / MIG
## 前置：allocate() 已调用；v 长度与契约一致
## 后置：对应数组逐位等于 v
## 不变量：INV-136
## 失败：越界或长度不符 → 返回 JWResult.Load.SCHEMA_HEADER / INDEX_OUT_OF_RANGE
func set_state_array(i: int, v: PackedInt64Array) -> int:
	# 下标不合法是调用方的编码缺陷，登记为故障；长度不符是内容包的数据缺陷，作为加载拒绝返回。
	if i < 0 or i >= STATE_ARRAY_IDS.size():
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	if v.size() != state_array_len()[i]:
		return JWResult.Load.SCHEMA_HEADER
	# duplicate()：Godot 4 的 Packed*Array 传参是引用语义，直接赋值会让本块与调用方的
	# 临时数组共用同一块内存，此后调用方改一位就等于偷改了内容包。
	match i:
		0:
			io_coeff = v.duplicate()
		1:
			labor_coeff = v.duplicate()
		2:
			energy_coeff = v.duplicate()
		3:
			spoilage_ppm = v.duplicate()
		4:
			depreciation_ppm = v.duplicate()
		5:
			capacity_per_capital_ppm = v.duplicate()
		6:
			emission_ppm = v.duplicate()
		7:
			storable = v.duplicate()
	return JWResult.OK


## §1.6 状态块协议：本类无标量状态，恒返回 0。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：—
## 失败：无
func state_scalar(_i: int) -> int:
	# STATE_SCALAR_IDS 为空：没有任何合法下标，也就没有「越界」可言（契约「失败：无」）。
	return 0


## §1.6 状态块协议：本类无标量状态，恒返回 OK 且不做任何事。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：—
## 失败：无
func set_state_scalar(_i: int, _v: int) -> int:
	return JWResult.OK


## §1.6 状态块协议：本类无流量，恒返回空数组。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：—
## 失败：无
func flow_array(_i: int) -> PackedInt64Array:
	# FLOW_ARRAY_IDS 为空：没有任何合法下标，契约明写「失败：无」，故不登记故障。
	return PackedInt64Array()


## §1.6 状态块协议：本类无流量，恒返回 0。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：—
## 失败：无
func flow_scalar(_i: int) -> int:
	return 0


## §1.6 状态块协议：本类无流量，S01 整表清零时对本类是空操作。
## 步骤：S01 §01.3
## 前置：phase == S01
## 后置：不改状态
## 不变量：INV-010（流量每季清零）
## 失败：无
func reset_flows() -> void:
	pass


## §1.6 状态块协议：S01 清零后的自检，非 0 即 FLOW_NOT_RESET。本类恒为 0。
## 步骤：S01 §01.3 末
## 前置：reset_flows() 已调用
## 后置：不改状态
## 不变量：INV-010
## 失败：无
func flow_abs_sum() -> int:
	return 0


## 第 i 个 state 数组的当前长度。只在 validate() 的长度前置检查里用，
## 不走 state_array()：那条路径会在下标非法时登记故障，而这里只想问长度。
## 步骤：LOAD
## 前置：i ∈ [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → 返回 -1（必然与任何契约长度不等，由调用方判 SCHEMA_HEADER）
func _array_size(i: int) -> int:
	match i:
		0:
			return io_coeff.size()
		1:
			return labor_coeff.size()
		2:
			return energy_coeff.size()
		3:
			return spoilage_ppm.size()
		4:
			return depreciation_ppm.size()
		5:
			return capacity_per_capital_ppm.size()
		6:
			return emission_ppm.size()
		7:
			return storable.size()
	return -1
