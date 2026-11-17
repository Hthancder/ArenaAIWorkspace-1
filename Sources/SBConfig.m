#import "SBConfig.h"
#import "SBPaths.h"
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
    static NSDictionary *cache; static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (NSString *path in SBPathCandidates(SBPrimaryPreferencesPath())) {
            NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
            if (dict.count) { cache = dict; return; }
        }
        cache = @{};
    });
    return cache;
}

static id SBGet(NSUserDefaults *d, NSString *k, id def) {
    id v = [d objectForKey:k];
    if (v) return v;
    v = SBPreferencesFallback()[k];
    return v ?: def;
}

- (void)reload {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:SBConfigDomain];
    // Suite chưa tồn tại (lần đầu) → dùng domain mặc định của process
    if (!d) d = [NSUserDefaults standardUserDefaults];

    _enabled            = [SBGet(d, @"Enabled", @NO) boolValue];
    _replaceSiri        = [SBGet(d, @"ReplaceSiri", @YES) boolValue];
    _dismissAfterAnswer = [SBGet(d, @"DismissAfterAnswer", @NO) boolValue];
    _speakAnswer        = [SBGet(d, @"SpeakAnswer", @YES) boolValue];

    _endpoint       = SBGet(d, @"Endpoint", @"https://api.openai.com/v1/chat/completions");
    _apiKey         = SBGet(d, @"APIKey", @"");
    _model          = SBGet(d, @"Model", @"gpt-4o-mini");
    _extraHeaders   = SBGet(d, @"ExtraHeaders", @"");
    _bodyTemplate   = SBGet(d, @"BodyTemplate", @"");
    _responseField  = SBGet(d, @"ResponseField", @"choices.0.message.content");
    _systemPrompt   = SBGet(d, @"SystemPrompt",
        @"Bạn là trợ lý giọng nói trên iPhone. Trả lời cực kỳ ngắn gọn, tự nhiên, "
        @"tối đa 2 câu, không markdown, không emoji, không liệt kê, vì câu trả lời sẽ được đọc thành tiếng.");
    _temperature    = [SBGet(d, @"Temperature", @0.6) doubleValue];
    _maxTokens      = [SBGet(d, @"MaxTokens", @400) integerValue];
    _historyTurns   = [SBGet(d, @"HistoryTurns", @6) integerValue];
    _timeout        = [SBGet(d, @"Timeout", @45) integerValue];
    _useTools       = [SBGet(d, @"UseTools", @YES) boolValue];

    _ttsMode            = [SBGet(d, @"TTSMode", @0) integerValue];
    _ttsVoiceID         = SBGet(d, @"TTSVoiceID", @"");
    _ttsRate            = [SBGet(d, @"TTSRate", @0.5) doubleValue];
    _ttsPitch           = [SBGet(d, @"TTSPitch", @1.0) doubleValue];
    _ttsVolume          = [SBGet(d, @"TTSVolume", @1.0) doubleValue];
    _ttsRemoteVoice     = SBGet(d, @"TTSRemoteVoice", @"alloy");
    _ttsEndpoint        = SBGet(d, @"TTSEndpoint", @"https://api.openai.com/v1/audio/speech");
    _ttsHeaders         = SBGet(d, @"TTSHeaders", @"");
    _ttsBodyTemplate    = SBGet(d, @"TTSBodyTemplate",
        @"{\"model\":\"gpt-4o-mini-tts\",\"input\":\"{{TEXT}}\",\"voice\":\"{{VOICE}}\",\"response_format\":\"mp3\"}");
    _ttsResponseIsAudio = [SBGet(d, @"TTSResponseIsAudio", @YES) boolValue];
    _ttsResponseField   = SBGet(d, @"TTSResponseField", @"");

    _nativeKeywords    = SBGet(d, @"NativeKeywords", @"");
    _activationPrefix  = SBGet(d, @"ActivationPrefix", @"");
}

- (void)postChanged {
    notify_post(SBConfigChangedNote.UTF8String);
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
