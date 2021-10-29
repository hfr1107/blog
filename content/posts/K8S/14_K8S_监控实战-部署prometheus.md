---
weight: 14
title: "14_K8S_监控实战-部署prometheus"
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
# 14_K8S_监控实战-部署prometheus
## 1 prometheus前言相关
由于docker容器的特殊性，传统的zabbix无法对k8s集群内的docker状态进行监控，所以需要使用prometheus来进行监控
prometheus官网：[官网地址](https://prometheus.io/)
### 1.1 Prometheus的特点

- 多维度数据模型,使用时间序列数据库TSDB而不使用mysql。
- 灵活的查询语言PromQL。
- 不依赖分布式存储，单个服务器节点是自主的。
- 主要基于HTTP的pull方式主动采集时序数据
- 也可通过pushgateway获取主动推送到网关的数据。
- 通过服务发现或者静态配置来发现目标服务对象。
- 支持多种多样的图表和界面展示，比如Grafana等。
### 1.2 基本原理
#### 1.2.1 原理说明
Prometheus的基本原理是通过各种exporter提供的HTTP协议接口
周期性抓取被监控组件的状态，任意组件只要提供对应的HTTP接口就可以接入监控。
不需要任何SDK或者其他的集成过程,非常适合做虚拟化环境监控系统，比如VM、Docker、Kubernetes等。
互联网公司常用的组件大部分都有exporter可以直接使用，如Nginx、MySQL、Linux系统信息等。
#### 1.2.2 架构图:
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219938866-fc30fe28-f729-49eb-a4b9-8cfeaa83ecb5.png)
#### 1.2.3 三大套件

- Server 主要负责数据采集和存储，提供PromQL查询语言的支持。
- Alertmanager 警告管理器，用来进行报警。
- Push Gateway 支持临时性Job主动推送指标的中间网关。
#### 1.2.4 架构服务过程

1. Prometheus Daemon负责定时去目标上抓取metrics(指标)数据
每个抓取目标需要暴露一个http服务的接口给它定时抓取。
支持通过配置文件、文本文件、Zookeeper、DNS SRV Lookup等方式指定抓取目标。
1. PushGateway用于Client主动推送metrics到PushGateway
而Prometheus只是定时去Gateway上抓取数据。
适合一次性、短生命周期的服务
1. Prometheus在TSDB数据库存储抓取的所有数据
通过一定规则进行清理和整理数据，并把得到的结果存储到新的时间序列中。
1. Prometheus通过PromQL和其他API可视化地展示收集的数据。
支持Grafana、Promdash等方式的图表数据可视化。
Prometheus还提供HTTP API的查询方式，自定义所需要的输出。
1. Alertmanager是独立于Prometheus的一个报警组件
支持Prometheus的查询语句，提供十分灵活的报警方式。
#### 1.2.5 常用的exporter
prometheus不同于zabbix，没有agent，使用的是针对不同服务的exporter
正常情况下，监控k8s集群及node，pod，常用的exporter有四个：

