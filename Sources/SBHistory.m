#import "SBHistory.h"
#import "SBConfig.h"

@interface SBHistory ()
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *items;
@end

@implementation SBHistory

+ (instancetype)shared {
    static SBHistory *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SBHistory new]; });
    return s;
}

- (id)init {
    if ((self = [super init])) { _items = [NSMutableArray array]; }
    return self;
}

- (void)addUser:(NSString *)text {
    if (!text.length) return;
    @synchronized (self) { [_items addObject:@{@"role": @"user", @"content": text}]; [self trim]; }
}

- (void)addAssistant:(NSString *)text {
    if (!text.length) return;
    @synchronized (self) { [_items addObject:@{@"role": @"assistant", @"content": text}]; [self trim]; }
}

- (void)trim {
    NSInteger keep = MAX(0, SBConfig.shared.historyTurns) * 2;
    while ((NSInteger)_items.count > keep && _items.count > 0) [_items removeObjectAtIndex:0];
}

- (NSArray<NSDictionary *> *)messages {
    @synchronized (self) { return [_items copy]; }
}

- (void)reset { @synchronized (self) { [_items removeAllObjects]; } }

@end
