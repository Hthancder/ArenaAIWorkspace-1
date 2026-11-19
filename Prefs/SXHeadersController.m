#import "SXHeadersController.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXUISupport.h"
#import "PSSpecifier.h"
#import <notify.h>
#import <UIKit/UIKit.h>

#pragma mark - Ô header trong danh sách

@interface SXHeaderRowCell : UITableViewCell
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UISwitch *toggle;
@end

@implementation SXHeaderRowCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self) return nil;

	self.selectionStyle = UITableViewCellSelectionStyleDefault;

	_nameLabel = [[UILabel alloc] init];
	_nameLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightSemibold];
	_nameLabel.numberOfLines = 1;
	_nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

	_valueLabel = [[UILabel alloc] init];
	_valueLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
	_valueLabel.textColor = UIColor.secondaryLabelColor;
	_valueLabel.numberOfLines = 1;
	_valueLabel.lineBreakMode = NSLineBreakByTruncatingTail;

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, _valueLabel]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 2;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:stack];

	_toggle = [[UISwitch alloc] init];
	_toggle.onTintColor = [SXUI accentColor];
	_toggle.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:_toggle];

	UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
	[NSLayoutConstraint activateConstraints:@[
		[stack.topAnchor constraintEqualToAnchor:margins.topAnchor constant:10],
		[stack.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor constant:-10],
		[stack.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
		[stack.trailingAnchor constraintEqualToAnchor:_toggle.leadingAnchor constant:-10],
		[_toggle.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
		[_toggle.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
	]];
	return self;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self.toggle removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
}

@end

#pragma mark - Ô nhập kèm dòng gợi ý

/// Ô nhập + một dòng chú thích nhỏ ngay dưới, cả hai nằm **trong** cell.
///
/// Hai lỗi cũ đều xuất phát từ chỗ này: gợi ý nằm ở footer section nên mỗi lần
/// gõ phải reload section để cập nhật chữ — reload gỡ ô nhập khỏi cửa sổ nên
/// UIKit hạ bàn phím ngay sau ký tự đầu tiên. Còn ô nhập do màn hình giữ rồi
/// "dời" giữa các cell khi cuộn cũng làm mất first responder. Nay mỗi cell tự
/// có ô nhập của nó, chữ do màn hình giữ trong `nameText`/`valueText`.
@interface SXHeaderFieldCell : UITableViewCell
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UILabel *hintLabel;
@end

@implementation SXHeaderFieldCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self) return nil;

	self.selectionStyle = UITableViewCellSelectionStyleNone;

	_field = [[UITextField alloc] init];
	_field.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
	// Tên header và token đều không được bàn phím "sửa giúp".
	_field.autocapitalizationType = UITextAutocapitalizationTypeNone;
	_field.autocorrectionType = UITextAutocorrectionTypeNo;
	_field.spellCheckingType = UITextSpellCheckingTypeNo;
	_field.smartQuotesType = UITextSmartQuotesTypeNo;
	_field.smartDashesType = UITextSmartDashesTypeNo;
	_field.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
	_field.clearButtonMode = UITextFieldViewModeWhileEditing;
	_field.translatesAutoresizingMaskIntoConstraints = NO;

	_hintLabel = [[UILabel alloc] init];
	_hintLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	_hintLabel.numberOfLines = 0;
	_hintLabel.textColor = UIColor.systemRedColor;
	_hintLabel.hidden = YES;

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_field, _hintLabel]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 4;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:stack];

	UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
	[NSLayoutConstraint activateConstraints:@[
		[stack.topAnchor constraintEqualToAnchor:margins.topAnchor constant:2],
		[stack.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor constant:-2],
		[stack.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
		[stack.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
		[_field.heightAnchor constraintGreaterThanOrEqualToConstant:32],
	]];
	return self;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self.field removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
	self.field.text = @"";
	self.field.rightView = nil;
	self.field.rightViewMode = UITextFieldViewModeNever;
	self.hintLabel.text = nil;
	self.hintLabel.hidden = YES;
}

@end

#pragma mark - Màn hình sửa một header

@interface SXHeaderEditController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic) SXHeaderPresetProvider presetProvider;
@property (nonatomic, copy) NSString *endpointHint;
@property (nonatomic, copy) NSArray<NSDictionary *> *existing;
@property (nonatomic, copy, nullable) NSDictionary *editing;
@property (nonatomic, copy) void (^onSave)(NSDictionary *header);
@property (nonatomic, strong) UITableView *table;
/// Chữ là nguồn dữ liệu duy nhất — ô nhập chỉ hiển thị và sửa nó.
@property (nonatomic, copy) NSString *nameText;
@property (nonatomic, copy) NSString *valueText;
@property (nonatomic, weak) UITextField *nameField;
@property (nonatomic, weak) UITextField *valueField;
@property (nonatomic, copy) NSArray<NSDictionary *> *suggestions;
@property (nonatomic, assign) SXHeaderIssue issue;
@property (nonatomic, copy) NSString *insecureWarning;
@end

