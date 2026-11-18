#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Kết quả công cụ: @{@"result": @"…"} hoặc nil + error.
typedef NSDictionary * _Nullable (^SXToolExec)(NSString *name,
											   NSDictionary *arguments,
											   NSError * _Nullable * _Nullable error);

@interface SXTools : NSObject

/// Danh sách công cụ dạng trung lập (OpenAI/Gemini đều tự chuyển đổi).
/// Mỗi phần tử: @{@"name", @"description", @"parameters" (JSON schema)}.
+ (NSArray<NSDictionary *> *)definitions;

/// Chạy công cụ đã bật. Trả về @{ @"result": … } hoặc nil kèm lỗi.
+ (nullable NSDictionary *)execute:(NSString *)name
						arguments:(NSDictionary *)arguments
							 error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
