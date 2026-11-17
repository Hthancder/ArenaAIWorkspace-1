#import "SBTTS.h"
#import "SBConfig.h"
#import <AVFoundation/AVFoundation.h>

#define SBLog(fmt, ...) NSLog(@"[SiriBridge] " fmt, ##__VA_ARGS__)

@interface SBTTS () <AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate>
@property (nonatomic, strong) AVSpeechSynthesizer *synth;
@property (nonatomic, strong) AVAudioPlayer     *player;
@property (nonatomic, copy)   void (^pending)(void);
@property (nonatomic, strong) NSURLSessionDataTask *task;
@end

@implementation SBTTS

+ (instancetype)shared {
    static SBTTS *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SBTTS new]; });
    return s;
}

- (id)init {
    if ((self = [super init])) {
        _synth = [AVSpeechSynthesizer new];
        _synth.delegate = self;
    }
    return self;
}

+ (NSArray<NSDictionary *> *)availableVoices {
    NSMutableArray *out = [NSMutableArray array];
    for (AVSpeechSynthesisVoice *v in [AVSpeechSynthesisVoice speechVoices]) {
        [out addObject:@{@"id": v.identifier ?: @"",
                         @"name": v.name ?: @"",
                         @"lang": v.language ?: @""}];
    }
    return out;
}

- (void)finish {
    void (^cb)(void) = self.pending;
    self.pending = nil;
    if (cb) cb();
}

- (void)configureAudioSession {
    AVAudioSession *s = [AVAudioSession sharedInstance];
    // Siri đang giữ .playAndRecord; đổi category có thể làm Siri mất micro.
    // Chỉ cần active + cho phép mix/duck.
    NSError *err = nil;
    [s setCategory:AVAudioSessionCategoryPlayAndRecord
              mode:AVAudioSessionModeDefault
           options:AVAudioSessionCategoryOptionDuckOthers | AVAudioSessionCategoryOptionAllowBluetooth
             error:&err];
    if (err) SBLog(@"audio category: %@", err.localizedDescription);
    [s setActive:YES error:&err];
    if (err) SBLog(@"audio active: %@", err.localizedDescription);
}

- (void)speak:(NSString *)text completion:(void (^)(void))completion {
    SBConfig *cfg = [SBConfig shared];
    if (!text.length) { if (completion) completion(); return; }
    self.pending = completion;

    if (cfg.ttsMode == 2) {          // để Siri tự đọc
        [self finish];
        return;
    }

    [self stop];

    if (cfg.ttsMode == 1) {          // TTS qua endpoint
        [self speakViaEndpoint:text cfg:cfg];
        return;
    }

    // mặc định: AVSpeechSynthesizer (on-device)
    [self configureAudioSession];
    AVSpeechUtterance *u = [AVSpeechUtterance speechUtteranceWithString:text];
    if (cfg.ttsVoiceID.length) {
        AVSpeechSynthesisVoice *v = [AVSpeechSynthesisVoice voiceWithIdentifier:cfg.ttsVoiceID];
        if (v) u.voice = v;
        else SBLog(@"voice không tồn tại: %@", cfg.ttsVoiceID);
    }
    if (!u.voice) {
        // chọn voice theo ngôn ngữ của Siri nếu có
        NSString *lang = [[NSLocale preferredLanguages] firstObject];
        u.voice = [AVSpeechSynthesisVoice voiceWithLanguage:lang];
    }
    u.rate    = cfg.ttsRate  > 0 ? cfg.ttsRate  : AVSpeechUtteranceDefaultSpeechRate;
    u.pitchMultiplier = cfg.ttsPitch > 0 ? cfg.ttsPitch : 1.0;
    u.volume  = cfg.ttsVolume > 0 ? cfg.ttsVolume : 1.0;
    [self.synth speakUtterance:u];
}

