---
weight: 8
title: "08_K8S_交付实战-架构说明并准备zk集群"
subtitle: ""
date: 2020-10-01T15:58:21+08:00
lastmod: 2020-10-01T15:58:21+08:00
draft: false
author: "老男孩"
authorLink: "https://space.bilibili.com/394449264"
description: "转载，原为老男孩教育视频内容"

tags: ["K8S", "转载"]
categories: ["转载", "K8S"]

featuredImage: ""
featuredImagePreview: ""
lightgallery: true
---
# 08_K8S_交付实战-架构说明并准备zk集群

## 1 交付的服务架构图：
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601204138577-068b05f7-606f-40ee-b174-a18a1b7138f5.png)
### 1.1 架构图解

1. 最上面一排为K8S集群外服务
1.1 代码仓库使用基于git的gitee
1.2 注册中心使用3台zk组成集群
1.3 用户通过ingress暴露出去的服务进行访问
1. 中间层是K8S集群内服务
2.1 jenkins以容器方式运行,数据目录通过共享磁盘做持久化
2.2 整套dubbo微服务都以POD方式交付,通过zk集群通信
2.3 需要提供的外部访问的服务通过ingress方式暴露
1. 最下层是运维主机层
3.1 harbor是docker私有仓库,存放docker镜像
3.2 POD相关yaml文件创建在运维主机特定目录
3.3 在K8S集群内通过nginx提供的下载连接应用yaml配置
### 1.2 交付说明:
docker虽然可以部署有状态服务,但如果不是有特别需要,还是建议不要部署有状态服务
K8S同理,也不建议部署有状态服务，如mysql，zk等。
因此手动将zookeeper创建集群提供给dubbo使用
## 2 部署ZK集群
集群分布：7-11，7-12，7-21
zk是java服务，需要依赖jdk
### 2.1 二进制安装JDK
jdk请自行下载,只要是1.8版本的就可以,rpm安装或二进制安装均可：
#### 2.1.1 解压jdk
```
mkdir /opt/src
mkdir /usr/java
cd /opt/src
tar -xf jdk-8u221-linux-x64.tar.gz -C /usr/java/
ln -s /usr/java/jdk1.8.0_221/ /usr/java/jdk
```
#### 2.1.2 写入环境变量
```
cat >>/etc/profile <<'EOF'
#JAVA HOME
export JAVA_HOME=/usr/java/jdk
export PATH=$JAVA_HOME/bin:$JAVA_HOME/bin:$PATH
export CLASSPATH=$CLASSPATH:$JAVA_HOME/lib:$JAVA_HOME/lib/tools.jar
EOF
# 使环境变量生效
source /etc/profile
```
验证结果
```
[root@hdss7-11 ~]# java -version
java version "1.8.0_221"
Java(TM) SE Runtime Environment (build 1.8.0_221-b11)
Java HotSpot(TM) 64-Bit Server VM (build 25.221-b11, mixed mode)
```
## 2.2 二进制安装zk
#### 2.2.1 下载zookeeper
[下载地址](https://archive.apache.org/dist/zookeeper/)
```
wget https://archive.apache.org/dist/zookeeper/zookeeper-3.4.14/zookeeper-3.4.14.tar.gz
tar -zxf zookeeper-3.4.14.tar.gz -C /opt/
ln -s /opt/zookeeper-3.4.14/ /opt/zookeeper
```
#### 2.2.2 创建zk配置文件：
```
cat >/opt/zookeeper/conf/zoo.cfg <<'EOF'
tickTime=2000
initLimit=10
syncLimit=5
dataDir=/data/zookeeper/data
dataLogDir=/data/zookeeper/logs
clientPort=2181
server.1=zk1.zq.com:2888:3888
server.2=zk2.zq.com:2888:3888
server.3=zk3.zq.com:2888:3888
EOF
```
创建相关目录
```
mkdir -p /data/zookeeper/data
mkdir -p /data/zookeeper/logs
```
#### 2.2.3 创建集群配置
给每个zk不同的myid,以便区分主从
```
#7-11上
echo 1 > /data/zookeeper/data/myid
#7-12上
echo 2 > /data/zookeeper/data/myid
#7-21上
echo 3 > /data/zookeeper/data/myid
```
#### 2.2.4 修改dns解析
到`7.11`上增加dns解析记录
```
vi /var/named/zq.com.zone
...
zk1        A    10.4.7.11
zk2        A    10.4.7.12
zk3        A    10.4.7.21
#验证结果
~]# dig -t A zk1.zq.com  +short
10.4.7.11
```
### 2.3 启动zk集群
### 2.3.1 启动zookeeper
在每台zk机器上都执行此操作
```
/opt/zookeeper/bin/zkServer.sh start
```
#### 2.3.2 检查zk启动情况
```
~]# ss -ln|grep 2181
tcp    LISTEN     0      50       :::2181                 :::*
```
#### 2.3.3 检查zk集群情况
```
[root@hdss7-11 ~]# /opt/zookeeper/bin/zkServer.sh status
ZooKeeper JMX enabled by default
Using config: /opt/zookeeper/bin/../conf/zoo.cfg
Mode: follower
[root@hdss7-12 ~]# /opt/zookeeper/bin/zkServer.sh status
ZooKeeper JMX enabled by default
Using config: /opt/zookeeper/bin/../conf/zoo.cfg
Mode: leader
[root@hdss7-21 ~]# /opt/zookeeper/bin/zkServer.sh status
ZooKeeper JMX enabled by default
Using config: /opt/zookeeper/bin/../conf/zoo.cfg
Mode: follower
```
到此，zookeeper集群就搭建好了。
## 3 准备java运行底包
运维主机上操作
### 3.1 拉取原始底包
```
docker pull stanleyws/jre8:8u112
docker tag fa3a085d6ef1 harbor.zq.com/public/jre:8u112
docker push harbor.zq.com/public/jre:8u112
```
### 3.2 制作新底包
```
mkdir -p /data/dockerfile/jre8/
cd /data/dockerfile/jre8/
```
#### 3.2.1 制作dockerfile
```
cat >Dockerfile <<'EOF'
FROM harbor.zq.com/public/jre:8u112
RUN /bin/cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime &&\
    echo 'Asia/Shanghai' >/etc/timezone
ADD config.yml /opt/prom/config.yml
ADD jmx_javaagent-0.3.1.jar /opt/prom/
WORKDIR /opt/project_dir
ADD entrypoint.sh /entrypoint.sh
CMD ["sh","/entrypoint.sh"]
EOF
```
#### 3.2.2准备dockerfile需要的文件
**添加config.yml**
此文件是为后面用普罗米修斯监控做准备的
```
cat >config.yml <<'EOF'
---
rules:
 - pattern: '.*'
EOF
```
**下载jmx_javaagent,监控jvm信息：**
```
wget https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.3.1/jmx_prometheus_javaagent-0.3.1.jar -O jmx_javaagent-0.3.1.jar
```
**创建entrypoint.sh启动脚本：**
使用exec 来运行java的jar包，能够使脚本将自己的pid 为‘1’ 传递给java进程，避免docker容器因没有前台进程而退出。并且不要加&符。
```
cat >entrypoint.sh <<'EOF'
#!/bin/sh
M_OPTS="-Duser.timezone=Asia/Shanghai -javaagent:/opt/prom/jmx_javaagent-0.3.1.jar=$(hostname -i):${M_PORT:-"12346"}:/opt/prom/config.yml"
C_OPTS=${C_OPTS}
JAR_BALL=${JAR_BALL}
exec java -jar ${M_OPTS} ${C_OPTS} ${JAR_BALL}
EOF
```
#### 3.2.3 构建底包并上传
在harbor中创建名为`base`的公开仓库,用来存放自己自定义的底包
```
docker build . -t harbor.zq.com/base/jre8:8u112
docker push  harbor.zq.com/base/jre8:8u112
```

