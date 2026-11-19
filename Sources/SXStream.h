#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SXStreamFormat) {
	SXStreamFormatOpenAI = 0, // data: {choices[0].delta.content} / [DONE]
	SXStreamFormatGemini,     // data: {candidates[0].content.parts[].text}
	SXStreamFormatResponses,  // data: {type:"response.output_text.delta", delta:"…"}
};

/// Nhận từng mảnh văn bản mới trong lúc model đang viết.
typedef void (^SXStreamDelta)(NSString *delta, NSInteger firstTokenMs);

/// POST JSON theo chế độ SSE (Server-Sent Events) — đồng bộ trên luồng gọi
/// (mọi thao tác URLSession đều bất đồng bộ — chỉ giữ semaphore như SXHTTP).
/// Trả về dict:
///   @"content"       NSString   nội dung tích lũy
///   @"sawToolCalls"  BOOL       model có phát tool/function call trong stream
///   @"toolCalls"     NSArray    (OpenAI) đã gộp đủ: @{id, type, function:{name, arguments}}
///   @"functionCalls" NSArray    (Gemini) đã gộp: @{name, args}
///   @"responseId"    NSString?  (Responses) id của lượt, để gửi `previous_response_id`
///   @"reasoning"     NSString?  (Responses) tóm tắt suy luận, nếu máy chủ gửi kèm
///   @"status"        NSNumber   HTTP status (0 nếu lỗi mạng trước khi có response)
///   @"firstTokenMs"  NSNumber   ms đến token đầu tiên (-1 nếu không có)
///   @"errorText"     NSString?  đoạn lỗi từ máy chủ (khi status ≥ 400)
/// Lỗi mạng thật → nil + *outErr.
@interface SXStream : NSObject

+ (nullable NSDictionary *)postJSON:(NSDictionary *)body
							   toURL:(NSString *)urlString
							 headers:(NSDictionary<NSString *, NSString *> *)headers
							  format:(SXStreamFormat)format
							 timeout:(NSTimeInterval)timeoutSeconds
						 idleTimeout:(NSTimeInterval)idleTimeout
							 onDelta:(nullable SXStreamDelta)onDelta
							   error:(NSError **)outErr;

@end

NS_ASSUME_NONNULL_END
