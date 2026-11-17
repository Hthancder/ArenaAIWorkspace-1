// SBRootListController.m — bảng cấu hình SiriBridge (UI tuỳ biến, không dùng specifier)
#import <Preferences/PSViewController.h>
#import <notify.h>
#import <AVFoundation/AVFoundation.h>
#import "SBPrefsUI.h"
#import "SBPaths.h"

static NSString *const kDomain = @"com.hthancder.siribridge";

#pragma mark - Header

@interface SBHeroHeader : UIView
@property (nonatomic, strong) UISwitch *masterSwitch;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *statusPill;
@property (nonatomic, strong) CAGradientLayer *gradient;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
@end

@implementation SBHeroHeader

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 20.0;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.clipsToBounds = YES;

        _gradient = [CAGradientLayer layer];
        _gradient.colors = @[(id)[[SBTheme accent] colorWithAlphaComponent:0.95].CGColor,
                             (id)[[UIColor colorWithRed:0.15 green:0.53 blue:0.98 alpha:0.92] CGColor]];
        _gradient.startPoint = CGPointMake(0.0, 0.0);
        _gradient.endPoint = CGPointMake(1.0, 1.0);
        [self.layer addSublayer:_gradient];

        UIImageView *icon = [[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:@"waveform" withConfiguration:
                [UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightBold]]];
        icon.tintColor = UIColor.whiteColor;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
        icon.layer.cornerRadius = 12.0;
        icon.layer.cornerCurve = kCACornerCurveContinuous;
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        [icon.widthAnchor constraintEqualToConstant:44.0].active = YES;
        [icon.heightAnchor constraintEqualToConstant:44.0].active = YES;

        UILabel *title = [[UILabel alloc] init];
        title.text = @"SiriBridge";
        title.font = [SBTheme titleFont:24.0];
        title.textColor = UIColor.whiteColor;

        UILabel *subtitle = [[UILabel alloc] init];
        subtitle.text = @"Siri + LLM endpoint của bạn";
        subtitle.font = [SBTheme bodyFont:13.0];
        subtitle.textColor = [UIColor colorWithWhite:1.0 alpha:0.82];

        UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[title, subtitle]];
        texts.axis = UILayoutConstraintAxisVertical;
        texts.spacing = 1.0;

        _masterSwitch = [[UISwitch alloc] init];
        _masterSwitch.onTintColor = [UIColor colorWithWhite:1.0 alpha:0.35];
        [_masterSwitch setContentHuggingPriority:UILayoutPriorityRequired
                                  forAxis:UILayoutConstraintAxisHorizontal];

        UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[icon, texts,
                                                                          [[UIView alloc] init],
                                                                          _masterSwitch]];
        top.axis = UILayoutConstraintAxisHorizontal;
        top.spacing = 12.0;
        top.alignment = UIStackViewAlignmentCenter;
        top.translatesAutoresizingMaskIntoConstraints = NO;

        _statusPill = [[UIView alloc] init];
        _statusPill.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.20];
        _statusPill.layer.cornerRadius = 11.0;
        _statusPill.translatesAutoresizingMaskIntoConstraints = NO;
        _statusLabel = [[UILabel alloc] init];
        _statusLabel.font = [SBTheme titleFont:11.0];
        _statusLabel.textColor = UIColor.whiteColor;
        _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_statusPill addSubview:_statusLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_statusLabel.leadingAnchor constraintEqualToAnchor:_statusPill.leadingAnchor constant:10.0],
            [_statusLabel.trailingAnchor constraintEqualToAnchor:_statusPill.trailingAnchor constant:-10.0],
            [_statusLabel.topAnchor constraintEqualToAnchor:_statusPill.topAnchor constant:4.0],
            [_statusLabel.bottomAnchor constraintEqualToAnchor:_statusPill.bottomAnchor constant:-4.0],
            [_statusPill.heightAnchor constraintEqualToConstant:22.0],
        ]];

        UILabel *hint = [[UILabel alloc] init];
        hint.text = @"Nói bất cứ điều gì với Siri — câu trả lời đến từ mô hình bạn chọn.";
        hint.font = [SBTheme bodyFont:12.0];
        hint.textColor = [UIColor colorWithWhite:1.0 alpha:0.80];
        hint.numberOfLines = 2;

        UIStackView *bottom = [[UIStackView alloc] initWithArrangedSubviews:@[_statusPill, hint]];
        bottom.axis = UILayoutConstraintAxisVertical;
        bottom.spacing = 8.0;
        bottom.alignment = UIStackViewAlignmentLeading;
        bottom.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:top];
        [self addSubview:bottom];
        [NSLayoutConstraint activateConstraints:@[
            [top.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16.0],
            [top.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
            [top.topAnchor constraintEqualToAnchor:self.topAnchor constant:16.0],
            [bottom.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16.0],
            [bottom.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
            [bottom.topAnchor constraintEqualToAnchor:top.bottomAnchor constant:14.0],
            [bottom.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-16.0],
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _gradient.frame = self.bounds;
}

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    _masterSwitch.on = on;
    _statusLabel.text = on ? @"ĐANG BẬT" : @"ĐANG TẮT";
    _statusPill.backgroundColor = on ? [UIColor colorWithRed:0.13 green:0.77 blue:0.42 alpha:0.95]
                                     : [UIColor colorWithWhite:1.0 alpha:0.20];
    if (animated) {
        [UIView transitionWithView:_statusPill duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:nil completion:nil];
    }
}

@end

#pragma mark - Controller

@interface SBRootListController : PSViewController
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) SBHeroHeader *hero;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *dependencies;   // row, key, expected
@property (nonatomic, strong) NSMutableArray<SBRowView *> *allRows;
@property (nonatomic, strong) UIButton *advancedButton;
@property (nonatomic, strong) NSMutableArray<UIView *> *advancedViews;
@property (nonatomic, strong) NSMutableArray<SBRowView *> *localVoiceRows;
@property (nonatomic, strong) SBCardView *remoteCard;
@property (nonatomic, assign) BOOL advancedExpanded;
@end

@implementation SBRootListController

#pragma mark Lifecycle

- (instancetype)init {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _dependencies = [NSMutableArray array];
        _allRows = [NSMutableArray array];
        _advancedViews = [NSMutableArray array];
        _localVoiceRows = [NSMutableArray array];
    }
    return self;
}

