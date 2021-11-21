# 牛刀小试：ElasticSearch轻松入门

这是我ES学习系列的第一篇文章，也是我的第一篇后端文章。万事开头难，然后中间难，结尾难，我将继续知难而上。大家有兴趣可以继续关注系列的后面几篇文章。

> 完整系列：
>
> - 牛刀小试：ElasticSearch轻松入门
> - 敬请期待

本文会关注入门使用所必需了解的基本概念、基本操作和原理，安装、升级等请自行谷歌，使用技巧、深层原理会在后面的系列中介绍。



## 1. 什么是ElasticSearch

ElasticSearch（后文简称ES）是一款稳定高效的**近实时**的分布式搜索和分析引擎。它的底层基于Lucene（一款强大的搜索和分析引擎），在Lucene基础上提供了友好的RESTful风格的交互方式。并且，ES开箱即用，上手容易，性能优秀。

官网给了ES的几个典型使用场景：

- 日志管理、系统指标检测和可视化
- 卓越的搜索体验，支持文档，地理数据等各种内容
- 交互式调查和自动威胁检测

当然，官网讲的东西还是有点玄乎，作为一个菜鸟，我们先了解最基本的搜索的使用就好，反正万变不离其宗嘛，搜索做好了其他的才能水到渠成。

目前ES在各大IT公司都有广泛的应用，比如Github拿来检索代码库，eBay拿来检索商品数据。当然数据量如果大到一定程度，ES的性能就可能不够了，可能会采用完全自研新框架的方式来解决问题，据我所知我司就有自研框架替代了ES。

那么可能有同学就问了，mysql不是也可以做搜索吗？为啥要用es来做呢？原因是mysql的性能就满足不了需求，在**模糊查询**的情况下，mysql的索引发挥不了作用，查找很慢，并且mysql也不能支持太高并发度的查询。

而ES就是专门做搜索的，它有几个突出的优点：

- 搜索速度快（近实时）
- 搜索到的数据可以进行评分，这样我们只需要返回评分高的数据给用户就行了（就像大家用搜索引擎一样，估计大部分都不会去点开第二页）
- 关键字不需要很准确也可以搜出相关的结果

一句话，Made For Search！



## 2. 基本使用

### 2.1 基本概念

上面我们讲到，ES是支持分布式的，所以它的架构也能体现出来分布式的特征。我们先了解下ES的一些基本组件。

- Node（节点）：进行数据存储，参与搜索和排序的单个实例。每个Node都有自己的唯一标识名
- Cluster（集群）：一个或多个Node组成的集合，人多力量大。
- Document（文档）：ES中信息存储和检索的最小单位，以json的形式存储。
- Field（字段）：每个文档包含多个字段，类比可以想象json文件也有多个字段。
- Index（索引）：一些具有相似特征的文档的集合。
- Type（类型）：Type是Index的逻辑类别分区，相当于一个index可以有多个type分区。不过从6.0.0之后，ES废弃了Type的概念。
- Shard（分片）：当Index存储大量数据时，可能会超过单个节点的硬件限制，ES提供了把索引垂直切分为分片的机制，这样就可以跨分片分发和并行化操作，提高性能和吞吐量。
- Replica（副本）：ES提供了将分片复制为一个或多个副本的功能，这样在复杂多变的网络环境中出现故障后也能快速地恢复。

Node和Cluster是服务相关的概念，一般接触过分布式的同学都会多少有些了解。Document、Index、Type、Field跟数据库的概念也可以对应上

| ES       | MySql    |
| -------- | -------- |
| Index    | DataBase |
| Type     | Table    |
| Document | Row      |
| Field    | Column   |



### 2.2 数据管理命令

ES提供了RESTful API来执行操作，请求的url需要遵循一定的格式。我这里用curl表示，一个完整的查询请求就如下所示，别的工具也相似

```shell
curl -X GET|PUT|HEAD|DELETE|POST http://localhost:9200/{cluster_name}/{type_name}/{document_name}
```

