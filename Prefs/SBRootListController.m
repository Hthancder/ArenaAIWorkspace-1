// SBRootListController.m — bảng cấu hình SiriBridge trong Settings
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <AVFoundation/AVFoundation.h>
#import <notify.h>

// Khai báo các selector private của PSSpecifier (không có trong header công khai)
@interface PSSpecifier (SBPrivate)
- (void)setValues:(NSArray *)values titles:(NSArray *)titles;
@end
#import "SBConfig.h"

static NSString *const kDomain = @"com.hthancder.siribridge";

@interface SBRootListController : PSListController
@end

@implementation SBRootListController

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kDomain];
    id v = [d objectForKey:[specifier propertyForKey:@"key"]];
    return v ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kDomain];
    [d setObject:value forKey:[specifier propertyForKey:@"key"]];
    [d synchronize];
    notify_post("com.hthancder.siribridge/settingsChanged");
}

#pragma mark - Specifier helpers

- (PSSpecifier *)group:(NSString *)title {
    return [PSSpecifier groupSpecifierWithName:title];
}

- (PSSpecifier *)sw:(NSString *)label key:(NSString *)key def:(BOOL)def {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:label
                                                    target:self set:@selector(setPreferenceValue:specifier:)
                                                    get:@selector(readPreferenceValue:)
                                                 detail:nil cell:PSSwitchCell edit:nil];
    [s setProperty:key forKey:@"key"];
    [s setProperty:@(def) forKey:@"default"];
    [s setProperty:@(def) forKey:@"defaults"];
    return s;
}

- (PSSpecifier *)text:(NSString *)label key:(NSString *)key def:(NSString *)def placeholder:(NSString *)ph {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:label target:self set:@selector(setPreferenceValue:specifier:)
                                                       get:@selector(readPreferenceValue:) detail:nil cell:PSEditTextCell edit:nil];
    [s setProperty:key forKey:@"key"];
    [s setProperty:def forKey:@"default"];
    [s setProperty:ph forKey:@"placeholder"];
    [s setProperty:@(YES) forKey:@"isMultiLine"]; // bị bỏ qua ở PSEditTextCell, nhưng vô hại
    return s;
}

- (PSSpecifier *)slider:(NSString *)label key:(NSString *)key def:(double)def min:(double)mn max:(double)mx {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:label target:self set:@selector(setPreferenceValue:specifier:)
                                                       get:@selector(readPreferenceValue:) detail:nil cell:PSSliderCell edit:nil];
    [s setProperty:key forKey:@"key"];
    [s setProperty:@(def) forKey:@"default"];
    [s setProperty:@(mn) forKey:@"min"];
    [s setProperty:@(mx) forKey:@"max"];
    [s setProperty:@(YES) forKey:@"showValue"];
    return s;
}

- (PSSpecifier *)button:(NSString *)label action:(SEL)action {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:label target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    s.buttonAction = action;
    return s;
}

- (PSSpecifier *)voiceSpecifier {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:@"Giọng đọc (on-device)"
                                                    target:self set:@selector(setPreferenceValue:specifier:)
                                                    get:@selector(readPreferenceValue:) detail:nil cell:PSLinkListCell edit:nil];
    [s setProperty:@"TTSVoiceID" forKey:@"key"];

    NSMutableArray *values = [NSMutableArray arrayWithObject:@""];
    NSMutableArray *titles = [NSMutableArray arrayWithObject:@"Tự động (theo ngôn ngữ máy)"];
    for (AVSpeechSynthesisVoice *v in [AVSpeechSynthesisVoice speechVoices]) {
        [values addObject:v.identifier ?: @""];
        [titles addObject:[NSString stringWithFormat:@"%@ — %@", v.name, v.language]];
    }
    [s setValues:values titles:titles];
    return s;
}

