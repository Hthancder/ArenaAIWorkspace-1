#import "SXRootListController.h"
#import "SXLogViewController.h"
#import "PSSpecifier.h"
#import "SXLog.h"
#import "SXPrefs.h"
#import "SXHistoryController.h"
#import "SXStore.h"
#import "SXNetwork.h"
#import "SXLLM.h"
#import "SXTTS.h"
#import "SXConfigIO.h"
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <notify.h>
#import <UIKit/UIKit.h>

#ifndef SX_SCHEME
#define SX_SCHEME "unknown"
#endif

#pragma mark - Chẩn đoán exception

static NSUncaughtExceptionHandler *SXPrevExceptionHandler = NULL;

static void SXExceptionHandler(NSException *exception) {
	SXLogErr(@"pref", @"EXCEPTION không bắt được: %@", exception.name);
	if (SXPrevExceptionHandler) SXPrevExceptionHandler(exception);
}

@interface SXRootListController () <UIDocumentPickerDelegate>
@end

@implementation SXRootListController {
	int _prefsToken;
	BOOL _needsHistoryRoute;
	NSString *_latestVersion, *_trialStatus;
	SXRequest *_voiceTest, *_diagnostics, *_updateCheck;
}

/// Chạy ngay khi bundle được nạp — mốc sớm nhất để chẩn đoán crash khi mở Settings.
+ (void)load {
	SXLogInit();
	SXPrevExceptionHandler = NSGetUncaughtExceptionHandler();
	NSSetUncaughtExceptionHandler(&SXExceptionHandler);
	SXLogInf(@"pref", @"bundle SiriXPreferences NẠP THÀNH CÔNG (process=%@)",
			 NSProcessInfo.processInfo.processName);
}

#pragma mark - Danh sách

- (NSArray *)specifiers {
	if (!_specifiers) {
		SXLogInf(@"pref", @"bắt đầu tạo bảng cài đặt…");
		NSMutableArray *loaded = nil;
		@try {
			loaded = [self loadSpecifiersFromPlistName:@"Root" target:self];
		} @catch (NSException *exception) {
			SXLogErr(@"pref", @"loadSpecifiers EXCEPTION: %@", exception.name);
			loaded = nil;
		}
		if (!loaded) {
			// Bảng dự phòng tối giản — Settings không được crash.
			PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"SiriX"];
			[group setProperty:@"Tải bảng cài đặt thất bại. Hãy gửi log tại "
							  @"/var/mobile/Library/Logs/SiriX.log để mình sửa."
					   forKey:@"footerText"];
			loaded = [NSMutableArray arrayWithObject:group];
		}

		SXPrefs *prefs = [[SXPrefs shared] snapshot];
		for (PSSpecifier *specifier in loaded) {
			if ([specifier.identifier isEqual:@"sx-provider-config"]) {
				specifier.name = [NSString stringWithFormat:@"Cấu hình %@", SXProviderName(prefs.provider)];
				[specifier setProperty:SXProviderID(prefs.provider) forKey:@"sxProvider"];
			}
			if ([specifier.identifier isEqual:@"sx-history"] && prefs.incognito) specifier.name = @"Lịch sử (không lưu lượt mới)";
		}
		_specifiers = [self sx_visibleSpecifiers:loaded settings:prefs.settings];
		SXLogInf(@"pref", @"bảng cài đặt sẵn sàng: %lu specifier", (unsigned long)_specifiers.count);
	}
	return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
	@try {
		NSString *key = [specifier propertyForKey:@"key"];
		if ([key isEqualToString:@"status"]) return [self statusText];
		if ([key isEqual:@"packageScheme"]) return @SX_SCHEME;
		if ([key isEqual:@"installedVersion"]) return SX_VERSION;
		if ([key isEqual:@"latestVersion"]) return _latestVersion ?: @"Chưa kiểm tra";
		if ([key isEqual:@"sttTrialStatus"]) return _trialStatus ?: @"Chưa thử";
		return [super readPreferenceValue:specifier];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"readPreferenceValue EXCEPTION: %@", exception.name);
		return nil;
	}
}

