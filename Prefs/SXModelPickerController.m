#import "SXModelPickerController.h"
#import "SXNavigationSupport.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXUISupport.h"
#import "PSSpecifier.h"
#import <notify.h>
#import <UIKit/UIKit.h>

/// Ô mô hình: tên thân thiện ở trên, mã mô hình (chữ đẳng khoảng) ở dưới, gợi ý
/// màu xám. Không dùng PSCell/PSSpecifier: bản trước dựng hàng bằng PSButtonCell
/// và gán `buttonAction` — Preferences thật không có setter đó nên Settings văng
/// ngay khi mở danh sách.
@interface SXModelCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *modelLabel;
@property (nonatomic, strong) UILabel *hintLabel;
- (void)setHint:(NSString *)hint;
@end

@implementation SXModelCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self) return nil;

	_titleLabel = [[UILabel alloc] init];
	_titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	_titleLabel.adjustsFontForContentSizeCategory = YES;
	_titleLabel.numberOfLines = 0;

	_modelLabel = [[UILabel alloc] init];
	_modelLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
	_modelLabel.textColor = UIColor.secondaryLabelColor;
	_modelLabel.numberOfLines = 0;

	_hintLabel = [[UILabel alloc] init];
	_hintLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	_hintLabel.adjustsFontForContentSizeCategory = YES;
	_hintLabel.textColor = UIColor.tertiaryLabelColor;
	_hintLabel.numberOfLines = 0;

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _modelLabel, _hintLabel]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 2;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[self.contentView addSubview:stack];

	UILayoutGuide *margins = self.contentView.layoutMarginsGuide;
	[NSLayoutConstraint activateConstraints:@[
		[stack.topAnchor constraintEqualToAnchor:margins.topAnchor constant:10],
		[stack.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor constant:-10],
		[stack.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
		[stack.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
	]];
	return self;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	self.hintLabel.text = nil;
	self.hintLabel.hidden = NO;
	self.accessoryType = UITableViewCellAccessoryNone;
	self.accessibilityValue = nil;
}

- (void)setHint:(NSString *)hint {
	self.hintLabel.text = hint;
	self.hintLabel.hidden = !hint.length;
}

@end

#pragma mark - Màn hình

@interface SXModelPickerController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic) SXProvider provider;
@property (nonatomic) BOOL providerResolved;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, copy) NSArray<NSDictionary *> *presets;
@property (nonatomic, copy) NSArray<NSDictionary *> *visiblePresets;
@property (nonatomic, copy) NSString *currentModel;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) UISearchController *search;
@end

@implementation SXModelPickerController

#pragma mark - Nhà cung cấp

- (SXProvider)provider {
	if (!self.providerResolved) {
		NSString *value = nil;
		@try {
			value = [[self specifier] propertyForKey:@"providerPicker"];
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"đọc providerPicker: %@", exception.reason);
		}
		if (![value isKindOfClass:[NSString class]] || !value.length) {
			value = [SXPrefs shared].provider == SXProviderGemini ? @"gemini" : @"openai";
		}
		_provider = [value isEqualToString:@"gemini"] ? SXProviderGemini : SXProviderOpenAI;
		_providerResolved = YES;
	}
	return _provider;
}

- (NSString *)modelKey {
	return self.provider == SXProviderGemini ? @"geminiModel" : @"openaiModel";
}

- (NSString *)defaultModel {
	return self.provider == SXProviderGemini ? @"gemini-2.0-flash" : @"gpt-4o-mini";
}

