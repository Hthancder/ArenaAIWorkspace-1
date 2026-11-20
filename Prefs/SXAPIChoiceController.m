#import "SXAPIChoiceController.h"
#import "SXChoiceRow.h"
#import "SXUISupport.h"
#import "PSSpecifier.h"
#import "SXLog.h"
#import <notify.h>

@interface SXAPIChoiceController () <UITableViewDataSource, UITableViewDelegate>
// Không khai báo lại `table`: PSListController đã có thuộc tính này, khai báo
// trùng làm clang báo -Wobjc-property-synthesis (thành lỗi vì -Werror).
@property (nonatomic, strong) NSArray *values;          // NSString hoặc NSNumber
@property (nonatomic, strong) NSArray<NSString *> *titles;
@property (nonatomic, strong) NSArray<NSString *> *hints;
@property (nonatomic, copy) NSString *prefsKey;
@property (nonatomic, copy) NSString *screenTitle;
@end

@implementation SXAPIChoiceController

- (void)loadView {
	// Không gọi `[super loadView]`: nó dựng bảng grouped mặc định rồi ta lại
	// thay ở viewDidLoad. Dựng thẳng bảng inset-grouped và gắn datasource.
	UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	table.dataSource = self;
	table.delegate = self;
	table.rowHeight = UITableViewAutomaticDimension;
	table.estimatedRowHeight = 56;
	table.backgroundColor = UIColor.systemGroupedBackgroundColor;
	self.view = table;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self sx_loadFromSpecifier];
	self.title = self.screenTitle.length ? self.screenTitle : @"Chọn giá trị";

	// Bảng đã được dựng ở `loadView` (cell của Preferences chỉ hiện chữ ở ô
	// "value" và không cho kiểm soát dấu ✓, nên ta tự vẽ).
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

	SXLogDbg(@"pref", @"bộ chọn giá trị mở: key=%@, %lu lựa chọn, specifier=%@",
			 self.prefsKey ?: @"(trống)", (unsigned long)self.values.count,
			 NSStringFromClass([self.specifier class]));
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	(void)tableView;
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	(void)tableView;
	(void)section;
	return (NSInteger)self.values.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	(void)tableView;
	(void)section;
	return self.screenTitle.length ? self.screenTitle : @"Chọn giá trị";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	(void)tableView;
	(void)section;
	return [self.specifier propertyForKey:@"footerText"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.row < 0 || (NSUInteger)indexPath.row >= self.values.count) {
		return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	}
	NSString *current = [self sx_current];
	NSString *value = [self sx_storedValueAtIndex:(NSUInteger)indexPath.row];
	NSString *title = self.titles[(NSUInteger)indexPath.row];
	PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:title
															target:nil set:NULL get:NULL
															detail:nil cell:PSListItemCell edit:nil];
	[specifier setProperty:@(SXChoiceCellModeOption) forKey:SXChoiceModeKey];
	[specifier setProperty:@([value isEqualToString:current]) forKey:SXChoiceActiveKey];
	[specifier setProperty:[self sx_hintAtIndex:(NSUInteger)indexPath.row] forKey:SXChoiceHintKey];
	return [SXChoiceRow cellForTable:tableView specifier:specifier];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row < 0 || (NSUInteger)indexPath.row >= self.values.count) return;
	[self sx_choose:(NSUInteger)indexPath.row];
}

/// Chuỗi thật được lưu cho lựa chọn thứ `index` (khác với nhãn hiển thị).
- (NSString *)sx_storedValueAtIndex:(NSUInteger)index {
	id candidate = self.values[index];
	NSString *stored = [candidate isKindOfClass:[NSString class]] ? candidate : [candidate description];
	if ([self.prefsKey isEqualToString:@"openaiApi"]) {
		stored = SXOpenAIApiStorageKey([candidate isKindOfClass:[NSNumber class]]
			? (SXOpenAIApi)[candidate integerValue] : SXOpenAIApiAuto);
	}
	return stored;
}

- (NSString *)sx_hintAtIndex:(NSUInteger)index {
	return index < self.hints.count ? self.hints[index] : nil;
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	SXShowContentFallbackIfNeeded(self, self.screenTitle ?: @"Chọn giá trị",
								  @"không đọc được danh sách lựa chọn");
}

/// `specifier` (hàng vừa bấm) có thể tới sau `viewDidLoad`; nếu lúc đó đang
/// dùng giá trị mặc định thì đọc lại. Không đọc lại thì trang hiện đúng số
/// hàng nhưng của SAI khoá — hoặc rỗng nếu plist không có `validValues`.
- (void)sx_refreshFromSpecifierIfNeeded {
	@try {
		PSSpecifier *specifier = self.specifier;
		if (!specifier) return;
		NSString *key = [specifier propertyForKey:@"configKey"];
		if (!key.length) key = [specifier propertyForKey:@"key"];
		if (!key.length) key = [specifier propertyForKey:PSKeyNameKey];
		if (![key isKindOfClass:[NSString class]] || !key.length) return;
		if ([key isEqualToString:self.prefsKey]) return;
		[self sx_loadFromSpecifier];
		self.title = self.screenTitle.length ? self.screenTitle : @"Chọn giá trị";
		_specifiers = nil;
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"đọc lại specifier: %@", exception.reason);
	}
}

