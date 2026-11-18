#import "SXNative.h"
#import "SXLog.h"
#import <objc/message.h>

static BOOL SXHasLeadingWord(NSString *text, NSString *word) {
	return [text isEqual:word] || ([text hasPrefix:word] && text.length > word.length &&
		[NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:[text characterAtIndex:word.length]]);
}
static NSString *SXNormalized(NSString *text) {
	return [[[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] precomposedStringWithCanonicalMapping] lowercaseString];
}
BOOL SXSystemUtterance(NSString *text) {
	NSString *normalized = SXNormalized(text);
	if (SXHasLeadingWord(normalized, @"@ai")) normalized = SXNormalized([normalized substringFromIndex:3]);
	static NSArray *actions;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ actions = @[@"set an alarm", @"set alarm", @"set a timer", @"start a timer", @"stop the timer", @"cancel my alarm",
		@"call", @"phone", @"text", @"send a message", @"facetime", @"open", @"remind me", @"play music", @"turn on", @"turn off", @"navigate to",
		@"đặt báo thức", @"tạo báo thức", @"hẹn giờ", @"đặt hẹn giờ", @"đặt bộ hẹn giờ", @"tắt báo thức", @"gọi", @"nhắn tin", @"gửi tin nhắn",
		@"mở ứng dụng", @"mở app", @"nhắc tôi", @"phát nhạc", @"dẫn đường", @"bật đèn pin", @"tắt đèn pin", @"bật bluetooth", @"tắt bluetooth"]; });
	for (NSString *action in actions) if (SXHasLeadingWord(normalized, action)) return YES;
	return NO;
}
BOOL SXBypassesAI(NSString *text, NSString *triggerMode) {
	NSString *lower = SXNormalized(text);
	return !lower.length || [lower isEqual:@"@ai"] || SXHasLeadingWord(lower, @"@siri") || SXSystemUtterance(lower) ||
		([triggerMode isEqual:@"prefix"] && (!SXHasLeadingWord(lower, @"@ai") || lower.length == 3));
}
static id SXGetObj(id object, NSString *name) {
	SEL selector = NSSelectorFromString(name);
	NSMethodSignature *sig = [object methodSignatureForSelector:selector];
	if (sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') return nil;
	return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}
static BOOL SXSetObj(id object, NSString *name, id value) {
	SEL selector = NSSelectorFromString(name);
	NSMethodSignature *sig = [object methodSignatureForSelector:selector];
	if (sig.numberOfArguments != 3 || sig.methodReturnType[0] != 'v' || [sig getArgumentTypeAtIndex:2][0] != '@') return NO;
	((void (*)(id, SEL, id))objc_msgSend)(object, selector, value);
	return YES;
}
static id SXDetachedCopy(id object) {
	id copy = [object respondsToSelector:@selector(copyWithZone:)] ? [object copy] : nil;
	return copy != object && [copy class] == [object class] ? copy : nil;
}
static id SXFirst(id items) { return [items isKindOfClass:NSArray.class] ? [items firstObject] : nil; }
NSString *SXRefID(id command) {
	@try {
		id ref = SXGetObj(command, @"refId");
		return [ref isKindOfClass:NSString.class] && [ref length] ? ref : nil;
	} @catch (NSException *ignored) { (void)ignored; return nil; }
}
id SXTranscriptCopy(id original, NSString *text) {
	if (!original || !text.length) return nil;
	@try {
		id command = SXDetachedCopy(original);
		if (!command) return nil;
		id wrapper = SXGetObj(original, @"recognition");
		id root = wrapper ? SXDetachedCopy(wrapper) : command;
		if (!root) return nil;
		id phrase = SXDetachedCopy(SXFirst(SXGetObj(root, @"phrases")));
		id interpretation = SXDetachedCopy(SXFirst(SXGetObj(phrase, @"interpretations")));
		id token = SXDetachedCopy(SXFirst(SXGetObj(interpretation, @"tokens")));
		if (!SXSetObj(token, @"setText:", text) || ![SXGetObj(token, @"text") isEqual:text] ||
			!SXSetObj(interpretation, @"setTokens:", @[token]) || !SXSetObj(phrase, @"setInterpretations:", @[interpretation]) ||
			!SXSetObj(root, @"setPhrases:", @[phrase]) || (wrapper && !SXSetObj(command, @"setRecognition:", root))) return nil;
		if ([command respondsToSelector:NSSelectorFromString(@"af_bestTextInterpretation")] && ![SXGetObj(command, @"af_bestTextInterpretation") isEqual:text]) {
			// Some ACE versions prefer the precomputed utterance over the phrases.
			if (!SXSetObj(root, @"setUtterances:", @[]) || ![SXGetObj(command, @"af_bestTextInterpretation") isEqual:text]) return nil;
		}
		return command;
	} @catch (NSException *ignored) { (void)ignored; return nil; }
}
BOOL SXSilentPreSynthesis(id command) {
	// Preserve the command and original reply handshake, clear only speech payload.
	id strings = nil, audio = nil;
	BOOL touched = NO;
	@try {
		strings = SXGetObj(command, @"dialogStrings"); audio = SXGetObj(command, @"aceAudioData");
		if (![command respondsToSelector:@selector(dialogStrings)] || ![command respondsToSelector:@selector(aceAudioData)]) return NO;
		touched = YES;
		if (SXSetObj(command, @"setDialogStrings:", @[]) && SXSetObj(command, @"setAceAudioData:", @[]) &&
			[SXGetObj(command, @"dialogStrings") isEqual:@[]] && [SXGetObj(command, @"aceAudioData") isEqual:@[]]) return YES;
	} @catch (NSException *ignored) { (void)ignored; }
	if (touched) {
		@try { SXSetObj(command, @"setDialogStrings:", strings); } @catch (NSException *ignored) { (void)ignored; }
		@try { SXSetObj(command, @"setAceAudioData:", audio); } @catch (NSException *ignored) { (void)ignored; }
	}
	return NO;
}

@implementation SXNativeBubble {
	__weak id _conversation;
	id _view;
	NSString *_viewID, *_ref;
}
+ (instancetype)bubbleInConversation:(id)conversation command:(id)command {
	if (!NSThread.isMainThread || ![conversation respondsToSelector:NSSelectorFromString(@"updateWithUpdateViewsCommand:")] ||
		![conversation respondsToSelector:NSSelectorFromString(@"containsItemForAceViewWithIdentifier:")] || !NSClassFromString(@"SAUIUpdateViews")) return nil;
	@try {
		NSString *ref = SXRefID(command);
		id views = SXGetObj(command, @"views");
		if (!ref.length || ![views isKindOfClass:NSArray.class]) return nil;
		Class utterance = NSClassFromString(@"SAUIAssistantUtteranceView");
		for (id view in views) {
			if (![view isKindOfClass:utterance]) continue;
			id identifier = SXGetObj(view, @"aceId");
			id copy = SXDetachedCopy(view);
			if (![identifier isKindOfClass:NSString.class] || ![identifier length] || !copy) continue;
			SXNativeBubble *target = [self new];
			target->_view = copy; target->_conversation = conversation; target->_viewID = [identifier copy]; target->_ref = ref;
			return target;
		}
	} @catch (NSException *ignored) { (void)ignored; }
	return nil;
}
- (BOOL)updateText:(NSString *)text {
	id conversation = _conversation;
	if (!NSThread.isMainThread || !conversation || !text.length) return NO;
	@try {
		SEL contains = NSSelectorFromString(@"containsItemForAceViewWithIdentifier:");
		NSMethodSignature *sig = [conversation methodSignatureForSelector:contains];
		if (sig.numberOfArguments != 3 || (sig.methodReturnType[0] != 'B' && sig.methodReturnType[0] != 'c') ||
			![conversation respondsToSelector:contains] || !((BOOL (*)(id, SEL, id))objc_msgSend)(conversation, contains, _viewID)) return NO;
		id view = SXDetachedCopy(_view);
		id update = [NSClassFromString(@"SAUIUpdateViews") new];
		if (!SXSetObj(view, @"setText:", text) || !SXSetObj(view, @"setSpeakableText:", @"") ||
			!SXSetObj(update, @"setViews:", @[view])) return NO;
		if (!SXSetObj(update, @"setRefId:", _ref) || !SXSetObj(update, @"setAceId:", NSUUID.UUID.UUIDString)) return NO;
		return SXSetObj(conversation, @"updateWithUpdateViewsCommand:", update);
	} @catch (NSException *ignored) { (void)ignored; return NO; }
}
@end

static __weak id SXBBServer;
static dispatch_queue_t SXBBQueue;
void SXRememberBulletinServer(id server, dispatch_queue_t queue) {
	if (!server || !queue) return;
	@synchronized (SXNativeBubble.class) { SXBBServer = server; SXBBQueue = queue; }
}
BOOL SXNotifyHistory(void) {
	id server;
	dispatch_queue_t queue;
	@synchronized (SXNativeBubble.class) { server = SXBBServer; queue = SXBBQueue; }
	SEL publish = NSSelectorFromString(@"publishBulletin:destinations:");
	if (!server || !queue || ![server respondsToSelector:publish]) return NO;
	dispatch_async(queue, ^{
		@try {
			id bulletin = [NSClassFromString(@"BBBulletin") new];
			NSString *identifier = NSUUID.UUID.UUIDString;
			NSURL *url = [NSURL URLWithString:@"prefs:root=SiriX&path=sx-history"];
			SEL launch = NSSelectorFromString(@"actionWithLaunchURL:");
			Class action = NSClassFromString(@"BBAction");
			if (![action respondsToSelector:launch]) return;
			id open = ((id (*)(id, SEL, id))objc_msgSend)(action, launch, url);
			if (!open || !SXSetObj(bulletin, @"setSectionID:", @"com.apple.Preferences") || !SXSetObj(bulletin, @"setDefaultAction:", open)) return;
			SXSetObj(bulletin, @"setTitle:", @"SiriX đã trả lời");
			SXSetObj(bulletin, @"setMessage:", @"Mở Lịch sử hội thoại để xem câu trả lời.");
			SXSetObj(bulletin, @"setBulletinID:", identifier);
			SXSetObj(bulletin, @"setRecordID:", identifier);
			SXSetObj(bulletin, @"setPublisherBulletinID:", identifier);
			SXSetObj(bulletin, @"setDate:", NSDate.date);
			SXSetObj(bulletin, @"setExpirationDate:", [NSDate dateWithTimeIntervalSinceNow:300]);
			NSMethodSignature *signature = [server methodSignatureForSelector:publish];
			if (signature.numberOfArguments != 4 || signature.methodReturnType[0] != 'v' || [signature getArgumentTypeAtIndex:3][0] != 'Q') return;
			((void (*)(id, SEL, id, unsigned long long))objc_msgSend)(server, publish, bulletin, 4 /* banner */);
		} @catch (NSException *ignored) { (void)ignored; SXLogWrn(@"resp", @"thông báo không khả dụng; đáp án ở Lịch sử."); }
	});
	return YES;
}