这里面，curl -X、http://localhost:9200都是固定不变的，我们后面把这些省略掉，把一些核心操作统一列在下面。我们先列举下数据管理相关的命令

- 集群管理相关

  ``` 
  // 查看集群状态
  GET /_cat/health?v
  
  // 查看节点状态
  GET /_cat/nodes?v
  
  // 查看所有索引信息
  GET /_cat/indices?v
  ```

- 索引相关

  ```
  // 创建索引
  PUT /customer
  
  // 删除索引
  DELETE /customer
  ```

- 文档相关

  ```shell
  // 在索引中添加文档
  PUT /customer/doc/1
  {
  	"name": "john"
  }
  //这里注意，如果用curl的话，需要这样写, 后面别的带了数据body的也类似
  curl -H "Content-Type:application/json"  -X PUT 'http://localhost:9200/customer/doc/1' -d'
  {
      "name": "json"
  }'
  
  
  // 查看索引中的文档
  GET /customer/doc/1
  
  // 修改文档
  POST /customer/doc/1/_update
  {
    "doc": { "name": "Jane Doe" }
  }
  
  // 删除文档
  DELETE /customer/doc/1
  ```



### 2.3 搜索命令

通过上面的文档建设起了数据，我们就可以进行搜索了。ES提供了非常多的搜索命令，我这里不能穷尽，只能列举一些常见的命令。更详细的命令，请查看[官网](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl.html)

假设我们在bank索引中有一些银行账户的数据，数据结构如下：

```json
{
    "account_number": 0,
    "balance": 16623,
    "firstname": "Bradshaw",
    "lastname": "Mckenzie",
    "age": 29,
    "gender": "F",
    "address": "244 Columbus Place",
    "employer": "Euron",
    "email": "bradshawmckenzie@euron.com",
    "city": "Hobucken",
    "state": "CO"
}
```

对全部文档搜索和排序的命令有

```
// 搜索全部
GET /bank/_search
{
  "query": { "match_all": {} }
}

// 分页搜索，from表示偏移量，从0开始，size表示每页的数量
GET /bank/_search
{
  "query": { "match_all": {} },
  "from": 0,
  "size": 10
}

// 搜索排序，使用sort表示，比如按balance降序排列
GET /bank/_search
{
  "query": { "match_all": {} },
  "sort": { "balance": { "order": "desc" } }
}

// 搜索并只返回指定字段内容，使用_source表示，例如只需要account_number和balance两个字段
GET /bank/_search
{
  "query": { "match_all": {} },
  "_source": ["account_number", "balance"]
}
```



按条件搜索的命令有

- 数值类型条件搜索，使用match作为匹配条件。match对于`数值类型、日期、布尔或not_analyzed字符串字段`都是精确匹配，这里搜索的是account_number为20的数据

```
GET /bank/_search
{
  "query": {
    "match": {
      "account_number": 20
    }
  }
}

// 查询某个范围的数据。被允许的操作符有 gt大于、gte大于等于、lt小于、lte小于等于
{
  "query": {
    "range": {
      "account_number": {
      	 "gte": 20,
      	 "lt": 30
      }
    }
  }
}
```

- 文本类型条件搜索。可以使用match，multi_match、terms等字段

```
// 文本类型条件搜索, 比如搜索match对于文本是模糊匹配。这里搜索含有mill的文档
GET /bank/_search
{
  "query": {
    "match": {
      "address": "mill"
    }
  }
}

// 短语匹配搜索，使用match_phrase表示，这里搜索address字段同时含有mill和lane的文档
GET /bank/_search
{
  "query": {
    "match_phrase": {
      "address": "mill lane"
    }
  }
}

// 使用terms查询，可以指定多值进行匹配。如果这个字段包含了指定值中的任何一个值，那么则符合条件
GET /bank/_search
{
    "query": {
        "terms": {
            "tag": ["search","full_text","nosql"]
        }
    }
}

```

- 存在性判断。可以使用exists和missing查找指定字段中有值或无值的文档。比如我在这里可以看balance没有赋值的文档

```
{
    "query": {
        "exists": {
            "field": "balance"
        }
    }
}
```



