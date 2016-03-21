//
//  LYImageCache.m
//  LYImageCache
//
//  Created by lysongzi on 16/3/19.
//  Copyright © 2016年 lysongzi. All rights reserved.
//

#import "LYImageCache.h"
#import <CommonCrypto/CommonDigest.h>

//默认缓存数据生存期为一周
static const NSInteger defaultMaxCacheAge = 60 * 60 * 24 * 7;
static unsigned char kPNGSignatureBytes[8] = {0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A};
static NSData *kPNGSignatureData = nil;

/**
 *  返回一张图片所占内存空间大小
 *
 *  @param image 待计算大小的图片
 *
 *  @return 图片大小
 */
FOUNDATION_STATIC_INLINE NSUInteger LYCacheCostForImage(UIImage *image)
{
    return image.size.height * image.size.width * image.scale * image.scale;
}

BOOL imageDataHasPNGPreffix(NSData *data){
    
    if (!kPNGSignatureData) {
        kPNGSignatureData = [NSData dataWithBytes:kPNGSignatureBytes length:sizeof(kPNGSignatureBytes)/sizeof(char)];
    }
    
    NSUInteger pngSignatureLength = [kPNGSignatureData length];
    if ([data length] >= pngSignatureLength) {
        //判断传入的data数据头部签名部分是否和PNG头部签名是否一致
        if ([[data subdataWithRange:NSMakeRange(0, pngSignatureLength)] isEqualToData:kPNGSignatureData]) {
            return YES;
        }
    }
    
    return NO;
}

#pragma mark - LYAutoReleaseCache

/**
 定义一个NSCache子类，添加了监听内存警告通知，然后清除所有的缓存
 */
@interface LYAutoReleaseCache : NSCache
@end

@implementation LYAutoReleaseCache

- (instancetype)init
{
    if (self = [super init]) {
        //自身添加接受内存警告通知，然后清除所有内存中的缓存数据
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(removeAllObjects) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}

-(void)dealloc
{
    //移除监听通知
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
}

@end

#pragma mark - LYImageCache

/**
 *  LYImageCache
 */
@interface LYImageCache ()

{
    NSFileManager *_fileManager;
}

@property (strong, nonatomic) NSCache *memoryCache;
@property (strong, nonatomic) NSString *diskCachePath;
@property (strong, nonatomic) dispatch_queue_t ioQueue;

@end

@implementation LYImageCache

#pragma mark -

- (instancetype)init
{
    return [self initWithNamespace:@"default"];
}

- (instancetype)initWithNamespace:(NSString *)ns
{
    NSString *path = [self getPathForNamespace:ns];
    return [self initWithNamespace:ns diskCacheDirector:path];
}

- (instancetype)initWithNamespace:(NSString *)ns diskCacheDirector:(NSString *)directory
{
    if (self = [super init]) {
        //生成全命名空间
        NSString *fullNamespace = [@"com.lysongzi.LYImageCahce." stringByAppendingString:ns];
        
        //创建一个用于处理IO操作的串行队列
        _ioQueue = dispatch_queue_create("com.lysongzi.LYImageCache", DISPATCH_QUEUE_SERIAL);
        
        _memoryCache = [LYAutoReleaseCache new];
        _memoryCache.name = fullNamespace;
        
        //设置缓存目录
        if (!directory) {
            _diskCachePath = [directory stringByAppendingPathComponent:fullNamespace];
        }
        else{
            //设置缓存文件存储的目录
            NSString *defaultPath = [self getPathForNamespace:ns];
            _diskCachePath = defaultPath;
        }
        
        //默认为内存，磁盘缓存都开启
        _shouldCacheInMemory = YES;
        _shouldCahceInDisk = YES;
        
        dispatch_sync(_ioQueue, ^{
            _fileManager = [NSFileManager new];
        });
        
#if TARGET_OS_IPHONE
        //当收到内存警告时清除内存中的缓存
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clearAllCacheInDisk) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        //当应用将关闭时，清除磁盘中过期的缓存
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clearDiskExpiredCache) name:UIApplicationWillTerminateNotification object:nil];
        //当应用进入后台时候，清除磁盘中过期的缓存,需要请求后台运行
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(backgroundClearExpiredDiskCache) name:UIApplicationDidEnterBackgroundNotification object:nil];
#endif
        
    }
    return self;
}

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    //记住如果不适用ARC，这里需要手动释放GCD创建的队列。
}

#pragma mark -

- (void)setMaxMemoryCost:(NSUInteger)maxSize
{
    self.memoryCache.totalCostLimit = maxSize;
}

/**
 *  获取沙盒中的cache目录
 */
- (NSString *)getPathForNamespace:(NSString *)ns
{
    NSArray *directories = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    return [[directories firstObject] stringByAppendingPathComponent:ns];
}


/**
 *  更具键值产生对应的缓存文件名
 *  使用MD5对key进行散列操作
 *
 *  @param key 缓存文件key
 *
 *  @return key对应的缓存文件名
 */
