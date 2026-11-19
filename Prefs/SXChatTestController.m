#import "SXChatTestController.h"
#import "SXNavigationSupport.h"
#import "SXLLM.h"
#import "SXPrefs.h"
#import "SXMarkdown.h"
#import "SXTools.h"
#import "SXLog.h"
#import "SXUISupport.h"
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, SXChatRole) {
	SXChatRoleUser = 0,
	SXChatRoleAssistant,
	SXChatRoleError,
	SXChatRoleTyping,
	SXChatRoleTool,   // “đang dùng công cụ …” — chỉ trong màn hình thử
	SXChatRoleNote,   // ghi chú hệ thống (“Đã huỷ lượt này.”) — không vào lịch sử
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
		case SXChatRoleNote:
			_bubble.backgroundColor = UIColor.secondarySystemBackgroundColor;
			_label.textColor = UIColor.secondaryLabelColor;
			break;
		case SXChatRoleTool:
			_bubble.backgroundColor = [[SXUI accentColor] colorWithAlphaComponent:0.12];
			_label.textColor = [SXUI accentColor];
			break;
	}
	if (message.role == SXChatRoleTyping || message.role == SXChatRoleTool ||
		message.role == SXChatRoleNote) {
		_label.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
	} else {
		_label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	}

	NSString *meta = (message.role == SXChatRoleError || message.role == SXChatRoleTyping ||
					  message.role == SXChatRoleTool || message.role == SXChatRoleNote)
		? @""
		: [SXUI relativeStringForDate:message.date];
	_meta.text = meta;
	_meta.hidden = meta.length == 0;
	_meta.textColor = fromUser ? [UIColor.whiteColor colorWithAlphaComponent:0.7] : UIColor.tertiaryLabelColor;

	// Tái sử dụng cell: nhãn đã từng được đo theo nội dung khác. Đặt lại chiều
	// rộng ưu tiên để bảng tính đúng chiều cao thay vì giữ kích thước cũ.
	_label.preferredMaxLayoutWidth = 0;
	[self setNeedsLayout];
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
/// Mỗi lần gửi là một "thế hệ"; phản hồi của thế hệ cũ (đã bị xoá hội thoại,
/// đã rời màn hình) không được chen vào màn hình mới.
@property (nonatomic) NSUInteger generation;
@property (nonatomic, strong) SXChatMessage *streamingReply;
@end

