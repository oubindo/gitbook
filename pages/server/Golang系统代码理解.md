# Golang系统代码理解

这篇文章主要是阅读及总结Golang的一些重要工具的实现原理，这些工具平时打交道比较多，针对性的熟悉他们的原理，对于后面的使用很有帮助。

这些工具主要分为以下几类：

- context
- 容器类：map, slice
- 网络类：http
- 通信类：channel，sync包
- 常用工具：singleflight

后面有新的有意思的源码分析，我也会陆续添加到这个系列中。



## Context

context是一个请求的全局上下文，可以在多个goroutine中进行安全的传递和使用。主要提供了三种能力。

- 手动取消：context.WithCancel(ctx)
- 携带数据：context.WithValue(ctx)
- 超时控制：context.WithTimeout(ctx)和context.WithDeadline(ctx)。这两个方法提供了相同的能力。



