- (NSString *)statusText {
	SXPrefs *prefs = [SXPrefs shared];
	if (!prefs.enabled) return @"Đã tắt";
	if (prefs.localOnly) return @"Chỉ dùng Siri gốc";
	NSString *provider = SXProviderName(prefs.provider);
	if (SXChatIssue(prefs.settings, prefs.provider)) return [NSString stringWithFormat:@"%@ · Chưa đủ cấu hình", provider];
	return [NSString stringWithFormat:@"%@ · %@", provider, [prefs.triggerMode isEqual:@"prefix"] ? @"Chờ tiền tố @ai" : @"Sẵn sàng"];
}

#pragma mark - Vòng đời

- (void)viewDidLoad {
	[super viewDidLoad];
	SXLogInf(@"pref", @"viewDidLoad — start");
	self.title = @"SiriX";

	@try {
		[self buildHeader];
	} @catch (NSException *exception) {
		SXLogErr(@"pref", @"buildHeader EXCEPTION: %@", exception.name);
	}

	// Tải lại cài đặt + danh sách mỗi khi có thay đổi (áp dụng ngay, không cần mở lại trang).
	__weak SXRootListController *weakSelf = self;
	notify_register_dispatch("com.sirix.tweak/prefs.changed", &_prefsToken,
							 dispatch_get_main_queue(), ^(int token) {
		[[SXPrefs shared] reload];
		SXRootListController *strongSelf = weakSelf;
		if (strongSelf.viewIfLoaded.window && strongSelf.navigationController.topViewController == strongSelf) {
			@try {
				[strongSelf sx_refreshLayout];
				[strongSelf reloadSpecifierID:@"sx-status" animated:NO];
			} @catch (NSException *exception) {
				SXLogErr(@"pref", @"reloadSpecifiers EXCEPTION: %@", exception.name);
			}
		}
	});
	SXLogInf(@"pref", @"viewDidLoad — xong");
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[_voiceTest cancel]; _voiceTest = nil;
	SXTTSStop();
}
- (void)dealloc {
	if (_prefsToken) notify_cancel(_prefsToken);
	[_diagnostics cancel]; [_updateCheck cancel]; [_voiceTest cancel];
}
- (void)handleURL:(NSURL *)url {
	NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
	NSString *path = [[components.queryItems filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name == 'path'"]] firstObject].value;
	if ([path isEqual:@"sx-history"]) {
		_needsHistoryRoute = YES;
		[self routeHistoryIfVisible];
		return;
	}
	[super handleURL:url];
}
- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self refreshSTTTrial];
	[self routeHistoryIfVisible];
}
- (void)routeHistoryIfVisible {
	if (!_needsHistoryRoute || !self.viewIfLoaded.window || self.navigationController.topViewController != self) return;
	_needsHistoryRoute = NO;
	[self pushController:[SXHistoryController new] animate:NO];
}

