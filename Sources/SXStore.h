#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Lưu dữ liệu dùng chung giữa SpringBoard và Preferences. Không gọi trên luồng ACE.
@interface SXStore : NSObject
+ (instancetype)shared;
/// Serializes asynchronous store work within each process.
+ (dispatch_queue_t)queue;
- (instancetype)initWithDirectory:(NSString *)directory;
/// {history: [{id,q,a,date}], historyEpoch: string, stats: dictionary, statsEpoch: string}.
- (nullable NSDictionary *)snapshot;
/// Từ chối ghi khi lịch sử đã được xóa sau khi request bắt đầu.
- (BOOL)appendQuestion:(NSString *)question answer:(NSString *)answer limit:(NSUInteger)limit epoch:(NSString *)epoch startedAt:(NSTimeInterval)startedAt;
- (BOOL)deleteHistoryID:(NSString *)identifier;
- (BOOL)clearHistory;
/// Epoch bảo vệ các sự kiện đang xếp hàng không phục hồi thống kê sau khi xóa.
- (BOOL)recordEvent:(NSString *)event milliseconds:(nullable NSNumber *)milliseconds epoch:(NSString *)epoch startedAt:(NSTimeInterval)startedAt;
- (BOOL)clearStats;
/// STT trial metadata only (no recorded audio or text), works across processes.
- (BOOL)armSTTTrial;
- (nullable NSString *)claimSTTTrialStartedAt:(NSTimeInterval)startedAt;
- (BOOL)finishSTTTrial:(NSString *)identifier success:(BOOL)success;
@end

NS_ASSUME_NONNULL_END
