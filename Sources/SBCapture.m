#import "SBCapture.h"

static NSString *gTurnText = nil;
static __weak id gSink = nil;
static NSLock *gLock = nil;

static NSLock *SBLock(void) {
    static dispatch_once_t once; dispatch_once(&once, ^{ gLock = [NSLock new]; });
    return gLock;
}

// Phần này phải chịu được cả ACE thật (có class) và NSDictionary (khi decode từ JSON).
static id SBGetValue(id obj, NSString *key) {
    if (!obj) return nil;
    @try {
        if ([obj isKindOfClass:[NSDictionary class]]) return obj[key];
        if ([obj respondsToSelector:NSSelectorFromString(key)]) return [obj valueForKey:key];
    } @catch (__unused NSException *e) {}
    return nil;
}

NSString *SBCaptureTextFromSpeechRecognized(id recognized) {
    if (!recognized) return nil;
    @try {
        // 1) recognition.utterances[].text  (SASUtterance)
        id rec = SBGetValue(recognized, @"recognition");
        for (id utt in (SBGetValue(rec, @"utterances") ?: @[])) {
            NSString *t = SBGetValue(utt, @"text");
            if ([t isKindOfClass:[NSString class]] && t.length) return t;
        }
        // 2) recognition.phrases[].interpretations[].tokens[]  (SASPhrase / SASInterpretation / SASToken)
        for (id phrase in (SBGetValue(rec, @"phrases") ?: @[])) {
            for (id interp in (SBGetValue(phrase, @"interpretations") ?: @[])) {
                NSMutableString *buf = [NSMutableString string];
                for (id tok in (SBGetValue(interp, @"tokens") ?: @[])) {
                    NSString *t = SBGetValue(tok, @"text");
                    if ([t isKindOfClass:[NSString class]]) {
                        if (buf.length && ![t hasPrefix:@"'"] && ![t hasPrefix:@"-"]) [buf appendString:@" "];
                        [buf appendString:t];
                    }
                }
                if (buf.length) return buf;
            }
        }
        // 3) title / refId fallback (một số locale để text ở title)
        NSString *title = SBGetValue(recognized, @"title");
        if ([title isKindOfClass:[NSString class]] && title.length) return title;
    } @catch (__unused NSException *e) {}
    return nil;
}

NSString *SBCaptureTextFromRequestOptions(id options) {
    NSString *t = SBGetValue(options, @"text");
    return [t isKindOfClass:[NSString class]] ? t : nil;
}

void SBCaptureRememberTurnText(NSString *text) {
    [SBLock() lock];
    gTurnText = [text copy];
    [SBLock() unlock];
}

NSString *SBCaptureCurrentTurnText(void) {
    [SBLock() lock];
    NSString *t = gTurnText;
    [SBLock() unlock];
    return t;
}

void SBCaptureClearTurn(void) {
    [SBLock() lock];
    gTurnText = nil;
    gSink = nil;
    [SBLock() unlock];
}

void SBCaptureSetAnswerSink(id sink) {
    [SBLock() lock];
    gSink = sink;
    [SBLock() unlock];
}

id SBCaptureAnswerSink(void) {
    [SBLock() lock];
    id s = gSink;
    [SBLock() unlock];
    return s;
}
