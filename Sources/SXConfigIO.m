#import "SXConfigIO.h"
#import "SXProviders.h"
#import "SXNetwork.h"
#import <math.h>

NSDictionary *SXConfigDefaults(void) {
	static NSDictionary *values;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSMutableDictionary *defaults = [@{
			@"enabled": @YES, @"mode": @"smart", @"triggerMode": @"auto", @"provider": @"openai", @"customBase": @"",
			@"temperature": @0.7, @"contextTurns": @8, @"timeout": @10, @"customPrompt": @"",
			@"hideWebCards": @YES, @"showOriginal": @NO, @"incognito": @NO, @"localOnly": @NO, @"verbose": @YES,
			@"streaming": @YES, @"markdown": @YES, @"timeoutAction": @"bubble", @"deferredReplies": @YES, @"liveSiriUpdates": @NO,
			@"maxToolRounds": @3, @"toolSystemInfo": @YES, @"toolClipboard": @YES, @"toolFetchURL": @YES, @"toolCurrentApp": @NO,
			@"sttEnabled": @NO, @"sttSource": @"auto", @"sttBaseUrl": @"",
			@"sttLanguage": @"auto", @"sttTranslate": @"off", @"sttPrompt": @"", @"sttMaxSec": @30, @"sttWaitMs": @2500,
			@"ttsMode": @"ai", @"ttsSource": @"system", @"ttsLang": @"auto", @"ttsSpeed": @1.0, @"ttsVolume": @100, @"ttsBaseUrl": @"",
		} mutableCopy];
		for (NSString *ID in SXChatProviderIDs()) {
			SXProvider provider = SXProviderFromID(ID);
			defaults[SXChatKey(provider, @"Key")] = @"";
			defaults[SXChatKey(provider, @"Model")] = SXChatDefaultModel(provider);
			defaults[SXChatKey(provider, @"FallbackModel")] = @"";
		}
		for (NSString *kind in @[@"stt", @"tts"]) for (NSDictionary *fields in SXMediaProfiles(kind).allValues) {
			for (NSString *key in fields.allValues) defaults[key] = @"";
		}
		values = [defaults copy];
	});
	return values;
}
static BOOL SXSecretKey(NSString *key) { return [key hasSuffix:@"Key"]; }
static BOOL SXBaseKey(NSString *key) { return [@[@"customBase", @"sttBaseUrl", @"ttsBaseUrl"] containsObject:key]; }
static BOOL SXBool(id obj) { return [obj isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)obj) == CFBooleanGetTypeID(); }