- kube-state-metrics
收集k8s集群master&etcd等基本状态信息
- node-exporter
收集k8s集群node信息
- cadvisor
收集k8s集群docker容器内部使用资源信息
- blackbox-exporte
收集k8s集群docker容器服务是否存活
## 2 部署4个exporter
老套路，下载docker镜像，准备资源配置清单，应用资源配置清单：
### 2.1 部署kube-state-metrics
#### 2.1.1 准备docker镜像
```
docker pull quay.io/coreos/kube-state-metrics:v1.5.0
docker tag  91599517197a harbor.zq.com/public/kube-state-metrics:v1.5.0
docker push harbor.zq.com/public/kube-state-metrics:v1.5.0
```
准备目录
```
mkdir /data/k8s-yaml/kube-state-metrics
cd /data/k8s-yaml/kube-state-metrics
```
#### 2.1.2 准备rbac资源清单
```
cat >rbac.yaml <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
    kubernetes.io/cluster-service: "true"
  name: kube-state-metrics
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
    kubernetes.io/cluster-service: "true"
  name: kube-state-metrics
rules:
- apiGroups:
  - ""
  resources:
  - configmaps
  - secrets
  - nodes
  - pods
  - services
  - resourcequotas
  - replicationcontrollers
  - limitranges
  - persistentvolumeclaims
  - persistentvolumes
  - namespaces
  - endpoints
  verbs:
  - list
  - watch
- apiGroups:
  - policy
  resources:
  - poddisruptionbudgets
  verbs:
  - list
  - watch
- apiGroups:
  - extensions
  resources:
  - daemonsets
  - deployments
  - replicasets
  verbs:
  - list
  - watch
- apiGroups:
  - apps
  resources:
  - statefulsets
  verbs:
  - list
  - watch
- apiGroups:
  - batch
  resources:
  - cronjobs
  - jobs
  verbs:
  - list
  - watch
- apiGroups:
  - autoscaling
  resources:
  - horizontalpodautoscalers
  verbs:
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
    kubernetes.io/cluster-service: "true"
  name: kube-state-metrics
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kube-state-metrics
subjects:
- kind: ServiceAccount
  name: kube-state-metrics
  namespace: kube-system
EOF
```
#### 2.1.3 准备Dp资源清单
```
cat >dp.yaml <<'EOF'
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  annotations:
    deployment.kubernetes.io/revision: "2"
  labels:
    grafanak8sapp: "true"
    app: kube-state-metrics
  name: kube-state-metrics
  namespace: kube-system
spec:
  selector:
    matchLabels:
      grafanak8sapp: "true"
      app: kube-state-metrics
  strategy:
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
    type: RollingUpdate
  template:
    metadata:
      labels:
        grafanak8sapp: "true"
        app: kube-state-metrics
    spec:
      containers:
      - name: kube-state-metrics
        image: harbor.zq.com/public/kube-state-metrics:v1.5.0
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8080
          name: http-metrics
          protocol: TCP
        readinessProbe:
          failureThreshold: 3
          httpGet:
            path: /healthz
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 5
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 5
      serviceAccountName: kube-state-metrics
EOF
```
#### 2.1.4 应用资源配置清单
任意node节点执行
```
kubectl apply -f http://k8s-yaml.zq.com/kube-state-metrics/rbac.yaml
kubectl apply -f http://k8s-yaml.zq.com/kube-state-metrics/dp.yaml
```
**验证测试**
```
kubectl get pod -n kube-system -o wide|grep kube-state-metrices
~]# curl http://172.7.21.4:8080/healthz
ok
```
返回OK表示已经成功运行。
### 2.2 部署node-exporter
**由于node-exporter是监控node的，需要每个节点启动一个，所以使用ds控制器**
#### 2.2.1 准备docker镜像
```
docker pull prom/node-exporter:v0.15.0
docker tag 12d51ffa2b22 harbor.zq.com/public/node-exporter:v0.15.0
docker push harbor.zq.com/public/node-exporter:v0.15.0
```
准备目录
```
mkdir /data/k8s-yaml/node-exporter
cd /data/k8s-yaml/node-exporter
```
#### 2.2.2 准备ds资源清单
```
cat >ds.yaml <<'EOF'
kind: DaemonSet
apiVersion: extensions/v1beta1
metadata:
  name: node-exporter
  namespace: kube-system
  labels:
    daemon: "node-exporter"
    grafanak8sapp: "true"
spec:
  selector:
    matchLabels:
      daemon: "node-exporter"
      grafanak8sapp: "true"
  template:
    metadata:
      name: node-exporter
      labels:
        daemon: "node-exporter"
        grafanak8sapp: "true"
    spec:
      volumes:
      - name: proc
        hostPath:
          path: /proc
          type: ""
      - name: sys
        hostPath:
          path: /sys
          type: ""
      containers:
      - name: node-exporter
        image: harbor.zq.com/public/node-exporter:v0.15.0
        imagePullPolicy: IfNotPresent
        args:
        - --path.procfs=/host_proc
        - --path.sysfs=/host_sys
        ports:
        - name: node-exporter
          hostPort: 9100
          containerPort: 9100
          protocol: TCP
        volumeMounts:
        - name: sys
          readOnly: true
          mountPath: /host_sys
        - name: proc
          readOnly: true
          mountPath: /host_proc
      hostNetwork: true
EOF
```
> 主要用途就是将宿主机的`/proc`,`sys`目录挂载给容器,是容器能获取node节点宿主机信息

