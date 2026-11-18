#import <Foundation/Foundation.h>
#import "SXTools.h"

NS_ASSUME_NONNULL_BEGIN

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

@end

NS_ASSUME_NONNULL_END
