## 帮助：用平常话讲清这局怎么玩（目标、一季怎么过、钱、百姓、产业链、时代、托管与顾问、快捷键）。
class_name JcHelp
extends JcOverlay

const SECTIONS: PackedStringArray = ["goal", "turn", "money", "people", "chain", "era", "steward", "keys"]


func build() -> void:
	width_ratio = 0.6
	set_title(t("jc.help.title"))
	for s: String in SECTIONS:
		body.add_child(JwUi.label(t("jc.help.%s.t" % s), "title_sub", "text.primary"))
		body.add_child(JwUi.para(t("jc.help.%s.b" % s), "text.secondary"))
