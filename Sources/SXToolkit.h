#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Nhóm công cụ — dùng cho cả prompt của model và màn hình Settings.
typedef NS_ENUM(NSInteger, SXToolCategory) {
	SXToolCategoryDevice = 0, // thiết bị, pin, dung lượng, mạng
	SXToolCategoryClipboard,  // bảng nhớ tạm
	SXToolCategoryWeb,        // đọc nội dung web
	SXToolCategorySystem,     // ứng dụng, URL, phím tắt
	SXToolCategoryMemory,     // ghi nhớ lâu dài
	SXToolCategoryMath,       // tính toán chính xác
};

FOUNDATION_EXPORT NSString *SXToolCategoryTitle(SXToolCategory category);

/// Lỗi công cụ luôn nằm trong domain này; message là câu tiếng Việt đọc được
/// (được đưa nguyên văn cho model để nó tự sửa tham số và thử lại).
FOUNDATION_EXPORT NSString *const SXToolErrorDomain;

/// JSON một dòng từ dictionary (dùng cho thân message `tool` của OpenAI và
/// cho message công cụ của chat thử).
FOUNDATION_EXPORT NSString *SXToolJSONString(NSDictionary *object);

/// Handler trả về @{ @“result”: NSString } hoặc nil + *error.
typedef NSDictionary * _Nullable (^SXToolHandler)(NSDictionary *arguments,
												  NSError * _Nullable * _Nullable error);

/// Một công cụ: mô tả cho model + mô tả cho người dùng + hàm thực thi.
@interface SXTool : NSObject

+ (instancetype)toolWithName:(NSString *)name
					   title:(NSString *)title
					 summary:(NSString *)summary
					  prompt:(NSString *)prompt
					category:(SXToolCategory)category
				  parameters:(NSDictionary *)parameters
					 handler:(SXToolHandler)handler;

@property (nonatomic, copy, readonly) NSString *name;       // snake_case, ổn định
@property (nonatomic, copy, readonly) NSString *title;       // tiếng Việt, cho Settings
@property (nonatomic, copy, readonly) NSString *summary;     // một câu, cho Settings
@property (nonatomic, copy, readonly) NSString *prompt;      // khi nào nên gọi, cho model
@property (nonatomic, readonly) SXToolCategory category;
@property (nonatomic, copy, readonly) NSDictionary *parameters; // JSON schema
@property (nonatomic, copy, readonly) SXToolHandler handler;

@property (nonatomic) NSTimeInterval timeout;   // mặc định 8 s
@property (nonatomic) BOOL requiresMainThread;  // chạm UIKit/pasteboard
@property (nonatomic) BOOL sideEffect;          // thay đổi trạng thái máy (mở app, chép…)
/// Công cụ chỉ đọc trạng thái máy (giờ, pin…): gọi hai lần trong cùng một lượt
/// đều phải chạy. Mặc định NO — các công cụ còn lại được cache trong lượt để
/// model lặp lại cùng tham số không tốn thêm thời gian.
@property (nonatomic) BOOL liveData;

/// @{ @“type”: @“function”, @“function”: @{ @“name”, @“description”, @“parameters” } }
- (NSDictionary *)functionPayload;
/// “url (bắt buộc), max_chars” — phần tham số cho dòng mô tả trong prompt.
- (NSString *)parameterSignature;

@end

/// Sổ đăng ký + bộ thực thi. Không phụ thuộc UIKit hay prefs để test được trên macOS.
@interface SXToolkit : NSObject

/// Đăng ký công cụ. Trùng tên thì thay thế (tiện cho test và mở rộng sau này).
+ (void)registerTool:(SXTool *)tool;
/// Bỏ toàn bộ đăng ký (chỉ dùng trong test).
+ (void)removeAllTools;

+ (NSArray<SXTool *> *)allTools;
+ (nullable SXTool *)toolNamed:(NSString *)name;

/// Danh sách công cụ đang bật (bỏ những tên nằm trong `disabled`).
+ (NSArray<SXTool *> *)toolsExcluding:(NSSet<NSString *> *)disabled;
/// Schema gửi cho model.
+ (NSArray<NSDictionary *> *)definitionsExcluding:(NSSet<NSString *> *)disabled;
/// Đoạn mô tả công cụ để nối vào system prompt.
+ (NSString *)promptBriefExcluding:(NSSet<NSString *> *)disabled;

/// Thực thi có kiểm soát: validate tham số, giới hạn thời gian, bọc exception,
/// chống gọi lặp cùng tham số trong một lượt hỏi.
+ (nullable NSDictionary *)execute:(NSString *)name
						 arguments:(NSDictionary * _Nullable)arguments
						  excluded:(NSSet<NSString *> *)disabled
							error:(NSError * _Nullable * _Nullable)error;

/// Mỗi lượt hỏi mới phải gọi hàm này (xoá cache chống lặp).
+ (void)resetCallCache;

@end

NS_ASSUME_NONNULL_END
