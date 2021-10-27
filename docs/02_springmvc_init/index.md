# 02_springmvc_init


# DispatcherServlet Init

> dispatcherServlet是springmvc的核心

## servlet的生命周期

> ==servlet==的三个重要方法`init`  `service` `destroy`

1.被创建：执行init方法，只执行一次

　　1.1 Servlet什么时候被创建？

　　1.2 默认情况下，第一次被访问时，Servlet被创建，然后执行init方法；

　　1.3 可以配置执行Servlet的创建时机；

2.提供服务：执行service方法，执行多次

3.被销毁：当Servlet服务器正常关闭时，执行destroy方法，只执行一次

## init

> dispatcherServlet的init做了什么？


最重要的方法：`initServletBean()`

![image-20200630151802535](https://i.loli.net/2020/07/03/O9Iwdst1JVRzGZe.png)

![image-20200630153348266](https://i.loli.net/2020/07/03/dW8piPYb7wvSMHn.png)

![image-20200630153834595](https://i.loli.net/2020/07/03/cEFToGaP4NdOgqi.png)

到此SpringMVC的初始化基本结束。

总结：

1. 完成上下文springmvc的上下文配置
2. 初始化九大组件的策略配置

## service

>service是servlet的业务处理核心，此处又做了些什么？

DispatcherServlet的service主要业务处理方法在`doDispatch`中

![image-20200701093416565](https://i.loli.net/2020/07/03/M1zDoecFalduvmU.png)

