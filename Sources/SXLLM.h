#import <Foundation/Foundation.h>
#import "SXTools.h"
#import "SXPrefs.h"

NS_ASSUME_NONNULL_BEGIN

/// Phát ra (trên hàng đợi chính) mỗi lần một công cụ chạy xong, để giao diện
/// hiển thị “đang làm gì” thay vì chỉ một chấm “đang trả lời”.
/// userInfo: @{ @"name": NSString, @"ms": NSNumber, @"failed": NSNumber }.
FOUNDATION_EXPORT NSNotificationName const SXLLMToolActivityNotification;

typedef void (^SXLLMCompletion)(NSString * _Nullable answer,
								NSError * _Nullable error,
								NSDictionary * _Nullable info);

/// Mảnh văn bản mới trong lúc model còn đang viết (chỉ có với streaming).
typedef void (^SXLLMDelta)(NSString *delta, NSInteger firstTokenMs);

@interface SXLLM : NSObject

/// Đặt câu hỏi cho model đã cấu hình. completion có thể được gọi đồng bộ
/// (lỗi cấu hình) hoặc bất đồng bộ — caller tự giữ lock / chuyển luồng.
+ (void)askQuestion:(NSString *)question
			history:(NSArray<NSDictionary *> *)history
			  tools:(NSArray<NSDictionary *> *)toolDefs
		   executor:(nullable SXToolExec)executor
		 completion:(SXLLMCompletion)completion;

/// Kiểm tra một provider cụ thể mà không thay đổi lựa chọn toàn cục
/// (nút “Kiểm tra kết nối” dùng): không công cụ, không stream, lỗi ngắn gọn.
+ (void)askQuestion:(NSString *)question
			history:(NSArray<NSDictionary *> *)history
			  tools:(NSArray<NSDictionary *> *)toolDefs
		   executor:(nullable SXToolExec)executor
		   provider:(SXProvider)provider
		 completion:(SXLLMCompletion)completion;

/// Như trên, kèm callback nhận từng mảnh văn bản khi đang stream (chat thử).
+ (void)askQuestion:(NSString *)question
			history:(NSArray<NSDictionary *> *)history
			  tools:(NSArray<NSDictionary *> *)toolDefs
		   executor:(nullable SXToolExec)executor
			onDelta:(nullable SXLLMDelta)onDelta
		 completion:(SXLLMCompletion)completion;

@end

NS_ASSUME_NONNULL_END