@implementation SXChatTestController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Trò chuyện thử";
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(sx_toolDidRun:)
												 name:SXLLMToolActivityNotification
											   object:nil];
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

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	SXEnsureBackButton(self, @"Trò chuyện thử");
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	SXShowContentFallbackIfNeeded(self, @"Trò chuyện thử", @"không dựng được khung chat");
	[self.input becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	// Đang chờ AI mà rời màn hình: tăng thế hệ để mọi callback (delta/finish/
	// tool) tự bỏ qua. Không có bước này, callback của lượt cũ vẫn reload bảng
	// đã bị pop và giữ nguyên trạng thái "đang trả lời…".
	if (self.busy) {
		self.generation++;
		self.busy = NO;
		SXLogDbg(@"chat-test", @"rời màn hình khi đang trả lời — bỏ lượt");
	}
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

/// Công cụ vừa chạy xong. Giữ MỘT dòng hoạt động trong lúc đang trả lời rồi
/// đóng băng nó khi có câu trả lời — nhờ vậy người dùng thấy AI thật sự làm gì
/// (đọc web, mở app…) mà không bị một loạt bong bóng làm rối màn hình.
- (void)sx_toolDidRun:(NSNotification *)notification {
	// Chỉ hiện khi chính màn hình này đang chờ trả lời — thông báo lạc từ lượt
	// kiểm tra kết nối ở màn hình khác không được chen vào hội thoại.
	if (!self.busy) return;
	NSDictionary *info = notification.userInfo;
	NSString *name = [info[@"name"] isKindOfClass:[NSString class]] ? info[@"name"] : @"?";
	NSInteger ms = [info[@"ms"] integerValue];
	BOOL failed = [info[@"failed"] boolValue];
	NSString *text = [NSString stringWithFormat:@"%@ %@ · %ld ms", failed ? @"⚠️" : @"🛠", name, (long)ms];

	SXChatMessage *typing = self.messages.lastObject;
	BOOL typingAtEnd = typing && typing.role == SXChatRoleTyping;
	SXChatMessage *last = typingAtEnd && self.messages.count >= 2
		? self.messages[self.messages.count - 2] : typing;

	if (last && last.role == SXChatRoleTool) {
		last.text = text;
		[UIView performWithoutAnimation:^{
			[self.table reloadData];
		}];
		return;
	}

	SXChatMessage *toolMessage = [SXChatMessage new];
	toolMessage.role = SXChatRoleTool;
	toolMessage.text = text;
	toolMessage.date = [NSDate date];
	NSUInteger insertAt = typingAtEnd ? self.messages.count - 1 : self.messages.count;
	[self.messages insertObject:toolMessage atIndex:insertAt];
	[self.table reloadData];
	if (!typingAtEnd) [self sx_scrollToBottom];
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
	self.sendButton.accessibilityLabel = @"Gửi hoặc dừng";
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
		? [NSString stringWithFormat:@"Hỏi thử để kiểm tra %@. Dùng đúng bộ công cụ như Siri thật — thử “pin còn bao nhiêu” hay “chép câu này”. Hội thoại chỉ nằm trong màn hình này.", prefs.providerSummary]
		: @"Chưa có khóa API. Mở Cấu hình nhà cung cấp để dán khóa trước.";
	self.table.backgroundView = [SXUI emptyStateWithSymbol:@"bubble.left.and.bubble.right"
													 title:@"Chưa có tin nhắn"
												   message:message];
}

- (void)sx_updateSendEnabled {
	BOOL hasText = self.input.text.length > 0;
	UIImage *icon = [UIImage systemImageNamed:self.busy ? @"stop.circle.fill" : @"arrow.up.circle.fill"];
	[self.sendButton setImage:icon forState:UIControlStateNormal];
	self.sendButton.enabled = self.busy || hasText;
	self.sendButton.alpha = self.sendButton.enabled ? 1.0 : 0.35;
	self.placeholder.hidden = hasText;
}

/// Trong lúc chờ, nút gửi thành nút dừng: huỷ lượt đang chạy và bỏ bong bóng
/// đang gõ, thay vì khoá UI cho tới khi hết ngân sách.
- (void)sx_cancel {
	if (!self.busy) return;
	self.generation++;
	self.busy = NO;
	NSUInteger count = self.messages.count;
	for (NSUInteger i = count; i > 0; i--) {
		SXChatMessage *message = self.messages[i - 1];
		if (message.role == SXChatRoleTyping || message == self.streamingReply) {
			[self.messages removeObjectAtIndex:i - 1];
		}
	}
	self.streamingReply = nil;
	SXChatMessage *note = [SXChatMessage new];
	note.role = SXChatRoleNote;
	note.text = @"Đã huỷ lượt này.";
	note.date = [NSDate date];
	[self.messages addObject:note];
	[self.table reloadData];
	[self sx_scrollToBottom];
	[self sx_updateSendEnabled];
	SXLogDbg(@"chat-test", @"người dùng huỷ lượt đang chạy");
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

/// Dựng lịch sử hội thoại từ các cặp hỏi–đáp đã có (bỏ dòng công cụ/lỗi).
- (NSArray<NSDictionary *> *)sx_history {
	NSMutableArray<NSDictionary *> *history = [NSMutableArray array];
	for (NSUInteger i = 0; i + 1 < self.messages.count; i++) {
		SXChatMessage *question = self.messages[i];
		SXChatMessage *answer = self.messages[i + 1];
		if (question.role != SXChatRoleUser || answer.role != SXChatRoleAssistant) continue;
		[history addObject:@{@"q": question.text ?: @"", @"a": answer.text ?: @""}];
		i++;
	}
	NSUInteger maxTurns = (NSUInteger)MAX((NSInteger)2, [SXPrefs shared].contextTurns);
	if (history.count > maxTurns) {
		return [history subarrayWithRange:NSMakeRange(history.count - maxTurns, maxTurns)];
	}
	return history;
}

- (void)sx_send {
	if (self.busy) {
		[self sx_cancel];
		return;
	}
	NSString *question = [self.input.text stringByTrimmingCharactersInSet:
						  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!question.length) return;

	[self.input resignFirstResponder];
	self.input.text = @"";
	[self sx_updateSendEnabled];

	SXChatMessage *userMessage = [SXChatMessage new];
	userMessage.role = SXChatRoleUser;
	userMessage.text = question;
	userMessage.date = [NSDate date];
	[self sx_appendMessage:userMessage];

	self.busy = YES;
	self.generation++;
	NSUInteger generation = self.generation;
	[self sx_updateSendEnabled];

	SXChatMessage *typing = [SXChatMessage new];
	typing.role = SXChatRoleTyping;
	typing.text = @"Đang trả lời…";
	typing.date = [NSDate date];
	[self sx_appendMessage:typing];

	NSArray<NSDictionary *> *history = [self sx_history];
	BOOL markdown = [SXPrefs shared].markdown;

	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		// Bật đúng bộ công cụ như Siri thật để kiểm chứng ngay trong Settings.
		SXToolExec executor = ^NSDictionary *(NSString *name, NSDictionary *arguments, NSError **error) {
			return [SXTools execute:name arguments:arguments error:error];
		};
		__block NSUInteger firstTokenMs = -1;
		__block NSUInteger deltaCount = 0;
		[SXLLM askQuestion:question
				   history:history
					 tools:[SXTools definitions]
				  executor:executor
				   onDelta:^(NSString *delta, NSInteger firstMs) {
			if (firstTokenMs == (NSUInteger)-1) firstTokenMs = (NSUInteger)MAX(firstMs, 0);
			deltaCount++;
			(void)delta;
			dispatch_async(dispatch_get_main_queue(), ^{
				typeof(self) strongSelf = weakSelf;
				if (!strongSelf || strongSelf.generation != generation) return;
				[strongSelf sx_appendDelta:delta firstTokenMs:firstTokenMs];
			});
		}
				completion:^(NSString *answer, NSError *error, NSDictionary *info) {
			dispatch_async(dispatch_get_main_queue(), ^{
				typeof(self) strongSelf = weakSelf;
				if (!strongSelf || strongSelf.generation != generation) return;
				[strongSelf sx_finishWithAnswer:answer error:error info:info typing:typing
									   markdown:markdown firstTokenMs:firstTokenMs deltas:deltaCount];
			});
		}];
	});
}

