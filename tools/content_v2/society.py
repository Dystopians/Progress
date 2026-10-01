# -*- coding: utf-8 -*-
"""阶层、需要清单、地区（docs/57 §3、§4.3）。"""

P, AR, M, GE = "peasant", "artisan", "merchant", "gentry"
CLASS_ORDER = [P, AR, M, GE]

# 阶层：wage 是基准工钱（两 / 人 / 季）；work 是可劳动人口占比；
# buffer 是想留在手上的积蓄（按几个季度的开销算）；save 是积蓄不够时每季最多从收入里省下的比例
# （积蓄够了就把收入花完，多出来的按 5% / 季慢慢花掉或拿去投资）；invest 表示闲钱会投入民间投资。
CLASSES = [
    dict(id=P, name="农户", wage=1.6, work=0.50, save=0.06, buffer=2.0, invest=False,
         note="种地、放牧、打鱼、伐木，也当兵、修路。"),
    dict(id=AR, name="工匠", wage=3.0, work=0.52, save=0.08, buffer=2.0, invest=False,
         note="作坊、矿场、营造、运输里的手艺人与工人。"),
    dict(id=M, name="商贾", wage=4.0, work=0.45, save=0.20, buffer=5.0, invest=True,
         note="买卖、经营作坊与商铺，是民间投资的主力。"),
    dict(id=GE, name="士绅", wage=5.5, work=0.40, save=0.15, buffer=5.0, invest=True,
         note="读书做官、收租、教书、行医，后来的专业人士。"),
]

