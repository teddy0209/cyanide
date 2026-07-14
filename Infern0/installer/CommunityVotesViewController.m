//
//  CommunityVotesViewController.m
//  Infern0
//

#import "CommunityVotesViewController.h"
#import "CYIconBadge.h"
#import <math.h>

static NSString * const kCommunityVotesAPI = @"https://api.github.com/repos/Nnnnnnn274/Infern0/issues?state=open&per_page=100";
static NSString * const kCommunityVotesHub = @"https://github.com/Nnnnnnn274/Infern0/issues?q=is%3Aissue%20state%3Aopen%20%22%5BTweak%20Vote%5D%22%20in%3Atitle";
static NSString * const kCommunityVoteIdeaURL = @"https://github.com/Nnnnnnn274/Infern0/issues/new?template=tweak_vote.yml";
static NSString * const kLocalVotesDefaultsKey = @"Infern0CommunityVoteSelections";

@interface CYCommunityVoteProposal : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, copy, nullable) NSString *githubURL;
@property (nonatomic, assign) NSInteger voteCount;
@property (nonatomic, assign) BOOL remote;
@end

@implementation CYCommunityVoteProposal
@end

static NSString *community_issue_summary(NSString *body)
{
    if (body.length == 0) return @"Open the proposal to read the details and vote.";
    NSString *marker = @"### What should the port do?";
    NSRange start = [body rangeOfString:marker options:NSCaseInsensitiveSearch];
    NSString *candidate = body;
    if (start.location != NSNotFound) {
        NSUInteger offset = NSMaxRange(start);
        candidate = [body substringFromIndex:offset];
        NSRange next = [candidate rangeOfString:@"\n### "];
        if (next.location != NSNotFound) candidate = [candidate substringToIndex:next.location];
    }
    candidate = [candidate stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (candidate.length == 0) return @"Open the proposal to read the details and vote.";
    if (candidate.length > 180) candidate = [[candidate substringToIndex:177] stringByAppendingString:@"…"];
    return candidate;
}

@interface CommunityVotesViewController ()
@property (nonatomic, copy) NSArray<CYCommunityVoteProposal *> *proposals;
@property (nonatomic, strong) NSMutableSet<NSString *> *localSelections;
@property (nonatomic, strong) UIRefreshControl *voteRefreshControl;
@property (nonatomic, strong) UIView *introHeader;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *candidateStatLabel;
@property (nonatomic, strong) UILabel *voteStatLabel;
@property (nonatomic, strong) UILabel *pickedStatLabel;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL showingRemoteResults;
@end

@implementation CommunityVotesViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Community Votes";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    CYConfigureTableView(self.tableView);
    CYApplyNavigationStyle(self.navigationController);
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 108.0;
    self.tableView.separatorInset = UIEdgeInsetsMake(0.0, 66.0, 0.0, 18.0);

    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kLocalVotesDefaultsKey];
    self.localSelections = [NSMutableSet setWithArray:[saved isKindOfClass:NSArray.class] ? saved : @[]];
    self.proposals = [self builtInProposals];
    [self buildIntroHeader];

    self.voteRefreshControl = [[UIRefreshControl alloc] init];
    self.voteRefreshControl.tintColor = CYAccentColor();
    [self.voteRefreshControl addTarget:self action:@selector(refreshCommunityResults) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = self.voteRefreshControl;

    UIBarButtonItem *suggest = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"lightbulb.max.fill"]
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(suggestTweak)];
    suggest.accessibilityLabel = @"Suggest a tweak";
    self.navigationItem.rightBarButtonItem = suggest;

    [self refreshCommunityResults];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGFloat width = self.tableView.bounds.size.width;
    if (width <= 0 || fabs(self.introHeader.frame.size.width - width) < 0.5) return;
    CGRect frame = self.introHeader.frame;
    frame.size.width = width;
    self.introHeader.frame = frame;
    [self layoutIntroHeader];
    self.tableView.tableHeaderView = self.introHeader;
}

