// Chạy trên macOS Foundation: kiểm thử SXIntercept thật với ACE/LLM giả.
#import <Foundation/Foundation.h>
#import "SXIntercept.h"
#import "SXPrefs.h"
#import "SXLLM.h"
#import "SXTools.h"
#import "SXLog.h"
#import "SXMarkdown.h"
#import "SXStore.h"
#import "SXTTS.h"
#include <assert.h>

static SXLLMCompletion pendingCompletion;
static dispatch_semaphore_t requestStarted;
static SXReplyMode testMode = SXReplyModeFull;
static NSString *testTimeoutAction = @"bubble";
static NSString *testTriggerMode = @"auto";
static NSString *lastQuestion;
static BOOL testShowOriginal;
static BOOL testIncognito, testLocalOnly, testDeferred;
static NSString *testFallback, *lastModel;
static NSString *testTTSMode = @"off";
static SXRequest *lastRequest;

@implementation SXPrefs
+ (instancetype)shared { static SXPrefs *p; static dispatch_once_t once; dispatch_once(&once, ^{ p = [SXPrefs new]; }); return p; }
- (BOOL)enabled { return YES; }
- (NSString *)triggerMode { return testTriggerMode; }
- (SXReplyMode)mode { return testMode; }
- (NSTimeInterval)responseTimeout { return 2; }
- (BOOL)markdown { return NO; }
- (BOOL)hideWebCards { return YES; }
- (BOOL)showOriginal { return testShowOriginal; }
- (BOOL)incognito { return testIncognito; }
- (NSString *)ttsMode { return testTTSMode; }
- (NSString *)ttsSource { return @"system"; }
- (BOOL)localOnly { return testLocalOnly; }
- (BOOL)deferredReplies { return testDeferred; }
- (NSString *)fallbackModelForProvider:(SXProvider)provider { (void)provider; return testFallback ?: @""; }
- (NSString *)activeModel { return @"primary"; }
- (SXPrefs *)snapshot { return self; }
- (NSString *)timeoutAction { return testTimeoutAction; }
- (NSInteger)contextTurns { return 8; }
@end
@implementation SXLLM
+ (void)performQuestion:(NSString *)question history:(NSArray *)history tools:(NSArray *)tools executor:(SXToolExec)executor
	prefs:(SXPrefs *)prefs provider:(SXProvider)provider model:(NSString *)model prompt:(NSString *)prompt maxTokens:(NSUInteger)maxTokens
	request:(SXRequest *)request progress:(SXStreamProgress)progress completion:(SXLLMCompletion)completion {
	lastQuestion = [question copy]; lastModel = [model copy]; lastRequest = request;
	(void)history; (void)tools; (void)executor; (void)prefs; (void)provider; (void)prompt; (void)maxTokens; (void)progress;
	pendingCompletion = [completion copy];
	dispatch_semaphore_signal(requestStarted);
}
@end
@implementation SXTools
+ (NSArray *)definitionsForPrefs:(SXPrefs *)prefs question:(NSString *)question { (void)prefs; (void)question; return @[]; }
+ (NSDictionary *)execute:(NSString *)name arguments:(NSDictionary *)arguments question:(NSString *)question request:(SXRequest *)request error:(NSError **)error {
	(void)name; (void)arguments; (void)question; (void)request; (void)error; return nil;
}
@end
@implementation SXTTSPlan
@end
BOOL SXTTSModeAllows(NSString *mode, BOOL isAnswer) {
	return [mode isEqual:@"all"] || [mode isEqual:(isAnswer ? @"ai" : @"errors")];
}
SXTTSPlan *SXTTSSystemPlan(NSString *text, SXPrefs *prefs) { (void)text; (void)prefs; return [SXTTSPlan new]; }
SXTTSPlan *SXTTSPrepare(NSString *text, SXPrefs *prefs, SXRequest *request) { (void)request; return SXTTSSystemPlan(text, prefs); }
void SXTTSPlay(SXTTSPlan *plan, void (^result)(BOOL)) { (void)plan; if (result) result(YES); }
void SXTTSStop(void) {}
NSString *SXMarkdownRender(NSString *text) { return text; }
void SXLogWrite(SXLogLevel level, NSString *category, NSString *format, ...) { (void)level; (void)category; (void)format; }

@interface FakeView : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *speakableText;
@end
@implementation FakeView
@end
@interface FailingView : FakeView
@end
@implementation FailingView
- (void)setText:(NSString *)text {
	[super setText:text];
	if ([text isEqualToString:@"throws"]) [NSException raise:@"test" format:@"setter failed"];
}
@end
@interface FakeAddViews : NSObject
@property (nonatomic, copy) NSArray *views;
@end
@implementation FakeAddViews
@end
@interface FakeSayIt : NSObject
@property (nonatomic, copy) NSString *message;
@end
@implementation FakeSayIt
@end
@interface FakeAlarm : NSObject
@end
@implementation FakeAlarm
@end

