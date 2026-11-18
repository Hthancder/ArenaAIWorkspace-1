#import "SXConfigIO.h"
#import <math.h>

NSDictionary *SXConfigDefaults(void) {
	static NSDictionary *values;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		values = @{
			@"enabled": @YES, @"mode": @"smart", @"triggerMode": @"auto", @"provider": @"openai",
			@"openaiKey": @"", @"openaiBase": @"https://api.openai.com/v1", @"openaiModel": @"gpt-4o-mini", @"openaiFallbackModel": @"",
			@"geminiKey": @"", @"geminiModel": @"gemini-2.0-flash", @"geminiFallbackModel": @"",
			@"temperature": @0.7, @"contextTurns": @8, @"timeout": @10, @"customPrompt": @"",
			@"hideWebCards": @YES, @"showOriginal": @NO, @"incognito": @NO, @"localOnly": @NO, @"verbose": @YES,
			@"streaming": @YES, @"markdown": @YES, @"timeoutAction": @"bubble", @"deferredReplies": @YES, @"liveSiriUpdates": @NO,
			@"maxToolRounds": @3, @"toolSystemInfo": @YES, @"toolClipboard": @YES, @"toolFetchURL": @YES, @"toolCurrentApp": @NO,
			@"sttEnabled": @NO, @"sttSource": @"auto", @"sttBaseUrl": @"", @"sttApiKey": @"", @"sttModel": @"",
			@"sttLanguage": @"auto", @"sttTranslate": @"off", @"sttPrompt": @"", @"sttMaxSec": @30, @"sttWaitMs": @2500,
			@"ttsMode": @"ai", @"ttsSource": @"system", @"ttsLang": @"auto", @"ttsVoice": @"", @"ttsSpeed": @1.0,
			@"ttsVolume": @100, @"ttsBaseUrl": @"", @"ttsApiKey": @"", @"ttsModel": @"",
		};
	});
	return values;
}
static NSArray<NSString *> *SXSecretKeys(void) { return @[@"openaiKey", @"geminiKey", @"sttApiKey", @"ttsApiKey"]; }
static BOOL SXBaseKey(NSString *key) { return [@[@"openaiBase", @"sttBaseUrl", @"ttsBaseUrl"] containsObject:key]; }
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
		if ([key isEqualToString:@"temperature"] || [key isEqualToString:@"ttsSpeed"]) return @(round(n * 10) / 10);
		return @((NSInteger)lround(n));
	}
	if (![value isKindOfClass:NSString.class]) return nil;
	BOOL prompt = [@[@"customPrompt", @"sttPrompt"] containsObject:key];
	NSString *text = prompt ? value : [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (text.length > (prompt ? 16384 : 2048)) return nil;
	if (!prompt && [text rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return nil;
	NSArray *choices = @{
		@"mode": @[@"smart", @"full"], @"triggerMode": @[@"auto", @"prefix"], @"provider": @[@"openai", @"gemini"],
		@"timeoutAction": @[@"bubble", @"keep", @"retry"], @"sttSource": @[@"off", @"auto", @"groq", @"openai", @"gemini", @"custom"],
		@"sttTranslate": @[@"off", @"vi", @"en"], @"ttsMode": @[@"off", @"ai", @"errors", @"all"],
		@"ttsSource": @[@"system", @"google", @"gemini", @"custom"], @"ttsLang": @[@"auto", @"vi", @"en"],
	}[key];
	if (choices) return [choices containsObject:text] ? text : nil;
	if (SXBaseKey(key) && text.length) {
		NSURLComponents *parts = [NSURLComponents componentsWithString:text];
		if (![parts.scheme.lowercaseString isEqualToString:@"https"] || !parts.host.length || !parts.URL ||
			parts.user || parts.password || parts.query || parts.fragment) return nil;
	}
	if ([key isEqualToString:@"sttLanguage"] && text.length && ![text isEqualToString:@"auto"]) {
		NSCharacterSet *letters = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"];
		if (text.length != 2 || [text rangeOfCharacterFromSet:letters.invertedSet].location != NSNotFound) return nil;
	}
	return text;
}
static NSDictionary *SXConfigFailure(NSError **error, NSString *message) {
	if (error) *error = [NSError errorWithDomain:@"com.sirix.config" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
	return nil;
}
NSData *SXExportConfig(NSDictionary *values, BOOL includeSecrets, NSError **error) {
	NSMutableDictionary *safe = [NSMutableDictionary dictionary];
	for (NSString *key in SXConfigDefaults()) {
		if (!includeSecrets && [SXSecretKeys() containsObject:key]) { safe[key] = @"***"; continue; }
		safe[key] = SXConfigValue(key, values[key]) ?: SXConfigDefaults()[key];
	}
	return [NSJSONSerialization dataWithJSONObject:@{@"version": @1, @"settings": safe}
		options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:error];
}
NSDictionary *SXImportConfig(NSData *data, NSDictionary *current, NSError **error) {
	if (!data.length || data.length > 128 * 1024) return SXConfigFailure(error, @"Tệp trống hoặc lớn hơn 128 KB.");
	id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
	if (![json isKindOfClass:NSDictionary.class] || SXBool(json[@"version"]) || ![json[@"version"] isEqual:@1] ||
		![json[@"settings"] isKindOfClass:NSDictionary.class]) return SXConfigFailure(error, @"Cần tệp JSON cấu hình SiriX phiên bản 1.");
	NSDictionary *settings = json[@"settings"];
	NSMutableDictionary *set = [NSMutableDictionary dictionary];
	NSMutableArray *remove = [NSMutableArray array];
	for (NSString *key in settings) {
		id raw = settings[key];
		if ([SXSecretKeys() containsObject:key] && [raw isEqual:@"***"]) continue;
		id value = SXConfigValue(key, raw);
		if (!value) return SXConfigFailure(error, SXConfigDefaults()[key] ? [NSString stringWithFormat:@"Giá trị không hợp lệ cho %@.", key] : @"Tệp có một mục không được SiriX hỗ trợ.");
		if (![value isEqual:current[key]]) set[key] = value;
	}
	// Do not silently send a saved key to an imported endpoint or provider.
	NSDictionary *origins = @{@"openaiKey": @[@"openaiBase"], @"sttApiKey": @[@"sttBaseUrl", @"sttSource"], @"ttsApiKey": @[@"ttsBaseUrl", @"ttsSource"]};
	for (NSString *secret in origins) {
		if (set[secret] || ![current[secret] length]) continue;
		for (NSString *origin in origins[secret]) {
			if (set[origin]) { [remove addObject:secret]; break; }
		}
	}
	return @{@"set": [set copy], @"remove": [remove copy]};
}
