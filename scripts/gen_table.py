#!/usr/bin/env python3
"""gen_table.py — 合并 m3u 元数据 + 探测摘要(_all_summary.tsv) → channels.md 的频道数据总表。

一张表，按 IPTV 遥控器编号排序（无编号排末尾）。包含既有频道 + 新增/缺失源。
多源频道（同一频道多个组播源）用“源”列标 1/2 并相邻排列。
确定性字段来自 iptv_classify，不在此处重新判断。
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # 仓库根（脚本在 scripts/ 下）
M3U = os.path.join(ROOT, "bj-unicom-iptv.m3u")
TSV = os.path.join(ROOT, "channel-probes/_all_summary.tsv")
OUT = "/tmp/channels_table.md"

# m3u 已是最终真源：显示名含最终后缀、新频道已并入、源1/源2 已在名里标注。
# 本脚本只负责把 m3u + 探测摘要 合成「按编号排序」的总表，不再做 EXTRA/override。


def load_tsv():
    # TSV 列：key addr name connect 画质 分辨率 动态 扫描 统计分类 显示名后缀 视频 音频 service provider shot
    d = {}
    for line in open(TSV, encoding="utf-8"):
        p = line.rstrip("\n").split("\t")
        if len(p) < 15:
            p += [""] * (15 - len(p))
        (key, addr, name, connect, q, res, dr, scan, cat, suffix,
         video, audio, svc, prov, shot) = p[:15]
        d[addr] = dict(key=key, connect=connect, quality=q, resolution=res,
                       dr=dr, scan=scan, cat=cat, suffix=suffix, video=video,
                       audio=audio, service=svc, provider=prov, shot=shot)
    return d


def parse_m3u():
    chans = []
    ext = None
    for line in open(M3U, encoding="utf-8"):
        line = line.rstrip("\r\n")
        if line.startswith("#EXTINF"):
            ext = line
        elif line.startswith("rtp://") and ext:
            addr = line[len("rtp://"):]
            disp = ext.split(",", 1)[-1] if "," in ext else ""  # 最终显示名（含后缀/源N）
            # 频道编号：取显示名里倒数第一个纯数字 [N]（质量后缀 [1080i]/[4K HDR] 非纯数字，不会误取）
            nums = re.findall(r"\[(\d+)\]", disp)
            ch_num = nums[-1] if nums else ""
            # 源号：显示名里出现 源1/源2 则提取
            msrc = re.search(r"源([12])", disp)
            src = msrc.group(1) if msrc else ""
            g = lambda k: (re.search(rf'{k}="([^"]*)"', ext) or [None, ""])[1] if re.search(rf'{k}="([^"]*)"', ext) else ""
            chans.append(dict(addr=addr, num=ch_num, disp=disp, src=src,
                              group=g("group-title"), tvg_id=g("tvg-id"),
                              tvg_name=g("tvg-name")))
            ext = None
    return chans


def short_video(v):
    m = re.match(r"(\S+)\s+(\S+(?:\s\S+)?)\s+(\d+bit)\s+\d+x\d+\s+\S+\s+transfer=\S+\s+primaries=\S+\s+field=\S+\s+level=(\S+)", v)
    if not m:
        return v.split(" ")[0] if v else "-"
    codec = m.group(1).upper().replace("H264", "H.264").replace("HEVC", "HEVC")
    prof, bits, lvl = m.group(2), m.group(3), m.group(4)
    try:
        lv = int(lvl); lvs = f"L{lv//10}.{lv%10}"
    except ValueError:
        lvs = f"L{lvl}"
    return f"{codec} {prof} {bits} {lvs}"


def main():
    tsv = load_tsv()
    chans = parse_m3u()

    header = ("| 编号 | 频道名称(显示名) | 统计分类 | 分辨率 | 动态范围 | 扫描 | 视频编码 | 音频 "
              "| 组播地址 | 源 | group-title | service_name | provider | tvg-id | tvg-name | 验证 | 原始数据 |")
    sep = "| --- " * 17 + "|"

    def sort_key(c):
        # 按编号升序；无编号排最后（仍保持 m3u 内相对顺序）
        try:
            return (0, int(c["num"]))
        except (ValueError, TypeError):
            return (1, 99999)

    chans.sort(key=sort_key)

    lines = [header, sep]
    for c in chans:
        p = tsv.get(c["addr"], {})
        key = p.get("key", c["addr"].replace(":", "_"))
        verify = "✓直播" if p.get("connect") == "True" else ("✗" if p else "—")
        probe = f"[📄](channel-probes/{key}.md)" if p else ""
        row = (
            f"| {c['num'] or '—'} | {c['disp']} | {p.get('cat','')} "
            f"| {p.get('resolution','')} | {p.get('dr','')} | {p.get('scan','')} "
            f"| {short_video(p.get('video',''))} | {p.get('audio','')} "
            f"| `{c['addr']}` | {c['src']} | {c['group']} "
            f"| {p.get('service','')} | {p.get('provider','')} "
            f"| {c['tvg_id']} | {c['tvg_name']} | {verify} | {probe} |"
        )
        lines.append(row)

    open(OUT, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print(f"wrote {len(chans)} rows to {OUT}  (m3u channels: {len(chans)})")


if __name__ == "__main__":
    main()
