# ElasticSearch快速入门

本文着力于介绍ES入门级的知识，目的是让大家能懂得基本使用，能应用到工作中；并产生兴趣，进而愿意去学习ES的深层设计思想和细节。

更深的ES框架设计思想和细节，欢迎关注后续文章。



## 一.ES是什么

ElasticSearch（后文简称ES）是一款稳定高效的**近实时**的**分布式搜索和分析**引擎。它的底层基于Lucene（一款强大的搜索和分析引擎），在Lucene基础上提供了友好的RESTful风格的交互方式。ES开箱即用，上手容易，性能优秀。

官网给了ES的几个典型使用场景：

- 日志管理、系统指标检测和可视化

- 卓越的搜索体验，支持文档，地理数据等各种内容

- 交互式调查和自动威胁检测

目前ES在各大IT公司都有广泛的应用，比如Github拿来检索代码库，eBay拿来检索商品数据。当然数据量如果大到一定程度，ES的性能就可能不够了，大公司就会采用自研框架来替代。

那么可能有同学就问了，mysql不是也可以做搜索吗？为啥要用es来做呢？原因是mysql的性能就满足不了需求，在**模糊查询**的情况下，mysql的索引发挥不了作用，查找很慢。

而ES就是专门做搜索的，它有几个突出的优点：

- 搜索速度快（近实时）