#### 2.2.3 应用资源配置清单：
任意node节点
```
kubectl apply -f http://k8s-yaml.zq.com/node-exporter/ds.yaml
kubectl get pod -n kube-system -o wide|grep node-exporter
```
### 2.3 部署cadvisor
#### 2.3.1 准备docker镜像
```
docker pull google/cadvisor:v0.28.3
docker tag 75f88e3ec333 harbor.zq.com/public/cadvisor:0.28.3
docker push harbor.zq.com/public/cadvisor:0.28.3
```
准备目录
```
mkdir /data/k8s-yaml/cadvisor
cd /data/k8s-yaml/cadvisor
```
#### 2.3.2 准备ds资源清单
cadvisor由于要获取每个node上的pod信息,因此也需要使用daemonset方式运行
```
cat >ds.yaml <<'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: cadvisor
  namespace: kube-system
  labels:
    app: cadvisor
spec:
  selector:
    matchLabels:
      name: cadvisor
  template:
    metadata:
      labels:
        name: cadvisor
    spec:
      hostNetwork: true
#------pod的tolerations与node的Taints配合,做POD指定调度----
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
#-------------------------------------
      containers:
      - name: cadvisor
        image: harbor.zq.com/public/cadvisor:v0.28.3
        imagePullPolicy: IfNotPresent
        volumeMounts:
        - name: rootfs
          mountPath: /rootfs
          readOnly: true
        - name: var-run
          mountPath: /var/run
        - name: sys
          mountPath: /sys
          readOnly: true
        - name: docker
          mountPath: /var/lib/docker
          readOnly: true
        ports:
          - name: http
            containerPort: 4194
            protocol: TCP
        readinessProbe:
          tcpSocket:
            port: 4194
          initialDelaySeconds: 5
          periodSeconds: 10
        args:
          - --housekeeping_interval=10s
          - --port=4194
      terminationGracePeriodSeconds: 30
      volumes:
      - name: rootfs
        hostPath:
          path: /
      - name: var-run
        hostPath:
          path: /var/run
      - name: sys
        hostPath:
          path: /sys
      - name: docker
        hostPath:
          path: /data/docker
EOF
```
#### 2.3.3 应用资源配置清单：
应用清单前,先在每个node上做以下软连接,否则服务可能报错
```
mount -o remount,rw /sys/fs/cgroup/
ln -s /sys/fs/cgroup/cpu,cpuacct /sys/fs/cgroup/cpuacct,cpu
```
应用清单
```
kubectl apply -f http://k8s-yaml.zq.com/cadvisor/ds.yaml
```
检查：
```
kubectl -n kube-system get pod -o wide|grep cadvisor
```
### 2.4 部署blackbox-exporter
#### 2.4.1 准备docker镜像
```
docker pull prom/blackbox-exporter:v0.15.1
docker tag  81b70b6158be  harbor.zq.com/public/blackbox-exporter:v0.15.1
docker push harbor.zq.com/public/blackbox-exporter:v0.15.1
```
准备目录
```
mkdir /data/k8s-yaml/blackbox-exporter
cd /data/k8s-yaml/blackbox-exporter
```
#### 2.4.2 准备cm资源清单
```
cat >cm.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  labels:
    app: blackbox-exporter
  name: blackbox-exporter
  namespace: kube-system
data:
  blackbox.yml: |-
    modules:
      http_2xx:
        prober: http
        timeout: 2s
        http:
          valid_http_versions: ["HTTP/1.1", "HTTP/2"]
          valid_status_codes: [200,301,302]
          method: GET
          preferred_ip_protocol: "ip4"
      tcp_connect:
        prober: tcp
        timeout: 2s
EOF
```
#### 2.4.3 准备dp资源清单
```
cat >dp.yaml <<'EOF'
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: blackbox-exporter
  namespace: kube-system
  labels:
    app: blackbox-exporter
  annotations:
    deployment.kubernetes.io/revision: 1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: blackbox-exporter
  template:
    metadata:
      labels:
        app: blackbox-exporter
    spec:
      volumes:
      - name: config
        configMap:
          name: blackbox-exporter
          defaultMode: 420
      containers:
      - name: blackbox-exporter
        image: harbor.zq.com/public/blackbox-exporter:v0.15.1
        imagePullPolicy: IfNotPresent
        args:
        - --config.file=/etc/blackbox_exporter/blackbox.yml
        - --log.level=info
        - --web.listen-address=:9115
        ports:
        - name: blackbox-port
          containerPort: 9115
          protocol: TCP
        resources:
          limits:
            cpu: 200m
            memory: 256Mi
          requests:
            cpu: 100m
            memory: 50Mi
        volumeMounts:
        - name: config
          mountPath: /etc/blackbox_exporter
        readinessProbe:
          tcpSocket:
            port: 9115
          initialDelaySeconds: 5
          timeoutSeconds: 5
          periodSeconds: 10
          successThreshold: 1
          failureThreshold: 3
EOF
```
#### 2.4.4 准备svc资源清单
```
cat >svc.yaml <<'EOF'
kind: Service
apiVersion: v1
metadata:
  name: blackbox-exporter
  namespace: kube-system
spec:
  selector:
    app: blackbox-exporter
  ports:
    - name: blackbox-port
      protocol: TCP
      port: 9115
EOF
```
#### 2.4.5 准备ingress资源清单
```
cat >ingress.yaml <<'EOF'
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: blackbox-exporter
  namespace: kube-system
spec:
  rules:
  - host: blackbox.zq.com
    http:
      paths:
      - path: /
        backend:
          serviceName: blackbox-exporter
          servicePort: blackbox-port
EOF
```
#### 2.4.6 添加域名解析
这里用到了一个域名，添加解析
```
vi /var/named/zq.com.zone
blackbox       A    10.4.7.10
systemctl restart named
```
#### 2.4.7 应用资源配置清单
```
kubectl apply -f http://k8s-yaml.zq.com/blackbox-exporter/cm.yaml
kubectl apply -f http://k8s-yaml.zq.com/blackbox-exporter/dp.yaml
kubectl apply -f http://k8s-yaml.zq.com/blackbox-exporter/svc.yaml
kubectl apply -f http://k8s-yaml.zq.com/blackbox-exporter/ingress.yaml
```
#### 2.4.8 访问域名测试
访问[http://blackbox.zq.com](http://blackbox.zq.com)，显示如下界面,表示blackbox已经运行成
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219938890-ac98286e-bfe4-40be-91ad-b1d024a5b92b.png)

