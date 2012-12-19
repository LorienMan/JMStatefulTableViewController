//
//  JMStatefulTableViewControllerViewController.m
//  JMStatefulTableViewControllerDemo
//
//  Created by Jake Marsh on 5/3/12.
//  Copyright (c) 2012 Jake Marsh. All rights reserved.
//

#import "JMStatefulTableViewController.h"

@interface JMStatefulTableViewController ()

@property (nonatomic, assign) BOOL isCountingRows;
@property (nonatomic, assign) BOOL hasAddedPullToRefreshControl;

// Loading

- (void) _loadFirstPage;
- (void) _loadNextPage;

- (void) _loadFromPullToRefresh;

// Table View Cells & NSIndexPaths
- (NSInteger) _totalNumberOfRows;
- (CGFloat) _cumulativeHeightForCellsAtIndexPaths:(NSArray *)indexPaths;

@end

@implementation JMStatefulTableViewController

- (id) initWithStyle:(UITableViewStyle)style {
    self = [super initWithStyle:style];
    if (!self) return nil;

    _statefulState = JMStatefulTableViewControllerStateIdle;
    self.statefulDelegate = self;

    return self;
}
- (void) dealloc {
    self.statefulDelegate = nil;
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

    [self.tableView reloadData];

    [self.statefulDelegate statefulTableViewControllerWillBeginInitialLoading:self completionBlock:^{
        [self.tableView reloadData]; // We have to call reloadData before we call _totalNumberOfRows otherwise the new count (after loading) won't be accurately reflected.

        if([self _totalNumberOfRows] > 0) {
            self.statefulState = JMStatefulTableViewControllerStateIdle;
        } else {
            self.statefulState = JMStatefulTableViewControllerStateEmpty;
        }
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

            if(![self.statefulDelegate statefulTableViewControllerShouldBeginLoadingNextPage:self]) {
                self.tableView.showsInfiniteScrolling = NO;
            };

            if([self _totalNumberOfRows] > 0) {
                self.statefulState = JMStatefulTableViewControllerStateIdle;
            } else {
                self.statefulState = JMStatefulTableViewControllerStateEmpty;
            }
        } failure:^(NSError *error) {
            //TODO What should we do here?
            self.statefulState = JMStatefulTableViewControllerStateIdle;
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

        if([self.statefulDelegate statefulTableViewControllerShouldBeginLoadingNextPage:self]) {
            self.tableView.showsInfiniteScrolling = YES;
        } else {
            self.tableView.showsInfiniteScrolling = NO;
        }

        self.statefulState = JMStatefulTableViewControllerStateIdle;
        [self _pullToRefreshFinishedLoading];
    } failure:^(NSError *error) {
        //TODO: What should we do here?

        self.statefulState = JMStatefulTableViewControllerStateIdle;
        [self _pullToRefreshFinishedLoading];
    }];
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

- (void) _pullToRefreshFinishedLoading {
    [self.tableView.pullToRefreshView stopAnimating];
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

#pragma mark - View Lifecycle

- (void) loadView {
    [super loadView];

    self.loadingView = [[JMStatefulTableViewLoadingView alloc] initWithFrame:self.tableView.bounds];
    self.loadingView.backgroundColor = [UIColor greenColor];

    self.emptyView = [[JMStatefulTableViewEmptyView alloc] initWithFrame:self.tableView.bounds];
    self.emptyView.backgroundColor = [UIColor yellowColor];

    self.errorView = [[JMStatefulTableViewErrorView alloc] initWithFrame:self.tableView.bounds];
    self.errorView.backgroundColor = [UIColor redColor];
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

    __block JMStatefulTableViewController *safeSelf = self;

    BOOL shouldPullToRefresh = YES;
    if([self.statefulDelegate respondsToSelector:@selector(statefulTableViewControllerShouldPullToRefresh:)]) {
        shouldPullToRefresh = [self.statefulDelegate statefulTableViewControllerShouldPullToRefresh:self];
    }

    // TODO: for iOS 6 make possible to use standart control
    if(!self.hasAddedPullToRefreshControl && shouldPullToRefresh) {
        if([self respondsToSelector:@selector(refreshControl)]) {
            self.refreshControl = [[UIRefreshControl alloc] init];
            [self.refreshControl addTarget:self action:@selector(_loadFromPullToRefresh) forControlEvents:UIControlEventValueChanged];
        } else {
            [self.tableView addPullToRefreshWithActionHandler:^{
                [safeSelf _loadFromPullToRefresh];
            }];
        }

        self.hasAddedPullToRefreshControl = YES;
    }

    BOOL shouldInfinitelyScroll = YES;
    if([self.statefulDelegate respondsToSelector:@selector(statefulTableViewControllerShouldInfinitelyScroll:)]) {
        shouldInfinitelyScroll = [self.statefulDelegate statefulTableViewControllerShouldInfinitelyScroll:self];
    }

    if (shouldInfinitelyScroll) {
        if(self.tableView.infiniteScrollingView == nil) {
            [self.tableView addInfiniteScrollingWithActionHandler:^{
                [safeSelf _loadNextPage];
            }];
            self.tableView.showsInfiniteScrolling = YES;
        }
    } else {
        self.tableView.showsInfiniteScrolling = NO;
    }

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