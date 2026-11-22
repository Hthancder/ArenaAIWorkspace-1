// Chạy trên macOS Foundation: kiểm thử SXIntercept thật với ACE/LLM giả.
#import <Foundation/Foundation.h>
#import "SXIntercept.h"
#import "SXDisplayPolicy.h"
#import "SXPrefs.h"
#import "SXLLM.h"
#import "SXTools.h"
#import "SXLog.h"
#import "SXMarkdown.h"
#import "SXStore.h"
#include <assert.h>

static SXLLMCompletion pendingCompletion;
static dispatch_semaphore_t requestStarted;
static SXReplyMode testMode = SXReplyModeFull;
static NSString *testTimeoutAction = @"bubble";
static NSString *testTriggerMode = @"auto";
static NSString *lastQuestion;
static NSArray *lastHistory;
static BOOL testShowOriginal;
static BOOL testIncognito;

@implementation SXPrefs
+ (instancetype)shared { static SXPrefs *p; static dispatch_once_t once; dispatch_once(&once, ^{ p = [SXPrefs new]; }); return p; }
- (BOOL)enabled { return YES; }
- (NSString *)triggerMode { return testTriggerMode; }
- (SXReplyMode)mode { return testMode; }
- (NSTimeInterval)responseTimeout { return 2; }
- (NSTimeInterval)replyDeadline { return 2; }
- (BOOL)markdown { return NO; }
- (BOOL)hideWebCards { return YES; }
- (BOOL)showOriginal { return testShowOriginal; }
- (BOOL)incognito { return testIncognito; }
- (BOOL)speakErrors { return NO; }
- (BOOL)deferLongReplies { return NO; }   // test không xin quyền thông báo
- (NSString *)timeoutAction { return testTimeoutAction; }
- (NSInteger)contextTurns { return 8; }
- (SXProvider)provider { return SXProviderOpenAI; }
- (NSArray<NSDictionary *> *)openaiHeaders { return @[]; }
- (NSArray<NSDictionary *> *)geminiHeaders { return @[]; }
- (NSArray<NSDictionary *> *)headersForProvider:(SXProvider)provider { (void)provider; return @[]; }
- (NSSet<NSString *> *)disabledTools { return [NSSet set]; }
- (id)valueFor:(NSString *)key { (void)key; return nil; }
@end
@implementation SXLLM
+ (void)askQuestion:(NSString *)question history:(NSArray *)history tools:(NSArray *)tools executor:(SXToolExec)executor completion:(SXLLMCompletion)completion {
	lastQuestion = [question copy]; lastHistory = [history copy]; (void)tools; (void)executor;
	pendingCompletion = [completion copy];
	dispatch_semaphore_signal(requestStarted);
}
@end
@implementation SXTools
+ (NSArray *)definitions { return @[]; }
+ (NSDictionary *)execute:(NSString *)name arguments:(NSDictionary *)arguments error:(NSError **)error {
	(void)name; (void)arguments; (void)error; return nil;
}
+ (NSString *)promptBrief { return @""; }
+ (void)beginTurn {}
+ (NSArray<SXTool *> *)catalog { return @[]; }
@end
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
@interface FakeDialogAddViews : FakeAddViews
@property (nonatomic, copy) NSString *dialogIdentifier;
@end
@implementation FakeDialogAddViews
@end

