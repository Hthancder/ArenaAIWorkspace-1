#import "SXTools.h"
#import "SXPrefs.h"
#import "SXLog.h"
#import <UIKit/UIKit.h>
#include <sys/utsname.h>
#include <arpa/inet.h>
#include <netinet/in.h>

static NSString *const kSXToolsErrorDomain = @"com.sirix.tools";

static NSError *SXToolError(NSInteger code, NSString *message) {
	return [NSError errorWithDomain:kSXToolsErrorDomain
							   code:code
						   userInfo:@{NSLocalizedDescriptionKey: message ?: @"Lỗi công cụ"}];
}

#pragma mark - Công cụ

static NSDictionary *SXToolSystemInfo(NSError **error) {
	UIDevice *device = UIDevice.currentDevice;
	struct utsname info;
	uname(&info);

	device.batteryMonitoringEnabled = YES;
	float battery = device.batteryLevel;
	NSString *batteryText = battery < 0 ? @"không rõ"
		: [NSString stringWithFormat:@"%.0f%%", battery * 100.0];

	NSDictionary *fs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:NULL];
	double freeGB = [fs[NSFileSystemFreeSize] doubleValue] / (1024.0 * 1024.0 * 1024.0);
	double totalGB = [fs[NSFileSystemSize] doubleValue] / (1024.0 * 1024.0 * 1024.0);

	NSString *result = [NSString stringWithFormat:
		@"Thiết bị: %@ (%@), iOS %@, tên “%@”. "
		@"Pin: %@. Dung lượng: %.1f/%.1f GB còn trống. Ngôn ngữ: %@. "
		@"Thời gian hiện tại: %@.",
		device.model, [NSString stringWithUTF8String:info.machine] ?: @"?",
		device.systemVersion, device.name,
		batteryText, freeGB, totalGB,
		[NSLocale.currentLocale localeIdentifier],
		[NSDateFormatter localizedStringFromDate:[NSDate date]
									   dateStyle:NSDateFormatterMediumStyle
									   timeStyle:NSDateFormatterMediumStyle]];
	return @{@"result": result};
}

static NSDictionary *SXToolClipboardCopy(NSDictionary *args, NSError **error) {
	id text = args[@"text"];
	if (![text isKindOfClass:[NSString class]] || !((NSString *)text).length) {
		if (error) *error = SXToolError(1, @"Thiếu tham số “text”.");
		return nil;
	}
	UIPasteboard.generalPasteboard.string = text;
	SXLogDbg(@"tool", @"clipboard_copy (%lu ký tự)", (unsigned long)[(NSString *)text length]);
	return @{@"result": @"Đã sao chép vào bảng nhớ tạm."};
}

static NSDictionary *SXToolClipboardRead(NSError **error) {
	NSString *text = UIPasteboard.generalPasteboard.string;
	if (!text.length) return @{@"result": @"Bảng nhớ tạm trống."};
	if (text.length > 1000) text = [[text substringToIndex:1000] stringByAppendingString:@"…"];
	return @{@"result": text};
}

static NSString *SXStripHTML(NSData *data) {
	NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (!html) html = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
	if (!html) return nil;

	static NSRegularExpression *script, *tags, *spaces;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		script = [NSRegularExpression regularExpressionWithPattern:@"<(script|style)[\\s\\S]*?</\\1\\s*>|<!--[\\s\\S]*?-->"
														  options:NSRegularExpressionCaseInsensitive
															error:NULL];
		tags = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>"
														options:0
														  error:NULL];
		spaces = [NSRegularExpression regularExpressionWithPattern:@"\\s+"
														  options:0
															error:NULL];
	});
	NSRange all = NSMakeRange(0, html.length);
	html = [script stringByReplacingMatchesInString:html options:0 range:all withTemplate:@" "];
	html = [tags stringByReplacingMatchesInString:html options:0 range:NSMakeRange(0, html.length) withTemplate:@" "];

	NSArray<NSString *> *entities = @[@"&nbsp;", @"&amp;", @"&lt;", @"&gt;", @"&quot;", @"&#39;", @"&#x27;"];
	NSArray<NSString *> *replacers = @[@" ", @"&", @"<", @">", @"\"", @"'", @"'"];
	for (NSUInteger i = 0; i < entities.count; i++) {
		html = [html stringByReplacingOccurrencesOfString:entities[i] withString:replacers[i]];
	}
	html = [spaces stringByReplacingMatchesInString:html options:0 range:NSMakeRange(0, html.length) withTemplate:@" "];
	html = [html stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (html.length > 3500) html = [[html substringToIndex:3500] stringByAppendingString:@"…"];
	return html;
}

