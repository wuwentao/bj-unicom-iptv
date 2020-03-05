# 1.北京联通IPTV播放列表

## 节目源维护：
节目源失效，新增，变化，可提交[issue](https://github.com/wuwentao/bj-unicom-iptv/issues/new)反馈变化
或提交merge request,共同维护与更新准确的节目源列表

## 节目源统计：
***合计***：   165个
- 高清： 54个
- 4K:    2个
- 标清： 109个

## 主要修改
* 重排序所有节目频道，按***画质+分类***排列
* 节目源标题增加关键字来排序并区分节目源
* 标识***高清***为1080p
* 标识***4K***为4K
* 无标识则为***标清***
* 重命名部分频道名称以及错误频道名称
* 验证所有节目源并核对节目名称有效 @2020.03.04

> - 部分小众频道可能在北京不同的区域会有所区别，例如:  ***朝阳，密云，房山***
> - MacOS 上使用***IINA***播放器，会有小部分节目源出现闪退，偶尔能播放，但使用***VLC/MPV***则播放正常

# 2. 在路由器上使用udpxy组播转单播
直接下载[bj-unicom-iptv.m3u](bj-unicom-iptv.m3u)播放列表文件，本地打开文件，查找关键字 `rtp://`，并全部替换为: `http://192.168.2.1:8012/rtp/` 即可使用使用PC播放器播放或者导入电视盒子
>其中***192.168.2.1:8012***为局域网udpxy的IP和端口

# 3.局域网观看北京联通IPTV方法
详情请参考：
[IPTV中继原理](iptv.md)

或参考OpenGG方法：
[北京联通IPTV的完美方案](https://exp.newsmth.net/topic/357dabb5a4dc6d5c4c75f96a30209cd9/1)


# 4.部分参考列表

https://github.com/OpenGG/bj-unicom-iptv

https://gist.github.com/sdhzdmzzl/93cf74947770066743fff7c7f4fc5820   

https://github.com/sdhzdmzzl/bj-unicom-iptv-scanner

http://epg.51zmt.top:8000/

https://iptvtools.readthedocs.io/en/latest/scripts/iptv-filter.html#example

http://m.newsmth.net/article/DigiHome/833031

