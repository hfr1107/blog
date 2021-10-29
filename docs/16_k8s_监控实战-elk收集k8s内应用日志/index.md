# 16_K8S_监控实战-ELK收集K8S内应用日志

# 16_K8S_监控实战-ELK收集K8S内应用日志
## 1 收集K8S日志方案
K8s系统里的业务应用是高度“动态化”的，随着容器编排的进行，业务容器在不断的被创建、被摧毁、被漂移、被扩缩容…
我们需要这样一套日志收集、分析的系统：

1. 收集 – 能够采集多种来源的日志数据（流式日志收集器）
1. 传输 – 能够稳定的把日志数据传输到中央系统（消息队列）
1. 存储 – 可以将日志以结构化数据的形式存储起来（搜索引擎）
1. 分析 – 支持方便的分析、检索方法，最好有GUI管理系统（web）
1. 警告 – 能够提供错误报告，监控机制（监控系统）
### 1.1 传统ELk模型缺点：
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601220131710-91d0ec84-4c3a-47cf-a7d7-9947bd6435be.jpeg)

1. Logstash使用Jruby语言开发，吃资源，大量部署消耗极高
1. 业务程序与logstash耦合过松，不利于业务迁移
1. 日志收集与ES耦合又过紧，（Logstash）易打爆（ES）、丢数据
1. 在容器云环境下，传统ELk模型难以完成工作
### 1.2 K8s容器日志收集模型
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601220131745-5701f5c6-17a2-4a80-9eda-f3389d14d071.png)

## 2 制作tomcat底包
### 2.1 准备tomcat底包
#### 2.1.1 下载tomcat8
```
cd /opt/src/
wget http://mirror.bit.edu.cn/apache/tomcat/tomcat-8/v8.5.50/bin/apache-tomcat-8.5.50.tar.gz
mkdir /data/dockerfile/tomcat
tar xf apache-tomcat-8.5.50.tar.gz -C /data/dockerfile/tomcat
cd /data/dockerfile/tomcat
```
#### 2.1.2 简单配置tomcat
删除自带网页
```
rm -rf apache-tomcat-8.5.50/webapps/*
```
关闭AJP端口
```
tomcat]# vim apache-tomcat-8.5.50/conf/server.xml
  <!-- <Connector port="8009" protocol="AJP/1.3" redirectPort="8443" /> -->
```
修改日志类型
> 删除3manager，4host-manager的handlers

