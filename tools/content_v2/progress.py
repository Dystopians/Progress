# -*- coding: utf-8 -*-
"""科技、时代、政令、贸易伙伴、地标、事件（docs/57 §7—§10）。

效果（effects）统一写成「修正」：{"target": 目标名, "value": 数值, "scope": 可选地区或商品}。
模拟核心认得的目标名见 campaign/core/jc_mods.gd 顶部的清单；数值一律是百分数（+20 表示 +20%）
或点数（民心、国望），单位在目标清单里注明。
"""


def mod(target, value, scope=""):
    return {"target": target, "value": value, "scope": scope}


# ════════════════════════════ 科技 ════════════════════════════════════════
# cost：研究点。bg：国内背景（建筑或商品 → 加速上限的贡献，满额 +50%）；
# 海外背景由伙伴是否掌握自动得出（满额 +100%）。
T = []


def tech(id, name, era, cost, prereq=(), key=False, bg=(), effects=(), desc="", foreign=True):
    T.append(dict(id=id, name=name, era=era, cost=cost, prereq=list(prereq), key=key, bg=list(bg),
                  effects=list(effects), desc=desc, foreign=foreign))


# 第一时代
tech("crop_rotation", "轮作与新作物", 1, 7000, bg=["dryfarm", "paddy"],
     desc="豆麦轮作、引种新作物，旱田与水田都能增产两成（需改用轮作的种法）。")
tech("water_management", "水利营造", 1, 7000, bg=["irrigation"],
     effects=[mod("irrigation_eff", 20)], desc="水利设施的增产效果提高两成。")
tech("survey", "土地清丈", 1, 6000, bg=["surveyoffice", "yamen"],
     desc="可以推行「清丈田亩」，也能建丈量所，止住隐田增长。")
tech("granary_system", "常平仓法", 1, 5000, bg=["granary"],
     desc="可以推行「常平仓」：丰年收储、荒年平粜。")
tech("movable_type", "活字印刷", 1, 7000, bg=["printing", "papermill"],
     desc="印坊可改用活字，书籍产量提高三分之二；读书人更多。")
tech("herbal_medicine", "本草", 1, 6000, bg=["herbalist", "clinic"],
     effects=[mod("health_eff", 20)], desc="医馆与药局的效果提高两成。")
tech("craft_guild", "行会工场", 1, 8000, bg=["weaving", "smithy", "porcelainkiln"],
     effects=[mod("workshop_labor", -8)], desc="作坊分工更细，用工减少 8%。")
tech("bookkeeping", "复式记账", 1, 10000, key=True, bg=["market"],
     effects=[mod("commerce_cap", 15), mod("invest_prop", 10)],
     desc="商帮记账更严密：集市能力 +15%，民间投资意愿 +10%；可以推行「一条鞭法」。")
tech("harbor_works", "港务营造", 1, 8000, bg=["port", "shipyard"],
     effects=[mod("sea_trade_cap", 30)], desc="港口吞吐能力提高三成。")
tech("navigation", "海图与罗盘", 1, 11000, prereq=["harbor_works"], bg=["port", "shipyard"],
     effects=[mod("sea_trade_cap", 15), mod("relation_all", 5)],
     desc="远航更安全：港口能力再 +15%，可以推行「遣使译书」。")
tech("water_power", "水力机械", 1, 14000, key=True, prereq=["water_management"], bg=["watermill"],
     desc="铁制水轮、水力锯木、水磨、水力机械营造。进入第二时代的关键科技。")

# 第二时代
tech("double_cropping", "双季稻", 2, 22000, prereq=["crop_rotation"], bg=["paddy"],
     desc="水田可改为双季稻，增产五成以上，用工也更多。")
tech("sugar_refining", "甘蔗制糖", 2, 18000, bg=["paddy"], desc="水田可改种甘蔗，可建制糖坊。")
tech("water_frame", "水力纺纱", 2, 24000, prereq=["water_power"], bg=["spinning", "watermill"],
     desc="纺纱坊改用水力，用工减少六成（需要本地区有水力）。")
tech("flying_shuttle", "飞梭", 2, 22000, prereq=["craft_guild"], bg=["weaving"],
     desc="织布用工减少四成；可建成衣坊。")
tech("coal_iron", "煤炭冶铁", 2, 26000, bg=["coalmine", "ironworks"],
     desc="冶铁、打铁、制陶、烧砖改烧煤，缓解木炭短缺。")
tech("banking", "钱庄汇兑", 2, 45000, prereq=["bookkeeping"], bg=["market"],
     effects=[mod("invest_prop", 15)], desc="钱庄兴起：民间投资意愿 +15%，可以推行「钱庄准入」、借商债。")
tech("canal_engineering", "运河营造", 2, 28000, prereq=["water_management"], bg=["irrigation"],
     desc="可以开凿运河，大幅降低有河地区的物流成本。")
tech("glassmaking", "玻璃", 2, 16000, bg=["pottery"], desc="可以开砂场、建玻璃坊。")
tech("chemistry_basic", "皂化", 2, 14000, bg=["chandlery"], desc="皂烛坊兼产肥皂。")
tech("ocean_navigation", "远洋航海", 2, 30000, prereq=["navigation"], bg=["shipyard", "port"],
     effects=[mod("sea_trade_cap", 25)], desc="远洋商会愿意来往；港口能力 +25%。")
tech("steam_principle", "蒸汽原理", 2, 34000, key=True, prereq=["water_power"], bg=["machineworks"],
     desc="进入第三时代的关键科技之一。")
tech("precision_mechanics", "精密机械", 2, 34000, key=True, prereq=["water_power"], bg=["machineworks", "smithy"],
     effects=[mod("workshop_labor", -5)], desc="进入第三时代的关键科技之一。")

# 第三时代
tech("steam_engine", "蒸汽机", 3, 60000, prereq=["steam_principle"], bg=["machineworks", "coalmine"],
     desc="蒸汽动力站、蒸汽纺织、竖井煤矿、机帆渔船……动力耗煤。")
