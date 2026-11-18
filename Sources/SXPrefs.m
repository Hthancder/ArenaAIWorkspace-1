#import "SXPrefs.h"
#import "SXLog.h"
#import <UIKit/UIKit.h>

static NSString *const kSXDomain = @"com.sirix.tweak";
static NSString *const kSXFilePath = @"/var/mobile/Library/Preferences/com.sirix.tweak.plist";

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
				 @"temperature", @"contextTurns", @"timeout", @"timeoutAction",
				 @"streaming", @"markdown", @"hideWebCards", @"showOriginal", @"speakErrors",
				 @"customPrompt", @"incognito",
				 @"maxToolRounds", @"toolSystemInfo", @"toolClipboard", @"toolFetchURL",
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

/// Giữ tham chiếu tới các giá trị vừa bị thay trong `reload`.
///
/// `SXPrefs` được đọc từ nhiều luồng (hook ACE, luồng mạng của LLM, hàng đợi kho)
/// trong khi `reload` chạy trên luồng chính mỗi lần người dùng đổi cài đặt. Nếu
/// một luồng nền đọc đúng ivar đang được thay, ARC có thể retain một con trỏ đã
/// giải phóng → SpringBoard crash (người dùng thấy “Siri văng”). Giữ lại giá trị
/// cũ (có giới hạn) biến ca đua đó thành “đọc giá trị cũ” thay vì dùng bộ nhớ đã
/// giải phóng; đổi lại chỉ tốn vài KB.
static void SXRetireValues(NSArray *values) {
	static NSMutableArray *retired;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ retired = [NSMutableArray array]; });
	@synchronized (retired) {
		for (id value in values) {
			if (value && value != [NSNull null]) [retired addObject:value];
		}
		if (retired.count > 256) {
			[retired removeObjectsInRange:NSMakeRange(0, retired.count - 256)];
		}
	}
}

@interface SXPrefs () {
	NSDictionary *_fileFallback;
}
@end

@implementation SXPrefs

+ (instancetype)shared {
	static SXPrefs *instance;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		instance = [[SXPrefs alloc] init];
		[instance reload];
	});
	return instance;
}

#pragma mark - Đọc giá trị

- (id)valueFor:(NSString *)key {
	id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
													   (__bridge CFStringRef)kSXDomain));
	if (!v) v = _fileFallback[key];
	return v;
}

- (BOOL)boolFor:(NSString *)key default:(BOOL)dflt {
	id v = [self valueFor:key];
	if ([v isKindOfClass:[NSNumber class]]) return [v boolValue];
	if ([v isKindOfClass:[NSString class]]) return [(NSString *)v boolValue];
	return dflt;
}

- (double)doubleFor:(NSString *)key default:(double)dflt {
	id v = [self valueFor:key];
	if ([v isKindOfClass:[NSNumber class]]) return [v doubleValue];
	if ([v isKindOfClass:[NSString class]]) return [(NSString *)v doubleValue];
	return dflt;
}

- (NSInteger)integerFor:(NSString *)key default:(NSInteger)dflt {
	id v = [self valueFor:key];
	if ([v isKindOfClass:[NSNumber class]]) return [v integerValue];
	if ([v isKindOfClass:[NSString class]]) return [(NSString *)v integerValue];
	return dflt;
}

- (NSString *)stringFor:(NSString *)key default:(NSString *)dflt {
	id v = [self valueFor:key];
	if ([v isKindOfClass:[NSString class]]) return [v copy];
	return dflt;
}

static double SXClamp(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

#pragma mark - Tải lại

+ (void)setString:(NSString *)value forKey:(NSString *)key {
	[self setValue:value forKey:key];
}

+ (void)setValue:(id)value forKey:(NSString *)key {
	if (!key.length) return;
	if (value && ![value isKindOfClass:[NSString class]] && ![value isKindOfClass:[NSNumber class]]) return;
	CFPreferencesSetAppValue((__bridge CFStringRef)key,
							 (__bridge CFPropertyListRef)value,
							 (__bridge CFStringRef)kSXDomain);
	CFPreferencesAppSynchronize((__bridge CFStringRef)kSXDomain);
}

+ (void)resetAll {
	CFArrayRef raw = CFPreferencesCopyKeyList((__bridge CFStringRef)kSXDomain,
											  kCFPreferencesCurrentUser,
											  kCFPreferencesAnyHost);
	NSArray *existing = raw ? CFBridgingRelease(raw) : @[];
	NSMutableSet *keys = [NSMutableSet setWithArray:SXPreferenceKeys()];
	if ([existing isKindOfClass:[NSArray class]]) [keys addObjectsFromArray:existing];
	for (NSString *key in keys) {
		if (![key isKindOfClass:[NSString class]] || !key.length) continue;
		CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, (__bridge CFStringRef)kSXDomain);
	}
	CFPreferencesAppSynchronize((__bridge CFStringRef)kSXDomain);
	SXLogInf(@"pref", @"đã khôi phục toàn bộ cài đặt mặc định (%lu key)", (unsigned long)keys.count);
}

