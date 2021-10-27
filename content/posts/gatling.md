---
title: "gatling"
subtitle: ""
date: 2019-10-27T15:58:21+08:00
lastmod: 2018-10-27T15:58:21+08:00
draft: false
author: "山脚下的脚下山"
authorLink: ""
description: ""

tags: ["test"]
categories: ["测试工具"]

hiddenFromHomePage: false
hiddenFromSearch: false

featuredImage: ""
featuredImagePreview: ""

toc:
  enable: true
math:
  enable: false
lightgallery: false
license: ""
---

# 测试工具gatling（加特林）
> 在学习Webflux响应式编程的过程中偶然听到了gatling这个负载测试工具，并且看着很简单。之前有听说过loadrunner和jmeter，并且使用过wrk这个小工具，但是没有一个详细完整的报告。因此看到这个工具的时候，就花了点时间在网上找资料学习了一下。这个文档只是为了记录我的学习过程。我是开发人员，因此不会关注太细，如有问题，请指正。

## 1、使用方式一
- 下载
[Download - Gatling Load and Performance testing](https://gatling.io/download/)
- 目录结构 
  + bin  //命令
  + conf //配置文件
  + lib  //类库
  + results //测试之后生成的报告地址
  + target 测试脚本编译目录
  + user-files //脚本目录
    - resource  脚本数据资源文件
    - simulations 脚本文件，脚本下文件目录以package方式
  
- 下载完成之后`simulations`下有样例文件`user-files/simulations/computerdatabase/BasicSimulation.scala`

- 执行样例
  - sh gatling.sh
  执行之后可以选择需要执行的脚本。最后会在results下生成测试报告

## 2、使用方式二
> 方式二使用的maven进行测试，个人觉得这种方式更适合，代码可调试。比下载工具方式更简单

1. 使用idea下载scala插件
2. 下载完成新建maven项目,如图配置
最新参见:[Maven Repository: io.gatling.highcharts » gatling-highcharts-maven-archetype](https://mvnrepository.com/artifact/io.gatling.highcharts/gatling-highcharts-maven-archetype)
```
GroupId:io.gatling.highcharts
ArtifactId:gatling-highcharts-maven.archetype
Version:3.0.2
```
![fcd8b311](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-08-04/15:45:45/fcd8b311.png)

```
├── pom.xml
├── src
│   └── test
│       ├── resources
│       │   ├── bodies
│       │   ├── data
│       │   ├── gatling.conf
│       │   ├── logback.xml
│       │   └── recorder.conf
│       └── scala
│          ├── BasicSimulation.scala  //源码文件
│          ├── Engine.scala  //执行文件
│          ├── IDEPathHelper.scala
│          └── Recorder.scala
└── target
```
3. 不使用artifact直接使用插件
如下：
```xml
<dependencies>
        <dependency>
            <groupId>io.gatling.highcharts</groupId>
            <artifactId>gatling-charts-highcharts</artifactId>
            <version>3.0.2</version>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>io.gatling</groupId>
                <artifactId>gatling-maven-plugin</artifactId>
                <version>3.0.2</version>
                <configuration>
                    <simulationsFolder>src/main/java</simulationsFolder>
                    <simulationClass>com.scemsjyd.BaseSimulation</simulationClass>
                </configuration>
                <executions>
                    <execution>
                        <phase>test</phase>
                        <goals>
                            <goal>execute</goal>
                        </goals>

                        <configuration>
                            <jvmArgs>
                                <jvmArg>-Dgatling.http.ahc.connectTimeout=6000000</jvmArg>
                                <jvmArg>-Dgatling.http.ahc.requestTimeout=6000000</jvmArg>
                                <jvmArg>-Dgatling.http.ahc.sslSessionTimeout=6000000</jvmArg>
                                <jvmArg>-Dgatling.http.ahc.pooledConnectionIdleTimeout=6000000</jvmArg>
                                <jvmArg>-Dgatling.http.ahc.readTimeout=6000000</jvmArg>
                            </jvmArgs>
                        </configuration>
                    </execution>
                </executions>
            </plugin>
        </plugins>
    </build>
```