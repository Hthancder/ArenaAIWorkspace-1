// SBTools.h — bộ công cụ để LLM điều khiển thiết bị (mở app, gọi, lịch, nhạc…)
#import <Foundation/Foundation.h>

@interface SBTools : NSObject
/// Mô tả tool theo chuẩn OpenAI function-calling.
+ (NSArray *)openAIToolSpecs;
/// Tên tool có tồn tại không (dùng để validate trước khi chạy).
+ (BOOL)isKnownTool:(NSString *)name;
/// Chạy tool. completion(textKếtQuả) luôn trên main queue.
+ (void)runTool:(NSString *)name arguments:(NSString *)json completion:(void (^)(NSString *result))completion;
@end
