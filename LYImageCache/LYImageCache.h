//
//  LYImageCache.h
//  LYImageCache
//
//  Created by lysongzi on 16/3/19.
//  Copyright © 2016年 lysongzi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

//宏定义枚举类型
//例子: typedef NS_ENUM(_type, _name){...}
//等价于:
//typedef enum _name : _type;
//enum _name : _type {...}

#ifndef NS_ENUM
#define NS_ENUM(_type, _name) enum _name : _type; enum _name : _type
#endif

//图片缓存类型
typedef NS_ENUM(NSInteger, LYImageCacheType) {
    //不使用缓存
    LYImageCacheTypeNone,
    //使用内存缓存
    LYImageCacheTypeMemory,
    //使用磁盘缓存
    LYImageCacheTypeDisk
};

typedef void(^LYImageQueryCompletionBlock)(UIImage *image, LYImageCacheType cacheType);

typedef void(^LYImageCheckCacheCompletionBlock)(BOOL isInCache);

typedef void(^LYSImageNoPramaBlock)();

/**
 *  LYImageCache默认会将数据缓存到内存，同时也可以选择缓存到磁盘中。
 *  并且磁盘的缓存操作会使用异步的方式，所以不会阻塞主线程的UI事件。
 */

@interface LYImageCache : NSObject

/**
 *  是否使用内存缓存,默认为YES
 */
@property (assign, nonatomic) BOOL shouldCacheInMemory;

/**
 *  是否使用磁盘缓存,默认为YES
 */
@property (assign, nonatomic) BOOL shouldCahceInDisk;

/**
 *  当前内存缓存消耗的空间大小
 */
@property (assign, nonatomic) NSInteger maxCacheCost;

/**
 *  缓存的生存期，默认值为1周（7天）
 */
@property (assign, nonatomic) NSInteger maxCacheAge;

/**
 *  允许的最大缓存大小
 */
@property (assign, nonatomic) NSInteger maxCacheSize;

#pragma mark -

/**
 *  提供一个默认单例对象，用于进行图片缓存操作
 *
 *  @return LYImageCache 单例对象
 */
+ (instancetype)sharedImageCache;

/**
 *  初始化一个用于在指定的文件名中存储缓存的对象
 *
 *  @param namespace 缓存储存的文件名
 */
- (instancetype)initWithNamespace:(NSString *)ns;

/**
 *  初始化一个用于在指定目录下的指定文件中存储的对象
 *
 *  @param namespace 缓存存储的文件名
 *  @param directory 缓存存储的目录
 */
- (instancetype)initWithNamespace:(NSString *)ns diskCacheDirector:(NSString *)directory;

#pragma mark -

- (void)setImage:(UIImage *)image forKey:(NSString *)key;

- (void)setImage:(UIImage *)image forKey:(NSString *)key toDisk:(BOOL)toDisk;

- (UIImage *)imageFromMemoryCacheForKey:(NSString *)key;

- (UIImage *)imageFromDiskCacheForKey:(NSString *)key;

- (void)removeImageForKey:(NSString *)key;

- (void)removeImageForKey:(NSString *)key fromDisk:(BOOL)fromDisk;

- (void)removeImageForKey:(NSString *)key withCompletion:(LYSImageNoPramaBlock)completion;

- (void)removeImageForKey:(NSString *)key fromDisk:(BOOL)fromDisk withCompletion:(LYSImageNoPramaBlock)completion;


#pragma mark -

/**
 *  清除所有的磁盘缓存数据
 */
- (void)clearDiskCache;

/**
 *  清除磁盘中所有过期缓存。
 */
- (void)clearDiskExpiredCache;

/**
 *  清除磁盘中所有过期的缓存。这个方法不会阻塞主线程。即它会立即返回结果。
 *
 *  @param completion 该block会在所有清除操作执行完后调用。
 */
- (void)clearDiskExpiredCacheWithCompletionBlock:(LYSImageNoPramaBlock)completion;

#pragma mark -

- (BOOL)diskImageCacheExistsForKey:(NSString *)key;

- (void)diskImageCacheExistsForKey:(NSString *)key withCompletion:(LYImageCheckCacheCompletionBlock)completion;

- (NSString *)cachePathForKey:(NSString *)key path:(NSString *)path;

- (NSString *)defaultCachePathForKey:(NSString *)key;

- (NSUInteger)getDiskCacheSize;

- (NSUInteger)getDiskCacheCount;

@end
