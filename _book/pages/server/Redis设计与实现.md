# Redis设计与实现

今天开始学习Redis，我对Redis的学习计划是先学习《Redis设计与实现》（基于Redis3.0开发版）学习Redis的基本原理，再结合极客时间Redis课程与源码学习最新版本，比较最新版本与旧版本的差异。

这篇文章主要是 《Redis设计与实现》黄健宏版 这本书的学习笔记，会附带一些我读书过程中不理解的知识点的补充，这些补充内容我会单独标注出来，方便后面的读者阅读。



## 一、数据结构

我们先列举下Redis中的五种数据类型。这部分内容比较简单，可以自行看网上的入门文章了解

| 数据类型  | 类型解释                           | 查询命令            | 插入命令    | 删除命令            |
| --------- | ---------------------------------- | ------------------- | ----------- | ------------------- |
| String    | 简单动态字符串                     | get                 | set         | del                 |
| Hash      | 散列类型，可以单独操作子字段       | hget                | hset        | hdel                |
| List      | 链表类型                           | lrange              | lpush,rpush | lpop,rpop,lrem,rrem |
| Set       | 无序集合                           | smembers            | sadd        | Srem                |
| SortedSet | 有序集合，会给元素一个分数进行排序 | zscore,zrange,zrank | zadd        | Zrem                |

Redis支持了这五种数据类型，覆盖了绝大部分的使用场景，也是Redis能火起来的重要原因之一。那么这几种数据类型都是什么底层数据结构在支撑，才能让Redis运行的这么快呢？



### 1.1 简单动态字符串

Redis使用C语言编写，但是没有直接使用C语言中传统的字符串表示，主要是考虑到C语言传统字符串的几个严重的缺点：

- 性能较差。因为使用数组存储，需要遍历数组直到空字符'\0'才能获取字符串的长度。
- 安全性不足，容易因为开发者操作不当出现字符串数组缓冲区溢出。

Redis构建了一种名为simple dynamic string(SDS)的抽象类型，用作Redis的默认字符串表示。sds.h/sdshdr结构类型如下

```c
struct sdshdr {
  int len;   // 记录buf数组中已使用字节的数量，等于SDS所保存字符串的长度
  int free;  // 记录buf数组中未使用字节的数量
  char buf[]; // 字节数组，用于保存字符串
}
```

可以看到相比C中的字符串，新增了len和free两个字段。举个栗子，假设一个sdshdr存了Redis这个字符串（没有空白空间），那么buf数组的长度就是Redis的长度加一个空字符的长度，为6。而len是redis的长度5，free为0。

sds设计的巧妙之处在于：

- sds中的buf数组与C语言字符串类型结构保持一致的好处是可以复用一部分C字符串函数。

- 通过增加len属性，sds不需要遍历字符串O(n)，通过O(1)时间就可以获取字符串的长度。基于len属性，sds在进行字符串修改时，会先检查sds的空间是否满足修改所需的大小，不满足时会自动扩容。这样也避免了c语言字符串的缓冲区溢出的问题。

- 通过增加free参数，sds可以实现未使用空间的概念，减少修改字符串时带来的内存重分配次数（内存重分配涉及复杂算法，甚至系统调用）。

C语言字符数组的长度总是等于字符串长度+1，这样的话一个C字符串从5字符扩张到10字符需要内存分配5次。而通过未使用空间，sds实现了**空间预分配**和**惰性空间释放**两种优化策略，解决了这个问题。

**空间预分配**：当我们修改sds，并且**需要对sds进行空间扩展**的时候，除了必要的空间外会给sds分配额外的未使用空间。如果对sds修改以后，len值小于1MB，那么分配和len同样大小的未使用空间；如果超过1MB，那么分配1MB的未使用空间。

> 比如初始sds，len=10，free=10，当需要修改变为len=15时，因为free=10大于扩张需要的5字符，这时候就不需要内存分配，直接赋值就行了。当再次修改变为len=25时，就会再触发一次内存分配变为len=25, free=25.

**惰性空间释放**：用于优化sds的字符串缩短操作。当sds需要缩短sds保存的字符串时，程序并不立即使用内存重分配回收缩短后多出来的字节，而是先用free属性记录下来，等待将来使用。同时sds也提供了api让我们真正释放sds的未使用空间。

sds的字符串数组是**二进制安全**的，可以存文本或二进制数据。这是因为sds只使用len判断长度，所以数据怎么存，取出来就是怎么样。所以sds可以存储空字符'\0'。



### 1.2 链表

每个链表节点使用一个adlist.h/listNode结构来表示。redis的链表类型使用的是双向链表。

```c
typedef struct listNode {
	struct listNode *prev;
	struct listNode *next;
	void *value;
}listNode;

typedef struct list {
	listNode *head;						 // 表头节点
	listNode *tail;						 // 表尾节点
	unsigned long len;         // 链表的节点数量
	void *(*dup)(void *ptr);   // 节点值复制
	void *(*free)(void *ptr);  // 节点值释放
	void *(*match)(void *ptr,void *key); //节点值对比
}
```



### 1.3 散列/字典

字典中，每个键都是独一无二的。一个键和一个值进行关联。Redis使用的C语言并没有内置这种数据类型，Redis构建了自己的字典实现。

```
// 哈希表实现  dict.h/dictht
typedef struct dictht {
      // hash 表数组
      dictEntry **table;
      // hash表的大小
      unsigned long size;
      // hash表大小掩码，用于计算索引值，总是等于size-1
      unsigned long sizemask;
      // 已有节点的数量
      unsigned long used;
}dictht;

// 哈希表节点
typedef struct dictEntry {
     void *key;   //键
     union{
          void *val;
          uint64_t u64;
          int64_t s64;
     } v;         // 值
     struct dictEntry *next;  //下一个节点，构成链表
} dictEntry;

// 字典实现 dict.h/dict
typedef struct dict {
	// 类型特定函数
	dictType *type;
	// 私有数据
	void *privdata;
	// 哈希表
	dictht ht[2];
	// rehash索引
	int rehashidx;
}dict;

```

dictEntry中的next属性，可以将多个哈希值相同的键值对链接在一起，解决键冲突的问题。

dict的type属性是一个指向dictType结构的指针，每个dictType结构保存了一簇用于操作指定类型键值对的函数，Redis会为用途不同的字典设置不同的类型特定函数。

ht属性是一个包含两个哈希表的数组，一般只用第一个，第二个哈希表只有在对第一个进行rehash时使用。rehashidx是一个rehash的标志位，当没有进行rehash时值为-1。



**Rehash**：随着操作执行，哈希表的键值对会逐渐增多或者减少，为了让哈希表的负载因子维持在合理范围内，程序需要对哈希表的大小进行相应扩展或收缩。

扩展的条件有：

- 服务器目前没有在执行BGSAVE或BGREWRITEAOF，并且哈希表的负载因子大于等于1
- 服务器目前正在执行BGSAVE或BGREWRITEAOF，并且哈希表的负载因子大于等于5

收缩的条件是：负载因子小于0.1

> 负载因子 = 哈希表已保存节点数量 / 哈希表大小

Redis的rehash采用的是渐进式rehash的方式。步骤如下：

1. **为ht[1] 分配空间**
2. **将rehashidx 初始化为0 ，代表rehash 工作正式开始。**
3. **每次字典进行删除、查找、更新操作时， 会同时在两个hash表上进行（先查找ht[0], 如果没找到，再去查找ht[1]）。 进行添加操作时，会直接添加到ht[1]。**
4. **在进行每次增删改查操作时， 会同时把ht[0] 在rehashidx 索引上的所有键值对都rehash到ht[1]上， 完成后 rehashidx 加1.**
5. **当ht[0] 所有元素都被复制到ht[1]， 设置rehashidx 的值为-1 。**
6. **回收 ht[0]。**

