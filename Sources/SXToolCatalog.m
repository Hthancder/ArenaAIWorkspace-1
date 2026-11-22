#import "SXToolCatalog.h"
#import "SXToolkit.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXHTTP.h"
#import "SXNetPolicy.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include <sys/utsname.h>
#include <math.h>
#include <string.h>

#pragma mark - Tiện ích

static NSError *SXErr(NSInteger code, NSString *message) {
	return [NSError errorWithDomain:SXToolErrorDomain
							   code:code
						   userInfo:@{NSLocalizedDescriptionKey: message ?: @"Công cụ gặp lỗi."}];
}

static NSDictionary *SXRes(NSString *text) {
	return @{@"result": text ?: @""};
}

static NSString *SXTrimmed(id value) {
	if (![value isKindOfClass:[NSString class]]) return nil;
	return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *SXCut(NSString *text, NSUInteger limit) {
	if (text.length <= limit) return text;
	return [[text substringToIndex:limit] stringByAppendingString:@"…"];
}

static id SXSend(id object, SEL selector) {
	if (!object || ![object respondsToSelector:selector]) return nil;
	return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

#pragma mark - Bối cảnh thiết bị

static NSString *SXNetworkType(void) {
	SCNetworkReachabilityRef reference = SCNetworkReachabilityCreateWithName(NULL, "apple.com");
	if (!reference) return @"không rõ";
	SCNetworkReachabilityFlags flags = 0;
	BOOL ok = SCNetworkReachabilityGetFlags(reference, &flags);
	CFRelease(reference);
	if (!ok || !(flags & kSCNetworkReachabilityFlagsReachable)) return @"không có mạng";
	return (flags & kSCNetworkReachabilityFlagsIsWWAN) ? @"mạng di động" : @"Wi-Fi";
}

static NSString *SXUptimeText(NSTimeInterval seconds) {
	long long total = (long long)seconds;
	long long days = total / 86400;
	long long hours = (total % 86400) / 3600;
	long long minutes = (total % 3600) / 60;
	if (days > 0) return [NSString stringWithFormat:@"%lld ngày %lld giờ", days, hours];
	if (hours > 0) return [NSString stringWithFormat:@"%lld giờ %lld phút", hours, minutes];
	return [NSString stringWithFormat:@"%lld phút", minutes];
}

static NSDictionary *SXDeviceInfo(NSDictionary *arguments, NSError **error) {
	(void)arguments; (void)error;
	UIDevice *device = UIDevice.currentDevice;
	struct utsname machine;
	uname(&machine);

	device.batteryMonitoringEnabled = YES;
	float level = device.batteryLevel;
	NSString *battery = level < 0 ? @"không rõ" : [NSString stringWithFormat:@"%.0f%%", level * 100.0f];
	NSString *charging = @"";
	switch (device.batteryState) {
		case UIDeviceBatteryStateCharging: charging = @", đang sạc"; break;
		case UIDeviceBatteryStateFull: charging = @", đã đầy"; break;
		case UIDeviceBatteryStateUnplugged: charging = @", không sạc"; break;
		default: break;
	}

	NSDictionary *fs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:NULL];
	double freeGB = [fs[NSFileSystemFreeSize] doubleValue] / 1073741824.0;
	double totalGB = [fs[NSFileSystemSize] doubleValue] / 1073741824.0;

	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.locale = [NSLocale localeWithLocaleIdentifier:@"vi_VN"];
	formatter.dateFormat = @"HH:mm 'ngày' dd/MM/yyyy";

	NSString *text = [NSString stringWithFormat:
		@"Thiết bị: %@ (%@), iOS %@, tên “%@”.\n"
		@"Pin: %@%@.\n"
		@"Dung lượng: %.1f GB trống trên %.1f GB. RAM: %.1f GB.\n"
		@"Mạng: %@.\n"
		@"Ngôn ngữ: %@; múi giờ: %@.\n"
		@"Bây giờ: %@.\n"
		@"Máy đã bật liên tục: %@.",
		device.model ?: @"iPhone",
		[NSString stringWithUTF8String:machine.machine] ?: @"?",
		device.systemVersion ?: @"?",
		device.name ?: @"iPhone",
		battery, charging,
		freeGB, totalGB,
		NSProcessInfo.processInfo.physicalMemory / 1073741824.0,
		SXNetworkType(),
		NSLocale.currentLocale.localeIdentifier ?: @"?",
		NSTimeZone.localTimeZone.name ?: @"?",
		[formatter stringFromDate:NSDate.date],
		SXUptimeText(NSProcessInfo.processInfo.systemUptime)];
	return SXRes(text);
}

#pragma mark - Bảng nhớ tạm

static NSDictionary *SXClipboardRead(NSDictionary *arguments, NSError **error) {
	(void)arguments; (void)error;
	UIPasteboard *board = UIPasteboard.generalPasteboard;
	NSString *text = board.string;
	if (!text.length) {
		if (board.hasImages) return SXRes(@"Bảng nhớ tạm đang chứa ảnh, không có văn bản.");
		return SXRes(@"Bảng nhớ tạm trống.");
	}
	NSString *note = text.length > 2000 ? @"\n…(đã cắt bớt)" : @"";
	return SXRes([NSString stringWithFormat:@"%@%@", SXCut(text, 2000), note]);
}

static NSDictionary *SXClipboardWrite(NSDictionary *arguments, NSError **error) {
	NSString *text = arguments[@"text"];
	if (![text isKindOfClass:[NSString class]] || !text.length) {
		if (error) *error = SXErr(422, @"Thiếu nội dung “text” để chép.");
		return nil;
	}
	UIPasteboard.generalPasteboard.string = text;
	SXLogDbg(@"tool", @"clipboard_write %lu ký tự", (unsigned long)text.length);
	return SXRes([NSString stringWithFormat:@"Đã chép %lu ký tự vào bảng nhớ tạm.",
				  (unsigned long)text.length]);
}

static NSDictionary *SXClipboardClear(NSDictionary *arguments, NSError **error) {
	(void)arguments; (void)error;
	UIPasteboard.generalPasteboard.items = @[];
	return SXRes(@"Đã xoá bảng nhớ tạm.");
}

#pragma mark - Đọc web

/// Luật thật nằm ở SXNetPolicy.h (C thuần, có test): xét cả IPv4 viết tắt,
/// IPv6, ::ffff:, CGNAT… — những dạng mà so chuỗi + inet_pton(AF_INET) bỏ sót.
static BOOL SXHostIsPrivate(NSString *host) {
	return SXNetHostIsPrivate(host.UTF8String) ? YES : NO;
}

/// Bỏ script/style/tag, giải mã entity, gộp khoảng trắng.
static NSString *SXHTMLToText(NSData *data) {
	if (!data.length) return @"";
	NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (!html) html = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
	if (!html) html = [[NSString alloc] initWithData:data encoding:NSWindowsCP1252StringEncoding];
	if (!html) return @"";

	static NSRegularExpression *noise, *tags, *spaces;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		noise = [NSRegularExpression regularExpressionWithPattern:
				 @"<(script|style|noscript|svg|head)[\\s\\S]*?</\\1\\s*>|<!--[\\s\\S]*?-->"
														 options:NSRegularExpressionCaseInsensitive error:NULL];
		tags = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>" options:0 error:NULL];
		spaces = [NSRegularExpression regularExpressionWithPattern:@"[ \\t\\r\\f]+" options:0 error:NULL];
	});
	NSString *text = [noise stringByReplacingMatchesInString:html options:0
													   range:NSMakeRange(0, html.length) withTemplate:@" "];
	text = [tags stringByReplacingMatchesInString:text options:0
											range:NSMakeRange(0, text.length) withTemplate:@"\n"];
	NSArray<NSString *> *entities = @[@"&nbsp;", @"&amp;", @"&lt;", @"&gt;", @"&quot;", @"&#39;",
									  @"&#x27;", @"&apos;", @"&ndash;", @"&mdash;", @"&hellip;"];
	NSArray<NSString *> *replacers = @[@" ", @"&", @"<", @">", @"\"", @"'", @"'", @"'", @"–", @"—", @"…"];
	for (NSUInteger i = 0; i < entities.count; i++) {
		text = [text stringByReplacingOccurrencesOfString:entities[i] withString:replacers[i]];
	}
	text = [spaces stringByReplacingMatchesInString:text options:0
											  range:NSMakeRange(0, text.length) withTemplate:@" "];
	// Gộp dòng trống liên tiếp, bỏ dòng chỉ có khoảng trắng.
	NSMutableArray<NSString *> *lines = [NSMutableArray array];
	for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
		NSString *trimmed = [line stringByTrimmingCharactersInSet:
							 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (!trimmed.length) continue;
		[lines addObject:trimmed];
	}
	return [lines componentsJoinedByString:@"\n"];
}

