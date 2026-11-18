# AGENTS.md

本文件是本仓库面向所有 AI 编码助手（Claude Code、OpenAI Codex、GitHub Copilot、Cursor、Gemini CLI、opencode 等）的统一指南。`CLAUDE.md`、`GEMINI.md`、`.github/copilot-instructions.md` 均为指向本文件的软链接。

> 本文件以中文为主，因为仓库内容、频道名称与维护讨论都使用中文。

---

## 1. 项目是什么

这是**北京联通 IPTV 组播节目源**的播放列表仓库。核心产物是一份手工维护的 M3U 播放列表 `bj-unicom-iptv.m3u`，记录北京联通 IPTV 各频道的**组播（multicast）地址**。

- 节目源仅在**北京联通 IPTV 网络**内可用（组播地址段 `239.3.x.x`）。
- 直接下载的列表里是 `rtp://` 组播地址。普通 PC 播放器与电视盒子无法直接播放组播流，需要通过路由器上的 `udpxy` 把组播转成单播（见[第 7 节](#7-局域网如何使用udpxy-组播转单播)）。
- 本仓库**不是软件项目**，没有构建系统、没有依赖安装、没有可运行的服务。主要工作是**维护纯文本数据**（M3U 列表）和配套文档。
- `scripts/` 下是辅助脚本，用于**在北京联通局域网内实测频道**（ffmpeg/ffprobe 探测、分类、生成数据表），运行在能访问组播流的 Ubuntu/树莓派等设备上（见[第 6 节](#6-频道有效性验证-scriptscheck_iptv_m3ush)、[第 11 节](#11-channelsmd-频道数据总表与探测体系)）。探测产出保存在 `channels.md` 与 `channel-probes/`。

### 对 AI agent 最重要的一句话

**改动 `bj-unicom-iptv.m3u` 时要极度小心。** 每个 `rtp://` 地址都是真实有效的组播源，是人工抓包/测试得来的，无法凭空推断或生成。不要臆造、补全或"修复"组播地址；不要重排序后破坏频道编号与分组的对应关系。拿不准就先问，不要猜。

---

## 2. 仓库文件地图

| 文件 / 目录 | 作用 |
| --- | --- |
| `bj-unicom-iptv.m3u` | **核心产物**。北京联通 IPTV 全部频道的 M3U 播放列表，含 EPG、台标、分组、频道编号、组播地址。 |
| `README.md` | 面向最终用户的首页说明：统计、使用方法、参考链接。 |
| `channels.md` | **频道数据总表**。每个频道/源经 ffprobe/ffmpeg 实测的分辨率、动态范围(SDR/HDR)、扫描、编码、音频、service_name、建议显示名、失效清单等；含基础知识科普。见[第 11 节](#11-channelsmd-频道数据总表与探测体系)。 |
| `channel-probes/` | 每个组播地址一个 `<ip>_<port>.md`，保存历次探测的**原始** ffmpeg banner + ffprobe JSON（带时间戳，追加不覆盖）。 |
| `scripts/` | 维护脚本（见[第 11 节](#11-channelsmd-频道数据总表与探测体系)）：`probe-and-record.sh`（探测+分类+记录）、`probe-all-m3u.sh`（批量）、`iptv_classify.py`（共享分类逻辑）、`build_summary.py`、`gen_table.py`、`regen_probe_tables.py`、`check_iptv_m3u.sh`（整表连通性验证）。 |
| `iptv.md` | IPTV 中继原理详解：光猫权限、udpxy、IGMP proxy/snooping、手工组播路由、抓包获取节目源的方法。 |
| `password.md` | 常见北京联通 IPTV 机顶盒的管理密码对照表。 |
| `.github/workflows/ci.yml` | GitHub Actions 工作流（目前是模板占位，见[第 9 节已知问题](#9-已知问题与技术债)）。 |
| `resource/` | 文档用图：`iptv.png`（拓扑图）、`merlin.jpg`、`modem.jpg`、`udpxy.png`。 |
| `AGENTS.md` 及其软链接 | 本文件，AI agent 指南。 |

---

## 3. M3U 数据模型（核心，必读）

`bj-unicom-iptv.m3u` 是 UTF-8 编码（无 BOM）的纯文本。结构如下：

### 3.1 文件头（第 1 行，全文件唯一）

```
#EXTM3U x-tvg-url="http://epg.51zmt.top:8000/e.xml.gz"
```

`x-tvg-url` 指向 EPG（电子节目单）数据源。保持不变，除非 EPG 源整体迁移。

### 3.2 频道条目（每个频道占两行，成对出现）

```
#EXTINF:-1 tvg-id="1" tvg-name="CCTV1" tvg-logo="http://epg.51zmt.top:8000/tb1/CCTV/CCTV1.png" group-title="[高清]央视",CCTV-1综合[1][高清]
rtp://239.3.1.129:8008
```

- **第 1 行 `#EXTINF`**：频道元数据，字段含义见下表。
- **第 2 行 `rtp://`**：该频道的组播地址，格式 `rtp://<组播IP>:<端口>`。

**不变式（agent 必须维持）：每个 `#EXTINF` 行后面必须紧跟且只跟一行 `rtp://` 地址。** 不能出现两个连续 `#EXTINF`，也不能出现没有前导 `#EXTINF` 的 `rtp://`。

### 3.3 `#EXTINF` 字段详解

以 `CCTV-1综合[1][高清]` 为例：

| 字段 | 示例值 | 含义与来源 |
| --- | --- | --- |
| `tvg-id` | `"1"` | EPG 频道 ID，来自 `http://epg.51zmt.top:8000`。用于匹配节目单。 |
| `tvg-name` | `"CCTV1"` | EPG 频道名，来自同一 EPG 源。 |
| `tvg-logo` | `"http://epg.51zmt.top:8000/tb1/CCTV/CCTV1.png"` | 台标图片 URL，来自同一 EPG 源。 |
| `group-title` | `"[高清]央视"` | 分组标签，决定频道在播放器中归入哪个分组。详见 [3.4](#34-group-title-分组规则)。 |
| 显示名（逗号后） | `CCTV-1综合[1][高清]` | 播放器里显示的频道名。格式见 [3.5](#35-显示名命名规则)。 |

> `tvg-id` / `tvg-name` / `tvg-logo` 的取值目前统一采用 `http://epg.51zmt.top:8000` 的数据。其他 EPG 源是否沿用相同的 `tvg-id` 尚未确认，当前直接使用 51zmt 的数据即可。

### 3.4 `group-title` 分组规则

`group-title` 由**两个维度**组合，用英文分号 `;` 可挂多个分组：

- **维度一·画质前缀**：`[高清]` / `[标清]`（4K 频道的内容组仍带 `[高清]`，其 4K 身份由横切标签 `4K` 表达）。
- **维度二·内容分类**：`央视` / `卫视` / `北京` / `北京IPTV`，以及**跨画质横切标签** `4K`、`少儿`。

示例：

- `group-title="[高清]央视;少儿"`（CCTV-14 少儿，既在央视高清组也在少儿组）
- `group-title="[高清]北京;[高清]卫视"`（北京卫视，既是北京频道也是卫视）
- `group-title="[高清]卫视;4K"`（4K 卫视频道：内容在高清卫视组，另进 4K 组）

当前出现过的分组（可能随维护变化，以文件实际内容为准）：`[高清]央视`、`[高清]卫视`、`[高清]北京`、`[高清]北京IPTV`、`[标清]卫视`、`[标清]北京`、`[标清]北京IPTV`、`4K`、`少儿` 等及其分号组合。分组维度、各组计数与面向使用的分组选择建议详见 `channels.md §3.2`。

> ⚠️ **强制匹配规则（必须满足，见 [3.5](#35-显示名命名规则) 末尾）**：频道的**实测画质**、**group-title 画质前缀/标签**、**显示名后缀** 三者必须一致，不得自相矛盾。

### 3.5 显示名命名规则

显示名（`#EXTINF` 行最后一个逗号之后的内容）遵循约定：

```
<频道名><[频道编号]><[画质/质量标识...]>
```

- **频道名**：如 `CCTV-1综合`、`BRTV北京卫视`、`湖南卫视`。北京台统一用 `BRTV` 前缀。4K 频道名里**不要**再重复"4K超高清/超清/SDR/HDR"（这些由质量标识表达），例如 `湖南卫视4K超高清` → `湖南卫视`。
- **`[频道编号]`**：IPTV 遥控器上对应的频道号，如 `[1]`、`[21]`、`[405]`。范围约 1–515，**不连续**。这是真实的物理频道号，不是数组下标。
- **`[画质/质量标识]`**：见下表的**新版约定**。

#### 画质/质量标识约定（新版，务必遵守）

分辨率仍分三档（也决定 `group-title` 归组：1080p/1080i 都归「高清」）：

| 档位 | 显示名标识 | 说明 |
| --- | --- | --- |
| 高清·逐行 | `[高清][1080p]` | **保留 `[高清]`，其后追加 `[1080p]`** |
| 高清·隔行 | `[高清][1080i]` | **保留 `[高清]`，其后追加 `[1080i]`** |
| 高清·扫描未定 | `[高清]` | ffprobe 未给扫描字段时只保留 `[高清]` |
| 4K·10bit HDR | `[4K HDR]` | 3840×2160 + 10bit + HLG/PQ |
| 4K·8bit SDR | `[4K SDR]` | 3840×2160 + 8bit（即使带 bt2020/HLG 标签） |
| 标清 | `[标清]` | 720×576；历史遗留无标识的也视作标清 |

示例（改名方向）：

```
CCTV-1综合[1][高清]        → CCTV-1综合[1][高清][1080i]
CCTV-3综艺[3][高清]        → CCTV-3综艺[3][高清][1080p]
湖南卫视4K超高清[405][4K]  → 湖南卫视[405][4K HDR]
BRTV北京卫视SDR[81][4K]    → BRTV北京卫视[81][4K SDR]
```

- **1080p / 1080i 不是新画质档，仍属"高清"**；`group-title` 的 `[高清]` 不变，只是显示名尾部多一个扫描标识。
- `[1080p]`/`[1080i]`/`[4K SDR]`/`[4K HDR]` **由脚本按实测确定性算出**（见[第 11 节](#11-channelsmd-频道数据总表与探测体系)），不要手工臆断；`channels.md §5.2` 的「频道名称(建议显示名)」列即为改名目标值。
- 判定依据（SDR/HDR 看**位深**，不看标签真伪）：10bit+HLG/PQ=HDR；8bit=SDR。科普见 `channels.md` 第 2 节。

#### ⚠️ 强制匹配规则（分辨率 ↔ 分组 ↔ 后缀，必须满足）

**每个频道的「实测分辨率/动态范围」「group-title 画质前缀/标签」「显示名后缀」三者必须一一对应，不得矛盾。** 新增或改动频道、重排序、补分组时都要据此核对；发现不符按实测为准改正。

| 实测分类 | group-title 必须 | 显示名后缀必须 |
| --- | --- | --- |
| 1080p（1920×1080 逐行） | 含 `[高清]…`，**不含** `4K` | `[高清][1080p]` |
| 1080i（1920×1080 隔行） | 含 `[高清]…`，**不含** `4K` | `[高清][1080i]` |
| 高清（扫描未定） | 含 `[高清]…`，**不含** `4K` | `[高清]` |
| 4K SDR（3840×2160·8bit） | 内容组带 `[高清]…` + 横切 `4K` 标签 | `[4K SDR]` |
| 4K HDR（3840×2160·10bit） | 内容组带 `[高清]…` + 横切 `4K` 标签 | `[4K HDR]` |
| 标清（720×576/560） | 含 `[标清]…` | `[标清]` |

> 反例（本 PR 已修正）：`VBR测试-2[502]` 实测 1080p 却挂 `group-title="4K"` → 改为 `[高清]北京IPTV`。
> 自检命令见 `channels.md §8.2`（`gen_table.py` + awk 校验），或[第 8 节](#8-常用核对与维护命令)。

### 3.6 组播地址

- 全部位于 `239.3.x.x` 组播段（IPTV 专用）。
- 格式 `rtp://<IP>:<端口>`，端口各频道不同（如 `8008`、`8001`、`8000`、`4220` 等）。
- **这些地址是实测得来的，不可推断、不可生成、不可"纠错"。** 新增频道的地址只能来自真实抓包或用户/issue 提供。

---

## 4. 频道统计（当前快照）

当前 `bj-unicom-iptv.m3u` 共 **168** 个频道。统计**一级按 4K / 高清 / 标清**，二级再细分（标清不细分），见 `channels.md §5.1`：

| 一级分类 | 分辨率 | 二级分类 | 数量 | 一级合计 |
| --- | --- | --- | --- | --- |
| **4K** | 3840×2160 | 4K HDR（10bit） | 10 | **17** |
| | | 4K SDR（8bit） | 7 | |
| **高清** | 1920×1080 | 1080p（逐行） | 61 | **127** |
| | | 1080i（隔行） | 65 | |
| | | 高清（扫描未定） | 1 | |
| **标清** | 720×576 | 标清（不细分） | 24 | **24** |
| | | **合计** | | **168** |

> 另有 5 个探测连通但无视频元数据的失效源，**已从 m3u 移除**，登记在 `channels.md §5.3`（不计入 168）。
> 显示名在 `[高清]` 后追加 `[1080p]`/`[1080i]`，4K 用 `[4K SDR]`/`[4K HDR]`。
> 修改 m3u 后请同步更新 README 与 `channels.md`（重跑 `scripts/build_summary.py` + `scripts/gen_table.py`）。不要以 README 旧值为准，始终以脚本核对的实际值为准。

---

## 5. 排序与组织约定

频道在文件中的顺序 = 在播放器/电视盒子里的呈现顺序，因此顺序本身是有意义的。总体按**画质 + 分类**排列，大致顺序为：

1. `[高清]央视`（CCTV 系列）
2. `[高清]北京` / `[高清]卫视`（BRTV 北京台、各省市卫视）
3. `[高清]北京IPTV`（北京本地 IPTV 频道、少儿等）
4. `4K` 频道集中一段
5. `[标清]…`（传统标清频道垫底）

维护顺序时的原则：

- **同一频道的编号、分组、画质、组播地址四者绑定，整体移动，不要拆散。**
- 重排序只调整 `#EXTINF`+`rtp://` 成对的块，不要只移动其中一行。
- 新增频道时，放到对应画质与分类的区段内，并确认 `[频道编号]` 与 IPTV 遥控器实际一致。

---

## 6. 频道有效性验证：`scripts/check_iptv_m3u.sh`

该脚本用 **ffmpeg/ffprobe 逐个探测每个频道是否真实有效**，并记录分辨率、音视频轨道、截图与统计报告。它是维护节目源质量的主要工具。

### 6.1 运行环境与依赖

- 运行在**北京联通局域网内**、能访问 IPTV 流的设备上（脚本注释示例为 Ubuntu / 树莓派）。在没有组播流的普通机器上跑不出有效结果。
- 依赖 `ffmpeg`（含 `ffprobe`）、`jq`、`bc`：

  ```sh
  sudo apt update && sudo apt install ffmpeg jq bc
  ```

  脚本启动时会检查这三者是否存在，缺失则报错退出。
- 脚本开头设置 `LANG=C.UTF-8` / `LC_ALL=C.UTF-8`，以正确处理中文频道名。

### 6.2 关键前提：只探测 `http://` 地址，不直接探测 `rtp://`

脚本里对每个频道的 URL 做了判断：**只有以 `http` 开头的地址才会被 ffprobe 探测**，否则记为无效并跳过。原始 `bj-unicom-iptv.m3u` 里是 `rtp://` 组播地址，**不能直接喂给脚本**。

正确用法是先把组播转成 udpxy 单播地址，再验证：

1. 复制一份播放列表：`cp bj-unicom-iptv.m3u iptv.m3u`
2. 把 `iptv.m3u` 里的 `rtp://` 全部替换为 `http://<udpxy_ip>:<port>/rtp/`（例：`http://192.168.2.1:8012/rtp/`）
3. 在局域网设备上运行脚本：`./scripts/check_iptv_m3u.sh`

> 提示：逐个频道的探测+分类+原始数据记录，推荐用 `scripts/probe-and-record.sh` / `scripts/probe-all-m3u.sh`（见[第 11 节](#11-channelsmd-频道数据总表与探测体系)），它直接吃 `rtp://`（内部走 udpxy），并自动判定 1080i/1080p/4K SDR/4K HDR。

> 注意：脚本当前把输入文件名**硬编码为 `iptv.m3u`**（变量 `M3U_FILE="iptv.m3u"`），而仓库里的列表叫 `bj-unicom-iptv.m3u`。这是一个已知的不一致，见[第 9 节](#9-已知问题与技术债)。

### 6.3 脚本做了什么

对每一对 `#EXTINF` + URL：

1. 解析频道名（取最后一个逗号后的内容），处理缺名等异常。
2. `ffprobe` 探测视频/音频轨道（编解码、分辨率、帧率、声道、采样率），带超时（默认 `FFPROBE_TIMEOUT=10` 秒）。
3. 根据分辨率判定画质标识：`1920x1080`→`高清`，`3840x2160` 或 `0x0`→`4K`，`720x576`/`720x560`→`标清`，其他→`其它`，连不上或无视频→`错误`。
4. 若有视频轨道，`ffmpeg` 在第 5 秒截一帧图（默认 `FFMPEG_TIMEOUT=10` 秒）。
5. 比对**显示名里的画质标识**与**实测画质**，不一致记入 `mismatch.log`。
6. 生成修正后的新列表 `modified_iptv.m3u`：更新画质标识，并**剔除所有连不上（connect_flag=false）的频道**。

### 6.4 输出产物

每次运行在当前目录生成一个带时间戳的目录 `iptv_YYYYMMDD_HHMMSS/`，内含：

| 文件 | 内容 |
| --- | --- |
| `results.csv` | 结果汇总（UTF-8 带 BOM，方便 Excel 打开中文）：编号、频道名、视频轨、音频轨、截图名、连接 flag、分辨率 flag。 |
| `script.log` | 完整运行日志（含每步耗时）。 |
| `screenshots/` | 各频道截图，命名 `${编号}_${频道名}.png`。 |
| `skipped_lines.log` | 被跳过的行号与内容（调试用）。 |
| `mismatch.log` | 显示名画质与实测画质不一致的记录。 |
| `modified_iptv.m3u` | 修正画质标识、剔除失效频道后的新列表。 |

### 6.5 如何用验证结果维护仓库

- 用 `results.csv` 和 `mismatch.log` 找出**失效频道**和**画质标注错误**的频道。
- **不要直接用 `modified_iptv.m3u` 覆盖 `bj-unicom-iptv.m3u`**：后者保留了人工排序、分组、编号和 EPG 字段，而脚本的修正可能丢失这些信息或误删临时抖动的频道。应**以验证结果为参考，手工改回主列表**。
- 可调参数：`FFPROBE_TIMEOUT`、`FFMPEG_TIMEOUT`（脚本顶部，单位秒）。网络较慢时可调大。

---

## 7. 局域网如何使用（udpxy 组播转单播）

最终用户的核心用法（README 已写明）：

1. 下载 `bj-unicom-iptv.m3u`。
2. 用文本编辑器把全部 `rtp://` 替换为 `http://192.168.2.1:8012/rtp/`（其中 `192.168.2.1:8012` 是局域网内运行 `udpxy` 的 IP 和端口，按实际环境改）。
3. 用 PC 播放器（VLC / MPV 推荐；IINA 对少数源可能闪退）播放，或导入电视盒子。

udpxy 的部署、IGMP proxy/snooping、手工组播路由、抓包获取节目源等原理与操作，详见 `iptv.md`。

---

## 8. 常用核对与维护命令

在仓库根目录运行（不需要联通网络，纯文本检查）：

```sh
# 总频道数 / 组播地址数（两者必须相等）
grep -c '^#EXTINF' bj-unicom-iptv.m3u
grep -c '^rtp://'   bj-unicom-iptv.m3u

# 画质统计（按显示名末尾标识）
names=$(grep '^#EXTINF' bj-unicom-iptv.m3u | sed 's/.*,//')
printf '高清: %s\n' "$(printf '%s\n' "$names" | grep -c '\[高清\]$')"
printf '4K:   %s\n' "$(printf '%s\n' "$names" | grep -c '\[4K\]$')"
printf '标清: %s\n' "$(printf '%s\n' "$names" | grep -c '\[标清\]$')"

# 分组清单与各组频道数
grep -o 'group-title="[^"]*"' bj-unicom-iptv.m3u | sort | uniq -c | sort -rn

# 结构校验：确保 #EXTINF 与 rtp:// 严格成对、无孤行
awk '/^#EXTINF/{if(p=="e")print "ERR dup EXTINF @"NR; p="e"; next}
     /^rtp:/{if(p!="e")print "ERR rtp without EXTINF @"NR; p="r"; next}
     {p="o"}' bj-unicom-iptv.m3u

# 找出缺少 EPG 元数据（tvg-id 为空）的频道
grep -n 'tvg-id=""' bj-unicom-iptv.m3u

# 强制匹配规则自检（§3.5）：分辨率 ↔ group-title ↔ 显示名后缀 三者一致
python3 scripts/gen_table.py   # → /tmp/channels_table.md
awk -F'|' 'NR>2 && NF>3{cat=$4;grp=$12;gsub(/^ +| +$/,"",cat);gsub(/^ +| +$/,"",grp);
  if(grp~/4K/ && cat!~/^4K/) print "ERR 非4K挂4K组: "$2;
  if(cat~/^4K/ && grp!~/4K/) print "ERR 4K缺4K标签: "$2;
  if(cat~/1080|高清/ && (grp!~/\[高清\]/||grp~/4K/)) print "ERR 高清分组不符: "$2;
  if(cat=="标清" && grp!~/\[标清\]/) print "ERR 标清分组不符: "$2}' /tmp/channels_table.md
```

**改动 m3u 后的自检清单：**

1. `#EXTINF` 行数 == `rtp://` 行数。
2. awk 结构校验无 `ERR` 输出。
3. 画质统计与 README 一致（如有变化同步更新 README）。
4. 新增/改动频道的 `[编号]`、`group-title`、画质标识、组播地址彼此对应无误。
5. **强制匹配规则自检**（上方 awk）无 `ERR`：实测分辨率 ↔ group-title ↔ 显示名后缀三者一致（见 [3.5](#35-显示名命名规则)）。

---

## 9. 已知问题与技术债

供 agent 参考，**未经用户确认不要擅自大改**，但发现时可提出或在相关 PR 中一并修复：

- **README 统计可能过时**：历史上写过 `213/116/13/25`，与实际不符。以第 4 节与第 8 节脚本核对值为准。
- **验证脚本输入文件名不一致**：`scripts/check_iptv_m3u.sh` 硬编码 `M3U_FILE="iptv.m3u"`，仓库列表名为 `bj-unicom-iptv.m3u`。使用时需手工复制/改名（见 6.2），或改脚本。
- **失效源处理流程（标准操作）**：探测连通但 `ffprobe` 读不到视频元数据的源，**从 `bj-unicom-iptv.m3u` 移除**，并在 `channels.md §5.3` removed list 登记（保留组播地址、移除前名称、原始数据链接），供日后复测；若换时段 `./scripts/probe-and-record.sh <addr>` 恢复，再加回 m3u。本 PR 已据此移除 5 个源（`CCTV 4K[85]`、`家有购物精选[30]`、`时尚购物[33]`、`湖南卫视茶频道[321]`、`财富天下[165]`）。`广东卫视4K[406]`/`深圳卫视4K[408]` 的旧 `*:2000` 源已换为活源 `239.3.1.27/28:2000`。
- **CI 工作流指向错误分支且仍是模板**：`.github/workflows/ci.yml` 的 `on.push` / `on.pull_request` 监听 `master`，而仓库默认分支是 `main`，因此实际从不触发；且内容只是 `echo Hello, world!` 占位，没有真正的校验逻辑。
- **部分频道缺 EPG 元数据**：约有数十条 `tvg-id=""`/`tvg-name=""`/`tvg-logo=""`，这些频道在支持 EPG 的播放器里不显示节目单和台标。补全需从 EPG 源查到对应 id。
- **文件末尾无换行符**：`bj-unicom-iptv.m3u` 最后一行没有结尾换行，追加内容时注意先补一个换行再追加。
- **地域差异**：部分小众频道在北京不同区域（朝阳、密云、房山等）可能不同；MacOS 的 IINA 播放器对少数源会闪退，VLC/MPV 正常。

---

## 10. AI Agent 工作约定

- **语言**：文档与提交说明用中文（与仓库风格一致），代码/命令用英文。
- **最小改动**：这是数据仓库，不要引入构建系统、依赖、框架或大规模重构。只做用户要求的改动。
- **保护数据**：绝不臆造组播地址或 EPG 字段；绝不用脚本输出直接覆盖主列表；重排序保持成对块完整。
- **改完即核对**：任何对 `bj-unicom-iptv.m3u` 的改动，都要跑第 8 节的自检清单，并在 PR 描述里附上核对结果。
- **提 PR**：改动通过 Pull Request 提交，描述里说明改了什么、为什么、如何核对。
- **GitHub Markdown 发布**：创建/编辑 PR 或 issue 的多行正文时，把 Markdown 写入临时 `.md` 文件并用 `--body-file` 发布，不要把带 `\n` 的字符串塞进 `--body`，发布后用 `gh pr view` 核对换行与渲染。
- **相关仓库**（同一维护者的其他城市/运营商列表，改动时可参照其风格）：
  - 北京联通 <https://github.com/wuwentao/bj-unicom-iptv>（本仓库）
  - 北京电信 <https://github.com/wuwentao/bj-telecom-iptv>
  - 北京移动 <https://github.com/wuwentao/bj-mobile-iptv>

---

## 11. channels.md 频道数据总表与探测体系

`channels.md` + `channel-probes/` + `scripts/` 构成一套**确定性**的频道实测数据体系。核心原则：**能用固定脚本确定性算出的，一律脚本算，不靠 AI/人工臆断**；只有「看台标认频道名」「定 group-title」才需人工。

### 11.1 组成

| 部分 | 作用 |
| --- | --- |
| `scripts/probe-and-record.sh` | 探测单个组播地址：经 udpxy 拉流 → ffprobe/ffmpeg → 确定性判定 画质/分辨率/动态范围(SDR/HDR)/扫描/编码/音频/显示名后缀 → 按 `channel-probes/<ip>_<port>.md` **追加**记录（含原始 banner+JSON+时间戳）→ 可选截图 + 摘要 TSV。 |
| `scripts/probe-all-m3u.sh` | 批量：解析 m3u 逐个调用上面脚本，可断点续跑。 |
| `scripts/iptv_classify.py` | **共享分类逻辑**（与 bash `classify()` 规则一致）：从 ffprobe JSON 算出 cat/name_suffix 等。改判定规则**只改这里 + bash classify()**，保持两者同步。 |
| `scripts/build_summary.py` | 读 `channel-probes/*.md` 内嵌 JSON → 重建合并摘要 `channel-probes/_all_summary.tsv`。 |
| `scripts/gen_table.py` | 合并 m3u 元数据 + 摘要 TSV → 生成 `channels.md §5.2` 总表（18 列，按 IPTV 编号排序）。**以 m3u 为最终真源**，不含 override 区。 |
| `scripts/regen_probe_tables.py` | 术语/规则变更后，从已存 JSON **重算**所有 `channel-probes/*.md` 判定表，**不重新探测**。 |
| `channel-probes/<ip>_<port>.md` | 单个组播地址的探测历史，新记录追加在末尾，**以最新一条为准**；换频道不换地址→同文件追加，换地址→新文件。 |

### 11.2 确定性判定规则（务必与脚本一致）

- **位深**：`pix_fmt` 含 `10le/10be/p010/10`→10bit，含 `12`→12bit，否则 8bit。
- **画质**：1920×1080→高清；3840×2160→4K；720×576/560→标清；其他→其它(WxH)。
- **动态范围（SDR/HDR 看位深，不看"标签真伪"）**：`transfer` 为 HLG(`arib-std-b67`)/PQ(`smpte2084`)/`bt2020-10` 且 **≥10bit** → HDR；否则 SDR（8bit 带 HLG/bt2020 标签也判 SDR，注明"带…标签但非10bit"）。
- **扫描**：`field_order=tt/bb/tb/bt`→隔行(i)；`progressive`→逐行(p)；空→未知。
- **显示名后缀**：高清→`[高清][1080p]`/`[高清][1080i]`/`[高清]`；4K→`[4K SDR]`/`[4K HDR]`；标清→`[标清]`（规则同[第 3.5 节](#35-显示名命名规则)）。

### 11.3 格式要求（防止后续 AGENT 改错）

- **`channels.md §5.2` 每行 18 列**，表头固定为：`编号 | 频道名称(显示名) | 统计分类 | 分辨率 | 动态范围 | 扫描 | 视频编码 | 音频 | 组播地址 | 源 | group-title | service_name | provider | tvg-id | tvg-name | tvg-logo | 验证 | 原始数据`（`tvg-logo` 在 `tvg-name` 之后，便于直接复制生成 m3u）。**不要手改表体**——改数据改源头（probe 记录 / m3u），然后重跑 `gen_table.py` 生成。
- **生成链路（改完任一环节按序重跑）**：`probe-and-record.sh`（新/变更源）→ `regen_probe_tables.py`（若改了分类规则）→ `build_summary.py` → `gen_table.py` → 把 `/tmp/channels_table.md` 并入 `channels.md §5.2`。完整分步流程与「每个脚本在哪一步、解决什么」见 `channels.md §7`。
- **脚本路径无关 cwd**：Python 脚本用 `__file__` 定位仓库根，bash 用 `ROOT_DIR="$SCRIPT_DIR/.."`；新增脚本请沿用，别写死相对路径。
- **瞬时产物**（`_m3u_summary.tsv`/`_done_keys.tmp`/`_m3u_progress.log`/`_candidates_summary.tsv`）已在 `channel-probes/.gitignore` 忽略；**保留并提交** `_all_summary.tsv` 与各 `<ip>_<port>.md`。
- **原始数据只增不改**：`channel-probes/*.md` 里的 ffmpeg banner + ffprobe JSON 是实测存档，复测用脚本**追加**新记录，不要手工编辑或删除历史。
- **依赖**：`ffmpeg`/`ffprobe`/`jq`（Ubuntu `apt install ffmpeg jq`）。探测必须在**能访问北京联通组播的局域网**内跑。

### 11.4 什么该脚本、什么该人工

| 字段 | 来源 |
| --- | --- |
| 分辨率/画质/动态范围/扫描/编码/音频/显示名后缀/service_name/provider | **脚本确定性算出** |
| 频道名称（看台标认台） | 人工/AI（截图在 `~/Downloads/iptv-new-channels-screenshots/` 等） |
| group-title 归组、IPTV 频道编号 | 人工（机顶盒核对） |
| tvg-id/tvg-name/tvg-logo | 取自 EPG 源 `epg.51zmt.top`，缺失留空 |

---

## 12. 参考资料

- EPG 台标与节目单源：<http://epg.51zmt.top:8000/>（EPG 配置页 <https://epg.51zmt.top:8001/>）
- IPTV 中继原理与抓包方法：见本仓库 `iptv.md`
- 机顶盒管理密码：见本仓库 `password.md`

---

*本文件由 AI agent 依据 `init-ai-agent` 流程生成，覆盖仓库结构、M3U 数据模型、探测体系与维护约定。*

<!-- Reviewed by: 🤖 Claude Code (model: Claude Opus 4.8) -->
