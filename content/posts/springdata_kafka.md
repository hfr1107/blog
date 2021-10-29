---
weight: 1000
title: "SpringData_kafka"
subtitle: ""
date: 2019-10-27T15:58:21+08:00
lastmod: 2019-10-27T15:58:21+08:00
draft: false
author: "山脚下的脚下山"
authorLink: ""
description: ""

tags: ["kafka"]
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
# Spring kafka 要点

> 以下内容记录了一些工作中遇到的kafka的要点（个人认为）

## 一、kafka消费者

### 1.1、源码分析

#### 1.1.1、 `@EnableKafka`

作用：kafka开启入口

```java
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@Documented
@Import(KafkaBootstrapConfiguration.class) // 最重要的入口配置
public @interface EnableKafka {
}
```

<!--more-->
#### 1.1.1.1、 `KafkaBootstrapConfiguration`

作用：kafka启动配置类，该类主要实例化以下两个Bean

##### 1.1.1.1.1、 `KafkaListenerAnnotationBeanPostProcessor`

作用：实现BeanPostProcessor接口，重写方法

###### 1.1.1.1.1.1、 `postProcessAfterInitialization`

```java
@Override
    public Object postProcessAfterInitialization(final Object bean, final String beanName) throws BeansException {
        if (!this.nonAnnotatedClasses.contains(bean.getClass())) {
            Class<?> targetClass = AopUtils.getTargetClass(bean);
      // 找到标记在类上的@KafkaListener注解
            Collection<KafkaListener> classLevelListeners = findListenerAnnotations(targetClass);
            final boolean hasClassLevelListeners = classLevelListeners.size() > 0;
            final List<Method> multiMethods = new ArrayList<>();
      // 找到标记在方法上的@KafkaListener注解
            Map<Method, Set<KafkaListener>> annotatedMethods = MethodIntrospector.selectMethods(targetClass,
                    new MethodIntrospector.MetadataLookup<Set<KafkaListener>>() {

                        @Override
                        public Set<KafkaListener> inspect(Method method) {
                            Set<KafkaListener> listenerMethods = findListenerAnnotations(method);
                            return (!listenerMethods.isEmpty() ? listenerMethods : null);
                        }

                    });
            if (hasClassLevelListeners) {
                Set<Method> methodsWithHandler = MethodIntrospector.selectMethods(targetClass,
                        (ReflectionUtils.MethodFilter) method ->
                                AnnotationUtils.findAnnotation(method, KafkaHandler.class) != null);
                multiMethods.addAll(methodsWithHandler);
            }
            if (annotatedMethods.isEmpty()) {
                this.nonAnnotatedClasses.add(bean.getClass());
                if (this.logger.isTraceEnabled()) {
                    this.logger.trace("No @KafkaListener annotations found on bean type: " + bean.getClass());
                }
            }
            else {
                // Non-empty set of methods
                for (Map.Entry<Method, Set<KafkaListener>> entry : annotatedMethods.entrySet()) {
                    Method method = entry.getKey();
                    for (KafkaListener listener : entry.getValue()) {
            // 重要的方法，处理kafkaListener
                        processKafkaListener(listener, method, bean, beanName);
                    }
                }
                if (this.logger.isDebugEnabled()) {
                    this.logger.debug(annotatedMethods.size() + " @KafkaListener methods processed on bean '"
                            + beanName + "': " + annotatedMethods);
                }
            }
            if (hasClassLevelListeners) {
                processMultiMethodListeners(classLevelListeners, multiMethods, bean, beanName);
            }
        }
        return bean;
    }
```

###### 1.1.1.1.1.2、`processKafkaListener`

```java
    protected void processKafkaListener(KafkaListener kafkaListener, Method method, Object bean, String beanName) {
        Method methodToUse = checkProxy(method, bean);
    // new endpoint实例，表示一个kafkaListener切入点
        MethodKafkaListenerEndpoint<K, V> endpoint = new MethodKafkaListenerEndpoint<>();
        endpoint.setMethod(methodToUse);
      // 处理Listener
        processListener(endpoint, kafkaListener, bean, methodToUse, beanName);
    }
```

