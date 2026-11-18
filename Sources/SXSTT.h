#import "SXPrefs.h"
#import "SXNetwork.h"

NS_ASSUME_NONNULL_BEGIN
/// Cancellable STT + optional translation; runs on a worker and never stores audio.
FOUNDATION_EXPORT NSString * _Nullable SXTranscribe(NSData *wav, SXPrefs *prefs, SXRequest *request);
NS_ASSUME_NONNULL_END
