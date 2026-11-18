#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// One recording, only in a user-initiated Siri speech request. No files.
@interface SXAudioTap : NSObject
- (instancetype)initWithMaxSeconds:(NSUInteger)seconds;
- (void)start;
- (void)stop;
- (void)discard;
- (nullable NSData *)takeWAV; // worker queue only; consumes the recording
@end
NS_ASSUME_NONNULL_END
