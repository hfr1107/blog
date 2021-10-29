---
weight: 22
title: "03_springmvc_handlermapping"
subtitle: ""
date: 2016-10-29T15:58:58+08:00
lastmod: 2016-10-29T15:58:58+08:00
draft: false
author: "山脚下的脚下山"
authorLink: ""
description: ""

tags: ["springmvc"]
categories: ["spring"]

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

# HandlerMapping

> HandlerMapping接口负责根据request请求找到对应的Handler处理器及Interceptor拦截器，并将它们封装在HandlerExecutionChain对象内，返回给中央调度器。
>
> HandlerMapping接口只有一个方法：
>
> ```java
> @Nullable
> HandlerExecutionChain getHandler(HttpServletRequest request) throws Exception;
> ```

这里我们主要讲清楚两个问题：

- HandlerMapping初始化
- HandlerMapping的唯一方法`getHandler`

## HandlerMapping初始化

我们在第02_DispatcherServlet里已经看到过了Springmvc初始化handlerMapping策略的方法：`initHandlerMappings`

![image-20200705125443769](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/mlUCtRydOArjesH.png)

此处可以看到将HandlerMapping的实现类封装到了`handlerMappings`属性中。

那HandlerMapping的实现类是在什么时候实例化的，并且里面有哪些东西呢？带着这个疑问我们往下走。

这里我们以`RequestMappingHandlerMapping`为例：

![image-20200705155250466](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/2020-07-15-22:52:49-2CvB3awGXkdShxq.png)

在非SpringBoot的环境下，我们以前写spring的启动配置dispatchServlet.xml的时候总会加一行

```xml
<mvc:annotation-driven/>
```

这个配置会为我们初始化三个类

```
RequestMappingHandlerMapping
RequestMappingHandlerAdapter
ExceptionHandlerExceptionResolver
```

但是在SpringBoot环境下，配置都是自动化添加的，那我们看一下`spring-boot-autoconfigure`的`spring.factories`，再搜索一下web。我们能在其中找到下面这个配置类：

```properties
org.springframework.boot.autoconfigure.web.servlet.WebMvcAutoConfiguration
```

这个类中有一个静态类`EnableWebMvcConfiguration`的目录结构如下：

![image-20200705161212278](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/2020-07-15-22:53:11-3wK1CrQouRnxfMG.png)

在其中，我们可以看到有一个方法`createRequestMappingHandlerMapping`。

### InitializingBean接口

在上面的`RequestMappingHandlerMapping`类图中，我们看到该类实现了`InitializingBean`接口，接口方法实现如下：

![image-20200705163032594](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/2020-07-15-22:53:32-ZENcSbBQnmYK6tR.png)

方法中实例化了一个*BuilderConfiguration*对象，并为该对象设置了一些路径抓取器，路径方法匹配器等。最后还需要调用父类的方法

![image-20200705163118853](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/2020-07-15-22:53:43-GzJ5tcf2O3Ujxue.png)

该方法比较重要，看名字可以猜测是初始化HandlerMethods用的。方法实现如下：

![image-20200705163614219](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/2020-07-15-22:53:48-qTzPjWcpwZdnKhX.png)

第一步是遍历AplicationContext中的所有Bean，只要不是以SCOPED_TARGET_NAME_PREFIX（private static final String SCOPED_TARGET_NAME_PREFIX = "scopedTarget.";）开头就调用`processCandidatebean`方法，方法如下：

![image-20200705164023406](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/2020-07-15-22:53:56-c9tITeFulxfq1Oj.png)

拿到Bean的类型，调用`isHandler(beanType)`方法，该方法如下：

![image-20200705164259297](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/2020-07-15-22:54:05-DFgn7bRI1Hk9Ja8.png)

看到两个非常熟悉的注解`@Controller`和`@RequestMapping`。

如果该Bean标注了以上两个注解，那么调用`detectHandlerMethos(beanName)`，方法如下：

![image-20200705164827326](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/2020-07-15-22:54:08-TFCSraUhEfpeIz4.png)

看方法描述可知，该方法在指定的bean中寻找handler methods。

我们先来看看该类中第一个重要的方法`getMappingForMethod(method, userType)`，方法如下：

![image-20200705165129247](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/2020-07-15-22:54:22-5MQPE1N38yRxgDL.png)

通过方法或者通过类级别标注的RequestMapping注解创建`RequestMappingInfo`，

