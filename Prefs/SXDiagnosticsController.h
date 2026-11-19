#import "PSViewController.h"

NS_ASSUME_NONNULL_BEGIN

/// Màn "Chẩn đoán": gom mọi điều kiện để SiriX trả lời được (bật/tắt, khoá API,
/// endpoint, model, ngân sách thời gian, trần chờ Siri, số liệu gần đây) thành
/// một danh sách có mức độ OK/cảnh báo/lỗi, kèm nút chia sẻ báo cáo.
@interface SXDiagnosticsController : PSViewController
@end

NS_ASSUME_NONNULL_END