```
tomcat]# vim apache-tomcat-8.5.50/conf/logging.properties
handlers = [1catalina.org.apache.juli.AsyncFileHandler](http://1catalina.org.apache.juli.asyncfilehandler/), [2localhost.org.apache.juli.AsyncFileHandler](http://2localhost.org.apache.juli.asyncfilehandler/), java.util.logging.ConsoleHandler
```
日志级别改为INFO
```
1catalina.org.apache.juli.AsyncFileHandler.level = INFO
2localhost.org.apache.juli.AsyncFileHandler.level = INFO
java.util.logging.ConsoleHandler.level = INFO
```
注释所有关于3manager，4host-manager日志的配置
```
#3manager.org.apache.juli.AsyncFileHandler.level = FINE
#3manager.org.apache.juli.AsyncFileHandler.directory = ${catalina.base}/logs
#3manager.org.apache.juli.AsyncFileHandler.prefix = manager.
#3manager.org.apache.juli.AsyncFileHandler.encoding = UTF-8
#4host-manager.org.apache.juli.AsyncFileHandler.level = FINE
#4host-manager.org.apache.juli.AsyncFileHandler.directory = ${catalina.base}/logs
#4host-manager.org.apache.juli.AsyncFileHandler.prefix = host-manager.
#4host-manager.org.apache.juli.AsyncFileHandler.encoding = UTF-8
```
### 2.2 准备docker镜像
#### 2.2.1 创建dockerfile
```
cat >Dockerfile <<'EOF'
From harbor.od.com/public/jre:8u112
RUN /bin/cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime &&\
  echo 'Asia/Shanghai' >/etc/timezone
ENV CATALINA_HOME /opt/tomcat
ENV LANG zh_CN.UTF-8
ADD apache-tomcat-8.5.50/ /opt/tomcat
ADD config.yml /opt/prom/config.yml
ADD jmx_javaagent-0.3.1.jar /opt/prom/jmx_javaagent-0.3.1.jar
WORKDIR /opt/tomcat
ADD entrypoint.sh /entrypoint.sh
CMD ["/bin/bash","/entrypoint.sh"]
EOF
```
#### 2.2.2 准备dockerfile所需文件
JVM监控所需jar包
```
wget  -O jmx_javaagent-0.3.1.jar https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.3.1/jmx_prometheus_javaagent-0.3.1.jar
```
jmx_agent读取的配置文件
```
cat >config.yml <<'EOF'
---
rules:
 - pattern: '.*'
EOF
```
容器启动脚本
```
cat  >entrypoint.sh <<'EOF'
#!/bin/bash
M_OPTS="-Duser.timezone=Asia/Shanghai -javaagent:/opt/prom/jmx_javaagent-0.3.1.jar=$(hostname -i):${M_PORT:-"12346"}:/opt/prom/config.yml" # Pod ip:port 监控规则传给jvm监控客户端
C_OPTS=${C_OPTS}             # 启动追加参数
MIN_HEAP=${MIN_HEAP:-"128m"} # java虚拟机初始化时的最小内存
MAX_HEAP=${MAX_HEAP:-"128m"} # java虚拟机初始化时的最大内存
JAVA_OPTS=${JAVA_OPTS:-"-Xmn384m -Xss256k -Duser.timezone=GMT+08  -XX:+DisableExplicitGC -XX:+UseConcMarkSweepGC -XX:+UseParNewGC -XX:+CMSParallelRemarkEnabled -XX:+UseCMSCompactAtFullCollection -XX:CMSFullGCsBeforeCompaction=0 -XX:+CMSClassUnloadingEnabled -XX:LargePageSizeInBytes=128m -XX:+UseFastAccessorMethods -XX:+UseCMSInitiatingOccupancyOnly -XX:CMSInitiatingOccupancyFraction=80 -XX:SoftRefLRUPolicyMSPerMB=0 -XX:+PrintClassHistogram  -Dfile.encoding=UTF8 -Dsun.jnu.encoding=UTF8"}     # 年轻代，gc回收
CATALINA_OPTS="${CATALINA_OPTS}"
JAVA_OPTS="${M_OPTS} ${C_OPTS} -Xms${MIN_HEAP} -Xmx${MAX_HEAP} ${JAVA_OPTS}"
sed -i -e "1a\JAVA_OPTS=\"$JAVA_OPTS\"" -e "1a\CATALINA_OPTS=\"$CATALINA_OPTS\"" /opt/tomcat/bin/catalina.sh
cd /opt/tomcat && /opt/tomcat/bin/catalina.sh run 2>&1 >> /opt/tomcat/logs/stdout.log # 日志文件
EOF
```
#### 2.2.3 构建docker
```
docker build . -t harbor.zq.com/base/tomcat:v8.5.50
docker push       harbor.zq.com/base/tomcat:v8.5.50
```
## 3 部署ElasticSearch
[官网](https://www.elastic.co/)
[官方github地址](https://github.com/elastic/elasticsearch)
[下载地址](https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-5.6.15.tar.gz)
部署`HDSS7-12.host.com`上：
### 3.1 安装ElasticSearch
#### 3.1.1 下载二进制包
```
cd /opt/src
wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-6.8.6.tar.gz
tar xf elasticsearch-6.8.6.tar.gz -C /opt/
ln -s /opt/elasticsearch-6.8.6/ /opt/elasticsearch
cd /opt/elasticsearch
```
#### 3.1.2 配置elasticsearch.yml
```
mkdir -p /data/elasticsearch/{data,logs}
cat >config/elasticsearch.yml <<'EOF'
cluster.name: es.zq.com
node.name: hdss7-12.host.com
path.data: /data/elasticsearch/data
path.logs: /data/elasticsearch/logs
bootstrap.memory_lock: true
network.host: 10.4.7.12
http.port: 9200
EOF
```
### 3.2 优化其他设置
#### 3.2.1 设置jvm参数
```
elasticsearch]# vi config/jvm.options
# 根据环境设置，-Xms和-Xmx设置为相同的值，推荐设置为机器内存的一半左右
-Xms512m
-Xmx512m
```
#### 3.2.2 创建普通用户
```
useradd -s /bin/bash -M es
chown -R es.es /opt/elasticsearch-6.8.6
chown -R es.es /data/elasticsearch/
```
#### 3.2.3 调整文件描述符
```
vim /etc/security/limits.d/es.conf
es hard nofile 65536
es soft fsize unlimited
es hard memlock unlimited
es soft memlock unlimited
```
#### 3.2.4 调整内核参数
```
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" > /etc/sysctl.conf
sysctl -p
```
### 3.3 启动ES
#### 3.3.1 启动es服务
```
]# su -c "/opt/elasticsearch/bin/elasticsearch -d" es
]# netstat -luntp|grep 9200
tcp6    0   0 10.4.7.12:9200     :::*          LISTEN   16784/java
```
#### 3.3.1 调整ES日志模板
```
curl -XPUT http://10.4.7.12:9200/_template/k8s -d '{
 "template" : "k8s*",
 "index_patterns": ["k8s*"],
 "settings": {
  "number_of_shards": 5,
  "number_of_replicas": 0    # 生产为3份副本集，本es为单节点，不能配置副本集
 }
}'
```
## 4 部署kafka和kafka-manager
[官网](http://kafka.apache.org/)
[官方github地址](https://github.com/apache/kafka)
[下载地址](http://mirrors.tuna.tsinghua.edu.cn/apache/kafka/2.1.1/kafka_2.12-2.1.1.tgz)
`HDSS7-11.host.com`上：
### 4.1 但节点安装kafka
#### 4.1.1 下载包
```
cd /opt/src
wget https://archive.apache.org/dist/kafka/2.2.0/kafka_2.12-2.2.0.tgz
tar xf kafka_2.12-2.2.0.tgz -C /opt/
ln -s /opt/kafka_2.12-2.2.0/ /opt/kafka
cd /opt/kafka
```
#### 4.1.2 修改配置
```
mkdir /data/kafka/logs -p
cat >config/server.properties <<'EOF'
log.dirs=/data/kafka/logs
zookeeper.connect=localhost:2181    # zk消息队列地址
log.flush.interval.messages=10000
log.flush.interval.ms=1000
delete.topic.enable=true
host.name=hdss7-11.host.com
EOF
```
#### 4.1.3 启动kafka
```
bin/kafka-server-start.sh -daemon config/server.properties
]# netstat -luntp|grep 9092
tcp6    0   0 10.4.7.11:9092     :::*          LISTEN   34240/java
```
### 4.2 获取kafka-manager的docker镜像
[官方github地址](https://github.com/yahoo/kafka-manager)
[源码下载地址](https://github.com/yahoo/kafka-manager/archive/2.0.0.2.tar.gz)
运维主机`HDSS7-200.host.com`上：
kafka-manager是kafka的一个web管理页面,非必须
#### 4.2.1 方法一 通过dockerfile获取
1 准备Dockerfile
```
cat >/data/dockerfile/kafka-manager/Dockerfile <<'EOF'
FROM hseeberger/scala-sbt
ENV ZK_HOSTS=10.4.7.11:2181 \
     KM_VERSION=2.0.0.2
RUN mkdir -p /tmp && \
    cd /tmp && \
    wget https://github.com/yahoo/kafka-manager/archive/${KM_VERSION}.tar.gz && \
    tar xxf ${KM_VERSION}.tar.gz && \
    cd /tmp/kafka-manager-${KM_VERSION} && \
    sbt clean dist && \
    unzip  -d / ./target/universal/kafka-manager-${KM_VERSION}.zip && \
    rm -fr /tmp/${KM_VERSION} /tmp/kafka-manager-${KM_VERSION}
WORKDIR /kafka-manager-${KM_VERSION}
EXPOSE 9000
ENTRYPOINT ["./bin/kafka-manager","-Dconfig.file=conf/application.conf"]
EOF
```
2 制作docker镜像
```
cd /data/dockerfile/kafka-manager
docker build . -t harbor.od.com/infra/kafka-manager:v2.0.0.2
(漫长的过程)
docker push harbor.zq.com/infra/kafka-manager:latest
```
> 构建过程极其漫长,大概率会失败,因此可以通过第二种方式下载构建好的镜像
> 但构建好的镜像写死了zk地址,要注意传入变量修改zk地址

#### 4.2.2 直接下载docker镜像
[镜像下载地址](https://hub.docker.com/r/sheepkiller/kafka-manager/tags)
```
docker pull sheepkiller/kafka-manager:latest
docker images|grep kafka-manager
docker tag  4e4a8c5dabab harbor.zq.com/infra/kafka-manager:latest
docker push harbor.zq.com/infra/kafka-manager:latest
```
#### 4.3 部署kafka-manager
```
mkdir /data/k8s-yaml/kafka-manager
cd /data/k8s-yaml/kafka-manager
```
### 4.3.1 准备dp清单
```
cat >deployment.yaml <<'EOF'
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: kafka-manager
  namespace: infra
  labels:
    name: kafka-manager
spec:
  replicas: 1
  selector:
    matchLabels:
      name: kafka-manager
  template:
    metadata:
      labels:
        app: kafka-manager
        name: kafka-manager
    spec:
      containers:
      - name: kafka-manager
        image: harbor.zq.com/infra/kafka-manager:latest
        ports:
        - containerPort: 9000
          protocol: TCP
        env:
        - name: ZK_HOSTS
          value: zk1.od.com:2181
        - name: APPLICATION_SECRET
          value: letmein
        imagePullPolicy: IfNotPresent
      imagePullSecrets:
      - name: harbor
      restartPolicy: Always
      terminationGracePeriodSeconds: 30
      securityContext:
        runAsUser: 0
      schedulerName: default-scheduler
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  revisionHistoryLimit: 7
  progressDeadlineSeconds: 600
EOF
```
#### 4.3.2 准备svc资源清单
```
cat >service.yaml <<'EOF'
kind: Service
apiVersion: v1
metadata:
  name: kafka-manager
  namespace: infra
spec:
  ports:
  - protocol: TCP
    port: 9000
    targetPort: 9000
  selector:
    app: kafka-manager
EOF
```
#### 4.3.3 准备ingress资源清单
```
cat >ingress.yaml <<'EOF'
kind: Ingress
apiVersion: extensions/v1beta1
metadata:
  name: kafka-manager
  namespace: infra
spec:
  rules:
  - host: km.zq.com
    http:
      paths:
      - path: /
        backend:
          serviceName: kafka-manager
          servicePort: 9000
EOF
```
#### 4.3.4 应用资源配置清单
任意一台运算节点上：
```
kubectl apply -f http://k8s-yaml.od.com/kafka-manager/deployment.yaml
kubectl apply -f http://k8s-yaml.od.com/kafka-manager/service.yaml
kubectl apply -f http://k8s-yaml.od.com/kafka-manager/ingress.yaml
```
#### 4.3.5 解析域名
`HDSS7-11.host.com`上
```
~]# vim /var/named/zq.com.zone
km    A   10.4.7.10
~]# systemctl restart named
~]# dig -t A km.od.com @10.4.7.11 +short
10.4.7.10
```
#### 4.3.6 浏览器访问
[http://km.zq.com](http://km.od.com/)
**添加集群**
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/456789875.png)
**查看集群信息**
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/09876543234.png)

## 5 部署filebeat
[官方下载地址](https://www.elastic.co/downloads/beats/filebeat)
运维主机`HDSS7-200.host.com`上：
### 5.1 制作docker镜像
```
mkdir /data/dockerfile/filebeat
cd /data/dockerfile/filebeat
```
#### 5.1.1 准备Dockerfile
```
cat >Dockerfile <<'EOF'
FROM debian:jessie
# 如果更换版本,需在官网下载同版本LINUX64-BIT的sha替换FILEBEAT_SHA1
ENV FILEBEAT_VERSION=7.5.1 \ FILEBEAT_SHA1=daf1a5e905c415daf68a8192a069f913a1d48e2c79e270da118385ba12a93aaa91bda4953c3402a6f0abf1c177f7bcc916a70bcac41977f69a6566565a8fae9c
RUN set -x && \
 apt-get update && \
 apt-get install -y wget && \
 wget https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${FILEBEAT_VERSION}-linux-x86_64.tar.gz -O /opt/filebeat.tar.gz && \
 cd /opt && \
 echo "${FILEBEAT_SHA1} filebeat.tar.gz" | sha512sum -c - && \
 tar xzvf filebeat.tar.gz && \
 cd filebeat-* && \
 cp filebeat /bin && \
 cd /opt && \
 rm -rf filebeat* && \
 apt-get purge -y wget && \
 apt-get autoremove -y && \
 apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
COPY filebeat.yaml /etc/
COPY docker-entrypoint.sh /
ENTRYPOINT ["/bin/bash","/docker-entrypoint.sh"]
EOF
```
#### 5.1.2 准备filebeat配置文件
```
cat >/etc/filebeat.yaml << EOF
filebeat.inputs:
- type: log
  fields_under_root: true
  fields:
    topic: logm-PROJ_NAME
  paths:
    - /logm/*.log
    - /logm/*/*.log
    - /logm/*/*/*.log
    - /logm/*/*/*/*.log
    - /logm/*/*/*/*/*.log
  scan_frequency: 120s
  max_bytes: 10485760
  multiline.pattern: 'MULTILINE'
  multiline.negate: true
  multiline.match: after
  multiline.max_lines: 100
- type: log
  fields_under_root: true
  fields:
    topic: logu-PROJ_NAME
  paths:
    - /logu/*.log
    - /logu/*/*.log
    - /logu/*/*/*.log
    - /logu/*/*/*/*.log
    - /logu/*/*/*/*/*.log
    - /logu/*/*/*/*/*/*.log
output.kafka:
  hosts: ["10.4.7.11:9092"]
  topic: k8s-fb-ENV-%{[topic]}
  version: 2.0.0      # kafka版本超过2.0，默认写2.0.0
  required_acks: 0
  max_message_bytes: 10485760
EOF
```
#### 5.1.3 准备启动脚本
```
cat >docker-entrypoint.sh <<'EOF'
#!/bin/bash
ENV=${ENV:-"test"}                    # 定义日志收集的环境
PROJ_NAME=${PROJ_NAME:-"no-define”}   # 定义项目名称
MULTILINE=${MULTILINE:-"^\d{2}"}      # 多行匹配，以2个数据开头的为一行，反之
# 替换配置文件中的内容
sed -i 's#PROJ_NAME#${PROJ_NAME}#g' /etc/filebeat.yaml
sed -i 's#MULTILINE#${MULTILINE}#g' /etc/filebeat.yaml
sed -i 's#ENV#${ENV}#g'             /etc/filebeat.yaml
if [[ "$1" == "" ]]; then
     exec filebeat  -c /etc/filebeat.yaml
else
    exec "$@"
fi
EOF
```
#### 5.1.4 构建镜像
```
docker build . -t harbor.od.com/infra/filebeat:v7.5.1
docker push       harbor.od.com/infra/filebeat:v7.5.1
```
### 5.2 以边车模式运行POD
#### 5.2.1 准备资源配置清单
使用dubbo-demo-consumer的镜像,以边车模式运行filebeat
```
]# vim /data/k8s-yaml/test/dubbo-demo-consumer/deployment.yaml
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: dubbo-demo-consumer
  namespace: test
  labels:
    name: dubbo-demo-consumer
spec:
  replicas: 1
  selector:
    matchLabels:
      name: dubbo-demo-consumer
  template:
    metadata:
      labels:
        app: dubbo-demo-consumer
        name: dubbo-demo-consumer
      annotations:
        blackbox_path: "/hello?name=health"
        blackbox_port: "8080"
        blackbox_scheme: "http"
        prometheus_io_scrape: "true"
        prometheus_io_port: "12346"
        prometheus_io_path: "/"
    spec:
      containers:
      - name: dubbo-demo-consumer
        image: harbor.zq.com/app/dubbo-tomcat-web:apollo_200513_1808
        ports:
        - containerPort: 8080
          protocol: TCP
        - containerPort: 20880
          protocol: TCP
        env:
        - name: JAR_BALL
          value: dubbo-client.jar
        - name: C_OPTS
          value: -Denv=fat -Dapollo.meta=http://config-test.zq.com
        imagePullPolicy: IfNotPresent
#--------新增内容--------
        volumeMounts:
        - mountPath: /opt/tomcat/logs
          name: logm
      - name: filebeat
        image: harbor.zq.com/infra/filebeat:v7.5.1
        imagePullPolicy: IfNotPresent
        env:
        - name: ENV
          value: test             # 测试环境
        - name: PROJ_NAME
          value: dubbo-demo-web   # 项目名
        volumeMounts:
        - mountPath: /logm
          name: logm
      volumes:
      - emptyDir: {} #随机在宿主机找目录创建,容器删除时一起删除
        name: logm
#--------新增结束--------
      imagePullSecrets:
      - name: harbor
      restartPolicy: Always
      terminationGracePeriodSeconds: 30
      securityContext:
        runAsUser: 0
      schedulerName: default-scheduler
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  revisionHistoryLimit: 7
  progressDeadlineSeconds: 600
```
#### 5.2.2 应用资源清单
任意node节点
```
kubectl apply -f http://k8s-yaml.od.com/test/dubbo-demo-consumer/deployment.yaml
```
### 5.2.3 验证
浏览器访问[http://km.zq.com,](http://km.zq.com,)看到kafaka-manager里，topic打进来，即为成功
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1765432234.png)
进入dubbo-demo-consumer的容器中,查看logm目录下是否有日志

```
kubectl -n test exec -it dobbo...... -c filebeat /bin/bash
ls /logm
# -c参数指定pod中的filebeat容器
# /logm是filebeat容器挂载的目录
```
## 6 部署logstash
运维主机`HDSS7-200.host.com`上：
### 6.1 准备docker镜像
#### 6.1.1 下载官方镜像
```
docker pull logstash:6.8.6
docker tag  d0a2dac51fcb harbor.od.com/infra/logstash:v6.8.6
docker push harbor.zq.com/infra/logstash:v6.8.6
```
#### 6.1.2 准备配置文件
准备目录
```
mkdir /etc/logstash/
```
创建test.conf
```
cat >/etc/logstash/logstash-test.conf <<'EOF'
input {
  kafka {
    bootstrap_servers => "10.4.7.11:9092"
    client_id => "10.4.7.200"
    consumer_threads => 4
    group_id => "k8s_test"               # 为test组
    topics_pattern => "k8s-fb-test-.*"   # 只收集k8s-fb-test开头的topics
  }
}
filter {
  json {
    source => "message"
  }
}
output {
  elasticsearch {
    hosts => ["10.4.7.12:9200"]
    index => "k8s-test-%{+YYYY.MM.DD}"
  }
}
EOF
```
创建prod.conf
```
cat >/etc/logstash/logstash-prod.conf <<'EOF'
input {
  kafka {
    bootstrap_servers => "10.4.7.11:9092"
    client_id => "10.4.7.200"
    consumer_threads => 4
    group_id => "k8s_prod"
    topics_pattern => "k8s-fb-prod-.*"
  }
}
filter {
  json {
    source => "message"
  }
}
output {
  elasticsearch {
    hosts => ["10.4.7.12:9200"]
    index => “k8s-prod-%{+YYYY.MM.DD}"
  }
}
EOF
```
### 6.2 启动logstash
#### 6.2.1 启动测试环境的logstash
```
docker run -d \
    --restart=always \
    --name logstash-test \
    -v /etc/logstash:/etc/logstash  \
    -f /etc/logstash/logstash-test.conf  \
    harbor.od.com/infra/logstash:v6.8.6
~]# docker ps -a|grep logstash
```
#### 6.2.2 查看es是否接收数据
```
~]# curl http://10.4.7.12:9200/_cat/indices?v
health status index        uuid          pri rep docs.count docs.deleted store.size pri.store.size
green open  k8s-test-2020.01.07 mFEQUyKVTTal8c97VsmZHw  5  0     12      0   78.4kb     78.4kb
```
#### 6.2.3 启动正式环境的logstash
```
docker run -d \
    --restart=always \
    --name logstash-prod \
    -v /etc/logstash:/etc/logstash  \
    -f /etc/logstash/logstash-prod.conf  \
    harbor.od.com/infra/logstash:v6.8.6
```
## 7 部署Kibana
运维主机`HDSS7-200.host.com`上：
### 7.1 准备相关资源
#### 7.1.1 准备docker镜像
[kibana官方镜像下载地址](https://hub.docker.com/_/kibana?tab=tags)
```
docker pull kibana:6.8.6
docker tag  adfab5632ef4 harbor.od.com/infra/kibana:v6.8.6
docker push harbor.zq.com/infra/kibana:v6.8.6
```
准备目录
```
mkdir /data/k8s-yaml/kibana
cd /data/k8s-yaml/kibana
```
#### 7.1.3 准备dp资源清单
```
cat >deployment.yaml <<'EOF'
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: kibana
  namespace: infra
  labels:
    name: kibana
spec:
  replicas: 1
  selector:
    matchLabels:
      name: kibana
  template:
    metadata:
      labels:
        app: kibana
        name: kibana
    spec:
      containers:
      - name: kibana
        image: harbor.zq.com/infra/kibana:v6.8.6
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 5601
          protocol: TCP
        env:
        - name: ELASTICSEARCH_URL
          value: http://10.4.7.12:9200
      imagePullSecrets:
      - name: harbor
      securityContext:
        runAsUser: 0
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  revisionHistoryLimit: 7
  progressDeadlineSeconds: 600
EOF
```
#### 7.1.4 准备svc资源清单
```
cat >service.yaml <<'EOF'
kind: Service
apiVersion: v1
metadata:
  name: kibana
  namespace: infra
spec:
  ports:
  - protocol: TCP
    port: 5601
    targetPort: 5601
  selector:
    app: kibana
EOF
```
#### 7.1.5 准备ingress资源清单
```
cat >ingress.yaml <<'EOF'
kind: Ingress
apiVersion: extensions/v1beta1
metadata:
  name: kibana
  namespace: infra
spec:
  rules:
  - host: kibana.zq.com
    http:
      paths:
      - path: /
        backend:
          serviceName: kibana
          servicePort: 5601
EOF
```
### 7.2 应用资源
#### 7.2.1 应用资源配置清单
```
kubectl apply -f http://k8s-yaml.zq.com/kibana/deployment.yaml
kubectl apply -f http://k8s-yaml.zq.com/kibana/service.yaml
kubectl apply -f http://k8s-yaml.zq.com/kibana/ingress.yaml
```
#### 7.2.2 解析域名
```
~]# vim /var/named/od.com.zone
kibana         A  10.4.7.10
~]# systemctl restart named
~]# dig -t A kibana.od.com @10.4.7.11 +short
10.4.7.10
```
#### 7.2.3 浏览器访问
访问[http://kibana.zq.com](http://kibana.zq.com)
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601220134708-c82a19f5-82bd-4be0-a8cf-193be188a250.png)

### 7.3 kibana的使用
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601220133815-6134311a-d55b-4d51-a5ab-da45338cdddb.png)

1. 选择区域
| 项目 | 用途 |
| --- | --- |
| @timestamp | 对应日志的时间戳 |
| og.file.path | 对应日志文件名 |
| message | 对应日志内容 |

1. 时间选择器
选择日志时间
```
快速时间
绝对时间
相对时间
```

1. 环境选择器
选择对应环境的日志
```
k8s-test-*
k8s-prod-*
```

1. 项目选择器
   - 对应filebeat的PROJ_NAME值
   - Add a fillter
   - topic is ${PROJ_NAME}
   dubbo-demo-service
   dubbo-demo-web
2. 关键字选择器
exception
error


