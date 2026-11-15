#!/usr/bin/env python3
# gen_table.py — merge m3u metadata + probe TSV → §4.2 markdown table rows
# Usage: python3 gen_table.py > /tmp/section42.md
import re, sys

M3U   = "bj-unicom-iptv.m3u"
TSV   = "channel-probes/_m3u_summary.tsv"
OUT   = "/tmp/section42.md"
SHOTS = "~/Downloads/iptv-new-channels-screenshots/m3u-channels"

# --- parse m3u ---
channels = []  # list of dicts
with open(M3U, encoding="utf-8") as f:
    extinf = None
    for line in f:
        line = line.rstrip("\r\n")
        if line.startswith("#EXTINF"):
            extinf = line
        elif line.startswith("rtp://") and extinf:
            addr = line[len("rtp://"):]
            # parse EXTINF attributes
            tvg_id    = re.search(r'tvg-id="([^"]*)"',    extinf)
            tvg_name  = re.search(r'tvg-name="([^"]*)"',  extinf)
            tvg_logo  = re.search(r'tvg-logo="([^"]*)"',  extinf)
            group     = re.search(r'group-title="([^"]*)"', extinf)
            # display name = after last comma
            disp = extinf.split(",", 1)[-1] if "," in extinf else ""
            # channel number = last [...] before quality tag
            nums = re.findall(r'\[(\d+)\]', disp)
            ch_num = nums[-2] if len(nums) >= 2 else (nums[-1] if nums else "")
            # quality tag at end
            qtag = ""
            for tag in ["[4K]", "[高清]", "[标清]"]:
                if disp.endswith(tag):
                    qtag = tag.strip("[]")
                    break
            channels.append({
                "addr":     addr,
                "tvg_id":   tvg_id.group(1)   if tvg_id   else "",
                "tvg_name": tvg_name.group(1) if tvg_name else "",
                "tvg_logo": tvg_logo.group(1) if tvg_logo else "",
                "group":    group.group(1)    if group    else "",
                "disp":     disp,
                "ch_num":   ch_num,
                "qtag":     qtag,
            })
            extinf = None

# --- parse TSV ---
# cols: key addr name connect 画质 动态 扫描 视频 音频 service provider shot
tsv = {}
with open(TSV, encoding="utf-8") as f:
    for line in f:
        parts = line.rstrip("\r\n").split("\t")
        if len(parts) < 12:
            parts += [""] * (12 - len(parts))
        key = parts[0]
        tsv[key] = {
            "connect":  parts[3],
            "quality":  parts[4],
            "dr":       parts[5],
            "scan":     parts[6],
            "video":    parts[7],
            "audio":    parts[8],
            "service":  parts[9],
            "provider": parts[10],
            "shot":     parts[11],
        }

# --- sort by channel number (blank = 9999) ---
def sort_key(c):
    try:
        return int(c["ch_num"])
    except (ValueError, TypeError):
        return 9999

channels.sort(key=sort_key)

# --- emit markdown ---
header = "| 编号 | 频道名称 | 画质 | 动态范围(真伪HDR) | 扫描/帧率 | 视频编码 | 色彩 range/space/transfer/primaries | 音频 | 组播地址 | 建议 group-title | service_name | provider | tvg-id | tvg-name | tvg-logo | 验证(日期) | 原始数据 |"
sep    = "| --- " * 17 + "|"

lines = [header, sep]
for c in channels:
    ip    = c["addr"].split(":")[0]
    port  = c["addr"].split(":")[1]
    key   = f"{ip}_{port}"
    p     = tsv.get(key, {})

    # extract colour tuple from video summary string (transfer=X primaries=X)
    vsumm  = p.get("video", "")
    tr_m   = re.search(r'transfer=(\S+)', vsumm)
    pri_m  = re.search(r'primaries=(\S+)', vsumm)
    rng_m  = re.search(r'yuv\S*', vsumm)
    sp_m   = re.search(r'bt\d+nc|bt\d+', vsumm)
    tr     = tr_m.group(1)  if tr_m  else "-"
    pri    = pri_m.group(1) if pri_m else "-"

    # derive short video encoding string  e.g. "H.264 High 8bit L4.1"
    vshort = vsumm
    codec_m = re.match(r'(\w+)\s+(\S+)\s+(\d+bit)\s+\d+x\d+\s+\S+\s+transfer=\S+\s+primaries=\S+\s+field=\S+\s+level=(\S+)', vsumm)
    if codec_m:
        codec = codec_m.group(1).upper()
        if codec == "H264": codec = "H.264"
        elif codec == "HEVC": codec = "HEVC"
        profile = codec_m.group(2)
        bits    = codec_m.group(3)
        level   = codec_m.group(4)
        # format level as e.g. L4.1
        try:
            lv = int(level)
            level_s = f"L{lv//10}.{lv%10}"
        except (ValueError, TypeError):
            level_s = f"L{level}"
        vshort = f"{codec} {profile} {bits} {level_s}"
    else:
        vshort = vsumm.split(" ")[0] if vsumm else "-"

    # colour tuple
    colour_map = {
        "bt709":    "tv/bt709/bt709/bt709",
        "bt2020nc": "tv/bt2020nc/…/bt2020",
        "-":        "未标注",
    }
    if tr == "-" or tr == "":
        colour = "未标注/未标注/未标注/未标注"
    else:
        col_range = "tv"
        col_space = sp_m.group(0) if sp_m else "-"
        colour = f"{col_range}/{col_space}/{tr}/{pri}"

    # probe file link
    probe_link = f"[📄](channel-probes/{key}.md)" if p else ""

    # display name without quality/number brackets → clean channel name
    name_clean = re.sub(r'\[\d+\]', '', c["disp"])
    name_clean = re.sub(r'\[高清\]|\[4K\]|\[标清\]', '', name_clean).strip()

    # verification date
    verify = "✓直播 2026-11-15" if p.get("connect") == "true" else "✗失败 2026-11-15"

    row = (
        f"| {c['ch_num'] or '—'} "
        f"| {name_clean} "
        f"| {p.get('quality', c.get('qtag',''))} "
        f"| {p.get('dr','-')} "
        f"| {p.get('scan','-')} "
        f"| {vshort} "
        f"| {colour} "
        f"| {p.get('audio','-')} "
        f"| `{c['addr']}` "
        f"| {c['group']} "
        f"| {p.get('service','')} "
        f"| {p.get('provider','')} "
        f"| {c['tvg_id']} "
        f"| {c['tvg_name']} "
        f"| {c['tvg_logo'][:60]+'…' if len(c['tvg_logo'])>60 else c['tvg_logo']} "
        f"| {verify} "
        f"| {probe_link} |"
    )
    lines.append(row)

with open(OUT, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

print(f"Written {len(channels)} rows to {OUT}")
# quick sanity
print(f"Channels: {len(channels)}, TSV entries: {len(tsv)}")