![image-20200705165914427](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/2020-07-15-22:54:33-tOZzFYm47xTJdoV.png)

![image-20200705165951303](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/2020-07-15-22:54:39-1EXKZyv8CLSMOxl.png)

这里可以看出RequestMappingInfo主要存放的就是RequestMapping注解标注的方法的相关信息请求信息。到这里RequestMappingInfo已经构造完成。然后我们回到之前的方法，在遍历完标注了@Controller或者@RequestMapping的类的方法并且生成了对应的RequestMappingInfo之后调用`registerHandlerMethod`

![image-20200705171114940](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/2020-07-15-22:54:44-fdCJnhjR1N2lU67.png)

至此，Controller中的HandlerMethods方法遍历查找并且注册到了RequestMapptinHandlerMapping中的mappingRegistry属性中。第一步结束。

我们再回到初始化之前，看 `initHandlerMethods` 接下来又做了什么?

翻看第6张图，得到接下来调用 `handlerMethodsInitialized` 方法：

![image-20200705172911972](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/2020-07-15-22:54:56-VqQhbi6Mg4SeNLH.png)

从该方法看到handlerMethods初始化结束之后并没有做其他特别的事，但是有一行注释，我们发现。handlerMethods包括了两部分：springmvc自动监测到的和用户显示通过`registerMapping（）`方法添加的。

到这里为止，`InitializingBean`方法执行结束。

### ApplicationContextAware接口

回到之前看的类结构图，得知该还继承了`ApplicationObjectSupport`类，而该类又实现了`ApplicationContextAware`接口。那我们再来看看该接口方法做了什么。

![image-20200705182213910](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/2020-07-15-22:55:01-tzvaSKgCTeoGPU4.png)

从该方法得知：该类对子类暴露了一个方法`initApplicationContext`，我们从`RequestMappingHandlerMapping`的父类`AbstractHandlerMapping`中看到以下实现：

![image-20200705182451569](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/2020-07-15-22:55:09-RHqcBpJN2u5aKwI.png)

我们看到这里内部执行了三个方法，

- extendInterceptors(this.interceptors) 该方法体内部为空，给子类使用

- detectMappedInterceptors(this.adaptedInterceptors) 从所有Bean对象中找出MappedInterceptor类的的Bean，添加到this.this.adaptedInterceptors中。

- initInterceptors() 将默认interceptors拦截器放入this.adaptedInterceptors中，

  - 比如SpringBoot配置类`EnableWebMvcConfiguration`默认添加了两个拦截器`ConversionServiceExposingInterceptor` `ResourceUrlProviderExposingInterceptor`

  ```java
  @Bean
  @Primary
  @Override
  public RequestMappingHandlerMapping requestMappingHandlerMapping(
    @Qualifier("mvcContentNegotiationManager") ContentNegotiationManager contentNegotiationManager,
    @Qualifier("mvcConversionService") FormattingConversionService conversionService,
    @Qualifier("mvcResourceUrlProvider") ResourceUrlProvider resourceUrlProvider) {
    // Must be @Primary for MvcUriComponentsBuilder to work
    return super.requestMappingHandlerMapping(contentNegotiationManager, conversionService,
                                              resourceUrlProvider);
  }
  ```

### HandlerInterceptor

>HandlerInterceptor接口主要有三个方法，三个方法会在dispatcherServlet执行过程中调用

- preHandle：执行HandlerAdaptor的handle方法前。

```java
default boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler)
			throws Exception {

return true;
}
```

- preHandle：执行HandlerAdaptor的handle方法后。

```java
default void postHandle(HttpServletRequest request, HttpServletResponse response, Object handler,
@Nullable ModelAndView modelAndView) throws Exception {
}
```

- afterCompletion：doDispatch方法执行完成前，即使抛出异常也会执行。

```java
default void afterCompletion(HttpServletRequest request, HttpServletResponse response, Object handler,
                             @Nullable Exception ex) throws Exception {
}
```



至此，`ApplicationContextAware`接口方法initApplicationContext执行结束





## getHandler方法

> HandlerExecutionChain getHandler(HttpServletRequest request)

![image-20200705174135770](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/2020-07-15-22:57:54-CvhNFjZwpLABr8u.png)

我们来看第一个方法`getHandlerInternal(request)`

![image-20200705174449675](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/2020-07-15-22:57:59-CtJicMm3sWUbuvg.png)

