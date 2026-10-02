# -*- coding: utf-8 -*-
"""v2 政治：政体、改革局势、外部局势（革命风潮、列强叩关、经济危机）。

政体沿用「政体」这道分档政令的档位（效果、民心都在那里算），但不再能直接点按钮换：
只有改革局势成功、或革命 / 政变 / 战败等外部局势，才会换政体。

金额单位：两（build.py 换成厘）。cost_rev 是「上一季财政收入的几成」（ppm），随国家大小伸缩。
"""


def mod(target, value, scope=""):
    return {"target": target, "value": value, "scope": scope}


# ════════════════════════════ 政体（顺序 = 「政体」政令的档位） ═════════════════════
# era：最早在第几时代能出现；noun：评语里用的称呼（评语另有成表的文案）。
REGIMES = [
    dict(id="empire", name="君主集权", noun="帝国", era=1, effects=[], support={},
         desc="皇帝一人独断，官僚层层执行。最稳当，也最难变。"),
    dict(id="enlightened", name="开明君主", noun="王朝", era=2,
         effects=[mod("research_speed", 5), mod("admin_eff", 3)], support={"gentry": 2, "merchant": 3},
         desc="君主肯听读书人与商贾的话：研究略快，衙门更有章法。"),
    dict(id="constitutional", name="君主立宪", noun="立宪王国", era=3,
         effects=[mod("invest_prop", 10), mod("interest_rate", -10)],
         support={"merchant": 6, "artisan": 2, "gentry": -2},
         desc="有宪法、有议会，君主保留尊位：商贾敢投资，借钱也便宜。"),
    dict(id="republic", name="议会共和", noun="共和国", era=3,
         effects=[mod("invest_prop", 15), mod("literacy_rate", 10)],
         support={"merchant": 8, "artisan": 4, "peasant": 2, "gentry": -8},
         desc="不再有君主，议会与内阁执政：商贾、工匠拥护，士绅失势。"),
    dict(id="socialist", name="社会主义", noun="工人国家", era=4,
         effects=[mod("invest_prop", -40), mod("unrest", -15, "artisan")],
         support={"artisan": 10, "peasant": 6, "merchant": -15, "gentry": -10},
         desc="国家主导生产，工人农户拥护，商贾士绅反对，民间投资大减。"),
    dict(id="merchant_republic", name="商人共和", noun="商人共和国", era=2,
         effects=[mod("invest_prop", 20), mod("customs_eff", 10), mod("export_price", 5, "all")],
         support={"merchant": 12, "artisan": 2, "peasant": -4, "gentry": -6},
         desc="富商巨贾组成议会掌国：投资与外贸兴旺，农户与士绅被冷落。"),
    dict(id="junta", name="军政府", noun="军政府", era=2,
         effects=[mod("unrest", -10), mod("admin_eff", 5), mod("research_speed", -10), mod("invest_prop", -10)],
         support={"gentry": 2, "merchant": -4, "artisan": -6, "peasant": -2},
         desc="将领掌权，枪杆子说了算：秩序好了，民怨被压下去，研究与投资都受拖累。"),
    dict(id="warlords", name="军阀割据", noun="割据之国", era=3,
         effects=[mod("admin_eff", -25), mod("tax_eff", -15), mod("land_tax_eff", -15), mod("hidden_growth", 50),
                  mod("unrest", 10), mod("invest_prop", -20)],
         support={"peasant": -6, "artisan": -6, "merchant": -6, "gentry": -6},
         desc="中央号令不出京城，各地拥兵自重：税收不上来，隐田疯长，人人不安。要「统一全国」才能结束。"),
    dict(id="one_party", name="一党执政", noun="党治国家", era=4,
         effects=[mod("invest_prop", 5), mod("research_speed", 5), mod("admin_eff", 5), mod("unrest", -5)],
         support={"artisan": 3, "peasant": 2, "merchant": -4, "gentry": -4},
         desc="一个政党统揽全局，集中力量办大事：动员力强，异议被压住。"),
    dict(id="protectorate", name="保护国", noun="保护国", era=3,
         effects=[mod("invest_prop", 10), mod("research_speed", -10), mod("export_price", -10, "all")],
         support={"merchant": 2, "artisan": -6, "peasant": -6, "gentry": -8},
         desc="战败后受列强控制：关税、外交由人做主，外国资本涌入，百姓屈辱。要「收回主权」才能结束。"),
]

