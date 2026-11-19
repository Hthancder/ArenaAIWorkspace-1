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
	// "retry": đang thử lại bằng model dự phòng ở luồng nền. Giữ Siri gốc để
	// hội thoại không bị chặn; đáp án tới sau hiện qua thông báo/Lịch sử.
	if ([timeoutAction isEqualToString:@"retry"]) return nil;
	// Mặc định: bubble
	return @"⏳ AI trả lời quá muộn — thử lại, hoặc tăng “Thời gian chờ AI” / đổi model nhanh hơn.";
}

+ (BOOL)shouldSendDeferredAnswerWhenEnabled:(BOOL)enabled privateTurn:(BOOL)privateTurn {
	return enabled && !privateTurn;
}

+ (void)logDecision:(NSString *)decision source:(NSString *)source {
	SXLogInf(@"resp", @"chính sách: %@ (%@)", decision, source);
}

@end