/// Tách riêng để dễ đọc: cập nhật bong bóng đang gõ dần (streaming) tại chỗ.
- (void)sx_appendDelta:(NSString *)delta firstTokenMs:(NSUInteger)firstTokenMs {
	(void)firstTokenMs;
	if (![delta isKindOfClass:[NSString class]] || !delta.length) return;
	SXChatMessage *reply = self.streamingReply;
	BOOL isNew = NO;
	if (!reply) {
		// Thay dòng “đang trả lời…” bằng bong bóng thật ngay từ token đầu.
		SXChatMessage *typing = self.messages.lastObject;
		if (typing && typing.role == SXChatRoleTyping) [self.messages removeObject:typing];
		reply = [SXChatMessage new];
		reply.role = SXChatRoleAssistant;
		reply.text = @"";
		reply.date = [NSDate date];
		[self.messages addObject:reply];
		self.streamingReply = reply;
		isNew = YES;
	}
	if (![reply.text isKindOfClass:[NSString class]]) reply.text = @"";
	reply.text = [reply.text stringByAppendingString:delta];

	if (isNew) {
		[UIView performWithoutAnimation:^{ [self.table reloadData]; }];
		[self sx_scrollToBottom];
		return;
	}
	// Có bong bóng rồi: chỉ sửa nhãn của đúng ô cuối, không reload bảng (reload mỗi
	// token làm bảng nhấp nháy và ăn CPU vô ích).
	[self sx_refreshStreamingBubble];
}