tech("coke_smelting", "焦炭炼铁", 3, 60000, prereq=["coal_iron"], bg=["ironworks", "coalmine"],
     desc="炼焦厂与焦炭高炉，生铁产量成倍提高。木炭开始淡出。")
tech("bessemer", "转炉炼钢", 3, 70000, prereq=["coke_smelting"], bg=["ironworks"], desc="可以建钢铁厂。")
tech("machine_tools", "机床", 3, 70000, prereq=["bessemer", "precision_mechanics"], bg=["machineworks"],
     desc="蒸汽机械厂、机加工工具、机械家具、成衣工厂。")
tech("railway", "铁路", 3, 80000, prereq=["steam_engine", "bessemer"], bg=["road", "railworks"],
     desc="铁路干线与铁路货运，物流成本大降；可建钢轨厂。")
tech("chemistry", "化学工业", 3, 65000, bg=["chandlery", "tannery"], desc="化工厂、硫磺矿、机械制皂、蒸汽制革。")
tech("fertilizer", "化肥", 3, 70000, prereq=["chemistry"], bg=["dryfarm", "paddy"],
     desc="磷矿与化肥厂；农田可改为施肥种法，增产七成。")
tech("cement", "水泥", 3, 50000, bg=["quarry", "brickkiln"], desc="石灰岩与水泥厂。")
tech("canning", "罐头", 3, 45000, bg=["fishery"], desc="罐头厂。")
tech("telegraph", "电报", 3, 60000, prereq=["steam_engine"], bg=["yamen"],
     effects=[mod("admin_eff", 25)], desc="衙署效率提高，可改为新式税关核算所。")
tech("public_health", "公共卫生", 3, 55000, bg=["clinic", "urbanworks"],
     effects=[mod("health_eff", 25)], desc="公共医院、卫生设施与制药工场。")
tech("public_education", "新式教育", 3, 55000, bg=["school", "library"],
     effects=[mod("literacy_rate", 30)], desc="新式学堂与公共图书馆。")
tech("sericulture_science", "蚕桑改良", 3, 40000, bg=["mulberry"], desc="良种桑蚕，蚕茧增产七成。")
tech("dynamo", "发电机", 3, 90000, key=True, prereq=["steam_engine"], bg=["steamplant"],
     desc="进入第四时代的关键科技之一。")
tech("internal_combustion", "内燃机", 3, 90000, key=True, prereq=["steam_engine"], bg=["machineworks"],
     desc="进入第四时代的关键科技之一。")

# 第四时代
tech("power_grid", "电网", 4, 140000, prereq=["dynamo"], bg=["steamplant"],
     desc="火电厂、水电站与跨区电网；大批工厂改用电力。")
tech("electrochemistry", "电化学", 4, 130000, prereq=["power_grid"], bg=["chemworks"], desc="电解铝、电解精炼铜。")
tech("petrochemistry", "石油化工", 4, 150000, prereq=["internal_combustion"], bg=["chemworks"],
     desc="油井、炼油厂、合成氨、石油化工。")
tech("automobile", "汽车", 4, 150000, prereq=["internal_combustion"], bg=["machineworks"],
     desc="汽车厂、汽车货运、公路网。")
tech("electronics", "电子管", 4, 140000, prereq=["power_grid"], bg=["electricalworks"], desc="电子厂。")
tech("television", "电视", 4, 160000, prereq=["electronics"], bg=["electronicsworks"], desc="收音机与电视机。")
tech("antibiotics", "抗生素", 4, 140000, prereq=["public_health"], bg=["clinic", "herbalist"],
     effects=[mod("health_eff", 40)], desc="现代药厂与区域医疗中心，死亡率大降。")
tech("mechanized_farming", "农业机械化", 4, 150000, prereq=["internal_combustion"], bg=["dryfarm", "paddy"],
     desc="农田可改为机械化种法，用工减少七成。")
tech("automation", "自动化", 4, 180000, prereq=["electronics"], bg=["machineworks", "electricalworks"],
     effects=[mod("workshop_labor", -10)], desc="家电厂、工业装备厂、精密工具。")
tech("computing", "计算机", 4, 220000, prereq=["electronics", "automation"], bg=["electronicsworks", "school"],
     effects=[mod("research_speed", 20)], desc="计算机、研究型大学、现代行政中心。")
tech("solar_wind", "新能源", 4, 200000, prereq=["power_grid"], bg=["hydroplant"], desc="风电场。")

# 研究造价的整体倍率（节奏：全托管·均衡大约 1680—1740 年进入第二时代，比世界晚几十年；
# 用心经营的玩家能追上，甚至领先）。上面各项写的是相对大小，这里统一放大。
COST_SCALE = {1: 2.8, 2: 3.4, 3: 2.5, 4: 2.5}
for _t in T:
    _t["cost"] = int(round(_t["cost"] * COST_SCALE[_t["era"]] / 1000.0)) * 1000

# ════════════════════════════ 时代 ════════════════════════════════════════
# need：进入该时代的门槛。techs 全部完成；buildings 按类型累计级数；social 为社会条件。
ERAS = [
    dict(id=1, name="农商", subtitle="土地、水利、手工业与互市", art="assets/eras/e01/era01_agriculture.png",
         need={}),
    dict(id=2, name="工场与商路", subtitle="水力工场、钱庄票号、运河与远洋商路",
         art="assets/eras/e01/era02_commerce.png",
         need={"techs": ["water_power", "bookkeeping", "banking"],
               "buildings": {"watermill": 8, "port": 8},
               "social": {"literacy": 0.18}}),
    dict(id=3, name="蒸汽与铁路", subtitle="煤铁、钢、机械、铁路与城市", art="assets/eras/e01/era04_industry.png",
         need={"techs": ["steam_engine", "coke_smelting"],
               "buildings": {"steamplant": 4, "cokeworks": 3},
               "social": {"urban": 0.14}}),
    dict(id=4, name="电气与现代国家", subtitle="电力、化工、汽车、电子与福利国家",
         art="assets/eras/e01/era05_electricity.png",
         need={"techs": ["power_grid", "internal_combustion"],
               "buildings": {"powerplant": 6, "electricalworks": 2},
               "social": {"literacy": 0.6}}),
]

