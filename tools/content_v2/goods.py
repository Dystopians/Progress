# -*- coding: utf-8 -*-
"""四百年战役 v2 的商品表（docs/57 §4）。

字段：
  id        商品 ID（与 Codex 物资图的 goods_id 对齐，去掉 goods. 前缀）
  name      中文名
  unit      显示单位
  sector    统计部门：agri 农 / manu 工 / energy 能 / serv 服
  tier      层级：0 原料，1 半成品，2 成品，3 资本品或复杂成品
  era       出现的时代（1—4）
  era_end   淡出的时代（含），缺省 4
  perish    每季损耗（百分数）
  price     仅对「不在本国生产的商品」或需要手工锚定的商品给出基准价（两 / 单位）；
            其余由 calibrate.py 按成本加成倒推
  durable   耐用投入（农具、役畜、船只）：投入取季初库存，用来打破产业链里的环
  art       物资图路径（相对工程根）；没有专属图时写 None，完成时汇总进资源需求
"""

G = []


def good(id, name, unit, sector, tier, era=1, era_end=4, perish=2, price=None, durable=False, art=None,
         note=""):
    G.append(dict(id=id, name=name, unit=unit, sector=sector, tier=tier, era=era, era_end=era_end,
                  perish=perish, price=price, durable=durable, art=art, note=note))


A = "assets/goods/"

# ── 第一时代：原料 ─────────────────────────────────────────────────────────
good("rice", "稻米", "石", "agri", 0, perish=2, art=A + "g07/goods_rice_v2.png")
good("grain", "麦粟", "石", "agri", 0, perish=2, art=A + "g01/goods_grain.png")
good("beans", "豆类", "石", "agri", 0, perish=2, art=A + "g07/goods_beans.png")
good("vegetables", "蔬菜", "担", "agri", 0, perish=35, art=A + "g01/goods_vegetables.png")
good("fruit", "水果", "担", "agri", 0, perish=30, art=A + "g01/goods_fruit.png")
good("cotton", "棉花", "担", "agri", 0, perish=1, art=A + "g01/goods_cotton.png")
good("hemp", "麻", "担", "agri", 0, perish=1, art=A + "g07/goods_hemp.png")
good("cocoon", "蚕茧", "担", "agri", 0, perish=10, art=A + "g05/goods_cocoon.png")
good("tea", "茶叶", "担", "agri", 0, perish=3, art=A + "g05/goods_tea.png")
good("oilseed", "油籽", "石", "agri", 0, perish=2, art=A + "g07/goods_oilseed_v2.png")
good("fish", "鱼", "担", "agri", 0, perish=40, art=A + "g01/goods_fish.png")
good("meat", "肉", "担", "agri", 0, perish=40, art=A + "g01/goods_meat_v2.png")
good("draft_animal", "役畜", "头", "agri", 0, perish=3, durable=True, art=A + "g05/goods_draft_animal.png")
good("wool", "羊毛", "担", "agri", 0, perish=1, art=A + "g01/goods_wool.png")
good("hides", "生皮", "张", "agri", 0, perish=5, art=A + "g01/goods_hides.png")
good("timber", "原木", "方", "agri", 0, perish=1, art=A + "g01/goods_timber.png")
good("iron_ore", "铁矿石", "担", "manu", 0, perish=0, art=A + "g02/goods_iron_ore.png")
good("copper_ore", "铜矿石", "担", "manu", 0, perish=0, art=A + "g09/goods_copper_ore.png")
good("kaolin", "瓷土", "担", "manu", 0, perish=0, art=A + "g05/goods_kaolin.png")
good("cut_stone", "石料", "方", "manu", 0, perish=0, art=A + "g08/goods_cut_stone_v2.png")
good("coal", "煤", "担", "energy", 0, perish=0, art=A + "g02/goods_coal.png")
good("salt", "盐", "担", "manu", 0, perish=1, art=A + "g05/goods_salt.png")

