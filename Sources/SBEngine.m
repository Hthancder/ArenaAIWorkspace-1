#import "SBEngine.h"
#import "SBConfig.h"
#import "SBLLM.h"
#import "SBTTS.h"
#import "SBTools.h"
#import "SBHistory.h"
#import "SBCapture.h"
#import <objc/message.h>
#import "SBDeliver.h"

@interface SBEngine ()
- (void)runToolCalls:(NSArray *)calls index:(NSInteger)i collected:(NSString *)c
            delegate:(id)delegate session:(id)session turn:(NSInteger)turn;
- (void)finishWithAnswer:(NSString *)answer delegate:(id)delegate session:(id)session turn:(NSInteger)turn;
- (void)showThinkingForDelegate:(id)delegate;
- (void)showAnswer:(NSString *)answer delegate:(id)delegate;
@end

#define SBLog(fmt, ...) NSLog(@"[SiriBridge] " fmt, ##__VA_ARGS__)

#pragma mark - ACE helpers (không cần link SAObjects)

static Class SBClass(NSString *n) { return NSClassFromString(n); }

@implementation SBEngine {
    BOOL _cancelled;
    NSInteger _turn;
}

+ (instancetype)shared {
    static SBEngine *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SBEngine new]; });
    return s;
}

- (BOOL)busy { return _turn > 0; }

- (void)cancel {
    _cancelled = YES;
    _turn = 0;
    [[SBTTS shared] stop];
}

#pragma mark - Public

- (void)handleTurnWithText:(NSString *)text session:(id)session delegate:(id)delegate {
    if (!text.length) return;
    if (_turn > 0) { SBLog(@"đang bận, bỏ qua lượt mới"); return; }

    SBConfig *cfg = [SBConfig shared];
    NSInteger myTurn = ++_turn;
    _cancelled = NO;

    SBLog(@"turn %ld: %@", (long)myTurn, text);
    [[SBHistory shared] addUser:text];

    // 1) hiển thị "đang xử lý" trong transcript Siri
    [self showThinkingForDelegate:delegate];

    NSArray *tools = (cfg.useTools ? [SBTools openAIToolSpecs] : nil);

    __weak typeof(self) weakSelf = self;
    [SBLLM ask:text tools:tools completion:^(NSString *answer, NSArray *toolCalls, NSError *error) {
        typeof(self) self_ = weakSelf;
        if (!self_ || self_->_cancelled || self_->_turn != myTurn) return;

        if (error) {
            NSString *msg = [NSString stringWithFormat:@"Lỗi: %@", error.localizedDescription];
            [self_ finishWithAnswer:msg delegate:delegate session:session turn:myTurn];
            return;
        }
        if (toolCalls.count) {
            [self_ runToolCalls:toolCalls index:0 collected:@""
                       delegate:delegate session:session turn:myTurn];
            return;
        }
        [self_ finishWithAnswer:answer delegate:delegate session:session turn:myTurn];
    }];
}

#pragma mark - Tools

