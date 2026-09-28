# -*- coding: utf-8 -*-
"""v2 开局校准：基准价、开局产能、阶层人口、收支（docs/57 §4—§6）。

经济规则与 campaign/core/jc_economy.gd 一致：
  · 市价 p；生产者在地区 r 拿到 p×(1−物流费率 L_r)，差额归本地区车马行（运费池）；
  · 居民按 p×(1+零售加价) 购买，加价归本地区集市；盐另加盐课（由买方负担）；作坊之间按 p 买卖；
  · 维护费：造价的 1.5% / 季，用来买板材、砖瓦、铁器（按价值 4:3:3）；
  · 利润 = 生产者收入 − 工钱 − 投入 − 维护 − 税（农田交田赋，作坊与矿交商税）；
  · 农田利润 45% 为地租归士绅、其余归农户；其余民营归商贾；官营与公共设施由国库负担。
两个自动校准：农林牧渔的农户用工倍数（使农户就业 ≈ 95%），各阶层非必需开支倍数（使储蓄 ≈ 目标）。
"""
import math

MARKUP = {"farm": 0.30, "mine": 0.20, "workshop": 0.18, "infra": 0.0, "public": 0.0}
MAINT_RATE = 0.015
L_AVG = 0.055
MAINT_MIX = {"lumber": 0.4, "bricks": 0.3, "tools": 0.3}
PUBLIC_FUNDED = ("public", "infra")
PRIVATE_INFRA = ("market", "carrier", "port", "caravanserai")
RENT_SHARE = 0.42
PORT_FEE = 0.03
INIT_EXPORT_SHARE = 0.5
INIT_IMPORT_SHARE = {"draft_animal": 0.35, "timber": 0.3, "tools": 0.25, "hides": 0.3, "wool": 0.3}


