#import "SXChatTestController.h"
#import "SXLLM.h"
#import "SXPrefs.h"
#import "SXMarkdown.h"
#import "SXUISupport.h"
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, SXChatRole) {
	SXChatRoleUser = 0,
	SXChatRoleAssistant,
	SXChatRoleError,
	SXChatRoleTyping,
};

@interface SXChatMessage : NSObject
@property (nonatomic) SXChatRole role;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSDate *date;
@end

@implementation SXChatMessage
@end

#pragma mark - Bong bóng

@interface SXChatBubbleCell : UITableViewCell
- (void)configureWithMessage:(SXChatMessage *)message;
@end

@implementation SXChatBubbleCell {
	UIView *_bubble;
	UILabel *_label;
	UILabel *_meta;
	UIStackView *_stack;
	NSLayoutConstraint *_leadingConstraint;
	NSLayoutConstraint *_trailingConstraint;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self) return nil;

	self.selectionStyle = UITableViewCellSelectionStyleNone;
	self.backgroundColor = UIColor.clearColor;
	self.contentView.backgroundColor = UIColor.clearColor;

	_bubble = [[UIView alloc] init];
	_bubble.translatesAutoresizingMaskIntoConstraints = NO;
	_bubble.layer.cornerRadius = 16;
	if (@available(iOS 13.0, *)) _bubble.layer.cornerCurve = kCACornerCurveContinuous;

	_label = [[UILabel alloc] init];
	_label.numberOfLines = 0;
	_label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	_label.translatesAutoresizingMaskIntoConstraints = NO;

	_meta = [[UILabel alloc] init];
	_meta.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
	_meta.numberOfLines = 1;

	_stack = [[UIStackView alloc] initWithArrangedSubviews:@[_label, _meta]];
	_stack.axis = UILayoutConstraintAxisVertical;
	_stack.spacing = 3;
	_stack.translatesAutoresizingMaskIntoConstraints = NO;

	[_bubble addSubview:_stack];
	[self.contentView addSubview:_bubble];

	[NSLayoutConstraint activateConstraints:@[
		[_stack.topAnchor constraintEqualToAnchor:_bubble.topAnchor constant:10],
		[_stack.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:-10],
		[_stack.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:13],
		[_stack.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-13],
		[_bubble.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
		[_bubble.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],
		[_bubble.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.82],
	]];

	_leadingConstraint = [_bubble.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14];
	_trailingConstraint = [_bubble.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14];
	_trailingConstraint.active = YES;
	return self;
}

- (void)configureWithMessage:(SXChatMessage *)message {
	BOOL fromUser = (message.role == SXChatRoleUser);
	_leadingConstraint.active = fromUser;
	_trailingConstraint.active = !fromUser;

	_label.text = message.text;
	_label.textColor = fromUser ? UIColor.whiteColor : UIColor.labelColor;

	switch (message.role) {
		case SXChatRoleUser:
			_bubble.backgroundColor = [SXUI accentColor];
			break;
		case SXChatRoleAssistant:
			_bubble.backgroundColor = UIColor.secondarySystemBackgroundColor;
			break;
		case SXChatRoleError:
			_bubble.backgroundColor = [[SXUI dangerColor] colorWithAlphaComponent:0.14];
			_label.textColor = [SXUI dangerColor];
			break;
		case SXChatRoleTyping:
			_bubble.backgroundColor = UIColor.secondarySystemBackgroundColor;
			_label.textColor = UIColor.secondaryLabelColor;
			break;
	}
	if (message.role == SXChatRoleTyping) {
		_label.font = [UIFont italicSystemFontOfSize:15];
	} else {
		_label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	}

	NSString *meta = (message.role == SXChatRoleError || message.role == SXChatRoleTyping)
		? @""
		: [SXUI relativeStringForDate:message.date];
	_meta.text = meta;
	_meta.hidden = meta.length == 0;
	_meta.textColor = fromUser ? [UIColor.whiteColor colorWithAlphaComponent:0.7] : UIColor.tertiaryLabelColor;
}

@end

#pragma mark - Màn hình

@interface SXChatTestController () <UITableViewDataSource, UITableViewDelegate, UITextViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSMutableArray<SXChatMessage *> *messages;
@property (nonatomic, strong) UITextView *input;
@property (nonatomic, strong) UILabel *placeholder;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic) BOOL busy;
@end

@implementation SXChatTestController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Trò chuyện thử";
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	self.messages = [NSMutableArray array];

	SXPrefs *prefs = [SXPrefs shared];
	self.navigationItem.prompt = prefs.providerSummary;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
		initWithImage:[UIImage systemImageNamed:@"trash"]
				style:UIBarButtonItemStylePlain
			   target:self
			   action:@selector(sx_confirmClear)];

	[self sx_buildViews];
	[self sx_updateEmptyState];
	[self sx_updateSendEnabled];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self.input becomeFirstResponder];
}

#pragma mark - Giao diện

