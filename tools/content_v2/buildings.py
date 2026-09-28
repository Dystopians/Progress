# -*- coding: utf-8 -*-
"""建筑与生产方式表（docs/57 §4、§5、§10）。

一级（level）的规模：
  农田类：10 万亩；牧场、林场、渔场：一片场地；矿、作坊：一处作坊群。
配方数量都是「每级每季」，单位同商品表。labor 是各阶层用工人数（每级）。

category：
  farm       占土地的农林牧渔（land 指定地类）
  mine       占矿藏（deposit 指定矿种）；盐场、渔场占海岸
  workshop   加工作坊与工厂
  infra      基础设施：提供能力（商贸、物流、港口、水利、水力、仓储、关津、丈量）
  public     公共设施：提供服务（学舍、书院、医馆、衙署、戏台、城政），不会过时，只会换代
  landmark   地标（见 progress.py）

effects（infra / public）：能力名 → 每级数值，由模拟核心解释（docs/57 §5、§6）。
capital：造价 = capital × 每级每季工钱 × 4（即 capital 年的工钱）；maint 缺省为造价的 1.5% / 季。
"""

B = []

ART = "assets/buildings/"


def art3(folder, family, early=None, industrial=None, modern=None):
    """按三档配图生成 {时代: 路径}：第一、二时代用早期，第三时代用工业期，第四时代用现代期。"""
    e = early or f"{ART}{folder}/{family}_early.png"
    i = industrial or f"{ART}{folder}/{family}_industrial.png"
    m = modern or f"{ART}{folder}/{family}_modern.png"
    return {"1": e, "2": e, "3": i, "4": m}


def method(id, name, era=1, tech=None, out=None, inp=None, labor=None, power=0, water=False,
           upgrade_cost=0.35, upgrade_q=2, era_end=4, note=""):
    return dict(id=id, name=name, era=era, era_end=era_end, tech=tech, out=out or {}, inp=inp or {},
                labor=labor or {}, power=power, water=water, upgrade_cost=upgrade_cost,
                upgrade_q=upgrade_q, note=note)


def building(id, name, category, sector, methods, art, owners=("private", "gov"), land=None,
             deposit=None, coast=False, capital=1.2, build_q=4, era=1, era_end=4, tech=None,
             effects=None, maint=None, note="", family=None):
    B.append(dict(id=id, name=name, category=category, sector=sector, methods=methods, art=art,
                  owners=list(owners), land=land, deposit=deposit, coast=coast, capital=capital,
                  build_q=build_q, era=era, era_end=era_end, tech=tech, effects=effects or {},
                  maint=maint, note=note, family=family or id))


P, AR, M, GE = "peasant", "artisan", "merchant", "gentry"

# ════════════════════════════ 农林牧渔 ════════════════════════════════════
FARM_ART = art3("b02", "farm")

# 旱田：作物即生产方式；换种作物是廉价、一季完成的「改种」。
# 同一作物有三档技术：传统（第一时代）、施肥（第三时代，化肥）、机械化（第四时代，机械与燃料）。
DRY_CROPS = [
    ("grain", "麦粟", 48000, "旱地麦粟"),
    ("beans", "豆类", 41000, "旱地豆类"),
    ("cotton", "棉花", 9000, "棉田"),
    ("hemp", "麻", 14000, "麻田"),
    ("oilseed", "油籽", 20000, "油籽田"),
    ("vegetables", "蔬菜", 160000, "菜园"),
]


