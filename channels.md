<!-- markdownlint-disable MD013 MD033 -->
# 北京联通 IPTV 频道数据总表

本文件是**北京联通 IPTV** 全部频道的详细数据总表，记录每个频道/节目源经 `ffprobe`/`ffmpeg` 实测的音视频参数、色彩与动态范围、MPEG-TS 官方台名、EPG 字段与组播地址，方便对比、问题回溯，以及直接生成 `bj-unicom-iptv.m3u` 条目。

- 只收录**北京联通**源（忽略电信/移动）。
- [第 2 节基础知识科普](#2-基础知识科普先看这里) 先讲清各项指标的含义与标准，再看[第 4 节总表](#4-数据总表)才不费解。
- 表格按 **IPTV 遥控器频道编号** 排序；编号未知的列在「编号待确认」区，随后由人工在 IPTV 上确认补齐。
- `bj-unicom-iptv.m3u` **不按编号排序**，仍维持原有「画质 + 分类」排序规则；本表与 m3u 是两套排序，互不影响。
- 每个源的 `ffprobe`/`ffmpeg` **原始输出**按[组播地址唯一键](#5-原始探测数据的组织方式)保存在 [`channel-probes/`](channel-probes/)，含探测时间戳，可追加历史、回溯差异。

---

## 1. 数据怎么来的（探测方法）

组播经本地 udpxy 转单播后探测：`rtp://<组播IP:端口>` → `http://192.168.2.1:8012/rtp/<组播IP:端口>`。

确定性字段（画质 / 动态范围 / 真伪HDR / 扫描 / 编码 / 音频）由固定脚本 [`probe-and-record.sh`](probe-and-record.sh) 用 `ffprobe`+`jq` 算出；只有**频道名称（看台标）**和**建议 group-title** 需要人工/AI 判断。复现命令见[第 6 节](#6-数据模板与复现)。

---

## 2. 基础知识科普（先看这里）

这些指标决定了「同样是 4K / 高清，画质音质其实差很多」。看懂它们，才能理解总表里每一列的差异，尤其是**真假 HDR**。

### 2.1 分辨率（画面像素数）

| 俗称 | 像素 | 本表 flag |
| --- | --- | --- |
| 标清 SD | 720×576（4:3） | `标清` |
| 高清 FHD | 1920×1080 | `高清` |
| 超高清 UHD | 3840×2160（=4K） | `4K` |

分辨率只是「有多少像素」，**不代表画质高低**——下面的编码、位深、动态范围、扫描方式同样决定观感。

### 2.2 扫描方式（逐行 vs 隔行）与帧率

- **逐行 progressive（p）**：每帧是完整一幅画面。如 `1080p`、`2160p`。清晰、无撕裂。
- **隔行 interlaced（i）**：每帧只含一半扫描线（奇/偶场交替），靠两场拼一幅。如 `1080i`。运动画面边缘会有「梳状」锯齿，需播放器反隔行（deinterlace）。
  - `field_order=tt` 表示**顶场优先**（top field first）。
- **帧率/场频**：`25fps` = 每秒 25 帧；隔行源常说 `50 field/s`（每秒 50 场，视觉刷新≈50Hz）。`50fps` 逐行则更流畅。
- 国内电视制式为 PAL/50Hz 体系，所以常见 25fps（逐行）或 50 场（隔行）。

> ⚠️ 很多「高清」卫视/地方台其实是 **1080i 隔行**，不是 1080p 逐行——本表如实标出。

### 2.3 视频编码（压缩格式）与 profile / level

- **H.264 / AVC**：主流高清编码。常见 profile：`Baseline < Main < High`（High 压缩效率/画质最好）。
- **H.265 / HEVC**：4K 常用，压缩率约为 H.264 两倍。关键 profile：
  - **`Main` = 8bit**
  - **`Main 10` = 10bit**（HDR 必需）
- **level**（如 `4.0`/`5.1`/`6.0`）：约束分辨率×帧率×码率上限，数字越大承载能力越强。

### 2.4 位深 bit depth（8bit / 10bit）

- **8bit**：每通道 256 级，约 1670 万色。SDR 常用。
- **10bit**：每通道 1024 级，约 10.7 亿色。渐变更平滑、不易出现「色带 banding」。**HDR 实际需要 10bit 才有意义。**
- 从 `pix_fmt` 判断：`yuv420p` = 8bit；`yuv420p10le` = 10bit。
- 从 HEVC profile 判断：`Main` = 8bit；`Main 10` = 10bit。

### 2.5 色彩四元组（range / space(matrix) / transfer / primaries）

ffprobe 给出四个色彩字段，决定「颜色怎么还原」：

| 字段 | 含义 | 常见值 |
| --- | --- | --- |
| `color_range` | 量化范围 | `tv`(有限 16–235) / `pc`(全 0–255) |
| `color_space`（matrix） | YUV↔RGB 转换矩阵 | `bt709`(高清) / `bt2020nc`(4K 广色域) |
| `color_transfer` | **传输特性（伽马/HDR 曲线）** | `bt709`(SDR) / `arib-std-b67`(**HLG**) / `smpte2084`(**PQ**) |
| `color_primaries` | 色域（三原色范围） | `bt709`(标准) / `bt2020`(广色域) |

> `color_transfer` 是判断 SDR/HDR 的核心：`bt709`=SDR；`arib-std-b67`=HLG(HDR)；`smpte2084`=PQ(HDR)。

### 2.6 动态范围：SDR / HDR，以及 HLG 与 PQ

- **SDR**（标准动态范围）：传统亮度范围，`transfer=bt709`。
- **HDR**（高动态范围）：更亮的高光、更暗的暗部、更广色域。两大曲线：
  - **HLG**（Hybrid Log-Gamma，`arib-std-b67`）：广电直播常用，兼容 SDR 屏。
  - **PQ / HDR10**（`smpte2084`）：流媒体/影视常用，通常带静态元数据（MaxCLL/MaxFALL）。

### 2.7 ⭐ 真 HDR vs 假 HDR（本表重点）

一条流要**真正是 HDR**，需要同时满足：

1. 广色域 `primaries=bt2020` + HDR 矩阵 `space=bt2020nc`；
2. HDR 传输曲线 `transfer=arib-std-b67`(HLG) 或 `smpte2084`(PQ)；
3. **位深 ≥ 10bit**（即 HEVC **Main 10**，`pix_fmt=yuv420p10le`）；
4. HDR10 还应带静态元数据。

**假 HDR** = 流打了 `bt2020`/`HLG` 的**标签**，但实际是 **8bit（HEVC Main，非 Main 10）**。播放器要么点不亮 HDR，要么把 HLG 曲线套在 8bit 上，画面发灰发暗。

> 📌 本仓库实测：**求索纪录4K、CCTV16 UHD（两个源）都是 `HEVC Main=8bit` + `bt2020/HLG` 标签 → 判定「假HDR-HLG(8bit·仅标签)」。** 这与 gist 评论区讨论的「CCTV 4K 标了 bt2020 却点不亮 HDR、实为 SDR」现象一致。脚本据此自动判定真/假 HDR（见 [`probe-and-record.sh`](probe-and-record.sh) 的 `classify()`）。

### 2.8 音频（编码 / 声道 / 采样率 / 码率）

- **编码**：`AAC(LC)`（高效、主流）、`MP2`（老格式，常见于部分频道，同码率下不如 AAC）。
- **声道**：`2ch` 立体声 / `1ch` 单声道 / `6ch` 5.1。
- **采样率**：`48kHz`（广电标准）/ `44.1kHz`（CD 标准，少见于电视）。
- **码率**：越高音质越好。本表新增频道区间约 `131k–256k`。

---

## 3. 字段与 flag 速查（图例）

### 3.1 画质 flag（显示名末尾 `[...]`，与 m3u 一致）

`[高清]`=1920×1080｜`[4K]`=3840×2160｜`[标清]`=720×576｜无标识=视作标清

### 3.2 动态范围 flag（脚本确定性判定，见 2.7）

| flag | 判定依据 |
| --- | --- |
| `SDR(bt709·8bit)` | transfer=bt709 |
| `SDR(未标注·8bit)` | 色彩字段全空，按 BT.709 隐式处理 |
| `真HDR-HLG(10bit)` | HLG + bt2020 + **≥10bit**（本次未出现） |
| `假HDR-HLG(8bit·仅标签)` | HLG + bt2020 **但仅 8bit** |
| `真HDR10(10bit)` / `假HDR10(8bit·仅标签)` | PQ 版同理（本次未出现） |

### 3.3 扫描方式 flag

`隔行 1080i/tt`（顶场优先）｜`逐行 p`｜`未知(字段缺失)`（ffprobe 未给 field_order，需看 ffmpeg banner 佐证）

---

## 4. 数据总表

### 4.1 编号待确认（2026-11 新增，源自 gist 评论，已本地实测）

> 列很多，GitHub 上可左右滚动查看。`原始数据` 指向该组播地址的探测历史文件。

| 编号 | 频道名称 | 画质 | 动态范围(真伪HDR) | 扫描/帧率 | 视频编码 | 色彩 range/space/transfer/primaries | 音频 | 组播地址 | 建议 group-title | service_name | provider | tvg-id | tvg-name | tvg-logo | 验证(日期) | 原始数据 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| （待定） | 平谷融媒 | 高清 | `SDR(未标注·8bit)` | 隔行 1080i/tt · 25fps(50场) | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 (tv) | AAC-LC 2ch 48kHz 192k | `239.3.1.23:8001` | `[高清]北京` | `pinggu` | `doteck` | | | | ✓直播 2026-11-14 | [📄](channel-probes/239.3.1.23_8001.md) |
| （待定） | 证券服务 | 高清 | `SDR(未标注·8bit)` | 隔行 1080i/tt · 25fps | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 (tv) | AAC-LC 2ch 48kHz 131k | `239.3.1.24:8001` | `[高清]北京IPTV` | `zhengquan` | | | | | ✓直播 2026-11-14 | [📄](channel-probes/239.3.1.24_8001.md) |
| （待定） | 重温经典 | 高清 | `SDR(bt709·8bit)` | 逐行 1080p · 25fps | H.264 Main 8bit L4.0 | tv/bt709/bt709/bt709 | AAC-LC 2ch **44.1kHz** 131k | `239.3.1.25:8001` | `[高清]北京IPTV` | | | | | | ✓直播 2026-11-14 | [📄](channel-probes/239.3.1.25_8001.md) |
| （待定） | CHC动作电影 | 高清 | `SDR(未标注·8bit)` | 隔行 1080i/tt · 25fps(50场) | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 (tv) | **MP2** 2ch 48kHz 192k | `239.3.1.106:8001` | `[高清]北京IPTV` | | | | | | ✓直播 2026-11-14 | [📄](channel-probes/239.3.1.106_8001.md) |
| （待定） | 求索纪录4K | 4K | **`假HDR-HLG(8bit·仅标签)`** | 2160p · 25fps（field 缺失，banner 无隔行标记→逐行） | **HEVC Main 8bit** L6.0 | tv/bt2020nc/**arib-std-b67(HLG)**/bt2020 | AAC-LC 2ch 48kHz 256k | `239.3.1.107:8001` | `[高清]北京IPTV;4K` | `QiuSuo-4K` | `WASU` | | | | ✓直播 2026-11-14 | [📄](channel-probes/239.3.1.107_8001.md) |
| （待定） | 中国天气 | 高清 | `SDR(未标注·8bit)` | 隔行 1080i/tt · 25fps(50场) | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 (tv) | **MP2** 2ch 48kHz 192k | `239.3.1.108:8001` | `[高清]北京IPTV` | | | | | | ✓直播 2026-11-14 | [📄](channel-probes/239.3.1.108_8001.md) |
| （待定） | 环球旅游 | 高清 | `SDR(未标注·8bit)` | 隔行 1080i/tt · 25fps(50场) | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 (tv) | **MP2** 2ch 48kHz 192k | `239.3.1.109:8001` | `[高清]北京IPTV` | | | | | | ✓直播 2026-11-14 | [📄](channel-probes/239.3.1.109_8001.md) |
| （待定） | CCTV16奥林匹克4K〔源1〕 | 4K | **`假HDR-HLG(8bit·仅标签)`** | 2160p · **50fps**（field 缺失→逐行） | **HEVC Main 8bit** L5.1 | tv/bt2020nc/**arib-std-b67(HLG)**/bt2020 | AAC-LC 2ch 48kHz 256k | `239.3.1.206:8001` | `[高清]央视;4K` | `CCTV 16 UHD` | `CCTV` | 7249(建议复用) | CCTV16 | `http://epg.51zmt.top:8000/tb1/CCTV/CCTV16.png`(建议复用) | ✓直播 2026-11-14 | [📄](channel-probes/239.3.1.206_8001.md) |
| （待定） | CCTV16奥林匹克4K〔源2〕 | 4K | **`假HDR-HLG(8bit·仅标签)`** | 2160p · **50fps**（field 缺失→逐行） | **HEVC Main 8bit** L5.1 | tv/bt2020nc/**arib-std-b67(HLG)**/bt2020 | AAC-LC 2ch 48kHz 256k | `239.2.1.206:8000` | `[高清]央视;4K` | `CCTV 16 UHD` | `CCTV` | 7249(建议复用) | CCTV16 | `http://epg.51zmt.top:8000/tb1/CCTV/CCTV16.png`(建议复用) | ✓直播 2026-11-14 | [📄](channel-probes/239.2.1.206_8000.md) |

### 4.2 既有频道（已在 `bj-unicom-iptv.m3u` 中，按 IPTV 编号排序）

> 全部 158 频道已于 2026-11-15 本地实测（通过 udpxy 单播探测）。画质 / 动态范围 / 真伪HDR / 扫描 / 编码 / 音频均由 `probe-and-record.sh` 确定性算出。编号列已按遥控器频道号升序排列；无编号或未知编号的频道排在最后（`—`）。
> 频道名称、tvg-id/name/logo 等 EPG 字段直接取自 `bj-unicom-iptv.m3u` 现有数据，空值待人工补齐。
> `其它(-x-)` 画质 = 探测时流通但 ffprobe 未读到视频元数据（可能为短暂抖动），截图缺失；`未知(transfer=…)` 动态范围 = 传输特性标签存在但不在已知映射内，详见对应 `channel-probes/*.md`。

| 编号 | 频道名称 | 画质 | 动态范围(真伪HDR) | 扫描/帧率 | 视频编码 | 色彩 range/space/transfer/primaries | 音频 | 组播地址 | 建议 group-title | service_name | provider | tvg-id | tvg-name | tvg-logo | 验证(日期) | 原始数据 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | CCTV-1综合 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.129:8008` | [高清]央视 |  |  | 1 | CCTV1 | http://epg.51zmt.top:8000/tb1/CCTV/CCTV1.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.129_8008.md) |
| 2 | CCTV-2财经 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.60:8084` | [高清]央视 |  |  | 2 | CCTV2 | http://epg.51zmt.top:8000/tb1/CCTV/CCTV2.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.60_8084.md) |
| 3 | CCTV-3综艺 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 128k | `239.3.1.172:8001` | [高清]央视 |  |  | 3 | CCTV3 | http://epg.51zmt.top:8000/tb1/CCTV/CCTV3.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.172_8001.md) |
| 4 | CCTV-4中文国际 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.105:8092` | [高清]央视 |  |  | 4 | CCTV4 | http://epg.51zmt.top:8000/tb1/CCTV/CCTV4.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.105_8092.md) |
| 5 | CCTV-5体育 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 128k | `239.3.1.173:8001` | [高清]央视 |  |  | 5 | CCTV5 | http://epg.51zmt.top:8000/tb1/CCTV/CCTV5.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.173_8001.md) |
| 6 | CCTV-6电影 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 128k | `239.3.1.174:8001` | [高清]央视 |  |  | 7 | CCTV6 | http://epg.51zmt.top:8000/tb1/CCTV/CCTV6.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.174_8001.md) |
| 7 | CCTV-7国防军事 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.61:8104` | [高清]央视 |  |  | 8 | CCTV7 | http://epg.51zmt.top:8000/tb1/CCTV/CCTV7.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.61_8104.md) |
| 8 | CCTV-8电视剧 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 128k | `239.3.1.175:8001` | [高清]央视 |  |  | 9 | CCTV8 | http://epg.51zmt.top:8000/tb1/CCTV/CCTV8.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.175_8001.md) |
| 9 | CCTV-9纪录 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.62:8112` | [高清]央视 |  |  | 10 | CCTV9 | http://epg.51zmt.top:8000/tb1/CCTV/CCTV9.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.62_8112.md) |
| 10 | CCTV-10科教 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.63:8116` | [高清]央视 |  |  | 11 | CCTV10 | http://epg.51zmt.top:8000/tb1/CCTV/CCTV10.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.63_8116.md) |
| 11 | CCTV-11戏曲 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.152:8120` | [高清]央视 |  |  | 12 | CCTV11 | http://epg.51zmt.top:8000/tb1/CCTV/CCTV11.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.152_8120.md) |
| 12 | CCTV-12社会与法 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.64:8124` | [高清]央视 |  |  | 13 | CCTV12 | http://epg.51zmt.top:8000/tb1/CCTV/CCTV12.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.64_8124.md) |
| 13 | CCTV-13新闻 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.124:8128` | [高清]央视 |  |  | 14 | CCTV13 | http://epg.51zmt.top:8000/tb1/CCTV/CCTV13.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.124_8128.md) |
| 14 | CCTV-14少儿 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.65:8132` | [高清]央视;少儿 |  |  | 15 | CCTV14 | http://epg.51zmt.top:8000/tb1/CCTV/CCTV14.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.65_8132.md) |
| 15 | CCTV-15音乐 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.153:8136` | [高清]央视 |  |  | 16 | CCTV15 | http://epg.51zmt.top:8000/tb1/CCTV/CCTV15.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.153_8136.md) |
| 16 | CCTV-16奥林匹克 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 128k | `239.3.1.184:8001` | [高清]央视 |  |  | 7249 | CCTV16 | http://epg.51zmt.top:8000/tb1/CCTV/CCTV16.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.184_8001.md) |
| 17 | CCTV-17农业农村 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.151:8144` | [高清]央视 |  |  | 17 | CCTV17 | http://epg.51zmt.top:8000/tb1/CCTV/CCTV17.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.151_8144.md) |
| 18 | CCTV5+ | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.130:8004` | [高清]央视 | CCTV5+HD |  | 6 | CCTV5+ | http://epg.51zmt.top:8000/tb1/CCTV/CCTV5+.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.130_8004.md) |
| 19 | 聚鲨环球精选 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 63k | `239.3.1.179:8001` | [高清]北京IPTV | DXjushahuanqiujingxuanNEW |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.179_8001.md) |
| 20 | 央广购物 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 130k | `239.3.1.222:8001` | [高清]北京IPTV | dxyangguanggouwu1 |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.222_8001.md) |
| 21 | BRTV北京卫视 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 128k | `239.3.1.241:8000` | [高清]北京;[高清]卫视 |  |  | 30 | 北京卫视 | http://epg.51zmt.top:8000/tb1/ws/beijing.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.241_8000.md) |
| 22 | BRTV文艺 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 128k | `239.3.1.242:8000` | [高清]北京 |  |  | 1873 | BTV文艺 | http://epg.51zmt.top:8000/tb1/sheng/BTV文艺.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.242_8000.md) |
| 23 | BRTV纪实科教 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 128k | `239.3.1.115:8000` | [高清]北京 |  |  | 1874 | BTV科教 | http://epg.51zmt.top:8000/tb1/sheng/BTV科教.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.115_8000.md) |
| 24 | BRTV影视 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 127k | `239.3.1.158:8000` | [高清]北京 |  |  | 1875 | BTV影视 | http://epg.51zmt.top:8000/tb1/sheng/BTV影视.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.158_8000.md) |
| 25 | BRTV财经 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 127k | `239.3.1.116:8000` | [高清]北京 |  |  | 1876 | BTV财经 | http://epg.51zmt.top:8000/tb1/sheng/BTV财经.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.116_8000.md) |
| 26 | BRTV体育休闲 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 128k | `239.3.1.243:8000` | [高清]北京 |  |  | 1877 | BTV体育 | http://epg.51zmt.top:8000/tb1/sheng/BTV体育.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.243_8000.md) |
| 27 | BRTV生活 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 128k | `239.3.1.117:8000` | [高清]北京 |  |  | 1878 | BTV生活 | http://epg.51zmt.top:8000/tb1/sheng/BTV生活.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.117_8000.md) |
| 28 | BRTV卡酷少儿 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 127k | `239.3.1.189:8000` | [高清]北京;少儿 |  |  | 67 | 卡酷动画 | http://epg.51zmt.top:8000/tb1/qt/kaku.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.189_8000.md) |
| 29 | BRTV新闻 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 127k | `239.3.1.159:8000` | [高清]北京 |  |  | 1880 | BTV新闻 | http://epg.51zmt.top:8000/tb1/sheng/BTV新闻.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.159_8000.md) |
| 30 | 家有购物精选 | 其它(-x-) | SDR(未标注·8bit) | 未知(字段缺失) | - | 未标注/未标注/未标注/未标注 | - -ch -Hz - | `239.3.1.186:8001` | [高清]北京IPTV | - | - |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.186_8001.md) |
| 32 | 优购物 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 130k | `239.3.1.180:8001` | [高清]北京IPTV | liantongyouguwu |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.180_8001.md) |
| 33 | 时尚购物 | 其它(-x-) | SDR(未标注·8bit) | 未知(字段缺失) | - | 未标注/未标注/未标注/未标注 | - -ch -Hz - | `239.3.1.181:8001` | [高清]北京IPTV | - | - |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.181_8001.md) |
| 34 | 北京IPTV萌宠TV | 高清 | SDR(bt709·8bit) | 逐行 p | H.264 Main 8bit L4.0 | tv/bt709/bt709/bt709 | aac 2ch 44100Hz 132k | `239.3.1.102:8001` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.102_8001.md) |
| 36 | 北京IPTV淘Baby | 高清 | SDR(bt709·8bit) | 逐行 p | H.264 Main 8bit L4.0 | tv/bt709/bt709/bt709 | aac 2ch 44100Hz 109k | `239.3.1.238:8001` | [高清]北京IPTV;少儿 |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.238_8001.md) |
| 37 | 北京IPTV淘剧场 | 高清 | SDR(bt709·8bit) | 逐行 p | H.264 Main 8bit L4.0 | tv/bt709/bt709/bt709 | aac 2ch 44100Hz 131k | `239.3.1.95:8001` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.95_8001.md) |
| 38 | 北京IPTV淘电影 | 高清 | SDR(bt709·8bit) | 逐行 p | H.264 Main 8bit L4.0 | tv/bt709/bt709/bt709 | aac 2ch 44100Hz 130k | `239.3.1.250:8001` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.250_8001.md) |
| 39 | 北京IPTV淘娱乐 | 高清 | SDR(bt709·8bit) | 逐行 p | H.264 Main 8bit L4.0 | tv/bt709/bt709/bt709 | aac 2ch 44100Hz 131k | `239.3.1.100:8001` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.100_8001.md) |
| 40 | 北京IPTV 4K超清 | 4K | 未知(transfer=bt2020-10·8bit) | 未知(字段缺失) | HEVC Main 8bit L15.3 | tv/bt2020/bt2020-10/bt2020 | aac 2ch 48000Hz 131k | `239.3.1.249:8001` | [高清]北京IPTV;4K |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.249_8001.md) |
| 41 | 湖南卫视 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.132:8012` | [高清]卫视 |  |  | 27 | 湖南卫视 | http://epg.51zmt.top:8000/tb1/ws/hunan.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.132_8012.md) |
| 42 | 家有购物 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 130k | `239.3.1.185:8001` | [高清]北京IPTV | jiayougouwuN | FFmpeg |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.185_8001.md) |
| 43 | 央广购物精选 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 130k | `239.3.1.223:8001` | [高清]北京IPTV | dxyangguanggouwu3 |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.223_8001.md) |
| 44 | 江苏卫视 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.135:8028` | [高清]卫视 |  |  | 29 | 江苏卫视 | http://epg.51zmt.top:8000/tb1/ws/jiangsu.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.135_8028.md) |
| 45 | 东方卫视 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.136:8032` | [高清]卫视 |  |  | 31 | 东方卫视 | http://epg.51zmt.top:8000/tb1/ws/dongfang.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.136_8032.md) |
| 46 | 浙江卫视 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.137:8036` | [高清]卫视 |  |  | 28 | 浙江卫视 | http://epg.51zmt.top:8000/tb1/ws/zhejiang.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.137_8036.md) |
| 47 | 湖北卫视 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.138:8044` | [高清]卫视 |  |  | 48 | 湖北卫视 | http://epg.51zmt.top:8000/tb1/ws/hubei.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.138_8044.md) |
| 48 | 天津卫视 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.141:1234` | [高清]卫视 | TJHD |  | 39 | 天津卫视 | http://epg.51zmt.top:8000/tb1/ws/tianjin.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.141_1234.md) |
| 50 | 山东卫视 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.209:8052` | [高清]卫视 |  |  | 38 | 山东卫视 | http://epg.51zmt.top:8000/tb1/ws/shandong.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.209_8052.md) |
| 51 | 辽宁卫视 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.210:8056` | [高清]卫视 |  | Bravo | 36 | 辽宁卫视 | http://epg.51zmt.top:8000/tb1/ws/liaoning.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.210_8056.md) |
| 52 | 安徽卫视 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.211:8064` | [高清]卫视 | AHHD |  | 32 | 安徽卫视 | http://epg.51zmt.top:8000/tb1/ws/anhui.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.211_8064.md) |
| 53 | 黑龙江卫视 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.133:8016` | [高清]卫视 |  |  | 46 | 黑龙江卫视 | http://epg.51zmt.top:8000/tb1/ws/heilongjiang.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.133_8016.md) |
| 55 | 贵州卫视 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.149:8076` | [高清]卫视 |  | Bravo | 44 | 贵州卫视 | http://epg.51zmt.top:8000/tb1/ws/guizhou.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.149_8076.md) |
| 56 | 东南卫视 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.156:8148` | [高清]卫视 | 东南卫视高清 |  | 41 | 东南卫视 | http://epg.51zmt.top:8000/tb1/ws/dongnan.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.156_8148.md) |
| 57 | 重庆卫视 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.122:8160` | [高清]卫视 |  |  | 40 | 重庆卫视 | http://epg.51zmt.top:8000/tb1/ws/chongqing.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.122_8160.md) |
| 58 | 江西卫视 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.123:8164` | [高清]卫视 |  |  | 50 | 江西卫视 | http://epg.51zmt.top:8000/tb1/ws/jiangxi.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.123_8164.md) |
| 59 | 河南卫视高清 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.50:8184` | [高清]卫视 |  | Bravo | 47 | 河南卫视 | http://epg.51zmt.top:8000/tb1/ws/henan.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.50_8184.md) |
| 62 | 甘肃卫视高清 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.201:8180` | [高清]卫视 |  |  | 42 | 甘肃卫视 | http://epg.51zmt.top:8000/tb1/ws/gansu.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.201_8180.md) |
| 63 | 西藏卫视高清 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.166:8188` | [高清]卫视 |  |  | 71 | 西藏卫视 | http://epg.51zmt.top:8000/tb1/ws/xizang.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.166_8188.md) |
| 64 | 新疆卫视高清 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.167:8192` | [高清]卫视 |  |  | 57 | 新疆卫视 | http://epg.51zmt.top:8000/tb1/ws/xinjiang.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.167_8192.md) |
| 66 | 睛彩竞技 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 192k | `239.3.1.125:8001` | [高清]北京IPTV | qingcai1 |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.125_8001.md) |
| 67 | 睛彩篮球 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 192k | `239.3.1.126:8001` | [高清]北京IPTV | qingcai2 |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.126_8001.md) |
| 68 | 睛彩青少 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 192k | `239.3.1.127:8001` | [高清]北京IPTV | qingcai3 |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.127_8001.md) |
| 69 | 睛彩广场舞 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 192k | `239.3.1.128:8001` | [高清]北京IPTV | qingcai4 |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.128_8001.md) |
| 71 | 宁夏卫视 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.169:8212` | [高清]卫视 |  |  | 53 | 宁夏卫视 | http://epg.51zmt.top:8000/tb1/ws/ningxia.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.169_8212.md) |
| 72 | 广东卫视 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.142:8048` | [高清]卫视 |  |  | 33 | 广东卫视 | http://epg.51zmt.top:8000/tb1/ws/guangdong.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.142_8048.md) |
| 73 | 河北卫视 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.148:8072` | [高清]卫视 |  | Bravo | 45 | 河北卫视 | http://epg.51zmt.top:8000/tb1/ws/hebei.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.148_8072.md) |
| 74 | 深圳卫视 | 高清 | SDR(未标注·8bit) | 隔行 1080i/bb | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.134:8020` | [高清]卫视 |  | Bravo | 34 | 深圳卫视 | http://epg.51zmt.top:8000/tb1/ws/shenzhen.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.134_8020.md) |
| 76 | 中国教育1台 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.57:8152` | [高清]北京 | CETV1HD |  |  | 教育1台 | http://epg.51zmt.top:8000/tb1/qt/中国教育1台.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.57_8152.md) |
| 77 | 金鹰纪实 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.58:8156` | [高清]北京IPTV | JYJSHD |  | 2025 | 金鹰纪实 | http://epg.51zmt.top:8000/tb1/ws/jinyingjishi.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.58_8156.md) |
| 78 | 吉林卫视 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.240:8172` | [高清]卫视 |  |  | 51 | 吉林卫视 | http://epg.51zmt.top:8000/tb1/ws/jilin.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.240_8172.md) |
| 79 | 中国交通 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.188:8001` | [高清]北京IPTV | TV-21 | TV-Provider |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.188_8001.md) |
| 81 | BRTV北京卫视SDR | 4K | SDR(bt709·8bit) | 未知(字段缺失) | HEVC Main 8bit L15.0 | tv/bt709/bt709/bt709 | aac 2ch 48000Hz 255k | `239.3.1.22:8001` | [高清]北京;[高清]卫视;4K |  |  | 30 | 北京卫视 | http://epg.51zmt.top:8000/tb1/ws/beijing.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.22_8001.md) |
| 85 | CCTV 4K | 其它(-x-) | SDR(未标注·8bit) | 未知(字段缺失) | - | 未标注/未标注/未标注/未标注 | - -ch -Hz - | `239.3.1.244:2000` | [高清]央视;[高清]北京IPTV;4K | - | - | 106 | CCTV4K | http://epg.51zmt.top:8000/tb1/CCTV/CCTV4k.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.244_2000.md) |
| 86 | CCTV 4K HDR | 4K | 未知(transfer=reserved·10bit) | 未知(字段缺失) | hevc | tv/bt2020/reserved/bt2020 | aac 2ch 48000Hz 260k | `239.3.1.245:2000` | [高清]央视;[高清]北京IPTV;4K |  |  | 106 | CCTV4K | http://epg.51zmt.top:8000/tb1/CCTV/CCTV4k.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.245_2000.md) |
| 121 | BRTV北京卫视 | 标清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L3.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 127k | `239.3.1.225:8000` | [标清]卫视;[标清]北京 |  |  | 30 | 北京卫视 | http://epg.51zmt.top:8000/tb1/ws/beijing.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.225_8000.md) |
| 122 | BRTV文艺 | 标清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L3.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 128k | `239.3.1.226:8000` | [标清]北京 |  |  | 1873 | BTV文艺 | http://epg.51zmt.top:8000/tb1/sheng/BTV文艺.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.226_8000.md) |
| 123 | BRTV纪实科教 | 标清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L3.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 128k | `239.3.1.227:8000` | [标清]北京 |  |  | 1874 | BTV科教 | http://epg.51zmt.top:8000/tb1/sheng/BTV科教.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.227_8000.md) |
| 124 | BRTV影视 | 标清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L3.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 127k | `239.3.1.228:8000` | [标清]北京 |  |  | 1875 | BTV影视 | http://epg.51zmt.top:8000/tb1/sheng/BTV影视.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.228_8000.md) |
| 125 | BRTV财经 | 标清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L3.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 128k | `239.3.1.229:8000` | [标清]北京 |  |  | 1876 | BTV财经 | http://epg.51zmt.top:8000/tb1/sheng/BTV财经.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.229_8000.md) |
| 127 | BRTV生活 | 标清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L3.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 128k | `239.3.1.231:8000` | [标清]北京 |  |  | 1878 | BTV生活 | http://epg.51zmt.top:8000/tb1/sheng/BTV生活.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.231_8000.md) |
| 128 | BRTV卡酷少儿 | 标清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L3.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 127k | `239.3.1.234:8000` | [标清]北京;少儿 |  |  | 67 | 卡酷动画 | http://epg.51zmt.top:8000/tb1/qt/kaku.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.234_8000.md) |
| 129 | BRTV新闻 | 标清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L3.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 128k | `239.3.1.233:8000` | [标清]北京 |  |  | 1880 | BTV新闻 | http://epg.51zmt.top:8000/tb1/sheng/BTV新闻.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.233_8000.md) |
| 131 | BRTV国际频道 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 127k | `239.3.1.235:8000` | 北京 |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.235_8000.md) |
| 139 | 山东教育 | 标清 | SDR(未标注·8bit) | 逐行 p | H.264 High 8bit L3.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 128k | `239.3.1.52:4120` | [标清]北京IPTV | SDJY |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.52_4120.md) |
| 142 | 四川卫视 | 标清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L3.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.29:8288` | [标清]卫视 |  | Bravo | 56 | 四川卫视 | http://epg.51zmt.top:8000/tb1/ws/sichuan.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.29_8288.md) |
| 152 | 广西卫视 | 标清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L3.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.39:8300` | [标清]卫视 |  |  | 43 | 广西卫视 | http://epg.51zmt.top:8000/tb1/ws/guangxi.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.39_8300.md) |
| 154 | 陕西卫视 | 标清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L3.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.41:8140` | [标清]卫视 |  | Bravo | 55 | 陕西卫视 | http://epg.51zmt.top:8000/tb1/ws/shanxi.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.41_8140.md) |
| 155 | 山西卫视 | 标清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L3.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.42:8172` | [标清]卫视 |  | Bravo | 54 | 山西卫视 | http://epg.51zmt.top:8000/tb1/ws/shanxi_.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.42_8172.md) |
| 156 | 内蒙古卫视 | 标清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L3.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.43:8176` | [标清]卫视 |  | Bravo | 52 | 内蒙古卫视 | http://epg.51zmt.top:8000/tb1/ws/neimeng.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.43_8176.md) |
| 157 | 青海卫视 | 标清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L3.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.44:8184` | [标清]卫视 |  |  | 59 | 青海卫视 | http://epg.51zmt.top:8000/tb1/ws/qinghai.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.44_8184.md) |
| 158 | 海南卫视 | 标清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L3.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.45:8304` | [标清]卫视 |  |  | 37 | 旅游卫视 | http://epg.51zmt.top:8000/tb1/ws/lvyou.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.45_8304.md) |
| 163 | 三沙卫视 | 标清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 Main 8bit L3.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.155:4120` | [标清]卫视 |  |  | 72 | 三沙卫视 | http://epg.51zmt.top:8000/tb1/ws/sansha.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.155_4120.md) |
| 164 | 云南卫视 | 标清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L3.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.26:8108` | [标清]卫视 |  |  | 58 | 云南卫视 | http://epg.51zmt.top:8000/tb1/ws/yunnan.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.26_8108.md) |
| 165 | 财富天下 | 其它(-x-) | SDR(未标注·8bit) | 未知(字段缺失) | - | 未标注/未标注/未标注/未标注 | - -ch -Hz - | `239.3.1.53:9136` | [标清]北京IPTV | - | - | 6623 | 财富天下 | http://epg.51zmt.top:8000/tb1/qt/财富天下.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.53_9136.md) |
| 166 | 厦门卫视 | 标清 | SDR(未标注·8bit) | 逐行 p | H.264 High 8bit L3.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 128k | `239.3.1.143:4120` | [标清]卫视 | XMSD |  | 68 | 厦门卫视 | http://epg.51zmt.top:8000/tb1/ws/xiamen.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.143_4120.md) |
| 169 | 金鹰卡通 | 标清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L3.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.51:9252` | 北京IPTV;少儿 |  |  | 69 | 金鹰卡通 | http://epg.51zmt.top:8000/tb1/qt/jinyingkatong.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.51_9252.md) |
| 170 | 嘉佳卡通 | 标清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L3.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.147:9268` | [标清]北京IPTV;少儿 |  |  | 6010 | 嘉佳卡通 | http://epg.51zmt.top:8000/tb1/qt/jiajiakt.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.147_9268.md) |
| 172 | 中国教育2台 | 标清 | SDR(未标注·8bit) | 逐行 p | H.264 High 8bit L3.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 128k | `239.3.1.54:4120` | [标清]北京IPTV | CETV2SD |  | 74 |  | http://epg.51zmt.top:8000/tb1/qt/中国教育2台.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.54_4120.md) |
| 174 | 中国教育4台 | 标清 | SDR(未标注·8bit) | 逐行 p | H.264 High 8bit L3.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 128k | `239.3.1.56:4120` | [标清]北京IPTV | CETV4SD |  | 7245 |  | http://epg.51zmt.top:8000/tb1/qt/中国教育4台.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.56_4120.md) |
| 201 | IPTV收视指南 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.193:8012` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.193_8012.md) |
| 202 | IPTV热播剧场 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.194:9020` | [高清]北京IPTV |  |  | 102 | IPTV热播剧场 | http://epg.51zmt.top:8000/tb1/qt/IPTV热播剧场.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.194_9020.md) |
| 203 | IPTV经典电影 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.195:9024` | [高清]北京IPTV |  |  | 101 | IPTV经典电影 | http://epg.51zmt.top:8000/tb1/qt/IPTV经典电影.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.195_9024.md) |
| 204 | IPTV魅力时尚 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.196:9012` | [高清]北京IPTV |  |  | 104 | IPTV魅力时尚 | http://epg.51zmt.top:8000/tb1/qt/IPTV魅力时尚.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.196_9012.md) |
| 207 | IPTV少儿动画 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.199:9000` | [高清]北京IPTV;少儿 |  |  | 103 | IPTV少儿动画 | http://epg.51zmt.top:8000/tb1/qt/IPTV少儿动画.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.199_9000.md) |
| 301 | 房山电视台 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | ac3 2ch 48000Hz 128k | `239.3.1.96:8001` | [高清]北京 | fangshan | doteck |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.96_8001.md) |
| 320 | 湖南卫视快乐垂钓 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 192k | `239.3.1.164:8001` | [高清]北京IPTV |  |  | 6595 | 快乐垂钓 | http://epg.51zmt.top:8000/tb1/qt/KUAILECHUIDIAO.jpg | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.164_8001.md) |
| 321 | 湖南卫视茶频道 | 其它(-x-) | SDR(未标注·8bit) | 未知(字段缺失) | - | 未标注/未标注/未标注/未标注 | - -ch -Hz - | `239.3.1.165:8001` | [高清]北京IPTV | - | - | 6585 | 茶频道 | http://epg.51zmt.top:8000/tb1/qt/DOCUMENTARY-CHANNEL.jpg | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.165_8001.md) |
| 341 | CCTV-4 中文国际 欧洲 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.213:4220` | [高清]央视 |  |  | 22 | CCTV4EUO | http://epg.51zmt.top:8000/tb1/CCTV/CCTV4EUO.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.213_4220.md) |
| 342 | CCTV-4 中文国际 美洲 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.214:4220` | [高清]央视 |  |  | 23 | CCTV4AME | http://epg.51zmt.top:8000/tb1/CCTV/CCTV4AME.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.214_4220.md) |
| 343 | CGTN 新闻 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.215:4220` | [高清]北京IPTV |  |  | 20 | CGTN | http://epg.51zmt.top:8000/tb1/CCTV/cgtn.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.215_4220.md) |
| 344 | CGTN 记录 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.216:4220` | [高清]北京IPTV |  |  | 20 | CGTN | http://epg.51zmt.top:8000/tb1/CCTV/cgtn.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.216_4220.md) |
| 345 | CGTN 西班牙语 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.217:4220` | [高清]北京IPTV |  |  | 20 | CGTN | http://epg.51zmt.top:8000/tb1/CCTV/cgtn.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.217_4220.md) |
| 346 | CGTN 法语 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.218:4220` | [高清]北京IPTV |  |  | 20 | CGTN | http://epg.51zmt.top:8000/tb1/CCTV/cgtn.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.218_4220.md) |
| 347 | CGTN 阿拉伯语 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.219:4220` | [高清]北京IPTV |  |  | 20 | CGTN | http://epg.51zmt.top:8000/tb1/CCTV/cgtn.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.219_4220.md) |
| 348 | CGTN 俄语 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.1 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 256k | `239.3.1.220:4220` | [高清]北京IPTV |  |  | 20 | CGTN | http://epg.51zmt.top:8000/tb1/CCTV/cgtn.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.220_4220.md) |
| 351 | IPTV城市剧场 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.67:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.67_4120.md) |
| 352 | IPTV军旅剧场 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.68:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.68_4120.md) |
| 353 | IPTV古装剧场 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.69:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.69_4120.md) |
| 354 | IPTV音乐现场 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.70:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.70_4120.md) |
| 355 | IPTV地理 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.71:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.71_4120.md) |
| 356 | IPTV美妆 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.72:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.72_4120.md) |
| 357 | IPTV读书 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.73:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.73_4120.md) |
| 358 | IPTV精选 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.74:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.74_4120.md) |
| 359 | IPTV解密 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.75:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.75_4120.md) |
| 360 | IPTV军事 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.76:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.76_4120.md) |
| 361 | IPTV国学 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.77:4120` | [高清]北京IPTV |  |  | 6590 | 国学 | http://epg.51zmt.top:8000/tb1/qt/SHUOWENJIEZI.jpg | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.77_4120.md) |
| 362 | IPTV戏曲 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.78:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.78_4120.md) |
| 363 | IPTV早教 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.79:4120` | [高清]北京IPTV;少儿 |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.79_4120.md) |
| 364 | IPTV动画 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.80:4120` | [高清]北京IPTV;少儿 |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.80_4120.md) |
| 365 | IPTV好学生 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.81:4120` | [高清]北京IPTV;少儿 |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.81_4120.md) |
| 366 | IPTV鉴赏 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.82:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.82_4120.md) |
| 367 | IPTV墨宝 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.83:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.83_4120.md) |
| 368 | IPTV光影 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.84:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.84_4120.md) |
| 369 | IPTV台球 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.85:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.85_4120.md) |
| 370 | IPTV爱生活 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.86:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.86_4120.md) |
| 371 | IPTV武术 | 高清 | SDR(未标注·10bit) | 未知(字段缺失) | hevc | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.87:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.87_4120.md) |
| 372 | IPTV高网 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.88:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.88_4120.md) |
| 373 | IPTV足球 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.89:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.89_4120.md) |
| 374 | IPTV武侠剧场 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.90:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.90_4120.md) |
| 375 | IPTV喜剧影院 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.91:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.91_4120.md) |
| 376 | IPTV动作影院 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.92:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.92_4120.md) |
| 377 | IPTV家庭影院 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.93:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.93_4120.md) |
| 378 | IPTV星影 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 Main 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 96k | `239.3.1.94:4120` | [高清]北京IPTV |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.94_4120.md) |
| 401 | 爱上4K | 4K | SDR(未标注·8bit) | 未知(字段缺失) | HEVC Main 8bit L15.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 258k | `239.3.1.236:2000` | [高清]北京IPTV;4K |  |  | 7244 | 爱上4K | http://epg.51zmt.top:8000/tb1/sheng/aishang4k.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.236_2000.md) |
| 405 | 湖南卫视4K超高清 | 4K | 真HDR-HLG(10bit) | 未知(字段缺失) | hevc | tv/bt2020/arib-std-b67/bt2020 | aac 2ch 48000Hz 258k | `239.3.1.112:3002` | [高清]卫视;4K |  |  | 26 | 湖南卫视 | https://epg.51zmt.top:8001/tb1/ws/hunan.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.112_3002.md) |
| 406 | 广东卫视4K超高清 | 其它(-x-) | SDR(未标注·8bit) | 未知(字段缺失) | - | 未标注/未标注/未标注/未标注 | - -ch -Hz - | `239.3.1.203:2000` | [高清]卫视;4K | - | - | 33 | 广东卫视 | https://epg.51zmt.top:8001/tb1/ws/guangdong.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.203_2000.md) |
| 407 | 江苏卫视4K超高清 | 4K | 真HDR-HLG(10bit) | 未知(字段缺失) | hevc | tv/bt2020/arib-std-b67/bt2020 | aac 2ch 48000Hz 258k | `239.3.1.113:3003` | [高清]卫视;4K |  |  | 29 | 江苏卫视 | https://epg.51zmt.top:8001/tb1/ws/jiangsu.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.113_3003.md) |
| 408 | 深圳卫视4K超高清 | 其它(-x-) | SDR(未标注·8bit) | 未知(字段缺失) | - | 未标注/未标注/未标注/未标注 | - -ch -Hz - | `239.3.1.202:2000` | [高清]卫视;4K | - | - | 34 | 深圳卫视 | https://epg.51zmt.top:8001/tb1/ws/shenzhen.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.202_2000.md) |
| 409 | 东方卫视4K超高清 | 4K | 真HDR-HLG(10bit) | 未知(字段缺失) | hevc | tv/bt2020/arib-std-b67/bt2020 | aac 2ch 48000Hz 258k | `239.3.1.119:3006` | [高清]卫视;4K |  |  | 31 | 东方卫视 | https://epg.51zmt.top:8001/tb1/ws/dongfang.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.119_3006.md) |
| 410 | 浙江卫视4K超高清 | 4K | 未知(transfer=reserved·10bit) | 未知(字段缺失) | hevc | tv/bt2020/reserved/bt2020 | aac 2ch 48000Hz 258k | `239.3.1.114:3004` | [高清]卫视;4K |  |  | 28 | 浙江卫视 | https://epg.51zmt.top:8001/tb1/ws/zhejiang.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.114_3004.md) |
| 411 | 山东卫视4K超高清 | 4K | 真HDR-HLG(10bit) | 未知(字段缺失) | hevc | tv/bt2020/arib-std-b67/bt2020 | aac 2ch 48000Hz 258k | `239.3.1.144:3005` | [高清]卫视;4K |  |  | 38 | 山东卫视 | https://epg.51zmt.top:8001/tb1/ws/shandong.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.144_3005.md) |
| 412 | 四川卫视4K超高清 | 4K | 真HDR-HLG(10bit) | 未知(字段缺失) | hevc | tv/bt2020/arib-std-b67/bt2020 | aac 2ch 48000Hz 258k | `239.3.1.131:3001` | [高清]卫视;4K |  |  | 56 | 四川卫视 | https://epg.51zmt.top:8001/tb1/ws/sichuan.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.131_3001.md) |
| 421 | BRTV北京卫视HDR | 4K | 真HDR-HLG(10bit) | 未知(字段缺失) | hevc | tv/bt2020/arib-std-b67/bt2020 | ac3 6ch 48000Hz 448k | `239.3.1.118:8001` | [高清]北京;[高清]卫视;4K | BRTV-WS4K | BRTV | 30 | 北京卫视 | http://epg.51zmt.top:8000/tb1/ws/beijing.png | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.118_8001.md) |
| 502 | VBR测试-2 | 高清 | SDR(未标注·8bit) | 逐行 p | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 128k | `239.3.1.140:8001` | 4K |  |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.140_8001.md) |
| 515 | VBR测试-1 | 4K | SDR(未标注·8bit) | 未知(字段缺失) | HEVC Main 8bit L15.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 96k | `239.3.1.139:8001` | 4K | - | - |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.139_8001.md) |
| — | 朝阳融媒 | 高清 | SDR(bt709·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.0 | tv/bt709/bt709/bt709 | mp2 2ch 48000Hz 320k | `239.3.1.163:8001` | [高清]北京 | ChaoyangHD |  |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.163_8001.md) |
| — | 密云电视台 | 高清 | SDR(未标注·8bit) | 隔行 1080i/bb | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 192k | `239.3.1.154:8001` | [高清]北京 | miyun | Encoder |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.154_8001.md) |
| — | 通州融媒 | 高清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L4.0 | 未标注/未标注/未标注/未标注 | aac 2ch 48000Hz 255k | `239.3.1.221:8001` | [高清]北京 | tongzhou | TV-Provider |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.221_8001.md) |
| — | 延庆电视台 | 标清 | SDR(未标注·8bit) | 隔行 1080i/tt | H.264 High 8bit L3.0 | 未标注/未标注/未标注/未标注 | mp2 2ch 48000Hz 128k | `239.3.1.187:8001` | [标清]北京IPTV | yanqingzhu | bwsc |  |  |  | ✓直播 2026-11-15 | [📄](channel-probes/239.3.1.187_8001.md) |
---

