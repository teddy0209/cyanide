//
//  InstallProgressViewController.m
//  Cyanide
//

#import "InstallProgressViewController.h"
#import "PackageQueue.h"
#import "QueueReviewViewController.h"
#import "CYIconBadge.h"
#import "../SettingsViewController.h"
#import "../LogTextView.h"
#import <sys/utsname.h>

@interface InstallProgressViewController ()
@property (nonatomic, strong) UILabel *bannerLabel;
@property (nonatomic, strong) LogTextView *logView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIBarButtonItem *hideOrDoneButton;
@property (nonatomic, assign) BOOL completed;
@property (nonatomic, assign) BOOL didPromptForHideHomeBarRespring;
@end

@implementation InstallProgressViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = CYCanvasColor();
    CYApplyNavigationStyle(self.navigationController);
    self.title = @"Applying Changes";
    self.modalInPresentation = NO;

    self.bannerLabel = [[UILabel alloc] init];
    self.bannerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.bannerLabel.numberOfLines = 0;
    self.bannerLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.bannerLabel.adjustsFontForContentSizeCategory = YES;
    self.bannerLabel.textColor = UIColor.labelColor;
    self.bannerLabel.backgroundColor = CYSurfaceColor();
    self.bannerLabel.textAlignment = NSTextAlignmentCenter;
    self.bannerLabel.attributedText = [self buildBannerText];
    self.bannerLabel.layer.cornerRadius = 18;
    self.bannerLabel.layer.borderWidth = 0.5;
    self.bannerLabel.layer.borderColor = CYSurfaceBorderColor().CGColor;
    self.bannerLabel.clipsToBounds = YES;
    [self.view addSubview:self.bannerLabel];

    UIView *separator = [[UIView alloc] init];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.07];
    [self.view addSubview:separator];

    self.logView = [[LogTextView alloc] initWithFrame:CGRectZero];
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.logView];

    // Blurred footer
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    UIVisualEffectView *footer = [[UIVisualEffectView alloc] initWithEffect:blur];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:footer];

    UIView *footerDivider = [[UIView alloc] init];
    footerDivider.translatesAutoresizingMaskIntoConstraints = NO;
    footerDivider.backgroundColor = UIColor.separatorColor;
    [footer.contentView addSubview:footerDivider];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.color = CYAccentColor();
    [self.spinner startAnimating];
    [footer.contentView addSubview:self.spinner];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.text = @"Preparing a safe live session…";
    self.statusLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightRegular];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.numberOfLines = 1;
    self.statusLabel.adjustsFontSizeToFitWidth = YES;
    self.statusLabel.minimumScaleFactor = 0.8;
    [footer.contentView addSubview:self.statusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.bannerLabel.topAnchor      constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [self.bannerLabel.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [self.bannerLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [self.bannerLabel.heightAnchor constraintGreaterThanOrEqualToConstant:76.0],

        [separator.topAnchor      constraintEqualToAnchor:self.bannerLabel.bottomAnchor constant:12],
        [separator.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [separator.heightAnchor   constraintEqualToConstant:0.5],

        [self.logView.topAnchor      constraintEqualToAnchor:separator.bottomAnchor],
        [self.logView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [self.logView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.logView.bottomAnchor   constraintEqualToAnchor:footer.topAnchor],

        [footer.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [footer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [footer.bottomAnchor   constraintEqualToAnchor:self.view.bottomAnchor],
        [footer.heightAnchor   constraintEqualToConstant:64.0],

        [footerDivider.topAnchor      constraintEqualToAnchor:footer.topAnchor],
        [footerDivider.leadingAnchor  constraintEqualToAnchor:footer.leadingAnchor],
        [footerDivider.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor],
        [footerDivider.heightAnchor   constraintEqualToConstant:0.5],

        [self.spinner.leadingAnchor      constraintEqualToAnchor:footer.leadingAnchor constant:20.0],
        [self.spinner.centerYAnchor      constraintEqualToAnchor:footer.safeAreaLayoutGuide.topAnchor constant:22.0],
        [self.statusLabel.leadingAnchor  constraintEqualToAnchor:self.spinner.trailingAnchor constant:12.0],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-20.0],
        [self.statusLabel.centerYAnchor  constraintEqualToAnchor:self.spinner.centerYAnchor],
    ]];

    self.hideOrDoneButton = [[UIBarButtonItem alloc] initWithTitle:@"Hide"
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(didTapDone)];
    self.navigationItem.rightBarButtonItem = self.hideOrDoneButton;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didReceiveCompleteNotification:)
                                                 name:kSettingsActionsDidCompleteNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didReceiveCompleteNotification:(NSNotification *)note
{
    if (self.completed) return;
    self.completed = YES;
    [self.spinner stopAnimating];
    self.spinner.hidden = YES;
    NSNumber *successValue = note.userInfo[kSettingsActionsDidCompleteSuccessKey];
    BOOL success = successValue ? successValue.boolValue : YES;
    NSString *message = note.userInfo[kSettingsActionsDidCompleteMessageKey];
    self.statusLabel.text = message.length
        ? message
        : (success ? @"All tweaks applied in-session." : @"Failed — check the log above.");
    self.statusLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightSemibold];
    self.statusLabel.textColor = success
        ? UIColor.systemGreenColor
        : UIColor.systemRedColor;
    self.title = success ? @"Complete" : @"Failed";
    if (success) CYSuccessHaptic();
    self.hideOrDoneButton.title = @"Done";
    if (success &&
        self.promptsForHideHomeBarRespring &&
        settings_hide_home_bar_respring_pending()) {
        [self scheduleHideHomeBarRespringPrompt];
    }
}

- (void)scheduleHideHomeBarRespringPrompt
{
    if (self.didPromptForHideHomeBarRespring) return;
    self.didPromptForHideHomeBarRespring = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!self.view.window) return;
        settings_present_hide_home_bar_respring_prompt(self);
    });
}