- (NSString *)preferredModel {
	SXPrefs *prefs = [SXPrefs shared];
	NSString *model = self.provider == SXProviderGemini ? prefs.geminiModel : prefs.openaiModel;
	model = [model stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	return model.length ? model : [self defaultModel];
}

- (NSDictionary *)presetForModel:(NSString *)model {
	for (NSDictionary *preset in self.presets) {
		if ([preset[@"model"] isEqualToString:model]) return preset;
	}
	return nil;
}

#pragma mark - Vòng đời

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = [NSString stringWithFormat:@"Mô hình %@", SXProviderDisplayName(self.provider)];
	// Dòng ngữ cảnh dưới tiêu đề: đang cấu hình endpoint nào.
	NSString *endpoint = self.provider == SXProviderGemini
		? @"generativelanguage.googleapis.com"
		: ([SXPrefs normalizedBaseURL:[SXPrefs shared].openaiBase] ?: @"endpoint chưa hợp lệ");
	self.navigationItem.prompt = endpoint;
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
	self.definesPresentationContext = YES;

	self.presets = SXModelPresets(self.provider) ?: @[];
	self.visiblePresets = self.presets;
	self.currentModel = [self preferredModel];

	self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.table.translatesAutoresizingMaskIntoConstraints = NO;
	self.table.dataSource = self;
	self.table.delegate = self;
	self.table.rowHeight = UITableViewAutomaticDimension;
	self.table.estimatedRowHeight = 78;
	[self.table registerClass:[SXModelCell class] forCellReuseIdentifier:@"model"];
	[self.view addSubview:self.table];
	[NSLayoutConstraint activateConstraints:@[
		[self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];

	self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
	self.search.searchResultsUpdater = self;
	self.search.obscuresBackgroundDuringPresentation = NO;
	self.search.hidesNavigationBarDuringPresentation = NO;
	self.search.searchBar.placeholder = @"Tìm mã mô hình";
	self.search.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.search.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
	self.navigationItem.searchController = self.search;
	self.navigationItem.hidesSearchBarWhenScrolling = NO;

	SXLogDbg(@"pref", @"mở danh sách mô hình %@ (%lu gợi ý, đang dùng %@)",
			 SXProviderDisplayName(self.provider), (unsigned long)self.presets.count, self.currentModel);
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	SXEnsureBackButton(self, @"Model");
	// Đổi model ở màn khác (nhập tay trong trang nhà cung cấp) thì phải thấy ngay.
	NSString *latest = [self preferredModel];
	if (![latest isEqualToString:self.currentModel]) {
		self.currentModel = latest;
		[self.table reloadData];
	}
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	SXShowContentFallbackIfNeeded(self, @"Chọn model", @"không có model gợi ý");
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	self.search.active = NO;
}

#pragma mark - Lọc

- (void)sx_applyQuery:(NSString *)query {
	NSString *trimmed = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	self.query = trimmed;
	if (!trimmed.length) {
		self.visiblePresets = self.presets;
	} else {
		NSString *lower = trimmed.lowercaseString;
		NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
		for (NSDictionary *preset in self.presets) {
			NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@",
								  preset[@"model"] ?: @"", preset[@"title"] ?: @"", preset[@"hint"] ?: @""];
			if ([haystack.lowercaseString containsString:lower]) [matches addObject:preset];
		}
		self.visiblePresets = matches;
	}
	[self.table reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
	[self sx_applyQuery:searchController.searchBar.text];
}

#pragma mark - Dữ liệu bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	(void)tableView;
	return 3; // đang dùng · gợi ý · nhập tay
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	(void)tableView;
	if (section == 0) return 1;
	if (section == 1) return (NSInteger)self.visiblePresets.count;
	return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	(void)tableView;
	if (section == 0) return @"Đang dùng";
	if (section == 1) {
		if (self.query.length) {
			return [NSString stringWithFormat:@"Khớp “%@”", [SXUI truncate:self.query limit:24]];
		}
		return [NSString stringWithFormat:@"Gợi ý cho %@", SXProviderDisplayName(self.provider)];
	}
	return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	(void)tableView;
	if (section == 1) {
		if (self.query.length) {
			return self.visiblePresets.count
				? @"Chạm để dùng mô hình. Muốn mã không có trong danh sách, chọn “Nhập mô hình khác”."
				: @"Không có gợi ý nào khớp. Bạn vẫn dùng được mã bất kỳ bằng “Nhập mô hình khác”.";
		}
		if (!self.presets.count) return @"Nhà cung cấp này không có gợi ý sẵn.";
		return @"Danh sách gợi ý là các mô hình phổ biến; endpoint vẫn nhận những mã khác.";
	}
	if (section == 2) {
		return @"Endpoint tương thích OpenAI dùng được mọi tên mô hình nó hỗ trợ (llama-3.3-70b, deepseek-chat…). "
			    "Mô hình suy luận (o4-mini, R1…) trả lời chậm hơn — SiriX vẫn chờ trong ngân sách đã đặt.";
	}
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	SXModelCell *cell = [tableView dequeueReusableCellWithIdentifier:@"model" forIndexPath:indexPath];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.tintColor = [SXUI accentColor];

	if (indexPath.section == 2) {
		cell.titleLabel.text = @"Nhập mô hình khác…";
		cell.titleLabel.textColor = [SXUI accentColor];
		cell.modelLabel.text = nil;
		cell.modelLabel.hidden = YES;
		[cell setHint:@"Gõ đúng mã mô hình mà endpoint của bạn nhận."];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		cell.accessibilityHint = @"Mở hộp thoại nhập mã mô hình.";
		return cell;
	}
	cell.modelLabel.hidden = NO;

	if (indexPath.section == 0) {
		NSDictionary *preset = [self presetForModel:self.currentModel];
		BOOL isDefault = [self.currentModel isEqualToString:[self defaultModel]];
		cell.titleLabel.text = preset[@"title"] ?: @"Mô hình nhập tay";
		cell.titleLabel.textColor = UIColor.labelColor;
		cell.modelLabel.text = self.currentModel;
		NSString *hint = preset[@"hint"];
		if (!hint.length) {
			hint = @"Không nằm trong danh sách gợi ý — vẫn dùng bình thường nếu endpoint hỗ trợ.";
		}
		if (isDefault) hint = [hint stringByAppendingString:@" (mặc định)"];
		[cell setHint:hint];
		cell.accessoryType = UITableViewCellAccessoryCheckmark;
		cell.accessibilityValue = @"Đang dùng";
		return cell;
	}

	NSDictionary *preset = indexPath.row < (NSInteger)self.visiblePresets.count
		? self.visiblePresets[(NSUInteger)indexPath.row] : nil;
	if (!preset) return cell;
	cell.titleLabel.text = preset[@"title"];
	cell.titleLabel.textColor = UIColor.labelColor;
	cell.modelLabel.text = preset[@"model"];
	[cell setHint:preset[@"hint"]];
	BOOL selected = [preset[@"model"] isEqualToString:self.currentModel];
	cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	cell.accessibilityValue = selected ? @"Đang dùng" : nil;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == 2) {
		[self sx_promptForCustomModel];
		return;
	}
	NSString *model = nil;
	if (indexPath.section == 0) {
		model = self.currentModel;
	} else if (indexPath.row < (NSInteger)self.visiblePresets.count) {
		model = self.visiblePresets[(NSUInteger)indexPath.row][@"model"];
	}
	if (![model isKindOfClass:[NSString class]] || !model.length) return;
	if ([model isEqualToString:self.currentModel]) {
		// Chạm lại mô hình đang dùng: không lưu lần nữa, chỉ đóng cho gọn.
		[self.navigationController popViewControllerAnimated:YES];
		return;
	}
	[self sx_saveModel:model];
}

