#import "SBPrefsUI.h"
#import <AVFoundation/AVFoundation.h>
#import <notify.h>

static NSString *const kDomain = @"com.hthancder.siribridge";
static NSString *const kChangedNote = @"com.hthancder.siribridge/settingsChanged";

static UIColor *SBDynamic(UIColor *light, UIColor *dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
    }];
}

#pragma mark - Theme

@implementation SBTheme

+ (UIColor *)accent     { return SBDynamic([UIColor colorWithRed:0.36 green:0.29 blue:0.96 alpha:1.0],
                                           [UIColor colorWithRed:0.56 green:0.49 blue:1.00 alpha:1.0]); }
+ (UIColor *)accentSoft { return [[self accent] colorWithAlphaComponent:0.14]; }
+ (UIColor *)bg         { return SBDynamic([UIColor colorWithRed:0.949 green:0.949 blue:0.969 alpha:1.0],
                                           [UIColor colorWithRed:0.043 green:0.043 blue:0.055 alpha:1.0]); }
+ (UIColor *)card       { return SBDynamic([UIColor whiteColor],
                                           [UIColor colorWithRed:0.110 green:0.110 blue:0.129 alpha:1.0]); }
+ (UIColor *)cardAlt    { return SBDynamic([UIColor colorWithRed:0.949 green:0.949 blue:0.961 alpha:1.0],
                                           [UIColor colorWithRed:0.153 green:0.153 blue:0.176 alpha:1.0]); }
+ (UIColor *)sep        { return SBDynamic([UIColor colorWithWhite:0.0 alpha:0.07],
                                           [UIColor colorWithWhite:1.0 alpha:0.08]); }
+ (UIColor *)label      { return SBDynamic([UIColor blackColor], [UIColor whiteColor]); }
+ (UIColor *)secondaryLabel {
    return SBDynamic([UIColor colorWithWhite:0.42 alpha:1.0], [UIColor colorWithWhite:0.60 alpha:1.0]);
}
+ (UIColor *)success    { return [UIColor systemGreenColor]; }
+ (UIColor *)warning    { return [UIColor systemOrangeColor]; }

+ (UIFont *)titleFont:(CGFloat)size {
    UIFont *f = [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
    if (@available(iOS 13.0, *)) {
        UIFontDescriptor *d = [f.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
        if (d) return [UIFont fontWithDescriptor:d size:size];
    }
    return f;
}
+ (UIFont *)bodyFont:(CGFloat)size { return [UIFont systemFontOfSize:size weight:UIFontWeightRegular]; }
+ (UIFont *)monoFont:(CGFloat)size { return [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightRegular]; }

@end

#pragma mark - Store

@implementation SBSettingsStore {
    dispatch_source_t _debounce;
}

+ (instancetype)shared {
    static SBSettingsStore *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SBSettingsStore new]; });
    return s;
}

- (NSUserDefaults *)defaults {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:kDomain];
    return d ?: [NSUserDefaults standardUserDefaults];
}

- (id)objectForKey:(NSString *)key {
    return [[self defaults] objectForKey:key];
}

- (BOOL)boolForKey:(NSString *)key def:(BOOL)def {
    id v = [self objectForKey:key];
    return v ? [v boolValue] : def;
}

- (NSString *)stringForKey:(NSString *)key def:(NSString *)def {
    id v = [self objectForKey:key];
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
    return def ?: @"";
}

- (double)doubleForKey:(NSString *)key def:(double)def {
    id v = [self objectForKey:key];
    return v ? [v doubleValue] : def;
}

- (NSInteger)intForKey:(NSString *)key def:(NSInteger)def {
    id v = [self objectForKey:key];
    return v ? [v integerValue] : def;
}

- (void)setBool:(BOOL)value forKey:(NSString *)key   { [self write:@(value) forKey:key]; }
- (void)setDouble:(double)value forKey:(NSString *)key { [self write:@(value) forKey:key]; }
- (void)setInt:(NSInteger)value forKey:(NSString *)key { [self write:@(value) forKey:key]; }

- (void)setString:(NSString *)value forKey:(NSString *)key {
    [self write:value ?: @"" forKey:key];
}

