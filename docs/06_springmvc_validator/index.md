# 06_springmvc_validator


# 参数校验器

> Spring MVC中的参数校验器并没有自己大量从新开发，而是使用了Hibernate-Validator，而Hibernate-Validator实现了JSR-303的所有功能。在SpringMVC中有两个地方可以于用参数校验。

## 1、Bean Validator

> 此处的Bean Validator指JSR-303（JSR是Java Specification Requests的缩写，意思是Java 规范提案，其中303号内容指提供一套基于注解的校验规范[This JSR will define a meta-data model and API for JavaBeanTM validation based on annotations, with overrides and extended meta-data through the use of XML validation descriptors.]）。Hibernate Validator是它最出名的实现，也是目前世界上使用最广的校验器实现。Hibernate Validator 提供了 JSR 303 规范中所有内置 constraint 的实现，除此之外还有一些附加的 constraint。

| Annotation      | 注解说明                                                     | 备注 |
| --------------- | ------------------------------------------------------------ | ---- |
| DecimalMax      | 元素必须是一个数字，其值必须小于或等于指定的最大值           |      |
| DecimalMin      | 元素必须是一个数字，其值必须大于或等于指定的最小值           |      |
| Pattern         | 必须与指定的正则表达式匹配                                   |      |
| Email           | 检查给定的字符序列（例如字符串）是否是格式正确的电子邮件地址 |      |
| Max             | 元素必须是一个数字，其值必须小于或等于指定的最大值           |      |
| Min             | 元素必须是一个数字，其值必须大于或等于指定的最小值           |      |
| AssertFalse     | 元素的值必须为false                                          |      |
| AssertTrue      | 元素的值必须为true                                           |      |
| Digits          | 元素必须是可接受范围内的数字                                 |      |
| NegativeOrZero  | 元素必须为严格的负数（即0视为无效值）                        |      |
| NotBlank        | 删除任何前导或尾随空格后，检查字符序列是否不为空             |      |
| NotEmpty        | 元素必须不为null且不为empty                                  |      |
| NotNull         | 元素必须不为null                                             |      |
| Null            | 元素必须为null                                               |      |
| PositiveOrZero  | 元素必须为正数或0                                            |      |
| Positive        | 元素必须为严格的正数（即0视为无效值）                        |      |
| Size            | 元素大小必须在指定的边界（包括在内）之间。                   |      |
| Future          | 元素必须是将来的瞬间，日期或时间                             |      |
| FutureOrPresent | 元素必须是当前或将来的瞬间，日期或时间                       |      |
| Past            | 元素必须是过去的瞬间，日期或时间                             |      |
| PastOrPresent   | 元素必须是过去或现在的瞬间，日期或时间                       |      |

## 2、Hibernate Validator编程式校验

- SpringBoot

```xml
<dependency>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-validation</artifactId>
</dependency>
```

- 直接导入

```xml
<dependency>
    <groupId>javax.validation</groupId>
    <artifactId>validation-api</artifactId>
    <version>2.0.0.Final</version>
</dependency>
<dependency>
  <groupId>org.hibernate.validator</groupId>
  <artifactId>hibernate-validator</artifactId>
  <version>6.1.5.Final</version>
</dependency>
<dependency>
```

### 2.1、普通对象校验

```java
public class User {

    @NotNull
    private String name;
  
    @Min(value="1")
    private String age;

    //...
}
```

```JAVA
ValidatorFactory factory = Validation.buildDefaultValidatorFactory();
validator = factory.getValidator();

Set<ConstraintViolation<Car>> constraintViolations = validator.validate( department );

assertEquals( 1, constraintViolations.size() );
assertEquals( "must not be null", constraintViolations.iterator().next().getMessage() );
```

Validation类是Bean Validation的入口点，buildDefaultValidatorFactory()方法基于默认的Bean Validation提供程序构建并返回ValidatorFactory实例。使用默认验证提供程序解析程序逻辑解析提供程序列表。代码上等同于Validation.byDefaultProvider().configure().buildValidatorFactory()。

之后调用该ValidatorFactory.getValidator()返回一个校验器实例，使用这个校验器的validate方法对目标对象的属性进行校验，返回一个ConstraintViolation集合。ConstraintViolation用于描述约束违规。 此对象公开约束违规上下文以及描述违规的消息。

### 2.2、分组校验

首先需要在constraint注解上指定groups属性，这个属性是一个class对象数组，再调用javax.validation.Validator接口的validate方法的时候将第二个参数groups传入class数组元素之一就可以针对这个这个group的校验规则生效。

## HandlerMethodArgumentResolver

> 在04_HandlerAdaptor那一章节中我们已经讲过参数解析器了，在参数解析过程中，SpringMVC会对参数进行校验。

我们这里以`RequestResponseBodyMethodProcessor`来举例，该类实现了`HandlerMethodArgumentResolver`接口，用于处理@RequestBody标记的参数类型。

![image-20200725145826050](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-07-25/16:25:12-image-20200725145826050.png)

### **validateIfApplicable**

该方法便是用于参数的校验，具体逻辑如下：

![image-20200725163025940](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-07-25/16:30:29-image-20200725163025940.png)



![image-20200725165301506](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-07-25/16:53:17-image-20200725165301506.png)



- ## ValidationAutoConfiguration

```java
@RestController
@Validated
public class TestController {
    @RequestMapping("/test")
    public String test(@RequestParam("age") @Max(200) Integer age) {
        return String.format("age = %s", age);
    }
}
```

spring驱动类：ValidationAutoConfiguration MethodValidationPostProcessor

校验器

https://blog.csdn.net/roberts939299/article/details/73730410




