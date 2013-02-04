//
//  JMStatefulTableViewControllerViewController.m
//  JMStatefulTableViewControllerDemo
//
//  Created by Jake Marsh on 5/3/12.
//  Copyright (c) 2012 Jake Marsh. All rights reserved.
//

#import "JMStatefulTableViewController.h"
#import "SVInfiniteScrollingView.h"

@interface JMStatefulTableViewController ()

@property (nonatomic, assign) BOOL isCountingRows;
@property (nonatomic, assign) BOOL hasAddedPullToRefreshControl;
@property (nonatomic, assign) BOOL hasAddedInfiniteScrollingControl;
@property (nonatomic, strong) UIView *backgroundView;

// Loading

- (void) _loadFirstPage:(BOOL)force;
- (void) _loadNextPage;

- (void) _loadFromPullToRefresh;

// Table View Cells & NSIndexPaths
- (NSInteger) _totalNumberOfRows;
- (CGFloat) _cumulativeHeightForCellsAtIndexPaths:(NSArray *)indexPaths;

@end

#define TABLE_TOP_MAX_OFFSET 350
typedef enum {
    TablePositionBottom = 0,
    TablePositionTop
} TablePosition;

@implementation JMStatefulTableViewController {
    BOOL observing;
    TablePosition tablePosition;
    UIView *_backgroundViewContainer;
    void (^successBlock)();
    void (^failureBlock)(NSError *error);
}
@synthesize pullToRefreshView;
@synthesize infiniteScrollingView;
@synthesize tryToUseStandardPullToRefresh;

- (id) initWithStyle:(UITableViewStyle)style {
    self = [super initWithStyle:style];
    if (!self) return nil;

    _statefulState = JMStatefulTableViewControllerStateIdle;
    self.statefulDelegate = self;

    return self;
}

- (void) dealloc {
    [self stopObserving];
    self.statefulDelegate = nil;
    [self.tableView removePullToRefresh];
    [self.tableView removeInfiniteScrolling];
}

#pragma mark - Loading Methods

- (void) reloadTable {
    [self reloadTableCompletionBlock:nil failureBlock:nil];
}

- (void) loadNewer {
    [self loadNewerCompletionBlock:nil failureBlock:nil];
}

- (void) loadNextPage {
    [self loadNextPageCompletionBlock:nil failureBlock:nil];
}

- (void)reloadTableCompletionBlock:(void (^)())success failureBlock:(void (^)(NSError *error))failure {
    successBlock = [success copy];
    failureBlock = [failure copy];
    [self _loadFirstPage:YES];
}

- (void)loadNewerCompletionBlock:(void (^)())success failureBlock:(void (^)(NSError *error))failure {
    successBlock = [success copy];
    failureBlock = [failure copy];
    if([self _totalNumberOfRows] == 0) {
        [self _loadFirstPage:NO];
    } else {
        [self _loadFromPullToRefresh];
    }
}

- (void)loadNextPageCompletionBlock:(void (^)())success failureBlock:(void (^)(NSError *error))failure {
    successBlock = [success copy];
    failureBlock = [failure copy];
    [self _loadNextPage];
}

- (void) _loadFirstPage:(BOOL)force {
    if(!force && (self.statefulState == JMStatefulTableViewControllerStateInitialLoading || [self _totalNumberOfRows] > 0)) return;

    if([self _totalNumberOfRows] > 0) {
        self.statefulState = JMStatefulTableViewControllerStateIdle;
    } else {
        self.statefulState = JMStatefulTableViewControllerStateInitialLoading;
    }

    [self.tableView reloadData];
    [self updateControlsStatuses];

    __weak JMStatefulTableViewController *safeSelf = self;
    [self.statefulDelegate statefulTableViewControllerWillBeginInitialLoading:self completionBlock:^{
        [safeSelf.tableView reloadData]; // We have to call reloadData before we call _totalNumberOfRows otherwise the new count (after loading) won't be accurately reflected.

        if([safeSelf _totalNumberOfRows] > 0) {
            safeSelf.statefulState = JMStatefulTableViewControllerStateIdle;
        } else {
            safeSelf.statefulState = JMStatefulTableViewControllerStateEmpty;
        }

        [safeSelf updateControlsStatuses];
        // Make attempt to load previous data
        tablePosition = TablePositionBottom;
        [self checkToLoadPreviousData:self.tableView.contentOffset];

        if (successBlock)
            successBlock();
        [self _clearBlocks];
    } failure:^(NSError *error) {
        safeSelf.statefulState = JMStatefulTableViewControllerError;

        if (failureBlock)
            failureBlock(error);
        [self _clearBlocks];
    }];
}

