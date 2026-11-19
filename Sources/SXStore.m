#import "SXStore.h"
#import "SXLog.h"
#include <sys/file.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

@implementation SXStore {
	NSString *_directory;
	NSString *_path;
	NSString *_lockPath;
}

+ (instancetype)shared {
	static SXStore *instance;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
#ifdef SX_TESTING
		NSString *path = NSProcessInfo.processInfo.environment[@"SIRIX_TEST_STORE_DIR"];
#else
		NSString *path = nil;
#endif
		instance = [[SXStore alloc] initWithDirectory:path.length ? path : @"/var/mobile/Library/SiriX"];
	});
	return instance;
}

+ (dispatch_queue_t)queue {
	static dispatch_queue_t queue;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ queue = dispatch_queue_create("com.sirix.store", DISPATCH_QUEUE_SERIAL); });
	return queue;
}

- (instancetype)initWithDirectory:(NSString *)directory {
	if ((self = [super init])) {
		_directory = [directory copy];
		_path = [_directory stringByAppendingPathComponent:@"state.plist"];
		_lockPath = [_directory stringByAppendingPathComponent:@"state.lock"];
	}
	return self;
}

// Mọi lần đọc/ghi dùng cùng lock file cố định. Atomic rename không thay inode lock.
- (int)acquireLock {
	NSError *error = nil;
	if (![[NSFileManager defaultManager] createDirectoryAtPath:_directory withIntermediateDirectories:YES
			attributes:@{NSFilePosixPermissions:@0700} error:&error]) {
		SXLogErr(@"err", @"không tạo được kho SiriX: %@", error.localizedDescription);
		return -1;
	}
	int fd = open(_lockPath.fileSystemRepresentation, O_CREAT | O_RDWR | O_CLOEXEC, 0600);
	if (fd < 0) return -1;
	while (flock(fd, LOCK_EX) != 0) {
		if (errno != EINTR) { close(fd); return -1; }
	}
	return fd;
}
- (NSMutableDictionary *)readLocked {
	NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:_path];
	if (!saved && [[NSFileManager defaultManager] fileExistsAtPath:_path]) {
		SXLogErr(@"err", @"kho SiriX bị hỏng hoặc không đọc được — không ghi đè");
		return nil;
	}
	if (![saved isKindOfClass:NSDictionary.class]) saved = @{};
	NSMutableArray *history = [NSMutableArray array];
	NSArray *raw = [saved[@"history"] isKindOfClass:NSArray.class] ? saved[@"history"] : @[];
	for (id item in raw) {
		if (![item isKindOfClass:NSDictionary.class]) continue;
		if (![item[@"id"] isKindOfClass:NSString.class] || ![item[@"q"] isKindOfClass:NSString.class] || ![item[@"a"] isKindOfClass:NSString.class]) continue;
		[history addObject:item];
	}
	if (history.count > 40) [history removeObjectsInRange:NSMakeRange(0, history.count - 40)];
	NSDictionary *rawStats = [saved[@"stats"] isKindOfClass:NSDictionary.class] ? saved[@"stats"] : @{};
	NSMutableDictionary *stats = [NSMutableDictionary dictionary];
	for (NSString *key in @[@"replaced", @"kept", @"timeout", @"error", @"msAvg",
							 @"tokensIn", @"tokensOut"]) {
		id value = rawStats[key];
		if ([value isKindOfClass:NSNumber.class] && [value doubleValue] >= 0) stats[key] = value;
	}
	NSString *historyEpoch = [saved[@"historyEpoch"] isKindOfClass:NSString.class] ? saved[@"historyEpoch"] : @"initial";
	NSString *statsEpoch = [saved[@"statsEpoch"] isKindOfClass:NSString.class] ? saved[@"statsEpoch"] : @"initial";
	NSNumber *historyClearedAt = [saved[@"historyClearedAt"] isKindOfClass:NSNumber.class] ? saved[@"historyClearedAt"] : @0;
	NSNumber *statsClearedAt = [saved[@"statsClearedAt"] isKindOfClass:NSNumber.class] ? saved[@"statsClearedAt"] : @0;
	NSDictionary *statsByDay = [saved[@"statsByDay"] isKindOfClass:NSDictionary.class]
		? saved[@"statsByDay"] : @{};
	return [@{@"history": history, @"stats": stats, @"statsByDay": statsByDay,
			  @"historyEpoch": historyEpoch, @"statsEpoch": statsEpoch,
		@"historyClearedAt": historyClearedAt, @"statsClearedAt": statsClearedAt} mutableCopy];
}
- (BOOL)writeLocked:(NSDictionary *)state {
	NSError *error = nil;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:state format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
	if (!data) return NO;
	NSString *template = [_directory stringByAppendingPathComponent:@"state.tmp.XXXXXX"];
	char *name = strdup(template.fileSystemRepresentation);
	if (!name) return NO;
	int fd = mkstemp(name);
	BOOL ok = fd >= 0;
	if (ok) {
		(void)fchmod(fd, 0600);
		const uint8_t *bytes = data.bytes;
		NSUInteger remaining = data.length;
		while (remaining) {
			ssize_t n = write(fd, bytes, remaining);
			if (n < 0 && errno == EINTR) continue;
			if (n <= 0) { ok = NO; break; }
			bytes += n; remaining -= (NSUInteger)n;
		}
		if (ok && fsync(fd) != 0) ok = NO;
		if (close(fd) != 0) ok = NO;
		if (ok && rename(name, _path.fileSystemRepresentation) != 0) ok = NO;
	}
	if (!ok) unlink(name);
	free(name);
	if (!ok) SXLogErr(@"err", @"không ghi được kho SiriX");
	return ok;
}
- (nullable NSDictionary *)snapshot {
	int fd = [self acquireLock];
	if (fd < 0) return nil;
	NSDictionary *result = [[self readLocked] copy];
	flock(fd, LOCK_UN); close(fd);
	return result;
}
- (BOOL)appendQuestion:(NSString *)question answer:(NSString *)answer limit:(NSUInteger)limit epoch:(NSString *)epoch startedAt:(NSTimeInterval)startedAt {
	if (!question.length || !answer.length || !epoch.length) return NO;
	int fd = [self acquireLock];
	if (fd < 0) return NO;
	NSMutableDictionary *state = [self readLocked];
	if (!state) { flock(fd, LOCK_UN); close(fd); return NO; }
	BOOL ok = NO;
	if ([state[@"historyEpoch"] isEqualToString:epoch] && startedAt > [state[@"historyClearedAt"] doubleValue]) {
		NSMutableArray *items = [state[@"history"] mutableCopy];
		[items addObject:@{@"id": NSUUID.UUID.UUIDString, @"q": question, @"a": answer, @"date": NSDate.date}];
		// Kho giữ tối đa 40 lượt để UI lịch sử vẫn đọc được; `limit` (ngữ cảnh) có thể 0.
		NSUInteger max = MIN(MAX(limit, (NSUInteger)1), (NSUInteger)40);
		while (items.count > max) [items removeObjectAtIndex:0];
		state[@"history"] = items;
		ok = [self writeLocked:state];
	}
	flock(fd, LOCK_UN); close(fd);
	return ok;
}
- (BOOL)deleteHistoryID:(NSString *)identifier {
	int fd = [self acquireLock]; if (fd < 0) return NO;
	NSMutableDictionary *state = [self readLocked];
	if (!state) { flock(fd, LOCK_UN); close(fd); return NO; }
	NSMutableArray *items = [state[@"history"] mutableCopy];
	NSIndexSet *indices = [items indexesOfObjectsPassingTest:^BOOL(id item, NSUInteger index, BOOL *stop) {
		(void)index; (void)stop;
		return [item isKindOfClass:NSDictionary.class] && [item[@"id"] isEqual:identifier];
	}];
	[items removeObjectsAtIndexes:indices];
	state[@"history"] = items;
	BOOL ok = [self writeLocked:state];
	flock(fd, LOCK_UN); close(fd); return ok;
}
- (BOOL)clearHistory {
	int fd = [self acquireLock]; if (fd < 0) return NO;
	NSMutableDictionary *state = [self readLocked];
	if (!state) { flock(fd, LOCK_UN); close(fd); return NO; }
	state[@"history"] = @[];
	state[@"historyEpoch"] = NSUUID.UUID.UUIDString;
	state[@"historyClearedAt"] = @(CFAbsoluteTimeGetCurrent());
	BOOL ok = [self writeLocked:state];
	flock(fd, LOCK_UN); close(fd); return ok;
}
/// Khoá ngày (giờ máy) cho thống kê theo ngày — "2026-11-19".
static NSString *SXStoreDayKey(NSDate *date) {
	static NSDateFormatter *formatter;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		formatter = [[NSDateFormatter alloc] init];
		formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
		formatter.dateFormat = @"yyyy-MM-dd";
	});
	return [formatter stringFromDate:date ?: [NSDate date]];
}

