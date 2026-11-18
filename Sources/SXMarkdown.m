#import "SXMarkdown.h"

static NSString *SXMDTrim(NSString *s) {
	return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

/// Thay regex đầu tiên khớp (trả về nguyên bản nếu không khớp).
static NSString *SXMDReplaceFirst(NSRegularExpression *re, NSString *input, NSString *tmpl) {
	NSRange full = NSMakeRange(0, input.length);
	NSRange r = [re rangeOfFirstMatchInString:input options:0 range:full];
	if (r.location == NSNotFound) return input;
	return [re stringByReplacingMatchesInString:input options:0 range:full withTemplate:tmpl];
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
		italicUnderRe = [NSRegularExpression regularExpressionWithPattern:@"(?<!\\w)_(?!\\w)(.+?)(?<!\\w)_(?!\\w)"
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
		tableSepRe = [NSRegularExpression regularExpressionWithPattern:@"^\\s*\\|?\\s*:?-{2,}[^|]*$"
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
		BOOL wasOrdered = [orderedRe numberOfMatchesInString:line options:0 range:NSMakeRange(0, line.length)] > 0;

		NSString *rendered = line;
		if (wasQuote) {
			rendered = [quoteRe stringByReplacingMatchesInString:rendered options:0
														   range:NSMakeRange(0, rendered.length)
													 withTemplate:@"▍"];
		}
		// Inline (thứ tự: link → code → bold → italic)
		rendered = SXMDReplaceFirst(linkRe, rendered, @"$1 ($2)");
		rendered = SXMDReplaceFirst(codeRe, rendered, @"$1");
		rendered = SXMDReplaceFirst(boldStarRe, rendered, @"$1");
		rendered = SXMDReplaceFirst(boldUnderRe, rendered, @"$1");
		rendered = SXMDReplaceFirst(italicStarRe, rendered, @"$1");
		rendered = SXMDReplaceFirst(italicUnderRe, rendered, @"$1");

		if (wasQuote) {
			[outLines addObject:rendered];
		} else if (wasBullet) {
			NSString *body = [bulletRe stringByReplacingMatchesInString:rendered options:0
																	range:NSMakeRange(0, rendered.length)
															  withTemplate:@""];
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