- (void)buildHeader {
	// Tìm UITableView: có thể là self.view hoặc một trong các subview (iOS 15).
	UITableView *table = nil;
	if ([self.view isKindOfClass:[UITableView class]]) {
		table = (UITableView *)self.view;
	} else {
		for (UIView *subview in self.view.subviews) {
			if ([subview isKindOfClass:[UITableView class]]) {
				table = (UITableView *)subview;
				break;
			}
		}
	}
	if (!table) {
		NSMutableArray<NSString *> *subviewClasses = [NSMutableArray array];
		for (UIView *subview in self.view.subviews) {
			[subviewClasses addObject:NSStringFromClass(subview.class)];
		}
		SXLogWrn(@"pref", @"không tìm thấy UITableView (view=%@, subviews=%@) — bỏ header",
				 NSStringFromClass(self.view.class),
				 [subviewClasses componentsJoinedByString:@","]);
		return;
	}

	CGFloat width = UIScreen.mainScreen.bounds.size.width;
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 124)];

	UIImage *iconImage = [UIImage imageNamed:@"SiriXIcon"
									inBundle:[NSBundle bundleForClass:self.class]
			   compatibleWithTraitCollection:nil];
	UIImageView *iconView = [[UIImageView alloc] initWithImage:iconImage];
	iconView.frame = CGRectMake((width - 68) / 2, 10, 68, 68);
	iconView.contentMode = UIViewContentModeScaleAspectFill;
	iconView.layer.cornerRadius = 15;
	iconView.clipsToBounds = YES;
	iconView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
	[header addSubview:iconView];

	UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 84, width, 28)];
	titleLabel.text = @"SiriX";
	titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightSemibold];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.adjustsFontSizeToFitWidth = YES;
	titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[header addSubview:titleLabel];

	UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 112, width, 16)];
	subtitleLabel.text = @"Trợ lý AI ngay trong giao diện Siri";
	subtitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
	subtitleLabel.textColor = [UIColor secondaryLabelColor];
	subtitleLabel.textAlignment = NSTextAlignmentCenter;
	subtitleLabel.adjustsFontSizeToFitWidth = YES;
	subtitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[header addSubview:subtitleLabel];

	table.tableHeaderView = header;
	SXLogInf(@"pref", @"header cài đặt đã gắn (icon=%d, table=%@)", iconImage != nil,
			 NSStringFromClass([table class]));
}

#pragma mark - Hành động

- (void)sx_respring:(id)sender {
	notify_post("com.sirix.respring");
}

- (void)showAlert:(NSString *)title message:(NSString *)message error:(BOOL)isError {
	if (!self.view.window || self.presentedViewController) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
																   message:message
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
	(void)isError;
}

#pragma mark - Kiểm tra và media

