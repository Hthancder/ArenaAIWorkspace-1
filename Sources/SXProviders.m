#import "SXProviders.h"
#import "SXNetwork.h"

// Order matches SXProvider. A preset never reads a stored URL.
static NSArray<NSDictionary *> *SXChatCatalog(void) {
	static NSArray *catalog;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		catalog = @[
			@{@"id": @"openai", @"name": @"OpenAI", @"base": @"https://api.openai.com/v1", @"model": @"gpt-4o-mini"},
			@{@"id": @"gemini", @"name": @"Gemini", @"base": SXGeminiBaseURL, @"model": @"gemini-2.5-flash"},
			@{@"id": @"groq", @"name": @"Groq", @"base": @"https://api.groq.com/openai/v1", @"model": @"llama-3.1-8b-instant"},
			@{@"id": @"custom", @"name": @"Tự chỉnh", @"base": @"", @"model": @""},
		];
	});
	return catalog;
}
static NSDictionary *SXChatPreset(SXProvider provider) {
	NSArray *catalog = SXChatCatalog();
	return catalog[(NSUInteger)provider < catalog.count ? provider : SXProviderOpenAI];
}
NSArray<NSString *> *SXChatProviderIDs(void) { return [SXChatCatalog() valueForKey:@"id"]; }
SXProvider SXProviderFromID(NSString *identifier) {
	NSArray *ids = SXChatProviderIDs();
	NSUInteger index = identifier ? [ids indexOfObject:identifier] : NSNotFound;
	return index == NSNotFound ? SXProviderOpenAI : (SXProvider)index;
}
NSString *SXProviderID(SXProvider provider) { return SXChatPreset(provider)[@"id"]; }
NSString *SXProviderName(SXProvider provider) { return SXChatPreset(provider)[@"name"]; }
NSString *SXChatKey(SXProvider provider, NSString *suffix) { return [SXProviderID(provider) stringByAppendingString:suffix]; }
NSString *SXChatDefaultModel(SXProvider provider) { return SXChatPreset(provider)[@"model"]; }
NSString *SXChatBase(NSDictionary *settings, SXProvider provider) {
	return provider == SXProviderCustom ? (settings[@"customBase"] ?: @"") : SXChatPreset(provider)[@"base"];
}
NSString *SXChatModel(NSDictionary *settings, SXProvider provider) {
	NSString *model = settings[SXChatKey(provider, @"Model")];
	return model.length ? model : SXChatDefaultModel(provider);
}
NSString *SXChatFallback(NSDictionary *settings, SXProvider provider) {
	NSString *fallback = settings[SXChatKey(provider, @"FallbackModel")];
	return fallback.length && ![fallback isEqual:SXChatModel(settings, provider)] ? fallback : @"";
}
NSString *SXChatIssue(NSDictionary *settings, SXProvider provider) {
	if (provider == SXProviderCustom && !SXHTTPSURL(SXChatBase(settings, provider))) return @"Nhập địa chỉ API HTTPS trong Cấu hình Tự chỉnh.";
	if (![settings[SXChatKey(provider, @"Key")] length]) return [NSString stringWithFormat:@"Nhập khóa API trong Cấu hình %@.", SXProviderName(provider)];
	if (!SXChatModel(settings, provider).length) return @"Nhập mã mô hình mà máy chủ API hỗ trợ.";
	return nil;
}

NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *SXMediaProfiles(NSString *kind) {
	static NSDictionary *profiles;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		profiles = @{
			@"stt": @{
				@"groq": @{@"key": @"sttGroqKey", @"model": @"sttGroqModel"},
				@"openai": @{@"key": @"sttOpenAIKey", @"model": @"sttOpenAIModel"},
				@"gemini": @{@"key": @"sttGeminiKey", @"model": @"sttGeminiModel"},
				@"custom": @{@"key": @"sttCustomKey", @"model": @"sttCustomModel"},
				@"auto-custom": @{@"model": @"sttAutoCustomModel"},
			},
			@"tts": @{
				@"system": @{@"voice": @"ttsSystemVoice"},
				@"google": @{@"key": @"ttsGoogleKey", @"voice": @"ttsGoogleVoice"},
				@"gemini": @{@"key": @"ttsGeminiKey", @"model": @"ttsGeminiModel", @"voice": @"ttsGeminiVoice"},
				@"custom": @{@"key": @"ttsCustomKey", @"model": @"ttsCustomModel", @"voice": @"ttsCustomVoice"},
			},
		};
	});
	return profiles[kind] ?: @{};
}
static NSString *SXMediaValue(NSDictionary *settings, NSDictionary *fields, NSString *field) {
	NSString *key = fields[field];
	return (key ? settings[key] : nil) ?: @"";
}
NSString *SXSTTEffectiveSource(NSDictionary *settings) {
	NSString *source = settings[@"sttSource"] ?: @"auto";
	return [source isEqual:@"auto"] ? SXProviderID(SXProviderFromID(settings[@"provider"])) : source;
}
BOOL SXSTTUsesFixedEnglishModel(NSDictionary *settings) {
	if (![settings[@"sttTranslate"] isEqual:@"en"]) return NO;
	NSString *source = SXSTTEffectiveSource(settings);
	return [source isEqual:@"openai"] || [source isEqual:@"groq"];
}
NSDictionary<NSString *, NSString *> *SXSTTFields(NSDictionary *settings) {
	BOOL automatic = [(settings[@"sttSource"] ?: @"auto") isEqual:@"auto"];
	NSString *source = SXSTTEffectiveSource(settings);
	NSDictionary *profiles = SXMediaProfiles(@"stt");
	if (automatic && [source isEqual:@"custom"]) return profiles[@"auto-custom"];
	NSDictionary *fields = profiles[source] ?: @{};
	return automatic && fields[@"model"] ? @{@"model": fields[@"model"]} : fields;
}
NSDictionary<NSString *, NSString *> *SXSTTConfiguration(NSDictionary *settings) {
	BOOL automatic = [(settings[@"sttSource"] ?: @"auto") isEqual:@"auto"];
	NSString *source = SXSTTEffectiveSource(settings);
	SXProvider provider = SXProviderFromID(source);
	NSDictionary *fields = SXSTTFields(settings);
	if (!fields[@"model"]) return @{@"source": source, @"issue": @"Chọn nguồn nhận diện giọng nói trong Cài đặt."};
	NSString *base = provider == SXProviderCustom && !automatic ? (settings[@"sttBaseUrl"] ?: @"") : SXChatBase(settings, provider);
	NSString *key = SXMediaValue(settings, fields, @"key");
	// Named sources may reuse only their own AI key. Explicit custom STT never
	// takes a key from a separate profile, even if the host happens to match.
	if (!key.length && (automatic || provider != SXProviderCustom)) key = settings[SXChatKey(provider, @"Key")] ?: @"";
	BOOL english = [settings[@"sttTranslate"] isEqual:@"en"];
	NSString *defaultModel = provider == SXProviderGemini ? @"gemini-2.5-flash" : @"whisper-1";
	if (provider == SXProviderGroq) defaultModel = english ? @"whisper-large-v3" : @"whisper-large-v3-turbo";
	NSString *model = SXMediaValue(settings, fields, @"model");
	NSMutableDictionary *config = [@{@"source": source, @"base": base, @"key": key,
		@"model": model.length && !SXSTTUsesFixedEnglishModel(settings) ? model : defaultModel, @"defaultModel": defaultModel} mutableCopy];
	if (!SXHTTPSURL(base)) config[@"issue"] = automatic ? @"Nguồn STT đang dùng địa chỉ của AI. Hãy nhập địa chỉ trong Cấu hình Tự chỉnh hoặc chọn nguồn STT riêng." : @"Nhập địa chỉ HTTPS trong Cấu hình STT.";
	else if (!key.length && provider != SXProviderCustom) config[@"issue"] = [NSString stringWithFormat:@"Chưa có khóa %@ cho STT. %@", SXProviderName(provider), automatic ? @"Nhập khóa trong cấu hình nhà cung cấp AI." : @"Nhập khóa trong Cấu hình STT hoặc cấu hình AI cùng nhà cung cấp."];
	else if ([settings[@"sttTranslate"] isEqual:@"vi"] && SXChatIssue(settings, SXProviderFromID(settings[@"provider"]))) config[@"issue"] = @"Dịch sang tiếng Việt cần cấu hình nhà cung cấp AI đang chọn.";
	return config;
}

BOOL SXTTSModeAllows(NSString *mode, BOOL answer) {
	return [mode isEqual:@"all"] || [mode isEqual:(answer ? @"ai" : @"errors")];
}
NSString *SXTTSEffectiveSource(NSDictionary *settings) {
	NSString *mode = settings[@"ttsMode"] ?: @"ai";
	if ([mode isEqual:@"off"]) return @"off";
	if ([mode isEqual:@"errors"] || [settings[@"incognito"] boolValue]) return @"system";
	return settings[@"ttsSource"] ?: @"system";
}
NSDictionary<NSString *, NSString *> *SXTTSConfiguration(NSDictionary *settings) {
	NSString *source = SXTTSEffectiveSource(settings);
	NSDictionary *fields = SXMediaProfiles(@"tts")[source];
	NSString *key = SXMediaValue(settings, fields, @"key");
	NSString *base = @"", *defaultModel = @"";
	if ([source isEqual:@"gemini"]) {
		if (!key.length) key = settings[@"geminiKey"] ?: @"";
		base = SXGeminiBaseURL; defaultModel = @"gemini-2.5-flash-preview-tts";
	} else if ([source isEqual:@"google"]) {
		base = @"https://texttospeech.googleapis.com/v1/text:synthesize";
	} else if ([source isEqual:@"custom"]) {
		base = settings[@"ttsBaseUrl"] ?: @""; defaultModel = @"tts-1";
	}
	NSString *model = SXMediaValue(settings, fields, @"model");
	NSMutableDictionary *config = [@{@"source": source, @"base": base, @"key": key, @"voice": SXMediaValue(settings, fields, @"voice"),
		@"model": model.length ? model : defaultModel, @"defaultModel": defaultModel} mutableCopy];
	if ([source isEqual:@"custom"] && !SXHTTPSURL(base)) config[@"issue"] = @"Nhập địa chỉ HTTPS trong Cấu hình TTS.";
	else if ([source isEqual:@"google"] && !key.length) config[@"issue"] = @"Nhập khóa Google Cloud Text-to-Speech trong Cấu hình TTS.";
	else if ([source isEqual:@"gemini"] && !key.length) config[@"issue"] = @"Nhập khóa trong Cấu hình TTS hoặc Cấu hình Gemini.";
	return config;
}
