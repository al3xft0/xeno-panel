#import "Menu.h"
#import "Core.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kPanelW = 300.f;
static const CGFloat kRowH   = 34.f;
static const CGFloat kHeadH  = 56.f;
static const CGFloat kTabH   = 38.f;
static const CGFloat kBtnSize = 56.f;

@implementation XenoMenu {
    CGPoint _origin;
    BOOL    _dragging;
    BOOL    _btnDragging;
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
    _origin = CGPointMake(24, gCfg.insetTop + 70);
    gCfg.menuOpen = YES;
    [self layoutRect];
    return self;
}

- (void)layoutRect {
    _rect = CGRectMake(_origin.x, _origin.y, kPanelW, kHeadH + kTabH + kRowH * 8 + 24);
    _btnRect = CGRectMake(self.bounds.size.width - kBtnSize - 20, self.bounds.size.height - kBtnSize - 90, kBtnSize, kBtnSize);
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
        _btnDragging = YES;
        _dragStart = CGPointMake(p.x - _btnRect.origin.x, p.y - _btnRect.origin.y);
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
    CGPoint p = [touches.anyObject locationInView:self];
    if (_btnDragging) {
        _btnRect.origin = CGPointMake(p.x - _dragStart.x, p.y - _dragStart.y);
        [self setNeedsDisplay];
        return;
    }
    if (!_dragging) return;
    _origin = CGPointMake(p.x - _dragStart.x, p.y - _dragStart.y);
    [self layoutRect];
    [self setNeedsDisplay];
}

- (void)touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event {
    if (_btnDragging) {
        _btnDragging = NO;
        // tap if barely moved → toggle
        // (simple: always allow toggle on short press; for now just end)
        gCfg.menuOpen = !gCfg.menuOpen;
        [self setNeedsDisplay];
        return;
    }
    _dragging = NO;
}
- (void)touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event {
    _btnDragging = NO;
    _dragging = NO;
}

