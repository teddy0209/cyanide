//
//  CYIconBadge.h
//  Cyanide
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

UIImage *CYIconBadgeImage(NSString *sfSymbol, UIColor *color, CGFloat size);
UIColor *CYSpectrumColor(NSUInteger index);
UIView *CYSectionHeaderView(NSString *title);
UIColor *CYAccentColor(void);
UIColor *CYCanvasColor(void);
UIColor *CYSurfaceColor(void);
UIColor *CYSurfaceBorderColor(void);
void CYApplyCardStyle(UIView *view, CGFloat cornerRadius);
void CYConfigureTableView(UITableView *tableView);
void CYApplyNavigationStyle(UINavigationController *navigationController);
void CYApplyTabBarStyle(UITabBar *tabBar);
void CYPolishButton(UIButton *button);
void CYPolishOverlayButton(UIButton *button, UIView *surface);
void CYSelectionHaptic(void);
void CYSuccessHaptic(void);
void CYAnimateEntrance(UIView *view);

NS_ASSUME_NONNULL_END
