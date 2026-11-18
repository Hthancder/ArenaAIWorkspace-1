#import "SXConfigIO.h"
#import "SXMediaFormat.h"
#import "SXNative.h"
#import "SXNetwork.h"
#import "SXStream.h"
#import "SXLog.h"
#import "SXLLM.h"
#import "SXSTT.h"
#include <assert.h>
#include <string.h>

void SXLogWrite(SXLogLevel level, NSString *category, NSString *format, ...) { (void)level; (void)category; (void)format; }
void SXLogSetVerbose(BOOL value) { (void)value; }

@interface FakeSpeechToken : NSObject <NSCopying>
@property (nonatomic, copy) NSString *text;
@end
@implementation FakeSpeechToken
- (id)copyWithZone:(NSZone *)zone { (void)zone; FakeSpeechToken *o = [FakeSpeechToken new]; o.text = self.text; return o; }
@end
@interface FakeSpeech : NSObject <NSCopying>
@property (nonatomic, copy) NSArray *phrases, *interpretations, *tokens;
@property (nonatomic, strong) FakeSpeech *recognition;
@property (nonatomic, copy) NSString *refId, *intent;
@end
@implementation FakeSpeech
- (id)copyWithZone:(NSZone *)zone {
	(void)zone;
	FakeSpeech *o = [FakeSpeech new]; o.phrases = self.phrases; o.interpretations = self.interpretations;
	o.tokens = self.tokens; o.recognition = self.recognition; o.refId = self.refId; o.intent = self.intent;
	return o;
}
@end
@interface FakeSpeechPayload : NSObject
@property (nonatomic, copy) NSArray *dialogStrings, *aceAudioData;
@end
@implementation FakeSpeechPayload
@end
@interface SAUIAssistantUtteranceView : NSObject <NSCopying>
@property (nonatomic, copy) NSString *aceId, *text, *speakableText;
@end
@implementation SAUIAssistantUtteranceView
- (id)copyWithZone:(NSZone *)zone {
	(void)zone; SAUIAssistantUtteranceView *item = [SAUIAssistantUtteranceView new];
	item.aceId = self.aceId; item.text = self.text; item.speakableText = self.speakableText; return item;
}
@end
@interface SAUIUpdateViews : NSObject
@property (nonatomic, copy) NSString *refId, *aceId;
@property (nonatomic, copy) NSArray *views;
@end
@implementation SAUIUpdateViews
@end
@interface FakeConversation : NSObject
@property (nonatomic) BOOL hasView;
@property (nonatomic, strong) SAUIUpdateViews *last;
@end
@implementation FakeConversation
- (BOOL)containsItemForAceViewWithIdentifier:(NSString *)identifier { return self.hasView && [identifier isEqual:@"existing-view"]; }
- (void)updateWithUpdateViewsCommand:(SAUIUpdateViews *)command { self.last = command; }
@end

