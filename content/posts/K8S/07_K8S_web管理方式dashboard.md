---
weight: 7
title: "07_K8S_web管理方式dashboard"
subtitle: ""
date: 2020-10-01T15:58:21+08:00
lastmod: 2020-10-01T15:58:21+08:00
draft: false
author: "老男孩"
authorLink: "https://space.bilibili.com/394449264"
description: "转载，原为老男孩教育视频内容"

tags: ["K8S", "转载"]
categories: ["转载", "K8S"]

featuredImage: "https://cdn.upyun.scemsjyd.com/PicGo/2022/03/ui-dashboard.png"
featuredImagePreview: ""
lightgallery: true
---
# 07_K8S_web管理方式dashboard
dashboard是k8s的可视化管理平台，是三种管理k8s集群方法之一
## 1 部署dashboard
### 1.1 获取dashboard镜像
获取镜像和创建资源配置清单的操作,还是老规矩:`7.200`上操作
#### 1.1.1 获取1.8.3版本的dsashboard
```
docker pull k8scn/kubernetes-dashboard-amd64:v1.8.3
docker tag  k8scn/kubernetes-dashboard-amd64:v1.8.3 harbor.zq.com/public/dashboard:v1.8.3
docker push harbor.zq.com/public/dashboard:v1.8.3
```
#### 1.1.2 获取1.10.1版本的dashboard
```
docker pull loveone/kubernetes-dashboard-amd64:v1.10.1
docker tag  loveone/kubernetes-dashboard-amd64:v1.10.1 harbor.zq.com/public/dashboard:v1.10.1
docker push harbor.zq.com/public/dashboard:v1.10.1
```
#### 1.1.3 为何要两个版本的dashbosrd

- 1.8.3版本授权不严格,方便学习使用
- 1.10.1版本授权严格,学习使用麻烦,但生产需要
### 1.2 创建dashboard资源配置清单
```
mkdir -p /data/k8s-yaml/dashboard
```
#### 1.2.1 创建rbca授权清单
```
cat >/data/k8s-yaml/dashboard/rbac.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    k8s-app: kubernetes-dashboard
    addonmanager.kubernetes.io/mode: Reconcile
  name: kubernetes-dashboard-admin
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubernetes-dashboard-admin
  namespace: kube-system
  labels:
    k8s-app: kubernetes-dashboard
    addonmanager.kubernetes.io/mode: Reconcile
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: kubernetes-dashboard-admin
  namespace: kube-system
EOF
```
#### 1.2.2 创建depoloy清单
```
cat >/data/k8s-yaml/dashboard/dp.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kubernetes-dashboard
  namespace: kube-system
  labels:
    k8s-app: kubernetes-dashboard
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
spec:
  selector:
    matchLabels:
      k8s-app: kubernetes-dashboard
  template:
    metadata:
      labels:
        k8s-app: kubernetes-dashboard
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ''
    spec:
      priorityClassName: system-cluster-critical
      containers:
      - name: kubernetes-dashboard
        image: harbor.zq.com/public/dashboard:v1.8.3
        resources:
          limits:
            cpu: 100m
            memory: 300Mi
          requests:
            cpu: 50m
            memory: 100Mi
        ports:
        - containerPort: 8443
          protocol: TCP
        args:
          # PLATFORM-SPECIFIC ARGS HERE
          - --auto-generate-certificates
        volumeMounts:
        - name: tmp-volume
          mountPath: /tmp
        livenessProbe:
          httpGet:
            scheme: HTTPS
            path: /
            port: 8443
          initialDelaySeconds: 30
          timeoutSeconds: 30
      volumes:
      - name: tmp-volume
        emptyDir: {}
      serviceAccountName: kubernetes-dashboard-admin
      tolerations:
      - key: "CriticalAddonsOnly"
        operator: "Exists"
EOF
```
#### 1.2.3 创建service清单
```
cat >/data/k8s-yaml/dashboard/svc.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: kubernetes-dashboard
  namespace: kube-system
  labels:
    k8s-app: kubernetes-dashboard
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
spec:
  selector:
    k8s-app: kubernetes-dashboard
  ports:
  - port: 443
    targetPort: 8443
EOF
```
#### 1.2.4 创建ingress清单暴露服务
```
cat >/data/k8s-yaml/dashboard/ingress.yaml <<EOF
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: kubernetes-dashboard
  namespace: kube-system
  annotations:
    kubernetes.io/ingress.class: traefik
spec:
  rules:
  - host: dashboard.zq.com
    http:
      paths:
      - backend:
          serviceName: kubernetes-dashboard
          servicePort: 443
EOF
```
### 1.3 创建相关资源
#### 1.3.1 在任意node上创建
```
kubectl create -f http://k8s-yaml.zq.com/dashboard/rbac.yaml
kubectl create -f http://k8s-yaml.zq.com/dashboard/dp.yaml
kubectl create -f http://k8s-yaml.zq.com/dashboard/svc.yaml
kubectl create -f http://k8s-yaml.zq.com/dashboard/ingress.yaml
```
#### 1.3.2 添加域名解析
```
vi /var/named/zq.com.zone
dashboard          A    10.4.7.10
# 注意前滚serial编号
systemctl restart named
```
#### 1.3.3 通过浏览器验证
在本机浏览器上访问`[http://dashboard.zq.com](http://dashboard.zq.com)`,如果出来web界面,表示部署成功
可以看到安装1.8版本的dashboard，默认是可以跳过验证的：
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601204047384-94dc3835-a308-4cea-85a2-b5ceff9a42c9.png)

