#import <UIKit/UIKit.h>
#import "../shared/PCShared.h"

@interface PCSafetyIndicator : NSObject
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) NSTimer *timer;
@end

@implementation PCSafetyIndicator

+ (instancetype)sharedIndicator {
    static PCSafetyIndicator *indicator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ indicator = [PCSafetyIndicator new]; });
    return indicator;
}

- (void)start {
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                 target:self
                                               selector:@selector(refresh)
                                               userInfo:nil
                                                repeats:YES];
    [self refresh];
}

- (void)refresh {
    NSDictionary *configuration = PCLoadConfiguration();
    BOOL visible = [configuration[@"enabled"] boolValue] &&
                   [configuration[@"armedUntil"] doubleValue] > NSDate.date.timeIntervalSince1970;
    if (!visible) {
        self.window.hidden = YES;
        return;
    }
    if (!self.window) {
        CGRect frame = CGRectMake(0, 46, UIScreen.mainScreen.bounds.size.width, 30);
        self.window = [[UIWindow alloc] initWithFrame:frame];
        self.window.windowLevel = UIWindowLevelAlert + 1000;
        self.window.userInteractionEnabled = NO;
        self.window.backgroundColor = UIColor.clearColor;
        UILabel *label = [[UILabel alloc] initWithFrame:self.window.bounds];
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        label.backgroundColor = [UIColor colorWithRed:0.88 green:0.02 blue:0.42 alpha:0.92];
        label.textColor = UIColor.whiteColor;
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont boldSystemFontOfSize:13];
        label.text = @"PRISMCAM • VIRTUAL CAMERA";
        [self.window addSubview:label];
    }
    self.window.hidden = NO;
}

@end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[PCSafetyIndicator sharedIndicator] start];
    });
}

