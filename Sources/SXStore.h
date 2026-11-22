#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Số lượt tối đa giữ trong kho Lịch sử. Đây là trần của KHO, độc lập với "Ngữ
/// cảnh hội thoại" (số câu gửi kèm cho AI): người dùng đặt ngữ cảnh 0 câu vẫn
/// xem được lịch sử, và đặt ngữ cảnh 40 câu cũng không làm phình tệp.
static const NSInteger SXStoreHistoryCapacity = 40;

// Lưu dữ liệu dùng chung giữa SpringBoard và Preferences. Không gọi trên luồng ACE.
@interface SXStore : NSObject
+ (instancetype)shared;
/// Serializes asynchronous store work within each process.
+ (dispatch_queue_t)queue;
- (instancetype)initWithDirectory:(NSString *)directory;
/// {history: [{id,q,a,date}], historyEpoch: string, stats: dictionary, statsEpoch: string}.
- (nullable NSDictionary *)snapshot;
/// Từ chối ghi khi lịch sử đã được xóa sau khi request bắt đầu.
/// `limit` KHÔNG cắt kho Lịch sử (kho luôn giữ tới SXStoreHistoryCapacity).
- (BOOL)appendQuestion:(NSString *)question answer:(NSString *)answer limit:(NSUInteger)limit epoch:(NSString *)epoch startedAt:(NSTimeInterval)startedAt;
- (BOOL)deleteHistoryID:(NSString *)identifier;
- (BOOL)clearHistory;
/// Epoch bảo vệ các sự kiện đang xếp hàng không phục hồi thống kê sau khi xóa.
- (BOOL)recordEvent:(NSString *)event milliseconds:(nullable NSNumber *)milliseconds epoch:(NSString *)epoch startedAt:(NSTimeInterval)startedAt;
/// Như trên, kèm số token máy chủ báo (@{in, out}) để Thống kê cộng dồn.
- (BOOL)recordEvent:(NSString *)event milliseconds:(nullable NSNumber *)milliseconds
			 tokens:(nullable NSDictionary *)tokens epoch:(NSString *)epoch startedAt:(NSTimeInterval)startedAt;
- (BOOL)clearStats;
@end

NS_ASSUME_NONNULL_END
