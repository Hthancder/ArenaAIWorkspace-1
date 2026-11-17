// SBTTS.h — phát câu trả lời, không phụ thuộc giọng Siri
#import <Foundation/Foundation.h>

@interface SBTTS : NSObject
+ (instancetype)shared;

/// Phát text. completion gọi trên main queue khi phát xong (hoặc lỗi).
/// Nếu TTSMode == 2 (Siri tự đọc) thì completion được gọi ngay lập tức.
- (void)speak:(NSString *)text completion:(void (^)(void))completion;

- (void)stop;

/// Danh sách voice AVSpeechSynthesis đã cài (để hiện trong Settings).
+ (NSArray<NSDictionary *> *)availableVoices;
@end