###### 1.1.1.1.1.3、`processListener`

```java
protected void processListener(MethodKafkaListenerEndpoint<?, ?> endpoint, KafkaListener kafkaListener,
            Object bean, Object adminTarget, String beanName) {

        String beanRef = kafkaListener.beanRef();
        if (StringUtils.hasText(beanRef)) {
            this.listenerScope.addListener(beanRef, bean);
        }
        endpoint.setBean(bean);
        endpoint.setMessageHandlerMethodFactory(this.messageHandlerMethodFactory);
        endpoint.setId(getEndpointId(kafkaListener));
        endpoint.setGroupId(getEndpointGroupId(kafkaListener, endpoint.getId()));
        endpoint.setTopicPartitions(resolveTopicPartitions(kafkaListener));
        endpoint.setTopics(resolveTopics(kafkaListener));
        endpoint.setTopicPattern(resolvePattern(kafkaListener));
        endpoint.setClientIdPrefix(resolveExpressionAsString(kafkaListener.clientIdPrefix(),
                "clientIdPrefix"));
        String group = kafkaListener.containerGroup();
        ...
        String concurrency = kafkaListener.concurrency();
        ...
        resolveKafkaProperties(endpoint, kafkaListener.properties());

      // 设置 KafkaListenerContainerFactory
        KafkaListenerContainerFactory<?> factory = null;
        String containerFactoryBeanName = resolve(kafkaListener.containerFactory());
        ...
        endpoint.setBeanFactory(this.beanFactory);
        ...
    // 将endpoint 登记到 KafkaListenerEndpointRegistrar 中，前面一大段代码都是设置endpoint属性
    // KafkaListenerEndpointRegistrar特别重要，实现了InitializingBean方法
        this.registrar.registerEndpoint(endpoint, factory);
        if (StringUtils.hasText(beanRef)) {
            this.listenerScope.removeListener(beanRef);
        }
    }
```

###### 1.1.1.1.1.4、`KafkaListenerEndpointRegistrar`类`registerEndpoint`方法

```java
    public void registerEndpoint(KafkaListenerEndpoint endpoint, KafkaListenerContainerFactory<?> factory) {
        Assert.notNull(endpoint, "Endpoint must be set");
        Assert.hasText(endpoint.getId(), "Endpoint id must be set");
        // Factory may be null, we defer the resolution right before actually creating the container

    // 创建descriptor对象，里面相当于是kafkaListener的元信息
        KafkaListenerEndpointDescriptor descriptor = new KafkaListenerEndpointDescriptor(endpoint, factory);
        synchronized (this.endpointDescriptors) {
            if (this.startImmediately) { // Register and start immediately

        // 当startImmediately=true，则开始注册listenerContainer容器，具体参考：1.1.1.1.2中的endpointRegistry
                this.endpointRegistry.registerListenerContainer(descriptor.endpoint,
                        resolveContainerFactory(descriptor), true);
            }
            else {
                this.endpointDescriptors.add(descriptor);
            }
        }
    }
```

##### 1.1.1.1.2、`KafkaListenerEndpointRegistry`

###### 1.1.1.1.2.1、 `registerListenerContainer`

