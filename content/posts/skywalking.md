---
weight: 1000
title: "skywalking源码分析"
subtitle: ""
date: 2018-09-27T15:58:21+08:00
lastmod: 2018-09-27T15:58:21+08:00
draft: false
author: "山脚下的脚下山"
authorLink: ""
description: ""

tags: ["apm"]
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

# skywalking-agent源码分析

## 执行顺序图

> 该顺序图大体内容都有了，缺少最后一步的BootService的生命周期调用，即下面的接口。在这个接口中会有一些服务调用，比如向Gprc注册发送的流程*

![0885a663](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-08-04/15:19:13/0885a663.png)

```
 public interface BootService {
    void prepare() throws Throwable;

    void boot() throws Throwable;

    void onComplete() throws Throwable;

    void shutdown() throws Throwable;
}
```
<!--more-->
## 分析
> 分析中主要讲`class Transformer implements AgentBuilder.Transformer`这个实现类中的`transform`方法

1. `transform`方法中调用`pluginFinder`的`find`方法。
```java
@Override
public DynamicType.Builder<?> transform(DynamicType.Builder<?> builder, TypeDescription typeDescription,
    ClassLoader classLoader, JavaModule module) {
    List<AbstractClassEnhancePluginDefine> pluginDefines = pluginFinder.find(typeDescription, classLoader);
    if (pluginDefines.size() > 0) {
        DynamicType.Builder<?> newBuilder = builder;
        EnhanceContext context = new EnhanceContext();
        for (AbstractClassEnhancePluginDefine define : pluginDefines) {
            DynamicType.Builder<?> possibleNewBuilder = define.define(typeDescription, newBuilder, classLoader, context);
            if (possibleNewBuilder != null) {
                newBuilder = possibleNewBuilder;
            }
        }
        if (context.isEnhanced()) {
            logger.debug("Finish the prepare stage for {}.", typeDescription.getName());
        }

        return newBuilder;
    }

    logger.debug("Matched class {}, but ignore by finding mechanism.", typeDescription.getTypeName());
    return builder;
}
```
2. 找到所有的`AbstractClassEnhancePluginDefine`实现类，在迭代所有子类，调用子类的`define`方法。在`define`方法中最主要的方法是`enhance`。该方法是抽象方法，由子类`ClassEnhancePluginDefine`中调用`enhanceClass`和`enhanceInstance`。
```java
@Override
protected DynamicType.Builder<?> enhance(TypeDescription typeDescription,
                                         DynamicType.Builder<?> newClassBuilder, ClassLoader classLoader,
                                         EnhanceContext context) throws PluginException {
    newClassBuilder = this.enhanceClass(typeDescription, newClassBuilder, classLoader);

    newClassBuilder = this.enhanceInstance(typeDescription, newClassBuilder, classLoader, context);

    return newClassBuilder;
}
```

3. 调用`enhanceClass`方法。该方法第一步也是最主要的一步调用`getStaticMethodsInterceptPoints`。这个方法也是抽象方法。这个方法由具体的插件实现。比如`LoadBalancedConnectionProxyInstrumentation`。这个类中会调用`getConstructorsInterceptPoints`来获取哪些方法是需要被拦截的。并且通过`getMethodsInterceptor`方法返回具体的实现类。这个方法类似AOP做切面处理。

