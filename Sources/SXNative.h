#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT BOOL SXSystemUtterance(NSString *text);
FOUNDATION_EXPORT BOOL SXBypassesAI(NSString *text, NSString *triggerMode);
FOUNDATION_EXPORT NSString * _Nullable SXRefID(id _Nullable command);
FOUNDATION_EXPORT id _Nullable SXTranscriptCopy(id original, NSString *text);
FOUNDATION_EXPORT BOOL SXSilentPreSynthesis(id command);

/// Optional native bubble updates (same conversation and existing view ID only).
@interface SXNativeBubble : NSObject
+ (nullable instancetype)bubbleInConversation:(id)conversation command:(id)command;
- (BOOL)updateText:(NSString *)text;
@end

FOUNDATION_EXPORT void SXRememberBulletinServer(id _Nullable server, dispatch_queue_t _Nullable queue);
/// Generic text only, opt-in. Returns whether the notification was submitted.
FOUNDATION_EXPORT BOOL SXNotifyHistory(void);
NS_ASSUME_NONNULL_END