- (void)write:(id)value forKey:(NSString *)key {
    if (!key.length) return;
    NSUserDefaults *d = [self defaults];
    [d setObject:value forKey:key];
    [d synchronize];
    [self scheduleNotify];
}

/// Gộp nhiều thay đổi liên tiếp (vd kéo slider) thành 1 notification.
- (void)scheduleNotify {
    if (_debounce) dispatch_source_cancel(_debounce);
    _debounce = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                       dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(_debounce, dispatch_time(DISPATCH_TIME_NOW, 250ull * NSEC_PER_MSEC),
                              600ull * NSEC_PER_SEC, 50ull * NSEC_PER_MSEC);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_debounce, ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        dispatch_source_cancel(self->_debounce);
        self->_debounce = nil;
        [self postChanged];
    });
    dispatch_resume(_debounce);
}

- (void)postChanged { notify_post(kChangedNote.UTF8String); }

@end

#pragma mark - Card

@implementation SBCardView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [SBTheme card];
        self.layer.cornerRadius = 14.0;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        self.layer.borderColor = [SBTheme sep].CGColor;

        _stack = [[UIStackView alloc] init];
        _stack.axis = UILayoutConstraintAxisVertical;
        _stack.spacing = 0;
        _stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_stack];
        [NSLayoutConstraint activateConstraints:@[
            [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (void)addArrangedSubview:(UIView *)view { [_stack addArrangedSubview:view]; }

- (void)addSeparator {
    UIView *line = [[UIView alloc] init];
    line.backgroundColor = [SBTheme sep];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    [_stack addArrangedSubview:line];
    [line.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
}

- (void)addPaddedView:(UIView *)view { [_stack addArrangedSubview:view]; }

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    self.layer.borderColor = [SBTheme sep].CGColor;
}

@end

#pragma mark - Row

@interface SBRowView () <UITextFieldDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, assign) SBRowKind kind;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UISwitch *toggle;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UISegmentedControl *segment;
@property (nonatomic, strong) UIButton *chevronButton;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, copy) NSString *defaultString;
@property (nonatomic, assign) BOOL defaultBool;
@property (nonatomic, assign) double defaultValue;
@property (nonatomic, assign) NSInteger defaultInt;
@property (nonatomic, assign) UIKeyboardType keyboard;
@property (nonatomic, assign) BOOL isSecret;
@property (nonatomic, copy, nullable) NSString *(^formatBlock)(double);
@property (nonatomic, copy, nullable) NSArray<NSDictionary *> *choices;
@property (nonatomic, copy, nullable) void (^actionBlock)(void);
@property (nonatomic, strong) UIStackView *rootStack;
@property (nonatomic, strong) UIStackView *customStack;
- (instancetype)initCustomStack;
@end

@implementation SBRowView

#pragma mark Build helpers

- (UILabel *)makeTitle:(NSString *)title {
    UILabel *l = [[UILabel alloc] init];
    l.text = title;
    l.font = [SBTheme bodyFont:16.0];
    l.textColor = [SBTheme label];
    l.numberOfLines = 1;
    l.adjustsFontSizeToFitWidth = YES;
    l.minimumScaleFactor = 0.8;
    return l;
}

- (UILabel *)makeSubtitle:(NSString *)subtitle {
    UILabel *l = [[UILabel alloc] init];
    l.text = subtitle;
    l.font = [SBTheme bodyFont:12.5];
    l.textColor = [SBTheme secondaryLabel];
    l.numberOfLines = 0;
    return l;
}

- (UIStackView *)textStackWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    UIStackView *v = [[UIStackView alloc] init];
    v.axis = UILayoutConstraintAxisVertical;
    v.spacing = 2.0;
    v.alignment = UIStackViewAlignmentFill;
    self.titleLabel = [self makeTitle:title];
    [v addArrangedSubview:self.titleLabel];
    if (subtitle.length) {
        self.subtitleLabel = [self makeSubtitle:subtitle];
        [v addArrangedSubview:self.subtitleLabel];
    }
    return v;
}

