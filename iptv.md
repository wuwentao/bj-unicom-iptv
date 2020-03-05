# 1. IPTV中继核心原理
- 光猫获取管理员权限
- 光猫的IPTV可以通过WIFI或者任意有线端口进行连接
- 光猫的IPTV设置里面，可以绑定**固定的WIFI或端口**，也可以***不绑定WIFI或端口***

- 模式A. [光猫][iptv 源端口]----------------[iptv下联端口][路由器IGMP proxy/snooping接口]------[下挂IPTV机顶盒IGMP，播放多播流量]

- 模式B. [光猫][iptv 源端口]----------------[iptv下联端口][udpxy多播源Interface转单播至局域网单播Interface + TCP服务 port 8012]------[下挂PC、平板，电视盒子，播放单播HTTP流量]

A + B 可以同时单独开启或者同时开启，看个人实际使用需求

# 2. 使用udpxy
2. 直接使用udpxy, 中继IPTV某个端口的流量，则无需在路由器上开启IGMP proxy/snooping
- udpxy程序非常小，100kb左右，编译完成以后可以任意拷贝或复制单文件即可运行使用
- udpxy程序根据设备的CPU型号，可以网上搜索并下载已经编译好的版本直接使用，2012年程序已不再更新
- 路由器或者树莓派或者任意下联设备，只要能够安装并运行udpxy程序即可， 设置开机启动即可
- ASUS Merlin 路由器或其他OpenWRT路由器, 或斐讯路由器能刷机的，基本都OK
- 根据对应的CPU和OS，网上搜索udpxy
- 启动udpxy参数说明：
   1. -m （必选） 上联的多播源接口
   2. -a （必选） 下联的单播目的接口
   3. -p （必选)  服务端口号
   4. -c  (可选） 最大运行的客户端数量, 默认值为3个，最大5000个
   5. -B （可选） 多播源接口缓冲区大小，默认2048，可以指定为65535，32Kb, 1Mb等
   6. -l  (可选)  指定log文件保存地址，路由器上可忽略，仅供其他存储空间较大的设备指定
   例子：
   /usr/bin/udpxy -m wlan0 -a eth0 -p 8012 -c 50 -B 32KB
   > 命令行输入后回车，自动后台运行，无需干预
   - 运行成功后可以ps命令查看进程是否存在
   - 局域网使用浏览器查看udpxy的运行状态： http://192.168.2.1:8012/status    [IP为运行udpxy的设备IP，8012为-p参数指定的端口号]

# 3. 使用路由器IGMP proxy/snooping
开启IGMP proxy/snooping的意义是使路由器下挂的IPTV机顶盒能够通过IGMP proxy/snooping去播放上级光猫中的IGMP视频流, 如果是udpxy的流量，则无需开启IGMP功能
- 路由器需支持IPTV或IGMP proxy/snooping
- ASUS Merlin/OpenWRT等路由器固件均支持
