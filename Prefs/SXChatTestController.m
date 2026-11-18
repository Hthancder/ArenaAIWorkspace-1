#import "SXChatTestController.h"
#import "SXLLM.h"
#import "SXPrefs.h"
#import "SXMarkdown.h"
#import <UIKit/UIKit.h>

@interface SXChatTestController () <UITextFieldDelegate>
@property (nonatomic, strong) UITextView *conversation;
@property (nonatomic, strong) UITextField *input;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *turns;
@property (nonatomic, strong) SXRequest *request;
@end

@implementation SXChatTestController
- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Trò chuyện thử";
	self.view.backgroundColor = UIColor.systemBackgroundColor;
	self.turns = [NSMutableArray array];
	self.conversation = [UITextView new];
	self.conversation.editable = NO;
	self.conversation.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	self.conversation.adjustsFontForContentSizeCategory = YES;
	self.conversation.backgroundColor = UIColor.secondarySystemBackgroundColor;
	self.conversation.text = @"Thử cấu hình AI mà không cần mở Siri. Hội thoại thử chỉ lưu trong màn hình này; công cụ AI không được gọi.\n";
	self.input = [UITextField new];
	self.input.borderStyle = UITextBorderStyleRoundedRect;
	self.input.placeholder = @"Nhập câu hỏi";
	self.input.returnKeyType = UIReturnKeySend;
	self.input.delegate = self;
	self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[self.sendButton setTitle:@"Gửi" forState:UIControlStateNormal];
	[self.sendButton addTarget:self action:@selector(send) forControlEvents:UIControlEventTouchUpInside];
	UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[self.input, self.sendButton]];
	row.spacing = 8;
	self.conversation.translatesAutoresizingMaskIntoConstraints = NO;
	row.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:self.conversation];
	[self.view addSubview:row];
	[NSLayoutConstraint activateConstraints:@[
		[self.conversation.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
		[self.conversation.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12],
		[self.conversation.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
		[self.conversation.bottomAnchor constraintEqualToAnchor:row.topAnchor constant:-8],
		[row.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12],
		[row.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
		[row.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-8],
		[row.heightAnchor constraintGreaterThanOrEqualToConstant:40],
	]];
}
- (BOOL)textFieldShouldReturn:(UITextField *)field { (void)field; [self send]; return YES; }
- (void)append:(NSString *)text {
	self.conversation.text = [self.conversation.text stringByAppendingFormat:@"\n%@\n", text];
	if (self.conversation.text.length) [self.conversation scrollRangeToVisible:NSMakeRange(self.conversation.text.length - 1, 1)];
}
- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.request cancel]; self.request = nil; self.sendButton.enabled = YES;
}
- (void)send {
	NSString *question = [self.input.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (self.request || !question.length) return;
	[[SXPrefs shared] reload];
	SXPrefs *prefs = [[SXPrefs shared] snapshot];
	if (prefs.localOnly) { [self append:@"SiriX đang không gửi yêu cầu mạng."]; return; }
	NSString *issue = SXChatIssue(prefs.settings, prefs.provider);
	if (issue) { [self append:issue]; return; }
	SXRequest *request = [[SXRequest alloc] initWithTimeout:30 firstOutput:prefs.responseTimeout];
	self.request = request;
	self.sendButton.enabled = NO;
	self.input.text = @"";
	[self append:[@"Bạn: " stringByAppendingString:question]];
	NSString *before = self.conversation.text;
	NSArray *history = [self.turns copy];
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		[SXLLM performQuestion:question history:history tools:@[] executor:nil prefs:prefs provider:prefs.provider model:nil prompt:nil
			maxTokens:0 request:request progress:^(NSString *partial) {
				dispatch_async(dispatch_get_main_queue(), ^{
					typeof(self) self = weakSelf;
					if (self.request != request || request.cancelled) return;
					self.conversation.text = before;
					[self append:[@"SiriX: " stringByAppendingString:prefs.markdown ? SXMarkdownRender(partial) : partial]];
				});
			} completion:^(NSString *answer, NSError *error, NSDictionary *info) {
				(void)info;
				dispatch_async(dispatch_get_main_queue(), ^{
					typeof(self) self = weakSelf;
					if (self.request != request) return;
					self.request = nil; self.sendButton.enabled = YES;
					self.conversation.text = before;
					if (request.cancelled) { [self append:@"Đã hủy yêu cầu."]; return; }
					if (error) {
						NSString *message = [error.domain isEqual:NSURLErrorDomain] ? @"Không kết nối được hoặc API hết thời gian chờ." : error.localizedDescription;
						[self append:[@"⚠️ " stringByAppendingString:message]];
					} else if (answer.length) {
						[self.turns addObject:@{@"q": question, @"a": answer}];
						while ((NSInteger)self.turns.count > prefs.contextTurns) [self.turns removeObjectAtIndex:0];
						[self append:[@"SiriX: " stringByAppendingString:prefs.markdown ? SXMarkdownRender(answer) : answer]];
					}
				});
			}];
	});
}
@end
