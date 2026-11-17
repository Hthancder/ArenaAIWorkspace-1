// SBHistory.h — lịch sử hội thoại ngắn hạn (trong RAM, mất khi Siri đóng)
#import <Foundation/Foundation.h>

@interface SBHistory : NSObject
+ (instancetype)shared;
- (void)addUser:(NSString *)text;
- (void)addAssistant:(NSString *)text;
/// Trả về mảng message đã cắt theo historyTurns
- (NSArray<NSDictionary *> *)messages;
- (void)reset;
@end
