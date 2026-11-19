#import "SXHeaders.h"

NSUInteger const SXHeaderMaximum = 16;

static NSString *const kSXReservedNames[] = {
	@"host", @"content-length", @"content-type", @"transfer-encoding",
	@"connection", @"accept-encoding", @"expect", @"upgrade",
};

NSString *SXHeaderIssueMessage(SXHeaderIssue issue, NSString *name) {
	switch (issue) {
		case SXHeaderIssueNone:
			return @"";
		case SXHeaderIssueEmptyName:
			return @"Hãy nhập tên header (ví dụ: X-Title).";
		case SXHeaderIssueInvalidName:
			return @"Tên header chỉ được chứa chữ, số và các ký tự !#$%&'*+-.^_`|~ — không dấu cách, không dấu hai chấm.";
		case SXHeaderIssueInvalidValue:
			return @"Giá trị header không được để trống, không chứa xuống dòng và dài tối đa 4 000 ký tự.";
		case SXHeaderIssueReservedName:
			return [NSString stringWithFormat:
					@"“%@” do hệ thống tự đặt (dữ liệu JSON, độ dài, host…). Ghi đè sẽ làm request hỏng nên SiriX bỏ qua header này.",
					name.length ? name : @"Header này"];
		case SXHeaderIssueDuplicateName:
			return [NSString stringWithFormat:
					@"Đã có header “%@”. Sửa header đó thay vì thêm cái thứ hai.", name ?: @""];
		case SXHeaderIssueTooMany:
			return [NSString stringWithFormat:
					@"Chỉ nên dùng tối đa %lu header mỗi nhà cung cấp.", (unsigned long)SXHeaderMaximum];
	}
	return @"";
}

BOOL SXHeaderNameIsValid(NSString *name) {
	if (![name isKindOfClass:[NSString class]] || !name.length) return NO;
	if (name.length > 256) return NO;
	static NSCharacterSet *allowed;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSMutableCharacterSet *set = [NSMutableCharacterSet alphanumericCharacterSet];
		[set addCharactersInString:@"!#$%&'*+-.^_`|~"];
		allowed = [set copy];
	});
	for (NSUInteger i = 0; i < name.length; i++) {
		unichar code = [name characterAtIndex:i];
		if (code > 127 || ![allowed characterIsMember:code]) return NO;
	}
	return YES;
}

BOOL SXHeaderNameIsReserved(NSString *name) {
	NSString *lower = SXHeaderTrimmedName(name).lowercaseString;
	if (!lower.length) return NO;
	size_t count = sizeof(kSXReservedNames) / sizeof(kSXReservedNames[0]);
	for (size_t i = 0; i < count; i++) {
		if ([lower isEqualToString:kSXReservedNames[i]]) return YES;
	}
	return NO;
}