```java
public void registerListenerContainer(KafkaListenerEndpoint endpoint, KafkaListenerContainerFactory<?> factory,
            boolean startImmediately) {
        Assert.notNull(endpoint, "Endpoint must not be null");
        Assert.notNull(factory, "Factory must not be null");

        String id = endpoint.getId();
        Assert.hasText(id, "Endpoint id must not be empty");
        synchronized (this.listenerContainers) {
            Assert.state(!this.listenerContainers.containsKey(id),
                    "Another endpoint is already registered with id '" + id + "'");

      // 创建listenerContainer容器 参考1.1.1.1.2.2
            MessageListenerContainer container = createListenerContainer(endpoint, factory);
            this.listenerContainers.put(id, container);
            if (StringUtils.hasText(endpoint.getGroup()) && this.applicationContext != null) {
                List<MessageListenerContainer> containerGroup;
                if (this.applicationContext.containsBean(endpoint.getGroup())) {
                    containerGroup = this.applicationContext.getBean(endpoint.getGroup(), List.class);
                }
                else {
                    containerGroup = new ArrayList<MessageListenerContainer>();
                    this.applicationContext.getBeanFactory().registerSingleton(endpoint.getGroup(), containerGroup);
                }
                containerGroup.add(container);
            }
      // startImmediately在`InitializingBean`接口实现中设置startImmediately = true
            if (startImmediately) {
                startIfNecessary(container);
            }
        }
    }
```



###### 1.1.1.1.2.2、`createListenerContainer`

```java
protected MessageListenerContainer createListenerContainer(KafkaListenerEndpoint endpoint,
            KafkaListenerContainerFactory<?> factory) {

    //使用工场创建容器，参考1.1.1.1.2.3
        MessageListenerContainer listenerContainer = factory.createListenerContainer(endpoint);
        // 如果实现了InitializingBean，则调用afterPropertiesSet方法
        if (listenerContainer instanceof InitializingBean) {
            try {
                ((InitializingBean) listenerContainer).afterPropertiesSet();
            }
            catch (Exception ex) {
                throw new BeanInitializationException("Failed to initialize message listener container", ex);
            }
        }

        int containerPhase = listenerContainer.getPhase();
        if (listenerContainer.isAutoStartup() &&
                containerPhase != AbstractMessageListenerContainer.DEFAULT_PHASE) {  // a custom phase value
            if (this.phase != AbstractMessageListenerContainer.DEFAULT_PHASE && this.phase != containerPhase) {
                throw new IllegalStateException("Encountered phase mismatch between container "
                        + "factory definitions: " + this.phase + " vs " + containerPhase);
            }
            this.phase = listenerContainer.getPhase();
        }

        return listenerContainer;
    }
```

###### 1.1.1.1.2.3、`createListenerContainer`

```java
@Override
    public C createListenerContainer(KafkaListenerEndpoint endpoint) {
    // 创建容器实例，参考1.1.1.1.2.4
        C instance = createContainerInstance(endpoint);

        if (endpoint.getId() != null) {
            instance.setBeanName(endpoint.getId());
        }
        if (endpoint instanceof AbstractKafkaListenerEndpoint) {
      //配置endpoint的额外属性
            configureEndpoint((AbstractKafkaListenerEndpoint<K, V>) endpoint);
        }

        endpoint.setupListenerContainer(instance, this.messageConverter);
    // 初始化容器实例，参考1.1.1.1.2.5
        initializeContainer(instance, endpoint);

        return instance;
    }
```

###### 1.1.1.1.2.4、`createContainerInstance`

```java
@Override
    protected ConcurrentMessageListenerContainer<K, V> createContainerInstance(KafkaListenerEndpoint endpoint) {
        Collection<TopicPartitionInitialOffset> topicPartitions = endpoint.getTopicPartitions();
        if (!topicPartitions.isEmpty()) {
            ContainerProperties properties = new ContainerProperties(
                    topicPartitions.toArray(new TopicPartitionInitialOffset[topicPartitions.size()]));
            return new ConcurrentMessageListenerContainer<K, V>(getConsumerFactory(), properties);
        }
        else {
            Collection<String> topics = endpoint.getTopics();
            if (!topics.isEmpty()) {
                ContainerProperties properties = new ContainerProperties(topics.toArray(new String[topics.size()]));
                return new ConcurrentMessageListenerContainer<K, V>(getConsumerFactory(), properties);
            }
            else {
                ContainerProperties properties = new ContainerProperties(endpoint.getTopicPattern());
                return new ConcurrentMessageListenerContainer<K, V>(getConsumerFactory(), properties);
            }
        }
    }
```