#pragma mark - Lưu

- (BOOL)sx_isValidModel:(NSString *)model {
	if (![model isKindOfClass:[NSString class]] || !model.length) return NO;
	if (model.length > 120) return NO;
	NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
		@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._/:@"];
	return [model rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

- (void)sx_saveModel:(NSString *)model {
	NSString *clean = [model stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (![self sx_isValidModel:clean]) {
		[SXUI alertOn:self
				title:@"Mã mô hình không hợp lệ"
			  message:@"Chỉ dùng chữ, số và các ký tự - . _ / : @, tối đa 120 ký tự. Ví dụ: gpt-4o-mini, gemini-2.0-flash."];
		return;
	}
	[SXPrefs setString:clean forKey:self.modelKey];
	[[SXPrefs shared] reload];
	notify_post("com.sirix.tweak/prefs.changed");
	[SXUI tapFeedback];
	SXLogInf(@"pref", @"chọn mô hình %@ = %@", SXProviderDisplayName(self.provider), clean);
	self.currentModel = clean;
	@try {
		[self.table reloadData];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"reload bảng mô hình: %@", exception.reason);
	}
	[self.navigationController popViewControllerAnimated:YES];
}

- (void)sx_promptForCustomModel {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Mô hình khác"
																  message:@"Nhập đúng mã mô hình mà endpoint của bạn hỗ trợ."
														   preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.placeholder = @"ví dụ: llama-3.3-70b";
		field.text = self.currentModel;
		field.autocapitalizationType = UITextAutocapitalizationTypeNone;
		field.autocorrectionType = UITextAutocorrectionTypeNo;
		field.returnKeyType = UIReturnKeyDone;
		field.clearButtonMode = UITextFieldViewModeWhileEditing;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	__weak UIAlertController *weakAlert = alert;
	[alert addAction:[UIAlertAction actionWithTitle:@"Dùng" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		(void)action;
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		NSString *text = [weakAlert.textFields.firstObject.text
			stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (!text.length) {
			[SXUI alertOn:strongSelf title:@"Chưa nhập gì" message:@"Mã mô hình không được để trống."];
			return;
		}
		[strongSelf sx_saveModel:text];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
