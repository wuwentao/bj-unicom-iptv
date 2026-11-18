#!/usr/bin/env python3
"""regen_probe_tables.py — 用新术语重算 channel-probes/*.md 的“判定表”，不重新探测。

从每条探测记录内嵌的 ffprobe JSON 重新计算分类字段，只替换判定表那几行，
保留原始 ffmpeg banner、ffprobe JSON、时间戳不变。幂等可重复运行。
"""
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # 便于导入同目录 iptv_classify
from iptv_classify import summarize

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # 仓库根（脚本在 scripts/ 下）
PROBE_DIR = os.path.join(ROOT, "channel-probes")


def build_table(addr, url, name_hint, shot, s):
    return "\n".join([
        "| 字段 | 值（脚本确定性判定） |",
        "| --- | --- |",
        f"| 组播地址 | `{addr}` |",
        f"| 探测 URL | `{url}` |",
        f"| 频道名称(hint·需人工/台标) | {name_hint} |",
        f"| service_name / provider | `{s['service']}` / `{s['provider']}` |",
        f"| 连接 | {'true' if s['connect'] else 'false'} |",
        f"| 画质 | {s['quality']} |",
        f"| 分辨率 | {s['resolution']} |",
        f"| 动态范围(SDR/HDR) | {s['dynamic_range']} |",
        f"| 扫描方式 | {s['scan']} |",
        f"| 统计分类 | {s.get('cat', s.get('tag',''))} |",
        f"| 显示名后缀 | {s.get('name_suffix','')} |",
        f"| 视频 | {s['video']} |",
        f"| 音频 | {s['audio']} |",
        f"| 截图 | {shot} |",
    ])


# 一条记录从 "## 探测 @ ..." 到下一个 "---"/EOF
REC_RE = re.compile(r"(## 探测 @ [^\n]+\n)(.*?)(?=\n---\n|\Z)", re.DOTALL)
# 旧判定表：从 "| 字段 |" 到 第一个空行前
TABLE_RE = re.compile(r"\| 字段 \|.*?(?=\n\n)", re.DOTALL)
JSON_RE = re.compile(r"```json\n(.*?)\n```", re.DOTALL)


def field(table_text, label):
    m = re.search(rf"\| {re.escape(label)} \| (.*?) \|", table_text)
    return m.group(1).strip() if m else ""


def process(path):
    txt = open(path, encoding="utf-8").read()
    changed = False

    def repl(m):
        nonlocal changed
        head, body = m.group(1), m.group(2)
        jm = JSON_RE.search(body)
        if not jm:
            return m.group(0)
        try:
            data = json.loads(jm.group(1))
        except json.JSONDecodeError:
            data = {}
        s = summarize(data)
        old_table = TABLE_RE.search(body)
        if not old_table:
            return m.group(0)
        ot = old_table.group(0)
        addr = field(ot, "组播地址").strip("`")
        url = field(ot, "探测 URL").strip("`")
        name_hint = field(ot, "频道名称(hint·需人工/台标)")
        shot = field(ot, "截图") or "-"
        new_table = build_table(addr, url, name_hint, shot, s)
        changed = True
        return head + body.replace(ot, new_table, 1)

    new_txt = REC_RE.sub(repl, txt)
    if changed and new_txt != txt:
        open(path, "w", encoding="utf-8").write(new_txt)
        return True
    return False


def main():
    files = sorted(f for f in glob.glob(os.path.join(PROBE_DIR, "*.md")))
    n = sum(process(f) for f in files)
    print(f"regenerated {n}/{len(files)} probe files")


if __name__ == "__main__":
    main()