## 3 部署prometheus server
### 3.1 准备prometheus server环境
#### 3.1.1 准备docker镜像
```
docker pull prom/prometheus:v2.14.0
docker tag  7317640d555e harbor.zq.com/infra/prometheus:v2.14.0
docker push harbor.zq.com/infra/prometheus:v2.14.0
```
准备目录
```
mkdir /data/k8s-yaml/prometheus-server
cd /data/k8s-yaml/prometheus-server
```
#### 3.1.2 准备rbac资源清单
```
cat >rbac.yaml <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
    kubernetes.io/cluster-service: "true"
  name: prometheus
  namespace: infra
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
    kubernetes.io/cluster-service: "true"
  name: prometheus
rules:
- apiGroups:
  - ""
  resources:
  - nodes
  - nodes/metrics
  - services
  - endpoints
  - pods
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - configmaps
  verbs:
  - get
- nonResourceURLs:
  - /metrics
  verbs:
  - get
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
    kubernetes.io/cluster-service: "true"
  name: prometheus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus
subjects:
- kind: ServiceAccount
  name: prometheus
  namespace: infra
EOF
```
#### 3.1.3 准备dp资源清单
> 加上`--web.enable-lifecycle`启用远程热加载配置文件,配置文件改变后不用重启prometheus
> 调用指令是`curl -X POST http://localhost:9090/-/reload`
> `storage.tsdb.min-block-duration=10m`只加载10分钟数据到内
> `storage.tsdb.retention=72h` 保留72小时数据

