---
weight: 10
title: "10_K8S_交付实战-流水线构建dubbo服务"
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

# 10_K8S_交付实战-流水线构建dubbo服务
## 1 jenkins流水线准备工作
### 1.1 参数构建要点
**jenkins流水线配置的java项目的十个常用参数:**

| 参数名 | 作用 | 举例或说明 |
| --- | --- | --- |
| app_name | 项目名 | dubbo_demo_service |
| image_name | docker镜像名 | app/dubbo-demo-service |
| git_repo | 项目的git地址 | [https://x.com/x/x.git](https://x.com/x/x.git) |
| git_ver | 项目的git分支或版本号 | master |
| add_tag | 镜像标签,常用时间戳 | 191203_1830 |
| mvn_dir | 执行mvn编译的目录 | ./ |
| target_dir | 编译产生包的目录 | ./target |
| mvn_cmd | 编译maven项目的命令 | mvc clean package -Dmaven. |
| base_image | 项目的docker底包 | 不同的项目底包不一样,下拉选择 |
| maven | maven软件版本 | 不同的项目可能maven环境不一样 |

> 除了base_image和maven是choice parameter，其他都是string parameter

### 1.2 创建流水线
#### 1.2.1 创建流水线
创建名为`dubbo-demo`的流水线(pipeline),并设置`Discard old builds` 为如下

| Discard old builds选项 | 值 |
| --- | --- |
| Days to keep builds | 3 |
| Max # of builds to keep | 30 |

#### 1.2.2 添加10个构建参数
`This project is parameterized`点击`Add Parameter`,分别添加如下10个参数
```
#第1个参数
参数类型 : String Parameter
Name : app_name
Description : 项目名 eg:dubbo-demo-service
#第2个参数
参数类型 : String Parameter
Name : image_name
Description : docker镜像名 eg: app/dubbo-demo-service
#第3个参数
参数类型 : String Parameter
Name : git_repo
Description : 仓库地址 eg: https://gitee.com/xxx/xxx.git
#第4个参数
参数类型 : String Parameter
Name : git_ver
Description : 项目的git分支或版本号
#第5个参数
参数类型 : String Parameter
Name : add_tag
Description :
给docker镜像添加标签组合的一部分,如
$git_ver_$add_tag=master_191203_1830
#第6个参数
参数类型 : String Parameter
Name : mvn_dir
Default Value : ./
Description : 执行mvn编译的目录,默认是项目根目录, eg: ./
#第7个参数
参数类型 : String Parameter
Name : target_dir
Default Value : ./target
Description : 编译产生的war/jar包目录 eg: ./dubbo-server/target
#第8个参数
参数类型 : String Parameter
Name : mvn_cmd
Default Value : mvn clean package -Dmaven.test.skip=true
Description : 编译命令,常加上-e -q参数只输出错误
#第9个参数
参数类型 : Choice Parameter
Name : base_image
Choices :
base/jre7:7u80
base/jre8:8u112
Description : 项目的docker底包
#第10个参数
参数类型 : Choice Parameter
Name : maven
Choices :
3.6.1
3.2.5
2.2.1
Description : 执行编译使用maven软件版本
```
#### 1.2.3 添加完成效果如下:
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601204368010-4c98901a-7615-4fb4-ae0a-aa199b0118a0.png)
#### 1.2.4 添加pipiline代码
流水线构建所用的pipiline代码语法比较有专门的生成工具
以下语句的作用大致是分为四步:拉代码->构建包->移动包-打docker镜像并推送
```
pipeline {
  agent any
    stages {
      stage('pull') { //get project code from repo
        steps {
          sh "git clone ${params.git_repo} ${params.app_name}/${env.BUILD_NUMBER} && cd ${params.app_name}/${env.BUILD_NUMBER} && git checkout ${params.git_ver}"
        }
      }
      stage('build') { //exec mvn cmd
        steps {
          sh "cd ${params.app_name}/${env.BUILD_NUMBER}  && /var/jenkins_home/maven-${params.maven}/bin/${params.mvn_cmd}"
        }
      }
      stage('package') { //move jar file into project_dir
        steps {
          sh "cd ${params.app_name}/${env.BUILD_NUMBER} && cd ${params.target_dir} && mkdir project_dir && mv *.jar ./project_dir"
        }
      }
      stage('image') { //build image and push to registry
        steps {
          writeFile file: "${params.app_name}/${env.BUILD_NUMBER}/Dockerfile", text: """FROM harbor.zq.com/${params.base_image}
ADD ${params.target_dir}/project_dir /opt/project_dir"""
          sh "cd  ${params.app_name}/${env.BUILD_NUMBER} && docker build -t harbor.zq.com/${params.image_name}:${params.git_ver}_${params.add_tag} . && docker push harbor.zq.com/${params.image_name}:${params.git_ver}_${params.add_tag}"
        }
      }
    }
}
```
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601204368104-5ca33656-62ba-46fd-96ec-9fad247bc1e6.png)
### 1.3 用流水线完成dubbo-service的构建
记得先在harbor中创建私有仓库`app`
#### 1.3.1 选择参数化构建
进入`dubbo-demo`后,选择的参数化构建`build with parameters` ,填写10个构建的参数