/// Cập nhật nhãn bong bóng đang stream tại chỗ.
- (void)sx_refreshStreamingBubble {
	if (!self.streamingReply) return;
	NSUInteger row = [self.messages indexOfObjectIdenticalTo:self.streamingReply];
	if (row == NSNotFound) return;
	NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(NSInteger)row inSection:0];
	UITableViewCell *cell = nil;
	@try {
		cell = [self.table cellForRowAtIndexPath:indexPath];
	} @catch (NSException *exception) {
		(void)exception;
		return;
	}
	if (!cell || ![cell respondsToSelector:@selector(configureWithMessage:)]) {
		[UIView performWithoutAnimation:^{ [self.table reloadData]; }];
		return;
	}
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
	[cell performSelector:@selector(configureWithMessage:) withObject:self.streamingReply];
#pragma clang diagnostic pop
	[self sx_scrollToBottom];
}

- (void)sx_finishWithAnswer:(NSString *)answer
					  error:(NSError *)error
					   info:(NSDictionary *)info
					 typing:(SXChatMessage *)typing
				   markdown:(BOOL)markdown
			   firstTokenMs:(NSUInteger)firstTokenMs
					 deltas:(NSUInteger)deltas {
	[self.messages removeObject:typing];
	NSString *streamed = self.streamingReply.text;
	if (self.streamingReply) [self.messages removeObject:self.streamingReply];
	self.streamingReply = nil;
	self.busy = NO;

	SXChatMessage *reply = [SXChatMessage new];
	reply.date = [NSDate date];
	if (error) {
		reply.role = SXChatRoleError;
		reply.text = error.localizedDescription;
	} else {
		NSString *raw = [answer stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (!raw.length && streamed.length) raw = streamed;   // stream đã hiện chữ
		if (!raw.length) {
			reply.role = SXChatRoleError;
			reply.text = @"Model không trả về nội dung.";
		} else {
			reply.role = SXChatRoleAssistant;
			reply.text = markdown ? SXMarkdownRender(raw) : raw;
		}
	}
	[self.messages addObject:reply];

	// Dòng chân bong bóng: thời gian + nhịp stream, có ích khi so sánh model.
	if (!error && [info isKindOfClass:[NSDictionary class]]) {
		NSInteger ms = [info[@"ms"] integerValue];
		NSMutableString *meta = [NSMutableString stringWithFormat:@"%ld ms", (long)ms];
		if (firstTokenMs < (NSUInteger)NSIntegerMax && firstTokenMs > 0) {
			[meta appendFormat:@" · token đầu %lu ms", (unsigned long)firstTokenMs];
		}
		if (deltas > 1) [meta appendFormat:@" · %lu mảnh", (unsigned long)deltas];
		self.navigationItem.prompt = meta;
	}

	[UIView performWithoutAnimation:^{
		[self.table reloadData];
	}];
	[self sx_scrollToBottom];
	[self sx_updateEmptyState];
	[self sx_updateSendEnabled];
	SXLogDbg(@"pref", @"chat thử: %@ (%@), %lu phần", error ? @"lỗi" : @"xong",
			 info[@"model"] ?: @"?", (unsigned long)self.messages.count);
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
	if (!message.text.length || message.role == SXChatRoleTool) return;
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
	if (self.busy) {
		// Xoá giữa lúc chờ sẽ làm câu trả lời rơi vào màn hình trống — đợi xong đã.
		[SXUI alertOn:self title:@"Đang chờ trả lời"
			  message:@"Đợi câu trả lời này xong rồi xoá, hoặc thoát ra và quay lại."];
		return;
	}
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
