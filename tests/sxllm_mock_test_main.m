// Tiện ích chung cho test SXLLM: lớp kết quả HTTP giả có thể tạo trực tiếp và
// một SXTools tối giản (test không kéo theo catalog UIKit).
#import <Foundation/Foundation.h>
#import "SXHTTP.h"
#import "SXTools.h"

@implementation SXTools
+ (NSArray<NSDictionary *> *)definitions { return @[]; }
+ (NSDictionary *)execute:(NSString *)name arguments:(NSDictionary *)arguments error:(NSError **)error {
	(void)name; (void)arguments; (void)error;
	return nil;
}
+ (NSString *)promptBrief { return @""; }
+ (void)beginTurn { }
+ (NSArray<SXTool *> *)catalog { return @[]; }
@end