- 搜索到的数据可以进行评分，这样我们只需要返回评分高的数据给用户就行了（就像大家用搜索引擎一样，估计大部分都不会去点开第二页）。[评分机制](https://www.elastic.co/guide/cn/elasticsearch/guide/current/scoring-theory.html)

- 关键字不需要很准确也可以搜出相关的结果

一句话，Made For Search！





## 二.基本概念

上面我们讲到，ES是支持分布式的，所以它也支持集群。我们先了解下ES的一些基本组件。

- Node（节点）：进行数据存储，参与搜索和排序的单个实例。每个Node都有自己的唯一标识名

- Cluster（集群）：一个或多个Node组成的集合，人多力量大。ES具有自发现的能力，会自动寻找网络上配置在相同集群中的节点共同组成一个集群

- Document（文档）：ES中信息存储和检索的最小单位，以json的形式存储。

- Field（字段）：每个文档包含多个字段，类比可以想象json文件也有多个字段。

- Index（索引）：一些具有相似特征的文档的集合。

- Type（类型）：Type是Index的逻辑类别分区，相当于一个index可以有多个type分区。不过从6.0.0之后，ES废弃了Type的概念。

- Shard（分片）：当Index存储大量数据时，可能会超过单个节点的硬件限制，ES提供了把索引垂直切分为分片的机制，这样就可以跨分片分发和并行化操作，提高性能和吞吐量。

- Replica（副本）：ES提供了将分片复制为一个或多个副本的功能，这样在复杂多变的网络环境中出现故障后也能快速地恢复。

Node和Cluster是服务相关的概念，一般接触过分布式的同学都会多少有些了解。Document、Index、Type、Field跟数据库的概念也可以对应上

| ES           | MySql          |
| ------------ | -------------- |
| 索引Index    | 数据库DataBase |
| 类型Type     | 表Table        |
| 文档Document | 行Row          |
| 字段Field    | 列Column       |
| 映射Mapping  | 约束Schema     |



## 三.ES集群

我们先看一个ES集群的架构图，

![image](https://cdn.jsdelivr.net/gh/oubindo/ImageBed@latest//img/image.png)

ES集群中的每个节点都会有两个配置项：

- node.master：表示节点是否具有成为主节点的资格。主节点负责管理集群范围内的所有变更，例如增加、删除索引，或者增加、删除节点等，而并不需要涉及到文档级别的变更和搜索等操作。

- node.data：表示节点是否能存储数据，处理文档变更，搜索等

针对这两个参数的配置不同，某个节点可能会有四种角色：

- node.master为true：主节点，不处理数据

- node.master和node.data都为true：主节点，同时也处理数据

- node.data为true：数据节点

- node.master和node.data都不为true：称为协调节点，不管理集群，也不维护数据，主要用作负载均衡。主节点和数据节点都拥有协调节点的能力。

ES给分片提供了Replicas机制，分片分为主分片和副分片，数据写入的时候是**写到主分片**，副本分片会**复制主分片**的数据，读取的时候**主副分片都可以读**。Index需要分成多少个主副分片可以通过配置设置。但是有一个强制要求：一个主分片至少有一个副分片，且主分片P0对应的副分片R0不能跟P0同时处于一个node上。当某个节点挂了，这个节点上的主分片也就挂了，那么master node就会把主分片对应的副分片提拔为主分片。

对于主分片来说，一个文档只会存在一个主分片上面，那么怎么定位这个存储了文档的分片呢？根据公式来算的。

```Plaintext
shard = hash(routing) % number_of_primary_shards
```

routing是拿来定位分片的可变值，默认是文档id。routing的选择非常重要，能显著提升ES使用性能。对应到我们C端ES来说，文档id是product_id，routing是shop_id，这是因为使用场景大多是店铺相关。

number_of_primary_shards是主分片的数量，这个是创建索引的时候就要确定好的。

所以协调节点的作用，就是根据公式计算出每个请求的具体需要处理的分片。

- 对于写操作（如写入文档），协调节点会路由到对应的主分片进行写入，然后复制到副本分片中。主副节点都写入成功之后，返回给客户端结果。

![image_2](https://cdn.jsdelivr.net/gh/oubindo/ImageBed@latest//img/image_2.png)

- 对于读操作（如读取某个文档），通过round-robin随机轮训算法随机寻找主副分片中的一个，进行读取操作。

- 对于搜索操作（如根据条件搜索），协调节点会把命令转发到所有的主分片或副分片，每一个分片将自己搜索的结果返回给协调节点，由协调节点进行数据的合并，排序，分页等操作，产出最后的结果。



## 四.搜索原理

### 4.1 倒排索引

前面我们说到了，ES是为搜索而生，那么为什么他可以做到那么高的搜索性能呢，主要是因为他使用了Lucene的**倒排索引**技术。

假设我们有这样几条数据。

| **docId** | **name** | **age** | **sex** | **desc**       |
| --------- | -------- | ------- | ------- | -------------- |
| 1         | Ada      | 18      | women   | rich and smart |
| 2         | Carla    | 20      | women   | rich and tough |
| 3         | John     | 18      | man     | beautiful      |

那么这样每一行都是一个document，每个document都有一个docId。

从docId去查询到这一条记录，我们称为是**正排索引**。而通过姓名，年龄，性别这些参数去查询到对应的docId，就叫做**倒排索引**。

在这个例子中，建立的倒排索引就是

| **name** |      |
| -------- | ---- |
| Ada      | [1]  |
| Carla    | [2]  |
| John     | [3]  |

| **age** |       |
| ------- | ----- |
| 18      | [1,3] |
| 20      | [2]   |

| **sex** |       |
| ------- | ----- |
| man     | [3]   |
| woman   | [1,2] |

这样如果我们想找男性且年龄为18的，就可以求交集得到docId为3。

而对于desc这种长端的文本，es会采用分词技术，拆解为单个有意义的词组，同样建立倒排索引

| **desc**  |       |
| --------- | ----- |
| rich      | [1,2] |
| smart     | [1]   |
| tough     | [2]   |
| beautiful | [3]   |

我们将倒排索引的查询项称为`term`，如Ada，man等。将对应查出来的docId list称为`posting list`。

但是，因为每个字段可能都有不同的取值，index规模大了以后，term的规模也会很大，这就需要ES能较快的查询到term。





### 4.2 ES Term查询

假设我们有很多个term，比如：

Carla,Sara,Elin,Ada,Patty,Kate,Selena

如果按照这样的顺序排列，找出某个特定的term一定很慢，因为term没有排序，需要全部过滤一遍才能找出特定的term。排序之后就变成了：

Ada,Carla,Elin,Kate,Patty,Sara,Selena

这样我们可以用二分查找的方式，比全遍历更快地找出目标的term。这个就是 `term dictionary`。

但是term dictionary可能会非常大，没办法放在内存中，只能放在硬盘中分块存储。于是，es采用了trie树来记录term的前缀，称为term index。

通过term index可以快速的定位到某个term dictionary的某个offset，然后从这个位置再往后查找。再加上一些压缩技术，term index的尺寸可能是所有term的尺寸的几十分之一，从而可以将term index缓存到内存中。

查询方式为：

![image_3](https://cdn.jsdelivr.net/gh/oubindo/ImageBed@latest//img/image_3.png)

注：数值类型的范围查找，并没有使用倒排索引，可以参考[range原理](https://blog.csdn.net/laoyang360/article/details/106740630)





## 五.基本使用

### 5.1 搭建集群

#### 5.1.1 搭建ES集群

接下来我们从0到1搭建一个集群，方便后续的练习。我这里使用的是公司的开发机，使用docker编排容器，es版本为7.8.1。

1.首先我们需要在开发机上安装docker，可参考 [docker安装](https://yeasy.gitbook.io/docker_practice/install)

2.安装好docker后，我们需要先拉取es的镜像。

```PowerShell
docker pull elasticsearch:7.8.1
```



3.配置网络

为了模拟我们的es是独立服务器，我们可以使用docker网络IP指定隔离；docker 创建容器时默认采用的bridge网络，自行分配IP，不允许我们自己指定。而在实际部署中，我们需要指定容器IP，不允许其自行分配IP，尤其是搭建集群时，固定IP时必须的。所以我们可以创建自己的bridge网络：mynet，创建容器的时候指定网络为mynet并指定IP即可

```PowerShell
#查看网络模式 
docker network ls
#创建一个新的bridge网络-mynet
docker network create --driver bridge --subnet=172.18.12.0/16 --gateway=172.18.1.1 mynet
#查看网络详情
docker network inspect mynet
#以后使用--network=mynet --ip 172.18.12.x 指定IP
```

![image_4](https://cdn.jsdelivr.net/gh/oubindo/ImageBed@latest//img/image_4.png)



4.接下来我们可以编写两个脚本，用于部署es的master节点和data节点。

创建三个master节点

```PowerShell
for port in $(seq 1 3); \
do \
mkdir -p ~/es/docker_es/elasticsearch/master-${port}/config
mkdir -p ~/es/docker_es/elasticsearch/master-${port}/data
chmod -R 777 ~/es/docker_es/elasticsearch/master-${port}
cat <<EOF >~/es/docker_es/elasticsearch/master-${port}/config/elasticsearch.yml
cluster.name: my-es #集群名称，同一集群该值必须设置相同
node.name: es-master-${port} #该节点的名字
node.master: true #该节点有机会成为master节点
node.data: false #该节点可以存储数据
network.host: 0.0.0.0
http.host: 0.0.0.0 #所有http均可访问
http.port: 920${port}
transport.tcp.port: 930${port}
discovery.zen.ping_timeout: 10s #设置集群中自动发现其他节点时ping连接的超时时间
discovery.seed_hosts: ["172.18.12.21:9301","172.18.12.22:9302","172.18.12.23:9303"] #设置集群中的master节点的初始化列表，可以通过这些节点来自动发现其他新加入集群的节点，es7的新增配置
cluster.initial_master_nodes: ["172.18.12.21"] # 新集群初始时的候选主节点，es7的新增配置
EOF
docker run --name es-master-${port} \
-p 920${port}:920${port} -p 930${port}:930${port} \
--network=mynet --ip 172.18.12.2${port} \
-e ES_JAVA_OPTS="-Xms300m -Xmx300m" \
-v ~/es/docker_es/elasticsearch/master-${port}/config/elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml \
-v ~/es/docker_es/elasticsearch/master-${port}/data:/usr/share/elasticsearch/data \
-v ~/es/docker_es/elasticsearch/master-${port}/plugins:/usr/share/elasticsearch/plugins \
-d elasticsearch:7.8.1

done
```

创建三个data节点

```PowerShell
for port in $(seq 4 6); \
do \
mkdir -p ~/es/docker_es/elasticsearch/node-${port}/config
mkdir -p ~/es/docker_es/elasticsearch/node-${port}/data
chmod -R 777 ~/es/docker_es/elasticsearch/node-${port}
cat <<EOF >~/es/docker_es/elasticsearch/node-${port}/config/elasticsearch.yml
cluster.name: my-es #集群名称，同一集群该值必须设置相同
node.name: es-node-${port} #该节点的名字
node.master: false #该节点有机会成为master节点
node.data: true #该节点可以存储数据
network.host: 0.0.0.0
http.host: 0.0.0.0 #所有http均可访问
http.port: 920${port}
transport.tcp.port: 930${port}
discovery.zen.ping_timeout: 10s #设置集群中自动发现其他节点时ping连接的超时时间
discovery.seed_hosts: ["172.18.12.21:9301","172.18.12.22:9302","172.18.12.23:9303"] #设置集群中的master节点的初始化列表，可以通过这些节点来自动发现其他新加入集群的节点，es7的新增配置
cluster.initial_master_nodes: ["172.18.12.21"] # 新集群初始时的候选主节点，es7的新增配置
EOF
docker run --name es-node-${port} \
-p 920${port}:920${port} -p 930${port}:930${port} \
--network=mynet --ip 172.18.12.2${port} \
-e ES_JAVA_OPTS="-Xms300m -Xmx300m" \
-v ~/es/docker_es/elasticsearch/node-${port}/config/elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml \
-v ~/es/docker_es/elasticsearch/node-${port}/data:/usr/share/elasticsearch/data \
-v ~/es/docker_es/elasticsearch/node-${port}/plugins:/usr/share/elasticsearch/plugins \
-d elasticsearch:7.8.1

done
```

最后出来的集群就是这样

![image_5](https://cdn.jsdelivr.net/gh/oubindo/ImageBed@latest//img/image_5.png)

这个时候我们就可以通过http://{devbox_ip}:9201/_cluster/health?pretty 来看到集群的配置详情了。

![image-20220125001926986](https://cdn.jsdelivr.net/gh/oubindo/ImageBed@latest//img/image-20220125001926986.png)



#### 5.1.2 搭建kibana工具

创建了es集群以后，我们再搭建一个kibana工具，便于我们使用这个es集群。

1.先拉取kibana镜像：注意kibana的版本要和es一致，不然会有问题

```PowerShell
docker pull kibana:7.8.1
```



2.接下来我们可以运行这个镜像

```PowerShell
# --link需要填写kibana连接到的es容器的名字  --net就是我们之前设定的网络名
docker run --name kibana --link=es-master-1 --net="mynet"  -p 5601:5601 -d kibana:7.8.1
```



- 3.一般情况下，这样操作以后都是没办法正常运行的。我们需要修改kibana的配置项。我们先进入到当前的kibana容器

```PowerShell
docker exec -it {container_id} /bin/bash
```

然后修改容器中的 config/kibana.yml 文件

![image_7](https://cdn.jsdelivr.net/gh/oubindo/ImageBed@latest//img/image_7.png)

将红框位置修改为你es容器的配置，然后退出来，重新restart kibana容器

```PowerShell
docker restart {container_id}
```



4.这时候，我们就可以通过 http://{devbox_ip}:5601/ 访问到kibana页面了。

http://10.227.15.83:5601/app/kibana#/dev_tools/console

![image_8](https://cdn.jsdelivr.net/gh/oubindo/ImageBed@latest//img/image_8.png)



### 5.2 settings && mapping

我们可以通过每个索引的settings和mapping来自定义索引行为。

settings定义的是索引维度的行为，比较重要的几个配置项：

- **index.number_of_replicas：**每个主分片的副本数

- **index.refresh_interval**：刷新间隔，默认为1s，数据写入以后处于不可读状态，只有刷新以后才能读到。

- **index.max_result_window**：数据查询窗口。默认为1w，不建议修改。



mapping定义的是单个document的行为，类似于mysql的约束schema。

elasticsearch中一条数据对应一条document，一条document包含一个或多个字段，例如：

```Prolog
{
        "name": "Bob",
        "host": "NYC",
        "date": "2020-02-11",
        "balance": 5000,
        ...
}
```

不同的字段拥有不同的类型(type)，不同的类型又会导致Elasticsearch在写入(index)和查询(query)中的行为方式不同。

Mapping类型大致分为以下类型：

1. 字符串类型：早期为`string`类型，目前有`text`，`keyword`类型，text类型会进行分词，适用于全文查找，而keyword适用于精确匹配。

1. 数字类型：`integer`,`long`,`double`等类型标识

1. 日期类型：date, date_nanos等

1. 地理位置信息类型：类似geo-*的信息

1. 其他：包括布尔类型，ip类型，嵌套类型，范围类型，形状类型等)

详见[links](https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-types.html)

这里要注意，mapping的选择会影响到查询的性能。对于不需要进行range查询，排序的数值类型，如product_id，不应该使用long类型，应该用keyword。



### 5.3 ES常用指令

1. 索引处理

```Shell
// 创建索引
PUT /customer

// 删除索引
DELETE /customer
```



1. 文档写入删除    

```Java
// 文档写入
PUT /customer/doc/1
{
        "name": "john"
}

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

1. 

1. 搜索全部、排序、分页、指定字段

```Java
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



1. 条件查询

1. 数值类型查询

```Java
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



文本类型查询。可以使用match，multi_match、terms等字段

```Java
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

// 存在性判断。可以使用exists和missing查找指定字段中有值或无值的文档。比如我在这里可以看balance没有赋值的文档
{
    "query": {
        "exists": {
            "field": "balance"
        }
    }
}
```



1. 除了上面的单条件查询，ES还提供了`多组合查询`

- **must** ：文档 *必须* 匹配这些条件才能被包含进来。

- **must_not**：文档 *必须不* 匹配这些条件才能被包含进来。

- **should**：如果满足这些语句中的任意语句，将增加 `_score` ，否则，无任何影响。它们主要用于修正每个文档的相关性得分。

- **filter**：*必须* 匹配，但它以不评分、过滤模式来进行。这些语句对评分没有贡献，只是根据过滤标准来排除或包含文档。

```Java
{
    "bool": {
        "must":     { "match": { "title": "how to make millions" }},
        "must_not": { "match": { "tag":   "spam" }},
        "should": [
            { "match": { "tag": "starred" }}
        ],
        "filter": {
          "bool": { 
              "must": [
                  { "range": { "date": { "gte": "2014-01-01" }}},
                  { "range": { "price": { "lte": 29.99 }}}
              ],
              "must_not": [
                  { "term": { "category": "ebooks" }}
              ]
          }
        }
    }
}
```

注意：must与filter虽然都是 *必须要* 的语义，但是must会计算每个文档的评分，按评分顺序返回文档，而filter只是单纯做判断。所以一般情况下filter性能好于must。





## 参考

https://www.elastic.co/cn/elasticsearch/

https://blog.csdn.net/xia296/article/details/108372102