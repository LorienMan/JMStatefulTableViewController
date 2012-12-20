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

// Loading

- (void) _loadFirstPage;
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

- (void) loadNewer {
    if([self _totalNumberOfRows] == 0) {
        [self _loadFirstPage];
    } else {
        [self _loadFromPullToRefresh];
    }
}

- (void) _loadFirstPage {
    if(self.statefulState == JMStatefulTableViewControllerStateInitialLoading || [self _totalNumberOfRows] > 0) return;

    self.statefulState = JMStatefulTableViewControllerStateInitialLoading;

    // For initial loading disable inf scrolling and pull to refresh
    self.tableView.showsInfiniteScrolling = NO;
    self.tableView.showsPullToRefresh = NO;

    [self.tableView reloadData];

    [self.statefulDelegate statefulTableViewControllerWillBeginInitialLoading:self completionBlock:^{
        [self.tableView reloadData]; // We have to call reloadData before we call _totalNumberOfRows otherwise the new count (after loading) won't be accurately reflected.

        if([self _totalNumberOfRows] > 0) {
            self.statefulState = JMStatefulTableViewControllerStateIdle;
        } else {
            self.statefulState = JMStatefulTableViewControllerStateEmpty;
        }

        [self updateControlsStatuses];
    } failure:^(NSError *error) {
        self.statefulState = JMStatefulTableViewControllerError;
    }];
}
- (void) _loadNextPage {
    if(self.statefulState == JMStatefulTableViewControllerStateLoadingNextPage) return;

    if([self.statefulDelegate statefulTableViewControllerShouldBeginLoadingNextPage:self]) {
        self.tableView.showsInfiniteScrolling = YES;

        self.statefulState = JMStatefulTableViewControllerStateLoadingNextPage;

        [self.statefulDelegate statefulTableViewControllerWillBeginLoadingNextPage:self completionBlock:^{
            [self.tableView reloadData];

            if([self _totalNumberOfRows] > 0) {
                self.statefulState = JMStatefulTableViewControllerStateIdle;
            } else {
                self.statefulState = JMStatefulTableViewControllerStateEmpty;
            }

            [self updateControlsStatuses];
            [self _infiniteScrollingFinishedLoading];
        } failure:^(NSError *error) {
            //TODO What should we do here?
            self.statefulState = JMStatefulTableViewControllerStateIdle;
            [self _infiniteScrollingFinishedLoading];
        }];
    } else {
        self.tableView.showsInfiniteScrolling = NO;
    }
}

- (void) _loadFromPullToRefresh {
    if(self.statefulState == JMStatefulTableViewControllerStateLoadingFromPullToRefresh) return;

    self.statefulState = JMStatefulTableViewControllerStateLoadingFromPullToRefresh;

    [self.statefulDelegate statefulTableViewControllerWillBeginLoadingFromPullToRefresh:self completionBlock:^(NSArray *indexPaths) {
        if([indexPaths count] > 0) {
            CGFloat totalHeights = [self _cumulativeHeightForCellsAtIndexPaths:indexPaths];

            //Offset by the height fo the pull to refresh view when it's expanded:
            [self.tableView setContentInset:UIEdgeInsetsMake(0.0f, 0.0f, 0.0f, 0.0f)];
            [self.tableView reloadData];

            if(self.tableView.contentOffset.y == 0) {
                self.tableView.contentOffset = CGPointMake(0, (self.tableView.contentOffset.y + totalHeights) - 60.0);
            } else {
                self.tableView.contentOffset = CGPointMake(0, (self.tableView.contentOffset.y + totalHeights));
            }
        }

        if([self _totalNumberOfRows] > 0) {
            self.statefulState = JMStatefulTableViewControllerStateIdle;
        } else {
            self.statefulState = JMStatefulTableViewControllerStateEmpty;
        }

        [self updateControlsStatuses];
        [self _pullToRefreshFinishedLoading];
    } failure:^(NSError *error) {
        //TODO: What should we do here?
        self.statefulState = JMStatefulTableViewControllerStateIdle;
        [self _pullToRefreshFinishedLoading];
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
            self.tableView.backgroundView = nil;
            self.tableView.scrollEnabled = YES;
            self.tableView.tableHeaderView.hidden = NO;
            self.tableView.tableFooterView.hidden = NO;
            [self.tableView reloadData];

            break;

        case JMStatefulTableViewControllerStateInitialLoading:
            self.tableView.backgroundView = self.loadingView;
            self.tableView.scrollEnabled = NO;
            self.tableView.tableHeaderView.hidden = YES;
            self.tableView.tableFooterView.hidden = YES;
            [self.tableView reloadData];

            break;

        case JMStatefulTableViewControllerStateEmpty:
            self.tableView.backgroundView = self.emptyView;
            self.tableView.scrollEnabled = NO;
            self.tableView.tableHeaderView.hidden = YES;
            self.tableView.tableFooterView.hidden = YES;
            [self.tableView reloadData];

        case JMStatefulTableViewControllerStateLoadingNextPage:
            // TODO
            break;

        case JMStatefulTableViewControllerStateLoadingFromPullToRefresh:
            // TODO
            break;

        case JMStatefulTableViewControllerError:
            self.tableView.backgroundView = self.errorView;
            self.tableView.scrollEnabled = NO;
            self.tableView.tableHeaderView.hidden = YES;
            self.tableView.tableFooterView.hidden = YES;
            [self.tableView reloadData];
            break;

        default:
            break;
    }

    if([self.statefulDelegate respondsToSelector:@selector(statefulTableViewController:didTransitionToState:)]) {
        [self.statefulDelegate statefulTableViewController:self didTransitionToState:statefulState];
    }
}

- (void)setEmptyView:(UIView *)emptyView {
    if (_emptyView && self.tableView.backgroundView == _emptyView)
        self.tableView.backgroundView = emptyView;
    _emptyView = emptyView;
}

- (void)setLoadingView:(UIView *)loadingView {
    if (_loadingView && self.tableView.backgroundView == _loadingView)
        self.tableView.backgroundView = loadingView;
    _loadingView = loadingView;
}

- (void)setErrorView:(UIView *)errorView {
    if (_errorView && self.tableView.backgroundView == _errorView)
        self.tableView.backgroundView = errorView;
    _errorView = errorView;
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
    [self _loadFirstPage];

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