static NSString *SXPageTitle(NSData *data) {
	NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (!html) return nil;
	static NSRegularExpression *title;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		title = [NSRegularExpression regularExpressionWithPattern:@"<title[^>]*>([\\s\\S]*?)</title>"
														  options:NSRegularExpressionCaseInsensitive error:NULL];
	});
	NSTextCheckingResult *match = [title firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
	if (!match || match.numberOfRanges < 2) return nil;
	NSString *value = [html substringWithRange:[match rangeAtIndex:1]];
	value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return value.length ? value : nil;
}

static NSDictionary *SXWebFetch(NSDictionary *arguments, NSError **error) {
	NSString *raw = SXTrimmed(arguments[@"url"]);
	if (!raw.length) {
		if (error) *error = SXErr(422, @"Thiếu tham số “url”.");
		return nil;
	}
	NSURL *url = [NSURL URLWithString:raw];
	NSString *scheme = url.scheme.lowercaseString;
	if (!url || !([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"])) {
		if (error) *error = SXErr(422, @"Chỉ tải được URL http/https. Ví dụ: https://example.com");
		return nil;
	}
	if (SXHostIsPrivate(url.host)) {
		NSString *hint = SXNetHostIsLoopback(url.host.UTF8String)
			? @"địa chỉ của chính máy này (loopback)"
			: @"một địa chỉ mạng nội bộ";
		if (error) *error = SXErr(403, [NSString stringWithFormat:
			@"Không đọc được %@ vì đó là %@. Chỉ tải được trang trên Internet công khai.",
			url.host ?: @"?", hint]);
		return nil;
	}

	// Đi theo tối đa 3 chuyển hướng, nhưng xét lại TỪNG đích: một trang công
	// khai hoàn toàn có thể chuyển vào 127.0.0.1/metadata nội bộ, hoặc hạ cấp
	// https→http. Bản trước ghi "không đi theo redirect" trong chú thích nhưng
	// URLSession vẫn đi theo — đó là lỗ hổng đọc mạng nội bộ qua trang trung gian.
	__block NSUInteger hops = 0;
	SXHTTPResult *response = [SXHTTP getURL:url.absoluteString
									headers:@{@"Accept": @"text/html,application/json,text/plain;q=0.9,*/*;q=0.5"}
									timeout:8.0
								idleTimeout:6.0
								   maxBytes:2 * 1024 * 1024
							 rejectRedirect:^BOOL(NSURL *target) {
		const char *scheme = target.scheme.UTF8String;
		const char *host = target.host.UTF8String;
		BOOL allowed = SXNetRedirectAllowed(url.scheme.UTF8String, scheme, host) && hops < 3;
		if (allowed) hops++;
		else SXLogWrn(@"tool", @"web_fetch: chặn chuyển hướng tới %@ (hạ cấp giao thức, host nội bộ hoặc quá 3 bước)",
					target.host ?: @"?");
		return !allowed;
	}];
	if (response.error) {
		if (error) *error = SXErr(response.error.code ?: 502, [NSString stringWithFormat:
			@"Không tải được trang: %@", response.error.localizedDescription]);
		return nil;
	}
	NSInteger status = response.status;
	if (status >= 300 && status < 400) {
		if (error) *error = SXErr(409, [NSString stringWithFormat:
			@"Trang chuyển hướng (HTTP %ld). Hãy gọi lại với URL đích nếu biết.", (long)status]);
		return nil;
	}
	if (status < 200 || status >= 300) {
		if (error) *error = SXErr(status ?: 502, [NSString stringWithFormat:
			@"Máy chủ trả về HTTP %ld.", (long)status]);
		return nil;
	}

	NSData *body = response.body ?: [NSData data];
	BOOL isJSON = [response.mimeType containsString:@"json"];
	NSString *text = nil;
	NSString *title = nil;
	if (isJSON) {
		id json = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
		NSData *pretty = body;
		if (json) {
			NSData *formatted = [NSJSONSerialization dataWithJSONObject:json
															   options:NSJSONWritingPrettyPrinted
																 error:NULL];
			if (formatted) pretty = formatted;
		}
		text = [[NSString alloc] initWithData:pretty encoding:NSUTF8StringEncoding];
	} else {
		text = SXHTMLToText(body);
		title = SXPageTitle(body);
	}
	if (!text.length) {
		if (error) *error = SXErr(204, @"Trang không có nội dung văn bản.");
		return nil;
	}

	NSString *header = [NSString stringWithFormat:@"Nguồn: %@%@\n\n", url.absoluteString,
						title.length ? [NSString stringWithFormat:@"\nTiêu đề: %@", title] : @""];
	NSString *result = [header stringByAppendingString:SXCut(text, 3600)];
	SXLogDbg(@"tool", @"web_fetch %@ → %lu ký tự", url.host ?: @"?", (unsigned long)text.length);
	return SXRes(result);
}

#pragma mark - Ứng dụng đang mở

/// Ứng dụng đang ở tiền cảnh. iOS 15 không có API công khai nên phải hỏi
/// SpringBoard qua một tiến trình khác (Siri/SpringBoard đều là system daemon).
/// Trả nil khi không xác định được — công cụ sẽ nói thật là “không rõ”.
static NSDictionary *SXFrontmostApp(void) {
	Class springBoard = NSClassFromString(@"SBApplicationController");
	if (!springBoard) return nil;
	id shared = ((id (*)(id, SEL))objc_msgSend)(springBoard, NSSelectorFromString(@"sharedInstanceIfExists"));
	if (!shared) {
		shared = ((id (*)(id, SEL))objc_msgSend)(springBoard, NSSelectorFromString(@"sharedInstance"));
	}
	if (!shared) return nil;
	id app = ((id (*)(id, SEL))objc_msgSend)(shared, NSSelectorFromString(@"applicationWithDisplayedApplication:"));
	if (![app isKindOfClass:NSObject.class]) {
		// Một số bản iOS đặt tên khác — thử lấy ứng dụng đang hiển thị qua
		// thuộc tính `frontmostApplication` nếu có.
		app = ((id (*)(id, SEL))objc_msgSend)(shared, NSSelectorFromString(@"frontmostApplication"));
	}
	if (![app isKindOfClass:NSObject.class]) return nil;

	NSString *identifier = nil;
	@try {
		id value = ((id (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"bundleIdentifier"));
		if ([value isKindOfClass:NSString.class]) identifier = value;
	} @catch (__unused NSException *exception) {}
	if (!identifier.length) return nil;

	NSString *name = nil;
	@try {
		id value = ((id (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"displayName"));
		if ([value isKindOfClass:NSString.class]) name = value;
	} @catch (__unused NSException *exception) {}
	return @{@"bundleIdentifier": identifier, @"name": name.length ? name : identifier};
}

static NSDictionary *SXCurrentApp(NSDictionary *arguments, NSError **error) {
	(void)arguments;
	NSDictionary *app = SXFrontmostApp();
	if (!app) {
		// Không đoán bừa: nói rõ giới hạn để model không bịa tên ứng dụng.
		return SXRes(@"Không xác định được ứng dụng đang mở trên phiên bản iOS này. "
					  @"Hãy hỏi người dùng nếu cần.");
	}
	NSString *name = app[@"name"];
	NSString *identifier = app[@"bundleIdentifier"];
	if ([identifier isEqualToString:@"com.apple.springboard"]) {
		return SXRes(@"Người dùng đang ở Màn hình chính (không có ứng dụng nào mở).");
	}
	SXLogDbg(@"tool", @"current_app → %@ (%@)", name, identifier);
	return SXRes([NSString stringWithFormat:@"Ứng dụng đang mở: %@ (%@).", name, identifier]);
}

#pragma mark - Ứng dụng & phím tắt

static id SXLSWorkspace(void) {
	Class cls = NSClassFromString(@"LSApplicationWorkspace");
	return SXSend(cls, NSSelectorFromString(@"defaultWorkspace"));
}

static BOOL SXLSResponds(id workspace, NSString *selectorName) {
	return workspace && [workspace respondsToSelector:NSSelectorFromString(selectorName)];
}

static BOOL SXOpenURL(NSURL *url) {
	id workspace = SXLSWorkspace();
	if (!url) return NO;
	if (SXLSResponds(workspace, @"openURL:withOptions:")) {
		SEL selector = NSSelectorFromString(@"openURL:withOptions:");
		return ((BOOL (*)(id, SEL, id, id))objc_msgSend)(workspace, selector, url, nil);
	}
	if (SXLSResponds(workspace, @"openURL:")) {
		return ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace, NSSelectorFromString(@"openURL:"), url);
	}
	return NO;
}

static NSArray *SXInstalledApps(void) {
	id workspace = SXLSWorkspace();
	id apps = SXSend(workspace, NSSelectorFromString(@"allInstalledApplications"));
	return [apps isKindOfClass:[NSArray class]] ? apps : @[];
}

static NSString *SXAppName(id proxy) {
	NSString *name = SXSend(proxy, NSSelectorFromString(@"localizedName"));
	if (![name isKindOfClass:[NSString class]] || !name.length) {
		name = SXSend(proxy, NSSelectorFromString(@"itemName"));
	}
	return [name isKindOfClass:[NSString class]] ? name : nil;
}

static NSString *SXAppBundleID(id proxy) {
	NSString *identifier = SXSend(proxy, NSSelectorFromString(@"bundleIdentifier"));
	return [identifier isKindOfClass:[NSString class]] ? identifier : nil;
}

static NSDictionary *SXListApps(NSDictionary *arguments, NSError **error) {
	(void)error;
	NSString *query = [SXTrimmed(arguments[@"query"]) lowercaseString];
	NSArray *apps = SXInstalledApps();
	if (!apps.count) {
		return SXRes(@"Không đọc được danh sách ứng dụng trên thiết bị này.");
	}

	NSMutableArray<NSString *> *matches = [NSMutableArray array];
	for (id proxy in apps) {
		NSString *identifier = SXAppBundleID(proxy);
		if (!identifier.length || [identifier hasPrefix:@"com.apple."]) continue;
		NSString *name = SXAppName(proxy) ?: identifier;
		if (query.length &&
			![name.lowercaseString containsString:query] &&
			![identifier.lowercaseString containsString:query]) continue;
		[matches addObject:[NSString stringWithFormat:@"%@ — %@", name, identifier]];
		if (matches.count >= 60) break;
	}
	if (!matches.count) {
		return SXRes(query.length ? [NSString stringWithFormat:@"Không có ứng dụng nào khớp “%@”.", query]
								  : @"Không có ứng dụng nào.");
	}
	[matches sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
	return SXRes([matches componentsJoinedByString:@"\n"]);
}

static NSDictionary *SXOpenApp(NSDictionary *arguments, NSError **error) {
	NSString *target = SXTrimmed(arguments[@"target"]);
	if (!target.length) {
		if (error) *error = SXErr(422, @"Thiếu “target”: bundle id hoặc tên ứng dụng.");
		return nil;
	}

	id workspace = SXLSWorkspace();
	if (!SXLSResponds(workspace, @"openApplicationWithBundleID:")) {
		if (error) *error = SXErr(501, @"Thiết bị không cho mở ứng dụng từ tiến trình này.");
		return nil;
	}

	NSString *bundleID = nil;
	NSString *displayName = nil;
	if ([target containsString:@"."] && ![target containsString:@" "]) {
		bundleID = target;
	} else {
		for (id proxy in SXInstalledApps()) {
			NSString *identifier = SXAppBundleID(proxy);
			if (!identifier.length || [identifier hasPrefix:@"com.apple."]) continue;
			NSString *name = SXAppName(proxy) ?: @"";
			if ([name caseInsensitiveCompare:target] == NSOrderedSame ||
				[name.lowercaseString containsString:target.lowercaseString]) {
				bundleID = identifier;
				displayName = name;
				break;
			}
		}
	}
	if (!bundleID.length) {
		if (error) *error = SXErr(404, [NSString stringWithFormat:
			@"Không tìm thấy ứng dụng “%@”. Gọi list_apps để lấy đúng bundle id.", target]);
		return nil;
	}

	BOOL ok = ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace,
		NSSelectorFromString(@"openApplicationWithBundleID:"), bundleID);
	if (!ok) {
		if (error) *error = SXErr(500, [NSString stringWithFormat:@"Không mở được %@.", bundleID]);
		return nil;
	}
	SXLogDbg(@"tool", @"open_app %@", bundleID);
	return SXRes([NSString stringWithFormat:@"Đã mở %@.", displayName ?: bundleID]);
}

static NSDictionary *SXOpenURLTool(NSDictionary *arguments, NSError **error) {
	NSString *raw = SXTrimmed(arguments[@"url"]);
	if (!raw.length) {
		if (error) *error = SXErr(422, @"Thiếu “url’.");
		return nil;
	}
	NSURL *url = [NSURL URLWithString:raw];
	if (!url || !url.scheme.length) {
		if (error) *error = SXErr(422, @"URL không hợp lệ.");
		return nil;
	}
	NSSet<NSString *> *allowed = [NSSet setWithArray:@[@"http", @"https", @"shortcuts", @"settings",
													   @"mailto", @"tel", @"sms", @"maps", @"music",
													   @"youtube", @"shazam", @"facetime"]];
	if (![allowed containsObject:url.scheme.lowercaseString]) {
		if (error) *error = SXErr(403, [NSString stringWithFormat:
			@"Không mở scheme “%@”. Chỉ hỗ trợ: http, https, shortcuts, settings, mailto, tel, sms, maps, music, youtube.",
			url.scheme]);
		return nil;
	}
	if (!SXOpenURL(url)) {
		if (error) *error = SXErr(500, @"Thiết bị không mở được liên kết này.");
		return nil;
	}
	return SXRes([NSString stringWithFormat:@"Đã mở %@.", raw]);
}

static NSDictionary *SXRunShortcut(NSDictionary *arguments, NSError **error) {
	NSString *name = SXTrimmed(arguments[@"name"]);
	if (!name.length) {
		if (error) *error = SXErr(422, @"Thiếu “name”: tên phím tắt trong ứng dụng Phím tắt.");
		return nil;
	}
	NSString *text = SXTrimmed(arguments[@"input"]);
	NSMutableString *urlString = [NSMutableString stringWithFormat:@"shortcuts://run-shortcut?name=%@",
								  [name stringByAddingPercentEncodingWithAllowedCharacters:
								   NSCharacterSet.URLQueryAllowedCharacterSet]];
	if (text.length) {
		NSString *encoded = [text stringByAddingPercentEncodingWithAllowedCharacters:
							 NSCharacterSet.URLQueryAllowedCharacterSet];
		[urlString appendFormat:@"&input=text&text=%@", encoded];
	}
	NSURL *url = [NSURL URLWithString:urlString];
	if (!SXOpenURL(url)) {
		if (error) *error = SXErr(500, @"Không mở được ứng dụng Phím tắt — có thể chưa cài.");
		return nil;
	}
	SXLogDbg(@"tool", @"run_shortcut %@", name);
	return SXRes([NSString stringWithFormat:@"Đã yêu cầu chạy phím tắt “%@”.", name]);
}

#pragma mark - Ghi nhớ

@interface SXMemoryStore : NSObject
+ (instancetype)shared;
- (NSArray<NSDictionary *> *)notes;
- (NSString *)addText:(NSString *)text tags:(NSString *)tags;
- (NSUInteger)removeMatching:(NSString *)query;
- (NSUInteger)removeAll;
@end

@implementation SXMemoryStore {
	NSMutableArray<NSDictionary *> *_notes;
	dispatch_queue_t _queue;
}

+ (instancetype)shared {
	static SXMemoryStore *store;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ store = [[SXMemoryStore alloc] init]; });
	return store;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_queue = dispatch_queue_create("com.sirix.tools.memory", DISPATCH_QUEUE_SERIAL);
		_notes = [NSMutableArray arrayWithContentsOfFile:[self filePath]] ?: [NSMutableArray array];
	}
	return self;
}

