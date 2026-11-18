#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SXProvider) {
	SXProviderOpenAI = 0,
	SXProviderGemini,
};

typedef NS_ENUM(NSInteger, SXReplyMode) {
	SXReplyModeSmart = 0, // AI trả lời câu hỏi tri thức, tác vụ hệ thống để Siri gốc
	SXReplyModeFull,      // AI thay toàn bộ câu trả lời
};

FOUNDATION_EXPORT NSString *SXDefaultSystemPrompt(void);

@interface SXPrefs : NSObject

+ (instancetype)shared;

/// Đọc lại toàn bộ cài đặt (CFPreferences + fallback file). Log lại tóm tắt.
- (void)reload;

@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) SXReplyMode mode;
@property (nonatomic, readonly) SXProvider provider;
@property (nonatomic, readonly, copy) NSString *openaiKey;
@property (nonatomic, readonly, copy) NSString *openaiBase;
@property (nonatomic, readonly, copy) NSString *openaiModel;
@property (nonatomic, readonly, copy) NSString *geminiKey;
@property (nonatomic, readonly, copy) NSString *geminiModel;
@property (nonatomic, readonly) double temperature;      // 0–2, làm tròn 0.1
@property (nonatomic, readonly) NSInteger contextTurns;  // 2–40 cặp Q/A giữ lại
@property (nonatomic, readonly) NSTimeInterval responseTimeout; // 2–15 giây
@property (nonatomic, readonly, copy) NSString *customPrompt;   // rỗng = dùng prompt mặc định
@property (nonatomic, readonly) BOOL hideWebCards;
@property (nonatomic, readonly) BOOL speakErrors;
@property (nonatomic, readonly) BOOL verbose;
@property (nonatomic, readonly) BOOL toolSystemInfo;
@property (nonatomic, readonly) BOOL toolClipboard;
@property (nonatomic, readonly) BOOL toolFetchURL;

- (nullable NSString *)activeAPIKey;
- (NSString *)activeModel;
- (NSString *)activeBaseURL;
- (NSString *)systemPrompt;

@end

NS_ASSUME_NONNULL_END
