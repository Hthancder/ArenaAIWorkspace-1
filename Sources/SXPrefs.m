#import "SXPrefs.h"
#import "SXLog.h"
#import <UIKit/UIKit.h>

static NSString *const kSXDomain = @"com.sirix.tweak";
static NSString *const kSXFilePath = @"/var/mobile/Library/Preferences/com.sirix.tweak.plist";


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
	/// Có đáng tin đọc `_fileFallback` không (xem `-reload`).
	BOOL _fallbackUsable;
}
@end

/// Kế thừa từ SXPrefs (Shared) — khai báo để `-reload` gọi được.
@interface SXPrefs (ReloadHelpers)
- (NSSet<NSString *> *)loadDisabledToolsForReload;
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
	// Chỉ dùng bản đọc từ tệp khi cả miền CFPreferences không đọc được gì.
	// Trước đây nó là "phương án hai cho MỌI key": một khoá đã bị xoá (Khôi
	// phục mặc định, hoặc Cài đặt gỡ bỏ) vẫn sống lại nhờ bản sao cũ trong
	// tệp — người dùng bấm "Khôi phục mặc định" mà cài đặt không đổi.
	if (!v && _fallbackUsable) v = _fileFallback[key];
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
	// Cho phép mọi kiểu property list: chuỗi, số, mảng (header tuỳ chỉnh), từ điển…
	if (value && ![NSPropertyListSerialization propertyList:value isValidForFormat:NSPropertyListBinaryFormat_v1_0]) {
		SXLogWrn(@"pref", @"bỏ qua key %@: giá trị không phải property list", key);
		return;
	}
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
	// Bản sao trên đĩa phải biến mất cùng lúc, nếu không lần `-reload` sau sẽ đọc
	// lại đúng những giá trị vừa xoá (xem `_fallbackUsable`).
	[[NSFileManager defaultManager] removeItemAtPath:kSXFilePath error:NULL];
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
					 _openaiFallbackModel ?: [NSNull null], _geminiFallbackModel ?: [NSNull null],
					 _customPrompt ?: [NSNull null], _timeoutAction ?: [NSNull null],
					 _disabledTools ?: [NSNull null],
					 _openaiHeaders ?: [NSNull null], _geminiHeaders ?: [NSNull null]]);

	// CFPreferences là nguồn sự thật. Chỉ khi nó trả về rỗng hoàn toàn (một số
	// bản rootless/roothide không đọc được miền của tweak) mới dùng bản sao trên
	// đĩa, và khi đó mới coi bản sao ấy là đáng tin.
	CFArrayRef rawKeys = CFPreferencesCopyKeyList((__bridge CFStringRef)kSXDomain,
												  kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	NSArray *domainKeys = rawKeys ? CFBridgingRelease(rawKeys) : nil;
	NSDictionary *file = nil;
	if (domainKeys.count == 0 && [[NSFileManager defaultManager] fileExistsAtPath:kSXFilePath]) {
		file = [NSDictionary dictionaryWithContentsOfFile:kSXFilePath];
	}
	_fileFallback = file;
	_fallbackUsable = (file != nil);
	if (file) {
		SXLogWrn(@"pref", @"CFPreferences rỗng — đọc %lu key từ %@ (chế độ dự phòng)",
				 (unsigned long)file.count, kSXFilePath);
	}

	_enabled = [self boolFor:@"enabled" default:YES];
	_mode = [[self stringFor:@"mode" default:@"smart"] isEqualToString:@"full"]
		? SXReplyModeFull : SXReplyModeSmart;
	_triggerMode = [[self stringFor:@"triggerMode" default:@"auto"] isEqualToString:@"prefix"] ? @"prefix" : @"auto";
	_provider = [[self stringFor:@"provider" default:@"openai"] isEqualToString:@"gemini"]
		? SXProviderGemini : SXProviderOpenAI;

	_openaiKey = [self stringFor:@"openaiKey" default:@""] ?: @"";
	_openaiBase = [self stringFor:@"openaiBase" default:@"https://api.openai.com/v1"] ?: @"https://api.openai.com/v1";
	_openaiModel = [self stringFor:@"openaiModel" default:@"gpt-4o-mini"] ?: @"gpt-4o-mini";
	NSString *api = [self stringFor:@"openaiApi" default:@"auto"];
	_openaiApi = [api isEqualToString:@"responses"] ? SXOpenAIApiResponses
		: [api isEqualToString:@"chat"] ? SXOpenAIApiChat : SXOpenAIApiAuto;
	_geminiKey = [self stringFor:@"geminiKey" default:@""] ?: @"";
	_geminiModel = [self stringFor:@"geminiModel" default:@"gemini-2.0-flash"] ?: @"gemini-2.0-flash";
	_openaiFallbackModel = [self stringFor:@"openaiFallbackModel" default:@""] ?: @"";
	_geminiFallbackModel = [self stringFor:@"geminiFallbackModel" default:@""] ?: @"";

	_temperature = SXClamp(round([self doubleFor:@"temperature" default:0.7] * 100.0) / 100.0, 0.0, 2.0);
	_contextTurns = (NSInteger)SXClamp((double)[self integerFor:@"contextTurns" default:8], 0, 40);
	_responseTimeout = SXClamp((double)[self integerFor:@"timeout" default:10], 2, 120);
	_replyDeadline = SXClamp((double)[self integerFor:@"replyDeadline" default:8], 2, 20);
	_customPrompt = [self stringFor:@"customPrompt" default:@""] ?: @"";

	_hideWebCards = [self boolFor:@"hideWebCards" default:YES];
	_showOriginal = [self boolFor:@"showOriginal" default:NO];
	_incognito = [self boolFor:@"incognito" default:NO];
	_speakErrors = [self boolFor:@"speakErrors" default:NO];
	_verbose = [self boolFor:@"verbose" default:YES];
	_streaming = [self boolFor:@"streaming" default:YES];
	_deferLongReplies = [self boolFor:@"deferLongReplies" default:YES];
	_markdown = [self boolFor:@"markdown" default:YES];
	NSString *timeoutAction = [self stringFor:@"timeoutAction" default:@"bubble"];
	_timeoutAction = ([timeoutAction isEqualToString:@"keep"] || [timeoutAction isEqualToString:@"retry"])
		? [timeoutAction copy] : @"bubble";
	_maxToolRounds = (NSInteger)SXClamp((double)[self integerFor:@"maxToolRounds" default:3], 1, 6);
	_disabledTools = [self loadDisabledToolsForReload];
	_openaiHeaders = SXHeadersNormalized([self valueFor:@"openaiHeaders"]);
	_geminiHeaders = SXHeadersNormalized([self valueFor:@"geminiHeaders"]);

	SXLogSetVerbose(_verbose);
	SXLogInf(@"pref", @"cài đặt: enabled=%d mode=%@ provider=%@ temp=%.1f turns=%ld timeout=%.0fs "
			 @"stream=%d md=%d timeoutAction=%@ toolRounds=%ld deferLong=%d toolsOff=%lu headers=%lu/%lu deadline=%.0fs "
			 @"openAIKey=%@ geminiKey=%@ customPrompt=%@",
			 _enabled, _mode == SXReplyModeFull ? @"full" : @"smart",
			 _provider == SXProviderGemini ? @"gemini" : @"openai",
			 _temperature, (long)_contextTurns, _responseTimeout,
			 _streaming, _markdown, _timeoutAction, (long)_maxToolRounds, _deferLongReplies,
			 (unsigned long)_disabledTools.count,
			 (unsigned long)_openaiHeaders.count, (unsigned long)_geminiHeaders.count, _replyDeadline,
			 SXRedactKey(_openaiKey), SXRedactKey(_geminiKey),
			 _customPrompt.length > 0 ? [NSString stringWithFormat:@"%lu ký tự", (unsigned long)_customPrompt.length] : @"(mặc định)");
}

@end
