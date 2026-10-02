# -*- coding: utf-8 -*-
"""四百年战役 v2 内容生成与校准（docs/57）。

用法：python tools/content_v2/build.py            生成 content_v2/*.json 与校准报告
      python tools/content_v2/build.py --check    只校验、打印报告，不写文件

做五件事：
  1. 校验引用（配方里的商品、科技、政令、地标都存在）。
  2. 成本加成反推全部商品的基准价（calib.py）。
  3. 按第一时代的人口需要反推开局需要的各级产能，并按产地分布分到各地区（calib.py）。
  4. 按用工反推各阶层人口，自动校准农户用工与各阶层开支，核对收支与财政（calib.py）。
  5. 输出整数化的 JSON（数量 ×1000、钱以「厘」计、比例以 ppm 计）。
"""
import hashlib
import io
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

import goods as goods_mod  # noqa: E402
import buildings as bld_mod  # noqa: E402
import society as soc  # noqa: E402
import progress as prog  # noqa: E402
import politics as pol  # noqa: E402
from calib import Calib, MAINT_RATE, RENT_SHARE, PORT_FEE  # noqa: E402
import topology  # noqa: E402

OUT = os.path.join(ROOT, "content_v2")
REPORT = []
SCALE = 1000
PPM = 1_000_000


def say(*a):
    s = " ".join(str(x) for x in a)
    REPORT.append(s)
    print(s)


class Ctx:
    GOODS = goods_mod.G
    GID = {g["id"]: g for g in GOODS}
    BLD = bld_mod.B
    BID = {b["id"]: b for b in BLD}
    CLASSES = soc.CLASSES
    CID = {c["id"]: c for c in CLASSES}
    CORDER = soc.CLASS_ORDER
    REGIONS = soc.REGIONS
    RID = {r["id"]: r for r in REGIONS}
    RORDER = [r["id"] for r in REGIONS]
    NEEDS = soc.NEEDS
    SPREAD = soc.SPREAD
    GOV = soc.GOV
    PARTNERS = prog.PARTNERS


C = Ctx
TID = {t["id"]: t for t in prog.T}


