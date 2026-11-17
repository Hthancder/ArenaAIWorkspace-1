#import "SBConfig.h"
#import "SBPaths.h"
#import "SBLog.h"
#import <notify.h>

NSString *const SBConfigDomain      = @"com.hthancder.siribridge";
NSString *const SBConfigChangedNote = @"com.hthancder.siribridge/settingsChanged";

@implementation SBConfig

+ (instancetype)shared {
    static SBConfig *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SBConfig new]; [s reload]; });
    return s;
}

- (id)init {
    if ((self = [super init])) { [self reload]; }
    return self;
}

// cfprefsd đôi khi không phục vụ domain cho process bị sandbox (SiriViewService
// trên một số bản jailbreak) → đọc thẳng plist làm fallback.
static NSDictionary *SBPreferencesFallback(void) {
    // SiriViewService can be sandboxed away from cfprefsd's suite domain.
    // Do not cache this plist forever: settingsChanged triggers reloads, and
    // the direct-file fallback must observe the newly saved values each time.
    for (NSString *path in SBPathCandidates(SBPrimaryPreferencesPath())) {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
        if (dict.count) return dict;
    }
    return @{};
}

static id SBGet(NSUserDefaults *d, NSDictionary *fallback, NSString *k, id def) {
    // Prefer the synchronized preference plist on each reload. A long-lived
    // SiriViewService may retain an older NSUserDefaults suite cache after a
    // Darwin notification, while the direct file is already atomically saved.
    id v = fallback[k];
    if (v) return v;
    v = [d objectForKey:k];
    return v ?: def;
}

- (void)reload {
    @try {
        [self sb_reload];
    } @catch (NSException *e) {
        SBLog(@"reload lỗi: %@ — dùng giá trị mặc định", e.reason);
    }
}

- (void)sb_reload {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:SBConfigDomain];
    // Suite chưa tồn tại (lần đầu) → dùng domain mặc định của process
    if (!d) d = [NSUserDefaults standardUserDefaults];
    NSDictionary *fallback = SBPreferencesFallback();

    _enabled            = [SBGet(d, fallback, @"Enabled", @NO) boolValue];
    _replaceSiri        = [SBGet(d, fallback, @"ReplaceSiri", @YES) boolValue];
    _dismissAfterAnswer = [SBGet(d, fallback, @"DismissAfterAnswer", @NO) boolValue];
    _speakAnswer        = [SBGet(d, fallback, @"SpeakAnswer", @YES) boolValue];

    _endpoint       = SBGet(d, fallback, @"Endpoint", @"https://api.openai.com/v1/chat/completions");
    _apiKey         = SBGet(d, fallback, @"APIKey", @"");
    _model          = SBGet(d, fallback, @"Model", @"gpt-4o-mini");
    _extraHeaders   = SBGet(d, fallback, @"ExtraHeaders", @"");
    _bodyTemplate   = SBGet(d, fallback, @"BodyTemplate", @"");
    _responseField  = SBGet(d, fallback, @"ResponseField", @"choices.0.message.content");
    _systemPrompt   = SBGet(d, fallback, @"SystemPrompt",
        @"Bạn là trợ lý giọng nói trên iPhone. Trả lời cực kỳ ngắn gọn, tự nhiên, "
        @"tối đa 2 câu, không markdown, không emoji, không liệt kê, vì câu trả lời sẽ được đọc thành tiếng.");
    _temperature    = [SBGet(d, fallback, @"Temperature", @0.6) doubleValue];
    _maxTokens      = [SBGet(d, fallback, @"MaxTokens", @400) integerValue];
    _historyTurns   = [SBGet(d, fallback, @"HistoryTurns", @6) integerValue];
    _timeout        = [SBGet(d, fallback, @"Timeout", @45) integerValue];
    _useTools       = [SBGet(d, fallback, @"UseTools", @YES) boolValue];

    _ttsMode            = [SBGet(d, fallback, @"TTSMode", @0) integerValue];
    _ttsVoiceID         = SBGet(d, fallback, @"TTSVoiceID", @"");
    _ttsRate            = [SBGet(d, fallback, @"TTSRate", @0.5) doubleValue];
    _ttsPitch           = [SBGet(d, fallback, @"TTSPitch", @1.0) doubleValue];
    _ttsVolume          = [SBGet(d, fallback, @"TTSVolume", @1.0) doubleValue];
    _ttsRemoteVoice     = SBGet(d, fallback, @"TTSRemoteVoice", @"alloy");
    _ttsEndpoint        = SBGet(d, fallback, @"TTSEndpoint", @"https://api.openai.com/v1/audio/speech");
    _ttsHeaders         = SBGet(d, fallback, @"TTSHeaders", @"");
    _ttsBodyTemplate    = SBGet(d, fallback, @"TTSBodyTemplate",
        @"{\"model\":\"gpt-4o-mini-tts\",\"input\":\"{{TEXT}}\",\"voice\":\"{{VOICE}}\",\"response_format\":\"mp3\"}");
    _ttsResponseIsAudio = [SBGet(d, fallback, @"TTSResponseIsAudio", @YES) boolValue];
    _ttsResponseField   = SBGet(d, fallback, @"TTSResponseField", @"");

    _nativeKeywords    = SBGet(d, fallback, @"NativeKeywords", @"báo thức,hẹn giờ,alarm,timer");
    _activationPrefix  = SBGet(d, fallback, @"ActivationPrefix", @"");
}

- (void)postChanged {
    notify_post(SBConfigChangedNote.UTF8String);
}

- (BOOL)shouldHandleTextSafe:(NSString *)text {
    @try { return [self shouldHandleText:text]; }
    @catch (NSException *e) { return NO; }
}

- (BOOL)shouldHandleText:(NSString *)text {
    if (!_enabled) return NO;
    NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length == 0) return NO;

    // Từ khoá "để Siri gốc lo": so khớp không phân biệt hoa thường, theo từ
    if (_nativeKeywords.length) {
        NSString *lower = t.lowercaseString;
        for (NSString *raw in [_nativeKeywords componentsSeparatedByString:@","]) {
            NSString *kw = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].lowercaseString;
            if (kw.length && [lower rangeOfString:kw].location != NSNotFound) return NO;
        }
    }

    // Prefix kích hoạt: nếu có, câu phải bắt đầu bằng prefix
    if (_activationPrefix.length) {
        NSString *p = _activationPrefix.lowercaseString;
        if (![t.lowercaseString hasPrefix:p]) return NO;
    }
    return YES;
}

@end