@implementation SXHeaderEditController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.editing ? @"Sửa header" : @"Thêm header";
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	self.suggestions = SXHeaderPresetsForEndpoint(self.presetProvider, self.endpointHint);
	self.insecureWarning = [self sx_insecureWarning];
	self.nameText = [self.editing[@"name"] isKindOfClass:[NSString class]] ? self.editing[@"name"] : @"";
	self.valueText = [self.editing[@"value"] isKindOfClass:[NSString class]] ? self.editing[@"value"] : @"";

	self.navigationItem.leftBarButtonItem =
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
													  target:self
													  action:@selector(sx_cancel)];
	self.navigationItem.rightBarButtonItem =
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
													  target:self
													  action:@selector(sx_save)];

	self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.table.translatesAutoresizingMaskIntoConstraints = NO;
	self.table.dataSource = self;
	self.table.delegate = self;
	self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
	self.table.rowHeight = UITableViewAutomaticDimension;
	self.table.estimatedRowHeight = 52;
	[self.table registerClass:[SXHeaderFieldCell class] forCellReuseIdentifier:@"field"];
	[self.view addSubview:self.table];
	[NSLayoutConstraint activateConstraints:@[
		[self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		// Bàn phím không che ô đang gõ (iOS 15+).
		[self.table.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
	]];
	[self sx_validate];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	if (self.editing) return;
	[self.table layoutIfNeeded];
	[[self sx_fieldInSection:0] becomeFirstResponder];
}

- (UITextField *)sx_fieldInSection:(NSInteger)section {
	SXHeaderFieldCell *cell = (SXHeaderFieldCell *)[self.table
		cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:section]];
	return [cell isKindOfClass:[SXHeaderFieldCell class]] ? cell.field : nil;
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	(void)tableView;
	return 3; // tên · giá trị · gợi ý
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	(void)tableView;
	return section == 2 ? (NSInteger)self.suggestions.count : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	(void)tableView;
	if (section == 0) return @"Tên header";
	if (section == 1) return @"Giá trị";
	return self.suggestions.count ? @"Gợi ý nhanh" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	(void)tableView;
	if (section == 0) {
		return @"Ví dụ: X-Title, HTTP-Referer, api-key. Header hệ thống (Host, Content-Type, Content-Length) bị bỏ qua vì sẽ làm hỏng request.";
	}
	if (section == 1) {
		if (self.insecureWarning.length) return self.insecureWarning;
		return @"Giá trị không được hiện trong danh sách và không bao giờ được ghi vào log.";
	}
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 2) {
		return [self sx_suggestionCellForTable:tableView indexPath:indexPath];
	}

	SXHeaderFieldCell *cell = [tableView dequeueReusableCellWithIdentifier:@"field" forIndexPath:indexPath];
	BOOL isName = indexPath.section == 0;
	UITextField *field = cell.field;
	field.tag = indexPath.section;
	field.delegate = self;
	field.returnKeyType = isName ? UIReturnKeyNext : UIReturnKeyDone;
	field.placeholder = isName ? @"X-Title" : @"giá trị";
	field.accessibilityLabel = isName ? @"Tên header" : @"Giá trị header";
	NSString *expected = isName ? self.nameText : self.valueText;
	NSString *current = field.text ?: @"";
	if (![current isEqualToString:expected]) field.text = expected;
	[field removeTarget:self action:@selector(sx_fieldChanged:) forControlEvents:UIControlEventEditingChanged];
	[field addTarget:self action:@selector(sx_fieldChanged:) forControlEvents:UIControlEventEditingChanged];
	if (isName) {
		self.nameField = field;
	} else {
		self.valueField = field;
		[self sx_installPasteButtonOnField:field];
	}
	[self sx_fillHintLabel:cell.hintLabel forSection:indexPath.section];
	return cell;
}