- (NSString *)filePath {
	return @"/var/mobile/Library/SiriX/memory.plist";
}

- (void)persist {
	NSString *directory = [[self filePath] stringByDeletingLastPathComponent];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory
							  withIntermediateDirectories:YES
											   attributes:nil
													error:NULL];
	[_notes writeToFile:[self filePath] atomically:YES];
}

- (NSArray<NSDictionary *> *)notes {
	__block NSArray *copy = nil;
	dispatch_sync(_queue, ^{ copy = [_notes copy]; });
	return copy;
}

- (NSString *)addText:(NSString *)text tags:(NSString *)tags {
	if (!text.length) return nil;
	__block NSString *identifier = nil;
	dispatch_sync(_queue, ^{
		identifier = [NSUUID.UUID.UUIDString substringToIndex:8].lowercaseString;
		NSMutableDictionary *note = [@{@"id": identifier, @"text": text, @"date": NSDate.date} mutableCopy];
		if (tags.length) note[@"tags"] = tags;
		[self->_notes addObject:note];
		if (self->_notes.count > 200) {
			[self->_notes removeObjectsInRange:NSMakeRange(0, self->_notes.count - 200)];
		}
		[self persist];
	});
	return identifier;
}

- (NSUInteger)removeMatching:(NSString *)query {
	__block NSUInteger removed = 0;
	dispatch_sync(_queue, ^{
		NSString *lower = query.lowercaseString;
		NSIndexSet *indexes = [self->_notes indexesOfObjectsPassingTest:^BOOL(NSDictionary *note,
																		   NSUInteger idx, BOOL *stop) {
			(void)idx; (void)stop;
			if (!lower.length) return YES;
			NSString *text = [note[@"text"] isKindOfClass:[NSString class]] ? note[@"text"] : @"";
			NSString *identifier = [note[@"id"] isKindOfClass:[NSString class]] ? note[@"id"] : @"";
			return [text.lowercaseString containsString:lower] || [identifier isEqualToString:lower];
		}];
		removed = indexes.count;
		if (removed) {
			[self->_notes removeObjectsAtIndexes:indexes];
			[self persist];
		}
	});
	return removed;
}