+ (NSString *)normalizedBaseURL:(NSString *)raw {
	if (![raw isKindOfClass:[NSString class]]) return nil;
	NSString *text = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!text.length) return nil;
	NSURLComponents *components = [NSURLComponents componentsWithString:text];
	NSString *scheme = components.scheme.lowercaseString;
	if (![scheme isEqualToString:@"https"] && ![scheme isEqualToString:@"http"]) return nil;
	if (!components.host.length) return nil;
	while ([text hasSuffix:@"/"]) text = [text substringToIndex:text.length - 1];
	return text;
}

+ (BOOL)isValidBaseURL:(NSString *)raw {
	return [self normalizedBaseURL:raw] != nil;
}

+ (NSString *)stringForKey:(NSString *)key {
	if (!key.length) return nil;
	id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
														   (__bridge CFStringRef)kSXDomain));
	return [value isKindOfClass:[NSString class]] ? value : nil;
}

+ (NSString *)maskedKey:(NSString *)key {
	if (![key isKindOfClass:[NSString class]]) return @"";
	NSString *trimmed = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!trimmed.length) return @"";
	if (trimmed.length <= 8) return @"••••••••";
	return [NSString stringWithFormat:@"%@…%@", [trimmed substringToIndex:3],
			[trimmed substringFromIndex:trimmed.length - 4]];
}

- (void)reload {
	// Xem SXRetireValues: không để luồng nền đọc phải một con trỏ đã giải phóng.
	SXRetireValues(@[_fileFallback ?: [NSNull null],
					 _triggerMode ?: [NSNull null],
					 _openaiKey ?: [NSNull null], _openaiBase ?: [NSNull null], _openaiModel ?: [NSNull null],
					 _geminiKey ?: [NSNull null], _geminiModel ?: [NSNull null],
					 _customPrompt ?: [NSNull null], _timeoutAction ?: [NSNull null]]);

	NSDictionary *file = nil;
	if ([[NSFileManager defaultManager] fileExistsAtPath:kSXFilePath]) {
		file = [NSDictionary dictionaryWithContentsOfFile:kSXFilePath];
	}
	_fileFallback = file;

	_enabled = [self boolFor:@"enabled" default:YES];
	_mode = [[self stringFor:@"mode" default:@"smart"] isEqualToString:@"full"]
		? SXReplyModeFull : SXReplyModeSmart;
	_triggerMode = [[self stringFor:@"triggerMode" default:@"auto"] isEqualToString:@"prefix"] ? @"prefix" : @"auto";
	_provider = [[self stringFor:@"provider" default:@"openai"] isEqualToString:@"gemini"]
		? SXProviderGemini : SXProviderOpenAI;

	_openaiKey = [self stringFor:@"openaiKey" default:@""] ?: @"";
	_openaiBase = [self stringFor:@"openaiBase" default:@"https://api.openai.com/v1"] ?: @"https://api.openai.com/v1";
	_openaiModel = [self stringFor:@"openaiModel" default:@"gpt-4o-mini"] ?: @"gpt-4o-mini";
	_geminiKey = [self stringFor:@"geminiKey" default:@""] ?: @"";
	_geminiModel = [self stringFor:@"geminiModel" default:@"gemini-2.0-flash"] ?: @"gemini-2.0-flash";

	_temperature = SXClamp(round([self doubleFor:@"temperature" default:0.7] * 10.0) / 10.0, 0.0, 2.0);
	_contextTurns = (NSInteger)SXClamp((double)[self integerFor:@"contextTurns" default:8], 2, 40);
	_responseTimeout = SXClamp((double)[self integerFor:@"timeout" default:10], 2, 30);
	_customPrompt = [self stringFor:@"customPrompt" default:@""] ?: @"";

	_hideWebCards = [self boolFor:@"hideWebCards" default:YES];
	_showOriginal = [self boolFor:@"showOriginal" default:NO];
	_incognito = [self boolFor:@"incognito" default:NO];
	_speakErrors = [self boolFor:@"speakErrors" default:NO];
	_verbose = [self boolFor:@"verbose" default:YES];
	_streaming = [self boolFor:@"streaming" default:YES];
	_markdown = [self boolFor:@"markdown" default:YES];
	_timeoutAction = [[self stringFor:@"timeoutAction" default:@"bubble"] isEqualToString:@"keep"]
		? @"keep" : @"bubble";
	_maxToolRounds = (NSInteger)SXClamp((double)[self integerFor:@"maxToolRounds" default:3], 1, 4);
	_toolSystemInfo = [self boolFor:@"toolSystemInfo" default:YES];
	_toolClipboard = [self boolFor:@"toolClipboard" default:YES];
	_toolFetchURL = [self boolFor:@"toolFetchURL" default:YES];

	SXLogSetVerbose(_verbose);
	SXLogInf(@"pref", @"cài đặt: enabled=%d mode=%@ provider=%@ temp=%.1f turns=%ld timeout=%.0fs "
			 @"stream=%d md=%d timeoutAction=%@ tools=%ld "
			 @"openAIKey=%@ geminiKey=%@ customPrompt=%@",
			 _enabled, _mode == SXReplyModeFull ? @"full" : @"smart",
			 _provider == SXProviderGemini ? @"gemini" : @"openai",
			 _temperature, (long)_contextTurns, _responseTimeout,
			 _streaming, _markdown, _timeoutAction, (long)_maxToolRounds,
			 SXRedactKey(_openaiKey), SXRedactKey(_geminiKey),
			 _customPrompt.length > 0 ? [NSString stringWithFormat:@"%lu ký tự", (unsigned long)_customPrompt.length] : @"(mặc định)");
}

