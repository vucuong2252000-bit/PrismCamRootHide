#import <Foundation/Foundation.h>
#import "PCFrameDaemon.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        PCFrameDaemon *daemon = [PCFrameDaemon new];
        [daemon start];
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}

