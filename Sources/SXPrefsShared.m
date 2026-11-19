// Phần "dùng chung" của SXPrefs: không phụ thuộc CFPreferences hay UIKit, chạy
// được trên mọi nền tảng. Tách ra để bản test (Linux/macOS) và bản tweak dùng
// đúng một nguồn — trước đây mỗi bản test tự viết lại nên hành vi lệch nhau.
#import "SXPrefs.h"
#import "SXHeaders.h"
#import "SXLog.h"
#if defined(__APPLE__) && __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
#endif

/// Phần này đọc thẳng các ivar mà `-reload` của SXPrefs.m nạp sẵn — đó là lý do
/// nó nằm chung @implementation với bản thật. Với bản test, các selector dưới
/// đây được khai báo trong lớp test (cùng ivar) nên vẫn ghép được.
@interface SXPrefs (Runtime)
@property (nonatomic, readonly) SXProvider provider;
- (NSArray<NSDictionary *> *)openaiHeaders;
- (NSArray<NSDictionary *> *)geminiHeaders;
- (NSArray<NSDictionary *> *)headersForProvider:(SXProvider)provider;
@end

// Các selector dùng chung đặt trong một category: bản đầy đủ (SXPrefs.m) kế
// thừa chúng, còn bản test có thể ghép đúng category này với lớp giả của mình.
NSString *SXProviderDisplayName(SXProvider provider) {
	return provider == SXProviderGemini ? @"Gemini" : @"OpenAI";
}

NSArray<NSString *> *SXPreferenceKeys(void) {
	static NSArray<NSString *> *keys;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		keys = @[@"enabled", @"mode", @"triggerMode", @"provider",
				 @"openaiKey", @"openaiBase", @"openaiModel",
				 @"geminiKey", @"geminiModel",
				 @"temperature", @"contextTurns", @"timeout", @"replyDeadline", @"timeoutAction",
				 @"streaming", @"markdown", @"hideWebCards", @"showOriginal", @"speakErrors",
				 @"customPrompt", @"incognito",
				 @"maxToolRounds", @"toolsDisabled",
				 @"openaiHeaders", @"geminiHeaders",
				 @"verbose"];
	});
	return keys;
}

NSArray<NSDictionary *> *SXModelPresets(SXProvider provider) {
	if (provider == SXProviderGemini) {
		return @[
			@{@"model": @"gemini-2.0-flash", @"title": @"Gemini 2.0 Flash", @"hint": @"Nhanh, miễn phí hạn mức rộng — mặc định"},
			@{@"model": @"gemini-2.0-flash-lite", @"title": @"Gemini 2.0 Flash Lite", @"hint": @"Nhanh nhất, câu trả lời ngắn hơn"},
			@{@"model": @"gemini-1.5-flash", @"title": @"Gemini 1.5 Flash", @"hint": @"Ổn định, phù hợp câu hỏi dài"},
			@{@"model": @"gemini-1.5-pro", @"title": @"Gemini 1.5 Pro", @"hint": @"Chất lượng cao hơn, chậm hơn"},
		];
	}
	return @[
		@{@"model": @"gpt-4o-mini", @"title": @"GPT-4o mini", @"hint": @"Nhanh, rẻ — mặc định"},
		@{@"model": @"gpt-4o", @"title": @"GPT-4o", @"hint": @"Chất lượng cao, độ trễ trung bình"},
		@{@"model": @"gpt-4.1-mini", @"title": @"GPT-4.1 mini", @"hint": @"Cân bằng tốc độ và chất lượng"},
		@{@"model": @"o4-mini", @"title": @"o4-mini (reasoning)", @"hint": @"Model suy luận — thường chậm hơn 5 giây"},
	];
}

