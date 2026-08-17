#import "PCViewController.h"
#import "../shared/PCShared.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface PCViewController ()
@property(nonatomic, strong) UISwitch *enabledSwitch;
@property(nonatomic, strong) UISwitch *colorSwitch;
@property(nonatomic, strong) UISegmentedControl *sourceControl;
@property(nonatomic, strong) UISlider *redSlider;
@property(nonatomic, strong) UISlider *greenSlider;
@property(nonatomic, strong) UISlider *blueSlider;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UILabel *tokenLabel;
@property(nonatomic, strong) UIButton *pickerButton;
@property(nonatomic, strong) NSMutableDictionary *configuration;
@property(nonatomic, strong) NSTimer *statusTimer;
@end

@implementation PCViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"PrismCam";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    PCEnsureSharedDirectory(nil);
    self.configuration = PCLoadConfiguration();
    if ([self.configuration[@"pairingToken"] length] < 12) {
        self.configuration[@"pairingToken"] = [NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
        PCSaveConfiguration(self.configuration, nil);
    }
    [self buildInterface];
    [self refreshControls];
    self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                       target:self
                                                     selector:@selector(refreshStatus)
                                                     userInfo:nil
                                                      repeats:YES];
}

- (void)dealloc {
    [self.statusTimer invalidate];
}

- (UILabel *)label:(NSString *)text {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    return label;
}