```
cat >dp.yaml <<'EOF'
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  annotations:
    deployment.kubernetes.io/revision: "5"
  labels:
    name: prometheus
  name: prometheus
  namespace: infra
spec:
  progressDeadlineSeconds: 600
  replicas: 1
  revisionHistoryLimit: 7
  selector:
    matchLabels:
      app: prometheus
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
      - name: prometheus
        image: harbor.zq.com/infra/prometheus:v2.14.0
        imagePullPolicy: IfNotPresent
        command:
        - /bin/prometheus
        args:
        - --config.file=/data/etc/prometheus.yml
        - --storage.tsdb.path=/data/prom-db
        - --storage.tsdb.min-block-duration=10m
        - --storage.tsdb.retention=72h
        - --web.enable-lifecycle
        ports:
        - containerPort: 9090
          protocol: TCP
        volumeMounts:
        - mountPath: /data
          name: data
        resources:
          requests:
            cpu: "1000m"
            memory: "1.5Gi"
          limits:
            cpu: "2000m"
            memory: "3Gi"
      imagePullSecrets:
      - name: harbor
      securityContext:
        runAsUser: 0
      serviceAccountName: prometheus
      volumes:
      - name: data
        nfs:
          server: hdss7-200
          path: /data/nfs-volume/prometheus
EOF
```
#### 3.1.4 准备svc资源清单
```
cat >svc.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: infra
spec:
  ports:
  - port: 9090
    protocol: TCP
    targetPort: 9090
  selector:
    app: prometheus
EOF
```
#### 3.1.5 准备ingress资源清单
```
cat >ingress.yaml <<'EOF'
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: traefik
  name: prometheus
  namespace: infra
spec:
  rules:
  - host: prometheus.zq.com
    http:
      paths:
      - path: /
        backend:
          serviceName: prometheus
          servicePort: 9090
EOF
```
#### 3.1.6 添加域名解析
这里用到一个域名`prometheus.zq.com`，添加解析：
```
vi /var/named/od.com.zone
prometheus         A    10.4.7.10
systemctl restart named
```
### 3.2 部署prometheus server
#### 3.2.1 准备目录和证书
```
mkdir -p /data/nfs-volume/prometheus/etc
mkdir -p /data/nfs-volume/prometheus/prom-db
cd /data/nfs-volume/prometheus/etc/
# 拷贝配置文件中用到的证书：
cp /opt/certs/ca.pem ./
cp /opt/certs/client.pem ./
cp /opt/certs/client-key.pem ./
```
#### 3.2.2 创建prometheus配置文件
> **配置文件说明:**
> 此配置为通用配置,除第一个job`etcd`是做的静态配置外,其他8个job都是做的自动发现
> 因此只需要修改`etcd`的配置后,就可以直接用于生产环境

