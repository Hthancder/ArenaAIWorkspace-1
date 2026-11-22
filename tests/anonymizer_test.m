// Kiểm thử bộ ẩn dữ liệu nhận dạng (Foundation-only, chạy trên macOS CI).
//
// Hai chiều đều phải đúng:
//   1. ẨN: số điện thoại/email/thẻ/CCCD/IP/URL có query không được đi lên máy chủ.
//   2. KHÔI PHỤC: người dùng vẫn đọc được số thật trong câu trả lời, kể cả khi
//      model viết lại nhãn (`[SDT 1]`, `[sdt-1]`, `(sđt 1)`).
//   3. KHÔNG PHÁ: câu hỏi không có dữ liệu nhận dạng phải đi nguyên vẹn, và
//      "sđt của tôi" (không có số) không được coi là nhãn để thay lại.
#import <Foundation/Foundation.h>
#import "SXAnonymizer.h"
#include <assert.h>
#include <stdio.h>

static void fail(NSString *message, NSString *input, NSString *got) {
	fprintf(stderr, "FAIL %s\n  vào: %s\n  nhận: %s\n",
			message.UTF8String, input.UTF8String, got.UTF8String);
	assert(0);
}

/// Ẩn rồi khôi phục phải trả lại ĐÚNG chuỗi ban đầu (kể cả khoảng trắng).
static void roundtrip(NSString *input, const char *label) {
	SXAnonTurn *turn = [SXAnonTurn new];
	NSString *hidden = [turn redact:input];
	if ([hidden isEqualToString:input] && [turn redactedCount] == 0) {
		fail([NSString stringWithFormat:@"không ẩn được gì (%s)", label], input, hidden);
	}
	NSString *back = [turn restore:hidden];
	if (![back isEqualToString:input]) fail([NSString stringWithFormat:@"khôi phục sai (%s)", label], input, back);
}

static void mustNotContain(NSString *input, NSArray<NSString *> *secrets, const char *label) {
	SXAnonTurn *turn = [SXAnonTurn new];
	NSString *hidden = [turn redact:input];
	for (NSString *secret in secrets) {
		if ([hidden containsString:secret]) {
			fail([NSString stringWithFormat:@"lộ “%@” (%s)", secret, label], input, hidden);
		}
	}
}

int main(void) {
	@autoreleasepool {
		// --- Số điện thoại Việt Nam, mọi kiểu viết
		roundtrip(@"gọi mẹ 0912345678 giúp tôi", "sđt liền");
		roundtrip(@"gọi 0912 345 678 nhé", "sđt có khoảng trắng");
		roundtrip(@"số +84912345678 lưu trong danh bạ", "sđt +84");
		mustNotContain(@"gọi mẹ 0912345678 giúp tôi", @[@"0912345678"], "sđt liền");
		mustNotContain(@"gọi 0912 345 678 nhé", @[@"345"], "sđt có khoảng trắng");

		// --- Email
		roundtrip(@"gửi mail cho minh.anh+test@example.com.vn nhé", "email");
		mustNotContain(@"gửi mail cho minh.anh@example.com nhé", @[@"minh.anh", @"example.com"], "email");

		// --- Số thẻ (nhóm 4) phải bị ẩn TRƯỚC số dài, nhãn phải là [thẻ-N]
		SXAnonTurn *card = [SXAnonTurn new];
		NSString *cardHidden = [card redact:@"thẻ 4111 1111 1111 1111 hết hạn 12/26"];
		assert(![cardHidden containsString:@"4111"]);
		assert([cardHidden containsString:@"[thẻ-1]"]);

		// --- CCCD / CMND
		roundtrip(@"CCCD 001203004567 của tôi", "cccd 12 số");
		mustNotContain(@"CMND 123456789", @[@"123456789"], "cmnd 9 số");

		// --- Số tài khoản ngân hàng (8–20 số, không thuộc mẫu trên)
		mustNotContain(@"chuyển vào tài khoản 19001234567890", @[@"19001234567890"], "số tài khoản");

		// --- IP và URL có query
		mustNotContain(@"máy 192.168.1.10 không vào được mạng", @[@"192.168.1.10"], "địa chỉ IP");
		mustNotContain(@"mở https://shop.example.com/order?token=abc123secret xem giúp",
					   @[@"abc123secret"], "URL có token");

		// --- Nhiều giá trị CÙNG loại: nhãn phải khác nhau để khôi phục đúng
		SXAnonTurn *two = [SXAnonTurn new];
		NSString *input = @"gọi 0912345678 hoặc 0987654321";
		NSString *hidden = [two redact:input];
		assert([hidden containsString:@"[sđt-1]"]);
		assert([hidden containsString:@"[sđt-2]"]);
		assert([[two restore:hidden] isEqualToString:input]);

		// --- Model viết lại nhãn: vẫn khôi phục được
		SXAnonTurn *shape = [SXAnonTurn new];
		NSString *shapeInput = @"gọi 0912345678 nhé";
		(void)[shape redact:shapeInput];
		for (NSString *variant in @[@"Gọi [sđt-1] ngay", @"Gọi [SDT 1] ngay",
									 @"Gọi [sdt 1] ngay", @"Gọi (sđt 1) ngay"]) {
			NSString *restored = [shape restore:variant];
			if (![restored containsString:@"0912345678"]) fail(@"không khôi phục được nhãn viết lại", variant, restored);
		}

		// --- KHÔNG được phá câu vô hại
		SXAnonTurn *clean = [SXAnonTurn new];
		NSString *plain = @"thời tiết Hà Nội hôm nay thế nào";
		assert([[clean redact:plain] isEqualToString:plain]);
		assert([clean redactedCount] == 0);
		// "sđt của tôi" không phải nhãn ⇒ khi khôi phục phải để nguyên
		assert([[clean restore:@"cho tôi xin sđt của bạn"] isEqualToString:@"cho tôi xin sđt của bạn"]);
		// Năm/tháng/giờ nhỏ không bị coi là dữ liệu nhận dạng
		assert([[clean redact:@"năm 2026 tháng 11"] isEqualToString:@"năm 2026 tháng 11"]);

		// --- Tắt công tắc thì không ẩn gì
		SXAnonTurn *off = [SXAnonTurn new];
		off.enabled = NO;
		assert([[off redact:@"gọi 0912345678"] isEqualToString:@"gọi 0912345678"]);
		assert([off redactedCount] == 0);

		// --- Rỗng/nil không làm văng
		assert([[SXAnonTurn new] redact:@""].length == 0);
		assert([[SXAnonTurn new] redact:nil] == nil);
		assert([[SXAnonTurn new] restore:nil] == nil);

		puts("anonymizer tests: OK");
	}
	return 0;
}
