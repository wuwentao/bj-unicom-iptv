#!/bin/bash
# probe-and-record.sh — 探测北京联通 IPTV 组播源，按【组播地址唯一键】记录探测历史。
#
# 设计原则：能确定性计算的字段（画质 / 动态范围 / 真伪HDR / 扫描 / 编码 / 音频）
# 全部由本脚本用 ffprobe+jq 固定算出；只有【频道名称(看台标)】和【建议 group-title】
# 需要人工/AI 判断。这样尽量用固定脚本，减少动态解析。
#
# 每个组播地址对应一个文件 channel-probes/<ip>_<port>.md，新记录【追加在末尾】，
# **以最新（最后）一条为准**。同一地址日后频道/质量变化，差异体现在不同时间戳记录之间。
#
# 用法：
#   ./probe-and-record.sh 239.3.1.23:8001 [更多地址...]
#   NAME="平谷融媒" ./probe-and-record.sh 239.3.1.23:8001     # 带频道名提示
#
# 依赖：ffprobe、ffmpeg、jq（Ubuntu: sudo apt install ffmpeg jq）
#
# 环境变量：
#   UDPXY_BASE     默认 http://192.168.2.1:8012/rtp   局域网 udpxy 的 rtp 端点
#   FFPROBE/FFMPEG 默认 ffprobe/ffmpeg                二进制路径
#   PROBE_TIMEOUT  默认 25                             每条命令墙钟超时(秒)
#   NAME           可选                                本次探测的频道名提示
#   SHOTS_DIR      可选                                设定则把截图(首帧)存到该目录
#   SUMMARY_TSV    可选                                设定则把一行摘要(TSV)追加到该文件
set -u
export LANG=C.UTF-8 LC_ALL=C.UTF-8
UDPXY_BASE="${UDPXY_BASE:-http://192.168.2.1:8012/rtp}"
FFPROBE="${FFPROBE:-ffprobe}"
FFMPEG="${FFMPEG:-ffmpeg}"
PROBE_TIMEOUT="${PROBE_TIMEOUT:-25}"
NAME="${NAME:-}"
SHOTS_DIR="${SHOTS_DIR:-}"
SUMMARY_TSV="${SUMMARY_TSV:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"   # 仓库根（脚本在 scripts/ 下）
OUTDIR="$ROOT_DIR/channel-probes"
mkdir -p "$OUTDIR"
[ -n "$SHOTS_DIR" ] && mkdir -p "$SHOTS_DIR"

for bin in "$FFPROBE" "$FFMPEG" jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "缺少依赖: $bin" >&2; exit 1; }
done

# 墙钟超时执行（macOS 无 timeout 命令时也可用）
run_to() { local t=$1; shift; "$@" & local p=$!; ( sleep "$t"; kill -9 "$p" 2>/dev/null ) & local w=$!; wait "$p" 2>/dev/null; local rc=$?; kill "$w" 2>/dev/null; return $rc; }

# 文件名安全化：去掉路径分隔符与空白
safe_name() { printf '%s' "$1" | tr '/ :' '___' | tr -d '\t\r\n'; }

