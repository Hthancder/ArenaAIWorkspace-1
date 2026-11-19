#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Lõi HTTP dùng chung cho mọi request của SiriX (chat, kiểm tra kết nối,
/// streaming). Trước đây mỗi nơi tự dựng `NSURLSession` + semaphore riêng nên
/// hành vi lệch nhau: chỗ chờ 60 giây, chỗ chờ timeout+2, chỗ không theo dõi
/// tiến trình stream. Một chỗ duy nhất ở đây để mọi thứ giống nhau và test được.
///
/// Hàm đồng bộ (gọi trên luồng nền). `timeout` là trần cho CẢ request, kể cả
/// phần thân trả về; `idleTimeout` là thời gian tối đa không nhận thêm byte.

FOUNDATION_EXPORT NSString *const SXHTTPErrorDomain;

/// Kết quả một request. status = 0 khi lỗi transport trước khi có response.
@interface SXHTTPResult : NSObject
@property (nonatomic) NSInteger status;
@property (nonatomic, strong) NSData *body;
@property (nonatomic, copy, nullable) NSString *mimeType;
@property (nonatomic, strong, nullable) NSError *error;
@end

/// Tiến trình đọc thân (dùng cho stream). Trả về NO để huỷ request.
typedef BOOL (^SXHTTPDataHandler)(NSData *data);

/// Báo mã trạng thái ngay khi có header (trước byte thân đầu tiên) — stream
/// dùng nó để quyết định có đọc thân theo kiểu SSE hay gom thân báo lỗi.
typedef void (^SXHTTPStatusHandler)(NSInteger status);

@interface SXHTTP : NSObject

/// POST JSON. `onData` (tuỳ chọn) được gọi liên tục với từng mẩu thân nhận
/// được — stream dùng nó để đọc SSE ngay khi có byte, không chờ hết body.
+ (SXHTTPResult *)postURL:(NSString *)urlString
					body:(NSDictionary *)body
				 headers:(NSDictionary<NSString *, NSString *> *)headers
				 timeout:(NSTimeInterval)timeout
			 idleTimeout:(NSTimeInterval)idleTimeout
				  onData:(nullable SXHTTPDataHandler)onData;

/// Như trên, kèm callback báo mã trạng thái khi header tới.
+ (SXHTTPResult *)postURL:(NSString *)urlString
					 body:(NSDictionary *)body
				  headers:(NSDictionary<NSString *, NSString *> *)headers
				  timeout:(NSTimeInterval)timeout
			  idleTimeout:(NSTimeInterval)idleTimeout
				 onStatus:(nullable SXHTTPStatusHandler)onStatus
				   onData:(nullable SXHTTPDataHandler)onData;

/// GET không đi theo redirect (công cụ đọc web). Chặn body quá `maxBytes`.
+ (SXHTTPResult *)getURL:(NSString *)urlString
				 headers:(NSDictionary<NSString *, NSString *> *)headers
				 timeout:(NSTimeInterval)timeout
				idleTimeout:(NSTimeInterval)idleTimeout
				  maxBytes:(NSUInteger)maxBytes;

/// Thông điệp lỗi tiếng Việt đọc được từ thân JSON `{error:{message}}`
/// (OpenAI, Gemini) — dùng chung cho mọi tầng hiển thị.
+ (NSString *)userMessageForStatus:(NSInteger)status data:(nullable NSData *)data;
+ (NSError *)errorWithStatus:(NSInteger)status data:(nullable NSData *)data;
+ (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message;

+ (NSString *)userAgent;

@end

NS_ASSUME_NONNULL_END
