# 13_K8S_配置中心实战-多环境交付apollo三组件


# 13_K8S_配置中心实战-多环境交付apollo三组件
## 1.环境准备工作
先删除infra名称空间中部署的apollo服务
```
kubectl delete -f http://k8s-yaml.zq.com/apollo-configservice/dp.yaml
kubectl delete -f http://k8s-yaml.zq.com/apollo-adminservice/dp.yaml
kubectl delete -f http://k8s-yaml.zq.com/apollo-portal/dp.yaml
```
要进行分环境，需要将现有实验环境进行拆分

1. portal服务，可以各个环境共用，只部署一套
1. adminservice和configservice必须要分开每个环境一套
1. zk和namespace也要区分环境
### 1.1 zk环境拆分
zk拆分最简单,只需要在dns那里修改解析规则即可：
同时添加好apollo、dubbo两个环境的域名解析
```
vi /var/named/zq.com.zone
zk-test				A    10.4.7.11
zk-prod				A    10.4.7.12
apollo-testconfig	A    10.4.7.10
apollo-prodconfig	A    10.4.7.10
dubbo-testdemo		A    10.4.7.10
dubbo-proddemo		A    10.4.7.10
# 重启服务
systemctl restart named.service
```
### 1.2 namespace分环境
**分别创建test 和prod两个名称空间**
```
kubectl create ns test
kubectl create ns prod
```
**给新名称空间创建secret授权**
```
kubectl create secret docker-registry harbor \
    --docker-server=harbor.zq.com \
    --docker-username=harbor \
    --docker-password=Harbor12345 \
    -n test
kubectl create secret docker-registry harbor \
    --docker-server=harbor.zq.com \
    --docker-username=harbor \
    --docker-password=Harbor12345 \
    -n prod
```
### 1.3 数据库拆分
因实验资源有限，故使用分库的形式模拟分环境
#### 1.3.1 修改初始化脚本并导入
数据库再`7.11`上哦
分别创建ApolloConfigTestDB和ApolloConfigProdDB
```
# 复制为新sql
cp apolloconfig.sql apolloconfigTest.sql
cp apolloconfig.sql apolloconfigProd.sql
# 替换关键字
sed -i 's#ApolloConfigDB#ApolloConfigTestDB#g' apolloconfigTest.sql
sed -i 's#ApolloConfigDB#ApolloConfigProdDB#g' apolloconfigProd.sql
# 导入数据库
mysql -uroot -p123456 < apolloconfigTest.sql
mysql -uroot -p123456 < apolloconfigProd.sql
```
#### 1.3.2 修改数据库中eureka地址
这里用到了两个新的域名，域名解析已经在添加zk域名那里一起加了
```
mysql -uroot -p123456
# 1.修改eureka注册中心配置
> update ApolloConfigProdDB.ServerConfig set ServerConfig.Value="http://apollo-prodconfig.zq.com/eureka" where ServerConfig.Key="eureka.service.url";
> update ApolloConfigTestDB.ServerConfig set ServerConfig.Value="http://apollo-testconfig.zq.com/eureka" where ServerConfig.Key="eureka.service.url";
# 2.在portl库中增加支持fat环境和pro环境
> update ApolloPortalDB.ServerConfig set Value='fat,pro' where Id=1;
# 3.授权数据库访问用户
> grant INSERT,DELETE,UPDATE,SELECT on ApolloConfigProdDB.* to "apollo"@"10.4.7.%";
> grant INSERT,DELETE,UPDATE,SELECT on ApolloConfigTestDB.* to "apollo"@"10.4.7.%";
```
### 1.4 变动原有资源配置启动
#### 1.4.1 修改portal的cm资源配置清单
`7.200`运维机操作,增加两个新环境的支持
```
cd /data/k8s-yaml/apollo-portal/
sed -i '$a\    fat.meta=http://apollo-testconfig.zq.com' cm.yaml
sed -i '$a\    pro.meta=http://apollo-prodconfig.zq.com' cm.yaml
# 查看结果
apollo-portal]# tail -4 cm.yaml
  apollo-env.properties: |
    dev.meta=http://apollo-config.zq.com
    fat.meta=http://apollo-testconfig.zq.com
    pro.meta=http://apollo-prodconfig.zq.com
```
#### 1.4.2 任意节点应用修改
```
kubectl apply -f http://k8s-yaml.zq.com/apollo-portal/cm.yaml
```
## 2 部署新环境的APOLLO服务
`7.200`运维机操作,
### 2.1 先创建出所需目录和文件
```
cd /data/k8s-yaml
mkdir -p test/{apollo-adminservice,apollo-configservice,dubbo-demo-server,dubbo-demo-consumer}
mkdir -p prod/{apollo-adminservice,apollo-configservice,dubbo-demo-server,dubbo-demo-consumer}
# 查看结果
k8s-yaml]# ll {test,prod}
prod:
total 0
drwxr-xr-x 2 root root 6 May 13 22:50 apollo-adminservice
drwxr-xr-x 2 root root 6 May 13 22:50 apollo-configservice
drwxr-xr-x 2 root root 6 May 13 22:50 dubbo-demo-consumer
drwxr-xr-x 2 root root 6 May 13 22:50 dubbo-demo-server
test:
total 0
drwxr-xr-x 2 root root 6 May 13 22:50 apollo-adminservice
drwxr-xr-x 2 root root 6 May 13 22:50 apollo-configservice
drwxr-xr-x 2 root root 6 May 13 22:50 dubbo-demo-consumer
drwxr-xr-x 2 root root 6 May 13 22:50 dubbo-demo-server
```
将之前的资源配置清单cp到对应环境的目录中，便于修改：
```
cp /data/k8s-yaml/apollo-configservice/* ./test/apollo-configservice/
cp /data/k8s-yaml/apollo-configservice/* ./prod/apollo-configservice/
cp /data/k8s-yaml/apollo-adminservice/* ./test/apollo-adminservice/
cp /data/k8s-yaml/apollo-adminservice/* ./prod/apollo-adminservice/
```
### 2.2 部署test环境的configservice
#### 2.2.1 修改configmap资源清单
要修改ns，数据库库名，eureka地址
```
cd /data/k8s-yaml/test/apollo-configservice/
sed -ri 's#(namespace:) infra#\1 test#g' cm.yaml
sed -i 's#ApolloConfigDB#ApolloConfigTestDB#g' cm.yaml
sed -i 's#apollo-config.zq.com#apollo-testconfig.zq.com#g' cm.yaml
```
#### 2.2.2 修改dp,ns,inress资源清单
```
# 1.dp只需要修改namesapce空间
sed -ri 's#(namespace:) infra#\1 test#g' dp.yaml
# 2.svc同样只需要修改namespace
sed -ri 's#(namespace:) infra#\1 test#g' svc.yaml
# 3.ingress需要修改namespace和域名
sed -ri 's#(namespace:) infra#\1 test#g' ingress.yaml
sed -i 's#apollo-config.zq.com#apollo-testconfig.zq.com#g' ingress.yaml
```
#### 2.2.3 应用资源配置
任意节点应用配置
```
kubectl apply -f http://k8s-yaml.zq.com/test/apollo-configservice/cm.yaml
kubectl apply -f http://k8s-yaml.zq.com/test/apollo-configservice/dp.yaml
kubectl apply -f http://k8s-yaml.zq.com/test/apollo-configservice/svc.yaml
kubectl apply -f http://k8s-yaml.zq.com/test/apollo-configservice/ingress.yaml
```
浏览器检查
浏览器输入[http://apollo-testconfig.zq.com,](http://apollo-testconfig.zq.com,)查看测试环境的apollo注册中心是否已有服务注册![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219746078-0b118a7a-ef5b-4ced-914e-3237314335df.png)
服务已经注册进来了

### 2.3 部署test环境的adminservice
#### 2.3.1 修改configmap资源清单
要修改ns，数据库库名，eureka地址
```
cd /data/k8s-yaml/test/apollo-adminservice/
sed -ri 's#(namespace:) infra#\1 test#g' cm.yaml
sed -i 's#ApolloConfigDB#ApolloConfigTestDB#g' cm.yaml
sed -i 's#apollo-config.zq.com#apollo-testconfig.zq.com#g' cm.yaml
```
#### 2.3.2 修改dp资源清单
```
# 1.dp只需要修改namesapce空间
sed -ri 's#(namespace:) infra#\1 test#g' dp.yaml
```
#### 2.3.3 应用资源配置清单
```
kubectl apply -f http://k8s-yaml.zq.com/test/apollo-adminservice/cm.yaml
kubectl apply -f http://k8s-yaml.zq.com/test/apollo-adminservice/dp.yaml
```
**浏览器检查:**
浏览器输入[http://apollo-testconfig.zq.com,](http://apollo-testconfig.zq.com,)查看测试环境的apollo注册中心是否已有adminservice服务注册
### 2.4 部署prod环境的configservice
套路基本上都是一样使用的
#### 2.4.1 修改configmap资源清单
要修改ns，数据库库名，eureka地址
```
cd /data/k8s-yaml/prod/apollo-configservice/
sed -ri 's#(namespace:) infra#\1 prod#g' cm.yaml
sed -i 's#ApolloConfigDB#ApolloConfigProdDB#g' cm.yaml
sed -i 's#apollo-config.zq.com#apollo-prodconfig.zq.com#g' cm.yaml
```
#### 2.4.2 修改dp,ns,inress资源清单
```
# 1.dp只需要修改namesapce空间
sed -ri 's#(namespace:) infra#\1 prod#g' dp.yaml
# 2.svc同样只需要修改namespace
sed -ri 's#(namespace:) infra#\1 prod#g' svc.yaml
# 3.ingress需要修改namespace和域名
sed -ri 's#(namespace:) infra#\1 prod#g' ingress.yaml
sed -i 's#apollo-config.zq.com#apollo-prodconfig.zq.com#g' ingress.yaml
```
#### 2.4.3 应用资源配置
任意节点应用配置
```
kubectl apply -f http://k8s-yaml.zq.com/prod/apollo-configservice/cm.yaml
kubectl apply -f http://k8s-yaml.zq.com/prod/apollo-configservice/dp.yaml
kubectl apply -f http://k8s-yaml.zq.com/prod/apollo-configservice/svc.yaml
kubectl apply -f http://k8s-yaml.zq.com/prod/apollo-configservice/ingress.yaml
```
浏览器检查
浏览器输入[http://apollo-prodconfig.zq.com,](http://apollo-prodconfig.zq.com,)查看测试环境的apollo注册中心是否已有服务注册![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219746078-5fe92a5d-c490-427f-801b-c3729589869a.png)
服务已经注册进来了

### 2.5 部署prod环境的adminservice
#### 2.5.1 修改configmap资源清单
要修改ns，数据库库名，eureka地址
```
cd /data/k8s-yaml/prod/apollo-adminservice/
sed -ri 's#(namespace:) infra#\1 prod#g' cm.yaml
sed -i 's#ApolloConfigDB#ApolloConfigProdDB#g' cm.yaml
sed -i 's#apollo-config.zq.com#apollo-prodconfig.zq.com#g' cm.yaml
```
#### 2.5.2 修改dp资源清单
```
# 1.dp只需要修改namesapce空间
sed -ri 's#(namespace:) infra#\1 prod#g' dp.yaml
```
#### 2.5.3 应用资源配置清单
```
kubectl apply -f http://k8s-yaml.zq.com/prod/apollo-adminservice/cm.yaml
kubectl apply -f http://k8s-yaml.zq.com/prod/apollo-adminservice/dp.yaml
```
**浏览器检查:**
浏览器输入[http://apollo-prodconfig.zq.com,](http://apollo-prodconfig.zq.com,)查看测试环境的apollo注册中心是否已有adminservice服务注册
### 2.6 启动portal服务
两个服务都已经注册进来了后，删除portal数据库中存储的关于之前项目的配置，再来启动portal项目
#### 2.6.1 清理数据库
```
mysql -uroot -p123456
> use ApolloPortalDB;
> truncate table App;
> truncate table AppNamespace;
```
![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219746288-1e756c40-c524-415a-abe2-51ca82250027.png)
#### 2.6.2 启动portal
```
kubectl apply -f http://k8s-yaml.zq.com/apollo-portal/cm.yaml
kubectl apply -f http://k8s-yaml.zq.com/apollo-portal/dp.yaml
kubectl apply -f http://k8s-yaml.zq.com/apollo-portal/svc.yaml
kubectl apply -f http://k8s-yaml.zq.com/apollo-portal/ingress.yaml
```
#### 2.6.3 验证部署结果
打开[http://apollo-portal.zq.com,](http://apollo-portal.zq.com,)创建两个项目如下:

| AppId | 应用名称 | 部门 |
| --- | --- | --- |
| dubbo-demo-service | dubbo服务提供者 | 研发部 |
| dubbo-demo-web | dubbo服务消费者 | 运维部 |

项目创建成功后,能看到左侧环境列表中有`FAT`和`PRO`,表示正确
#### 2.6.4 添加test环境的配置
**dubbo-demo-service**

| key | value | 备注 |
| --- | --- | --- |
| dubbo.registry | zookeeper://zk-test.zq.com:2181 | 注册中心地址 |
| dubbo.port | 20880 | dubbo服务监听端口 |

**dubbo-demo-web**

| key | value | 备注 |
| --- | --- | --- |
| dubbo.registry | zookeeper://zk-test.zq.com:2181 | 注册中心地址 |

#### 2.6.5 添加prod环境的配置
**dubbo-demo-service**

| key | value | 备注 |
| --- | --- | --- |
| dubbo.registry | zookeeper://zk-prod.zq.com:2181 | 注册中心地址 |
| dubbo.port | 20880 | dubbo服务监听端口 |

**dubbo-demo-web**

| key | value | 备注 |
| --- | --- | --- |
| dubbo.registry | zookeeper://zk-prod.zq.com:2181 | 注册中心地址 |

## 3 分环境交付dubbo服务
### 3.1 交付test环境dubbo服务
```
cd /data/k8s-yaml/
cp ./dubbo-server/*   ./test/dubbo-demo-server/
cp ./dubbo-consumer/* ./test/dubbo-demo-consumer/
```
#### 3.1.1 修改server资源配置清单
只修改dp的ns配置和apollo配置
```
cd /data/k8s-yaml/test/dubbo-demo-server
sed -ri 's#(namespace:) app#\1 test#g' dp.yaml
sed -i 's#Denv=dev#Denv=fat#g' dp.yaml
sed -i 's#apollo-config.zq.com#apollo-testconfig.zq.com#g' dp.yaml
```
任意node应用资源清单：
```
kubectl apply -f http://k8s-yaml.zq.com/test/dubbo-demo-server/dp.yaml
```
#### 3.1.2 修改consumer资源配置清单
修改资源清单
```
cd /data/k8s-yaml/test/dubbo-demo-consumer
# 1.修改dp中的ns配置和apollo配置
sed -ri 's#(namespace:) app#\1 test#g' dp.yaml
sed -i 's#Denv=dev#Denv=fat#g' dp.yaml
sed -i 's#apollo-config.zq.com#apollo-testconfig.zq.com#g' dp.yaml
# 2.修改svc中的ns配置
sed -ri 's#(namespace:) app#\1 test#g' svc.yaml
# 3.修改ingress中的ns配置和域名
sed -ri 's#(namespace:) app#\1 test#g' ingress.yaml
sed -i 's#dubbo-demo.zq.com#dubbo-testdemo.zq.com#g' ingress.yaml
```
添加域名解析
> 由于最开始已经统一做了域名解析,这里就不单独添加了
> 如果没有添加域名解析的话,需要去添加`dubbo-testdemo.zq.com`的解析

任意node应用资源清单：
```
kubectl apply -f http://k8s-yaml.zq.com/test/dubbo-demo-consumer/dp.yaml
kubectl apply -f http://k8s-yaml.zq.com/test/dubbo-demo-consumer/svc.yaml
kubectl apply -f http://k8s-yaml.zq.com/test/dubbo-demo-consumer/ingress.yaml
```
### 3.2 交付prod环境dubbo服务
```
cd /data/k8s-yaml/
cp ./dubbo-server/*   ./prod/dubbo-demo-server/
cp ./dubbo-consumer/* ./prod/dubbo-demo-consumer/
```
#### 3.2.1 修改server资源配置清单
只修改dp的ns配置和apollo配置
```
cd /data/k8s-yaml/prod/dubbo-demo-server
sed -ri 's#(namespace:) app#\1 prod#g' dp.yaml
sed -i 's#Denv=dev#Denv=pro#g' dp.yaml
sed -i 's#apollo-config.zq.com#apollo-prodconfig.zq.com#g' dp.yaml
```
任意node应用资源清单：
```
kubectl apply -f http://k8s-yaml.zq.com/prod/dubbo-demo-server/dp.yaml
```
#### 3.2.2 修改consumer资源配置清单
修改资源清单
```
cd /data/k8s-yaml/prod/dubbo-demo-consumer
# 1.修改dp中的ns配置和apollo配置
sed -ri 's#(namespace:) app#\1 prod#g' dp.yaml
sed -i 's#Denv=dev#Denv=pro#g' dp.yaml
sed -i 's#apollo-config.zq.com#apollo-prodconfig.zq.com#g' dp.yaml
# 2.修改svc中的ns配置
sed -ri 's#(namespace:) app#\1 prod#g' svc.yaml
# 3.修改ingress中的ns配置和域名
sed -ri 's#(namespace:) app#\1 prod#g' ingress.yaml
sed -i 's#dubbo-demo.zq.com#dubbo-proddemo.zq.com#g' ingress.yaml
```
添加域名解析
> 由于最开始已经统一做了域名解析,这里就不单独添加了
> 如果没有添加域名解析的话,需要去添加`dubbo-proddemo.zq.com`的解析

任意node应用资源清单：
```
kubectl apply -f http://k8s-yaml.zq.com/prod/dubbo-demo-consumer/dp.yaml
kubectl apply -f http://k8s-yaml.zq.com/prod/dubbo-demo-consumer/svc.yaml
kubectl apply -f http://k8s-yaml.zq.com/prod/dubbo-demo-consumer/ingress.yaml
```
### 3.3 关于dp中的apollo域名

1. dp.yaml中配置的`-Dapollo.meta=http://apollo-testconfig.zq.com`
1. 其实可以直接使用`-Dapollo.meta=http://apollo-configservice:8080`
1. 也直接使用svc资源名称调用,这样还可以少走一次外网解析,相当于走内网
1. 因为不同环境的apollo名称空间都不一样,而svc只在当前namespace中生效

![](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/1601219746017-446de116-e33c-48a6-8c10-785b2e3dc6ab.png)**
## 4 验证并模拟发布
### 4.1 验证访问两个环境
分别访问以下域名,看是否可以出来网页内容
test：[http://dubbo-testdemo.zq.com/hello?name=noah](http://dubbo-testdemo.zq.com/hello?name=noah)
prod：[http://dubbo-proddemo.zq.com/hello?name=noah](http://dubbo-proddemo.zq.com/hello?name=noah)
### 4.2 模拟发版：
任意修改码云上的dubbo-demo-web项目的say方法返回内容
路径`dubbo-client/src/main/java/com/od/dubbotest/action/HelloAction.java`
#### 4.2.1 用jenkins构建新镜像
参数如下：

| 参数名 | 参数值 |
| --- | --- |
| app_name | dubbo-demo-consumer |
| image_name | app/dubbo-demo-consumer |
| git_repo | git@gitee.com:noah-luo/dubbo-demo-web.git |
| git_ver | apollo |
| add_tag | 200513_1808 |
| mvn_dir | ./ |
| target_dir | ./dubbo-client/target |
| mvn_cmd | mvn clean package -Dmaven.test.skip=true |
| base_image | base/jre8:8u112 |
| maven | 3.6.1 |

#### 4.2.2 发布test环境
构建成功，然后我们在测试环境发布此版本镜像
修改测试环境的dp.yaml
```
cd /data/k8s-yaml/test/dubbo-demo-consumer
sed -ri 's#(dubbo-demo-consumer:apollo).*#\1_200513_1808#g' dp.yaml
```
应用修改后的资源配置清单：
```
kubectl apply -f http://k8s-yaml.zq.com/test/dubbo-demo-consumer/dp.yaml
```
访问[http://dubbo-testdemo.zq.com/hello?name=noah](http://dubbo-testdemo.zq.com/hello?name=noah)看是否有我们更改的内容
#### 4.2.3 发布prod环境
镜像在测试环境测试没有问题后,直接使用该镜像发布生产环境,不在重新打包,避免发生错误
同样修改prod环境的dp.yaml,并且应用该资源配置清单
```
cd /data/k8s-yaml/prod/dubbo-demo-server
sed -ri 's#(dubbo-demo-consumer:apollo).*#\1_200513_1808#g' dp.yaml
```
应用修改后的资源配置清单：
```
kubectl apply -f http://k8s-yaml.zq.com/test/dubbo-demo-consumer/dp.yaml
```
已经上线到生产环境，这样一套完整的分环境使用apollo配置中心发布流程已经可以使用了，并且真正做到了一次构建，多平台使用