- (void)speakViaEndpoint:(NSString *)text cfg:(SBConfig *)cfg {
    NSString *tmpl = cfg.ttsBodyTemplate ?: @"";
    NSString *bodyStr = [tmpl stringByReplacingOccurrencesOfString:@"{{TEXT}}"
        withString:[self escape:text]];
    bodyStr = [bodyStr stringByReplacingOccurrencesOfString:@"{{VOICE}}"
        withString:[self escape:cfg.ttsRemoteVoice.length ? cfg.ttsRemoteVoice : @"alloy"]];
    NSURL *url = [NSURL URLWithString:cfg.ttsEndpoint];
    if (!url) { SBLog(@"TTS endpoint sai"); [self finish]; return; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 60;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (cfg.apiKey.length) [req setValue:[@"Bearer " stringByAppendingString:cfg.apiKey]
                      forHTTPHeaderField:@"Authorization"];
    id extra = [NSJSONSerialization JSONObjectWithData:[(cfg.ttsHeaders ?: @"{}") dataUsingEncoding:NSUTF8StringEncoding]
                                              options:0 error:NULL];
    if ([extra isKindOfClass:[NSDictionary class]])
        for (NSString *k in extra) if ([extra[k] isKindOfClass:[NSString class]])
            [req setValue:extra[k] forHTTPHeaderField:k];
    req.HTTPBody = [bodyStr dataUsingEncoding:NSUTF8StringEncoding];

    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
    self.task = [session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!data.length || err) { SBLog(@"TTS lỗi: %@", err.localizedDescription); [self finish]; return; }
        NSData *audio = data;
        if (!cfg.ttsResponseIsAudio) {          // JSON → base64 / url
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            NSString *path = cfg.ttsResponseField.length ? cfg.ttsResponseField : @"data";
            id v = json;
            for (NSString *p in [path componentsSeparatedByString:@"."]) v = v[p];
            if ([v isKindOfClass:[NSString class]]) {
                audio = [[NSData alloc] initWithBase64EncodedString:v options:0];
            }
            if (!audio.length) { SBLog(@"TTS: không lấy được audio"); [self finish]; return; }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self configureAudioSession];
            NSError *e = nil;
            self.player = [[AVAudioPlayer alloc] initWithData:audio error:&e];
            if (!self.player) { SBLog(@"AVAudioPlayer: %@", e.localizedDescription); [self finish]; return; }
            self.player.delegate = self;
            self.player.volume = cfg.ttsVolume > 0 ? cfg.ttsVolume : 1.0;
            [self.player play];
        });
    }];
    [self.task resume];
}

- (NSString *)escape:(NSString *)s {
    NSMutableString *o = [NSMutableString string];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '"' || c == '\\') [o appendFormat:@"\\%C", c];
        else if (c == '\n') [o appendString:@"\\n"];
        else if (c == '\r') [o appendString:@"\\r"];
        else if (c == '\t') [o appendString:@"\\t"];
        else if (c < 0x20) [o appendFormat:@"\\u%04x", c];
        else [o appendFormat:@"%C", c];
    }
    return o;
}

- (void)stop {
    [self.task cancel]; self.task = nil;
    if (self.synth.isSpeaking) [self.synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    if (self.player.isPlaying) [self.player stop];
    self.player = nil;
}

#pragma mark - AVSpeechSynthesizerDelegate

- (void)speechSynthesizer:(AVSpeechSynthesizer *)s didFinishSpeechUtterance:(AVSpeechUtterance *)u { [self finish]; }
- (void)speechSynthesizer:(AVSpeechSynthesizer *)s didCancelSpeechUtterance:(AVSpeechUtterance *)u { [self finish]; }

#pragma mark - AVAudioPlayerDelegate

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)p successfully:(BOOL)ok {
    self.player = nil;
    [self finish];
}
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)p error:(NSError *)error {
    SBLog(@"decode: %@", error.localizedDescription);
    self.player = nil;
    [self finish];
}

@end
