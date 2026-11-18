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

/// Các key UI được phép ghi trực tiếp (dùng cho nút "Khôi phục mặc định" và trang cấu hình).
FOUNDATION_EXPORT NSArray<NSString *> *SXPreferenceKeys(void);

/// Tên hiển thị của nhà cung cấp — "OpenAI" / "Gemini".
FOUNDATION_EXPORT NSString *SXProviderDisplayName(SXProvider provider);

/// Model gợi ý cho từng nhà cung cấp: @[ @{@"model", @"title", @"hint"} ].
FOUNDATION_EXPORT NSArray<NSDictionary *> *SXModelPresets(SXProvider provider);

@interface SXPrefs : NSObject

+ (instancetype)shared;

/// Đọc lại toàn bộ cài đặt (CFPreferences + fallback file). Log lại tóm tắt.
- (void)reload;

/// Ghi một key chuỗi (CFPreferences + đồng bộ ngay). value = nil → xóa key.
+ (void)setString:(nullable NSString *)value forKey:(NSString *)key;

/// Ghi giá trị bất kỳ (NSString / NSNumber / nil để xóa) + đồng bộ ngay.
+ (void)setValue:(nullable id)value forKey:(NSString *)key;

/// Xóa toàn bộ key của SiriX khỏi domain (dùng cho "Khôi phục cài đặt mặc định").
+ (void)resetAll;

/// Chuẩn hóa endpoint OpenAI: bỏ khoảng trắng + "/" cuối. nil nếu không phải http(s) có host.
+ (nullable NSString *)normalizedBaseURL:(nullable NSString *)raw;

/// Kiểm tra nhanh một endpoint có dùng được không (để UI cảnh báo trước khi lưu).
+ (BOOL)isValidBaseURL:(nullable NSString *)raw;

/// "sk-…a1b2" — hiển thị khóa đã che, không bao giờ in đầy đủ.
+ (NSString *)maskedKey:(nullable NSString *)key;

/// Đọc một key chuỗi bất kỳ (dùng cho dữ liệu phụ như kết quả kiểm tra gần nhất).
+ (nullable NSString *)stringForKey:(NSString *)key;

@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) SXReplyMode mode;
@property (nonatomic, readonly) SXProvider provider;
@property (nonatomic, readonly, copy) NSString *triggerMode; // auto | prefix
@property (nonatomic, readonly, copy) NSString *openaiKey;
@property (nonatomic, readonly, copy) NSString *openaiBase;
@property (nonatomic, readonly, copy) NSString *openaiModel;
@property (nonatomic, readonly, copy) NSString *geminiKey;
@property (nonatomic, readonly, copy) NSString *geminiModel;
@property (nonatomic, readonly) double temperature;      // 0–2, làm tròn 0.1
@property (nonatomic, readonly) NSInteger contextTurns;  // 2–40 cặp Q/A giữ lại
@property (nonatomic, readonly) NSTimeInterval responseTimeout; // 2–30 giây (ngân sách AI từ lúc hỏi)
@property (nonatomic, readonly, copy) NSString *customPrompt;   // rỗng = dùng prompt mặc định
@property (nonatomic, readonly) BOOL hideWebCards;
@property (nonatomic, readonly) BOOL showOriginal;
@property (nonatomic, readonly) BOOL incognito;
@property (nonatomic, readonly) BOOL speakErrors;
@property (nonatomic, readonly) BOOL verbose;
@property (nonatomic, readonly) BOOL streaming;                 // trả lời theo SSE (v1.1)
@property (nonatomic, readonly) BOOL markdown;                  // trình bày Markdown khi hiển thị (v1.1)
@property (nonatomic, readonly, copy) NSString *timeoutAction;  // "bubble" | "keep" — khi hết giờ (chế độ Thay thế)
@property (nonatomic, readonly) NSInteger maxToolRounds;        // 1–4, mặc định 3
/// Tên các công cụ người dùng đã tắt (xem `SXTools catalog`). Rỗng = bật tất cả.
@property (nonatomic, readonly, copy) NSSet<NSString *> *disabledTools;

/// Công cụ có đang bật không (dùng cho màn hình Cài đặt → Công cụ).
- (BOOL)isToolEnabled:(NSString *)name;
/// Bật/tắt một công cụ và ghi ngay xuống prefs.
+ (void)setToolNamed:(NSString *)name enabled:(BOOL)enabled;

- (nullable NSString *)activeAPIKey;
- (NSString *)activeModel;
- (NSString *)activeBaseURL;
- (NSString *)systemPrompt;

#pragma mark - Tóm tắt trạng thái cho giao diện

/// "Sẵn sàng" / "Đã tắt" / "Thiếu khóa API".
@property (nonatomic, readonly, copy) NSString *statusSummary;
/// "OpenAI · gpt-4o-mini".
@property (nonatomic, readonly, copy) NSString *providerSummary;
/// "Thông minh · tự động · chờ 10s".
@property (nonatomic, readonly, copy) NSString *replySummary;
/// "Đang lưu · 8 câu gần nhất" hoặc "Không lưu".
@property (nonatomic, readonly, copy) NSString *historySummary;
@property (nonatomic, readonly, copy) NSString *activeProviderName;

@end

NS_ASSUME_NONNULL_END