# ════════════════════════════ 1 校验 ══════════════════════════════════════
def validate():
    errs = []
    seen = set()
    for b in C.BLD:
        if b["id"] in seen:
            errs.append("建筑 ID 重复：" + b["id"])
        seen.add(b["id"])
        mids = set()
        for m in b["methods"]:
            if m["id"] in mids:
                errs.append(f"{b['id']} 方法 ID 重复：{m['id']}")
            mids.add(m["id"])
            for g in list(m["out"]) + list(m["inp"]):
                if g not in C.GID:
                    errs.append(f"{b['id']}.{m['id']} 引用了不存在的商品 {g}")
            for c in m["labor"]:
                if c not in C.CID:
                    errs.append(f"{b['id']}.{m['id']} 引用了不存在的阶层 {c}")
            if m["tech"] and m["tech"] not in TID:
                errs.append(f"{b['id']}.{m['id']} 引用了不存在的科技 {m['tech']}")
        if b["tech"] and b["tech"] not in TID:
            errs.append(f"{b['id']} 引用了不存在的科技 {b['tech']}")
    all_mids = [m["id"] for b in C.BLD for m in b["methods"]]
    if len(all_mids) != len(set(all_mids)):
        errs.append("生产方式 ID 在不同建筑之间重复")
    for t in prog.T:
        for p in t["prereq"]:
            if p not in TID:
                errs.append(f"科技 {t['id']} 的前置 {p} 不存在")
        for x in t["bg"]:
            if x not in C.BID:
                errs.append(f"科技 {t['id']} 的国内背景 {x} 不是建筑")
    for d in prog.D:
        if d["tech"] and d["tech"] not in TID:
            errs.append(f"政令 {d['id']} 引用了不存在的科技 {d['tech']}")
    for n in soc.NEEDS:
        for g in n["goods"]:
            if g not in C.GID:
                errs.append(f"需要 {n['id']} 引用了不存在的商品 {g}")
    for p in prog.PARTNERS:
        for g in list(p["wants"]) + list(p["offers"]):
            if g not in C.GID:
                errs.append(f"伙伴 {p['id']} 引用了不存在的商品 {g}")
    for e in prog.ERAS:
        for t in e["need"].get("techs", []):
            if t not in TID:
                errs.append(f"时代 {e['id']} 的关键科技 {t} 不存在")
        for b in e["need"].get("buildings", {}):
            if b not in C.BID:
                errs.append(f"时代 {e['id']} 的标志建筑 {b} 不存在")
    for era, lst in prog.TECH_ORDER.items():
        for t in lst:
            if t not in TID:
                errs.append(f"伙伴科技顺序里 {t} 不存在")
    producers = {}
    for b in C.BLD:
        for m in b["methods"]:
            for g in m["out"]:
                producers.setdefault(g, []).append((b["id"], m["id"]))
    offered = {g for p in prog.PARTNERS for g in p["offers"]}
    for g in C.GOODS:
        if g["id"] not in producers and g["id"] not in offered:
            errs.append(f"商品 {g['id']} 既没有生产方式也没有伙伴出售")
    for n in soc.NEEDS:
        if n.get("el", 1.0) not in (0.5, 1.0, 1.5):
            errs.append(f"需要 {n['id']} 的弹性只能是 0.5、1、1.5")
    for mixes in (bld_mod.BUILD_MIX, bld_mod.MAINT_MIX):
        for era, mix in mixes.items():
            if abs(sum(mix.values()) - 1.0) > 1e-9:
                errs.append(f"第 {era} 时代的用料份额之和不是 1")
            for g in mix:
                if g not in C.GID or C.GID[g]["era"] > era:
                    errs.append(f"第 {era} 时代的用料 {g} 不存在或还没出现")
    # 产业链：每个时代的断头（产了没人要）与无源（要了没处来）
    for era in (1, 2, 3, 4):
        dead, orphan, _, _ = topology.audit(era)
        for gid, name, c in orphan:
            errs.append(f"第 {era} 时代 {name}（{gid}）有人要却没处来：{c}")
        for gid, name, c in dead:
            say(f"  提示：第 {era} 时代 {name}（{gid}）只能出口或无人要")
    if errs:
        for e in errs:
            say("✗", e)
        raise SystemExit(1)
    say(f"校验通过：商品 {len(C.GOODS)}、建筑 {len(C.BLD)}、生产方式 {len(all_mids)}、科技 {len(prog.T)}、"
        f"政令 {len(prog.D)}、伙伴 {len(prog.PARTNERS)}、地标 {len(prog.L)}、事件 {len(prog.E)}")
    return producers


# ════════════════════════════ 5 输出 ══════════════════════════════════════
def i_qty(x):
    return int(round(x * SCALE))


def i_li(x):
    return int(round(x * 1000))


def i_ppm(x):
    return int(round(x * PPM))


def write_json(name, obj):
    path = os.path.join(OUT, name)
    text = json.dumps(obj, ensure_ascii=False, indent=1)
    with io.open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text + "\n")
    return text


def _no_art(o):
    """去掉所有 art 键（配图路径），算内容哈希用。"""
    if isinstance(o, dict):
        return {k: _no_art(v) for k, v in o.items() if k != "art"}
    if isinstance(o, list):
        return [_no_art(v) for v in o]
    return o


def _politics_out():
    """政体、改革局势、外部局势（金额换成厘；cost_rev 是上季财政收入的几成，ppm）。"""
    def opt(o):
        d = dict(o)
        return d
    reforms = []
    for r in pol.REFORMS:
        to = r["to"] if isinstance(r["to"], dict) else {"any": r["to"]}
        reforms.append(dict(id=r["id"], name=r["name"], frm=r["frm"], to=to, era=r["era"], tech=r["tech"] or "",
                            quarters=r["quarters"], cost_start_li=i_li(r["cost_start"]), cost_q_li=i_li(r["cost_q"]),
                            pro=r["pro"], con=r["con"], desc=r["desc"]))
    crises = {}
    for k, c in pol.CRISES.items():
        crises[k] = dict(default=c["default"], every=c.get("every", 0), options=[opt(o) for o in c["options"]],
                         effects=mods(c["effects"]))
    return dict(regimes=[dict(id=r["id"], name=r["name"], noun=r["noun"], era=r["era"], desc=r["desc"])
                         for r in pol.REGIMES],
                reforms=reforms, reform_stages=[dict(s) for s in pol.REFORM_STAGES], crises=crises,
                pressure=dict(pol.PRESSURE))