- (instancetype)initCommonWithKind:(SBRowKind)kind title:(NSString *)title subtitle:(NSString *)subtitle {
    if ((self = [super initWithFrame:CGRectZero])) {
        _kind = kind;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = UIColor.clearColor;

        UIStackView *root = [[UIStackView alloc] init];
        root.axis = UILayoutConstraintAxisHorizontal;
        root.alignment = UIStackViewAlignmentCenter;
        root.spacing = 12.0;
        root.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:root];
        [NSLayoutConstraint activateConstraints:@[
            [root.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16.0],
            [root.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
            [root.topAnchor constraintEqualToAnchor:self.topAnchor constant:12.0],
            [root.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12.0],
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:44.0],
        ]];

        UIStackView *text = [self textStackWithTitle:title subtitle:subtitle];
        [text setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        [root addArrangedSubview:text];
        [root addArrangedSubview:[[UIView alloc] init]];   // spacer co giãn
        root.arrangedSubviews.lastObject.translatesAutoresizingMaskIntoConstraints = NO;
        [(UIView *)root.arrangedSubviews.lastObject setContentHuggingPriority:0
                                                              forAxis:UILayoutConstraintAxisHorizontal];
        self.rootStack = root;
    }
    return self;
}

- (void)addTrailingView:(UIView *)view {
    [view setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [view setContentCompressionResistancePriority:UILayoutPriorityRequired
                                          forAxis:UILayoutConstraintAxisHorizontal];
    [self.rootStack addArrangedSubview:view];
}

#pragma mark Switch

+ (instancetype)switchRow:(NSString *)title
                 subtitle:(NSString *)subtitle
                      key:(NSString *)key
                      def:(BOOL)def {
    SBRowView *row = [[self alloc] initCommonWithKind:SBRowKindSwitch title:title subtitle:subtitle];
    row.key = key;
    row.defaultBool = def;

    UISwitch *sw = [[UISwitch alloc] init];
    sw.transform = CGAffineTransformMakeScale(0.86, 0.86);
    sw.onTintColor = [SBTheme accent];
    [sw addTarget:row action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    row.toggle = sw;
    [row addTrailingView:sw];
    [row refreshValue];
    return row;
}

- (void)toggleChanged:(UISwitch *)sw {
    [SBSettingsStore.shared setBool:sw.isOn forKey:self.key];
    if (self.onChange) self.onChange(@(sw.isOn));
}

#pragma mark Text

+ (instancetype)textRow:(NSString *)title
               subtitle:(NSString *)subtitle
                    key:(NSString *)key
                    def:(NSString *)def
            placeholder:(NSString *)placeholder
               keyboard:(UIKeyboardType)keyboard
               isSecret:(BOOL)isSecret {
    SBRowView *row = [[self alloc] initCommonWithKind:SBRowKindText title:title subtitle:subtitle];
    row.key = key;
    row.defaultString = def ?: @"";
    row.keyboard = keyboard;
    row.isSecret = isSecret;

    UITextField *tf = [[UITextField alloc] init];
    tf.textAlignment = NSTextAlignmentRight;
    tf.font = [SBTheme bodyFont:15.5];
    tf.textColor = [SBTheme secondaryLabel];
    tf.placeholder = placeholder;
    tf.keyboardType = keyboard;
    tf.secureTextEntry = isSecret;
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    tf.returnKeyType = UIReturnKeyDone;
    tf.delegate = row;
    tf.translatesAutoresizingMaskIntoConstraints = NO;
    [tf.widthAnchor constraintGreaterThanOrEqualToConstant:150.0].active = YES;
    [tf addTarget:row action:@selector(textChanged:) forControlEvents:UIControlEventEditingChanged];
    [tf addTarget:row action:@selector(textCommitted:) forControlEvents:UIControlEventEditingDidEnd];
    row.field = tf;
    [row addTrailingView:tf];
    [row refreshValue];
    return row;
}

+ (instancetype)longTextRow:(NSString *)title
                   subtitle:(NSString *)subtitle
                        key:(NSString *)key
                        def:(NSString *)def
                placeholder:(NSString *)placeholder {
    SBRowView *row = [[self alloc] initCommonWithKind:SBRowKindLongText title:title subtitle:subtitle];
    row.key = key;
    row.defaultString = def ?: @"";

    UILabel *preview = [[UILabel alloc] init];
    preview.font = [SBTheme monoFont:12.0];
    preview.textColor = [SBTheme secondaryLabel];
    preview.numberOfLines = 1;
    preview.lineBreakMode = NSLineBreakByTruncatingMiddle;
    preview.textAlignment = NSTextAlignmentRight;
    [preview.widthAnchor constraintLessThanOrEqualToConstant:170.0].active = YES;
    row.valueLabel = preview;

    UIImageView *chev = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"chevron.right" withConfiguration:
            [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold]]];
    chev.tintColor = [SBTheme secondaryLabel];
    chev.alpha = 0.5;
    chev.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *trail = [[UIStackView alloc] initWithArrangedSubviews:@[preview, chev]];
    trail.axis = UILayoutConstraintAxisHorizontal;
    trail.spacing = 6.0;
    trail.alignment = UIStackViewAlignmentCenter;
    [row addTrailingView:trail];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:row
                                                                         action:@selector(openLongTextEditor)];
    [row addGestureRecognizer:tap];
    [row refreshValue];
    return row;
}

