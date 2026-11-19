#import "UIViewController+SXBack.h"
#import "SXLog.h"

@implementation UIViewController (SXBack)

/// Đóng trang hiện tại, không giả định có `UINavigationController`.
///
/// Bài học từ máy thật (1.1.11 -> 1.1.12): trong Settings của iOS 15,
/// `self.navigationController` CÓ khác nil nhưng `viewControllers` chỉ có một
/// trang, nên `popViewControllerAnimated:` không làm gì (hoặc pop nhầm trang).
/// Nút vì thế "nhìn thấy mà bấm không được".
///
/// Thứ tự bây giờ ưu tiên theo mức chắc chắn của hành động, không theo cấu trúc:
///   1. đang là modal (có `presentingViewController`) -> dismiss, luôn đóng được;
///   2. ngăn xếp có trang trước -> pop;
///   3. `PSViewController` chứa nó giữ ngăn xếp riêng -> `showController:` trang trước;
///   4. còn lại -> dismiss / settings://.
- (void)sx_goBack:(id)sender {
	(void)sender;
	UINavigationController *navigation = self.navigationController;
	SXLogInf(@"pref", @"Quay lại từ %@ (nav=%@, %lu trang, modal=%@)",
			 NSStringFromClass(self.class),
			 navigation ? @"có" : @"không",
			 (unsigned long)navigation.viewControllers.count,
			 self.presentingViewController ? @"có" : @"không");

	// 1. Modal: đường thoát chắc chắn nhất, làm trước tiên.
	if (self.presentingViewController) {
		[self dismissViewControllerAnimated:YES completion:nil];
		SXLogInf(@"pref", @"đã dismiss %@", NSStringFromClass(self.class));
		return;
	}

	// 2. Ngăn xếp thật có trang trước.
	if (navigation) {
		NSArray<UIViewController *> *stack = navigation.viewControllers;
		if (stack.count > 1 && [stack lastObject] == self) {
			[navigation popViewControllerAnimated:YES];
			SXLogInf(@"pref", @"đã pop %@", NSStringFromClass(self.class));
			return;
		}
	}

	// 3. Ngăn xếp riêng của Preferences (PSRootController / PSListController).
	UIViewController *container = self.parentViewController;
	while (container) {
		if ([container respondsToSelector:@selector(showController:)]) {
			UIViewController *previous = nil;
			if ([container respondsToSelector:@selector(parentController)]) {
				previous = [container performSelector:@selector(parentController)];
			}
			if (previous && previous != self) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
				[container performSelector:@selector(showController:) withObject:previous];
#pragma clang diagnostic pop
				SXLogInf(@"pref", @"quay lại bằng showController: -> %@",
						 NSStringFromClass(previous.class));
				return;
			}
		}
		if (container.parentViewController == container) break;
		container = container.parentViewController;
	}

	// 4. Một số bản Preferences chỉ cho controller biết trang trước qua
	//    `parentController`. Hỏi thẳng, không cần lớp chứa.
	if ([self respondsToSelector:NSSelectorFromString(@"parentController")]) {
		SEL parentSelector = NSSelectorFromString(@"parentController");
		UIViewController *previous = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		previous = [self performSelector:parentSelector];
		id container = self.parentViewController;
		if (previous && previous != self && [container respondsToSelector:@selector(showController:)]) {
			[container performSelector:@selector(showController:) withObject:previous];
			SXLogInf(@"pref", @"quay lại qua parentController → %@", NSStringFromClass(previous.class));
			return;
		}
#pragma clang diagnostic pop
	}

	// 5. Còn lại: đóng bằng navigation controller hoặc quay về Settings.
	if (navigation) {
		[navigation dismissViewControllerAnimated:YES completion:nil];
		SXLogWrn(@"pref", @"không pop được, dismiss cả ngăn xếp %@",
				 NSStringFromClass(self.class));
		return;
	}
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"settings://"]
									   options:@{}
							 completionHandler:nil];
	SXLogWrn(@"pref", @"không tìm được cách quay lại trực tiếp từ %@, dùng settings://",
			 NSStringFromClass(self.class));
}

@end