- (NSString *)cacheFileNameForKey:(NSString *)key
{
    const char *str = [key UTF8String];
    if (!str) {
        str = "";
    }
    
    unsigned char r[CC_MD5_DIGEST_LENGTH];
    //参数一：需要散列的char*数组
    //参数二：需要散列的数据长度
    //参数三：存放散列结果的char数组
    CC_MD5(str, (CC_LONG)strlen(str), r);
    //构造一个NSString类型结果,每个字符以十六进制方式输出
    NSString *filename = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%@",
                          r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7],
                          r[8], r[9], r[10], r[11], r[12], r[13], r[14], r[15],
                          [[key pathExtension] isEqualToString:@""] ? @"" : [NSString stringWithFormat:@".%@", [key pathExtension]]];
    return filename;
}

/**
 *  根据键值和目录获取对应缓存路径
 *
 *  @param key  缓存文件key
 *  @param path 缓存文件目录
 *
 *  @return 缓存文件路径
 */
- (NSString *)cachePathForKey:(NSString *)key path:(NSString *)path
{
    NSString *filename = [self cacheFileNameForKey:key];
    return [path stringByAppendingPathComponent:filename];
}

/**
 *  返回对应key的缓存的路径
 *
 *  @param key 缓存的key
 *
 *  @return 缓存的默认文件路径
 */
- (NSString *)defaultCachePathForKey:(NSString *)key
{
    return [self cachePathForKey:key path:self.diskCachePath];
}

#pragma mark - 缓存存储/更新接口

/**
 *  存储图片数据到磁盘中。图片数据需要转化为二进制数据才会存储到磁盘中。
 *
 *  @param image   UIImage图片数据
 *  @param refetch 是否需要从UIImage中提取二进制数据
 *  @param data    二进制图像数据
 *  @param key     图片关键字
 *  @param toDisk  是否存储到磁盘中
 */
- (void)setImage:(UIImage *)image refetchDateFromImage:(BOOL)refetch imageData:(NSData *)imageData forKey:(NSString *)key toDisk:(BOOL)toDisk
{
    if (!image && !key) {
        return;
    }
    
    if (self.shouldCacheInMemory) {
        NSUInteger cost = LYCacheCostForImage(image);
        [self.memoryCache setObject:image forKey:key cost:cost];
    }
    
    if (toDisk) {
        dispatch_async(self.ioQueue, ^{
            NSData *data = imageData;
            
#if TARGET_OS_IPHONE
            //需要先判断图片时PNG还是JPG格式，然后分别用不同方式提取响应的data数据
            //PNG格式的图片前八个字节都是固定的：137 80 78 71 13 10 26 10
            if (image && (refetch || !imageData)) {
                int alphaInfo = CGImageGetAlphaInfo(image.CGImage);
                BOOL imageIsPNG = !(alphaInfo == kCGImageAlphaNone ||
                                    alphaInfo == kCGImageAlphaNoneSkipFirst ||
                                    alphaInfo == kCGImageAlphaNoneSkipLast);
                
                //如果传进来了imageData，则直接提取相应数据
                if ([imageData length] >= [kPNGSignatureData length]) {
                    imageIsPNG = imageDataHasPNGPreffix(imageData);
                }
                
                //根据不同类型图片提取图片数据
                if (imageIsPNG) {
                    data = UIImagePNGRepresentation(image);
                }
                else{
                    data = UIImageJPEGRepresentation(image, (CGFloat)1.0);
                }
            }
#endif
            if (data) {
                //如果缓存目录不存在，则创建该目录
                if (![_fileManager fileExistsAtPath:_diskCachePath]) {
                    [_fileManager createDirectoryAtPath:_diskCachePath withIntermediateDirectories:YES attributes:nil error:nil];
                }
                
                //根据image key获取缓存路径
                NSString *cachePathForKey = [self defaultCachePathForKey:key];
                
                [_fileManager createFileAtPath:cachePathForKey contents:data attributes:nil];
            }
        });
    }
}

- (void)setImage:(UIImage *)image forKey:(NSString *)key toDisk:(BOOL)toDisk
{
    [self setImage:image refetchDateFromImage:YES imageData:nil forKey:key toDisk:toDisk];
}

- (void)setImage:(UIImage *)image forKey:(NSString *)key
{
    [self setImage:image forKey:key toDisk:self.shouldCahceInDisk];
}

- (UIImage *)imageFromMemoryCacheForKey:(NSString *)key
{
    return [self.memoryCache objectForKey:key];
}

/**
 *  从磁盘中获取缓存。这里不是一开始就去磁盘查找的，为了提升性能还是现在内存中查找，如果没有才去磁盘查找。
 *
 *  @param key 缓存的key
 *
 *  @return 缓存的图像数据
 */
- (UIImage *)imageFromDiskCacheForKey:(NSString *)key
{
    UIImage *image = [self imageFromMemoryCacheForKey:key];
 
    if (image) {
        return image;
    }
    
    image = [self diskImageForKey:key];
    //为了提高效率，把该数据也缓存到内存中
    if (image && self.shouldCacheInMemory) {
        NSUInteger cost = LYCacheCostForImage(image);
        [self.memoryCache setObject:image forKey:key cost:cost];
    }
    
    return image;
}