- (void) _loadNextPage {
    if(self.statefulState == JMStatefulTableViewControllerStateLoadingNextPage) return;

    if([self.statefulDelegate statefulTableViewControllerShouldBeginLoadingNextPage:self]) {

        if([self _totalNumberOfRows] > 0) {
            self.statefulState = JMStatefulTableViewControllerStateLoadingNextPage;
            self.tableView.showsInfiniteScrolling = YES;
        } else {
            self.statefulState = JMStatefulTableViewControllerStateInitialLoading;
            self.tableView.showsInfiniteScrolling = NO;
        }

        __weak JMStatefulTableViewController *safeSelf = self;
        [self.statefulDelegate statefulTableViewControllerWillBeginLoadingNextPage:self completionBlock:^{
            [safeSelf.tableView reloadData];

            if([safeSelf _totalNumberOfRows] > 0) {
                safeSelf.statefulState = JMStatefulTableViewControllerStateIdle;
            } else {
                safeSelf.statefulState = JMStatefulTableViewControllerStateEmpty;
            }

            [safeSelf _infiniteScrollingFinishedLoading];
            [safeSelf updateControlsStatuses];

            if (successBlock)
                successBlock();
            [self _clearBlocks];
        } failure:^(NSError *error) {
            //TODO What should we do here?
            if([safeSelf _totalNumberOfRows] > 0) {
                safeSelf.statefulState = JMStatefulTableViewControllerStateIdle;
            } else {
                safeSelf.statefulState = JMStatefulTableViewControllerError;
            }
            [safeSelf _infiniteScrollingFinishedLoading];
            [safeSelf updateControlsStatuses];

            if (failureBlock)
                failureBlock(error);
            [self _clearBlocks];
        }];
    } else {
        self.tableView.showsInfiniteScrolling = NO;
    }
}

- (void) _loadFromPullToRefresh {
    if(self.statefulState == JMStatefulTableViewControllerStateLoadingFromPullToRefresh) return;

    self.statefulState = JMStatefulTableViewControllerStateLoadingFromPullToRefresh;

    __weak JMStatefulTableViewController *safeSelf = self;
    [self.statefulDelegate statefulTableViewControllerWillBeginLoadingFromPullToRefresh:self completionBlock:^(NSArray *indexPaths) {
        if([indexPaths count] > 0) {
            CGFloat totalHeights = [safeSelf _cumulativeHeightForCellsAtIndexPaths:indexPaths];

            //Offset by the height fo the pull to refresh view when it's expanded:
            [safeSelf.tableView setContentInset:UIEdgeInsetsMake(0.0f, 0.0f, 0.0f, 0.0f)];
            [safeSelf.tableView reloadData];

            if(safeSelf.tableView.contentOffset.y == 0) {
                safeSelf.tableView.contentOffset = CGPointMake(0, (safeSelf.tableView.contentOffset.y + totalHeights) - 60.0);
            } else {
                safeSelf.tableView.contentOffset = CGPointMake(0, (safeSelf.tableView.contentOffset.y + totalHeights));
            }
        } else {
            [safeSelf.tableView reloadData];
        }

        if([safeSelf _totalNumberOfRows] > 0) {
            safeSelf.statefulState = JMStatefulTableViewControllerStateIdle;
        } else {
            safeSelf.statefulState = JMStatefulTableViewControllerStateEmpty;
        }

        [safeSelf _pullToRefreshFinishedLoading];
        [safeSelf updateControlsStatuses];

        if (successBlock)
            successBlock();
        [self _clearBlocks];
    } failure:^(NSError *error) {
        //TODO: What should we do here?
        if([safeSelf _totalNumberOfRows] > 0) {
            safeSelf.statefulState = JMStatefulTableViewControllerStateIdle;
        } else {
            safeSelf.statefulState = JMStatefulTableViewControllerError;
        }
        [safeSelf _pullToRefreshFinishedLoading];
        [safeSelf updateControlsStatuses];

        if (failureBlock)
            failureBlock(error);
        [self _clearBlocks];
    }];
}

