# Redis实践经验

## 1. 有一亿个keys要统计，应该用哪种集合？

聚合统计：统计多个集合元素的聚合结果，包括：统计多个集合的共有元素（交集统计）；把两个集合相比，统计其中一个集合独有的元素（差集统计）；统计多个集合的所有元素（并集统计）。

排序统计：集合类型能对元素保序

二值状态统计：二值状态就是指集合元素的取值就只有 0 和 1 两种。

基数统计：基数统计就是指统计一个集合中不重复的元素个数

![img](https://cdn.jsdelivr.net/gh/oubindo/ImageBed@latest//img/c0bb35d0d91a62ef4ca1bd939a9b136e.jpg)