- (void)openLongTextEditor {
    SBTextEditorController *ed = [[SBTextEditorController alloc] initWithTitle:(self.titleLabel.text ?: @"")];
    ed.text = [SBSettingsStore.shared stringForKey:self.key def:self.defaultString];
    ed.monospaced = (self.keyboard == UIKeyboardTypeDefault);
    __weak typeof(self) weakSelf = self;
    ed.onDone = ^(NSString *text) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [SBSettingsStore.shared setString:text forKey:self.key];
        [self refreshValue];
        if (self.onChange) self.onChange(text);
    };
    UIViewController *host = [self sb_hostController];
    if (!host) return;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:ed];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [host presentViewController:nav animated:YES completion:nil];
}

- (UIViewController *)sb_hostController {
    UIResponder *r = self;
    while (r && ![r isKindOfClass:[UIViewController class]]) r = r.nextResponder;
    return (UIViewController *)r;
}

- (void)textChanged:(UITextField *)tf {
    [SBSettingsStore.shared setString:tf.text forKey:self.key];
}

- (void)textCommitted:(UITextField *)tf {
    [SBSettingsStore.shared setString:tf.text forKey:self.key];
    if (self.onChange) self.onChange(tf.text ?: @"");
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    [tf resignFirstResponder];
    return YES;
}

#pragma mark Slider

+ (instancetype)sliderRow:(NSString *)title
                     key:(NSString *)key
                     def:(double)def
                     min:(double)mn
                     max:(double)mx
                  format:(NSString *(^)(double))format {
    SBRowView *row = [[self alloc] initCommonWithKind:SBRowKindSlider title:title subtitle:nil];
    row.key = key;
    row.defaultValue = def;
    row.formatBlock = format;

    UILabel *value = [[UILabel alloc] init];
    value.font = [SBTheme monoFont:13.0];
    value.textColor = [SBTheme accent];
    value.textAlignment = NSTextAlignmentRight;
    value.translatesAutoresizingMaskIntoConstraints = NO;
    [value.widthAnchor constraintEqualToConstant:56.0].active = YES;
    row.valueLabel = value;

    UISlider *sl = [[UISlider alloc] init];
    sl.minimumValue = mn;
    sl.maximumValue = mx;
    sl.minimumTrackTintColor = [SBTheme accent];
    sl.translatesAutoresizingMaskIntoConstraints = NO;
    [sl.widthAnchor constraintGreaterThanOrEqualToConstant:130.0].active = YES;
    [sl addTarget:row action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    row.slider = sl;

    UIStackView *trail = [[UIStackView alloc] initWithArrangedSubviews:@[value, sl]];
    trail.axis = UILayoutConstraintAxisHorizontal;
    trail.spacing = 10.0;
    trail.alignment = UIStackViewAlignmentCenter;
    [row addTrailingView:trail];
    [row refreshValue];
    return row;
}

- (void)sliderChanged:(UISlider *)sl {
    double v = sl.value;
    // làm tròn nhẹ để không spam ghi
    v = round(v * 100.0) / 100.0;
    [SBSettingsStore.shared setDouble:v forKey:self.key];
    self.valueLabel.text = self.formatBlock ? self.formatBlock(v)
                                            : [NSString stringWithFormat:@"%.2f", v];
    if (self.onChange) self.onChange(@(v));
}

#pragma mark Segment

+ (instancetype)segmentRow:(NSString *)title
                       key:(NSString *)key
                       def:(NSInteger)def
                    titles:(NSArray<NSString *> *)titles {
    SBRowView *row = [[SBRowView alloc] initCustomStack];
    row.kind = SBRowKindSegment;
    row.key = key;
    row.defaultInt = def;

    UILabel *lbl = [row makeTitle:title];
    lbl.font = [SBTheme titleFont:13.0];
    lbl.textColor = [SBTheme secondaryLabel];
    lbl.text = [title uppercaseString];

    UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:titles];
    seg.selectedSegmentTintColor = [SBTheme accent];
    seg.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(iOS 13.0, *)) {
        [seg setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor,
                                      NSFontAttributeName: [SBTheme bodyFont:13.0]}
                           forState:UIControlStateSelected];
        [seg setTitleTextAttributes:@{NSForegroundColorAttributeName: [SBTheme label],
                                      NSFontAttributeName: [SBTheme bodyFont:13.0]}
                           forState:UIControlStateNormal];
    }
    [seg addTarget:row action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    row.segment = seg;

    [row.customStack addArrangedSubview:lbl];
    [row.customStack addArrangedSubview:seg];
    [row refreshValue];
    return row;
}

