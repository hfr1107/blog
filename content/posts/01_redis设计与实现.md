---
title: "01_redis设计与实现"
subtitle: ""
date: 2018-01-27T15:58:21+08:00
lastmod: 2018-01-27T15:58:21+08:00
draft: false
author: "山脚下的脚下山"
authorLink: ""
description: ""

tags: ["redis"]
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

# 《redis设计与实现》学习记录（一）

> 一直在使用redis，使用熟练，但是好像一直没有关注过底层如何实现，最近准备关注一下底层的数据结构，于是买了本《redis设计与实现》第二版，晚上睡前抽时间看看，让自己在脑海中对redis有一个更清晰的认识。以下内容是自己看书的一些记录。因此有些内容摘自书中。

## 数据结构

### 字符串

- redis自定义了自己的字符串数据结构。（SDS=简单动态字符串）

  ```c
  struct{
      int len;//所保存的字符数长度
      int free;//未使用字节数量
      char buf[];//用于保存字符串，并且使用‘\0’结尾，与c保持一致，方便使用c的部分函数
  }
  ```
- 优势

  - 获取字符串长度（STRLEN函数）时间复杂度为O(1)，因为有len这个属性。而C语言没有这个属性，要获取长度需要遍历数组。
  - 杜绝缓冲区溢出或者泄露：当字符串拼接或者添加时，C语言默认字符数组容量足够，而SDS会默认检查free是否足够。
    - 空间预分配：对字符串增加，如果SDS.len小于1M,分配free和len同样大小的空间；如果>1M，将分配1M的free空间。
    - 惰性空间释放：缩减SDS，并且立即释放内存，而是将释放大小增加到free空间。不用担心内存浪费，因为SDS提供了api在真正需要释放空间时执行。
    - 目的：减小频繁的内存分配，即减小了程序的时间开销，增加性能。
  - 二进制安全：C以‘\0’为结尾，如果存储二进制图片等数据会认为‘\0’即结束。但是SDS有一个len属性，会读取len属性大小（+1）的长度才会结束，即安全的二进制存储。
  - 兼容部分C语言函数：SDS同样以‘\0’结尾，即遵询了部分C的结构，可以重用部分C函数，不必重写。

### 链表

- 自定义链表结构：

  ```c
  typedef struct listNode{
      struct listNode *prev;//前置节点
      struct listNode *next;//后置节点
      void *value;//链表结点数据
  }listNode;
  
  typedef struct list{
      listNode *head;//头节点
      listNode *tail;//尾节点
      unsigned long len;//链表节点数量
      void *(*dup)(void *ptr);//节点复制函数
      void *(*free)(void *ptr);//节点释放函数
      int (*match)(void *ptr,void *key);//节点对比函数
  }list;
  ```

- 优势：

  - 双端链表：获取前置节点与后置节点时间复杂度O(1)，通过prev和next指针。
  - 无环：next=null即尾节点，prev=null即头节点
  - 链表长度计数器：len属性获取节点长度时间复杂度O(1)
  - 多态：可以根据value的类型为内置的三个函数指向具体类型的函数。如value是string,则三个函数为操作string的函数。

### 字典

- redis字典使用哈希表为底层实现。一个哈希表里有多个hash节点，一个节点保存一个k-v（键值对）

  ```c
  typedef struct dictht{ //dict hash table
      dictEntry **table;//哈希表 *数组*
      unsigned long size;//哈希表大小
      unsigned long sizemask;//hash table大小掩码，计算索引值,总等于size-1,用户计算键放于table哪个索引上
      unsigned long used;//hash table已使用节点大小
  }dictht;
  
  typedef struct dictEntry{
      void *key;//键
      union{
          void *val;
          uint64_tu64;
          int64_ts64;
      }v; //值
      struct dictEntry *next; //指向下个哈希表节点，形成链表。拉链表解决hash冲突。
  }
  
  typedef struct dict{
      dictType *type; //类型特定函数
      void *privdaa;//私有数据
      dictht ht[2]; // 哈希表，大小为2，一个存储，另一个用于rehash时
      in rehashidx; //rehash 索引，不rehash 值 = -1
  }
  ```

  ![image-20190319212810155](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-08-04/15:27:15/image-20190319212810155.png)

