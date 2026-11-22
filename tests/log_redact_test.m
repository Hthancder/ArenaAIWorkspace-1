// Kiểm thử bộ ẩn khoá trong log (Foundation-only, chạy trên macOS CI).
//
// Vì sao có tệp này: người dùng được yêu cầu "sao chép log" rồi **dán vào chat**
// khi cần hỗ trợ. Một khoá API lọt vào đó là lộ khoá (và lộ hoá đơn) của chính
// họ. `SXLogWrite` lọc mọi dòng qua `SXRedactLogLine`, nên hàm đó phải:
//   1. ẩn mọi hình dạng khoá/token đã biết; và
//   2. KHÔNG phá dòng log bình thường (dòng log vô dụng cũng là lỗi).
#import <Foundation/Foundation.h>
#import "SXLog.h"
#include <assert.h>
#include <stdio.h>

static void expectRedacted(NSString *input, NSString *forbidden, const char *label) {
	NSString *got = SXRedactLogLine(input);
	if ([got rangeOfString:forbidden].location != NSNotFound) {
		fprintf(stderr, "FAIL %s\n  vào: %s\n  vẫn còn: %s\n  nhận: %s\n", label,
				[input UTF8String], [forbidden UTF8String], [got UTF8String]);
		assert(0);
	}
	assert(![got isEqualToString:input]);
}

static void expectSame(NSString *input, const char *label) {
	NSString *got = SXRedactLogLine(input);
	if (![got isEqualToString:input]) {
		fprintf(stderr, "FAIL %s\n  vào: %s\n  nhận: %s\n", label,
				[input UTF8String], [got UTF8String]);
		assert(0);
	}
}

int main(void) {
	@autoreleasepool {
		// --- Phải ẩn
		expectRedacted(@"gọi API với sk-proj-abcdefgh12345678 xong", @"abcdefgh12345678",
					   "khoá OpenAI");
		expectRedacted(@"Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456",
					   @"abcdefghijklmnopqrstuvwxyz123456", "Bearer token");
		expectRedacted(@"https://api.example.com/v1?api_key=SECRET123456&x=1",
					   @"SECRET123456", "api_key trong URL");
		expectRedacted(@"{\"api_key\": \"SECRET123456\", \"model\": \"gpt\"}",
					   @"SECRET123456", "api_key trong JSON");
		expectRedacted(@"khoá Gemini AIzaSyD-abcdefghijklmnopqrstuvwxyz123456",
					   @"AIzaSyD-abcdefghijklmnopqrstuvwxyz123456", "khoá Gemini");
		expectRedacted(@"khoá Groq gsk_abcdefghijklmnopqrstuvwxyz1234",
					   @"gsk_abcdefghijklmnopqrstuvwxyz1234", "khoá Groq");

		// Giữ tiền tố để dòng log còn đọc được
		NSString *bearer = SXRedactLogLine(@"Authorization: Bearer abcdefghijklmnopqrstuvwxyz");
		assert([bearer containsString:@"Bearer"]);

		// --- Không được đổi
		expectSame(@"2026-11-22 10:00:00.123 [INFO ] [llm] [SpringBoard] ngữ cảnh 8 câu",
				   "dòng log thường");
		expectSame(@"model gpt-4o-mini trả lời trong 812 ms", "tên model");
		expectSame(@"người dùng huỷ lượt đang chạy", "câu tiếng Việt");
		expectSame(@"\"token\": \"abc\"", "token quá ngắn để là khoá thật");
		expectSame(@"", "dòng rỗng");

		puts("log redaction tests: OK");
	}
	return 0;
}