def mods(lst):
    return [dict(target=m["target"], value=m["value"], scope=m["scope"]) for m in lst]


def export(cal, res):
    os.makedirs(OUT, exist_ok=True)
    texts = []
    prices = cal.prices
    goods_out = [dict(id=g["id"], name=g["name"], unit=g["unit"], sector=g["sector"], tier=g["tier"], era=g["era"],
                      era_end=g["era_end"], perish_ppm=i_ppm(g["perish"] / 100.0),
                      base_price_li=max(1, i_li(prices[g["id"]])), durable=g["durable"], art=g["art"] or "",
                      note=g["note"]) for g in C.GOODS]
    texts.append(write_json("goods.json", {"schema": "jc.goods", "version": 1, "goods": goods_out}))

    b_out = []
    for b in C.BLD:
        cost = cal.cost(b)
        maint = cost * MAINT_RATE if b["maint"] is None else b["maint"]
        ms = []
        for m in b["methods"]:
            lab = cal.labor_of(b, m)
            ms.append(dict(id=m["id"], name=m["name"], era=m["era"], era_end=m["era_end"], tech=m["tech"] or "",
                           out={g: i_qty(q) for g, q in m["out"].items()},
                           inp={g: i_qty(q) for g, q in m["inp"].items()},
                           labor={c: int(round(n)) for c, n in lab.items()}, water=m["water"],
                           upgrade_cost_ppm=i_ppm(m["upgrade_cost"]), upgrade_q=m["upgrade_q"],
                           eff_ppm=i_ppm(m.get("eff", 1.0)), note=m["note"]))
        b_out.append(dict(id=b["id"], name=b["name"], category=b["category"], sector=b["sector"], owners=b["owners"],
                          land=b["land"] or "", deposit=b["deposit"] or "", coast=b["coast"], cost_li=i_li(cost),
                          maint_li=i_li(maint), build_q=b["build_q"], era=b["era"], era_end=b["era_end"],
                          tech=b["tech"] or "", effects={k: int(v) for k, v in b["effects"].items()},
                          art=b["art"], methods=ms, note=b["note"]))
    texts.append(write_json("buildings.json", {
        "schema": "jc.buildings", "version": 1, "buildings": b_out,
        "maint_mix": {str(e): {g: i_ppm(v) for g, v in mix.items()} for e, mix in bld_mod.MAINT_MIX.items()},
        "build_mix": {str(e): {g: i_ppm(v) for g, v in mix.items()} for e, mix in bld_mod.BUILD_MIX.items()}}))

    classes_out = [dict(id=c["id"], name=c["name"], base_wage_li=i_li(c["wage"]), work_ppm=i_ppm(c["work"]),
                        save_ppm=i_ppm(c["save"]), buffer_ppm=i_ppm(c["buffer"]), invest=c["invest"],
                        note=c["note"]) for c in C.CLASSES]
    needs_out = []
    for n in soc.NEEDS:
        taste = {rid: {g: i_ppm(v) for g, v in t.items()} for rid, t in n.get("taste", {}).items()}
        qty = {c: i_qty(v) for c, v in n["qty"].items()}
        needs_out.append(dict(id=n["id"], name=n["name"], essential=n.get("essential", False), weight=n["weight"],
                              era=n["era"], era_end=n.get("era_end", 4), el_ppm=i_ppm(n.get("el", 1.0)),
                              own_food=n.get("own_food", False),
                              goods={g: i_ppm(v) for g, v in n["goods"].items()}, qty=qty, taste=taste))
    texts.append(write_json("society.json", {"schema": "jc.society", "version": 1, "classes": classes_out,
                                             "needs": needs_out}))

    land_used = {rid: {} for rid in C.RORDER}
    dep_used = {rid: {} for rid in C.RORDER}
    for (rid, bid, mid), lv in res["stacks"].items():
        b = C.BID[bid]
        if b["land"]:
            land_used[rid][b["land"]] = land_used[rid].get(b["land"], 0) + lv
        if b["deposit"]:
            dep_used[rid][b["deposit"]] = dep_used[rid].get(b["deposit"], 0) + lv
    regions_out = []
    for r in C.REGIONS:
        rid = r["id"]
        land = {}
        for lt in ("paddy", "dry", "slope", "forest", "pasture", "coast"):
            used = land_used[rid].get(lt, 0)
            cap = int(math.ceil(used * r["slack"].get(lt, 1.3)))
            if lt == "coast":
                cap = max(cap, r["deposit"].get("coast", 0)) if r["coast"] else 0
            land[lt] = cap
        deposit = {}
        for dk, v in r["deposit"].items():
            if dk != "coast":
                deposit[dk] = max(v, int(math.ceil(dep_used[rid].get(dk, 0) * 1.3)))
        for dk, v in dep_used[rid].items():
            deposit.setdefault(dk, int(math.ceil(v * 1.3)))
        pop = {c: int(round(res["pop_rc"][rid][c])) for c in C.CORDER}
        pop["peasant"] += r["pop"] - sum(pop.values())
        regions_out.append(dict(id=rid, name=r["name"], desc=r["desc"], river=r["river"], coast=r["coast"],
                                capital=r.get("capital", False), logistics_ppm=i_ppm(r["logistics"]),
                                logistics_start_ppm=i_ppm(cal.eff_log(rid)), rent_ppm=i_ppm(cal.rent[rid]), land=land,
                                deposit=deposit, pop=pop))
    stacks_out = []
    for (rid, bid, mid), lv in sorted(res["stacks"].items()):
        b = C.BID[bid]
        owner = "gov" if (b["category"] in ("public", "infra") and bid not in ("market", "carrier", "port",
                                                                            "caravanserai")) else "private"
        stacks_out.append(dict(region=rid, building=bid, method=mid, owner=owner, level=int(lv)))
    cons = cal.report(res, lambda *a: None)
    gv = C.GOV
    savings = {f"{rid}:{c}": i_li(cons[(rid, c)] * res["pop_rc"][rid][c] * C.CID[c]["buffer"])
               for rid in C.RORDER for c in C.CORDER}
    basket = {f"{rid}:{c}": i_ppm(cal.k[rid][c]) for rid in C.RORDER for c in C.CORDER}
    scenario = dict(schema="jc.scenario", version=1, id="campaign_v2", name="四百年战役", start_year=1600,
                    regions=regions_out, stacks=stacks_out, savings_li=savings, basket_ppm=basket,
                    gov=dict(treasury_li=i_li(gv["treasury"]), land_tax_ppm=i_ppm(gv["land_tax"]),
                             salt_tax_li=i_li(gv["salt_tax"]), commerce_tax_ppm=i_ppm(gv["commerce_tax"]),
                             customs_ppm=i_ppm(gv["customs"]), hidden_land_ppm=i_ppm(gv["hidden_land"]),
                             hidden_growth_ppm=i_ppm(gv["hidden_growth"]), soldiers=int(round(res["soldiers"])),
                             soldier_wage_li=i_li(gv["soldier_wage"]),
                             soldier_ration_milli=i_qty(gv["soldier_ration"]),
                             soldier_cloth_milli=i_qty(gv["soldier_cloth"]),
                             soldier_leather_milli=i_qty(gv["soldier_leather"]), court_li=i_li(cal.court),
                             comfort_expect_ppm=[i_ppm(v) for v in gv["comfort_expect"]],
                             relief_li=i_li(gv["relief_budget"]), commerce_margin_ppm=i_ppm(gv["commerce_margin"]),
                             rent_share_ppm=i_ppm(RENT_SHARE), port_fee_ppm=i_ppm(PORT_FEE),
                             literacy_ppm=i_ppm(0.08)),
                    initial_trade=dict(exports={g: i_qty(q) for g, q in res["exp"].items()},
                                       imports={g: i_qty(q) for g, q in res["imp"].items()}))
    texts.append(write_json("scenario.json", scenario))

    techs_out = [dict(id=t["id"], name=t["name"], era=t["era"], cost=int(t["cost"]), prereq=t["prereq"],
                      key=t["key"], bg=t["bg"], effects=mods(t["effects"]), desc=t["desc"]) for t in prog.T]
    decrees_out = [dict(id=d["id"], name=d["name"], era=d["era"], era_end=d["era_end"], kind=d["kind"],
                        desc=d["desc"], tech=d["tech"] or "", levels=d["levels"], default=d["default"],
                        cost_once_li=i_li(d["cost_once"]), cost_q_li=i_li(d["cost_q"]), duration=d["duration"],
                        effects=[mods(x) for x in d["effects"]], support=d["support"], cooldown=d["cooldown"],
                        level_era=d["level_era"], level_tech=d["level_tech"])
                   for d in prog.D]
    partners_out = [dict(id=p["id"], name=p["name"], route=p["route"], dev_ppm=i_ppm(p["dev"]),
                         rate_ppm=i_ppm(p["rate"]), relation=p["relation"], appear_era=p.get("appear_era", 1),
                         art=p["art"], desc=p["desc"],
                         wants={g: [i_ppm(v[0]), i_qty(v[1])] for g, v in p["wants"].items()},
                         offers={g: [i_ppm(v[0]), i_qty(v[1])] for g, v in p["offers"].items()})
                    for p in prog.PARTNERS]
    landmarks_out = [dict(id=l["id"], name=l["name"], era=l["era"], kind=l["kind"], cost_li=i_li(l["cost"]),
                          build_q=l["build_q"], effects_full=mods(l["effects_full"]),
                          effects_lite=mods(l["effects_lite"]), desc=l["desc"], art=l["art"], need=l["need"],
                          eraband=l["eraband"], convert=l["convert"]) for l in prog.L]
    events_out = []
    for e in prog.E:
        opts = [dict(text=o["text"], cost_li=i_li(o["cost"]), effects=mods(o["effects"]), support=o["support"],
                     duration=o["duration"]) for o in e["options"]]
        events_out.append(dict(id=e["id"], name=e["name"], era=e["era"], era_end=e["era_end"], when=e["when"],
                               options=opts, text=e["text"], art=e["art"] or "", region=e["region"],
                               chance_ppm=i_ppm(e["chance"]), cooldown=e["cooldown"]))
    texts.append(write_json("progress.json", dict(schema="jc.progress", version=1, techs=techs_out, eras=prog.ERAS,
                                                  obsolescence={"per_year_ppm": i_ppm(prog.OBSOLESCENCE["per_year"] / 100.0),
                                                                "cap_ppm": i_ppm(prog.OBSOLESCENCE["cap"] / 100.0)},
                                                  decrees=decrees_out,
                                                  partners=partners_out,
                                                  tech_order={str(k): v for k, v in prog.TECH_ORDER.items()},
                                                  landmarks=landmarks_out, events=events_out,
                                                  **_politics_out())))
    # 内容哈希不算配图：图换了、补了都不该让存档作废（存档里内容哈希对不上就要从种子重放）
    h = hashlib.sha256("\n".join(json.dumps(_no_art(json.loads(t)), ensure_ascii=False, sort_keys=True)
                                  for t in texts).encode("utf-8")).hexdigest()
    write_json("meta.json", {"schema": "jc.meta", "version": 1, "content_hash": h,
                             "files": ["goods.json", "buildings.json", "society.json", "scenario.json",
                                       "progress.json"]})
    with io.open(os.path.join(OUT, "calibration_report.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(REPORT) + "\n")
    say(f"\n已写出 {OUT}（内容指纹 {h[:12]}）")


def main():
    check_only = "--check" in sys.argv
    producers = validate()
    cal = Calib(C)
    res = cal.run(producers, say)
    say("\n── 基准价（两 / 单位）──")
    line = []
    for g in C.GOODS:
        line.append(f"{g['name']} {cal.prices[g['id']]:.3f}/{g['unit']}")
        if len(line) == 6:
            say("  " + "；".join(line))
            line = []
    if line:
        say("  " + "；".join(line))
    say("\n── 开局阶层比例 ──")
    for rid in C.RORDER:
        s = cal.shares[rid]
        say(f"  {C.RID[rid]['name']}：" + "，".join(f"{C.CID[c]['name']} {100*s[c]:.1f}%" for c in C.CORDER))
    say("\n── 开局建筑（地区 · 建筑 · 方式 · 级）──")
    for (rid, bid, mid), lv in sorted(res["stacks"].items()):
        say(f"  {C.RID[rid]['name']} · {C.BID[bid]['name']} · {mid} · {lv}")
    say(f"  共 {len(res['stacks'])} 堆，{sum(res['stacks'].values())} 级")
    cal.report(res, say)
    if not check_only:
        export(cal, res)


if __name__ == "__main__":
    main()