- (void)runToolCalls:(NSArray *)calls index:(NSInteger)i collected:(NSString *)collected
            delegate:(id)delegate session:(id)session turn:(NSInteger)myTurn {
    if (_cancelled || _turn != myTurn) return;
    if (i >= (NSInteger)calls.count) {
        // Hết tool → hỏi lại LLM một lần để có câu trả lời tự nhiên
        NSString *followUp = [NSString stringWithFormat:
            @"[Kết quả thực thi: %@] Hãy trả lời người dùng thật ngắn gọn bằng lời, "
            @"xác nhận đã làm xong (hoặc nói rõ nếu thất bại).", collected];
        __weak typeof(self) weakSelf = self;
        [SBLLM ask:followUp tools:nil completion:^(NSString *answer, NSArray *tc, NSError *error) {
            typeof(self) self_ = weakSelf;
            if (!self_ || self_->_cancelled || self_->_turn != myTurn) return;
            [self_ finishWithAnswer:(error ? collected : answer) delegate:delegate session:session turn:myTurn];
        }];
        return;
    }
    NSDictionary *call = calls[i];
    NSString *name = call[@"name"];
    NSString *args = call[@"arguments"];

    if (![SBTools isKnownTool:name]) {
        [self runToolCalls:calls index:i + 1 collected:collected delegate:delegate session:session turn:myTurn];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [SBTools runTool:name arguments:args completion:^(NSString *result) {
        typeof(self) self_ = weakSelf;
        if (!self_) return;
        NSString *acc = [NSString stringWithFormat:@"%@%@", collected,
                         [NSString stringWithFormat:@"%@ → %@. ", name, result]];
        [self_ runToolCalls:calls index:i + 1 collected:acc delegate:delegate session:session turn:myTurn];
    }];
}

#pragma mark - Kết thúc lượt

- (void)finishWithAnswer:(NSString *)answer delegate:(id)delegate session:(id)session turn:(NSInteger)myTurn {
    if (_cancelled || _turn != myTurn) return;
    SBConfig *cfg = [SBConfig shared];
    SBLog(@"answer: %@", answer);

    if (!answer.length) answer = @"Xong.";
    [[SBHistory shared] addAssistant:answer];

    // Hiển thị trong transcript Siri
    [self showAnswer:answer delegate:delegate];

    // Đọc bằng TTS tuỳ chỉnh
    BOOL shouldSpeak = cfg.speakAnswer && cfg.ttsMode != 2;
    __weak typeof(self) weakSelf = self;
    void (^afterSpeak)(void) = ^{
        typeof(self) self_ = weakSelf;
        if (!self_) return;
        self_->_turn = 0;
        if (cfg.dismissAfterAnswer) {
            SEL endSel = NSSelectorFromString(@"end");
            if ([session respondsToSelector:endSel]) {
                ((void (*)(id, SEL))objc_msgSend)(session, endSel);
            }
        }
    };

    if (shouldSpeak) [[SBTTS shared] speak:answer completion:afterSpeak];
    else afterSpeak();
}

#pragma mark - UI helpers

- (void)showThinkingForDelegate:(id)delegate {
    Class AV = SBClass(@"SAUIAddViews");
    Class UV = SBClass(@"SAUIAssistantUtteranceView");
    if (!AV || !UV) { SBLog(@"thiếu SAObjects"); return; }

    id view = ((id (*)(id, SEL))objc_msgSend)(UV, NSSelectorFromString(@"assistantUtteranceView"));
    [view setValue:@"…" forKey:@"text"];

    id add = ((id (*)(id, SEL))objc_msgSend)(AV, NSSelectorFromString(@"addViews"));
    [add setValue:@[view] forKey:@"views"];
    [add setValue:@"Reflected" forKey:@"dialogPhase"];   // phase "đang xử lý"

    SBDeliverCommand(delegate, add, @"siriSessionDidReceiveAddViewsCommand:completion:");
}

- (void)showAnswer:(NSString *)answer delegate:(id)delegate {
    Class AV = SBClass(@"SAUIAddViews");
    Class UV = SBClass(@"SAUIAssistantUtteranceView");
    if (!AV || !UV) { SBLog(@"thiếu SAObjects"); return; }

    SBConfig *cfg = [SBConfig shared];
    id view = ((id (*)(id, SEL))objc_msgSend)(UV, NSSelectorFromString(@"assistantUtteranceView"));
    [view setValue:answer forKey:@"text"];
    // Chỉ để Siri tự đọc khi người dùng chọn TTSMode = 2,
    // nếu không sẽ bị đọc 2 lần (Siri + SBTTS).
    if (cfg.ttsMode == 2 && cfg.speakAnswer) {
        [view setValue:answer forKey:@"speakableText"];
    }
    [view setValue:@(NO)   forKey:@"canUseServerTTS"];
    [view setValue:[NSUUID UUID].UUIDString forKey:@"dialogIdentifier"];

    id add = ((id (*)(id, SEL))objc_msgSend)(AV, NSSelectorFromString(@"addViews"));
    [add setValue:@[view] forKey:@"views"];
    [add setValue:@"Completion" forKey:@"dialogPhase"];

    SBDeliverCommand(delegate, add, @"siriSessionDidReceiveAddViewsCommand:completion:");
}

@end
