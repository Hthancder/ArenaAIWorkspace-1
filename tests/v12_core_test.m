#import "SXConfigIO.h"
#import "SXMediaFormat.h"
#import "SXNative.h"
#import "SXNetwork.h"
#import "SXStream.h"
#import "SXLog.h"
#include <assert.h>
#include <string.h>

void SXLogWrite(SXLogLevel level, NSString *category, NSString *format, ...) { (void)level; (void)category; (void)format; }

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

@interface SXFixtureProtocol : NSURLProtocol
@end
@implementation SXFixtureProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [request.URL.host isEqual:@"test.sirix.invalid"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
	id<NSURLProtocolClient> client = self.client;
	NSString *path = self.request.URL.path;
	BOOL http = [path isEqual:@"/http"];
	NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1"
		headerFields:@{@"Content-Type": http ? @"application/json" : @"text/event-stream"}];
	[client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
	NSString *payload = @"{\"ok\":true}";
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

static NSData *JSON(NSDictionary *settings) {
	return [NSJSONSerialization dataWithJSONObject:@{@"version": @1, @"settings": settings} options:0 error:NULL];
}
static void testConfig(void) {
	NSMutableDictionary *current = [SXConfigDefaults() mutableCopy];
	current[@"openaiKey"] = @"test-placeholder-a"; current[@"geminiKey"] = @"test-placeholder-b";
	current[@"sttApiKey"] = @"test-placeholder-c"; current[@"ttsApiKey"] = @"test-placeholder-d";
	NSError *error = nil;
	NSData *data = SXExportConfig(current, NO, &error);
	assert(data && !error);
	NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	assert(![text containsString:@"test-placeholder"]);
	assert([text containsString:@"***"]);
	NSDictionary *same = SXImportConfig(data, current, &error);
	assert(same && [same[@"set"] count] == 0 && [same[@"remove"] count] == 0);
	NSData *withKeys = SXExportConfig(current, YES, &error);
	NSDictionary *clearSettings = SXConfigDefaults();
	assert([SXImportConfig(withKeys, clearSettings, &error)[@"set"] count] == 4);
	NSDictionary *changes = SXImportConfig(JSON(@{@"openaiBase": @"https://new.invalid/v1", @"openaiKey": @"***", @"ttsSource": @"google"}), current, &error);
	assert([changes[@"set"] count] == 2 && [changes[@"remove"] containsObject:@"openaiKey"] && [changes[@"remove"] containsObject:@"ttsApiKey"]);
	assert(!SXImportConfig(JSON(@{@"openaiBase": @"https://bad.invalid/v1?secret=value"}), current, &error) && error);
	assert(!SXImportConfig(JSON(@{@"sttEnabled": @1}), current, &error));
	assert(!SXImportConfig(JSON(@{@"sttMaxSec": @31}), current, &error));
	assert(!SXImportConfig(JSON(@{@"somethingUnknown": @"value"}), current, &error));
	assert([SXEndpoint(@"https://new.invalid/v1/chat/completions", @"/audio/speech") isEqual:@"https://new.invalid/v1/audio/speech"]);
	assert(!SXHTTPSURL(@"ftp://example.com/a") && !SXHTTPSURL(@"https://user:pass@example.com") && !SXGeminiEndpoint(@"../not-a-model", NO));
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
		testConfig(); testMediaAndNative(); testNetwork();
		puts("v1.2 config, media, native guards, cancellation and SSE tests: OK");
	}
	return 0;
}