def crop_methods(prefix, crops, base_labor, tools, draft, extra_era2=None):
    ms = []
    for gid, gname, qty, label in crops:
        ms.append(method(f"{prefix}_{gid}", label, out={gid: qty},
                         inp={"tools": tools, "draft_animal": draft}, labor={P: base_labor},
                         upgrade_cost=0.05, upgrade_q=1))
        ms.append(method(f"{prefix}_{gid}_rot", label + "（轮作）", era=1, tech="crop_rotation",
                         out={gid: int(qty * 1.2)}, inp={"tools": tools, "draft_animal": draft},
                         labor={P: base_labor}, upgrade_cost=0.08, upgrade_q=1))
        ms.append(method(f"{prefix}_{gid}_fert", label + "（施肥）", era=3, tech="fertilizer",
                         out={gid: int(qty * 1.75)},
                         inp={"tools": tools, "draft_animal": draft // 2, "fertilizer": qty // 400 + 20},
                         labor={P: int(base_labor * 0.8)}, upgrade_cost=0.15, upgrade_q=1))
        ms.append(method(f"{prefix}_{gid}_mech", label + "（机械化）", era=4, tech="mechanized_farming",
                         out={gid: int(qty * 2.4)},
                         inp={"machinery": 30, "refined_fuel": 400, "fertilizer": qty // 300 + 30},
                         labor={P: int(base_labor * 0.3)}, upgrade_cost=0.4, upgrade_q=2))
    return ms


building("dryfarm", "旱田", "farm", "agri", land="dry", art=FARM_ART, capital=0.8,
         methods=crop_methods("dry", DRY_CROPS, 20000, 150, 55),
         note="一级 = 10 万亩旱地。作物即生产方式，改种一季完成。")

PADDY_CROPS = [("rice", "稻米", 50000, "水田稻作")]
paddy_methods = crop_methods("paddy", PADDY_CROPS, 20000, 150, 50)
paddy_methods.insert(2, method("paddy_rice_double", "水田稻作（双季稻）", era=2, tech="double_cropping",
                               out={"rice": 78000}, inp={"tools": 200, "draft_animal": 60},
                               labor={P: 24000}, upgrade_cost=0.12, upgrade_q=1))
paddy_methods.append(method("paddy_sugarcane", "甘蔗田", era=2, tech="sugar_refining",
                            out={"sugarcane": 70000}, inp={"tools": 150, "draft_animal": 40},
                            labor={P: 22000}, upgrade_cost=0.05, upgrade_q=1))
building("paddy", "水田", "farm", "agri", land="paddy", art=FARM_ART, capital=0.9,
         methods=paddy_methods, note="一级 = 10 万亩水田。")

building("mulberry", "桑园", "farm", "agri", land="slope", capital=1.0,
         art=art3("b11", "sericulture"),
         methods=[method("mulberry_trad", "桑园养蚕", out={"cocoon": 5000}, inp={"tools": 80},
                         labor={P: 22000}),
                  method("mulberry_improved", "良种桑蚕", era=3, tech="sericulture_science",
                         out={"cocoon": 8500}, inp={"tools": 80, "fertilizer": 30},
                         labor={P: 20000})])

building("teagarden", "茶园", "farm", "agri", land="slope", capital=1.0, art=art3("b11", "tea"),
         methods=[method("tea_trad", "梯田焙茶", out={"tea": 2600}, inp={"tools": 60}, labor={P: 22000}),
                  method("tea_mech", "机械揉茶", era=3, tech="steam_engine", out={"tea": 4200},
                         inp={"tools": 60, "power": 40}, labor={P: 15000})])

building("orchard", "果园", "farm", "agri", land="slope", capital=1.0, art=art3("b05", "orchard"),
         methods=[method("orchard_trad", "果园", out={"fruit": 60000}, inp={"tools": 60}, labor={P: 16000}),
                  method("orchard_modern", "温室园艺", era=4, tech="mechanized_farming",
                         out={"fruit": 120000}, inp={"tools": 60, "fertilizer": 200, "electricity": 50},
                         labor={P: 9000})])

building("ranch", "牧场", "farm", "agri", land="pasture", capital=1.0, art=art3("b05", "ranch"),
         methods=[method("ranch_trad", "放牧", out={"draft_animal": 1600, "meat": 3500, "hides": 2600,
                                                     "wool": 1500},
                         labor={P: 9000}),
                  method("ranch_feed", "舍饲", era=3, tech="fertilizer",
                         out={"draft_animal": 1600, "meat": 7000, "hides": 4200, "wool": 2600},
                         inp={"grain": 6000}, labor={P: 8000}),
                  method("ranch_modern", "现代畜牧", era=4, tech="mechanized_farming",
                         out={"meat": 14000, "hides": 6000, "wool": 3500},
                         inp={"grain": 10000, "electricity": 30, "machinery": 5}, labor={P: 5000})])

building("fishery", "渔场", "farm", "agri", land="coast", capital=1.0, art=art3("b05", "fishing",
                                                                            modern=ART + "b05/fishing_modern_v2.png"),
         methods=[method("fish_trad", "沿岸捕捞", out={"fish": 32000}, inp={"ships": 1, "rope": 300},
                         labor={P: 10000}),
                  method("fish_motor", "机帆渔船", era=3, tech="steam_engine", out={"fish": 60000},
                         inp={"ships": 2, "coal": 3000}, labor={P: 8000}),
                  method("fish_cold", "冷链渔业", era=4, tech="power_grid", out={"fish": 100000},
                         inp={"ships": 2, "refined_fuel": 800, "electricity": 60}, labor={P: 6000})])

building("forestry", "伐木场", "farm", "agri", land="forest", capital=0.9, art=art3("b05", "forestry"),
         methods=[method("forestry_trad", "伐木", out={"timber": 42000}, inp={"tools": 100},
                         labor={P: 8000}),
                  method("forestry_mech", "机械伐木", era=3, tech="steam_engine", out={"timber": 70000},
                         inp={"tools": 100, "coal": 2000}, labor={P: 6000}),
                  method("forestry_modern", "林木综合经营", era=4, tech="mechanized_farming",
                         out={"timber": 90000}, inp={"refined_fuel": 500, "machinery": 5},
                         labor={P: 4000})])

# ════════════════════════════ 矿与盐 ══════════════════════════════════════
MINE_ART = art3("b02", "mine")

building("ironmine", "铁矿", "mine", "manu", deposit="iron", capital=1.4, art=MINE_ART,
         methods=[method("ironmine_trad", "露天采矿", out={"iron_ore": 40000}, inp={"tools": 220},
                         labor={AR: 4000, P: 2000}),
                  method("ironmine_steam", "竖井采矿", era=3, tech="steam_engine", out={"iron_ore": 80000},
                         inp={"tools": 200, "power": 60, "coal": 2000}, labor={AR: 5000}),
                  method("ironmine_mech", "机械采矿", era=4, tech="power_grid", out={"iron_ore": 150000},
                         inp={"machinery": 20, "electricity": 150}, labor={AR: 3000})])

building("coppermine", "铜矿", "mine", "manu", deposit="copper", capital=1.4, art=MINE_ART,
         methods=[method("coppermine_trad", "采铜", out={"copper_ore": 22000}, inp={"tools": 220},
                         labor={AR: 4000, P: 2000}),
                  method("coppermine_steam", "竖井采铜", era=3, tech="steam_engine",
                         out={"copper_ore": 45000}, inp={"tools": 200, "power": 60, "coal": 2000},
                         labor={AR: 5000}),
                  method("coppermine_mech", "机械采铜", era=4, tech="power_grid",
                         out={"copper_ore": 90000}, inp={"machinery": 20, "electricity": 150},
                         labor={AR: 3000})])

building("kaolinpit", "瓷土采场", "mine", "manu", deposit="kaolin", capital=1.2, art=MINE_ART,
         methods=[method("kaolin_trad", "采瓷土", out={"kaolin": 30000}, inp={"tools": 100},
                         labor={AR: 2000, P: 2000}),
                  method("kaolin_mech", "机械采掘", era=4, tech="power_grid", out={"kaolin": 70000},
                         inp={"machinery": 10, "electricity": 80}, labor={AR: 1500})])

building("quarry", "采石场", "mine", "manu", deposit="stone", capital=1.2,
         art=art3("b14", "stonequarry", modern=ART + "b14/stonequarry_modern_v2.png"),
         methods=[method("quarry_trad", "采石", out={"cut_stone": 20000}, inp={"tools": 150},
                         labor={AR: 2000, P: 3000}),
                  method("quarry_lime", "采石与石灰岩", era=3, tech="cement",
                         out={"cut_stone": 20000, "limestone": 30000}, inp={"tools": 150, "power": 30},
                         labor={AR: 3000, P: 2000}),
                  method("quarry_mech", "机械采石", era=4, tech="power_grid",
                         out={"cut_stone": 40000, "limestone": 60000},
                         inp={"machinery": 10, "electricity": 80}, labor={AR: 2500})])

building("coalmine", "煤矿", "mine", "energy", deposit="coal", capital=1.4, art=art3("b09", "coal"),
         methods=[method("coal_trad", "平硐采煤", out={"coal": 50000}, inp={"tools": 200},
                         labor={AR: 3000, P: 2500}),
                  method("coal_steam", "竖井煤矿", era=3, tech="steam_engine", out={"coal": 140000},
                         inp={"tools": 200, "power": 80}, labor={AR: 6000}),
                  method("coal_mech", "机械化煤矿", era=4, tech="power_grid", out={"coal": 300000},
                         inp={"machinery": 30, "electricity": 200}, labor={AR: 4000})])

building("saltworks", "盐场", "mine", "manu", deposit="salt", capital=1.2,
         art=art3("b11", "saltworks", industrial=ART + "b11/saltworks_industrial_v3.png"),
         methods=[method("salt_trad", "海边晒盐", out={"salt": 60000}, labor={P: 6000, AR: 1000}),
                  method("salt_mech", "机械化盐场", era=3, tech="steam_engine", out={"salt": 120000},
                         inp={"power": 30}, labor={P: 3000, AR: 1500}),
                  method("salt_modern", "现代制盐", era=4, tech="power_grid", out={"salt": 220000},
                         inp={"electricity": 80}, labor={AR: 2000})])

building("sulfurmine", "硫磺矿", "mine", "manu", deposit="sulfur", capital=1.4, era=3, tech="chemistry",
         art=MINE_ART,
         methods=[method("sulfur_mine", "采硫", era=3, out={"sulfur": 20000}, inp={"tools": 150, "power": 30},
                         labor={AR: 3000})])

building("phosphatemine", "磷矿", "mine", "manu", deposit="phosphate", capital=1.4, era=3,
         tech="fertilizer", art=MINE_ART,
         methods=[method("phosphate_mine", "采磷", era=3, out={"phosphate": 20000},
                         inp={"tools": 150, "power": 40}, labor={AR: 3000}),
                  method("phosphate_mech", "机械采磷", era=4, tech="power_grid", out={"phosphate": 45000},
                         inp={"machinery": 10, "electricity": 100}, labor={AR: 2000})])

building("sandpit", "砂场", "mine", "manu", deposit="sand", capital=1.0, era=2, tech="glassmaking",
         art=MINE_ART,
         methods=[method("sand_trad", "采砂", era=2, out={"sand": 30000}, inp={"tools": 60},
                         labor={P: 3000})])

building("oilwell", "油井", "mine", "energy", deposit="oil", capital=2.0, era=4, tech="petrochemistry",
         art=art3("b09", "oil", early=ART + "b09/oil_early_v2.png"),
         methods=[method("oil_well", "井架采油", era=4, out={"crude_oil": 60000},
                         inp={"machinery": 20, "electricity": 100}, labor={AR: 3000})])

building("bauxitemine", "铝土矿", "mine", "manu", deposit="bauxite", capital=1.6, era=4, tech="electrochemistry",
         art=MINE_ART,
         methods=[method("bauxite_mine", "采铝土", era=4, out={"bauxite": 30000},
                         inp={"machinery": 10, "electricity": 80}, labor={AR: 2500})])

# ════════════════════════════ 作坊与工厂 ══════════════════════════════════
TEX_ART = art3("b06", "textile")

building("spinning", "纺纱坊", "workshop", "manu", capital=1.0, art=TEX_ART,
         methods=[method("spin_hand", "手摇纺车", out={"yarn": 7200}, inp={"cotton": 8000},
                         labor={AR: 4500, M: 100}),
                  method("spin_water", "水力纺纱", era=2, tech="water_frame", water=True,
                         out={"yarn": 7200}, inp={"cotton": 8000, "tools": 30}, labor={AR: 1800, M: 100}),
                  method("spin_steam", "蒸汽纺纱厂", era=3, tech="steam_engine",
                         out={"yarn": 16000}, inp={"cotton": 17800, "power": 80, "machinery": 4},
                         labor={AR: 2200, M: 150}),
                  method("spin_modern", "电动纺纱", era=4, tech="power_grid",
                         out={"yarn": 30000}, inp={"cotton": 33400, "electricity": 150, "machinery": 6},
                         labor={AR: 1500, M: 150})])

building("weaving", "织布坊", "workshop", "manu", capital=1.0, art=TEX_ART,
         methods=[method("weave_hand", "手织", out={"fabric": 140000}, inp={"yarn": 7000},
                         labor={AR: 4000, M: 100}),
                  method("weave_shuttle", "飞梭织机", era=2, tech="flying_shuttle",
                         out={"fabric": 140000}, inp={"yarn": 7000, "tools": 20}, labor={AR: 2400, M: 100}),
                  method("weave_power", "动力织机", era=3, tech="steam_engine",
                         out={"fabric": 320000}, inp={"yarn": 16000, "power": 80, "machinery": 4},
                         labor={AR: 2600, M: 150}),
                  method("weave_modern", "现代织造", era=4, tech="power_grid",
                         out={"fabric": 600000}, inp={"yarn": 30000, "electricity": 150, "machinery": 6},
                         labor={AR: 1800, M: 150})])

building("silkreel", "缫丝坊", "workshop", "manu", capital=1.1, art=art3("b11", "sericulture"),
         methods=[method("reel_hand", "手工缫丝", out={"silk_thread": 1100}, inp={"cocoon": 4600},
                         labor={AR: 3000, M: 80}),
                  method("reel_machine", "机器缫丝", era=3, tech="steam_engine", out={"silk_thread": 2600},
                         inp={"cocoon": 10500, "power": 40, "machinery": 2}, labor={AR: 2500, M: 100}),
                  method("reel_modern", "现代丝厂", era=4, tech="power_grid", out={"silk_thread": 5000},
                         inp={"cocoon": 20000, "electricity": 80, "machinery": 3}, labor={AR: 2000, M: 100})])

building("silkweave", "织绸坊", "workshop", "manu", capital=1.2, art=TEX_ART,
         methods=[method("silkweave_hand", "花楼织机", out={"silk": 22000}, inp={"silk_thread": 1100},
                         labor={AR: 4000, M: 120}),
                  method("silkweave_jacquard", "提花织机", era=3, tech="steam_engine", out={"silk": 52000},
                         inp={"silk_thread": 2600, "power": 40, "machinery": 2}, labor={AR: 3000, M: 150}),
                  method("silkweave_modern", "电动织绸", era=4, tech="power_grid", out={"silk": 100000},
                         inp={"silk_thread": 5000, "electricity": 80, "machinery": 3}, labor={AR: 2000, M: 150})])

building("ropesail", "绳帆坊", "workshop", "manu", capital=1.0, art=art3("b14", "ropesail"),
         methods=[method("ropesail_hand", "手工绳帆", out={"rope": 30000, "sailcloth": 8000},
                         inp={"hemp": 12000}, labor={AR: 3000, M: 80}),
                  method("ropesail_mech", "机械制绳", era=3, tech="steam_engine",
                         out={"rope": 70000, "sailcloth": 18000}, inp={"hemp": 27000, "power": 40},
                         labor={AR: 2500, M: 100})])

building("charcoalkiln", "炭窑", "workshop", "energy", capital=0.8, era_end=3,
         art={"1": ART + "b11/charcoalkiln_early.png", "2": ART + "b11/charcoalkiln_early.png",
              "3": ART + "b11/charcoalkiln_early.png", "4": ART + "b11/charcoalkiln_early.png"},
         methods=[method("charcoal_kiln", "覆土炭窑", out={"charcoal": 30000}, inp={"timber": 20000},
                         labor={P: 2500, AR: 800})],
         note="第三时代起被焦炭取代，逐步淡出。")

building("sawmill", "锯木坊", "workshop", "manu", capital=1.0,
         art={"1": ART + "b05/forestry_industrial.png", "2": ART + "b05/forestry_industrial.png",
              "3": ART + "b05/forestry_industrial.png", "4": ART + "b05/forestry_modern.png"},
         methods=[method("saw_hand", "手工锯木", out={"lumber": 10000}, inp={"timber": 15000},
                         labor={AR: 2000, M: 50}),
                  method("saw_water", "水力锯木", era=2, tech="water_power", water=True,
                         out={"lumber": 10000}, inp={"timber": 15000}, labor={AR: 1000, M: 50}),
                  method("saw_steam", "蒸汽锯木", era=3, tech="steam_engine", out={"lumber": 26000},
                         inp={"timber": 38000, "power": 50}, labor={AR: 1500, M: 80})])

building("ironworks", "冶铁作坊", "workshop", "manu", capital=1.4,
         art={"1": ART + "b07/steel_early_v2.png", "2": ART + "b07/steel_early_v2.png",
              "3": ART + "b07/steel_industrial_v2.png", "4": ART + "b07/steel_modern.png"},
         methods=[method("iron_charcoal", "木炭冶铁", out={"pig_iron": 12000},
                         inp={"iron_ore": 30000, "charcoal": 30000}, labor={AR: 3000, M: 80}),
                  method("iron_coal", "煤炭冶铁", era=2, tech="coal_iron", out={"pig_iron": 14000},
                         inp={"iron_ore": 34000, "coal": 36000}, labor={AR: 2800, M: 80}),
                  method("iron_blast", "焦炭高炉", era=3, tech="coke_smelting", out={"pig_iron": 40000},
                         inp={"iron_ore": 95000, "coke": 45000, "power": 60}, labor={AR: 3500, M: 120}),
                  method("iron_modern", "现代高炉", era=4, tech="power_grid", out={"pig_iron": 90000},
                         inp={"iron_ore": 210000, "coke": 90000, "electricity": 200}, labor={AR: 2500, M: 150})])

building("steelworks", "钢铁厂", "workshop", "manu", capital=2.2, era=3, tech="bessemer",
         art={"1": ART + "b07/steel_industrial_v2.png", "2": ART + "b07/steel_industrial_v2.png",
              "3": ART + "b07/steel_industrial_v2.png", "4": ART + "b07/steel_modern.png"},
         methods=[method("steel_bessemer", "转炉炼钢", era=3, out={"steel": 8000},
                         inp={"pig_iron": 18000, "coke": 6000, "power": 80}, labor={AR: 3000, M: 150}),
                  method("steel_electric", "电炉炼钢", era=4, tech="power_grid", out={"steel": 20000},
                         inp={"pig_iron": 40000, "electricity": 600}, labor={AR: 2500, M: 150})])

building("smithy", "铁匠铺", "workshop", "manu", capital=1.0, art=art3("b07", "tools"),
         methods=[method("smith_hand", "打铁", out={"tools": 30000}, inp={"pig_iron": 6000, "charcoal": 6000},
                         labor={AR: 3000, M: 60}),
                  method("smith_coal", "煤火打铁", era=2, tech="coal_iron", out={"tools": 32000},
                         inp={"pig_iron": 6400, "coal": 7000}, labor={AR: 2800, M: 60}),
                  method("smith_machine", "机加工工具", era=3, tech="machine_tools", out={"tools": 90000},
                         inp={"steel": 3000, "power": 40, "machinery": 3}, labor={AR: 2500, M: 100}),
                  method("smith_precision", "精密工具", era=4, tech="automation", out={"tools": 200000},
                         inp={"steel": 6000, "electricity": 150, "machinery": 5}, labor={AR: 1800, M: 100})])

building("copperworks", "炼铜作坊", "workshop", "manu", capital=1.3, art=art3("b14", "copperworks"),
         methods=[method("copper_charcoal", "木炭炼铜", out={"copper": 3000},
                         inp={"copper_ore": 20000, "charcoal": 15000}, labor={AR: 3000, M: 60}),
                  method("copper_coke", "焦炭炼铜", era=3, tech="coke_smelting", out={"copper": 8000},
                         inp={"copper_ore": 52000, "coke": 12000, "power": 40}, labor={AR: 3000, M: 100}),
                  method("copper_electro", "电解精炼", era=4, tech="electrochemistry", out={"copper": 18000},
                         inp={"copper_ore": 110000, "electricity": 400}, labor={AR: 2500, M: 100})])

building("porcelainkiln", "瓷窑", "workshop", "manu", capital=1.3,
         art=art3("b11", "porcelainkiln"),
         methods=[method("kiln_dragon", "龙窑烧瓷", out={"porcelain": 150000},
                         inp={"kaolin": 12000, "charcoal": 12000}, labor={AR: 3200, M: 100}),
                  method("kiln_coal", "煤烧瓷厂", era=3, tech="coke_smelting", out={"porcelain": 320000},
                         inp={"kaolin": 25000, "coal": 20000, "power": 30}, labor={AR: 3000, M: 150}),
                  method("kiln_modern", "现代陶瓷厂", era=4, tech="power_grid", out={"porcelain": 700000},
                         inp={"kaolin": 55000, "electricity": 200}, labor={AR: 2200, M: 150})])

building("pottery", "陶器作坊", "workshop", "manu", capital=0.9, art=art3("b14", "pottery"),
         methods=[method("pottery_hand", "手工制陶", out={"earthenware": 300000}, inp={"charcoal": 4000},
                         labor={AR: 2500, M: 50}),
                  method("pottery_coal", "煤窑制陶", era=2, tech="coal_iron", out={"earthenware": 320000},
                         inp={"coal": 5000}, labor={AR: 2300, M: 50}),
                  method("pottery_mech", "机械陶器", era=3, tech="steam_engine", out={"earthenware": 700000},
                         inp={"coal": 9000, "power": 30}, labor={AR: 2000, M: 80})])

building("brickkiln", "砖瓦窑", "workshop", "manu", capital=0.9, art=art3("b07", "brick"),
         methods=[method("brick_hand", "土窑烧砖", out={"bricks": 5000}, inp={"charcoal": 5000},
                         labor={AR: 2000, P: 1000}),
                  method("brick_coal", "煤窑烧砖", era=2, tech="coal_iron", out={"bricks": 5500},
                         inp={"coal": 6000}, labor={AR: 2000, P: 800}),
                  method("brick_ring", "轮窑砖厂", era=3, tech="steam_engine", out={"bricks": 14000},
                         inp={"coal": 12000, "power": 30}, labor={AR: 2200})])

building("oilpress", "榨油坊", "workshop", "manu", capital=0.9, art=art3("b15", "oilpress",
                                                                       modern=ART + "b15/oilpress_modern_v3.png"),
         methods=[method("oilpress_wood", "木榨", out={"cooking_oil": 2600}, inp={"oilseed": 10000},
                         labor={AR: 1500, M: 50}),
                  method("oilpress_mech", "机械榨油", era=3, tech="steam_engine", out={"cooking_oil": 6400},
                         inp={"oilseed": 23000, "power": 30}, labor={AR: 1400, M: 80})])

building("chandlery", "皂烛坊", "workshop", "manu", capital=0.9,
         art=art3("b13", "soapworks"),
         methods=[method("candle_hand", "手工蜡烛", out={"candles": 60000}, inp={"cooking_oil": 800},
                         labor={AR: 1000, M: 40}),
                  method("candle_soap", "皂烛兼营", era=2, tech="chemistry_basic",
                         out={"candles": 60000, "soap": 3000}, inp={"cooking_oil": 1400},
                         labor={AR: 1300, M: 50}),
                  method("soap_factory", "机械制皂", era=3, tech="chemistry",
                         out={"soap": 12000, "candles": 30000}, inp={"cooking_oil": 2600, "chemicals": 300, "power": 20},
                         labor={AR: 1200, M: 80})])

building("brewery", "酿坊", "workshop", "manu", capital=0.9, art=art3("b13", "brewery"),
         methods=[method("brew_trad", "酿酒", out={"wine": 60000}, inp={"grain": 8000},
                         labor={AR: 1500, M: 60}),
                  method("brew_beer", "蒸汽酿造（啤酒）", era=3, tech="steam_engine",
                         out={"beer": 30000, "wine": 30000}, inp={"grain": 14000, "power": 20},
                         labor={AR: 1500, M: 80})])

building("papermill", "纸坊", "workshop", "manu", capital=1.0, art=art3("b06", "paper"),
         methods=[method("paper_hand", "手工造纸", out={"paper": 100000}, inp={"timber": 6000},
                         labor={AR: 2500, M: 50}),
                  method("paper_machine", "机械造纸", era=3, tech="steam_engine", out={"paper": 260000},
                         inp={"timber": 14000, "chemicals": 200, "power": 40}, labor={AR: 2200, M: 80})])

building("printing", "印坊", "workshop", "manu", capital=1.0, art=art3("b06", "printing"),
         methods=[method("print_block", "雕版印刷", out={"books": 12000}, inp={"paper": 40000},
                         labor={AR: 1500, GE: 80, M: 40}),
                  method("print_movable", "活字印刷", era=1, tech="movable_type", out={"books": 20000},
                         inp={"paper": 60000}, labor={AR: 1500, GE: 80, M: 40}),
                  method("print_rotary", "轮转印刷", era=3, tech="steam_engine", out={"books": 60000},
                         inp={"paper": 170000, "power": 30}, labor={AR: 1500, GE: 100, M: 60})])

building("furnitureshop", "家具坊", "workshop", "manu", capital=0.9, art=art3("b14", "furniture"),
         methods=[method("furniture_hand", "木作家具", out={"furniture": 20000}, inp={"lumber": 4000},
                         labor={AR: 2500, M: 60}),
                  method("furniture_mech", "机械家具", era=3, tech="machine_tools", out={"furniture": 50000},
                         inp={"lumber": 9000, "power": 20}, labor={AR: 2200, M: 80})])

building("tannery", "制革坊", "workshop", "manu", capital=0.9, art=art3("b06", "leather"),
         methods=[method("tan_hand", "手工制革", out={"leather": 7000}, inp={"hides": 8000},
                         labor={AR: 1500, M: 40}),
                  method("tan_steam", "蒸汽制革", era=3, tech="chemistry", out={"leather": 16000},
                         inp={"hides": 18000, "chemicals": 200, "power": 20}, labor={AR: 1400, M: 60})])

building("herbalist", "药局", "workshop", "manu", capital=1.0,
         art=art3("b15", "pharmacy", early=ART + "b15/pharmacy_early_v3.png"),
         methods=[method("herbal", "草药炮制", out={"medicine": 50000}, inp={"vegetables": 6000},
                         labor={AR: 1000, GE: 150}),
                  method("pharma", "制药工场", era=3, tech="public_health", out={"medicine": 150000},
                         inp={"chemicals": 600, "power": 20}, labor={AR: 1200, GE: 200}),
                  method("pharma_modern", "现代药厂", era=4, tech="antibiotics", out={"medicine": 500000},
                         inp={"chemicals": 1500, "electricity": 100}, labor={AR: 1200, GE: 300})])

building("shipyard", "船坞", "workshop", "manu", capital=1.6, art=art3("b08", "shipyard"),
         methods=[method("ship_wood", "木帆船", out={"ships": 30},
                         inp={"lumber": 3000, "rope": 3000, "sailcloth": 1500, "tools": 100},
                         labor={AR: 3000, M: 80}),
                  method("ship_steam", "蒸汽轮船", era=3, tech="steam_engine", out={"ships": 40},
                         inp={"steel": 1500, "machinery": 20, "rope": 2000}, labor={AR: 3500, M: 120}),
                  method("ship_modern", "现代船厂", era=4, tech="power_grid", out={"ships": 70},
                         inp={"steel": 3000, "machinery": 30, "electricity": 150}, labor={AR: 3000, M: 150})])

# ── 第二时代起 ──
building("gristmill", "磨坊", "workshop", "manu", capital=1.0, era=2, tech="water_power",
         art=art3("b05", "grainmill"),
         methods=[method("mill_water", "水磨", era=2, water=True, out={"flour": 20000}, inp={"grain": 21000},
                         labor={AR: 800, M: 40}),
                  method("mill_steam", "蒸汽面粉厂", era=3, tech="steam_engine", out={"flour": 60000},
                         inp={"grain": 63000, "power": 40}, labor={AR: 900, M: 60})])

building("sugarmill", "制糖坊", "workshop", "manu", capital=1.1, era=2, tech="sugar_refining",
         art=art3("b13", "sugarworks"),
         methods=[method("sugar_press", "甘蔗榨糖", era=2, out={"sugar": 6000}, inp={"sugarcane": 60000},
                         labor={AR: 2000, M: 60}),
                  method("sugar_steam", "蒸汽制糖", era=3, tech="steam_engine", out={"sugar": 15000},
                         inp={"sugarcane": 140000, "coal": 3000, "power": 30}, labor={AR: 2000, M: 80})])

building("glassworks", "玻璃坊", "workshop", "manu", capital=1.2, era=2, tech="glassmaking",
         art=art3("b06", "glass"),
         methods=[method("glass_hand", "吹制玻璃", era=2, out={"glass": 5000}, inp={"sand": 8000, "coal": 6000},
                         labor={AR: 2000, M: 60}),
                  method("glass_industrial", "工业玻璃", era=3, tech="steam_engine", out={"glass": 14000},
                         inp={"sand": 20000, "coal": 12000, "power": 30}, labor={AR: 2000, M: 80})])

building("tailor", "成衣坊", "workshop", "manu", capital=0.9, era=2, tech="flying_shuttle",
         art=art3("b06", "clothing"),
         methods=[method("tailor_hand", "裁缝作坊", era=2, out={"clothing": 60000}, inp={"fabric": 70000},
                         labor={AR: 3000, M: 80}),
                  method("tailor_factory", "成衣工厂", era=3, tech="machine_tools", out={"clothing": 160000},
                         inp={"fabric": 180000, "power": 30}, labor={AR: 3000, M: 120})])

# ── 第三时代起 ──
building("cokeworks", "炼焦厂", "workshop", "energy", capital=1.6, era=3, tech="coke_smelting",
         art={"1": ART + "b12/cokeworks_industrial.png", "2": ART + "b12/cokeworks_industrial.png",
              "3": ART + "b12/cokeworks_industrial.png", "4": ART + "b12/cokeworks_modern.png"},
         methods=[method("coke_beehive", "蜂巢炼焦", era=3, out={"coke": 40000}, inp={"coal": 60000},
                         labor={AR: 2000, M: 60}),
                  method("coke_recovery", "回收式炼焦", era=4, tech="petrochemistry",
                         out={"coke": 80000, "chemicals": 1500, "gas": 800}, inp={"coal": 110000, "electricity": 80},
                         labor={AR: 1800, M: 80})])

building("steamplant", "蒸汽动力站", "workshop", "energy", capital=1.8, era=3, tech="steam_engine",
         art={"1": ART + "b02/power_industrial.png", "2": ART + "b02/power_industrial.png",
              "3": ART + "b02/power_industrial.png", "4": ART + "b02/power_modern.png"},
         methods=[method("steam_power", "蒸汽机组", era=3, era_end=3, out={"power": 900},
                         inp={"coal": 30000, "machinery": 6}, labor={AR: 1500, M: 40})],
         note="第四时代由电厂取代。")

building("gasworks", "煤气厂", "workshop", "energy", capital=1.5, era=3, tech="steam_engine",
         art=art3("b09", "gas", early=ART + "b09/gas_early.png", modern=ART + "b09/gas_modern_v2.png"),
         methods=[method("gas_coal", "煤制气", era=3, out={"gas": 4000, "coke": 8000}, inp={"coal": 20000},
                         labor={AR: 1500, M: 60})])

building("cementworks", "水泥厂", "workshop", "manu", capital=1.8, era=3, tech="cement",
         art=art3("b07", "cement", industrial=ART + "b07/cement_industrial_v3.png"),
         methods=[method("cement_kiln", "立窑水泥", era=3, out={"cement": 20000},
                         inp={"limestone": 30000, "coal": 10000, "power": 40}, labor={AR: 2000, M: 60}),
                  method("cement_rotary", "回转窑水泥", era=4, tech="power_grid", out={"cement": 60000},
                         inp={"limestone": 85000, "coal": 20000, "electricity": 200}, labor={AR: 1800, M: 80})])

building("chemworks", "化工厂", "workshop", "manu", capital=2.0, era=3, tech="chemistry",
         art=art3("b07", "chemical"),
         methods=[method("chem_basic", "基础化工", era=3, out={"chemicals": 10000},
                         inp={"salt": 12000, "sulfur": 6000, "coal": 8000, "power": 40}, labor={AR: 2000, GE: 80, M: 60}),
                  method("chem_petro", "石油化工", era=4, tech="petrochemistry", out={"chemicals": 30000},
                         inp={"refined_fuel": 8000, "salt": 20000, "electricity": 200}, labor={AR: 1800, GE: 150, M: 80})])

building("fertilizerworks", "化肥厂", "workshop", "manu", capital=2.0, era=3, tech="fertilizer",
         art=art3("b07", "chemical"),
         methods=[method("fert_phosphate", "磷肥", era=3, out={"fertilizer": 12000},
                         inp={"phosphate": 14000, "chemicals": 2000, "power": 40}, labor={AR: 1800, M: 60}),
                  method("fert_synthetic", "合成氨", era=4, tech="petrochemistry", out={"fertilizer": 40000},
                         inp={"phosphate": 20000, "refined_fuel": 6000, "electricity": 300}, labor={AR: 1600, GE: 80, M: 80})])

building("machineworks", "机械厂", "workshop", "manu", capital=2.0, era=2, tech="water_power",
         art=art3("b07", "machineworks"),
         methods=[method("mach_water", "水力机械营造", era=2, water=True, out={"machinery": 200},
                         inp={"lumber": 2000, "tools": 2000, "pig_iron": 800}, labor={AR: 2500, M: 80}),
                  method("mach_steam", "蒸汽机械厂", era=3, tech="machine_tools", out={"machinery": 900},
                         inp={"steel": 2500, "tools": 1500, "power": 60}, labor={AR: 3000, GE: 60, M: 120}),
                  method("mach_modern", "工业装备厂", era=4, tech="automation", out={"machinery": 2500},
                         inp={"steel": 6000, "electric_motor": 400, "electricity": 300}, labor={AR: 2600, GE: 150, M: 150})])

building("railworks", "钢轨厂", "workshop", "manu", capital=2.0, era=3, tech="railway",
         art={"1": ART + "b07/steel_industrial_v2.png", "2": ART + "b07/steel_industrial_v2.png",
              "3": ART + "b07/steel_industrial_v2.png", "4": ART + "b07/steel_modern.png"},
         methods=[method("rail_rolling", "轧制钢轨", era=3, out={"rail": 5000}, inp={"steel": 5500, "power": 60},
                         labor={AR: 2000, M: 80})])

building("cannery", "罐头厂", "workshop", "manu", capital=1.4, era=3, tech="canning",
         art=art3("b05", "foodpreserve", modern=ART + "b05/foodpreserve_modern_v2.png"),
         methods=[method("can_steam", "罐藏食品", era=3, out={"preserved_food": 40000},
                         inp={"fish": 12000, "meat": 8000, "steel": 400, "power": 20}, labor={AR: 2500, M: 80}),
                  method("can_modern", "冷冻食品", era=4, tech="power_grid", out={"preserved_food": 120000},
                         inp={"fish": 30000, "meat": 25000, "electricity": 150, "plastic": 300}, labor={AR: 2200, M: 100})])

building("bakery", "面包坊", "workshop", "manu", capital=0.9, era=3, tech="steam_engine",
         art=art3("b13", "bakery"),
         methods=[method("bake_brick", "砖炉烘焙", era=3, out={"bread": 30000}, inp={"flour": 26000, "coal": 3000},
                         labor={AR: 1500, M: 60}),
                  method("bake_modern", "连续烘焙", era=4, tech="automation", out={"bread": 90000},
                         inp={"flour": 76000, "electricity": 80}, labor={AR: 1000, M: 60})])

# ── 第四时代 ──
building("powerplant", "火电厂", "workshop", "energy", capital=2.4, era=4, tech="power_grid",
         art={"1": ART + "b02/power_modern.png", "2": ART + "b02/power_modern.png",
              "3": ART + "b02/power_modern.png", "4": ART + "b02/power_modern.png"},
         methods=[method("power_coal", "燃煤发电", era=4, out={"electricity": 1500}, inp={"coal": 60000, "machinery": 8},
                         labor={AR: 1200, GE: 60}),
                  method("power_oil", "燃油发电", era=4, tech="petrochemistry", out={"electricity": 1500},
                         inp={"refined_fuel": 12000, "machinery": 8}, labor={AR: 1000, GE: 60})])

building("hydroplant", "水电站", "workshop", "energy", capital=3.0, era=4, tech="power_grid", deposit="hydro",
         art=art3("b09", "hydropower"),
         methods=[method("hydro", "水力发电", era=4, out={"electricity": 1400}, inp={"machinery": 4},
                         labor={AR: 500, GE: 40})])

building("windfarm", "风电场", "workshop", "energy", capital=2.6, era=4, tech="solar_wind",
         art={"1": ART + "b09/windpower_early.png", "2": ART + "b09/windpower_early.png",
              "3": ART + "b09/windpower_industrial.png", "4": ART + "b09/windpower_modern_v2.png"},
         methods=[method("wind", "风力发电", era=4, out={"electricity": 700}, inp={"machinery": 3},
                         labor={AR: 300, GE: 30})])

building("refinery", "炼油厂", "workshop", "energy", capital=2.4, era=4, tech="petrochemistry",
         art=art3("b09", "refinery", early=ART + "b09/refinery_early_v2.png"),
         methods=[method("refine", "炼油", era=4, out={"refined_fuel": 50000, "plastic": 2000},
                         inp={"crude_oil": 60000, "electricity": 150}, labor={AR: 1500, GE: 80, M: 80})])

building("aluminumworks", "铝厂", "workshop", "manu", capital=2.4, era=4, tech="electrochemistry",
         art={"1": ART + "b14/copperworks_modern.png", "2": ART + "b14/copperworks_modern.png",
              "3": ART + "b14/copperworks_modern.png", "4": ART + "b14/copperworks_modern.png"},
         methods=[method("alu_electro", "电解铝", era=4, out={"aluminum": 6000},
                         inp={"bauxite": 24000, "electricity": 900}, labor={AR: 1500, GE: 60, M: 60})],
         note="暂借炼铜厂现代期配图；需一张「电解铝厂」建筑图。")

building("electricalworks", "电气设备厂", "workshop", "manu", capital=2.2, era=4, tech="power_grid",
         art=art3("b08", "electrical", modern=ART + "b08/electrical_modern_v2.png"),
         methods=[method("elec_motor", "电机与变压器", era=4, out={"electric_motor": 1200, "cable": 3000},
                         inp={"copper": 3000, "steel": 1500, "electricity": 200}, labor={AR: 2500, GE: 120, M: 100})])

building("electronicsworks", "电子厂", "workshop", "manu", capital=2.6, era=4, tech="electronics",
         art=art3("b08", "electronics"),
         methods=[method("elec_parts", "电子元件", era=4, out={"electronic_parts": 20000},
                         inp={"copper": 800, "plastic": 1500, "chemicals": 600, "electricity": 200},
                         labor={AR: 2500, GE: 200, M: 100}),
                  method("elec_radio", "收音机与电视机", era=4, tech="television",
                         out={"radio": 30000, "television": 12000},
                         inp={"electronic_parts": 18000, "plastic": 2000, "electricity": 150},
                         labor={AR: 3000, GE: 150, M: 120}),
                  method("elec_computer", "计算机", era=4, tech="computing", out={"computer": 6000},
                         inp={"electronic_parts": 30000, "plastic": 1000, "electricity": 300},
                         labor={AR: 2000, GE: 600, M: 120})])

building("applianceworks", "家电厂", "workshop", "manu", capital=2.2, era=4, tech="automation",
         art={"1": ART + "b08/electrical_modern_v2.png", "2": ART + "b08/electrical_modern_v2.png",
              "3": ART + "b08/electrical_modern_v2.png", "4": ART + "b08/electrical_modern_v2.png"},
         methods=[method("appliance", "家用电器", era=4, out={"appliances": 30000},
                         inp={"steel": 2500, "electric_motor": 900, "plastic": 1500, "electricity": 150},
                         labor={AR: 3000, GE: 100, M: 120})],
         note="暂借电气设备厂配图；需一张「家电装配厂」建筑图。")

building("autoworks", "汽车厂", "workshop", "manu", capital=2.8, era=4, tech="automobile",
         art=art3("b08", "vehicle", early=ART + "b08/vehicle_early_v3.png", modern=ART + "b08/vehicle_modern_v2.png"),
         methods=[method("auto_assembly", "汽车装配", era=4, out={"automobile": 4000},
                         inp={"steel": 5000, "machinery": 200, "rubber": 1500, "electronic_parts": 1200,
                              "refined_fuel": 500, "electricity": 200},
                         labor={AR: 4000, GE: 150, M: 150})])

# ════════════════════════════ 基础设施 ════════════════════════════════════
building("market", "集市", "infra", "serv", capital=1.2, art=art3("b10", "market",
                                                                modern=ART + "b10/market_modern_v2.png"),
         methods=[method("market_trad", "集市", out={}, labor={M: 2500, AR: 800}),
                  method("market_hall", "商贸市场", era=3, tech="railway", out={}, labor={M: 2200, AR: 600}),
                  method("market_modern", "城市批发中心", era=4, tech="automation", out={}, labor={M: 1800, AR: 400})],
         effects={"commerce": 180000},
         note="每级每季可承接约 18 万两的零售额（商贸市场 ×2.5、批发中心 ×6）。商贸能力不足时商贩加价。")

building("carrier", "车马行", "infra", "serv", capital=1.0, art=art3("b08", "vehicle",
                                                                  early=ART + "b08/vehicle_early_v3.png",
                                                                  modern=ART + "b08/vehicle_modern_v2.png"),
         methods=[method("carrier_animal", "车马运输", out={}, inp={"draft_animal": 30}, labor={AR: 1000, P: 1000}),
                  method("carrier_rail", "铁路货运", era=3, tech="railway", out={}, inp={"coal": 4000, "rail": 40},
                         labor={AR: 2500}),
                  method("carrier_truck", "汽车货运", era=4, tech="automobile", out={},
                         inp={"refined_fuel": 3000, "automobile": 20}, labor={AR: 2000})],
         effects={"freight": 9000},
         note="每级每季可收约 9 千两运费（铁路 ×4、汽车 ×8）。运力不足时物流成本上升。")

building("road", "驿路", "infra", "serv", owners=("gov",), capital=2.0, art=art3("b03", "transport",
                                                                               modern=ART + "b03/transport_modern_v2.png"),
         methods=[method("road_post", "驿路", out={}, labor={P: 1500}),
                  method("road_rail", "铁路干线", era=3, tech="railway", out={}, inp={"rail": 60}, labor={AR: 1500}),
                  method("road_highway", "公路网", era=4, tech="automobile", out={}, inp={"cement": 400}, labor={AR: 1200})],
         effects={"logistics_cut": 15000},
         note="每级把本地区的物流成本降低 1.5 个百分点（铁路 4 个、公路 5 个），有下限。")

building("canal", "运河", "infra", "serv", owners=("gov",), capital=3.0, era=2, tech="canal_engineering",
         art={"1": ART + "b12/canal_early.png", "2": ART + "b12/canal_early.png",
              "3": ART + "b12/canal_industrial.png", "4": ART + "b12/canal_modern.png"},
         methods=[method("canal_lock", "纤道船闸", era=2, out={}, labor={P: 2000}),
                  method("canal_steam", "蒸汽拖船闸", era=3, tech="steam_engine", out={}, inp={"coal": 1000},
                         labor={AR: 1200})],
         effects={"logistics_cut": 30000},
         note="只能建在有河的地区；每级降低物流成本 3 个百分点。")

building("port", "港口", "infra", "serv", capital=1.6, coast=True,
         art=art3("b03", "port"),
         methods=[method("port_wharf", "河港仓栈", out={}, inp={"ships": 2}, labor={AR: 2000, M: 300}),
                  method("port_trade", "商贸港区", era=3, tech="steam_engine", out={}, inp={"ships": 2, "coal": 1500},
                         labor={AR: 2500, M: 400}),
                  method("port_modern", "机械化港区", era=4, tech="automation", out={}, inp={"ships": 3, "electricity": 100},
                         labor={AR: 2000, M: 400})],
         effects={"sea_trade": 400000},
         note="每级每季可吞吐约 40 万两的海上贸易（第三时代 ×2.5，第四时代 ×6）。需要船只维持。")

building("caravanserai", "关津商栈", "infra", "serv", capital=1.4, art=art3("b16", "customs"),
         methods=[method("caravan", "关津商栈", out={}, inp={"draft_animal": 40}, labor={M: 400, AR: 800, P: 800}),
                  method("customs_house", "海关验货仓", era=3, tech="railway", out={}, labor={M: 500, AR: 800}),
                  method("customs_modern", "现代通关中心", era=4, tech="computing", out={}, labor={M: 400, GE: 100})],
         effects={"land_trade": 200000, "customs_eff": 20000},
         note="每级每季可承接约 20 万两的陆路贸易，并提高关税征收率。")

building("irrigation", "水利", "infra", "serv", owners=("gov",), capital=2.2,
         art=art3("b01", "irrigation"),
         methods=[method("irrig_canal", "渠系水轮", out={}, labor={P: 1500}),
                  method("irrig_pump", "工业泵站", era=3, tech="steam_engine", out={}, inp={"coal": 800}, labor={AR: 600}),
                  method("irrig_electric", "电动灌溉", era=4, tech="power_grid", out={}, inp={"electricity": 60},
                         labor={AR: 400})],
         effects={"irrigate": 25},
         note="每级灌溉本地区 25 级农田（250 万亩），使其增产 25%（工业泵站 35%，电动 45%）。")

building("watermill", "水力动力坊", "infra", "energy", owners=("gov",), capital=1.6, art=art3("b02", "power"),
         methods=[method("waterwheel", "水轮", out={}, labor={AR: 600}),
                  method("waterwheel_iron", "铁制水轮", era=2, tech="water_power", out={}, inp={"pig_iron": 100},
                         labor={AR: 500})],
         effects={"waterpower": 6},
         note="只能建在有河的地区；每级为本地区 6 级「水力」作坊提供动力，使其满产。")

building("granary", "粮仓", "infra", "serv", owners=("gov",), capital=1.2,
         art={"1": ART + "b13/granary_early.png", "2": ART + "b13/granary_early.png",
              "3": ART + "b13/granary_industrial.png", "4": ART + "b13/granary_modern.png"},
         methods=[method("granary_raised", "架空粮仓", out={}, labor={P: 300, GE: 20})],
         effects={"grain_store": 400000},
         note="每级可储存 40 万石口粮，平时收储、灾年开仓（配合「常平仓」政令）。")

building("surveyoffice", "丈量所", "infra", "serv", owners=("gov",), capital=1.0,
         art=art3("b16", "survey", early=ART + "b16/survey_early_v2.png"),
         methods=[method("survey_trad", "丈量制图", out={}, labor={GE: 300, AR: 200})],
         effects={"survey": 1},
         note="每级把本地区隐田每年的增长减少一半（两级以上基本止住）。")

# ════════════════════════════ 公共设施 ════════════════════════════════════
building("school", "学舍", "public", "serv", owners=("gov",), capital=1.6, art=art3("b01", "education"),
         methods=[method("school_trad", "地方学舍", out={}, inp={"paper": 3000, "books": 300}, labor={GE: 500}),
                  method("school_modern", "新式学堂", era=3, tech="public_education", out={}, inp={"paper": 6000, "books": 800},
                         labor={GE: 700}),
                  method("school_research", "研究型大学", era=4, tech="computing", out={}, inp={"paper": 8000, "books": 1200, "electricity": 60},
                         labor={GE: 900})],
         effects={"edu_seats": 20000},
         note="每级每季有 2 万个学位（新式学堂 3 万，大学 4 万）；提高识字率，培养士人，产生研究点。")

building("library", "藏书院", "public", "serv", owners=("gov",), capital=1.4, art=art3("b10", "library"),
         methods=[method("library_trad", "藏书院", out={}, inp={"books": 800}, labor={GE: 120}),
                  method("library_public", "公共图书馆", era=3, tech="public_education", out={}, inp={"books": 2000},
                         labor={GE: 200}),
                  method("library_modern", "知识资料中心", era=4, tech="computing", out={}, inp={"books": 2000, "computer": 20},
                         labor={GE: 250})],
         effects={"research": 60, "literacy": 5000},
         note="每级每季 60 研究点（公共图书馆 120、资料中心 220），并提高本地区识字率。")

building("clinic", "医馆", "public", "serv", owners=("gov",), capital=1.4, art=art3("b04", "health"),
         methods=[method("clinic_trad", "地方医馆", out={}, inp={"medicine": 6000}, labor={GE: 200, AR: 200}),
                  method("clinic_hospital", "公共医院", era=3, tech="public_health", out={}, inp={"medicine": 15000},
                         labor={GE: 400, AR: 400}),
                  method("clinic_modern", "区域医疗中心", era=4, tech="antibiotics", out={}, inp={"medicine": 40000, "electricity": 60},
                         labor={GE: 600, AR: 500})],
         effects={"health": 400000},
         note="每级照顾约 40 万人（医院 80 万、医疗中心 150 万），降低死亡率。")

building("yamen", "衙署", "public", "serv", owners=("gov",), capital=1.6, art=art3("b04", "administration"),
         methods=[method("yamen_trad", "地方衙署", out={}, inp={"paper": 4000}, labor={GE: 1500}),
                  method("yamen_modern", "税关核算所", era=3, tech="telegraph", out={}, inp={"paper": 8000}, labor={GE: 1500}),
                  method("yamen_digital", "现代行政中心", era=4, tech="computing", out={}, inp={"paper": 6000, "computer": 30},
                         labor={GE: 1200})],
         effects={"admin": 1000000},
         note="每级治理约 100 万人口（新式 200 万、现代 400 万）；治理不足时征收率下降、隐田增长加快。")

building("theater", "戏台", "public", "serv", owners=("gov",), capital=1.0,
         art=art3("b16", "theater", early=ART + "b16/theater_early_v2.png"),
         methods=[method("theater_folk", "民间戏台", out={}, labor={AR: 300, M: 50}),
                  method("theater_city", "城市剧院", era=3, tech="railway", out={}, labor={AR: 400, M: 80}),
                  method("theater_modern", "现代演艺中心", era=4, tech="television", out={}, inp={"electricity": 40},
                         labor={AR: 400, M: 100})],
         effects={"amenity": 500000},
         note="每级让约 50 万人的民心略有提升。")

building("urbanworks", "城政", "public", "serv", owners=("gov",), capital=1.6,
         art=art3("b04", "utility", early=ART + "b04/utility_early_v2.png"),
         methods=[method("urban_wells", "水井与排水", out={}, labor={P: 800, AR: 300}),
                  method("urban_sanitation", "供水卫生设施", era=3, tech="public_health", out={}, inp={"coal": 500, "cement": 100},
                         labor={AR: 600}),
                  method("urban_modern", "综合公用设施", era=4, tech="power_grid", out={}, inp={"electricity": 80, "chemicals": 100},
                         labor={AR: 500})],
         effects={"sanitation": 800000},
         note="每级覆盖约 80 万人（卫生设施 150 万、综合公用 300 万），降低疫病风险与死亡率。")
