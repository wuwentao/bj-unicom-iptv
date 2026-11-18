#!/usr/bin/env python3
"""iptv_classify.py — 共享的确定性分类逻辑（与 probe-and-record.sh 的 classify() 保持一致）。

从 ffprobe JSON 提取视频/音频/节目元数据，确定性算出：
  画质 / 分辨率 / 动态范围(SDR·HDR) / 扫描 / 位深 / 建议显示名标识 / 视频摘要 / 音频摘要 / service / provider

动态范围定义（以位深为准，不做“真伪”表述）：
  - HDR 需要 10bit + HLG(arib-std-b67)/PQ(smpte2084)/bt2020-10 曲线
  - 8bit 即使带 bt2020/HLG 标签也只能呈现 SDR（标签与实际能力不符，会注明）
"""
import json


def _bits_from_pixfmt(pf: str) -> int:
    pf = pf or ""
    if pf.endswith(("10le", "10be")) or "p010" in pf or pf.endswith("10"):
        return 10
    if pf.endswith(("12le", "12be")) or pf.endswith("12"):
        return 12
    return 8


def classify(width, height, pix_fmt, transfer, primaries, field_order):
    w, h = str(width), str(height)
    bits = _bits_from_pixfmt(pix_fmt)
    tr = transfer or "-"
    prim = primaries or "-"
    fo = field_order or "-"

    # 画质
    if w == "1920" and h == "1080":
        q = "高清"
    elif w == "3840" and h == "2160":
        q = "4K"
    elif w == "720" and h in ("576", "560"):
        q = "标清"
    else:
        q = f"其它({w}x{h})"

    # 动态范围
    is_hdr = False
    if tr in ("arib-std-b67", "smpte2084", "bt2020-10", "bt2020-12"):
        is_hdr = bits >= 10
    elif tr == "reserved":
        is_hdr = bits >= 10 and "bt2020" in prim

    if is_hdr:
        dr = f"HDR({bits}bit·{tr})"
    elif tr in ("arib-std-b67", "smpte2084") or tr.startswith("bt2020"):
        dr = f"SDR({bits}bit·带{tr}标签但非10bit)"
    elif tr == "bt709":
        dr = f"SDR({bits}bit·bt709)"
    elif tr in ("", "-", "unknown"):
        dr = f"SDR({bits}bit·未标注)"
    else:
        dr = f"SDR({bits}bit·{tr})"

    # 扫描
    if fo in ("tt", "bb", "tb", "bt"):
        scan, scode = f"隔行({fo})", "i"
    elif fo == "progressive":
        scan, scode = "逐行", "p"
    elif fo in ("", "-", "unknown"):
        scan, scode = "未知(字段缺失)", ""
    else:
        scan, scode = fo, ""

    # 统计分类(cat) + 显示名后缀(name_suffix)
    # 规则：1080p/1080i 仍属“高清”分组，显示名保留 [高清] 再追加 [1080p]/[1080i]；
    #       4K 用 [4K SDR]/[4K HDR]；标清用 [标清]。
    if q == "4K":
        if is_hdr:
            cat, name_suffix = "4K HDR", "[4K HDR]"
        else:
            cat, name_suffix = "4K SDR", "[4K SDR]"
    elif q == "高清":
        if scode == "i":
            cat, name_suffix = "1080i", "[高清][1080i]"
        elif scode == "p":
            cat, name_suffix = "1080p", "[高清][1080p]"
        else:
            cat, name_suffix = "高清(扫描未定)", "[高清]"
    elif q == "标清":
        cat, name_suffix = "标清", "[标清]"
    else:
        cat, name_suffix = q, f"[{q}]"

    return {
        "quality": q, "resolution": f"{w}x{h}", "dynamic_range": dr,
        "scan": scan, "bits": bits, "cat": cat, "name_suffix": name_suffix,
        "tag": cat, "is_hdr": is_hdr,
        "transfer": tr, "primaries": prim, "field_order": fo,
    }


def summarize(probe_json: dict) -> dict:
    """从 ffprobe JSON 得到一行完整摘要。"""
    streams = probe_json.get("streams", []) if probe_json else []
    programs = probe_json.get("programs", []) if probe_json else []
    v = next((s for s in streams if s.get("codec_type") == "video"), None)
    a = next((s for s in streams if s.get("codec_type") == "audio"), None)

    svc = prov = "-"
    for p in programs:
        tags = p.get("tags", {}) or {}
        if tags.get("service_name"):
            svc = tags["service_name"]
        if tags.get("service_provider"):
            prov = tags["service_provider"]
        if svc != "-":
            break

    if not v:
        return {
            "quality": "错误", "resolution": "-", "dynamic_range": "错误",
            "scan": "错误", "bits": "-", "cat": "错误", "name_suffix": "",
            "tag": "错误", "is_hdr": False,
            "video": "(无视频轨/探测失败)", "audio": "-",
            "service": svc, "provider": prov, "connect": bool(streams),
        }

    c = classify(v.get("width"), v.get("height"), v.get("pix_fmt"),
                 v.get("color_transfer"), v.get("color_primaries"), v.get("field_order"))

    codec = v.get("codec_name", "-")
    profile = (v.get("profile") or "-")
    level = v.get("level", "-")
    video = (f"{codec} {profile} {c['bits']}bit {c['resolution']} "
             f"{v.get('pix_fmt','-')} transfer={c['transfer']} "
             f"primaries={c['primaries']} field={c['field_order']} level={level}")

    audio = "-"
    if a:
        br = a.get("bit_rate")
        brs = f"{int(int(br)/1000)}k" if br and str(br).isdigit() else "-"
        audio = f"{a.get('codec_name','-')} {a.get('channels','-')}ch {a.get('sample_rate','-')}Hz {brs}"

    c.update({"video": video, "audio": audio, "service": svc,
              "provider": prov, "connect": True})
    return c


if __name__ == "__main__":
    import sys
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    print(json.dumps(summarize(data), ensure_ascii=False, indent=2))
