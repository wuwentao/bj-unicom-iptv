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

# —— 人工确认区（来自 IPTV 机顶盒核对）——
# 新增/缺失源（不在 m3u 中）的地址 → (确认编号或"", 频道名, 建议group, 源号或"")
EXTRA = {
    # gist 评论新增（2026-11 实测）
    "239.3.1.23:8001":  ("",    "平谷融媒",     "[高清]北京",        ""),   # 与房山/通州等地方台放最后
    "239.3.1.24:8001":  ("",    "证券服务",     "[高清]北京IPTV",    ""),
    "239.3.1.25:8001":  ("",    "重温经典",     "[高清]北京IPTV",    ""),
    "239.3.1.106:8001": ("70",  "CHC动作电影",  "[高清]北京IPTV",    ""),
    "239.3.1.107:8001": ("",    "求索纪录4K",   "[高清]北京IPTV;4K", ""),
    "239.3.1.108:8001": ("322", "中国天气",     "[高清]北京IPTV",    ""),
    "239.3.1.109:8001": ("323", "环球旅游",     "[高清]北京IPTV",    ""),
    "239.3.1.206:8001": ("",    "CCTV16奥林匹克4K", "[高清]央视;4K", "1"),
    "239.2.1.206:8000": ("",    "CCTV16奥林匹克4K", "[高清]央视;4K", "2"),
    # gist 原始列表里但本仓库缺失的
    "239.3.1.168:8196": ("65",  "兵团卫视",     "[高清]卫视",        ""),
    "239.3.1.59:8001":  ("",    "门头沟融媒",   "[高清]北京",        ""),   # 地方台，放最后
    # 跨仓库交叉对比(qwerttvv/islercn)补齐、且本地实测有真实视频数据的频道
    "239.3.1.205:8228": ("60",  "海南卫视",     "[高清]卫视",        ""),   # 实测1080i，台标确认
    "239.3.1.204:8224": ("75",  "内蒙古卫视",   "[高清]卫视",        ""),   # 实测1080i，NMTV台标确认
    "239.3.1.203:8220": ("",    "陕西卫视",     "[高清]卫视",        ""),   # 实测1080i高清(本仓库原仅标清[154])
    "239.3.1.27:2000":  ("406", "广东卫视4K",   "[高清]卫视;4K",     "2"),  # 实测4K HDR 10bit(现有.203:2000源已失效)
    "239.3.1.28:2000":  ("408", "深圳卫视4K",   "[高清]卫视;4K",     "2"),  # 实测4K HDR 10bit(现有.202:2000源已失效)
    # 多源第二源（源1 已在 m3u 中）
    "239.3.1.160:8001": ("49",  "聚鲨环球精选", "[高清]北京IPTV",    "2"),  # 频道号 19→49(用户确认)
    "239.3.1.190:8001": ("",    "优购物",       "[高清]北京IPTV",    "2"),
    "239.3.1.191:8001": ("",    "时尚购物",     "[高清]北京IPTV",    "2"),
}

# m3u 中作为“源1”的地址（与 EXTRA 里对应的“源2”配对）→ 源号 "1"
SOURCE1 = {
    "239.3.1.179:8001": "1",  # 聚鲨环球精选 源1
    "239.3.1.180:8001": "1",  # 优购物 源1
    "239.3.1.181:8001": "1",  # 时尚购物 源1
    "239.3.1.203:2000": "1",  # 广东卫视4K 源1(已失效，见源2 .27:2000)
    "239.3.1.202:2000": "1",  # 深圳卫视4K 源1(已失效，见源2 .28:2000)
}

# 对 m3u 中既有频道的编号/名称人工修正（机顶盒/台标确认，暂不改 m3u 本体，仅反映在本表）
NUM_OVERRIDE = {
    "239.3.1.179:8001": "49",  # 聚鲨环球精选 频道号 19→49(用户确认)
}
NAME_OVERRIDE = {
    "239.3.1.164:8001": "四海钓鱼",  # 原 m3u 误标“湖南卫视快乐垂钓”，台标实为四海钓鱼
}