- (void) _loadPreviousPage {
    __weak JMStatefulTableViewController *safeSelf = self;
    [self.statefulDelegate statefulTableViewControllerWillBeginLoadingPreviousPage:self completionBlock:^{
        CGSize contentSize = self.tableView.contentSize;
        CGPoint contentOffset = self.tableView.contentOffset;
        [safeSelf.tableView reloadData];
        tablePosition = TablePositionBottom;
        CGSize newContentSize = self.tableView.contentSize;

        if (newContentSize.height > self.tableView.bounds.size.height) {
            CGFloat dy = newContentSize.height - contentSize.height;
            contentOffset.y += dy;
            contentOffset.y = MIN(contentOffset.y, newContentSize.height - self.tableView.bounds.size.height);
            self.tableView.contentOffset = contentOffset;
        }

        if([safeSelf _totalNumberOfRows] > 0) {
            safeSelf.statefulState = JMStatefulTableViewControllerStateIdle;
        } else {
            safeSelf.statefulState = JMStatefulTableViewControllerStateEmpty;
        }

        [self checkToLoadPreviousData:self.tableView.contentOffset];
    } failure:^(NSError *error) {
        tablePosition = TablePositionBottom;
    }];
}

- (void)updateControlsStatuses {
    __weak JMStatefulTableViewController *safeSelf = self;

    BOOL shouldPullToRefresh = YES;
    if([self.statefulDelegate respondsToSelector:@selector(statefulTableViewControllerShouldPullToRefresh:)]) {
        shouldPullToRefresh = [self.statefulDelegate statefulTableViewControllerShouldPullToRefresh:self];
    }

    if(!self.hasAddedPullToRefreshControl && shouldPullToRefresh) {
       if(tryToUseStandardPullToRefresh && [self respondsToSelector:@selector(refreshControl)] && !self.pullToRefreshView) {
            self.refreshControl = [[UIRefreshControl alloc] init];
            [self.refreshControl addTarget:self action:@selector(_loadFromPullToRefresh) forControlEvents:UIControlEventValueChanged];
        } else {
            [self.tableView addPullToRefreshWithActionHandler:^{
                [safeSelf _loadFromPullToRefresh];
            } pullToRefreshView:pullToRefreshView];
        }

        self.hasAddedPullToRefreshControl = YES;
    }

    BOOL shouldInfinitelyScroll = YES;
    if([self.statefulDelegate respondsToSelector:@selector(statefulTableViewControllerShouldInfinitelyScroll:)]) {
        shouldInfinitelyScroll = [self.statefulDelegate statefulTableViewControllerShouldInfinitelyScroll:self];
    }

    if (!self.hasAddedInfiniteScrollingControl && shouldInfinitelyScroll) {
        [self.tableView addInfiniteScrollingWithActionHandler:^{
            [safeSelf _loadNextPage];
        } infiniteScrollingView:infiniteScrollingView];
        self.hasAddedInfiniteScrollingControl = YES;
    }

    self.tableView.showsPullToRefresh = shouldPullToRefresh;
    self.tableView.showsInfiniteScrolling = self.statefulState == JMStatefulTableViewControllerStateInitialLoading ||
                                            self.statefulState == JMStatefulTableViewControllerError ||
                                            self.statefulState == JMStatefulTableViewControllerStateEmpty  ? NO : shouldInfinitelyScroll;

    if (self.tableView.showsPullToRefresh)
        [self.tableView updatePullToRefresh];

    if (self.tableView.showsInfiniteScrolling)
        [self.tableView updateInfiniteScrolling];
}

- (void) _clearBlocks {
    successBlock = nil;
    failureBlock = nil;
}

#pragma mark - Table View Cells & NSIndexPaths

- (NSInteger) _totalNumberOfRows {
    self.isCountingRows = YES;

    NSInteger numberOfRows = 0;

    NSInteger numberOfSections = [self.tableView.dataSource numberOfSectionsInTableView:self.tableView];
    for(NSInteger i = 0; i < numberOfSections; i++) {
        numberOfRows += [self.tableView.dataSource tableView:self.tableView numberOfRowsInSection:i];
    }

    self.isCountingRows = NO;

    return numberOfRows;
}
- (CGFloat) _cumulativeHeightForCellsAtIndexPaths:(NSArray *)indexPaths {
    if(!indexPaths) return 0.0;

    CGFloat totalHeight = 0.0;

    for(NSIndexPath *indexPath in indexPaths) {
        totalHeight += [self tableView:self.tableView heightForRowAtIndexPath:indexPath];
    }

    return totalHeight;
}