- (void)sx_installPasteButtonOnField:(UITextField *)field {
	if (field.rightView) return;
	UIButton *paste = [UIButton buttonWithType:UIButtonTypeSystem];
	[paste setTitle:@"Dán" forState:UIControlStateNormal];
	paste.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	[paste sizeToFit];
	[paste addTarget:self action:@selector(sx_pasteValue) forControlEvents:UIControlEventTouchUpInside];
	paste.accessibilityHint = @"Lấy dòng đầu tiên trong bộ nhớ tạm";
	field.rightView = paste;
	field.rightViewMode = UITextFieldViewModeAlways;
}

- (UITableViewCell *)sx_suggestionCellForTable:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"suggestion"];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"suggestion"];
	}
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.textLabel.textColor = UIColor.labelColor;
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.detailTextLabel.numberOfLines = 0;

	NSDictionary *preset = indexPath.row < (NSInteger)self.suggestions.count ? self.suggestions[indexPath.row] : nil;
	NSString *value = preset[@"value"];
	cell.textLabel.text = preset ? (value.length ? [NSString stringWithFormat:@"%@: %@", preset[@"name"], value]
												: [NSString stringWithFormat:@"%@: (tự điền)", preset[@"name"]]) : @"";
	cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
	cell.detailTextLabel.text = preset[@"note"];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 2) return;
	if (indexPath.row >= (NSInteger)self.suggestions.count) return;
	NSDictionary *preset = self.suggestions[indexPath.row];
	NSString *name = [preset[@"name"] isKindOfClass:[NSString class]] ? preset[@"name"] : @"";
	NSString *value = [preset[@"value"] isKindOfClass:[NSString class]] ? preset[@"value"] : @"";
	self.nameText = name;
	self.valueText = value;
	[SXUI tapFeedback];
	// Điền xong thì đưa người dùng tới ô còn thiếu để gõ tiếp ngay.
	[UIView performWithoutAnimation:^{
		[self.table reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]
				  withRowAnimation:UITableViewRowAnimationNone];
	}];
	[self.table layoutIfNeeded];
	[self sx_validate];
	if (!value.length) [[self sx_fieldInSection:1] becomeFirstResponder];
	else [[self sx_fieldInSection:0] resignFirstResponder];
}

#pragma mark - Gợi ý lỗi tại chỗ

- (NSString *)sx_messageForSection:(NSInteger)section {
	NSString *name = SXHeaderTrimmedName(self.nameText);
	if (section == 0) {
		if (!name.length) return nil;   // chưa gõ gì thì đừng doạ người dùng
		return SXHeaderIssueMessage(self.issue, name);
	}
	if (self.issue != SXHeaderIssueInvalidValue) return nil;
	if (!name.length) return nil;
	return SXHeaderIssueMessage(self.issue, name);
}

- (void)sx_fillHintLabel:(UILabel *)label forSection:(NSInteger)section {
	NSString *text = [self sx_messageForSection:section];
	if (![label.text isEqualToString:text ?: @""]) label.text = text;
	BOOL shouldHide = !text.length;
	if (label.hidden != shouldHide) label.hidden = shouldHide;
}

