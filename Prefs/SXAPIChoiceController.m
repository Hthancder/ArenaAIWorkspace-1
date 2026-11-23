#import "SXAPIChoiceController.h"
#import "SXChoiceRow.h"
#import "SXUISupport.h"
#import "PSSpecifier.h"
#import "SXLog.h"
#import <notify.h>

/// Ghi chẩn đoán chi tiết của bộ chọn. Bật bằng Cài đặt → Gỡ lỗi → Nhật ký chi
/// tiết (khoá `verbose`), để log thường không bị nhiễu.
static BOOL gSXAPIChoiceVerboseLogging = YES;

@interface SXAPIChoiceController () <UITableViewDataSource, UITableViewDelegate>
// Không khai báo lại `table`: PSListController đã có thuộc tính này, khai báo
// trùng làm clang báo -Wobjc-property-synthesis (thành lỗi vì -Werror).
@property (nonatomic, strong) NSArray *values;          // NSString hoặc NSNumber
@property (nonatomic, strong) NSArray<NSString *> *titles;
@property (nonatomic, strong) NSArray<NSString *> *hints;
@property (nonatomic, copy) NSString *prefsKey;
@property (nonatomic, copy) NSString *screenTitle;
/// Đã dọn reference `sxParent` ở specifier NÀY chưa (xem `sx_customizeOptions:`).
@property (nonatomic) BOOL sxDidCustomize;
/// Giá trị đang lưu, đọc một lần mỗi lần hiện trang (xem `-sx_current`).
@property (nonatomic, copy) NSString *sx_currentCache;
@end

/// Chuẩn hoá `validValues`/`validTitles` từ plist thành mảng CHUỖI.
///
/// Vì sao cần: trang này được dựng bằng tay, nên một plist sai kiểu (số thay vì
/// chuỗi, NSNull, từ điển lồng) từng làm `titles[i]` sai kiểu ⇒
/// `-[__NSCFNumber length]: unrecognized selector` ngay khi bảng hỏi số hàng —
/// biểu hiện đúng là “bấm vào là văng”. Mảng rỗng/hỏng thì trả @[] để trang hiện
/// khối dự phòng, không văng.
static NSArray<NSString *> *SXAPIChoiceStringList(id raw) {
	if (![raw isKindOfClass:[NSArray class]]) return @[];
	NSMutableArray<NSString *> *out = [NSMutableArray array];
	for (id item in (NSArray *)raw) {
		if ([item isKindOfClass:[NSString class]]) [out addObject:item];
		else if ([item isKindOfClass:[NSNumber class]]) [out addObject:[(NSNumber *)item stringValue]];
	}
	return out;
}

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

/// Bọc một khối dựng giao diện: nếu có ngoại lệ thì ghi log rõ ràng và để trang
/// hiện khối dự phòng, KHÔNG để ngoại lệ nổi lên Preferences (làm văng app).
/// Người dùng báo “bấm vào là văng” mà log không có dòng nào thì không sửa được;
/// log + khối dự phòng biến một lần văng thành một báo cáo đọc được.
- (void)sx_guarded:(NSString *)what run:(void (^)(void))block {
	@try {
		block();
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"bộ chọn %@: lỗi khi %@ — %@: %@", self.prefsKey ?: @"(trống)",
				 what, exception.name, exception.reason);
	}
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self sx_guarded:@"nạp lựa chọn" run:^{ [self sx_loadFromSpecifier]; }];
	self.title = self.screenTitle.length ? self.screenTitle : @"Chọn giá trị";

	// Bảng đã được dựng ở `loadView` (cell của Preferences chỉ hiện chữ ở ô
	// "value" và không cho kiểm soát dấu ✓, nên ta tự vẽ).
	self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

	SXLogDbg(@"pref", @"bộ chọn giá trị mở: key=%@, %lu lựa chọn, specifier=%@",
			 self.prefsKey ?: @"(trống)", (unsigned long)self.values.count,
			 NSStringFromClass([self.specifier class]));
}