- (CGRect)rectForRow:(int)i {
    return CGRectMake(_rect.origin.x, _rect.origin.y + kHeadH + kTabH + kRowH * i, kPanelW, kRowH);
}

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();

    // floating M button
    CGContextSetFillColorWithColor(c, [UIColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:0.95].CGColor);
    CGContextFillEllipseInRect(c, _btnRect);
    CGContextSetStrokeColorWithColor(c, [UIColor colorWithWhite:1 alpha:0.35].CGColor);
    CGContextSetLineWidth(c, 1.8);
    CGContextStrokeEllipseInRect(c, _btnRect);
    NSDictionary* mAttr = @{ NSFontAttributeName: [UIFont systemFontOfSize:30 weight:UIFontWeightBold],
                             NSForegroundColorAttributeName: UIColor.whiteColor };
    [@"M" drawAtPoint:CGPointMake(_btnRect.origin.x + 16, _btnRect.origin.y + 9) withAttributes:mAttr];

    // FOV ring always (when enabled)
    if (gCfg.on[T_ESP_MASTER] && gCfg.on[T_RING]) {
        CGContextSetStrokeColorWithColor(c, [UIColor colorWithRed:0.3 green:0.85 blue:0.5 alpha:0.55].CGColor);
        CGContextSetLineWidth(c, 1.4);
        float r = xenoFovRadius();
        CGRect ring = CGRectMake(self.bounds.size.width * 0.5f - r, self.bounds.size.height * 0.5f - r, r * 2, r * 2);
        CGContextStrokeEllipseInRect(c, ring);
    }

    if (!gCfg.menuOpen) return;

    UIBezierPath* panel = [UIBezierPath bezierPathWithRoundedRect:_rect cornerRadius:18];
    CGContextSetFillColorWithColor(c, [UIColor colorWithRed:0.07 green:0.07 blue:0.09 alpha:0.97].CGColor);
    [panel fill];
    CGContextSetStrokeColorWithColor(c, [UIColor colorWithWhite:1 alpha:0.12].CGColor);
    CGContextSetLineWidth(c, 0.8);
    [panel stroke];

    NSDictionary* headAttr = @{ NSFontAttributeName: [UIFont monospacedSystemFontOfSize:18 weight:UIFontWeightSemibold],
                                NSForegroundColorAttributeName: UIColor.whiteColor };
    [@"mirage" drawAtPoint:CGPointMake(_rect.origin.x + 18, _rect.origin.y + 16) withAttributes:headAttr];

    NSDictionary* subAttr = @{ NSFontAttributeName: [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular],
                               NSForegroundColorAttributeName: [UIColor colorWithWhite:0.7 alpha:0.55] };
    NSString* sub;
    switch (gCfg.status) {
        case S_LIVE:      sub = @"live"; break;
        case S_NO_MATCH:  sub = @"no match"; break;
        case S_NO_MODULE: sub = @"no UnityFramework"; break;
        case S_UUID_BAD:  sub = [NSString stringWithFormat:@"uuid %s", gUuidActual]; break;
        default:          sub = @"booting"; break;
    }
    [sub drawAtPoint:CGPointMake(_rect.origin.x + 18, _rect.origin.y + 36) withAttributes:subAttr];

    NSArray* tabs = @[@"AIM", @"VISUAL", @"MOVE"];
    for (int t = 0; t < TAB_COUNT; t++) {
        CGRect tr = CGRectMake(_rect.origin.x + t * (kPanelW / TAB_COUNT), _rect.origin.y + kHeadH, kPanelW / TAB_COUNT, kTabH);
        BOOL sel = gCfg.tab == t;
        if (sel) {
            CGContextSetFillColorWithColor(c, [UIColor colorWithWhite:1 alpha:0.08].CGColor);
            CGContextFillRect(c, tr);
        }
        NSDictionary* ta = @{ NSFontAttributeName: [UIFont monospacedSystemFontOfSize:12 weight:sel ? UIFontWeightSemibold : UIFontWeightRegular],
                              NSForegroundColorAttributeName: sel ? UIColor.whiteColor : [UIColor colorWithWhite:0.65 alpha:0.5] };
        [tabs[t] drawAtPoint:CGPointMake(tr.origin.x + 14, tr.origin.y + 11) withAttributes:ta];
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

    NSDictionary* onAttr  = @{ NSFontAttributeName: [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular],
                               NSForegroundColorAttributeName: UIColor.whiteColor };
    NSDictionary* offAttr = @{ NSFontAttributeName: [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular],
                               NSForegroundColorAttributeName: [UIColor colorWithWhite:0.65 alpha:0.45] };

    for (int i = 0; i < labels.count; i++) {
        CGFloat y = _rect.origin.y + kHeadH + kTabH + kRowH * i;
        int idx = base + i;
        bool on = (idx < T_COUNT) && gCfg.on[idx];
        [labels[i] drawAtPoint:CGPointMake(_rect.origin.x + 18, y + 9) withAttributes:(on ? onAttr : offAttr)];

        CGRect pill = CGRectMake(_rect.origin.x + kPanelW - 62, y + 7, 44, 20);
        UIBezierPath* pillPath = [UIBezierPath bezierPathWithRoundedRect:pill cornerRadius:10];
        CGContextSetFillColorWithColor(c, (on ? [UIColor whiteColor] : [UIColor colorWithWhite:1 alpha:0.1]).CGColor);
        [pillPath fill];
        if (on) {
            CGContextSetFillColorWithColor(c, [UIColor colorWithRed:0.07 green:0.07 blue:0.09 alpha:1].CGColor);
            CGContextFillEllipseInRect(c, CGRectMake(pill.origin.x + 24, pill.origin.y + 3, 14, 14));
        }
    }
}

- (void)teardown { [self.link invalidate]; [self removeFromSuperview]; }
@end
