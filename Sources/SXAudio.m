#import "SXAudio.h"
#import "SXMediaFormat.h"
#import "SXLog.h"
#import <AVFoundation/AVFoundation.h>
#import <os/lock.h>
#include <math.h>
#include <stdatomic.h>
#include <stdint.h>

static dispatch_queue_t SXAudioQueue(void) {
	static dispatch_queue_t queue;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ queue = dispatch_queue_create("com.sirix.audio.capture", DISPATCH_QUEUE_SERIAL); });
	return queue;
}
@implementation SXAudioTap {
	AVAudioEngine *_engine; // audio queue only
	os_unfair_lock _samplesLock;
	NSMutableData *_samples;
	int16_t *_buffer;
	NSUInteger _count, _limit;
	double _phase, _sum;
	NSUInteger _bucketCount;
	atomic_bool _discarded, _stopping;
}
- (instancetype)initWithMaxSeconds:(NSUInteger)seconds {
	if ((self = [super init])) {
		_samplesLock = OS_UNFAIR_LOCK_INIT;
		_limit = MAX(3, MIN(seconds, 30)) * 16000;
		_samples = [NSMutableData dataWithLength:_limit * sizeof(int16_t)];
		_buffer = _samples.mutableBytes;
		atomic_init(&_discarded, false); atomic_init(&_stopping, false);
	}
	return self;
}
- (void)collect:(AVAudioPCMBuffer *)buffer rate:(double)rate {
	// No allocation, rescheduling or blocking the realtime render callback.
	if (atomic_load(&_stopping) || !buffer.floatChannelData || !os_unfair_lock_trylock(&_samplesLock)) return;
	const float *samples = buffer.floatChannelData[0];
	for (AVAudioFrameCount i = 0; i < buffer.frameLength && _count < _limit; i++) {
		float sample = samples[i];
		_sum += isfinite(sample) ? sample : 0;
		_bucketCount++;
		_phase += 16000;
		while (_phase >= rate && _count < _limit) {
			double avg = _bucketCount ? _sum / _bucketCount : sample;
			_buffer[_count++] = (int16_t)lrint(MAX(-1.0, MIN(1.0, isfinite(avg) ? avg : 0)) * 32767.0);
			_phase -= rate;
			_sum = 0; _bucketCount = 0;
		}
	}
	os_unfair_lock_unlock(&_samplesLock);
}
- (void)start {
	dispatch_async(SXAudioQueue(), ^{
		if (atomic_load(&self->_stopping) || self->_engine) return;
		if (AVAudioSession.sharedInstance.recordPermission != AVAudioSessionRecordPermissionGranted) {
			SXLogWrn(@"stt", @"mic denied — giữ nhận diện Apple (kiểm tra quyền Mic)."); return;
		}
		@try {
			AVAudioEngine *engine = [AVAudioEngine new];
			AVAudioInputNode *input = engine.inputNode;
			AVAudioFormat *format = [input outputFormatForBus:0];
			double rate = format.sampleRate;
			if (!input || !format.channelCount || rate < 8000 || rate > 192000 || format.commonFormat != AVAudioPCMFormatFloat32 || format.isInterleaved) {
				SXLogWrn(@"stt", @"không có định dạng mic phù hợp; dùng Apple."); return;
			}
			__weak SXAudioTap *weakSelf = self;
			[input installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *time) {
				(void)time; [weakSelf collect:buffer rate:rate];
			}];
			self->_engine = engine;
			if (![engine startAndReturnError:NULL]) { [self stopOnQueue]; SXLogWrn(@"stt", @"không mở được mic trong phiên Siri."); return; }
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self->_limit / 16000 * NSEC_PER_SEC)), SXAudioQueue(), ^{ [weakSelf stopOnQueue]; });
		} @catch (NSException *exception) {
			[self stopOnQueue]; SXLogWrn(@"stt", @"audio engine không khả dụng (%@).", exception.name);
		}
	});
}
- (void)stopOnQueue {
	atomic_store(&_stopping, true);
	AVAudioEngine *engine = _engine;
	_engine = nil;
	if (!engine) return;
	@try { [engine stop]; [engine.inputNode removeTapOnBus:0]; } @catch (NSException *ignored) { (void)ignored; }
}
- (void)stop {
	atomic_store(&_stopping, true);
	dispatch_async(SXAudioQueue(), ^{ [self stopOnQueue]; });
}
- (void)discard { atomic_store(&_discarded, true); [self stop]; }
- (NSData *)takeWAV {
	[self stop];
	if (atomic_load(&_discarded)) return nil;
	os_unfair_lock_lock(&_samplesLock);
	NSData *pcm = _count >= 2400 ? [NSData dataWithBytes:_buffer length:_count * sizeof(int16_t)] : nil;
	_count = 0;
	os_unfair_lock_unlock(&_samplesLock);
	return pcm ? SXPCM16WAV(pcm, 16000) : nil;
}
@end