# 时代更替时旧生产方式的落后：每年相对新方式少产多少（百分数），封顶。
OBSOLESCENCE = dict(per_year=1.5, cap=15)

# ════════════════════════════ 政令 ════════════════════════════════════════
# kind：toggle（开关）、level（档位，levels 列出各档名）、campaign（一次性运动，duration 季）。
# cost_once / cost_q：两。support：各阶层民心变化（点）。effects：按档位给出（toggle 与 campaign 只有一档）。
D = []


def decree(id, name, era, kind, desc, tech=None, levels=None, default=0, cost_once=0, cost_q=0, duration=0,
           effects=None, support=None, cooldown=8, exclusive=None, era_end=4):
    D.append(dict(id=id, name=name, era=era, era_end=era_end, kind=kind, desc=desc, tech=tech,
                  levels=levels or [], default=default, cost_once=cost_once, cost_q=cost_q,
                  duration=duration, effects=effects or [], support=support or [], cooldown=cooldown,
                  exclusive=exclusive))


decree("land_survey", "清丈田亩", 1, "campaign", tech="survey", duration=8, cost_once=300000, cost_q=50000,
       effects=[[mod("hidden_cut", 9)]], support=[{"gentry": -12, "peasant": 3}],
       desc="派员逐县丈量田亩，八季内把隐田追回七成。士绅不满，农户略喜。")
decree("single_whip", "一条鞭法", 1, "toggle", tech="bookkeeping",
       effects=[[mod("land_tax_eff", 12), mod("admin_cost", -5)]], support=[{"peasant": 5, "gentry": -3}],
       desc="赋役合并、折银征收：田赋征收率 +12%，吏员开支 −5%。")
decree("ever_normal_granary", "常平仓", 1, "toggle", tech="granary_system", cost_q=20000,
       effects=[[mod("granary_ops", 1)]], support=[{"peasant": 4}],
       desc="粮价低于基准时官府收储，高于基准时平价出粜，需要粮仓。")
decree("sea_policy", "海禁与开海", 1, "level", levels=["海禁", "限开", "开海"], default=1,
       effects=[[mod("sea_trade_cap", -70), mod("customs_eff", -40)], [], [mod("sea_trade_cap", 60), mod("invest_prop", 5)]],
       support=[{"merchant": -10, "gentry": 5}, {}, {"merchant": 10, "gentry": -5}],
       desc="海禁时海上贸易只剩三成；开海时海港能力 +60%，商贾欢迎、士绅疑虑。")
decree("commerce_policy", "农商取向", 1, "level", levels=["重农抑商", "农商并重", "恤商惠工"], default=1,
       effects=[[mod("invest_prop", -40), mod("farm_yield", 3)], [], [mod("invest_prop", 40), mod("commerce_cap", 10)]],
       support=[{"merchant": -10, "gentry": 5, "peasant": 2}, {}, {"merchant": 10, "gentry": -5, "artisan": 3}],
       desc="决定民间投资的意愿：重农抑商时民间投资减四成，恤商惠工时增四成。")
decree("salt_policy", "盐政", 1, "level", levels=["商销", "官督商销", "官卖"], default=1,
       effects=[[mod("salt_tax_eff", -40)], [], [mod("salt_tax_eff", 50), mod("salt_markup", 40)]],
       support=[{"merchant": 5, "peasant": 3}, {}, {"peasant": -8, "merchant": -5}],
       desc="官卖时盐课增五成，但盐价上涨四成、私盐与民怨随之而来。")
decree("famine_relief", "赈济", 1, "toggle", cost_q=10000,
       effects=[[mod("relief", 1)]], support=[{"peasant": 3}],
       desc="口粮不足的地区由官府买粮发放；花费随灾情而定。")
decree("promote_schools", "兴学", 1, "toggle", cost_q=30000,
       effects=[[mod("literacy_rate", 25), mod("edu_eff", 15)]], support=[{"gentry": 4}],
       desc="资助书院与乡学：识字率增长加快，学舍效果 +15%。")
decree("foreign_learning", "遣使译书", 1, "toggle", tech="navigation", cost_q=40000,
       effects=[[mod("research_foreign", 50), mod("relation_all", 5)]], support=[{"gentry": -3, "merchant": 3}],
       desc="派使节、译西书：从伙伴那里学来的科技研究加速 +50%。")
decree("tea_horse", "茶马互市", 1, "toggle",
       effects=[[mod("export_price", 30, "partner:inland_khanate:tea"), mod("import_price", -30, "partner:inland_khanate:draft_animal"),
                 mod("relation", 10, "inland_khanate")]],
       support=[{"merchant": 2}], desc="以茶易马：卖给内陆汗国的茶叶加价三成，买役畜便宜三成。")
decree("sell_titles", "捐纳", 1, "campaign", duration=4, effects=[[mod("title_sales", 1)]],
       support=[{"gentry": 4, "peasant": -4, "merchant": 2}], cooldown=24,
       desc="出售功名官衔，四季内多收一笔银子，但伤合法性。")
decree("corvee_works", "征发徭役", 1, "campaign", duration=8, effects=[[mod("construction_cost", -25)]],
       support=[{"peasant": -8}], cooldown=16,
       desc="征发民夫修筑官办工程：八季内官办建设成本 −25%，农户不满。")
decree("reclamation", "招民垦荒", 1, "campaign", duration=8, cost_once=200000, cost_q=30000,
       effects=[[mod("reclaim", 1)]], support=[{"peasant": 3}], cooldown=16,
       desc="开垦林地为旱地：八季内各地区旱地增加约一成，林地相应减少。")
decree("tax_remission", "蠲免钱粮", 1, "campaign", duration=4, effects=[[mod("land_tax_eff", -50)]],
       support=[{"peasant": 10, "gentry": 3}], cooldown=16,
       desc="四季内田赋减半，民心大振，国库吃紧。")

# 第二时代
decree("banking_license", "钱庄准入", 2, "toggle", tech="banking",
       effects=[[mod("invest_prop", 20), mod("interest_rate", -30)]], support=[{"merchant": 6, "gentry": -2}],
       desc="准许钱庄票号：民间投资意愿 +20%，官府借债利息 −30%。")
