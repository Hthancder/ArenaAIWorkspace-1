#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SXStreamFormat) {
	SXStreamFormatOpenAI = 0, // data: {choices[0].delta.content} / [DONE]
	SXStreamFormatGemini,     // data: {candidates[0].content.parts[].text}
};

/// POST JSON theo chế độ SSE (Server-Sent Events) — đồng bộ trên luồng gọi
/// (mọi thao tác URLSession đều bất đồng bộ — chỉ giữ semaphore như SXHTTPPost).
/// Trả về dict:
///   @"content"       NSString   nội dung tích lũy
///   @"sawToolCalls"  BOOL       model muốn gọi công cụ → caller chuyển non-stream
///   @"status"        NSNumber   HTTP status (0 nếu lỗi mạng trước khi có response)
///   @"firstTokenMs"  NSNumber   ms đến token đầu tiên (-1 nếu không có)
///   @"errorText"     NSString?  đoạn lỗi từ máy chủ (khi status ≥ 400)
/// `timeoutSeconds` là ngân sách còn lại của cả lượt (SXLLM truyền vào) —
/// không bao giờ chờ lâu hơn trần 60 giây của SSE.
/// Lỗi mạng thật → nil + *outErr.
@interface SXStream : NSObject

+ (nullable NSDictionary *)postJSON:(NSDictionary *)body
							  toURL:(NSString *)urlString
							headers:(NSDictionary<NSString *, NSString *> *)headers
							 format:(SXStreamFormat)format
							timeout:(NSTimeInterval)timeoutSeconds
							   error:(NSError **)outErr;

@end

NS_ASSUME_NONNULL_END
