#import <Foundation/Foundation.h>
#import "SXToolkit.h"

NS_ASSUME_NONNULL_BEGIN

/// Kết quả công cụ: @{@"result": @"…"} hoặc nil + error.
typedef NSDictionary * _Nullable (^SXToolExec)(NSString *name,
											   NSDictionary *arguments,
											   NSError * _Nullable * _Nullable error);

/// Cầu nối giữa pipeline LLM và SXToolkit: áp cấu hình người dùng (công cụ nào
/// đang bật) rồi chuyển tiếp xuống bộ thực thi.
@interface SXTools : NSObject

/// Schema công cụ đang bật, dạng trung lập (OpenAI/Gemini tự chuyển đổi).
+ (NSArray<NSDictionary *> *)definitions;

/// Chạy công cụ đang bật. Trả về @{ @"result": … } hoặc nil kèm lỗi.
+ (nullable NSDictionary *)execute:(NSString *)name
						 arguments:(NSDictionary *)arguments
							 error:(NSError * _Nullable * _Nullable)error;

/// Đoạn mô tả công cụ để nối vào system prompt (rỗng khi không có công cụ nào bật).
+ (NSString *)promptBrief;

/// Bắt đầu một lượt hỏi mới: xoá cache chống gọi lặp.
+ (void)beginTurn;

/// Toàn bộ công cụ có sẵn (kể cả đang tắt) — dùng cho màn hình Công cụ.
+ (NSArray<SXTool *> *)catalog;

@end

NS_ASSUME_NONNULL_END
