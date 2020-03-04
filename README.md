# 1.北京联通IPTV播放列表
- 重排序所有节目频道，按画质+分类排列
- [高清]标识为1080p
- [4K]标识为4K
- 无标识则为标清
- 重命名部分频道名称以及错误频道名称

> - 部分小众频道可能在北京不同的区域会有所区别，例如：朝阳，密云，房山，依然保留在列表中。
> - MacOS 上使用IINA播放器，会有小部分节目源出现闪退，偶尔能播放，但使用VLC/MPV则播放正常

## 在路由器上使用udproxy将组播转单播：
直接下载m3u播放列表文件，查找关键字__rtp://__，并全部替换为: __http://192.168.2.1:8012/rtp/__ 即可
>其中__192.168.2.1:8012__为udproxy的IP和端口

# 2.局域网播放北京联通IPTV方法
北京联通IPTV的完美方案：
https://github.com/OpenGG/bj-unicom-iptv/issues/4
https://exp.newsmth.net/topic/357dabb5a4dc6d5c4c75f96a30209cd9/1

# 3.参考播放列表

https://github.com/OpenGG/bj-unicom-iptv

https://gist.github.com/sdhzdmzzl/93cf74947770066743fff7c7f4fc5820