class Calib:
    def __init__(self, ctx):
        self.c = ctx
        self.peasant_mult = 1.0
        self.k = {r["id"]: {c: 1.0 for c in ctx.CORDER} for r in ctx.REGIONS}
        self.shares = None
        self.prices = {}
        self.prim = {}
        total = sum(r["pop"] for r in ctx.REGIONS)
        self.pop_share = {r["id"]: r["pop"] / total for r in ctx.REGIONS}
        # 可在地区之间挪动的产地份额（按农户就业率自动平衡）
        self.spread = {g: dict(v) for g, v in ctx.SPREAD.items()}
        self.flexible = ("grain", "beans", "vegetables", "oilseed", "hemp", "cotton", "timber", "charcoal",
                         "wine", "fruit", "tea", "draft_animal", "cooking_oil", "lumber", "yarn", "fabric")

    # ── 基础量 ──────────────────────────────────────────────────────────
    def wage(self, cls):
        return self.c.CID[cls]["wage"]

    def labor_of(self, b, m):
        out = {}
        for cl, n in m["labor"].items():
            if cl == "peasant" and b["category"] == "farm":
                n = n * self.peasant_mult
            out[cl] = n
        return out

    def wage_bill(self, b, m):
        return sum(n * self.wage(cl) for cl, n in self.labor_of(b, m).items())

    def cost(self, b):
        m0 = b["methods"][0]
        wb = sum(n * self.wage(cl) for cl, n in m0["labor"].items())
        return 200000.0 if wb <= 0 else b["capital"] * wb * 4

    def maint(self, b):
        return self.cost(b) * MAINT_RATE

    def tax_rate(self, b):
        gv = self.c.GOV
        if b["category"] == "farm" and b["land"] in ("paddy", "dry", "slope"):
            return gv["land_tax"] * (1 - gv["hidden_land"])
        if b["category"] in ("workshop", "mine"):
            return gv["commerce_tax"]
        return 0.0

    # ── 基准价 ──────────────────────────────────────────────────────────
    def primary(self, g, producers):
        best = None
        for bid, mid in producers.get(g, []):
            b = self.c.BID[bid]
            m = next(x for x in b["methods"] if x["id"] == mid)
            key = (m["era"], 0 if not m["tech"] else 1, len(m["out"]))
            if best is None or key < best[0]:
                best = (key, b, m)
        return (best[1], best[2]) if best else (None, None)

    def compute_prices(self, producers):
        G = self.c.GOODS
        price = {g["id"]: (g["price"] or 1.0) for g in G}
        prim = {g["id"]: self.primary(g["id"], producers) for g in G}
        for _ in range(200):
            new = dict(price)
            for g in G:
                gid = g["id"]
                if g["price"]:
                    continue
                b, m = prim[gid]
                if b is None:
                    continue
                cost = self.wage_bill(b, m) + self.maint(b) + sum(q * price[x] for x, q in m["inp"].items())
                vals = {x: q * price[x] for x, q in m["out"].items()}
                share = vals[gid] / (sum(vals.values()) or 1.0)
                unit = cost * share / m["out"][gid]
                new[gid] = unit * (1 + MARKUP.get(b["category"], 0.18)) / (1 - L_AVG) / (1 - self.tax_rate(b))
            diff = max(abs(new[k] - price[k]) / max(price[k], 1e-9) for k in price)
            price = new
            if diff < 1e-10:
                break
        self.prices, self.prim = price, prim
        return price, prim

    # ── 需要 ────────────────────────────────────────────────────────────
    def active_needs(self):
        return [n for n in self.c.NEEDS if n["era"] <= 1 <= n.get("era_end", 4)]

    def split(self, n, rid):
        avail = [g for g in n["goods"] if self.c.GID[g]["era"] <= 1]
        taste = n.get("taste", {}).get(rid)
        if taste:
            tot = sum(v for g, v in taste.items() if g in avail)
            return {g: v / tot for g, v in taste.items() if g in avail}
        return {avail[0]: 1.0}

    def need_qty(self, n, cl, rid):
        q = n["qty"][cl]
        return q if n.get("essential") else q * self.k[rid][cl]

    def consumer_price(self, g):
        p = self.prices[g] * (1 + self.c.GOV["commerce_margin"])
        if g == "salt":
            p += self.c.GOV["salt_tax"]
        return p

    def needs_cost(self, rid, cl):
        ess, non = 0.0, 0.0
        for n in self.active_needs():
            q = n["qty"][cl]
            v = sum(q * s / n["goods"][g] * self.consumer_price(g) for g, s in self.split(n, rid).items())
            if n.get("essential"):
                ess += v
            else:
                non += v
        return ess, non

    def household_demand(self, pop_rc):
        d = {}
        for rid in self.c.RORDER:
            for cl in self.c.CORDER:
                persons = pop_rc[rid][cl]
                for n in self.active_needs():
                    q = self.need_qty(n, cl, rid) * persons
                    if q <= 0:
                        continue
                    for g, s in self.split(n, rid).items():
                        d[g] = d.get(g, 0.0) + q * s / n["goods"][g]
        return d

    # ── 贸易与国家采购 ──────────────────────────────────────────────────
    def initial_trade(self):
        exp, imp = {}, {}
        for p in self.c.PARTNERS:
            if p.get("appear_era", 1) > 1:
                continue
            for g, (mult, cap) in p["wants"].items():
                if self.c.GID[g]["era"] == 1:
                    exp[g] = exp.get(g, 0.0) + cap * INIT_EXPORT_SHARE
            for g, (mult, cap) in p["offers"].items():
                if g in INIT_IMPORT_SHARE and self.c.GID[g]["era"] == 1:
                    imp[g] = imp.get(g, 0.0) + cap * INIT_IMPORT_SHARE[g]
        return exp, imp

    def trade_values(self):
        sea = land = 0.0
        for p in self.c.PARTNERS:
            if p.get("appear_era", 1) > 1:
                continue
            v = sum(cap * INIT_EXPORT_SHARE * self.prices[g] * mult for g, (mult, cap) in p["wants"].items()
                    if self.c.GID[g]["era"] == 1)
            v += sum(cap * INIT_IMPORT_SHARE.get(g, 0) * self.prices[g] * mult
                     for g, (mult, cap) in p["offers"].items() if self.c.GID[g]["era"] == 1)
            if p["route"] == "sea":
                sea += v
            else:
                land += v
        return sea, land

    def gov_goods(self, total_pop):
        gv = self.c.GOV
        soldiers = total_pop * gv["soldiers_per_capita"]
        return {"rice": soldiers * gv["soldier_ration"] * 0.5, "grain": soldiers * gv["soldier_ration"] * 0.5,
                "fabric": soldiers * gv["soldier_cloth"]}, soldiers

    # ── 产能 ────────────────────────────────────────────────────────────
    @staticmethod
    def driver(m):
        for g in ["draft_animal", "rope", "coke", "refined_fuel", "radio", "electric_motor", "candles", "beer"]:
            if g in m["out"]:
                return g
        return max(m["out"], key=lambda g: m["out"][g])

    def solve(self, final, fixed):
        GID = self.c.GID
        x = {g: final.get(g, 0.0) + fixed.get(g, 0.0) for g in GID}
        for _ in range(400):
            need = {g: final.get(g, 0.0) + fixed.get(g, 0.0) for g in GID}
            for g, q in x.items():
                if q <= 0 or GID[g]["era"] > 1:
                    continue
                b, m = self.prim[g]
                if b is None or (len(m["out"]) > 1 and g != self.driver(m)):
                    continue
                per = q / m["out"][g]
                for i, qi in m["inp"].items():
                    need[i] = need.get(i, 0.0) + per * qi
                mv = self.maint(b) * per
                for mg, sh in MAINT_MIX.items():
                    need[mg] = need.get(mg, 0.0) + mv * sh / self.prices[mg]
            diff = max(abs(need[g] - x.get(g, 0.0)) for g in need)
            x = need
            if diff < 1e-6:
                break
        return x

    def public_levels(self):
        out = {}
        for rid in self.c.RORDER:
            r = self.c.RID[rid]
            pop = r["pop"]
            out[(rid, "yamen")] = max(1, round(pop / 1_000_000 * 0.92))
            out[(rid, "school")] = max(1, round(pop / 1_600_000))
            out[(rid, "clinic")] = max(1, round(pop * 0.3 / 400_000))
            out[(rid, "urbanworks")] = max(1, round(pop * 0.22 / 800_000))
            out[(rid, "granary")] = 1
            out[(rid, "theater")] = max(1, round(pop / 3_000_000))
            out[(rid, "road")] = {"beiyuan": 3, "zhongzhou": 4, "haijia": 2, "xiling": 2}[rid]
            if rid in ("zhongzhou", "haijia"):
                out[(rid, "library")] = 1
            if r["river"]:
                out[(rid, "watermill")] = {"beiyuan": 1, "zhongzhou": 2, "xiling": 2}.get(rid, 1)
        return out

    def add_volume_infra(self, stacks, hh):
        c = self.c
        stacks = dict(stacks)
        cap_market = c.BID["market"]["effects"]["commerce"]
        cap_freight = c.BID["carrier"]["effects"]["freight"]
        cap_port = c.BID["port"]["effects"]["sea_trade"]
        cap_land = c.BID["caravanserai"]["effects"]["land_trade"]
        total_pop = sum(r["pop"] for r in c.REGIONS)
        retail = sum(q * self.prices[g] for g, q in hh.items())
        for rid in c.RORDER:
            share = c.RID[rid]["pop"] / total_pop
            stacks[(rid, "market", "market_trad")] = max(1, math.ceil(retail * share / cap_market * 1.02))
            sales = 0.0
            for (r2, bid, mid), lv in stacks.items():
                b = c.BID[bid]
                if r2 != rid or b["category"] in PUBLIC_FUNDED:
                    continue
                m = next(mm for mm in b["methods"] if mm["id"] == mid)
                sales += lv * sum(q * self.prices[g] for g, q in m["out"].items())
            fee = sales * c.RID[rid]["logistics"]
            stacks[(rid, "carrier", "carrier_animal")] = max(1, math.ceil(fee / cap_freight * 1.02))
            farm_lv = sum(lv for (r2, bid, mid), lv in stacks.items() if r2 == rid and bid in ("paddy", "dryfarm"))
            stacks[(rid, "irrigation", "irrig_canal")] = max(1, round(farm_lv * 0.35 / 25))
        sea, land = self.trade_values()
        stacks[("haijia", "port", "port_wharf")] = max(1, math.ceil(sea * 0.8 / cap_port * 1.05))
        stacks[("zhongzhou", "port", "port_wharf")] = max(1, math.ceil(sea * 0.2 / cap_port * 1.05))
        n_land = max(2, math.ceil(land / cap_land * 1.05))
        stacks[("xiling", "caravanserai", "caravan")] = math.ceil(n_land * 0.6)
        stacks[("beiyuan", "caravanserai", "caravan")] = max(1, n_land - math.ceil(n_land * 0.6))
        return stacks

    def build_initial(self):
        c = self.c
        total_pop = sum(r["pop"] for r in c.REGIONS)
        pop_share = {r["id"]: r["pop"] / total_pop for r in c.REGIONS}
        shares = self.shares or {rid: {"peasant": 0.82, "artisan": 0.1, "merchant": 0.05, "gentry": 0.03}
                                 for rid in c.RORDER}
        exp, imp = self.initial_trade()
        gov_goods, soldiers = self.gov_goods(total_pop)
        res = None
        for _ in range(40):
            pop_rc = {rid: {cl: c.RID[rid]["pop"] * shares[rid][cl] for cl in c.CORDER} for rid in c.RORDER}
            hh = self.household_demand(pop_rc)
            final = dict(hh)
            for src, sign in ((gov_goods, 1), (exp, 1), (imp, -1)):
                for g, q in src.items():
                    final[g] = final.get(g, 0.0) + sign * q
            public = self.public_levels()
            fixed = {}
            for (rid, bid), lv in public.items():
                b = c.BID[bid]
                for g, q in b["methods"][0]["inp"].items():
                    fixed[g] = fixed.get(g, 0.0) + q * lv
                mv = self.maint(b) * lv
                for mg, sh in MAINT_MIX.items():
                    fixed[mg] = fixed.get(mg, 0.0) + mv * sh / self.prices[mg]
            x = self.solve(final, fixed)
            stacks = {}
            for g, q in x.items():
                if q <= 0 or c.GID[g]["era"] > 1:
                    continue
                b, m = self.prim[g]
                if b is None or (len(m["out"]) > 1 and g != self.driver(m)):
                    continue
                levels = q / m["out"][g] * 1.02
                for rid, sh in self.spread.get(g, pop_share).items():
                    key = (rid, b["id"], m["id"])
                    stacks[key] = stacks.get(key, 0.0) + levels * sh
            for (rid, bid), lv in public.items():
                key = (rid, bid, c.BID[bid]["methods"][0]["id"])
                stacks[key] = stacks.get(key, 0.0) + lv
            ist = {k: max(1, int(round(v))) for k, v in stacks.items() if v >= 0.35}
            ist = self.add_volume_infra(ist, hh)
            labor = {rid: {cl: 0.0 for cl in c.CORDER} for rid in c.RORDER}
            for (rid, bid, mid), lv in ist.items():
                b = c.BID[bid]
                m = next(mm for mm in b["methods"] if mm["id"] == mid)
                for cl, n in self.labor_of(b, m).items():
                    labor[rid][cl] += n * lv
            for rid in c.RORDER:
                labor[rid]["peasant"] += soldiers * pop_share[rid]
            new = {}
            for rid in c.RORDER:
                pop = c.RID[rid]["pop"]
                ar = labor[rid]["artisan"] / (c.CID["artisan"]["work"] * 0.96)
                me = labor[rid]["merchant"] / (c.CID["merchant"]["work"] * 0.96)
                ge = max(labor[rid]["gentry"] / (c.CID["gentry"]["work"] * 0.9), 0.025 * pop)
                new[rid] = {"peasant": (pop - ar - me - ge) / pop, "artisan": ar / pop, "merchant": me / pop,
                            "gentry": ge / pop}
            diff = max(abs(new[r][cl] - shares[r][cl]) for r in c.RORDER for cl in c.CORDER)
            shares = {r: {cl: 0.5 * shares[r][cl] + 0.5 * new[r][cl] for cl in c.CORDER} for r in c.RORDER}
            res = dict(stacks=ist, labor=labor, x=x, hh=hh, exp=exp, imp=imp, soldiers=soldiers, pop_rc=pop_rc)
            if diff < 1e-6:
                break
        self.shares = shares
        return res

    # ── 收支 ────────────────────────────────────────────────────────────
    def accounts(self, res):
        c = self.c
        gv = c.GOV
        stacks = res["stacks"]
        inc = {rid: {cl: 0.0 for cl in c.CORDER} for rid in c.RORDER}
        rev = {"田赋": 0.0, "盐课": 0.0, "商税": 0.0, "关税": 0.0}
        exp = {"公共设施": 0.0, "基础设施": 0.0, "兵饷军需": 0.0, "宫廷": gv["court"]}
        va = {"agri": 0.0, "manu": 0.0, "energy": 0.0, "serv": 0.0}
        retail_r = {rid: 0.0 for rid in c.RORDER}
        for rid in c.RORDER:
            for cl in c.CORDER:
                persons = res["pop_rc"][rid][cl]
                for n in self.active_needs():
                    q = self.need_qty(n, cl, rid) * persons
                    for g, s in self.split(n, rid).items():
                        retail_r[rid] += q * s / n["goods"][g] * self.prices[g]
        rev["盐课"] = res["hh"].get("salt", 0.0) * gv["salt_tax"]
        sea, land = self.trade_values()
        lv_by = {}
        for (rid, bid, mid), lv in stacks.items():
            lv_by[(rid, bid)] = lv_by.get((rid, bid), 0) + lv
        port_total = sum(lv for (rid, bid), lv in lv_by.items() if bid == "port")
        cara_total = sum(lv for (rid, bid), lv in lv_by.items() if bid == "caravanserai")
        freight = {rid: 0.0 for rid in c.RORDER}
        rows = []
        for (rid, bid, mid), lv in stacks.items():
            b = c.BID[bid]
            m = next(mm for mm in b["methods"] if mm["id"] == mid)
            lab = self.labor_of(b, m)
            wages = sum(n * self.wage(cl) * lv for cl, n in lab.items())
            for cl, n in lab.items():
                inc[rid][cl] += n * self.wage(cl) * lv
            inputs = sum(q * self.prices[g] * lv for g, q in m["inp"].items())
            maint = self.maint(b) * lv
            if b["category"] in PUBLIC_FUNDED and bid not in PRIVATE_INFRA:
                exp["公共设施" if b["category"] == "public" else "基础设施"] += wages + inputs + maint
                continue
            if bid == "market":
                revenue = retail_r[rid] * gv["commerce_margin"] * lv / lv_by[(rid, bid)]
            elif bid == "port":
                revenue = sea * PORT_FEE * lv / max(port_total, 1)
            elif bid == "caravanserai":
                revenue = land * PORT_FEE * lv / max(cara_total, 1)
            elif bid == "carrier":
                revenue = None
            else:
                gross = sum(q * self.prices[g] * lv for g, q in m["out"].items())
                freight[rid] += gross * c.RID[rid]["logistics"]
                revenue = gross * (1 - c.RID[rid]["logistics"])
                va[b["sector"]] += gross - inputs - maint
            rows.append((rid, bid, b, lv, wages, inputs, maint, revenue))
        for (rid, bid, b, lv, wages, inputs, maint, revenue) in rows:
            if revenue is None:
                revenue = freight[rid] * lv / lv_by[(rid, bid)]
            tax = revenue * self.tax_rate(b)
            if tax:
                rev["田赋" if b["category"] == "farm" else "商税"] += tax
            profit = revenue - wages - inputs - maint - tax
            if b["category"] == "farm":
                inc[rid]["gentry"] += profit * RENT_SHARE
                inc[rid]["peasant"] += profit * (1 - RENT_SHARE)
            else:
                inc[rid]["merchant"] += profit
            if bid in PRIVATE_INFRA:
                va["serv"] += revenue - inputs - maint
        rev["关税"] = (sea + land) * gv["customs"]
        total_pop = sum(r["pop"] for r in c.REGIONS)
        soldiers = res["soldiers"]
        for rid in c.RORDER:
            inc[rid]["peasant"] += soldiers * c.RID[rid]["pop"] / total_pop * gv["soldier_wage"]
        exp["兵饷军需"] = soldiers * gv["soldier_wage"] + soldiers * gv["soldier_ration"] * (
            self.prices["rice"] + self.prices["grain"]) / 2 + soldiers * gv["soldier_cloth"] * self.prices["fabric"]
        inc["zhongzhou"]["gentry"] += gv["court"]
        emp = {}
        for rid in c.RORDER:
            for cl in c.CORDER:
                emp[(rid, cl)] = res["labor"][rid][cl] / max(res["pop_rc"][rid][cl] * c.CID[cl]["work"], 1)
        return inc, rev, exp, va, emp

    # ── 校准循环 ────────────────────────────────────────────────────────
    def run(self, producers, say):
        c = self.c
        target = {cl["id"]: cl["save"] for cl in c.CLASSES}
        res = None
        for outer in range(60):
            self.compute_prices(producers)
            res = self.build_initial()
            inc, rev, exp, va, emp = self.accounts(res)
            sup = sum(res["pop_rc"][r]["peasant"] * c.CID["peasant"]["work"] for r in c.RORDER)
            dem = sum(res["labor"][r]["peasant"] for r in c.RORDER)
            e_p = dem / sup
            step = (0.95 / e_p) ** 0.6
            self.peasant_mult *= step
            moved = abs(step - 1)
            # 地区之间按农户就业率挪动可挪的产地份额
            e_r = {r: res["labor"][r]["peasant"] / max(res["pop_rc"][r]["peasant"] * c.CID["peasant"]["work"], 1)
                   for r in c.RORDER}
            for g in self.flexible:
                sp = self.spread.get(g) or dict(self.pop_share)
                adj = {r: w * (e_p / e_r[r]) ** 0.35 for r, w in sp.items() if w > 0}
                tot = sum(adj.values())
                self.spread[g] = {r: v / tot for r, v in adj.items()}
            moved = max(moved, max(abs(e_r[r] / e_p - 1) for r in c.RORDER) * 0.1)
            for r in c.RORDER:
                for cl in c.CORDER:
                    y = inc[r][cl]
                    ess, non = self.needs_cost(r, cl)
                    persons = res["pop_rc"][r][cl]
                    k_new = min(3.0, max(0.1, (y * (1 - target[cl]) - ess * persons) / max(non * persons, 1e-9)))
                    moved = max(moved, abs(k_new / self.k[r][cl] - 1))
                    self.k[r][cl] = 0.5 * self.k[r][cl] + 0.5 * k_new
            if moved < 0.001:
                break
        self.compute_prices(producers)
        res = self.build_initial()
        say(f"\n校准：{outer+1} 轮；农活用工倍数 {self.peasant_mult:.3f}；非必需开支倍数（地区 × 阶层）：")
        for r in c.RORDER:
            say(f"  {c.RID[r]['name']}：" + "，".join(f"{c.CID[cl]['name']} {self.k[r][cl]:.2f}" for cl in c.CORDER))
        return res

    def report(self, res, say):
        c = self.c
        inc, rev, exp, va, emp = self.accounts(res)
        say("\n── 各地区各阶层：人口、就业、人均季收入、人均季开支（两） ──")
        cons = {}
        for rid in c.RORDER:
            for cl in c.CORDER:
                persons = res["pop_rc"][rid][cl]
                ess, non = self.needs_cost(rid, cl)
                cost = ess + non * self.k[rid][cl]
                cons[(rid, cl)] = cost
                pi = inc[rid][cl] / max(persons, 1)
                say(f"  {c.RID[rid]['name']}·{c.CID[cl]['name']}：{persons/1e4:7.1f} 万人  就业 {100*emp[(rid,cl)]:5.1f}%  "
                    f"收入 {pi:6.2f}  开支 {cost:6.2f}  储蓄 {100*(pi-cost)/max(pi,1e-9):6.1f}%")
        rt, et = sum(rev.values()), sum(exp.values())
        say("\n── 国家财政（两 / 季） ──")
        say("  收：" + "，".join(f"{k} {v/1e4:.1f} 万" for k, v in rev.items()) + f"；合计 {rt/1e4:.1f} 万")
        say("  支：" + "，".join(f"{k} {v/1e4:.1f} 万" for k, v in exp.items()) + f"；合计 {et/1e4:.1f} 万")
        say(f"  余 {(rt-et)/1e4:.1f} 万（{100*(rt-et)/max(rt,1):.0f}%）")
        say("\n── 增加值（两 / 季）：" + "，".join(f"{k} {v/1e4:.0f} 万" for k, v in va.items()) +
            f"；合计 {sum(va.values())/1e4:.0f} 万；人均年 {4*sum(va.values())/sum(r['pop'] for r in c.REGIONS):.2f} 两")
        return cons