# 需要清单（docs/57 §4.3）：每项按优先级排列；qty 是每人每季的需要量（该项的「需要单位」），
# 按阶层给出；goods 是可满足该项的商品及换算（1 单位商品 = 多少需要单位）；
# weight 是该项在「生活水平」里的权重；era/era_end 是生效时代；essential 表示缺了会伤身（口粮、盐）。
# taste（可选）按地区给出口味份额（商品 → 份额），不写的地区按全国统一份额。
# el 是随「日用水平」（篮子 b）伸缩的弹性：0.5 → √b（柴米油盐一类，富了也吃不了多少），
#   1 → b，1.5 → b√b（家具、书、绸缎、瓷器、家电，富了买得更多）。必需品不随篮子变。
NEEDS = [
    # 口粮：农户多是自产自食，不经集市，不付零售加价（其余阶层照付）
    dict(id="staple", name="口粮", essential=True, weight=30, era=1, own_food=True,
         goods={"rice": 1.0, "grain": 1.0, "beans": 0.9, "flour": 1.0, "bread": 1.2},
         qty={P: 0.45, AR: 0.5, M: 0.52, GE: 0.54},
         # 面粉（第二时代）、面包（第三时代）只在吃麦的北方与西岭慢慢普及；稻作区照吃米
         taste={"beiyuan": {"grain": 0.72, "beans": 0.2, "rice": 0.08, "flour": 0.3, "bread": 0.12},
                "zhongzhou": {"rice": 0.72, "grain": 0.14, "beans": 0.14, "flour": 0.06, "bread": 0.04},
                "haijia": {"rice": 0.78, "grain": 0.08, "beans": 0.14, "flour": 0.03, "bread": 0.03},
                "xiling": {"grain": 0.46, "rice": 0.34, "beans": 0.2, "flour": 0.15, "bread": 0.06}}),
    dict(id="salt", name="盐", essential=True, weight=8, era=1, goods={"salt": 1.0},
         qty={P: 0.025, AR: 0.025, M: 0.028, GE: 0.03}),
    dict(id="clothes", name="衣", weight=12, era=1, el=1.0, goods={"fabric": 1.0, "clothing": 1.3, "wool": 3.0},
         qty={P: 0.10, AR: 0.2, M: 0.34, GE: 0.4},
         taste={"beiyuan": {"fabric": 0.9, "wool": 0.1}, "xiling": {"fabric": 0.93, "wool": 0.07},
                "zhongzhou": {"fabric": 1.0}, "haijia": {"fabric": 1.0}}),
    dict(id="fuel", name="柴炭", weight=8, era=1, era_end=4, el=0.5,
         goods={"charcoal": 1.0, "timber": 1.2, "coal": 1.3, "gas": 4.0},
         qty={P: 0.14, AR: 0.40, M: 0.55, GE: 0.65},
         taste={"beiyuan": {"coal": 0.4, "charcoal": 0.3, "timber": 0.3},
                "zhongzhou": {"charcoal": 0.55, "timber": 0.45},
                "haijia": {"charcoal": 0.5, "timber": 0.5},
                "xiling": {"timber": 0.7, "charcoal": 0.3}}),
    dict(id="greens", name="蔬果", weight=6, era=1, el=0.5, goods={"vegetables": 1.0, "fruit": 0.8},
         qty={P: 0.10, AR: 0.24, M: 0.3, GE: 0.32},
         taste={"beiyuan": {"vegetables": 0.86, "fruit": 0.14}, "zhongzhou": {"vegetables": 0.8, "fruit": 0.2},
                "haijia": {"vegetables": 0.7, "fruit": 0.3}, "xiling": {"vegetables": 0.8, "fruit": 0.2}}),
    dict(id="protein", name="鱼肉", weight=6, era=1, el=1.0, goods={"fish": 1.0, "meat": 1.1, "preserved_food": 1.4},
         qty={P: 0.02, AR: 0.06, M: 0.12, GE: 0.15},
         taste={"haijia": {"fish": 0.8, "meat": 0.2}, "beiyuan": {"meat": 0.7, "fish": 0.3},
                "zhongzhou": {"fish": 0.55, "meat": 0.45}, "xiling": {"meat": 0.6, "fish": 0.4}}),
    dict(id="oil", name="油", weight=4, era=1, el=0.5, goods={"cooking_oil": 1.0}, qty={P: 0.004, AR: 0.012, M: 0.03, GE: 0.035}),
    dict(id="wares", name="器用", weight=4, era=1, el=1.0, goods={"earthenware": 1.0, "porcelain": 1.5, "glass": 6.0},
         qty={P: 0.04, AR: 0.15, M: 0.26, GE: 0.3}),
    dict(id="light", name="灯火", weight=3, era=1, el=1.0, goods={"candles": 1.0, "gas": 60.0, "electricity": 200.0},
         qty={P: 0.03, AR: 0.14, M: 0.4, GE: 0.6}),
    dict(id="medicine", name="医药", weight=4, era=1, el=1.0, goods={"medicine": 1.0}, qty={P: 0.004, AR: 0.015, M: 0.03, GE: 0.04}),
    dict(id="furniture", name="家具", weight=3, era=1, el=1.5, goods={"furniture": 1.0}, qty={P: 0.0015, AR: 0.008, M: 0.03, GE: 0.04}),
    dict(id="tea", name="茶", weight=2, era=1, el=1.0, goods={"tea": 1.0, "coffee": 1.0}, qty={P: 0.001, AR: 0.006, M: 0.02, GE: 0.03}),
    dict(id="drink", name="酒", weight=2, era=1, el=0.5, goods={"wine": 1.0, "beer": 1.0}, qty={P: 0.02, AR: 0.08, M: 0.15, GE: 0.2}),
    dict(id="letters", name="纸墨", weight=2, era=1, el=1.5, goods={"paper": 1.0}, qty={P: 0.003, AR: 0.03, M: 0.12, GE: 0.4}),
    dict(id="books", name="书籍", weight=2, era=1, el=1.5, goods={"books": 1.0}, qty={P: 0.0005, AR: 0.002, M: 0.015, GE: 0.06}),
    dict(id="silk", name="绸缎", weight=2, era=1, el=1.5, goods={"silk": 1.0}, qty={P: 0.0, AR: 0.004, M: 0.06, GE: 0.1}),
    dict(id="porcelain_lux", name="瓷器", weight=1, era=1, el=1.5, goods={"porcelain": 1.0}, qty={P: 0.0, AR: 0.004, M: 0.04, GE: 0.06}),
    # 第二时代起
    dict(id="sugar", name="糖", weight=2, era=2, el=1.0, goods={"sugar": 1.0}, qty={P: 0.002, AR: 0.008, M: 0.03, GE: 0.04}),
    dict(id="soap", name="皂", weight=2, era=2, el=1.0, goods={"soap": 1.0}, qty={P: 0.002, AR: 0.006, M: 0.02, GE: 0.025}),
    dict(id="spice", name="香料", weight=1, era=2, el=1.5, goods={"spices": 1.0}, qty={P: 0.0, AR: 0.0005, M: 0.004, GE: 0.006}),
    # 第四时代
    dict(id="power_home", name="用电", weight=4, era=4, el=1.0, goods={"electricity": 1.0},
         qty={P: 0.02, AR: 0.04, M: 0.08, GE: 0.1}),
    dict(id="appliance", name="家电", weight=3, era=4, el=1.5,
         goods={"appliances": 1.0, "radio": 1.2, "television": 0.6},
         qty={P: 0.004, AR: 0.008, M: 0.02, GE: 0.025},
         taste={r: {"appliances": 0.5, "radio": 0.25, "television": 0.25}
                for r in ("beiyuan", "zhongzhou", "haijia", "xiling")}),
    dict(id="car", name="出行", weight=3, era=4, el=1.5, goods={"automobile": 1.0}, qty={P: 0.0003, AR: 0.001, M: 0.004, GE: 0.005}),
    # 第三时代起：上茶楼、看戏、下馆子……日子宽裕了花得越来越多（弹性 1.5），是城里活计的一大来源
    dict(id="leisure", name="游乐与服务", weight=3, era=3, el=1.5, goods={"services": 1.0},
         qty={P: 0.02, AR: 0.06, M: 0.15, GE: 0.2}),
]