- (void)sx_buildViews {
	self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
	self.table.translatesAutoresizingMaskIntoConstraints = NO;
	self.table.dataSource = self;
	self.table.delegate = self;
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.table.backgroundColor = UIColor.clearColor;
	self.table.rowHeight = UITableViewAutomaticDimension;
	self.table.estimatedRowHeight = 64;
	self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
	self.table.contentInset = UIEdgeInsetsMake(10, 0, 10, 0);
	[self.table registerClass:[SXChatBubbleCell class] forCellReuseIdentifier:@"bubble"];

	UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self
																					   action:@selector(sx_handleLongPress:)];
	[self.table addGestureRecognizer:press];

	UIView *inputBar = [[UIView alloc] init];
	inputBar.translatesAutoresizingMaskIntoConstraints = NO;
	inputBar.backgroundColor = UIColor.secondarySystemBackgroundColor;

	self.input = [[UITextView alloc] init];
	self.input.translatesAutoresizingMaskIntoConstraints = NO;
	self.input.delegate = self;
	self.input.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	self.input.backgroundColor = UIColor.clearColor;
	self.input.textContainerInset = UIEdgeInsetsMake(9, 6, 9, 6);
	self.input.returnKeyType = UIReturnKeySend;
	self.input.scrollEnabled = YES;
	[self.input.heightAnchor constraintEqualToConstant:36].active = YES;

	self.placeholder = [[UILabel alloc] init];
	self.placeholder.translatesAutoresizingMaskIntoConstraints = NO;
	self.placeholder.text = @"Hỏi thử một câu…";
	self.placeholder.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	self.placeholder.textColor = UIColor.placeholderTextColor;
	self.placeholder.userInteractionEnabled = NO;

	self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
	[self.sendButton setImage:[UIImage systemImageNamed:@"arrow.up.circle.fill"] forState:UIControlStateNormal];
	self.sendButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
	self.sendButton.tintColor = [SXUI accentColor];
	[self.sendButton addTarget:self action:@selector(sx_send) forControlEvents:UIControlEventTouchUpInside];
	[self.sendButton.widthAnchor constraintEqualToConstant:40].active = YES;
	[self.sendButton.heightAnchor constraintEqualToConstant:40].active = YES;

	[inputBar addSubview:self.input];
	[inputBar addSubview:self.placeholder];
	[inputBar addSubview:self.sendButton];

	UIView *hairline = [[UIView alloc] init];
	hairline.translatesAutoresizingMaskIntoConstraints = NO;
	hairline.backgroundColor = UIColor.separatorColor;
	[inputBar addSubview:hairline];

	[self.view addSubview:self.table];
	[self.view addSubview:inputBar];

	[NSLayoutConstraint activateConstraints:@[
		[self.table.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
		[self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.table.bottomAnchor constraintEqualToAnchor:inputBar.topAnchor],

		[inputBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[inputBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[inputBar.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
		[inputBar.heightAnchor constraintGreaterThanOrEqualToConstant:52],

		[hairline.topAnchor constraintEqualToAnchor:inputBar.topAnchor],
		[hairline.leadingAnchor constraintEqualToAnchor:inputBar.leadingAnchor],
		[hairline.trailingAnchor constraintEqualToAnchor:inputBar.trailingAnchor],
		[hairline.heightAnchor constraintEqualToConstant:0.5],

		[self.input.leadingAnchor constraintEqualToAnchor:inputBar.leadingAnchor constant:10],
		[self.input.topAnchor constraintEqualToAnchor:inputBar.topAnchor constant:6],
		[self.input.bottomAnchor constraintEqualToAnchor:inputBar.bottomAnchor constant:-8],
		[self.input.trailingAnchor constraintEqualToAnchor:self.sendButton.leadingAnchor constant:-6],

		[self.placeholder.leadingAnchor constraintEqualToAnchor:self.input.leadingAnchor constant:11],
		[self.placeholder.topAnchor constraintEqualToAnchor:self.input.topAnchor constant:9],

		[self.sendButton.trailingAnchor constraintEqualToAnchor:inputBar.trailingAnchor constant:-12],
		[self.sendButton.centerYAnchor constraintEqualToAnchor:self.input.centerYAnchor],
	]];
}

- (void)sx_updateEmptyState {
	if (self.messages.count) {
		self.table.backgroundView = nil;
		return;
	}
	SXPrefs *prefs = [SXPrefs shared];
	NSString *message = prefs.activeAPIKey.length
		? [NSString stringWithFormat:@"Hỏi thử để kiểm tra %@. Hội thoại chỉ nằm trong màn hình này, công cụ AI không được gọi.", prefs.providerSummary]
		: @"Chưa có khóa API. Mở Cấu hình nhà cung cấp để dán khóa trước.";
	self.table.backgroundView = [SXUI emptyStateWithSymbol:@"bubble.left.and.bubble.right"
													 title:@"Chưa có tin nhắn"
												   message:message];
}

- (void)sx_updateSendEnabled {
	BOOL hasText = self.input.text.length > 0;
	self.sendButton.enabled = hasText && !self.busy;
	self.sendButton.alpha = self.sendButton.enabled ? 1.0 : 0.35;
	self.placeholder.hidden = hasText;
}

- (void)sx_scrollToBottom {
	if (!self.messages.count) return;
	[self.table layoutIfNeeded];
	NSInteger last = (NSInteger)self.messages.count - 1;
	[self.table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:last inSection:0]
					  atScrollPosition:UITableViewScrollPositionBottom
							  animated:YES];
}

- (void)sx_appendMessage:(SXChatMessage *)message {
	[self.messages addObject:message];
	[self.table reloadData];
	[self sx_updateEmptyState];
	[self sx_scrollToBottom];
}

#pragma mark - Gửi

- (void)sx_send {
	NSString *question = [self.input.text stringByTrimmingCharactersInSet:
						  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (self.busy || !question.length) return;

	[self.input resignFirstResponder];
	self.input.text = @"";
	[self sx_updateSendEnabled];

	SXChatMessage *userMessage = [SXChatMessage new];
	userMessage.role = SXChatRoleUser;
	userMessage.text = question;
	userMessage.date = [NSDate date];
	[self sx_appendMessage:userMessage];

	self.busy = YES;
	[self sx_updateSendEnabled];

	SXChatMessage *typing = [SXChatMessage new];
	typing.role = SXChatRoleTyping;
	typing.text = @"Đang trả lời…";
	typing.date = [NSDate date];
	[self sx_appendMessage:typing];

	NSMutableArray<NSDictionary *> *history = [NSMutableArray array];
	for (NSUInteger i = 0; i + 1 < self.messages.count; i++) {
		SXChatMessage *q = self.messages[i];
		SXChatMessage *a = self.messages[i + 1];
		if (q.role == SXChatRoleUser && a.role == SXChatRoleAssistant) {
			[history addObject:@{@"q": q.text ?: @"", @"a": a.text ?: @""}];
			i++;
		}
	}
	NSUInteger maxTurns = (NSUInteger)MAX((NSInteger)2, [SXPrefs shared].contextTurns);
	if (history.count > maxTurns) {
		history = [[history subarrayWithRange:NSMakeRange(history.count - maxTurns, maxTurns)] mutableCopy];
	}

	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		[SXLLM askQuestion:question
				   history:history
					 tools:@[]
				  executor:nil
				completion:^(NSString *answer, NSError *error, NSDictionary *info) {
			dispatch_async(dispatch_get_main_queue(), ^{
				typeof(self) strongSelf = weakSelf;
				if (!strongSelf) return;
				[strongSelf.messages removeObject:typing];
				strongSelf.busy = NO;

				SXChatMessage *reply = [SXChatMessage new];
				reply.date = [NSDate date];
				if (error) {
					reply.role = SXChatRoleError;
					reply.text = error.localizedDescription;
				} else if (answer.length) {
					reply.role = SXChatRoleAssistant;
					reply.text = [SXPrefs shared].markdown ? SXMarkdownRender(answer) : answer;
				} else {
					reply.role = SXChatRoleError;
					reply.text = @"Model không trả về nội dung.";
				}
				[strongSelf.messages addObject:reply];
				[strongSelf.table reloadData];
				[strongSelf sx_scrollToBottom];
				[strongSelf sx_updateEmptyState];
				[strongSelf sx_updateSendEnabled];
				(void)info;
			});
		}];
	});
}

#pragma mark - Bảng

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	(void)tableView; (void)section;
	return (NSInteger)self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	SXChatBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"bubble" forIndexPath:indexPath];
	[cell configureWithMessage:self.messages[(NSUInteger)indexPath.row]];
	return cell;
}

