//
//  JMImageCache.m
//  JMCache
//
//  Created by Jake Marsh on 2/7/11.
//  Copyright 2011 Rubber Duck Software. All rights reserved.
//

#import "JMImageCache.h"

NSString * const JMImageCacheDownloadStartNotification = @"JMImageCacheDownloadStart";
NSString * const JMImageCacheDownloadStopNotification = @"JMImageCacheDownloadStop";
NSString * const JMImageCacheDownloadURLKey = @"url";


static NSString* _JMImageCacheDirectory;

static inline NSString* JMImageCacheDirectory() {
	if(!_JMImageCacheDirectory) {
		_JMImageCacheDirectory = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/JMCache"] copy];
	}

	return _JMImageCacheDirectory;
}


inline static NSString* keyForURL(NSString *url) {
	return [NSString stringWithFormat:@"JMImageCache-%u", [url hash]];
}


static inline NSString* cachePathForURL(NSString* key) {
	return [JMImageCacheDirectory() stringByAppendingPathComponent:keyForURL(key)];
}

JMImageCache *_sharedCache = nil;

@implementation JMImageCache

+ (JMImageCache *) sharedCache {
	if(!_sharedCache) {
		_sharedCache = [[JMImageCache alloc] init];
	}

	return _sharedCache;
}

+ (dispatch_queue_t)downloadQueue {
    static dispatch_queue_t jmDownloadQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        jmDownloadQueue = dispatch_queue_create("com.jmimagecache.downloadqueue", DISPATCH_QUEUE_CONCURRENT);
    });
    return jmDownloadQueue;
}

- (id) init {
	if((self = [super init])) {
		_diskOperationQueue = [[NSOperationQueue alloc] init];

		[[NSFileManager defaultManager] createDirectoryAtPath:JMImageCacheDirectory() 
							 withIntermediateDirectories:YES 
										   attributes:nil 
											   error:NULL];
	}
	
	return self;
}


#pragma mark -
#pragma mark Getter Methods

- (UIImage *) imageForURL:(NSString *)url delegate:(id<JMImageCacheDelegate>)d {
	if(!url) {
		return nil;
	}

	id returner = [super objectForKey:url];

	if(returner) {
		return returner;
	} else {
		UIImage *i = [self imageFromDiskForURL:url];
		if(i) {
			[self setImage:i forURL:url];

			return i;
		}

		dispatch_async([JMImageCache downloadQueue], ^{
            NSDictionary *infoDictionary = [NSDictionary dictionaryWithObject:url forKey:JMImageCacheDownloadURLKey];
            [[NSNotificationCenter defaultCenter] postNotificationName:JMImageCacheDownloadStartNotification object:self userInfo:infoDictionary];
			NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:url]];
            [[NSNotificationCenter defaultCenter] postNotificationName:JMImageCacheDownloadStopNotification object:self userInfo:infoDictionary];
			UIImage *i = [[UIImage alloc] initWithData:data];

			NSString* cachePath = cachePathForURL(url);
			NSInvocation* writeInvocation = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(writeData:toPath:)]];
			[writeInvocation setTarget:self];
			[writeInvocation setSelector:@selector(writeData:toPath:)];
			[writeInvocation setArgument:&data atIndex:2];
			[writeInvocation setArgument:&cachePath atIndex:3];

			[self performDiskWriteOperation:writeInvocation];
			[self setImage:i forURL:url];

			dispatch_async(dispatch_get_main_queue(), ^{
				if(d) {
					if([d respondsToSelector:@selector(cache:didDownloadImage:forURL:)]) {
						[d cache:self didDownloadImage:i forURL:url];
					}
				}
			});
		});

		return nil;
	}
}

- (UIImage *)imageForURL:(NSString *)url completion:(void (^)(UIImage *image))completion {
    if(!url) {
		return nil;
	}
    
	id returner = [super objectForKey:url];
    
	if(returner) {
		return returner;
	} else {
		UIImage *i = [self imageFromDiskForURL:url];
		if(i) {
			[self setImage:i forURL:url];
            
			return i;
		}
        __weak JMImageCache *weakSelf = self;
		dispatch_async([JMImageCache downloadQueue], ^{
            NSDictionary *infoDictionary = [NSDictionary dictionaryWithObject:url forKey:@"url"];
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:JMImageCacheDownloadStartNotification object:self userInfo:infoDictionary];
            });
            
			NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:url]];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:JMImageCacheDownloadStopNotification object:self userInfo:infoDictionary];
            });
            
			UIImage *i = [[UIImage alloc] initWithData:data];
            
			NSString* cachePath = cachePathForURL(url);
			NSInvocation* writeInvocation = [NSInvocation invocationWithMethodSignature:[weakSelf methodSignatureForSelector:@selector(writeData:toPath:)]];
			[writeInvocation setTarget:weakSelf];
			[writeInvocation setSelector:@selector(writeData:toPath:)];
			[writeInvocation setArgument:&data atIndex:2];
			[writeInvocation setArgument:&cachePath atIndex:3];
            
			[weakSelf performDiskWriteOperation:writeInvocation];
			[weakSelf setImage:i forURL:url];
            
			dispatch_async(dispatch_get_main_queue(), ^{
				if(completion) {
                    completion(i);
                }
			});
		});
        
		return nil;
	}
}

- (UIImage *) imageFromDiskForURL:(NSString *)url {
	UIImage *i = [[UIImage alloc] initWithData:[NSData dataWithContentsOfFile:cachePathForURL(url) options:0 error:NULL]];

	return i;
}


#pragma mark -
#pragma mark Setter Methods

- (void) setImage:(UIImage *)i forURL:(NSString *)url {
	if (i) {
		[super setObject:i forKey:url];
	}
}


- (void) removeImageForURL:(NSString *)url {
	[super removeObjectForKey:keyForURL(url)];
}


#pragma mark -
#pragma mark Disk Writing Operations

- (void) writeData:(NSData*)data toPath:(NSString *)path {
	[data writeToFile:path atomically:YES];
}


- (void) performDiskWriteOperation:(NSInvocation *)invoction {
	NSInvocationOperation *operation = [[NSInvocationOperation alloc] initWithInvocation:invoction];
	[_diskOperationQueue addOperation:operation];
}


@end
