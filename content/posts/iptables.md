---
title: "iptables"
subtitle: ""
date: 2017-09-27T15:58:21+08:00
lastmod: 2017-09-27T15:58:21+08:00
draft: false
author: "山脚下的脚下山"
authorLink: ""
description: ""

tags: ["iptables"]
categories: ["运维"]

hiddenFromHomePage: false
hiddenFromSearch: false

featuredImage: ""
featuredImagePreview: ""

toc:
  enable: true
math:
  enable: false
lightgallery: false
license: ""
---
# iptables 简单入门介绍

> iptables 是组成Linux平台下的包过滤防火墙。提到iptables就不能不提到netfliter。这里可以简单理解iptables是客户端，而真正进行包过滤的是内核中的netfliter组件。

## 一、网络基础知识

### 1.1、网络分层模型

![img](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2021-04-24/08:41:22-v2-8846b3d85c724a94e13419a4ab3a4644_1440w.jpg)

还有一个四层模型，是将五层模型中的数据链路及物理层合并为网络接口层(链路层)

1. 物理层：主要负责在物理载体上的数据包传输，如 WiFi，以太网，光纤，电话线等。
2. 数据链路层：主要负责链路层协议解析（主要为以太网帧）。
3. 网络层：主要负责 IP 协议（包括 IPv4 和 IPv6）解析。
4. 传输层：负责传输层协议解析（主要为 TCP，UDP 等）
5. 应用层：传输层以上我们均归类为应用层，主要包括各类应用层协议，如我们常用的 HTTP，FTP，SMTP，DNS，DHCP 等。



### 1.2、几种网络协议

> TCP/IP 是互联网。≤相关的各类协议族的总称，比如：TCP，UDP，IP，FTP，HTTP，ICMP，SMTP 等都属于 TCP/IP 族内的协议。

- ICMP：网际报文控制协议，比如常用的ping命令，traceroute命令
  - 用于IP主机、路由器之间传递控制消息。控制消息是在网络通不通、主机是否可达、路由是否可用等网络本身的消息。这些控制消息虽然不传输用户数据，但是对于用户数据的传递起着重要的作用。
- IGMP：互联网组管理协议。
  - IP组播通信的特点是报文从一个源发出，被转发到一组特定的接收者。但在组播通信模型中，发送者不关注接收者的位置信息，只是将数据发送到约定的目的组播地址。要使组播报文最终能够到达接收者，需要某种机制使连接接收者网段的组播路由器能够了解到该网段存在哪些组播接收者，同时保证接收者可以加入相应的组播组中。IGMP就是用来在接收者主机和与其所在网段直接相邻的组播路由器之间建立、维护组播组成员关系的协议。
- ARP/RARP：地址解析协议/反地址解析协议。
  - 根据IP地址获取物理地址/根据物理地址获取IP地址，同一局域网下网络传输使用。
- TCP：传输控制协议
  - 三次握手，四次挥手。面向有连接，可靠传输
- UDP：用户数据报协议
  - 无连接，不可靠

|              | UDP                                        | TCP                                    |
| :----------- | :----------------------------------------- | :------------------------------------- |
| 是否连接     | 无连接                                     | 面向连接                               |
| 是否可靠     | 不可靠传输，不使用流量控制和拥塞控制       | 可靠传输，使用流量控制和拥塞控制       |
| 连接对象个数 | 支持一对一，一对多，多对一和多对多交互通信 | 只能是一对一通信                       |
| 传输方式     | 面向报文                                   | 面向字节流                             |
| 首部开销     | 首部开销小，仅8字节                        | 首部最小20字节，最大60字节             |
| 适用场景     | 适用于实时应用（IP电话、视频会议、直播等） | 适用于要求可靠传输的应用，例如文件传输 |



## 二、Iptables/netfliter

> 要学会使用iptables和理解netfliter，就必须弄懂数据包在设备上的传输流程，及在每一个阶段所能做的事。

### 2.1、Packet传输流程图

![iptables](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2021-04-24/09:25:27-iptables.png)

### 2.2、iptables

