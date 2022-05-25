---
weight: 6
title: "06_K8S_核心插件-ingress(服务暴露)控制器traefik"
subtitle: ""
date: 2020-10-01T15:58:21+08:00
lastmod: 2020-10-01T15:58:21+08:00
draft: false
author: "老男孩"
authorLink: "https://space.bilibili.com/394449264"
description: "转载，原为老男孩教育视频内容"

tags: ["K8S", "转载"]
categories: ["转载", "K8S"]

featuredImage: "https://cdn.yopngs.com/2022/05/25/8807396f-1d6d-47e0-ae0e-c8127d1d7be9.jpg"
featuredImagePreview: ""
lightgallery: true
---

# 06_K8S_核心插件-ingress(服务暴露)控制器traefik
## 1 K8S两种服务暴露方法
前面通过coredns在k8s集群内部做了serviceNAME和serviceIP之间的自动映射,使得不需要记录service的IP地址,只需要通过serviceNAME就能访问POD
但是在K8S集群外部,显然是不能通过serviceNAME或serviceIP来解析服务的
要在K8S集群外部来访问集群内部的资源,需要用到服务暴露功能
### 1.1 K8S常用的两种服务暴露方法

1. 使用NodePort型的Service
nodeport型的service原理相当于端口映射，将容器内的端口映射到宿主机上的某个端口。
K8S集群不能使用ipvs的方式调度,必须使用iptables,且只支持rr模式
1. 使用Ingress资源
Ingress是K8S API标准资源之一,也是核心资源
是一组基于域名和URL路径的规则,把用户的请求转发至指定的service资源
可以将集群外部的请求流量,转发至集群内部,从而实现'**服务暴露**'
### 1.2 Ingress控制器是什么
可以理解为一个简化版本的nginx
Ingress控制器是能够为Ingress资源健康某套接字,然后根据ingress规则匹配机制路由调度流量的一个组件
只能工作在七层网络下，建议暴露http, https可以使用前端nginx来做证书方面的卸载
我们使用的ingress控制器为**`Traefik`**
traefik：[GITHUB官方地址](https://github.com/containous/traefik)
## 2 部署traefik
同样的,现在`7.200`完成docker镜像拉取和配置清单创建,然后再到任意master节点执行配置清单
### 2.1 准备docker镜像
```
docker pull traefik:v1.7.2-alpine
docker tag  traefik:v1.7.2-alpine harbor.zq.com/public/traefik:v1.7.2
docker push harbor.zq.com/public/traefik:v1.7.2
```
### 2.2 创建资源清单
```
mkdir -p /data/k8s-yaml/traefik
```
#### 2.2.1 rbac授权清单
```
cat >/data/k8s-yaml/traefik/rbac.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: traefik-ingress-controller
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  name: traefik-ingress-controller
rules:
  - apiGroups:
      - ""
    resources:
      - services
      - endpoints
      - secrets
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - extensions
    resources:
      - ingresses
    verbs:
      - get
      - list
      - watch
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: traefik-ingress-controller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: traefik-ingress-controller
subjects:
- kind: ServiceAccount
  name: traefik-ingress-controller
  namespace: kube-system
EOF
```
#### 2.2.2 delepoly资源清单
```
cat >/data/k8s-yaml/traefik/ds.yaml <<EOF
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: traefik-ingress
  namespace: kube-system
  labels:
    k8s-app: traefik-ingress
spec:
  template:
    metadata:
      labels:
        k8s-app: traefik-ingress
        name: traefik-ingress
    spec:
      serviceAccountName: traefik-ingress-controller
      terminationGracePeriodSeconds: 60
      containers:
      - image: harbor.zq.com/public/traefik:v1.7.2
        name: traefik-ingress
        ports:
        - name: controller
          containerPort: 80
          hostPort: 81
        - name: admin-web
          containerPort: 8080
        securityContext:
          capabilities:
            drop:
            - ALL
            add:
            - NET_BIND_SERVICE
        args:
        - --api
        - --kubernetes
        - --logLevel=INFO
        - --insecureskipverify=true
        - --kubernetes.endpoint=https://10.4.7.10:7443
        - --accesslog
        - --accesslog.filepath=/var/log/traefik_access.log
        - --traefiklog
        - --traefiklog.filepath=/var/log/traefik.log
        - --metrics.prometheus
EOF
```
#### 2.2.3 service清单
```
cat >/data/k8s-yaml/traefik/svc.yaml <<EOF
kind: Service
apiVersion: v1
metadata:
  name: traefik-ingress-service
  namespace: kube-system
spec:
  selector:
    k8s-app: traefik-ingress
  ports:
    - protocol: TCP
      port: 80
      name: controller
    - protocol: TCP
      port: 8080
      name: admin-web
EOF
```
#### 2.2.4 ingress清单
```
cat >/data/k8s-yaml/traefik/ingress.yaml <<EOF
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: traefik-web-ui
  namespace: kube-system
  annotations:
    kubernetes.io/ingress.class: traefik
spec:
  rules:
  - host: traefik.zq.com
    http:
      paths:
      - path: /
        backend:
          serviceName: traefik-ingress-service
          servicePort: 8080
EOF
```
### 2.3 创建资源
#### 2.3.1 任意节点上创建资源
```
kubectl create -f http://k8s-yaml.zq.com/traefik/rbac.yaml
kubectl create -f http://k8s-yaml.zq.com/traefik/ds.yaml
kubectl create -f http://k8s-yaml.zq.com/traefik/svc.yaml
kubectl create -f http://k8s-yaml.zq.com/traefik/ingress.yaml
```
#### 2.3.2 在前端nginx上做反向代理
在`7.11`和`7.12`上,都做反向代理,将泛域名的解析都转发到`traefik`上去
```
cat >/etc/nginx/conf.d/zq.com.conf <<'EOF'
upstream default_backend_traefik {
    server 10.4.7.21:81    max_fails=3 fail_timeout=10s;
    server 10.4.7.22:81    max_fails=3 fail_timeout=10s;
}
server {
    server_name *.zq.com;

    location / {
        proxy_pass http://default_backend_traefik;
        proxy_set_header Host       $http_host;
        proxy_set_header x-forwarded-for $proxy_add_x_forwarded_for;
    }
}
EOF
# 重启nginx服务
nginx -t
nginx -s reload
```
#### 2.3.3 在bind9中添加域名解析
需要将traefik 服务的解析记录添加的DNS解析中,注意是绑定到VIP上
```
vi /var/named/zq.com.zone
........
traefik            A    10.4.7.10
```
> 注意前滚serial编号

重启named服务
```
systemctl restart named
#dig验证解析结果
[root@hdss7-11 ~]# dig -t A traefik.zq.com +short
10.4.7.10
```
#### 2.3.4 在集群外访问验证

在集群外,访问`[http://traefik.zq.com](http://traefik.zq.com)`,如果能正常显示web页面.说明我们已经暴露服务成功