###### 1.1.1.1.2.5、`initializeContainer`

配置容器的属性，比如rollback，ack模式等，至此就容器就配置完成了

```java
    protected void initializeContainer(C instance, KafkaListenerEndpoint endpoint) {
        ContainerProperties properties = instance.getContainerProperties();
        BeanUtils.copyProperties(this.containerProperties, properties, "topics", "topicPartitions", "topicPattern",
                "messageListener", "ackCount", "ackTime");
        if (this.afterRollbackProcessor != null) {
            instance.setAfterRollbackProcessor(this.afterRollbackProcessor);
        }
        if (this.containerProperties.getAckCount() > 0) {
            properties.setAckCount(this.containerProperties.getAckCount());
        }
        if (this.containerProperties.getAckTime() > 0) {
            properties.setAckTime(this.containerProperties.getAckTime());
        }
        if (this.errorHandler != null) {
            instance.setGenericErrorHandler(this.errorHandler);
        }
        if (endpoint.getAutoStartup() != null) {
            instance.setAutoStartup(endpoint.getAutoStartup());
        }
        else if (this.autoStartup != null) {
            instance.setAutoStartup(this.autoStartup);
        }
        if (this.phase != null) {
            instance.setPhase(this.phase);
        }
        if (this.applicationEventPublisher != null) {
            instance.setApplicationEventPublisher(this.applicationEventPublisher);
        }
        instance.getContainerProperties().setGroupId(endpoint.getGroupId());
        instance.getContainerProperties().setClientId(endpoint.getClientIdPrefix());
        if (endpoint.getConsumerProperties() != null) {
            instance.getContainerProperties().setConsumerProperties(endpoint.getConsumerProperties());
        }
    }
```

到此为止也只看到了容器的初始化完成，那么是在哪里开始连接kafka的broker并且消费数据的呢？

上面的代码中有一处可以看到`1.1.1.1.2.1`中

```java
if (startImmediately) {
    startIfNecessary(container);
}
```

但是要满足条件，applicationContext refresh完或者设置了listenerContainer开启了autoStart

```java
private void startIfNecessary(MessageListenerContainer listenerContainer) {
        if (this.contextRefreshed || listenerContainer.isAutoStartup()) {
            listenerContainer.start();
        }
}
```



还有其他地方吗？翻遍代码发现容器实现了接口`SmartLifecycle`

