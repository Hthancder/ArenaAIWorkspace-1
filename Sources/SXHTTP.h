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
/// Địa chỉ cuối cùng sau các lần chuyển hướng đã được chấp nhận (nil = như cũ).
@property (nonatomic, copy, nullable) NSURL *finalURL;
@property (nonatomic, strong, nullable) NSError *error;
@end

/// Tiến trình đọc thân (dùng cho stream). Trả về NO để huỷ request.
typedef BOOL (^SXHTTPDataHandler)(NSData *data);

/// Báo mã trạng thái ngay khi có header (trước byte thân đầu tiên) — stream
/// dùng nó để quyết định có đọc thân theo kiểu SSE hay gom thân báo lỗi.
typedef void (^SXHTTPStatusHandler)(NSInteger status);

@interface SXHTTP : NSObject

/// Nhãn request mặc định cho LUỒNG hiện tại. Bên gọi đặt một lần (ví dụ màn
/// trò chuyện thử đặt @"chat-test" trước khi lên luồng nền), mọi request phát
/// sinh trên luồng đó — kể cả stream — tự mang nhãn ấy và huỷ được theo nhóm.
+ (void)setCurrentRequestLabel:(nullable NSString *)label;
+ (nullable NSString *)currentRequestLabel;

/// Huỷ mọi request đang chạy của một "phiên" (nhãn bất kỳ, ví dụ @"chat-test").
/// Màn trò chuyện thử dùng nó để nút Dừng thật sự dừng mạng, thay vì chỉ ẩn
/// bong bóng và để request chạy tới hết ngân sách (tốn token, giữ kết nối).
/// Gọi được từ luồng bất kỳ; request đã bị huỷ trả lỗi NSURLErrorCancelled.
+ (void)cancelRequestsWithLabel:(nullable NSString *)label;

/// Như `+postURL:…onData:` nhưng có nhãn để huỷ về sau.
+ (SXHTTPResult *)postURL:(NSString *)urlString
					 body:(NSDictionary *)body
				  headers:(NSDictionary<NSString *, NSString *> *)headers
				  timeout:(NSTimeInterval)timeout
			  idleTimeout:(NSTimeInterval)idleTimeout
				   onData:(nullable SXHTTPDataHandler)onData
					label:(nullable NSString *)label;

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

/// GET mặc định KHÔNG đi theo redirect: bên gọi (công cụ đọc web) cần tự xét
/// đích chuyển hướng bằng SXNetPolicy trước khi đi tiếp. Chặn body quá `maxBytes`.
+ (SXHTTPResult *)getURL:(NSString *)urlString
				 headers:(NSDictionary<NSString *, NSString *> *)headers
				 timeout:(NSTimeInterval)timeout
				idleTimeout:(NSTimeInterval)idleTimeout
				  maxBytes:(NSUInteger)maxBytes;

/// Như trên nhưng cho phép đi theo chuyển hướng. `rejectRedirect` được hỏi cho
/// MỖI bước nhảy (nhận URL đích): trả YES để DỪNG và trả 3xx về cho bên gọi.
/// Nhờ vậy một redirect không thể lọt qua host nội bộ hay hạ cấp https→http.
+ (SXHTTPResult *)getURL:(NSString *)urlString
				 headers:(NSDictionary<NSString *, NSString *> *)headers
				 timeout:(NSTimeInterval)timeout
				idleTimeout:(NSTimeInterval)idleTimeout
				  maxBytes:(NSUInteger)maxBytes
	rejectRedirect:(BOOL (^ _Nullable)(NSURL *target))rejectRedirect;



/// Thông điệp lỗi tiếng Việt đọc được từ thân JSON `{error:{message}}`
/// (OpenAI, Gemini) — dùng chung cho mọi tầng hiển thị.
+ (NSString *)userMessageForStatus:(NSInteger)status data:(nullable NSData *)data;
+ (NSError *)errorWithStatus:(NSInteger)status data:(nullable NSData *)data;
+ (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message;

+ (NSString *)userAgent;

@end

NS_ASSUME_NONNULL_END