- (NSUInteger)removeAll {
	__block NSUInteger count = 0;
	dispatch_sync(_queue, ^{
		count = self->_notes.count;
		[self->_notes removeAllObjects];
		[self persist];
	});
	return count;
}

@end

static NSDictionary *SXRemember(NSDictionary *arguments, NSError **error) {
	NSString *text = SXTrimmed(arguments[@"text"]);
	if (!text.length) {
		if (error) *error = SXErr(422, @"Thiếu “text”: điều cần ghi nhớ.");
		return nil;
	}
	NSString *tags = SXTrimmed(arguments[@"tags"]);
	NSString *identifier = [[SXMemoryStore shared] addText:text tags:tags];
	if (!identifier.length) {
		if (error) *error = SXErr(500, @"Không lưu được vào bộ nhớ.");
		return nil;
	}
	return SXRes([NSString stringWithFormat:@"Đã ghi nhớ (id %@): %@", identifier, text]);
}

static NSDictionary *SXRecall(NSDictionary *arguments, NSError **error) {
	(void)error;
	NSString *query = [SXTrimmed(arguments[@"query"]) lowercaseString];
	NSArray<NSDictionary *> *notes = [[SXMemoryStore shared] notes];
	if (!notes.count) return SXRes(@"Chưa có ghi chú nào được lưu.");

	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.locale = [NSLocale localeWithLocaleIdentifier:@"vi_VN"];
	formatter.dateFormat = @"dd/MM/yyyy";

	NSMutableArray<NSString *> *lines = [NSMutableArray array];
	NSInteger shown = 0;
	for (NSDictionary *note in [notes reverseObjectEnumerator]) {
		NSString *text = [note[@"text"] isKindOfClass:[NSString class]] ? note[@"text"] : @"";
		if (query.length && ![text.lowercaseString containsString:query]) continue;
		NSString *identifier = [note[@"id"] isKindOfClass:[NSString class]] ? note[@"id"] : @"?";
		NSDate *date = [note[@"date"] isKindOfClass:[NSDate class]] ? note[@"date"] : nil;
		[lines addObject:[NSString stringWithFormat:@"[%@ · %@] %@", identifier,
						  date ? [formatter stringFromDate:date] : @"?", text]];
		if (++shown >= 20) break;
	}
	if (!lines.count) {
		return SXRes(query.length ? [NSString stringWithFormat:@"Không có ghi chú nào khớp “%@”.", query]
								  : @"Chưa có ghi chú nào.");
	}
	return SXRes([lines componentsJoinedByString:@"\n"]);
}

