# 05_springmvc_handlerExceptionResolver

# HandlerExceptionResolver

> Spring的处理器异常解析器`HandlerExceptionResolver`接口的实现负责处理各类控制器执行过程中出现的异常

```java
public interface HandlerExceptionResolver {
   @Nullable
   ModelAndView resolveException(
         HttpServletRequest request, HttpServletResponse response, @Nullable Object handler, Exception ex);
}
```

## 初始化

初始化过程比较简单，在`DispatcherServlet`类`initStrategies`方法中调用`initHandlerExceptionResolvers`获取所有实现了`HandlerExceptionResolver`接口的实例

![image-20200721183147936](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-07-21/18:31:58/image-20200721183147936.png)

```java
/**
 * Initialize the HandlerExceptionResolver used by this class.
 * <p>If no bean is defined with the given name in the BeanFactory for this namespace,
 * we default to no exception resolver.
 */
private void initHandlerExceptionResolvers(ApplicationContext context) {
   this.handlerExceptionResolvers = null;

   if (this.detectAllHandlerExceptionResolvers) {
      // Find all HandlerExceptionResolvers in the ApplicationContext, including ancestor contexts.
      // 找到所有实现了HandlerExceptionResolver接口
      Map<String, HandlerExceptionResolver> matchingBeans = BeanFactoryUtils
            .beansOfTypeIncludingAncestors(context, HandlerExceptionResolver.class, true, false);
      if (!matchingBeans.isEmpty()) {
         this.handlerExceptionResolvers = new ArrayList<>(matchingBeans.values());
         // We keep HandlerExceptionResolvers in sorted order.
         AnnotationAwareOrderComparator.sort(this.handlerExceptionResolvers);
      }
   }
   else {
      try {
         HandlerExceptionResolver her =
               context.getBean(HANDLER_EXCEPTION_RESOLVER_BEAN_NAME, HandlerExceptionResolver.class);
         this.handlerExceptionResolvers = Collections.singletonList(her);
      }
      catch (NoSuchBeanDefinitionException ex) {
         // Ignore, no HandlerExceptionResolver is fine too.
      }
   }

   // Ensure we have at least some HandlerExceptionResolvers, by registering
   // default HandlerExceptionResolvers if no other resolvers are found.
   // 获取默认的异常解析器
   if (this.handlerExceptionResolvers == null) {
      this.handlerExceptionResolvers = getDefaultStrategies(context, HandlerExceptionResolver.class);
      if (logger.isTraceEnabled()) {
         logger.trace("No HandlerExceptionResolvers declared in servlet '" + getServletName() +
               "': using default strategies from DispatcherServlet.properties");
      }
   }
}
```

## 处理逻辑

在处理请求过程中，当发生了异常，被try...catch抓到之后，赋值给了`dispatchException`变量，然后在`processDispatchResult`方法中，判断exception是否为空，非空即表示存在异常，调用异常处理解析器（方法：`processHandlerException`）处理异常，返回ModelAndView

```java
private void processDispatchResult(HttpServletRequest request, HttpServletResponse response,
      @Nullable HandlerExecutionChain mappedHandler, @Nullable ModelAndView mv,
      @Nullable Exception exception) throws Exception {

   boolean errorView = false;

   if (exception != null) {
      if (exception instanceof ModelAndViewDefiningException) {
         logger.debug("ModelAndViewDefiningException encountered", exception);
         mv = ((ModelAndViewDefiningException) exception).getModelAndView();
      }
      else {
         Object handler = (mappedHandler != null ? mappedHandler.getHandler() : null);
         // 处理异常
         mv = processHandlerException(request, response, handler, exception);
         errorView = (mv != null);
      }
   }

   // Did the handler return a view to render?
   if (mv != null && !mv.wasCleared()) {
      render(mv, request, response);
      if (errorView) {
         WebUtils.clearErrorRequestAttributes(request);
      }
   }
   ...省略
}
```

处理异常

```java
protected ModelAndView processHandlerException(HttpServletRequest request, HttpServletResponse response,
      @Nullable Object handler, Exception ex) throws Exception {
	 ... 省略
   // Check registered HandlerExceptionResolvers...
   ModelAndView exMv = null;
   if (this.handlerExceptionResolvers != null) {
      for (HandlerExceptionResolver resolver : this.handlerExceptionResolvers) {
        // 调用异常处理解析器处理异常
         exMv = resolver.resolveException(request, response, handler, ex);
         if (exMv != null) {
            break;
         }
      }
   }
   ...省略
   throw ex;
}
```

### ExceptionHandlerMethodResolver

> 异常解析器中默认最常用的，也是工作中使用最多的，就是该类。主要处理`@ExceptionHandler`注解

该类继承和实现的接口如下图：

![image-20200725142446281](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-07-25/14:25:07-image-20200725142446281.png)

由上图可知，该类主要实现了HandlerExeptionResolver用于解析异常，并且实现了`@InitializationBean`接口。

#### @InitializationBean