# 确定性分类：输入 width height pix_fmt profile transfer primaries field_order
# 输出(制表符分隔)：画质  动态范围  扫描  位深  建议标识
#
# 动态范围定义（以位深为准，不看“标签”真伪）：
#   - 4K/HDR 需要 10bit + HLG(arib-std-b67)/PQ(smpte2084)/bt2020-10 曲线
#   - 8bit 即使带 bt2020/HLG 标签也只能呈现 SDR（标签与实际能力不符，会另注）
#   - 其余为 SDR
# 建议标识（用于 m3u 显示名后缀）：4K HDR / 4K SDR / 1080p / 1080i / 标清 等
classify() {
  local w="$1" h="$2" pf="$3" prof="$4" tr="$5" prim="$6" fo="$7"
  # 位深：pix_fmt 带 10/12 则为 10/12bit，否则 8bit
  local bits=8
  case "$pf" in *10le|*10be|*p010*|*10) bits=10;; *12le|*12be|*12) bits=12;; esac
  # 画质
  local q="其它(${w}x${h})"
  if [ "$w" = "1920" ] && [ "$h" = "1080" ]; then q="高清"
  elif [ "$w" = "3840" ] && [ "$h" = "2160" ]; then q="4K"
  elif [ "$w" = "720" ] && { [ "$h" = "576" ] || [ "$h" = "560" ]; }; then q="标清"; fi
  # 动态范围（SDR / HDR，以位深为准）
  local dr is_hdr=0
  case "$tr" in
    arib-std-b67|smpte2084|bt2020-10|bt2020-12)
      if [ "$bits" -ge 10 ]; then is_hdr=1; fi ;;
    reserved) # ffprobe 未映射，但若 10bit+bt2020 基本可判为 HDR
      if [ "$bits" -ge 10 ] && printf '%s' "$prim" | grep -q bt2020; then is_hdr=1; fi ;;
  esac
  if [ "$is_hdr" = "1" ]; then
    dr="HDR(${bits}bit·${tr})"
  else
    case "$tr" in
      arib-std-b67|smpte2084|bt2020*) dr="SDR(${bits}bit·带${tr}标签但非10bit)" ;;
      bt709)                          dr="SDR(${bits}bit·bt709)" ;;
      ""|unknown|-)                   dr="SDR(${bits}bit·未标注)" ;;
      *)                              dr="SDR(${bits}bit·${tr})" ;;
    esac
  fi
  # 扫描
  local scan scode
  case "$fo" in
    tt|bb|tb|bt)  scan="隔行(${fo})"; scode="i" ;;
    progressive)  scan="逐行";       scode="p" ;;
    ""|unknown|-) scan="未知(字段缺失)"; scode="" ;;
    *)            scan="${fo}";       scode="" ;;
  esac
  # 统计分类(cat) + 显示名后缀(name_suffix)
  # 1080p/1080i 仍属“高清”分组：显示名保留 [高清] 再追加 [1080p]/[1080i]
  local cat suffix
  if [ "$q" = "4K" ]; then
    if [ "$is_hdr" = "1" ]; then cat="4K HDR"; suffix="[4K HDR]"; else cat="4K SDR"; suffix="[4K SDR]"; fi
  elif [ "$q" = "高清" ]; then
    case "$scode" in
      i) cat="1080i"; suffix="[高清][1080i]" ;;
      p) cat="1080p"; suffix="[高清][1080p]" ;;
      *) cat="高清(扫描未定)"; suffix="[高清]" ;;
    esac
  elif [ "$q" = "标清" ]; then
    cat="标清"; suffix="[标清]"
  else
    cat="$q"; suffix="[$q]"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s' "$q" "$dr" "$scan" "$bits" "$cat" "$suffix"
}

