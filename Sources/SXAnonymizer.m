#import "SXAnonymizer.h"
#import "SXLog.h"

/// Khoảng trắng vẫn được giữ để câu hỏi không dính chữ sau khi thay thế.
static NSString *SXAnonLabelForKind(NSString *kind, NSUInteger index) {
	if ([kind isEqualToString:@"email"]) return [NSString stringWithFormat:@"[email-%lu]", (unsigned long)index];
	if ([kind isEqualToString:@"phone"]) return [NSString stringWithFormat:@"[sđt-%lu]", (unsigned long)index];
	if ([kind isEqualToString:@"card"]) return [NSString stringWithFormat:@"[thẻ-%lu]", (unsigned long)index];
	if ([kind isEqualToString:@"id"]) return [NSString stringWithFormat:@"[cccd-%lu]", (unsigned long)index];
	if ([kind isEqualToString:@"bank"]) return [NSString stringWithFormat:@"[tk-%lu]", (unsigned long)index];
	if ([kind isEqualToString:@"ip"]) return [NSString stringWithFormat:@"[ip-%lu]", (unsigned long)index];
	if ([kind isEqualToString:@"url"]) return [NSString stringWithFormat:@"[link-%lu]", (unsigned long)index];
	return [NSString stringWithFormat:@"[ẩn-%lu]", (unsigned long)index];
}

@implementation SXAnonTurn {
	/// placeholder đầy đủ (đúng như đã chèn) → giá trị gốc.
	NSMutableDictionary<NSString *, NSString *> *_map;
	/// placeholder đã chuẩn hoá (bỏ dấu, viết thường, bỏ khoảng trắng) → placeholder đầy đủ.
	NSMutableDictionary<NSString *, NSString *> *_normalized;
	/// Bộ đếm theo loại để nhãn không trùng giữa các lượt ẩn trong cùng câu.
	NSMutableDictionary<NSString *, NSNumber *> *_counters;
	NSUInteger _order;
}

- (instancetype)init {
	if ((self = [super init])) {
		_map = [NSMutableDictionary dictionary];
		_normalized = [NSMutableDictionary dictionary];
		_counters = [NSMutableDictionary dictionary];
		_enabled = YES;
	}
	return self;
}

- (NSUInteger)redactedCount {
	return _map.count;
}

#pragma mark - Chuẩn hoá để khôi phục chịu lỗi

/// Bỏ dấu tiếng Việt + viết thường + bỏ mọi ký tự không phải chữ/số.
/// Model có thể trả `[SDT 1]`, `[sđt-1]` hay `(sđt 1)` — tất cả phải khớp.
///
/// `đ` không có dạng NFD nên `stringByFoldingWithOptions:` xử lý tuỳ phiên bản
/// ICU (có bản trả "d", có bản để nguyên "đ"). Vì nhãn `[sđt-1]` do chính hàm
/// này chuẩn hoá, nếu hai bên chuẩn hoá khác nhau thì việc khôi phục hỏng đúng
/// với cái nhãn phổ biến nhất — nên đổi `đ`→`d` NGAY, trước mọi bước khác.
static NSString *SXAnonNormalize(NSString *text) {
	NSString *lower = [text.lowercaseString stringByFoldingWithOptions:NSDiacriticInsensitiveSearch
																 locale:nil];
	lower = [lower stringByReplacingOccurrencesOfString:@"đ" withString:@"d"];
	NSData *data = [lower dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
	NSString *ascii = data ? [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding] : lower;
	NSMutableString *out = [NSMutableString stringWithCapacity:ascii.length];
	for (NSUInteger i = 0; i < ascii.length; i++) {
		unichar c = [ascii characterAtIndex:i];
		if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) [out appendFormat:@"%C", c];
	}
	return out;
}

#pragma mark - Nhận dạng

