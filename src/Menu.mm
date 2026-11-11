#import "Menu.h"
#import "Core.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kPanelW = 268.f;
static const CGFloat kRowH   = 34.f;
static const CGFloat kHeadH  = 46.f;

@implementation XenoMenu {
    CGPoint _origin;
    BOOL    _dragging;
    CGPoint _dragStart;
    CGRect  _rect;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.multipleTouchEnabled = NO;
    _origin = CGPointMake(18, gCfg.insetTop + 24);
    [self layoutRect];
    CALayer* glow = [CALayer layer];
    glow.backgroundColor = [UIColor colorWithWhite:1 alpha:0.05].CGColor;
    glow.cornerRadius = 16;
    glow.shadowColor = UIColor.whiteColor.CGColor;
    glow.shadowRadius = 20;
    glow.shadowOpacity = 0.28;
    glow.shadowOffset = CGSizeZero;
    glow.name = @"glow";
    [self.layer addSublayer:glow];
    return self;
}

- (void)layoutRect {
    _rect = CGRectMake(_origin.x, _origin.y, kPanelW, kHeadH + kRowH * T_COUNT + 14);
    CALayer* glow = [self.layer valueForKey:@"glow"] ?: self.layer.sublayers.firstObject;
    glow.frame = CGRectInset(_rect, -10, -10);
    glow.cornerRadius = 16;
}

- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent*)e {
    return !self.collapsed && CGRectContainsPoint(_rect, p);
}