/// Cập nhật gợi ý trên các ô đang hiện mà **không** reload cell — đây chính là
/// chỗ từng làm bàn phím tắt sau mỗi ký tự.
- (void)sx_refreshHints {
	BOOL changed = NO;
	for (NSInteger section = 0; section <= 1; section++) {
		SXHeaderFieldCell *cell = (SXHeaderFieldCell *)[self.table
			cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:section]];
		if (![cell isKindOfClass:[SXHeaderFieldCell class]]) continue;
		NSString *before = cell.hintLabel.text ?: @"";
		BOOL hiddenBefore = cell.hintLabel.hidden;
		[self sx_fillHintLabel:cell.hintLabel forSection:section];
		NSString *after = cell.hintLabel.text ?: @"";
		if (![before isEqualToString:after] || hiddenBefore != cell.hintLabel.hidden) changed = YES;
	}
	if (!changed) return;
	@try {
		// Chỉ tính lại chiều cao, không tạo lại cell ⇒ bàn phím giữ nguyên.
		[self.table beginUpdates];
		[self.table endUpdates];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"cập nhật gợi ý header: %@", exception.reason);
	}
}

#pragma mark - Kiểm tra & lưu

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	if (textField.tag == 0) {
		[[self sx_fieldInSection:1] becomeFirstResponder];
	} else {
		[self sx_save];
	}
	return YES;
}

/// Endpoint http:// (không phải https) thì header — kể cả token — đi trên mạng
/// không mã hoá. Cảnh báo ngay dưới ô nhập thay vì để người dùng tự phát hiện.
- (NSString *)sx_insecureWarning {
	if (self.presetProvider != SXHeaderPresetProviderOpenAI) return nil;
	NSString *base = [SXPrefs shared].openaiBase;
	if (![base isKindOfClass:[NSString class]]) return nil;
	if (![base.lowercaseString hasPrefix:@"http://"]) return nil;
	return @"⚠️ Endpoint đang dùng http:// nên giá trị header (kể cả token) đi trên mạng không mã hoá. "
			"Hãy đổi sang https:// nếu máy chủ hỗ trợ.";
}

- (void)sx_pasteValue {
	NSString *clipboard = UIPasteboard.generalPasteboard.string;
	if (![clipboard isKindOfClass:[NSString class]] || !clipboard.length) {
		[SXUI alertOn:self title:@"Bộ nhớ tạm trống" message:@"Sao chép giá trị header trước rồi thử lại."];
		return;
	}
	NSString *firstLine = [[clipboard componentsSeparatedByCharactersInSet:
							[NSCharacterSet newlineCharacterSet]] firstObject];
	self.valueText = [firstLine stringByTrimmingCharactersInSet:
					  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	UITextField *field = [self sx_fieldInSection:1];
	field.text = self.valueText;
	[self sx_validate];
	[field becomeFirstResponder];
	[SXUI tapFeedback];
}

- (void)sx_fieldChanged:(UITextField *)field {
	if (field.tag == 0) self.nameText = field.text ?: @"";
	else self.valueText = field.text ?: @"";
	[self sx_validate];
}

- (void)sx_validate {
	self.issue = SXHeaderValidate(self.nameText, self.valueText, self.existing, self.editing[@"name"]);
	self.navigationItem.rightBarButtonItem.enabled = (self.issue == SXHeaderIssueNone);
	[self sx_refreshHints];
}

- (void)sx_close {
	if (self.navigationController && self.navigationController.viewControllers.count > 1) {
		[self.navigationController popViewControllerAnimated:YES];
		return;
	}
	if (self.navigationController) {
		[self.navigationController dismissViewControllerAnimated:YES completion:nil];
		return;
	}
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)sx_save {
	NSString *name = SXHeaderTrimmedName(self.nameText);
	NSString *value = [self.valueText stringByTrimmingCharactersInSet:
					   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	SXHeaderIssue issue = SXHeaderValidate(name, value, self.existing, self.editing[@"name"]);
	if (issue != SXHeaderIssueNone) {
		self.issue = issue;
		[self sx_validate];
		[SXUI alertOn:self title:@"Header chưa hợp lệ" message:SXHeaderIssueMessage(issue, name)];
		return;
	}
	NSDictionary *header = @{@"name": name, @"value": value,
							 @"enabled": self.editing[@"enabled"] ?: @YES};
	[self.view endEditing:YES];
	if (self.onSave) self.onSave(header);
	[SXUI tapFeedback];
	SXLogInf(@"pref", @"header %@ đã lưu từ màn hình sửa", name);
	[self sx_close];
}

- (void)sx_cancel {
	[self.view endEditing:YES];
	[self sx_close];
}

@end

#pragma mark - Danh sách header

@interface SXHeadersController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic) SXProvider provider;
@property (nonatomic) BOOL providerResolved;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *headers;   // strong: `copy` sẽ biến thành mảng bất biến
/// Nhãn chân bảng được cập nhật tại chỗ: reload section sau mỗi lần gạt công
/// tắc hay xoá hàng là đường dẫn tới exception “invalid update”.
@property (nonatomic, strong) UILabel *footerLabel;
@end

@implementation SXHeadersController

#pragma mark - Nhà cung cấp

- (SXProvider)provider {
	if (!self.providerResolved) {
		NSString *value = nil;
		@try {
			value = [[self specifier] propertyForKey:@"headersProvider"];
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"đọc headersProvider: %@", exception.reason);
		}
		if (![value isKindOfClass:[NSString class]] || !value.length) {
			value = [SXPrefs shared].provider == SXProviderGemini ? @"gemini" : @"openai";
		}
		_provider = [value isEqualToString:@"gemini"] ? SXProviderGemini : SXProviderOpenAI;
		_providerResolved = YES;
	}
	return _provider;
}