# ── 第一时代：半成品 ───────────────────────────────────────────────────────
good("yarn", "纱线", "担", "manu", 1, perish=1, art=A + "g08/goods_yarn.png")
good("silk_thread", "生丝", "担", "manu", 1, perish=1, art=A + "g08/goods_silk_thread.png")
good("charcoal", "木炭", "担", "energy", 1, era_end=3, perish=1, art=A + "g05/goods_charcoal.png")
good("lumber", "板材", "方", "manu", 1, perish=1, art=A + "g01/goods_lumber.png")
good("pig_iron", "生铁", "担", "manu", 1, perish=0, art=A + "g09/goods_pig_iron.png")
good("copper", "铜材", "担", "manu", 1, perish=0, art=A + "g03/goods_copper_v2.png")
good("cooking_oil", "食用油", "担", "manu", 1, perish=3, art=A + "g08/goods_cooking_oil.png")
good("leather", "皮革", "张", "manu", 1, perish=1, art=A + "g02/goods_leather.png")
good("paper", "纸张", "刀", "manu", 1, perish=1, art=A + "g02/goods_paper.png")
good("bricks", "砖瓦", "千块", "manu", 1, perish=0, art=A + "g02/goods_bricks.png")
good("rope", "绳索", "捆", "manu", 1, perish=1, art=A + "g08/goods_rope.png")
good("sailcloth", "帆布", "匹", "manu", 1, perish=1, art=A + "g08/goods_sailcloth.png")

# ── 第一时代：成品 ─────────────────────────────────────────────────────────
good("fabric", "布匹", "匹", "manu", 2, perish=1, art=A + "g02/goods_fabric.png")
good("silk", "绸缎", "匹", "manu", 2, perish=1, art=A + "g05/goods_silk.png")
good("tools", "铁器农具", "件", "manu", 2, perish=2, durable=True, art=A + "g03/goods_tools.png")
good("porcelain", "瓷器", "件", "manu", 2, perish=0, art=A + "g05/goods_porcelain.png")
good("earthenware", "粗陶", "件", "manu", 2, perish=1, art=A + "g08/goods_earthenware_v2.png")
good("furniture", "家具", "件", "manu", 2, perish=1, art=A + "g08/goods_furniture.png")
good("books", "书籍", "部", "manu", 2, perish=0, art=A + "g02/goods_books.png")
good("candles", "蜡烛", "斤", "manu", 2, perish=1, art=A + "g08/goods_candles.png")
good("wine", "酒", "坛", "manu", 2, perish=1, art=A + "g11/goods_wine.png", note="米酒、黄酒与烧酒，用粮食酿成。")
good("medicine", "药材成药", "剂", "manu", 2, perish=3, art=A + "g04/goods_medicine.png")
good("ships", "船只", "艘", "manu", 3, perish=2, durable=True, art=A + "g11/goods_ships.png", note="货船与渔船，港口运货、打鱼都要用；会慢慢磨损，要不断补充。")

# ── 第二时代 ───────────────────────────────────────────────────────────────
good("sugarcane", "甘蔗", "担", "agri", 0, era=2, perish=20, art=A + "g07/goods_sugarcane.png")
good("sugar", "蔗糖", "担", "manu", 1, era=2, perish=1, art=A + "g06/goods_sugar.png")
good("flour", "面粉", "石", "manu", 1, era=2, perish=3, art=A + "g01/goods_flour_v2.png")
good("sand", "砂料", "方", "manu", 0, era=2, perish=0, art=A + "g09/goods_sand_v2.png")
good("glass", "玻璃", "箱", "manu", 2, era=2, perish=1, art=A + "g02/goods_glass.png")
good("soap", "肥皂", "箱", "manu", 2, era=2, perish=1, art=A + "g08/goods_soap.png")
good("spices", "香料", "担", "agri", 0, era=2, perish=2, price=12.0, art=A + "g07/goods_spices.png",
     note="只能进口")
good("coffee", "咖啡豆", "担", "agri", 0, era=2, perish=2, price=9.0, art=A + "g07/goods_coffee.png",
     note="只能进口")
good("clothing", "成衣", "件", "manu", 2, era=2, perish=1, art=A + "g02/goods_clothing.png")