#pragma mark - Không route "detail" thêm lần nữa

/// Gỡ reference `sxParent` khỏi các hàng của chính mình.
///
/// Vì sao phải làm: hàng “Nhà cung cấp” (và 3 hàng chọn chuỗi khác) khai báo
/// `detail` = `SXAPIChoiceController` trong Root.plist. `PSListController` giữ
/// controller vừa đẩy trong một ivar **có tiền tố `_`** xoá mọi thuộc tính khai
/// báo `detail` trên từng specifier (đó là cách nó nhớ “hàng này đã push”), rồi
/// ở `viewWillAppear:` của trang cha nó lặp lại việc xoá đó. Ta tự dựng bảng và
/// tự xử lý chạm, nên thuộc tính `detail` không còn tác dụng — nhưng nếu để
/// nguyên thì trang cha còn tham chiếu tới controller này và có thể đẩy nó thêm
/// một lần nữa (màn hình mở hai lần / đẩy một controller đã bị gỡ ⇒ văng).
/// Gỡ từ phía ta thì không phải đoán tên ivar nội bộ nào của Apple.
- (void)sx_customizeOptions:(PSSpecifier *)row {
	if (!row || self.sxDidCustomize) return;
	self.sxDidCustomize = YES;
	// Quét MỌI khoá thay vì đoán tên (`sxParent` là một trong các tên đã thấy ở
	// các bản Preferences khác nhau): khoá nào đang giữ một UIViewController mà
	// không phải `detail` thì đó chính là “đã push” — gỡ đi.
	NSMutableDictionary *properties = [row.properties isKindOfClass:[NSMutableDictionary class]]
		? row.properties : nil;
	if (!properties) return;
	NSMutableArray *staleKeys = [NSMutableArray array];
	for (id key in [properties allKeys]) {
		if (![key isKindOfClass:[NSString class]]) continue;
		if ([key isEqualToString:PSCellClassKey] || [key isEqualToString:@"detail"]) continue;
		// Chỉ gỡ giá trị là CONTROLLER: đó là dấu hiệu "hàng này đã push".
		// (Không gỡ NSValue/UIView — chúng có thể là dữ liệu hợp lệ của cell.)
		id value = properties[key];
		if ([value isKindOfClass:[UIViewController class]]) [staleKeys addObject:key];
	}
	for (NSString *key in staleKeys) {
		[row removePropertyForKey:key];
		SXLogDbg(@"pref", @"bộ chọn %@: gỡ khoá “%@” khỏi hàng gọi", self.prefsKey ?: @"(trống)", key);
	}
	// `detail` để nguyên cho lần mở sau (hàng vẫn hiện mũi tên), nhưng ta không
	// phụ thuộc vào nó: bảng dưới đây là bảng thật.
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	// `specifier` có thể tới muộn; thử lại ở đây một lần.
	[self sx_customizeOptions:self.specifier];
	// Đọc lại trong `viewWillAppear` (không phải viewDidLoad): lúc này specifier
	// chắc chắn đã có, và người dùng quay lại trang này sau khi đổi cài đặt ở nơi
	// khác cũng thấy đúng dấu ✓.
	self.sx_currentCache = nil;   // đọc lại prefs đúng một lần cho lần hiện này
	[self sx_refreshFromSpecifierIfNeeded];
	if ([self.view isKindOfClass:[UITableView class]]) [(UITableView *)self.view reloadData];
	[self sx_logDiagnostics];
}

