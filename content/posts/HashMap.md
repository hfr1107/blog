---
title: "HashMap"
subtitle: ""
date: 2016-04-27T15:58:21+08:00
lastmod: 2016-04-27T15:58:21+08:00
draft: false
author: "山脚下的脚下山"
authorLink: ""
description: ""

tags: ["hashmap"]
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

# HashMap源码解析

## 构造方法

- ==无参构造方法==

```java
/**
 * Constructs an empty <tt>HashMap</tt> with the default initial capacity
 * (16) and the default load factor (0.75).
 */
public HashMap() {
  this.loadFactor = DEFAULT_LOAD_FACTOR; // all other fields defaulted
}
```

看方法注释可知：无参构造方法默认capacity = 16 、loadFactor = 0.75

- ==带有初始容量的构造方法==

```java
/**
 * Constructs an empty <tt>HashMap</tt> with the specified initial
 * capacity and the default load factor (0.75).
 *
 * @param  initialCapacity the initial capacity.
 * @throws IllegalArgumentException if the initial capacity is negative.
 */
public HashMap(int initialCapacity) {
  this(initialCapacity, DEFAULT_LOAD_FACTOR);
}
```

初始容量负数扔IllegalArgumentException异常，loadFactor = 0.75

- ==带有初始容量及负载因子的构造方法==

```java
/**
 * Constructs an empty <tt>HashMap</tt> with the specified initial
 * capacity and load factor.
 *
 * @param  initialCapacity the initial capacity
 * @param  loadFactor      the load factor
 * @throws IllegalArgumentException if the initial capacity is negative
 *         or the load factor is nonpositive
 */
public HashMap(int initialCapacity, float loadFactor) {
  if (initialCapacity < 0)
    throw new IllegalArgumentException("Illegal initial capacity: " +
                                       initialCapacity);
  if (initialCapacity > MAXIMUM_CAPACITY)
    initialCapacity = MAXIMUM_CAPACITY;
  if (loadFactor <= 0 || Float.isNaN(loadFactor))
    throw new IllegalArgumentException("Illegal load factor: " +
                                       loadFactor);
  this.loadFactor = loadFactor;
  this.threshold = tableSizeFor(initialCapacity);
}
```

```java
static final int MAXIMUM_CAPACITY = 1 << 30;
```



- ==另一个Map作为参数==

```java
/**
 * Constructs a new <tt>HashMap</tt> with the same mappings as the
 * specified <tt>Map</tt>.  The <tt>HashMap</tt> is created with
 * default load factor (0.75) and an initial capacity sufficient to
 * hold the mappings in the specified <tt>Map</tt>.
 *
 * @param   m the map whose mappings are to be placed in this map
 * @throws  NullPointerException if the specified map is null
 */
public HashMap(Map<? extends K, ? extends V> m) {
  this.loadFactor = DEFAULT_LOAD_FACTOR;
  putMapEntries(m, false);
}
```

## tableSizeFor

> 返回大于输入参数且最近的2的整数次幂的数。比如10，则返回16。
>
> 参考https://www.jianshu.com/p/cbe3f22793be

```java
/**
 * Returns a power of two size for the given target capacity.
 */
static final int tableSizeFor(int cap) {
  int n = cap - 1;
  n |= n >>> 1;
  n |= n >>> 2;
  n |= n >>> 4;
  n |= n >>> 8;
  n |= n >>> 16;
  return (n < 0) ? 1 : (n >= MAXIMUM_CAPACITY) ? MAXIMUM_CAPACITY : n + 1;
}
```

通过无符号右移再异或取到高位全是1，最后再加1.

## put

> 存放值

```java
public V put(K key, V value) {
    return putVal(hash(key), key, value, false, true);
}
```

### hash(key)

> 求key的hash值

```java
static final int hash(Object key) {
    int h;
    return (key == null) ? 0 : (h = key.hashCode()) ^ (h >>> 16);
}
```

**(h = key.hashCode()) ^ (h >>> 16)** 

为什么需要h >>> 16位？扰动函数，减轻了哈希冲突

### putValue

![image-20200710234635207](https://i.loli.net/2020/07/10/vTe7XaWgrAYqOJG.png)

### resize

![image-20200711002519369](https://i.loli.net/2020/07/11/6eHJD5iERcNdkUj.png)