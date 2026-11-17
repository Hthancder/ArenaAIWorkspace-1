// SBLLM.h — gọi endpoint chat tuỳ chỉnh (OpenAI-compatible / Gemini / Anthropic / tự host)
#import <Foundation/Foundation.h>

@interface SBLLM : NSObject
/// Gửi câu hỏi bất đồng bộ. completion luôn được gọi trên main queue.
/// tools: mảng tool spec OpenAI, có thể nil.
+ (void)ask:(NSString *)prompt
      tools:(NSArray *)tools
 completion:(void (^)(NSString *answer, NSArray *toolCalls, NSError *error))completion;

/// Gọi tool đơn giản: trả lời cuối cùng dạng text.
+ (void)ask:(NSString *)prompt completion:(void (^)(NSString *, NSError *))completion;
@end