## 5. 新增频道逐个说明（质量差异与注意点）

这些差异不便塞进表格单元格，单列于此，便于问题回溯：

1. **平谷融媒（PRM）** `239.3.1.23:8001` — 台标 "PRM"（P=平谷、RM=融媒），service_name `pinggu`、provider `doteck`。**1080i 隔行**（顶场优先），色彩无标签。北京平谷区级融媒频道。
2. **证券服务** `239.3.1.24:8001` — 台标 "证券服务 / NBM"，节目《股动乾坤》。service_name `zhengquan`。1080i，音频码率偏低（131k）。
3. **重温经典** `239.3.1.25:8001` — 唯一**逐行 1080p** 且**显式 bt709 SDR** 的新增频道；音频采样率是特例 **44.1kHz**（其余均 48kHz）。实测播《赌神》。
4. **CHC动作电影** `239.3.1.106:8001` — 台标 "CHC 动作电影"。音频是 **MP2**（非 AAC）。1080i。
5. **求索纪录4K** `239.3.1.107:8001` — service_name `QiuSuo-4K`、provider `WASU`（华数）。**2160p25，打 HLG/bt2020 标签但 HEVC Main=8bit → 假 HDR**，真实 HDR 效果存疑。
6. **中国天气** `239.3.1.108:8001` — 台标 "中国天气"（中国气象局）。音频 MP2。1080i。
7. **环球旅游** `239.3.1.109:8001` — 台标 "Global Travel 环球旅游"。音频 MP2。1080i。
8. **CCTV16奥林匹克4K** `239.3.1.206:8001`（源1）与 `239.2.1.206:8000`（源2） — service_name 均 `CCTV 16 UHD`、provider `CCTV`。**两个源音视频参数完全一致**（HEVC Main 8bit、2160**p50**、bt2020+HLG 假 HDR、AAC 256k），从流元数据看**不是 HDR/SDR 之分，而像主/备两个组播组**。按你的要求显示名用「源1/源2」区分；tvg 建议复用现有 CCTV16（id 7249、CCTV16.png）。
   - 另：gist 评论还给了移动源 `228.1.1.69:8002` / `228.1.1.216:8002`，按「只收北京联通」已忽略。

