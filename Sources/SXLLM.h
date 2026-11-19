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

@interface SXLLM : NSObject

/// Đặt câu hỏi cho model đã cấu hình. completion có thể được gọi đồng bộ
/// (lỗi cấu hình) hoặc bất đồng bộ (từ callback URLSession) — caller tự giữ lock.
+ (void)askQuestion:(NSString *)question
			history:(NSArray<NSDictionary *> *)history
			  tools:(NSArray<NSDictionary *> *)toolDefs
			executor:(nullable SXToolExec)executor
		 completion:(SXLLMCompletion)completion;

/// Kiểm tra một provider cụ thể mà không thay đổi lựa chọn toàn cục.
+ (void)askQuestion:(NSString *)question
            history:(NSArray<NSDictionary *> *)history
              tools:(NSArray<NSDictionary *> *)toolDefs
           executor:(nullable SXToolExec)executor
           provider:(SXProvider)provider
         completion:(SXLLMCompletion)completion;

@end

NS_ASSUME_NONNULL_END
