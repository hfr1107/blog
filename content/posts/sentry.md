---
title: "01_springmvc_flow"
subtitle: ""
date: 2018-11-27T15:58:21+08:00
lastmod: 2018-11-27T15:58:21+08:00
draft: false
author: "山脚下的脚下山"
authorLink: ""
description: ""

tags: ["sentry"]
categories: ["中间件"]

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

# sentry配置
> 使用sentry 进行异常报警

1. sentry安装
    sentry 目前推荐使用docker安装，docker-compose启动
    官方安装链接：`https://docs.sentry.io/server/installation`

2. 添加maven依赖
```xml
<dependency>
    <groupId>com.getsentry.raven</groupId>
    <artifactId>raven-logback</artifactId>
    <version>8.0.3</version>
</dependency>
```
3. 配置logback
```xml
<appender name="Sentry" class="com.getsentry.raven.logback.SentryAppender">
    <dsn>https://username:password@sentry.abc.com/117</dsn>
    <filter class="ch.qos.logback.classic.filter.ThresholdFilter">
        <level>ERROR</level>
    </filter>
</appender>
```