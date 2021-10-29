# 09_K8S_交付实战-交付jenkins到k8s集群

# 09_K8S_交付实战-交付jenkins到k8s集群
## 1 准备jenkins镜像
准备镜像的操作在`7.200`运维机上完成
### 1.1 下载官方镜像
```
docker pull jenkins/jenkins:2.190.3
docker tag jenkins/jenkins:2.190.3 harbor.zq.com/public/jenkins:v2.190.3
docker push harbor.zq.com/public/jenkins:v2.190.3
```
### 1.2 修改官方镜像
基于官方jenkins镜像,编写dockerfile做个性化配置
#### 1.2.1 创建目录
```
mkdir -p /data/dockerfile/jenkins/
cd /data/dockerfile/jenkins/
```
#### 1.2.2 创建dockerfile
```
cat >/data/dockerfile/jenkins/Dockerfile <<'EOF'
FROM harbor.zq.com/public/jenkins:v2.190.3
#定义启动jenkins的用户
USER root
#修改时区为东八区
RUN /bin/cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime &&\
    echo 'Asia/Shanghai' >/etc/timezone
#加载用户密钥，使用ssh拉取dubbo代码需要
ADD id_rsa /root/.ssh/id_rsa
#加载运维主机的docker配置文件，里面包含登录harbor仓库的认证信息。
ADD config.json /root/.docker/config.json
#在jenkins容器内安装docker客户端，docker引擎用的是宿主机的docker引擎
ADD get-docker.sh /get-docker.sh
# 跳过ssh时候输入yes的交互步骤，并执行安装docker
RUN echo "    StrictHostKeyChecking no" >/etc/ssh/ssh_config &&\
    /get-docker.sh
EOF
```
#### 1.2.3 准备dockerfile所需文件
**创建秘钥对:**
```
ssh-keygen -t rsa -b 2048 -C "lg@126.com" -N "" -f /root/.ssh/id_rsa
cp /root/.ssh/id_rsa /data/dockerfile/jenkins/
```
> 邮箱请根据自己的邮箱自行修改
> 创建完成后记得把公钥放到gitee的信任中

**获取docker.sh脚本:**
```
curl -fsSL get.docker.com -o /data/dockerfile/jenkins/get-docker.sh
chmod u+x /data/dockerfile/jenkins/get-docker.sh
```
**拷贝config.json文件:**
```
cp /root/.docker/config.json /data/dockerfile/jenkins/
```
#### 1.2.4 harbor中创建私有仓库infra
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601204260224-22a79075-dfc1-4cfe-b45f-e15ccfc72859.png)
#### 1.2.5 构建自定义的jenkins镜像
```
cd /data/dockerfile/jenkins/
docker build . -t harbor.zq.com/infra/jenkins:v2.190.3
docker push harbor.zq.com/infra/jenkins:v2.190.3
```
## 2 准备jenkins运行环境
### 2.1 专有名称空间和secret资源
#### 2.1.1 创建专有namespace
创建专有名词空间`infra`的目录是将jenkins等运维相关软件放到同一个namespace下,便于统一管理以及和其他资源分开
```
kubectl create ns infra
```
#### 2.1.2 创建访问harbor的secret规则
`Secret`用来保存敏感信息，例如密码、OAuth 令牌和 ssh key等,有三种类型:

1. Opaque：
base64 编码格式的 Secret，用来存储密码、密钥等,可以反解,加密能力弱
1. kubernetes.io/dockerconfigjson：
用来存储私有docker registry的认证信息。
1. kubernetes.io/service-account-token：
用于被`serviceaccount`引用，serviceaccout 创建时Kubernetes会默认创建对应的secret
前面dashborad部分以及用过了

访问docker的私有仓库,必须要创建专有的secret类型,创建方法如下:
```
kubectl create secret docker-registry harbor \
    --docker-server=harbor.zq.com \
    --docker-username=admin \
    --docker-password=Harbor12345 \
    -n infra
# 查看结果
~]# kubectl -n infra get secrets
NAME                  TYPE                                  DATA   AGE
default-token-rkg7q   kubernetes.io/service-account-token   3      19s
harbor                kubernetes.io/dockerconfigjson        1      12s
```
> 解释命令：
> 创建一条secret，资源类型是docker-registry，名字是 harbor
> 并指定docker仓库地址、访问用户、密码、仓库名