- (void) _infiniteScrollingFinishedLoading {
    [self.tableView.infiniteScrollingControl loadingCompleted];
}

- (void) _pullToRefreshFinishedLoading {
    [self.tableView.pullToRefreshControl loadingCompleted];
    if([self respondsToSelector:@selector(refreshControl)]) {
        [self.refreshControl endRefreshing];
    }
}

#pragma mark - Setter Overrides

- (void) setStatefulState:(JMStatefulTableViewControllerState)statefulState {
    if([self.statefulDelegate respondsToSelector:@selector(statefulTableViewController:willTransitionToState:)]) {
        [self.statefulDelegate statefulTableViewController:self willTransitionToState:statefulState];
    }

    _statefulState = statefulState;

    switch (_statefulState) {
        case JMStatefulTableViewControllerStateIdle:
            self.backgroundView = nil;
            self.tableView.scrollEnabled = YES;
            self.tableView.tableHeaderView.hidden = NO;
            self.tableView.tableFooterView.hidden = NO;

            break;

        case JMStatefulTableViewControllerStateInitialLoading:
            self.backgroundView = self.loadingView;
            self.tableView.scrollEnabled = NO;
            self.tableView.tableHeaderView.hidden = YES;
            self.tableView.tableFooterView.hidden = YES;

            break;

        case JMStatefulTableViewControllerStateEmpty:
            self.backgroundView = self.emptyView;
            self.tableView.scrollEnabled = NO;
            self.tableView.tableHeaderView.hidden = YES;
            self.tableView.tableFooterView.hidden = YES;

        case JMStatefulTableViewControllerStateLoadingNextPage:
            // TODO
            break;

        case JMStatefulTableViewControllerStateLoadingFromPullToRefresh:
            // TODO
            break;

        case JMStatefulTableViewControllerError:
            self.backgroundView = self.errorView;
            self.tableView.scrollEnabled = NO;
            self.tableView.tableHeaderView.hidden = YES;
            self.tableView.tableFooterView.hidden = YES;
            break;

        default:
            break;
    }

    if([self.statefulDelegate respondsToSelector:@selector(statefulTableViewController:didTransitionToState:)]) {
        [self.statefulDelegate statefulTableViewController:self didTransitionToState:statefulState];
    }
}

- (void)setEmptyView:(UIView *)emptyView {
    BOOL show = _emptyView && self.backgroundView == _emptyView;
    [_emptyView removeFromSuperview];
    _emptyView = emptyView;

    if (_emptyView)
        [_backgroundViewContainer addSubview:_emptyView];

    _emptyView.hidden = YES;
    if (show)
        self.backgroundView = _emptyView;
}

- (void)setLoadingView:(UIView *)loadingView {
    BOOL show = _loadingView && self.backgroundView == _loadingView;
    [_loadingView removeFromSuperview];
    _loadingView = loadingView;

    if (_loadingView)
        [_backgroundViewContainer addSubview:_loadingView];

    _loadingView.hidden = YES;
    if (show)
        self.backgroundView = _loadingView;
}

- (void)setErrorView:(UIView *)errorView {
    BOOL show = _errorView && self.backgroundView == _errorView;
    [_errorView removeFromSuperview];
    _errorView = errorView;

    if (_errorView)
        [_backgroundViewContainer addSubview:_errorView];

    _errorView.hidden = YES;
    if (show)
        self.backgroundView = _errorView;
}

- (void)setBackgroundView:(UIView *)backgroundView {
    _backgroundView.hidden = YES;
    _backgroundView = backgroundView;
    _backgroundView.hidden = NO;

    _backgroundViewContainer.hidden = _backgroundView == nil;
}

- (void)setPullToRefreshView:(UIView <SVPullToRefreshViewProtocol> *)_pullToRefreshView {
    pullToRefreshView = _pullToRefreshView;
    self.tableView.pullToRefreshControl.pullToRefreshView = _pullToRefreshView;
}

- (void)setInfiniteScrollingView:(UIView <SVInfiniteScrollingViewProtocol> *)_infiniteScrollingView {
    infiniteScrollingView = _infiniteScrollingView;
    self.tableView.infiniteScrollingControl.infiniteScrollingView = _infiniteScrollingView;
}