# ── 地区 ──────────────────────────────────────────────────────────────────
# pop：开局人口；land：各地类的「规模上限倍数」只作为参考，真正的上限由 calibrate.py
# 按开局用地 × slack 算出；deposit：矿藏上限（级）；river / coast：是否有大河、海岸；
# logistics：没有驿路时的物流成本（卖到全国市场时被扣掉的比例）；驿路、运河、铁路按级往下减。
REGIONS = [
    dict(id="beiyuan", name="北原", pop=9_170_000, river=True, coast=False, logistics=0.085,
         desc="北方平原，旱地与草场广阔，人口最多，冬季寒冷。",
         slack={"dry": 1.22, "paddy": 1.3, "slope": 1.6, "forest": 1.8, "pasture": 1.5, "coast": 1.0},
         deposit={"coal": 30, "stone": 12, "iron": 4, "oil": 10, "phosphate": 6, "sand": 10}),
    dict(id="zhongzhou", name="中州", pop=6_895_000, river=True, coast=False, logistics=0.05, capital=True,
         desc="大河中游的富庶之地，水田与桑园相连，首府与商贸中心。",
         slack={"dry": 1.25, "paddy": 1.2, "slope": 1.5, "forest": 1.6, "pasture": 1.4, "coast": 1.0},
         deposit={"kaolin": 16, "stone": 8, "coal": 4, "sand": 8, "hydro": 6}),
    dict(id="haijia", name="海岬", pop=5_028_000, river=False, coast=True, logistics=0.06,
         desc="东南沿海，产盐与鱼，良港众多，对外贸易的门户，常遭台风。",
         slack={"dry": 1.3, "paddy": 1.2, "slope": 1.5, "forest": 1.6, "pasture": 1.4, "coast": 2.0},
         deposit={"salt": 30, "stone": 6, "sand": 10, "coast": 40}),
    dict(id="xiling", name="西岭", pop=2_999_000, river=True, coast=False, logistics=0.11,
         desc="西部山地，茶园、林木与铁铜矿藏丰富，人少路险，河流湍急宜建水力。",
         slack={"dry": 1.3, "paddy": 1.25, "slope": 1.8, "forest": 2.2, "pasture": 1.6, "coast": 1.0},
         deposit={"iron": 30, "copper": 18, "sulfur": 8, "stone": 10, "coal": 12, "bauxite": 10, "hydro": 20,
                  "phosphate": 4}),
]