```
cat >/data/nfs-volume/prometheus/etc/prometheus.yml <<'EOF'
global:
  scrape_interval:     15s
  evaluation_interval: 15s
scrape_configs:
- job_name: 'etcd'
  tls_config:
    ca_file: /data/etc/ca.pem
    cert_file: /data/etc/client.pem
    key_file: /data/etc/client-key.pem
  scheme: https
  static_configs:
  - targets:
    - '10.4.7.12:2379'
    - '10.4.7.21:2379'
    - '10.4.7.22:2379'

- job_name: 'kubernetes-apiservers'
  kubernetes_sd_configs:
  - role: endpoints
  scheme: https
  tls_config:
    ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
  bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
  relabel_configs:
  - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
    action: keep
    regex: default;kubernetes;https

- job_name: 'kubernetes-pods'
  kubernetes_sd_configs:
  - role: pod
  relabel_configs:
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
    action: keep
    regex: true
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
    action: replace
    target_label: __metrics_path__
    regex: (.+)
  - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
    action: replace
    regex: ([^:]+)(?::\d+)?;(\d+)
    replacement: $1:$2
    target_label: __address__
  - action: labelmap
    regex: __meta_kubernetes_pod_label_(.+)
  - source_labels: [__meta_kubernetes_namespace]
    action: replace
    target_label: kubernetes_namespace
  - source_labels: [__meta_kubernetes_pod_name]
    action: replace
    target_label: kubernetes_pod_name

- job_name: 'kubernetes-kubelet'
  kubernetes_sd_configs:
  - role: node
  relabel_configs:
  - action: labelmap
    regex: __meta_kubernetes_node_label_(.+)
  - source_labels: [__meta_kubernetes_node_name]
    regex: (.+)
    target_label: __address__
    replacement: ${1}:10255

- job_name: 'kubernetes-cadvisor'
  kubernetes_sd_configs:
  - role: node
  relabel_configs:
  - action: labelmap
    regex: __meta_kubernetes_node_label_(.+)
  - source_labels: [__meta_kubernetes_node_name]
    regex: (.+)
    target_label: __address__
    replacement: ${1}:4194

- job_name: 'kubernetes-kube-state'
  kubernetes_sd_configs:
  - role: pod
  relabel_configs:
  - action: labelmap
    regex: __meta_kubernetes_pod_label_(.+)
  - source_labels: [__meta_kubernetes_namespace]
    action: replace
    target_label: kubernetes_namespace
  - source_labels: [__meta_kubernetes_pod_name]
    action: replace
    target_label: kubernetes_pod_name
  - source_labels: [__meta_kubernetes_pod_label_grafanak8sapp]
    regex: .*true.*
    action: keep
  - source_labels: ['__meta_kubernetes_pod_label_daemon', '__meta_kubernetes_pod_node_name']
    regex: 'node-exporter;(.*)'
    action: replace
    target_label: nodename

- job_name: 'blackbox_http_pod_probe'
  metrics_path: /probe
  kubernetes_sd_configs:
  - role: pod
  params:
    module: [http_2xx]
  relabel_configs:
  - source_labels: [__meta_kubernetes_pod_annotation_blackbox_scheme]
    action: keep
    regex: http
  - source_labels: [__address__, __meta_kubernetes_pod_annotation_blackbox_port,  __meta_kubernetes_pod_annotation_blackbox_path]
    action: replace
    regex: ([^:]+)(?::\d+)?;(\d+);(.+)
    replacement: $1:$2$3
    target_label: __param_target
  - action: replace
    target_label: __address__
    replacement: blackbox-exporter.kube-system:9115
  - source_labels: [__param_target]
    target_label: instance
  - action: labelmap
    regex: __meta_kubernetes_pod_label_(.+)
  - source_labels: [__meta_kubernetes_namespace]
    action: replace
    target_label: kubernetes_namespace
  - source_labels: [__meta_kubernetes_pod_name]
    action: replace
    target_label: kubernetes_pod_name

- job_name: 'blackbox_tcp_pod_probe'
  metrics_path: /probe
  kubernetes_sd_configs:
  - role: pod
  params:
    module: [tcp_connect]
  relabel_configs:
  - source_labels: [__meta_kubernetes_pod_annotation_blackbox_scheme]
    action: keep
    regex: tcp
  - source_labels: [__address__, __meta_kubernetes_pod_annotation_blackbox_port]
    action: replace
    regex: ([^:]+)(?::\d+)?;(\d+)
    replacement: $1:$2
    target_label: __param_target
  - action: replace
    target_label: __address__
    replacement: blackbox-exporter.kube-system:9115
  - source_labels: [__param_target]
    target_label: instance
  - action: labelmap
    regex: __meta_kubernetes_pod_label_(.+)
  - source_labels: [__meta_kubernetes_namespace]
    action: replace
    target_label: kubernetes_namespace
  - source_labels: [__meta_kubernetes_pod_name]
    action: replace
    target_label: kubernetes_pod_name

- job_name: 'traefik'
  kubernetes_sd_configs:
  - role: pod
  relabel_configs:
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scheme]
    action: keep
    regex: traefik
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
    action: replace
    target_label: __metrics_path__
    regex: (.+)
  - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
    action: replace
    regex: ([^:]+)(?::\d+)?;(\d+)
    replacement: $1:$2
    target_label: __address__
  - action: labelmap
    regex: __meta_kubernetes_pod_label_(.+)
  - source_labels: [__meta_kubernetes_namespace]
    action: replace
    target_label: kubernetes_namespace
  - source_labels: [__meta_kubernetes_pod_name]
    action: replace
    target_label: kubernetes_pod_name
EOF
```
#### 3.2.3 应用资源配置清单
```
kubectl apply -f http://k8s-yaml.zq.com/prometheus-server/rbac.yaml
kubectl apply -f http://k8s-yaml.zq.com/prometheus-server/dp.yaml
kubectl apply -f http://k8s-yaml.zq.com/prometheus-server/svc.yaml
kubectl apply -f http://k8s-yaml.zq.com/prometheus-server/ingress.yaml
```
#### 3.2.4 浏览器验证
访问[http://prometheus.zq.com,](http://prometheus.zq.com,)如果能成功访问的话,表示启动成功
点击**status->configuration**就是我们的配置文件
![](https://cdn.nlark.com/yuque/0/2020/png/2511954/1601219938865-a380d765-1bde-4948-9878-46528803c465.png#align=left&display=inline&height=333&margin=%5Bobject%20Object%5D&originHeight=333&originWidth=496&size=0&status=done&style=none&width=496)
## 4 使服务能被prometheus自动监控
点击**status->targets**，展示的就是我们在prometheus.yml中配置的job-name，这些targets基本可以满足我们收集数据的需求。
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219938915-db8767e1-361c-415d-bb55-b6f7bf37db50.png)

> 5个编号的job-name已经被发现并获取数据
> 接下来就需要将剩下的4个ob-name对应的服务纳入监控
> 纳入监控的方式是给需要收集数据的服务添加annotations

### 4.1 让traefik能被自动监控
#### 4.1.1 修改traefik的yaml
修改fraefik的yaml文件,跟labels同级,添加annotations配置
```
vim /data/k8s-yaml/traefik/ds.yaml
........
spec:
  template:
    metadata:
      labels:
        k8s-app: traefik-ingress
        name: traefik-ingress
#--------增加内容--------
      annotations:
        prometheus_io_scheme: "traefik"
        prometheus_io_path: "/metrics"
        prometheus_io_port: "8080"
#--------增加结束--------
    spec:
      serviceAccountName: traefik-ingress-controller
........
```
任意节点重新应用配置
```
kubectl delete -f http://k8s-yaml.zq.com/traefik/ds.yaml
kubectl apply  -f http://k8s-yaml.zq.com/traefik/ds.yaml
```
#### 4.1.2 应用配置查看
等待pod重启以后，再在prometheus上查看traefik是否能正常获取数据了
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219938921-6fc54a66-c82d-4886-bcba-839ad5a311b2.png)

