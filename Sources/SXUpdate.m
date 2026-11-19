#import "SXUpdate.h"
#import "SXHTTP.h"
#import "SXLog.h"

/// Repo phát hành — sửa ở đây nếu fork sang tên khác.
static NSString *const SXUpdateRepository = @"Hthancder/ArenaAIWorkspace-1";

@implementation SXUpdate

+ (NSString *)repository {
	return SXUpdateRepository;
}

/// Tách "v1.2.3", "1.2.3-build.135", "1.2" → @[@1, @2, @3]. Phần không phải số
/// bị cắt bỏ: người dùng chỉ so sánh ba con số đầu.
+ (NSArray<NSNumber *> *)componentsOfVersion:(NSString *)version {
	if (![version isKindOfClass:[NSString class]]) return @[];
	NSMutableString *clean = [NSMutableString string];
	NSString *trimmed = [version stringByTrimmingCharactersInSet:
						 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([trimmed hasPrefix:@"v"] || [trimmed hasPrefix:@"V"]) {
		trimmed = [trimmed substringFromIndex:1];
	}
	for (NSUInteger i = 0; i < trimmed.length; i++) {
		unichar c = [trimmed characterAtIndex:i];
		if ((c >= '0' && c <= '9') || c == '.') [clean appendFormat:@"%C", c];
		else break;   // "-build.135" hay "+meta" không tính
	}
	NSMutableArray<NSNumber *> *parts = [NSMutableArray array];
	for (NSString *piece in [clean componentsSeparatedByString:@"."]) {
		if (!piece.length) continue;
		[parts addObject:@(piece.integerValue)];
	}
	return parts;
}

+ (BOOL)isVersion:(NSString *)candidate newerThan:(NSString *)current {
	NSArray<NSNumber *> *a = [self componentsOfVersion:candidate];
	NSArray<NSNumber *> *b = [self componentsOfVersion:current];
	if (!a.count) return NO;
	for (NSUInteger i = 0; i < MAX(a.count, b.count); i++) {
		NSInteger left = i < a.count ? a[i].integerValue : 0;
		NSInteger right = i < b.count ? b[i].integerValue : 0;
		if (left > right) return YES;
		if (left < right) return NO;
	}
	return NO;
}

+ (NSDictionary *)checkWithTimeout:(NSTimeInterval)timeout error:(NSError **)error {
	NSString *url = [NSString stringWithFormat:@"https://api.github.com/repos/%@/releases/latest",
					 SXUpdateRepository];
	NSDictionary *headers = @{
		@"Accept": @"application/vnd.github+json",
		@"User-Agent": [SXHTTP userAgent],
	};
	SXHTTPResult *result = [SXHTTP getURL:url headers:headers
								 timeout:MAX(4.0, timeout) idleTimeout:MAX(4.0, timeout)
								  maxBytes:512 * 1024];
	if (result.error && result.status == 0) {
		SXLogWrn(@"update", @"kiểm tra cập nhật lỗi mạng: %@", result.error.localizedDescription);
		if (error) *error = result.error;
		return nil;
	}
	if (result.status == 404) {
		// Chưa có bản phát hành nào — không phải lỗi của người dùng.
		SXLogInf(@"update", @"repo chưa có release (404)");
		if (error) *error = [SXHTTP errorWithCode:404 message:@"Chưa có bản phát hành nào."];
		return nil;
	}
	if (result.status < 200 || result.status >= 300) {
		NSError *err = [SXHTTP errorWithStatus:result.status data:result.body];
		SXLogWrn(@"update", @"GitHub HTTP %ld: %@", (long)result.status, err.localizedDescription);
		if (error) *error = err;
		return nil;
	}
	id json = [NSJSONSerialization JSONObjectWithData:result.body options:0 error:NULL];
	if (![json isKindOfClass:[NSDictionary class]]) {
		if (error) *error = [SXHTTP errorWithCode:-3 message:@"Phản hồi GitHub không hợp lệ."];
		return nil;
	}
	NSString *tag = [json[@"tag_name"] isKindOfClass:[NSString class]] ? json[@"tag_name"] : nil;
	NSString *name = [json[@"name"] isKindOfClass:[NSString class]] ? json[@"name"] : tag;
	NSString *html = [json[@"html_url"] isKindOfClass:[NSString class]] ? json[@"html_url"] : nil;
	if (!tag.length) {
		if (error) *error = [SXHTTP errorWithCode:-3 message:@"Bản phát hành không có tag."];
		return nil;
	}
	// Tag do CI đặt: "sirix-1.2.0-build.140" — lấy phần số để so sánh.
	NSString *latest = tag;
	NSRange sirix = [tag rangeOfString:@"sirix-" options:NSCaseInsensitiveSearch];
	if (sirix.location != NSNotFound) latest = [tag substringFromIndex:NSMaxRange(sirix)];
	BOOL newer = [self isVersion:latest newerThan:SX_VERSION];
	SXLogInf(@"update", @"bản hiện tại %@ · mới nhất %@%@", SX_VERSION, latest,
			 newer ? @" (có bản mới)" : @" (đã là mới nhất)");
	return @{@"current": SX_VERSION,
			 @"latest": latest,
			 @"tag": tag,
			 @"name": name ?: latest,
			 @"newer": @(newer),
			 @"url": html ?: @""};
}

@end
