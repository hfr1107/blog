# 01_springmvc_flow


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