/// Endpoint đang cấu hình — dùng để xếp gợi ý khớp lên đầu (OpenRouter, Azure…).
- (NSString *)endpointHint {
	if (self.provider == SXProviderGemini) return @"generativelanguage.googleapis.com";
	NSString *base = [SXPrefs shared].openaiBase;
	return [base isKindOfClass:[NSString class]] ? base : @"";
}

- (SXHeaderPresetProvider)presetProvider {
	return self.provider == SXProviderGemini ? SXHeaderPresetProviderGemini : SXHeaderPresetProviderOpenAI;
}

#pragma mark - Vòng đời

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Header tuỳ chỉnh";
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

	self.navigationItem.rightBarButtonItem =
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
													  target:self
													  action:@selector(sx_addHeader)];
	self.navigationItem.leftBarButtonItem =
		[[UIBarButtonItem alloc] initWithTitle:@"Sửa" style:UIBarButtonItemStylePlain
										target:self action:@selector(sx_toggleEditing)];

	self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.table.translatesAutoresizingMaskIntoConstraints = NO;
	self.table.dataSource = self;
	self.table.delegate = self;
	self.table.rowHeight = UITableViewAutomaticDimension;
	self.table.estimatedRowHeight = 64;
	[self.table registerClass:[SXHeaderRowCell class] forCellReuseIdentifier:@"header"];
	self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
	[self.view addSubview:self.table];
	[NSLayoutConstraint activateConstraints:@[
		[self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];

	[self sx_reloadFromPrefs];
	[self sx_refreshSummary];
	SXLogDbg(@"pref", @"mở header tuỳ chỉnh %@ (%lu mục)",
			 SXProviderDisplayName(self.provider), (unsigned long)self.headers.count);
}

#pragma mark - Dữ liệu

- (void)sx_reloadFromPrefs {
	self.headers = [[[SXPrefs shared] headersForProvider:self.provider] mutableCopy] ?: [NSMutableArray array];
	[self sx_refreshEmptyState];
	@try {
		[self.table reloadData];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"reload header: %@", exception.reason);
	}
}

- (void)sx_persist {
	[SXPrefs setHeaders:self.headers forProvider:self.provider];
	notify_post("com.sirix.tweak/prefs.changed");
	[self sx_refreshEmptyState];
}

