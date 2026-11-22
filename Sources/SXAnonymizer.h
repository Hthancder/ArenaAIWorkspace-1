#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Ẩn thông tin nhận dạng khỏi câu hỏi TRƯỚC KHI gửi lên nhà cung cấp AI, rồi
/// khôi phục lại trong đáp án.
///
/// Vì sao cần: câu hỏi hay chứa số điện thoại ("nhắc mẹ gọi 0912345678"), email,
/// số thẻ, số CCCD, số tài khoản. Những thứ đó đi thẳng tới OpenAI/Google, nằm
/// trong log của họ, và (tuỳ cấu hình) trong lịch sử trên máy. Chế độ "Không lưu
/// lịch sử" của SiriX chỉ ngừng GHI trên máy — nó không giảm dữ liệu gửi đi.
///
/// Cách làm: mỗi lượt hỏi có một "phiên" (`SXAnonTurn`) giữ bảng
/// placeholder → giá trị gốc trong RAM. Model chỉ thấy `[sđt-1]`, `[email-1]`,
/// `[số-1]`; khi đáp án về, `-restore:` đổi lại để người dùng vẫn đọc được số
/// thật. Bảng này **không** được ghi xuống đĩa và bị bỏ khi lượt kết thúc.
///
/// Giới hạn có ý thức (đừng hứa quá):
/// - KHÔNG ẩn tên người, địa chỉ, tên trường/công ty — không thể nhận đúng mà
///   không phá nghĩa câu hỏi (xem `docs/IMPLEMENTATION-STATUS.md`).
/// - KHÔNG ẩn nội dung do công cụ trả về (web_fetch…) vì đó là dữ liệu công khai
///   do máy chủ trả, không phải do người dùng gõ.
@interface SXAnonTurn : NSObject

/// Ẩn các giá trị nhận dạng đã biết. Chuỗi rỗng/nil trả về nguyên trạng.
- (NSString *)redact:(nullable NSString *)text;

/// Khôi phục placeholder (kể cả khi model viết lại hơi khác: `[sđt 1]`,
/// `[SDT-1]`, `sđt-1`). Không có placeholder nào thì trả nguyên trạng.
- (NSString *)restore:(nullable NSString *)text;

/// Số giá trị đã ẩn trong lượt này (để ghi log/kiểm thử).
- (NSUInteger)redactedCount;

/// Bật/tắt toàn cục cho bộ lọc. Đọc từ `SXPrefs` ở tầng gọi, không phải ở đây —
/// lớp này cố ý không phụ thuộc UIKit hay CFPreferences để test được trên macOS.
@property (nonatomic) BOOL enabled;

@end

NS_ASSUME_NONNULL_END