除了上面的单个搜索命令，ES还提供了`组合多查询`，主要有这么几个命令

- **must** ：文档 *必须* 匹配这些条件才能被包含进来。

- **must_not**：文档 *必须不* 匹配这些条件才能被包含进来。

- **should**：如果满足这些语句中的任意语句，将增加 `_score` ，否则，无任何影响。它们主要用于修正每个文档的相关性得分。

- **filter**：*必须* 匹配，但它以不评分、过滤模式来进行。这些语句对评分没有贡献，只是根据过滤标准来排除或包含文档。

这里也给个例子，查询age为40，state不包含ID，且余额在20000-30000之间的文档

```
GET /bank/_search
{
    "query": {
        "bool": {
            "must": [
                {
                    "match": {
                        "age": "40"
                    }
                }
            ],
            "must_not": [
                {
                    "match": {
                        "state": "ID"
                    }
                }
            ],
            "filter": {
                "range": {
                    "balance": {
                        "gte": 20000,
                        "lte": 30000
                    }
                }
            }
        }
    }
}
```



ES也提供了`搜索聚合`的命令`aggs`，可以对搜索结果进行聚合，类似于MySql中的`group by`。例如对state字段进行聚合，统计出相同state的文档数量，再统计出`balance`的平均值。

```
GET /bank/_search
{
  "size": 0,
  "aggs": {
    "group_by_state": {
      "terms": {
        "field": "state.keyword"
      },
      "aggs": {
        "average_balance": {
          "avg": {
            "field": "balance"
          }
        }
      }
    }
  }
}
```



### 2.4 Mapping和Setting









## 3. 基本原理

### 3.1 集群与分片架构

前面我们在`基本概念`小节也讲到了，ES是一个分布式的引擎，支持集群配置，并且还提供了index切分为shard的能力。我们用一张图来表示几个概念之间的关系。

<img src="https://ucc.alicdn.com/pic/developer-ecology/4e4b8b0ef1a04aa88c3ec550305cc1e4.png" alt="ElasticSearch原理篇-集群结构.png" />

既然是一个分布式集群，他的节点也会有不同的角色。ES中的节点有三种不同的类型：`主节点`、`数据节点`、`协调节点`。

**1）主节点 master node**

负责管理集群的所有变更，主要责任有：创建或删除索引，维护索引元数据；跟踪管理节点，比如增加和删除节点；分配分片到相关的节点，切换主分片和副本分片的身份。可以通过属性 node.master=true 设置节点是否具有被选举为主节点的资格。一个集群中只能有一个主节点，如果主节点挂了，会选举出一个新的主节点。

**2）数据节点 data node**

数据节点负责数据的存储和其他操作，比如增删查改和聚合。数据节点对机器配置要求较高，默认每个节点都是数据节点，包括主节点，当然我们一般情况下不会让主节点参与太多的数据操作，影响主节点角色职责。可以用 node.data=true 表示节点为数据节点

**3）协调节点 client node**

协调节点不存储数据，也不管理集群，他只能处理路由请求、搜索、分发索引操作等。协调节点存在的意义是在海量请求的时候进行负载均衡。协调节点的node.master=false且node.data=false。

>  注意，master node，data node都拥有client node的能力，如路由请求，搜索等，但是当这些节点的master能力和data能力都被剥夺以后，他就被归类为纯粹的client node了，只拥有路由请求，搜索能力了。



部分同学可能会有疑问，一个index分成了多个shard，那么岂不是只要有一个shard损坏了，数据就不完整了吗？

ES肯定也想到了这个问题，所以ES给分片提供了Replicas机制，分片分为`主分片`和`副分片`，数据写入的时候是**写到主分片**，副本分片会**复制主分片**的数据，读取的时候**主副分片都可以读**。默认情况下主分片会等所有副本都完成更新后返回给客户端成功的信号。