#pragma mark - View Lifecycle

- (void) loadView {
    [super loadView];

    self.loadingView = [[JMStatefulTableViewLoadingView alloc] initWithFrame:self.tableView.bounds];

    self.emptyView = [[JMStatefulTableViewEmptyView alloc] initWithFrame:self.tableView.bounds];

    self.errorView = [[JMStatefulTableViewErrorView alloc] initWithFrame:self.tableView.bounds];

    _backgroundViewContainer = [[UIView alloc] initWithFrame:self.tableView.bounds];
    _backgroundViewContainer.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    _backgroundViewContainer.backgroundColor = [UIColor clearColor];
    [self.tableView addSubview:_backgroundViewContainer];
    [self.tableView sendSubviewToBack:_backgroundViewContainer];
}

- (void) viewDidLoad {
    [super viewDidLoad];
    [self startObserving];
}

- (void) viewDidUnload {
    [super viewDidUnload];

    [self stopObserving];
    self.loadingView = nil;
    self.emptyView = nil;
    self.errorView = nil;
}

- (void) viewWillAppear:(BOOL)animated {
    [self _loadFirstPage:NO];

    [super viewWillAppear:animated];
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

#pragma mark Content offset observing

- (void)startObserving {
    if (observing)
        return;

    observing = YES;
    [self.tableView addObserver:self forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial context:NULL];
}

- (void)stopObserving {
    if (!observing)
        return;

    observing = NO;
    [self.tableView removeObserver:self forKeyPath:@"contentOffset"];
}

- (void)contentOffsetChanged:(CGPoint)contentOffset {
    if ((!self.tableView.isDecelerating && !self.tableView.tracking) || (self.statefulState != JMStatefulTableViewControllerStateIdle && self.statefulState != JMStatefulTableViewControllerStateEmpty))
        return;

    [self checkToLoadPreviousData:contentOffset];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"contentOffset"]) {
        [self contentOffsetChanged:[[change valueForKey:NSKeyValueChangeNewKey] CGPointValue]];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)checkToLoadPreviousData:(CGPoint)contentOffset {
    TablePosition newPosition;
    CGRect headerFrame = self.tableView.tableHeaderView.frame;
    if (contentOffset.y <= headerFrame.origin.y + headerFrame.size.height + TABLE_TOP_MAX_OFFSET) {
        newPosition = TablePositionTop;
    } else {
        newPosition = TablePositionBottom;
    }

    if (newPosition != tablePosition && newPosition == TablePositionTop) {
        if ([self.statefulDelegate respondsToSelector:@selector(statefulTableViewControllerShouldLoadPreviousPage:)] &&
                [self.statefulDelegate statefulTableViewControllerShouldLoadPreviousPage:self]) {
            tablePosition = TablePositionTop;
            [self _loadPreviousPage];
        }
    }
}

#pragma mark - JMStatefulTableViewControllerDelegate

- (void) statefulTableViewControllerWillBeginInitialLoading:(JMStatefulTableViewController *)vc completionBlock:(void (^)())success failure:(void (^)(NSError *error))failure {
    NSAssert(NO, @"statefulTableViewControllerWillBeginInitialLoading:completionBlock:failure: is meant to be implementd by it's subclasses!");
}

- (void) statefulTableViewControllerWillBeginLoadingFromPullToRefresh:(JMStatefulTableViewController *)vc completionBlock:(void (^)(NSArray *indexPathsToInsert))success failure:(void (^)(NSError *error))failure {
    NSAssert(NO, @"statefulTableViewControllerWillBeginLoadingFromPullToRefresh:completionBlock:failure: is meant to be implementd by it's subclasses!");
}

- (void) statefulTableViewControllerWillBeginLoadingNextPage:(JMStatefulTableViewController *)vc completionBlock:(void (^)())success failure:(void (^)(NSError *))failure {
    NSAssert(NO, @"statefulTableViewControllerWillBeginLoadingNextPage:completionBlock:failure: is meant to be implementd by it's subclasses!");
}
- (BOOL) statefulTableViewControllerShouldBeginLoadingNextPage:(JMStatefulTableViewController *)vc {
    NSAssert(NO, @"statefulTableViewControllerShouldBeginLoadingNextPage is meant to be implementd by it's subclasses!");

    return NO;
}

@end