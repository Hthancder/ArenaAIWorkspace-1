#import "UIViewController+SXBack.h"
#import "SXLog.h"

@implementation UIViewController (SXBack)

/// Đóng trang hiện tại, không giả định có `UINavigationController`.
///
/// Settings của iOS có thể dựng ngăn xếp trang bằng `PSRootController` +
/// `showController:` — ở đó `self.navigationController` là nil. Nút Back do hệ
/// thống vẽ vẫn hiện nhưng target không còn trang trước để pop, nên "nhìn thấy
/// mà bấm không được". Đi theo thứ tự chắc chắn nhất:
///   1. navigation controller có trang trước → pop;
///   2. có `PSViewController` chứa nó → `showController:` trang trước;
///   3. đang ở dạng modal → dismiss;
///   4. còn lại → gọi về `parentController` nếu có, hoặc dismiss.
- (void)sx_goBack:(id)sender {
	(void)sender;
	UINavigationController *navigation = self.navigationController;
	if (navigation && navigation.viewControllers.count > 1) {
		[navigation popViewControllerAnimated:YES];
		return;
	}

	// PSViewController (Settings của Apple) giữ ngăn xếp riêng.
	UIViewController *container = self.parentViewController;
	while (container) {
		if ([container respondsToSelector:@selector(showController:)]) {
			UIViewController *previous = nil;
			if ([container respondsToSelector:@selector(parentController)]) {
				previous = [container performSelector:@selector(parentController)];
			}
			if (previous && previous != self) {
				SXLogInf(@"pref", @"quay lại bằng showController: → %@",
						 NSStringFromClass(previous.class));
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
				[container performSelector:@selector(showController:) withObject:previous];
#pragma clang diagnostic pop
				return;
			}
		}
		if (container.presentingViewController) break;
		if (container.parentViewController == container) break;
		container = container.parentViewController;
	}

	if (self.presentingViewController) {
		[self dismissViewControllerAnimated:YES completion:nil];
		return;
	}
	if (navigation) {
		[navigation dismissViewControllerAnimated:YES completion:nil];
		return;
	}
	// Cuối cùng: cách Settings tự đóng ngăn xếp trang con trên iOS 15.
	// `settings://` không có host/section nên Preferences quay về trang trước.
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"settings://"]
									   options:@{}
							 completionHandler:nil];
	SXLogWrn(@"pref", @"không tìm được cách quay lại trực tiếp từ %@ — dùng settings://",
			 NSStringFromClass(self.class));
}

@end