- (void)sx_refreshEmptyState {
	if (self.headers.count) {
		self.table.backgroundView = nil;
		return;
	}
	self.table.backgroundView = [SXUI emptyStateWithSymbol:@"list.bullet.rectangle"
													 title:@"Chưa có header nào"
												   message:@"Hầu hết nhà cung cấp không cần header thêm. Chỉ thêm khi gateway hoặc proxy của bạn yêu cầu (OpenRouter, Azure, máy chủ nội bộ…)."];
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	(void)tableView;
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	(void)section;
	return (NSInteger)self.headers.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	(void)section;
	return SXProviderDisplayName(self.provider);
}

- (NSString *)sx_footerText {
	NSString *text = [NSString stringWithFormat:
		@"%@. Header được gửi kèm mọi request tới %@ — kể cả Kiểm tra kết nối và Trò chuyện thử. "
		@"Giá trị chỉ lưu trên máy, không ghi vào log; tắt công tắc để ngừng gửi mà không phải xoá.",
		SXHeadersSummary(self.headers), SXProviderDisplayName(self.provider)];
	if (self.provider == SXProviderOpenAI) {
		NSString *base = [SXPrefs shared].openaiBase;
		if ([base isKindOfClass:[NSString class]] && [base.lowercaseString hasPrefix:@"http://"]) {
			text = [text stringByAppendingString:@"\n\n⚠️ Endpoint đang dùng http:// nên giá trị header "
					@"(kể cả token) đi trên mạng không mã hoá. Hãy đổi sang https:// nếu máy chủ hỗ trợ."];
		}
	}
	return text;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	(void)section;
	if (!self.footerLabel) {
		UILabel *label = [[UILabel alloc] init];
		label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
		label.adjustsFontForContentSizeCategory = YES;
		label.textColor = UIColor.secondaryLabelColor;
		label.numberOfLines = 0;
		self.footerLabel = label;
	}
	self.footerLabel.text = [self sx_footerText];
	self.footerLabel.frame = CGRectMake(0, 0, MAX(tableView.bounds.size.width - 40, 1),
										[self tableView:tableView heightForFooterInSection:section]);
	return self.footerLabel;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	(void)section;
	if (!self.headers.count) return UITableViewAutomaticDimension;
	NSString *text = [self sx_footerText];
	CGRect rect = [text boundingRectWithSize:CGSizeMake(MAX(tableView.bounds.size.width - 56, 1), CGFLOAT_MAX)
									 options:NSStringDrawingUsesLineFragmentOrigin
								  attributes:@{NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]}
									 context:nil];
	return MAX(rect.size.height, 20) + 30;
}

#pragma mark - Cập nhật tại chỗ

/// Đồng bộ lại nhãn chân bảng + dòng trạng thái mà không reload bảng.
- (void)sx_refreshSummary {
	self.footerLabel.text = [self sx_footerText];
	[self.table beginUpdates];
	[self.table endUpdates];
	NSUInteger enabled = 0;
	for (NSDictionary *header in self.headers) {
		if (header[@"enabled"] == nil || [header[@"enabled"] boolValue]) enabled++;
	}
	self.navigationItem.prompt = self.headers.count
		? [NSString stringWithFormat:@"%lu/%lu header đang gửi · %@",
		   (unsigned long)enabled, (unsigned long)self.headers.count,
		   SXProviderDisplayName(self.provider)]
		: SXProviderDisplayName(self.provider);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	SXHeaderRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"header" forIndexPath:indexPath];
	NSDictionary *header = indexPath.row < (NSInteger)self.headers.count ? self.headers[indexPath.row] : nil;
	if (!header) return cell;
	cell.nameLabel.text = header[@"name"];
	cell.valueLabel.text = SXHeaderValueMasked(header[@"value"]);
	cell.toggle.on = header[@"enabled"] == nil || [header[@"enabled"] boolValue];
	cell.toggle.tag = indexPath.row;
	cell.toggle.accessibilityLabel = [NSString stringWithFormat:@"Gửi header %@", header[@"name"]];
	cell.nameLabel.accessibilityLabel = nil;
	[cell.toggle removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
	[cell.toggle addTarget:self action:@selector(sx_toggleChanged:) forControlEvents:UIControlEventValueChanged];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row >= (NSInteger)self.headers.count) return;
	[self sx_editHeaderAtIndex:indexPath.row];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	(void)tableView; (void)indexPath;
	return YES;
}

