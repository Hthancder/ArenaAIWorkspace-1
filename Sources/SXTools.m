#import "SXTools.h"
#import "SXPrefs.h"
#import "SXLog.h"
#import <UIKit/UIKit.h>
#include <sys/utsname.h>
#import <objc/message.h>
#include <arpa/inet.h>

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
		@"Thiết bị: %@ (%@), iOS %@. "
		@"Pin: %@. Dung lượng: %.1f/%.1f GB còn trống. Ngôn ngữ: %@. "
		@"Thời gian hiện tại: %@.",
		device.model, [NSString stringWithUTF8String:info.machine] ?: @"?",
		device.systemVersion,
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
	SXLogDbg(@"llm", @"clipboard_copy (%lu ký tự)", (unsigned long)[(NSString *)text length]);
	return @{@"result": @"Đã sao chép vào bảng nhớ tạm."};
}

static NSDictionary *SXToolClipboardRead(NSError **error) {
	NSString *text = UIPasteboard.generalPasteboard.string;
	if (!text.length) return @{@"result": @"Bảng nhớ tạm trống."};
	if (text.length > 1000) text = SXShort(text, 1000);
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

static NSDictionary *SXToolFetchURL(NSDictionary *args, NSString *question, SXRequest *budget, NSError **error) {
	id raw = args[@"url"];
	if (![raw isKindOfClass:[NSString class]]) {
		if (error) *error = SXToolError(2, @"Thiếu tham số “url”.");
		return nil;
	}
	NSURL *url = SXHTTPSURL(raw);
	// Only fetch a public-looking, explicitly supplied URL; the model cannot
	// invent arbitrary destinations or follow redirects on the phone's network.
	NSString *host = url.host.lowercaseString;
	struct in_addr ipv4;
	struct in6_addr ipv6;
	BOOL valid = url && [host containsString:@"."] && ![host hasSuffix:@".local"] && ![host hasSuffix:@".internal"] &&
		inet_pton(AF_INET, host.UTF8String, &ipv4) != 1 && inet_pton(AF_INET6, host.UTF8String, &ipv6) != 1;
	NSDataDetector *links = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:NULL];
	BOOL explicit = NO;
	for (NSTextCheckingResult *item in [links matchesInString:question options:0 range:NSMakeRange(0, question.length)]) {
		if ([item.URL isEqual:url]) { explicit = YES; break; }
	}
	if (!valid || !explicit) { if (error) *error = SXToolError(3, @"Chỉ đọc URL HTTPS công khai được nêu trong câu hỏi."); return nil; }
	NSMutableURLRequest *get = [NSMutableURLRequest requestWithURL:url];
	get.timeoutInterval = 8;
	NSDictionary *response = SXHTTP(get, budget, 512 * 1024, error);
	if (!response) return nil;
	NSInteger status = [response[@"status"] integerValue];
	if (status < 200 || status >= 300) { if (error) *error = SXToolError(status, @"Trang web không trả nội dung hợp lệ."); return nil; }
	NSData *body = response[@"data"];

	NSString *text = SXStripHTML(body ?: [NSData data]);
	if (!text.length) {
		if (error) *error = SXToolError(6, @"Trang không có nội dung văn bản.");
		return nil;
	}
	SXLogDbg(@"llm", @"fetch_url: %lu ký tự", (unsigned long)text.length);
	return @{@"result": text};
}

#pragma mark - API

@implementation SXTools

+ (NSArray<NSDictionary *> *)definitionsForPrefs:(SXPrefs *)prefs question:(NSString *)question {
	if (prefs.incognito || prefs.localOnly) return @[];
	NSString *lower = question.lowercaseString;
	NSMutableArray<NSDictionary *> *defs = [NSMutableArray array];

	if (prefs.toolSystemInfo) {
		[defs addObject:@{
			@"name": @"system_info",
			@"description": @"Lấy thông tin trạng thái thiết bị: model, phiên bản iOS, pin, dung lượng trống, múi giờ.",
			@"parameters": @{@"type": @"object", @"properties": @{}, @"required": @[]},
		}];
	}
	if (prefs.toolClipboard && ([lower containsString:@"clipboard"] || [lower containsString:@"bảng nhớ tạm"] || [lower containsString:@"bộ nhớ tạm"])) {
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
	if (prefs.toolFetchURL && [lower containsString:@"https://"]) {
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
	if (prefs.toolCurrentApp && [NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) {
		[defs addObject:@{@"name": @"current_app", @"description": @"Tên và mã gói của ứng dụng trước Siri; không đọc màn hình.",
			@"parameters": @{@"type": @"object", @"properties": @{}, @"required": @[]}}];
	}
	return defs;
}

static id SXAppProperty(id object, NSString *name) {
	SEL selector = NSSelectorFromString(name);
	NSMethodSignature *sig = [object methodSignatureForSelector:selector];
	if (sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') return nil;
	return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}
static NSDictionary *SXToolCurrentApp(void) {
	@try {
		id app = SXAppProperty(UIApplication.sharedApplication, @"_accessibilityFrontMostApplication");
		id name = SXAppProperty(app, @"displayName"), identifier = SXAppProperty(app, @"bundleIdentifier");
		if (![identifier isKindOfClass:NSString.class] || ![identifier length] || [identifier isEqual:@"com.apple.springboard"]) return nil;
		return @{@"result": [NSString stringWithFormat:@"%@ (%@)", [name isKindOfClass:NSString.class] ? name : @"Ứng dụng", identifier]};
	} @catch (NSException *ignored) { (void)ignored; return nil; }
}

+ (NSDictionary *)execute:(NSString *)name arguments:(NSDictionary *)arguments question:(NSString *)question request:(SXRequest *)request error:(NSError **)error {
	SXPrefs *prefs = [[SXPrefs shared] snapshot];
	NSSet *allowed = [NSSet setWithArray:[[self definitionsForPrefs:prefs question:question] valueForKey:@"name"]];
	if (request.remaining <= 0 || ![allowed containsObject:name]) {
		if (error) *error = SXToolError(403, @"Công cụ đã tắt hoặc lượt này đã kết thúc."); return nil;
	}
	if ([name isEqual:@"system_info"]) return SXToolSystemInfo(error);
	if ([name isEqual:@"fetch_url"]) return SXToolFetchURL(arguments, question, request, error);
	if ([name isEqual:@"clipboard"]) {
		NSString *action = [arguments[@"action"] isKindOfClass:NSString.class] ? arguments[@"action"] : @"";
		if ([action isEqual:@"copy"]) return SXToolClipboardCopy(arguments, error);
		if ([action isEqual:@"read"]) return SXToolClipboardRead(error);
	}
	if ([name isEqual:@"current_app"]) {
		if (NSThread.isMainThread) return SXToolCurrentApp();
		dispatch_semaphore_t ready = dispatch_semaphore_create(0);
		__block NSDictionary *result = nil;
		dispatch_async(dispatch_get_main_queue(), ^{
			if (request.remaining > 0 && ![SXPrefs shared].incognito && [SXPrefs shared].toolCurrentApp) result = SXToolCurrentApp();
			dispatch_semaphore_signal(ready);
		});
		if (dispatch_semaphore_wait(ready, dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC)) == 0 && result) return result;
		if (error) *error = SXToolError(4, @"Không đọc được ứng dụng hiện tại."); return nil;
	}
	if (error) *error = SXToolError(404, @"Công cụ không hỗ trợ thao tác này.");
	return nil;
}
@end
