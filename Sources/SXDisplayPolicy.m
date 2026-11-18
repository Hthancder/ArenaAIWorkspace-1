#import "SXDisplayPolicy.h"
#import "SXLog.h"

@implementation SXDisplayPolicy

+ (BOOL)shouldShowErrorBubbleInMode:(SXReplyMode)mode speakErrors:(BOOL)speakErrors {
	if (mode == SXReplyModeFull) return YES;
	return speakErrors;
}

+ (NSString *)timeoutBubbleMessageInMode:(SXReplyMode)mode action:(NSString *)timeoutAction {
	if (mode != SXReplyModeFull) return nil; // Thông minh: giữ Siri gốc
	if ([timeoutAction isEqualToString:@"keep"]) return nil;
	// Mặc định: bubble
	return @"⏳ AI trả lời quá muộn — thử lại, hoặc tăng “Thời gian chờ AI” / đổi model nhanh hơn.";
}

+ (void)logDecision:(NSString *)decision source:(NSString *)source {
	SXLogInf(@"resp", @"chính sách: %@ (%@)", decision, source);
}

@end