- (instancetype)initForContentSize:(CGSize)contentSize {
    return [self init];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SBTheme bg];
    if (@available(iOS 13.0, *)) self.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;

    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = 10.0;
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentStack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:14.0],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-28.0],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16.0],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16.0],
    ]];

    [self buildUI];

    // Cập nhật lại khi quay về từ app khác (cấu hình có thể đã đổi)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadAll)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)reloadAll {
    for (SBRowView *row in self.allRows) [row refreshValue];
    [self.hero setOn:[SBSettingsStore.shared boolForKey:@"Enabled" def:NO] animated:YES];
    [self applyDependencies];
    [self refreshTTSVisibility];
}

#pragma mark Building blocks

- (void)addSectionHeader:(NSString *)title {
    UILabel *l = [[UILabel alloc] init];
    l.text = [title uppercaseString];
    l.font = [SBTheme titleFont:11.5];
    l.textColor = [SBTheme secondaryLabel];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *wrap = [[UIView alloc] init];
    [wrap addSubview:l];
    [NSLayoutConstraint activateConstraints:@[
        [l.leadingAnchor constraintEqualToAnchor:wrap.leadingAnchor constant:6.0],
        [l.trailingAnchor constraintLessThanOrEqualToAnchor:wrap.trailingAnchor],
        [l.topAnchor constraintEqualToAnchor:wrap.topAnchor constant:12.0],
        [l.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor],
    ]];
    [self.contentStack addArrangedSubview:wrap];
}

- (SBCardView *)addCard {
    SBCardView *card = [[SBCardView alloc] init];
    [self.contentStack addArrangedSubview:card];
    return card;
}

/// Thêm row vào card, có phân cách tự động.
- (void)addRow:(SBRowView *)row toCard:(SBCardView *)card {
    if (card.stack.arrangedSubviews.count > 0) [card addSeparator];
    [card addArrangedSubview:row];
    if (row.key) [self.allRows addObject:row];
}

- (void)registerRow:(SBRowView *)row dependsOn:(NSString *)key value:(BOOL)value {
    [self.dependencies addObject:@{@"row": row, @"key": key, @"value": @(value)}];
}

- (void)applyDependencies {
    for (NSDictionary *d in self.dependencies) {
        SBRowView *row = d[@"row"];
        BOOL on = [SBSettingsStore.shared boolForKey:d[@"key"] def:YES];
        BOOL ok = (on == [d[@"value"] boolValue]);
        row.hidden = !ok;
    }
}

