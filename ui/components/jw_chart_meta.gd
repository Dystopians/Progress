## 图表四标注（docs/20 §4.4）：时间范围、单位、价格基期、分母。「不适用」必须显式写出，空串即违规（AC-16）。
class_name JwChartMeta
extends Resource

@export var time_range: String = ""
@export var unit: String = ""
@export var price_base: String = ""
@export var denominator: String = ""

const FIELDS: PackedStringArray = ["time_range", "unit", "price_base", "denominator"]


static func make(p_time_range: String, p_unit: String, p_price_base: String, p_denominator: String) -> JwChartMeta:
	var m: JwChartMeta = JwChartMeta.new()
	m.time_range = p_time_range
	m.unit = p_unit
	m.price_base = p_price_base
	m.denominator = p_denominator
	return m


## 为空的字段名（按 FIELDS 顺序）。
func missing() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for f: String in FIELDS:
		if String(get(f)).strip_edges() == "":
			out.append(f)
	return out
