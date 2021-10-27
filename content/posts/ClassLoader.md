---
title: "classloader"
subtitle: ""
date: 2017-10-27T15:58:21+08:00
lastmod: 2017-10-27T15:58:21+08:00
draft: false
author: "山脚下的脚下山"
authorLink: ""
description: ""

tags: ["classloader"]
categories: ["java基础"]

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
# ClassLoader 介绍

## 什么是ClassLoader

java源码编译出来是一个个的`.class`文件，而ClassLoader的作用是将一个个的.class文件加载到jvm中。

## ClassLoader加载机制

> Java中默认提供了三个ClassLoader
>
> - BootStrap ClassLoader
> - Extension ClassLoader
> - App ClassLoader

### BootStrap ClassLoader

>启动类加载器
>
>作用：java中是最顶层的加载器，负责加载jdk的核心类库：rt.jar、resources.jar、charsets.jar

```java
public class BootStrapTest
{
    public static void main(String[] args)
    {
      URL[] urls = sun.misc.Launcher.getBootstrapClassPath().getURLs();
      for (int i = 0; i < urls.length; i++) {
          System.out.println(urls[i].toExternalForm());
       }
    }
}
```

以上程序可以得到BootStrap ClassLoader从哪些地址加载了哪些jar包

```txt
file://Users/xxx/java/jdk1.8.0_60/jre/lib/resources.jar
file://Users/xxx/java/jdk1.8.0_60/jre/lib/rt.jar
file://Users/xxx/java/jdk1.8.0_60/jre/lib/sunrsasign.jar
file://Users/xxx/java/jdk1.8.0_60/jre/lib/jsse.jar
file://Users/xxx/java/jdk1.8.0_60/jre/lib/charsets.jar
file://Users/xxx/java/jdk1.8.0_60/jre/lib/jfr.jar
file://Users/xxx/java/jdk1.8.0_60/jre/classes
```

该结果和`System.out.println(System.getProperty("sun.boot.class.path"));`输出结果一致



### Extension ClassLoader

> 扩展类加载器
>
> 作用：负责加载java的扩展类库，默认加载`$JAVA_HOME/jre/lib/ext/`目录下的所有jar



### App ClassLoader

>系统类加载器
>
>作用：负责加载classpath目录下的所有jar和class文件。主要负责加载程序员自己编码的java应用代码
>
>可以通过`ClassLoader.getSystemClassLoader()`方法获取



除了以上三种加载器之外，程序员可以自己实现自定义加载器，方式：继承`java.lang.ClassLoader`类。比如使用该方式可以对源class文件进行混淆加密，通过自定义ClassLoader进行解密

默认三种加载器之前存在父子关系（注意不是继承）`AppClassLoader -> ExtensionClassLoader -> BootStrapClassLoader` 。通过`getParent()`方法获取父类加载器（父类加载器使用包含关系引用）



## ClassLoader加载原理

> 摘自https://zhuanlan.zhihu.com/p/25493756

### 原理介绍

ClassLoader使用的是双亲委托模型来搜索类的，每个ClassLoader实例都有一个父类加载器的引用（不是继承的关系，是一个包含的关系），虚拟机内置的类加载器（Bootstrap ClassLoader）本身没有父类加载器，但可以用作其它ClassLoader实例的的父类加载器。当一个ClassLoader实例需要加载某个类时，它会试图亲自搜索某个类之前，先把这个任务委托给它的父类加载器，这个过程是由上至下依次检查的，首先由最顶层的类加载器Bootstrap ClassLoader试图加载，如果没加载到，则把任务转交给Extension ClassLoader试图加载，如果也没加载到，则转交给App ClassLoader 进行加载，如果它也没有加载得到的话，则返回给委托的发起者，由它到指定的文件系统或网络等URL中加载该类。如果它们都没有加载到这个类时，则抛出ClassNotFoundException异常。否则将这个找到的类生成一个类的定义，并将它加载到内存当中，最后返回这个类在内存中的Class实例对象。



### 为什么使用双亲委托模型？

因为这样可以避免重复加载，当父亲已经加载了该类的时候，就没有必要 ClassLoader再加载一次。考虑到安全因素，我们试想一下，如果不使用这种委托模式，那我们就可以随时使用自定义的String来动态替代java核心api中定义的类型，这样会存在非常大的安全隐患，而双亲委托的方式，就可以避免这种情况，因为String已经在启动时就被引导类加载器（Bootstrcp ClassLoader）加载，所以用户自定义的ClassLoader永远也无法加载一个自己写的String，除非你改变JDK中ClassLoader搜索类的默认算法。



### 但是JVM在搜索类的时候，又是如何判定两个class是相同的呢？

JVM在判定两个class是否相同时，不仅要判断两个类名是否相同，而且要判断是否由同一个类加载器实例加载的。只有两者同时满足的情况下，JVM才认为这两个class是相同的。就算两个class是同一份class字节码，如果被两个不同的ClassLoader实例所加载，JVM也会认为它们是两个不同class。比如网络上的一个Java类org.classloader.simple.NetClassLoaderSimple，javac编译之后生成字节码文件NetClassLoaderSimple.class，ClassLoaderA和ClassLoaderB这两个类加载器并读取了NetClassLoaderSimple.class文件，并分别定义出了java.lang.Class实例来表示这个类，对于JVM来说，它们是两个不同的实例对象，但它们确实是同一份字节码文件，如果试图将这个Class实例生成具体的对象进行转换时，就会抛运行时异常java.lang.ClassCaseException，提示这是两个不同的类型。现在通过实例来验证上述所描述的是否正确：