---

## 6. 数据模板与复现

### 6.1 本表一行的字段模板

```text
| 编号 | 频道名称 | 画质 | 动态范围(真伪HDR) | 扫描/帧率 | 视频编码 | 色彩 range/space/transfer/primaries | 音频 | 组播地址 | 建议 group-title | service_name | provider | tvg-id | tvg-name | tvg-logo | 验证(日期) | 原始数据 |
```

取值约定：
- 画质 ∈ {高清, 4K, 标清, 其它(WxH)}
- 动态范围 ∈ {SDR(bt709·Nbit), SDR(未标注·Nbit), 真HDR-HLG(10bit), 假HDR-HLG(8bit·仅标签), 真HDR10(10bit), 假HDR10(8bit·仅标签)}
- 扫描/帧率：`隔行 1080i/tt · 25fps(50场)`、`逐行 1080p · 25fps`、`2160p · 50fps` 等
- 视频编码：`H.264 High 8bit L4.0`、`HEVC Main 8bit L5.1`、`HEVC Main 10 10bit` 等
- 音频：`AAC-LC 2ch 48kHz 192k`、`MP2 2ch 48kHz 192k` 等

### 6.2 表字段 → m3u 行映射

由本表一行生成 `bj-unicom-iptv.m3u` 的两行：