- (BOOL)recordEvent:(NSString *)event milliseconds:(NSNumber *)milliseconds epoch:(NSString *)epoch startedAt:(NSTimeInterval)startedAt {
	return [self recordEvent:event milliseconds:milliseconds tokens:nil epoch:epoch startedAt:startedAt];
}

- (BOOL)recordEvent:(NSString *)event milliseconds:(NSNumber *)milliseconds
			 tokens:(NSDictionary *)tokens epoch:(NSString *)epoch startedAt:(NSTimeInterval)startedAt {
	if (![@[@"replaced", @"kept", @"timeout", @"error"] containsObject:event] || !epoch.length) return NO;
	int fd = [self acquireLock]; if (fd < 0) return NO;
	NSMutableDictionary *state = [self readLocked];
	if (!state) { flock(fd, LOCK_UN); close(fd); return NO; }
	BOOL ok = NO;
	if ([state[@"statsEpoch"] isEqualToString:epoch] && startedAt > [state[@"statsClearedAt"] doubleValue]) {
		NSMutableDictionary *stats = [state[@"stats"] mutableCopy];
		stats[event] = @([stats[event] integerValue] + 1);
		if (milliseconds && milliseconds.doubleValue >= 0) {
			double previous = [stats[@"msAvg"] doubleValue];
			stats[@"msAvg"] = @(stats[@"msAvg"] ? 0.2 * milliseconds.doubleValue + 0.8 * previous : milliseconds.doubleValue);
		}
		// Số token máy chủ báo: cộng dồn để Thống kê hiện chi phí thật của ngày.
		NSInteger in = [tokens[@"in"] integerValue];
		NSInteger out = [tokens[@"out"] integerValue];
		if (in > 0) stats[@"tokensIn"] = @([stats[@"tokensIn"] integerValue] + in);
		if (out > 0) stats[@"tokensOut"] = @([stats[@"tokensOut"] integerValue] + out);
		state[@"stats"] = stats;

		// Số liệu theo ngày: đủ để vẽ 7 ngày gần nhất mà không phình tệp.
		NSMutableDictionary *byDay = [state[@"statsByDay"] isKindOfClass:[NSDictionary class]]
			? [state[@"statsByDay"] mutableCopy] : [NSMutableDictionary dictionary];
		NSString *day = SXStoreDayKey([NSDate date]);
		NSMutableDictionary *bucket = [byDay[day] isKindOfClass:[NSDictionary class]]
			? [byDay[day] mutableCopy] : [NSMutableDictionary dictionary];
		bucket[event] = @([bucket[event] integerValue] + 1);
		if (in > 0) bucket[@"tokensIn"] = @([bucket[@"tokensIn"] integerValue] + in);
		if (out > 0) bucket[@"tokensOut"] = @([bucket[@"tokensOut"] integerValue] + out);
		if (milliseconds && milliseconds.doubleValue >= 0) {
			double previous = [bucket[@"msAvg"] doubleValue];
			bucket[@"msAvg"] = @(bucket[@"msAvg"] ? 0.2 * milliseconds.doubleValue + 0.8 * previous
												  : milliseconds.doubleValue);
		}
		byDay[day] = bucket;
		if (byDay.count > 7) {
			NSArray *keys = [[byDay allKeys] sortedArrayUsingSelector:@selector(compare:)];
			for (NSUInteger i = 0; i + 7 < keys.count; i++) [byDay removeObjectForKey:keys[i]];
		}
		state[@"statsByDay"] = byDay;
		ok = [self writeLocked:state];
	}
	flock(fd, LOCK_UN); close(fd); return ok;
}
- (BOOL)clearStats {
	int fd = [self acquireLock]; if (fd < 0) return NO;
	NSMutableDictionary *state = [self readLocked];
	if (!state) { flock(fd, LOCK_UN); close(fd); return NO; }
	state[@"stats"] = @{};
	state[@"statsByDay"] = @{};
	state[@"statsEpoch"] = NSUUID.UUID.UUIDString;
	state[@"statsClearedAt"] = @(CFAbsoluteTimeGetCurrent());
	BOOL ok = [self writeLocked:state];
	flock(fd, LOCK_UN); close(fd); return ok;
}
@end