#pragma mark - Truy vấn theo provider hiện tại

- (NSString *)activeAPIKey {
	// Cắt khoảng trắng/dấu xuống dòng thừa — dán khóa từ web thường dính "\n" ở đuôi.
	NSString *key = _provider == SXProviderGemini ? _geminiKey : _openaiKey;
	return [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)activeModel {
	NSString *model = _provider == SXProviderGemini ? _geminiModel : _openaiModel;
	model = [model stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!model.length) {
		return _provider == SXProviderGemini ? @"gemini-2.0-flash" : @"gpt-4o-mini";
	}
	return model;
}

- (NSString *)activeBaseURL {
	NSString *base = [SXPrefs normalizedBaseURL:_openaiBase];
	return base.length ? base : @"https://api.openai.com/v1";
}

- (NSString *)systemPrompt {
	NSString *base = _customPrompt.length ? _customPrompt : SXDefaultSystemPrompt();
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
		base = [base stringByReplacingOccurrencesOfString:@"{device}"
											   withString:[NSString stringWithFormat:@"%@ (iOS %@)",
														   UIDevice.currentDevice.model ?: @"iPhone",
														   UIDevice.currentDevice.systemVersion ?: @"?"]];
		base = [base stringByReplacingOccurrencesOfString:@"{lang}"
											   withString:NSLocale.currentLocale.languageCode ?: @"vi"];
	}
	return base;
}

#pragma mark - Tóm tắt trạng thái

- (NSString *)statusSummary {
	if (!_enabled) return @"Đã tắt";
	if (!self.activeAPIKey.length) return @"Thiếu khóa API";
	return @"Sẵn sàng";
}

- (NSString *)activeProviderName {
	return SXProviderDisplayName(_provider);
}

- (NSString *)providerSummary {
	return [NSString stringWithFormat:@"%@ · %@", self.activeProviderName, self.activeModel];
}

- (NSString *)replySummary {
	NSString *mode = _mode == SXReplyModeFull ? @"Thay thế mọi câu" : @"Thông minh";
	NSString *trigger = [_triggerMode isEqualToString:@"prefix"] ? @"tiền tố @ai" : @"tự động";
	return [NSString stringWithFormat:@"%@ · %@ · chờ %.0fs", mode, trigger, _responseTimeout];
}

- (NSString *)historySummary {
	if (_incognito) return @"Không lưu";
	return [NSString stringWithFormat:@"Đang lưu · %ld câu gần nhất", (long)_contextTurns];
}

@end