/// Đọc `key`, `validValues`, `validTitles` (và `footerText` làm gợi ý) từ đúng
/// hàng gọi nó. Một controller phục vụ mọi câu “chọn một trong vài giá trị”,
/// nên không còn lớp Apple nào phải đoán dữ liệu nằm ở đâu.
- (void)sx_loadFromSpecifier {
	PSSpecifier *specifier = self.specifier;
	NSString *key = [specifier propertyForKey:@"configKey"];
	if (!key.length) key = [specifier propertyForKey:@"key"];
	if (!key.length) key = [specifier propertyForKey:PSKeyNameKey];
	// Không đoán bừa khi thiếu key: trước đây rơi về `openaiApi` nên mở nhầm
	// trang sẽ thấy 3 lựa chọn giao thức cho một khoá khác hẳn.
	self.prefsKey = ([key isKindOfClass:[NSString class]] && key.length) ? key : nil;
	self.screenTitle = [specifier propertyForKey:@"label"];
	NSArray *values = [specifier propertyForKey:@"validValues"];
	NSArray *titles = [specifier propertyForKey:@"validTitles"];
	if (![values isKindOfClass:[NSArray class]] || !values.count) {
		// Chỉ trang “Giao thức API” mới không khai báo validValues trong plist.
		if ([self.prefsKey isEqualToString:@"openaiApi"]) {
			values = @[@"auto", @"responses", @"chat"];
		} else {
			SXLogWrn(@"pref", @"bộ chọn %@ thiếu validValues trong plist (specifier=%@)",
					 self.prefsKey ?: @"(trống)", NSStringFromClass(specifier.class));
			values = @[];
		}
	}
	if (![titles isKindOfClass:[NSArray class]] || titles.count != values.count) {
		if ([self.prefsKey isEqualToString:@"openaiApi"]) {
			titles = @[@"Tự dò", @"Responses API", @"Chat completions"];
		} else {
			titles = values;
		}
	}
	self.values = values;
	self.titles = titles;
	NSString *footer = [specifier propertyForKey:@"footerText"];
	self.hints = footer.length ? @[] : @[];
	(void)footer;
}

/// Giá trị đang lưu (dạng chuỗi đã chuẩn hoá), đọc lại từ đĩa mỗi lần vẽ để
/// không hiện ✓ cũ. Dùng chung phép chuẩn hoá với lúc ghi.
- (NSString *)sx_current {
	if (!self.prefsKey.length) return [self sx_defaultValue];
	[[SXPrefs shared] reload];
	if ([self.prefsKey isEqualToString:@"openaiApi"]) {
		return SXOpenAIApiStorageKey([SXPrefs shared].openaiApi);
	}
	NSString *value = [SXPrefs stringForKey:self.prefsKey];
	return value.length ? value : [self sx_defaultValue];
}

- (NSString *)sx_defaultValue {
	NSString *value = [self.specifier propertyForKey:@"default"];
	if ([value isKindOfClass:[NSString class]] && value.length) return value;
	if ([self.prefsKey isEqualToString:@"openaiApi"]) return @"auto";
	return [self.values.firstObject isKindOfClass:[NSString class]] ? self.values.firstObject : @"";
}

/// `PSListController` không tự hiện dấu "đang chọn" cho PSListItemCell — giá trị
/// trả về ở đây được cell vẽ ở phía phải (cùng chỗ với chữ "Giá trị" của hàng
/// số), nên chỉ cần trả "✓" cho hàng đang dùng.
- (id)readPreferenceValue:(PSSpecifier *)specifier {
	// Trả giá trị THẬT (không phải "✓"): cell của Preferences tra giá trị này
	// trong `validValues`, trả chuỗi trang trí thì ô giá trị sẽ rỗng.
	(void)specifier;
	return [self sx_current];
}

/// Ghi lựa chọn và quay lại trang trước. Không có bước "lưu xong mà không thấy
/// gì": ghi → đọc lại → phát notify → rung → log → pop, và trang gốc vẽ lại giá
/// trị mới nhờ notify.
- (void)sx_choose:(NSUInteger)index {
	if (!self.prefsKey.length) {
		[SXUI alertOn:self title:@"Chưa xác định được khoá cài đặt"
			  message:@"Mở lại trang này từ màn hình chính SiriX. Nếu vẫn lỗi, vào Gỡ lỗi → Xem log để gửi lại."];
		return;
	}
	if (index >= self.values.count) return;
	NSString *stored = [self sx_storedValueAtIndex:index];
	[SXPrefs setString:stored forKey:self.prefsKey];
	[[SXPrefs shared] reload];
	notify_post("com.sirix.tweak/prefs.changed");
	[SXUI tapFeedback];
	SXLogInf(@"pref", @"chọn %@ = %@ (nhãn “%@”)", self.prefsKey, stored,
			 index < self.titles.count ? self.titles[index] : @"?");
	if ([self.view isKindOfClass:[UITableView class]]) [(UITableView *)self.view reloadData];
	if (self.navigationController.viewControllers.count > 1) {
		[self.navigationController popViewControllerAnimated:YES];
	} else {
		[self dismissViewControllerAnimated:YES completion:nil];
	}
}

@end