/// Chặn máy chủ nội bộ/loopback: công cụ này do model điều khiển, nên không được
/// phép quét router, NAS hay service chạy trên máy người dùng.
static BOOL SXHostLooksPrivate(NSString *host) {
	if (![host isKindOfClass:[NSString class]] || !host.length) return YES;
	NSString *lower = host.lowercaseString;
	if ([lower isEqualToString:@"localhost"] || [lower hasSuffix:@".local"] ||
		[lower hasSuffix:@".internal"] || [lower hasSuffix:@".lan"]) return YES;

	// IPv6 literal
	if ([lower containsString:@":"]) {
		if ([lower isEqualToString:@"::1"] || [lower hasPrefix:@"fc"] ||
			[lower hasPrefix:@"fd"] || [lower hasPrefix:@"fe80"] || [lower isEqualToString:@"::"]) return YES;
	}

	// IPv4 literal
	struct in_addr addr;
	if (inet_pton(AF_INET, lower.UTF8String, &addr) == 1) {
		uint32_t value = ntohl(addr.s_addr);
		uint32_t a = (value >> 24) & 0xFF;
		uint32_t b = (value >> 16) & 0xFF;
		if (a == 0 || a == 10 || a == 127) return YES;
		if (a == 169 && b == 254) return YES;
		if (a == 172 && b >= 16 && b <= 31) return YES;
		if (a == 192 && b == 168) return YES;
		return NO;
	}

	// Host toàn chữ số (dạng thập phân của IPv4, ví dụ 2130706433).
	NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
	if ([lower rangeOfCharacterFromSet:[digits invertedSet]].location == NSNotFound) return YES;
	return NO;
}

/// Delegate nhỏ: không đi theo redirect, cắt body ở 2 MB.
@interface SXFetchDelegate : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, copy) void (^completion)(NSData *data, NSInteger status, NSError *error);
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSMutableData *buffer;
@property (nonatomic) NSInteger status;
@property (nonatomic) BOOL finished;
@property (nonatomic) NSUInteger limit;
@end

@implementation SXFetchDelegate

- (instancetype)init {
	self = [super init];
	if (self) {
		_buffer = [NSMutableData data];
		_limit = 2 * 1024 * 1024;
	}
	return self;
}

- (void)finishWithError:(NSError *)error {
	if (self.finished) return;
	self.finished = YES;
	void (^completion)(NSData *, NSInteger, NSError *) = self.completion;
	self.completion = nil;
	[self.session finishTasksAndInvalidate];
	self.session = nil;
	if (completion) completion(self.buffer, self.status, error);
}

- (void)URLSession:(NSURLSession *)session
				task:(NSURLSessionTask *)task
	willPerformHTTPRedirection:(NSHTTPURLResponse *)response
			newRequest:(NSURLRequest *)request
	 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
	(void)session; (void)task; (void)response;
	SXLogWrn(@"tool", @"fetch_url: chặn redirect → %@", request.URL.absoluteString);
	completionHandler(nil); // giữ nguyên phản hồi 3xx, không tải tiếp
}

- (void)URLSession:(NSURLSession *)session
		  dataTask:(NSURLSessionDataTask *)dataTask
	didReceiveResponse:(NSURLResponse *)response
	 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
	(void)session; (void)dataTask;
	self.status = [(NSHTTPURLResponse *)response statusCode];
	completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
	(void)session;
	if (self.buffer.length + data.length > self.limit) {
		[dataTask cancel];
		NSError *error = SXToolError(7, @"Trang quá lớn để đọc (giới hạn 2 MB).");
		[self finishWithError:error];
		return;
	}
	[self.buffer appendData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
	(void)session; (void)task;
	[self finishWithError:error];
}

@end

static NSDictionary *SXToolFetchURL(NSDictionary *args, NSError **error) {
	id raw = args[@"url"];
	if (![raw isKindOfClass:[NSString class]]) {
		if (error) *error = SXToolError(2, @"Thiếu tham số “url”.");
		return nil;
	}
	NSURL *url = [NSURL URLWithString:(NSString *)raw];
	if (!url || ![url.scheme.lowercaseString isEqualToString:@"https"]) {
		if (error) *error = SXToolError(3, @"Chỉ hỗ trợ URL bắt đầu bằng https://.");
		return nil;
	}
	if (SXHostLooksPrivate(url.host)) {
		SXLogWrn(@"tool", @"fetch_url bị chặn: máy chủ nội bộ (%@)", url.host ?: @"?");
		if (error) *error = SXToolError(8, @"Không cho phép đọc địa chỉ mạng nội bộ.");
		return nil;
	}

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	request.HTTPMethod = @"GET";
	// Công cụ chạy BÊN TRONG một lượt Siri (ngân sách ~10s) → không được tải
	// trang lâu hơn thế, nếu không câu trả lời luôn về muộn.
	request.timeoutInterval = 6;
	[request setValue:[NSString stringWithFormat:
		@"Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) SiriX/%@", SX_VERSION]
   forHTTPHeaderField:@"User-Agent"];

	SXFetchDelegate *delegate = [[SXFetchDelegate alloc] init];
	dispatch_semaphore_t sem = dispatch_semaphore_create(0);
	__block NSData *body = nil;
	__block NSInteger status = 0;
	__block NSError *fetchError = nil;
	delegate.completion = ^(NSData *data, NSInteger code, NSError *err) {
		body = data;
		status = code;
		fetchError = err;
		dispatch_semaphore_signal(sem);
	};

	NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	configuration.timeoutIntervalForRequest = 6;
	// Redirect đã bị chặn ở delegate (completionHandler(nil)) — không cần cấu hình thêm.
	NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration
														  delegate:delegate
													 delegateQueue:nil];
	delegate.session = session;
	[[session dataTaskWithRequest:request] resume];

	if (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(7 * NSEC_PER_SEC)))) {
		delegate.completion = nil;
		[session invalidateAndCancel];
		if (error) *error = SXToolError(4, @"Hết thời gian chờ khi tải trang.");
		return nil;
	}
	if (fetchError) {
		if (error) *error = SXToolError(5, [NSString stringWithFormat:@"Không tải được trang: %@", fetchError.localizedDescription]);
		return nil;
	}
	if (status < 200 || status >= 400) {
		if (error) *error = SXToolError(status, [NSString stringWithFormat:@"Máy chủ trả về HTTP %ld.", (long)status]);
		return nil;
	}
	NSString *text = SXStripHTML(body ?: [NSData data]);
	if (!text.length) {
		if (error) *error = SXToolError(6, @"Trang không có nội dung văn bản.");
		return nil;
	}
	SXLogDbg(@"tool", @"fetch_url %@ → %lu ký tự trích được", url.absoluteString, (unsigned long)text.length);
	return @{@"result": text};
}