```java
@Override
public void afterPropertiesSet() {
  // Do this first, it may add ResponseBodyAdvice beans
  // ①
  initExceptionHandlerAdviceCache(); 
  // ②
  if (this.argumentResolvers == null) {
    List<HandlerMethodArgumentResolver> resolvers = getDefaultArgumentResolvers();
    this.argumentResolvers = new HandlerMethodArgumentResolverComposite().addResolvers(resolvers);
  }
  // ③
  if (this.returnValueHandlers == null) {
    List<HandlerMethodReturnValueHandler> handlers = getDefaultReturnValueHandlers();
    this.returnValueHandlers = new HandlerMethodReturnValueHandlerComposite().addHandlers(handlers);
  }
}

```

① 、遍历所有标注了`ControllerAdvice`的类，并从标注了该注解的类下找到所有标注了`@ExceptionHandler`的方法。具体代码如下：

```java
private void initExceptionHandlerAdviceCache() {
	... 省略
  // 遍历Spring上下文，找出所有@ControllerAdvice的Bean
  List<ControllerAdviceBean> adviceBeans = ControllerAdviceBean.findAnnotatedBeans(getApplicationContext());
  for (ControllerAdviceBean adviceBean : adviceBeans) {
    Class<?> beanType = adviceBean.getBeanType();
    if (beanType == null) {
      throw new IllegalStateException("Unresolvable type for ControllerAdviceBean: " + adviceBean);
    }
    // 循环所有@ControllerAdvice的Bean，构造ExceptionHandlerMethodResolver实例用于缓存处理异常的方法
    ExceptionHandlerMethodResolver resolver = new ExceptionHandlerMethodResolver(beanType);
    // 如果该@ControllerAdvice中没有@ExceptionHandler，则丢弃刚new的实例
    if (resolver.hasExceptionMappings()) {
      this.exceptionHandlerAdviceCache.put(adviceBean, resolver);
    }
    // 如果标注了@ControllerAdvice的类实现了ResponseBodyAdvice，放到responseBodyAdvice属性中
    if (ResponseBodyAdvice.class.isAssignableFrom(beanType)) {
      this.responseBodyAdvice.add(adviceBean);
    }
  }
	... 省略
}
```

②、获取异常处理解析器中，用于`异常处理方法`的`参数解析器`

③、获取异常处理解析器中，用于`异常处理方法`的`返回值解析器`



接下来的流程和HandlerAdapter的处理逻辑差不多

```java
@Override
@Nullable
protected ModelAndView doResolveHandlerMethodException(HttpServletRequest request,
                                                       HttpServletResponse response, @Nullable HandlerMethod handlerMethod, Exception exception) {
	// 获取异常处理方法
  ServletInvocableHandlerMethod exceptionHandlerMethod = getExceptionHandlerMethod(handlerMethod, exception);
  if (exceptionHandlerMethod == null) {
    return null;
  }
	// 设置异常处理方法的参数解析器
  if (this.argumentResolvers != null) {
    exceptionHandlerMethod.setHandlerMethodArgumentResolvers(this.argumentResolvers);
  }
  // 设置异常处理方法的返回值解析器
  if (this.returnValueHandlers != null) {
    exceptionHandlerMethod.setHandlerMethodReturnValueHandlers(this.returnValueHandlers);
  }

  ServletWebRequest webRequest = new ServletWebRequest(request, response);
  ModelAndViewContainer mavContainer = new ModelAndViewContainer();

  try {
    if (logger.isDebugEnabled()) {
      logger.debug("Using @ExceptionHandler " + exceptionHandlerMethod);
    }
    Throwable cause = exception.getCause();
    if (cause != null) {
      // Expose cause as provided argument as well
      // 调用异常解析方法
      exceptionHandlerMethod.invokeAndHandle(webRequest, mavContainer, exception, cause, handlerMethod);
    }
    else {
      // Otherwise, just the given exception as-is
      // 调用异常解析方法
      exceptionHandlerMethod.invokeAndHandle(webRequest, mavContainer, exception, handlerMethod);
    }
  }
  catch (Throwable invocationEx) {
    // Any other than the original exception (or its cause) is unintended here,
    // probably an accident (e.g. failed assertion or the like).
    if (invocationEx != exception && invocationEx != exception.getCause() && logger.isWarnEnabled()) {
      logger.warn("Failure in @ExceptionHandler " + exceptionHandlerMethod, invocationEx);
    }
    // Continue with default processing of the original exception...
    return null;
  }

  if (mavContainer.isRequestHandled()) {
    return new ModelAndView();
  }
  else {
    ModelMap model = mavContainer.getModel();
    HttpStatus status = mavContainer.getStatus();
    ModelAndView mav = new ModelAndView(mavContainer.getViewName(), model, status);
    mav.setViewName(mavContainer.getViewName());
    if (!mavContainer.isViewReference()) {
      mav.setView((View) mavContainer.getView());
    }
    if (model instanceof RedirectAttributes) {
      Map<String, ?> flashAttributes = ((RedirectAttributes) model).getFlashAttributes();
      RequestContextUtils.getOutputFlashMap(request).putAll(flashAttributes);
    }
    return mav;
  }
}
```