- (instancetype)initCustomStack {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        _customStack = [[UIStackView alloc] init];
        _customStack.axis = UILayoutConstraintAxisVertical;
        _customStack.spacing = 8.0;
        _customStack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_customStack];
        [NSLayoutConstraint activateConstraints:@[
            [_customStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16.0],
            [_customStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
            [_customStack.topAnchor constraintEqualToAnchor:self.topAnchor constant:11.0],
            [_customStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12.0],
        ]];
    }
    return self;
}

- (void)segmentChanged:(UISegmentedControl *)seg {
    NSInteger v = seg.selectedSegmentIndex;
    [SBSettingsStore.shared setInt:v forKey:self.key];
    if (self.onChange) self.onChange(@(v));
}

#pragma mark Choice

+ (instancetype)choiceRow:(NSString *)title
                 subtitle:(NSString *)subtitle
                      key:(NSString *)key
                      def:(NSString *)def
                  choices:(NSArray<NSDictionary *> *)choices {
    SBRowView *row = [[self alloc] initCommonWithKind:SBRowKindChoice title:title subtitle:subtitle];
    row.key = key;
    row.defaultString = def ?: @"";
    row.choices = choices;

    UILabel *value = [[UILabel alloc] init];
    value.font = [SBTheme bodyFont:15.0];
    value.textColor = [SBTheme secondaryLabel];
    value.textAlignment = NSTextAlignmentRight;
    value.numberOfLines = 1;
    value.lineBreakMode = NSLineBreakByTruncatingTail;
    [value.widthAnchor constraintLessThanOrEqualToConstant:180.0].active = YES;
    row.valueLabel = value;

    UIImageView *chev = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"chevron.right" withConfiguration:
            [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold]]];
    chev.tintColor = [SBTheme secondaryLabel];
    chev.alpha = 0.5;

    UIStackView *trail = [[UIStackView alloc] initWithArrangedSubviews:@[value, chev]];
    trail.axis = UILayoutConstraintAxisHorizontal;
    trail.spacing = 6.0;
    trail.alignment = UIStackViewAlignmentCenter;
    [row addTrailingView:trail];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:row
                                                                         action:@selector(openChoices)];
    [row addGestureRecognizer:tap];
    [row refreshValue];
    return row;
}

