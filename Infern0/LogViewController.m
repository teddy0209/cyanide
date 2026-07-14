//
//  LogViewController.m
//  Cyanide
//

#import "LogViewController.h"
#import "LogTextView.h"
#import "installer/CYIconBadge.h"
#import <sys/utsname.h>

@interface LogViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) UILabel *bannerLabel;
@property (nonatomic, strong) LogTextView *logView;
@property (nonatomic, strong) UISegmentedControl *filterControl;
@end

@implementation LogViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Activity";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.view.backgroundColor = CYCanvasColor();
    CYApplyNavigationStyle(self.navigationController);
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(shareActivity)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = @"Share activity log";
    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.placeholder = @"Search activity";
    self.navigationItem.searchController = search;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;

    _bannerLabel = [[UILabel alloc] init];
    _bannerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _bannerLabel.numberOfLines = 0;
    _bannerLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    _bannerLabel.adjustsFontForContentSizeCategory = YES;
    _bannerLabel.textColor = UIColor.labelColor;
    _bannerLabel.backgroundColor = CYSurfaceColor();
    _bannerLabel.textAlignment = NSTextAlignmentCenter;
    _bannerLabel.attributedText = [self buildBannerText];
    _bannerLabel.layer.cornerRadius = 18;
    _bannerLabel.layer.borderWidth = 0.5;
    _bannerLabel.layer.borderColor = CYSurfaceBorderColor().CGColor;
    _bannerLabel.clipsToBounds = YES;
    [self.view addSubview:_bannerLabel];

    self.filterControl = [[UISegmentedControl alloc] initWithItems:@[@"All", @"Warnings", @"Errors"]];
    self.filterControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.filterControl.selectedSegmentIndex = 0;
    self.filterControl.selectedSegmentTintColor = CYAccentColor();
    [self.filterControl addTarget:self action:@selector(filterChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.filterControl];

    UIView *separator = [[UIView alloc] init];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.backgroundColor = UIColor.separatorColor;
    [self.view addSubview:separator];

    _logView = [[LogTextView alloc] initWithFrame:CGRectZero];
    _logView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_logView];

    [NSLayoutConstraint activateConstraints:@[
        [_bannerLabel.topAnchor      constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [_bannerLabel.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_bannerLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [_bannerLabel.heightAnchor constraintGreaterThanOrEqualToConstant:76],

        [self.filterControl.topAnchor constraintEqualToAnchor:_bannerLabel.bottomAnchor constant:10],
        [self.filterControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.filterControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.filterControl.heightAnchor constraintEqualToConstant:34],

        [separator.topAnchor      constraintEqualToAnchor:self.filterControl.bottomAnchor constant:10],
        [separator.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [separator.heightAnchor   constraintEqualToConstant:0.5],

        [_logView.topAnchor      constraintEqualToAnchor:separator.bottomAnchor],
        [_logView.bottomAnchor   constraintEqualToAnchor:self.view.bottomAnchor],
        [_logView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor],
        [_logView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

- (void)filterChanged:(UISegmentedControl *)sender
{
    [self.logView setLogSeverityFilter:sender.selectedSegmentIndex];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    [self.logView setLogFilterText:searchController.searchBar.text];
}

- (void)shareActivity
{
    NSString *snapshot = log_inapp_buffer_snapshot();
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[snapshot.length ? snapshot : @"No Infern0 activity yet."] applicationActivities:nil];
    activity.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:activity animated:YES completion:nil];
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

    NSString *banner = [NSString stringWithFormat:@"● LIVE ACTIVITY\nInfern0 %@ (%@) · %s · iOS %@\nDetailed operations, warnings, and recovery information appear below.",
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

@end
