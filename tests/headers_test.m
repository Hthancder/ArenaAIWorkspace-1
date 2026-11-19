// Kiểm thử tầng header tuỳ chỉnh (Foundation-only) trên macOS.
// Trọng tâm: cái gì Settings cho lưu thì đúng là cái được gửi đi — không hơn.
#import <Foundation/Foundation.h>
#import "SXHeaders.h"
#include <assert.h>
#include <stdio.h>

static NSDictionary *Pair(NSString *name, NSString *value, BOOL enabled) {
	return @{@"name": name, @"value": value, @"enabled": @(enabled)};
}

int main(void) {
	@autoreleasepool {
		// --- tên header hợp lệ theo token RFC 7230
		assert(SXHeaderNameIsValid(@"X-Title"));
		assert(SXHeaderNameIsValid(@"HTTP-Referer"));
		assert(SXHeaderNameIsValid(@"api-key"));
		assert(SXHeaderNameIsValid(@"x_custom.thing"));
		assert(!SXHeaderNameIsValid(@""));
		assert(!SXHeaderNameIsValid(nil));
		assert(!SXHeaderNameIsValid(@"X Title"));       // khoảng trắng
		assert(!SXHeaderNameIsValid(@"X-Title:"));      // dấu hai chấm
		assert(!SXHeaderNameIsValid(@"Tên-Việt"));      // ký tự ngoài ASCII
		assert(!SXHeaderNameIsValid(@"X-Title\nInjected"));

		// --- header do hệ thống tự đặt
		assert(SXHeaderNameIsReserved(@"Host"));
		assert(SXHeaderNameIsReserved(@"content-type"));
		assert(SXHeaderNameIsReserved(@" Content-Length "));
		assert(!SXHeaderNameIsReserved(@"Authorization"));  // cho phép thay (gateway riêng)
		assert(!SXHeaderNameIsReserved(@"api-key"));

		// --- validate
		NSArray *existing = @[Pair(@"X-Title", @"SiriX", YES)];
		assert(SXHeaderValidate(@"X-New", @"1", existing, nil) == SXHeaderIssueNone);
		assert(SXHeaderValidate(@"", @"1", existing, nil) == SXHeaderIssueEmptyName);
		assert(SXHeaderValidate(@"Bad Name", @"1", existing, nil) == SXHeaderIssueInvalidName);
		assert(SXHeaderValidate(@"Host", @"evil", existing, nil) == SXHeaderIssueReservedName);
		assert(SXHeaderValidate(@"X-New", @"", existing, nil) == SXHeaderIssueInvalidValue);
		assert(SXHeaderValidate(@"X-New", @"a\nb", existing, nil) == SXHeaderIssueInvalidValue);
		// trùng tên (không phân biệt hoa thường) khi thêm mới
		assert(SXHeaderValidate(@"x-title", @"khác", existing, nil) == SXHeaderIssueDuplicateName);
		// nhưng khi đang sửa chính nó thì không tính là trùng
		assert(SXHeaderValidate(@"X-Title", @"SiriX 2", existing, @"X-Title") == SXHeaderIssueNone);

		// --- trần số header
		NSMutableArray *many = [NSMutableArray array];
		for (NSUInteger i = 0; i < SXHeaderMaximum; i++) {
			[many addObject:Pair([NSString stringWithFormat:@"X-H%lu", (unsigned long)i], @"1", YES)];
		}
		assert(SXHeaderValidate(@"X-Them", @"1", many, nil) == SXHeaderIssueTooMany);
		assert(SXHeaderValidate(@"X-H1", @"2", many, @"X-H1") == SXHeaderIssueNone);

		// --- chuẩn hoá dữ liệu thô
		assert(SXHeadersNormalized(nil).count == 0);
		assert(SXHeadersNormalized(@"rác").count == 0);
		NSArray *messy = @[
			Pair(@"  X-Title  ", @"  SiriX  ", YES),
			@{@"name": @"Content-Type", @"value": @"text/plain"},   // bị loại: header hệ thống
			@{@"name": @"Bad Name", @"value": @"x"},                // bị loại: tên sai
			@{@"name": @"X-NoValue"},
			@"chuỗi rác",
			@{@"name": @"X-Off", @"value": @"1", @"enabled": @NO},
		];
		NSArray *clean = SXHeadersNormalized(messy);
		assert(clean.count == 2);
		assert([clean[0][@"name"] isEqualToString:@"X-Title"]);
		assert([clean[0][@"value"] isEqualToString:@"SiriX"]);
		assert([clean[0][@"enabled"] boolValue]);          // mặc định bật
		assert(![clean[1][@"enabled"] boolValue]);

		// --- dạng từ điển cũ vẫn đọc được
		NSArray *fromDictionary = SXHeadersNormalized(@{@"X-Title": @"SiriX"});
		assert(fromDictionary.count == 1);
		assert([fromDictionary[0][@"name"] isEqualToString:@"X-Title"]);

		// --- bộ header thực sự gửi
		NSDictionary *applied = SXHeadersApplied(@[
			Pair(@"X-Title", @"SiriX", YES),
			Pair(@"X-Off", @"1", NO),                       // tắt → không gửi
			@{@"name": @"Host", @"value": @"evil"},         // hệ thống → không gửi
			@{@"name": @"Bad Name", @"value": @"x"},        // sai → không gửi
		]);
		assert(applied.count == 1);
		assert([applied[@"X-Title"] isEqualToString:@"SiriX"]);

		// trùng tên: giá trị sau thắng, giữ cách viết hoa của lần đầu
		NSDictionary *duplicated = SXHeadersApplied(@[
			Pair(@"X-Title", @"mot", YES),
			Pair(@"x-title", @"hai", YES),
		]);
		assert(duplicated.count == 1);
		assert([duplicated[@"X-Title"] isEqualToString:@"hai"]);

		// --- tóm tắt & che giá trị
		assert([SXHeadersSummary(@[]) isEqualToString:@"Chưa có header tuỳ chỉnh"]);
		assert([SXHeadersSummary(@[Pair(@"A", @"1", YES), Pair(@"B", @"2", YES)])
				isEqualToString:@"2 header · đang gửi tất cả"]);
		assert([SXHeadersSummary(@[Pair(@"A", @"1", YES), Pair(@"B", @"2", NO)])
				isEqualToString:@"2 header · 1 đang bật"]);
		assert([SXHeaderValueMasked(@"abcdefghij") isEqualToString:@"••••ghij"]);
		assert([SXHeaderValueMasked(@"abc") isEqualToString:@"••••"]);

		// --- gợi ý: Gemini không có gợi ý Azure/OpenRouter
		NSArray *openai = SXHeaderPresets(SXHeaderPresetProviderOpenAI);
		NSArray *gemini = SXHeaderPresets(SXHeaderPresetProviderGemini);
		assert(openai.count > gemini.count);
		for (NSDictionary *preset in openai) {
			assert(SXHeaderNameIsValid(preset[@"name"]));
			assert(!SXHeaderNameIsReserved(preset[@"name"]));
			assert([preset[@"note"] length] > 0);
		}
		for (NSDictionary *preset in gemini) {
			assert(![preset[@"name"] isEqualToString:@"api-key"]);
		}

		// --- xếp gợi ý theo endpoint đang cấu hình
		NSArray *openrouter = SXHeaderPresetsForEndpoint(SXHeaderPresetProviderOpenAI,
														 @"https://openrouter.ai/api/v1");
		assert(openrouter.count == openai.count);   // chỉ đổi thứ tự, không thêm/bớt
		assert([openrouter.firstObject[@"name"] isEqualToString:@"HTTP-Referer"]);
		assert([openrouter[1][@"name"] isEqualToString:@"X-Title"]);
		NSArray *azure = SXHeaderPresetsForEndpoint(SXHeaderPresetProviderOpenAI,
													@"https://myres.openai.azure.com/openai/v1");
		assert([azure.firstObject[@"name"] isEqualToString:@"api-key"]);
		assert(SXHeaderPresetsForEndpoint(SXHeaderPresetProviderOpenAI, nil).count == openai.count);
		// endpoint Gemini không được kéo gợi ý Azure lên
		NSArray *geminiRanked = SXHeaderPresetsForEndpoint(SXHeaderPresetProviderGemini,
														   @"https://generativelanguage.googleapis.com");
		assert(![geminiRanked.firstObject[@"name"] isEqualToString:@"api-key"]);

		printf("✓ headers: 9 nhóm kiểm thử đều đạt\n");
	}
	return 0;
}