### 4.2 用blackbox检测TCP/HTTP服务状态
blackbox是检测容器内服务存活性的，也就是端口健康状态检查，分为tcp和http两种方法
能用http的情况尽量用http,没有提供http接口的服务才用tcp
#### 4.2.1 被检测服务准备
使用测试环境的dubbo服务来做演示,其他环境类似

1. dashboard中开启apollo-portal和test空间中的apollo
1. dubbo-demo-service使用tcp的annotation
1. dubbo-demo-consumer使用HTTP的annotation
#### 4.2.2 添加tcp的annotation
等两个服务起来以后，首先在dubbo-demo-service资源中添加一个TCP的annotation
```
vim /data/k8s-yaml/test/dubbo-demo-server/dp.yaml
......
spec:
......
  template:
    metadata:
      labels:
        app: dubbo-demo-service
        name: dubbo-demo-service
#--------增加内容--------
      annotations:
        blackbox_port: "20880"
        blackbox_scheme: "tcp"
#--------增加结束--------
    spec:
      containers:
        image: harbor.zq.com/app/dubbo-demo-service:apollo_200512_0746
```
任意节点重新应用配置
```
kubectl delete -f http://k8s-yaml.zq.com/test/dubbo-demo-server/dp.yaml
kubectl apply  -f http://k8s-yaml.zq.com/test/dubbo-demo-server/dp.yaml
```
浏览器中查看[http://blackbox.zq.com/](http://blackbox.zq.com/)和[http://prometheus.zq.com/targets](http://prometheus.zq.com/targets)
我们运行的dubbo-demo-server服务,tcp端口20880已经被发现并在监控中
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219938915-2fc3c386-8185-4e5a-9692-86524c14201e.png)