NSString *SXDefaultSystemPrompt(void) {
	return @"Bạn là SiriX, trợ lý AI tích hợp sẵn trong Siri trên iPhone. "
		   @"Trả lời chính xác, tự nhiên, ngắn gọn (thường 1–3 câu, trừ khi người dùng hỏi điều cần giải thích kỹ). "
		   @"Luôn trả lời bằng ngôn ngữ mà người dùng đã đặt câu hỏi. "
		   @"Ưu tiên văn bản thuần (phần lớn câu trả lời chỉ cần vậy); khi thật sự cần nhấn mạnh hoặc liệt kê, "
		   @"duy nhất dùng **đậm**, danh sách gạch đầu dòng ngắn, `mã code` hoặc khối code gọn — "
		   @"SiriX tự trình bày đẹp và vẫn phát giọng nói trôi chảy. Không emoji. "
		   @"Nếu người dùng yêu cầu thao tác trên máy (mở ứng dụng, đặt báo thức, gọi điện, nhắn tin…), "
		   @"hệ thống tự thực hiện — hãy xác nhận ngắn gọn, ví dụ: “Đã đặt báo thức 7 giờ.” "
		   @"trong ngôn ngữ của người dùng, đừng nói mình không thể.";
}

@implementation SXPrefs (Shared)

#pragma mark - Công cụ & header tuỳ chỉnh

#pragma mark - Khoá & công cụ

/// Tên công cụ theo ba công tắc của bản 1.1.x (để người dùng nâng cấp không bị mất lựa chọn).
static NSArray<NSString *> *SXLegacyToolNames(NSString *legacyKey) {
	if ([legacyKey isEqualToString:@"toolSystemInfo"]) return @[@"device_info"];
	if ([legacyKey isEqualToString:@"toolClipboard"]) {
		return @[@"clipboard_read", @"clipboard_write", @"clipboard_clear"];
	}
	if ([legacyKey isEqualToString:@"toolFetchURL"]) return @[@"web_fetch"];
	return @[];
}

- (NSSet<NSString *> *)loadDisabledToolsForReload {
	id stored = [self valueFor:@"toolsDisabled"];
	if ([stored isKindOfClass:[NSArray class]]) {
		NSMutableSet *set = [NSMutableSet set];
		for (id name in (NSArray *)stored) {
			if ([name isKindOfClass:[NSString class]] && [(NSString *)name length]) [set addObject:name];
		}
		return [set copy];
	}
	// Chưa có key mới: chuyển ba công tắc cũ sang danh sách tắt (nếu người dùng đã tắt).
	NSMutableSet *set = [NSMutableSet set];
	for (NSString *legacy in @[@"toolSystemInfo", @"toolClipboard", @"toolFetchURL"]) {
		id value = [self valueFor:legacy];
		if (!value) continue;
		BOOL enabled = [value isKindOfClass:[NSNumber class]] ? [value boolValue] : YES;
		if (!enabled) [set addObjectsFromArray:SXLegacyToolNames(legacy)];
	}
	return [set copy];
}

- (BOOL)isToolEnabled:(NSString *)name {
	if (!name.length) return NO;
	return ![self.disabledTools containsObject:name];
}

+ (void)setToolNamed:(NSString *)name enabled:(BOOL)enabled {
	if (!name.length) return;
	NSSet<NSString *> *current = [SXPrefs shared].disabledTools ?: [NSSet set];
	NSMutableSet<NSString *> *disabled = [current mutableCopy];
	if (enabled) [disabled removeObject:name];
	else [disabled addObject:name];
	[self setDisabledTools:disabled];
	SXLogInf(@"pref", @"công cụ %@: %@", name, enabled ? @"bật" : @"tắt");
}

+ (void)setDisabledTools:(NSSet<NSString *> *)names {
	NSArray *sorted = [[names allObjects] sortedArrayUsingSelector:@selector(compare:)];
	[SXPrefs setValue:(sorted.count ? sorted : @[]) forKey:@"toolsDisabled"];
	[[SXPrefs shared] reload];
}

#pragma mark - Header tuỳ chỉnh

/// Header đang cấu hình. Đặt trong phần dùng chung (không phải lớp chính) để
/// cả tweak lẫn test đều dùng đúng một cách.
- (NSArray<NSDictionary *> *)headersForProvider:(SXProvider)provider {
	NSString *key = provider == SXProviderGemini ? @"geminiHeaders" : @"openaiHeaders";
	id stored = [self valueFor:key];
	return [stored isKindOfClass:[NSArray class]] ? stored : @[];
}

