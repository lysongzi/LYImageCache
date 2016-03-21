# LYImageCache
一个极简单的用于对UIImage图像数据进行缓存操作的库。   
这个库的实现主要参考了SDWebImage中的图片缓存的实现。   
目前只支持iOS平台，且需要启动ARC。

## 说明   
* 缓存主要为内存缓存，还有可选的磁盘缓存方式。
* 缓存可以指定磁盘缓存的目录。并提供一定的接口用于清除过期的缓存文件。

PS: 本库乃是模仿学习专用的。。要看完整的去看SDWebImage源码鸟亲。

## 部分改进
在SDWebImage中会在以下三个时刻做三种缓存清除操作。

1. 接收到UIApplicationDidReceiveMemoryWarningNotification时会把内存中的缓存都清除。   
2. 接收到UIApplicationWillTerminateNotification时，会清除磁盘上过期的缓存文件。   
3. 接收到UIApplicationDidEnterBackgroundNotification时，会请求在后台继续运行清除磁盘中过期的缓存文件。   

&emsp;&emsp;根据分析，应用一天内会多次被关闭或进入后台状态。所以可能会造成频繁的文件操作（哪怕有些时候根本就没有过期文件需要删除）。

&emsp;&emsp;所以我YY了一个小改进方案，维护一个属性记录最新一次进行磁盘缓存过期文件清理的时间，然后再设置一个值表明清理磁盘缓存的间隔期为多长（默认设置为12小时或24小时？）。只有当当前时间距离上一次磁盘缓存清理时间超过设定的时间间隔时，才去真正的执行磁盘缓存过期文件删除工作。