decree("industrial_charter", "工场特许", 2, "toggle", tech="water_frame",
       effects=[[mod("invest_workshop", 30)]], support=[{"merchant": 5, "artisan": 3, "gentry": -3}],
       desc="准许民间开办大型工场：作坊类投资意愿 +30%。")
decree("official_press", "官办书局", 2, "toggle", tech="movable_type", cost_q=40000,
       effects=[[mod("literacy_rate", 20), mod("research_speed", 8)]], support=[{"gentry": 3}],
       desc="官府刊印书籍：识字率增长加快，研究 +8%。")
decree("navigation_act", "航海条例", 2, "toggle", tech="ocean_navigation",
       effects=[[mod("sea_trade_cap", 20), mod("export_price", 8, "sea")]], support=[{"merchant": 4}],
       desc="本国货物由本国船只承运：港口能力 +20%，海运出口价 +8%。")

# 第三时代
decree("factory_act", "工厂法", 3, "toggle", tech="steam_engine",
       effects=[[mod("unrest", -20, "artisan"), mod("workshop_labor", 5)]], support=[{"artisan": 10, "merchant": -5}],
       desc="限制工时、改善工人待遇：工匠不满减少，作坊用工 +5%。")
decree("railway_policy", "铁路经营", 3, "level", tech="railway", levels=["民营", "官督商办", "国有"], default=1,
       effects=[[mod("invest_prop", 10)], [], [mod("logistics_cut_all", 2)]],
       support=[{"merchant": 5}, {}, {"merchant": -5, "peasant": 2}],
       desc="铁路交给谁经营：民营时民间投资更积极，国有时全国物流成本再降 2 个百分点。")
decree("income_tax", "所得税", 3, "toggle", tech="telegraph",
       effects=[[mod("income_tax", 1)]], support=[{"merchant": -6, "gentry": -6}],
       desc="开征所得税：按商贾、士绅收入的一成征收。")
decree("protective_tariff", "保护关税", 3, "toggle",
       effects=[[mod("tariff", 100), mod("export_price", -5, "all")]], support=[{"artisan": 4, "merchant": -2}],
       desc="进口关税翻倍，保护本国工场，出口略受报复。")
decree("compulsory_school", "初等义务教育", 3, "toggle", tech="public_education", cost_q=150000,
       effects=[[mod("literacy_rate", 60)]], support=[{"artisan": 3, "peasant": 3}],
       desc="儿童必须入学：识字率增长大幅加快。")

# 第四时代
decree("central_bank", "中央银行", 4, "toggle", tech="electrochemistry",
       effects=[[mod("interest_rate", -40), mod("price_stability", 1)]], support=[{"merchant": 3}],
       desc="统一货币与信贷：借债利息 −40%，物价更稳。")
decree("social_insurance", "社会保险", 4, "toggle", cost_q=300000,
       effects=[[mod("pension", 1), mod("unrest", -30, "all")]], support=[{"artisan": 8, "peasant": 6}],
       desc="养老、失业与医疗保险：各阶层不满大减，财政负担显著。")
decree("environment_law", "环境保护法", 4, "toggle", effects=[[mod("pollution_cut", 50), mod("workshop_cost", 5)]],
       support=[{"gentry": 4, "merchant": -3}], desc="限制排放：污染事件减半，工厂成本 +5%。")

# ════════════════════════════ 贸易伙伴 ════════════════════════════════════
# dev：开局发展度（1.55 表示第一时代、离第二时代还差 45%）；rate：每年基础增长；
# route：sea 海路 / land 陆路；appear：出现的世界年份区间（由世界进程决定具体年份）。
# wants / offers：商品 → [价格系数, 每季上限（单位）]。
PARTNERS = [
    dict(id="north_ports", name="北方海港诸邦", route="sea", dev=1.56, rate=0.0080, relation=10,
         art="assets/partners/partner_north_ports.png",
         desc="北方海上的城邦联盟，航海与商业发达，掌握复式记账、海图与钱庄。",
         wants={"silk": [1.5, 30000], "porcelain": [1.6, 400000], "tea": [1.4, 6000], "sugar": [1.3, 20000]},
         offers={"tools": [1.1, 60000], "pig_iron": [1.15, 12000], "glass": [1.2, 8000], "books": [1.3, 2000],
                 "machinery": [1.3, 400], "steel": [1.2, 3000], "chemicals": [1.3, 3000]}),
    dict(id="south_isles", name="南洋列岛", route="sea", dev=1.12, rate=0.0060, relation=0,
         art="assets/partners/partner_south_isles.png",
         desc="南方群岛，盛产木材、稻米与香料，需要布匹、铁器与盐。",
         wants={"fabric": [1.2, 400000], "tools": [1.3, 30000], "salt": [1.2, 30000], "porcelain": [1.2, 200000]},
         offers={"timber": [0.9, 30000], "rice": [0.9, 150000], "fruit": [0.9, 60000], "spices": [1.0, 3000],
                 "sugar": [0.9, 20000], "rubber": [1.0, 4000], "copper": [1.1, 1500]}),
    dict(id="inland_khanate", name="内陆汗国", route="land", dev=1.05, rate=0.0050, relation=5,
         art="assets/partners/partner_inland_khanate_v2.png",
         desc="西部草原上的汗国，出役畜、羊毛与皮张，渴求茶叶、布匹与盐。",
         wants={"tea": [1.6, 5000], "fabric": [1.2, 200000], "salt": [1.3, 25000], "silk": [1.2, 8000]},
         offers={"draft_animal": [0.8, 4000], "wool": [0.8, 6000], "hides": [0.8, 10000], "meat": [0.9, 8000]}),
    dict(id="oceanic_league", name="远洋商会", route="sea", dev=1.9, rate=0.0085, relation=0, appear_era=2,
         art="assets/partners/partner_oceanic_league.png",
         desc="从大洋彼岸驶来的商会，带来香料、咖啡与新式器物，也要丝、瓷、茶、糖。",
         wants={"silk": [1.7, 40000], "porcelain": [1.7, 500000], "tea": [1.6, 10000], "sugar": [1.4, 40000],
                "cotton": [1.2, 40000]},
         offers={"spices": [1.0, 8000], "coffee": [1.0, 8000], "glass": [1.1, 10000], "machinery": [1.2, 800],
                 "chemicals": [1.2, 5000], "rubber": [1.0, 8000]}),
    dict(id="industrial_power", name="新兴工业国", route="sea", dev=2.6, rate=0.0100, relation=0, appear_era=3,
         art="assets/partners/partner_industrial_power.png",
         desc="率先完成工业化的强国，出售机器、钢铁与化学品，大量收购原料。",
         wants={"cotton": [1.3, 80000], "silk_thread": [1.4, 8000], "tea": [1.3, 12000], "coal": [1.1, 300000],
                "iron_ore": [1.1, 200000]},
         offers={"machinery": [1.1, 3000], "steel": [1.05, 20000], "chemicals": [1.1, 20000], "rail": [1.1, 8000],
                 "electric_motor": [1.2, 1000], "automobile": [1.2, 500]}),
    dict(id="alliance_bloc", name="联盟集团", route="sea", dev=3.5, rate=0.0110, relation=0, appear_era=4,
         art="assets/partners/partner_alliance_bloc.png",
         desc="战后结成的经济联盟，出售石油、电子与汽车，收购轻工产品与食品。",
         wants={"clothing": [1.3, 300000], "preserved_food": [1.3, 200000], "porcelain": [1.3, 600000],
                "appliances": [1.2, 30000]},
         offers={"crude_oil": [1.0, 100000], "refined_fuel": [1.05, 60000], "electronic_parts": [1.1, 20000],
                 "computer": [1.3, 2000], "automobile": [1.1, 3000], "plastic": [1.05, 5000]}),
]