static void begin(NSString *question) {
	[[SXIntercept shared] noteQuestion:question source:@"test"];
	assert(dispatch_semaphore_wait(requestStarted, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
}
static FakeAddViews *viewCommand(void) {
	FakeView *view = [FakeView new]; view.text = @"Siri gốc"; view.speakableText = @"Siri gốc";
	FakeAddViews *command = [FakeAddViews new]; command.views = @[view]; return command;
}
static FakeSayIt *sayCommand(void) {
	FakeSayIt *command = [FakeSayIt new]; command.message = @"Siri gốc"; return command;
}
int main(void) {
	@autoreleasepool {
		requestStarted = dispatch_semaphore_create(0);
		SXIntercept *intercept = [SXIntercept shared];

		begin(@"question one");
		pendingCompletion(@"AI answer", nil, nil);
		FakeAddViews *views = viewCommand();
		assert([intercept handleIncomingCommand:views]);
		assert([((FakeView *)views.views[0]).text isEqualToString:@"AI answer"]);
		assert([intercept handleAddViewsInsertion:views]); // cùng object qua cả hai hook
		assert(views.views.count == 1);
		FakeSayIt *say = sayCommand();
		assert([intercept handleIncomingCommand:say]);
		assert([say.message isEqualToString:@"AI answer"]);
		FakeAddViews *next = viewCommand();
		assert([intercept handleIncomingCommand:next]);
		assert([((FakeView *)next.views[0]).text isEqualToString:@"AI answer"]);

		// Chỉ hiển thị câu gốc, không đọc footer bằng giọng nói.
		testShowOriginal = YES;
		begin(@"question original");
		pendingCompletion(@"answer", nil, nil);
		views = viewCommand(); assert([intercept handleIncomingCommand:views]);
		assert([((FakeView *)views.views[0]).text containsString:@"Siri: Siri gốc"]);
		assert([((FakeView *)views.views[0]).speakableText isEqualToString:@"answer"]);
		testShowOriginal = NO;

		// Lệnh không sửa được không được chặn lệnh tiếp theo thử lại.
		begin(@"question two");
		pendingCompletion(@"second answer", nil, nil);
		assert(![intercept handleIncomingCommand:[FakeAddViews new]]);
		say = sayCommand();
		assert([intercept handleIncomingCommand:say]);
		assert([say.message isEqualToString:@"second answer"]);

		// Setter hỏng sau khi ghi: rollback cả text lẫn speakableText.
		begin(@"question rollback");
		pendingCompletion(@"throws", nil, nil);
		FailingView *broken = [FailingView new]; broken.text = @"old"; broken.speakableText = @"old voice";
		views = [FakeAddViews new]; views.views = @[broken];
		assert(![intercept handleIncomingCommand:views]);
		assert([broken.text isEqualToString:@"old"] && [broken.speakableText isEqualToString:@"old voice"]);
		say = sayCommand(); assert([intercept handleIncomingCommand:say]);
		assert([say.message isEqualToString:@"throws"]);

		// Đáp án cũ không được ghi đè khi câu hỏi mới đã bắt đầu.
		begin(@"question stale");
		SXLLMCompletion stale = pendingCompletion;
		begin(@"question fresh");
		stale(@"stale answer", nil, nil);
		pendingCompletion(@"fresh answer", nil, nil);
		say = sayCommand(); assert([intercept handleIncomingCommand:say]);
		assert([say.message isEqualToString:@"fresh answer"]);

		// Lỗi và timeout bubble cũng phải nhất quán giữa AddViews và SayIt.
		begin(@"question error");
		pendingCompletion(nil, [NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"lỗi thử"}], nil);
		views = viewCommand(); assert([intercept handleIncomingCommand:views]);
		say = sayCommand(); assert([intercept handleIncomingCommand:say]);
		assert([((FakeView *)views.views[0]).text containsString:@"lỗi thử"]);
		assert([say.message isEqual:@""]);
		testDeferred = YES;
		begin(@"question timeout");
		views = viewCommand(); assert([intercept handleIncomingCommand:views]);
		assert([((FakeView *)views.views[0]).text containsString:@"quá muộn"]);
		say = sayCommand(); assert([intercept handleIncomingCommand:say]);
		assert([say.message isEqual:@""]);
		pendingCompletion(@"late answer", nil, nil);
		say = sayCommand(); assert([intercept handleIncomingCommand:say]);
		assert([say.message isEqual:@""]);
		dispatch_sync([SXStore queue], ^{});
		assert([[[SXStore shared] snapshot][@"history"] lastObject] != nil);
		assert([[[[SXStore shared] snapshot][@"history"] lastObject][@"a"] isEqual:@"late answer"]);
		testDeferred = NO;

		// Tùy chọn keep và chế độ thông minh chủ động giữ phản hồi Siri khi hết giờ.
		testTimeoutAction = @"keep";
		begin(@"question keep");
		say = sayCommand(); assert(![intercept handleIncomingCommand:say]);
		assert([say.message isEqualToString:@"Siri gốc"]);
		testTimeoutAction = @"bubble";
		testMode = SXReplyModeSmart;
		begin(@"question smart error");
		pendingCompletion(nil, [NSError errorWithDomain:@"test" code:1 userInfo:nil], nil);
		say = sayCommand(); assert(![intercept handleIncomingCommand:say]);
		assert([say.message isEqualToString:@"Siri gốc"]);
		testMode = SXReplyModeFull;

		// Tiền tố: loại khỏi câu gửi AI; không tiền tố hủy đáp án cũ.
		testTriggerMode = @"prefix";
		begin(@"@AI hello prefix");
		assert([lastQuestion isEqualToString:@"hello prefix"]);
		pendingCompletion(@"prefix answer", nil, nil);
		say = sayCommand(); assert([intercept handleIncomingCommand:say]);
		[intercept noteQuestion:@"@siri ordinary request" source:@"test"];
		say = sayCommand(); assert(![intercept handleIncomingCommand:say]);
		assert(dispatch_semaphore_wait(requestStarted, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC)) != 0);
		[intercept noteQuestion:@"@aim not a prefix" source:@"test"];
		assert(dispatch_semaphore_wait(requestStarted, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC)) != 0);
		testTriggerMode = @"auto";

		// Không lưu lịch sử: câu riêng tư chỉ nằm trong bộ nhớ.
		dispatch_sync([SXStore queue], ^{});
		NSUInteger savedCount = [[[SXStore shared] snapshot][@"history"] count];
		testIncognito = YES;
		begin(@"private question");
		pendingCompletion(@"private answer", nil, nil);
		say = sayCommand(); assert([intercept handleIncomingCommand:say]);
		dispatch_sync([SXStore queue], ^{});
		assert([[[SXStore shared] snapshot][@"history"] count] == savedCount);
		testIncognito = NO;

		// Xóa khi một yêu cầu đang chờ: đáp án trễ không được phục hồi lịch sử.
		begin(@"before reset question");
		assert([[SXStore shared] clearHistory]);
		pendingCompletion(@"after reset answer", nil, nil);
		say = sayCommand(); assert([intercept handleIncomingCommand:say]);
		dispatch_sync([SXStore queue], ^{});
		assert([[[SXStore shared] snapshot][@"history"] count] == 0);

		// Tác vụ tới trong lúc chờ: full cũng phải giữ Siri gốc.
		begin(@"question action");
		dispatch_semaphore_t done = dispatch_semaphore_create(0);
		FakeSayIt *actionSay = sayCommand();
		__block BOOL changed = YES;
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
			changed = [intercept handleIncomingCommand:actionSay];
			dispatch_semaphore_signal(done);
		});
		[NSThread sleepForTimeInterval:0.1];
		assert(![intercept handleIncomingCommand:[FakeAlarm new]]);
		assert(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0);
		assert(!changed && [actionSay.message isEqualToString:@"Siri gốc"]);
		pendingCompletion(@"unused", nil, nil);
		say = sayCommand(); assert(![intercept handleIncomingCommand:say]);
		assert(lastRequest.cancelled);

		// Explicit controls and obvious actions must not reach the provider.
		[intercept noteQuestion:@"Đặt báo thức lúc 7 giờ" source:@"test"];
		assert(dispatch_semaphore_wait(requestStarted, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC)) != 0);
		testLocalOnly = YES;
		[intercept noteQuestion:@"private network off" source:@"test"];
		assert(dispatch_semaphore_wait(requestStarted, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC)) != 0);
		testLocalOnly = NO;

		// One fallback only; the old attempt is canceled and never runs tools again.
		testFallback = @"secondary";
		testTimeoutAction = @"retry";
		begin(@"retry this turn");
		SXRequest *first = lastRequest;
		SXLLMCompletion firstCompletion = pendingCompletion;
		firstCompletion(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil], nil);
		assert(dispatch_semaphore_wait(requestStarted, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0);
		assert(first.cancelled && [lastModel isEqual:@"secondary"]);
		pendingCompletion(@"backup answer", nil, nil);
		say = sayCommand(); assert([intercept handleIncomingCommand:say]);
		assert([say.message isEqual:@"backup answer"]);
		testFallback = nil; testTimeoutAction = @"bubble";

		// A ready custom voice uses silent Apple fields; generation cancels playback.
		testTTSMode = @"ai";
		begin(@"try a voice");
		pendingCompletion(@"answer with voice", nil, nil);
		views = viewCommand(); assert([intercept handleIncomingCommand:views]);
		assert([((FakeView *)views.views[0]).text isEqual:@"answer with voice"]);
		assert([((FakeView *)views.views[0]).speakableText isEqual:@""]);
		say = sayCommand(); assert([intercept handleIncomingCommand:say] && [say.message isEqual:@""]);
		SXRequest *voice = lastRequest;
		begin(@"new capture cancels voice");
		assert(voice.cancelled);
		[intercept preferencesDidChange];
		puts("intercept regression tests: OK");
	}
	return 0;
}
