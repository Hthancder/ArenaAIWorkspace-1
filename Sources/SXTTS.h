#import "SXPrefs.h"
#import "SXNetwork.h"

NS_ASSUME_NONNULL_BEGIN
@interface SXTTSPlan : NSObject
@end

/// Only returns a plan when playback can be attempted. On failure, leave Apple speech intact.
FOUNDATION_EXPORT SXTTSPlan * _Nullable SXTTSPrepare(NSString *text, SXPrefs *prefs, SXRequest * _Nullable network);
FOUNDATION_EXPORT SXTTSPlan * _Nullable SXTTSSystemPlan(NSString *text, SXPrefs *prefs);
FOUNDATION_EXPORT NSArray<NSDictionary *> *SXTTSVoices(SXPrefs *prefs);
/// Must run on main. Result: YES = selected output, NO = fallback/failed.
FOUNDATION_EXPORT void SXTTSPlay(SXTTSPlan *plan, void (^ _Nullable result)(BOOL));
FOUNDATION_EXPORT void SXTTSStop(void);
NS_ASSUME_NONNULL_END