```text
#EXTINF:-1 tvg-id="<tvg-id>" tvg-name="<tvg-name>" tvg-logo="<tvg-logo>" group-title="<建议 group-title>",<频道名称>[<编号>][<画质>]
rtp://<组播地址>
```

示例（求索纪录4K，编号假设 402）：

```text
#EXTINF:-1 tvg-id="" tvg-name="" tvg-logo="" group-title="[高清]北京IPTV;4K",求索纪录4K[402][4K]
rtp://239.3.1.107:8001
```

### 6.3 复现 / 继续探测的命令

确定性字段全部由固定脚本算出，优先用脚本、少用人工：

```sh
# 批量/单个探测并记录（自动判定画质/真伪HDR/扫描/编码/音频，按组播地址存历史）
./probe-and-record.sh 239.3.1.107:8001
NAME="求索纪录4K" ./probe-and-record.sh 239.3.1.107:8001   # 带频道名提示

# 底层命令（脚本内部用的就是这些）
URL="http://192.168.2.1:8012/rtp/239.3.1.107:8001"
ffprobe -v quiet -print_format json -show_format -show_streams -show_programs -i "$URL"
ffmpeg  -hide_banner -rw_timeout 12000000 -i "$URL" -t 1 -f null - 2>&1 | sed -n '/Input #0/,/Stream mapping/p'
ffmpeg  -nostdin -rw_timeout 12000000 -i "$URL" -vf "fps=1/5" -frames:v 3 shot_%d.png   # 抓台标帧
```

> 整份 m3u 的批量连通性验证另见 [`check_iptv_m3u.sh`](check_iptv_m3u.sh)（同样需先把 `rtp://` 转成 udpxy 的 `http://`）。

---

## 7. 原始探测数据的组织方式

- 目录 [`channel-probes/`](channel-probes/)，**每个组播地址一个文件** `<ip>_<port>.md`（如 `239.3.1.107_8001.md`）。
- 文件内按**探测时间戳**追加记录，**以最新（最后）一条为准**。
- 每条记录含：脚本确定性判定表 + `ffmpeg -i` 原始 banner + `ffprobe` 原始 JSON。
- **同一组播地址日后改了频道或画质**：再次 `./probe-and-record.sh <addr>` 追加新记录，新旧对比即可看出变化，不覆盖历史。
- 组播地址是唯一键：换频道不换地址→同文件追加；换地址→新文件。

---

*本文件由 AI agent 结合固定脚本本地实测生成；确定性字段由 [`probe-and-record.sh`](probe-and-record.sh) 计算，原始数据见 [`channel-probes/`](channel-probes/)。*

<!-- Reviewed by: 🤖 Claude Code (model: Claude Opus 4.8) -->