### 2.2 创建NFS共享存储
jenkins中一些数据需要持久化的，可以使用共享存储进行挂载：
这里使用最简单的NFS共享存储，因为k8s默认支持nfs模块
如果使用其他类型的共享存储
#### 2.2.1 运维机部署NFS
```
yum install nfs-utils -y
echo '/data/nfs-volume 10.4.7.0/24(rw,no_root_squash)' >>/etc/exports
mkdir -p /data/nfs-volume/jenkins_home
systemctl start nfs
systemctl enable nfs
# 查看结果
~]# showmount -e
Export list for hdss7-200:
/data/nfs-volume 10.4.7.0/24
```
#### 2.2.2 node节点安装nfs
```
yum install nfs-utils -y
```
### 2.3 运维机创建jenkins资源清单
```
mkdir /data/k8s-yaml/jenkins
```
#### 2.3.1 创建depeloy清单
有两个需要注意的地方:

1. 挂载了宿主机的docker.sock
使容器内的docker客户端可以直接与宿主机的docker引擎进行通信
1. 在使用私有仓库的时候，资源清单中，一定要声明：
```
imagePullSecrets:
- name: harbor
```
```
cat >/data/k8s-yaml/jenkins/dp.yaml <<EOF
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: jenkins
  namespace: infra
  labels:
    name: jenkins
spec:
  replicas: 1
  selector:
    matchLabels:
      name: jenkins
  template:
    metadata:
      labels:
        app: jenkins
        name: jenkins
    spec:
      volumes:
      - name: data
        nfs:
          server: hdss7-200
          path: /data/nfs-volume/jenkins_home
      - name: docker
        hostPath:
          path: /run/docker.sock
          type: ''
      containers:
      - name: jenkins
        image: harbor.zq.com/infra/jenkins:v2.190.3
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8080
          protocol: TCP
        env:
        - name: JAVA_OPTS
          value: -Xmx512m -Xms512m
        volumeMounts:
        - name: data
          mountPath: /var/jenkins_home
        - name: docker
          mountPath: /run/docker.sock
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
### 2.3.2 创建service清单
```
cat >/data/k8s-yaml/jenkins/svc.yaml <<EOF
kind: Service
apiVersion: v1
metadata:
  name: jenkins
  namespace: infra
spec:
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
  selector:
    app: jenkins
EOF
```
#### 2.3.3 创建ingress清单
```
cat >/data/k8s-yaml/jenkins/ingress.yaml <<EOF
kind: Ingress
apiVersion: extensions/v1beta1
metadata:
  name: jenkins
  namespace: infra
spec:
  rules:
  - host: jenkins.zq.com
    http:
      paths:
      - path: /
        backend:
          serviceName: jenkins
          servicePort: 80