/// Mẫu nhận dạng theo thứ tự ưu tiên: mẫu cụ thể trước (email, thẻ), mẫu dễ
/// nhầm sau (số điện thoại, số dài). Thứ tự này quan trọng — số thẻ 16 chữ số
/// cũng khớp mẫu "số dài", phải ẩn nó TRƯỚC để nhãn đúng loại.
static NSArray<NSDictionary *> *SXAnonPatterns(void) {
	static NSArray<NSDictionary *> *patterns;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		patterns = @[
			// Email
			@{@"kind": @"email",
			  @"re": [NSRegularExpression regularExpressionWithPattern:
					  @"[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}" options:0 error:NULL]},
			// Số thẻ 13–19 chữ số, cho phép nhóm cách nhau bởi dấu cách/gạch
			// (thẻ in trên nhựa luôn có nhóm: 4111 1111 1111 1111).
			@{@"kind": @"card",
			  @"re": [NSRegularExpression regularExpressionWithPattern:
					  @"\\b(?:\\d[ \\-]?){12,18}\\d\\b" options:0 error:NULL]},
			// Số điện thoại Việt Nam: 0xxxxxxxxx / +84xxxxxxxxx, có thể có dấu
			// cách hoặc chấm giữa các nhóm như người ta vẫn viết tay.
			@{@"kind": @"phone",
			  @"re": [NSRegularExpression regularExpressionWithPattern:
					  @"(?:\\+?84|0)(?:[ .\\-]?\\d){9,10}\\b" options:0 error:NULL]},
			// CCCD 12 số / CMND 9 số đứng riêng.
			@{@"kind": @"id",
			  @"re": [NSRegularExpression regularExpressionWithPattern:
					  @"\\b\\d{9}\\b|\\b\\d{12}\\b" options:0 error:NULL]},
			// Số tài khoản ngân hàng: 8–20 chữ số đứng riêng (đã trừ các mẫu trên).
			@{@"kind": @"bank",
			  @"re": [NSRegularExpression regularExpressionWithPattern:
					  @"\\b\\d{8,20}\\b" options:0 error:NULL]},
			// Địa chỉ IPv4 trong câu hỏi ("máy 192.168.1.10 bị sao").
			@{@"kind": @"ip",
			  @"re": [NSRegularExpression regularExpressionWithPattern:
					  @"\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b" options:0 error:NULL]},
			// URL có query — tham số hay chứa token/mã đơn hàng.
			@{@"kind": @"url",
			  @"re": [NSRegularExpression regularExpressionWithPattern:
					  @"https?://[^\\s]+\\?[^\\s]+" options:0 error:NULL]},
		];
	});
	return patterns;
}

- (NSString *)redact:(NSString *)text {
	if (!_enabled || !text.length) return text;

	NSMutableString *result = [text mutableCopy];
	for (NSDictionary *pattern in SXAnonPatterns()) {
		NSRegularExpression *re = pattern[@"re"];
		NSString *kind = pattern[@"kind"];
		// Tìm từ CUỐI lên để thay thế không làm lệch vị trí các khớp trước đó.
		// `matchesInString:` trả về theo thứ tự tăng dần và mỗi khớp nằm trong
		// `result` hiện tại (cùng một chuỗi), nên duyệt ngược là an toàn.
		NSArray<NSTextCheckingResult *> *matches =
			[re matchesInString:result options:0 range:NSMakeRange(0, result.length)];
		for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
			NSString *value = [result substringWithRange:match.range];
			NSString *trimmed = [value stringByTrimmingCharactersInSet:
								 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if (!trimmed.length) continue;
			// Số quá ngắn (như "2024") vẫn được ẩn: năm tháng không phải dữ liệu
			// nhận dạng, và ẩn nhầm một con số vô hại rẻ hơn nhiều so với lộ một
			// số điện thoại. Mẫu đã yêu cầu ≥8 chữ số nên không ẩn số nhỏ.
			NSUInteger index = [_counters[kind] unsignedIntegerValue] + 1;
			_counters[kind] = @(index);
			NSString *label = SXAnonLabelForKind(kind, index);
			_map[label] = trimmed;
			_normalized[SXAnonNormalize(label)] = label;
			_order++;
			[result replaceCharactersInRange:match.range withString:label];
		}
	}
	if (_map.count) {
		SXLogDbg(@"capture", @"ẩn %lu giá trị nhận dạng trước khi gửi (khôi phục sau)",
				 (unsigned long)_map.count);
	}
	return result;
}

#pragma mark - Khôi phục

- (NSString *)restore:(NSString *)text {
	if (!text.length || !_map.count) return text;
	NSMutableString *result = [text mutableCopy];
	// Ba hình dạng model thường trả về:
	//  1. trong ngoặc vuông — `[sđt-1]`, `[SDT 1]` (chuẩn, do ta chèn);
	//  2. trong ngoặc tròn — `(sđt 1)`;
	//  3. trần — `sđt-1`, `sdt 1`.
	// Mẫu 1 nhận MỌI cụm trong ngoặc vuông (rồi tra bảng, không khớp thì để
	// nguyên) vì viết một mẫu "bắt đầu bằng từ khoá" dễ hỏng: bản trước dùng
	// lượng tử lười `{0,12}?` nên chỉ khớp được `[sđt` — thiếu số và dấu đóng.
	static NSRegularExpression *candidateRe;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		candidateRe = [NSRegularExpression regularExpressionWithPattern:
					   @"\\[[^\\[\\]]{1,24}\\]"
					   @"|\\([^()]{1,16}\\)"
					   @"|\\b(?:sđt|sdt|email|thẻ|the|cccd|tk|ip|link|ẩn|an)[\\s\\-_]?\\d{1,3}\\b"
					   options:NSRegularExpressionCaseInsensitive error:NULL];
	});
	NSArray<NSTextCheckingResult *> *matches =
		[candidateRe matchesInString:result options:0 range:NSMakeRange(0, result.length)];
	for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
		NSString *candidate = [result substringWithRange:match.range];
		NSString *label = _normalized[SXAnonNormalize(candidate)];
		if (!label) continue;   // cụm vô hại ("sđt của tôi", "[ảnh]"…) — để nguyên
		NSString *original = _map[label];
		if (!original.length) continue;
		[result replaceCharactersInRange:match.range withString:original];
	}
	return result;
}

@end
