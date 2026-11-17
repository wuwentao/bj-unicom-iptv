#!/usr/bin/env python3
"""build_summary.py — 从 channel-probes/*.md 内嵌 JSON 重建合并摘要 TSV（_all_summary.tsv）。

用于 gen_table.py 生成总表。确定性字段由 iptv_classify 计算，不重新探测。
列：key addr name connect 画质 分辨率 动态范围 扫描 建议标识 视频 音频 service provider 截图
"""
import glob
import json
import re

from iptv_classify import summarize

PROBE_DIR = "channel-probes"
OUT = "channel-probes/_all_summary.tsv"

JSON_RE = re.compile(r"```json\n(.*?)\n```", re.DOTALL)
NAME_RE = re.compile(r"频道名称\(hint·需人工/台标\) \| (.*?) \|")
SHOT_RE = re.compile(r"截图 \| (.*?) \|")


def main():
    rows = []
    for f in sorted(glob.glob(f"{PROBE_DIR}/*.md")):
        key = f.split("/")[-1][:-3]
        txt = open(f, encoding="utf-8").read()
        jm = JSON_RE.search(txt)
        data = json.loads(jm.group(1)) if jm else {}
        s = summarize(data)
        nm = NAME_RE.search(txt)
        name = nm.group(1).strip() if nm else ""
        sm = SHOT_RE.search(txt)
        shot = sm.group(1).strip() if sm else "-"
        ip, port = key.rsplit("_", 1)
        addr = f"{ip}:{port}"
        rows.append([key, addr, name, str(s["connect"]), s["quality"],
                     s["resolution"], s["dynamic_range"], s["scan"], s["tag"],
                     s["video"], s["audio"], s["service"], s["provider"], shot])
    with open(OUT, "w", encoding="utf-8") as o:
        for r in rows:
            o.write("\t".join(r) + "\n")
    print(f"wrote {len(rows)} rows to {OUT}")


if __name__ == "__main__":
    main()
