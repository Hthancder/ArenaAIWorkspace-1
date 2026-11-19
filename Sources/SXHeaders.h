#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Header tuỳ chỉnh cho request tới nhà cung cấp AI.
///
/// Một header được lưu dưới dạng @{ @"name": NSString, @"value": NSString,
/// @"enabled": NSNumber }. Tầng này là nguồn sự thật duy nhất cho cả giao diện
/// Settings và pipeline mạng (`SXLLM`): cùng một hàm kiểm tra, cùng một cách
/// chuẩn hoá — nên cái gì hiện trong Settings đúng là cái được gửi đi.

/// Trần số header mỗi nhà cung cấp. Đủ cho mọi gateway thực tế, đủ nhỏ để một
/// danh sách dài không âm thầm làm request chậm.
FOUNDATION_EXPORT NSUInteger const SXHeaderMaximum;

typedef NS_ENUM(NSInteger, SXHeaderIssue) {
	SXHeaderIssueNone = 0,
	SXHeaderIssueEmptyName,
	SXHeaderIssueInvalidName,    // không phải token RFC 7230
	SXHeaderIssueInvalidValue,   // rỗng, quá dài, hoặc chứa CR/LF
	SXHeaderIssueReservedName,   // header do hệ thống tự đặt
	SXHeaderIssueDuplicateName,  // đã có header cùng tên trong danh sách
	SXHeaderIssueTooMany,        // đã đạt SXHeaderMaximum
};

/// Câu giải thích tiếng Việt cho lỗi — hiển thị ngay dưới ô nhập.
FOUNDATION_EXPORT NSString *SXHeaderIssueMessage(SXHeaderIssue issue, NSString * _Nullable name);

/// Tên header hợp lệ theo RFC 7230 (token): chữ, số và !#$%&'*+-.^_`|~
FOUNDATION_EXPORT BOOL SXHeaderNameIsValid(NSString * _Nullable name);

/// Header hệ thống: ghi đè sẽ làm hỏng request (body JSON, độ dài, host…).
FOUNDATION_EXPORT BOOL SXHeaderNameIsReserved(NSString * _Nullable name);

/// Chuẩn hoá tên để hiển thị: giữ nguyên chữ người dùng gõ nhưng bỏ khoảng trắng
/// thừa hai đầu ("  X-Title  " → "X-Title").
FOUNDATION_EXPORT NSString *SXHeaderTrimmedName(NSString * _Nullable name);

/// Kiểm tra một cặp name/value trước khi lưu.
///
/// @param existing  danh sách header hiện có (để bắt trùng tên)
/// @param editingName  tên đang sửa (nil khi thêm mới) — trùng với chính nó không tính là lỗi
FOUNDATION_EXPORT SXHeaderIssue SXHeaderValidate(NSString * _Nullable name,
												 NSString * _Nullable value,
												 NSArray<NSDictionary *> * _Nullable existing,
												 NSString * _Nullable editingName);

/// Làm sạch dữ liệu thô đọc từ prefs: bỏ rác, bỏ header sai, cắt trần, điền
/// `enabled` mặc định. Luôn trả về mảng (có thể rỗng), không bao giờ nil.
FOUNDATION_EXPORT NSArray<NSDictionary *> *SXHeadersNormalized(id _Nullable raw);

/// Bộ header thực sự gửi đi: chỉ header đang bật và hợp lệ. Trùng tên (không
/// phân biệt hoa thường) thì giá trị sau thắng; thứ tự giữ theo lần xuất hiện đầu.
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> *SXHeadersApplied(NSArray<NSDictionary *> * _Nullable rules);

/// "3 header · 2 bật" / "Chưa có header" — nhãn tóm tắt cho Settings.
FOUNDATION_EXPORT NSString *SXHeadersSummary(NSArray<NSDictionary *> * _Nullable rules);

/// Giá trị đã che để hiển thị trong danh sách ("••••••a1b2") — không lộ token.
FOUNDATION_EXPORT NSString *SXHeaderValueMasked(NSString * _Nullable value);

typedef NS_ENUM(NSInteger, SXHeaderPresetGroup) {
	SXHeaderPresetGroupRouting = 0, // OpenRouter, gateway
	SXHeaderPresetGroupAuth,        // Azure api-key, Anthropic
	SXHeaderPresetGroupDebug,       // X-Debug, X-Request-Id
};

typedef NS_ENUM(NSInteger, SXHeaderPresetProvider) {
	SXHeaderPresetProviderAny = 0,
	SXHeaderPresetProviderOpenAI,
	SXHeaderPresetProviderGemini,
};

/// Gợi ý header theo nhà cung cấp: @[ @{ @"name", @"value", @"note", @"group", @"match" } ].
/// Chỉ là gợi ý — người dùng sửa được ngay trong màn hình thêm header.
/// `match` (nếu có) là đoạn cần thấy trong endpoint để gợi ý được xếp lên đầu.
FOUNDATION_EXPORT NSArray<NSDictionary *> *SXHeaderPresets(SXHeaderPresetProvider provider);

/// Như `SXHeaderPresets` nhưng xếp gợi ý khớp endpoint hiện tại lên trước:
/// endpoint OpenRouter → HTTP-Referer/X-Title, endpoint Azure → api-key…
/// Giữ nguyên thứ tự tương đối trong từng nhóm.
FOUNDATION_EXPORT NSArray<NSDictionary *> *SXHeaderPresetsForEndpoint(SXHeaderPresetProvider provider,
																	 NSString * _Nullable endpoint);

/// Tiêu đề nhóm gợi ý.
FOUNDATION_EXPORT NSString *SXHeaderPresetGroupTitle(SXHeaderPresetGroup group);

NS_ASSUME_NONNULL_END