# 伙伴掌握科技的顺序（发展度越高，掌握越多）；每个时代按列表顺序逐项掌握。
TECH_ORDER = {
    1: ["bookkeeping", "navigation", "harbor_works", "movable_type", "crop_rotation", "water_management",
        "craft_guild", "survey", "herbal_medicine", "granary_system", "water_power"],
    2: ["banking", "ocean_navigation", "glassmaking", "coal_iron", "flying_shuttle", "water_frame",
        "chemistry_basic", "sugar_refining", "canal_engineering", "double_cropping", "precision_mechanics",
        "steam_principle"],
    3: ["steam_engine", "coke_smelting", "bessemer", "railway", "machine_tools", "telegraph", "chemistry",
        "cement", "canning", "public_health", "public_education", "fertilizer", "sericulture_science", "dynamo",
        "internal_combustion"],
    4: ["power_grid", "electrochemistry", "internal_combustion", "petrochemistry", "automobile", "electronics",
        "antibiotics", "mechanized_farming", "television", "automation", "computing", "solar_wind"],
}

# ════════════════════════════ 地标 ════════════════════════════════════════
# kind：achievement（第一时代成就地标，满足条件即可建）/ leading（第二至第四时代，引领时一座完整版）。
# effects_full / effects_lite（降级版）。eraband：带时代标签的加成，进入 eraband+2 时代后 10 年内失效。
L = []


def landmark(id, name, era, kind, cost, effects, desc, art, need=None, eraband=0, convert=None, build_q=12,
             lite=None):
    L.append(dict(id=id, name=name, era=era, kind=kind, cost=cost, effects_full=effects,
                  effects_lite=lite if lite is not None else [dict(m, value=m["value"] / 2) for m in effects],
                  desc=desc, art=art, need=need or {}, eraband=eraband, convert=convert, build_q=build_q))


LA = "assets/landmarks/"
landmark("imperial_exam_hall", "贡院", 1, "achievement", 1_500_000,
         [mod("admin_eff", 10), mod("support", 5, "gentry"), mod("literacy_rate", 20)],
         "科举考场。治理效率 +10%，士绅民心 +5，识字率增长加快。进入第三时代十年后作用消失，那时可以改成新式学堂，或留作古迹。",
         LA + "l02/landmark_imperial_exam_hall_v2.png", need={"techs": ["movable_type"], "literacy": 0.11}, eraband=1,
         convert={"to": "school", "levels": 3})
landmark("astronomical_observatory", "古天象台", 1, "achievement", 1_000_000,
         [mod("research_speed", 10), mod("disaster_cut", 20)],
         "观天测候、修订历法。研究 +10%，天灾损失 −20%。", LA + "l02/landmark_astronomical_observatory.png",
         need={"tech_count": 6})
landmark("great_public_granary", "公共义仓总库", 1, "achievement", 1_200_000,
         [mod("relief_eff", 50), mod("support", 3, "peasant")],
         "全国义仓的总库。赈济效果 +50%，农户民心 +3。", LA + "l02/landmark_great_public_granary_v2.png",
         need={"buildings": {"granary": 4}})

landmark("grand_canal_hub", "大运河枢纽", 2, "leading", 3_000_000, [mod("logistics_cut_all", 4)],
         "南北漕运的总枢纽。全国物流成本 −4 个百分点（降级版 −2）。", LA + "landmark_grand_canal_hub.png")
landmark("merchant_exchange", "通商会馆", 2, "leading", 2_500_000,
         [mod("sea_trade_cap", 25), mod("land_trade_cap", 25), mod("support", 5, "merchant")],
         "各地商帮的总会馆。海陆贸易能力 +25%，商贾民心 +5。", LA + "l02/landmark_merchant_exchange.png")
landmark("public_archive", "国家档案馆", 2, "leading", 2_200_000,
         [mod("admin_eff", 15), mod("hidden_growth", -50)],
         "户籍田册的总档。治理效率 +15%，隐田增长减半。", LA + "l02/landmark_public_archive.png")
landmark("maritime_lighthouse", "海岬大灯塔", 2, "leading", 2_000_000,
         [mod("sea_trade_cap", 20), mod("disaster_cut", 10, "haijia")],
         "照亮海岬航道。海港能力 +20%，海岬台风损失 −10%。", LA + "l02/landmark_maritime_lighthouse_v3.png")
