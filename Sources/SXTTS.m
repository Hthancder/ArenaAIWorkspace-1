#import "SXTTS.h"
#import "SXMediaFormat.h"
#import "SXLog.h"
#import <AVFoundation/AVFoundation.h>

@interface SXTTSPlan ()
@property (nonatomic, copy) NSString *text, *language, *voice;
@property (nonatomic, copy) NSData *audio;
@property (nonatomic) float speed, volume;
@end
@implementation SXTTSPlan
@end

BOOL SXTTSModeAllows(NSString *mode, BOOL answer) {
	return [mode isEqualToString:@"all"] || [mode isEqualToString:(answer ? @"ai" : @"errors")];
}
static NSString *SXTTSLanguage(NSString *text, SXPrefs *prefs) {
	NSString *language = prefs.ttsLang;
	if ([language isEqual:@"auto"] || !language.length) {
		NSString *fallback = [NSLocale.currentLocale.languageCode isEqual:@"en"] ? @"en" : @"vi";
		language = SXDetectedLanguage(text, fallback);
	}
	return [language isEqual:@"en"] ? @"en-US" : @"vi-VN";
}
SXTTSPlan *SXTTSSystemPlan(NSString *text, SXPrefs *prefs) {
	if (!text.length) return nil;
	SXTTSPlan *plan = [SXTTSPlan new];
	plan.text = text;
	plan.language = SXTTSLanguage(text, prefs);
	plan.voice = [prefs.ttsSource isEqual:@"system"] ? prefs.ttsVoice : @"";
	plan.speed = prefs.ttsSpeed;
	plan.volume = prefs.ttsVolume / 100.f;
	return plan;
}
static NSArray *SXVoiceItems(NSArray<NSString *> *ids) {
	NSMutableArray *result = [NSMutableArray array];
	for (NSString *voice in ids) [result addObject:@{@"id": voice, @"name": voice}];
	return result;
}
NSArray<NSDictionary *> *SXTTSVoices(SXPrefs *prefs) {
	if ([prefs.ttsSource isEqual:@"system"]) {
		NSMutableArray *result = [NSMutableArray array];
		for (AVSpeechSynthesisVoice *voice in AVSpeechSynthesisVoice.speechVoices) {
			if (![prefs.ttsLang isEqual:@"auto"] && ![voice.language hasPrefix:[prefs.ttsLang stringByAppendingString:@"-"]]) continue;
			[result addObject:@{@"id": voice.identifier, @"name": [NSString stringWithFormat:@"%@ · %@", voice.name, voice.language]}];
		}
		return [result sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)]]];
	}
	if ([prefs.ttsSource isEqual:@"gemini"]) return SXVoiceItems(@[@"Kore", @"Puck", @"Zephyr", @"Aoede", @"Charon", @"Fenrir", @"Leda", @"Orus"]);
	if ([prefs.ttsSource isEqual:@"google"]) {
		NSMutableArray *ids = [NSMutableArray array];
		for (NSString *lang in @[@"vi-VN", @"en-US"]) {
			if (![prefs.ttsLang isEqual:@"auto"] && ![lang hasPrefix:prefs.ttsLang]) continue;
			for (NSString *slot in @[@"A", @"B", @"C", @"D"]) [ids addObject:[NSString stringWithFormat:@"%@-Standard-%@", lang, slot]];
		}
		return SXVoiceItems(ids);
	}
	return SXVoiceItems(@[@"alloy", @"ash", @"coral", @"echo", @"fable", @"nova", @"onyx", @"sage", @"shimmer"]);
}
static NSData *SXTTSFetch(NSString *url, NSDictionary *body, NSDictionary *headers, SXRequest *budget) {
	NSMutableURLRequest *post = SXJSONRequest(url, body, headers);
	if (!post) return nil;
	NSError *error = nil;
	NSDictionary *response = SXHTTP(post, budget, 3 * 1024 * 1024, &error);
	NSInteger status = [response[@"status"] integerValue];
	if (status >= 200 && status < 300) return response[@"data"];
	SXLogDbg(@"tts", @"provider không sẵn sàng (HTTP %ld, mạng %ld).", (long)status, (long)error.code);
	return nil;
}
static NSDictionary *SXAudioJSON(NSData *data) {
	id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
	return [json isKindOfClass:NSDictionary.class] ? json : nil;
}
static NSData *SXDecodeAudio(id raw) { return [raw isKindOfClass:NSString.class] ? [[NSData alloc] initWithBase64EncodedString:raw options:0] : nil; }
static NSData *SXGeminiAudio(NSData *data) {
	id candidates = SXAudioJSON(data)[@"candidates"];
	id first = [candidates isKindOfClass:NSArray.class] ? [candidates firstObject] : nil;
	id content = [first isKindOfClass:NSDictionary.class] ? first[@"content"] : nil;
	id parts = [content isKindOfClass:NSDictionary.class] ? content[@"parts"] : nil;
	if (![parts isKindOfClass:NSArray.class]) return nil;
	NSMutableData *pcm = [NSMutableData data];
	NSUInteger rate = 0;
	for (id part in parts) {
		if (![part isKindOfClass:NSDictionary.class]) continue;
		id inlineData = part[@"inlineData"] ?: part[@"inline_data"];
		if (![inlineData isKindOfClass:NSDictionary.class]) continue;
		NSData *bytes = SXDecodeAudio(inlineData[@"data"]);
		id mime = inlineData[@"mimeType"] ?: inlineData[@"mime_type"];
		if (![mime isKindOfClass:NSString.class] || ![[mime lowercaseString] hasPrefix:@"audio/l16"] || !bytes.length || bytes.length % 2) continue;
		NSUInteger sampleRate = 24000;
		for (NSString *parameter in [mime componentsSeparatedByString:@";"]) {
			NSString *value = [parameter stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
			if ([value hasPrefix:@"rate="]) sampleRate = (NSUInteger)[[value substringFromIndex:5] integerValue];
		}
		if (sampleRate < 8000 || sampleRate > 96000 || (rate && sampleRate != rate)) return nil;
		rate = sampleRate;
		[pcm appendData:bytes];
	}
	return SXPCM16WAV(pcm, (uint32_t)rate);
}
SXTTSPlan *SXTTSPrepare(NSString *text, SXPrefs *prefs, SXRequest *request) {
	SXTTSPlan *plan = SXTTSSystemPlan(text, prefs);
	if (!plan || [prefs.ttsSource isEqual:@"system"]) return plan;
	if (!request || request.remaining <= 0 || prefs.localOnly || prefs.incognito || SXDefinitelyOffline()) return nil;
	NSData *audio = nil;
	NSString *voice = prefs.ttsVoice;
	if ([prefs.ttsSource isEqual:@"gemini"]) {
		NSString *key = prefs.ttsApiKey.length ? prefs.ttsApiKey : prefs.geminiKey;
		NSString *url = SXGeminiEndpoint(prefs.ttsModel.length ? prefs.ttsModel : @"gemini-2.5-flash-preview-tts", NO);
		if (!url || !key.length) return nil;
		NSDictionary *generation = @{@"responseModalities": @[@"AUDIO"], @"speechConfig": @{@"voiceConfig":
			@{@"prebuiltVoiceConfig": @{@"voiceName": voice.length ? voice : @"Kore"}}}};
		NSString *instruction = [NSString stringWithFormat:@"Read aloud verbatim in %@. Only say the text after the next newline.\n%@", plan.language, text];
		audio = SXGeminiAudio(SXTTSFetch(url, @{@"contents": @[@{@"parts": @[@{@"text": instruction}]}], @"generationConfig": generation}, @{@"x-goog-api-key": key}, request));
	} else if ([prefs.ttsSource isEqual:@"google"]) {
		if (!prefs.ttsApiKey.length) return nil;
		if (![voice hasPrefix:plan.language]) voice = [plan.language stringByAppendingString:@"-Standard-A"];
		audio = SXDecodeAudio(SXAudioJSON(SXTTSFetch(@"https://texttospeech.googleapis.com/v1/text:synthesize",
			@{@"input": @{@"text": text}, @"voice": @{@"languageCode": plan.language, @"name": voice},
				@"audioConfig": @{@"audioEncoding": @"MP3"}}, @{@"x-goog-api-key": prefs.ttsApiKey}, request))[@"audioContent"]);
	} else if ([prefs.ttsSource isEqual:@"custom"]) {
		NSString *url = SXEndpoint(prefs.ttsBaseUrl, @"/audio/speech");
		NSDictionary *headers = prefs.ttsApiKey.length ? @{@"Authorization": [@"Bearer " stringByAppendingString:prefs.ttsApiKey]} : @{};
		audio = SXTTSFetch(url, @{@"model": prefs.ttsModel.length ? prefs.ttsModel : @"tts-1", @"voice": voice.length ? voice : @"alloy",
			@"input": text, @"response_format": @"mp3"}, headers, request);
	}
	if (!audio.length || request.remaining <= 0) return nil;
	// Validate before emptying Apple's speech field, not after forwarding the ACE object.
	AVAudioPlayer *probe = [[AVAudioPlayer alloc] initWithData:audio error:NULL];
	if (!probe || probe.duration <= 0) return nil;
	plan.audio = audio;
	return plan;
}

@interface SXSpeechPlayer : NSObject <AVAudioPlayerDelegate>
@property (nonatomic, strong) AVSpeechSynthesizer *synth;
@property (nonatomic, strong) AVAudioPlayer *player;
@property (nonatomic, strong) SXTTSPlan *plan;
@property (nonatomic, copy) void (^result)(BOOL);
- (BOOL)speakPlan:(SXTTSPlan *)plan;
@end
@implementation SXSpeechPlayer
- (BOOL)speakPlan:(SXTTSPlan *)plan {
	@try {
		AVSpeechSynthesisVoice *voice = plan.voice.length ? [AVSpeechSynthesisVoice voiceWithIdentifier:plan.voice] : nil;
		if (![voice.language hasPrefix:[plan.language substringToIndex:2]]) voice = [AVSpeechSynthesisVoice voiceWithLanguage:plan.language];
		AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:plan.text];
		utterance.voice = voice;
		utterance.rate = MAX(AVSpeechUtteranceMinimumSpeechRate, MIN(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * plan.speed));
		utterance.volume = plan.volume;
		self.synth = [AVSpeechSynthesizer new];
		self.synth.usesApplicationAudioSession = NO;
		[self.synth speakUtterance:utterance];
		return YES;
	} @catch (NSException *exception) {
		SXLogWrn(@"tts", @"không phát được âm thanh (%@).", exception.name); return NO;
	}
}
- (void)finishPlayer:(AVAudioPlayer *)player success:(BOOL)success {
	// Audio delegates should run on main; this also avoids racing a generation stop.
	dispatch_async(dispatch_get_main_queue(), ^{
		if (player != self.player) return;
		SXTTSPlan *plan = self.plan;
		void (^result)(BOOL) = self.result;
		self.result = nil; self.plan = nil; self.player = nil;
		if (!success && plan) [self speakPlan:plan];
		if (result) result(success);
	});
}
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag { [self finishPlayer:player success:flag]; }
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error { (void)error; [self finishPlayer:player success:NO]; }
@end
static SXSpeechPlayer *SXPlayer(void) {
	static SXSpeechPlayer *player;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ player = [SXSpeechPlayer new]; });
	return player;
}
void SXTTSStop(void) {
	SXSpeechPlayer *owner = SXPlayer();
	owner.player.delegate = nil;
	[owner.player stop]; owner.player = nil; owner.plan = nil; owner.result = nil;
	[owner.synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate]; owner.synth = nil;
}
void SXTTSPlay(SXTTSPlan *plan, void (^result)(BOOL)) {
	SXTTSStop();
	SXSpeechPlayer *owner = SXPlayer();
	if (!plan.audio.length) { BOOL ok = [owner speakPlan:plan]; if (result) result(ok); return; }
	@try {
		owner.player = [[AVAudioPlayer alloc] initWithData:plan.audio error:NULL];
		owner.player.delegate = owner;
		owner.player.enableRate = YES;
		owner.player.rate = plan.speed;
		owner.player.volume = plan.volume;
		owner.plan = plan; owner.result = result;
		if ([owner.player play]) return;
	} @catch (NSException *ignored) { (void)ignored; }
	// Apple received a silent command based on the preflight. Do not reissue it.
	owner.player.delegate = nil; owner.player = nil; owner.plan = nil; owner.result = nil;
	[owner speakPlan:plan];
	if (result) result(NO);
}