# ════════════════════════════ 改革局势（主动推行） ═══════════════════════════════
# frm：从哪些政体出发；to：目标政体（{"3": .., "4": ..} 按时代；"_prev" 回到受制之前的政体）；
# quarters：民心平平时要几季推完；pro / con：拥护与反对的阶层（他们的民心决定推得快慢）。
REFORMS = [
    dict(id="enlighten", name="开明改革", frm=["empire"], to="enlightened", era=2, tech="movable_type", quarters=12,
         cost_start=200000, cost_q=30000, pro=["merchant", "gentry"], con=[],
         desc="开言路、设书局，延揽读书人与商贾议政。"),
    dict(id="merchant_rule", name="商人议政", frm=["enlightened", "constitutional"], to="merchant_republic", era=2,
         tech="banking", quarters=12, cost_start=500000, cost_q=60000, pro=["merchant"], con=["gentry", "peasant"],
         desc="让富商组成的议会掌握国政，以商立国。"),
    dict(id="constitution", name="立宪运动", frm=["empire", "enlightened"], to="constitutional", era=3, tech="telegraph",
         quarters=16, cost_start=600000, cost_q=80000, pro=["merchant", "artisan"], con=["gentry"],
         desc="制定宪法、召开议会，君主保留尊位。"),
    dict(id="republic", name="共和改制", frm=["constitutional", "enlightened", "merchant_republic"], to="republic", era=3,
         tech="public_education", quarters=16, cost_start=800000, cost_q=100000, pro=["merchant", "artisan", "peasant"],
         con=["gentry"], desc="废除君位，由议会与内阁治国。"),
    dict(id="civil_rule", name="还政于民", frm=["junta"], to="republic", era=3, tech="", quarters=12,
         cost_start=500000, cost_q=60000, pro=["merchant", "artisan"], con=["gentry"],
         desc="将领交出权力，恢复议会与选举。"),
    dict(id="restoration", name="君主复辟", frm=["republic", "junta", "warlords"], to="constitutional", era=3, tech="",
         quarters=12, cost_start=600000, cost_q=80000, pro=["gentry"], con=["merchant", "artisan"],
         desc="请回君主，以立宪之名恢复旧秩序。"),
    dict(id="unify", name="统一全国", frm=["warlords"], to={"3": "republic", "4": "one_party"}, era=3, tech="",
         quarters=16, cost_start=1200000, cost_q=200000, pro=["peasant", "artisan", "merchant"], con=["gentry"],
         desc="削平割据，重建中央号令（蒸汽时代建共和，电气时代由一党统一）。"),
    dict(id="independence", name="收回主权", frm=["protectorate"], to="_prev", era=3, tech="", quarters=20,
         cost_start=1500000, cost_q=200000, pro=["peasant", "artisan", "merchant", "gentry"], con=[],
         desc="废除不平等条约，请走外国顾问，恢复受制之前的政体。"),
    dict(id="socialism", name="社会主义改造", frm=["republic", "one_party", "junta", "constitutional"], to="socialist",
         era=4, tech="power_grid", quarters=20, cost_start=1500000, cost_q=250000, pro=["artisan", "peasant"],
         con=["merchant", "gentry"], desc="工厂、土地收归公有，由国家统一安排生产。"),
    dict(id="one_party_rule", name="一党建国", frm=["republic", "junta"], to="one_party", era=4, tech="", quarters=12,
         cost_start=1000000, cost_q=150000, pro=["artisan"], con=["merchant"],
         desc="由一个政党统揽军政，集中力量建设国家。"),
    dict(id="market", name="市场化改革", frm=["socialist"], to="one_party", era=4, tech="", quarters=16,
         cost_start=1000000, cost_q=120000, pro=["merchant", "peasant"], con=["artisan"],
         desc="放开市场、允许私营，执政党不变。"),
    dict(id="democratize", name="民主化", frm=["one_party", "socialist"], to="republic", era=4, tech="", quarters=16,
         cost_start=1000000, cost_q=120000, pro=["merchant", "gentry"], con=["artisan"],
         desc="开放党禁、举行选举。"),
]

