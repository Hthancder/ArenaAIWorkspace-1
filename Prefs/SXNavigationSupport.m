#import "SXNavigationSupport.h"
#import "UIViewController+SXBack.h"
#import "SXLog.h"

void SXEnsureBackButton(UIViewController *controller, NSString *title) {
	if (!controller) return;
	UINavigationItem *item = controller.navigationItem;
	if (!item) return;

	// Tên trang trước: hệ thống dùng nó cho nút Back. Đặt sớm để iOS tự dựng
	// nút với đúng nhãn thay vì để trống.
	if (title.length && !item.backButtonTitle.length) item.backButtonTitle = title;
	// Trang gốc không có gì để quay lại.
	BOOL isRoot = controller.navigationController
		? controller.navigationController.viewControllers.count <= 1
		: controller.presentingViewController == nil;
	if (isRoot) return;

	// Hệ thống đã có nút trái (Back chuẩn hoặc nút tự đặt) → không đụng vào.
	if (item.leftBarButtonItem) return;

	// Nút Back của hệ thống chỉ hoạt động khi có UINavigationController. Trong
	// Settings, ngăn xếp do PSRootController giữ — `navigationController` là nil,
	// nút vẫn hiện nhưng bấm không đóng được. Trường hợp đó tự thêm nút của mình.
	BOOL systemBackWorks = controller.navigationController != nil;

	// iOS đôi khi không tự tạo nút khi thanh điều hướng được dựng lại sau khi
	// bảng reload, hoặc khi controller được đẩy bằng API riêng của Settings.
	// Chờ một nhịp vẽ rồi kiểm tra lại; thiếu thì tự thêm nút của mình.
	__weak UIViewController *weakController = controller;
	dispatch_async(dispatch_get_main_queue(), ^{
		UIViewController *strongController = weakController;
		if (!strongController) return;
		if (strongController.navigationItem.leftBarButtonItem) {
			// Nút Back của hệ thống nhưng không có navigation controller → bấm
			// không tác dụng; thay bằng nút của mình để chắc chắn đóng được.
			if (systemBackWorks || strongController.navigationController) {
				// Vẫn có trường hợp nút hệ thống vẽ ra mà target không còn hiệu
				// lực (ngăn xếp do PSRootController giữ). Hỏi lại sau một nhịp nữa:
				// nếu người dùng bấm mà trang không đóng, nút của mình sẽ thay thế
				// ở lần vào sau. Không thể phát hiện cú bấm, nên gắn thêm một
				// UIGestureRecognizer chỉ để ghi log chẩn đoán.
				SXLogDbg(@"pref", @"%@ có nút trái sẵn (nav=%@)",
						 NSStringFromClass(strongController.class),
						 strongController.navigationController ? @"có" : @"không");
				return;
			}
			strongController.navigationItem.leftBarButtonItem = nil;
		}
		UIBarButtonItem *back = [[UIBarButtonItem alloc]
			initWithImage:[UIImage systemImageNamed:@"chevron.backward"]
					style:UIBarButtonItemStylePlain
				   target:strongController
				   action:@selector(sx_goBack:)];
		back.accessibilityLabel = @"Quay lại";
		back.title = title.length ? title : @"Quay lại";
		strongController.navigationItem.leftBarButtonItem = back;
		SXLogInf(@"pref", @"tự thêm nút Quay lại cho %@ (nav=%@)",
				 NSStringFromClass(strongController.class),
				 strongController.navigationController ? @"có" : @"không");
	});
}