| 参数名 | 参数值 |
| --- | --- |
| app_name | dubbo-demo-service |
| image_name | app/dubbo-demo-service |
| git_repo | [https://gitee.com/noah-luo/dubbo-demo-service.git](https://gitee.com/noah-luo/dubbo-demo-service.git) |
| git_ver | master |
| add_tag | 200509_0800 |
| mvn_dir | ./ |
| target_dir | ./dubbo-server/target |
| mvn_cmd | mvn clean package -Dmaven.test.skip=true |
| base_image | base/jre8:8u112 |
| maven | 3.6.1 |

#### 1.3.2 填写完成效果如下
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601204368021-24e1272c-d6ea-40f7-bc12-92de8bf30d68.png)
#### 1.3.3 执行构建并检查
填写完以后执行**bulid**
第一次构建需要下载很多依赖包，时间很长，抽根烟，喝杯茶
经过漫长的等待后，已经构建完成了
**点击`打开 Blue Ocean`查看构建历史及过程：**
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601204368085-320e5621-5975-4ee9-8040-aa5b9bcf01c0.png)
**检查harbor是否已经有这版镜像：**
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601204368034-28b6c518-cc96-470c-b615-f2b192a4fffa.png)

## 2 交付dubbo-service到k8s
### 2.1 准备资源清单
创建清单操作都在`7.200`上操作
```
mkdir /data/k8s-yaml/dubbo-server/
cd /data/k8s-yaml/dubbo-server
```
#### 2.1.1 创建depeloy清单
```yaml
cat >dp.yaml <<EOF
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: dubbo-demo-service
  namespace: app
  labels:
    name: dubbo-demo-service
spec:
  replicas: 1
  selector:
    matchLabels:
      name: dubbo-demo-service
  template:
    metadata:
      labels:
        app: dubbo-demo-service
        name: dubbo-demo-service
    spec:
      containers:
      - name: dubbo-demo-service
        image: harbor.zq.com/app/dubbo-demo-service:master_200509_0800
        ports:
        - containerPort: 20880
          protocol: TCP
        env:
        - name: JAR_BALL
          value: dubbo-server.jar
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
> 需要根据自己构建镜像的tag来修改image
> dubbo的server服务,只向zk注册并通过zk与dobbo的web交互,不需要对外提供服务
> 因此不需要service资源和ingress资源

### 2.2 创建k8s资源
创建K8S资源的操作,在任意node节点上操作即可
#### 2.2.1 创建app名称空间
业务资源和运维资源等应该通过名称空间来隔离,因此创建专有名称空间app
```
kubectl create namespace app
```
#### 2.2.2 创建secret资源
我们的业务镜像是harbor中的私有项目，所以需要创建`docker-registry`的secret资源：
```
kubectl -n app \
    create secret docker-registry harbor \
    --docker-server=harbor.zq.com \
    --docker-username=admin \
    --docker-password=Harbor12345
