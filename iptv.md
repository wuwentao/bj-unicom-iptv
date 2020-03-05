# 1. IPTV中继核心原理
- 光猫获取管理员权限
- 光猫的IPTV可以通过WIFI或者任意有线端口进行连接
- 光猫的IPTV设置里面，可以绑定**固定的WIFI或端口**，也可以***不绑定WIFI或端口***

### IPTV二种工作模式网络拓扑图
![IPTV二种模式网络拓扑图](resource/iptv.png)

说明：
- 模式A: 适合路由器下无需下挂联通赠送的IPTV机顶盒, 运行udpxy即可
`
[光猫][IPTV源端口]--->----[IPTV第一级下联/中继端口][路由器IGMP proxy/snooping转为第二级下联接口]------[下挂IPTV机顶盒，播放IGMP多播流量]
`
- 模式B：适合路由器下面需要下挂联通赠送的IPTV机顶盒，需开启IGMP proxy/snooping
`
[光猫][IPTV源端口]--->----[IPTV第一级下联/中继端口][路由器IGMP proxy/snooping转为第二级下联接口]------[下挂IPTV机顶盒，播放IGMP多播流量]
`

- ***注意***：模式A + 模式B 可以**单独**开启或者**同时**开启，看个人实际使用需求

# 2. 使用udpxy
直接使用`udpxy`, 中继IPTV某个端口的流量，则无需在路由器上开启IGMP proxy/snooping
- `udpxy`程序非常小，100kb左右，编译完成以后可以任意拷贝或复制单文件即可运行使用
- `udpxy`程序根据设备的CPU型号，可以网上搜索并下载已经编译好的版本直接使用，2012年程序已不再更新
- ASUS Merlin 路由器或其他OpenWRT路由器, 或斐讯路由器能刷机的，基本都OK
- 路由器刷机后或者树莓派或者x86软路由等任意下联的IPTV中继设备，只要能够安装并运行`udpxy`程序即可， 设置开机启动即可
- 启动`udpxy`参数说明：
   * `-m` **（必选)** 上联的多播源接口
   * `-a` **（必选)** 下联的单播目的接口
   * `-p` **（必选)** 中继服务运行的端口号
   * `-c`  (可选） 最大运行的客户端数量, 默认值为3个，最大5000个
   * `-B` （可选） 多播源接口缓冲区大小，默认2048，可以指定为65535，32Kb, 1Mb等
   * `-l`  (可选)  指定log文件保存地址，路由器上可忽略，仅供其他存储空间较大的设备指定
   
   举例：
   
   `/usr/bin/udpxy -m wlan0 -a eth0 -p 8012 -c 50 -B 65535`
   > 命令行输入后回车，自动后台运行，无需干预, wlan0 为第一级多播源接口，eth0为第二级下联单播接口，最大客户端50，端口8012, 缓冲65535
   - 运行成功后可以ps命令查看进程是否存在
   - 局域网使用浏览器查看udpxy的运行状态： `http://192.168.2.1:8012/status`    [IP为运行udpxy的设备IP，8012为-p参数指定的端口号]
   
   HTTP网页运行效果图：
   ![HTTP网页运行效果图：](resource/udpxy.png)

udpxy命令行完整帮助文件：
```
ubuntu@raspberrypi:~$ /usr/local/bin/udpxy
udpxy 1.0-23.12 (prod) standard [Linux 5.3.0-1018-raspi2 aarch64]
usage: /usr/local/bin/udpxy [-vTS] [-a listenaddr] -p port [-m mcast_ifc_addr] [-c clients] [-l logfile] [-B sizeK] [-n nice_incr]
	-v : enable verbose output [default = disabled]
	-S : enable client statistics [default = disabled]
	-T : do NOT run as a daemon [default = daemon if root]
	-a : (IPv4) address/interface to listen on [default = 0.0.0.0]
	-p : port to listen on
	-m : (IPv4) address/interface of (multicast) source [default = 0.0.0.0]
	-c : max clients to serve [default = 3, max = 5000]
	-l : log output to file [default = stderr]
	-B : buffer size (65536, 32Kb, 1Mb) for inbound (multicast) data [default = 2048 bytes]
	-R : maximum messages to store in buffer (-1 = all) [default = 1]
	-H : maximum time (sec) to hold data in buffer (-1 = unlimited) [default = 1]
	-n : nice value increment [default = 0]
	-M : periodically renew multicast subscription (skip if 0 sec) [default = 0 sec]
Examples:
  /usr/local/bin/udpxy -p 4022
	listen for HTTP requests on port 4022, all network interfaces
  /usr/local/bin/udpxy -a lan0 -p 4022 -m lan1
	listen for HTTP requests on interface lan0, port 4022;
	subscribe to multicast groups on interface lan1

  udpxy and udpxrec are Copyright (C) 2008-2018 Pavel V. Cherenkov and licensed under GNU GPLv3
  Email: support@udpxy.com; Telegram: GigaX-discussions; Google+: udpxy community

ubuntu@raspberrypi:~$
```
> 树莓派设备可以直接下载源码，安装gcc，解压缩源码，运行make即可成功编译出udpxy，拷贝至任意文件夹即可使用

# 3. 使用路由器IGMP Proxy/Snooping
开启IGMP proxy/snooping的意义是使路由器下挂的IPTV机顶盒能够通过IGMP proxy/snooping去播放上级光猫中的IGMP视频流, 如果是PC等自定义设备去播放`udpxy`的单播流量，则无需开启IGMP功能
- 路由器需支持IPTV或IGMP proxy/snooping
- ASUS Merlin/OpenWRT等路由器固件均支持

如下图为Merlin路由固件开启IGMP Proxy/Snooping + UDPxy同时开启：
   ![Merlin路由器固件开启IGMP Proxy/Snooping + UDPxy同时开启：](resource/merlin.jpg)


# 4. 获取IPTV播放列表
方法A:
1. 通过电脑连接光猫IPTV有线接口
2. 开启Wireshark抓包，过滤只显示HTTP报文即可
3. 电脑开热点共享， IPTV机顶盒连接电脑共享的WIFI热点
4. IPTV机顶盒重启，机顶盒会发出获取频道列表的请求
5. wireshark获取到频道列表，转换成m3u格式

方法B:
1. 树莓派或者其他便携式设备连接光猫IPTV源端口
2. 使用UDP协议连接(扫描)某个固定网段(例如：239.3.1.x或类似地址段)和某些特定的服务端口（例如：8001，1234，9000等），端口可连接成功则是提供IPTV服务