## 2 升级dashboard版本
跳过登录是不科学的，因为我们在配置dashboard的rbac权限时，绑定的角色是system:admin，这个是集群管理员的角色，权限很大，如果任何人都可跳过登录直接使用,那你就等着背锅吧
### 2.1 把版本换成1.10以上版本
在前面我们已经同时下载了1.10.1版本的docker镜像
#### 2.1.1 在线修改直接使用
```
kubectl edit deploy kubernetes-dashboard -n kube-system
```
#### 2.2.2 等待滚动发布
```
[root@hdss7-21 ~]# kubectl -n kube-system get pod|grep dashboard
kubernetes-dashboard-5bccc5946b-vgk5n   1/1     Running       0          20s
kubernetes-dashboard-b75bfb487-h7zft    0/1     Terminating   0          2m27s
[root@hdss7-21 ~]# kubectl -n kube-system get pod|grep dashboard
kubernetes-dashboard-5bccc5946b-vgk5n   1/1     Running   0          52s
```
#### 2.2.3 刷新dashboard页面：
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601204047500-c1ac6c4c-07b5-4209-a821-9a217a7ffa63.png)
可以看到这里原来的skip跳过已经没有了，我们如果想登陆，必须输入token，那我们如何获取token呢：

### 2.2 使用token登录
#### 2.2.1 首先获取`secret`资源列表
```
kubectl get secret  -n kube-system
```
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601204047326-4c00405b-d778-4d37-b19e-7d1c5e2d8aa5.png)
#### 2.2.2 获取角色的详情
列表中有很多角色,不同到角色有不同的权限,找到想要的角色`dashboard-admin`后,再用describe命令获取详情
```
kubectl -n kube-system describe secrets kubernetes-dashboard-admin-token-85gmd
```
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601204047339-9035a2fe-7c4b-4f65-9399-707aecde4b33.png)

找到详情中的token字段,就是我们需要用来登录的东西
拿到token去尝试登录,发现仍然登录不了,因为必须使用https登录,所以需要申请证书

#### 2.2.3 申请证书
申请证书在`7.200`主机上
**创建json文件:**
```
cd /opt/certs/
cat >/opt/certs/dashboard-csr.json <<EOF
{
    "CN": "*.zq.com",
    "hosts": [
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "ST": "beijing",
            "L": "beijing",
            "O": "zq",
            "OU": "ops"
        }
    ]
}
EOF
```
**申请证书**
```
cfssl gencert -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -profile=server \
      dashboard-csr.json |cfssl-json -bare dashboard
```
**查看申请的证书**
```
[root@hdss7-200 certs]# ll |grep dash
-rw-r--r-- 1 root root  993 May  4 12:08 dashboard.csr
-rw-r--r-- 1 root root  280 May  4 12:08 dashboard-csr.json
-rw------- 1 root root 1675 May  4 12:08 dashboard-key.pem
-rw-r--r-- 1 root root 1359 May  4 12:08 dashboard.pem
```
#### 2.2.4 前端nginx服务部署证书
在`7.11`,`7.12`两个前端代理上,都做相同操作
**拷贝证书:**
```
mkdir /etc/nginx/certs
scp 10.4.7.200:/opt/certs/dashboard.pem /etc/nginx/certs
scp 10.4.7.200:/opt/certs/dashboard-key.pem /etc/nginx/certs
```
**创建nginx配置**
```
cat >/etc/nginx/conf.d/dashboard.zq.com.conf <<'EOF'
server {
    listen       80;
    server_name  dashboard.zq.com;
    rewrite ^(.*)$ https://${server_name}$1 permanent;
}
server {
    listen       443 ssl;
    server_name  dashboard.zq.com;
    ssl_certificate     "certs/dashboard.pem";
    ssl_certificate_key "certs/dashboard-key.pem";
    ssl_session_cache shared:SSL:1m;
    ssl_session_timeout  10m;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    location / {
        proxy_pass http://default_backend_traefik;
        proxy_set_header Host       $http_host;
        proxy_set_header x-forwarded-for $proxy_add_x_forwarded_for;
    }
}
EOF
```
**重启nginx服务**
```
nginx -t
nginx -s reload
```
#### 2.2.5 再次登录dashboard
刷新页面后,再次使用前面的token登录,可以成功登录进去了
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601204047482-1b9839d4-faa7-47a7-956c-c7f335eca9d0.png)

### 2.3 授权细则思考
登录是登录了，但是我们要思考一个问题，我们使用rbac授权来访问dashboard,如何做到权限精细化呢？比如开发，只能看，不能摸，不同的项目组，看到的资源应该是不一样的，测试看到的应该是测试相关的资源