EOF
```
## 3 交付jenkins
### 3.1 应用jenkins资源清单
#### 3.1.2 部署jenkins
任意node节点
```
kubectl create -f http://k8s-yaml.zq.com/jenkins/dp.yaml
kubectl create -f http://k8s-yaml.zq.com/jenkins/svc.yaml
kubectl create -f http://k8s-yaml.zq.com/jenkins/ingress.yaml
```
启动时间很长,等待结果
```
kubectl get pod -n infra
```
#### 3.1.2 验证jenkins容器状态
```
docker exec -it 8ff92f08e3aa /bin/bash
# 查看用户
whoami
# 查看时区
date
# 查看是否能用宿主机的docker引擎
docker ps
# 看是否能免密访问gitee
ssh -i /root/.ssh/id_rsa -T git@gitee.com
# 是否能访问是否harbor仓库
docker login harbor.zq.com
```
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601204260157-328ee975-afc6-4915-a129-7e6beae415c2.png)
#### 3.1.3 查看持久化结果和密码
到运维机上查看持久化数据是否成功存放到共享存储
```
~]# ll /data/nfs-volume/jenkins_home
total 36
-rw-r--r--  1 root root 1643 May  5 13:18 config.xml
-rw-r--r--  1 root root   50 May  5 13:13 copy_reference_file.log
-rw-r--r--  1 root root  156 May  5 13:14 hudson.model.UpdateCenter.xml
-rw-------  1 root root 1712 May  5 13:14 identity.key.enc
-rw-r--r--  1 root root    7 May  5 13:14 jenkins.install.UpgradeWizard.state
-rw-r--r--  1 root root  171 May  5 13:14 jenkins.telemetry.Correlator.xml
drwxr-xr-x  2 root root    6 May  5 13:13 jobs
drwxr-xr-x  3 root root   19 May  5 13:14 logs
-rw-r--r--  1 root root  907 May  5 13:14 nodeMonitors.xml
drwxr-xr-x  2 root root    6 May  5 13:14 nodes
drwxr-xr-x  2 root root    6 May  5 13:13 plugins
-rw-r--r--  1 root root   64 May  5 13:13 secret.key
-rw-r--r--  1 root root    0 May  5 13:13 secret.key.not-so-secret
drwx------  4 root root  265 May  5 13:14 secrets
drwxr-xr-x  2 root root   67 May  5 13:19 updates
drwxr-xr-x  2 root root   24 May  5 13:14 userContent
drwxr-xr-x  3 root root   56 May  5 13:14 users
drwxr-xr-x 11 root root 4096 May  5 13:13 war
```
找到jenkins初始化的密码
```
~]# cat /data/nfs-volume/jenkins_home/secrets/initialAdminPassword
02f69d78026d489e87b01332f1caa85a
```
#### 3.1.4 替换jenkins插件源
```
cd /data/nfs-volume/jenkins_home/updates
sed -i 's#http:\/\/updates.jenkins-ci.org\/download#https:\/\/mirrors.tuna.tsinghua.edu.cn\/jenkins#g' default.json
sed -i 's#http:\/\/www.google.com#https:\/\/www.baidu.com#g' default.json
```
### 3.2 解析jenkins
jenkins部署成功后后,需要给他添加外网的域名解析
```
vi /var/named/zq.com.zone
jenkins         A    10.4.7.10
# 重启服务
systemctl restart named
```
### 3.3 初始化jenkins
浏览器访问`[http://jenkins.zq.com](http://jenkins.zq.com)`,使用前面的密码进入jenkins
进入后操作:

1. 跳过安装自动安装插件的步骤
1. 在`manage jenkins`->`Configure Global Security`菜单中设置
2.1 允许匿名读：勾选`allow anonymous read access`
2.2 允许跨域：勾掉`prevent cross site request forgery exploits`
1. 搜索并安装蓝海插件`blue ocean`
1. 设置用户名密码为`admin:admin123`
### 3.4 给jenkins配置maven环境
因为jenkins的数据目录已经挂载到了NFS中做持久化,因此可以直接将maven放到NFS目录中,同时也就部署进了jenkins
#### 3.4.1 下载并解压
```
wget https://archive.apache.org/dist/maven/maven-3/3.6.1/binaries/apache-maven-3.6.1-bin.tar.gz
tar -zxf apache-maven-3.6.1-bin.tar.gz -C /data/nfs-volume/jenkins_home/
mv /data/nfs-volume/jenkins_home/{apache-,}maven-3.6.1
cd /data/nfs-volume/jenkins_home/maven-3.6.1
```
#### 3.4.2 初始化maven配置：
修改下载仓库地址,除了`<mirror>`中是新增的阿里云仓库地址外,其他内容都是`settings.xml`中原有的配置(只是清除了注释内容)
```
cat >conf/settings.xml  <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 http://maven.apache.org/xsd/settings-1.0.0.xsd">
  <pluginGroups>
  </pluginGroups>
  <proxies>
  </proxies>
  <servers>
  </servers>
  <mirrors>
	<mirror>
	  <id>nexus-aliyun</id>
	  <mirrorOf>*</mirrorOf>
	  <name>Nexus aliyun</name>
	  <url>http://maven.aliyun.com/nexus/content/groups/public</url>
	</mirror>
  </mirrors>
  <profiles>
  </profiles>
</settings>
EOF
```


