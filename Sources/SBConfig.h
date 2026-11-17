// SBConfig.h — đọc/ghi cấu hình dùng chung giữa SiriViewService và app Settings
#import <Foundation/Foundation.h>

extern NSString *const SBConfigDomain;          // com.hthancder.siribridge
extern NSString *const SBConfigChangedNote;     // CFNotificationName

@interface SBConfig : NSObject
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL replaceSiri;          // YES: chặn câu trả lời của Siri
@property (nonatomic, assign) BOOL dismissAfterAnswer;   // tự đóng Siri sau khi trả lời
@property (nonatomic, assign) BOOL speakAnswer;          // đọc câu trả lời

// LLM
@property (nonatomic, copy)   NSString *endpoint;        // https://api.openai.com/v1/chat/completions
@property (nonatomic, copy)   NSString *apiKey;
@property (nonatomic, copy)   NSString *model;
@property (nonatomic, copy)   NSString *extraHeaders;    // JSON dict, vd {"X-Foo":"bar"}
@property (nonatomic, copy)   NSString *bodyTemplate;    // JSON có {{SYSTEM}} {{PROMPT}} {{HISTORY}} {{MODEL}}
@property (nonatomic, copy)   NSString *responseField;   // "choices.0.message.content"
@property (nonatomic, copy)   NSString *systemPrompt;
@property (nonatomic, assign) double      temperature;
@property (nonatomic, assign) NSInteger   maxTokens;
@property (nonatomic, assign) NSInteger   historyTurns;   // số lượt giữ lại trong context
@property (nonatomic, assign) NSInteger   timeout;
@property (nonatomic, assign) BOOL        useTools;       // cho phép điều khiển máy

// TTS
@property (nonatomic, assign) NSInteger ttsMode;          // 0 = AVSpeechSynthesizer, 1 = endpoint, 2 = để Siri tự đọc
@property (nonatomic, copy)   NSString *ttsVoiceID;       // com.apple.ttsbundle.siri_...
@property (nonatomic, assign) double    ttsRate;          // 0..1 (AVSpeechUtteranceDefaultSpeechRate ~ 0.5)
@property (nonatomic, assign) double    ttsPitch;
@property (nonatomic, assign) double    ttsVolume;
@property (nonatomic, copy)   NSString *ttsRemoteVoice;    // tên voice của endpoint (alloy, vi-VN-...)
@property (nonatomic, copy)   NSString *ttsEndpoint;
@property (nonatomic, copy)   NSString *ttsHeaders;       // JSON dict
@property (nonatomic, copy)   NSString *ttsBodyTemplate;  // JSON có {{TEXT}} {{VOICE}}
@property (nonatomic, assign) BOOL      ttsResponseIsAudio; // YES: body trả về là audio; NO: JSON, lấy ttsResponseField
@property (nonatomic, copy)   NSString *ttsResponseField; // vd "data" (base64) hoặc "url"

// Khác
@property (nonatomic, copy)   NSString *nativeKeywords;   // "alarm,timer,báo thức,hẹn giờ,gọi,mở máy ảnh"
@property (nonatomic, copy)   NSString *activationPrefix; // rỗng = mọi câu; "ai" = chỉ câu bắt đầu bằng "ai"

+ (instancetype)shared;
- (void)reload;
/// Bản không bao giờ ném — dùng trong hook của process hệ thống.
- (BOOL)shouldHandleTextSafe:(NSString *)text;
- (void)postChanged;
- (BOOL)shouldHandleText:(NSString *)text;   // prefix + native keyword
@end