#pragma mark UI

- (void)buildUI {
    SBSettingsStore *store = SBSettingsStore.shared;

    // ---------- Hero ----------
    self.hero = [[SBHeroHeader alloc] init];
    [self.contentStack addArrangedSubview:self.hero];
    [self.hero.masterSwitch addTarget:self action:@selector(masterToggled:)
                     forControlEvents:UIControlEventValueChanged];
    [self.hero setOn:[store boolForKey:@"Enabled" def:NO] animated:NO];

    // ---------- Kích hoạt ----------
    [self addSectionHeader:@"Kích hoạt"];
    SBCardView *card = [self addCard];

    SBRowView *enabled = [SBRowView switchRow:@"Bật SiriBridge" subtitle:nil key:@"Enabled" def:NO];
    enabled.onChange = ^(id value) {
        [self.hero setOn:[value boolValue] animated:YES];
        [self applyDependencies];
        [self updateAdvancedButtonState];
    };
    [self addRow:enabled toCard:card];

    SBRowView *replace = [SBRowView switchRow:@"Thay câu trả lời của Siri"
                                     subtitle:@"Không cho Siri gốc trả lời khi đã có kết quả"
                                          key:@"ReplaceSiri" def:YES];
    [self addRow:replace toCard:card];

    SBRowView *prefix = [SBRowView textRow:@"Chỉ xử lý khi câu bắt đầu bằng"
                                 subtitle:@"Để trống = mọi câu nói"
                                      key:@"ActivationPrefix" def:@"" placeholder:@"ví dụ: ai"
                                 keyboard:UIKeyboardTypeDefault isSecret:NO];
    [self addRow:prefix toCard:card];

    SBRowView *keywords = [SBRowView longTextRow:@"Từ khoá dành cho Siri gốc"
                                        subtitle:@"Câu chứa các từ này sẽ do Siri xử lý"
                                             key:@"NativeKeywords" def:@"báo thức,hẹn giờ,alarm,timer"
                                     placeholder:@"báo thức, hẹn giờ, alarm, timer, gọi điện"];
    [self addRow:keywords toCard:card];

    // ---------- Trả lời ----------
    [self addSectionHeader:@"Trả lời"];
    card = [self addCard];

    SBRowView *speak = [SBRowView switchRow:@"Đọc câu trả lời" subtitle:nil
                                        key:@"SpeakAnswer" def:YES];
    [self addRow:speak toCard:card];

    [self addRow:[SBRowView switchRow:@"Cho phép điều khiển máy"
                             subtitle:@"Bật/tắt, âm lượng, mở app, lịch, liên hệ…"
                                  key:@"UseTools" def:YES]
          toCard:card];

    [self addRow:[SBRowView switchRow:@"Tự đóng Siri sau khi trả lời" subtitle:nil
                                  key:@"DismissAfterAnswer" def:NO]
          toCard:card];

    // ---------- Mô hình ----------
    [self addSectionHeader:@"Mô hình (endpoint)"];
    card = [self addCard];

    [self addRow:[SBRowView choiceRow:@"Preset nhanh"
                             subtitle:@"Điền sẵn endpoint, model, field trả lời"
                                  key:@"__preset" def:@"" choices:@[
                                      @{@"value": @"openai",    @"title": @"OpenAI",             @"detail": @"api.openai.com · gpt-4o-mini"},
                                      @{@"value": @"openrouter", @"title": @"OpenRouter",        @"detail": @"openrouter.ai · mọi model"},
                                      @{@"value": @"ollama",     @"title": @"Ollama (LAN)",      @"detail": @"192.168.x.x:11434 · llama3.1"},
                                      @{@"value": @"lmstudio",   @"title": @"LM Studio (LAN)",   @"detail": @"localhost:1234 · model cục bộ"},
                                      @{@"value": @"gemini",     @"title": @"Gemini",            @"detail": @"generativelanguage.googleapis.com"},
                                      @{@"value": @"groq",       @"title": @"Groq",              @"detail": @"api.groq.com · llama-3.3-70b"},
                                      @{@"value": @"custom",     @"title": @"Tự cấu hình",       @"detail": @"Giữ nguyên giá trị hiện tại"}]
                     ] toCard:card];

    // Hook preset: choice row ghi vào __preset, ta phản ứng riêng
    SBRowView *presetRow = (SBRowView *)card.stack.arrangedSubviews.lastObject;
    __weak typeof(self) weakSelf = self;
    presetRow.onChange = ^(id value) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self applyPreset:[value description]];
    };

    [self addRow:[SBRowView textRow:@"Endpoint (POST)"
                           subtitle:@"OpenAI-compatible /v1/chat/completions"
                                key:@"Endpoint" def:@"https://api.openai.com/v1/chat/completions"
                        placeholder:@"https://…/v1/chat/completions"
                           keyboard:UIKeyboardTypeURL isSecret:NO]
          toCard:card];

    [self addRow:[SBRowView textRow:@"API key" subtitle:@"Lưu trong plist của tweak"
                                key:@"APIKey" def:@"" placeholder:@"sk-…"
                           keyboard:UIKeyboardTypeDefault isSecret:YES]
          toCard:card];

    [self addRow:[SBRowView textRow:@"Model" subtitle:nil key:@"Model" def:@"gpt-4o-mini"
                        placeholder:@"gpt-4o-mini"
                           keyboard:UIKeyboardTypeDefault isSecret:NO]
          toCard:card];

    [self addRow:[SBRowView textRow:@"Field chứa câu trả lời"
                           subtitle:@"Đường dẫn JSON, dấu . phân cấp"
                                key:@"ResponseField" def:@"choices.0.message.content"
                        placeholder:@"choices.0.message.content"
                           keyboard:UIKeyboardTypeDefault isSecret:NO]
          toCard:card];

    [self addRow:[SBRowView longTextRow:@"System prompt"
                               subtitle:@"Định hình giọng điệu trả lời"
                                    key:@"SystemPrompt" def:@""
                            placeholder:@"Bạn là trợ lý giọng nói trên iPhone. Trả lời rất ngắn gọn, không markdown."]
          toCard:card];

    // ---------- Tinh chỉnh ----------
    [self addSectionHeader:@"Tinh chỉnh"];
    card = [self addCard];

    [self addRow:[SBRowView sliderRow:@"Temperature" key:@"Temperature" def:0.6 min:0.0 max:1.5
                               format:^NSString *(double v) { return [NSString stringWithFormat:@"%.2f", v]; }]
          toCard:card];

    [self addRow:[SBRowView sliderRow:@"Max tokens" key:@"MaxTokens" def:400 min:64 max:2048
                               format:^NSString *(double v) { return [NSString stringWithFormat:@"%d", (int)v]; }]
          toCard:card];

    [self addRow:[SBRowView sliderRow:@"Số lượt nhớ lại" key:@"HistoryTurns" def:6 min:0 max:20
                               format:^NSString *(double v) { return [NSString stringWithFormat:@"%d", (int)v]; }]
          toCard:card];

    [self addRow:[SBRowView sliderRow:@"Timeout" key:@"Timeout" def:45 min:10 max:120
                               format:^NSString *(double v) { return [NSString stringWithFormat:@"%ds", (int)v]; }]
          toCard:card];

    [self addRow:[SBRowView longTextRow:@"Header phụ (JSON)"
                               subtitle:@"Thêm header tuỳ ý khi gọi endpoint"
                                    key:@"ExtraHeaders" def:@"" placeholder:@"{\"X-Title\": \"Siri\"}"]
          toCard:card];

    [self addRow:[SBRowView longTextRow:@"Body template (JSON)"
                               subtitle:@"Trống = body chuẩn OpenAI"
                                    key:@"BodyTemplate" def:@""
                            placeholder:@"{\"model\":\"{{MODEL}}\",\"messages\":{{MESSAGES}}}"]
          toCard:card];

    [self addRow:[SBRowView actionRow:@"Kiểm tra kết nối" subtitle:@"Gửi thử một câu và in kết quả"
                                color:nil
                               action:^{ [self testConnection]; }]
          toCard:card];

    // ---------- Giọng đọc ----------
    [self addSectionHeader:@"Giọng đọc"];
    card = [self addCard];

    SBRowView *ttsMode = [SBRowView segmentRow:@"Kiểu TTS" key:@"TTSMode" def:0
                                        titles:@[@"Máy", @"Endpoint", @"Siri"]];
    [self addRow:ttsMode toCard:card];
    __weak typeof(self) weakTTS = self;
    ttsMode.onChange = ^(id value) {
        __strong typeof(weakTTS) self = weakTTS;
        [self refreshTTSVisibility];
    };

    // Giọng on-device
    SBRowView *voice = [SBRowView choiceRow:@"Giọng on-device"
                                   subtitle:@"Danh sách voice đã cài trên máy"
                                        key:@"TTSVoiceID" def:@""
                                    choices:[self voiceChoices]];
    [self addRow:voice toCard:card];
    [self.localVoiceRows addObject:voice];

    SBRowView *rate = [SBRowView sliderRow:@"Tốc độ đọc" key:@"TTSRate" def:0.5 min:0.0 max:1.0
                                    format:^NSString *(double v) { return [NSString stringWithFormat:@"%.2f", v]; }];
    [self addRow:rate toCard:card];
    [self.localVoiceRows addObject:rate];

    SBRowView *pitch = [SBRowView sliderRow:@"Cao độ" key:@"TTSPitch" def:1.0 min:0.5 max:2.0
                                     format:^NSString *(double v) { return [NSString stringWithFormat:@"%.2f", v]; }];
    [self addRow:pitch toCard:card];
    [self.localVoiceRows addObject:pitch];

    SBRowView *volume = [SBRowView sliderRow:@"Âm lượng" key:@"TTSVolume" def:1.0 min:0.0 max:1.0
                                      format:^NSString *(double v) { return [NSString stringWithFormat:@"%.0f%%", v * 100]; }];
    [self addRow:volume toCard:card];
    [self.localVoiceRows addObject:volume];

    // Endpoint TTS (chỉ hiện khi mode == 1)
    SBCardView *remoteCard = [self addCard];
    self.remoteCard = remoteCard;
    SBRowView *remoteEndpoint = [SBRowView textRow:@"Endpoint TTS" subtitle:@"OpenAI /audio/speech, ElevenLabs…"
                                               key:@"TTSEndpoint" def:@"https://api.openai.com/v1/audio/speech"
                                       placeholder:@"https://…/audio/speech"
                                          keyboard:UIKeyboardTypeURL isSecret:NO];
    [self addRow:remoteEndpoint toCard:remoteCard];

    SBRowView *remoteVoice = [SBRowView textRow:@"Voice" subtitle:@"alloy, nova, vi-VN-Neural…"
                                            key:@"TTSRemoteVoice" def:@"alloy" placeholder:@"alloy"
                                       keyboard:UIKeyboardTypeDefault isSecret:NO];
    [self addRow:remoteVoice toCard:remoteCard];

    SBRowView *remoteHeaders = [SBRowView longTextRow:@"Header (JSON)" subtitle:nil
                                                  key:@"TTSHeaders" def:@"" placeholder:@"{\"xi-api-key\":\"…\"}"];
    [self addRow:remoteHeaders toCard:remoteCard];

    SBRowView *remoteBody = [SBRowView longTextRow:@"Body template (JSON)" subtitle:@"{{TEXT}} và {{VOICE}} được thay tự động"
                                               key:@"TTSBodyTemplate" def:@""
                                       placeholder:@"{\"input\":\"{{TEXT}}\",\"voice\":\"{{VOICE}}\"}"];
    [self addRow:remoteBody toCard:remoteCard];

    SBRowView *isAudio = [SBRowView switchRow:@"Response là audio nhị phân" subtitle:nil
                                          key:@"TTSResponseIsAudio" def:YES];
    [self addRow:isAudio toCard:remoteCard];

    SBRowView *audioField = [SBRowView textRow:@"Nếu là JSON: field base64" subtitle:nil
                                           key:@"TTSResponseField" def:@"" placeholder:@"data"
                                      keyboard:UIKeyboardTypeDefault isSecret:NO];
    [self addRow:audioField toCard:remoteCard];

    // ---------- Nâng cao (thu gọn) ----------
    self.advancedButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.advancedButton setTitle:@"  Nâng cao & gỡ lỗi" forState:UIControlStateNormal];
    [self.advancedButton setImage:[UIImage systemImageNamed:@"chevron.right"] forState:UIControlStateNormal];
    self.advancedButton.titleLabel.font = [SBTheme titleFont:14.0];
    self.advancedButton.tintColor = [SBTheme accent];
    self.advancedButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.advancedButton.imageEdgeInsets = UIEdgeInsetsMake(0, 4, 0, 0);
    [self.advancedButton addTarget:self action:@selector(toggleAdvanced) forControlEvents:UIControlEventTouchUpInside];
    [self.contentStack addArrangedSubview:self.advancedButton];

    SBCardView *advCard = [self addCard];
    advCard.hidden = YES;
    [self.advancedViews addObject:advCard];

    NSString *jb = [self jailbreakRoot];
    [advCard addArrangedSubview:[SBRowView infoRow:@"Môi trường"
                                          subtitle:[NSString stringWithFormat:@"%@ · jbroot: %@",
                                                    [self environmentName], jb]]];

    SBRowView *reset = [SBRowView actionRow:@"Xoá lịch sử hội thoại" subtitle:@"Bắt đầu cuộc trò chuyện mới"
                                      color:[SBTheme warning]
                                     action:^{ [self resetHistory]; }];
    [self addRow:reset toCard:advCard];

    SBRowView *resetAll = [SBRowView actionRow:@"Đặt lại toàn bộ cấu hình" subtitle:@"Xoá mọi tuỳ chọn đã lưu"
                                         color:[UIColor systemRedColor]
                                        action:^{ [self confirmResetAll]; }];
    [self addRow:resetAll toCard:advCard];

    SBRowView *voices = [SBRowView actionRow:@"Liệt kê voice ra log" subtitle:@"Xem trong Console.app"
                                       color:nil
                                      action:^{
        for (AVSpeechSynthesisVoice *v in [AVSpeechSynthesisVoice speechVoices])
            NSLog(@"[SiriBridge] voice %@ (%@) %@", v.name, v.language, v.identifier);
    }];
    [self addRow:voices toCard:advCard];

    // ---------- Footer ----------
    UILabel *footer = [[UILabel alloc] init];
    footer.text = @"SiriBridge 0.1.0 · mã nguồn mở, miễn phí\nKhông telemetry · Không tài khoản · arm64 rootless + roothide";
    footer.font = [SBTheme bodyFont:11.5];
    footer.textColor = [SBTheme secondaryLabel];
    footer.textAlignment = NSTextAlignmentCenter;
    footer.numberOfLines = 0;
    [self.contentStack setCustomSpacing:18.0 afterView:self.advancedButton];
    [self.contentStack addArrangedSubview:footer];

    [self applyDependencies];
    [self refreshTTSVisibility];
    [self updateAdvancedButtonState];
}

