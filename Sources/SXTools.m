#import "SXTools.h"
#import "SXPrefs.h"
#import "SXLog.h"
#import <UIKit/UIKit.h>
#include <sys/utsname.h>

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

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	request.HTTPMethod = @"GET";
	request.timeoutInterval = 12;
	[request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) SiriX/1.0"
   forHTTPHeaderField:@"User-Agent"];

	dispatch_semaphore_t sem = dispatch_semaphore_create(0);
	__block NSData *body = nil;
	__block NSInteger status = 0;
	__block NSError *sessionError = nil;
	[[[NSURLSession sharedSession] dataTaskWithRequest:request
									completionHandler:^(NSData *data, NSURLResponse *response, NSError *err) {
		body = data;
		status = [(NSHTTPURLResponse *)response statusCode];
		sessionError = err;
		dispatch_semaphore_signal(sem);
	}] resume];

	if (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)))) {
		if (error) *error = SXToolError(4, @"Hết thời gian chờ khi tải trang.");
		return nil;
	}
	if (sessionError) {
		if (error) *error = SXToolError(5, [NSString stringWithFormat:@"Không tải được trang: %@", sessionError.localizedDescription]);
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
	SXLogDbg(@"tool", @"fetch_url %@ → %lu ký từ trích được", url.absoluteString, (unsigned long)text.length);
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

	if (localError) {
		SXLogWrn(@"tool", @"%@ lỗi: %@", name, localError.localizedDescription);
		if (error) *error = localError;
		return nil;
	}
	return result;
}

@end