#pragma mark - Specifiers

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *sp = [NSMutableArray array];

    [sp addObject:[self group:@"SiriBridge  ·  Siri + LLM của bạn"]];

    PSSpecifier *master = [self sw:@"Bật SiriBridge" key:@"Enabled" def:NO];
    [sp addObject:master];
    [sp addObject:[self sw:@"Thay thế câu trả lời của Siri" key:@"ReplaceSiri" def:YES]];
    [sp addObject:[self sw:@"Đọc câu trả lời" key:@"SpeakAnswer" def:YES]];
    [sp addObject:[self sw:@"Tự đóng Siri sau khi trả lời" key:@"DismissAfterAnswer" def:NO]];
    [sp addObject:[self sw:@"Cho phép điều khiển thiết bị (tools)" key:@"UseTools" def:YES]];

    [sp addObject:[self group:@"Kích hoạt" ]];
    [sp addObject:[self text:@"Chỉ xử lý khi câu bắt đầu bằng" key:@"ActivationPrefix"
                         def:@"" placeholder:@"để trống = mọi câu" ]];
    [sp addObject:[self text:@"Câu chứa các từ này thì để Siri gốc" key:@"NativeKeywords"
                         def:@"báo thức,hẹn giờ,alarm,timer" placeholder:@"cách nhau bằng dấu phẩy"]];

    [sp addObject:[self group:@"LLM endpoint" ]];
    [sp addObject:[self text:@"Endpoint (POST)" key:@"Endpoint"
                         def:@"https://api.openai.com/v1/chat/completions" placeholder:@"https://..." ]];
    [sp addObject:[self text:@"API key" key:@"APIKey" def:@"" placeholder:@"sk-..." ]];
    [sp addObject:[self text:@"Model" key:@"Model" def:@"gpt-4o-mini" placeholder:@"gpt-4o-mini / llama3.1 / gemini-2.0-flash" ]];
    [sp addObject:[self text:@"Response field (đường dẫn JSON)" key:@"ResponseField"
                         def:@"choices.0.message.content" placeholder:@"choices.0.message.content"]];
    [sp addObject:[self text:@"Headers phụ (JSON)" key:@"ExtraHeaders" def:@"" placeholder:@"{\"X-Title\":\"Siri\"}"]];
    [sp addObject:[self text:@"Body template (tuỳ chọn)" key:@"BodyTemplate" def:@""
                         placeholder:@"{\"model\":\"{{MODEL}}\",\"messages\":...}" ]];
    [sp addObject:[self text:@"System prompt" key:@"SystemPrompt"
                         def:@"Bạn là trợ lý giọng nói trên iPhone. Trả lời cực kỳ ngắn gọn." placeholder:@"..."]];
    [sp addObject:[self slider:@"Temperature" key:@"Temperature" def:0.6 min:0.0 max:1.5]];
    [sp addObject:[self slider:@"Số lượt hội thoại nhớ lại" key:@"HistoryTurns" def:6 min:0 max:20]];
    [sp addObject:[self text:@"Max tokens" key:@"MaxTokens" def:@"400" placeholder:@"400"]];
    [sp addObject:[self text:@"Timeout (giây)" key:@"Timeout" def:@"45" placeholder:@"45"]];
    [sp addObject:[self button:@"Xoá lịch sử hội thoại" action:@selector(resetHistory)]];

    [sp addObject:[self group:@"TTS (đọc câu trả lời)" ]];
    PSSpecifier *mode = [PSSpecifier preferenceSpecifierNamed:@"Kiểu TTS"
                                                       target:self set:@selector(setPreferenceValue:specifier:)
                                                       get:@selector(readPreferenceValue:) detail:nil cell:PSLinkListCell edit:nil];
    [mode setProperty:@"TTSMode" forKey:@"key"];
    [mode setValues:@[@0, @1, @2]
             titles:@[@"Trên máy (AVSpeechSynthesizer)",
                      @"Endpoint TTS (OpenAI/ElevenLabs/Piper…)",
                      @"Để Siri tự đọc (giọng Siri gốc)"]];
    [sp addObject:mode];
    [sp addObject:[self voiceSpecifier]];
    [sp addObject:[self slider:@"Tốc độ (0–1)" key:@"TTSRate" def:0.5 min:0.0 max:1.0]];
    [sp addObject:[self slider:@"Cao độ" key:@"TTSPitch" def:1.0 min:0.5 max:2.0]];
    [sp addObject:[self slider:@"Âm lượng" key:@"TTSVolume" def:1.0 min:0.0 max:1.0]];

    [sp addObject:[self group:@"TTS endpoint (chỉ khi chọn kiểu 2)" ]];
    [sp addObject:[self text:@"Endpoint POST" key:@"TTSEndpoint"
                         def:@"https://api.openai.com/v1/audio/speech" placeholder:@"https://..." ]];
    [sp addObject:[self text:@"Voice (endpoint)" key:@"TTSRemoteVoice" def:@"alloy" placeholder:@"alloy / vi-VN-Neural ..."]];
    [sp addObject:[self text:@"Headers (JSON)" key:@"TTSHeaders" def:@"" placeholder:@"{\"xi-api-key\":\"...\"}"]];
    [sp addObject:[self text:@"Body template" key:@"TTSBodyTemplate" def:@""
                         placeholder:@"{\"input\":\"{{TEXT}}\",\"voice\":\"{{VOICE}}\"}"]];
    [sp addObject:[self sw:@"Response là audio nhị phân" key:@"TTSResponseIsAudio" def:YES]];
    [sp addObject:[self text:@"Nếu là JSON, field chứa base64" key:@"TTSResponseField" def:@"" placeholder:@"data"]];

    [sp addObject:[self group:@"Công cụ" ]];
    [sp addObject:[self button:@"Danh sách voice có trên máy (log)" action:@selector(logVoices)]];
    [sp addObject:[self group:@"SiriBridge là bản mã nguồn mở, miễn phí. Không telemetry, không tài khoản."]];

    _specifiers = sp;
    return _specifiers;
}

#pragma mark - Actions

- (void)resetHistory {
    notify_post("com.hthancder.siribridge/resetHistory");
    notify_post("com.hthancder.siribridge/settingsChanged");
}

- (void)logVoices {
    for (AVSpeechSynthesisVoice *v in [AVSpeechSynthesisVoice speechVoices]) {
        NSLog(@"[SiriBridge] voice %@ (%@) %@", v.name, v.language, v.identifier);
    }
}

@end