- (void)openChoices {
    __weak typeof(self) weakSelf = self;
    SBPickerController *picker = [[SBPickerController alloc] initWithTitle:self.titleLabel.text ?: @""
                                                                   choices:self.choices
                                                                selectedID:[SBSettingsStore.shared stringForKey:self.key def:self.defaultString]
                                                                  onSelect:^(NSString *identifier) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [SBSettingsStore.shared setString:identifier forKey:self.key];
        [self refreshValue];
        if (self.onChange) self.onChange(identifier);
    }];
    UIViewController *host = [self sb_hostController];
    if (!host) return;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [host presentViewController:nav animated:YES completion:nil];
}

#pragma mark Action / Info

+ (instancetype)actionRow:(NSString *)title
                 subtitle:(NSString *)subtitle
                    color:(UIColor *)color
                   action:(void (^)(void))action {
    SBRowView *row = [[self alloc] initCommonWithKind:SBRowKindAction title:title subtitle:subtitle];
    row.actionBlock = action;
    row.titleLabel.textColor = color ?: [SBTheme accent];
    row.titleLabel.font = [SBTheme bodyFont:16.0];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:row
                                                                         action:@selector(runAction)];
    [row addGestureRecognizer:tap];
    [row addHighlightTouch];
    return row;
}

- (void)runAction { if (self.actionBlock) self.actionBlock(); }

+ (instancetype)infoRow:(NSString *)title subtitle:(NSString *)subtitle {
    SBRowView *row = [[self alloc] initCommonWithKind:SBRowKindInfo title:title subtitle:subtitle];
    row.titleLabel.font = [SBTheme bodyFont:14.0];
    row.titleLabel.textColor = [SBTheme secondaryLabel];
    return row;
}

- (void)addHighlightTouch {
    self.userInteractionEnabled = YES;
    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                        action:@selector(pressState:)];
    press.minimumPressDuration = 0.01;
    [self addGestureRecognizer:press];
}

- (void)pressState:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        self.backgroundColor = [SBTheme cardAlt];
    } else if (g.state == UIGestureRecognizerStateEnded ||
               g.state == UIGestureRecognizerStateCancelled) {
        self.backgroundColor = UIColor.clearColor;
    }
}

#pragma mark Refresh

- (void)refreshValue {
    SBSettingsStore *store = SBSettingsStore.shared;
    switch (self.kind) {
        case SBRowKindSwitch:
            self.toggle.on = [store boolForKey:self.key def:self.defaultBool];
            break;
        case SBRowKindText: {
            NSString *v = [store stringForKey:self.key def:self.defaultString];
            if (self.field.isFirstResponder) break;
            self.field.text = v.length ? v : @"";
            break;
        }
        case SBRowKindLongText: {
            NSString *v = [store stringForKey:self.key def:self.defaultString];
            self.valueLabel.text = v.length ? [self compactPreview:v] : @"Trống";
            self.valueLabel.textColor = v.length ? [SBTheme secondaryLabel] : [SBTheme secondaryLabel];
            break;
        }
        case SBRowKindSlider: {
            double v = [store doubleForKey:self.key def:self.defaultValue];
            self.slider.value = v;
            self.valueLabel.text = self.formatBlock ? self.formatBlock(v)
                                                    : [NSString stringWithFormat:@"%.2f", v];
            break;
        }
        case SBRowKindSegment: {
            NSInteger v = [store intForKey:self.key def:self.defaultInt];
            if (v >= 0 && v < (NSInteger)self.segment.numberOfSegments) self.segment.selectedSegmentIndex = v;
            break;
        }
        case SBRowKindChoice: {
            NSString *v = [store stringForKey:self.key def:self.defaultString];
            self.valueLabel.text = [self titleForValue:v];
            break;
        }
        default:
            break;
    }
}