id SXConfigValue(NSString *key, id value) {
	id sample = SXConfigDefaults()[key];
	if (!sample || !value) return nil;
	if (SXBool(sample)) return SXBool(value) ? value : nil;
	if ([sample isKindOfClass:NSNumber.class]) {
		if (![value isKindOfClass:NSNumber.class] || SXBool(value)) return nil;
		double n = [value doubleValue];
		NSArray *range = @{
			@"temperature": @[@0, @2], @"contextTurns": @[@2, @40], @"timeout": @[@2, @30], @"maxToolRounds": @[@1, @4],
			@"sttMaxSec": @[@3, @30], @"sttWaitMs": @[@250, @2500], @"ttsSpeed": @[@0.5, @2], @"ttsVolume": @[@0, @100],
		}[key];
		if (!isfinite(n) || !range || n < [range[0] doubleValue] || n > [range[1] doubleValue]) return nil;
		if ([key isEqual:@"temperature"] || [key isEqual:@"ttsSpeed"]) return @(round(n * 10) / 10);
		return @((NSInteger)lround(n));
	}
	if (![value isKindOfClass:NSString.class]) return nil;
	BOOL prompt = [@[@"customPrompt", @"sttPrompt"] containsObject:key];
	NSString *text = prompt ? value : [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (text.length > (prompt ? 16384 : 2048)) return nil;
	if (!prompt && [text rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return nil;
	NSArray *choices = @{
		@"mode": @[@"smart", @"full"], @"triggerMode": @[@"auto", @"prefix"], @"provider": SXChatProviderIDs(),
		@"timeoutAction": @[@"bubble", @"keep", @"retry"], @"sttSource": @[@"auto", @"groq", @"openai", @"gemini", @"custom"],
		@"sttTranslate": @[@"off", @"vi", @"en"], @"ttsMode": @[@"off", @"ai", @"errors", @"all"],
		@"ttsSource": @[@"system", @"google", @"gemini", @"custom"], @"ttsLang": @[@"auto", @"vi", @"en"],
	}[key];
	if (choices) return [choices containsObject:text] ? text : nil;
	if (SXBaseKey(key) && text.length) {
		if (!SXHTTPSURL(text) || [NSURLComponents componentsWithString:text].query) return nil;
	}
	if ([key isEqual:@"sttLanguage"]) {
		if (!text.length || [text.lowercaseString isEqual:@"auto"]) return @"auto";
		NSCharacterSet *letters = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"];
		if (text.length != 2 || [text rangeOfCharacterFromSet:letters.invertedSet].location != NSNotFound) return nil;
		return text.lowercaseString;
	}
	if (text.length && [@[@"geminiModel", @"geminiFallbackModel", @"sttGeminiModel", @"ttsGeminiModel"] containsObject:key]) {
		if (!SXGeminiEndpoint(text, NO)) return nil;
		return [text hasPrefix:@"models/"] ? [text substringFromIndex:7] : text;
	}
	return text;
}

NSDictionary<NSString *, NSString *> *SXLegacyConfigKeys(void) {
	return @{@"openaiBase": @"customBase", @"sttApiKey": @"sttCustomKey", @"sttModel": @"sttCustomModel",
		@"ttsApiKey": @"ttsCustomKey", @"ttsModel": @"ttsCustomModel", @"ttsVoice": @"ttsCustomVoice"};
}
static SXProvider SXLegacyChatProvider(NSString *base) {
	NSURL *endpoint = SXHTTPSURL(SXEndpoint(base, @"/chat/completions"));
	for (NSNumber *number in @[@(SXProviderOpenAI), @(SXProviderGroq)]) {
		SXProvider provider = number.integerValue;
		NSURL *known = SXHTTPSURL(SXEndpoint(SXChatBase(@{}, provider), @"/chat/completions"));
		if ([endpoint.host.lowercaseString isEqual:known.host] && [(endpoint.port ?: @443) isEqual:@443] && [endpoint.path isEqual:known.path]) return provider;
	}
	return SXProviderCustom;
}
NSDictionary *SXUpgradeLegacyConfig(NSDictionary *settings) {
	NSMutableDictionary *upgraded = [settings mutableCopy];
	if (settings[@"openaiBase"]) {
		NSString *base = SXConfigValue(@"customBase", settings[@"openaiBase"]) ?: @"";
		SXProvider provider = SXLegacyChatProvider(base);
		if (provider == SXProviderCustom) upgraded[@"customBase"] = base;
		if (provider != SXProviderOpenAI) {
			for (NSString *field in @[@"Key", @"Model", @"FallbackModel"]) {
				NSString *old = SXChatKey(SXProviderOpenAI, field), *next = SXChatKey(provider, field);
				if (upgraded[old] && !upgraded[next]) upgraded[next] = upgraded[old];
				[upgraded removeObjectForKey:old];
			}
			if (provider == SXProviderCustom && ![upgraded[@"customModel"] length]) upgraded[@"customModel"] = SXChatDefaultModel(SXProviderOpenAI);
			if ([(upgraded[@"provider"] ?: @"openai") isEqual:@"openai"]) upgraded[@"provider"] = SXProviderID(provider);
		}
		[upgraded removeObjectForKey:@"openaiBase"];
	}
	if ([settings[@"sttSource"] isEqual:@"off"]) {
		upgraded[@"sttEnabled"] = @NO;
		upgraded[@"sttSource"] = @"auto";
	} else {
		NSDictionary *fields = SXSTTFields(upgraded);
		if (fields[@"key"] && settings[@"sttApiKey"] && !upgraded[fields[@"key"]]) upgraded[fields[@"key"]] = settings[@"sttApiKey"];
		if (fields[@"model"] && settings[@"sttModel"] && !upgraded[fields[@"model"]]) upgraded[fields[@"model"]] = settings[@"sttModel"];
	}
	NSDictionary *voiceFields = SXMediaProfiles(@"tts")[settings[@"ttsSource"] ?: @"system"];
	for (NSString *field in @[@"key", @"model", @"voice"]) {
		NSString *old = @{@"key": @"ttsApiKey", @"model": @"ttsModel", @"voice": @"ttsVoice"}[field];
		NSString *next = voiceFields[field];
		// Use the saved source, not the effective (possibly off/private) source.
		if (next && settings[old] && !upgraded[next]) upgraded[next] = settings[old];
	}
	[upgraded removeObjectsForKeys:@[@"sttApiKey", @"sttModel", @"ttsApiKey", @"ttsModel", @"ttsVoice"]];
	return upgraded;
}

NSDictionary *SXConfigChangePlan(NSDictionary *current, NSDictionary *edits) {
	NSMutableDictionary *set = [NSMutableDictionary dictionary];
	NSMutableArray *remove = [NSMutableArray array];
	for (NSString *key in edits) if (![edits[key] isEqual:current[key]]) set[key] = edits[key];
	// Independent profiles keep their credentials when switching. Changing the
	// URL of a custom profile, however, requires an explicitly supplied key.
	NSDictionary *bindings = @{@"customBase": @"customKey", @"sttBaseUrl": @"sttCustomKey", @"ttsBaseUrl": @"ttsCustomKey"};
	for (NSString *base in bindings) {
		NSString *key = bindings[base];
		if (set[base] && !edits[key] && [current[key] length]) [remove addObject:key];
	}
	return @{@"set": [set copy], @"remove": [remove copy]};
}
static NSDictionary *SXConfigFailure(NSError **error, NSString *message) {
	if (error) *error = [NSError errorWithDomain:@"com.sirix.config" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
	return nil;
}
NSData *SXExportConfig(NSDictionary *values, BOOL includeSecrets, NSError **error) {
	NSMutableDictionary *safe = [NSMutableDictionary dictionary];
	for (NSString *key in SXConfigDefaults()) {
		safe[key] = !includeSecrets && SXSecretKey(key) ? @"***" : (SXConfigValue(key, values[key]) ?: SXConfigDefaults()[key]);
	}
	return [NSJSONSerialization dataWithJSONObject:@{@"version": @2, @"settings": safe}
		options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:error];
}
NSDictionary *SXImportConfig(NSData *data, NSDictionary *current, NSError **error) {
	if (!data.length || data.length > 128 * 1024) return SXConfigFailure(error, @"Tệp trống hoặc lớn hơn 128 KB.");
	id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
	if (![json isKindOfClass:NSDictionary.class] || SXBool(json[@"version"]) ||
		(![json[@"version"] isEqual:@1] && ![json[@"version"] isEqual:@2]) ||
		![json[@"settings"] isKindOfClass:NSDictionary.class]) return SXConfigFailure(error, @"Cần tệp JSON cấu hình SiriX phiên bản 1 hoặc 2.");
	BOOL legacy = [json[@"version"] isEqual:@1];
	NSDictionary *aliases = SXLegacyConfigKeys();
	NSDictionary *settings = json[@"settings"];
	NSMutableDictionary *edits = [NSMutableDictionary dictionary];
	for (NSString *key in settings) {
		NSString *typeKey = (legacy ? aliases[key] : nil) ?: key;
		if (!SXConfigDefaults()[typeKey]) return SXConfigFailure(error, @"Tệp có một mục không được SiriX hỗ trợ.");
		id raw = settings[key];
		if (SXSecretKey(typeKey) && [raw isEqual:@"***"]) continue;
		id value = legacy && [key isEqual:@"sttSource"] && [raw isEqual:@"off"] ? raw : SXConfigValue(typeKey, raw);
		if (!value) return SXConfigFailure(error, [NSString stringWithFormat:@"Giá trị không hợp lệ cho %@.", key]);
		edits[key] = value;
	}
	if (!legacy) return SXConfigChangePlan(current, edits);
	NSMutableDictionary *upgraded = [SXUpgradeLegacyConfig(edits) mutableCopy];
	// A partial v1 file may edit a profile without selecting it.
	if (!settings[@"provider"]) [upgraded removeObjectForKey:@"provider"];
	for (NSString *key in upgraded.allKeys) {
		id value = SXConfigValue(key, upgraded[key]);
		if (!value) return SXConfigFailure(error, [NSString stringWithFormat:@"Giá trị không hợp lệ cho %@.", key]);
		upgraded[key] = value;
	}
	return SXConfigChangePlan(current, upgraded);
}

static BOOL SXHasFallback(NSDictionary *settings) { return SXChatFallback(settings, SXProviderFromID(settings[@"provider"])).length > 0; }
NSString *SXEffectiveTimeoutAction(NSDictionary *settings) {
	NSString *action = settings[@"timeoutAction"];
	if ([action isEqual:@"retry"] && SXHasFallback(settings)) return @"retry";
	return [settings[@"mode"] isEqual:@"full"] && ![action isEqual:@"keep"] ? @"bubble" : @"keep";
}
BOOL SXConfigSupportsNativeUpdates(NSDictionary *settings) {
	return ([settings[@"streaming"] boolValue] && SXTTSModeAllows(settings[@"ttsMode"], YES)) ||
		([settings[@"deferredReplies"] boolValue] && ![settings[@"incognito"] boolValue]);
}
static BOOL SXAnyTools(NSDictionary *settings) {
	return [settings[@"toolSystemInfo"] boolValue] || [settings[@"toolClipboard"] boolValue] ||
		[settings[@"toolFetchURL"] boolValue] || [settings[@"toolCurrentApp"] boolValue];
}
BOOL SXConfigShowsRule(NSString *rule, NSDictionary *settings) {
	if (!rule.length) return YES;
	if ([rule isEqual:@"chat-custom"]) return [settings[@"provider"] isEqual:@"custom"];
	if ([rule hasPrefix:@"stt"]) {
		if (![settings[@"sttEnabled"] boolValue]) return NO;
		if ([rule isEqual:@"stt"]) return YES;
		if ([rule isEqual:@"stt-custom"]) return [settings[@"sttSource"] isEqual:@"custom"];
		if ([rule isEqual:@"stt-model"]) return !SXSTTUsesFixedEnglishModel(settings);
		if ([rule isEqual:@"stt-key"]) return SXSTTFields(settings)[@"key"] != nil;
		if ([rule isEqual:@"stt-language"]) return ![settings[@"sttTranslate"] isEqual:@"en"] || [SXSTTEffectiveSource(settings) isEqual:@"gemini"];
	}
	if ([rule hasPrefix:@"tts"]) {
		NSString *source = SXTTSEffectiveSource(settings);
		if ([source isEqual:@"off"]) return NO;
		if ([rule isEqual:@"tts"]) return YES;
		if ([rule isEqual:@"tts-select"]) return ![settings[@"incognito"] boolValue] && SXTTSModeAllows(settings[@"ttsMode"], YES);
		if ([rule isEqual:@"tts-picker"]) return ![source isEqual:@"custom"];
		if ([rule isEqual:@"tts-online"]) return ![source isEqual:@"system"];
		if ([rule isEqual:@"tts-custom"]) return [source isEqual:@"custom"];
		if ([rule isEqual:@"tts-model"]) return SXMediaProfiles(@"tts")[source][@"model"] != nil;
	}
	if ([rule isEqual:@"live"]) return SXConfigSupportsNativeUpdates(settings);
	if ([rule isEqual:@"not-private"]) return ![settings[@"incognito"] boolValue];
	if ([rule isEqual:@"tool-rounds"]) return ![settings[@"incognito"] boolValue] && SXAnyTools(settings);
	if ([rule hasPrefix:@"timeout-"]) {
		BOOL full = [settings[@"mode"] isEqual:@"full"], fallback = SXHasFallback(settings);
		if ([rule isEqual:@"timeout-full"]) return full && !fallback;
		if ([rule isEqual:@"timeout-full-retry"]) return full && fallback;
		if ([rule isEqual:@"timeout-smart-retry"]) return !full && fallback;
	}
	return NO;
}
NSDictionary *SXConfigPresentationState(NSDictionary *settings) {
	NSMutableDictionary *state = [[settings dictionaryWithValuesForKeys:@[@"provider", @"mode", @"sttEnabled", @"sttSource", @"sttTranslate",
		@"ttsMode", @"ttsSource", @"incognito", @"streaming", @"deferredReplies"]] mutableCopy];
	state[@"fallback"] = @(SXHasFallback(settings));
	state[@"tools"] = @(SXAnyTools(settings));
	return state;
}
