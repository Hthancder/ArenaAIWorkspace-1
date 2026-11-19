#import <Foundation/Foundation.h>
#import "SXStore.h"
#import "SXLog.h"
#include <assert.h>
#include <sys/stat.h>
void SXLogWrite(SXLogLevel level, NSString *category, NSString *format, ...) { (void)level; (void)category; (void)format; }
int main(void) {
	@autoreleasepool {
		NSString *dir = NSProcessInfo.processInfo.environment[@"SIRIX_TEST_STORE_DIR"];
		assert(dir.length);
		SXStore *store = [[SXStore alloc] initWithDirectory:dir];
		NSDictionary *snapshot = [store snapshot];
		assert(snapshot);
		NSString *epoch = snapshot[@"historyEpoch"];
		NSTimeInterval startedAt = CFAbsoluteTimeGetCurrent();
		assert([store appendQuestion:@"q1" answer:@"a1" limit:2 epoch:epoch startedAt:startedAt]);
		assert([store appendQuestion:@"q2" answer:@"a2" limit:2 epoch:epoch startedAt:startedAt]);
		assert([store appendQuestion:@"q3" answer:@"a3" limit:2 epoch:epoch startedAt:startedAt]);
		snapshot = [store snapshot];
		NSArray *history = snapshot[@"history"];
		assert(history.count == 2 && [history[0][@"q"] isEqualToString:@"q2"]);
		assert([store deleteHistoryID:history[0][@"id"]]);
		assert([[[store snapshot] objectForKey:@"history"] count] == 1);
		assert([store clearHistory]);
		assert(![store appendQuestion:@"old" answer:@"old" limit:2 epoch:epoch startedAt:startedAt]);
		assert([[[store snapshot] objectForKey:@"history"] count] == 0);
		// Snapshot có thể xảy ra sau reset dù câu hỏi bắt đầu trước reset.
		NSString *newEpoch = [store snapshot][@"historyEpoch"];
		assert(![store appendQuestion:@"before" answer:@"after" limit:2 epoch:newEpoch startedAt:startedAt]);
		NSString *statsEpoch = [store snapshot][@"statsEpoch"];
		dispatch_group_t group = dispatch_group_create();
		for (int i = 0; i < 50; i++) dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
			assert([store recordEvent:@"replaced" milliseconds:nil epoch:statsEpoch startedAt:startedAt]);
		});
		assert(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)) == 0);
		assert([[[store snapshot][@"stats"] objectForKey:@"replaced"] integerValue] == 50);
		assert([store recordEvent:@"error" milliseconds:@100 epoch:statsEpoch startedAt:startedAt]);
		assert([store recordEvent:@"error" milliseconds:@200 epoch:statsEpoch startedAt:startedAt]);
		assert([[[store snapshot][@"stats"] objectForKey:@"msAvg"] intValue] == 120);
		// Token: cộng dồn cả tổng lẫn theo ngày, bỏ qua giá trị âm/thiếu.
		assert([store recordEvent:@"replaced" milliseconds:nil
						   tokens:@{@"in": @120, @"out": @45} epoch:statsEpoch startedAt:startedAt]);
		assert([store recordEvent:@"replaced" milliseconds:nil
						   tokens:@{@"in": @80, @"out": @30} epoch:statsEpoch startedAt:startedAt]);
		NSDictionary *tokenStats = [store snapshot][@"stats"];
		assert([tokenStats[@"tokensIn"] integerValue] == 200);
		assert([tokenStats[@"tokensOut"] integerValue] == 75);
		NSDictionary *byDay = [store snapshot][@"statsByDay"];
		assert(byDay.count >= 1);
		NSDictionary *today = nil;
		for (NSString *key in byDay) today = byDay[key];
		assert([today[@"tokensIn"] integerValue] >= 200);

		assert([store clearStats]);
		assert(![store recordEvent:@"error" milliseconds:nil epoch:statsEpoch startedAt:startedAt]);
		assert([[[store snapshot] objectForKey:@"stats"] count] == 0);
		assert(![store recordEvent:@"error" milliseconds:nil epoch:[store snapshot][@"statsEpoch"] startedAt:startedAt]);
		struct stat st;
		assert(stat([[dir stringByAppendingPathComponent:@"state.plist"] fileSystemRepresentation], &st) == 0);
		assert((st.st_mode & 0777) == 0600);
		puts("store regression tests: OK");
	}
	return 0;
}
