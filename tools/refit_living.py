#!/usr/bin/env python3
"""生活与服务指数的基年基准（R-LIVING-01）：给 population_init 的每个群组补两项内容字段。

背景：docs/10 定义了 content.base_real_consumption_uqs（36）与 content.base_delivered_service（108），
但内容包里从未提供（加载器置 0，JWPopulation.update_living_indices 以 max(x,1) 兜底）。后果：
  - 公共服务需求恒为 0 ⇒ 交付量恒为 0 ⇒ 服务可及率恒为 0（而剧本开局写的是 100%）；
    生活指数一开局就丢掉整个「服务」权重项，支持度从第 0 季起系统性下滑；
  - 消费指数以 1 μQ 为基准，数值无意义。

取法（全部整数、最大余数法、下标决胜，可复算）：
  1. base_delivered_service_uqs[g][k]：
     各地区公共服务产能（pubserv_init.capacity_active_uqs_per_q）先按该地区的
     service_capacity_split_ppm 拆到三类服务，再按「人口 × 年龄权重」拆到本地区 9 个群组。
     基年可用率 100% 时交付量恰等于基准，可及率 == 100%，与剧本开局 service_access_ppm 一致；
     此后产能折旧或运行费欠拨 ⇒ 可及率下降。年龄权重是设计假设（见 AGE_WEIGHT）。
  2. base_real_consumption_uqs[g]：
     全国基年居民商品消费量（基年核算的居民消费 − 基年租金，按基价折成 μQ）
     按「人口 × 基年人均实际收入」拆到 36 个群组。消费指数只用于报告（不进支持度），近似即可。

用法：  python tools/refit_living.py --check | --apply
"""

from __future__ import annotations

import argparse
import io
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCEN = ROOT / "content" / "scenarios" / "chengwan"
REGIONS = ["beiyuan", "zhongzhou", "haijia", "xiling"]
KINDS = ["health", "education", "utility"]
BASE_PRICE_UU_PER_UQS = 1000  # 1e9 μU/Q ÷ 1e6 μQ/Q

# 每人服务需求的相对权重（ppm），设计假设：
#   医疗：老年 2.5 倍、未成年 0.7 倍；教育：未成年为主，成年少量培训，老年 0；公用：人人等量。
AGE_WEIGHT = {
    "health": {"minor": 700_000, "working": 1_000_000, "elder": 2_500_000},
    "education": {"minor": 1_000_000, "working": 100_000, "elder": 0},
    "utility": {"minor": 1_000_000, "working": 1_000_000, "elder": 1_000_000},
}


def split_lr(total: int, weights: list[int]) -> list[int]:
    s = sum(weights)
    if s <= 0:
        return [0] * len(weights)
    base = [total * w // s for w in weights]
    rem = [total * w - b * s for w, b in zip(weights, base)]
    left = total - sum(base)
    order = sorted(range(len(weights)), key=lambda i: (-rem[i], i))
    for i in order[:left]:
        base[i] += 1
    return base


def load(name: str) -> dict:
    return json.load(io.open(SCEN / name, encoding="utf-8"))


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, OSError):
        pass
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    if not a.apply and not a.check:
        print("必须指定 --check 或 --apply")
        return 2

    pop = load("population_init.json")
    pub = load("pubserv_init.json")
    scen = load("scenario.json")
    iot = load("io_table.json")
    groups = pop["groups"]

    def parts(gid: str) -> tuple[str, str, str]:
        _, r, age, sk = gid.split(".")
        return r, age, sk

    # ── 1) 服务基准 ─────────────────────────────────────────────────────────
    svc: dict[str, dict[str, int]] = {g["group_id"]: {} for g in groups}
    for u in pub["units"]:
        r = u["pubserv_id"].split(".")[1]
        cap = int(u["capacity_active_uqs_per_q"])
        split = u["service_capacity_split_ppm"]
        cap_k = split_lr(cap, [int(split[k]) for k in KINDS])
        members = [g for g in groups if parts(g["group_id"])[0] == r]
        for ki, k in enumerate(KINDS):
            w = [int(g["population_persons"]) * AGE_WEIGHT[k][parts(g["group_id"])[1]] for g in members]
            out = split_lr(cap_k[ki], w)
            for g, v in zip(members, out):
                svc[g["group_id"]][k] = v
        print(f"  {r}: 产能 {cap} μQ/季 → 分类 {dict(zip(KINDS, cap_k))}")

    # ── 2) 消费基准 ─────────────────────────────────────────────────────────
    acc = iot["_note_base_year_accounting"]
    c_year = int(acc["final_use_uu"]["household_consumption"]["total_uu"])
    rent = scen["prices_init"]["housing_rent_uu_per_unit_q"]
    rent_q = 0
    for g in groups:
        r = parts(g["group_id"])[0]
        rent_q += int(g["housing_units_occupied"]) * int(rent[REGIONS.index(r)])
    goods_q_uu = c_year // 4 - rent_q
    goods_q_uqs = goods_q_uu // BASE_PRICE_UU_PER_UQS
    w_inc = [int(g["population_persons"]) * int(g["base_per_capita_real_income_uu"]) for g in groups]
    cons = split_lr(goods_q_uqs, w_inc)
    print(f"  居民消费 {c_year // 4} μU/季 − 租金 {rent_q} μU/季 = 商品 {goods_q_uu} μU/季 = {goods_q_uqs} μQ/季")

    changed = 0
    for g, c in zip(groups, cons):
        new_svc = {k: svc[g["group_id"]][k] for k in KINDS}
        if g.get("base_real_consumption_uqs") != c or g.get("base_delivered_service_uqs") != new_svc:
            changed += 1
        g["base_real_consumption_uqs"] = c
        g["base_delivered_service_uqs"] = new_svc
    pop["_note_living_baselines_zh"] = (
        "R-LIVING-01（tools/refit_living.py 生成，勿手改）：base_delivered_service_uqs = 地区公共服务产能按 "
        "service_capacity_split_ppm 拆到三类服务，再按「人口 × 年龄权重」拆到本地区群组（医疗 未成年/成年/老年 = 0.7/1/2.5，"
        "教育 = 1/0.1/0，公用 = 1/1/1，设计假设）；基年可用率 100% 时交付量恰等于基准，可及率 100%，与开局 service_access_ppm 一致。"
        f"base_real_consumption_uqs = 全国基年居民商品消费（{c_year // 4} μU/季 减基年租金 {rent_q} μU/季，按基价折 μQ）"
        "按「人口 × 基年人均实际收入」拆到群组；消费指数只进报告，不进支持度。")
    print(f"  群组 {len(groups)} 个，变更 {changed} 个")
    if a.apply:
        io.open(SCEN / "population_init.json", "w", encoding="utf-8", newline="\n").write(
            json.dumps(pop, ensure_ascii=False, indent=2) + "\n")
        print("已写盘")
    else:
        g0 = groups[0]
        print("  样例", g0["group_id"], g0["base_real_consumption_uqs"], g0["base_delivered_service_uqs"])
        print("未写盘（--check）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