- (UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e {
    return [self pointInside:p withEvent:e] ? self : nil;
}

// ---- drag by header ----
- (void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event {
    CGPoint p = [touches.anyObject locationInView:self];
    CGRect head = CGRectMake(_rect.origin.x, _rect.origin.y, kPanelW, kHeadH);
    if (CGRectContainsPoint(head, p)) {
        _dragging = YES;
        _dragStart = CGPointMake(p.x - _origin.x, p.y - _origin.y);
        return;
    }
    for (int i = 0; i < T_COUNT; i++) {
        if (CGRectContainsPoint([self rectForRow:i], p)) { xenoSetToggle(i); [self setNeedsDisplay]; return; }
    }
    if (CGRectContainsPoint([self rectForStepper:T_COUNT - 2 minus:YES], p)) { xenoStep(T_COUNT - 2, -1); [self setNeedsDisplay]; return; }
    if (CGRectContainsPoint([self rectForStepper:T_COUNT - 2 minus:NO],  p)) { xenoStep(T_COUNT - 2, +1); [self setNeedsDisplay]; return; }
    if (CGRectContainsPoint([self rectForStepper:T_COUNT - 1 minus:YES], p)) { xenoStep(T_COUNT - 1, -1); [self setNeedsDisplay]; return; }
    if (CGRectContainsPoint([self rectForStepper:T_COUNT - 1 minus:NO],  p)) { xenoStep(T_COUNT - 1, +1); [self setNeedsDisplay]; return; }
}

- (void)touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event {
    if (!_dragging) return;
    CGPoint p = [touches.anyObject locationInView:self];
    _origin = CGPointMake(p.x - _dragStart.x, p.y - _dragStart.y);
    [self layoutRect];
    [self setNeedsDisplay];
}

- (void)touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event { _dragging = NO; }
- (void)touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event { _dragging = NO; }

- (CGRect)rectForRow:(int)i {
    return CGRectMake(_rect.origin.x, _rect.origin.y + kHeadH + kRowH * i, kPanelW, kRowH);
}

- (CGRect)rectForStepper:(int)i minus:(BOOL)minus {
    CGFloat y = _rect.origin.y + kHeadH + kRowH * i;
    return CGRectMake(_rect.origin.x + kPanelW - (minus ? 84 : 44), y + 7, 30, 20);
}

static NSString* const kLabels[T_COUNT] = {
    @"Aimbot", @"Soft Aim", @"No Recoil", @"No Spread",
    @"Fast Reload", @"Unlimited Ammo", @"Fly", @"Noclip", @"FOV Ring"
};

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();

    UIBezierPath* panel = [UIBezierPath bezierPathWithRoundedRect:_rect cornerRadius:14];
    CGContextSetFillColorWithColor(c, [UIColor colorWithWhite:0 alpha:0.94].CGColor);
    [panel fill];
    CGContextSetStrokeColorWithColor(c, [UIColor colorWithWhite:1 alpha:0.22].CGColor);
    CGContextSetLineWidth(c, 0.75);
    [panel stroke];

    // header
    NSDictionary* headAttr = @{ NSFontAttributeName: [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightSemibold],
                                NSForegroundColorAttributeName: UIColor.whiteColor };
    [@"XENO" drawAtPoint:CGPointMake(_rect.origin.x + 14, _rect.origin.y + 13) withAttributes:headAttr];

    NSDictionary* subAttr = @{ NSFontAttributeName: [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular],
                               NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.45] };
    NSString* sub;
    switch (gCfg.status) {
        case S_LIVE:      sub = @"live"; break;
        case S_NO_MATCH:  sub = @"no match"; break;
        case S_NO_MODULE: sub = @"no UnityFramework"; break;
        case S_UUID_BAD:  sub = [NSString stringWithFormat:@"uuid mismatch %s", gUuidActual]; break;
        default:          sub = @"booting"; break;
    }
    [sub drawAtPoint:CGPointMake(_rect.origin.x + 14, _rect.origin.y + 28) withAttributes:subAttr];

    NSDictionary* onAttr  = @{ NSFontAttributeName: [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular],
                               NSForegroundColorAttributeName: UIColor.whiteColor };
    NSDictionary* offAttr = @{ NSFontAttributeName: [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular],
                               NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.42] };
    NSDictionary* valAttr = @{ NSFontAttributeName: [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular],
                               NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.7] };

    for (int i = 0; i < T_COUNT; i++) {
        CGFloat y = _rect.origin.y + kHeadH + kRowH * i;
        if (i == T_COUNT - 2 || i == T_COUNT - 1) {
            NSString* label = i == T_COUNT - 2 ? @"Smooth" : @"FOV";
            [label drawAtPoint:CGPointMake(_rect.origin.x + 14, y + 9) withAttributes:offAttr];
            float v = i == T_COUNT - 2 ? gCfg.smooth : gCfg.fovDeg;
            NSString* s = i == T_COUNT - 2
                ? [NSString stringWithFormat:@"%.2f", v]
                : [NSString stringWithFormat:@"%.0f", v];
            [s drawAtPoint:CGPointMake(_rect.origin.x + kPanelW - 132, y + 9) withAttributes:valAttr];
            for (int k = 0; k < 2; k++) {
                CGRect r = [self rectForStepper:i minus:(k == 0)];
                CGContextSetFillColorWithColor(c, [UIColor colorWithWhite:1 alpha:0.1].CGColor);
                [[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:6] fill];
                NSString* g = k == 0 ? @"−" : @"+";
                [g drawAtPoint:CGPointMake(r.origin.x + 10, r.origin.y + 2) withAttributes:offAttr];
            }
            continue;
        }

        if (i == T_COUNT - 3) {   // divider before steppers
            CGContextSetStrokeColorWithColor(c, [UIColor colorWithWhite:1 alpha:0.12].CGColor);
            CGContextSetLineWidth(c, 0.5);
            CGContextMoveToPoint(c, _rect.origin.x + 14, y + 1);
            CGContextAddLineToPoint(c, _rect.origin.x + kPanelW - 14, y + 1);
            CGContextStrokePath(c);
        }

        bool on = gCfg.on[i];
        [kLabels[i] drawAtPoint:CGPointMake(_rect.origin.x + 14, y + 9) withAttributes:(on ? onAttr : offAttr)];

        CGRect pill = CGRectMake(_rect.origin.x + kPanelW - 58, y + 8, 40, 18);
        CGContextSetFillColorWithColor(c, (on ? [UIColor whiteColor] : [UIColor colorWithWhite:1 alpha:0.14]).CGColor);
        [[UIBezierPath bezierPathWithRoundedRect:pill cornerRadius:9] fill];
        if (on) {
            CGContextSetFillColorWithColor(c, UIColor.blackColor.CGColor);
            CGContextFillEllipseInRect(c, CGRectMake(pill.origin.x + 22, pill.origin.y + 2, 14, 14));
        }
    }

    // FOV ring
    if (gCfg.on[T_AIMBOT] || gCfg.on[T_SOFT]) {
        float r = xenoFovRadius();
        CGContextSetStrokeColorWithColor(c, [UIColor colorWithWhite:1 alpha:0.16].CGColor);
        CGContextSetLineWidth(c, 0.6);
        CGRect ring = CGRectMake(self.bounds.size.width * 0.5f - r, self.bounds.size.height * 0.5f - r, r * 2, r * 2);
        CGContextStrokeEllipseInRect(c, ring);
    }
}

- (void)teardown { [self.link invalidate]; [self removeFromSuperview]; }
@end