- (NSArray<CYCommunityVoteProposal *> *)builtInProposals
{
    NSArray<NSArray<NSString *> *> *items = @[
        @[@"choicy-lite", @"Choicy Lite", @"Per-app tweak profiles and safer feature exclusions without Substrate injection."],
        @[@"zenith-lite", @"Zenith Lite", @"Stack related apps behind a Home Screen icon with a compact pressable launcher."],
        @[@"dodo-lite", @"Dodo Lock Screen", @"A clean modular lock-screen layout with clock, weather, media, and notification positioning."],
        @[@"jellyfish-lite", @"Jellyfish Lite", @"Large adaptive lock-screen date, time, and weather styling."],
        @[@"complications-lite", @"Complications Lite", @"Apple Watch-style information widgets for the Lock Screen."],
        @[@"vesta-lite", @"Vesta App Drawer", @"A fast gesture-driven app drawer with favorites and category filtering."],
        @[@"tako-lite", @"Tako Notifications", @"Group notifications by app with compact expandable stacks."],
        @[@"messagesxi-lite", @"MessagesXI", @"More configurable Messages list styling, pinned chats, and conversation actions."],
        @[@"eneko-lite", @"Eneko Video Wallpaper", @"Video wallpaper playback with battery-aware pause and visibility rules."],
        @[@"crane-lite", @"Crane Profiles", @"Research per-app data profiles and quick profile switching within non-jailbroken limits."],
    ];
    NSMutableArray<CYCommunityVoteProposal *> *out = [NSMutableArray arrayWithCapacity:items.count];
    for (NSArray<NSString *> *item in items) {
        CYCommunityVoteProposal *proposal = [[CYCommunityVoteProposal alloc] init];
        proposal.identifier = item[0];
        proposal.name = item[1];
        proposal.summary = item[2];
        proposal.voteCount = 0;
        proposal.remote = NO;
        [out addObject:proposal];
    }
    return out;
}

- (void)buildIntroHeader
{
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 254.0)];
    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.tag = 101;
    CYApplyCardStyle(card, 22.0);
    [header addSubview:card];

    UILabel *eyebrow = [[UILabel alloc] initWithFrame:CGRectZero];
    eyebrow.tag = 102;
    eyebrow.text = @"COMMUNITY ROADMAP";
    eyebrow.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightHeavy];
    eyebrow.textColor = CYAccentColor();
    [card addSubview:eyebrow];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.tag = 103;
    title.text = @"Choose what comes next";
    title.font = [UIFont systemFontOfSize:22.0 weight:UIFontWeightBold];
    [card addSubview:title];

    UILabel *body = [[UILabel alloc] initWithFrame:CGRectZero];
    body.tag = 104;
    body.text = @"Build a private shortlist here, then use GitHub to add a verified thumbs-up to the public roadmap.";
    body.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    body.textColor = UIColor.secondaryLabelColor;
    body.numberOfLines = 2;
    [card addSubview:body];

    UILabel *status = [[UILabel alloc] initWithFrame:CGRectZero];
    status.tag = 105;
    status.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
    status.textColor = UIColor.secondaryLabelColor;
    status.numberOfLines = 2;
    [card addSubview:status];

    NSArray<NSString *> *statTitles = @[@"Candidates", @"Thumbs up", @"Shortlisted"];
    NSMutableArray<UILabel *> *statLabels = [NSMutableArray arrayWithCapacity:3];
    for (NSString *statTitle in statTitles) {
        UILabel *stat = [[UILabel alloc] initWithFrame:CGRectZero];
        stat.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightBold];
        stat.textColor = UIColor.secondaryLabelColor;
        stat.textAlignment = NSTextAlignmentCenter;
        stat.numberOfLines = 2;
        stat.accessibilityLabel = statTitle;
        [card addSubview:stat];
        [statLabels addObject:stat];
    }
    statLabels[0].tag = 107;
    statLabels[1].tag = 108;
    statLabels[2].tag = 109;

    UIButtonConfiguration *hubConfig = [UIButtonConfiguration filledButtonConfiguration];
    hubConfig.title = @"Open verified ballot";
    hubConfig.image = [UIImage systemImageNamed:@"hand.thumbsup.fill"];
    hubConfig.imagePadding = 7.0;
    hubConfig.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    hubConfig.baseBackgroundColor = CYAccentColor();
    UIButton *hub = [UIButton buttonWithConfiguration:hubConfig primaryAction:nil];
    hub.tag = 106;
    hub.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    [hub addTarget:self action:@selector(openVotingHub) forControlEvents:UIControlEventTouchUpInside];
    CYPolishButton(hub);
    [card addSubview:hub];

    self.introHeader = header;
    self.statusLabel = status;
    self.candidateStatLabel = statLabels[0];
    self.voteStatLabel = statLabels[1];
    self.pickedStatLabel = statLabels[2];
    self.tableView.tableHeaderView = header;
    [self layoutIntroHeader];
    [self updateStatusText];
    CYAnimateEntrance(card);
}