- (void)sx_handleLongPress:(UILongPressGestureRecognizer *)recognizer {
	if (recognizer.state != UIGestureRecognizerStateBegan) return;
	CGPoint point = [recognizer locationInView:self.table];
	NSIndexPath *indexPath = [self.table indexPathForRowAtPoint:point];
	if (!indexPath || (NSUInteger)indexPath.row >= self.messages.count) return;
	SXChatMessage *message = self.messages[(NSUInteger)indexPath.row];
	if (!message.text.length) return;
	UIPasteboard.generalPasteboard.string = message.text;
	[SXUI tapFeedback];
	NSString *restore = [SXPrefs shared].providerSummary;
	self.navigationItem.prompt = @"Đã sao chép tin nhắn ✓";
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		weakSelf.navigationItem.prompt = restore;
	});
}

#pragma mark - Soạn tin

- (void)textViewDidChange:(UITextView *)textView {
	(void)textView;
	[self sx_updateSendEnabled];
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
	if ([text isEqualToString:@"\n"]) {
		[self sx_send];
		return NO;
	}
	return YES;
}

#pragma mark - Xoá

- (void)sx_confirmClear {
	if (!self.messages.count) {
		[SXUI alertOn:self title:@"Chưa có tin nhắn" message:nil];
		return;
	}
	__weak typeof(self) weakSelf = self;
	[SXUI confirmOn:self
			  title:@"Xoá hội thoại thử?"
			message:@"Toàn bộ tin nhắn trong màn hình này sẽ bị xoá."
		confirmText:@"Xoá"
			 action:^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		[strongSelf.messages removeAllObjects];
		[strongSelf.table reloadData];
		[strongSelf sx_updateEmptyState];
		[strongSelf sx_updateSendEnabled];
	}];
}

@end
