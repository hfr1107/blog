# 04_springmvc_handleradapter


# HandlerAdapter

>HandlerAdapter是处理器适配器，Spring MVC通过HandlerAdapter来实际调用处理函数。它是SpringMvc处理流程的第二步,当HandlerMapping获取了定位请求处理器Handler，DispatcherServlet会将得到的Handler告知HandlerAdapter，HandlerAdapter再根据请求去定位请求的具体处理方法是哪一个。
>
>1. HandlerAdapter定义了如何处理请求的策略，通过请求url、请求Method和处理器的requestMapping定义，最终确定使用处理类的哪个方法来处理请求，并检查处理类相应处理方法的参数以及相关的Annotation配置，确定如何转换需要的参数传入调用方法，并最终调用返回ModelAndView。
>
>2. DispatcherServlet中根据HandlerMapping找到对应的handler method后，首先检查当前工程中注册的所有可用的handlerAdapter，根据handlerAdapter中的supports方法找到可以使用的handlerAdapter。
>
>3. 通过调用handlerAdapter中的handler方法来处理及准备handler method的参数及annotation(这就是spring mvc如何将request中的参数变成handle method中的输入参数的地方)，最终调用实际的handler method。
>
>handlerAdapter这个类的作用就是接过handlermapping解析请求得到的handler对象。在更精确的定位到能够执行请求的方法。

- `initStrategies`调用`initHandlerAdapters`

![image-20200713144810889](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-07-15/23:28:34-mlUY7Z8SRfxDQeK.png)

❶从Spring的上下文环境中获取实现了`HandlerAdapter`接口的实现类，默认会有以下实现类：

    RequestMappingHandlerAdapter
    HandlerFunctionAdapter
    HttpRequestHandlerAdapter
    SimpleControllerHandlerAdapter
❷对❶中查找到的实现类排序

❸如果配置了`detectAllHandlerAdapters`属性为false，则从Spring上下文中获取一个beanName = `handlerAdapter`的实例

❹如果前几步都没有获取到`HandlerAdapter`的实现类，则从`dispatcherServlet.properties`中获取默认的实现类。

```properties
org.springframework.web.servlet.HandlerAdapter=org.springframework.web.servlet.mvc.HttpRequestHandlerAdapter,\
	org.springframework.web.servlet.mvc.SimpleControllerHandlerAdapter,\
	org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerAdapter,\
	org.springframework.web.servlet.function.support.HandlerFunctionAdapter
```

- `RequestMappingHandlerAdapter`UML类图，在没有自定义特殊情况下，该类便是`HandlerAdapter`的主要实现类。以下我们便以该类来讲解。

![RequestMappingHandlerAdapter](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-07-15/23:29:45-HtO7GVeNXJW4i2f.png)

## InitializationBean

> 由以上类图可知：`RequestMappingHandlerAdapter`实现了`InitializationBean`接口，所以我们看一眼该接口方法做了什么？

- afterPropertiesSet

![image-20200713210108442](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-07-15/23:30:28-CQzUfMZ8EAHhvrV.png)

### ❶ InitControllerAdviceCache

遍历Spring上下文实例，找出`@ControllerAdvice`、`@ModelAttribute`、`@InitBinder`和实现了`RequestBodyAdvice`或者`ResponseBodyAdvice`相关的处理方法，并缓存起来。具体如下：

![image-20200713211625660](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-07-15/23:31:26-B9vuAZRX6fMJcV3.png)

1. 从Spring上下文找到`@ControllerAdvice`注解的类
2. 遍历1.中找到的标记了`@ControllerAdvice`的类中找到注解了`@ModelAttribute`的方法
3. 遍历1.中找到的标记了`@ControllerAdvice`的类中找到注解了`@InitBinder`的方法
4. 遍历1.中找到的标记了`@ControllerAdvice`的类中找到实现了`RequestBodyAdvice`和`ResponseBodyAdvice`的实现

### ❷ 参数解析器 

> 1. 解析特定注解的参数
> 2. 参数校验

获取默认的参数解析器，针对各种类型参数具体解析器如下：

![image-20200713212613258](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-07-15/23:33:51-PcSAfYzLbMH3TyQ.png)

由该方法可知，参数解析器包含了4大块：`基于注解的`，`基于类型的`，`自定义的`，`其他`

所以接口都实现了`HandlerMethodArgumentResolver`接口。该接口有两个方法，一个判断是否支持该类型参数，一个用于解析参数。

![image-20200714110456697](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/image-20200714110456697.png)

- #### `RequestParamMethodArgumentResolver`
  
  - 主要用来解析`@RequestParam`注解的参数

