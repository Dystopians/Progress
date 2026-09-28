# -*- coding: utf-8 -*-
"""产业链拓扑检查（docs/57 §4）：每个时代里，每种商品都该有来处（生产或进口）和去处（居民、投入、国家、出口）。

用法：python tools/content_v2/topology.py      打印各时代的断头与无源商品、每种商品的上下游
build.py 在校验时调用 audit()，把「断头」与「无源」写进校准报告。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import goods as goods_mod  # noqa: E402
import buildings as bld_mod  # noqa: E402
import society as soc  # noqa: E402
import progress as prog  # noqa: E402

GOV_GOODS = {"rice", "grain", "fabric", "leather"}


def _live(x, era):
    return x.get("era", 1) <= era <= x.get("era_end", 4)


def need_goods(n, era):
    """该时代里这项需要真正会买的商品（与引擎 need_shares 一致）。"""
    if not _live(n, era):
        return set()
    gid = {g["id"]: g for g in goods_mod.G}
    out = set()
    live = [g for g in n["goods"] if gid[g]["era"] <= era <= gid[g].get("era_end", 4) + 1]
    taste = n.get("taste") or {}
    for g in live:
        if taste and any(g in t for t in taste.values()):
            out.add(g)
        elif gid[g]["era"] > 1 and taste:
            out.add(g)
    if not taste:
        seen_era = set()
        for g in live:
            e = gid[g]["era"]
            if e not in seen_era:
                seen_era.add(e)
                out.add(g)
    return out


def links(era):
    prod, cons = {}, {}
    for b in bld_mod.B:
        for m in b["methods"]:
            if not _live(m, era):
                continue
            for g in m["out"]:
                prod.setdefault(g, set()).add(b["name"])
            for g in m["inp"]:
                cons.setdefault(g, set()).add(b["name"])
    for n in soc.NEEDS:
        for g in need_goods(n, era):
            cons.setdefault(g, set()).add("居民·" + n["name"])
    for g in GOV_GOODS:
        cons.setdefault(g, set()).add("军需")
    for mixes in (bld_mod.BUILD_MIX, bld_mod.MAINT_MIX):
        for g in mixes[era]:
            cons.setdefault(g, set()).add("营造维护")
    for p in prog.PARTNERS:
        if p.get("appear_era", 1) > era:
            continue
        for g in p["wants"]:
            cons.setdefault(g, set()).add("出口·" + p["name"])
        for g in p["offers"]:
            prod.setdefault(g, set()).add("进口·" + p["name"])
    return prod, cons


def audit(era):
    gid = {g["id"]: g for g in goods_mod.G}
    prod, cons = links(era)
    dead, orphan = [], []
    for g in goods_mod.G:
        c = cons.get(g["id"], set())
        live = g["era"] <= era <= g.get("era_end", 4)
        if not live and not c:
            continue
        p = prod.get(g["id"], set())
        domestic = {x for x in c if not x.startswith("出口·")}
        made = {x for x in p if not x.startswith("进口·")}
        if live and made and not domestic:
            dead.append((g["id"], g["name"], sorted(c)))
        if c and not p:
            orphan.append((g["id"], g["name"], sorted(c)))
    return dead, orphan, prod, cons


if __name__ == "__main__":
    for era in (1, 2, 3, 4):
        dead, orphan, prod, cons = audit(era)
        print(f"\n══ 第 {era} 时代 ══")
        for gid_, name, c in dead:
            print(f"  断头（只能出口或无人要）：{name}（{gid_}）→ {c}")
        for gid_, name, c in orphan:
            print(f"  无源（有人要、没人产也买不到）：{name}（{gid_}）← {c}")
    if "-v" in sys.argv:
        dead, orphan, prod, cons = audit(4)
        for g in goods_mod.G:
            print(f"{g['name']:6s} 来自 {sorted(prod.get(g['id'], []))}  去往 {sorted(cons.get(g['id'], []))}")
