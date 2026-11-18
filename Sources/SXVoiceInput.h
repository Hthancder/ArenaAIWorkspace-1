#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface SXVoiceInput : NSObject
+ (instancetype)shared;
- (void)begin:(id)owner;
- (void)endRecording:(id)owner;
- (void)cancel;
/// At most one upload per Siri turn. Unknown/late audio always returns Apple text.
- (NSString *)finalText:(NSString *)appleText owner:(nullable id)owner reference:(nullable NSString *)reference outcome:(NSString * _Nullable * _Nullable)outcome;
@end
NS_ASSUME_NONNULL_END