```
#### 2.2.3 应用资源清单
```
kubectl apply -f http://k8s-yaml.zq.com/dubbo-server/dp.yaml
```
**3分钟后检查启动情况**
```
# 检查pod是否创建：
~]# kubectl -n app get pod
NAME                                  READY   STATUS    RESTARTS   AGE
dubbo-demo-service-79574b6879-cxkls   1/1     Running   0          24s
# 检查是否启动成功：
~]# kubectl -n app logs dubbo-demo-service-79574b6879-cxkls --tail=2
Dubbo server started
Dubbo 服务端已经启动
```
**到zk服务器检查是否有服务注册**
```
sh /opt/zookeeper/bin/zkCli.sh
[zk: localhost:2181(CONNECTED) 0] ls /
[dubbo, zookeeper]
[zk: localhost:2181(CONNECTED) 1] ls /dubbo
[com.od.dubbotest.api.HelloService]
```
## 3 交付dubbo-monitor监控服务到k8s
dobbo-monitor源码地址: [https://github.com/Jeromefromcn/dubbo-monitor.git](https://github.com/Jeromefromcn/dubbo-monitor.git)
dubbo-monitor是监控zookeeper状态的一个服务，另外还有dubbo-admin，效果一样
### 3.1 制作dobbo-monitor镜像
制作镜像在管理机`7.200`上操作
#### 3.1.1 下载源码
```
cd /opt/src
wget https://github.com/Jeromefromcn/dubbo-monitor/archive/master.zip
yum -y install unzip
unzip master.zip
mv dubbo-monitor-mster /data/dockerfile/dubbo-monitor
cd  /data/dockerfile/dubbo-monitor
```
#### 3.1.2 修改配置文件：
直接覆盖它原始的配置
其实它原本就没什么内容,只是修改了addr,端口,目录等
```
cat >dubbo-monitor-simple/conf/dubbo_origin.properties <<'EOF'
dubbo.container=log4j,spring,registry,jetty
dubbo.application.name=simple-monitor
dubbo.application.owner=
dubbo.registry.address=zookeeper://zk1.zq.com:2181?backup=zk2.zq.com:2181,zk3.zq.com:2181
dubbo.protocol.port=20880
dubbo.jetty.port=8080
dubbo.jetty.directory=/dubbo-monitor-simple/monitor
dubbo.statistics.directory=/dubbo-monitor-simple/statistics
dubbo.charts.directory=/dubbo-monitor-simple/charts
dubbo.log4j.file=logs/dubbo-monitor.log
dubbo.log4j.level=WARN
EOF
```
#### 3.1.3 优化Dockerfile启动脚本
```
# 修改jvm资源限制(非必须)
sed -i '/Xmx2g/ s#128m#16m#g' ./dubbo-monitor-simple/bin/start.sh
sed -i '/Xmx2g/ s#256m#32m#g' ./dubbo-monitor-simple/bin/start.sh
sed -i '/Xmx2g/ s#2g#128m#g'  ./dubbo-monitor-simple/bin/start.sh
# 修改nohup为exec不能改去掉改行最后的&符号
sed -ri 's#^nohup(.*) &#exec\1#g' ./dubbo-monitor-simple/bin/start.sh
# 删除exec命令行后面所有行
sed -i '66,$d'  ./dubbo-monitor-simple/bin/start.sh
```
#### 3.1.4 构建并上传
```
docker build . -t harbor.zq.com/infra/dubbo-monitor:latest
docker push       harbor.zq.com/infra/dubbo-monitor:latest
```
### 3.2 创建资源配置清单
#### 3.2.1 准备目录
```
mkdir /data/k8s-yaml/dubbo-monitor
cd /data/k8s-yaml/dubbo-monitor
```
#### 3.2.2 创建deploy资源文件
```
cat >dp.yaml <<EOF
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: dubbo-monitor
  namespace: infra
  labels:
    name: dubbo-monitor
