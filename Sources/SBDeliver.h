// SBDeliver.h — bơm ACE command vào Siri UI qua delegate
#import <Foundation/Foundation.h>

/// Gửi command cho delegate của AFUISiriSession (vd SRSiriViewController).
/// Trả về YES nếu delegate có xử lý.
FOUNDATION_EXPORT BOOL SBDeliverCommand(id delegate, id command, NSString *selectorName);

/// YES khi luồng hiện tại đang bơm câu trả lời của chính SiriBridge
/// (các hook chặn AddViews phải bỏ qua trong trường hợp này).
FOUNDATION_EXPORT BOOL SBDeliverIsOwnInjection(void);

/// Đánh dấu "đây là câu trả lời của SiriBridge" quanh một khối code.
FOUNDATION_EXPORT void SBDeliverMarkOwn(BOOL own);
