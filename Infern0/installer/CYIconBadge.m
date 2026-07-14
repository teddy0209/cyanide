//
//  CYIconBadge.m
//  Cyanide
//

#import "CYIconBadge.h"
#import <objc/runtime.h>

static const void *kCYPolishedButtonKey = &kCYPolishedButtonKey;
static const void *kCYButtonSurfaceKey = &kCYButtonSurfaceKey;
static const void *kCYEntranceAnimatedKey = &kCYEntranceAnimatedKey;

@interface CYInteractionDriver : NSObject
@end

@implementation CYInteractionDriver

+ (UIView *)surfaceForButton:(UIButton *)button
{
    NSValue *value = objc_getAssociatedObject(button, kCYButtonSurfaceKey);
    return value.nonretainedObjectValue ?: button;
}

+ (void)pressBegan:(UIButton *)button
{
    UIView *surface = [self surfaceForButton:button];
    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut animations:^{
        surface.transform = CGAffineTransformMakeScale(0.975, 0.975);
        surface.alpha = 0.88;
    } completion:nil];
}

+ (void)pressEnded:(UIButton *)button
{
    UIView *surface = [self surfaceForButton:button];
    [UIView animateWithDuration:0.36 delay:0 usingSpringWithDamping:0.72 initialSpringVelocity:0.4 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        surface.transform = CGAffineTransformIdentity;
        surface.alpha = 1.0;
    } completion:nil];
}

+ (void)pressCommitted:(UIButton *)button
{
    [self pressEnded:button];
    CYSelectionHaptic();
}

@end

UIColor *CYAccentColor(void)
{
    return [UIColor colorWithRed:1.0 green:0.29 blue:0.10 alpha:1.0];
}

UIColor *CYCanvasColor(void)
{
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.035 green:0.028 blue:0.026 alpha:1.0]
            : [UIColor colorWithRed:0.975 green:0.965 blue:0.955 alpha:1.0];
    }];
}

UIColor *CYSurfaceColor(void)
{
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.095 green:0.080 blue:0.074 alpha:0.96]
            : [UIColor colorWithWhite:1.0 alpha:0.92];
    }];
}

UIColor *CYSurfaceBorderColor(void)
{
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.09]
            : [UIColor colorWithRed:0.40 green:0.20 blue:0.12 alpha:0.10];
    }];
}

void CYApplyCardStyle(UIView *view, CGFloat cornerRadius)
{
    view.backgroundColor = CYSurfaceColor();
    view.layer.cornerRadius = cornerRadius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    view.layer.borderColor = CYSurfaceBorderColor().CGColor;
    view.layer.shadowColor = UIColor.blackColor.CGColor;
    view.layer.shadowOpacity = 0.08;
    view.layer.shadowRadius = 14.0;
    view.layer.shadowOffset = CGSizeMake(0.0, 6.0);
}

void CYConfigureTableView(UITableView *tableView)
{
    tableView.backgroundColor = CYCanvasColor();
    tableView.separatorColor = [UIColor.separatorColor colorWithAlphaComponent:0.42];
    tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    tableView.estimatedSectionHeaderHeight = 38.0;
    tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    tableView.delaysContentTouches = NO;
    tableView.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(0.0, 18.0, 0.0, 18.0);
    if (@available(iOS 15.0, *)) tableView.sectionHeaderTopPadding = 4.0;
}

void CYPolishButton(UIButton *button)
{
    CYPolishOverlayButton(button, button);
}