![image-20191129144939915](https://jyd01.oss-cn-beijing.aliyuncs.com/uPic/image-20191129144939915.png)

发现父类`AbstractMessageListenerContainer`实现了`start`方法

```java
@Override
    public final void start() {
        checkGroupId();
        synchronized (this.lifecycleMonitor) {
            if (!isRunning()) {
                Assert.isTrue(this.containerProperties.getMessageListener() instanceof GenericMessageListener,
                        () -> "A " + GenericMessageListener.class.getName() + " implementation must be provided");
                doStart();
            }
        }
    }
```

然后子类重写`doStart`方法

```java
@Override
protected void doStart() {
  if (!isRunning()) {
    checkTopics();
    ContainerProperties containerProperties = getContainerProperties();
    TopicPartitionInitialOffset[] topicPartitions = containerProperties.getTopicPartitions();
    if (topicPartitions != null && this.concurrency > topicPartitions.length) {
      this.logger.warn("When specific partitions are provided, the concurrency must be less than or "
                       + "equal to the number of partitions; reduced from " + this.concurrency + " to "
                       + topicPartitions.length);
      this.concurrency = topicPartitions.length;
    }
    setRunning(true);
        // 根据
    for (int i = 0; i < this.concurrency; i++) {
      KafkaMessageListenerContainer<K, V> container;
      if (topicPartitions == null) {
        container = new KafkaMessageListenerContainer<>(this, this.consumerFactory, containerProperties);
      }
      else {
        container = new KafkaMessageListenerContainer<>(this, this.consumerFactory,
                                                        containerProperties, partitionSubset(containerProperties, i));
      }
      String beanName = getBeanName();
      container.setBeanName((beanName != null ? beanName : "consumer") + "-" + i);
      if (getApplicationEventPublisher() != null) {
        container.setApplicationEventPublisher(getApplicationEventPublisher());
      }
      container.setClientIdSuffix("-" + i);
      container.setGenericErrorHandler(getGenericErrorHandler());
      container.setAfterRollbackProcessor(getAfterRollbackProcessor());
      container.setEmergencyStop(() -> {
        stop(() -> {
          // NOSONAR
        });
        publishContainerStoppedEvent();
      });
      container.start();
      this.containers.add(container);
    }
  }
}
```





### 1.1.3、 `KafkaMessageListenerContainer`

> `KafkaMessageListenerContainer` 该类封装了`KafkaConsumer` ，主要作用是连接kafka，并且poll数据，然后根据配置处理数据。

- run 方法

```java
@Override
        public void run() {
            this.consumerThread = Thread.currentThread();
            if (this.genericListener instanceof ConsumerSeekAware) {
                ((ConsumerSeekAware) this.genericListener).registerSeekCallback(this);
            }
            if (this.transactionManager != null) {
                ProducerFactoryUtils.setConsumerGroupId(this.consumerGroupId);
            }
            this.count = 0;
            this.last = System.currentTimeMillis();
      // 初始消费者线程绑定分区
            initAsignedPartitions();
            while (isRunning()) {
                try {
          // 拉取数据并且调用listener注解的业务方法处理数据
                    pollAndInvoke();
                }
                catch (@SuppressWarnings(UNUSED) WakeupException e) {
                    // Ignore, we're stopping
                }
                catch (NoOffsetForPartitionException nofpe) {
                    this.fatalError = true;
                    ListenerConsumer.this.logger.error("No offset and no reset policy", nofpe);
                    break;
                }
                catch (Exception e) {
                    handleConsumerException(e);
                }
                catch (Error e) { // NOSONAR - rethrown
                    Runnable runnable = KafkaMessageListenerContainer.this.emergencyStop;
                    if (runnable != null) {
                        runnable.run();
                    }
                    this.logger.error("Stopping container due to an Error", e);
                    wrapUp();
                    throw e;
                }
            }
            wrapUp();
        }
```

- pollAndInvoke 方法

```java
protected void pollAndInvoke() {
      // 非自动提交并且(ack == COUNT || COUNT_TIME)，处理co
            if (!this.autoCommit && !this.isRecordAck) {
        // 该方法会提交ack，但是会判断是否该线程消费者线程，还会判断ack mode.只有非手动提交的这里才会提交。并且注意，提交线程一但提交，因为是多线程消费，会出现消费顺序不一致。
                processCommits();
            }
          // seek 指定消费者偏移量
            processSeeks();
            checkPaused();
      // 开始拉取数据，指定超时时间
            ConsumerRecords<K, V> records = this.consumer.poll(this.pollTimeout);
            this.lastPoll = System.currentTimeMillis();
            checkResumed();
            debugRecords(records);
            if (records != null && records.count() > 0) {
                if (this.containerProperties.getIdleEventInterval() != null) {
                    this.lastReceive = System.currentTimeMillis();
                }
        // 调用@KafkaListener注解的业务代码，方法内部会判断是否有事务
                invokeListener(records);
            }
            else {
                checkIdle();
            }
        }
```



## 1.2 要点

1. 多线徎多记录消费顺序会不一致，手动提交偏移量会导致数据数据丢失
2. 一个@KafkaListener会启动concurrency个消费者；concurrency应该小于等于partitions数。

## 引用

[1] spring-kafka源码解析 https://blog.csdn.net/qq_26323323/article/details/84938892