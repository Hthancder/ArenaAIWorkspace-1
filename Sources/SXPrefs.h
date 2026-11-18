#import "SXProviders.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SXReplyMode) {
	SXReplyModeSmart = 0, // AI trả lời câu hỏi tri thức, tác vụ hệ thống để Siri gốc
	SXReplyModeFull,      // AI thay toàn bộ câu trả lời
};

FOUNDATION_EXPORT NSString *SXDefaultSystemPrompt(void);

@interface SXPrefs : NSObject

+ (instancetype)shared;

/// Đọc lại toàn bộ cài đặt (CFPreferences + fallback file). Log lại tóm tắt.
- (void)reload;
/// Immutable per-turn configuration; never mutate the live object in a worker.
- (SXPrefs *)snapshot;
@property (atomic, readonly, copy) NSDictionary *settings;
+ (BOOL)writeValues:(NSDictionary *)values removing:(NSArray<NSString *> *)keys;

/// Ghi một key chuỗi (CFPreferences + đồng bộ ngay). value = nil → xóa key.
+ (void)setString:(nullable NSString *)value forKey:(NSString *)key;

@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) SXReplyMode mode;
@property (nonatomic, readonly) SXProvider provider;
@property (nonatomic, readonly, copy) NSString *triggerMode; // auto | prefix
@property (nonatomic, readonly) double temperature;      // 0–2, làm tròn 0.1
@property (nonatomic, readonly) NSInteger contextTurns;  // 2–40 cặp Q/A giữ lại
@property (nonatomic, readonly) NSTimeInterval responseTimeout; // 2–30 giây (ngân sách AI từ lúc hỏi)
@property (nonatomic, readonly, copy) NSString *customPrompt;   // rỗng = dùng prompt mặc định
@property (nonatomic, readonly) BOOL hideWebCards;
@property (nonatomic, readonly) BOOL showOriginal;
@property (nonatomic, readonly) BOOL incognito;
@property (nonatomic, readonly) BOOL localOnly;
@property (nonatomic, readonly) BOOL verbose;
@property (nonatomic, readonly) BOOL streaming;                 // trả lời theo SSE (v1.1)
@property (nonatomic, readonly) BOOL markdown;                  // trình bày Markdown khi hiển thị (v1.1)
@property (nonatomic, readonly, copy) NSString *timeoutAction;  // bubble | keep | retry
@property (nonatomic, readonly) NSInteger maxToolRounds;        // 1–4, mặc định 3
@property (nonatomic, readonly) BOOL toolSystemInfo;
@property (nonatomic, readonly) BOOL toolClipboard;
@property (nonatomic, readonly) BOOL toolFetchURL;

@property (nonatomic, readonly) BOOL toolCurrentApp;
@property (nonatomic, readonly) BOOL deferredReplies;
@property (nonatomic, readonly) BOOL liveSiriUpdates;
@property (nonatomic, readonly) BOOL sttEnabled;
@property (nonatomic, readonly, copy) NSString *sttLanguage, *sttTranslate, *sttPrompt;
@property (nonatomic, readonly) NSInteger sttMaxSec, sttWaitMs;
@property (nonatomic, readonly, copy) NSString *ttsMode, *ttsSource, *ttsLang; // ttsSource is effective; private / errors-only use system
@property (nonatomic, readonly) double ttsSpeed, ttsVolume;

- (NSString *)fallbackModelForProvider:(SXProvider)provider;
- (NSString *)activeModel;
- (NSString *)systemPrompt;

@end

NS_ASSUME_NONNULL_END
