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

@implementation JMStatefulTableViewController
@synthesize pullToRefreshView;
@synthesize infiniteScrollingView;

- (id) initWithStyle:(UITableViewStyle)style {
    self = [super initWithStyle:style];
    if (!self) return nil;

    _statefulState = JMStatefulTableViewControllerStateIdle;
    self.statefulDelegate = self;

    return self;
}

- (void) dealloc {
    self.statefulDelegate = nil;
    [self.tableView removePullToRefresh];
    [self.tableView removeInfiniteScrolling];
}

#pragma mark - Loading Methods

- (void) reloadTable {
    [self _loadFirstPage:YES];
}

- (void) loadNewer {
    if([self _totalNumberOfRows] == 0) {
        [self _loadFirstPage:NO];
    } else {
        [self _loadFromPullToRefresh];
    }
}

- (void) _loadFirstPage:(BOOL)force {
    if(!force && (self.statefulState == JMStatefulTableViewControllerStateInitialLoading || [self _totalNumberOfRows] > 0)) return;
    
    [self.tableView reloadData];
    
    // For initial loading disable inf scrolling
    self.tableView.showsInfiniteScrolling = NO;
    self.tableView.showsPullToRefresh = NO;

    self.statefulState = JMStatefulTableViewControllerStateInitialLoading;

    __weak JMStatefulTableViewController *safeSelf = self;
    [self.statefulDelegate statefulTableViewControllerWillBeginInitialLoading:self completionBlock:^{
        [safeSelf.tableView reloadData]; // We have to call reloadData before we call _totalNumberOfRows otherwise the new count (after loading) won't be accurately reflected.

        if([safeSelf _totalNumberOfRows] > 0) {
            safeSelf.statefulState = JMStatefulTableViewControllerStateIdle;
        } else {
            safeSelf.statefulState = JMStatefulTableViewControllerStateEmpty;
        }

        [safeSelf updateControlsStatuses];
    } failure:^(NSError *error) {
        safeSelf.statefulState = JMStatefulTableViewControllerError;
    }];
}

- (void) _loadNextPage {
    if(self.statefulState == JMStatefulTableViewControllerStateLoadingNextPage) return;

    if([self.statefulDelegate statefulTableViewControllerShouldBeginLoadingNextPage:self]) {
        self.tableView.showsInfiniteScrolling = YES;

        self.statefulState = JMStatefulTableViewControllerStateLoadingNextPage;

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
        } failure:^(NSError *error) {
            //TODO What should we do here?
            safeSelf.statefulState = JMStatefulTableViewControllerStateIdle;
            [safeSelf _infiniteScrollingFinishedLoading];
            [safeSelf updateControlsStatuses];
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
    } failure:^(NSError *error) {
        //TODO: What should we do here?
        safeSelf.statefulState = JMStatefulTableViewControllerStateIdle;
        [safeSelf _pullToRefreshFinishedLoading];
        [safeSelf updateControlsStatuses];
    }];
}

- (void)updateControlsStatuses {
    __weak JMStatefulTableViewController *safeSelf = self;

    BOOL shouldPullToRefresh = YES;
    if([self.statefulDelegate respondsToSelector:@selector(statefulTableViewControllerShouldPullToRefresh:)]) {
        shouldPullToRefresh = [self.statefulDelegate statefulTableViewControllerShouldPullToRefresh:self];
    }

    if(!self.hasAddedPullToRefreshControl && shouldPullToRefresh) {
        if([self respondsToSelector:@selector(refreshControl)] && !self.pullToRefreshView) {
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
    self.tableView.showsInfiniteScrolling = shouldInfinitelyScroll;

    if (self.tableView.showsPullToRefresh)
        [self.tableView updatePullToRefresh];

    if (self.tableView.showsInfiniteScrolling)
        [self.tableView updateInfiniteScrolling];
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
    if (_emptyView && self.backgroundView == _emptyView)
        self.backgroundView = emptyView;
    _emptyView = emptyView;
}

- (void)setLoadingView:(UIView *)loadingView {
    if (_loadingView && self.backgroundView == _loadingView)
        self.backgroundView = loadingView;
    _loadingView = loadingView;
}

- (void)setErrorView:(UIView *)errorView {
    if (_errorView && self.backgroundView == _errorView)
        self.backgroundView = errorView;
    _errorView = errorView;
}

- (void)setBackgroundView:(UIView *)backgroundView {
    [_backgroundView removeFromSuperview];
    _backgroundView = backgroundView;
    [self.tableView insertSubview:_backgroundView atIndex:0];
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
}

- (void) viewDidLoad {
    [super viewDidLoad];
}
- (void) viewDidUnload {
    [super viewDidUnload];

    self.loadingView = nil;
    self.emptyView = nil;
    self.errorView = nil;
}

- (void) viewWillAppear:(BOOL)animated {
    [self _loadFirstPage:NO];

    // TODO: add handler to observe loading previous data

    [super viewWillAppear:animated];
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
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