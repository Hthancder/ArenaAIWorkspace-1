#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SXIntercept : NSObject

+ (instancetype)shared;

/// Đăng ký notify xóa lịch sử (gọi từ %ctor).
- (void)setup;

/// Có câu hỏi mới (bắt được từ nhận diện giọng nói / Type-to-Siri).
- (void)noteQuestion:(NSString *)text source:(NSString *)source;
- (void)noteQuestion:(NSString *)text source:(NSString *)source reference:(nullable NSString *)reference stt:(nullable NSString *)outcome;
/// A user starts a new Siri request; cancel outstanding work before new text arrives.
- (void)beginRequest;
- (void)dialogDidDismiss;
- (void)preferencesDidChange;

/// Đường vào lệnh ACE đến (AFConnection _handleCommand:reply:) — phân loại,
/// chờ câu trả lời AI rồi thay thế tại chỗ. Trả về YES nếu đã thay đổi.
- (BOOL)handleIncomingCommand:(id)command;

/// Đường dự phòng khi AddViews được chèn vào hội thoại (AFConversation).
- (BOOL)handleAddViewsInsertion:(id)command;
- (BOOL)handleAddViewsInsertion:(id)command conversation:(nullable id)conversation;

- (BOOL)clearHistory;

@end

NS_ASSUME_NONNULL_END