# 地方台（排在最后，与平谷/门头沟同区）
LOCAL_LAST = {"239.3.1.23:8001", "239.3.1.59:8001"}


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
            disp = ext.split(",", 1)[-1] if "," in ext else ""
            nums = re.findall(r"\[(\d+)\]", disp)
            ch_num = nums[-2] if len(nums) >= 2 else (nums[-1] if nums else "")
            name = re.sub(r"\[\d+\]", "", disp)
            name = re.sub(r"\[(高清|4K|标清)\]", "", name).strip()
            # 人工修正（机顶盒/台标确认）
            ch_num = NUM_OVERRIDE.get(addr, ch_num)
            name = NAME_OVERRIDE.get(addr, name)
            g = lambda k: (re.search(rf'{k}="([^"]*)"', ext) or [None, ""])[1] if re.search(rf'{k}="([^"]*)"', ext) else ""
            chans.append(dict(addr=addr, num=ch_num, name=name,
                              group=g("group-title"), tvg_id=g("tvg-id"),
                              tvg_name=g("tvg-name"), tvg_logo=g("tvg-logo"),
                              extra=False))
            ext = None
    return chans


def clean_4k_name(name):
    """4K 频道名去掉冗余的 '4K超高清'/'超高清'/尾部 SDR/HDR（画质由后缀标识表达）。
    保留作为品牌一部分的 'CCTV 4K'（空格+4K）。"""
    n = re.sub(r"4K超高清|4K超清|超高清|超清", "", name)
    n = re.sub(r"\s*(SDR|HDR)\s*$", "", n)
    return n.strip() or name


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

    # 附加 EXTRA（不在 m3u 的新增/缺失源）
    for addr, (num, name, group, src) in EXTRA.items():
        chans.append(dict(addr=addr, num=num, name=name, group=group,
                          tvg_id="", tvg_name="", tvg_logo="", extra=True, src=src))

    header = ("| 编号 | 频道名称(建议显示名) | 统计分类 | 分辨率 | 动态范围 | 扫描 | 视频编码 | 音频 "
              "| 组播地址 | 源 | 现 group-title | service_name | provider | tvg-id | tvg-name | 验证 | 原始数据 |")
    sep = "| --- " * 17 + "|"

    def sort_key(c):
        n = c.get("num", "")
        local = 1 if c["addr"] in LOCAL_LAST else 0
        try:
            return (local, int(n))
        except (ValueError, TypeError):
            return (2 + local, 99999)  # 无编号排最后，地方台更后

    chans.sort(key=sort_key)

    lines = [header, sep]
    for c in chans:
        p = tsv.get(c["addr"], {})
        key = p.get("key", c["addr"].replace(":", "_").replace(".", "."))
        src = c.get("src", SOURCE1.get(c["addr"], ""))
        verify = "✓直播" if p.get("connect") == "True" else ("✗" if p else "—")
        probe = f"[📄](channel-probes/{key}.md)" if p else ""
        cat = p.get("cat", "")
        # 建议显示名 = 频道名 + [编号] + 显示名后缀（如 CCTV-1综合[1][高清][1080i]）
        num_part = f"[{c['num']}]" if c["num"] else ""
        suffix = p.get("suffix", "")
        base = clean_4k_name(c["name"]) if p.get("quality") == "4K" else c["name"]
        disp_name = f"{base}{num_part}{suffix}"
        row = (
            f"| {c['num'] or '—'} | {disp_name} | {cat} "
            f"| {p.get('resolution','')} | {p.get('dr','')} | {p.get('scan','')} "
            f"| {short_video(p.get('video',''))} | {p.get('audio','')} "
            f"| `{c['addr']}` | {src} | {c['group']} "
            f"| {p.get('service','')} | {p.get('provider','')} "
            f"| {c['tvg_id']} | {c['tvg_name']} | {verify} | {probe} |"
        )
        lines.append(row)

    open(OUT, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print(f"wrote {len(chans)} rows to {OUT}")
    print(f"  m3u channels: {sum(1 for c in chans if not c.get('extra'))}")
    print(f"  extra (new/missing): {sum(1 for c in chans if c.get('extra'))}")


if __name__ == "__main__":
    main()
