#import "SXPrefs.h"
#import "SXLog.h"
#import "SXConfigIO.h"
#import "SXNetwork.h"
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
		   @"Tác vụ trên máy do Siri xử lý; không khẳng định đã thực hiện tác vụ nếu bạn không xác minh được.";
}

@interface SXPrefs ()
@property (atomic, readwrite, copy) NSDictionary *settings;
@end

@implementation SXPrefs
+ (instancetype)shared {
	static SXPrefs *instance;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ instance = [SXPrefs new]; [instance reload]; });
	return instance;
}
- (SXPrefs *)snapshot {
	SXPrefs *result = [SXPrefs new];
	result.settings = self.settings;
	return result;
}

+ (BOOL)writeValues:(NSDictionary *)values removing:(NSArray<NSString *> *)keys {
	CFStringRef domain = (__bridge CFStringRef)kSXDomain;
	CFPreferencesSetMultiple((__bridge CFDictionaryRef)values, (__bridge CFArrayRef)keys, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	return CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
+ (void)setString:(NSString *)value forKey:(NSString *)key {
	if (key.length) [self writeValues:(value ? @{key: value} : @{}) removing:(value ? @[] : @[key])];
}
- (void)reload {
	@synchronized (self) {
		CFStringRef domain = (__bridge CFStringRef)kSXDomain;
		CFPreferencesAppSynchronize(domain);
		NSDictionary *file = [NSDictionary dictionaryWithContentsOfFile:kSXFilePath];
		NSDictionary *defaults = SXConfigDefaults();
		NSMutableDictionary *next = [defaults mutableCopy];
		id (^read)(NSString *) = ^id(NSString *key) {
			return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain)) ?: file[key];
		};
		for (NSString *key in defaults) {
			id raw = read(key);
			// Older Settings bundles sometimes wrote booleans as integer values.
			if (CFGetTypeID((__bridge CFTypeRef)defaults[key]) == CFBooleanGetTypeID() && [raw isKindOfClass:NSNumber.class]) raw = @([raw boolValue]);
			id typed = SXConfigValue(key, raw);
			// A malformed saved endpoint must never redirect its secret to a default host.
			if (raw && !typed && [key isEqualToString:@"openaiBase"]) next[key] = @"";
			else if (typed) next[key] = typed;
		}
		id legacyVoice = read(@"speakErrors");
		if (!read(@"ttsMode") && [legacyVoice respondsToSelector:@selector(boolValue)] && [legacyVoice boolValue]) next[@"ttsMode"] = @"all";
		if (![next[@"openaiBase"] length] && !read(@"openaiBase")) next[@"openaiBase"] = defaults[@"openaiBase"];
		if ([next isEqual:self.settings]) return;
		if ([next[@"localOnly"] boolValue]) [SXRequest setNetworkAllowed:NO];
		self.settings = next;
		if (![next[@"localOnly"] boolValue]) [SXRequest setNetworkAllowed:YES];
		SXLogSetVerbose(self.verbose);
		SXLogInf(@"pref", @"cài đặt: enabled=%d provider=%ld localOnly=%d privateHistory=%d STT=%d streaming=%d",
			self.enabled, (long)self.provider, self.localOnly, self.incognito, self.sttEnabled, self.streaming);
	}
}
#define SX_BOOL(name) - (BOOL)name { return [self.settings[@#name] boolValue]; }
#define SX_INT(name) - (NSInteger)name { return [self.settings[@#name] integerValue]; }
#define SX_DOUBLE(name) - (double)name { return [self.settings[@#name] doubleValue]; }
#define SX_STRING(name) - (NSString *)name { return self.settings[@#name] ?: @""; }
SX_BOOL(enabled) SX_BOOL(hideWebCards) SX_BOOL(showOriginal) SX_BOOL(incognito) SX_BOOL(localOnly)
SX_BOOL(verbose) SX_BOOL(streaming) SX_BOOL(markdown) SX_BOOL(toolSystemInfo) SX_BOOL(toolClipboard)
SX_BOOL(toolFetchURL) SX_BOOL(toolCurrentApp) SX_BOOL(deferredReplies) SX_BOOL(liveSiriUpdates) SX_BOOL(sttEnabled)
SX_INT(contextTurns) SX_INT(maxToolRounds) SX_INT(sttMaxSec) SX_INT(sttWaitMs)
SX_DOUBLE(temperature) SX_DOUBLE(ttsSpeed) SX_DOUBLE(ttsVolume)
SX_STRING(triggerMode) SX_STRING(openaiKey) SX_STRING(openaiBase) SX_STRING(openaiModel) SX_STRING(geminiKey)
SX_STRING(geminiModel) SX_STRING(customPrompt) SX_STRING(timeoutAction)
SX_STRING(sttSource) SX_STRING(sttBaseUrl) SX_STRING(sttApiKey) SX_STRING(sttModel) SX_STRING(sttLanguage) SX_STRING(sttTranslate) SX_STRING(sttPrompt)
SX_STRING(ttsMode) SX_STRING(ttsSource) SX_STRING(ttsLang) SX_STRING(ttsVoice) SX_STRING(ttsBaseUrl) SX_STRING(ttsApiKey) SX_STRING(ttsModel)
- (NSTimeInterval)responseTimeout { return [self.settings[@"timeout"] doubleValue]; }
- (SXReplyMode)mode { return [self.settings[@"mode"] isEqual:@"full"] ? SXReplyModeFull : SXReplyModeSmart; }
- (SXProvider)provider { return [self.settings[@"provider"] isEqual:@"gemini"] ? SXProviderGemini : SXProviderOpenAI; }
- (NSString *)activeAPIKey { return self.provider == SXProviderGemini ? self.geminiKey : self.openaiKey; }
- (NSString *)activeModel {
	if (self.provider == SXProviderGemini) return self.geminiModel.length ? self.geminiModel : SXConfigDefaults()[@"geminiModel"];
	return self.openaiModel.length ? self.openaiModel : SXConfigDefaults()[@"openaiModel"];
}
- (NSString *)activeBaseURL { return self.openaiBase; }
- (NSString *)fallbackModelForProvider:(SXProvider)provider {
	return self.settings[provider == SXProviderGemini ? @"geminiFallbackModel" : @"openaiFallbackModel"] ?: @"";
}

- (NSString *)systemPrompt {
	NSString *base = self.customPrompt.length ? self.customPrompt : SXDefaultSystemPrompt();
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
