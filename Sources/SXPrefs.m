#import "SXPrefs.h"
#import "SXLog.h"
#import <UIKit/UIKit.h>

static NSString *const kSXDomain = @"com.sirix.tweak";
static NSString *const kSXFilePath = @"/var/mobile/Library/Preferences/com.sirix.tweak.plist";

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
	if (!key.length) return;
	CFPreferencesSetAppValue((__bridge CFStringRef)key,
							 (__bridge CFPropertyListRef)value,
							 (__bridge CFStringRef)kSXDomain);
	CFPreferencesAppSynchronize((__bridge CFStringRef)kSXDomain);
}

- (void)reload {
	NSDictionary *file = nil;
	if ([[NSFileManager defaultManager] fileExistsAtPath:kSXFilePath]) {
		file = [NSDictionary dictionaryWithContentsOfFile:kSXFilePath];
	}
	_fileFallback = file;

	_enabled = [self boolFor:@"enabled" default:YES];
	_mode = [[self stringFor:@"mode" default:@"smart"] isEqualToString:@"full"]
		? SXReplyModeFull : SXReplyModeSmart;
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
	return _provider == SXProviderGemini ? _geminiKey : _openaiKey;
}

- (NSString *)activeModel {
	if (_provider == SXProviderGemini) {
		return _geminiModel.length ? _geminiModel : @"gemini-2.0-flash";
	}
	return _openaiModel.length ? _openaiModel : @"gpt-4o-mini";
}

- (NSString *)activeBaseURL {
	NSString *base = [_openaiBase stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!base.length) base = @"https://api.openai.com/v1";
	while ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
	return base;
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

@end