static NSDictionary *SXForget(NSDictionary *arguments, NSError **error) {
	NSString *query = SXTrimmed(arguments[@"query"]);
	BOOL all = [arguments[@"all"] boolValue];
	if (all) {
		NSUInteger count = [[SXMemoryStore shared] removeAll];
		return SXRes([NSString stringWithFormat:@"Đã xoá toàn bộ %lu ghi chú.", (unsigned long)count]);
	}
	if (!query.length) {
		if (error) *error = SXErr(422, @"Cần “query” (từ khoá hoặc id) hoặc “all”: true.");
		return nil;
	}
	NSUInteger removed = [[SXMemoryStore shared] removeMatching:query];
	if (!removed) {
		if (error) *error = SXErr(404, [NSString stringWithFormat:@"Không có ghi chú nào khớp “%@”.", query]);
		return nil;
	}
	return SXRes([NSString stringWithFormat:@"Đã xoá %lu ghi chú khớp “%@”.", (unsigned long)removed, query]);
}

#pragma mark - Máy tính (parser đệ quy, không eval)

typedef struct {
	const char *text;
	size_t length;
	size_t position;
	BOOL failed;
} SXMathParser;

static void SXMathSkipSpaces(SXMathParser *parser) {
	while (parser->position < parser->length && isspace((unsigned char)parser->text[parser->position]))
		parser->position++;
}