# 改革推到三成五、七成时各有一个关口（{pro}、{con}、{reform} 由界面换成阶层名与改革名）
REFORM_STAGES = [
    dict(id="backlash", at=350000, default="compromise",
         options=[dict(id="push", progress=100000, pro=2, con=-8),
                  dict(id="compromise", progress=-100000, pro=-3, con=5),
                  dict(id="buy", progress=30000, con=2, cost_rev=300000)]),
    dict(id="rally", at=700000, default="steady",
         options=[dict(id="ride", progress=150000, pro=4, con=-4, unrest=5),
                  dict(id="steady", progress=0, pro=-2),
                  dict(id="slow", progress=-150000, pro=-5, con=4)]),
]

# ════════════════════════════ 外部局势 ══════════════════════════════════════════
# 选项的效果由模拟核心按 id 处理；数值在这里。default 是过期不决时按哪一项办。
CRISES = dict(
    revolution=dict(default="wait", every=3,
                    options=[dict(id="repress", cost_rev=400000), dict(id="concede"),
                             dict(id="appease", cost_rev=800000), dict(id="wait")],
                    effects=[mod("unrest", 10), mod("invest_prop", -20)]),
    invasion=dict(default="negotiate",
                  options=[dict(id="resist"), dict(id="negotiate"), dict(id="selfstrength", cost_rev=500000)],
                  effects=[mod("unrest", 3), mod("invest_prop", -10)]),
    war=dict(default="fight", every=4,
             options=[dict(id="fight"), dict(id="sue")],
             effects=[mod("invest_prop", -25), mod("research_speed", -10), mod("unrest", 5)]),
    depression=dict(default="let",
                    options=[dict(id="let", quarters=6, spending=-18, invest=-50),
                             dict(id="works", quarters=10, spending=-8, invest=-30, works_rev=200000),
                             dict(id="tariff", quarters=10, spending=-12, invest=-35)],
                    effects=[mod("unrest", 5, "artisan"), mod("unrest", 5, "merchant")]),
)

# ════════════════════════════ 压力与触发的数值 ══════════════════════════════════
PRESSURE = dict(
    # 革命压力（每季，ppm）：从第三时代起累积
    rev_legit_k=120000,        # 威信低于 45% 的部分 × 0.12
    rev_class_floor=300000,    # 某阶层民心低于三成时
    rev_class_k={"peasant": 60000, "artisan": 100000, "merchant": 60000, "gentry": 40000},
    rev_unemp_floor=80000, rev_unemp_k=150000,
    rev_harsh=3000, rev_depression=8000,
    rev_decay=8000, rev_legit_hi=450000, rev_legit_hi_k=150000,
    # 政体落后于时代：{政体: [第三时代, 第四时代]}
    rev_outdated={"empire": [4000, 12000], "enlightened": [0, 6000], "constitutional": [0, 2000],
                  "junta": [5000, 5000], "warlords": [10000, 10000], "protectorate": [8000, 8000]},
    # 列强压力：世界进入第三时代起累积
    for_gap_k=10000, for_weak_k=10000, for_closed=6000, for_prestige_floor=10, for_prestige_k=300,
    for_decay=6000, for_lead_k=10000,
    # 经济危机：第三时代起，每季的发生机会（ppm）
    dep_base=6000, dep_boom=8000, dep_cool_q=40,
)
