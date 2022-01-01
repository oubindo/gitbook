# ElasticSearch使用要点

这篇文章主要是我阅读 [ElasticSearch官方文档](https://www.elastic.co/guide/en/elasticsearch/reference/current/getting-started.html) 的阅读笔记，是上一篇文章《ElasticSearch轻松入门》的补充篇。主要涉及ElasticSearch的使用技巧、性能优化、内部实现等。内容可能比较散。



## 一、使用技巧

1.使用fields属性获取指定字段

因为解析_source是非常复杂的操作，所以在我们只需要部分字段的情况下，可以使用fields属性指定需要的字段

```shell
GET logs-my_app-default/_search
{
  "query": {
    "match_all": { }
  },
  "fields": [
    "@timestamp"
  ],
  "_source": false,
  "sort": [
    {
      "@timestamp": "desc"
    }
  ]
}
```



2.修改本地ES配置

通过brew安装的es，配置文件路径在/usr/local/etc/elasticsearch/elasticsearch.yml



3.index的重要属性

- number_of_shards：index创建时候就必须确定的分片数量，属于类似于redis的分片
- number_of_routing_shards：用于索引routing，对单一属性进行分片整合的分片数。类似于redis的slot。number_of_routing_shards必须是number_of_shards的倍数，两者可以相等。
- max_terms_count：terms查询的参数的最大个数。默认是65536
- index.translog.sync_interval：translog被fsync到磁盘中的时间
- index.index.translog.durability：fsync的时机和频率。有request和async两种，request是每次请求都会，async是异步。







## 二、性能优化

[官网文档：Tune for search speed](https://www.elastic.co/guide/en/elasticsearch/reference/current/tune-for-search-speed.html)

1.尽量少查询fields。当我们的查询语句里的查询条件越多，查询就越慢。我们可以使用copy-to把多个字段合并为一个字段，对这一个字段进行查询。

2.预索引字段。比如用户请求经常对价格做range操作，我们就可以先预定义一些可以用的区间，直接写入到索引中去，作为一个索引字段。这样等查询的时候就只需要term查询这个区间是否匹配就行了。

3.使用keyword代替numeric类型。对于不需要进行range操作的数字类型，直接用keyword进行term。

4.如果一个字符串需要同时兼顾text和keyword，一个数字需要同时兼顾keyword和numberic的两种功能，可以定义多种类型，在需要的时候去使用不同的字段。如

```
PUT my-index-000001
{
  "mappings": {
    "properties": {
      "city": {
        "type": "text",
        "fields": {
          "raw": { 
            "type":  "keyword"
          }
        }
      }
    }
  }
}
GET my-index-000001/_search
{
  "query": {
    "match": {
      "city": "york" 
    }
  },
  "sort": {
    "city.raw": "asc" 
  },
  "aggs": {
    "Cities": {
      "terms": {
        "field": "city.raw" 
      }
    }
  }
}
```

5.尽量不使用script-based sorting, scripts in aggregations, and the script_score query。见 [Scripts, caching, and search speed](https://www.elastic.co/guide/en/elasticsearch/reference/current/scripts-and-search-speed.html).

6.通过时间查询范围的时候，使用一个范围，而不是单独的now。因为now无法缓存。

7.使用Global ordinals来优化用来聚合的字段的性能。会影响jvm heap usage

8.nested的坑点：nested很好用，但是es会给nested中的每个参数创建一个document，如果一个文档的某个nested字段有一百个item，那么总共就是101个文档。查询起来也是比较大的问题。





## 三、内部实现