Index需要分成多少个主副分片可以通过配置设置。但是有一个强制要求：**一个主分片至少有一个副分片，且主分片A对应的副分片A'不能跟A同时处于一个node上**。当某个节点挂了，这个节点上的主分片也就挂了，那么master node就会把主分片对应的副分片提拔为主分片。这样，数据就不会丢，只是少了一个副本而已。



### 3.2 读写操作

当集群中含有多个主分片时，ES会根据路由公式决定哪个分片来处理。

```
shard = hash(routing) % number_of_primary_shards
```

这里的routing是一个可变值，默认是文档的_id，也可以设置成一个自定义的值。这里需要注意的是，我们需要在创建索引的时候就确定好主分片的数量，并且不会改变这个数量，不然根据公司计算出来的值就会发生变化导致结果完全错乱。当然跟Redis不太一样，Redis使用的是一致性hash算法保障调整集群数量时影响尽量小，ES的计算公式就比较简单，可以让每一个节点都可以计算出文档的存放位置，从而拥有处理读写请求的能力。



**1）读请求**

在一个读请求被发送到某个节点后，节点会根据路由公式计算出数据存储在哪个分片上，节点会以负载均衡的方式选择一个节点，然后将读请求转发到该分片节点上。

![ElasticSearch原理篇-分片-读数据.png](https://ucc.alicdn.com/pic/developer-ecology/24af18addc2345b79d2e89b6964e246f.png)

具体过程如下：

- 假设Node1节点收到一个读请求。
- Node1节点通过shard=hash(routing)% number_of_primary_shards计算数据落到哪一个分片上。假设计算出来的shard=1。
- Shard=1的分片有三个，其中主分片P1在Node3上，副分片R1在Node1、Node2上，此时Node1根据负载均衡的方式来选择一个副本。图中选择的是Node2节点的R1副本。Node1将请求转发给Node2处理此次读操作。
- Node2处理完成以后，将结果返回给Node1节点，Node1节点将数据返回给客户端。



**2）写操作**

在一个写请求被发送到主节点后，节点会根据路由公式计算出需要写到哪个分片上，再将请求转发到该分片的主分片节点上，主分片处理成功以后会将请求转发给副分片。

![ElasticSearch原理篇-分片-写数据.png](https://ucc.alicdn.com/pic/developer-ecology/82f32df12ed5420ab35163a9ca081161.png)

具体过程如下：

- 假设Node1收到一个创建索引的请求。
- Node1根据shard=hash(routing)% number_of_primary_shards计算数据落到哪一个分片上。假设计算出来的shard=1。
- 因为shard=1的主分片P1在Node3上，所以Node1将写请求转发到Node3节点。
- Node3如果处理成功，因为P1的两个副本R1在Node1、Node2上，所以Node3会将写请求转发到Node1、Node2上。
- 当所有的副本R1报告处理成功后，Node3向请求的Node1返回成功信息，Node1最后返回客户端索引创建成功。



### 3.3 搜索

前面我们讲到了，ES是个为搜索而生的引擎，搜索性能优异，那么他到底是做了什么技术实践来支持快速搜索海量数据呢？我们先来看下ES的底层数据结构。

我们根据key查找value叫做**正向索引**；比如一本书的章节目录就是正向索引，通过章节名称就找到对应的页码。而**倒排索引**就是根据value去查找对应的key，比如通过页码来找对应的章节名称。我们用一个例子来说明。

假设有三份数据文档分别如下：

- Doc1: I love China。
- Doc2: I love work。
- Doc3: I love coding。

正排索引就是通过Doc1来得到 I love China的结果。为了创建倒排索引，首先要通过分词器将每个文档的内容拆分成单独的词条。创建一个包含所有不重复词条的排序列表，然后列出每个词条出现在哪个文档。

| Term   | Doc1 | Doc2 | Doc3 |
| :----- | :--- | :--- | :--- |
| I      | Y    | Y    | Y    |
| China  | Y    |      |      |
| coding |      |      | Y    |
| love   | Y    | Y    | Y    |
| work   |      | Y    |      |







### 3.4 存储



























## 参考资料

https://juejin.cn/post/6844904117580595214#heading-13

https://developer.aliyun.com/article/775303











