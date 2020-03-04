# 1.北京联通IPTV播放列表
* 重排序所有节目频道，按***画质+分类***排列
* 标识***[高清]***为1080p
* 标识***[4K]***为4K
* 无标识则为***标清***
* 重命名部分频道名称以及错误频道名称

> - 部分小众频道可能在北京不同的区域会有所区别，例如:  ***朝阳，密云，房山***
> - MacOS 上使用***IINA***播放器，会有小部分节目源出现闪退，偶尔能播放，但使用***VLC/MPV***则播放正常

## 在路由器上使用udproxy将组播转单播：
直接下载m3u播放列表文件，查找关键字 ***rtp://***，并全部替换为: ***http://192.168.2.1:8012/rtp/*** 即可
>其中***192.168.2.1:8012***为udproxy的IP和端口

# 2.局域网观看北京联通IPTV方法
北京联通IPTV的完美方案：

https://github.com/OpenGG/bj-unicom-iptv/issues/4

https://exp.newsmth.net/topic/357dabb5a4dc6d5c4c75f96a30209cd9/1

# 3.参考播放列表

https://github.com/OpenGG/bj-unicom-iptv

https://gist.github.com/sdhzdmzzl/93cf74947770066743fff7c7f4fc5820   




