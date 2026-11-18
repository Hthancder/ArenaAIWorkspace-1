// Kiểm thử tầng công cụ (Foundation-only) trên macOS: registry, validate tham
// số, cache trong lượt, timeout, exception, cắt kết quả, lọc công cụ đang tắt.
#import <Foundation/Foundation.h>
#import "SXToolkit.h"
#include <assert.h>
#include <stdio.h>

static NSInteger handlerCalls = 0;

static SXTool *EchoTool(void) {
	return [SXTool toolWithName:@"echo"
						  title:@"Lặp lại"
						summary:@"Trả lại đúng nội dung."
						 prompt:@"Dùng khi cần lặp lại văn bản."
					   category:SXToolCategoryMath
					 parameters:@{@"type": @"object",
								  @"properties": @{@"text": @{@"type": @"string", @"description": @"nội dung"}},
								  @"required": @[@"text"]}
						handler:^NSDictionary *(NSDictionary *arguments, NSError **error) {
		(void)error;
		handlerCalls++;
		return @{@"result": arguments[@"text"]};
	}];
}

static SXTool *NumberTool(void) {
	return [SXTool toolWithName:@"add_two"
						  title:@"Cộng hai"
						summary:@"Cộng 2 vào số."
						 prompt:@"Dùng để kiểm tra ép kiểu số."
					   category:SXToolCategoryDevice
					 parameters:@{@"type": @"object",
								  @"properties": @{@"value": @{@"type": @"integer"}},
								  @"required": @[@"value"]}
						handler:^NSDictionary *(NSDictionary *arguments, NSError **error) {
		(void)error;
		NSInteger value = [arguments[@"value"] integerValue];
		return @{@"result": [NSString stringWithFormat:@"%ld", (long)(value + 2)]};
	}];
}

