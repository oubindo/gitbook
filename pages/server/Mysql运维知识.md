# Mysql数据库运维

## 一条SQL的生命历程

### 整体执行过程介绍

![image-20220405144458673](https://cdn.jsdelivr.net/gh/oubindo/ImageBed@latest//img/image-20220405144458673.png)

连接器默认会使用长连接，使用一个连接池来处理。

缓存场景：查询两条完全一样的sql语句，会在第一条执行完成后有缓存。但是缓存会在几种情况下失效：

- 查询语句中含有不确定的值时，不会缓存
- 查询mysql, information_schema或performance_schema数据库中的表时，不会走查询缓存。
- 在存储的函数，触发器或事件的主体内执行的查询。
- 如果表更改，则使用该表的所有高速缓存查询都变为无效并从缓存中删除。

优化器会根据执行计划选择最优的选择，匹配合适的索引，选择最佳的方案。



通过非主键索引查询的执行方式是：

- 在非主键索引上找到符合条件的row的主键索引
- 根据主键索引找到需要的数据



书写查询sql的时候的顺序：

```sql
Select xxx from xxx where xxx group by xxx having xxx order by xxx limit xxx;
```



## Mysql生态系统构建介绍

![image-20220407130840511](https://cdn.jsdelivr.net/gh/oubindo/ImageBed@latest//img/image-20220407130840511.png)

存储引擎选择：

- innodb
  - 空间占用高，因为B+分裂会导致很多碎片，且不易回收。
  - 写入开销大：innodb按page更新存在写入放大，随机io多
  - 普通读性能：一般
  - 稳定性较高
- MyRocks(Rocksdb)
  - 空间占用：较小，可以在性能下降不明显的情况下提供高压缩率
  - 写入开销
  - 普通读性能：与innodb大致持平，但是排序性能低。差距很小
  - 稳定性：相比较低





