渐进式rehash的过程中，字段会同时使用两个哈希表。所以字段的删除、查找、更新等操作会在两个哈希表上进行，而新添加到字典的key一律只保存到ht[1]中，不加入到ht[0]中。





### 1.4 跳跃表

跳跃表（后文又称跳表）是一种有序数据结构，通过在多个节点中维持多个指向其他节点的指针，从而达到快速访问节点的目的。跳跃表支持平均O(logN)、最坏O(N)复杂度的节点查找，还可以通过顺序操作来批量处理节点。它的最大优势是原理简单、容易实现、方便扩展、效率更高。因此在一些热门的项目里用来替代平衡树。Redis的有序集合SortedSet（也称zset）就使用了跳跃表。

Redis跳跃表实现由redis.h/zskiplistNode和redis.h/zskiplist两个结构定义。

```c
typedef struct zskiplistNode {
    // 后退指针
    struct zskiplistNode *backward;
    // 分值
    double score;
    // 成员对象
    robj *obj;
    // 层
    struct zskiplistLevel {
        // 前进指针
        struct zskiplistNode *forward;
        // 跨度
        unsigned int span;
    } level[];
} zskiplistNode;

typedef struct zskiplist {
    // 表头节点和表尾节点
    struct zskiplistNode *header, *tail;
    // 表中节点的数量
    unsigned long length;
    // 表中层数最大的节点的层数
    int level;

} zskiplist;
```

先给一张跳跃表的示意图，我们边看示意图边分析结构。

![img](https://raw.githubusercontent.com/oubindo/ImageBed/master/img/09c4bcae0e8647038fcadd43a7bf8fb1%7Etplv-k3u1fbpfcp-watermark.awebp)

每个zskiplistNode都有几个关键属性：

1.level数组

level数组就是层高。level数组包含多个元素，每个元素都包含一个指向其他节点的指针，程序可以通过这些层来加快访问其他节点的速度。一般来说层数量越多，访问其他节点速度越快。

每次创建一个新的跳跃表节点的时候，程序会根据幂次定律随机生成一个1和32之间的值作为level数组的大小。

> level数组的随机方式可以参考 https://www.cyningsun.com/06-18-2018/skiplist.html 这篇文章

2.前进指针forward

每层都有一个指向表尾方向的前进指针forward，用于从表头向表尾方向访问节点。

3.跨度span

跨度span参数用于记录两个节点之间的距离。跨度越大，距离越远。跨度与遍历无关，遍历主要使用前进指针，而跨度实际上是用来计算排位的。在查找过程中把经过的所有层的跨度累计起来，得到的结果就是目标节点在跳跃表中的排位。

4.后退指针backward

后退指针用于从表尾向表头方向访问节点，后退指针每次只能后退至前一个节点。

5.分值score和成员obj

分值是一个double类型的浮点数，跳跃表中所有节点都按分值从小到大来排序。成员对象obj是一个指针，指向一个sds字符串对象。



多个跳跃表节点就可以组成一个跳跃表。zskiplist维护了跳表的首尾节点，长度和最高层级。



### 1.5 整数集合

整数集合intset是redis的set类型的底层实现之一，当一个集合只包含整数值元素，并且集合元素不超过512时，就会使用intset作为set的底层实现。（不满足这两个条件，就会使用hash表作为底层实现）

整数集合可以保存类型为int16_t、int32_t或int64_t的整数值，并且保证集合中不会出现重复元素。整数集合用intset.h/intset表示。

```c
typedef struct intset {
	// 编码方式
	uint32_t encoding;
	// 集合包含的元素数量
	uint32_t length;
	// 保存元素的数组
	int8_t contents[];
}intset;
```

contents数组中每个项在数组中按值的大小从小到大有序排列。

虽然contents数组声明是int8_t类型的数组，但是contents数组并不保存任何int8_t类型的值，contents数组的真正类型取决于encoding属性的值。

- 如果encoding属性值为INTSET_ENC_INT16，contents数组为int16_t类型
- 如果encoding属性值为INTSET_ENC_INT32，contents数组为int32_t类型
- 如果encoding属性值为INTSET_ENC_INT64，contents数组为int64_t类型

这里大家就有疑问了，我们在给整数集合中添加值的时候，并没有手动指定他的类型，也没有限制add进去的数值的int类型，那整数集合是怎么确定类型的呢？这里就涉及到整数集合的**升级机制**。

**升级机制**：每当我们将一个新元素添加到整数集合中，并且新元素的类型比整数集合现有所有元素类型都要长时，整数集合需要先进行升级，才能将新元素添加到整数集合中。

升级整数集合并添加新元素分为三步进行：

1) 根据新元素类型，扩展整数集合底层数组的空间大小，并为新元素分配空间
2) 将底层数组现有所有元素都**转换为与新元素相同的类型**，并将类型转换后的元素放在正确的位上。在这个过程中要维持数组有序性不变。
3) 将新元素加到底层数组里面。

当然，升级是有好处的。首先他对外屏蔽了int的几种类型，使得我们使用的时候可以无脑塞入int数据，提升了灵活性；其次，升级操作可以确保只有在用户有需要的时候，才提升到更高的类型，避免直接使用int64_t数组，节省了空间。

当然，整数集合不支持降级，避免了数据变更带来内存空间的经常性变更。



### 1.6 压缩列表

压缩列表ziplist是列表键和哈希键的底层实现之一。当一个列表键只包含少量列表项，并且每个列表项要么就是小整数值，要么就是长度比较短的字符串时，redis就是使用压缩列表来做列表键的底层实现。

压缩列表是为了节约内存而开发的，由一系列特殊编码的连续内存块组成的顺序型数据结构。可以包含任意多个节点，每个节点可以保存一个字节数组或者一个整数值。压缩列表的组成结构如下