+ (void)setHeaders:(NSArray<NSDictionary *> *)headers forProvider:(SXProvider)provider {
	NSArray *clean = SXHeadersNormalized(headers);
	NSString *key = provider == SXProviderGemini ? @"geminiHeaders" : @"openaiHeaders";
	[self setValue:clean forKey:key];
	[[SXPrefs shared] reload];
	SXLogInf(@"pref", @"header %@: %lu mục (%lu đang gửi)", SXProviderDisplayName(provider),
			 (unsigned long)clean.count,
			 (unsigned long)SXHeadersApplied(clean).count);
}

#pragma mark - Truy vấn theo provider hiện tại

- (NSString *)activeAPIKey {
	// Cắt khoảng trắng/dấu xuống dòng thừa — dán khóa từ web thường dính "\n" ở đuôi.
	SXProvider provider = self.provider;
	NSString *key = provider == SXProviderGemini ? [self geminiKey] : [self openaiKey];
	return [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)activeModel {
	SXProvider provider = self.provider;
	NSString *model = provider == SXProviderGemini ? [self geminiModel] : [self openaiModel];
	model = [model stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!model.length) {
		return provider == SXProviderGemini ? @"gemini-2.0-flash" : @"gpt-4o-mini";
	}
	return model;
}

- (NSString *)activeBaseURL {
	NSString *base = [SXPrefs normalizedBaseURL:[self openaiBase]];
	return base.length ? base : @"https://api.openai.com/v1";
}

- (NSString *)systemPrompt {
	NSString *custom = self.customPrompt;
	NSString *base = custom.length ? custom : SXDefaultSystemPrompt();
	if ([base containsString:@"{"] && [base containsString:@"}"]) {
		static NSDateFormatter *dateFormatter;
		static dispatch_once_t once;
		dispatch_once(&once, ^{
			dateFormatter = [[NSDateFormatter alloc] init];
			dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
			dateFormatter.dateFormat = @"yyyy-MM-dd";
		});
		base = [base stringByReplacingOccurrencesOfString:@"{date}"
											   withString:[dateFormatter stringFromDate:NSDate.date]];
#if defined(__APPLE__) && __has_include(<UIKit/UIKit.h>)
		base = [base stringByReplacingOccurrencesOfString:@"{device}"
										   withString:[NSString stringWithFormat:@"%@ (iOS %@)",
													   UIDevice.currentDevice.model ?: @"iPhone",
													   UIDevice.currentDevice.systemVersion ?: @"?"]];
#else
		base = [base stringByReplacingOccurrencesOfString:@"{device}" withString:@"iPhone (iOS)"];
#endif
		base = [base stringByReplacingOccurrencesOfString:@"{lang}"
											   withString:NSLocale.currentLocale.languageCode ?: @"vi"];
	}
	return base;
}


#pragma mark - Tóm tắt trạng thái

- (NSString *)statusSummary {
	if (!self.enabled) return @"Đã tắt";
	if (!self.activeAPIKey.length) return @"Thiếu khóa API";
	return @"Sẵn sàng";
}

- (NSString *)activeProviderName {
	return SXProviderDisplayName(self.provider);
}

- (NSString *)providerSummary {
	NSArray<NSDictionary *> *headers = [self headersForProvider:self.provider];
	NSUInteger active = SXHeadersApplied(headers).count;
	if (active) {
		return [NSString stringWithFormat:@"%@ · %@ · %lu header", self.activeProviderName,
				self.activeModel, (unsigned long)active];
	}
	return [NSString stringWithFormat:@"%@ · %@", self.activeProviderName, self.activeModel];
}

- (NSString *)replySummary {
	NSString *mode = self.mode == SXReplyModeFull ? @"Thay thế mọi câu" : @"Thông minh";
	NSString *trigger = [self.triggerMode isEqualToString:@"prefix"] ? @"tiền tố @ai" : @"tự động";
	return [NSString stringWithFormat:@"%@ · %@ · chờ %.0fs", mode, trigger, self.responseTimeout];
}

- (NSString *)historySummary {
	if (self.incognito) return @"Không lưu";
	return [NSString stringWithFormat:@"Đang lưu · %ld câu gần nhất", (long)self.contextTurns];
}


@end