NSString *SXHeaderTrimmedName(NSString *name) {
	if (![name isKindOfClass:[NSString class]]) return @"";
	return [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

SXHeaderIssue SXHeaderValidate(NSString *name, NSString *value, NSArray<NSDictionary *> *existing,
							   NSString *editingName) {
	NSString *cleanName = SXHeaderTrimmedName(name);
	if (!cleanName.length) return SXHeaderIssueEmptyName;
	if (!SXHeaderNameIsValid(cleanName)) return SXHeaderIssueInvalidName;
	if (SXHeaderNameIsReserved(cleanName)) return SXHeaderIssueReservedName;

	if (![value isKindOfClass:[NSString class]]) return SXHeaderIssueInvalidValue;
	NSString *cleanValue = [value stringByTrimmingCharactersInSet:
							[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!cleanValue.length || cleanValue.length > 4000) return SXHeaderIssueInvalidValue;
	NSRange control = [cleanValue rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]];
	if (control.location != NSNotFound) return SXHeaderIssueInvalidValue;

	NSString *editing = SXHeaderTrimmedName(editingName).lowercaseString;
	NSString *candidate = cleanName.lowercaseString;
	for (NSDictionary *item in existing) {
		if (![item isKindOfClass:[NSDictionary class]]) continue;
		NSString *other = SXHeaderTrimmedName(item[@"name"]).lowercaseString;
		if (!other.length || [other isEqualToString:candidate] == NO) continue;
		if (editing.length && [editing isEqualToString:other]) continue;
		return SXHeaderIssueDuplicateName;
	}

	if (!editing.length) {
		NSUInteger count = 0;
		for (id item in existing) {
			if ([item isKindOfClass:[NSDictionary class]]) count++;
		}
		if (count >= SXHeaderMaximum) return SXHeaderIssueTooMany;
	}
	return SXHeaderIssueNone;
}

NSArray<NSDictionary *> *SXHeadersNormalized(id raw) {
	NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
	NSArray *items = nil;
	if ([raw isKindOfClass:[NSArray class]]) {
		items = raw;
	} else if ([raw isKindOfClass:[NSDictionary class]]) {
		// Chấp nhận cả dạng từ điển cũ { "X-Title": "SiriX" }.
		NSMutableArray *pairs = [NSMutableArray array];
		[(NSDictionary *)raw enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
			(void)stop;
			[pairs addObject:@{@"name": key, @"value": value}];
		}];
		items = pairs;
	}

	for (id item in items) {
		if (![item isKindOfClass:[NSDictionary class]]) continue;
		NSString *name = SXHeaderTrimmedName(item[@"name"]);
		if (!SXHeaderNameIsValid(name) || SXHeaderNameIsReserved(name)) continue;
		id rawValue = item[@"value"];
		if (![rawValue isKindOfClass:[NSString class]]) {
			if ([rawValue respondsToSelector:@selector(description)]) rawValue = [rawValue description];
			else continue;
		}
		NSString *value = [(NSString *)rawValue stringByTrimmingCharactersInSet:
						   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (!value.length || value.length > 4000) continue;
		if ([value rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location != NSNotFound) continue;

		id enabledValue = item[@"enabled"];
		BOOL enabled = enabledValue == nil ? YES : [enabledValue boolValue];

		[result addObject:@{@"name": name, @"value": value, @"enabled": @(enabled)}];
		if (result.count >= SXHeaderMaximum) break;
	}
	return result;
}

NSDictionary<NSString *, NSString *> *SXHeadersApplied(NSArray<NSDictionary *> *rules) {
	NSMutableDictionary<NSString *, NSString *> *applied = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, NSString *> *byLowercase = [NSMutableDictionary dictionary];

	for (NSDictionary *item in rules) {
		if (![item isKindOfClass:[NSDictionary class]]) continue;
		id enabledValue = item[@"enabled"];
		if (enabledValue != nil && ![enabledValue boolValue]) continue;
		NSString *name = SXHeaderTrimmedName(item[@"name"]);
		id rawValue = item[@"value"];
		if (![rawValue isKindOfClass:[NSString class]]) continue;
		NSString *value = [(NSString *)rawValue stringByTrimmingCharactersInSet:
						   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (!SXHeaderNameIsValid(name) || SXHeaderNameIsReserved(name) || !value.length) continue;

		NSString *lower = name.lowercaseString;
		NSString *existingName = byLowercase[lower];
		if (existingName.length) {
			// Trùng tên: giá trị sau thắng, giữ cách viết hoa của lần đầu.
			applied[existingName] = value;
		} else {
			byLowercase[lower] = name;
			applied[name] = value;
		}
	}
	return applied;
}

NSString *SXHeadersSummary(NSArray<NSDictionary *> *rules) {
	if (!rules.count) return @"Chưa có header tuỳ chỉnh";
	NSUInteger total = 0, enabled = 0;
	for (NSDictionary *item in rules) {
		if (![item isKindOfClass:[NSDictionary class]]) continue;
		total++;
		if (item[@"enabled"] == nil || [item[@"enabled"] boolValue]) enabled++;
	}
	if (enabled == total) {
		return [NSString stringWithFormat:@"%lu header · đang gửi tất cả", (unsigned long)total];
	}
	return [NSString stringWithFormat:@"%lu header · %lu đang bật", (unsigned long)total, (unsigned long)enabled];
}

NSString *SXHeaderValueMasked(NSString *value) {
	if (![value isKindOfClass:[NSString class]] || !value.length) return @"";
	if (value.length <= 6) return @"••••";
	NSString *tail = [value substringFromIndex:value.length - 4];
	return [NSString stringWithFormat:@"••••%@", tail];
}

NSString *SXHeaderPresetGroupTitle(SXHeaderPresetGroup group) {
	switch (group) {
		case SXHeaderPresetGroupRouting: return @"Định tuyến & đối tác";
		case SXHeaderPresetGroupAuth: return @"Xác thực thay thế";
		case SXHeaderPresetGroupDebug: return @"Gỡ lỗi";
	}
	return @"Khác";
}

NSArray<NSDictionary *> *SXHeaderPresets(SXHeaderPresetProvider provider) {
	NSMutableArray<NSDictionary *> *presets = [NSMutableArray array];
	if (provider != SXHeaderPresetProviderGemini) {
		[presets addObjectsFromArray:@[
			@{@"name": @"HTTP-Referer", @"value": @"https://sirix.app", @"match": @"openrouter",
			  @"note": @"OpenRouter dùng để xếp hạng ứng dụng", @"group": @(SXHeaderPresetGroupRouting)},
			@{@"name": @"X-Title", @"value": @"SiriX", @"match": @"openrouter",
			  @"note": @"Tên ứng dụng hiện trên OpenRouter", @"group": @(SXHeaderPresetGroupRouting)},
			@{@"name": @"api-key", @"value": @"", @"match": @"azure",
			  @"note": @"Azure OpenAI: khóa thay cho Authorization", @"group": @(SXHeaderPresetGroupAuth)},
			@{@"name": @"X-Request-Id", @"value": @"sirix",
			  @"note": @"Gateway nội bộ cần mã đơn vị", @"group": @(SXHeaderPresetGroupDebug)},
		]];
	}
	[presets addObjectsFromArray:@[
		@{@"name": @"X-Sirix-Client", @"value": @"ios",
		  @"note": @"Đánh dấu lưu lượng từ SiriX ở proxy của bạn", @"group": @(SXHeaderPresetGroupDebug)},
		@{@"name": @"X-Debug", @"value": @"1",
		  @"note": @"Bật log chi tiết ở gateway tự dựng", @"group": @(SXHeaderPresetGroupDebug)},
	]];
	return presets;
}

NSArray<NSDictionary *> *SXHeaderPresetsForEndpoint(SXHeaderPresetProvider provider, NSString *endpoint) {
	NSArray<NSDictionary *> *presets = SXHeaderPresets(provider);
	NSString *lower = [endpoint isKindOfClass:[NSString class]] ? endpoint.lowercaseString : @"";
	if (!lower.length) return presets;

	NSMutableArray<NSDictionary *> *matched = [NSMutableArray array];
	NSMutableArray<NSDictionary *> *rest = [NSMutableArray array];
	for (NSDictionary *preset in presets) {
		NSString *needle = preset[@"match"];
		BOOL hit = [needle isKindOfClass:[NSString class]] && needle.length &&
				   [lower containsString:needle];
		[(hit ? matched : rest) addObject:preset];
	}
	[matched addObjectsFromArray:rest];
	return matched;
}