- type属性和privdata属性，用于不同类型设置不同的函数

- ht 大小为2，ht[1]只会在对ht[0]进行rehash时使用

- 使用了`链地址法`解决hash冲突dictEntry.next指针存储下一个节点

- rehash

  - 扩展操作：为ht[1]分配ht[0].used * 2的2^n
  - 收缩操作：为ht[1]分配ht[0].used 的2^n
  - 时机，以下任一个满足：
    - 服务器没有执行BGSAVE或者BGREWRITEAOF，并且load_factor>=1
    - 正在执行BGSAVE或者BGREWRITEAOF，并且load_factor>=5
    - load_factor = ht[0].used / ht[0].size
    - Load_facotr < 0.1自动执行收缩
  - rehash并不是一次性完成，而是多次，激进式完成。避免当数据量大时，计算量导致停止服务。
  - rehash时的查询先ht[0]再ht[1],新增直接操作ht[1]

### 跳跃表 

- 跳跃表（skiplist）是一种有序数据结构。平均O(logN)、最坏O(N)时间复杂度。redis使用跳跃表作为有序集成键的底层实现之一。

  ```c
  typedef struct zskiplistNode{
      struct zskiplistLevel{
          struct zskiplistNode *forward;//前进指针
          unsigned int span;//跨度
      }level[]; //层
      struct zskiplistNode *backward;
      double score;//分值
      robj *obj;
  }zskiplistNode;
  
  typedef struct zskiplist{
      struct skiplistNode *header,*tail;//头尾指针
      unsigned long length;
      int level;
  }
  ```

- 跳跃表是有序集合的底层实现之一

- `zskiplist`保存跳跃表信息，`zskiplistNode`保存节点信息

- 跳跃表按照分值大小排序

### 整数集合（intset）

- 整数集合是redis保存整数值的集合底层数据结构。

  ```
  typedef struct intset{
      uint32_t encoding;//编码方式 
      uint32_t length;//集合元素个数
      int8_t contents[];//保存的元素
  }intset;
  ```

- 虽然intset的content属性类型为int8_t，但是content并不保存int8_t类型的值，而是取决于encoding类型的值。

- 升级：当向contents添加一个类型比当前值的最大类型还大时，比如现在存放int16型的数据，但是下一个存放int32类型数据，那么intset集合会先进行`升级`。扩展contents的底层数据字节长度，再把之前的值改变成新的字节长度。最后更改encoding编码。因此intset添加元素的时间复杂度为O(N)

- 不支持降级

### 压缩列表

- 压缩列表是列表键及哈希键的底层实现之一，当列表键少量并且是小整数或者短字符时使用。

![image-20190322175139662](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-08-04/15:27:40/image-20190322175139662-6526059.png)

- zlbytes表示压缩列表占用内存总字节数
- zltail表示压缩列表表尾距离开始节点的偏移量
- zllen表示节点数量
- entry节点数据
- zlend标记压缩列表结尾

压缩列表节点数据结构，即上图的entry节点：