![image-20211024153703545](https://raw.githubusercontent.com/oubindo/ImageBed/master/img/image-20211024153703545.png)

每个压缩列表节点可以保存一个字节数组或者一个整数值，每个节点都由previous_entry_length, encoding, content三个部分组成。

![image-20211024173251489](https://raw.githubusercontent.com/oubindo/ImageBed/master/img/image-20211024173251489.png)

但是这里要注意，content并不是真正意义上的模型参数，而是我们抽象出来的部分。我们可以看下数据模型，定义在ziplist.c里面

```c
typedef struct zlentry {
    unsigned int prevrawlensize; //上个节点的previous_entry_length的长度
    unsigned int prevrawlen;     // 上个节点的previous_entry_length的内容
    unsigned int lensize;        // 当前节点的encoding的长度，string有1，2，5，int有1
    unsigned int len;            // 当前节点的content的长度，string的长度或者是int的位数
    unsigned int headersize;     // prevrawlensize + lensize
    unsigned char encoding;      // ZIP_STR_* or ZIP_INT_*
      
    unsigned char *p;            // 当前节点的首地址
} zlentry;
```

**1.previous_entry_length**

previous_entry_length自身以字节为单位，记录压缩列表中前一个节点的长度。如果前一节点的长度小于254字节，那么previous_entry_length属性长度为1字节；如果前一节点长度大于等于254字节，那么previous_entry_length属性长度为5字节。其中第一字节会被设置为0xFE，后面的四个字节保存前一节点的长度。

previous_entry_length主要拿来干什么用呢？主要是为了在当前节点获得前一个节点首位的偏移地址，便于从表尾往表头遍历。

**2.encoding**

encoding属性记录节点的content属性所保存数据的类型和长度。有两种情况：

- 一字节、两字节或五字节，值的最高位为00，01或10的是字节数组编码。这种编码表示节点的content属性保存着字节数组。数组的长度为编码除去最高两位之后的其它位记录。
- 一字节长，值的最高位以11开头的是整数编码，表示节点的content属性保存着整数值。整数值的类型和长度由编码除去最高两位之后的其它位记录。

**3.content**

content并不是节点真正意义上的属性，但是他负责保存节点的值。可以是字节数组或整数，值的类型和长度由节点的encoding属性决定。



**连锁更新**

连锁更新基于previous_entry_length的两种长度机制：

- 如果前一节点的长度小于254字节，那么previous_entry_length属性长度为1字节
- 如果前一节点长度大于等于254字节，那么previous_entry_length属性长度为5字节

压缩列表中恰好有多个连续的，长度介于250字节至253字节之间的节点，此时在他最前面插入一个大于254字节的节点，就会连续触发后面节点的previous_entry_length的长度变更，称为连续更新。

连续更新看起来比较可怕，但是因为触发的时机比较苛刻，所以并不会造成多大的性能问题。



## 二、对象

上面我们介绍了Redis用到的主要数据结构，比如简单动态字符串sds，链表，字典，压缩列表，整数集合，redis并没有直接使用这些数据结构，而是基于这些数据结构创建了一个对象系统，这个系统包含了字符串对象，列表对象，哈希对象，集合对象和有序集合对象五种类型的对象，这样就可以灵活的使用数据结构，优化使用效率。

Redis的对象系统还实现了基于引用计数技术的内存回收和对象共享机制，当程序不使用某对象的时候，内存就会被释放；也可以在适当条件下，让多个数据库键共享一个对象来节约内存。

Redis的对象还带有访问时间记录信息，可以用于计算数据库键的空转时长，在服务器启用了maxmemory功能的情况下，空转时长较大的键可能被优先删除。



### 2.1 对象定义

对象定义在redisObject结构中

```
typedef struct redisObject {
    unsigned type:4;
    unsigned encoding:4;
    unsigned lru:LRU_BITS; /* LRU time (relative to global lru_clock) or
                            * LFU data (least significant 8 bits frequency
                            * and most significant 16 bits access time). */
    int refcount;
    void *ptr;
} robj;
```

**1.类型参数type**

type属性记录了对象的类型，这个属性值可以是REDIS_STRING, REDIS_LIST, REDIS_HASH, REDIS_SET, REDIS_ZSET五个常量之一，也对应我们上面提到的五种数据类型。

> redis的键总是字符串，值可能是五种数据类型之一。后面我们讲到“字符串键”、“列表键”的时候，其实是在说这个键值对的值的类型。

**2.编码encoding**

encoding属性记录了对象所使用的的编码，也就是这个对象使用了什么数据结构作为对象的底层实现。这个值可以是下表的常量中的其中之一。

![image-20211030094646350](https://raw.githubusercontent.com/oubindo/ImageBed/master/img/image-20211030094646350.png)

每种类型的对象都至少使用了两种不同的编码。

![image-20211030094817895](https://raw.githubusercontent.com/oubindo/ImageBed/master/img/image-20211030094817895.png)

通过encoding属性来设定编码，而不是为特定类型的对象关联一种固定的编码，这样就可以根据不同的使用场景来设置不同的编码，极大的提升了Redis的灵活性和效率，优化了对象在某一场景下的效率。

后面介绍Redis的五种不同类型的对象，说明这些对象使用的编码方式及转换编码的条件。



###2.2 字符串对象 

字符串对象的编码可以是int，raw或者embstr。

- int：字符串对象保存的是整数值，并且这个整数值可以用long类型表示
- raw：字符串对象保存的是一个长度大于32字节的字符串值，用sds保存，编码为raw
- embstr：字符串对象保存的是一个长度小于等于32字节的字符串值，用sds保存，编码为embstr

embstr比raw编码的好处是，创建和释放字符串对象都只需要一次内存操作，而raw需要调用两次；并且embstr编码的字符串所有数据都保存在连续内存中，所以能很好地利用缓存。

编码转换：int和embstr编码在条件满足情况下可以转换为raw

- Int->raw：我们操作完后，对象不再是整数值，而是字符串
- embstr->raw：对embstr进行任何修改时

注意，字符串对象是redis五种类型对象中唯一会被其他四种对象嵌套的对象。



### 2.3 列表对象

列表对象的编码可以是ziplist或linkedlist。

- ziplist：列表对象保存的所有字符串元素的长度都小于64字节；列表对象保存的元素数量小于512
- linkedlist：不满足上述条件

当数据不满足ziplist的条件时，编码就会转换为linkedlist。



### 2.4 哈希对象

哈希对象的编码可以是ziplist或者hashtable。

ziplist编码的哈希对象使用压缩列表作为底层实现，当有新的键值对加入到哈希对象时，程序会先将保存了键的压缩列表节点推入到压缩列表表尾，然后再将保存了值的压缩列表节点推入到压缩列表表尾，所以他们相当于是两个不同的节点紧靠在一起。

- ziplist: 哈希对象保存的所有键值对的键和值的字符串长度都小于64字节；哈希对象保存的键值对数量小于512个
- hashtable: 不满足上述条件

当数据不满足ziplist的条件时，编码就会转换为hashtable



### 2.5 集合对象

集合对象的编码可以是intset或者hashtable

hashtable编码的集合对象使用字典作为底层实现，每个键都是一个字符串对象，每个字符串对象包含了一个集合元素，而值全部被设置为null。

- intset: 集合对象保存的所有元素都是整数值；元素数量不超过512个
- hashtable：不满足上述条件



### 2.6 有序集合对象

有序集合的编码可以是ziplist或者skiplist。

ziplist编码的有序集合对象使用压缩列表作为底层实现，每个元素使用两个紧挨在一起的压缩列表节点来保存，第一个节点保存元素的成员，第二个元素保存元素的分值。所有元素在压缩列表中从小到大排列。

skiplist编码的有序集合对象使用zset结构作为底层实现，一个zset结构同时包含一个字典和一个跳跃表

```c
typedef struct zset {
	zskiplist *zsl;
	dict *dict;
}
```

zset结构中的zsl跳跃表按从小到大保存所有元素，而dict字典为有序集合创建了一个从成员到分值的映射，字典中的每个键值对都保存了一个集合元素。有了字典，就可以用O(1)复杂度查找给定成员的分值。

编码转换：

- ziplist：元素数量小于128；保存的元素成员的长度都小于64字节
- skiplist：不满足上述条件





### 2.7 内存回收

对象的引用计数信息由redisObject结构的refcount属性记录，随着使用状态不断变化。

- 创建新对象时，引入计数初始化为1
- 被新对象使用时，引用计数赠一；反正减一
- 当引用计数变为0时，释放内存

主要有三个api用于处理引用计数

- incrRefcount
- decrRefcount
- resetRefcount



### 2.8 对象共享

当两个键的值完全一样时，会在现有的对象上新增一个引用，而不是新增一个一模一样的对象。

redis会共享0-9999的字符串对象



### 2.9 空转时长

对象的空转时长由redisObject结构的lru属性处理，这个属性记录了对象最后一次被命令程序访问的时间。如果服务器打开了maxmemory选项，并且算法为volatile-lru或者allkeys-lru，这样当服务器占用的内存超过maxmemory选项设置的上限值时，空转时长较高的键会优先被释放



## 三、单机数据库的实现

### 3.1 数据库

Redis服务器将所有数据库都保存在服务器状态redis.h/redisServer结构的db数组中，每项都是一个redis.h/redisDb结构。单机状态下redis服务器会默认创建16个数据库，而集群模式下只能有一个数据库。

```c
struct redisServer {
	redisDb *db;                    /* 一个数组，保存着服务器中所有数据库 */
	int dbnum;                      /* 保存着服务器的数据库数量 */
  dict *expires;                  /* 保存了数据库键的过期时间 */
	// ...
}

typedef struct redisDb {
	dict *dict;                     /* 数据库键空间，保存着数据库中的所有键值对 */ 
}
```

数据库键空间的值可以是字符串对象，列表对象，哈希表对象，集合对象和有序集合对象中的任何一种redis对象。



### 3.2 过期时间

redisDb结构的expires字典保存了所有键的过期时间。过期时间字典的键是一个指针，指向键空间的某个键对象，而值是一个long long类型的整数，这个整数保存了键所指向的数据库键的过期时间戳。

PEXPIRTAT命令可以设置键的过期时间，PERSIST命令可以解除键和值在过期字典中的关联。TTL命令以秒为单位返回键的剩余生存空间，而PTTL命令则以毫秒为单位返回键的剩余生存时间

程序判定一个指定键过期的步骤：

- 检查给定键是否存在于过期字典，如果存在，则取得键的过期时间
- 检查当前UNIX时间戳是否大于键的过期时间，如果是的话，那么键已经过期，否则键未过期

如果一个键过期了，它是什么时候会被删除呢？这个问题对应着三种不同的删除策略：

- 定时删除：在设置键过期时间同时，创建一个定时器，让定时器在键过期时间来临时，立即执行对键的删除操作
  - 定时删除的缺点是创建定时器和删除过期键需要耗费较高的CPU时间。创建定时器需要用到Redis的时间事件，而时间事件的实现方式-无序链表查找事件的时间复杂度为O(n)。
- 惰性删除：放任键过期不管，而是在获取键的时候判断键是否过期，如果过期的话就删除，否则返回
  - 惰性删除的优点是节省CPU时间，但是浪费内存
- 定期删除：每隔一段时间，程序就对数据库进行一次检查，删除里面的过期键。至于删除多少过期键，以及检查多少数据库，由算法决定
  - 定期删除是上面两种删除方式的折中，但是难以确定操作执行的时长和频率。



Redis服务器实际使用的是惰性删除和定期删除两种策略。

- 惰性删除：所有读写数据库的Redis命令在执行之前都会调用redis.c/expireIfNeeded函数对输入键进行检查，如果过期了就会将输入键从数据库中删除。
- 定期删除：过期键的定期删除策略由redis.c/activeExpireCycle函数实现，这个函数周期性被调用，它会在规定的时间中分多次遍历服务器中的各个数据库，从数据库的expires字段随机检查一部分键的过期时间并删除过期键。



### 3.3 RDB持久化

由于Redis是内存数据库，所以如果不想办法将内存中的数据库状态保存到磁盘中，那么一旦服务器进程退出，服务器中的数据库数据也会消失不见。为了解决这个问题，Redis提供了RDB持久化功能，这个功能可以把某个时间点的数据库状态保存到一个RDB文件中。

RDB持久化生成的RDB文件是一个经过压缩的二进制文件，通过该文件可以还原生成RDB文件时的数据库状态。

Redis提供了SAVE和BGSAVE两个命令来生成RDB文件，SAVE和BGSAVE的区别是**BGSAVE会派生出一个子进程**，然后由子进程负责创建RDB文件，父进程继续处理命令请求。而使用SAVE后，主进程会被阻塞，只有生成完才能继续使用。

Redis载入RDB的工作是在服务器启动时自动执行的，所以Redis并没有专门用于载入RDB文件的命令。并且，如果服务器开启了AOF持久化功能，会优先使用AOF文件来还原数据库。

整个RDB文件的格式如下

```
----------------------------# RDB 是一个二进制文件。文件里没有新行或空格。
52 45 44 49 53              # 魔术字符串 "REDIS"
00 00 00 03                 # RDB 版本号，高位优先。在这种情况下，版本是 0003 = 3
---------------------------- 选择数据库
FE 00                       # FE = code 指出数据库选择器. 数据库号 = 00
----------------------------# 键值对开始
FD $unsigned int            # FD 指出 "有效期限时间是秒为单位". 在这之后，读取4字节无符号整数作为有效期限时间。
$value-type                 # 1 字节标记指出值的类型 － set，map，sorted set 等。
$string-encoded-key         # 键，编码为一个redis字符串。
$encoded-value              # 值，编码取决于 $value-type.
----------------------------
FC $unsigned long           # FC 指出 "有效期限时间是豪秒为单位". 在这之后，读取8字节无符号长整数作为有效期限时间。
$value-type                 # 1 字节标记指出值的类型 － set，map，sorted set 等。
$string-encoded-key         # 键，编码为一个redis字符串。
$encoded-value              # 值，编码取决于 $value-type.
----------------------------
$value-type                 # 这个键值对没有有效期限。$value_type 保证 != to FD, FC, FE and FF
$string-encoded-key
$encoded-value
----------------------------
FE $length-encoding         # 前一个数据库结束，下一个数据库开始。数据库号用长度编码读取。
----------------------------
...                         # 这个数据库的键值对，另外的数据库。
FF                          ## RDB 文件结束指示器
8 byte checksum             ## 整个文件的 CRC 32 校验和。
```

针对不同的value类型，redis会选择不同的编码方式。

1. 字符串对象

type为REDIS_RDB_TYPE_STRING, 编码可以是REDIS_ENCODING_INT（又分为INT8， INT16，INT32三种）或者REDIS_ENCODING_RAW。使用REDIS_ENCODING_RAW编码的时候，根据字符串长度是否大于20字节，会有压缩和不压缩两种方法来保存字符串。压缩主要是使用LZF算法进行。

保存格式为：| REDIS_RDB_ENC_LZF | compressed_len | origin_len | compressed_string |

2. 列表对象

type为REDIS_RDB_TYPE_LIST, 编码为REDIS_ENCODING_LINKEDLIST。

保存格式为：| list_length | item1 | item2 | ... | itemN |

3. 集合对象

Type值为REDIS_RDB_TYPE_SET, value编码为REDIS_ENCODING_HT。

保存格式为：| set_size | item1 | item2 | ... | itemN |。每个item的格式为 | length | raw |

4. 哈希表对象

type为REDIS_RDB_TYPE_HASH， value为REDIS_ENCODING_HT。格式为| ht_size | item1 | item2 | ... | itemN |。每个item的格式为 | key | value |

5. 有序集合对象

type为REDIS_RDB_TYPE_ZSET, value为REDIS_ENCODING_SKIPLIST。保存格式为| zset_size | item1 | item2 | ... | itemN |。每个item的格式为 | score | raw |

6. IntSet编码的集合，Ziplist编码的列表，哈希表或有序集合

这些都是先转换为字符串对象，在保存到RDB文件中。



### 3.4 AOF持久化

AOF（Append Only File）是通过保存Redis服务器执行的写命令来记录数据库状态的方式。AOF的实现可以分为命令追加、文件写入、文件同步三个步骤。

1. 命令追加

当AOF持久化功能打开状态时，服务器在执行完一个写命令以后，会以协议格式将被执行的写命令追加到服务器的aof_buf缓冲区的末尾。

2. 文件写入与同步

Redis的服务器进程就是一个事件循环，这个循环中的文件事件负责接受客户端的命令请求及发送命令回复，而时间事件则负责执行需要定时运行的函数。服务器在处理文件事件时可能会执行写命令，使得一些内容被追加到aof_buf缓冲区里面，所以每次结束一个事件循环之前，他都会调用flushAppendOnlyFile函数，考虑是否要将aof_buf缓冲区写入到aof文件里面。伪代码类似于

```c
while True:
	processFileEvents()  // 处理文件事件
  processTimeEvents()  // 处理时间事件
  flushAppendOnlyFile() // 考虑是否刷新aof
```

flushAppendOnlyFile函数的行为由服务器配置appendfsync选项的值来决定。

- always：将aof_buf缓冲区所有内容**写入并同步**到aof文件
- everysec：将aof_buf缓冲区所有内容**写入**到aof文件，如果上次同步aof文件的时间距离现在超过了一秒钟，那么再次对aof文件进行**同步**，并且这个同步操作是由一个线程专门负责执行的。
- no：**只写入而不同步**，何时同步由操作系统决定

> 文件的写入和同步：
>
> 为了提高文件操作效率，当用户调用write系统调用，将数据写入到文件的时候，操作系统通常会将写入数据暂时保存在一个内存缓冲区里，等到缓冲区空间被填满，或者超过指定的时限之后，才真正的将缓冲区中的数据写入到磁盘中。
>
> 写入指的是写入到缓冲区，同步指的是数据从内存缓冲区同步到磁盘中



3. AOF载入和数据还原

Redis读取AOF文件并还原数据库状态的步骤如下：

- 创建不带网络连接的伪客户端
- 从AOF文件分析和读取一条写命令
- 使用伪客户端执行被读出的写命令



4. AOF重写

AOF重写功能主要是为了解决服务器运行较长时间后，AOF文件膨胀的问题。通过该功能，Redis服务器可以创建一个新的AOF文件来替代现有的AOF文件，新旧两个文件所保存的数据库状态相同，但是新AOF文件不会包含任何浪费空间的冗余命令，所以新AOF文件的体积会比旧AOF文件的体积会小得多。

AOF重写功能并不需要读取旧的AOF文件，而是直接根据现在的数据库中的数据，循环所有的键值对，用写入命令直接进行写入。这里会根据执行命令时数据的大小，考虑使用一条还是多条写入命令。

Redis会将AOF重写程序放到**子进程**中执行，子进程会带有主进程的**数据副本**。同时为了解决在AOF重写过程中可能因为主进程写入而导致的数据不一致问题，Redis设置了一个**AOF重写缓冲区**。这个缓冲区在服务器创建子进程之后开始使用，当Redis服务器执行完一个写命令之后，它会同时将这个写命令发送到AOF缓冲区和AOF重写缓冲区。这样就可以保证两边的操作都不受影响了。

当子进程重写完成时，它会向父进程发送一个信号，父进程接到信号后，调用一个信号处理函数，并执行以下工作：

- 将AOF重写缓冲区的所有内容写入到新AOF文件中。
- 对新的AOF文件进行改名，原子的覆盖现有的AOF文件，完成新旧文件的替换。



### 3.5 事件

Redis服务器是一个事件驱动程序，服务器需要处理两类事件：

- 文件事件：Redis服务器通过套接字与客户端进行连接，而文件事件就是服务器对套接字操作的抽象

- 时间事件：Redis服务器的一些操作（比如serverCron函数）需要在给定的时间点执行，而时间事件就是服务器对这类定时操作的抽象。

下面对这两种事件调度方式进行介绍。

1. 文件事件

Redis基于Reactor模式开发了自己的网络事件处理器，被称为文件事件处理器。

文件事件处理器使用**IO多路复用程序**来同时监听多个套接字，并根据套接字目前执行的任务来关联不同的事件处理器。当被监听的套接字准备好执行连接应答、读取、写入、关闭等操作时，与操作相对应的文件事件就会产出。文件事件处理器就会调用套接字之前关联好的事件处理器来处理这些事件。

![image-20211107163839054](https://raw.githubusercontent.com/oubindo/ImageBed/master/img/image-20211107163839054.png)

尽管多个套接字可能会并发向IO多路复用程序发送文件事件，但是IO多路复用程序还是会串行给文件事件分派器发文件事件。

文件事件中，最常用的主要是连接应答处理器，命令请求处理器和命令回复处理器。

- 连接应答处理器：客户端在连接监听套接字的时候，产生AE_READABLE事件，引起该处理器执行。
- 命令请求处理器：当客户端通过连接应答处理器成功连接到服务器之后，服务器会将客户端套接字的AE_READABLE事件和命令请求处理器关联起来。当客户端发送命令请求的时候，套接字就会产生AE_READABLE事件，引发命令请求处理器执行。
- 命令回复处理器：当服务端有命令回复需要传送到客户端的时候，服务端会将客户端套接字的AE_WRITABLE事件和命令回复处理器关联起来



2. 时间事件

时间事件分为定时事件和周期性事件。定时事件是在指定时间后执行一次，周期性事件是每隔一段时间就执行一次。

一个时间事件有三个属性组成：id（全局唯一标识），when（时间事件到达时间），timeProc（时间事件处理器）

服务器将所有时间事件都放在一个无序链表中，每当时间事件执行器运行时，它就遍历整个链表，查找所有已到达的时间事件，并调用相应的事件处理器。由于正常模式下的Redis服务器只使用serverCron一个时间事件，所以不会影响性能。

持续运行的Redis服务器需要定期对自身的资源和状态进行检查和调整，从而确保服务器可以长期、稳定地运行，这些定期操作由redis.c/serverCron函数负责执行，它的主要工作包括：

- 更新服务器的各类统计信息，比如时间、内存占用、数据库占用情况等。

- 清理数据库中的过期键值对。

- 关闭和清理连接失效的客户端。

- 尝试进行AOF或RDB持久化操作。

- 如果服务器是主服务器，那么对从服务器进行定期同步。

- 如果处于集群模式，对集群进行定期同步和连接测试。

Redis服务器以周期性事件的方式来运行serverCron函数，在服务器运行期间，每隔一段时间，serverCron就会执行一次，直到服务器关闭为止。

服务器是这样处理文件事件和时间事件的：

![image-20211110134856132](https://raw.githubusercontent.com/oubindo/ImageBed/master/img/image-20211110134856132.png)



### 3.6 客户端

Redis是典型的一对多服务器程序，一个服务器可以与多个客户端建立网络连接，并且为他们建立了相应的redis.h/client结构。server维护的client是一个链表，保存了所有与服务器连接的客户端的状态结构。

```c
struct redisServer {
	list *clients;  // 保存客户端的链表
}

typedef struct client {
  uint64_t flags;         // 标志，记录客户端的角色以及状态
  // --- 输入缓冲区
  sds querybuf;           // 输入缓冲区，用于保存客户端发送的命令请求
  robj **argv;            // 服务端将客户端发送的命令请求保存到querybuf属性之后，将命令请求的内容进行分析，将得出的命令参数以及命令参数的个数分别保存到argv属性和argc属性
  int argc;
  // --- 输出缓冲区
  char buf[PROTO_REPLY_CHUNK_BYTES]; // 一个固定大小的缓冲区，bufpos保存的是使用的长度
  int bufpos;  
  list *reply;                       // 可变大小缓存区，保存的是多个字符串对象的链表
  // --- 时间参数
  time_t ctime;           // 连接时间
  time_t lastinteraction; // 上次交互的时间
  time_t obuf_soft_limit_reached_time; // 记录输出缓冲区第一次到达软性限制的时间
}
```



### 3.7 服务端

一个命令请求从发送到获得回复的过程：

- 客户端发送命令请求，连接到服务器的套接字，发送给服务器
- 服务器读取套接字中的命令请求，保存到客户端的输入缓冲区中，分析命令请求，将参数和参数个数保存到客户端状态的argv属性和argc属性里面
- 调用命令执行器执行命令。首先要根据argv[0]参数在命令表中查找参数所指定的命令（命令表中会有函数指针，参数个数，命令属性标识值等信息），然后进行一些预备操作，最后调用命令实现函数。



serverCron函数执行的操作

- 更新服务器时间缓存：每100ms更新一次
- 更新LRU时钟：用于计算数据库键的空转时间
- 更新服务器每秒执行命令次数：每100ms执行一次，估算并记录服务器最近一秒钟处理的命令请求数量
- 更新服务器内存峰值记录
- 处理SIGTERM信号
- 管理客户端资源，释放无效客户端
- 管理数据库资源
- **将AOF缓冲区内容写入AOF文件**



初始化服务器的整个过程：

- 初始化服务器状态结构
- 载入配置选项
- 初始化服务器数据结构
- 根据RDB文件或者AOF文件还原服务器状态
- **执行事件循环**





## 四、多机数据库

### 4.1 复制

Redis中，用户可以通过SLAVEOF命令或者设置slaveof选项，让一个服务器去复制另一个服务器，我们称呼被复制的服务器为主服务器，而对主服务器进行复制的服务器则被称为从服务器。

本章首先介绍Redis在2.8版本之前的旧版复制功能的实现原理，并说明旧版复制功能在处理断线后重连的从服务器时，会遇上怎样的低效情况，后面再介绍2.8版本以后的新版复制功能。



**旧版复制**

Redis的复制功能分为同步sync和命令传播command propagate两个操作。

- 同步用于将服务器的数据库状态更新至主服务器当前所处的数据库状态
- 命令传播用于在主服务器的数据库状态被修改，导致主从服务器的数据库状态出现不一致时，让主从服务器的数据库重新回到一致状态。

同步的过程：

- 从服务器向主服务器发送SYNC命令
- 收到SYNC命令的主服务器执行BGSAVE命令，在后台生成一个RDB文件，并使用一个缓冲区记录从现在开始执行的所有写命令
- 当主服务器BGSAVE执行完后，主服务器把RDB文件发送到从服务器，从服务器载入这个RDB文件，将自己的数据库状态更新
- 主服务器将缓冲区中的写命令发送给从服务器，从服务器执行写命令，将自己的数据库状态更新至主服务器数据库当前所处的状态。

当同步执行完毕后，主从数据库将达到一致状态，但是主服务器执行客户端的写命令时，主服务器的数据库就可能被修改，导致主从服务器状态不一致。在这种情况下，主服务器就需要对从服务器执行**命令传播**操作，把自己执行的写命令发送到从服务器执行。

这种旧版复制的缺陷在于：在主从服务器从正常连接状态断联后，从服务器需要发送sync命令，主从服务器需要处理生成和载入RDB文件，成本很高。



**新版复制**

为了解决旧版复制功能在断线后重复复制的低效问题，redis推出了psync命令来代替sync命令执行复制时的同步操作。

psync具有完整重同步和部分重同步两种模式：

- 完整重同步用于处理初次复制情况，与sync命令执行步骤一致
- 部分重同步用于处理断线后重复复制，当从服务器重新连接主服务器时，如果条件允许，主服务器可以将断开期间的写命令发送给从服务器，从服务器只要接收和执行。

那么新版复制是怎么实现的呢？

主服务器会维护一个固定长度的**先进先出**队列，默认大小1M，称为**复制积压缓冲区**，这个队列不但维护写命令，还维护偏移量。当主服务器进行命令传播时，他不仅将写命令发送给从服务器，还将写命令入队到复制积压缓冲区里面。而主从服务器都会维护一个复制偏移量，以字节为单位。主服务器每次向从服务器传播N个字节时，就将自己的复制偏移量加N；从服务器每次收到N个字节，就把自己的复制偏移量加N。

但从服务器重连的时候，如果发现复制偏移量已经超出了复制积压缓冲区，就执行完整重同步；否则只进行部分重同步。



### 4.2 Sentinel 哨兵

Sentinel是Redis的高可用解决方案：由一个或多个Sentinel实例组成的Sentinel系统可以监视任意多个主服务器，以及这些主服务器属下的所有从服务器，并在被监视的主服务器进入下线状态时，自动将下线主服务器属下的某个从服务器升级为新的主服务器。

当一个Sentinel启动时，他需要执行下面步骤：

- 初始化服务器：sentinel不会载入RDB和AOF文件
- 使用Sentinel专用代码：将一部分普通Redis服务器使用的代码替换成Sentinel专用代码，比如服务器的命令表。这也解释了为啥sentinel模式下，Redis服务器不能执行注入SET、DBSIZE等命令
- 初始化Sentinel状态：初始化一个sentinel.c/sentinelState状态，保存所有和Sentinel功能有关的状态。
- 初始化Sentinel状态的masters属性：sentinelState中的masters字典记录了所有被Sentinel监视的主服务器的相关信息。
- 创建连向主服务器的网络连接：Sentinel会创建两个连向主服务器的异步网络连接，一个是命令连接用于向主服务器发送命令并接收回复，另一个是订阅连接用于订阅主服务器的__sentinel__:hello频道。



**Sentinel交互**

接下来我们介绍Sentinel是怎么跟主服务器及其他sentinel交互的。

1.获取主服务器信息：Sentinel默认会以**10s**一次的频率，通过**命令连接**向被监视的主服务器发送INFO命令，通过回复获取主服务器的当前信息和其下属的从服务器的相关信息，并更新自己的相关记录。

2.获取从服务器信息：当Sentinel发现主服务器有新的从服务器出现时，Sentinel会为新的从服务器创建相应的实例结构，并且创建连接到从服务器的命令连接和订阅连接，每十秒通过**命令连接**向从服务器发送INFO命令。

3.向主服务器和从服务器发送信息：Sentinel以每**2s**一次的频率，通过命令连接向所有被监视的主服务器和从服务器发送sentinel:hello命令。

4.接收来自主服务器和从服务器的频道信息：当Sentinel与主从服务器建立起订阅连接之后，sentinel就会通过订阅连接从服务器的sentinel:hello频道接收信息。**当有多个sentinel同时监视一个从服务器时，只要一个发了sentinel:hello命令，其余的都能收到。**

这里讲了两种连接，命令连接的主要作用是监视主从服务器的关系和状态，订阅连接主要是接收其余sentinel服务器的信息，更新到主服务器的sentinels字段里面。

5.更新主服务器中的sentinels字典，这个字典记录了所有监听他的sentinel的相关信息

6.创建连向其他sentinel的命令连接：当sentinel发现一个新的sentinel时，他除了更新sentinels字典，还会创建一个连向新sentinel的**命令连接**，而新sentinel也会创建连向这个Sentinel的命令连接。最终监视同一主服务器的多个sentinel将形成网络。

经过上面的过程，Sentinel和服务器之间，Sentinel和Sentinel之间，构建起了完整的节点网络，由Sentinel进行监视和管理。



**检测主观下线状态**

Sentinel会以每秒一次的频率向所有与它创建了命令连接的实例（包括主从服务器，其他sentinel）发送Ping命令，并通过实例返回的Ping命令回复（PONG，LOADING，MASTERDOWN三种有效，其他命令或超时未回复都无效）来判断实例是否在线。

Sentinel配置文件中的`down-after-milliseconds`选项指定了Sentinel判断实例进入主观下线所需的时间长度。如果一个实例在down-after-milliseconds毫秒中，连续返回无效回复，那么Sentinel会修改这个实例对应的实例结构，在flags属性中打开SRI_S_DOWN标识，依次表示这个实例已经进入**主观下线**状态。

> 需要注意，不同Sentinel如果配置不一致，会出现不同Sentinel对实例的判定不一致的情况。



**检测客观下线状态**

当Sentinel将一个主服务器判断为主观下线之后，为了确认这个主服务器是否真的下线了，它会向同样监视这一主服务器的其它Sentinel进行询问。当他从其它Sentinel那里接收到足够数量的已下线判断之后，就会将服务器判定为客观下线，并对主服务器进行故障转移操作。这个过程为：

- 发送SENTINEL is-master-down-by-addr命令，询问其它Sentinel是否同意该主服务器已下线
- 接收别的Sentinel的 SENTINEL is-master-down-by-addr 命令，别的sentinel会返回他们认为的是否下线
- 接收Sentinel is-master-down-by-addr命令的回复，同时统计其它sentinel同意主服务器已下线的数量，当这个数量达到指定的配置时，就会认为这个主服务器已经进入客观下线状态。

当一个主服务器被判断为客观下线时，监视这个下线主服务器的各个Sentinel会通过**Raft协议选举**出一个领头Sentinel，并由领头Sentinel对这个服务器执行故障转移操作。该操作包含三个步骤：

- 从已下线主服务器属下的所有从服务器里面，挑选出一个从服务器，转换为主服务器
- 让其他从服务器改为复制新的主服务器
- 将下线主服务器设置为新的主服务器的从服务器



### 4.3 集群

一个Redis集群由多个节点组成，刚开始的时候，每个节点都是相互独立的，要组成集群必须将各个独立的节点连接起来，构成一个包含多个节点的集群。

**节点**

连接各个节点可以用CLUSTER MEET命令完成。向一个节点发CLUSTER MEET命令，可以让那个节点与自己进行握手，同时添加到自己的集群中。

节点会拥有正常redis服务器相关的所有数据，跟集群相关的数据都会放到cluster.h/clusterNode，cluster.h/clusterLink，cluster.h/clusterState结构中。

```c
typedef struct clusterNode {
    mstime_t ctime; /* 创建时间 */
    char name[CLUSTER_NAMELEN]; /* 节点名字 */
    int flags;      /* 节点标识 */
    uint64_t configEpoch; /* 节点的配置纪元 */
    char ip[NET_IP_STR_LEN];  /* 节点IP地址 */
    int port;                 /* 节点端口号 */
    clusterLink *link;          /* 保存连接节点所需的有关信息 */
  	unsigned char slots[16384/8];  /* 处理的槽 */
  	int numslots;          /* 处理的槽的数量 */
    // ...
}

typedef struct clusterLink {
    mstime_t ctime;             /* 连接的创建时间 */
    int fd;                     /* TCP套接字描述符 */
    sds sndbuf;                 /* 输出缓冲区 */
    char *rcvbuf;               /* 输入缓冲区 */
    struct clusterNode *node;   /* 与这个连接相关联的节点 */
} clusterLink;

// clusterState被server.h/redisServer所持有
typedef struct clusterState {
    clusterNode *myself;  /* 指向当前节点的指针 */ 
    uint64_t currentEpoch;  /* 集群的配置纪元，用于实现故障转移 */
    int state;            /* 集群的状态，在线还是下线 */
    int size;             /* 集群中至少处理着一个槽的节点的数量 */
    dict *nodes;          /* 集群节点名单 */
  	clusterNode *slots[16384];  /* slot分配的数组，每个槽对应一个clusterNode */
}
```

握手的步骤为

![image-20211113223335285](https://raw.githubusercontent.com/oubindo/ImageBed/master/img/image-20211113223335285.png)



**槽指派**

Redis集群通过分片的方式来保存数据库中的键值对：集群的整个数据库被分为**16384**个槽，集群中的每个节点可以处理0或最多16384个槽。**当所有的槽都有节点在处理时，集群处于上线状态，如果有任何一个槽没有得到处理，集群都处于下线状态。**

通过向节点发送CLUSTER ADDSLOTS命令，我们可以将一个或多个槽指派给节点负责。节点处理的槽的信息会记录在clusterNode的slots和numslots属性中，并且他还会将自己的slots数组通过消息发送给集群中的其它节点。因此，集群中的每个节点都知道这16384个槽分别被指派给了集群中的哪些节点，槽的分配信息被记录到了clusterState结构中的slots数组中。

**所以clusterState.slots数组记录16384个槽的分配情况，clusterNode.slots数组记录当前节点负责处理的槽。**

![image-20211114111317559](https://raw.githubusercontent.com/oubindo/ImageBed/master/img/image-20211114111317559.png)

如何计算键属于哪个槽呢？主要使用以下算法

```c
slot_number = CRC16(key) & 16383
```

当节点发现某个键不是自己处理的时候，就会向客户端返回一个MOVED错误，并且把正确的节点返回，指引客户端转向正确处理槽的节点



**节点数据库**

节点数据库和单机数据库完全相同，唯一的区别是节点只能使用0号数据库，而单机Redis服务器则没有这个限制。

同时，clusterState中也会记录槽和键的对应关系，clusterState会维护一个16384大小的数组，每个item都是一个链表，记录的是这个槽下的所有键。



**故障检测与转移**

集群中的每个节点都会定期向集群中的其他节点发送PING消息，如果接收PING消息的节点没有在规定的时间内，向发送PING消息的节点返回PONG消息，那么发送PING消息的节点就会将接收PING消息的节点标记为疑似下线。

集群中的各个节点会通过互相发送消息的方式来交换集群中各个节点的状态信息。如果半数以上负责处理槽的主节点都将某个主节点x报告为疑似下线，那么这个主节点就会被标记为下线，同时将主节点x标记为已下线的节点会向集群广播一条关于主节点x的FAIL消息，所有收到这条FAIL消息的节点都会立即将主节点x标记为已下线。

新的主节点通过原有的主节点的从节点进行选举产生。从节点会向其余的主节点发送消息，要求他们给自己投票，率先获得超过一半的票就能选举为新主节点。



**消息**

集群中的各个节点通过发送和接受消息来进行通信。节点发送的消息主要有五种：

- MEET消息：发送方请求接收方加入到自己所处的集群
- PING消息：集群中的每个节点每隔1s钟向已知节点列表随机选五个，选择这五个中最长时间没发送过PING消息的节点发送PING消息；或者距离某个节点上次接收到PONG消息的时间超过了cluster-node-timeout的一半，就会发PING消息
- PONG消息：当接收者收到发送者发来的MEET和PING消息时的回复；或者主动向集群广播自己的PONG消息让其他节点刷新关于这个节点的认识
- FAIL消息：当节点A判断另一个主节点B已经进入FAIL状态时，A向集群广播一条关于B的FAIL消息，收到消息的节点立即将B标记为下线
- PUBLISH消息：当节点收到PUBLISH命令时，节点会执行这个命令，同时像集群广播PUBLISH消息，收到消息的节点都会执行相同的PUBLISH命令

消息由消息头和消息正文组成。每个消息由cluster.h/clusterMsg结构表示

```c
typedef struct {
    uint32_t totlen;    /* 消息的长度 */
    uint16_t type;      /* 消息类型 */
    uint16_t count;     /* 消息正文包含的节点信息数量 */
    uint64_t currentEpoch;  /* 发送者所处的配置纪元 */
    uint64_t configEpoch;   /* 如果发送者是主节点，那么这是发送者配置纪元；如果是从节点，那么是发送者正在复制的主节点的配置纪元 */
    char sender[CLUSTER_NAMELEN]; /* 发送者的名字 */
    unsigned char myslots[CLUSTER_SLOTS/8];  /* 发送者目前的槽指派信息 */
    char slaveof[CLUSTER_NAMELEN]; /* 如果发送者是主节点，那么这是REDIS_NODE_NULL_NAME；如果是从节点，那么是发送者正在复制的主节点的名字 */
    uint16_t flags;      /* 发送者标识 */
    unsigned char state; /* 发送者集群状态 */
    union clusterMsgData data;  /* 消息内容 */
} clusterMsg;

union clusterMsgData {
    /* PING, MEET and PONG */
    struct {
        /* Array of N clusterMsgDataGossip structures */
        clusterMsgDataGossip gossip[1];
    } ping;

    /* FAIL */
    struct {
        clusterMsgDataFail about;
    } fail;

    /* PUBLISH */
    struct {
        clusterMsgDataPublish msg;
    } publish;
};
```

消息头的type属性可以用来判断消息是MEET消息，PING消息还是PONG消息。

当接收者收到MEET，PING，PONG消息时，接收者会访问两个clusterMsgDataGossip结构，并根据自己是否认识clusterMsgDataGossip结构中记录的被选中节点来选择进行哪种操作：

- 如果被选中节点不存在于接收者的已知节点列表，那么说明接收者第一次接触到被选中节点，接收者会与选中节点进行握手
- 如果被选中节点存在于接收者的已知节点列表，那么接收者将根据clusterMsgDataGossip中记录的信息，对被选中节点对应的clusterNode结构进行更新

当集群中的主节点A将主节点B标记为已下线（FAIL）时，主节点将向集群广播一条关于主节点B的FAIL消息，所有接收到这条FAIL消息的节点都会将主节点B标记为已下线。

> Redis中的消息传播用的是Gossip协议，补充文档 https://segmentfault.com/a/1190000038373546

PUBLISH主要用于发布-订阅模式。



## 五、独立功能的实现

### 5.1 发布与订阅

Redis的发布订阅功能由PUBLISH、SUBSCRIBE、PSUBSCRIBE等命令组成。

客户端可以通过执行SUBSCRIBE命令，订阅一个或多个**频道**。每当有其他客户端向被订阅的频道发送消息时，频道的所有订阅者都会收到这条消息。除了订阅频道以外，客户端还可以通过执行PSUBSCRIBE命令订阅一个或多个**模式**，每当有其他客户端向某个频道发送消息时，

**频道的订阅和退订**

Redis将所有频道的订阅关系都保存在服务器状态redisServer的pubsub_channels字典里面。这个字典的键是某个被订阅的频道，而键的值则是一个记录了所有订阅这个频道的链表。

当一个客户端退订某个频道时，服务器将从pubsub_channels中解除客户端与被退订频道之间的关联，从链表中删除对应的订阅者，**当频道的订阅者变成了空链表，没有任何订阅者时，程序将从pubsub_channels字典中删除频道对应的键。**

**模式的订阅与退订**

服务器将所有模式的订阅关系都保存在服务器状态redisServer的pubsub_patterns字典里面，这个结构的pattern属性记录了被订阅的模式，而client属性则记录了订阅模式的客户端。

每当客户端执行PSUBSCRIBE命令订阅某个模式时，服务器会对每个被订阅的模式和客户端的信息存入pubsub_patterns字典。退订的时候进行删除

**发送消息**

当一个Redis客户端执行PUBLISH channel message命令将消息message发送给频道channel的时候，服务器会执行以下两个动作：

- 将消息message发送给channel频道的所有订阅者
- 如果有一个或多个模式pattern与频道channel相匹配，那么僵消息message发送给pattern模式的订阅者。

**一些有用的命令**

PUBSUB CHANNELS [pattern]：返回服务器当前被订阅的频道。不传pattern则返回全部

PUBSUB NUMSUB [channel-1，channel-2]：接收任意多个频道作为输入参数，并返回这些频道的订阅者数量。

PUBSUB NUMPAT：返回服务器当前被订阅模式的数量

> 问：为什么大家没使用redis的发布-订阅模式，而是使用了rmq呢？
>
> 答: 因为https://stackoverflow.com/questions/52592796/redis-pub-sub-vs-rabbit-mq/52595962



### 5.2 事务

Redis通过MULTI、EXEC、WATCH等命令来实现事务功能。使用举例：

```shell
redis> MULTI
redis> SET "xxx" "xxx"
redis> GET "xxx"
redis> EXEC
```

一个事务的生命周期会经历三个阶段：

1.事务开始：MULTI命令的执行标志着事务的开始。主要是将执行该命令的客户端从非事务状态切换至事务状态，通过在客户端状态的flags属性中打开REDIS_MULTI标识来完成的。

2.命令入队：当一个客户端切换到事务状态之后，服务器会根据客户端发来的不同命令执行不同操作。如果是EXEC, DISCARD, WATCH, MULTI四个命令的其中一个，那么服务器立即执行；如果客户端发送的是其他命令，那么服务器会把这个命令放入一个事务队列里面，然后向客户端返回QUEUED回复。

每个客户端都有自己的事务状态，这个状态保存在client的mstate属性中。

```c
typedef struct client {
		multiState mstate;   // 事务状态
}

typedef struct multiState {
    multiCmd *commands;     /* 事务队列，FIFO事件 */
    int count;              /* 已入队命令计数 */
} multiState;

typedef struct multiCmd {
    robj **argv;           /* 命令的参数 */
    int argv_len;          
    int argc;            
    struct redisCommand *cmd; /* 命令实现函数的指针 */
} multiCmd;
```

3.执行事务

当一个处于事务状态的客户端向服务器发送EXCE命令时，这个EXEC命令将立即被服务器执行。服务器会遍历这个客户端的事务队列，执行队列中保存的所有命令，最后将执行命令所得的结果全部返回给客户端。



**WATCH命令**

WATCH命令是一个乐观锁，他可以在EXEC命令执行之前，监视任意数量的数据库键，并在EXEC命令执行时，检查被监视的键是否至少有一个已经被修改过，如果是的话，服务器将拒绝执行事务，并向客户端返回代表事务执行失败的空回复。

这里主要是因为我们的事务队列是存放在客户端上面的，所以可能出现多个客户端同时修改同一个key的情况。使用WATCH命令可以部分解决这个问题。

每个Redis数据库都保存着一个watched_keys字典，字典的键是某个被WATCH命令监视的数据库键，字典的值是一个链表，记录了所有监视相应数据库键的客户端。任何对数据库进行修改的命令，在执行之后都会调用multi.c/touchWatchKey函数对watched_key字典进行检查，如果有监视对应键的客户端，就会把他们的REDIS_DIRTY_CAS标识打开，标识该客户端的事务安全性已经被破坏。服务器在这种情况下就会拒绝事务的执行

Redis的事务和传统的关系型数据库事务的最大区别是：**Redis不支持事务回滚机制**。即使事务队列中的某个命令在执行期间出现了错误，整个事务也会继续执行下去，直到把事务队列中的所有命令都执行完毕为止。主要的原因是因为作者因为这种复杂功能和Redis的设计初衷不一致。 















