landmark("mountain_aqueduct", "西岭引水渠", 2, "leading", 2_400_000, [mod("farm_yield", 20, "xiling")],
         "穿山引水灌溉西岭。西岭农田 +20%。", LA + "l02/landmark_mountain_aqueduct.png")

landmark("world_exposition", "万国博览馆", 3, "leading", 6_000_000,
         [mod("export_price", 10, "all"), mod("literacy_rate", 20), mod("prestige", 10)],
         "向世界展示本国工艺。出口价格 +10%，识字率增长加快。", LA + "landmark_world_exposition.png")
landmark("central_rail_terminal", "中央铁路总站", 3, "leading", 5_500_000,
         [mod("logistics_cut_all", 3), mod("migration", 30)],
         "全国铁路的总站。物流成本 −3 个百分点，人口流动更顺畅。", LA + "l02/landmark_central_rail_terminal.png")
landmark("technical_university", "国家工科大学", 3, "leading", 5_000_000,
         [mod("research_speed", 15), mod("skill_up", 30)],
         "培养工程师。研究 +15%，工匠与士人成长更快。", LA + "l03/landmark_technical_university.png")
landmark("great_dry_dock", "国家大船坞", 3, "leading", 5_000_000,
         [mod("sea_trade_cap", 30), mod("ships_output", 40)],
         "建造远洋巨轮。海港能力 +30%，船只产量 +40%。", LA + "l03/landmark_great_dry_dock.png")
landmark("transregional_viaduct", "跨谷铁路大桥", 3, "leading", 4_500_000, [mod("logistics_cut", 6, "xiling")],
         "打通西岭铁路。西岭物流成本 −6 个百分点。", LA + "l02/landmark_transregional_viaduct_v2.png")

landmark("national_academy", "国家科学院", 4, "leading", 12_000_000, [mod("research_speed", 25), mod("prestige", 10)],
         "全国科学研究的中枢。研究 +25%。", LA + "landmark_national_academy.png")
landmark("hydroelectric_dam", "跨江水电枢纽", 4, "leading", 14_000_000,
         [mod("electricity_bonus", 20), mod("disaster_cut", 20)],
         "拦江发电、防洪。全国电力 +20%，水灾损失 −20%。", LA + "l03/landmark_hydroelectric_dam.png")
landmark("computing_institute", "国家计算中心", 4, "leading", 11_000_000,
         [mod("research_speed", 15), mod("admin_eff", 20)],
         "国家的计算中枢。研究 +15%，治理效率 +20%。", LA + "l03/landmark_computing_institute.png")
landmark("international_air_terminal", "国际航空站", 4, "leading", 10_000_000,
         [mod("export_price", 8, "all"), mod("relation_all", 10)],
         "通往世界的空中门户。出口价格 +8%，与各伙伴关系 +10。", LA + "l03/landmark_international_air_terminal.png")
landmark("national_broadcast_house", "国家广播大楼", 4, "leading", 9_000_000,
         [mod("support", 6, "all"), mod("literacy_rate", 20)],
         "全国广播中心。各阶层民心 +6。", LA + "l03/landmark_national_broadcast_house.png")

# ════════════════════════════ 事件 ════════════════════════════════════════
# when：触发条件（全部满足）；metric 由模拟核心解释，见 jc_events.gd。
# region：pick 表示从满足条件的地区里按随机数挑一个；none 表示全国事件。
# options：每个选项的 cost（两）、effects（修正，duration 季）、support（民心）、text。
E = []


def event(id, name, era, era_end, when, options, text, art=None, region="none", chance=0.08, cooldown=16):
    E.append(dict(id=id, name=name, era=era, era_end=era_end, when=when, options=options, text=text, art=art,
                  region=region, chance=chance, cooldown=cooldown))


def opt(text, cost=0, effects=(), support=None, duration=8, goods=None):
    return dict(text=text, cost=cost, effects=list(effects), support=support or {}, duration=duration,
                goods=goods or {})


EA = "assets/events/"
event("drought", "旱季水井", 1, 2, [["harvest", "<", 0.85]],
      [opt("开仓放粮、打井抗旱", cost=250000, effects=[mod("unrest", -30)], support={"peasant": 4}),
       opt("减免当地田赋", effects=[mod("land_tax_eff", -40)], support={"peasant": 3, "gentry": 1}, duration=4),
       opt("听其自然", support={"peasant": -6})],
      "{region}久旱，井水见底，秋粮减收。", art=EA + "ev01/event_drought_wells.png", region="pick", chance=0.6,
      cooldown=8)
event("flood", "河水漫田", 1, 2, [["flood", ">", 0]],
      [opt("拨款修堤、安置灾民", cost=300000, effects=[mod("unrest", -30)], support={"peasant": 4}),
       opt("征发民夫抢修", effects=[mod("unrest", 10)], support={"peasant": -3}, duration=4),
       opt("听其自然", support={"peasant": -6})],
      "大河决口，{region}良田被淹。", art=EA + "ev01/event_flooded_fields.png", region="pick", chance=0.7, cooldown=8)
event("harvest_fair", "秋收集市", 1, 2, [["harvest", ">", 1.05]],
      [opt("官府出资办庙会", cost=60000, effects=[mod("unrest", -20)], support={"peasant": 3, "merchant": 2}),
       opt("趁丰年多收田赋", effects=[mod("land_tax_eff", 10)], support={"peasant": -3}, duration=4)],
      "{region}五谷丰登，四乡八镇齐赶秋集。", art=EA + "ev01/event_harvest_fair.png", region="pick", chance=0.25)
event("merchant_convoy", "山路商队", 1, 2, [["relation", ">", 0, "inland_khanate"]],
      [opt("派兵护送、减免过路钱", cost=80000, effects=[mod("land_trade_cap", 20)], support={"merchant": 4}, duration=12),
       opt("照常征税", effects=[mod("customs_eff", 10)], support={"merchant": -2}, duration=8)],
      "西去汗国的驼队请求官府护送山路。", art=EA + "ev01/event_merchant_convoy.png", chance=0.06)
