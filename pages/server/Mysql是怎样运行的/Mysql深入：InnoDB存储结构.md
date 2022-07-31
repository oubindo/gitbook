# Mysql深入：InnoDB存储结构

## 一.存储格式

InnoDB以页作为磁盘和内存之间交互的基本单位，页的大小一般是16k。

InnoDB有四种行格式：compact, redundant, dynamic, compressed。默认为dynamic。dynamic与compact的格式类似，下面以compact的格式为例。

![image.png](https://cdn.jsdelivr.net/gh/oubindo/ImageBed@latest//img/4beb83ce7efa4ed99596da1f82241e33~tplv-k3u1fbpfcp-zoom-in-crop-mark:1304:0:0:0.awebp)

MySQL中有一些变长字段类型，如 VARCHAR(M)、TEXT、BLOB 等，变长字段的长度是不固定的，所以在存储数据的时候要把这些数据占用的字节数也存起来，读取数据的时候才能根据这个长度列表去读取对应长度的数据。

**变长字段长度列表** 就是用来记录一行中所有变长字段的真实数据所占用的字节长度，并且各变长字段数据占用的字节数是按照列的顺序`逆序存放`。变长字段长度列表中只存储值为`非NULL`的列内容占用的长度，值为 NULL 的列的长度是不储存的。如果表中所有的列都不是变长的数据类型的话，就不需要变长字段长度列表了。若变长字段的长度小于 255字节，就用`1字节`表示；若大于 255字节，用`2字节`表示，最大不会不超过`2字节`，因为MySQL中VARCHAR类型的最大字节长度限制为`65535`。对于一些占用字节数非常多的字段，比方说某个字段长度大于了16KB，那么如果该记录在单个页面中无法存储时，InnoDB会把一部分数据存放到所谓的`溢出页`中，在变长字段长度列表处只存储留在本页面中的长度

**NULL值列表**：表中的某些列可能会存储NULL值，如果把这些NULL值都放到记录的真实数据中会比较浪费空间，所以Compact行格式把这些值为NULL的列存储到NULL值列表中

**记录头信息**是由固定的5个字节组成，5个字节也就是40个二进制位，不同的位代表不同的意思，这些头信息会在后面的一些功能中看到。

![image.png](https://cdn.jsdelivr.net/gh/oubindo/ImageBed@latest//img/ea1713e3b7c944ca9ab94862c4af1ba9~tplv-k3u1fbpfcp-zoom-in-crop-mark:1304:0:0:0.awebp)

**真实数据**中，除了用户输入的数据外，数据库会默认为每条记录新生成row_id（无主键的时候生成）, trx_id, roll_ptr。



## 二.数据页结构

数据页由七个部分组成。

![image.png](https://cdn.jsdelivr.net/gh/oubindo/ImageBed@latest//img/6d066e690d22484ebe33bbb4977c3cfb~tplv-k3u1fbpfcp-zoom-in-crop-mark:1304:0:0:0.awebp)