- (NSAttributedString *)buildBannerText {
    NSBundle *b = [NSBundle mainBundle];
    NSDictionary *info = b.infoDictionary;
    NSString *shortVer = info[@"CFBundleShortVersionString"] ?: @"?";
    NSString *build = info[@"CFBundleVersion"] ?: @"?";

    struct utsname u = {0};
    const char *machine = "device";
    if (uname(&u) == 0 && u.machine[0])
        machine = u.machine;
    NSString *ios = UIDevice.currentDevice.systemVersion ?: @"?";

    NSString *banner = [NSString stringWithFormat:@"APPLYING YOUR SETUP\nInfern0 %@ (%@) · %s · iOS %@\nEach package reports its preparation, apply, verification, and cleanup stages below.",
                        shortVer, build, machine, ios];

    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.lineSpacing = 3.0;
    para.alignment = NSTextAlignmentCenter;

    return [[NSAttributedString alloc] initWithString:banner attributes:@{
        NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline],
        NSForegroundColorAttributeName: UIColor.labelColor,
        NSParagraphStyleAttributeName: para,
    }];
}

- (void)didTapDone
{
    UIViewController *presenter = self.presentingViewController;
    UINavigationController *nav = [presenter isKindOfClass:UINavigationController.class]
        ? (UINavigationController *)presenter
        : presenter.navigationController;
    [self dismissViewControllerAnimated:YES completion:^{
        if (!nav) return;
        NSMutableArray<__kindof UIViewController *> *stack = [nav.viewControllers mutableCopy];
        NSInteger removed = 0;
        for (NSInteger i = (NSInteger)stack.count - 1; i >= 0; i--) {
            if ([stack[i] isKindOfClass:QueueReviewViewController.class]) {
                [stack removeObjectAtIndex:i];
                removed++;
            }
        }
        if (removed > 0) {
            [nav setViewControllers:stack animated:YES];
        }
    }];
}

@end