#### 4.2.3 添加http的annotation
接下来在dubbo-demo-consumer资源中添加一个HTTP的annotation：
```
vim /data/k8s-yaml/test/dubbo-demo-consumer/dp.yaml
spec:
......
  template:
    metadata:
      labels:
        app: dubbo-demo-consumer
        name: dubbo-demo-consumer
#--------增加内容--------
      annotations:
        blackbox_path: "/hello?name=health"
        blackbox_port: "8080"
        blackbox_scheme: "http"
#--------增加结束--------
    spec:
      containers:
      - name: dubbo-demo-consumer
......
```
任意节点重新应用配置
```
kubectl delete -f http://k8s-yaml.zq.com/test/dubbo-demo-consumer/dp.yaml
kubectl apply  -f http://k8s-yaml.zq.com/test/dubbo-demo-consumer/dp.yaml
```
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219938954-b889a59e-91de-4c2b-85b7-36f390c529ad.png)
### 4.3 添加监控jvm信息
dubbo-demo-service和dubbo-demo-consumer都添加下列annotation注解,以便监控pod中的jvm信息
```
vim /data/k8s-yaml/test/dubbo-demo-server/dp.yaml
vim /data/k8s-yaml/test/dubbo-demo-consumer/dp.yaml
      annotations:
        #....已有略....
        prometheus_io_scrape: "true"
        prometheus_io_port: "12346"
        prometheus_io_path: "/"
```
> 12346是dubbo的POD启动命令中使用jmx_javaagent用到的端口,因此可以用来收集jvm信息

任意节点重新应用配置
```
kubectl apply  -f http://k8s-yaml.zq.com/test/dubbo-demo-server/dp.yaml
kubectl apply  -f http://k8s-yaml.zq.com/test/dubbo-demo-consumer/dp.yaml
```
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219938896-309a3f84-71c6-4d02-8245-4d782ee272af.png)

**至此,所有9个服务,都获取了数据**


