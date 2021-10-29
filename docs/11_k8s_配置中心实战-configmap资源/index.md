# 11_K8S_配置中心实战-configmap资源


# 11_K8S配置中心实战-configmap资源
## 1 configmap使用准备
使用configmap前,需要先做如下准备工作
### 1.1 清理资源
先将前面部署的3个dubbo服务的POD个数全部调整(scale)为0个,避免在应用configmap过程中可能的报错,也为了节省资源
直接在dashboard上操作即可,
### 1.2 拆分zk集群
将3个zk组成的集群,拆分成独立的zk单机服务,分别表示测试环境和开发环境(节约资源)

| IP地址 | ZK地址 | 角色 |
| --- | --- | --- |
| 10.4.7.11 | zk1.zq.com | test测试环境 |
| 10.4.7.12 | zk2.zq.com | pro生产环境 |

**停止3个zk服务**
```
sh /opt/zookeeper/bin/zkServer.sh stop
rm -rf /data/zookeeper/data/*
rm -rf /data/zookeeper/logs/*
```
**注释掉集群配置**
```
sed -i 's@^server@#server@g' /opt/zookeeper/conf/zoo.cfg
```
启动zk单机
```
sh /opt/zookeeper/bin/zkServer.sh start
sh /opt/zookeeper/bin/zkServer.sh status
```
### 1.3 创建dubbo-monitor资源清单
老规矩,资源清单在`7.200`运维机上统一操作
```
cd /data/k8s-yaml/dubbo-monitor
```
#### 1.3.1 创建comfigmap清单
```
cat >cm.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: dubbo-monitor-cm
  namespace: infra
data:
  dubbo.properties: |
    dubbo.container=log4j,spring,registry,jetty
    dubbo.application.name=simple-monitor
    dubbo.application.owner=zqkj
    dubbo.registry.address=zookeeper://zk1.zq.com:2181
    dubbo.protocol.port=20880
    dubbo.jetty.port=8080
    dubbo.jetty.directory=/dubbo-monitor-simple/monitor
    dubbo.charts.directory=/dubbo-monitor-simple/charts
    dubbo.statistics.directory=/dubbo-monitor-simple/statistics
    dubbo.log4j.file=/dubbo-monitor-simple/logs/dubbo-monitor.log
    dubbo.log4j.level=WARN
EOF
```
> 其实就是把dubbo-monitor配置文件中的内容用configmap语法展示出来了
> 当然最前面加上了相应的元数据信息