```java
private DynamicType.Builder<?> enhanceClass(TypeDescription typeDescription,
    DynamicType.Builder<?> newClassBuilder, ClassLoader classLoader) throws PluginException {
    StaticMethodsInterceptPoint[] staticMethodsInterceptPoints = getStaticMethodsInterceptPoints();
    String enhanceOriginClassName = typeDescription.getTypeName();
    if (staticMethodsInterceptPoints == null || staticMethodsInterceptPoints.length == 0) {
        return newClassBuilder;
    }

    for (StaticMethodsInterceptPoint staticMethodsInterceptPoint : staticMethodsInterceptPoints) {
        String interceptor = staticMethodsInterceptPoint.getMethodsInterceptor();
        if (StringUtil.isEmpty(interceptor)) {
            throw new EnhanceException("no StaticMethodsAroundInterceptor define to enhance class " + enhanceOriginClassName);
        }

        if (staticMethodsInterceptPoint.isOverrideArgs()) {
            newClassBuilder = newClassBuilder.method(isStatic().and(staticMethodsInterceptPoint.getMethodsMatcher()))
                .intercept(
                    MethodDelegation.withDefaultConfiguration()
                        .withBinders(
                            Morph.Binder.install(OverrideCallable.class)
                        )
                        .to(new StaticMethodsInterWithOverrideArgs(interceptor))
                );
        } else {
            newClassBuilder = newClassBuilder.method(isStatic().and(staticMethodsInterceptPoint.getMethodsMatcher()))
                .intercept(
                    MethodDelegation.withDefaultConfiguration()
                        .to(new StaticMethodsInter(interceptor))
                );
        }

    }

    return newClassBuilder;
}
```
`LoadBalancedConnectionProxyInstrumentation`的实现方法
```java
@Override protected StaticMethodsInterceptPoint[] getStaticMethodsInterceptPoints() {
    return new StaticMethodsInterceptPoint[] {
        new StaticMethodsInterceptPoint() {
            @Override public ElementMatcher<MethodDescription> getMethodsMatcher() {
                return named("createProxyInstance");
            }
            //返回具体的拦截器实现类
            @Override public String getMethodsInterceptor() {
                return METHOD_INTERCEPTOR;
            }

            @Override public boolean isOverrideArgs() {
                return false;
            }
        }
    };
}
```
4. 调用`enhanceInstance`方法。这个方法中最主要的是调用下面的两个方法，一个是对构造器进行切面拦截，另一个是对实例对象中的方法进行拦截。比如`InvocableHandlerInstrumentation`这个实现类是对Springmvc中`InvocableHandlerMethod`的`invokeForRequest`进行拦截，具体的拦截器类是`org.apache.skywalking.apm.plugin.spring.mvc.commons.interceptor.InvokeForRequestInterceptor`。

```java
ConstructorInterceptPoint[] constructorInterceptPoints = getConstructorsInterceptPoints();
InstanceMethodsInterceptPoint[] instanceMethodsInterceptPoints = getInstanceMethodsInterceptPoints();
```

5. 实现类中的方法调用，3和4步骤中对方法进行了增强即拦截进行了代理操作。以`enhanceInstance`为例，在调用`getConstructorsInterceptPoints`和方法`getInstanceMethodsInterceptPoints`之后，如果存在需要拦截的方法，通过返回的`newClassBuilder`对方法进行拦截配置。如下代码，`newClassBuilder.method(junction).intercept(...)`调用intercept方法，然后在intercept方法中分别调用接口的具体实现方法。
```java
if (existedMethodsInterceptPoints) {
    for (InstanceMethodsInterceptPoint instanceMethodsInterceptPoint : instanceMethodsInterceptPoints) {
        String interceptor = instanceMethodsInterceptPoint.getMethodsInterceptor();
        if (StringUtil.isEmpty(interceptor)) {
            throw new EnhanceException("no InstanceMethodsAroundInterceptor define to enhance class " + enhanceOriginClassName);
        }
        ElementMatcher.Junction<MethodDescription> junction = not(isStatic()).and(instanceMethodsInterceptPoint.getMethodsMatcher());
        if (instanceMethodsInterceptPoint instanceof DeclaredInstanceMethodsInterceptPoint) {
            junction = junction.and(ElementMatchers.<MethodDescription>isDeclaredBy(typeDescription));
        }
        if (instanceMethodsInterceptPoint.isOverrideArgs()) {
            newClassBuilder =
                newClassBuilder.method(junction)
                    .intercept(
                        MethodDelegation.withDefaultConfiguration()
                            .withBinders(
                                Morph.Binder.install(OverrideCallable.class)
                            )
                            .to(new InstMethodsInterWithOverrideArgs(interceptor, classLoader))
                    );
        } else {
            newClassBuilder =
                newClassBuilder.method(junction)
                    .intercept(
                        MethodDelegation.withDefaultConfiguration()
                            .to(new InstMethodsInter(interceptor, classLoader))
                    );
        }
    }
}
```

## 总结重要实现及接口
> 该流程过程中主要是在enhance方法内进程代理（拦截器）的创建。具体的拦截器接口有`InstanceConstructorInterceptor`,`InstanceMethodsAroundInterceptor`,`StaticMethodsAroundInterceptor`,然后在上面三个接口的子类中有些会实现`EnhancedInstance`接口进行动态属性添加。而最主要的三个接口的实现类的调用是通过`newClassBuilder.method(junction).intercept`方法内部调用的。

如下图：
![e6ceb470](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-08-04/15:20:57/e6ceb470.png)

![c5f55da0](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-08-04/15:21:07/c5f55da0.png)

![a7f4cc7f](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-08-04/15:21:15/a7f4cc7f.png)