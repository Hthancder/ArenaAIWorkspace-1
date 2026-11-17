// SBCapture.h — bắt text người dùng từ SASSpeechRecognized / SASRequestOptions
#import <Foundation/Foundation.h>

/// Trích câu người dùng từ SASSpeechRecognized (ACE object).
FOUNDATION_EXPORT NSString *SBCaptureTextFromSpeechRecognized(id recognized);

/// Trích câu người dùng từ SASRequestOptions (Type-to-Siri).
FOUNDATION_EXPORT NSString *SBCaptureTextFromRequestOptions(id options);

/// Lưu text của turn hiện tại để các hook sau dùng lại.
FOUNDATION_EXPORT void     SBCaptureRememberTurnText(NSString *text);
FOUNDATION_EXPORT NSString *SBCaptureCurrentTurnText(void);
FOUNDATION_EXPORT void     SBCaptureClearTurn(void);

/// Bắt đầu một "sink" cho câu trả lời LLM (xem SBAnswer.h).
FOUNDATION_EXPORT void     SBCaptureSetAnswerSink(id sink);
FOUNDATION_EXPORT id       SBCaptureAnswerSink(void);