- (void)layoutIntroHeader
{
    UIView *card = [self.introHeader viewWithTag:101];
    CGFloat width = self.introHeader.bounds.size.width;
    card.frame = CGRectMake(16.0, 8.0, width - 32.0, 234.0);
    [card viewWithTag:102].frame = CGRectMake(18.0, 14.0, card.bounds.size.width - 36.0, 17.0);
    [card viewWithTag:103].frame = CGRectMake(18.0, 34.0, card.bounds.size.width - 36.0, 28.0);
    [card viewWithTag:104].frame = CGRectMake(18.0, 65.0, card.bounds.size.width - 36.0, 38.0);
    [card viewWithTag:105].frame = CGRectMake(18.0, 105.0, card.bounds.size.width - 36.0, 20.0);
    CGFloat statWidth = (card.bounds.size.width - 36.0) / 3.0;
    for (NSInteger i = 0; i < 3; i++) {
        [card viewWithTag:107 + i].frame = CGRectMake(18.0 + statWidth * i, 132.0, statWidth, 42.0);
    }
    [card viewWithTag:106].frame = CGRectMake(18.0, 184.0, card.bounds.size.width - 36.0, 40.0);
}

- (void)updateStatusText
{
    NSInteger totalVotes = 0;
    for (CYCommunityVoteProposal *proposal in self.proposals) totalVotes += proposal.voteCount;
    self.candidateStatLabel.text = [NSString stringWithFormat:@"%ld\nCandidates", (long)self.proposals.count];
    self.voteStatLabel.text = [NSString stringWithFormat:@"%ld\nThumbs up", (long)totalVotes];
    self.pickedStatLabel.text = [NSString stringWithFormat:@"%ld\nShortlisted", (long)self.localSelections.count];
    if (self.loading) {
        self.statusLabel.text = @"Refreshing verified totals…";
        self.statusLabel.textColor = UIColor.secondaryLabelColor;
    } else if (self.showingRemoteResults) {
        self.statusLabel.text = @"Verified GitHub ranking is live";
        self.statusLabel.textColor = UIColor.systemGreenColor;
    } else {
        self.statusLabel.text = @"Offline shortlist; selections stay on this device";
        self.statusLabel.textColor = CYAccentColor();
    }
}

- (void)refreshCommunityResults
{
    if (self.loading) return;
    self.loading = YES;
    [self updateStatusText];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kCommunityVotesAPI]];
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    request.timeoutInterval = 15.0;
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"Infern0-Community-Votes" forHTTPHeaderField:@"User-Agent"];

    __weak typeof(self) weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        NSArray *json = nil;
        if (!error && http.statusCode >= 200 && http.statusCode < 300 && data.length > 0) {
            id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([object isKindOfClass:NSArray.class]) json = object;
        }
        NSMutableArray<CYCommunityVoteProposal *> *remote = [NSMutableArray array];
        for (NSDictionary *issue in json ?: @[]) {
            if (![issue isKindOfClass:NSDictionary.class] || issue[@"pull_request"]) continue;
            NSString *title = [issue[@"title"] isKindOfClass:NSString.class] ? issue[@"title"] : @"Untitled proposal";
            if (![title hasPrefix:@"[Tweak Vote]"]) continue;
            NSString *body = [issue[@"body"] isKindOfClass:NSString.class] ? issue[@"body"] : @"Community tweak proposal";
            NSString *summary = community_issue_summary(body);
            NSDictionary *reactions = [issue[@"reactions"] isKindOfClass:NSDictionary.class] ? issue[@"reactions"] : nil;
            CYCommunityVoteProposal *proposal = [[CYCommunityVoteProposal alloc] init];
            proposal.identifier = [NSString stringWithFormat:@"github-%@", issue[@"number"] ?: @0];
            proposal.name = [title stringByReplacingOccurrencesOfString:@"[Tweak Vote] " withString:@""];
            proposal.summary = summary;
            proposal.githubURL = [issue[@"html_url"] isKindOfClass:NSString.class] ? issue[@"html_url"] : nil;
            proposal.voteCount = [reactions[@"+1"] integerValue];
            proposal.remote = proposal.githubURL.length > 0;
            [remote addObject:proposal];
        }
        [remote sortUsingComparator:^NSComparisonResult(CYCommunityVoteProposal *a, CYCommunityVoteProposal *b) {
            if (a.voteCount != b.voteCount) return a.voteCount > b.voteCount ? NSOrderedAscending : NSOrderedDescending;
            return [a.name localizedCaseInsensitiveCompare:b.name];
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            CommunityVotesViewController *self = weakSelf;
            if (!self) return;
            self.loading = NO;
            [self.voteRefreshControl endRefreshing];
            if (remote.count > 0) {
                self.proposals = remote;
                self.showingRemoteResults = YES;
            } else {
                self.proposals = [self builtInProposals];
                self.showingRemoteResults = NO;
            }
            [self updateStatusText];
            [self.tableView reloadData];
        });
    }] resume];
}