- 表（tables）
  - filter：一般的过滤功能
  - nat：用于nat功能（端口映射，地址映射等）
  - mangle：用于对特定数据包的修改
  - Raw：有限级最高，设置raw时一般是为了不再让iptables做数据包的链接跟踪处理，提高性能RAW 表只使用在PREROUTING链和OUTPUT链上,因为优先级最高，从而可以对收到的数据包在连接跟踪前进行处理。一但用户使用了RAW表,在某个链 上,RAW表处理完后,将跳过NAT表和 ip_conntrack处理,即不再做地址转换和数据包的链接跟踪处理了。RAW表可以应用在那些不需要做nat的情况下，以提高性能。如大量访问的web服务器，可以让80端口不再让iptables做数据包的链接跟踪处理，以提高用户的访问速度。

- 链（chains）

  - PREROUTING：数据包进入路由表之前        
  - INPUT：通过路由表后目的地为本机        
  - FORWARD：通过路由表后，目的地不为本机        
  - OUTPUT：由本机产生，向外转发        
  - POSTROUTIONG：发送到网卡接口之前

- 规则（rules）

  ```
  *nat
  :PREROUTING ACCEPT [60:4250]
  :INPUT ACCEPT [31:1973]
  :OUTPUT ACCEPT [3:220]
  :POSTROUTING ACCEPT [3:220]
  -A PREROUTING -p tcp -m tcp --dport 8088 -j DNAT --to-destination 192.168.1.160:80                              //PREROUTING规则都放在上面
  -A PREROUTING -p tcp -m tcp --dport 33066 -j DNAT --to-destination 192.168.1.161:3306
  -A POSTROUTING -d 192.168.1.160/32 -p tcp -m tcp --sport 80 -j SNAT --to-source 192.168.1.7             //POSTROUTING规则都放在下面
  -A POSTROUTING -d 192.168.1.161/32 -p tcp -m tcp --sport 3306 -j SNAT --to-source 192.168.1.7
  .....
  *filter
  :INPUT ACCEPT [16:7159]
  :FORWARD ACCEPT [0:0]
  :OUTPUT ACCEPT [715:147195]
  -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
  -A INPUT -p icmp -j ACCEPT
  -A INPUT -i lo -j ACCEPT
  -A INPUT -p tcp -m state --state NEW -m tcp --dport 8088 -j ACCEPT
  -A INPUT -p tcp -m state --state NEW -m tcp --dport 33066 -j ACCEPT
  ```

### 2.3、使用

`iptables [-t 表名] 命令选项 ［链名］ ［条件匹配］ ［-j 目标动作或跳转］`

- 查看iptables命令

```
iptables --help
```

#### 2.3.1、操作filter表

![img](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2021-04-24/09:44:41-907596-20170109105720728-1179021991.png)



- 禁用ping

```
iptables -t filter -A INPUT -p icmp --icmp-type 8 -s 0.0.0.0/0 -j DROP
```

- 开通一段ip的端口

```
iptables -t filter -I YZW -m iprange --src-range 192.168.110.236-192.168.110.237 -p tcp -m multiport --dport 3011,3012,3301,8005,3302,3015,3016,20930 -j ACCEPT
```

- 保存iptables

```
iptables-save > /etc/sysconfig/iptables-yzw
```



#### 2.3.2、操作nat表

比如访问本机（192.168.1.7）的8088端口转发到192.168.1.160的80端口；

- DNAT

```
iptables -t nat -A PREROUTING -p tcp -m tcp --dport 8088 -j DNAT --to-destination 192.168.1.160:80
```

- SNAT

```
iptables -t nat -A POSTROUTING -d 192.168.1.160/32 -p tcp -m tcp --sport 80 -j SNAT --to-source 192.168.1.7
```

- MASQUERADE

```
iptables -t nat -A POSTROUTING -s 192.168.1.7/255.255.255.0 -o eth0 -j MASQUERADE
```



## 引用

【1】[Iptables 规则用法小结](https://www.cnblogs.com/kevingrace/p/6265113.html)

【2】[状态机制](https://klose911.github.io/html/iptables/state.html)