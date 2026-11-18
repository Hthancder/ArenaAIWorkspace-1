#import "SXPrefs.h"
#import "SXLog.h"
#import "SXConfigIO.h"
#import "SXNetwork.h"
#import <TargetConditionals.h>
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#endif

#ifdef SX_TESTING
extern NSString *SXFixturePreferencesDomain(void);
#define kSXDomain (SXFixturePreferencesDomain())
#else
static NSString *const kSXDomain = @"com.sirix.tweak";
#endif

NSString *SXDefaultSystemPrompt(void) {
	return @"Bạn là SiriX, trợ lý AI tích hợp sẵn trong Siri trên iPhone. "
		   @"Trả lời chính xác, tự nhiên, ngắn gọn (thường 1–3 câu, trừ khi người dùng hỏi điều cần giải thích kỹ). "
		   @"Luôn trả lời bằng ngôn ngữ mà người dùng đã đặt câu hỏi. "
		   @"Ưu tiên văn bản thuần (phần lớn câu trả lời chỉ cần vậy); khi thật sự cần nhấn mạnh hoặc liệt kê, "
		   @"duy nhất dùng **đậm**, danh sách gạch đầu dòng ngắn, `mã code` hoặc khối code gọn — "
		   @"SiriX tự trình bày đẹp và vẫn phát giọng nói trôi chảy. Không emoji. "
		   @"Tác vụ trên máy do Siri xử lý; không khẳng định đã thực hiện tác vụ nếu bạn không xác minh được.";
}

// Older installs used one OpenAI-compatible profile and shared media fields.
// Resolve them without writing from SpringBoard; persist atomically with the
// next explicit Settings write, so switching back to OpenAI cannot remigrate.
static NSDictionary *SXReadSavedSettings(void) {
	CFStringRef domain = (__bridge CFStringRef)kSXDomain;
	CFPreferencesAppSynchronize(domain);
	NSDictionary *file = nil;
#ifndef SX_TESTING
	file = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.sirix.tweak.plist"];
#endif
	id (^read)(NSString *) = ^id(NSString *key) {
		return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain)) ?: file[key];
	};
	NSDictionary *defaults = SXConfigDefaults();
	NSMutableDictionary *settings = [NSMutableDictionary dictionary];
	for (NSString *key in defaults) {
		id raw = read(key);
		if (CFGetTypeID((__bridge CFTypeRef)defaults[key]) == CFBooleanGetTypeID() && [raw isKindOfClass:NSNumber.class]) raw = @([raw boolValue]);
		id typed = [key isEqual:@"sttSource"] && [raw isEqual:@"off"] ? raw : SXConfigValue(key, raw);
		if (typed) settings[key] = typed;
	}
	if (![read(@"sxProfileSchema") isEqual:@2]) {
		NSDictionary *legacy = SXLegacyConfigKeys();
		for (NSString *key in legacy) {
			id raw = read(key);
			id value = SXConfigValue(legacy[key], raw);
			// Invalid or blank legacy URLs are not the official OpenAI endpoint.
			if (raw && [key isEqual:@"openaiBase"] && !value) value = @"";
			if (value) settings[key] = value;
		}
	}
	id legacyVoice = read(@"speakErrors");
	if (!read(@"ttsMode") && [legacyVoice respondsToSelector:@selector(boolValue)] && [legacyVoice boolValue]) settings[@"ttsMode"] = @"all";
	return settings;
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
	@synchronized ([self shared]) {
		CFStringRef domain = (__bridge CFStringRef)kSXDomain;
		NSDictionary *stored = SXReadSavedSettings();
		NSDictionary *upgraded = SXUpgradeLegacyConfig(stored);
		NSMutableDictionary *write = [NSMutableDictionary dictionary];
		NSMutableSet *remove = [NSMutableSet setWithArray:keys];
		if (![upgraded isEqual:stored]) {
			for (NSString *key in SXConfigDefaults()) {
				id value = SXConfigValue(key, upgraded[key]);
				if (value && ![value isEqual:stored[key]]) write[key] = value;
				else if (!value && stored[key]) write[key] = SXConfigDefaults()[key];
			}
			[remove addObjectsFromArray:SXLegacyConfigKeys().allKeys];
			write[@"sxProfileSchema"] = @2;
		}
		[write addEntriesFromDictionary:values];
		for (NSString *key in keys) {
			// Explicitly blank secrets; the fallback plist must not revive them.
			if ([key hasSuffix:@"Key"]) { write[key] = @""; [remove removeObject:key]; }
			else [write removeObjectForKey:key];
		}
		CFPreferencesSetMultiple((__bridge CFDictionaryRef)write, (__bridge CFArrayRef)remove.allObjects, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
		return CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	}
}
+ (void)setString:(NSString *)value forKey:(NSString *)key {
	if (key.length) [self writeValues:(value ? @{key: value} : @{}) removing:(value ? @[] : @[key])];
}
- (void)reload {
	@synchronized (self) {
		NSMutableDictionary *next = [SXConfigDefaults() mutableCopy];
		NSDictionary *saved = SXUpgradeLegacyConfig(SXReadSavedSettings());
		for (NSString *key in saved) {
			id typed = SXConfigValue(key, saved[key]);
			if (typed) next[key] = typed;
		}
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
SX_BOOL(toolFetchURL) SX_BOOL(toolCurrentApp) SX_BOOL(deferredReplies) SX_BOOL(sttEnabled)
SX_INT(contextTurns) SX_INT(maxToolRounds) SX_INT(sttMaxSec) SX_INT(sttWaitMs)
SX_DOUBLE(temperature) SX_DOUBLE(ttsSpeed) SX_DOUBLE(ttsVolume)
SX_STRING(triggerMode) SX_STRING(customPrompt)
SX_STRING(sttLanguage) SX_STRING(sttTranslate) SX_STRING(sttPrompt)
SX_STRING(ttsMode) SX_STRING(ttsLang)
- (NSTimeInterval)responseTimeout { return [self.settings[@"timeout"] doubleValue]; }
- (SXReplyMode)mode { return [self.settings[@"mode"] isEqual:@"full"] ? SXReplyModeFull : SXReplyModeSmart; }
- (SXProvider)provider { return SXProviderFromID(self.settings[@"provider"]); }
- (NSString *)activeModel { return SXChatModel(self.settings, self.provider); }
- (NSString *)fallbackModelForProvider:(SXProvider)provider { return SXChatFallback(self.settings, provider); }
- (NSString *)timeoutAction { return SXEffectiveTimeoutAction(self.settings); }
- (BOOL)liveSiriUpdates { NSDictionary *settings = self.settings; return [settings[@"liveSiriUpdates"] boolValue] && SXConfigSupportsNativeUpdates(settings); }
- (NSString *)ttsSource { return SXTTSEffectiveSource(self.settings); }

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
#if TARGET_OS_IOS
		NSString *device = [NSString stringWithFormat:@"%@ (iOS %@)", UIDevice.currentDevice.model ?: @"iPhone", UIDevice.currentDevice.systemVersion ?: @"?"];
#else
		NSString *device = NSProcessInfo.processInfo.operatingSystemVersionString;
#endif
		base = [base stringByReplacingOccurrencesOfString:@"{device}" withString:device];
		base = [base stringByReplacingOccurrencesOfString:@"{lang}"
											   withString:NSLocale.currentLocale.languageCode ?: @"vi"];
	}
	return base;
}

@end