event("craft_dispute", "停工的作坊", 1, 2, [["unemployment", ">", 0.06, "artisan"]],
      [opt("调解工钱，官府补贴一半", cost=120000, effects=[mod("unrest", -25, "artisan")], support={"artisan": 5}),
       opt("责令复工", effects=[mod("unrest", 20, "artisan")], support={"artisan": -6, "merchant": 3})],
      "{region}作坊工匠因欠薪罢工，街市冷清。", art=EA + "ev01/event_craft_dispute.png", region="pick", chance=0.3)
event("school_opening", "乡学开馆", 1, 2, [["literacy", "<", 0.2]],
      [opt("官府资助乡学", cost=150000, effects=[mod("literacy_rate", 40)], support={"gentry": 3, "peasant": 2}, duration=16),
       opt("由士绅自办", support={"gentry": 1})],
      "{region}士绅集资办乡学，请求官府资助。", art=EA + "ev01/event_school_opening.png", region="pick", chance=0.05)
event("locusts", "蝗灾", 1, 3, [["staple_sat", "<", 1.1]],
      [opt("悬赏捕蝗", cost=120000, effects=[mod("farm_yield", -10)], duration=2),
       opt("听其自然", effects=[mod("farm_yield", -30)], support={"peasant": -4}, duration=2)],
      "{region}飞蝗蔽日，禾苗被啃食殆尽。", region="pick", chance=0.02)
event("epidemic", "疫病流行", 1, 3, [["sanitation", "<", 0.5]],
      [opt("设药局、施药", cost=200000, effects=[mod("mortality", 20)], support={"peasant": 3}, duration=4),
       opt("封锁城门", effects=[mod("mortality", 40), mod("commerce_cap", -30)], duration=4),
       opt("听其自然", effects=[mod("mortality", 80)], support={"peasant": -5}, duration=4)],
      "{region}疫气流行，死者相枕。", region="pick", chance=0.03)
event("typhoon", "台风过境", 1, 4, [["region", "=", "haijia"]],
      [opt("拨款重建港口与盐田", cost=250000, support={"merchant": 3}),
       opt("由商户自行修复", effects=[mod("sea_trade_cap", -30)], support={"merchant": -3}, duration=4)],
      "强台风登陆海岬，港口与盐田受损。", region="pick", chance=0.04)
event("bandits", "流民与盗匪", 1, 3, [["unrest", ">", 0.35]],
      [opt("招抚流民、以工代赈", cost=200000, effects=[mod("unrest", -40)], support={"peasant": 4}),
       opt("派兵剿办", cost=100000, effects=[mod("unrest", -20)], support={"peasant": -3, "gentry": 3})],
      "{region}流民啸聚山林，劫掠商旅。", region="pick", chance=0.5, cooldown=8)
event("silver_drain", "银荒", 1, 2, [["silver_flow", "<", 0]],
      [opt("鼓励出口、限制奢侈进口", effects=[mod("tariff", 50)], support={"merchant": -3}, duration=8),
       opt("铸造铜钱应急", cost=0, effects=[mod("price_level", 5)], duration=8)],
      "白银持续外流，市面银根紧缩。", chance=0.15, cooldown=16)
event("border_raid", "边警", 1, 3, [["defense", "<", 0.8]],
      [opt("增兵戍边", cost=300000, support={"peasant": -2, "gentry": 2}),
       opt("遣使议和、互市安抚", cost=150000, effects=[mod("relation", 10, "inland_khanate")]),
       opt("坚守不出", effects=[mod("unrest", 20)], support={"peasant": -4}, duration=8)],
      "北原边境有游骑袭扰村落。", region="none", chance=0.1, cooldown=12)
# 第二时代
event("canal_opening", "运河通航", 2, 3, [["building", ">", 0, "canal"]],
      [opt("大办通航典礼", cost=80000, effects=[mod("unrest", -20)], support={"merchant": 4}),
       opt("低调通航", support={})],
      "新开运河首次通航，漕船鱼贯而过。", art=EA + "ev02/event_canal_opening_v2.png", chance=0.5, cooldown=40)
event("crop_innovation", "新作物试种", 2, 3, [["tech", "=", 1, "crop_rotation"]],
      [opt("官府推广新种", cost=120000, effects=[mod("farm_yield", 5)], duration=40, support={"peasant": 2}),
       opt("任民自便", support={})],
      "有农户从海外引种高产作物，请求官府推广。", art=EA + "ev02/event_crop_innovation.png", chance=0.05, cooldown=80)
event("harbor_quarantine", "港口检疫", 2, 3, [["sanitation", "<", 0.7]],
      [opt("封港检疫", effects=[mod("sea_trade_cap", -40), mod("mortality", -30)], duration=2),
       opt("照常通商", effects=[mod("mortality", 30)], duration=4)],
      "远洋船带来疫病，港口人心惶惶。", art=EA + "ev02/event_harbor_quarantine.png", chance=0.05)
event("mill_expansion", "水力工场扩建", 2, 3, [["building", ">", 3, "watermill"]],
      [opt("官府贴息扶持", cost=150000, effects=[mod("invest_workshop", 20)], duration=16, support={"merchant": 3}),
       opt("任其自筹", support={})],
      "工场主请求贴息扩建水力工场。", art=EA + "ev02/event_mill_expansion.png", chance=0.06)
event("trade_embargo", "商路受阻", 2, 3, [["relation", "<", 0, "any"]],
      [opt("遣使修好", cost=150000, effects=[mod("relation_all", 10)]),
       opt("以牙还牙", effects=[mod("tariff", 50)], support={"merchant": -3}, duration=8)],
      "一方伙伴对本国商船加征重税。", art=EA + "ev02/event_trade_embargo.png", chance=0.08)
event("warehouse_fire", "仓库火灾", 2, 3, [["building", ">", 2, "port"]],
      [opt("拨款救济商户", cost=100000, support={"merchant": 3}),
       opt("责令商户自理", support={"merchant": -3})],
      "港口货栈失火，积货付之一炬。", art=EA + "ev02/event_warehouse_fire.png", chance=0.03)