# ── 第三时代 ───────────────────────────────────────────────────────────────
good("coke", "焦炭", "担", "energy", 1, era=3, perish=0, art=A + "g06/goods_coke.png")
good("steel", "钢材", "吨", "manu", 2, era=3, perish=0, art=A + "g02/goods_steel.png")
good("machinery", "机械", "台", "manu", 3, era=3, perish=2, durable=True, art=A + "g03/goods_machinery_v2.png")
good("rail", "钢轨", "吨", "manu", 3, era=3, perish=0, art=A + "g10/goods_rail.png")
good("limestone", "石灰岩", "方", "manu", 0, era=3, perish=0, art=A + "g09/goods_limestone.png")
good("cement", "水泥", "吨", "manu", 1, era=3, perish=1, art=A + "g02/goods_cement_v2.png")
good("sulfur", "硫磺", "担", "manu", 0, era=3, perish=0, art=A + "g09/goods_sulfur.png")
good("chemicals", "化学品", "桶", "manu", 1, era=3, perish=1, art=A + "g03/goods_chemicals.png")
good("phosphate", "磷矿石", "吨", "manu", 0, era=3, perish=0, art=A + "g09/goods_phosphate.png")
good("fertilizer", "化肥", "吨", "manu", 2, era=3, perish=1, art=A + "g03/goods_fertilizer_v2.png")
good("preserved_food", "罐藏食品", "箱", "manu", 2, era=3, perish=1, art=A + "g02/goods_preserved_food.png")
good("bread", "面包", "担", "manu", 2, era=3, perish=40, art=A + "g08/goods_bread.png")
good("beer", "啤酒", "桶", "manu", 2, era=3, perish=5, art=A + "g08/goods_beer_v2.png")
good("gas", "煤气", "千方", "energy", 1, era=3, perish=100, art=A + "g03/goods_gas.png")
good("rubber", "橡胶", "担", "agri", 0, era=3, perish=1, price=14.0, art=A + "g03/goods_rubber.png",
     note="只能进口")
good("power", "动力", "千马力时", "energy", 1, era=3, perish=100, art=A + "g11/goods_power_v2.png",
     note="蒸汽机带动的动力，当季用掉、存不住；第四时代仍可用，渐渐被电力取代。")

# ── 第四时代 ───────────────────────────────────────────────────────────────
good("electricity", "电力", "万度", "energy", 1, era=4, perish=100, art=A + "g04/goods_electricity.png")
good("crude_oil", "原油", "桶", "energy", 0, era=4, perish=0, art=A + "g03/goods_crude_oil.png")
good("refined_fuel", "燃料油", "桶", "energy", 1, era=4, perish=0, art=A + "g03/goods_refined_fuel.png")
good("plastic", "塑料", "吨", "manu", 1, era=4, perish=0, art=A + "g10/goods_plastic.png")
good("bauxite", "铝土矿", "吨", "manu", 0, era=4, perish=0, art=A + "g09/goods_bauxite.png")
good("aluminum", "铝材", "吨", "manu", 1, era=4, perish=0, art=A + "g09/goods_aluminum.png")
good("cable", "电缆", "千米", "manu", 2, era=4, perish=0, art=A + "g03/goods_cable.png")
good("electric_motor", "电动机", "台", "manu", 3, era=4, perish=1, durable=True, art=A + "g03/goods_electric_motor.png")
good("electronic_parts", "电子元件", "箱", "manu", 2, era=4, perish=1, art=A + "g03/goods_electronic_parts.png")
good("radio", "收音机", "台", "manu", 3, era=4, perish=1, art=A + "g10/goods_radio.png")
good("television", "电视机", "台", "manu", 3, era=4, perish=1, art=A + "g10/goods_television.png")
good("appliances", "家用电器", "台", "manu", 3, era=4, perish=1, art=A + "g06/goods_appliances.png")
good("automobile", "机动车", "辆", "manu", 3, era=4, perish=1, art=A + "g06/goods_automobile.png")
good("computer", "计算机", "台", "manu", 3, era=4, perish=2, art=A + "g10/goods_computer.png")
# 第三时代起：服务（茶楼酒肆、戏园、理发、餐馆……）。当季用掉、存不住；越富越多买，靠人手，城里的活计跟着多
good("services", "服务", "人次", "serv", 2, era=3, perish=100, art=None,
     note="茶楼酒肆、戏园、理发、餐馆这类花钱买的服务；当季用掉，存不住。")
