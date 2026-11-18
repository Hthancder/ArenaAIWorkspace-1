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
	for (NSString *key in @[@"replaced", @"kept", @"timeout", @"error", @"stt_ok", @"stt_fb", @"tts_ok", @"tts_fb", @"msAvg"]) {
		id value = rawStats[key];
		if ([value isKindOfClass:NSNumber.class] && [value doubleValue] >= 0) stats[key] = value;
	}
	NSString *historyEpoch = [saved[@"historyEpoch"] isKindOfClass:NSString.class] ? saved[@"historyEpoch"] : @"initial";
	NSString *statsEpoch = [saved[@"statsEpoch"] isKindOfClass:NSString.class] ? saved[@"statsEpoch"] : @"initial";
	NSNumber *historyClearedAt = [saved[@"historyClearedAt"] isKindOfClass:NSNumber.class] ? saved[@"historyClearedAt"] : @0;
	NSNumber *statsClearedAt = [saved[@"statsClearedAt"] isKindOfClass:NSNumber.class] ? saved[@"statsClearedAt"] : @0;
	NSMutableDictionary *state = [@{@"history": history, @"stats": stats, @"historyEpoch": historyEpoch, @"statsEpoch": statsEpoch,
		@"historyClearedAt": historyClearedAt, @"statsClearedAt": statsClearedAt} mutableCopy];
	if ([saved[@"sttTrial"] isKindOfClass:NSDictionary.class]) state[@"sttTrial"] = saved[@"sttTrial"];
	return state;
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
		NSUInteger max = MAX(1, MIN(limit, 40));
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
- (BOOL)recordEvent:(NSString *)event milliseconds:(NSNumber *)milliseconds epoch:(NSString *)epoch startedAt:(NSTimeInterval)startedAt {
	if (![@[@"replaced", @"kept", @"timeout", @"error", @"stt_ok", @"stt_fb", @"tts_ok", @"tts_fb"] containsObject:event] || !epoch.length) return NO;
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
		state[@"stats"] = stats;
		ok = [self writeLocked:state];
	}
	flock(fd, LOCK_UN); close(fd); return ok;
}
- (BOOL)clearStats {
	int fd = [self acquireLock]; if (fd < 0) return NO;
	NSMutableDictionary *state = [self readLocked];
	if (!state) { flock(fd, LOCK_UN); close(fd); return NO; }
	state[@"stats"] = @{};
	state[@"statsEpoch"] = NSUUID.UUID.UUIDString;
	state[@"statsClearedAt"] = @(CFAbsoluteTimeGetCurrent());
	BOOL ok = [self writeLocked:state];
	flock(fd, LOCK_UN); close(fd); return ok;
}
- (BOOL)armSTTTrial {
	int fd = [self acquireLock]; if (fd < 0) return NO;
	NSMutableDictionary *state = [self readLocked];
	NSTimeInterval now = CFAbsoluteTimeGetCurrent();
	state[@"sttTrial"] = @{@"id": NSUUID.UUID.UUIDString, @"armedAt": @(now), @"expires": @(now + 60), @"status": @"waiting"};
	BOOL ok = state && [self writeLocked:state];
	flock(fd, LOCK_UN); close(fd); return ok;
}
- (NSString *)claimSTTTrialStartedAt:(NSTimeInterval)startedAt {
	int fd = [self acquireLock]; if (fd < 0) return nil;
	NSMutableDictionary *state = [self readLocked];
	NSMutableDictionary *trial = [state[@"sttTrial"] mutableCopy];
	NSString *identifier = nil;
	if ([trial[@"status"] isEqual:@"waiting"] && [trial[@"id"] isKindOfClass:NSString.class] &&
		[trial[@"armedAt"] isKindOfClass:NSNumber.class] && [trial[@"expires"] isKindOfClass:NSNumber.class] &&
		startedAt >= [trial[@"armedAt"] doubleValue] && CFAbsoluteTimeGetCurrent() <= [trial[@"expires"] doubleValue]) {
		trial[@"status"] = @"running"; state[@"sttTrial"] = trial;
		if ([self writeLocked:state]) identifier = trial[@"id"];
	}
	flock(fd, LOCK_UN); close(fd); return identifier;
}
- (BOOL)finishSTTTrial:(NSString *)identifier success:(BOOL)success {
	int fd = [self acquireLock]; if (fd < 0) return NO;
	NSMutableDictionary *state = [self readLocked];
	NSMutableDictionary *trial = [state[@"sttTrial"] mutableCopy];
	BOOL ok = NO;
	if ([trial[@"id"] isEqual:identifier] && [trial[@"status"] isEqual:@"running"]) {
		trial[@"status"] = success ? @"ok" : @"fallback"; state[@"sttTrial"] = trial;
		ok = [self writeLocked:state];
	}
	flock(fd, LOCK_UN); close(fd); return ok;
}
@end
