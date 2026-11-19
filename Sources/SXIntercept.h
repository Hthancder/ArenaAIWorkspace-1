#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Máy trạng thái của một lượt hỏi–đáp:
///
///   (nhận câu hỏi) → chờ AI → quyết định (thay bằng đáp án / bubble lỗi /
///   bubble hết giờ / giữ nguyên Siri) → áp quyết định cho mọi lệnh ACE cùng
///   hội thoại trong một cửa sổ ngắn.
///
/// Mọi hook của tweak đi qua đối tượng này; nó không vẽ UI, chỉ quyết định nội
/// dung và sửa lệnh ACE tại chỗ (an toàn khi hook chạy trên luồng chính).
@interface SXIntercept : NSObject

+ (instancetype)shared;

/// Đăng ký notify xoá lịch sử (gọi từ %ctor).
- (void)setup;

/// Có câu hỏi mới (bắt được từ nhận diện giọng nói / Type-to-Siri / phím tắt).
- (void)noteQuestion:(NSString *)text source:(NSString *)source;

/// Đường vào lệnh ACE đến (AFConnection _handleCommand:reply:) — phân loại,
/// chờ câu trả lời AI rồi thay thế tại chỗ. Trả về YES nếu đã thay đổi.
- (BOOL)handleIncomingCommand:(id)command;

/// Đường dự phòng khi AddViews được chèn vào hội thoại (AFConversation).
- (BOOL)handleAddViewsInsertion:(id)command;

/// Xoá lịch sử đã lưu + ngữ cảnh trong bộ nhớ (công cụ reset_conversation).
- (BOOL)clearHistory;

@end

NS_ASSUME_NONNULL_END