/// Ghi lại đúng những gì trang nhận được. Khi người dùng báo “bấm vào là văng”,
/// dòng log này là thứ phân biệt “không có dữ liệu” với “dữ liệu sai kiểu” —
/// không phải đoán.
- (void)sx_logDiagnostics {
	if (!gSXAPIChoiceVerboseLogging) return;
	PSSpecifier *row = self.specifier;
	SXLogDbg(@"pref", @"bộ chọn %@ · specifier=%@ · values=%lu · titles=%lu",
			 self.prefsKey ?: @"(trống)", row ? NSStringFromClass(row.class) : @"(nil)",
			 (unsigned long)self.values.count, (unsigned long)self.titles.count);
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	(void)tableView;
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	(void)tableView;
	(void)section;
	// Dùng MIN của hai mảng: `titles` ngắn hơn `values` (plist lệch) từng làm
	// cellForRow lấy `titles[i]` ngoài phạm vi ⇒ văng khi bảng hỏi hàng.
	return (NSInteger)MIN(self.values.count, self.titles.count);
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
	NSUInteger row = (NSUInteger)indexPath.row;
	if (indexPath.row < 0 || row >= self.values.count || row >= self.titles.count) {
		return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	}
	NSString *current = [self sx_current];
	NSString *value = [self sx_storedValueAtIndex:row];
	NSString *title = self.titles[row];
	PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:title
															target:nil set:NULL get:NULL
															detail:nil cell:PSListItemCell edit:nil];
	[specifier setProperty:@(SXChoiceCellModeOption) forKey:SXChoiceModeKey];
	[specifier setProperty:@([value isEqualToString:current]) forKey:SXChoiceActiveKey];
	[specifier setProperty:[self sx_hintAtIndex:row] ?: @"" forKey:SXChoiceHintKey];
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
	// Nếu `specifier` chỉ tới sau khi bảng đã dựng, số hàng sẽ là 0 và màn hình
	// trống. Thử đọc lại một lần trước khi hiện khối dự phòng, để người dùng
	// không phải thoát ra vào lại.
	if (!self.values.count && self.specifier) {
		[self sx_loadFromSpecifier];
		if (self.values.count && [self.view isKindOfClass:[UITableView class]]) {
			[(UITableView *)self.view reloadData];
		}
	}
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
		// Khoá KHÁC ⇒ trang đang sử dụng dữ liệu của hàng khác (thường vì
		// `specifier` tới sau `viewDidLoad`). Gán lại rồi nạp lại từ đầu, kể cả
		// khi lần nạp trước đã suy ra nhầm nhánh `openaiApi`.
		self.prefsKey = key;
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
	[self sx_customizeOptions:specifier];
	NSString *key = [specifier propertyForKey:@"configKey"];
	if (!key.length) key = [specifier propertyForKey:@"key"];
	if (!key.length) key = [specifier propertyForKey:PSKeyNameKey];
	// Không đoán bừa khi thiếu key: trước đây rơi về `openaiApi` nên mở nhầm
	// trang sẽ thấy 3 lựa chọn giao thức cho một khoá khác hẳn.
	self.prefsKey = ([key isKindOfClass:[NSString class]] && key.length) ? key : nil;
	self.screenTitle = [specifier propertyForKey:@"label"];
	NSArray *values = SXAPIChoiceStringList([specifier propertyForKey:@"validValues"]);
	NSArray *titles = SXAPIChoiceStringList([specifier propertyForKey:@"validTitles"]);
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
	// Đọc lại prefs MỘT lần cho mỗi lần hiện trang (`sx_currentCache`), không phải
	// mỗi cell: bản cũ gọi `-reload` (CFPreferences + đọc tệp plist dự phòng)
	// trong từng `cellForRow`, tức I/O trên luồng chính N lần cho N hàng.
	if (self.sx_currentCache) return self.sx_currentCache;
	[[SXPrefs shared] reload];
	if ([self.prefsKey isEqualToString:@"openaiApi"]) {
		return SXOpenAIApiStorageKey([SXPrefs shared].openaiApi);
	}
	NSString *value = [SXPrefs stringForKey:self.prefsKey];
	if (!value.length) value = [self sx_defaultValue];
	self.sx_currentCache = value;
	return value;
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
	self.sx_currentCache = nil;
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