event("wood_shortage", "林木枯竭", 2, 3, [["price_ratio", ">", 1.6, "timber"]],
      [opt("封山育林", effects=[mod("forest_regrow", 50)], duration=40, support={"peasant": -2}),
       opt("鼓励改烧煤炭", effects=[mod("coal_shift", 30)], duration=40)],
      "木材价格飞涨，山林砍伐殆尽。", chance=0.3, cooldown=40)
# 第三时代
event("bank_crisis", "银根吃紧", 3, 3, [["debt_ratio", ">", 0.6]],
      [opt("官府注资钱庄", cost=600000, effects=[mod("invest_prop", 10)], duration=8),
       opt("听其倒闭", effects=[mod("invest_prop", -40)], duration=8, support={"merchant": -6})],
      "钱庄挤兑，银根骤紧。", art=EA + "ev03/event_bank_liquidity_crisis.png", chance=0.15)
event("coal_shortage", "燃料短缺", 3, 3, [["price_ratio", ">", 1.5, "coal"]],
      [opt("官府平价调煤", cost=300000, support={"artisan": 3}),
       opt("听其涨价", support={"artisan": -4})],
      "煤价飞涨，工厂停炉、城里人家断炊。", art=EA + "ev03/event_coal_shortage.png", chance=0.3)
event("industrial_exhibition", "工艺展览", 3, 3, [["building", ">", 10, "machineworks"]],
      [opt("官府主办", cost=200000, effects=[mod("research_speed", 10), mod("prestige", 3)], duration=8),
       opt("由商会承办", support={"merchant": 2})],
      "各地工场要办一场工艺展览。", art=EA + "ev03/event_industrial_exhibition_v2.png", chance=0.05)
event("health_campaign", "街区卫生整治", 3, 3, [["sanitation", "<", 0.8]],
      [opt("拨款整治街区", cost=250000, effects=[mod("mortality", -20)], duration=16),
       opt("暂缓", support={"artisan": -2})],
      "城市街区拥挤污秽，时疫频发。", art=EA + "ev03/event_public_health_campaign.png", chance=0.08)
event("railway_opening", "铁路启用", 3, 3, [["building", ">", 0, "road:rail"]],
      [opt("举行通车典礼", cost=100000, effects=[mod("unrest", -20)], support={"merchant": 3}),
       opt("低调通车", support={})],
      "第一条铁路通车。", art=EA + "ev03/event_railway_opening.png", chance=0.5, cooldown=200)
event("workers_housing", "工人住宅落成", 3, 3, [["unrest", ">", 0.2, "artisan"]],
      [opt("官府补贴工人住宅", cost=300000, effects=[mod("unrest", -30, "artisan")], support={"artisan": 5}),
       opt("由工厂自建", support={"merchant": 1, "artisan": -2})],
      "工人聚居区拥挤不堪，要求建新住宅。", art=EA + "ev03/event_workers_housing.png", chance=0.1)
# 第四时代
event("air_pollution", "工业烟霾", 4, 4, [["building", ">", 8, "powerplant"]],
      [opt("加装除尘设备", cost=800000, effects=[mod("mortality", -10)], support={"gentry": 3}),
       opt("暂不处理", effects=[mod("mortality", 10)], support={"gentry": -3, "artisan": -2})],
      "城市上空烟霾不散。", art=EA + "ev04/event_air_pollution.png", chance=0.1)
event("electrification", "乡村通电", 4, 4, [["building", ">", 4, "powerplant"]],
      [opt("官府出资拉线", cost=1000000, effects=[mod("unrest", -20, "peasant")], support={"peasant": 6}),
       opt("由电厂自筹", support={})],
      "乡村请求通电。", art=EA + "ev04/event_electrification.png", chance=0.08)
event("container_trade", "集装箱贸易", 4, 4, [["building", ">", 8, "port"]],
      [opt("投资集装箱码头", cost=1500000, effects=[mod("sea_trade_cap", 40)], duration=400),
       opt("维持现状", support={})],
      "港口可以改建集装箱码头。", art=EA + "ev04/event_container_trade.png", chance=0.05, cooldown=200)
event("computer_network", "计算机联网", 4, 4, [["tech", "=", 1, "computing"]],
      [opt("建设全国网络", cost=2000000, effects=[mod("research_speed", 15), mod("admin_eff", 15)], duration=400),
       opt("暂缓", support={})],
      "计算机可以联网了。", art=EA + "ev04/event_computer_network.png", chance=0.1, cooldown=400)
event("bridge_reconstruction", "桥梁重建", 4, 4, [["year", ">", 1950]],
      [opt("拨款重建", cost=600000, effects=[mod("logistics_cut_all", 1)], duration=400),
       opt("暂缓", effects=[mod("logistics_cut_all", -1)], duration=40)],
      "老旧桥梁年久失修。", art=EA + "ev04/event_bridge_reconstruction.png", chance=0.03, cooldown=200)
event("university_expansion", "大学扩建", 4, 4, [["literacy", ">", 0.6]],
      [opt("扩建大学", cost=1200000, effects=[mod("research_speed", 10)], duration=80, support={"gentry": 3}),
       opt("暂缓", support={"gentry": -2})],
      "大学请求扩建。", art=EA + "ev04/event_university_expansion.png", chance=0.05, cooldown=80)


# ── 事件画（Codex 第五批，docs/58 §7）：原来没有配图的七个事件 ─────────────────
EVENT_ART = {
    "locusts": EA + "ev05/event_locusts.png",
    "epidemic": EA + "ev05/event_epidemic.png",
    "typhoon": EA + "ev05/event_typhoon_v2.png",
    "bandits": EA + "ev05/event_displacement_bandits.png",
    "silver_drain": EA + "ev05/event_silver_shortage.png",
    "border_raid": EA + "ev05/event_border_alarm.png",
    "wood_shortage": EA + "ev05/event_timber_depletion.png",
}
for _e in E:
    if _e["id"] in EVENT_ART and not _e.get("art"):
        _e["art"] = EVENT_ART[_e["id"]]