spec:
  replicas: 1
  selector:
    matchLabels:
      name: dubbo-monitor
  template:
    metadata:
      labels:
        app: dubbo-monitor
        name: dubbo-monitor
    spec:
      containers:
      - name: dubbo-monitor
        image: harbor.zq.com/infra/dubbo-monitor:latest
        ports:
        - containerPort: 8080
          protocol: TCP
        - containerPort: 20880
          protocol: TCP
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
#### 3.2.3 创建service资源文件
```
cat >svc.yaml <<EOF
kind: Service
apiVersion: v1
metadata:
  name: dubbo-monitor
  namespace: infra
spec:
  ports:
  - protocol: TCP
    port: 8080
    targetPort: 8080
  selector:
    app: dubbo-monitor
EOF
```
#### 3.2.4 创建ingress资源文件
```
cat >ingress.yaml <<EOF
kind: Ingress
apiVersion: extensions/v1beta1
metadata:
  name: dubbo-monitor
  namespace: infra
spec:
  rules:
  - host: dubbo-monitor.zq.com
    http:
      paths:
      - path: /
        backend:
          serviceName: dubbo-monitor
          servicePort: 8080
EOF
```
### 3.3 创建dobbo-miniotr服务
#### 3.3.1 应用资源配置清单
在任意node节点
```
kubectl apply -f http://k8s-yaml.zq.com/dubbo-monitor/dp.yaml
kubectl apply -f http://k8s-yaml.zq.com/dubbo-monitor/svc.yaml
kubectl apply -f http://k8s-yaml.zq.com/dubbo-monitor/ingress.yaml
```
验证：
```
~]# kubectl -n infra get pod
NAME                            READY   STATUS    RESTARTS   AGE
dubbo-monitor-d9675688c-sctsx   1/1     Running   0          29s
jenkins-7cd8b95d79-6vrbn        1/1     Running   0          3d2h
```
#### 3.3.2 添加dns解析
这个服务是有web页面的，创建了ingress和service资源的,所以需要添加dns解析
```
vi /var/named/zq.com.zone
dobbo-monitor		A    10.4.7.10
```
重启并验证
```
systemctl restart named
dig -t A dubbo-monitor.zq.com @10.4.7.11 +short
```
#### 3.3.3 访问monitor的web页面
访问`dubbo-monitor.zq.com`
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601204368042-4d67eb3e-e800-4ed9-abc3-11908482adb2.png)
这里已经可以看到我们之前部署的dubbo-demo-service服务了，启动了两个进程来提供服务。
至此，dubbo-monitor监控服务已经部署完成。

## 4 构建dubbo-consumer服务
### 4.1 构建docker镜像
#### 4.1.1 获取私有仓库代码
之前创建的dubbo-service是微服务的提供者,现在创建一个微服务的消费者
使用`git@gitee.com:noah-luo/dubbo-demo-web.git`这个私有仓库中的代码构建消费者
先从`[https://gitee.com/sunx66/dubbo-demo-service](https://gitee.com/sunx66/dubbo-demo-service)`这里fork到自己仓库,在设为私有
并修改zk的配置
#### 4.1.2 配置流水线
之前已经在jenkins配置好了流水线，只需要填写参数就行了。

| 参数名 | 参数值 |
| --- | --- |
| app_name | dubbo-demo-consumer |
| image_name | app/dubbo-demo-consumer |
| git_repo | git@gitee.com:noah-luo/dubbo-demo-web.git |
| git_ver | master |
| add_tag | 200506_1430 |
| mvn_dir | ./ |
| target_dir | ./dubbo-client/target |
| mvn_cmd | mvn clean package -Dmaven.test.skip=true |
| base_image | base/jre8:8u112 |
| maven | 3.6.1 |

#### 4.1.3 查看构建结果
如果构建不报错,则应该已经推送到harbor仓库中了,这时我们直接再给镜像一个新tag,以便后续模拟更新
```
docker tag \
    harbor.zq.com/app/dubbo-demo-consumer:master_200506_1430 \
    harbor.zq.com/app/dubbo-demo-consumer:master_200510_1430
docker push harbor.zq.com/app/dubbo-demo-consumer:master_200510_1430
```
查看harbor仓库
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601204368028-4ba20ef3-8d31-4b15-b40a-7234e8bdd6fe.png)