- (void)tableView:(UITableView *)tableView
commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete) return;
	if (indexPath.row >= (NSInteger)self.headers.count) return;
	NSString *name = self.headers[indexPath.row][@"name"];
	[self.headers removeObjectAtIndex:indexPath.row];
	[self sx_persist];
	@try {
		[self.table deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"deleteRows header: %@", exception.reason);
		[self.table reloadData];
	}
	[SXUI tapFeedback];
	SXLogInf(@"pref", @"xoá header %@ của %@", name, SXProviderDisplayName(self.provider));
	[self sx_refreshSummary];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
	(void)tableView; (void)indexPath;
	return YES;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
	if (from.row >= (NSInteger)self.headers.count || to.row >= (NSInteger)self.headers.count) return;
	NSDictionary *header = self.headers[from.row];
	[self.headers removeObjectAtIndex:from.row];
	[self.headers insertObject:header atIndex:to.row];
	[self sx_persist];
	[self sx_refreshSummary];
}

#pragma mark - Hành động

- (void)sx_toggleEditing {
	BOOL editing = !self.table.isEditing;
	[self.table setEditing:editing animated:YES];
	self.navigationItem.leftBarButtonItem.title = editing ? @"Xong" : @"Sửa";
	self.navigationItem.rightBarButtonItem.enabled = !editing;
}

- (void)sx_toggleChanged:(UISwitch *)sender {
	NSInteger index = sender.tag;
	if (index < 0 || index >= (NSInteger)self.headers.count) return;
	NSDictionary *header = self.headers[index];
	self.headers[index] = @{@"name": header[@"name"] ?: @"", @"value": header[@"value"] ?: @"",
							@"enabled": @(sender.isOn)};
	[self sx_persist];
	[SXUI tapFeedback];
	SXLogDbg(@"pref", @"header %@ → %@", header[@"name"], sender.isOn ? @"bật" : @"tắt");
	[self sx_refreshSummary];
}

- (void)sx_addHeader {
	[self sx_presentEditorWithIndex:NSNotFound];
}

- (void)sx_editHeaderAtIndex:(NSInteger)index {
	[self sx_presentEditorWithIndex:index];
}

- (void)sx_presentEditorWithIndex:(NSInteger)index {
	SXHeaderEditController *editor = [[SXHeaderEditController alloc] init];
	editor.presetProvider = self.presetProvider;
	editor.endpointHint = [self endpointHint];
	editor.existing = [self.headers copy];
	editor.editing = (index != NSNotFound && index < (NSInteger)self.headers.count) ? self.headers[index] : nil;
	__weak typeof(self) weakSelf = self;
	editor.onSave = ^(NSDictionary *header) {
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf || ![header isKindOfClass:[NSDictionary class]]) return;
		if (![header[@"name"] isKindOfClass:[NSString class]] || ![(NSString *)header[@"name"] length]) return;
		if (!strongSelf.headers) strongSelf.headers = [NSMutableArray array];
		NSUInteger count = strongSelf.headers.count;
		if (index != NSNotFound && index < (NSInteger)count) {
			strongSelf.headers[index] = header;
		} else {
			[strongSelf.headers addObject:header];
		}
		[strongSelf sx_persist];
		@try {
			[strongSelf.table reloadData];
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"reload sau lưu header: %@", exception.reason);
		}
		[strongSelf sx_refreshSummary];
		SXLogInf(@"pref", @"lưu header %@ cho %@ (%lu mục)",
				 header[@"name"], SXProviderDisplayName(strongSelf.provider),
				 (unsigned long)strongSelf.headers.count);
	};
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
	[self presentViewController:nav animated:YES completion:nil];
}

@end
