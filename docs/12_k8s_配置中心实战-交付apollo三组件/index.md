# 12_K8S_配置中心实战-交付apollo三组件


# 12_K8S_配置中心实战-交付apollo三组件
## 1 apollo简单说明
[官方地址](https://github.com/ctripcorp/apollo)
[概念请参考](http://www.liuhaihua.cn/archives/522960.html)

### 1.1 apollo最简架构图：

### 1.2 apollo组件部署关系

1. configservice自带eureka注册中心、配置写入configDB数据库、优先部署、为client提供服务
1. adminservice向eureka注册服务、与configservice共用数据库、为portal提供服务
1. configservice和adminservice组成一套环境、多个环境就得部署多套config和admin
1. portal是web端、各环境共用、只需部署一套、有自己单独的数据库
## 2 为appllo准备数据库
apollo需要使用数据库，如果是mysql，需要版本在5.6以上：
本次环境mysql部署在10.4.7.11上，使用mysql5.7，为测试简单起见，各环境数据库使用同一个，不做隔离
### 2.1 下载安装mysql
#### 2.1.1 yum安装mysql
```
rpm -Uvh https://dev.mysql.com/get/mysql80-community-release-el7-1.noarch.rpm
yum -y install yum-utils
yum-config-manager --disable mysql80-community
yum-config-manager --enable mysql57-community
yum install mysql-server -y
```
#### 2.1.2 创建简单配置文件
```
cat >/etc/my.cnf <<'EOF'
[mysqld]
character_set_server = utf8mb4
collation_server = utf8mb4_general_ci
init_connect = "SET NAMES 'utf8mb4'"
[mysql]
default-character-set = utf8mb4
EOF
```
#### 2.1.2 启动mysql并初始设置
```
systemctl start  mysqld
systemctl enable mysqld
mysql -u root -p`grep password /var/log/messages|awk '{print $NF}'`
# 修改密码
> set global validate_password_policy=0;
> set global validate_password_length=1;
> set password=password('123456');
> flush privileges;
# 检查字符集：需要四个都是utf8mb4
> \s
```
## 3 初始化appllo数据库
[configdb初始化脚本](https://github.com/ctripcorp/apollo/blob/1.5.1/scripts/db/migration/configdb/V1.0.0__initialization.sql)
[portal初始化脚本](https://github.com/ctripcorp/apollo/blob/master/scripts/db/migration/portaldb/V1.0.0__initialization.sql)
### 3.1 configdb数据库
#### 3.1.1下载脚本并执行：
```
wget -O apolloconfig.sql https://raw.githubusercontent.com/ctripcorp/apollo/1.5.1/scripts/db/migration/configdb/V1.0.0__initialization.sql
# 导入sql文件
mysql -uroot -p123456 < apolloconfig.sql
# 检查是否导入成功
mysql -uroot -p123456 -e "show databases;"|grep ApolloConfigDB
```
#### 3.1.2 授权并修改初始数据：
```
mysql -uroot -p123456
> grant INSERT,DELETE,UPDATE,SELECT on ApolloConfigDB.* to 'apollo'@'10.4.7.%'  identified by "123456";
# 修改数据
> use ApolloConfigDB
> update ServerConfig set Value='http://apollo-config.zq.com/eureka' where Id=1;
```
#### 3.1.3 添加config域名解析：
```
vi /var/named/zq.com.zone
mysql				A    10.4.7.11
apollo-config		A    10.4.7.10
apollo-admin		A    10.4.7.10
apollo-portal		A    10.4.7.10
# 重启并验证
systemctl restart named
dig -t A apollo-config.zq.com @10.4.7.11 +short
```
### 3.2 portal数据库
由于portal使用的是另一个portaldb，我们需要在数据库中新建portdb，并初始化
#### 3.2.1 下载并执行
```
wget -O apollo-portal.sql https://raw.githubusercontent.com/ctripcorp/apollo/1.5.1/scripts/db/migration/portaldb/V1.0.0__initialization.sql
# 导入sql文件
mysql -uroot -p123456 < apollo-portal.sql
# 检查是否导入成功
mysql -uroot -p123456 -e "show databases;"|grep ApolloPortalDB
```
#### 3.2.2 授权用户并更新初始数据
都使用`apollo`用户来管理数据库是为了方便,如果有相关的安全考虑可以给config和portal分别使用不同的数据库账号
```
mysql -uroot -p123456
> grant INSERT,DELETE,UPDATE,SELECT on ApolloPortalDB.* to "apollo"@"10.4.7.%" identified by "123456";
# 更新部门名
> update ApolloPortalDB.ServerConfig set Value='[{"orgId":"zq01","orgName":"研发部"},{"orgId":"zq02","orgName":"运维部"}]' where Id=2;
```
## 4 部署configservice
### 4.1 制作docker镜像
操作在`7.200`上完成
#### 4.1.1 下载程序包
```
wget https://github.com/ctripcorp/apollo/releases/download/v1.5.1/apollo-configservice-1.5.1-github.zip
mkdir /data/dockerfile/apollo-configservice
unzip -o apollo-configservice-1.5.1-github.zip -d /data/dockerfile/apollo-configservice/
```
#### 4.1.2 修改连接数据库配置：
```
cd /data/dockerfile/apollo-configservice/config
# 修改数据库连接地址
sed -i 's#fill-in-the-correct-server#mysql.zq.com#g' application-github.properties
# 修改数据库连接用户和密码
sed -i 's#FillInCorrectUser#apollo#g'     application-github.properties
sed -i 's#FillInCorrectPassword#123456#g' application-github.properties
# 查看结果
config]# egrep -v "^#|$^" application-github.properties
spring.datasource.url = jdbc:mysql://mysql.zq.com:3306/ApolloConfigDB?characterEncoding=utf8
spring.datasource.username = apollo
spring.datasource.password = 123456
```
#### 4.1.3 创建启动脚本：
程序中自带的`start.sh`启动脚本时不适用与K8S运行,因此需要专门下载他们提供的K8S内使用的脚本
```
# 1.从官网下载启动脚本
cd /data/dockerfile/apollo-configservice/scripts/
wget https://raw.githubusercontent.com/ctripcorp/apollo/1.5.1/scripts/apollo-on-kubernetes/apollo-config-server/scripts/startup-kubernetes.sh
# 2. 添加一行使用主机名的变量
sed -i '5i APOLLO_CONFIG_SERVICE_NAME=$(hostname -i)' startup-kubernetes.sh
# 3.根据需要修改下jvm限制
```
#### 4.1.4 编写dockerfile
[dockerfile官方地址](https://github.com/ctripcorp/apollo/blob/1.5.1/scripts/apollo-on-kubernetes/apollo-config-server/Dockerfile)
```
cd ..
cat >Dockerfile <<'EOF'
FROM harbor.zq.com/base/jre8:8u112
ENV VERSION 1.5.1
RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime &&\
    echo "Asia/Shanghai" > /etc/timezone
ADD apollo-configservice-${VERSION}.jar /apollo-configservice/apollo-configservice.jar
ADD config/  /apollo-configservice/config
ADD scripts/ /apollo-configservice/scripts
CMD ["sh","/apollo-configservice/scripts/startup-kubernetes.sh"]
EOF
```
#### 4.1.5 构建docker镜像
```
docker build . -t harbor.zq.com/infra/apollo-configservice:v1.5.1
docker push       harbor.zq.com/infra/apollo-configservice:v1.5.1
```
### 4.2 编写资源配置清单：
```
mkdir /data/k8s-yaml/apollo-configservice
cd /data/k8s-yaml/apollo-configservice
```
#### 4.2.1 创建config的configmap资源清单
给configservice创建cm资源的清单的目的是方便修改
其实里面的内容就是前面修改的`application-github.properties`文件
如果确定不会修改,可以不创建此cm,直接写死配置到docker镜像中
```
cat >cm.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: apollo-configservice-cm
  namespace: infra
data:
  application-github.properties: |
    # DataSource
    spring.datasource.url = jdbc:mysql://mysql.zq.com:3306/ApolloConfigDB?characterEncoding=utf8
    spring.datasource.username = apollo
    spring.datasource.password = 123456
    eureka.service.url = http://apollo-config.zq.com/eureka
  app.properties: |
    appId=100003171
EOF
```
> 在同一个configmap资源中,可以添加多个配置文件,上述配置就有两个,分别是:
> `application-github.properties`和`app.properties`

#### 4.2.2 创建Deployment资源清单
```
cat >dp.yaml <<'EOF'
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: apollo-configservice
  namespace: infra
  labels:
    name: apollo-configservice
spec:
  replicas: 1
  selector:
    matchLabels:
      name: apollo-configservice
  template:
    metadata:
      labels:
        app: apollo-configservice
        name: apollo-configservice
    spec:
      volumes:
      - name: configmap-volume
        configMap:
          name: apollo-configservice-cm
      containers:
      - name: apollo-configservice
        image: harbor.zq.com/infra/apollo-configservice:v1.5.1
        ports:
        - containerPort: 8080
          protocol: TCP
        volumeMounts:
        - name: configmap-volume
          mountPath: /apollo-configservice/config
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
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
#### 4.2.3 创建service资源清单
```
cat >svc.yaml <<'EOF'
kind: Service
apiVersion: v1
metadata:
  name: apollo-configservice
  namespace: infra
spec:
  ports:
  - protocol: TCP
    port: 8080
    targetPort: 8080
  selector:
    app: apollo-configservice
EOF
```
#### 4.2.4 创建ingress资源清单
```
cat >ingress.yaml <<'EOF'
kind: Ingress
apiVersion: extensions/v1beta1
metadata:
  name: apollo-configservice
  namespace: infra
spec:
  rules:
  - host: apollo-config.zq.com
    http:
      paths:
      - path: /
        backend:
          serviceName: apollo-configservice
          servicePort: 8080
EOF
```
> service中不一定必须暴露8080,分配的clusterIP中所有的端口都可以
> 但ingress中的servicePort一定要与service中暴露的端口匹配

### 4.3 应用资源配置清单：
#### 4.3.1 任意node执行
```
kubectl create -f http://k8s-yaml.zq.com/apollo-configservice/cm.yaml
kubectl create -f http://k8s-yaml.zq.com/apollo-configservice/dp.yaml
kubectl create -f http://k8s-yaml.zq.com/apollo-configservice/svc.yaml
kubectl create -f http://k8s-yaml.zq.com/apollo-configservice/ingress.yaml
```
#### 4.3.2 检查启动情况：
```
kubectl -n infra get pod|grep apollo-config
# 检查命令
kubectl -n infra logs apollo-configservice-64fc749978-9nz5h --tail=4
```
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219581895-435fc5dd-2685-4c88-b68c-8137bb3b9bd3.png)
![](https://cdn.nlark.com/yuque/0/2020/png/2511954/1601219581709-4b3e7a7f-b40c-4f4f-9c80-fa020a92d2b3.png#align=left&display=inline&height=32&margin=%5Bobject%20Object%5D&originHeight=32&originWidth=785&size=0&status=done&style=none&width=785)
![](https://cdn.nlark.com/yuque/0/2020/png/2511954/1601219581687-b1ddac7f-619a-41bb-bb6e-75b02db5fc28.png#align=left&display=inline&height=135&margin=%5Bobject%20Object%5D&originHeight=135&originWidth=744&size=0&status=done&style=none&width=744)
需要等到eureka启动以后才可以，接下来使用浏览器访问`apollo-config.zq.com`
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219581678-8c7e25fe-3979-4358-8307-8d0287710b7c.png)

## 5 部署adminservice
[官方地址](https://github.com/ctripcorp/apollo/releases/download/v1.5.1/apollo-adminservice-1.5.1-github.zip)
### 5.1 制作docker镜像
操作在`7.200`上完成
#### 5.1.1 下载程序包
```
wget https://github.com/ctripcorp/apollo/releases/download/v1.5.1/apollo-adminservice-1.5.1-github.zip
mkdir /data/dockerfile/apollo-adminservice
unzip -o apollo-adminservice-1.5.1-github.zip -d /data/dockerfile/apollo-adminservice/
```
#### 5.1.2 修改连接数据库配置：
由于使用了configmap资源将配置文件挂载出来了，所以不在修改配置文件，如需修改配置文件，请参考部署apollo-configservice时候的修改方法：
#### 5.1.3 创建启动脚本：
程序中自带的`start.sh`启动脚本时不适用与K8S运行,因此需要专门下载他们提供的K8S内使用的脚本
```
# 1.从官网下载启动脚本
cd /data/dockerfile/apollo-adminservice/scripts/
wget https://raw.githubusercontent.com/ctripcorp/apollo/1.5.1/scripts/apollo-on-kubernetes/apollo-admin-server/scripts/startup-kubernetes.sh
# 2. 添加一行使用主机名的变量
sed -i '5i APOLLO_CONFIG_SERVICE_NAME=$(hostname -i)' startup-kubernetes.sh
# 3.修改端口为8080
sed -i 's#8090#8080#g' startup-kubernetes.sh
```
> 官方配置文件端口改为8090的目的是虚拟机部署的时候端口不冲突
> 但我们用K8S部署,会给他单独的clusterIP,所以不用担心端口重复

#### 5.1.4 编写dockerfile
```
cd ..
cat >Dockerfile <<'EOF'
FROM stanleyws/jre8:8u112
ENV VERSION 1.5.1
RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime &&\
    echo "Asia/Shanghai" > /etc/timezone
ADD apollo-adminservice-${VERSION}.jar /apollo-adminservice/apollo-adminservice.jar
ADD config/ /apollo-adminservice/config
ADD scripts/ /apollo-adminservice/scripts
CMD ["/bin/bash","/apollo-adminservice/scripts/startup-kubernetes.sh"]
EOF
```
> 由于要使用cm配置资源,因此就不改config中的配置了

#### 5.1.5 构建docker镜像
```
docker build . -t harbor.zq.com/infra/apollo-adminservice:v1.5.1
docker push       harbor.zq.com/infra/apollo-adminservice:v1.5.1
```
### 5.2 制作资源配置清单：
adminservice向注册中心注册服务,不直接对外提供服务,因此不需要暴露端口,只需要cm资源和dp资源
```
mkdir /data/k8s-yaml/apollo-adminservice
cd /data/k8s-yaml/apollo-adminservice
```
#### 5.2.1 创建configmap资源清单
```
cat >cm.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: apollo-adminservice-cm
  namespace: infra
data:
  application-github.properties: |
    # DataSource
    spring.datasource.url = jdbc:mysql://mysql.zq.com:3306/ApolloConfigDB?characterEncoding=utf8
    spring.datasource.username = apollo
    spring.datasource.password = 123456
    eureka.service.url = http://apollo-config.zq.com/eureka
  app.properties: |
    appId=100003172
EOF
```
> 注意每个服务的appId都不会一样哦

#### 5.2.2 创建Deployment资源清单
```
cat >dp.yaml <<'EOF'
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: apollo-adminservice
  namespace: infra
  labels:
    name: apollo-adminservice
spec:
  replicas: 1
  selector:
    matchLabels:
      name: apollo-adminservice
  template:
    metadata:
      labels:
        app: apollo-adminservice
        name: apollo-adminservice
    spec:
      volumes:
      - name: configmap-volume
        configMap:
          name: apollo-adminservice-cm
      containers:
      - name: apollo-adminservice
        image: harbor.zq.com/infra/apollo-adminservice:v1.5.1
        ports:
        - containerPort: 8080
          protocol: TCP
        volumeMounts:
        - name: configmap-volume
          mountPath: /apollo-adminservice/config
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
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
### 5.3 应用资源配置清单
#### 5.3.1 任意node执行
```
kubectl create -f http://k8s-yaml.zq.com/apollo-adminservice/cm.yaml
kubectl create -f http://k8s-yaml.zq.com/apollo-adminservice/dp.yaml
```
#### 5.3.2 检查启动情况
```
~]# kubectl -n infra get pod|grep apollo-admin
apollo-adminservice-6cd4fcfdc8-2drnq    1/1     Running   0          9s
# 检查命令
kubectl -n infra logs apollo-configservice-6cd4fcfdc8-2drnq --tail=4
```
通过 apollo-config.zq.com 检查是否注册到了eureka：
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219581647-740a84ca-3d5a-41cf-9fdc-26deb1335482.png)
已经顺利的注册到了注册中心中。

## 6 部署portal
### 6.1 制作docker镜像
[portal官方地址](https://github.com/ctripcorp/apollo/releases/download/v1.5.1/apollo-portal-1.5.1-github.zip)
#### 6.1.1 下载程序包
```
wget https://github.com/ctripcorp/apollo/releases/download/v1.5.1/apollo-portal-1.5.1-github.zip
mkdir /data/dockerfile/apollo-portal
unzip -o apollo-portal-1.5.1-github.zip -d /data/dockerfile/apollo-portal/
```
#### 6.1.2 修改配置文件
由于使用concigmap资源，故不在这里修改
注意如果要修改的话,要分别修改两个文件

1. `apollo-env.properties`修改数据库配置
1. `apollo-env.properties`修改支持的环境列表
#### 6.1.3 创建启动脚本
[脚本官方地址](https://raw.githubusercontent.com/ctripcorp/apollo/1.5.1/scripts/apollo-on-kubernetes/apollo-portal-server/scripts/startup-kubernetes.sh)
```
# 1.从官网下载启动脚本
cd /data/dockerfile/apollo-portal/scripts/
wget https://raw.githubusercontent.com/ctripcorp/apollo/1.5.1/scripts/apollo-on-kubernetes/apollo-portal-server/scripts/startup-kubernetes.sh
# 2. 添加一行使用主机名的变量
sed -i '5i APOLLO_CONFIG_SERVICE_NAME=$(hostname -i)' startup-kubernetes.sh
# 3.修改端口为8080
sed -i 's#8070#8080#g' startup-kubernetes.sh
```
#### 6.1.4 制作dockerfile：
```
cd /data/dockerfile/apollo-portal/
cat >Dockerfile <<'EOF'
FROM stanleyws/jre8:8u112
ENV VERSION 1.5.1
RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime &&\
    echo "Asia/Shanghai" > /etc/timezone
ADD apollo-portal-${VERSION}.jar /apollo-portal/apollo-portal.jar
ADD config/ /apollo-portal/config
ADD scripts/ /apollo-portal/scripts
CMD ["/bin/bash","/apollo-portal/scripts/startup-kubernetes.sh"]
EOF
```
#### 6.1.5 构建docker镜像
```
docker build . -t harbor.zq.com/infra/apollo-portal:v1.5.1
docker push       harbor.zq.com/infra/apollo-portal:v1.5.1
```
### 6.2 编写资源配置清单：
```
mkdir /data/k8s-yaml/apollo-portal
cd /data/k8s-yaml/apollo-portal
```
#### 6.2.1 创建configmap资源清单
```
cat >cm.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: apollo-portal-cm
  namespace: infra
data:
  application-github.properties: |
    # DataSource
    spring.datasource.url = jdbc:mysql://mysql.zq.com:3306/ApolloPortalDB?characterEncoding=utf8
    spring.datasource.username = apollo
    spring.datasource.password = 123456
  app.properties: |
    appId=100003173
  apollo-env.properties: |
    dev.meta=http://apollo-config.zq.com
EOF
```
> 这里暂时只管理一个环境,等跑通了以后,再演示多环境问题

#### 6.2.2 创建Deployment资源清单
```
cat >dp.yaml <<'EOF'
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: apollo-portal
  namespace: infra
  labels:
    name: apollo-portal
spec:
  replicas: 1
  selector:
    matchLabels:
      name: apollo-portal
  template:
    metadata:
      labels:
        app: apollo-portal
        name: apollo-portal
    spec:
      volumes:
      - name: configmap-volume
        configMap:
          name: apollo-portal-cm
      containers:
      - name: apollo-portal
        image: harbor.zq.com/infra/apollo-portal:v1.5.1
        ports:
        - containerPort: 8080
          protocol: TCP
        volumeMounts:
        - name: configmap-volume
          mountPath: /apollo-portal/config
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
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
#### 6.2.3 创建service资源清单
```
cat >svc.yaml <<'EOF'
kind: Service
apiVersion: v1
metadata:
  name: apollo-portal
  namespace: infra
spec:
  ports:
  - protocol: TCP
    port: 8080
    targetPort: 8080
  selector:
    app: apollo-portal
EOF
```
#### 6.2.4 创建ingress资源清单
```
cat >ingress.yaml <<'EOF'
kind: Ingress
apiVersion: extensions/v1beta1
metadata:
  name: apollo-portal
  namespace: infra
spec:
  rules:
  - host: apollo-portal.zq.com
    http:
      paths:
      - path: /
        backend:
          serviceName: apollo-portal
          servicePort: 8080
EOF
```
### 6.3 应用资源配置清单
#### 6.3.1 在任意node执行
```
kubectl create -f http://k8s-yaml.zq.com/apollo-portal/cm.yaml
kubectl create -f http://k8s-yaml.zq.com/apollo-portal/dp.yaml
kubectl create -f http://k8s-yaml.zq.com/apollo-portal/svc.yaml
kubectl create -f http://k8s-yaml.zq.com/apollo-portal/ingress.yaml
```
#### 6.3.2 检查启动情况
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219581934-efceea0e-1eaa-4193-96fc-c6f129d5b4ca.png)
#### 6.3.3 网页验证
由于前面已经一起添加了域名解析,因此portal创建好后不需要在添加域名解析,直接浏览器登录验证
网页：apollo-portal.zq.com
默认用户名：apollo
默认密码：admin
登录成功后,立马修改密码为`apollo123`
到此，apollo的三个组件都已经交付到k8s里了。
## 7 配置服务使用apollo配置中心
使用配置中心，需要开发对代码进行调整，将一些配置，通过变量的形式配置到apollo中，服务通过配置中心来获取具体的配置
### 7.1 新建dubbo-service项目配置
#### 7.1.1 在配置中心修改新增项目:
**项目属性：**
AppId：dubbo-demo-service
应用名称：dubbo服务提供者
部门：研发部
**为新项目添加配置如下：**

| key | value | 备注 |
| --- | --- | --- |
| dubbo.registry | zookeeper://zk1.zq.com:2181 | 注册中心地址 |
| dubbo.port | 20880 | dubbo服务监听端口 |

**发布后效果图如下：**
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219581669-4f254c8b-1382-4170-a5d8-6c6a0dbbe7f0.png)

#### 7.1.2 重新打包service镜像
还是使用之前的流水线，但是使用分支为apollo的代码进行打包，参数如下：

| 参数名 | 参数值 |
| --- | --- |
| app_name | dubbo-demo-service |
| image_name | app/dubbo-demo-service |
| git_repo | [https://gitee.com/noah-luo/dubbo-demo-service.git](https://gitee.com/noah-luo/dubbo-demo-service.git) |
| git_ver | apollo |
| add_tag | 200512_0746 |
| mvn_dir | ./ |
| target_dir | ./dubbo-server/target |
| mvn_cmd | mvn clean package -Dmaven.test.skip=true |
| base_image | base/jre8:8u112 |
| maven | 3.6.1 |

#### 7.1.3 重新应用资源配置清单
修改dp.yaml资源配置清单

1. 将镜像改为刚刚打包的镜像名：
1. 添加环境变量`C_OPTS`,以便指定配置中心
```
vim /data/k8s-yaml/dubbo-server/dp.yaml
#----------原内容----------
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

#----------新内容----------
    spec:
      containers:
      - name: dubbo-demo-service
        image: harbor.zq.com/app/dubbo-demo-service:apollo_200512_0746
        ports:
        - containerPort: 20880
          protocol: TCP
        env:
        - name: JAR_BALL
          value: dubbo-server.jar
        - name: C_OPTS
          value: -Denv=dev -Dapollo.meta=http://apollo-config.zq.com
```
**应用资源配置清单：**
```
kubectl apply -f http://k8s-yaml.zq.com/dubbo-server/dp.yaml
```
### 7.2 新建dubbo-web项目配置
#### 7.2.1 在配置中心修改新增项目:
**项目属性：**
AppId：dubbo-demo-web
应用名称：dubbo服务消费者
部门：运维部
**为新项目添加配置如下：**

| key | value | 备注 |
| --- | --- | --- |
| dubbo.registry | zookeeper://zk1.zq.com:2181 | 注册中心地址 |

**发布后效果图如下：**
略
#### 7.1.2 重新打包service镜像
还是使用之前的流水线，但是使用分支为apollo的代码进行打包，参数如下：

| 参数名 | 参数值 |
| --- | --- |
| app_name | dubbo-demo-consumer |
| image_name | app/dubbo-demo-consumer |
| git_repo | git@gitee.com:noah-luo/dubbo-demo-web.git |
| git_ver | apollo |
| add_tag | 200512_0801 |
| mvn_dir | ./ |
| target_dir | ./dubbo-client/target |
| mvn_cmd | mvn clean package -Dmaven.test.skip=true |
| base_image | base/jre8:8u112 |
| maven | 3.6.1 |

构建完成后，修改资源配置清单并应用：
#### 7.1.3 重新应用资源配置清单
修改dp.yaml资源配置清单

1. 将镜像改为刚刚打包的镜像名：
1. 添加环境变量`C_OPTS`,以便指定配置中心
```
vim /data/k8s-yaml/dubbo-consumer/dp.yaml
#----------原内容----------
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

#----------新内容----------
    spec:
      containers:
      - name: dubbo-demo-consumer
        image: harbor.zq.com/app/dubbo-demo-consumer:apollo_200512_0801
        ports:
        - containerPort: 8080
          protocol: TCP
        - containerPort: 20880
          protocol: TCP
        env:
        - name: JAR_BALL
          value: dubbo-client.jar
        - name: C_OPTS
          value: -Denv=dev -Dapollo.meta=http://apollo-config.zq.com
```
**应用资源配置清单：**
```
kubectl apply -f http://k8s-yaml.zq.com/dubbo-consumer/dp.yaml
```
### 7.3 验证结果
#### 7.3.1 修改dubbo-monitor资源
管理机上,修改dubbo-monitor的dp资源的使用的cm资源
```
set -i 's#dubbo-monitor-cm-pro#dubbo-monitor-cm#g' /data/k8s-yaml/dubbo-monitor/dp-cm.yaml
```
**任意node节点应用资源**
```
kubectl apply -f http://k8s-yaml.zq.com/dubbo-monitor/dp.yaml
```
**登录dubbo-monitor查看**
访问[http://dubbo-monitor.zq.com/](http://dubbo-monitor.zq.com/)
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219581671-216e68d4-f937-4d6e-b44c-89d13ae0a6a7.png)
**浏览器查看**
访问[http://dubbo-demo.zq.com/hello?name=lg](http://dubbo-demo.zq.com/hello?name=lg)
![](https://cdn.nlark.com/yuque/0/2020/png/2511954/1601219581884-7966d18a-c741-4661-aa50-09bd44f37437.png#align=left&display=inline&height=196&margin=%5Bobject%20Object%5D&originHeight=196&originWidth=578&size=0&status=done&style=none&width=578)
**apollo中看实例列表**
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219581897-d17ff60c-f74e-459a-be91-793e7cf20d2f.png)


