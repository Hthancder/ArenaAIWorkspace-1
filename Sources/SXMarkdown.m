#import "SXMarkdown.h"

static NSString *SXMDTrim(NSString *s) {
	return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

/// Thay MỌI lần khớp của `re` (trả về nguyên bản nếu không khớp).
/// Tên cũ là `SXMDReplaceFirst`, nhưng hàm luôn thay toàn bộ — `rangeOfFirstMatch`
/// chỉ dùng để thoát sớm. Tên sai khiến người đọc sau tưởng chỉ một chỗ được
/// thay rồi "sửa" lại đúng hành vi hiện tại, nên đã đổi tên cho khớp việc nó làm.
static NSString *SXMDReplaceAll(NSRegularExpression *re, NSString *input, NSString *tmpl) {
	NSRange full = NSMakeRange(0, input.length);
	if ([re rangeOfFirstMatchInString:input options:0 range:full].location == NSNotFound) return input;
	return [re stringByReplacingMatchesInString:input options:0 range:full withTemplate:tmpl];
}

/// Bỏ ký hiệu đầu dòng danh sách khỏi văn bản, nhưng KHÔNG trả về thân rỗng:
/// nếu văn bản chỉ còn toàn khoảng trắng (ví dụ dòng "- " hoặc "- **" lạc từ
/// model) thì giữ nguyên, để còn thấy dòng đó thay vì một gạch đầu dòng trống.
static NSString *SXMDStripMarker(NSRegularExpression *re, NSString *text) {
	NSString *body = [re stringByReplacingMatchesInString:text options:0
												 range:NSMakeRange(0, text.length) withTemplate:@""];
	return SXMDTrim(body).length ? body : text;
}

NSString *SXMarkdownRender(NSString *markdown) {
	if (!markdown.length) return @"";

	static NSRegularExpression *linkRe, *boldStarRe, *boldUnderRe, *codeRe,
		*italicStarRe, *italicUnderRe, *headingRe, *fenceRe,
		*bulletRe, *orderedRe, *quoteRe, *tableSepRe, *hrRe, *blankRunsRe;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		linkRe = [NSRegularExpression regularExpressionWithPattern:@"\\[([^\\]]+)\\]\\(([^)\\s]+)\\)"
														  options:NSRegularExpressionAnchorsMatchLines error:NULL];
		boldStarRe = [NSRegularExpression regularExpressionWithPattern:@"\\*\\*([^*]+?)\\*\\*"
															  options:NSRegularExpressionAnchorsMatchLines error:NULL];
		boldUnderRe = [NSRegularExpression regularExpressionWithPattern:@"__([^_]+?)__"
																options:NSRegularExpressionAnchorsMatchLines error:NULL];
		codeRe = [NSRegularExpression regularExpressionWithPattern:@"`([^`]+)`"
														  options:NSRegularExpressionAnchorsMatchLines error:NULL];
		italicStarRe = [NSRegularExpression regularExpressionWithPattern:@"(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)"
																options:NSRegularExpressionAnchorsMatchLines error:NULL];
		// `_nghiêng_` có chữ ngay sát dấu gạch dưới, nên mẫu cũ `(?<!\w)_(?!\w)`
		// KHÔNG BAO GIỜ khớp (nó đòi khoảng trắng hai bên). Nay chỉ cấm khi hai bên
		// là chữ/số, để `snake_case_name` vẫn nguyên vẹn.
		italicUnderRe = [NSRegularExpression regularExpressionWithPattern:@"(?<![\\w])_(?!\\s)(.+?)(?<!\\s)_(?![\\w])"
																  options:NSRegularExpressionAnchorsMatchLines error:NULL];
		headingRe = [NSRegularExpression regularExpressionWithPattern:@"^#{1,6}\\s+(.+)$"
															 options:NSRegularExpressionAnchorsMatchLines error:NULL];
		fenceRe = [NSRegularExpression regularExpressionWithPattern:@"^\\s*```.*$"
														   options:NSRegularExpressionAnchorsMatchLines error:NULL];
		bulletRe = [NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*[-*+]\\s+"
															options:NSRegularExpressionAnchorsMatchLines error:NULL];
		orderedRe = [NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*(\\d+)\\.\\s+"
															 options:NSRegularExpressionAnchorsMatchLines error:NULL];
		quoteRe = [NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*>[ \\t]?"
														  options:NSRegularExpressionAnchorsMatchLines error:NULL];
		// Dòng phân cách bảng có thể có NHIỀU ô (`|---|---|`). Mẫu cũ `[^|]*$`
		// chỉ cho một ô, nên bảng chuẩn của model vẫn lọt ra thành
		// "• --- · ---" — người dùng đọc lên một hàng toàn gạch.
		tableSepRe = [NSRegularExpression regularExpressionWithPattern:@"^\\s*\\|?\\s*:?-{2,}:?\\s*(\\|\\s*:?-{2,}:?\\s*)*\\|?\\s*$"
															  options:NSRegularExpressionAnchorsMatchLines error:NULL];
		hrRe = [NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*(-{3,}|\\*{3,}|_{3,})[ \\t]*$"
														options:NSRegularExpressionAnchorsMatchLines error:NULL];
		blankRunsRe = [NSRegularExpression regularExpressionWithPattern:@"\\n{3,}"
																 options:NSRegularExpressionAnchorsMatchLines error:NULL];
	});

	NSMutableArray<NSString *> *outLines = [NSMutableArray array];
	BOOL inFence = NO;

	for (NSString *line in [markdown componentsSeparatedByString:@"\n"]) {
		// Khối code ``` — tự đóng khi hết input (an toàn khi render giữa chừng).
		if ([fenceRe numberOfMatchesInString:line options:0 range:NSMakeRange(0, line.length)]) {
			inFence = !inFence;
			continue;
		}
		if (inFence) {
			[outLines addObject:[@"▸ " stringByAppendingString:line]];
			continue;
		}

		// Tiêu đề → — TIÊU ĐỀ —
		NSRange hr2 = [headingRe rangeOfFirstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
		if (hr2.location != NSNotFound) {
			NSString *title = [line substringWithRange:hr2];
			title = [title stringByReplacingOccurrencesOfString:@"^#{1,6}\\s+" withString:@""
													options:NSRegularExpressionSearch
													  range:NSMakeRange(0, title.length)];
			[outLines addObject:[NSString stringWithFormat:@"— %@ —", SXMDTrim(title).uppercaseString]];
			continue;
		}

		// Phân cách --- → · · ·
		if ([hrRe numberOfMatchesInString:line options:0 range:NSMakeRange(0, line.length)]) {
			[outLines addObject:@"· · ·"];
			continue;
		}

		BOOL hasPipe = [line containsString:@"|"];
		// Bỏ dòng phân cách bảng (|---|---|)
		if (hasPipe && [tableSepRe numberOfMatchesInString:line options:0 range:NSMakeRange(0, line.length)]) {
			continue;
		}
		// Bảng → “• ô1 · ô2 …”
		if (hasPipe && [SXMDTrim(line) hasPrefix:@"|"]) {
			NSString *body = SXMDTrim(line);
			if ([body hasPrefix:@"|"]) body = [body substringFromIndex:1];
			if ([body hasSuffix:@"|"]) body = [body substringToIndex:body.length - 1];
			NSMutableArray<NSString *> *cells = [NSMutableArray array];
			for (NSString *cell in [body componentsSeparatedByString:@"|"]) {
				NSString *v = SXMDTrim(cell);
				if (v.length) [cells addObject:v];
			}
			if (cells.count) {
				[outLines addObject:[@"• " stringByAppendingString:
									 [cells componentsJoinedByString:@" · "]]];
				continue;
			}
		}

		// Ghi nhận dạng đầu dòng trước khi làm sạch inline
		BOOL wasQuote = [quoteRe numberOfMatchesInString:line options:0 range:NSMakeRange(0, line.length)] > 0;
		BOOL wasBullet = [bulletRe numberOfMatchesInString:line options:0 range:NSMakeRange(0, line.length)] > 0;
		// Danh sách chỉ khi phần số nằm ở ĐẦU dòng. Dùng vị trí khớp (không chỉ
		// "có khớp") để điều kiện này đọc rõ ngay tại chỗ và không phụ thuộc vào
		// việc dòng đang xét chắc chắn không chứa ký tự xuống dòng.
		NSRange orderedMatch = [orderedRe rangeOfFirstMatchInString:line options:0
														  range:NSMakeRange(0, line.length)];
		BOOL wasOrdered = orderedMatch.location == 0 && orderedMatch.length > 0;

		NSString *rendered = line;
		if (wasQuote) {
			rendered = [quoteRe stringByReplacingMatchesInString:rendered options:0
														   range:NSMakeRange(0, rendered.length)
													 withTemplate:@"▍"];
		}
		// Inline (thứ tự: link → code → bold → italic)
		rendered = SXMDReplaceAll(linkRe, rendered, @"$1 ($2)");
		rendered = SXMDReplaceAll(codeRe, rendered, @"$1");
		rendered = SXMDReplaceAll(boldStarRe, rendered, @"$1");
		rendered = SXMDReplaceAll(boldUnderRe, rendered, @"$1");
		rendered = SXMDReplaceAll(italicStarRe, rendered, @"$1");
		rendered = SXMDReplaceAll(italicUnderRe, rendered, @"$1");

		if (wasQuote) {
			[outLines addObject:rendered];
		} else if (wasBullet) {
			NSString *body = SXMDStripMarker(bulletRe, rendered);
			[outLines addObject:[@"• " stringByAppendingString:body]];
		} else if (wasOrdered) {
			NSString *body = [orderedRe stringByReplacingMatchesInString:rendered options:0
																	range:NSMakeRange(0, rendered.length)
															  withTemplate:@"$1. "];
			[outLines addObject:body];
		} else {
			[outLines addObject:rendered];
		}
	}

	NSString *result = [outLines componentsJoinedByString:@"\n"];
	result = [blankRunsRe stringByReplacingMatchesInString:result options:0
													 range:NSMakeRange(0, result.length)
											withTemplate:@"\n\n"];
	result = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (result.length > 2000) {
		result = [[result substringToIndex:2000] stringByAppendingString:@"…"];
	}
	return result;
}
