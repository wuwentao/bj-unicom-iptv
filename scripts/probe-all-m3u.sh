#!/bin/bash
# probe-all-m3u.sh — 批量探测 bj-unicom-iptv.m3u 中【全部频道】，逐个调用 probe-and-record.sh。
#
# - 解析 m3u 的 #EXTINF 显示名 + 下一行 rtp:// 地址，逐个探测。
# - 原始数据按组播地址写入 channel-probes/<ip>_<port>.md（见 probe-and-record.sh）。
# - 截图存入 SHOTS_DIR；一行摘要写入 SUMMARY_TSV（供生成总表 §4.2）。
# - 可断点续跑：已在 SUMMARY_TSV 出现过的组播地址(key)默认跳过（FORCE=1 可强制重跑）。
#
# 用法：
#   ./probe-all-m3u.sh [m3u文件，默认 bj-unicom-iptv.m3u]
#
# 环境变量（透传给 probe-and-record.sh）：
#   UDPXY_BASE / FFPROBE / FFMPEG / PROBE_TIMEOUT
#   SHOTS_DIR     默认 ~/iptv-shots-m3u
#   SUMMARY_TSV   默认 channel-probes/_m3u_summary.tsv
#   FORCE=1       忽略续跑、强制重新探测全部
set -u
export LANG=C.UTF-8 LC_ALL=C.UTF-8
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"   # 仓库根（脚本在 scripts/ 下）
M3U="${1:-$ROOT_DIR/bj-unicom-iptv.m3u}"
REC="$SCRIPT_DIR/probe-and-record.sh"
export SHOTS_DIR="${SHOTS_DIR:-$HOME/iptv-shots-m3u}"
export SUMMARY_TSV="${SUMMARY_TSV:-$ROOT_DIR/channel-probes/_m3u_summary.tsv}"
FORCE="${FORCE:-0}"
PROGRESS="$ROOT_DIR/channel-probes/_m3u_progress.log"

[ -f "$M3U" ]  || { echo "找不到 m3u: $M3U" >&2; exit 1; }
[ -x "$REC" ]  || { echo "找不到可执行的 probe-and-record.sh" >&2; exit 1; }
mkdir -p "$SHOTS_DIR" "$(dirname "$SUMMARY_TSV")"

# 已完成的 key 集合（续跑用）——用 grep 代替 bash 4+ 的 declare -A，兼容 bash 3.2
done_keys_file="$SCRIPT_DIR/channel-probes/_done_keys.tmp"
[ "$FORCE" = "1" ] && rm -f "$done_keys_file"
if [ -f "$SUMMARY_TSV" ]; then
  cut -f1 "$SUMMARY_TSV" | sort -u > "$done_keys_file"
else
  : > "$done_keys_file"
fi

key_done() { grep -qxF "$1" "$done_keys_file" 2>/dev/null; }

# 解析 m3u：成对的 #EXTINF + rtp://
total=0; done_cnt=0; skip_cnt=0
name=""
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    \#EXTINF*)
      # 显示名 = 最后一个逗号之后
      name="${line##*,}"
      ;;
    rtp://*)
      addr="${line#rtp://}"
      ip="${addr%%:*}"; port="${addr##*:}"; key="${ip}_${port}"
      total=$((total+1))
      if key_done "$key"; then
        skip_cnt=$((skip_cnt+1))
        echo "[skip] $key 已探测，跳过（FORCE=1 可重跑）"
      else
        echo "[$(date '+%H:%M:%S')] ($total) 探测 $name  $addr"
        NAME="$name" "$REC" "$addr" >>"$PROGRESS" 2>&1
        # 追加到已完成列表，防止同次运行中出现重复地址
        echo "$key" >> "$done_keys_file"
        done_cnt=$((done_cnt+1))
      fi
      name=""
      ;;
  esac
done < "$M3U"

echo "============================================"
echo "完成。总频道=$total  本次探测=$done_cnt  跳过(已存在)=$skip_cnt"
echo "原始数据: channel-probes/<ip>_<port>.md"
echo "截图:     $SHOTS_DIR"
echo "摘要TSV:  $SUMMARY_TSV"
echo "进度日志: $PROGRESS"
