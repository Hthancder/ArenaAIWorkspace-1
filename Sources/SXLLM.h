#import <Foundation/Foundation.h>
#import "SXTools.h"
#import "SXPrefs.h"
#import "SXStream.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^SXLLMCompletion)(NSString * _Nullable answer,
								NSError * _Nullable error,
								NSDictionary * _Nullable info);

@interface SXLLM : NSObject

/// Gọi trên hàng đợi nền. Completion được gọi đúng một lần trên hàng đợi gọi.
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

/// Một lần thử, có hủy/giới hạn token. Dùng model/prompt nil để lấy cấu hình.
+ (void)performQuestion:(NSString *)question
                history:(NSArray<NSDictionary *> *)history
                  tools:(NSArray<NSDictionary *> *)tools
               executor:(nullable SXToolExec)executor
                  prefs:(SXPrefs *)prefs
               provider:(SXProvider)provider
                  model:(nullable NSString *)model
                 prompt:(nullable NSString *)prompt
              maxTokens:(NSUInteger)maxTokens
                request:(SXRequest *)request
               progress:(nullable SXStreamProgress)progress
             completion:(SXLLMCompletion)completion;
@end

NS_ASSUME_NONNULL_END
