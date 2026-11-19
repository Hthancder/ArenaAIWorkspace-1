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
	// Trang gốc của Settings không có gì để quay lại.
	UINavigationController *navigation = controller.navigationController;
	if (!navigation || navigation.viewControllers.count <= 1) return;

	// Hệ thống đã có nút trái (Back chuẩn hoặc nút tự đặt) → không đụng vào.
	if (item.leftBarButtonItem) return;

	// iOS đôi khi không tự tạo nút khi thanh điều hướng được dựng lại sau khi
	// bảng reload hoặc khi controller được push bằng API riêng của Settings.
	// Chờ một nhịp vẽ rồi kiểm tra lại; thiếu thì tự thêm nút.
	__weak UIViewController *weakController = controller;
	dispatch_async(dispatch_get_main_queue(), ^{
		UIViewController *strongController = weakController;
		if (!strongController) return;
		if (strongController.navigationItem.leftBarButtonItem) return;
		UINavigationController *nav = strongController.navigationController;
		if (!nav || nav.viewControllers.count <= 1) return;

		UIBarButtonItem *back = [[UIBarButtonItem alloc]
			initWithImage:[UIImage systemImageNamed:@"chevron.backward"]
					style:UIBarButtonItemStylePlain
				   target:strongController
				   action:@selector(sx_goBack:)];
		back.accessibilityLabel = @"Quay lại";
		strongController.navigationItem.leftBarButtonItem = back;
		SXLogInf(@"pref", @"tự thêm nút Quay lại cho %@", NSStringFromClass(strongController.class));
	});
}