- (void)buildInterface {
    UIScrollView *scroll = [UIScrollView new];
    UIStackView *stack = [[UIStackView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.layoutMargins = UIEdgeInsetsMake(20, 20, 30, 20);
    stack.layoutMarginsRelativeArrangement = YES;
    [self.view addSubview:scroll];
    [scroll addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
    ]];

    UILabel *warning = [self label:@"Camera ảo luôn có vạch màu và banner hiển thị. Khi bật, quyền kích hoạt tự hết hạn sau 4 giờ."];
    warning.numberOfLines = 0;
    warning.textColor = UIColor.secondaryLabelColor;
    [stack addArrangedSubview:warning];

    UIStackView *enabledRow = [self rowWithLabel:@"Bật camera ảo"];
    self.enabledSwitch = [UISwitch new];
    [self.enabledSwitch addTarget:self action:@selector(controlChanged:) forControlEvents:UIControlEventValueChanged];
    [enabledRow addArrangedSubview:self.enabledSwitch];
    [stack addArrangedSubview:enabledRow];

    self.sourceControl = [[UISegmentedControl alloc] initWithItems:@[@"Ảnh", @"Video", @"OBS"]];
    [self.sourceControl addTarget:self action:@selector(controlChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:[self label:@"Nguồn hình"]];
    [stack addArrangedSubview:self.sourceControl];

    self.pickerButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.pickerButton setTitle:@"Chọn ảnh hoặc video" forState:UIControlStateNormal];
    self.pickerButton.configuration = [UIButtonConfiguration filledButtonConfiguration];
    [self.pickerButton addTarget:self action:@selector(selectAsset) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:self.pickerButton];

    UIStackView *colorRow = [self rowWithLabel:@"Đồng bộ màu tự động"];
    self.colorSwitch = [UISwitch new];
    [self.colorSwitch addTarget:self action:@selector(controlChanged:) forControlEvents:UIControlEventValueChanged];
    [colorRow addArrangedSubview:self.colorSwitch];
    [stack addArrangedSubview:colorRow];

    self.redSlider = [self addSliderToStack:stack title:@"Gain đỏ"];
    self.greenSlider = [self addSliderToStack:stack title:@"Gain xanh lá"];
    self.blueSlider = [self addSliderToStack:stack title:@"Gain xanh dương"];

    self.tokenLabel = [self label:@""];
    self.tokenLabel.numberOfLines = 0;
    self.tokenLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    [stack addArrangedSubview:[self label:@"Mã ghép nối OBS"]];
    [stack addArrangedSubview:self.tokenLabel];

    UIButton *newToken = [UIButton buttonWithType:UIButtonTypeSystem];
    [newToken setTitle:@"Tạo mã ghép nối mới" forState:UIControlStateNormal];
    [newToken addTarget:self action:@selector(regenerateToken) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:newToken];

    self.statusLabel = [self label:@"Đang đọc trạng thái…"];
    self.statusLabel.numberOfLines = 0;
    [stack addArrangedSubview:self.statusLabel];
}

- (UIStackView *)rowWithLabel:(NSString *)text {
    UIStackView *row = [UIStackView new];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.distribution = UIStackViewDistributionEqualSpacing;
    [row addArrangedSubview:[self label:text]];
    return row;
}

- (UISlider *)addSliderToStack:(UIStackView *)stack title:(NSString *)title {
    UISlider *slider = [UISlider new];
    slider.minimumValue = 0.65;
    slider.maximumValue = 1.45;
    [slider addTarget:self action:@selector(controlChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:[self label:title]];
    [stack addArrangedSubview:slider];
    return slider;
}

- (void)refreshControls {
    self.enabledSwitch.on = [self.configuration[@"enabled"] boolValue];
    self.colorSwitch.on = [self.configuration[@"colorSyncEnabled"] boolValue];
    NSDictionary *indexes = @{@"image": @0, @"video": @1, @"obs": @2};
    self.sourceControl.selectedSegmentIndex = [indexes[self.configuration[@"sourceMode"]] integerValue];
    self.redSlider.value = [self.configuration[@"redGain"] floatValue];
    self.greenSlider.value = [self.configuration[@"greenGain"] floatValue];
    self.blueSlider.value = [self.configuration[@"blueGain"] floatValue];
    self.tokenLabel.text = self.configuration[@"pairingToken"];
    self.pickerButton.hidden = self.sourceControl.selectedSegmentIndex == 2;
}

- (void)controlChanged:(id)sender {
    NSArray *modes = @[@"image", @"video", @"obs"];
    self.configuration[@"enabled"] = @(self.enabledSwitch.on);
    self.configuration[@"armedUntil"] = self.enabledSwitch.on ? @([NSDate.date timeIntervalSince1970] + 4 * 60 * 60) : @0;
    self.configuration[@"sourceMode"] = modes[MAX(0, self.sourceControl.selectedSegmentIndex)];
    self.configuration[@"colorSyncEnabled"] = @(self.colorSwitch.on);
    self.configuration[@"redGain"] = @(self.redSlider.value);
    self.configuration[@"greenGain"] = @(self.greenSlider.value);
    self.configuration[@"blueGain"] = @(self.blueSlider.value);
    PCSaveConfiguration(self.configuration, nil);
    [self refreshControls];
}

- (void)selectAsset {
    BOOL video = self.sourceControl.selectedSegmentIndex == 1;
    UTType *type = video ? UTTypeMovie : UTTypeImage;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[type] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *source = urls.firstObject;
    if (!source) return;
    BOOL video = self.sourceControl.selectedSegmentIndex == 1;
    NSString *extension = source.pathExtension.length ? source.pathExtension : (video ? @"mov" : @"jpg");
    NSString *name = [NSString stringWithFormat:@"SourceAsset.%@", extension];
    NSString *destination = [PCSharedDirectory() stringByAppendingPathComponent:name];
    NSFileManager *manager = NSFileManager.defaultManager;
    for (NSString *file in [manager contentsOfDirectoryAtPath:PCSharedDirectory() error:nil]) {
        if ([file hasPrefix:@"SourceAsset."]) {
            [manager removeItemAtPath:[PCSharedDirectory() stringByAppendingPathComponent:file] error:nil];
        }
    }
    NSError *error = nil;
    [manager copyItemAtPath:source.path toPath:destination error:&error];
    if (error) {
        [self showMessage:error.localizedDescription];
        return;
    }
    self.configuration[@"assetPath"] = destination;
    self.configuration[@"sourceMode"] = video ? @"video" : @"image";
    PCSaveConfiguration(self.configuration, nil);
    [self showMessage:@"Đã cập nhật nguồn hình."];
}

- (void)regenerateToken {
    self.configuration[@"pairingToken"] = [NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""];
    PCSaveConfiguration(self.configuration, nil);
    [self refreshControls];
}

- (void)refreshStatus {
    NSDictionary *daemon = [NSDictionary dictionaryWithContentsOfFile:PCDaemonStatusPath()] ?: @{};
    NSDictionary *camera = [NSDictionary dictionaryWithContentsOfFile:PCCameraStatusPath()] ?: @{};
    NSString *daemonText = daemon[@"message"] ?: @"Daemon chưa báo trạng thái";
    NSString *cameraText = camera[@"message"] ?: @"Camera tweak chưa được nạp";
    self.statusLabel.text = [NSString stringWithFormat:@"Daemon: %@\nCamera: %@", daemonText, cameraText];
}

- (void)showMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"PrismCam"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

