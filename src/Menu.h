#pragma once
#import <UIKit/UIKit.h>

@interface XenoMenu : UIView
@property (nonatomic, assign) BOOL collapsed;
@property (nonatomic, weak) CADisplayLink *link;
- (void)teardown;
@end
