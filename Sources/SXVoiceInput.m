#import "SXVoiceInput.h"
#import "SXAudio.h"
#import "SXSTT.h"
#import "SXNative.h"
#import "SXLog.h"
#import "SXStore.h"

@implementation SXVoiceInput {
	NSCondition *_lock;
	__weak id _owner;
	SXAudioTap *_tap;
	SXPrefs *_prefs;
	SXRequest *_request;
	NSString *_appleText, *_ref, *_transcript;
	BOOL _done;
	uint64_t _generation;
	NSTimeInterval _started, _startedAt, _deadline;
}
+ (instancetype)shared {
	static SXVoiceInput *input;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ input = [SXVoiceInput new]; });
	return input;
}
- (instancetype)init { if ((self = [super init])) _lock = [NSCondition new]; return self; }
- (void)invalidateLocked {
	_generation++;
	[_tap discard]; [_request cancel];
	_tap = nil; _owner = nil; _request = nil; _prefs = nil; _transcript = nil; _appleText = nil; _ref = nil; _done = NO;
	[_lock broadcast];
}
- (void)begin:(id)owner {
	SXPrefs *prefs = [[SXPrefs shared] snapshot];
	NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
	[_lock lock];
	if (_owner == owner && _tap && now - _started < 0.3) { [_lock unlock]; return; }
	[self invalidateLocked];
	if (prefs.enabled && prefs.sttEnabled && !prefs.localOnly && ![prefs.sttSource isEqual:@"off"] && !SXDefinitelyOffline()) {
		_started = now; _startedAt = CFAbsoluteTimeGetCurrent();
		_owner = owner; _prefs = prefs;
		_tap = [[SXAudioTap alloc] initWithMaxSeconds:(NSUInteger)prefs.sttMaxSec];
		[_tap start];
	}
	[_lock unlock];
}
- (void)endRecording:(id)owner {
	[_lock lock]; if (_owner == owner) [_tap stop]; [_lock unlock];
}
- (void)cancel { [_lock lock]; [self invalidateLocked]; [_lock unlock]; }
- (NSString *)finalText:(NSString *)appleText owner:(id)owner reference:(NSString *)reference outcome:(NSString **)outcome {
	if (outcome) *outcome = nil;
	[_lock lock];
	NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
	if (!_tap || !_owner || (owner && owner != _owner) || now - _started > _prefs.sttMaxSec + 5 ||
		(_ref && reference && ![_ref isEqual:reference]) || (_appleText && [_appleText caseInsensitiveCompare:appleText] != NSOrderedSame && ![_ref isEqual:reference])) {
		[_lock unlock]; return appleText;
	}
	if (SXBypassesAI(appleText, _prefs.triggerMode)) {
		[self invalidateLocked]; [_lock unlock]; return appleText;
	}
	uint64_t generation = _generation;
	if (!_request) {
		_deadline = now + MIN(2.5, MAX(0.25, _prefs.sttWaitMs / 1000.0));
		_ref = reference; _appleText = appleText;
		SXAudioTap *tap = _tap;
		SXPrefs *prefs = _prefs;
		SXRequest *request = [[SXRequest alloc] initWithTimeout:_deadline - now];
		_request = request;
		NSTimeInterval startedAt = _startedAt;
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			// The trial is tied to a real Siri invocation; it never starts the mic.
			__block NSString *trial = nil;
			dispatch_sync([SXStore queue], ^{ trial = [[SXStore shared] claimSTTTrialStartedAt:startedAt]; });
			NSData *wav = [tap takeWAV];
			NSString *result = wav.length && request.remaining > 0 ? SXTranscribe(wav, prefs, request) : nil;
			[self->_lock lock];
			BOOL successful = generation == self->_generation && request.remaining > 0 && result.length;
			if (generation == self->_generation && !self->_done) {
				self->_transcript = request.remaining > 0 ? result : nil;
				self->_done = YES;
				[self->_lock broadcast];
			}
			[self->_lock unlock];
			if (trial) dispatch_async([SXStore queue], ^{ [[SXStore shared] finishSTTTrial:trial success:successful]; });
		});
	}
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:MAX(0, _deadline - now)];
	while (!_done && generation == _generation) if (![_lock waitUntilDate:deadline]) break;
	if (generation != _generation) { [_lock unlock]; return appleText; }
	if (!_done) { [_request cancel]; _done = YES; }
	NSString *result = _transcript;
	// Never let a recognizer-generated prefix activate SiriX or override @siri.
	if (result && SXBypassesAI(result, @"auto")) result = nil;
	if (result && [_prefs.triggerMode isEqual:@"prefix"] && SXBypassesAI(result, @"prefix")) result = [@"@ai " stringByAppendingString:result];
	if (outcome) *outcome = result ? @"stt_ok" : @"stt_fb";
	[_lock unlock];
	SXLogDbg(@"stt", @"final=%@", result ? @"stt" : @"apple-fallback");
	return result ?: appleText;
}
@end