![image-20190322180325931](https://gitee.com/scemsjyd/static_pic/raw/master/uPic/2020-08-04/15:28:08/image-20190322180325931.png)

- 描述：
  - Previous_entry_length前一节点的长度，如果是< 254字节，使用1字节长保存，如果>=254字节，使用5字节保存，并且属性第一字节设置为OxFE=254。
  - encoding content内容的编码
  - content 真正保存的内容
- 影响 ：
  - 压缩列表会引起连锁更新：因为previous_entry_length保存了前一个节点的长度。如果介于250~254之前，新增一个节点在前面并且是大于254的，接下来的节点的previous_entry_length会调整为5字节，又会影响下一个节点，连锁反应。

## 对象

> 1. redis并不直接使用上面的提到的数据结构来构建数据库。而是使用上面提到的数据结构构建了五种redis对象：`字符串对象` `列表对象` `哈希对象` `集合对象` `有序集合对象`。
>
> 2. 使用对象的好处是可以对同一种对象底层使用不同的实现。并且根据对象类型执行不同的命令。优化对象在不同的场景下的使用效率。
>
> 3. redis对象实现了引用计数对内存进行回收。同时实现了对象的共享，以实现内存的节约。
>
> 4. redis对象带有访问时间记录信息，lru等属性，用于回收最近最少使用的对象。

```c
typedef struct redisObject{
  unsigned type:4; //对象类型
  unsigned encodeing:4; //编码
  void *ptr; //指向底层实现该对象的数据结构指针
}robj;
```

type值有5种类型常量，分别对应redis的5种对象。

| 类型常量     | 对象的名称   |
| ------------ | ------------ |
| REDIS_STRING | 字符串对象   |
| REDIS_LIST   | 列表对象     |
| REDIS_HASH   | 哈希对象     |
| REDIS_SET    | 集合对象     |
| REDIS_ZSET   | 有序集合对象 |

可以使用`type`命令返回redis对象的值类型

```lua
set msg "hello world"
type msg //返回string
```

### 编码和底层编码

> 对象的`ptr`指针指向了具体该对象的实现数据结构，而数据结构邮对象的`encoding`决定.

| 编码常量                  | 编码对象底层数据结构 | OBJECT ENCODING命令输出 |
| ------------------------- | -------------------- | ----------------------- |
| REDIS_ENCODING_INT        | long类型整数         | int                     |
| REDIS_ENCODING_EMBSTR     | embtr编码的SDS       | embstr                  |
| REDIS_ENCODING_RAW        | SDS                  | raw                     |
| REDIS_ENCODING_HT         | 字典                 | hashtable               |
| REDIS_ENCODING_LINKEDLIST | 双端列表             | linkedlist              |
| REDIS_ENCODING_ZIPLIST    | 压缩列表             | ziplist                 |
| REDIS_ENCODING_INTSET     | 整数集合             | intset                  |
| REDIS_ENCODING_SKIPLIST   | 跳跃表               | skiplist                |

### 字符串对象

> 字符串对象编码可以是int、raw、embstr。
>
> 1. 如果字符串对象保存的值类型为整数，那么encoding=REDIS_ENCODING_INT
> 2. 如何值为字符串值，并且字符串值length > 32 byte 那么encoding = REDIS_ENCODING_RAW。
> 3. 相反如果length <= 32 byte encoding = REDIS_ENCODING_EMBSTR
> 4. 类型的编码不是永恒不变的，当原来保存的是int值，但是使用了`APPEND`函数添加了字符串，那么类型将变成raw。为什么不是embstr，是因为embstr没有修改函数，只有先将其转为raw才能执行修改操作。



### 列表对象

> 列表对象的编码可以是`ziplist`或者`linkedlist`
>
> 使用ziplist的条件如下：
>
> 1. 列表对象保存的所有字符串元素长度 < 64 byte
> 2. 列表对象保存的元素数量 < 512个
>
> 除此之外都使用linkedlist结构。
>
> 可以修改配置：`list-max-ziplist-value` 和`list-max-ziplist-entries`来修改上面的条件



### 哈希对象

> 哈希对象的编码是`ziplist`和`hashtable`
>
> 使用`ziplist`条件如下：
>
> 1. 所有键值对的length < 64 byte
> 2. 所有键值对的数据< 512
>
> 除此之外使用`hashtable`
>
> 可以修改配置：`hash-max-ziplist-value` 和`hash-max-ziplist-entries`来修改上面的条件



### 集合对象

> 集合对象使用的编码是：`intset`和`hashtable`
>
> 使用`intset`条件如下：
>
> 1. 集合对象保存的所有元素都是整数
> 2. 集合对象保存的元素个数 <= 512
>
> 除此之外使用`hashtable`
>
> 可以修改配置：`set-max-intset-value`来修改上面的条件



### 有序集合对象

> 有序集合对象编码是：`ziplist`和`skiplist`
>
> 使用`ziplist`条件如下：
>
> 1. 有序集合保存元素个数 < 128
> 2. 有序集合保存的所有元素长度 < 64 byte
>
> 除此之外使用`skiplist`编码
>
> 可以修改配置：`zset-max-ziplist-value` 和`zset-max-ziplist-entries`来修改上面的条件