/**
 *  根据key在缓存目录下查找是否存在对应的缓存文件
 *
 *  @param key 缓存文件的key
 *
 *  @return 返回缓存的UIImage数据
 */
- (UIImage *)diskImageForKey:(NSString *)key
{
    UIImage *image = nil;
    NSString *defaultCachePath = [self defaultCachePathForKey:key];
    
    NSData *data = [NSData dataWithContentsOfFile:defaultCachePath];
    if (data) {
        image =  [UIImage imageWithData:data];
    }
    
    data = [NSData dataWithContentsOfFile:[defaultCachePath stringByDeletingPathExtension]];
    if (data) {
        image =  [UIImage imageWithData:data];
    }
    
    if (image) {
        //如果需要对图片进行其他处理
        //但是暂时没有
    }
    
    return image;
}

#pragma mark - 缓存移除接口

- (void)removeImageForKey:(NSString *)key fromDisk:(BOOL)fromDisk withCompletion:(LYSImageNoPramaBlock)completion
{
    if (!key) {
        return;
    }
    
    //删除内存中的缓存
    if (self.shouldCacheInMemory) {
        [self.memoryCache removeObjectForKey:key];
    }

    if (fromDisk) {
        dispatch_async(self.ioQueue, ^{
            [_fileManager removeItemAtPath:[self defaultCachePathForKey:key] error:nil];
            
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion();
                });
            }
        });
    }
    else if(completion){
        //这里需要在主线程回调么?
        dispatch_async(dispatch_get_main_queue(), ^{
            completion();
        });
    }
}

- (void)removeImageForKey:(NSString *)key withCompletion:(LYSImageNoPramaBlock)completion
{
    [self removeImageForKey:key fromDisk:YES withCompletion:completion];
}

- (void)removeImageForKey:(NSString *)key fromDisk:(BOOL)fromDisk
{
    [self removeImageForKey:key fromDisk:fromDisk withCompletion:nil];
}

- (void)removeImageForKey:(NSString *)key
{
    [self removeImageForKey:key withCompletion:nil];
}

/**
 *  清除所有内存缓冲
 */
- (void)clearMemory
{
    [self.memoryCache removeAllObjects];
}

/**
 *  清除所有磁盘缓存
 */
- (void)clearDiskCache
{
    dispatch_async(self.ioQueue, ^{
        //删除缓存目录,直接把所有缓存都删除了hahahahahhaha
        [_fileManager removeItemAtPath:self.diskCachePath error:nil];
        //创建新的缓存目录
        [_fileManager createDirectoryAtPath:self.diskCachePath withIntermediateDirectories:YES attributes:nil error:nil];
    });
}

/**
 *  清除过期缓存
 *
 *  @param completion 清除完毕的回调
 */
- (void)clearDiskExpiredCacheWithCompletionBlock:(LYSImageNoPramaBlock)completion
{
    //待完成...
}

- (void)clearDiskExpiredCache
{
    [self clearDiskExpiredCacheWithCompletionBlock:nil];
}

/**
 *  在后台执行清除磁盘缓存中过期文件的操作
 */
- (void)backgroundClearExpiredDiskCache
{
    Class UIApplicationClass = NSClassFromString(@"UIApplication");
    if (!UIApplicationClass || ![UIApplicationClass respondsToSelector:@selector(sharedApplication)]) {
        return;
    }
    
    UIApplication *application = [UIApplication sharedApplication];
    //请求一个后台任务
    __block UIBackgroundTaskIdentifier bgTask = [application beginBackgroundTaskWithExpirationHandler:^{
        //如果后台任务过期/超时，则终止任务
        [application endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }];
    
    //在后台执行一个耗时的清除过期缓存的任务
    [self clearDiskExpiredCacheWithCompletionBlock:^{
        [application endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }];
}


#pragma mark - 缓存查询接口

- (BOOL)diskImageCacheExistsForKey:(NSString *)key
{
    BOOL exist = NO;
    exist = [[NSFileManager defaultManager]  fileExistsAtPath:[self defaultCachePathForKey:key]];
    
    if (!exist) {
        //删除最后一部分的扩展名再查询
        [[NSFileManager defaultManager] fileExistsAtPath:[[self defaultCachePathForKey:key] stringByDeletingPathExtension]];
    }
    return exist;
}

- (void)diskImageCacheExistsForKey:(NSString *)key withCompletion:(LYImageCheckCacheCompletionBlock)completion
{
    BOOL exist = NO;
    exist = [[NSFileManager defaultManager]  fileExistsAtPath:[self defaultCachePathForKey:key]];
    
    if (!exist) {
        //删除最后一部分的扩展名再查询
        [[NSFileManager defaultManager] fileExistsAtPath:[[self defaultCachePathForKey:key] stringByDeletingPathExtension]];
    }
    
    if (!completion) {
        //在主线程中执行回调
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(exist);
        });
    }
}



@end