static BOOL SXMathConsume(SXMathParser *parser, char expected) {
	SXMathSkipSpaces(parser);
	if (parser->position < parser->length && parser->text[parser->position] == expected) {
		parser->position++;
		return YES;
	}
	return NO;
}

static double SXMathExpression(SXMathParser *parser);

static double SXMathPrimary(SXMathParser *parser) {
	SXMathSkipSpaces(parser);
	if (parser->failed || parser->position >= parser->length) {
		parser->failed = YES;
		return 0;
	}
	char current = parser->text[parser->position];

	if (current == '(') {
		parser->position++;
		double value = SXMathExpression(parser);
		if (!SXMathConsume(parser, ')')) parser->failed = YES;
		return value;
	}

	if (isalpha((unsigned char)current)) {
		size_t start = parser->position;
		while (parser->position < parser->length &&
			   (isalnum((unsigned char)parser->text[parser->position]) || parser->text[parser->position] == '_'))
			parser->position++;
		size_t length = parser->position - start;
		char name[16] = {0};
		if (length >= sizeof(name)) {
			parser->failed = YES;
			return 0;
		}
		memcpy(name, parser->text + start, length);

		if (!strcmp(name, "pi")) return M_PI;
		if (!strcmp(name, "e")) return M_E;

		double argument = 0;
		BOOL hasArgument = NO;
		if (SXMathConsume(parser, '(')) {
			argument = SXMathExpression(parser);
			hasArgument = YES;
			double second = 0;
			BOOL hasSecond = NO;
			if (SXMathConsume(parser, ',')) {
				second = SXMathExpression(parser);
				hasSecond = YES;
			}
			if (!SXMathConsume(parser, ')')) parser->failed = YES;
			if (hasSecond && !strcmp(name, "min")) return fmin(argument, second);
			if (hasSecond && !strcmp(name, "max")) return fmax(argument, second);
		}
		if (!hasArgument) {
			parser->failed = YES;
			return 0;
		}
		if (!strcmp(name, "sqrt")) return sqrt(argument);
		if (!strcmp(name, "abs")) return fabs(argument);
		if (!strcmp(name, "round")) return round(argument);
		if (!strcmp(name, "floor")) return floor(argument);
		if (!strcmp(name, "ceil")) return ceil(argument);
		if (!strcmp(name, "min")) return argument;
		if (!strcmp(name, "max")) return argument;
		if (!strcmp(name, "log")) return log(argument);
		parser->failed = YES;
		return 0;
	}

	// Số: dùng strtod trên phần còn lại (chuỗi đã NUL-terminated).
	char *end = NULL;
	double value = strtod(parser->text + parser->position, &end);
	if (end == parser->text + parser->position) {
		parser->failed = YES;
		return 0;
	}
	parser->position = (size_t)(end - parser->text);
	return value;
}

static double SXMathUnary(SXMathParser *parser) {
	SXMathSkipSpaces(parser);
	if (parser->position < parser->length) {
		char current = parser->text[parser->position];
		if (current == '-') { parser->position++; return -SXMathUnary(parser); }
		if (current == '+') { parser->position++; return SXMathUnary(parser); }
	}
	return SXMathPrimary(parser);
}

static double SXMathPower(SXMathParser *parser) {
	double base = SXMathUnary(parser);
	SXMathSkipSpaces(parser);
	if (parser->position < parser->length && parser->text[parser->position] == '^') {
		parser->position++;
		double exponent = SXMathPower(parser); // kết hợp phải
		return pow(base, exponent);
	}
	return base;
}

static double SXMathTerm(SXMathParser *parser) {
	double value = SXMathPower(parser);
	while (!parser->failed) {
		SXMathSkipSpaces(parser);
		if (parser->position >= parser->length) break;
		char op = parser->text[parser->position];
		if (op != '*' && op != '/' && op != '%') break;
		parser->position++;
		double rhs = SXMathPower(parser);
		if (op == '*') value *= rhs;
		else if (op == '/') {
			if (rhs == 0) { parser->failed = YES; return 0; }
			value /= rhs;
		} else {
			if (rhs == 0) { parser->failed = YES; return 0; }
			value = fmod(value, rhs);
		}
	}
	return value;
}

static double SXMathExpression(SXMathParser *parser) {
	double value = SXMathTerm(parser);
	while (!parser->failed) {
		SXMathSkipSpaces(parser);
		if (parser->position >= parser->length) break;
		char op = parser->text[parser->position];
		if (op != '+' && op != '-') break;
		parser->position++;
		double rhs = SXMathTerm(parser);
		value = (op == '+') ? value + rhs : value - rhs;
	}
	return value;
}

static NSString *SXFormatNumber(double value) {
	if (!isfinite(value)) return @"không xác định";
	double rounded = round(value);
	if (fabs(value - rounded) < 1e-9 && fabs(value) < 1e15) {
		return [NSString stringWithFormat:@"%lld", (long long)rounded];
	}
	NSString *text = [NSString stringWithFormat:@"%.10g", value];
	return text;
}

static NSDictionary *SXCalculate(NSDictionary *arguments, NSError **error) {
	NSString *expression = SXTrimmed(arguments[@"expression"]);
	if (!expression.length) {
		if (error) *error = SXErr(422, @"Thiếu “expression”, ví dụ: (1250*1.1)+sqrt(16)");
		return nil;
	}
	if (expression.length > 200) {
		if (error) *error = SXErr(413, @"Biểu thức quá dài (tối đa 200 ký tự).");
		return nil;
	}
	SXMathParser parser = {0};
	parser.text = expression.UTF8String;
	parser.length = strlen(parser.text);
	double value = SXMathExpression(&parser);
	SXMathSkipSpaces(&parser);
	if (parser.failed || parser.position != parser.length || !isfinite(value)) {
		if (error) *error = SXErr(422, @"Biểu thức không hợp lệ. Dùng số, + - * / % ^, ngoặc, "
										@"sqrt/abs/round/floor/ceil/min/max/log, pi, e.");
		return nil;
	}
	return SXRes([NSString stringWithFormat:@"%@ = %@", expression, SXFormatNumber(value)]);
}