- (void)refreshSTTTrial {
	if (![SXPrefs shared].sttEnabled) return;
	__weak typeof(self) weakSelf = self;
	dispatch_async([SXStore queue], ^{
		NSDictionary *trial = [[SXStore shared] snapshot][@"sttTrial"];
		NSString *status = trial[@"status"];
		NSString *text = @"Chưa thử";
		if ([status isEqual:@"ok"]) text = @"✓ STT nhận được câu nói";
		else if ([status isEqual:@"fallback"]) text = @"Đã dùng nhận diện Apple";
		else if (status && [trial[@"expires"] doubleValue] > CFAbsoluteTimeGetCurrent()) text = @"Đang chờ câu Siri";
		else if (status) text = @"Đã hết thời gian thử";
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) self = weakSelf; if (!self) return;
			self->_trialStatus = text;
			if ([self specifierForID:@"sx-stt-trial"]) [self reloadSpecifierID:@"sx-stt-trial" animated:NO];
		});
	});
}
- (void)sx_testSTT:(id)sender {
	(void)sender;
	[[SXPrefs shared] reload];
	SXPrefs *prefs = [SXPrefs shared];
	if (!prefs.enabled || !prefs.sttEnabled || prefs.localOnly) {
		[self showAlert:@"Không thể thử STT" message:prefs.localOnly ? @"Tắt Chỉ dùng Siri gốc để cho phép gửi âm thanh." : @"Bật SiriX và nhận diện giọng nói trước khi thử." error:NO]; return;
	}
	NSDictionary *config = SXSTTConfiguration(prefs.settings);
	if (config[@"issue"]) {
		[self showAlert:@"Nguồn STT chưa sẵn sàng" message:config[@"issue"] error:NO]; return;
	}
	NSString *hint = [prefs.triggerMode isEqual:@"prefix"] ? @"Apple phải nhận được tiền tố @ai thì SiriX mới gửi âm thanh. " : @"";
	NSString *message = [NSString stringWithFormat:@"%@Trong 60 giây, mở Siri và nói một câu thử không chứa thông tin riêng tư. Âm thanh sẽ gửi đến %@. Quay lại đây để xem kết quả; không cần cấp mic cho Cài đặt.",
		hint, SXProviderName(SXProviderFromID(config[@"source"]))];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Thử STT trên Siri" message:message preferredStyle:UIAlertControllerStyleAlert];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:@"Bắt đầu" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		(void)action;
		dispatch_async([SXStore queue], ^{
			BOOL ok = [[SXStore shared] armSTTTrial];
			dispatch_async(dispatch_get_main_queue(), ^{
				if (ok) [weakSelf refreshSTTTrial];
				else [weakSelf showAlert:@"Không tạo được lượt thử" message:@"Kiểm tra quyền ghi kho SiriX." error:YES];
			});
		});
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}
- (void)sx_testVoice:(id)sender {
	(void)sender;
	[_voiceTest cancel]; _voiceTest = nil;
	[[SXPrefs shared] reload];
	SXPrefs *prefs = [[SXPrefs shared] snapshot];
	if ([prefs.ttsMode isEqual:@"off"]) return;
	SXTTSStop();
	NSString *fallbackNote = SXTTSConfiguration(prefs.settings)[@"issue"];
	if (prefs.localOnly && ![prefs.ttsSource isEqual:@"system"]) fallbackNote = @"Chỉ dùng Siri gốc đang chặn kết nối tới nguồn trực tuyến.";
	SXRequest *request = [[SXRequest alloc] initWithTimeout:2];
	_voiceTest = request;
	BOOL english = SXConfigShowsRule(@"tts-picker", prefs.settings) && [prefs.ttsLang isEqual:@"en"];
	NSString *text = english ? @"Hello, this is SiriX." : @"Xin chào, đây là SiriX.";
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		SXTTSPlan *selected = SXTTSPrepare(text, prefs, request);
		SXTTSPlan *plan = selected ?: SXTTSSystemPlan(text, prefs);
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) self = weakSelf;
			if (!self || self->_voiceTest != request || !self.view.window) return;
			self->_voiceTest = nil;
			if (![prefs.settings isEqual:[SXPrefs shared].settings]) return;
			if (plan) SXTTSPlay(plan, nil);
			if (!selected) [self showAlert:@"Đang thử giọng hệ thống" message:fallbackNote ?: @"Không phát được từ nguồn đã chọn trong thời gian chờ." error:NO];
		});
	});
}
- (void)sx_diagnostics:(id)sender {
	(void)sender;
	if (_diagnostics) return;
	[[SXPrefs shared] reload];
	SXPrefs *prefs = [[SXPrefs shared] snapshot];
	SXRequest *request = [[SXRequest alloc] initWithTimeout:6];
	_diagnostics = request;
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		BOOL offline = SXDefinitelyOffline();
		NSString *sttIssue = SXSTTConfiguration(prefs.settings)[@"issue"];
		NSString *mic = !prefs.sttEnabled ? @"STT đang tắt." :
			((prefs.localOnly || !prefs.enabled) ? @"STT chưa chạy khi SiriX tắt hoặc chỉ dùng Siri gốc." : (sttIssue ?: @"Đã cấu hình; dùng Thử STT để kiểm tra mic trong Siri."));
		NSString *chatIssue = SXChatIssue(prefs.settings, prefs.provider);
		NSString *endpoint = chatIssue ?: @"Chưa thử kết nối.";
		if (!offline && !chatIssue && !prefs.localOnly) {
			__block NSString *result;
			[SXLLM performQuestion:@"Reply with OK." history:@[] tools:@[] executor:nil prefs:prefs provider:prefs.provider model:nil
				prompt:@"Connection check." maxTokens:64 request:request progress:nil completion:^(NSString *answer, NSError *error, NSDictionary *info) {
					(void)info; result = error ? [NSString stringWithFormat:@"API chưa phản hồi thành công (mã %ld).", (long)error.code] : (answer.length ? @"✓ API hoạt động." : @"API không trả nội dung.");
				}];
			endpoint = result ?: endpoint;
		}
		NSString *message = [NSString stringWithFormat:@"Nhà cung cấp: %@\nMạng: %@\nMic: %@\nAPI: %@",
			SXProviderName(prefs.provider), prefs.localOnly ? @"Không gửi mạng (cài đặt)" : (offline ? @"Không có kết nối" : @"Có tuyến kết nối"), mic, endpoint];
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) self = weakSelf; if (!self || self->_diagnostics != request) return;
			self->_diagnostics = nil; [self showAlert:@"Kiểm tra nhanh" message:message error:NO];
		});
	});
}
- (void)sx_clearStats:(id)sender {
	(void)sender;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Xóa thống kê?" message:@"Không thể hoàn tác. Lịch sử không thay đổi." preferredStyle:UIAlertControllerStyleAlert];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:@"Xóa" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		(void)action;
		dispatch_async([SXStore queue], ^{
			BOOL ok = [[SXStore shared] clearStats];
			dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf showAlert:(ok ? @"Đã xóa thống kê" : @"Không xóa được thống kê") message:nil error:!ok]; });
		});
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}
- (void)sx_checkUpdate:(id)sender {
	(void)sender;
	if (_updateCheck) return;
	if ([SXPrefs shared].localOnly) {
		[self showAlert:@"Không thể kiểm tra cập nhật" message:@"Chỉ dùng Siri gốc đang chặn kết nối mạng của SiriX." error:NO]; return;
	}
	SXRequest *request = [[SXRequest alloc] initWithTimeout:5]; _updateCheck = request;
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		NSMutableURLRequest *get = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.github.com/repos/Hthancder/ArenaAIWorkspace-1/releases/latest"]];
		[get setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
		NSDictionary *response = SXHTTP(get, request, 256 * 1024, NULL);
		id raw = nil;
		if ([response[@"status"] integerValue] == 200 && [response[@"data"] length]) {
			id package = [NSJSONSerialization JSONObjectWithData:response[@"data"] options:0 error:NULL];
			if ([package isKindOfClass:NSDictionary.class]) raw = package[@"tag_name"];
		}
		NSString *tag = [raw isKindOfClass:NSString.class] && [raw length] <= 32 ? raw : nil;
		NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"^v?[0-9]+[.][0-9]+[.][0-9]+$" options:0 error:NULL];
		if (!tag || ![pattern numberOfMatchesInString:tag options:0 range:NSMakeRange(0, tag.length)]) tag = nil;
		if (!tag) SXLogDbg(@"pref", @"không đọc được tag phát hành ổn định (HTTP %ld).", (long)[response[@"status"] integerValue]);
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) self = weakSelf; if (!self || self->_updateCheck != request) return;
			self->_updateCheck = nil;
			if (tag) {
				NSString *version = [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag;
				self->_latestVersion = [version compare:SX_VERSION options:NSNumericSearch] == NSOrderedDescending ? [version stringByAppendingString:@" — có bản mới"] : version;
			} else {
				self->_latestVersion = [response[@"status"] integerValue] == 404 ? @"Chưa có bản ổn định" : @"Không kiểm tra được";
			}
			[self reloadSpecifierID:@"sx-latest" animated:YES];
		});
	});
}