[ $# -ge 1 ] || { echo "用法: $0 <组播IP:端口> [更多...]"; exit 2; }

for addr in "$@"; do
  ip="${addr%%:*}"; port="${addr##*:}"
  key="${ip}_${port}"
  url="$UDPXY_BASE/$addr"
  ts="$(date '+%Y-%m-%d %H:%M:%S %z')"
  file="$OUTDIR/${key}.md"
  shot_rel="-"

  echo ">>> 探测 $addr  ($url)"
  # 1) ffprobe JSON（权威元数据）
  sj="$(run_to "$PROBE_TIMEOUT" "$FFPROBE" -v quiet -print_format json -show_format -show_streams -show_programs -i "$url" 2>/dev/null)"
  # 2) 一次 ffmpeg 读流：同时抓首帧截图 + 取 banner（二合一，省一次拉流）
  if [ -n "$SHOTS_DIR" ]; then
    shot_file="${SHOTS_DIR}/${key}__$(safe_name "${NAME:-$key}").png"
    banner="$(run_to "$PROBE_TIMEOUT" "$FFMPEG" -nostdin -hide_banner -rw_timeout 12000000 -i "$url" -frames:v 1 -update 1 -y "$shot_file" 2>&1 | sed -n '/Input #0/,/Stream mapping:/p')"
    [ -f "$shot_file" ] && shot_rel="$(basename "$shot_file")"
  else
    banner="$(run_to "$PROBE_TIMEOUT" "$FFMPEG" -hide_banner -rw_timeout 12000000 -i "$url" -t 1 -f null - 2>&1 | sed -n '/Input #0/,/Stream mapping:/p')"
  fi

  if [ -n "$sj" ]; then
    svc="$(printf '%s' "$sj"  | jq -r '[.programs[]?.tags?.service_name    // empty]|first // "-"')"
    prov="$(printf '%s' "$sj" | jq -r '[.programs[]?.tags?.service_provider // empty]|first // "-"')"
    read -r vw vh vpf vprof vtr vprim vfo vcodec vlevel < <(printf '%s' "$sj" | jq -r '
      ([.streams[]?|select(.codec_type=="video")][0]) as $v |
      "\($v.width//"-") \($v.height//"-") \($v.pix_fmt//"-") \(($v.profile//"-")|gsub(" ";"_")) \($v.color_transfer//"-") \($v.color_primaries//"-") \($v.field_order//"-") \($v.codec_name//"-") \($v.level//"-")"')
    acodec="$(printf '%s' "$sj" | jq -r '([.streams[]?|select(.codec_type=="audio")][0]) as $a | "\($a.codec_name//"-") \($a.channels//"-")ch \($a.sample_rate//"-")Hz \(if $a.bit_rate then (($a.bit_rate|tonumber/1000|floor|tostring)+"k") else "-" end)"')"
    IFS=$'\t' read -r cq cdr cscan cbits ccat csuffix < <(classify "$vw" "$vh" "$vpf" "$vprof" "$vtr" "$vprim" "$vfo")
    vres="${vw}x${vh}"
    vsummary="${vcodec} ${vprof//_/ } ${cbits}bit ${vw}x${vh} ${vpf} transfer=${vtr} primaries=${vprim} field=${vfo} level=${vlevel}"
    connect="true"
  else
    svc="-"; prov="-"; acodec="-"; vsummary="(探测失败/无数据)"; cq="错误"; cdr="错误"; cscan="错误"; cbits="-"; ccat="错误"; csuffix=""; vres="-"
    connect="false"
  fi

  if [ ! -f "$file" ]; then
    {
      echo "# 组播地址 \`${addr}\` — 探测历史（probe history）"
      echo
      echo "> 本文件按【组播地址唯一键】记录历次探测，新记录【追加在末尾】，**以最新（最后）一条为准**。"
      echo "> 同一地址若日后频道或质量变化，差异会体现在不同时间戳记录之间。"
      echo ">"
      echo "> 追加新记录：\`./probe-and-record.sh ${addr}\`　整体说明见 [../channels.md](../channels.md)"
      echo
    } > "$file"
  fi

  {
    echo "---"
    echo
    echo "## 探测 @ ${ts}"
    echo
    echo "| 字段 | 值（脚本确定性判定） |"
    echo "| --- | --- |"
    echo "| 组播地址 | \`${addr}\` |"
    echo "| 探测 URL | \`${url}\` |"
    echo "| 频道名称(hint·需人工/台标) | ${NAME:-（未提供，见 service_name）} |"
    echo "| service_name / provider | \`${svc}\` / \`${prov}\` |"
    echo "| 连接 | ${connect} |"
    echo "| 画质 | ${cq} |"
    echo "| 分辨率 | ${vres} |"
    echo "| 动态范围(SDR/HDR) | ${cdr} |"
    echo "| 扫描方式 | ${cscan} |"
    echo "| 统计分类 | ${ccat} |"
    echo "| 显示名后缀 | ${csuffix} |"
    echo "| 视频 | ${vsummary} |"
    echo "| 音频 | ${acodec} |"
    echo "| 截图 | ${shot_rel} |"
    echo
    echo "### ffmpeg -i (raw)"
    echo '```'
    printf '%s\n' "$banner"
    echo '```'
    echo
    echo "### ffprobe -show_format -show_streams -show_programs (raw JSON)"
    echo '```json'
    printf '%s\n' "$sj"
    echo '```'
    echo
  } >> "$file"

  # 摘要 TSV（供批量汇总生成总表）：
  # key \t addr \t name \t connect \t 画质 \t 分辨率 \t 动态 \t 扫描 \t 统计分类 \t 显示名后缀 \t 视频 \t 音频 \t service \t provider \t shot
  if [ -n "$SUMMARY_TSV" ]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$key" "$addr" "${NAME:-}" "$connect" "$cq" "$vres" "$cdr" "$cscan" "$ccat" "$csuffix" "$vsummary" "$acodec" "$svc" "$prov" "$shot_rel" >> "$SUMMARY_TSV"
  fi
  echo "    画质=${cq} 动态=${cdr} 扫描=${cscan} 分类=${ccat} 连接=${connect}  -> channel-probes/${key}.md"
done