通过UrlPathHelper从request获取请求的path，然后根据path调用`lookupHandlerMethod()`方法获取处理这个request的HandlerMethod。

`lookupHandlerMethod`方法作用：查找当前请求的最佳匹配处理程序方法，如果找到多个匹配项，则选择最佳匹配项。这个方法的作用也比较明确，就不多说了。

回到之前，找到HandlerMethod，如果没有找到，返回默认的Handler。接下来是最核心的方法`getHandlerExecutionChain(handler, request)`

![image-20200705180210185](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/2020-07-15-22:58:14-6rjf7LT3KNReGI2.png)

从此方法可以看出通过HandlerMethod new了一个HandlerExecutionChain对象。然后将属性`adaptedInterceptors`中的`HandlerInterceptor`添加到HandlerExecutionChain中，形成了调用执行链。

其中一个包括`includePatterns`和`excludePatterns`字符串集合并带有`MappedInterceptor`的类。 很明显，就是对于某些地址做特殊包括和排除的拦截器。

![image-20200705185612898](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/2020-07-15-22:58:33-mu1H5LvcBkjoJxr.png)

接下来，判断请求或者Handler是否是CROS请求，如果是，则添加

```java
chain.addInterceptor(0, new CorsInterceptor(config));
```

到此，getHandler执行结束。



## 使用

### 基础用法

- 实现HandlerInterceptor接口

```java
package com.example.springmvcexample.handlerMapping;

import lombok.extern.slf4j.Slf4j;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.ModelAndView;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

@Slf4j
public class LogHandlerInterceptor implements HandlerInterceptor {
    public LogHandlerInterceptor() {
        log.info("LogHandlerInterceptor 构造方法被调用");
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        log.info("preHandle hanlder = {}", handler);
        return true;
    }

    @Override
    public void postHandle(HttpServletRequest request, HttpServletResponse response, Object handler, ModelAndView modelAndView) throws Exception {
        log.info("postHandle hanlder = {}, modelAndView = {}", handler, modelAndView);
    }

    @Override
    public void afterCompletion(HttpServletRequest request, HttpServletResponse response, Object handler, Exception ex) throws Exception {
        log.info("postHandle hanlder = {}, Exception = {}", handler, ex);

    }
}
```

**注意**： 实现`HandlerInterceptor`接口的实现类使用@Component注解之后，仍然无法使用，因为该实例没有被放入`AbstractHandlerMapping`的`adaptedInterceptors`属性中。

- 继承`WebMvcConfigurationSupport`重写`addInterceptors`方法，将自定义的拦截器放入`adaptedInterceptors`中。

```java
package com.example.springmvcexample.handlerMapping;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurationSupport;
import org.springframework.web.servlet.handler.MappedInterceptor;

@Configuration
public class WebMvcConfig extends WebMvcConfigurationSupport {

    @Override
    protected void addInterceptors(InterceptorRegistry registry) {
        super.addInterceptors(registry);
        // 第一种直接添加自定义的拦截器
//        registry.addInterceptor(new LogHandlerInterceptor());
        // 如果需要对指定url的请求调用拦截器，使用MappedInterceptor
        String[] includes = new String[]{"/hello/{name}"};
        String[] excludes = new String[]{"/echo/{name}"};
        registry.addInterceptor(new MappedInterceptor(includes, excludes, new LogHandlerInterceptor()));
    }
}
```

- 如果是异步请求使用`WebRequestInterceptor`，这里不作具体描述。

### 高级用法

- 自定义HandlerMapping

参考spring boot actuator 的  `WebMvcEndpointHandlerMapping`



## 总结

1. RequestMappingHandlerMapping初始化过程中会遍历所有的Bean，找到注解了@Controller或者@RequestMapping的类，通过反射找到所有的注解了@RequestMapping的方法，将其信息封装到一个RequestMapingInfo类对象中；最后将Handler（可以理解为Controller）、Method（注解标记的方法）、RequestMappingInfo三者注册到mappingRegistry的registry属性中。
2. 执行doDispatch方法内部调用getHandler方法将HandlerInterceptor实现类封装得到HandlerExecutionChain对象。
3. 得到HandlerExecutionChain对象之后调用HandlerInterceptor的preHandle方法
4. 调用HandlerAdapter的handle方法后调用HandlerInterceptor的postHandle方法
5. 在doDispatch方法调用结束前调用HandlerInterceptor的afterCompletion方法（异常处理之后，preHandle返回false也会执行）