#pragma mark - Xuất và nhập cấu hình

- (void)sx_export:(id)sender {
	(void)sender;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Xuất cấu hình" message:@"Mặc định không kèm khóa API. Nếu xuất kèm khóa, tệp chứa bí mật ở dạng văn bản; chỉ lưu hoặc gửi cho người bạn tin tưởng." preferredStyle:UIAlertControllerStyleAlert];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:@"Xuất không kèm khóa" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { (void)action; [weakSelf exportIncludingKeys:NO]; }]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Xuất kèm khóa" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { (void)action; [weakSelf exportIncludingKeys:YES]; }]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}
- (void)exportIncludingKeys:(BOOL)includeKeys {
	[[SXPrefs shared] reload];
	NSData *data = SXExportConfig([SXPrefs shared].settings, includeKeys, NULL);
	NSURL *dir = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
	NSURL *path = [dir URLByAppendingPathComponent:@"SiriX-config.json"];
	NSFileManager *files = NSFileManager.defaultManager;
	if (!data || ![files createDirectoryAtURL:dir withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions: @0700} error:NULL] ||
		![data writeToURL:path options:NSDataWritingAtomic | NSDataWritingFileProtectionComplete error:NULL] ||
		![files setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:path.path error:NULL]) {
		[files removeItemAtURL:dir error:NULL];
		[self showAlert:@"Không xuất được" message:@"Không tạo được tệp cấu hình." error:YES]; return;
	}
	UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[path] applicationActivities:nil];
	share.popoverPresentationController.sourceView = self.view;
	share.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
	share.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *error) {
		(void)type; (void)completed; (void)items; (void)error; [files removeItemAtURL:dir error:NULL];
	};
	[self presentViewController:share animated:YES completion:nil];
}
- (void)sx_import:(id)sender {
	(void)sender;
	UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
	picker.delegate = self; picker.allowsMultipleSelection = NO;
	[self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	(void)controller;
	NSURL *url = urls.firstObject;
	if (!url.isFileURL) return;
	[[SXPrefs shared] reload];
	NSDictionary *current = [SXPrefs shared].settings;
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		BOOL scoped = [url startAccessingSecurityScopedResource];
		NSData *data = nil;
		NSFileHandle *file = [NSFileHandle fileHandleForReadingFromURL:url error:NULL];
		@try { data = [file readDataUpToLength:128 * 1024 + 1 error:NULL]; }
		@catch (NSException *ignored) { (void)ignored; }
		@finally {
			[file closeFile]; if (scoped) [url stopAccessingSecurityScopedResource];
		}
		NSError *error = nil;
		NSDictionary *plan = data ? SXImportConfig(data, current, &error) : nil;
		dispatch_async(dispatch_get_main_queue(), ^{
			if (plan) [weakSelf confirmImport:plan previous:current];
			else { SXLogWrn(@"pref", @"import: tệp không hợp lệ"); [weakSelf showAlert:@"Không nhập được" message:error.localizedDescription ?: @"Không đọc được tệp." error:YES]; }
		});
	});
}
- (void)confirmImport:(NSDictionary *)plan previous:(NSDictionary *)before {
	NSDictionary *values = plan[@"set"]; NSArray *remove = plan[@"remove"];
	if (!values.count && !remove.count) { [self showAlert:@"Không có thay đổi" message:nil error:NO]; return; }
	NSString *message = [NSString stringWithFormat:@"Sẽ đổi %lu mục và xóa %lu khóa cũ do đổi nguồn/địa chỉ. Endpoint và các công tắc chia sẻ dữ liệu có thể thay đổi. Chỉ xác nhận nếu bạn tin tưởng tệp này.", (unsigned long)values.count, (unsigned long)remove.count];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Nhập cấu hình?" message:message preferredStyle:UIAlertControllerStyleAlert];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:@"Nhập" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		(void)action;
		[[SXPrefs shared] reload];
		if (![[SXPrefs shared].settings isEqual:before]) {
			[weakSelf showAlert:@"Cấu hình vừa thay đổi" message:@"Chọn lại tệp để xem các thay đổi mới." error:YES]; return;
		}
		if (![SXPrefs writeValues:values removing:remove]) {
			[weakSelf showAlert:@"Không lưu được cấu hình" message:@"Kiểm tra quyền ghi Cài đặt." error:YES]; return;
		}
		[[SXPrefs shared] reload];
		notify_post("com.sirix.tweak/prefs.changed");
		[weakSelf reloadSpecifiers];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
	if (self.view.window && !self.presentedViewController) [self presentViewController:alert animated:YES completion:nil];
}

@end