#pragma mark - Đăng ký

static NSDictionary *SXObjectSchema(void) {
	return @{@"type": @"object", @"properties": @{}, @"required": @[]};
}

static NSDictionary *SXSchema(NSDictionary *properties, NSArray<NSString *> *required) {
	return @{@"type": @"object", @"properties": properties, @"required": required ?: @[]};
}

void SXInstallBuiltinTools(void) {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		SXTool *device = [SXTool toolWithName:@"device_info"
										title:@"Thông tin thiết bị"
									  summary:@"Model, iOS, pin, dung lượng, mạng, giờ, thời gian đã bật."
									   prompt:@"Lấy trạng thái thật của máy (pin, dung lượng, phiên bản iOS, mạng, giờ, uptime). Dùng khi người dùng hỏi về máy hoặc cần mốc thời gian hiện tại."
									 category:SXToolCategoryDevice
								   parameters:SXObjectSchema()
									  handler:^NSDictionary *(NSDictionary *arguments, NSError **error) {
			return SXDeviceInfo(arguments, error);
		}];
		device.timeout = 3.0;
		device.requiresMainThread = NO;
		device.liveData = YES;   // giờ/pin phải mới mỗi lần gọi trong cùng lượt
		[SXToolkit registerTool:device];

		SXTool *read = [SXTool toolWithName:@"clipboard_read"
									  title:@"Đọc bảng nhớ tạm"
									summary:@"Lấy văn bản đang có trong bảng nhớ tạm."
									 prompt:@"Đọc nội dung người dùng vừa sao chép (bảng nhớ tạm) khi họ nói “cái tôi vừa copy”, “đoạn vừa chép”."
								   category:SXToolCategoryClipboard
								 parameters:SXObjectSchema()
									handler:^NSDictionary *(NSDictionary *arguments, NSError **error) {
			return SXClipboardRead(arguments, error);
		}];
		read.timeout = 3.0;
		read.requiresMainThread = YES;
		[SXToolkit registerTool:read];

		SXTool *write = [SXTool toolWithName:@"clipboard_write"
									   title:@"Chép vào bảng nhớ tạm"
									 summary:@"Đặt một đoạn văn bản vào bảng nhớ tạm."
									  prompt:@"Sao chép văn bản người dùng muốn dùng lại (mã, địa chỉ, câu trả lời) vào bảng nhớ tạm."
									category:SXToolCategoryClipboard
								  parameters:SXSchema(@{@"text": @{@"type": @"string",
																 @"description": @"Nội dung cần chép"}},
													   @[@"text"])
									 handler:^NSDictionary *(NSDictionary *arguments, NSError **error) {
			return SXClipboardWrite(arguments, error);
		}];
		write.timeout = 3.0;
		write.requiresMainThread = YES;
		write.sideEffect = YES;
		[SXToolkit registerTool:write];

		SXTool *clear = [SXTool toolWithName:@"clipboard_clear"
									   title:@"Xoá bảng nhớ tạm"
									 summary:@"Làm trống bảng nhớ tạm."
									  prompt:@"Xoá bảng nhớ tạm khi người dùng yêu cầu dọn dữ liệu đã sao chép."
									category:SXToolCategoryClipboard
								  parameters:SXObjectSchema()
									 handler:^NSDictionary *(NSDictionary *arguments, NSError **error) {
			return SXClipboardClear(arguments, error);
		}];
		clear.timeout = 3.0;
		clear.requiresMainThread = YES;
		clear.sideEffect = YES;
		[SXToolkit registerTool:clear];

		SXTool *web = [SXTool toolWithName:@"web_fetch"
									 title:@"Đọc trang web"
								   summary:@"Tải một URL http/https và trả về phần văn bản đọc được."
									prompt:@"Đọc nội dung một trang web cụ thể (bài viết, tài liệu, API JSON) khi người dùng đưa URL hoặc khi cần dữ liệu mới nhất từ một trang. Không dùng cho tìm kiếm."
								  category:SXToolCategoryWeb
								parameters:SXSchema(@{@"url": @{@"type": @"string",
															 @"description": @"URL đầy đủ, bắt đầu bằng https://"}},
													 @[@"url"])
								   handler:^NSDictionary *(NSDictionary *arguments, NSError **error) {
			return SXWebFetch(arguments, error);
		}];
		web.timeout = 10.0;
		[SXToolkit registerTool:web];

		SXTool *apps = [SXTool toolWithName:@"list_apps"
									  title:@"Liệt kê ứng dụng"
									summary:@"Danh sách ứng dụng đã cài kèm bundle id."
									 prompt:@"Liệt kê ứng dụng đã cài để tìm đúng tên hoặc bundle id trước khi gọi open_app. Có thể lọc bằng “query”."
								   category:SXToolCategorySystem
								 parameters:SXSchema(@{@"query": @{@"type": @"string",
																 @"description": @"Từ khoá lọc (tuỳ chọn)"}}, @[])
									handler:^NSDictionary *(NSDictionary *arguments, NSError **error) {
			return SXListApps(arguments, error);
		}];
		apps.timeout = 4.0;
		[SXToolkit registerTool:apps];

		SXTool *currentApp = [SXTool toolWithName:@"current_app"
										  title:@"Ứng dụng đang mở"
										summary:@"Cho biết người dùng đang ở ứng dụng nào."
										 prompt:@"Cho biết ứng dụng đang hiển thị trước mặt người dùng. Gọi khi câu trả lời phụ thuộc vào ngữ cảnh màn hình (“cái này”, “ở đây”, “trong app này”). Nếu không xác định được, hỏi lại thay vì đoán."
									   category:SXToolCategorySystem
									 parameters:SXObjectSchema()
										handler:^NSDictionary *(NSDictionary *arguments, NSError **error) {
			return SXCurrentApp(arguments, error);
		}];
		currentApp.timeout = 3.0;
		currentApp.requiresMainThread = YES;
		currentApp.liveData = YES;   // người dùng có thể đã chuyển app trong lượt
		[SXToolkit registerTool:currentApp];

		SXTool *openApp = [SXTool toolWithName:@"open_app"
										 title:@"Mở ứng dụng"
									   summary:@"Mở ứng dụng theo tên hoặc bundle id."
										prompt:@"Mở một ứng dụng trên máy. Truyền bundle id (ví dụ com.apple.Maps) hoặc tên ứng dụng. Nếu không chắc tên, gọi list_apps trước."
									  category:SXToolCategorySystem
									parameters:SXSchema(@{@"target": @{@"type": @"string",
																	 @"description": @"Bundle id hoặc tên ứng dụng"}},
														 @[@"target"])
									   handler:^NSDictionary *(NSDictionary *arguments, NSError **error) {
			return SXOpenApp(arguments, error);
		}];
		openApp.timeout = 5.0;
		openApp.requiresMainThread = YES;
		openApp.sideEffect = YES;
		[SXToolkit registerTool:openApp];

		SXTool *openURL = [SXTool toolWithName:@"open_url"
										 title:@"Mở liên kết"
									   summary:@"Mở URL bằng ứng dụng phù hợp (https, maps, tel, sms…)."
										prompt:@"Mở một liên kết hoặc scheme (https, maps, tel, sms, mailto, music, youtube). Dùng khi người dùng muốn đi tới một địa chỉ cụ thể."
									  category:SXToolCategorySystem
									parameters:SXSchema(@{@"url": @{@"type": @"string",
																 @"description": @"URL đầy đủ có scheme"}},
													 @[@"url"])
									   handler:^NSDictionary *(NSDictionary *arguments, NSError **error) {
			return SXOpenURLTool(arguments, error);
		}];
		openURL.timeout = 5.0;
		openURL.requiresMainThread = YES;
		openURL.sideEffect = YES;
		[SXToolkit registerTool:openURL];

		SXTool *shortcut = [SXTool toolWithName:@"run_shortcut"
										  title:@"Chạy phím tắt"
										summary:@"Chạy một phím tắt trong ứng dụng Phím tắt, kèm dữ liệu đầu vào."
										 prompt:@"Chạy phím tắt có sẵn trên máy theo tên. Dùng khi người dùng đặt tên phím tắt hoặc khi thao tác cần tới phím tắt của họ."
									   category:SXToolCategorySystem
									 parameters:SXSchema(@{@"name": @{@"type": @"string",
																	  @"description": @"Tên phím tắt"},
															  @"input": @{@"type": @"string",
																		 @"description": @"Văn bản đầu vào (tuỳ chọn)"}},
														 @[@"name"])
										handler:^NSDictionary *(NSDictionary *arguments, NSError **error) {
			return SXRunShortcut(arguments, error);
		}];
		shortcut.timeout = 5.0;
		shortcut.requiresMainThread = YES;
		shortcut.sideEffect = YES;
		[SXToolkit registerTool:shortcut];

		SXTool *remember = [SXTool toolWithName:@"remember"
										  title:@"Ghi nhớ"
										summary:@"Lưu một ghi chú lâu dài (sở thích, dữ kiện về người dùng)."
										 prompt:@"Lưu điều người dùng muốn bạn nhớ về lâu dài (tên, sở thích, thông tin lặp lại). Chỉ lưu khi được yêu cầu hoặc khi thật hữu ích."
									   category:SXToolCategoryMemory
									 parameters:SXSchema(@{@"text": @{@"type": @"string",
																	  @"description": @"Nội dung cần nhớ"},
															  @"tags": @{@"type": @"string",
																		 @"description": @"Nhãn phân loại (tuỳ chọn)"}},
														 @[@"text"])
										handler:^NSDictionary *(NSDictionary *arguments, NSError **error) {
			return SXRemember(arguments, error);
		}];
		remember.timeout = 4.0;
		remember.sideEffect = YES;
		[SXToolkit registerTool:remember];

		SXTool *recall = [SXTool toolWithName:@"recall"
										title:@"Nhớ lại"
									  summary:@"Đọc các ghi chú đã lưu (lọc theo từ khoá)."
									   prompt:@"Đọc lại những gì đã ghi nhớ trước đây. Gọi khi câu trả lời phụ thuộc vào thông tin người dùng đã dặn bạn nhớ."
									 category:SXToolCategoryMemory
								   parameters:SXSchema(@{@"query": @{@"type": @"string",
																  @"description": @"Từ khoá lọc (tuỳ chọn)"}}, @[])
									  handler:^NSDictionary *(NSDictionary *arguments, NSError **error) {
			return SXRecall(arguments, error);
		}];
		recall.timeout = 4.0;
		[SXToolkit registerTool:recall];

		SXTool *forget = [SXTool toolWithName:@"forget"
										title:@"Quên ghi chú"
									  summary:@"Xoá ghi chú theo từ khoá/id, hoặc xoá tất cả."
									   prompt:@"Xoá ghi chú đã lưu khi người dùng yêu cầu quên đi, hoặc khi thông tin đã sai."
									 category:SXToolCategoryMemory
								   parameters:SXSchema(@{@"query": @{@"type": @"string",
																  @"description": @"Từ khoá hoặc id ghi chú"},
														  @"all": @{@"type": @"boolean",
																	 @"description": @"true để xoá tất cả"}},
													   @[])
									  handler:^NSDictionary *(NSDictionary *arguments, NSError **error) {
			return SXForget(arguments, error);
		}];
		forget.timeout = 4.0;
		forget.sideEffect = YES;
		[SXToolkit registerTool:forget];

		SXTool *math = [SXTool toolWithName:@"calculate"
									  title:@"Tính toán"
									summary:@"Tính biểu thức số học chính xác (có sqrt, ^, min, max…)."
									 prompt:@"Tính toán chính xác thay vì nhẩm trong đầu: số học, phần trăm, lãi, đổi đơn vị đơn giản. Ví dụ: (1250*1.1)+sqrt(16)."
								   category:SXToolCategoryMath
								 parameters:SXSchema(@{@"expression": @{@"type": @"string",
																	   @"description": @"Biểu thức, ví dụ (1250*1.1)/3"}},
													 @[@"expression"])
									handler:^NSDictionary *(NSDictionary *arguments, NSError **error) {
			return SXCalculate(arguments, error);
		}];
		math.timeout = 2.0;
		[SXToolkit registerTool:math];
	});
}
