// Kiểm thử bộ render Markdown → văn bản Siri (Foundation-only, chạy trên macOS).
//
// Vì sao có tệp này: bong bóng Siri chỉ nhận chữ thuần, nên `SXMarkdownRender`
// là thứ DUY NHẤT người dùng nhìn thấy. Mọi lỗi ở đây không phải "hiển thị hơi
// xấu" mà là "Siri đọc lên dấu sao" hoặc "mất chữ của model".
#import <Foundation/Foundation.h>
#import "SXMarkdown.h"
#include <assert.h>
#include <stdio.h>

static void expect(NSString *input, NSString *want, const char *label) {
	NSString *got = SXMarkdownRender(input);
	if (![got isEqualToString:want]) {
		fprintf(stderr, "FAIL %s\n  vào: %s\n  mong: %s\n  nhận: %s\n", label,
				[input UTF8String], [want UTF8String], [got UTF8String]);
		assert(0);
	}
}

int main(void) {
	@autoreleasepool {
		// --- Inline: thay MỌI lần khớp, không chỉ lần đầu
		expect(@"**một** và **hai**", @"một và hai", "hai cụm đậm cùng dòng");
		expect(@"`a` và `b`", @"a và b", "hai đoạn code cùng dòng");
		expect(@"*x* *y* *z*", @"x y z", "ba cụm nghiêng");
		expect(@"[tài liệu](https://example.com/a)", @"tài liệu (https://example.com/a)", "liên kết");
		expect(@"__đậm__ và _nghiêng_", @"đậm và nghiêng", "gạch dưới");

		// --- Danh sách
		expect(@"- Một\n- Hai", @"• Một\n• Hai", "bullet");
		expect(@"* Một\n+ Hai", @"• Một\n• Hai", "bullet với * và +");
		expect(@"1. Một\n2. Hai", @"1. Một\n2. Hai", "danh sách số giữ số");
		// Dòng chỉ có ký hiệu, không có thân: phải giữ nguyên, không thành "• "
		expect(@"- **", @"• **", "bullet không có thân không bị xoá sạch");

		// --- Tiêu đề / phân cách
		expect(@"# Tiêu đề", @"— TIÊU ĐỀ —", "tiêu đề cấp 1");
		expect(@"### Ba", @"— BA —", "tiêu đề cấp 3");
		expect(@"---", @"· · ·", "phân cách");

		// --- Trích dẫn
		expect(@"> câu nói", @"▍câu nói", "trích dẫn");

		// --- Khối code: giữ nguyên nội dung, chỉ đánh dấu
		expect(@"```\nlet a = 1\n```", @"▸ let a = 1", "khối code");
		// Dấu ``` chưa đóng (model bị cắt giữa chừng) vẫn phải render phần còn lại
		expect(@"```\nlet a = 1", @"▸ let a = 1", "khối code chưa đóng");

		// --- Bảng
		expect(@"| a | b |\n|---|---|\n| 1 | 2 |", @"• a · b\n• 1 · 2", "bảng");

		// --- Không phá định danh lập trình
		expect(@"snake_case_name", @"snake_case_name", "snake_case không bị coi là nghiêng");

		// --- Không bao giờ để lại dấu Markdown
		NSString *dirty = SXMarkdownRender(@"**đậm** `code` [x](y) _nghiêng_");
		assert(![dirty containsString:@"**"]);
		assert(![dirty containsString:@"`"]);
		assert(![dirty containsString:@"]("]);

		// --- Danh sách số: nội dung sau số được giữ, số được viết lại
		expect(@"  1.   lùi lề", @"1. lùi lề", "danh sách số lùi lề");

		// --- Giới hạn độ dài: bong bóng Siri không nhận chuỗi vô hạn
		NSString *longText = [@"" stringByPaddingToLength:3000 withString:@"a" startingAtIndex:0];
		NSString *clipped = SXMarkdownRender(longText);
		assert(clipped.length <= 2001);
		assert([clipped hasSuffix:@"…"]);

		// --- Đầu vào rỗng/khoảng trắng
		expect(@"", @"", "rỗng");
		expect(@"   \n\n  ", @"", "toàn khoảng trắng");

		// --- Nhiều dòng trống bị gộp
		expect(@"A\n\n\n\nB", @"A\n\nB", "gộp dòng trống");

		puts("markdown regression tests: OK");
	}
	return 0;
}