![image-20200714105830467](https://cdn.jsdelivr.net/gh/scemsjyd/static@master/uPic/image-20200714105830467.png)

- #### `RequestParamMapMethodArgumentResolver`
  
  - 用来解析@RequestParam注解并参数类型为Map的参数，并且requestParam.name为空

```java
@Override
public boolean supportsParameter(MethodParameter parameter) {
  RequestParam requestParam = parameter.getParameterAnnotation(RequestParam.class);
  return (requestParam != null && Map.class.isAssignableFrom(parameter.getParameterType()) &&
          !StringUtils.hasText(requestParam.name()));
```

- `PathVariableMethodArgumentResolver`
  - 用来解析`@PathVariable`注解的参数；参数类型是Map，并且pathVariable.value()存在的参数

```java
@Override
public boolean supportsParameter(MethodParameter parameter) {
  if (!parameter.hasParameterAnnotation(PathVariable.class)) {
    return false;
  }
  if (Map.class.isAssignableFrom(parameter.nestedIfOptional().getNestedParameterType())) {
    PathVariable pathVariable = parameter.getParameterAnnotation(PathVariable.class);
    return (pathVariable != null && StringUtils.hasText(pathVariable.value()));
  }
  return true;
}
```

- #### `PathVariableMapMethodArgumentResolver`
  
  - 用来解析`@PathVariable`注解的参数类型是Map，并且pathVariable.value()不存在的参数

```java
@Override
public boolean supportsParameter(MethodParameter parameter) {
  PathVariable ann = parameter.getParameterAnnotation(PathVariable.class);
  return (ann != null && Map.class.isAssignableFrom(parameter.getParameterType()) &&
          !StringUtils.hasText(ann.value()));
}
```

- #### `MatrixVariableMethodArgumentResolver`
  
  - 用于解析`@MatrixVariable`注解的参数；*参数类型是Map，并且matrixVariable.name存在的参数，也能被解析，但是没有默认的数据绑定器，所以会报错。

```java
@Override
public boolean supportsParameter(MethodParameter parameter) {
  if (!parameter.hasParameterAnnotation(MatrixVariable.class)) {
    return false;
  }
  if (Map.class.isAssignableFrom(parameter.nestedIfOptional().getNestedParameterType())) {
    MatrixVariable matrixVariable = parameter.getParameterAnnotation(MatrixVariable.class);
    return (matrixVariable != null && StringUtils.hasText(matrixVariable.name()));
  }
  return true;
}
```

 示例

 ```java
/**
 * 请求示例： GET http://localhost:8080/mv1/123;q=123/456;q=456 
 * 正常响应
 */
@RequestMapping("/mv1/{x}/{y}")
public String matrixVairable1(
  @PathVariable String x,
  @PathVariable String y,
  @MatrixVariable(name = "q", pathVar = "x") int q1,
  @MatrixVariable(name = "q", pathVar = "y") int q2) {

  return String.format("x = %s, y = %s, q1 = %s, q2 = %s", x, y, q1, q2);
}
 ```

```java
/**
 * 请求示例： GET http://localhost:8080/mv2/q=123/q=456 
 * 正常响应
 */
@RequestMapping("/mv2/{a}/{b}")
public String matrixVairable2(
  @MatrixVariable(name = "q", pathVar = "a") int q1,
  @MatrixVariable(name = "q", pathVar = "b") int q2) {

  return String.format("a = %s, b = %s", q1, q2);
}
```

```java
/**
 * 请求示例： GET http://localhost:8080/mv4/a=123/b=456; 
 * 结果报错：Cannot convert value of type 'java.lang.String' to required type 'java.util.Map': no matching editors or conversion strategy found
 */
@RequestMapping("/mv4/{a}/{b}")
public String matrixVairable4(
  @MatrixVariable(name = "a", pathVar = "a") Map<String, String> m1,
  @MatrixVariable(name = "b", pathVar = "b") Map<String, String> m2) throws JsonProcessingException {
  ObjectMapper objectMapper = new ObjectMapper();
  return String.format("a = %s, b = %s", objectMapper.writeValueAsString(m1), objectMapper.writeValueAsString(m2));
}
```

- #### `MatrixVariableMapMethodArgumentResolver`
  
  - 用于解析`@MatrixVariable`注解的参数类型是Map，并且matrixVariable.name不存在的参数

```java
@Override
public boolean supportsParameter(MethodParameter parameter) {
  MatrixVariable matrixVariable = parameter.getParameterAnnotation(MatrixVariable.class);
  return (matrixVariable != null && Map.class.isAssignableFrom(parameter.getParameterType()) &&
          !StringUtils.hasText(matrixVariable.name()));
}
```

示例

```java
/**
 *  请求示例： GET http://localhost:8080/mv3/a1=123;a2=321/b1=456;b2=654
 */
@RequestMapping("/mv3/{a}/{b}")
public String matrixVairable3(
  @MatrixVariable(pathVar = "a") Map<String, String> m1,
  @MatrixVariable(pathVar = "b") Map<String, String> m2) throws JsonProcessingException {
  ObjectMapper objectMapper = new ObjectMapper();
  return String.format("a = %s, b = %s", objectMapper.writeValueAsString(m1), objectMapper.writeValueAsString(m2));
}
```

**注意**： `@MatrixVariable`在SpringBoot中默认是无法使用矩阵参数的，需要修改Path解析

```java
@Configuration
public class WebConfig implements WebMvcConfigurer {

    @Override
    public void configurePathMatch(PathMatchConfigurer configurer) {
        UrlPathHelper urlPathHelper=new UrlPathHelper();
        urlPathHelper.setRemoveSemicolonContent(false);
        configurer.setUrlPathHelper(urlPathHelper);
    }
}
```

- #### `ServletModelAttributeMethodProcessor`

  - 有两个相同的参数解析器，一个构造函数传false，一个传true

  - **被`@ModelAttribute`注解注释的方法会在此controller每个方法执行前被执行**
  - 解析`@ModelAttribute`注解的参数
  - 解析`@ModelAttribute`注解的响应

```java
@Override
public boolean supportsParameter(MethodParameter parameter) {
  return (parameter.hasParameterAnnotation(ModelAttribute.class) ||
          (this.annotationNotRequired && !BeanUtils.isSimpleProperty(parameter.getParameterType())));
}

@Override
public boolean supportsReturnType(MethodParameter returnType) {
  return (returnType.hasMethodAnnotation(ModelAttribute.class) ||
          (this.annotationNotRequired && !BeanUtils.isSimpleProperty(returnType.getParameterType())));
}
```

示例

1. 使用`@ModelAttribute`注解无返回值的方法

```java
@ModelAttribute
public void myModel(@RequestParam(required = false) String abc, Model model) {
  model.addAttribute("attributeName", abc);
}

@RequestMapping(value = "/method")
public String method() {
  return "method";
}
```

在`@RequestMapping`返回视图名称，`@ModelAttribute`返回模型数据

2. 使用`@ModelAttribute`注解带有返回值的方法

```java
@ModelAttribute
public String myModel(@RequestParam(required = false) String abc) {
    return abc;
}

@ModelAttribute
public Student myModel(@RequestParam(required = false) String abc) {
    Student student = new Student(abc);
    return student;
}

@ModelAttribute
public int myModel(@RequestParam(required = false) int number) {
    return number;
}

@ModelAttribute(value="name")
public String myModel(@RequestParam(required = false) String name) {
    return name;
}

// 上面4个等同于下面
model.addAttribute("string", abc);
model.addAttribute("int", number);
model.addAttribute("student", student);
model.addAttribute("name", name);
```

对于这种情况，返回值对象会被默认放到隐含的`Model`中，在`Model`中的`key`为**`返回值首字母小写`**，`value`为返回的值。

3. 使用@ModelAttribute注解的参数

```java
@Controller
@RequestMapping(value = "/modelattribute")
public class ModelAttributeParamController {

    @ModelAttribute(value = "attributeName")
    public String myModel(@RequestParam(required = false) String abc) {
        return abc;
    }

    @ModelAttribute
    public void myModel3(Model model) {
        model.addAttribute("name", "zong");
        model.addAttribute("age", 20);
    }

    @RequestMapping(value = "/param")
    public String param(@ModelAttribute("attributeName") String str,
                       @ModelAttribute("name") String str2,
                       @ModelAttribute("age") int str3) {
        return "param";
    }
}
```

使用`@ModelAttribute`注解的参数，意思是从前面的`Model`中提取对应名称的属性。

- #### `RequestResponseBodyMethodProcessor`
  
  - 解析`@RequestBody`注解的参数
  - 解析`@ResponseBody`注解的响应

```java
// 参数类型
@Override
public boolean supportsParameter(MethodParameter parameter) {
  return parameter.hasParameterAnnotation(RequestBody.class);
}
// 响应类型
@Override
public boolean supportsReturnType(MethodParameter returnType) {
  return (AnnotatedElementUtils.hasAnnotation(returnType.getContainingClass(), ResponseBody.class) ||
          returnType.hasMethodAnnotation(ResponseBody.class));
}
```

其他解析器

```
# 解析@RequestPart注解，解析上传的文件
RequestPartMethodArgumentResolver

# 解析@RequestHeader注解，解析Header中的值到参数中
RequestHeaderMethodArgumentResolver
RequestHeaderMapMethodArgumentResolver

# 解析@CookieValue注解，解析cookie中的值到参数中
ServletCookieValueMethodArgumentResolver

# 解析@Value注解，解析@Value("${xxx}"，配置环境变量的值到参数中，例如xxx = servlet.port)
ExpressionValueMethodArgumentResolver

# 解析@SessionAttribute注解，解析session.getAttribute中的值到参数中
SessionAttributeMethodArgumentResolver

# 解析@ReqReuqestMappingHandlerAdapterAttribute中的值到参数中
RequestAttributeMethodArgumentResolver

......
更多参考ReuqestMappingHandlerAdapter.getDefaultArgumentResolvers方法
```



### ❸InitBinder参数解析器

> 调用`@InitBinder`注解的方法，解析被注解的方法的参数。

支持的参数解析器如下：

```java
/**
 * Return the list of argument resolvers to use for {@code @InitBinder}
 * methods including built-in and custom resolvers.
 */
private List<HandlerMethodArgumentResolver> getDefaultInitBinderArgumentResolvers() {
  List<HandlerMethodArgumentResolver> resolvers = new ArrayList<>();

  // Annotation-based argument resolution
  resolvers.add(new RequestParamMethodArgumentResolver(getBeanFactory(), false));
  resolvers.add(new RequestParamMapMethodArgumentResolver());
  resolvers.add(new PathVariableMethodArgumentResolver());
  resolvers.add(new PathVariableMapMethodArgumentResolver());
  resolvers.add(new MatrixVariableMethodArgumentResolver());
  resolvers.add(new MatrixVariableMapMethodArgumentResolver());
  resolvers.add(new ExpressionValueMethodArgumentResolver(getBeanFactory()));
  resolvers.add(new SessionAttributeMethodArgumentResolver());
  resolvers.add(new RequestAttributeMethodArgumentResolver());

  // Type-based argument resolution
  resolvers.add(new ServletRequestMethodArgumentResolver());
  resolvers.add(new ServletResponseMethodArgumentResolver());

  // Custom arguments
  if (getCustomArgumentResolvers() != null) {
    resolvers.addAll(getCustomArgumentResolvers());
  }

  // Catch-all
  resolvers.add(new RequestParamMethodArgumentResolver(getBeanFactory(), true));

  return resolvers;
}
```

调用流程：

Controller标注的`@RequestMapping`方法的参数解析时，比如：`RequestParamMethodArgumentResolver`解析器。有如下代码：

```java
...省略
if (binderFactory != null) {
  // 创建WebDataBinder对象，其中调用@InitBinder注解的方法
  WebDataBinder binder = binderFactory.createBinder(webRequest, null, namedValueInfo.name);
  try {
    arg = binder.convertIfNecessary(arg, parameter.getParameterType(), parameter);
  }
  catch (ConversionNotSupportedException ex) {
    throw new MethodArgumentConversionNotSupportedException(arg, ex.getRequiredType(),
                                                            namedValueInfo.name, parameter, ex.getCause());
  }
  catch (TypeMismatchException ex) {
    throw new MethodArgumentTypeMismatchException(arg, ex.getRequiredType(),
                                                  namedValueInfo.name, parameter, ex.getCause());
  }
}
...省略
```

```java
public final WebDataBinder createBinder(
  NativeWebRequest webRequest, @Nullable Object target, String objectName) throws Exception {

  WebDataBinder dataBinder = createBinderInstance(target, objectName, webRequest);
  if (this.initializer != null) {
    // 为initbinder方法添加消息转换大，属性编辑器等
    this.initializer.initBinder(dataBinder, webRequest);
  }
  // 调用@InitBinder方法
  initBinder(dataBinder, webRequest);
  return dataBinder;
}
```

调用`@ControllerAdvice`中`@InitBinder`的全局方法和`@Controller`中的单属于每个controller的`@InitBinder`方法

```java
public void initBinder(WebDataBinder dataBinder, NativeWebRequest request) throws Exception {
  for (InvocableHandlerMethod binderMethod : this.binderMethods) {
    if (isBinderMethodApplicable(binderMethod, dataBinder)) {
    	// 调用@initBinder注解的方法
      Object returnValue = binderMethod.invokeForRequest(request, null, dataBinder);
      if (returnValue != null) {
        throw new IllegalStateException(
          "@InitBinder methods must not return a value (should be void): " + binderMethod);
      }
    }
  }
}
```

调用参数解析器解析initBinder参数

```java
protected Object[] getMethodArgumentValues(NativeWebRequest request, @Nullable ModelAndViewContainer mavContainer,
			Object... providedArgs) throws Exception {
			... 省略
      // 此处resolvers便是afterPropertiesSet中调用getDefaultInitBinderArgumentResolvers()
			if (!this.resolvers.supportsParameter(parameter)) {
				throw new IllegalStateException(formatArgumentError(parameter, "No suitable resolver"));
			}
			try {
				args[i] = this.resolvers.resolveArgument(parameter, mavContainer, request, this.dataBinderFactory);
			}
			... 省略
	}
```



### ❹返回值解析器

> 处理返回值

源码位置：

```java
public void invokeAndHandle(ServletWebRequest webRequest, ModelAndViewContainer mavContainer,
			Object... providedArgs) throws Exception {
		// ①调用handle，Controller方法的处理函数得到返回值
		Object returnValue = invokeForRequest(webRequest, mavContainer, providedArgs);
		setResponseStatus(webRequest);

		if (returnValue == null) {
			if (isRequestNotModified(webRequest) || getResponseStatus() != null || mavContainer.isRequestHandled()) {
				disableContentCachingIfNecessary(webRequest);
				mavContainer.setRequestHandled(true);
				return;
			}
		}
		else if (StringUtils.hasText(getResponseStatusReason())) {
			mavContainer.setRequestHandled(true);
			return;
		}

		mavContainer.setRequestHandled(false);
		Assert.state(this.returnValueHandlers != null, "No return value handlers");
		try {
      // ②处理返回值
			this.returnValueHandlers.handleReturnValue(
					returnValue, getReturnValueType(returnValue), mavContainer, webRequest);
		}
		catch (Exception ex) {
			if (logger.isTraceEnabled()) {
				logger.trace(formatErrorForReturnValue(returnValue), ex);
			}
			throw ex;
		}
	}
```

①处调用请求的处理，②处调用返回值处理逻辑。

返回值处理逻辑如下：

```java
/**
 * Iterate over registered {@link HandlerMethodReturnValueHandler HandlerMethodReturnValueHandlers} and invoke the one that supports it.
 * @throws IllegalStateException if no suitable {@link HandlerMethodReturnValueHandler} is found.
 */
@Override
public void handleReturnValue(@Nullable Object returnValue, MethodParameter returnType,
                              ModelAndViewContainer mavContainer, NativeWebRequest webRequest) throws Exception {
	// 获取处理返回值的解析器
  HandlerMethodReturnValueHandler handler = selectHandler(returnValue, returnType);
  if (handler == null) {
    throw new IllegalArgumentException("Unknown return value type: " + returnType.getParameterType().getName());
  }
  // 根据返回的对应解析器处理返回值
  handler.handleReturnValue(returnValue, returnType, mavContainer, webRequest);
}
```



## handle流程

> handle方法是HandleAdapter的核心方法，Controller中业务的处理逻辑也是在此方法中被调用 

`RequestMappingHandlerAdapter`中的`handle`方法如下：

```java
/**
 * This implementation expects the handler to be an {@link HandlerMethod}.
 */
@Override
@Nullable
public final ModelAndView handle(HttpServletRequest request, HttpServletResponse response,   Object handler) throws Exception {

  return handleInternal(request, response, (HandlerMethod) handler);
}
```

![image-20200725153200873](/Users/Adam.Jin/Library/Mobile Documents/com~apple~CloudDocs/笔记/技术/Java/springmvc/04_HandlerAdapter.assets/image-20200725153200873.png)

invokeHandlerMethod方法：

![image-20200725155710291](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-07-25/15:57:15-image-20200725155710291.png)



❶、获取DataBinderFactory代码如下：

![image-20200725160459638](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-07-25/16:05:07-image-20200725160459638.png)

❷、获取ModelFactory的逻辑与DataBinderFacotory差不多

![image-20200725160743451](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-07-25/16:13:24-image-20200725160743451.png)

❼、参数名解析参考https://blog.csdn.net/qq271859852/article/details/84963672

❽、填充model数据，包括SessionAtrribute中的数据。

![image-20200725161203519](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-07-25/16:13:16-image-20200725161203519.png)

![image-20200725161310748](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-07-25/16:13:14-image-20200725161310748.png)

接着调用invokeAndHandle方法

![image-20200725161740953](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-07-25/16:17:53-image-20200725161740953.png)

![image-20200725161931914](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-07-25/16:19:37-image-20200725161931914.png)

![image-20200725162130625](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-07-25/16:21:34-image-20200725162130625.png)

![image-20200725164435096](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-07-25/16:44:37-image-20200725164435096.png)

