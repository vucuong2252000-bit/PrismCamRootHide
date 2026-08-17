#import "PCAppDelegate.h"
#import "PCViewController.h"

@implementation PCAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    PCViewController *controller = [PCViewController new];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:controller];
    [self.window makeKeyAndVisible];
    return YES;
}

@end

