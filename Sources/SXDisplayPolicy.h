#import <Foundation/Foundation.h>
#import "SXPrefs.h"

NS_ASSUME_NONNULL_BEGIN

/// Chính sách hiển thị — MỌI quyết định hiển thị đi qua đây (DESIGN-SYSTEM §3).
/// Đầu vào: chế độ + kết quả (sẵn sàng / lỗi / hết giờ) + lựa chọn khi hết giờ.
@interface SXDisplayPolicy : NSObject

/// Lỗi AI có nên hiện bubble không?
/// - Thông minh: chỉ khi "Báo lỗi bằng giọng nói" bật.
/// - Thay thế mọi câu: LUÔN hiện bubble lỗi (không thả câu trả lời Siri gốc).
+ (BOOL)shouldShowErrorBubbleInMode:(SXReplyMode)mode speakErrors:(BOOL)speakErrors;

/// Hết giờ chờ: trả về NỘI DUNG bubble cần chèn, hoặc nil = giữ câu trả lời Siri gốc.
/// - Thông minh: luôn nil (giữ Siri gốc — an toàn).
/// - Thay thế mọi câu: theo timeoutAction (bubble → thông điệp; keep → nil;
///   retry → nil vì đáp án của lần thử lại sẽ tới qua thông báo/Lịch sử).
+ (nullable NSString *)timeoutBubbleMessageInMode:(SXReplyMode)mode
										   action:(NSString *)timeoutAction;

/// Trả lời trễ chỉ được đưa vào Notification Center nếu được bật và lượt không riêng tư.
+ (BOOL)shouldSendDeferredAnswerWhenEnabled:(BOOL)enabled privateTurn:(BOOL)privateTurn;

/// Ghi 1 dòng log thống nhất cho mọi quyết định hiển thị.
+ (void)logDecision:(NSString *)decision source:(NSString *)source;

@end

NS_ASSUME_NONNULL_END