### 4.2 准备资源配置清单：
先准备目录
```
mkdir /data/k8s-yaml/dubbo-consumer
cd /data/k8s-yaml/dubbo-consumer
```
#### 4.2.1 创建deploy资源清单
```
cat >dp.yaml <<EOF
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: dubbo-demo-consumer
  namespace: app
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
    spec:
      containers:
      - name: dubbo-demo-consumer
        image: harbor.zq.com/app/dubbo-demo-consumer:master_200506_1430
        ports:
        - containerPort: 8080
          protocol: TCP
        - containerPort: 20880
          protocol: TCP
        env:
        - name: JAR_BALL
          value: dubbo-client.jar
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
> 注意修改镜像的tag

#### 4.2.2 创建service资源清单
```
cat >svc.yaml <<EOF
kind: Service
apiVersion: v1
metadata:
  name: dubbo-demo-consumer
  namespace: app
spec:
  ports:
  - protocol: TCP
    port: 8080
    targetPort: 8080
  selector:
    app: dubbo-demo-consumer
EOF
```
#### 4.2.3 创建ingress资源清单
```
cat >ingress.yaml <<EOF
kind: Ingress
apiVersion: extensions/v1beta1
metadata:
  name: dubbo-demo-consumer
  namespace: app
spec:
  rules:
  - host: dubbo-demo.zq.com
    http:
      paths:
      - path: /
        backend:
          serviceName: dubbo-demo-consumer
          servicePort: 8080
EOF
```
### 4.3 创建K8S资源
#### 4.3.1 应用资源配置清单：
```
kubectl apply -f http://k8s-yaml.zq.com/dubbo-consumer/dp.yaml
kubectl apply -f http://k8s-yaml.zq.com/dubbo-consumer/svc.yaml
kubectl apply -f http://k8s-yaml.zq.com/dubbo-consumer/ingress.yaml
# 查看容器启动成功没
~]# kubectl get pod -n app
NAME                                  READY   STATUS    RESTARTS   AGE
dubbo-demo-consumer-b8d86bd5b-wbqhs   1/1     Running   0          6s
dubbo-demo-service-79574b6879-cxkls   1/1     Running   0          4h39m
```
#### 4.3.2 验证启动结果
查看log，是否启动成功：
```
~]# kubectl -n app  logs --tail=2 dubbo-demo-consumer-b8d86bd5b-wbqhs
Dubbo client started
Dubbo 消费者端启动
```
检查dubbo-monitor是否已经注册成功：
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601204368242-db7a8ac0-8c7f-4b71-b656-49969137fc83.png)

#### 4.3.3 添加dns解析
```
vi /var/named/zq.com.zone
dubbo-demo		A    10.4.7.10
# 重启服务
systemctl restart named
# 验证
~]# dig -t A dubbo-demo.zq.com @10.4.7.11 +short
10.4.7.10
```
浏览器访问`[http://dubbo-demo.zq.com/hello?name=lg](http://dubbo-demo.zq.com/hello?name=lg)`
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601204368060-46fb580a-0c41-4633-b2b1-6b6f843860bb.png)

### 4.4 模拟版本升级
接下来我们模拟升级发版，之前已经用同一个镜像打了不同的tag并推送到从库
当然正常发版的顺序是:

1. 提交修改过的代码的代码块
1. 使用jenkins构建新镜像
1. 上传到私有harbor仓库中
1. 更新de文件并apply
#### 4.4.1 修改dp.yaml资源配置清单
修改harbor镜像仓库中对应的tag版本：
```
sed -i 's#master_200506_1430#master_200510_1430#g' dp.yaml
```
#### 4.4.2 应用修改后的资源配置清单
当然也可以在dashboard中进行在线修改：
```
kubectl apply -f http://k8s-yaml.zq.com/dubbo-consumer/dp.yaml
~]# kubectl -n app  get pod
NAME                                   READY   STATUS    RESTARTS   AGE
dubbo-demo-consumer-84f75b679c-kdwd7   1/1     Running   0          54s
dubbo-demo-service-79574b6879-cxkls    1/1     Running   0          4h58m
```
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601204368205-01dd6858-d8ad-4ab9-8a98-0ed740a29399.png)
#### 4.4.3 使用浏览器验证
使用浏览器验证：[http://dubbo-demo.zq.com/hello?name=lg](http://dubbo-demo.zq.com/hello?name=lg)
在短暂的超时后,即可正常访问
至此，我们一套完成的dubbo服务就已经交付到k8s集群当中了，并且也演示了如何发版。