- (void)persistLocalSelections
{
    NSArray *sorted = [[self.localSelections allObjects] sortedArrayUsingSelector:@selector(compare:)];
    [[NSUserDefaults standardUserDefaults] setObject:sorted forKey:kLocalVotesDefaultsKey];
}

- (void)openURLString:(NSString *)string
{
    NSURL *url = [NSURL URLWithString:string];
    if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)openVotingHub { [self openURLString:kCommunityVotesHub]; }
- (void)suggestTweak { [self openURLString:kCommunityVoteIdeaURL]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 0 ? (NSInteger)self.proposals.count : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return section == 0 ? (self.showingRemoteResults ? @"Community Ranking" : @"Your Shortlist") : @"Shape the Roadmap";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section != 0) return nil;
    return self.showingRemoteResults
        ? @"Totals come from GitHub thumbs-up reactions. Open any candidate to add yours with your GitHub account."
        : @"Local picks are a private shortlist until the repository voting hub is enabled. Pull down to retry community sync.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 1) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SuggestCell"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SuggestCell"];
        cell.textLabel.text = @"Suggest a New Tweak";
        cell.textLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
        cell.detailTextLabel.text = @"Describe what it should do and why it fits Infern0.";
        cell.imageView.image = [UIImage systemImageNamed:@"lightbulb.fill"];
        cell.imageView.tintColor = CYAccentColor();
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    CYCommunityVoteProposal *proposal = self.proposals[indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"VoteCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"VoteCell"];
    BOOL selected = [self.localSelections containsObject:proposal.identifier];
    cell.textLabel.text = proposal.name;
    cell.textLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    cell.textLabel.numberOfLines = 1;
    cell.detailTextLabel.text = proposal.summary;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 3;
    cell.imageView.image = CYIconBadgeImage(selected ? @"checkmark" : @"sparkles",
                                            selected ? UIColor.systemGreenColor : CYSpectrumColor((NSUInteger)indexPath.row),
                                            38.0);

    UIButtonConfiguration *voteConfig = proposal.remote
        ? [UIButtonConfiguration tintedButtonConfiguration]
        : (selected ? [UIButtonConfiguration filledButtonConfiguration]
                    : [UIButtonConfiguration tintedButtonConfiguration]);
    voteConfig.image = [UIImage systemImageNamed:selected ? @"checkmark" : @"hand.thumbsup.fill"];
    voteConfig.title = proposal.remote ? [NSString stringWithFormat:@"%ld", (long)proposal.voteCount] : nil;
    voteConfig.imagePadding = proposal.remote ? 4.0 : 0.0;
    voteConfig.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    voteConfig.baseForegroundColor = selected ? UIColor.whiteColor : CYAccentColor();
    if (selected) voteConfig.baseBackgroundColor = UIColor.systemGreenColor;
    UIButton *voteIcon = [UIButton buttonWithConfiguration:voteConfig primaryAction:nil];
    voteIcon.userInteractionEnabled = NO;
    voteIcon.accessibilityLabel = proposal.remote
        ? [NSString stringWithFormat:@"%ld GitHub thumbs up", (long)proposal.voteCount]
        : (selected ? @"Remove from shortlist" : @"Add to shortlist");
    cell.accessoryView = voteIcon;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CYSelectionHaptic();
    if (indexPath.section == 1) {
        [self suggestTweak];
        return;
    }

    CYCommunityVoteProposal *proposal = self.proposals[indexPath.row];
    if (proposal.remote && proposal.githubURL.length) {
        [self openURLString:proposal.githubURL];
        return;
    }
    if ([self.localSelections containsObject:proposal.identifier]) [self.localSelections removeObject:proposal.identifier];
    else [self.localSelections addObject:proposal.identifier];
    [self persistLocalSelections];
    [self updateStatusText];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

@end