#pragma mark - API

@implementation SXTools

+ (NSArray<NSDictionary *> *)definitions {
	SXPrefs *prefs = [SXPrefs shared];
	NSMutableArray<NSDictionary *> *defs = [NSMutableArray array];

	if (prefs.toolSystemInfo) {
		[defs addObject:@{
			@"name": @"system_info",
			@"description": @"Lấy thông tin trạng thái thiết bị: model, phiên bản iOS, pin, dung lượng trống, múi giờ.",
			@"parameters": @{@"type": @"object", @"properties": @{}, @"required": @[]},
		}];
	}
	if (prefs.toolClipboard) {
		[defs addObject:@{
			@"name": @"clipboard",
			@"description": @"Đọc hoặc ghi bảng nhớ tạm (copy/paste).",
			@"parameters": @{
				@"type": @"object",
				@"properties": @{
					@"action": @{@"type": @"string", @"enum": @[@"read", @"copy"], @"description": @"read = lấy nội dung, copy = sao chép text vào"},
					@"text": @{@"type": @"string", @"description": @"Nội dung cần sao chép (bắt buộc khi action=copy)"},
				},
				@"required": @[@"action"],
			},
		}];
	}
	if (prefs.toolFetchURL) {
		[defs addObject:@{
			@"name": @"fetch_url",
			@"description": @"Tải một trang web (https) và trả về phần văn bản thuần để đọc nội dung.",
			@"parameters": @{
				@"type": @"object",
				@"properties": @{@"url": @{@"type": @"string", @"description": @"URL https cần tải"}},
				@"required": @[@"url"],
			},
		}];
	}
	[defs addObject:@{
		@"name": @"reset_conversation",
		@"description": @"Xóa toàn bộ lịch sử hội thoại hiện tại. Dùng khi người dùng muốn bắt đầu lại.",
		@"parameters": @{@"type": @"object", @"properties": @{}, @"required": @[]},
	}];
	return defs;
}

+ (NSDictionary *)execute:(NSString *)name arguments:(NSDictionary *)arguments error:(NSError **)error {
	NSError *localError = nil;
	NSDictionary *result = nil;

	// Lưới an toàn cuối cùng: công cụ chạy trên luồng nền của SpringBoard và có
	// thể chạm UIKit/pasteboard/mạng. Một exception lọt ra ngoài sẽ giết cả
	// SpringBoard (người dùng thấy "Siri văng") — mọi lỗi phải thành NSError.
	@try {
	if ([name isEqualToString:@"system_info"]) {
		result = SXToolSystemInfo(&localError);
	} else if ([name isEqualToString:@"clipboard"]) {
		NSString *action = [arguments[@"action"] isKindOfClass:[NSString class]] ? arguments[@"action"] : @"read";
		if ([action isEqualToString:@"copy"]) {
			result = SXToolClipboardCopy(arguments, &localError);
		} else {
			result = SXToolClipboardRead(&localError);
		}
	} else if ([name isEqualToString:@"fetch_url"]) {
		result = SXToolFetchURL(arguments, &localError);
	} else {
		localError = SXToolError(404, [NSString stringWithFormat:@"Không có công cụ “%@”.", name]);
	}
	} @catch (NSException *exception) {
		SXLogErr(@"err", @"công cụ “%@” ném exception %@: %@ | %@",
				 name, exception.name, exception.reason,
				 [exception.callStackSymbols componentsJoinedByString:@" ; "]);
		localError = SXToolError(10, [NSString stringWithFormat:@"Công cụ “%@” gặp lỗi nội bộ.", name]);
	}

	if (localError) {
		SXLogWrn(@"tool", @"%@ lỗi: %@", name, localError.localizedDescription);
		if (error) *error = localError;
		return nil;
	}
	return result;
}

@end