- (NSString *)compactPreview:(NSString *)text {
    NSString *one = [text stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    if (one.length <= 34) return one;
    return [NSString stringWithFormat:@"…%@", [one substringFromIndex:one.length - 32]];
}

- (NSString *)titleForValue:(NSString *)value {
    for (NSDictionary *c in self.choices) {
        NSString *v = [NSString stringWithFormat:@"%@", c[@"value"]];
        if ([v isEqualToString:value ?: @""]) return c[@"title"] ?: v;
    }
    return value.length ? value : @"Mặc định";
}

- (void)setEnabled:(BOOL)enabled {
    self.alpha = enabled ? 1.0 : 0.45;
    self.userInteractionEnabled = enabled;
}

@end

#pragma mark - Editor

@interface SBTextEditorController () <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *hintLabel;
@end

@implementation SBTextEditorController

- (instancetype)initWithTitle:(NSString *)title {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        self.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SBTheme bg];

    self.textView = [[UITextView alloc] init];
    self.textView.delegate = self;
    self.textView.text = self.text ?: @"";
    self.textView.font = self.monospaced ? [SBTheme monoFont:13.0] : [SBTheme bodyFont:16.0];
    self.textView.backgroundColor = [SBTheme card];
    self.textView.textColor = [SBTheme label];
    self.textView.layer.cornerRadius = 12.0;
    self.textView.layer.cornerCurve = kCACornerCurveContinuous;
    self.textView.textContainerInset = UIEdgeInsetsMake(12, 10, 12, 10);
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    if (!self.monospaced) self.textView.keyboardType = UIKeyboardTypeDefault;
    [self.view addSubview:self.textView];

    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.text = self.placeholder ?: self.hint;
    self.hintLabel.font = [SBTheme bodyFont:12.0];
    self.hintLabel.textColor = [SBTheme secondaryLabel];
    self.hintLabel.numberOfLines = 0;
    self.hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.hintLabel];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.textView.topAnchor constraintEqualToAnchor:safe.topAnchor constant:16.0],
        [self.textView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16.0],
        [self.textView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16.0],
        [self.textView.bottomAnchor constraintEqualToAnchor:self.hintLabel.topAnchor constant:-10.0],
        [self.hintLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20.0],
        [self.hintLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20.0],
        [self.hintLabel.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16.0],
    ]];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(done)];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(cancel)];
    self.navigationController.navigationBar.tintColor = [SBTheme accent];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.textView becomeFirstResponder];
}

- (void)done {
    self.text = self.textView.text ?: @"";
    if (self.onDone) self.onDone(self.text);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }

@end

#pragma mark - Picker

@interface SBPickerController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSArray<NSDictionary *> *choices;
@property (nonatomic, copy) NSString *selectedID;
@property (nonatomic, copy) void (^onSelect)(NSString *identifier);
@property (nonatomic, strong) UITableView *table;
@end

@implementation SBPickerController

- (instancetype)initWithTitle:(NSString *)title
                      choices:(NSArray<NSDictionary *> *)choices
                   selectedID:(NSString *)selectedID
                     onSelect:(void (^)(NSString *))onSelect {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        self.title = title;
        _choices = [choices copy];
        _selectedID = [selectedID copy];
        _onSelect = [onSelect copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [SBTheme bg];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.backgroundColor = [SBTheme bg];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];
    [NSLayoutConstraint activateConstraints:@[
        [self.table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(close)];
    self.navigationController.navigationBar.tintColor = [SBTheme accent];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.choices.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ident = @"choice";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                             reuseIdentifier:ident];
    NSDictionary *c = self.choices[(NSUInteger)indexPath.row];
    NSString *value = [NSString stringWithFormat:@"%@", c[@"value"]];
    cell.textLabel.text = c[@"title"] ?: value;
    cell.textLabel.font = [SBTheme bodyFont:16.0];
    cell.detailTextLabel.text = c[@"detail"];
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.font = [SBTheme bodyFont:12.0];
    cell.backgroundColor = [SBTheme card];
    cell.textLabel.textColor = [SBTheme label];
    cell.detailTextLabel.textColor = [SBTheme secondaryLabel];
    cell.accessoryType = [value isEqualToString:self.selectedID ?: @""] ? UITableViewCellAccessoryCheckmark
                                                                       : UITableViewCellAccessoryNone;
    cell.tintColor = [SBTheme accent];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    UIView *sel = [[UIView alloc] init];
    sel.backgroundColor = [SBTheme accentSoft];
    cell.selectedBackgroundView = sel;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *c = self.choices[(NSUInteger)indexPath.row];
    NSString *value = [NSString stringWithFormat:@"%@", c[@"value"]];
    self.selectedID = value;
    [tableView reloadData];
    if (self.onSelect) self.onSelect(value);
}

@end