如果转换不来格式,也可以使用命令行工具直接将配置文件转换为configmap
```
kubectl create configmap <map-name> <data-source>
# <map-name> 是希望创建的ConfigMap的名称，<data-source>是一个目录、文件和具体值。
```
案例如下:
```
# 1.通过单个文件创建ConfigMap
kubectl create configmap game-config-1 --from-file=/xxx/xxx.properties
# 2.通过多个文件创建ConfigMap
kubectl create configmap game-config-2 \
    --from-file=/xxx/xxx.properties \
    --from-file=/xxx/www.properties
# 3.通过在一个目录下的多个文件创建ConfigMap
kubectl create configmap game-config-3 --from-file=/xxx/www/
```
#### 1.3.2 修改deploy清单内容
为了和原来的`dp.yaml`对比,我们新建一个`dp-cm.yaml`
```
cat >dp-cm.yaml <<'EOF'
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
#----------------start---------------------------
        volumeMounts:
          - name: configmap-volume
            mountPath: /dubbo-monitor-simple/conf
      volumes:
        - name: configmap-volume
          configMap:
            name: dubbo-monitor-cm
#----------------end-----------------------------
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
> 注释中的内容就是新增在原`dp.yaml`中增加的内容,解释如下:
> 1. 申明一个卷,卷名为`configmap-volume`
> 1. 指定这个卷使用名为`dubbo-monitor-cm`的configMap
> 1. 在`containers`中挂载卷,卷名与申明的卷相同
> 1. 用`mountPath`的方式挂载到指定目录

### 1.4 创建资源并检查
#### 1.4.1 应用资源配置清单
```
kubectl apply -f http://k8s-yaml.zq.com/dubbo-monitor/cm.yaml
kubectl apply -f http://k8s-yaml.zq.com/dubbo-monitor/dp-cm.yaml
```
#### 1.4.2 dashboard检查创建结果
在dashboard中查看`infra`名称空间中的`configmap`资源
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219475420-f310f68a-6361-4a93-af9a-15d182a27c6b.png)
然后检查容器中的配置

```
kubectl -n infra exec -it dubbo-monitor-5b7cdddbc5-xpft6 bash
# 容器内
bash-4.3# cat /dubbo-monitor-simple/conf/dubbo.properties
dubbo.container=log4j,spring,registry,jetty
dubbo.application.name=simple-monitor
dubbo.application.owner=zqkj
dubbo.registry.address=zookeeper://zk1.zq.com:2181
....
```
#### 1.4.3 检查dubbo-monitor页面的注册信息
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219475407-be507fc0-7200-4cbf-931d-616fe2ccae51.png)
## 2 更新configmap资源
### 2.1 多配置更新法
#### 2.1.1 准备新configmap
再准备一个configmap叫`cm-pro.yaml`
```
cp cm.yaml cm-pro.yaml
# 把资源名字改成dubbo-monitor-cm-pro
sed -i 's#dubbo-monitor-cm#dubbo-monitor-cm-pro#g' cm-pro.yaml
# 把服务注册到zk2.zq.com上
sed -i 's#zk1#zk2#g' cm-pro.yaml
```
#### 2.1.2 修改deploy配置
```
sed -i 's#dubbo-monitor-cm#dubbo-monitor-cm-pro#g' dp-cm.yaml
```
#### 2.1.3 更新资源
```
# 应用新configmap
kubectl apply -f http://k8s-yaml.zq.com/dubbo-monitor/cm-pro.yaml
# 更新deploy
kubectl apply -f http://k8s-yaml.zq.com/dubbo-monitor/dp-cm.yaml
```
#### 2.1.4 检查配置是否更新
新的pod已经起来了
```
~]# kubectl -n infra get pod
NAME                            READY   STATUS    RESTARTS   AGE
dubbo-monitor-c7fbf68b9-7nffj   1/1     Running   0          52s
```
进去看看是不是应用的新的configmap配置：
```
kubectl  -n infra exec -it dubbo-monitor-5cb756cc6c-xtnrt bash
# 容器内
bash-4.3# cat /dubbo-monitor-simple/conf/dubbo.properties |grep zook
dubbo.registry.address=zookeeper://zk2.zq.com:2181
```
看下dubbo-monitor的页面：已经是zk2了。
## 3 挂载方式探讨
### 3.1 monutPath挂载的问题
我们使用的是mountPath，这个是挂载整个目录，会使容器内的被挂载目录中原有的文件不可见，可以看见我们。
查看我们pod容器启动的命令可以看见原来脚本中的命令已经无法对挂载的目录操作了
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219475472-a323a491-bd17-473b-b60c-825d7f78fada.png)
**如何单独挂载一个配置文件:**
只挂载单独一个文件而不是整个目录，需要添加`subPath`方法

### 3.2 单独挂载文件演示
#### 3.2.1 更新配置
在`dp-cm.yaml`的配置中,将原来的volume配置做一下更改
```
#----------------start---------------------------
        volumeMounts:
          - name: configmap-volume
            mountPath: /dubbo-monitor-simple/conf
      volumes:
        - name: configmap-volume
          configMap:
            name: dubbo-monitor-cm
#----------------end-----------------------------
# 调整为
#----------------start---------------------------
        volumeMounts:
          - name: configmap-volume
            mountPath: /dubbo-monitor-simple/conf
          - name: configmap-volume
            mountPath: /var/dubbo.properties
            subPath: dubbo.properties
      volumes:
        - name: configmap-volume
          configMap:
            name: dubbo-monitor-cm
#----------------end-----------------------------
```
#### 3.2.2 应用apply配置并验证
```
kubectl apply -f http://k8s-yaml.zq.com/dubbo-monitor/dp-cm.yaml
kubectl  -n infra exec -it dubbo-monitor-5cb756cc6c-xtnrt bash
# 容器内操作
bash-4.3# ls -l /var/
total 4
drwxr-xr-x    1 root     root      29 Apr 13  2016 cache
-rw-r--r--    1 root     root     459 May 10 10:02 dubbo.properties
drwxr-xr-x    2 root     root       6 Apr  1  2016 empty
.....
```



