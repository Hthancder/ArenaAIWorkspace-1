#import "SXStatsController.h"
#import "SXStore.h"
#import <UIKit/UIKit.h>

@interface SXStatsController ()
@property (nonatomic, strong) UITextView *text;
@end
@implementation SXStatsController
- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Thống kê";
	self.view.backgroundColor = UIColor.systemBackgroundColor;
	self.text = [[UITextView alloc] initWithFrame:self.view.bounds];
	self.text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.text.editable = NO;
	self.text.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	self.text.textContainerInset = UIEdgeInsetsMake(20, 18, 20, 18);
	[self.view addSubview:self.text];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Xóa" style:UIBarButtonItemStylePlain target:self action:@selector(confirmClear)];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refresh]; }
- (void)refresh {
	__weak typeof(self) weakSelf = self;
	dispatch_async([SXStore queue], ^{
		NSDictionary *snapshot = [[SXStore shared] snapshot];
		dispatch_async(dispatch_get_main_queue(), ^{
			typeof(self) self = weakSelf;
			if (!self) return;
			if (!snapshot) { self.text.text = @"Không đọc được thống kê. Kiểm tra quyền ghi kho SiriX."; return; }
			NSDictionary *stats = snapshot[@"stats"];
			NSInteger replaced = [stats[@"replaced"] integerValue], kept = [stats[@"kept"] integerValue];
			double rate = replaced + kept ? (100.0 * replaced / (replaced + kept)) : 0;
			self.text.text = [NSString stringWithFormat:@"Đã thay phản hồi: %ld\nGiữ Siri gốc: %ld\nHết giờ: %ld\nLỗi AI: %ld\nTỉ lệ thay: %.1f%%\nThời gian AI trung bình có trọng số: %.0f ms\n\nHết giờ và lỗi có thể đồng thời được tính vào thay hoặc giữ. Tác vụ hệ thống không tính vào tỉ lệ. Số liệu ghi theo lượt đã quan sát, không phải chi phí API.", (long)replaced, (long)kept, (long)[stats[@"timeout"] integerValue], (long)[stats[@"error"] integerValue], rate, [stats[@"msAvg"] doubleValue]];
		});
	});
}
- (void)confirmClear {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Xóa thống kê?" message:@"Không thể hoàn tác." preferredStyle:UIAlertControllerStyleAlert];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:@"Xóa" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		(void)action;
		dispatch_async([SXStore queue], ^{
			BOOL ok = [[SXStore shared] clearStats];
			dispatch_async(dispatch_get_main_queue(), ^{
				if (ok) [weakSelf refresh];
				else weakSelf.text.text = @"Không xóa được thống kê. Kiểm tra quyền ghi kho SiriX.";
			});
		});
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}
@end