int main(void) {
	@autoreleasepool {
		[SXToolkit removeAllTools];

		// --- rỗng
		assert([SXToolkit allTools].count == 0);
		assert([[SXToolkit promptBriefExcluding:[NSSet set]] length] == 0);

		[SXToolkit registerTool:EchoTool()];
		[SXToolkit registerTool:NumberTool()];

		// --- thứ tự: theo nhóm (device < math) rồi theo tên
		NSArray<SXTool *> *tools = [SXToolkit allTools];
		assert(tools.count == 2);
		assert([tools[0].name isEqualToString:@"add_two"]);
		assert([tools[1].name isEqualToString:@"echo"]);

		// --- đăng ký trùng tên thì thay thế, không nhân đôi
		[SXToolkit registerTool:EchoTool()];
		assert([SXToolkit allTools].count == 2);

		// --- schema gửi cho model
		NSArray<NSDictionary *> *defs = [SXToolkit definitionsExcluding:[NSSet set]];
		assert(defs.count == 2);
		NSDictionary *payload = defs[1];
		assert([payload[@"type"] isEqualToString:@"function"]);
		assert([payload[@"function"][@"name"] isEqualToString:@"echo"]);
		assert([payload[@"function"][@"parameters"][@"required"][0] isEqualToString:@"text"]);

		// --- prompt brief có tên + dấu hiệu tham số bắt buộc
		NSString *brief = [SXToolkit promptBriefExcluding:[NSSet set]];
		assert([brief containsString:@"echo("]);
		assert([brief containsString:@"bắt buộc"]);

		// --- tắt công cụ: không có trong schema, gọi bị từ chối 403
		NSSet *disabled = [NSSet setWithObject:@"echo"];
		assert([SXToolkit definitionsExcluding:disabled].count == 1);
		NSError *error = nil;
		assert([SXToolkit execute:@"echo" arguments:@{@"text": @"x"} excluded:disabled error:&error] == nil);
		assert(error.code == 403);

		// --- gọi đúng
		handlerCalls = 0;
		[SXToolkit resetCallCache];
		error = nil;
		NSDictionary *result = [SXToolkit execute:@"echo" arguments:@{@"text": @"xin chào"}
										excluded:[NSSet set] error:&error];
		assert(result && !error);
		assert([result[@"result"] isEqualToString:@"xin chào"]);
		assert(handlerCalls == 1);

		// --- gọi lặp cùng tham số trong một lượt: dùng cache, handler không chạy lại
		result = [SXToolkit execute:@"echo" arguments:@{@"text": @"xin chào"}
						   excluded:[NSSet set] error:&error];
		assert([result[@"result"] isEqualToString:@"xin chào"]);
		assert(handlerCalls == 1);

		// --- lượt mới: cache xoá, handler chạy lại
		[SXToolkit resetCallCache];
		result = [SXToolkit execute:@"echo" arguments:@{@"text": @"xin chào"}
						   excluded:[NSSet set] error:&error];
		assert(result && handlerCalls == 2);

		// --- thiếu tham số bắt buộc → 422 kèm tên tham số
		error = nil;
		assert([SXToolkit execute:@"echo" arguments:@{} excluded:[NSSet set] error:&error] == nil);
		assert(error.code == 422);
		assert([error.localizedDescription containsString:@"text"]);

		// --- ép kiểu: model gửi "40" (chuỗi) cho tham số integer
		error = nil;
		result = [SXToolkit execute:@"add_two" arguments:@{@"value": @"40"}
						   excluded:[NSSet set] error:&error];
		assert([result[@"result"] isEqualToString:@"42"]);

		// --- công cụ không tồn tại → 404 kèm danh sách đang bật
		error = nil;
		assert([SXToolkit execute:@"khong_co" arguments:@{} excluded:[NSSet set] error:&error] == nil);
		assert(error.code == 404);
		assert([error.localizedDescription containsString:@"add_two"]);

		// --- exception trong handler không được làm sập tiến trình
		SXTool *boom = [SXTool toolWithName:@"boom" title:@"Nổ" summary:@"Ném exception."
									prompt:@"Kiểm thử." category:SXToolCategorySystem
								parameters:@{@"type": @"object", @"properties": @{}}
								   handler:^NSDictionary *(NSDictionary *arguments, NSError **err) {
			(void)arguments; (void)err;
			[NSException raise:@"SXFake" format:@"hỏng"];
			return nil;
		}];
		[SXToolkit registerTool:boom];
		error = nil;
		assert([SXToolkit execute:@"boom" arguments:@{} excluded:[NSSet set] error:&error] == nil);
		assert(error.code == 500);

		// --- quá thời gian → 504, không treo vô hạn
		SXTool *slow = [SXTool toolWithName:@"slow" title:@"Chậm" summary:@"Ngủ 2 giây."
									prompt:@"Kiểm thử timeout." category:SXToolCategoryWeb
								parameters:@{@"type": @"object", @"properties": @{}}
								   handler:^NSDictionary *(NSDictionary *arguments, NSError **err) {
			(void)arguments; (void)err;
			[NSThread sleepForTimeInterval:2.0];
			return @{@"result": @"xong"};
		}];
		slow.timeout = 0.3;
		[SXToolkit registerTool:slow];
		CFAbsoluteTime began = CFAbsoluteTimeGetCurrent();
		error = nil;
		assert([SXToolkit execute:@"slow" arguments:@{} excluded:[NSSet set] error:&error] == nil);
		assert(error.code == 504);
		assert(CFAbsoluteTimeGetCurrent() - began < 1.5);

		// --- kết quả dài bị cắt, có ghi chú
		SXTool *longTool = [SXTool toolWithName:@"long" title:@"Dài" summary:@"Trả 5000 ký tự."
										prompt:@"Kiểm thử cắt." category:SXToolCategoryMemory
									parameters:@{@"type": @"object", @"properties": @{}}
									   handler:^NSDictionary *(NSDictionary *arguments, NSError **err) {
			(void)arguments; (void)err;
			return @{@"result": [@"" stringByPaddingToLength:5000 withString:@"a" startingAtIndex:0]};
		}];
		[SXToolkit registerTool:longTool];
		result = [SXToolkit execute:@"long" arguments:@{} excluded:[NSSet set] error:NULL];
		NSString *text = result[@"result"];
		assert([text length] < 4200);
		assert([text hasSuffix:@"(đã cắt bớt)"]);

		// --- handler trả nil, không lỗi → vẫn có câu trả lời cho model
		SXTool *silent = [SXTool toolWithName:@"silent" title:@"Im" summary:@"Trả nil."
									  prompt:@"Kiểm thử." category:SXToolCategoryMemory
								  parameters:@{@"type": @"object", @"properties": @{}}
									 handler:^NSDictionary *(NSDictionary *arguments, NSError **err) {
			(void)arguments; (void)err;
			return nil;
		}];
		[SXToolkit registerTool:silent];
		result = [SXToolkit execute:@"silent" arguments:@{} excluded:[NSSet set] error:NULL];
		assert([result[@"result"] length] > 0);

		printf("✓ toolkit: 11 nhóm kiểm thử đều đạt\n");
	}
	return 0;
}
