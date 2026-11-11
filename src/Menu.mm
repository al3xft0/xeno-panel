#import "Menu.h"
#import "Core.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kPanelW = 280.f;
static const CGFloat kRowH   = 32.f;
static const CGFloat kHeadH  = 52.f;
static const CGFloat kTabH   = 36.f;
static const CGFloat kBtnSize = 52.f;

@implementation XenoMenu {
    CGPoint _origin;
    BOOL    _dragging;
    CGPoint _dragStart;
    CGRect  _rect;
    CGRect  _btnRect;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.multipleTouchEnabled = NO;
    _origin = CGPointMake(20, gCfg.insetTop + 60);
    gCfg.menuOpen = YES;
    [self layoutRect];
    return self;
}

- (void)layoutRect {
    _rect = CGRectMake(_origin.x, _origin.y, kPanelW, kHeadH + kTabH + kRowH * 8 + 20);
    _btnRect = CGRectMake(self.bounds.size.width - kBtnSize - 16, self.bounds.size.height - kBtnSize - 80, kBtnSize, kBtnSize);
}

- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent*)e {
    if (CGRectContainsPoint(_btnRect, p)) return YES;
    return gCfg.menuOpen && CGRectContainsPoint(_rect, p);
}

- (UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e {
    return [self pointInside:p withEvent:e] ? self : nil;
}

- (void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event {
    CGPoint p = [touches.anyObject locationInView:self];
    if (CGRectContainsPoint(_btnRect, p)) {
        gCfg.menuOpen = !gCfg.menuOpen;
        [self setNeedsDisplay];
        return;
    }
    if (!gCfg.menuOpen) return;
    CGRect head = CGRectMake(_rect.origin.x, _rect.origin.y, kPanelW, kHeadH);
    if (CGRectContainsPoint(head, p)) {
        _dragging = YES;
        _dragStart = CGPointMake(p.x - _origin.x, p.y - _origin.y);
        return;
    }
    for (int t = 0; t < TAB_COUNT; t++) {
        CGRect tr = CGRectMake(_rect.origin.x + t * (kPanelW / TAB_COUNT), _rect.origin.y + kHeadH, kPanelW / TAB_COUNT, kTabH);
        if (CGRectContainsPoint(tr, p)) { gCfg.tab = t; [self setNeedsDisplay]; return; }
    }
    int base = 0;
    if (gCfg.tab == TAB_AIM) base = T_AIM_MASTER;
    else if (gCfg.tab == TAB_VISUAL) base = T_ESP_MASTER;
    else base = T_FLY;
    for (int i = 0; i < 6; i++) {
        int idx = base + i;
        if (idx >= T_COUNT) break;
        CGRect rr = [self rectForRow:i];
        if (CGRectContainsPoint(rr, p)) { xenoSetToggle(idx); [self setNeedsDisplay]; return; }
    }
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
    return CGRectMake(_rect.origin.x, _rect.origin.y + kHeadH + kTabH + kRowH * i, kPanelW, kRowH);
}

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();

    CGContextSetFillColorWithColor(c, [UIColor colorWithWhite:0.08 alpha:0.92].CGColor);
    CGContextFillEllipseInRect(c, _btnRect);
    CGContextSetStrokeColorWithColor(c, [UIColor whiteColor].CGColor);
    CGContextSetLineWidth(c, 1.5);
    CGContextStrokeEllipseInRect(c, _btnRect);
    NSDictionary* mAttr = @{ NSFontAttributeName: [UIFont boldSystemFontOfSize:28],
                             NSForegroundColorAttributeName: UIColor.whiteColor };
    [@"M" drawAtPoint:CGPointMake(_btnRect.origin.x + 14, _btnRect.origin.y + 8) withAttributes:mAttr];

    if (!gCfg.menuOpen) return;

    UIBezierPath* panel = [UIBezierPath bezierPathWithRoundedRect:_rect cornerRadius:16];
    CGContextSetFillColorWithColor(c, [UIColor colorWithWhite:0.06 alpha:0.96].CGColor);
    [panel fill];
    CGContextSetStrokeColorWithColor(c, [UIColor colorWithWhite:1 alpha:0.18].CGColor);
    CGContextSetLineWidth(c, 0.6);
    [panel stroke];

    NSDictionary* headAttr = @{ NSFontAttributeName: [UIFont monospacedSystemFontOfSize:16 weight:UIFontWeightBold],
                                NSForegroundColorAttributeName: UIColor.whiteColor };
    [@"mirage" drawAtPoint:CGPointMake(_rect.origin.x + 16, _rect.origin.y + 14) withAttributes:headAttr];

    NSDictionary* subAttr = @{ NSFontAttributeName: [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular],
                               NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.45] };
    NSString* sub;
    switch (gCfg.status) {
        case S_LIVE:      sub = @"live"; break;
        case S_NO_MATCH:  sub = @"no match"; break;
        case S_NO_MODULE: sub = @"no UnityFramework"; break;
        case S_UUID_BAD:  sub = [NSString stringWithFormat:@"uuid %s", gUuidActual]; break;
        default:          sub = @"booting"; break;
    }
    [sub drawAtPoint:CGPointMake(_rect.origin.x + 16, _rect.origin.y + 32) withAttributes:subAttr];

    NSArray* tabs = @[@"AIM", @"VISUAL", @"MOVE"];
    for (int t = 0; t < TAB_COUNT; t++) {
        CGRect tr = CGRectMake(_rect.origin.x + t * (kPanelW / TAB_COUNT), _rect.origin.y + kHeadH, kPanelW / TAB_COUNT, kTabH);
        BOOL sel = gCfg.tab == t;
        CGContextSetFillColorWithColor(c, (sel ? [UIColor colorWithWhite:1 alpha:0.12] : [UIColor clearColor]).CGColor);
        CGContextFillRect(c, tr);
        NSDictionary* ta = @{ NSFontAttributeName: [UIFont monospacedSystemFontOfSize:11 weight:sel ? UIFontWeightSemibold : UIFontWeightRegular],
                              NSForegroundColorAttributeName: sel ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:0.4] };
        [tabs[t] drawAtPoint:CGPointMake(tr.origin.x + 12, tr.origin.y + 10) withAttributes:ta];
    }

    NSArray* labels;
    int base;
    if (gCfg.tab == TAB_AIM) {
        labels = @[@"Aim Master", @"Aimbot", @"Soft Aim", @"No Recoil", @"No Spread", @"Fast Reload"];
        base = T_AIM_MASTER;
    } else if (gCfg.tab == TAB_VISUAL) {
        labels = @[@"ESP Master", @"Box", @"Line", @"Name", @"Distance", @"FOV Ring"];
        base = T_ESP_MASTER;
    } else {
        labels = @[@"Fly", @"Noclip", @"Rest Guest"];
        base = T_FLY;
    }

    NSDictionary* onAttr  = @{ NSFontAttributeName: [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular],
                               NSForegroundColorAttributeName: UIColor.whiteColor };
    NSDictionary* offAttr = @{ NSFontAttributeName: [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular],
                               NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.4] };

    for (int i = 0; i < labels.count; i++) {
        CGFloat y = _rect.origin.y + kHeadH + kTabH + kRowH * i;
        int idx = base + i;
        bool on = (idx < T_COUNT) && gCfg.on[idx];
        [labels[i] drawAtPoint:CGPointMake(_rect.origin.x + 16, y + 8) withAttributes:(on ? onAttr : offAttr)];

        CGRect pill = CGRectMake(_rect.origin.x + kPanelW - 56, y + 6, 40, 20);
        CGContextSetFillColorWithColor(c, (on ? [UIColor whiteColor] : [UIColor colorWithWhite:1 alpha:0.12]).CGColor);
        [[UIBezierPath bezierPathWithRoundedRect:pill cornerRadius:10] fill];
        if (on) {
            CGContextSetFillColorWithColor(c, UIColor.blackColor.CGColor);
            CGContextFillEllipseInRect(c, CGRectMake(pill.origin.x + 22, pill.origin.y + 3, 14, 14));
        }
    }

    if (gCfg.on[T_ESP_MASTER]) {
        CGContextSetStrokeColorWithColor(c, [UIColor colorWithRed:0.2 green:1 blue:0.4 alpha:0.7].CGColor);
        CGContextSetLineWidth(c, 1.2);
        if (gCfg.on[T_RING]) {
            float r = xenoFovRadius();
            CGRect ring = CGRectMake(self.bounds.size.width * 0.5f - r, self.bounds.size.height * 0.5f - r, r * 2, r * 2);
            CGContextStrokeEllipseInRect(c, ring);
        }
    }
}

- (void)teardown { [self.link invalidate]; [self removeFromSuperview]; }
@end