static void begin(NSString *question) {
	[[SXIntercept shared] noteQuestion:question source:@"test"];
	assert(dispatch_semaphore_wait(requestStarted, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
}
static FakeAddViews *viewCommand(void) {
	FakeView *view = [FakeView new]; view.text = @"Siri gốc"; view.speakableText = @"Siri gốc";
	FakeAddViews *command = [FakeAddViews new]; command.views = @[view]; return command;
}
static FakeDialogAddViews *dialogCommand(NSString *dialog, NSString *text) {
	FakeView *view = [FakeView new];
	view.text = text;
	view.speakableText = text;
	FakeDialogAddViews *command = [FakeDialogAddViews new];
	command.dialogIdentifier = dialog;
	command.views = @[view];
	return command;
}
static FakeSayIt *sayCommand(void) {
	FakeSayIt *command = [FakeSayIt new]; command.message = @"Siri gốc"; return command;
}
int main(void) {
	@autoreleasepool {
		assert(![SXDisplayPolicy shouldSendDeferredAnswerWhenEnabled:NO privateTurn:NO]);
		assert([SXDisplayPolicy shouldSendDeferredAnswerWhenEnabled:YES privateTurn:NO]);
		assert(![SXDisplayPolicy shouldSendDeferredAnswerWhenEnabled:YES privateTurn:YES]);
		// "retry": giữ Siri gốc để chờ đáp án của lần thử lại (tới qua thông báo).
		assert(![SXDisplayPolicy timeoutBubbleMessageInMode:SXReplyModeFull action:@"retry"]);
		assert([[SXDisplayPolicy timeoutBubbleMessageInMode:SXReplyModeFull action:@"bubble"]
				hasPrefix:@"⏳"]);
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

		// AddViews nhiều view: chỉ view chính (cuối) bị thay, view khác giữ nguyên.
		begin(@"question multi view");
		pendingCompletion(@"multi answer", nil, nil);
		FakeView *titleView = [FakeView new];
		titleView.text = @"Tiêu đề";
		titleView.speakableText = @"Tiêu đề";
		FakeView *bodyView = [FakeView new];
		bodyView.text = @"Siri gốc";
		bodyView.speakableText = @"Siri gốc";
		FakeAddViews *multi = [FakeAddViews new];
		multi.views = @[titleView, bodyView];
		assert([intercept handleIncomingCommand:multi]);
		assert([bodyView.text isEqualToString:@"multi answer"]);
		assert([titleView.text isEqualToString:@"Tiêu đề"]);

		// Khác dialogIdentifier: không áp quyết định của lượt trước sang lệnh UI khác.
		begin(@"question dialog");
		pendingCompletion(@"dialog answer", nil, nil);
		FakeDialogAddViews *dialogA = dialogCommand(@"A", @"Siri gốc");
		assert([intercept handleIncomingCommand:dialogA]);
		assert([((FakeView *)dialogA.views.firstObject).text isEqualToString:@"dialog answer"]);
		FakeDialogAddViews *dialogB = dialogCommand(@"B", @"Siri gốc");
		assert(![intercept handleIncomingCommand:dialogB]);
		assert([((FakeView *)dialogB.views.firstObject).text isEqualToString:@"Siri gốc"]);

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
		assert([say.message containsString:@"lỗi thử"]);
		begin(@"question timeout");
		views = viewCommand(); assert([intercept handleIncomingCommand:views]);
		say = sayCommand(); assert([intercept handleIncomingCommand:say]);
		assert([say.message containsString:@"quá muộn"]);
		pendingCompletion(@"late answer", nil, nil);
		say = sayCommand(); assert([intercept handleIncomingCommand:say]);
		assert([say.message containsString:@"quá muộn"]);

		// Tùy chọn keep và chế độ thông minh chủ động giữ phản hồi Siri khi hết giờ.
		testTimeoutAction = @"keep";
		begin(@"question keep");
		say = sayCommand(); assert(![intercept handleIncomingCommand:say]);
		assert([say.message isEqualToString:@"Siri gốc"]);
		// Chính sách retry: cùng đường "giữ Siri gốc" như keep, không bubble.
		testTimeoutAction = @"retry";
		begin(@"question retry");
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
		assert(lastHistory.count == 0); // không gửi lịch sử cũ cho provider trong lượt riêng tư
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

		// Xoá lịch sử của SXIntercept KHÔNG chặn luồng gọi (trước đây là
		// `dispatch_sync` vào hàng đợi kho, tức chặn luồng chính của Settings).
		// Việc ghi tệp vẫn phải hoàn tất: đợi hàng đợi kho rồi kiểm tra.
		begin(@"question to clear");
		pendingCompletion(@"answer to clear", nil, nil);
		say = sayCommand();
		assert([intercept handleIncomingCommand:say]);
		// Lượt hỏi chạy trên hàng đợi riêng (com.sirix.turn) và chỉ trả đáp án cho
		// ACE; lịch sử được ghi ngay sau đó, nên đọc kho trên luồng này có thể
		// chạy trước. Chờ tới khi MỘT trong hai hàng đợi ghi xong, rồi kiểm tra
		// theo hướng xoá (điều cần chứng minh), không phụ thuộc thứ tự còn lại.
		dispatch_sync([SXStore queue], ^{});
		assert([intercept clearHistory]);   // trả về NGAY, không chặn luồng gọi
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
		puts("intercept regression tests: OK");
	}
	return 0;
}