void CYPolishOverlayButton(UIButton *button, UIView *surface)
{
    if (!button || objc_getAssociatedObject(button, kCYPolishedButtonKey)) return;
    objc_setAssociatedObject(button, kCYPolishedButtonKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (surface && surface != button) {
        objc_setAssociatedObject(button, kCYButtonSurfaceKey,
                                 [NSValue valueWithNonretainedObject:surface],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [button addTarget:CYInteractionDriver.class action:@selector(pressBegan:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [button addTarget:CYInteractionDriver.class action:@selector(pressEnded:) forControlEvents:UIControlEventTouchCancel | UIControlEventTouchDragExit | UIControlEventTouchUpOutside];
    [button addTarget:CYInteractionDriver.class action:@selector(pressCommitted:) forControlEvents:UIControlEventTouchUpInside];
}

void CYSelectionHaptic(void)
{
    UISelectionFeedbackGenerator *generator = [[UISelectionFeedbackGenerator alloc] init];
    [generator prepare];
    [generator selectionChanged];
}

void CYSuccessHaptic(void)
{
    UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
    [generator prepare];
    [generator notificationOccurred:UINotificationFeedbackTypeSuccess];
}

void CYAnimateEntrance(UIView *view)
{
    if (!view || [UIAccessibility isReduceMotionEnabled] || objc_getAssociatedObject(view, kCYEntranceAnimatedKey)) return;
    objc_setAssociatedObject(view, kCYEntranceAnimatedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.alpha = 0.0;
    view.transform = CGAffineTransformMakeTranslation(0.0, 10.0);
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.48 delay:0.04 usingSpringWithDamping:0.86 initialSpringVelocity:0.15 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            view.alpha = 1.0;
            view.transform = CGAffineTransformIdentity;
        } completion:nil];
    });
}

void CYApplyNavigationStyle(UINavigationController *navigationController)
{
    if (!navigationController) return;
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithTransparentBackground];
    appearance.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    appearance.backgroundColor = [CYCanvasColor() colorWithAlphaComponent:0.72];
    appearance.shadowColor = UIColor.clearColor;
    appearance.titleTextAttributes = @{
        NSFontAttributeName: [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: UIColor.labelColor,
    };
    appearance.largeTitleTextAttributes = @{
        NSFontAttributeName: [UIFont systemFontOfSize:34.0 weight:UIFontWeightBold],
        NSForegroundColorAttributeName: UIColor.labelColor,
    };
    UINavigationBar *bar = navigationController.navigationBar;
    bar.standardAppearance = appearance;
    bar.scrollEdgeAppearance = appearance;
    bar.compactAppearance = appearance;
    bar.tintColor = CYAccentColor();
}

void CYApplyTabBarStyle(UITabBar *tabBar)
{
    UITabBarAppearance *appearance = [[UITabBarAppearance alloc] init];
    [appearance configureWithTransparentBackground];
    appearance.backgroundEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    appearance.backgroundColor = [CYSurfaceColor() colorWithAlphaComponent:0.82];
    appearance.shadowColor = CYSurfaceBorderColor();
    appearance.stackedLayoutAppearance.selected.iconColor = CYAccentColor();
    appearance.stackedLayoutAppearance.selected.titleTextAttributes = @{NSForegroundColorAttributeName: CYAccentColor(),
                                                                         NSFontAttributeName: [UIFont systemFontOfSize:10.0 weight:UIFontWeightSemibold]};
    appearance.stackedLayoutAppearance.normal.iconColor = UIColor.secondaryLabelColor;
    appearance.stackedLayoutAppearance.normal.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.secondaryLabelColor};
    tabBar.standardAppearance = appearance;
    tabBar.scrollEdgeAppearance = appearance;
    tabBar.tintColor = CYAccentColor();
}

UIImage *CYIconBadgeImage(NSString *sfSymbol, UIColor *color, CGFloat size)
{
    UIGraphicsImageRendererFormat *fmt = [[UIGraphicsImageRendererFormat alloc] init];
    fmt.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size) format:fmt];

    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGRect badgeRect = CGRectInset(CGRectMake(0, 0, size, size), 0.5, 0.5);
        UIBezierPath *badge = [UIBezierPath bezierPathWithRoundedRect:badgeRect cornerRadius:size * 0.30];
        [[color colorWithAlphaComponent:0.13] setFill];
        [badge fill];
        [[color colorWithAlphaComponent:0.22] setStroke];
        badge.lineWidth = 1.0;
        [badge stroke];

        UIImageSymbolConfiguration *symCfg = [UIImageSymbolConfiguration
            configurationWithPointSize:size * 0.42 weight:UIImageSymbolWeightSemibold];
        UIImage *sym = [[UIImage systemImageNamed:sfSymbol withConfiguration:symCfg]
            imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
        if (!sym) return;

        CGSize symSize = [sym size];
        CGFloat x = (size - symSize.width) / 2.0;
        CGFloat y = (size - symSize.height) / 2.0;
        [sym drawInRect:CGRectMake(x, y, symSize.width, symSize.height)];
    }];
}

UIColor *CYSpectrumColor(NSUInteger index)
{
    static NSArray<UIColor *> *colors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        colors = @[
            UIColor.systemRedColor,
            UIColor.systemTealColor,
            UIColor.systemGreenColor,
            UIColor.systemOrangeColor,
            UIColor.systemPinkColor,
            UIColor.systemPurpleColor,
            UIColor.systemIndigoColor,
            UIColor.systemOrangeColor,
            UIColor.systemRedColor,
            UIColor.systemMintColor,
        ];
    });
    return colors[index % colors.count];
}

UIView *CYSectionHeaderView(NSString *title)
{
    UIView *container = [[UIView alloc] init];

    UILabel *lbl = [[UILabel alloc] init];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.text = title;
    lbl.text = title.uppercaseString;
    lbl.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightHeavy];
    lbl.textColor = CYAccentColor();
    lbl.adjustsFontForContentSizeCategory = YES;
    [container addSubview:lbl];

    [NSLayoutConstraint activateConstraints:@[
        [lbl.leadingAnchor  constraintEqualToAnchor:container.leadingAnchor constant:20.0],
        [lbl.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-20.0],
        [lbl.topAnchor      constraintEqualToAnchor:container.topAnchor constant:14.0],
        [lbl.bottomAnchor   constraintEqualToAnchor:container.bottomAnchor constant:-5.0],
    ]];

    return container;
}