#pragma mark TTS visibility

- (void)refreshTTSVisibility {
    NSInteger mode = [SBSettingsStore.shared intForKey:@"TTSMode" def:0];
    self.remoteCard.hidden = (mode != 1);
    BOOL localEnabled = (mode == 0);
    for (SBRowView *row in self.localVoiceRows) {
        row.hidden = (mode == 2);
        [row setEnabled:localEnabled];
    }
}

#pragma mark Presets

- (void)applyPreset:(NSString *)preset {
    SBSettingsStore *store = SBSettingsStore.shared;
    NSDictionary *values = @{
        @"openai": @{@"Endpoint": @"https://api.openai.com/v1/chat/completions",
                     @"Model": @"gpt-4o-mini",
                     @"ResponseField": @"choices.0.message.content"},
        @"openrouter": @{@"Endpoint": @"https://openrouter.ai/api/v1/chat/completions",
                         @"Model": @"anthropic/claude-3.5-haiku",
                         @"ResponseField": @"choices.0.message.content"},
        @"ollama": @{@"Endpoint": @"http://192.168.1.10:11434/v1/chat/completions",
                     @"Model": @"llama3.1",
                     @"ResponseField": @"choices.0.message.content"},
        @"lmstudio": @{@"Endpoint": @"http://192.168.1.10:1234/v1/chat/completions",
                       @"Model": @"local-model",
                       @"ResponseField": @"choices.0.message.content"},
        @"gemini": @{@"Endpoint": @"https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
                     @"Model": @"gemini-2.0-flash",
                     @"ResponseField": @"choices.0.message.content"},
        @"groq": @{@"Endpoint": @"https://api.groq.com/openai/v1/chat/completions",
                   @"Model": @"llama-3.3-70b-versatile",
                   @"ResponseField": @"choices.0.message.content"},
    }[preset];

    if (!values) return;   // "custom": không đổi gì

    for (NSString *k in values) [store setString:values[k] forKey:k];
    [self reloadAll];

    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Đã điền preset"
                                                              message:[NSString stringWithFormat:
                                  @"%@\n%@", values[@"Endpoint"], values[@"Model"]]
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark Advanced

- (void)toggleAdvanced {
    self.advancedExpanded = !self.advancedExpanded;
    for (UIView *v in self.advancedViews) v.hidden = !self.advancedExpanded;
    [self updateAdvancedButtonState];
    if (self.advancedExpanded) {
        [UIView animateWithDuration:0.25 animations:^{ [self.view layoutIfNeeded]; }];
    }
}

- (void)updateAdvancedButtonState {
    UIImage *img = [UIImage systemImageNamed:self.advancedExpanded ? @"chevron.down" : @"chevron.right"];
    [self.advancedButton setImage:img forState:UIControlStateNormal];
}

- (NSString *)jailbreakRoot { return SBJailbreakRoot(); }

- (NSString *)environmentName {
    if (SBIsRootHide()) return @"roothide";
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
    return @"roothide (chưa resolve được jbroot)";
#else
    return [SBJailbreakRoot() isEqualToString:@"/"] ? @"rootful?!" : @"rootless";
#endif
}

#pragma mark Actions

- (void)masterToggled:(UISwitch *)sw {
    [SBSettingsStore.shared setBool:sw.isOn forKey:@"Enabled"];
    [self.hero setOn:sw.isOn animated:YES];
    [self applyDependencies];
}

- (void)resetHistory {
    notify_post("com.hthancder.siribridge/resetHistory");
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Đã xoá lịch sử"
                                                              message:@"SiriBridge sẽ bắt đầu cuộc trò chuyện mới."
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)confirmResetAll {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Đặt lại toàn bộ?"
                                                              message:@"Mọi tuỳ chọn sẽ bị xoá. Bạn có chắc?"
                                                       preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Xoá tất cả" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kDomain];
        for (NSString *key in d.dictionaryRepresentation.allKeys) [d removeObjectForKey:key];
        [d synchronize];
        [self reloadAll];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),
                                                            CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (NSArray<NSDictionary *> *)voiceChoices {
    NSMutableArray *out = [NSMutableArray arrayWithObject:@{@"value": @"", @"title": @"Tự động (theo ngôn ngữ máy)"}];
    for (AVSpeechSynthesisVoice *v in [AVSpeechSynthesisVoice speechVoices]) {
        [out addObject:@{@"value": v.identifier ?: @"",
                         @"title": [NSString stringWithFormat:@"%@", v.name ?: @"?"],
                         @"detail": v.language ?: @""}];
    }
    return out;
}

#pragma mark Test connection

- (void)testConnection {
    SBSettingsStore *store = SBSettingsStore.shared;
    NSString *endpoint = [store stringForKey:@"Endpoint" def:@""];
    if (endpoint.length == 0) {
        [self alert:@"Thiếu endpoint" body:@"Hãy nhập endpoint trước khi kiểm tra."];
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:endpoint]];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = MAX(10, [store doubleForKey:@"Timeout" def:45]);
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSString *key = [store stringForKey:@"APIKey" def:@""];
    if (key.length) [req setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];

    NSString *headers = [store stringForKey:@"ExtraHeaders" def:@""];
    if (headers.length) {
        NSData *hd = [headers dataUsingEncoding:NSUTF8StringEncoding];
        id obj = hd ? [NSJSONSerialization JSONObjectWithData:hd options:0 error:NULL] : nil;
        if ([obj isKindOfClass:[NSDictionary class]]) {
            [(NSDictionary *)obj enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
                [req setValue:[v description] forHTTPHeaderField:[k description]];
            }];
        }
    }

    NSDictionary *body = @{
        @"model": [store stringForKey:@"Model" def:@"gpt-4o-mini"],
        @"messages": @[@{@"role": @"user", @"content": @"ping"}],
        @"max_tokens": @(16),
    };
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (err) {
                [self alert:@"Không kết nối được" body:err.localizedDescription];
                return;
            }
            NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
            NSString *text = [[NSString alloc] initWithData:data ?: [NSData data]
                                                   encoding:NSUTF8StringEncoding] ?: @"";
            if (text.length > 400) text = [[text substringToIndex:400] stringByAppendingString:@"…"];
            [self alert:[NSString stringWithFormat:@"HTTP %ld", (long)code] body:text];
        });
    }];
    [task resume];
    self.navigationItem.prompt = @"Đang kiểm tra…";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ self.navigationItem.prompt = nil; });
}

- (void)alert:(NSString *)title body:(NSString *)body {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                              message:body
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