// No fixture request ever escapes to a real host, even if routing regresses.
static NSDictionary *expectedRoute;
static NSData *fixtureBody(NSURLRequest *request) {
	if (request.HTTPBody) return request.HTTPBody;
	NSInputStream *stream = request.HTTPBodyStream;
	[stream open];
	NSMutableData *data = [NSMutableData data];
	uint8_t buffer[4096];
	NSInteger size;
	while ((size = [stream read:buffer maxLength:sizeof(buffer)]) > 0) [data appendBytes:buffer length:(NSUInteger)size];
	[stream close];
	return data;
}
@interface SXFixtureProtocol : NSURLProtocol
@end
@implementation SXFixtureProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { (void)request; return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
	id<NSURLProtocolClient> client = self.client;
	NSString *path = self.request.URL.path;
	NSDictionary *route = expectedRoute;
	BOOL http = route || [path isEqual:@"/http"];
	if (route) {
		assert([self.request.URL.host isEqual:route[@"host"]] && [path isEqual:route[@"path"]]);
		assert([self.request.HTTPMethod isEqual:@"POST"]);
		assert([[self.request valueForHTTPHeaderField:route[@"header"]] isEqual:route[@"key"]]);
		if (route[@"bodyModel"]) {
			id json = [NSJSONSerialization JSONObjectWithData:fixtureBody(self.request) options:0 error:NULL];
			assert([json isKindOfClass:NSDictionary.class] && [json[@"model"] isEqual:route[@"bodyModel"]]);
		}
		if (route[@"speechModel"]) {
			NSString *form = [[NSString alloc] initWithData:fixtureBody(self.request) encoding:NSUTF8StringEncoding];
			assert(([form containsString:[NSString stringWithFormat:@"name=\"model\"\r\n\r\n%@\r\n", route[@"speechModel"]]]));
			assert(![form containsString:@"name=\"language\""]);
		}
	} else assert([self.request.URL.host isEqual:@"test.sirix.invalid"]);
	NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1"
		headerFields:@{@"Content-Type": http ? @"application/json" : @"text/event-stream"}];
	[client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
	NSString *payload = route[@"response"] ?: @"{\"ok\":true}";
	if ([path isEqual:@"/delta"]) payload = @"data: {\"choices\":[{\"delta\":{\"content\":\"Chào\"}}]}\r\n\r\ndata: {\"choices\":[{\"delta\":{\"content\":\" bạn\"}}]}\n\ndata: [DONE]\n\n";
	else if ([path isEqual:@"/tool"]) payload = @"data: {\"choices\":[{\"delta\":{\"tool_calls\":[{}]}}]}\n\n";
	else if ([path isEqual:@"/gemini"]) payload = @"data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"thought\",\"thought\":true},{\"text\":\"answer\"}]}}]}\n\n";
	NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
	if ([path isEqual:@"/delta"]) {
		NSUInteger i = [data rangeOfData:[@"à" dataUsingEncoding:NSUTF8StringEncoding] options:0 range:NSMakeRange(0, data.length)].location + 1;
		[client URLProtocol:self didLoadData:[data subdataWithRange:NSMakeRange(0, i)]];
		[client URLProtocol:self didLoadData:[data subdataWithRange:NSMakeRange(i, data.length - i)]];
	} else [client URLProtocol:self didLoadData:data];
	[client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

static NSData *JSON(NSInteger version, NSDictionary *settings) {
	return [NSJSONSerialization dataWithJSONObject:@{@"version": @(version), @"settings": settings} options:0 error:NULL];
}
static NSMutableDictionary *settingsWith(NSDictionary *changes) {
	NSMutableDictionary *settings = [SXConfigDefaults() mutableCopy];
	[settings addEntriesFromDictionary:changes];
	return settings;
}
static void testConfig(void) {
	NSMutableDictionary *current = settingsWith(@{@"customBase": @"https://old.invalid/v1", @"customModel": @"private-model",
		@"sttBaseUrl": @"https://speech.invalid/v1", @"ttsBaseUrl": @"https://voice.invalid/v1"});
	NSUInteger secrets = 0;
	for (NSString *key in current.allKeys) if ([key hasSuffix:@"Key"]) { current[key] = @"test-placeholder"; secrets++; }
	assert(secrets >= 10);
	NSError *error = nil;
	NSData *data = SXExportConfig(current, NO, &error);
	assert(data && !error);
	id exported = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
	assert([exported[@"version"] isEqual:@2]);
	for (NSString *key in current) if ([key hasSuffix:@"Key"]) assert([exported[@"settings"][key] isEqual:@"***"]);
	assert(![[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] containsString:@"test-placeholder"]);
	NSDictionary *same = SXImportConfig(data, current, &error);
	assert(same && [same[@"set"] count] == 0 && [same[@"remove"] count] == 0);
	NSData *withKeys = SXExportConfig(current, YES, &error);
	assert([SXImportConfig(withKeys, SXConfigDefaults(), &error)[@"set"] count] == secrets + 4);

	NSDictionary *edits = @{@"provider": @"groq", @"sttSource": @"groq", @"ttsSource": @"google"};
	NSDictionary *plan = SXConfigChangePlan(current, edits);
	assert([plan[@"set"] count] == 3 && [plan[@"remove"] count] == 0);
	assert([SXImportConfig(JSON(2, edits), current, &error) isEqual:plan]);
	edits = @{@"customBase": @"https://new.invalid/v1", @"sttBaseUrl": @"https://next.invalid/api", @"ttsBaseUrl": @"https://voice-next.invalid/v1"};
	plan = SXImportConfig(JSON(2, edits), current, &error);
	assert(([[NSSet setWithArray:plan[@"remove"]] isEqual:[NSSet setWithArray:@[@"customKey", @"sttCustomKey", @"ttsCustomKey"]]]));
	NSDictionary *direct = SXConfigChangePlan(current, edits);
	assert([direct[@"set"] isEqual:plan[@"set"]] && [[NSSet setWithArray:direct[@"remove"]] isEqual:[NSSet setWithArray:plan[@"remove"]]]);
	plan = SXImportConfig(JSON(2, @{@"customBase": @"https://new.invalid/v1", @"customKey": @"***"}), current, &error);
	assert([plan[@"remove"] isEqual:@[@"customKey"]]);
	plan = SXImportConfig(JSON(2, @{@"customBase": @"https://new.invalid/v1", @"customKey": current[@"customKey"]}), current, &error);
	assert([plan[@"remove"] count] == 0); // explicit key in confirmed document, even if unchanged

	assert(!SXImportConfig(JSON(2, @{@"customBase": @"https://bad.invalid/v1?secret=value"}), current, &error) && error);
	assert(!SXImportConfig(JSON(2, @{@"openaiBase": @"https://bad.invalid/v1"}), current, &error));
	assert(!SXImportConfig(JSON(2, @{@"sttEnabled": @1}), current, &error));
	assert(!SXImportConfig(JSON(2, @{@"sttMaxSec": @31}), current, &error));
	assert(!SXImportConfig(JSON(2, @{@"somethingUnknownKey": @"***"}), current, &error));
	assert([SXConfigValue(@"sttLanguage", @"") isEqual:@"auto"] && [SXConfigValue(@"sttLanguage", @"VI") isEqual:@"vi"]);
	assert([SXConfigValue(@"geminiModel", @"models/gemini-2.5-flash") isEqual:@"gemini-2.5-flash"]);
	assert(!SXConfigValue(@"ttsGeminiModel", @"../not-a-model"));
	assert([SXEndpoint(@"https://new.invalid/v1/chat/completions", @"/audio/speech") isEqual:@"https://new.invalid/v1/audio/speech"]);
	assert(!SXHTTPSURL(@"ftp://example.com/a") && !SXHTTPSURL(@"https://user:pass@example.com") && !SXGeminiEndpoint(@"../not-a-model", NO));
}
static void testLegacyProfiles(void) {
	NSDictionary *legacy = @{@"provider": @"openai", @"openaiBase": @"https://API.groq.com:443/openai/v1/chat/completions/", @"openaiKey": @"old-groq",
		@"openaiModel": @"my-groq-model", @"openaiFallbackModel": @"my-groq-fallback", @"sttSource": @"auto", @"sttApiKey": @"old-unused",
		@"sttModel": @"whisper-large-v3", @"ttsMode": @"off", @"ttsSource": @"google", @"ttsApiKey": @"old-google", @"ttsModel": @"unused-model", @"ttsVoice": @"vi-VN-Standard-B"};
	NSDictionary *result = SXUpgradeLegacyConfig(legacy);
	assert([result[@"provider"] isEqual:@"groq"] && [result[@"groqKey"] isEqual:@"old-groq"] && !result[@"openaiKey"] && !result[@"openaiBase"]);
	assert([result[@"groqModel"] isEqual:@"my-groq-model"] && [result[@"groqFallbackModel"] isEqual:@"my-groq-fallback"]);
	assert([result[@"sttGroqModel"] isEqual:@"whisper-large-v3"] && !result[@"sttGroqKey"] && !result[@"sttApiKey"]);
	assert([result[@"ttsGoogleKey"] isEqual:@"old-google"] && [result[@"ttsGoogleVoice"] isEqual:@"vi-VN-Standard-B"] && !result[@"ttsModel"]);
	assert([SXUpgradeLegacyConfig(result) isEqual:result]);
	NSError *error = nil;
	NSDictionary *current = settingsWith(@{@"openaiKey": @"existing-openai", @"groqKey": @"existing-groq"});
	NSDictionary *imported = SXImportConfig(JSON(1, legacy), current, &error)[@"set"];
	assert(imported && !error && !imported[@"openaiKey"]);
	for (NSString *key in result) assert([(imported[key] ?: current[key]) isEqual:result[key]]);
	NSMutableDictionary *masked = [legacy mutableCopy]; masked[@"openaiKey"] = @"***";
	NSDictionary *plan = SXImportConfig(JSON(1, masked), current, &error);
	assert([plan[@"remove"] count] == 0 && !plan[@"set"][@"openaiKey"] && !plan[@"set"][@"groqKey"]);

	result = SXUpgradeLegacyConfig(@{@"provider": @"gemini", @"openaiBase": @"https://proxy.invalid/openai/v1", @"openaiKey": @"proxy-key",
		@"sttSource": @"off", @"sttEnabled": @YES, @"ttsVoice": @"my-system-voice"});
	assert([result[@"provider"] isEqual:@"gemini"] && [result[@"customKey"] isEqual:@"proxy-key"] && !result[@"openaiKey"]);
	assert([result[@"customBase"] isEqual:@"https://proxy.invalid/openai/v1"] && [result[@"customModel"] isEqual:@"gpt-4o-mini"]);
	assert([result[@"sttSource"] isEqual:@"auto"] && [result[@"sttEnabled"] isEqual:@NO] && [result[@"ttsSystemVoice"] isEqual:@"my-system-voice"]);
	for (NSString *base in @[@"", @"http://api.openai.com/v1", @"https://api.openai.com:8443/v1", @"https://api.groq.com/other/v1"]) {
		result = SXUpgradeLegacyConfig(@{@"provider": @"openai", @"openaiBase": base, @"openaiKey": @"not-preset"});
		assert([result[@"provider"] isEqual:@"custom"] && [result[@"customKey"] isEqual:@"not-preset"] && !result[@"groqKey"] && !result[@"openaiKey"]);
	}
	result = SXUpgradeLegacyConfig(@{@"openaiBase": @"https://api.openai.com/v1/", @"openaiKey": @"old-openai"});
	assert([result[@"openaiKey"] isEqual:@"old-openai"] && !result[@"customKey"]);
	plan = SXImportConfig(JSON(1, @{@"provider": @"openai", @"openaiBase": @"https://next.invalid/v1", @"openaiKey": @"***"}),
		settingsWith(@{@"customBase": @"https://old.invalid/v1", @"customKey": @"bound-key"}), &error);
	assert([plan[@"set"][@"provider"] isEqual:@"custom"] && [plan[@"remove"] isEqual:@[@"customKey"]]);
}
NSString *SXFixturePreferencesDomain(void) {
	static NSString *domain;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ domain = [@"com.sirix.tweak.fixture." stringByAppendingString:NSUUID.UUID.UUIDString]; });
	return domain;
}
static void testSavedMigration(void) {
	CFStringRef domain = (__bridge CFStringRef)SXFixturePreferencesDomain();
	NSDictionary *old = @{@"provider": @"openai", @"openaiBase": @"https://api.groq.com/openai/v1", @"openaiKey": @"saved-groq",
		@"openaiModel": @"saved-model", @"ttsSource": @"gemini", @"ttsVoice": @"Puck", @"sttSource": @"off", @"sttEnabled": @YES, @"speakErrors": @YES};
	CFPreferencesSetMultiple((__bridge CFDictionaryRef)old, NULL, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	assert(CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
	SXPrefs *prefs = [SXPrefs shared];
	[prefs reload];
	assert(prefs.provider == SXProviderGroq && !prefs.sttEnabled && [prefs.ttsMode isEqual:@"all"]);
	assert([prefs.settings[@"groqKey"] isEqual:@"saved-groq"] && ![prefs.settings[@"openaiKey"] length]);
	assert([prefs.settings[@"ttsGeminiVoice"] isEqual:@"Puck"]);
	assert(([SXPrefs writeValues:@{@"provider": @"openai", @"openaiKey": @"new-openai"} removing:@[]]));
	[prefs reload];
	assert(prefs.provider == SXProviderOpenAI && [prefs.settings[@"openaiKey"] isEqual:@"new-openai"]);
	assert([prefs.settings[@"groqKey"] isEqual:@"saved-groq"] && [prefs.settings[@"groqModel"] isEqual:@"saved-model"]);
	assert(!prefs.sttEnabled && [prefs.settings[@"ttsGeminiVoice"] isEqual:@"Puck"]);
	NSArray *keys = CFBridgingRelease(CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
	assert(![keys containsObject:@"openaiBase"] && ![keys containsObject:@"ttsVoice"]);
	CFPreferencesSetMultiple(NULL, (__bridge CFArrayRef)keys, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
	assert(CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
}
static NSArray *rows(NSString *pane, NSDictionary *settings) {
	NSString *path = [NSString stringWithFormat:@"Prefs/Resources/%@.plist", pane];
	NSArray *items = [NSDictionary dictionaryWithContentsOfFile:path][@"items"];
	assert(items.count);
	return [items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *row, NSDictionary *bindings) {
		(void)bindings; return SXConfigShowsRule(row[@"sxRule"], settings);
	}]];
}
static NSUInteger countRows(NSString *pane, NSString *property, NSString *value, NSDictionary *settings) {
	return [rows(pane, settings) filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"%K == %@", property, value]].count;
}
static void testSettingsPresentation(void) {
	NSMutableDictionary *settings = settingsWith(@{});
	NSArray *choices = [[rows(@"Root", settings) filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"key == 'provider'"]] firstObject][@"validValues"];
	assert([[NSSet setWithArray:choices] isEqual:[NSSet setWithArray:SXChatProviderIDs()]]);
	for (NSString *ID in SXChatProviderIDs()) {
		settings[@"provider"] = ID;
		assert(countRows(@"Root", @"detail", @"SXProviderConfigController", settings) == 1);
		assert(countRows(@"ProviderConfig", @"sxField", @"base", settings) == [ID isEqual:@"custom"]);
	}
	assert(!countRows(@"Root", @"key", @"sttSource", settings));
	settings[@"sttEnabled"] = @YES;
	for (NSString *source in @[@"auto", @"groq", @"openai", @"gemini", @"custom"]) {
		settings[@"sttSource"] = source;
		assert(countRows(@"STTConfig", @"key", @"sttBaseUrl", settings) == [source isEqual:@"custom"]);
		assert(countRows(@"STTConfig", @"sxField", @"key", settings) == ![source isEqual:@"auto"]);
	}
	settings[@"sttSource"] = @"groq"; settings[@"sttTranslate"] = @"en";
	assert(!countRows(@"STTConfig", @"key", @"sttLanguage", settings) && !countRows(@"STTConfig", @"sxField", @"model", settings));
	settings[@"sttSource"] = @"gemini";
	assert(countRows(@"STTConfig", @"key", @"sttLanguage", settings) && countRows(@"STTConfig", @"sxField", @"model", settings));

	for (NSString *source in @[@"system", @"google", @"gemini", @"custom"]) {
		settings[@"ttsSource"] = source;
		assert(countRows(@"Root", @"id", @"sx-tts-config", settings) == ![source isEqual:@"system"]);
		assert(countRows(@"Root", @"id", @"sx-voice-picker", settings) == ![source isEqual:@"custom"]);
		assert(countRows(@"TTSConfig", @"key", @"ttsBaseUrl", settings) == [source isEqual:@"custom"]);
		assert(countRows(@"TTSConfig", @"sxField", @"model", settings) == ([source isEqual:@"gemini"] || [source isEqual:@"custom"]));
		assert(countRows(@"TTSConfig", @"sxField", @"voice", settings) == [source isEqual:@"custom"]);
	}
	settings[@"ttsMode"] = @"off";
	assert(!countRows(@"Root", @"key", @"ttsSource", settings) && !countRows(@"Root", @"id", @"sx-voice-test", settings));
	settings[@"ttsMode"] = @"errors";
	assert(!countRows(@"Root", @"key", @"ttsSource", settings) && countRows(@"Root", @"id", @"sx-voice-picker", settings));
	assert([SXTTSEffectiveSource(settings) isEqual:@"system"]);
	settings[@"ttsMode"] = @"all"; settings[@"incognito"] = @YES;
	assert(!countRows(@"Root", @"key", @"ttsSource", settings) && !countRows(@"Root", @"key", @"deferredReplies", settings));
	assert(!countRows(@"Root", @"key", @"toolClipboard", settings) && [SXTTSEffectiveSource(settings) isEqual:@"system"]);
	settings[@"streaming"] = @NO;
	assert(!countRows(@"Root", @"key", @"liveSiriUpdates", settings));
	settings[@"incognito"] = @NO;
	assert(countRows(@"Root", @"key", @"liveSiriUpdates", settings)); // independent late-update path

	settings[@"provider"] = @"groq"; settings[@"timeoutAction"] = @"retry";
	for (NSString *mode in @[@"smart", @"full"]) for (NSString *fallback in @[@"", @"alternate", SXChatDefaultModel(SXProviderGroq)]) {
		settings[@"mode"] = mode; settings[@"groqFallbackModel"] = fallback;
		NSArray *visible = [rows(@"Root", settings) filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"key == 'timeoutAction'"]];
		assert(visible.count == ([mode isEqual:@"full"] || [fallback isEqual:@"alternate"]));
		if (visible.count) assert([visible.firstObject[@"validValues"] containsObject:SXEffectiveTimeoutAction(settings)]);
		assert([SXEffectiveTimeoutAction(settings) isEqual:@"retry"] == [fallback isEqual:@"alternate"]);
	}
}
static void testMediaProfiles(void) {
	NSMutableDictionary *settings = settingsWith(@{@"provider": @"groq", @"groqKey": @"groq-ai", @"openaiKey": @"openai-ai", @"geminiKey": @"gemini-ai",
		@"sttGroqKey": @"groq-stt", @"sttModel": @"stale", @"sttBaseUrl": @"https://speech.invalid/v1", @"customBase": @"https://proxy.invalid/v1",
		@"customKey": @"custom-ai", @"sttGroqModel": @"whisper-override", @"ttsGeminiVoice": @"Puck", @"ttsSystemVoice": @"system-voice",
		@"ttsGoogleKey": @"google-tts", @"ttsCustomKey": @"custom-tts", @"ttsBaseUrl": @"https://voice.invalid/v1"});
	NSDictionary *config = SXSTTConfiguration(settings);
	assert([config[@"base"] isEqual:@"https://api.groq.com/openai/v1"] && [config[@"key"] isEqual:@"groq-ai"] && [config[@"model"] isEqual:@"whisper-override"]);
	settings[@"sttSource"] = @"groq";
	assert([SXSTTConfiguration(settings)[@"key"] isEqual:@"groq-stt"]);
	settings[@"sttSource"] = @"openai";
	assert([SXSTTConfiguration(settings)[@"key"] isEqual:@"openai-ai"] && [SXSTTConfiguration(settings)[@"model"] isEqual:@"whisper-1"]);
	settings[@"sttSource"] = @"custom";
	assert([SXSTTConfiguration(settings)[@"base"] isEqual:@"https://speech.invalid/v1"] && [SXSTTConfiguration(settings)[@"key"] length] == 0);
	settings[@"sttSource"] = @"auto"; settings[@"provider"] = @"custom";
	assert([SXSTTConfiguration(settings)[@"base"] isEqual:@"https://proxy.invalid/v1"] && [SXSTTConfiguration(settings)[@"key"] isEqual:@"custom-ai"]);
	settings[@"ttsSource"] = @"gemini";
	assert([SXTTSConfiguration(settings)[@"key"] isEqual:@"gemini-ai"] && [SXTTSConfiguration(settings)[@"voice"] isEqual:@"Puck"]);
	settings[@"ttsSource"] = @"google";
	assert([SXTTSConfiguration(settings)[@"key"] isEqual:@"google-tts"] && [SXTTSConfiguration(settings)[@"model"] length] == 0);
	settings[@"ttsSource"] = @"custom";
	assert([SXTTSConfiguration(settings)[@"key"] isEqual:@"custom-tts"] && [SXTTSConfiguration(settings)[@"base"] isEqual:@"https://voice.invalid/v1"]);
	settings[@"incognito"] = @YES;
	assert([SXTTSConfiguration(settings)[@"voice"] isEqual:@"system-voice"] && [SXTTSConfiguration(settings)[@"key"] length] == 0);
}
static SXPrefs *prefsWith(NSDictionary *settings) {
	SXPrefs *prefs = [SXPrefs new];
	[prefs setValue:settings forKey:@"settings"];
	return [prefs snapshot];
}
static void testRequestRoutes(void) {
	NSMutableDictionary *settings = settingsWith(@{@"provider": @"groq", @"streaming": @NO, @"groqKey": @"fixture-groq", @"openaiKey": @"fixture-openai",
		@"geminiKey": @"fixture-gemini", @"customKey": @"fixture-custom", @"customBase": @"https://test.sirix.invalid/api/v1", @"customModel": @"test-custom-model",
		@"openaiBase": @"https://should-never-be-used.invalid/v1"});
	SXPrefs *snapshot = prefsWith(settings);
	NSArray *routes = @[
		@{@"host": @"api.openai.com", @"path": @"/v1/chat/completions", @"key": @"Bearer fixture-openai"},
		@{@"host": @"generativelanguage.googleapis.com", @"path": @"/v1beta/models/gemini-2.5-flash:generateContent", @"key": @"fixture-gemini"},
		@{@"host": @"api.groq.com", @"path": @"/openai/v1/chat/completions", @"key": @"Bearer fixture-groq"},
		@{@"host": @"test.sirix.invalid", @"path": @"/api/v1/chat/completions", @"key": @"Bearer fixture-custom"},
	];
	for (NSString *ID in SXChatProviderIDs()) {
		SXProvider provider = SXProviderFromID(ID);
		NSMutableDictionary *route = [routes[provider] mutableCopy];
		BOOL gemini = provider == SXProviderGemini;
		route[@"header"] = gemini ? @"x-goog-api-key" : @"Authorization";
		route[@"response"] = gemini ? @"{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"ok\"}]}}]}" : @"{\"choices\":[{\"message\":{\"content\":\"ok\"}}]}";
		NSString *model = provider == SXProviderGroq ? @"fixture-fallback" : nil;
		if (!gemini) route[@"bodyModel"] = model ?: SXChatModel(settings, provider);
		expectedRoute = route;
		[SXLLM performQuestion:@"fixture" history:@[] tools:@[] executor:nil prefs:snapshot provider:provider model:model prompt:nil maxTokens:0
			request:[[SXRequest alloc] initWithTimeout:5] progress:nil completion:^(NSString *answer, NSError *error, NSDictionary *info) {
				assert(!error && [answer isEqual:@"ok"] && [info[@"provider"] isEqual:ID]);
				assert([info[@"model"] isEqual:(model ?: SXChatModel(settings, provider))]);
			}];
		expectedRoute = nil;
	}
	settings[@"sttSource"] = @"groq"; settings[@"sttEnabled"] = @YES; settings[@"sttTranslate"] = @"en";
	settings[@"sttGroqKey"] = @"fixture-stt"; settings[@"sttGroqModel"] = @"whisper-large-v3-turbo";
	settings[@"sttBaseUrl"] = @"https://should-never-be-used.invalid/v1"; settings[@"sttLanguage"] = @"vi";
	expectedRoute = @{@"host": @"api.groq.com", @"path": @"/openai/v1/audio/translations", @"header": @"Authorization", @"key": @"Bearer fixture-stt",
		@"speechModel": @"whisper-large-v3", @"response": @"{\"text\":\"hello\"}"};
	int16_t pcm[] = { 0, 1, 0 };
	NSData *wav = SXPCM16WAV([NSData dataWithBytes:pcm length:sizeof(pcm)], 16000);
	assert([SXTranscribe(wav, prefsWith(settings), [[SXRequest alloc] initWithTimeout:5]) isEqual:@"hello"]);
	expectedRoute = nil;
}
static void testMediaAndNative(void) {
	int16_t pcm[] = {0, 123, -123};
	NSData *wav = SXPCM16WAV([NSData dataWithBytes:pcm length:sizeof(pcm)], 16000);
	const uint8_t *header = wav.bytes;
	assert(wav.length == 44 + sizeof(pcm) && !memcmp(header, "RIFF", 4) && !memcmp(header + 36, "data", 4));
	assert(header[22] == 1 && header[24] == 0x80 && header[25] == 0x3e && header[34] == 16);
	assert(!SXPCM16WAV([NSData dataWithBytes:pcm length:3], 16000));
	assert([SXDetectedLanguage(@"Xin chào, bạn!", @"en") isEqual:@"vi"]);
	assert([SXDetectedLanguage(@"How are you?", @"vi") isEqual:@"en"]);
	assert([SXDetectedLanguage(@"42", @"vi") isEqual:@"vi"]);
	assert(SXSystemUtterance(@"Đặt báo thức lúc 7 giờ") && SXBypassesAI(@"@siri how are you", @"auto"));
	assert(SXBypassesAI(@"@aim no", @"prefix") && !SXBypassesAI(@"@ai hello", @"prefix"));

	FakeSpeech *command = [FakeSpeech new], *root = [FakeSpeech new], *phrase = [FakeSpeech new], *meaning = [FakeSpeech new];
	FakeSpeechToken *token = [FakeSpeechToken new]; token.text = @"original";
	meaning.tokens = @[token]; phrase.interpretations = @[meaning]; root.phrases = @[phrase]; command.recognition = root;
	command.intent = @"original-intent"; command.refId = @"request";
	FakeSpeech *copy = SXTranscriptCopy(command, @"new transcript");
	FakeSpeech *copiedPhrase = copy.recognition.phrases.firstObject;
	FakeSpeech *copiedMeaning = copiedPhrase.interpretations.firstObject;
	FakeSpeechToken *updated = copiedMeaning.tokens.firstObject;
	assert(copy && copy != command && [updated.text isEqual:@"new transcript"] && [token.text isEqual:@"original"]);
	assert([copy.intent isEqual:command.intent] && [SXRefID(copy) isEqual:command.refId]);
	assert(!SXTranscriptCopy([NSObject new], @"new transcript"));

	FakeSpeechPayload *speech = [FakeSpeechPayload new]; speech.aceAudioData = @[@"audio"]; speech.dialogStrings = @[@"dialog"];
	assert(SXSilentPreSynthesis(speech) && !speech.aceAudioData.count && !speech.dialogStrings.count);
	SAUIAssistantUtteranceView *view = [SAUIAssistantUtteranceView new]; view.aceId = @"existing-view"; view.text = @"original";
	SAUIUpdateViews *source = [SAUIUpdateViews new]; source.refId = @"request"; source.views = @[view];
	FakeConversation *conversation = [FakeConversation new]; conversation.hasView = YES;
	SXNativeBubble *bubble = [SXNativeBubble bubbleInConversation:conversation command:source];
	assert([bubble updateText:@"partial"]);
	SAUIAssistantUtteranceView *rendered = conversation.last.views.firstObject;
	assert([rendered.text isEqual:@"partial"] && [view.text isEqual:@"original"] && [rendered.aceId isEqual:view.aceId]);
	conversation.hasView = NO;
	assert(![bubble updateText:@"after dismiss"]);
}
static void testNetwork(void) {
	SXRequest *request = [[SXRequest alloc] initWithTimeout:3 firstOutput:1];
	assert(request.remaining > 0 && request.remaining <= 1);
	[request markFirstOutput]; assert(request.remaining > 1.5);
	dispatch_semaphore_t ready = dispatch_semaphore_create(0), finished = dispatch_semaphore_create(0);
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
		dispatch_semaphore_signal(ready);
		assert(![request waitForCompletion:dispatch_semaphore_create(0)]);
		dispatch_semaphore_signal(finished);
	});
	assert(dispatch_semaphore_wait(ready, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0);
	[SXRequest setNetworkAllowed:NO];
	assert(request.cancelled && [[[SXRequest alloc] initWithTimeout:1] isCancelled]);
	assert(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0);
	[SXRequest setNetworkAllowed:YES];

	NSError *error = nil;
	NSDictionary *result = SXHTTP([NSURLRequest requestWithURL:[NSURL URLWithString:@"https://test.sirix.invalid/http"]],
		[[SXRequest alloc] initWithTimeout:5], 1024, &error);
	assert(!error && [result[@"status"] isEqual:@200]);
	assert(!SXHTTP([NSURLRequest requestWithURL:[NSURL URLWithString:@"https://test.sirix.invalid/http"]],
		[[SXRequest alloc] initWithTimeout:5], 2, &error) && error.code == NSURLErrorDataLengthExceedsMaximum);
	__block NSUInteger callbacks = 0;
	error = nil;
	NSDictionary *stream = [SXStream postJSON:@{} toURL:@"https://test.sirix.invalid/delta" headers:@{} format:SXStreamFormatOpenAI
		request:[[SXRequest alloc] initWithTimeout:6 firstOutput:4] progress:^(NSString *partial) {
			assert([partial hasPrefix:@"Chào"]); callbacks++;
		} error:&error];
	assert(!error && [stream[@"content"] isEqual:@"Chào bạn"] && callbacks >= 1 && [stream[@"firstTokenMs"] integerValue] >= 0);
	stream = [SXStream postJSON:@{} toURL:@"https://test.sirix.invalid/tool" headers:@{} format:SXStreamFormatOpenAI
		request:[[SXRequest alloc] initWithTimeout:5] progress:nil error:&error];
	assert(!error && [stream[@"sawToolCalls"] boolValue]);
	stream = [SXStream postJSON:@{} toURL:@"https://test.sirix.invalid/gemini" headers:@{} format:SXStreamFormatGemini
		request:[[SXRequest alloc] initWithTimeout:5] progress:nil error:&error];
	assert(!error && [stream[@"content"] isEqual:@"answer"]);
}
int main(void) {
	@autoreleasepool {
		testConfig(); testLegacyProfiles(); testSavedMigration(); testSettingsPresentation(); testMediaProfiles(); testRequestRoutes(); testMediaAndNative(); testNetwork();
		puts("v1.2 config migration, Settings gates, provider routing, media and SSE tests: OK");
	}
	return 0;
}
