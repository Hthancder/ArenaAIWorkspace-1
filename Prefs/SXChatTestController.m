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
@property (nonatomic) BOOL busy;
@end

@implementation SXChatTestController
- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Trò chuyện thử";
	self.view.backgroundColor = UIColor.systemBackgroundColor;
	self.turns = [NSMutableArray array];
	self.conversation = [UITextView new];
	self.conversation.editable = NO;
	self.conversation.font = [UIFont systemFontOfSize:16];
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
- (void)send {
	NSString *question = [self.input.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (self.busy || !question.length) return;
	self.busy = YES;
	self.sendButton.enabled = NO;
	self.input.text = @"";
	[self append:[@"Bạn: " stringByAppendingString:question]];
	NSArray *history = [self.turns copy];
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		[SXLLM askQuestion:question history:history tools:@[] executor:nil completion:^(NSString *answer, NSError *error, NSDictionary *info) {
			(void)info;
			dispatch_async(dispatch_get_main_queue(), ^{
				typeof(self) strongSelf = weakSelf;
				if (!strongSelf) return;
				strongSelf.busy = NO;
				strongSelf.sendButton.enabled = YES;
				if (error) {
					[strongSelf append:[@"⚠️ " stringByAppendingString:error.localizedDescription]];
				} else if (answer.length) {
					[strongSelf.turns addObject:@{@"q": question, @"a": answer}];
					while ((NSInteger)strongSelf.turns.count > [SXPrefs shared].contextTurns) [strongSelf.turns removeObjectAtIndex:0];
					[strongSelf append:[@"SiriX: " stringByAppendingString:[SXPrefs shared].markdown ? SXMarkdownRender(answer) : answer]];
				}
			});
		}];
	});
}
@end
