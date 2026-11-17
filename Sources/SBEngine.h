// SBEngine.h — điều phối một lượt hỏi-đáp
#import <Foundation/Foundation.h>

/// delegate thực tế là AFUISiriSession delegate (SRSiriViewController).
@interface SBEngine : NSObject
+ (instancetype)shared;

/// session: AFUISiriSession (dùng để lấy delegate / end).
- (void)handleTurnWithText:(NSString *)text
                   session:(id)session
                  delegate:(id)delegate;

- (void)cancel;
@property (nonatomic, readonly) BOOL busy;
@end