# 开局各商品的产地分布（全国产量在地区之间的份额）。没写的商品按人口分布。
SPREAD = {
    "rice": {"zhongzhou": 0.44, "haijia": 0.36, "xiling": 0.12, "beiyuan": 0.08},
    "grain": {"beiyuan": 0.66, "zhongzhou": 0.14, "xiling": 0.15, "haijia": 0.05},
    "beans": {"beiyuan": 0.45, "zhongzhou": 0.25, "haijia": 0.15, "xiling": 0.15},
    "cotton": {"zhongzhou": 0.45, "beiyuan": 0.35, "haijia": 0.2},
    "hemp": {"beiyuan": 0.4, "xiling": 0.3, "zhongzhou": 0.3},
    "oilseed": {"zhongzhou": 0.4, "beiyuan": 0.3, "haijia": 0.15, "xiling": 0.15},
    "cocoon": {"zhongzhou": 0.7, "haijia": 0.2, "xiling": 0.1},
    "tea": {"xiling": 0.5, "zhongzhou": 0.3, "haijia": 0.2},
    "fruit": {"haijia": 0.4, "zhongzhou": 0.3, "xiling": 0.3},
    "fish": {"haijia": 1.0},
    "draft_animal": {"beiyuan": 0.62, "xiling": 0.25, "zhongzhou": 0.1, "haijia": 0.03},
    "timber": {"xiling": 0.34, "beiyuan": 0.26, "zhongzhou": 0.2, "haijia": 0.2},
    "iron_ore": {"xiling": 0.8, "beiyuan": 0.2},
    "copper_ore": {"xiling": 1.0},
    "kaolin": {"zhongzhou": 1.0},
    "cut_stone": {"beiyuan": 0.4, "xiling": 0.3, "zhongzhou": 0.3},
    "coal": {"beiyuan": 0.9, "xiling": 0.1},
    "salt": {"haijia": 1.0},
    # 加工业
    "yarn": {"zhongzhou": 0.4, "beiyuan": 0.3, "haijia": 0.2, "xiling": 0.1},
    "fabric": {"zhongzhou": 0.4, "beiyuan": 0.25, "haijia": 0.25, "xiling": 0.1},
    "silk_thread": {"zhongzhou": 0.75, "haijia": 0.25},
    "silk": {"zhongzhou": 0.7, "haijia": 0.3},
    "charcoal": {"xiling": 0.28, "beiyuan": 0.27, "zhongzhou": 0.25, "haijia": 0.2},
    "lumber": {"xiling": 0.4, "zhongzhou": 0.25, "haijia": 0.2, "beiyuan": 0.15},
    "pig_iron": {"xiling": 0.65, "beiyuan": 0.35},
    "copper": {"xiling": 1.0},
    "porcelain": {"zhongzhou": 0.9, "haijia": 0.1},
    "cooking_oil": {"zhongzhou": 0.4, "beiyuan": 0.3, "haijia": 0.15, "xiling": 0.15},
    "leather": {"beiyuan": 0.6, "xiling": 0.2, "zhongzhou": 0.2},
    "paper": {"xiling": 0.4, "zhongzhou": 0.4, "haijia": 0.2},
    "books": {"zhongzhou": 0.6, "haijia": 0.2, "beiyuan": 0.2},
    "rope": {"haijia": 0.7, "zhongzhou": 0.3},
    "sailcloth": {"haijia": 0.7, "zhongzhou": 0.3},
    "ships": {"haijia": 0.85, "zhongzhou": 0.15},
    "wine": {"beiyuan": 0.4, "zhongzhou": 0.3, "haijia": 0.15, "xiling": 0.15},
    "meat": {"beiyuan": 0.62, "xiling": 0.25, "zhongzhou": 0.1, "haijia": 0.03},
    "wool": {"beiyuan": 0.62, "xiling": 0.25, "zhongzhou": 0.1, "haijia": 0.03},
    "hides": {"beiyuan": 0.62, "xiling": 0.25, "zhongzhou": 0.1, "haijia": 0.03},
}

# 地区偏好的建筑（地图标记与开局分布用）；由 calibrate.py 自动得出，这里只给地图图标的优先顺序。
LANDMARK_HINT = {}

# ── 国家开局设定（第一时代财政，docs/57 §6） ──────────────────────────────
GOV = dict(
    treasury=5_000_000.0,           # 两
    land_tax=0.09,                  # 田赋科则：农产值的比例
    salt_tax=0.60,                  # 盐课：每担征银（两）
    commerce_tax=0.02,              # 商税：非农产品销售额的比例
    customs=0.05,                   # 关税：进出口额的比例
    hidden_land=0.12,               # 开局隐田比例
    hidden_growth=0.0024,           # 隐田每年增长（占在册田亩）
    soldiers_per_capita=0.016,     # 兵额占人口
    soldier_wage=1.8,               # 兵饷（两 / 人 / 季，按农户阶层领取）
    soldier_ration=0.6,             # 军粮（石 / 人 / 季）
    soldier_cloth=0.2,              # 军衣（匹 / 人 / 季）
    soldier_leather=0.02,           # 军用皮革（张 / 人 / 季：靴、甲、鞍具）
    court=500_000.0,                # 宫廷与杂项（两 / 季）
    relief_budget=150_000.0,        # 赈济拨款基数（两 / 季）
    commerce_margin=0.08,           # 零售加价（归商贾经营的集市）
    # 各时代人们心里「过得去」的日用水平（相对开局篮子）：世界在变，期待也在涨
    comfort_expect=[1.0, 1.2, 1.5, 2.0],
)
