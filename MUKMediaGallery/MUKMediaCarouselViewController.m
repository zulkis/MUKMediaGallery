#import "MUKMediaCarouselViewController.h"

#import "MUKMediaCarouselFullImageViewController.h"
#import "MUKMediaCarouselPlayerViewController.h"
#import "MUKMediaCarouselYouTubePlayerViewController.h"

#import "MUKMediaAttributesCache.h"
#import "MUKMediaCarouselFlowLayout.h"
#import "MUKMediaGalleryUtils.h"
#import <XCDYouTubeKit/XCDYouTubeKit.h>
#import <QuartzCore/QuartzCore.h>

#define DEBUG_YOUTUBE_EXTRACTION_ALWAYS_FAIL    0
#define DEBUG_LOAD_LOGGING                      0

@interface MUKMediaCarouselViewController () <MUKMediaCarouselItemViewControllerDelegate, MUKMediaCarouselFullImageViewControllerDelegate, MUKMediaCarouselPlayerViewControllerDelegate, MUKMediaCarouselYouTubePlayerViewControllerDelegate>
@property (nonatomic) MUKMediaAttributesCache *mediaAttributesCache;
@property (nonatomic) MUKMediaModelCache *imagesCache, *thumbnailImagesCache, *youTubeDecodedURLCache;
@property (nonatomic) NSMutableIndexSet *loadingImageIndexes, *loadingThumbnailImageIndexes;
@property (nonatomic) NSMutableDictionary *runningYouTubeExtractors;
@property (nonatomic) BOOL shouldReloadDataInViewWillAppear;
@property (nonatomic) NSMutableArray *pendingViewControllers;

@property (nonatomic, weak, readwrite) UIView *controlsView;
@property (nonatomic, strong) NSLayoutConstraint *controlsViewTopConstraint, *controlsViewBottomConstraint;

@end

const CGFloat MUKMediaControlsHeight = 60.f;

@implementation MUKMediaCarouselViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        CommonInitialization(self);
    }
    
    return self;
}

- (id)initWithTransitionStyle:(UIPageViewControllerTransitionStyle)style navigationOrientation:(UIPageViewControllerNavigationOrientation)navigationOrientation options:(NSDictionary *)options
{
    self = [super initWithTransitionStyle:style navigationOrientation:navigationOrientation options:options];
    if (self) {
        CommonInitialization(self);
    }
    
    return self;
}

- (id)init {
    return [self initWithTransitionStyle:UIPageViewControllerTransitionStyleScroll navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal options:@{ UIPageViewControllerOptionInterPageSpacingKey : @4.0f }];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    
    UIView *controlsView = [self newBottomAttachedControlsViewInSuperview:self.view];
    self.controlsView = controlsView;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    if (self.shouldReloadDataInViewWillAppear) {
        self.shouldReloadDataInViewWillAppear = NO;
        
        // Reload data after -viewDidDisappear has cancelled all loadings
        for (MUKMediaCarouselItemViewController *viewController in self.viewControllers)
        {
            // Load attributes
            MUKMediaAttributes *attributes = [self mediaAttributesForItemAtIndex:viewController.mediaIndex];
            [self configureItemViewController:viewController forMediaAttributes:attributes];
        } // for
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
    for (MUKMediaCarouselItemViewController *viewController in self.viewControllers)
    {
        [self cancelAllLoadingsForItemViewController:viewController];
        self.shouldReloadDataInViewWillAppear = YES;
    }
}

#pragma mark - Controls

- (UIView *)newBottomAttachedControlsViewInSuperview:(UIView *)superview {
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0,
                                                            0,
                                                            CGRectGetWidth(superview.frame),
                                                            MUKMediaControlsHeight)];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.backgroundColor = [UIColor colorWithWhite:245.f/255.f alpha:1.f]; //#F5F5F5
    [superview addSubview:view];
    
    UIView *borderView = [[UIView alloc] initWithFrame:CGRectMake(0,
                                                                  0,
                                                                  CGRectGetWidth(superview.frame),
                                                                  1)];
    borderView.backgroundColor = [UIColor colorWithWhite:216.f/255.f alpha:1.f]; //#D8D8D8
    [view addSubview:borderView];
    NSDictionary *viewsDict = NSDictionaryOfVariableBindings(borderView);
    NSArray *constraints = [NSLayoutConstraint constraintsWithVisualFormat:@"|-(0)-[borderView]-(0)-|" options:0 metrics:nil views:viewsDict];
    [view addConstraints:constraints];
    
    
    UIImage *captionImage =[MUKMediaGalleryUtils imageNamed:@"carouselItem_caption"];
    UIImage *deleteImage = [MUKMediaGalleryUtils imageNamed:@"carouselItem_delete"];
    
    UIButton *captionButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, captionImage.size.width, captionImage.size.height)];
    captionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [captionButton setImage:captionImage forState:UIControlStateNormal];
    captionButton.showsTouchWhenHighlighted = YES;
    [captionButton addTarget:self action:@selector(onCaptionButtonTap:) forControlEvents:UIControlEventTouchUpInside];
    
    UIButton *deleteButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, deleteImage.size.width, deleteImage.size.height)];
    deleteButton.translatesAutoresizingMaskIntoConstraints = NO;
    [deleteButton setImage:deleteImage forState:UIControlStateNormal];
    deleteButton.showsTouchWhenHighlighted = YES;
    [deleteButton addTarget:self action:@selector(onDeleteButtonTap:) forControlEvents:UIControlEventTouchUpInside];
    
    
    [view addSubview:captionButton];
    [view addSubview:deleteButton];
    
    viewsDict = NSDictionaryOfVariableBindings(view, captionButton, deleteButton);
    // Our controls view width must be == to superview width
    constraints = [NSLayoutConstraint constraintsWithVisualFormat:@"|-(0)-[view]-(0)-|" options:0 metrics:nil views:viewsDict];
    [superview addConstraints:constraints];
    
    constraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:[view(==controlsHeight)]" options:0 metrics:@{ @"controlsHeight" : @(MUKMediaControlsHeight) } views:viewsDict];
    [superview addConstraints:constraints];
    
    constraints = [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[captionButton(>=0)]-[deleteButton(==captionButton)]-|"
                                                          options:0
                                                          metrics:nil
                                                            views:viewsDict];
    [view addConstraints:constraints];
    
    constraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|[captionButton(==view)]|"
                                                          options:0
                                                          metrics:nil
                                                            views:viewsDict];
    [view addConstraints:constraints];
    
    constraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|[deleteButton(==view)]|"
                                                          options:0
                                                          metrics:nil
                                                            views:viewsDict];
    [view addConstraints:constraints];
    
    constraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-[captionButton(>=0)][deleteButton(==captionButton)]-|"
                                                          options:0
                                                          metrics:nil
                                                            views:viewsDict];
    
    return view;
}

- (void)onCaptionButtonTap:(UIButton *)sender {
    MUKMediaCarouselItemViewController *currentViewController = [self firstVisibleItemViewController];
    [self carouselItemViewControllerWantsEditCaption:currentViewController];
}

- (void)onDeleteButtonTap:(UIButton *)sender {
    MUKMediaCarouselItemViewController *currentViewController = [self firstVisibleItemViewController];
    [self carouselItemViewControllerWantsDeleteItem:currentViewController];
}

#pragma mark - Overrides

- (BOOL)prefersStatusBarHidden {
    return self.navigationController.isNavigationBarHidden;
}

#pragma mark - Methods

- (void)scrollToItemAtIndex:(NSInteger)idx animated:(BOOL)animated completion:(void (^)(BOOL finished))completionHandler
{
    MUKMediaCarouselItemViewController *itemViewController = [self newItemViewControllerForMediaAtIndex:idx];
    MUKMediaCarouselItemViewController *currentViewController = [self firstVisibleItemViewController];
    
    UIPageViewControllerNavigationDirection direction = UIPageViewControllerNavigationDirectionForward;
    if (currentViewController && currentViewController.mediaIndex > itemViewController.mediaIndex)
    {
        direction = UIPageViewControllerNavigationDirectionReverse;
    }
    
    // Load attributes & configure
    MUKMediaAttributes *attributes = [self mediaAttributesForItemAtIndex:idx];
    [self configureItemViewController:itemViewController forMediaAttributes:attributes];
    
    
    __block typeof(self) blocksafeSelf = self;
    self.view.userInteractionEnabled = NO;
    NSArray *viewControllers = @[itemViewController];
    [self setViewControllers:viewControllers direction:direction
                    animated:animated completion:^(BOOL finished) {
                        if(finished && animated)
                        {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [blocksafeSelf setViewControllers:viewControllers direction:direction animated:NO completion:NULL];// bug fix for uipageview controller
                            });
                        }
                        blocksafeSelf.view.userInteractionEnabled = YES;
                    }];
}

#pragma mark - Private

static void CommonInitialization(MUKMediaCarouselViewController *viewController)
{
    // <UIPageViewControllerDelegate, UIPageViewControllerDataSource>
    viewController.shouldCacheAttributes = YES;
    viewController.delegate = viewController;
    viewController.dataSource = viewController;
    
    if ([viewController respondsToSelector:@selector(setAutomaticallyAdjustsScrollViewInsets:)])
    {
        viewController.automaticallyAdjustsScrollViewInsets = NO;
    }
    else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        viewController.wantsFullScreenLayout = YES;
#pragma clang diagnostic pop
    }
    
    viewController.imagesCache = [[MUKMediaModelCache alloc] initWithCountLimit:2 cacheNulls:NO];
    viewController.thumbnailImagesCache = [[MUKMediaModelCache alloc] initWithCountLimit:7 cacheNulls:NO];
    viewController.mediaAttributesCache = [[MUKMediaAttributesCache alloc] initWithCountLimit:7 cacheNulls:YES];
    
    viewController.loadingImageIndexes = [[NSMutableIndexSet alloc] init];
    viewController.loadingThumbnailImageIndexes = [[NSMutableIndexSet alloc] init];
    
    viewController.youTubeDecodedURLCache = [[MUKMediaModelCache alloc] initWithCountLimit:7 cacheNulls:YES];
    viewController.runningYouTubeExtractors = [[NSMutableDictionary alloc] init];
}

- (void)cancelAllLoadingsForItemViewController:(MUKMediaCarouselItemViewController *)viewController
{
    [self cancelAllImageLoadingsForItemAtIndex:viewController.mediaIndex];
    [self cancelDecodingMovieURLFromYouTubeForItemAtIndex:viewController.mediaIndex];
    
    viewController = viewController ?: [self visibleItemViewControllerForMediaAtIndex:viewController.mediaIndex];
    
    // If it's a video player and there is no movie player presented full screen,
    // stop playback
    if ([viewController isKindOfClass:[MUKMediaCarouselPlayerViewController class]] &&
        !viewController.presentedViewController)
    {
        [self cancelMediaPlaybackInPlayerViewController:(MUKMediaCarouselPlayerViewController *)viewController];
    }
}

#pragma mark - Private — Item View Controllers

- (MUKMediaCarouselItemViewController *)newItemViewControllerForMediaAtIndex:(NSInteger)idx
{
    // Load attributes
    MUKMediaAttributes *attributes = [self mediaAttributesForItemAtIndex:idx];
    
    // Choose the most appropriate class based on media kind
    Class vcClass = [MUKMediaCarouselFullImageViewController class];
    
    if (attributes) {
        switch (attributes.kind) {
            case MUKMediaKindAudio:
            case MUKMediaKindVideo:
                vcClass = [MUKMediaCarouselPlayerViewController class];
                break;
                
            case MUKMediaKindYouTubeVideo:
                vcClass = [MUKMediaCarouselYouTubePlayerViewController class];
                break;
                
            default:
                break;
        }
    }
    
    // Allocate an instance
    MUKMediaCarouselItemViewController *viewController = [[vcClass alloc] initWithMediaIndex:idx];
    viewController.captionBottomOffset = MUKMediaControlsHeight;
    return viewController;
}

- (void)configureItemViewController:(MUKMediaCarouselItemViewController *)viewController forMediaAttributes:(MUKMediaAttributes *)attributes
{
    // Common configuration
    viewController.delegate = self;
    viewController.view.backgroundColor = self.view.backgroundColor;
    
    viewController.captionLabel.text = attributes.caption;
    if (![self areBarsHidden]) {
        [self updateUIConstraintsWhenHidden:NO animated:NO];
        [viewController setCaptionHidden:NO animated:NO completion:nil];
    }
    else {
        [self updateUIConstraintsWhenHidden:YES animated:NO];
        [viewController setCaptionHidden:YES animated:NO completion:nil];
    }
    
    // Specific configuration
    if ([viewController isKindOfClass:[MUKMediaCarouselFullImageViewController class]])
    {
        [self configureFullImageViewController:(MUKMediaCarouselFullImageViewController *)viewController forMediaAttributes:attributes];
    }
    else if ([viewController isKindOfClass:[MUKMediaCarouselPlayerViewController class]])
    {
        [self configurePlayerViewController:(MUKMediaCarouselPlayerViewController *)viewController forMediaAttributes:attributes];
    }
    else if ([viewController isKindOfClass:[MUKMediaCarouselYouTubePlayerViewController class]])
    {
        [self configureYouTubePlayerViewController:(MUKMediaCarouselYouTubePlayerViewController *)viewController forMediaAttributes:attributes];
    }
}

- (MUKMediaCarouselItemViewController *)visibleItemViewControllerForMediaAtIndex:(NSInteger)idx
{
    for (MUKMediaCarouselItemViewController *viewController in self.viewControllers)
    {
        if (viewController.mediaIndex == idx) {
            return viewController;
        }
    }
    
    return nil;
}

- (MUKMediaCarouselItemViewController *)pendingItemViewControllerForMediaAtIndex:(NSInteger)idx
{
    for (MUKMediaCarouselItemViewController *viewController in self.pendingViewControllers)
    {
        if (viewController.mediaIndex == idx) {
            return viewController;
        }
    }
    
    return nil;
}

#pragma mark - Private — Full Image View Controllers

- (void)configureFullImageViewController:(MUKMediaCarouselFullImageViewController *)viewController forMediaAttributes:(MUKMediaAttributes *)attributes
{
    MUKMediaImageKind foundImageKind = MUKMediaImageKindNone;
    UIImage *image = [self biggestCachedImageOrRequestLoadingForItemAtIndex:viewController.mediaIndex foundImageKind:&foundImageKind];
    [self setImage:image ofKind:foundImageKind inFullImageViewController:viewController];
}

- (void)setImage:(UIImage *)image ofKind:(MUKMediaImageKind)kind inFullImageViewController:(MUKMediaCarouselFullImageViewController *)viewController
{
    BOOL shouldShowActivityIndicator = (kind != MUKMediaImageKindFullSize);
    if (shouldShowActivityIndicator) {
        [viewController.activityIndicatorView startAnimating];
    }
    else {
        [viewController.activityIndicatorView stopAnimating];
    }
    
    [viewController setImage:image ofKind:kind];
}

- (BOOL)shouldSetLoadedImageOfKind:(MUKMediaImageKind)imageKind intoFullImageViewController:(MUKMediaCarouselFullImageViewController *)viewController
{
    if (!viewController) return NO;
    
    BOOL shouldSetImage = NO;
    
    // It's still visible or it will be visible
    if ([self isVisibleItemViewControllerForMediaAtIndex:viewController.mediaIndex] || [self isPendingItemViewControllerForMediaAtIndex:viewController.mediaIndex])
    {
        // Don't overwrite bigger images
        if (imageKind == MUKMediaImageKindThumbnail &&
            viewController.imageKind == MUKMediaImageKindFullSize)
        {
            shouldSetImage = NO;
        }
        else {
            shouldSetImage = YES;
        }
    }
    
    return shouldSetImage;
}

#pragma mark - Private — Player View Controllers

- (void)configurePlayerViewController:(MUKMediaCarouselPlayerViewController *)viewController forMediaAttributes:(MUKMediaAttributes *)attributes
{
    NSURL *mediaURL = [self.carouselDelegate carouselViewController:self mediaURLForItemAtIndex:viewController.mediaIndex];
    [self configurePlayerViewController:viewController mediaURL:mediaURL forMediaAttributes:attributes];
}

- (void)configurePlayerViewController:(MUKMediaCarouselPlayerViewController *)viewController mediaURL:(NSURL *)mediaURL forMediaAttributes:(MUKMediaAttributes *)attributes
{
    // Set media URL (this will create room for thumbnail)
    if (mediaURL) {
        [viewController setMediaURL:mediaURL];
    }
    
    // Nullify existing thumbnail
    viewController.thumbnailImageView.image = nil;
    
    // Try to load thumbnail to appeal user eye, from cache
    UIImage *thumbnail = [[self cacheForImageKind:MUKMediaImageKindThumbnail] objectAtIndex:viewController.mediaIndex isNull:NULL];
    
    // Thumbnail available: display it
    if (thumbnail) {
        [self setThumbnailImage:thumbnail stock:NO inPlayerViewController:viewController hideActivityIndicator:YES];
    }
    
    // Thumbnail unavailable: request to delegate
    else {
        // Show loading
        [viewController.activityIndicatorView startAnimating];
        
        // Request loading
        [self loadImageOfKind:MUKMediaImageKindThumbnail forItemAtIndex:viewController.mediaIndex inNextRunLoop:YES];
        
        // Use stock thumbnail in the meanwhile
        if (viewController.thumbnailImageView.image == nil) {
            thumbnail = [self stockThumbnailForMediaKind:attributes.kind];
            [self setThumbnailImage:thumbnail stock:YES inPlayerViewController:viewController hideActivityIndicator:NO];
        }
    }
}

- (BOOL)shouldSetLoadedImageOfKind:(MUKMediaImageKind)imageKind intoPlayerViewController:(MUKMediaCarouselPlayerViewController *)viewController
{
    if (!viewController) return NO;
    
    BOOL shouldSetImage = NO;
    
    // Only thumbnails and when view controller is still visible (or
    // it will be visible soon)
    if (imageKind == MUKMediaImageKindThumbnail &&
        ([self isVisibleItemViewControllerForMediaAtIndex:viewController.mediaIndex] || [self isPendingItemViewControllerForMediaAtIndex:viewController.mediaIndex]))
    {
        shouldSetImage = YES;
    }
    
    return shouldSetImage;
}

- (void)setThumbnailImage:(UIImage *)image stock:(BOOL)isStock inPlayerViewController:(MUKMediaCarouselPlayerViewController *)viewController hideActivityIndicator:(BOOL)hideActivityIndicator
{
    if (hideActivityIndicator) {
        [viewController.activityIndicatorView stopAnimating];
    }
    
    viewController.thumbnailImageView.image = image;
    viewController.thumbnailImageView.contentMode = (isStock ? UIViewContentModeCenter : UIViewContentModeScaleAspectFit);
}

- (void)dismissThumbnailInPlayerViewController:(MUKMediaCarouselPlayerViewController *)viewController
{
    // Cancel thumbnail loading
    [self cancelAllImageLoadingsForItemAtIndex:viewController.mediaIndex];
    
    // Hide thumbnail
    [self setThumbnailImage:nil stock:NO inPlayerViewController:viewController hideActivityIndicator:YES];
}

#pragma mark - Private — YouTube Player View Controllers

- (void)configureYouTubePlayerViewController:(MUKMediaCarouselYouTubePlayerViewController *)viewController forMediaAttributes:(MUKMediaAttributes *)attributes
{
    BOOL isNull = NO;
    NSURL *decodedMediaURL = [self.youTubeDecodedURLCache objectAtIndex:viewController.mediaIndex isNull:&isNull];
    
    BOOL isUsingWebView = NO;
    if (decodedMediaURL == nil) {
        NSURL *youTubeURL = [self.carouselDelegate carouselViewController:self mediaURLForItemAtIndex:viewController.mediaIndex];
        
        if (isNull) {
            // Go straight with web view
            isUsingWebView = YES;
            [self configureYouTubePlayerViewController:viewController forMediaAttributes:attributes undecodableYouTubeURL:youTubeURL];
        }
        else {
            // No cached URL, but try to decode
            [self beginDecodingMovieURLFromYouTubeURL:youTubeURL forItemAtIndex:viewController.mediaIndex];
        }
    }
    
    // Call full configuration if needed
    if (isUsingWebView == NO) {
        [self configureYouTubePlayerViewController:viewController forMediaAttributes:attributes decodedMediaURL:decodedMediaURL];
    }
}

- (void)configureYouTubePlayerViewController:(MUKMediaCarouselYouTubePlayerViewController *)viewController forMediaAttributes:(MUKMediaAttributes *)attributes decodedMediaURL:(NSURL *)mediaURL
{
    // Anyway, call plain media player method
    [self configurePlayerViewController:viewController mediaURL:mediaURL forMediaAttributes:attributes];
    
    // Show spinner if no media has been set
    if (!mediaURL) {
        [viewController.activityIndicatorView startAnimating];
    }
}

- (void)configureYouTubePlayerViewController:(MUKMediaCarouselYouTubePlayerViewController *)viewController forMediaAttributes:(MUKMediaAttributes *)attributes undecodableYouTubeURL:(NSURL *)youTubeURL
{
    // Anyway, call plain media player method
    [self configurePlayerViewController:viewController mediaURL:nil forMediaAttributes:attributes];
    
    // Show web view with spinner
    [viewController.activityIndicatorView startAnimating];
    [viewController setYouTubeURL:youTubeURL];
}

#pragma mark - Private — Current State

- (BOOL)isPendingItemViewControllerForMediaAtIndex:(NSInteger)idx {
    for (MUKMediaCarouselItemViewController *viewController in self.pendingViewControllers)
    {
        if (viewController.mediaIndex == idx) {
            return YES;
        }
    }
    
    return NO;
}

- (BOOL)isVisibleItemViewControllerForMediaAtIndex:(NSInteger)idx {
    for (MUKMediaCarouselItemViewController *viewController in self.viewControllers)
    {
        if (viewController.mediaIndex == idx) {
            return YES;
        }
    }
    
    return NO;
}

- (MUKMediaCarouselItemViewController *)firstVisibleItemViewController {
    return [self.viewControllers firstObject];
}

#pragma mark - Private — Media Attributes

- (MUKMediaAttributes *)mediaAttributesForItemAtIndex:(NSInteger)idx {
    return [self.mediaAttributesCache mediaAttributesAtIndex:idx cacheIfNeeded:self.shouldCacheAttributes loadingHandler:^MUKMediaAttributes *
            {
                if ([self.carouselDelegate respondsToSelector:@selector(carouselViewController:attributesForItemAtIndex:)])
                {
                    return [self.carouselDelegate carouselViewController:self attributesForItemAtIndex:idx];
                }
                
                return nil;
            }];
}

#pragma mark - Private — Images

- (MUKMediaModelCache *)cacheForImageKind:(MUKMediaImageKind)kind {
    MUKMediaModelCache *cache;
    
    switch (kind) {
        case MUKMediaImageKindThumbnail:
            cache = self.thumbnailImagesCache;
            break;
            
        case MUKMediaImageKindFullSize:
            cache = self.imagesCache;
            break;
            
        default:
            cache = nil;
            break;
    }
    
    return cache;
}

- (NSMutableIndexSet *)loadingIndexesForImageKind:(MUKMediaImageKind)kind {
    NSMutableIndexSet *indexSet;
    
    switch (kind) {
        case MUKMediaImageKindThumbnail:
            indexSet = self.loadingThumbnailImageIndexes;
            break;
            
        case MUKMediaImageKindFullSize:
            indexSet = self.loadingImageIndexes;
            break;
            
        default:
            indexSet = nil;
            break;
    }
    
    return indexSet;
}

- (BOOL)isLoadingImageOfKind:(MUKMediaImageKind)imageKind atIndex:(NSInteger)idx
{
    return [[self loadingIndexesForImageKind:imageKind] containsIndex:idx];
}

- (void)setLoading:(BOOL)loading imageOfKind:(MUKMediaImageKind)imageKind atIndex:(NSInteger)idx
{
    NSMutableIndexSet *indexSet = [self loadingIndexesForImageKind:imageKind];
    
    if (loading) {
        [indexSet addIndex:idx];
    }
    else {
        [indexSet removeIndex:idx];
    }
}

- (UIImage *)biggestCachedImageOrRequestLoadingForItemAtIndex:(NSInteger)idx foundImageKind:(MUKMediaImageKind *)foundImageKind
{
#if DEBUG_LOAD_LOGGING
    NSLog(@"Loading image for media at index %i...", idx);
#endif
    // Try to load biggest image
    UIImage *fullImage = [[self cacheForImageKind:MUKMediaImageKindFullSize] objectAtIndex:idx isNull:NULL];
    
    // If full image is there, we have just finished :)
    if (fullImage) {
        if (foundImageKind != NULL) {
            *foundImageKind = MUKMediaImageKindFullSize;
        }
        
#if DEBUG_LOAD_LOGGING
        NSLog(@"Found in cache!");
#endif
        
        return fullImage;
    }
    
    // No full image in cache :(
    // We need to request full image loading to delegate
    [self loadImageOfKind:MUKMediaImageKindFullSize forItemAtIndex:idx inNextRunLoop:YES];
    
    // Try to load thumbnail to appeal user eye from cache
    UIImage *thumbnail = [[self cacheForImageKind:MUKMediaImageKindThumbnail] objectAtIndex:idx isNull:NULL];
    
    // Give back thumbnail if it's in memory
    if (thumbnail) {
        if (foundImageKind != NULL) {
            *foundImageKind = MUKMediaImageKindThumbnail;
        }
        
        return thumbnail;
    }
    
    // Thumbnail is not available, too :(
    // Request it to delegate!
    [self loadImageOfKind:MUKMediaImageKindThumbnail forItemAtIndex:idx inNextRunLoop:YES];
    
    // No image in memory
    if (foundImageKind != NULL) {
        *foundImageKind = MUKMediaImageKindNone;
    }
    
    return nil;
}

- (void)loadImageOfKind:(MUKMediaImageKind)imageKind forItemAtIndex:(NSInteger)idx inNextRunLoop:(BOOL)useNextRunLoop
{
    // Mark as loading
    [self setLoading:YES imageOfKind:imageKind atIndex:idx];
    
    // This block is called by delegate which can give back an image
    // asynchronously
    __weak MUKMediaCarouselViewController *weakSelf = self;
    void (^completionHandler)(UIImage *) = ^(UIImage *image) {
        MUKMediaCarouselViewController *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        
        // If it's still loading
        if ([strongSelf isLoadingImageOfKind:imageKind atIndex:idx]) {
            // Mark as not loading
            [strongSelf setLoading:NO imageOfKind:imageKind atIndex:idx];
            
            // Stop smaller loading
            [strongSelf cancelImageLoadingSmallerThanKind:imageKind atIndex:idx];
            
            // Cache image
            [[strongSelf cacheForImageKind:imageKind] setObject:image atIndex:idx];
            
            // Get actual item view controller, searching for it inside visible
            // view controllers and pending view controllers
            MUKMediaCarouselItemViewController *viewController = [strongSelf visibleItemViewControllerForMediaAtIndex:idx] ?: [self pendingItemViewControllerForMediaAtIndex:idx];
            
            // Set image if needed
            if ([viewController isKindOfClass:[MUKMediaCarouselFullImageViewController class]])
            {
                MUKMediaCarouselFullImageViewController *fullImageViewController = (MUKMediaCarouselFullImageViewController *)viewController;
                
                if ([strongSelf shouldSetLoadedImageOfKind:imageKind intoFullImageViewController:fullImageViewController])
                {
                    [strongSelf setImage:image ofKind:imageKind inFullImageViewController:fullImageViewController];
                }
            }
            
            // Set video if needed
            else if ([viewController isKindOfClass:[MUKMediaCarouselPlayerViewController class]])
            {
                MUKMediaCarouselPlayerViewController *playerViewController = (MUKMediaCarouselPlayerViewController *)viewController;
                if ([strongSelf shouldSetLoadedImageOfKind:imageKind intoPlayerViewController:playerViewController])
                {
                    BOOL stock = NO;
                    
                    if (!image) {
                        // Use stock thumbnail
                        MUKMediaAttributes *attributes = [strongSelf mediaAttributesForItemAtIndex:idx];
                        image = [strongSelf stockThumbnailForMediaKind:attributes.kind];
                        stock = YES;
                    }
                    
                    BOOL hideActivityIndicator = YES;
                    if ([viewController isKindOfClass:[MUKMediaCarouselYouTubePlayerViewController class]])
                    {
                        hideActivityIndicator = NO;
                    }
                    
                    [strongSelf setThumbnailImage:image stock:stock inPlayerViewController:playerViewController hideActivityIndicator:hideActivityIndicator];
                }
            }
        } // if isLoadingImageKind
    }; // completionHandler
    
    // Call delegate in next run loop when we need view controller enters in reuse queue
    if (useNextRunLoop) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.carouselDelegate carouselViewController:self loadImageOfKind:imageKind forItemAtIndex:idx completionHandler:completionHandler];
        });
    }
    else {
        [self.carouselDelegate carouselViewController:self loadImageOfKind:imageKind forItemAtIndex:idx completionHandler:completionHandler];
    }
}

- (void)cancelLoadingForImageOfKind:(MUKMediaImageKind)imageKind atIndex:(NSInteger)index
{
    if ([self isLoadingImageOfKind:imageKind atIndex:index]) {
        // Mark as not loading
        [self setLoading:NO imageOfKind:imageKind atIndex:index];
        
        // Request delegate to abort
        if ([self.carouselDelegate respondsToSelector:@selector(carouselViewController:cancelLoadingForImageOfKind:atIndex:)])
        {
            [self.carouselDelegate carouselViewController:self cancelLoadingForImageOfKind:imageKind atIndex:index];
        }
    }
}

- (void)cancelImageLoadingSmallerThanKind:(MUKMediaImageKind)imageKind atIndex:(NSInteger)idx
{
    if (imageKind == MUKMediaImageKindFullSize) {
        [self cancelLoadingForImageOfKind:MUKMediaImageKindThumbnail atIndex:idx];
    }
}

- (void)cancelAllImageLoadingsForItemAtIndex:(NSInteger)idx {
    [self cancelLoadingForImageOfKind:MUKMediaImageKindFullSize atIndex:idx];
    [self cancelLoadingForImageOfKind:MUKMediaImageKindThumbnail atIndex:idx];
}

- (UIImage *)stockThumbnailForMediaKind:(MUKMediaKind)mediaKind {
    UIImage *thumbnail;
    
    switch (mediaKind) {
        case MUKMediaKindAudio: {
            thumbnail = [MUKMediaGalleryUtils imageNamed:@"audio_big_transparent"];
            
            if ([thumbnail respondsToSelector:@selector(imageWithRenderingMode:)]) {
                
                thumbnail = [thumbnail imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            }
            
            break;
        }
            
        case MUKMediaKindVideo:
        case MUKMediaKindYouTubeVideo: {
            thumbnail = [MUKMediaGalleryUtils imageNamed:@"video_big_transparent"];
            
            if ([thumbnail respondsToSelector:@selector(imageWithRenderingMode:)])
            {
                thumbnail = [thumbnail imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            }
            
            break;
        }
            
        default:
            thumbnail = nil;
            break;
    }
    
    return thumbnail;
}

#pragma mark - Private — Media Playback

- (void)cancelMediaPlaybackInPlayerViewController:(MUKMediaCarouselPlayerViewController *)viewController
{
    [viewController setMediaURL:nil];
    
    if ([viewController isKindOfClass:[MUKMediaCarouselYouTubePlayerViewController class]])
    {
        [(MUKMediaCarouselYouTubePlayerViewController *)viewController setYouTubeURL:nil];
    }
}

- (BOOL)shouldDismissThumbnailAsNewPlaybackStartsInPlayerViewController:(MUKMediaCarouselPlayerViewController *)viewController
{
    // Load attributes
    MUKMediaAttributes *attributes = [self mediaAttributesForItemAtIndex:viewController.mediaIndex];
    
    BOOL shouldDismissThumbnail;
    
    // Keep thumbnail for audio tracks
    if (attributes.kind == MUKMediaKindAudio) {
        shouldDismissThumbnail = NO;
    }
    else {
        if (viewController.moviePlayerController.playbackState != MPMoviePlaybackStateStopped ||
            viewController.moviePlayerController.playbackState != MPMoviePlaybackStatePaused)
        {
            shouldDismissThumbnail = YES;
        }
        else {
            shouldDismissThumbnail = NO;
        }
    }
    
    return shouldDismissThumbnail;
}

#pragma mark - Private — YouTube

- (BOOL)isDecodingMovieURLFromYouTubeForItemAtIndex:(NSInteger)index {
    return [[self.runningYouTubeExtractors allKeys] containsObject:@(index)];
}

- (void)beginDecodingMovieURLFromYouTubeURL:(NSURL *)youTubeURL forItemAtIndex:(NSInteger)index
{
    if (!youTubeURL || [self isDecodingMovieURLFromYouTubeForItemAtIndex:index]) {
        return;
    }
    
    NSString *const videoIdentifier = [self identifierInYouTubeURL:youTubeURL];
    if (!videoIdentifier) {
        return;
    }
    
    __weak MUKMediaCarouselViewController *weakSelf = self;
    id<XCDYouTubeOperation> operation = [[XCDYouTubeClient defaultClient] getVideoWithIdentifier:videoIdentifier completionHandler:^(XCDYouTubeVideo *video, NSError *error)
                                         {
                                             MUKMediaCarouselViewController *strongSelf = weakSelf;
                                             [strongSelf didFinishExtractingYouTubeVideo:video error:error forItemAtIndex:index withYouTubeURL:youTubeURL];
                                         }];
    
    self.runningYouTubeExtractors[@(index)] = operation;
}

- (void)cancelDecodingMovieURLFromYouTubeForItemAtIndex:(NSInteger)index {
    id<XCDYouTubeOperation> operation = self.runningYouTubeExtractors[@(index)];
    [operation cancel];
    [self.runningYouTubeExtractors removeObjectForKey:@(index)];
}

- (NSString *)identifierInYouTubeURL:(NSURL *)youTubeURL {
    if (!youTubeURL) {
        return nil;
    }
    
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(?<=v(=|/))([-a-zA-Z0-9_]+)|(?<=youtu.be/)([-a-zA-Z0-9_]+)" options:NSRegularExpressionCaseInsensitive error:&error];
    NSString *const youTubeURLString = [youTubeURL absoluteString];
    NSTextCheckingResult *match = [regex firstMatchInString:youTubeURLString options:0 range:NSMakeRange(0, [youTubeURLString length])];
    
    if (match) {
        NSRange range = [match rangeAtIndex:0];
        NSString *videoIdentifier = [youTubeURLString substringWithRange:range];
        return videoIdentifier;
    }
    
    return nil;
}

- (void)didFinishExtractingYouTubeVideo:(XCDYouTubeVideo *)video error:(NSError *)error forItemAtIndex:(NSInteger)itemIndex withYouTubeURL:(NSURL *)youTubeURL
{
    // Set as not running
    [self cancelDecodingMovieURLFromYouTubeForItemAtIndex:itemIndex];
    
    // Check item is the same
    NSURL *const updatedYouTubeURL = [self.carouselDelegate carouselViewController:self mediaURLForItemAtIndex:itemIndex];
    
    if (![youTubeURL isEqual:updatedYouTubeURL]) {
        // If it's not the same, stop here
        return;
    }
    
    // If it's the same, continue caching it (if no video URL, cache is cleared properly)
#if !DEBUG_YOUTUBE_EXTRACTION_ALWAYS_FAIL
    NSURL *const extractedURL = [self preferredExtractedYouTubeMovieURLFromVideo:video];
#else
    NSURL *const extractedURL = nil;
#endif
    [self.youTubeDecodedURLCache setObject:extractedURL atIndex:itemIndex];
    
    // Get & configure view controller
    MUKMediaCarouselYouTubePlayerViewController *viewController = (MUKMediaCarouselYouTubePlayerViewController *)[self visibleItemViewControllerForMediaAtIndex:itemIndex];
    
    if ([viewController isMemberOfClass:[MUKMediaCarouselYouTubePlayerViewController class]])
    {
        MUKMediaAttributes *const attributes = [self mediaAttributesForItemAtIndex:itemIndex];
        
        if (extractedURL && !DEBUG_YOUTUBE_EXTRACTION_ALWAYS_FAIL) {
            [self configureYouTubePlayerViewController:viewController forMediaAttributes:attributes decodedMediaURL:extractedURL];
        }
        else {
            [self configureYouTubePlayerViewController:viewController forMediaAttributes:attributes undecodableYouTubeURL:youTubeURL];
        }
    }
}

- (NSURL *)preferredExtractedYouTubeMovieURLFromVideo:(XCDYouTubeVideo *)video {
    if (!video) {
        return nil;
    }
    
    // Check live streaming first
    NSURL *URL = video.streamURLs[XCDYouTubeVideoQualityHTTPLiveStreaming];
    if (URL) {
        return URL;
    }
    
    // Check video from best quality
    URL = video.streamURLs[@(XCDYouTubeVideoQualityHD720)];
    if (URL) {
        return URL;
    }
    
    URL = video.streamURLs[@(XCDYouTubeVideoQualityMedium360)];
    if (URL) {
        return URL;
    }
    
    return video.streamURLs[@(XCDYouTubeVideoQualitySmall240)];
}

#pragma mark - Private — Bars

- (BOOL)areBarsHidden {
    return self.navigationController.navigationBarHidden;
}

- (void)updateUIConstraintsWhenHidden:(BOOL)hidden animated:(BOOL)animated {
    if (!self.controlsViewTopConstraint) {
        self.controlsViewTopConstraint = [NSLayoutConstraint constraintWithItem:self.controlsView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeBottom multiplier:1.0f constant:0];
    }
    if (!self.controlsViewBottomConstraint) {
        self.controlsViewBottomConstraint = [NSLayoutConstraint constraintWithItem:self.controlsView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeBottom multiplier:1.0f constant:0];
    }
    
    // Change constraints
    NSArray *unusedConstraints, *usedConstraints;
    
    if (hidden) {
        usedConstraints = @[ self.controlsViewTopConstraint];
        unusedConstraints = @[ self.controlsViewBottomConstraint];
    }
    else {
        usedConstraints = @[self.controlsViewBottomConstraint];
        unusedConstraints = @[self.controlsViewTopConstraint];
    }
    
    [self.view removeConstraints:unusedConstraints];
    [self.view addConstraints:usedConstraints];
    
    [self.view setNeedsUpdateConstraints];
    
    
    NSTimeInterval const duration = animated ? UINavigationControllerHideShowBarDuration : 0.0;
    
    
    [UIView animateWithDuration:duration animations:^{
        [self.view layoutIfNeeded];
    } completion:nil];
}

- (void)setBarsHidden:(BOOL)hidden animated:(BOOL)animated {
    BOOL automaticallyManagesStatusBar = [self respondsToSelector:@selector(setNeedsStatusBarAppearanceUpdate)];
    
    if (!automaticallyManagesStatusBar) {
        UIStatusBarAnimation animation = UIStatusBarAnimationNone;
        
        if (animated) {
            if (hidden) {
                animation = UIStatusBarAnimationSlide;
            }
            else {
                animation = UIStatusBarAnimationFade;
            }
        }
        
        [[UIApplication sharedApplication] setStatusBarHidden:hidden withAnimation:animation];
    }
    
    [self.navigationController setNavigationBarHidden:hidden animated:animated];
    
    
    if (automaticallyManagesStatusBar) {
        [self setNeedsStatusBarAppearanceUpdate];
    }
    
    for (MUKMediaCarouselItemViewController *viewController in self.viewControllers)
    {
        [viewController setCaptionHidden:hidden animated:animated completion:nil];
    } // for
    
    [self updateUIConstraintsWhenHidden:hidden animated:animated];
}

- (void)toggleBarsVisibility {
    BOOL barsHidden = [self areBarsHidden];
    [self setBarsHidden:!barsHidden animated:YES];
}

#pragma mark - <UIPageViewControllerDelegate>

- (void)pageViewController:(UIPageViewController *)pageViewController willTransitionToViewControllers:(NSArray *)pendingViewControllers
{
    self.view.userInteractionEnabled = NO;
    
    // Save pending view controllers
    self.pendingViewControllers = [pendingViewControllers mutableCopy];
    
    // Configure new view controllers
    for (MUKMediaCarouselItemViewController *itemViewController in pendingViewControllers)
    {
#if DEBUG_LOAD_LOGGING
        NSLog(@"Configuring media at index %i at -pageViewController:willTransitionToViewControllers:", itemViewController.mediaIndex);
#endif
        // Load attributes
        MUKMediaAttributes *attributes = [self mediaAttributesForItemAtIndex:itemViewController.mediaIndex];
        [self configureItemViewController:itemViewController forMediaAttributes:attributes];
    }
}

- (void)pageViewController:(UIPageViewController *)pageViewController didFinishAnimating:(BOOL)finished previousViewControllers:(NSArray *)previousViewControllers transitionCompleted:(BOOL)completed
{
    self.view.userInteractionEnabled = YES;
    // When view controller disappear, stop loadings
    for (MUKMediaCarouselItemViewController *previousViewController in previousViewControllers)
    {
        if (![pageViewController.viewControllers containsObject:previousViewController])
        {
#if DEBUG_LOAD_LOGGING
            NSLog(@"Cancel all loadings for media at index %i at -didFinishAnimating:previousViewControllers:transitionCompleted:", previousViewController.mediaIndex);
#endif
            [self cancelAllLoadingsForItemViewController:previousViewController];
        }
    } // for
    
    // Clean pending view controllers
    self.pendingViewControllers = nil;
}

#pragma mark - <UIPageViewControllerDataSource>

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerBeforeViewController:(UIViewController *)viewController
{
    MUKMediaCarouselItemViewController *itemViewController = (MUKMediaCarouselItemViewController *)viewController;
    
    // It's first item
    if (itemViewController.mediaIndex <= 0) {
        return nil;
    }
    
    return [self newItemViewControllerForMediaAtIndex:itemViewController.mediaIndex - 1];
}

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerAfterViewController:(UIViewController *)viewController
{
    MUKMediaCarouselItemViewController *itemViewController = (MUKMediaCarouselItemViewController *)viewController;
    
    // It's last item
    NSInteger itemsCount = [self.carouselDelegate numberOfItemsInCarouselViewController:self];
    if (itemViewController.mediaIndex + 1 >= itemsCount) {
        return nil;
    }
    
    return [self newItemViewControllerForMediaAtIndex:itemViewController.mediaIndex + 1];
}

#pragma mark - <MUKMediaCarouselItemViewControllerDelegate>

- (void)carouselItemViewControllerDidReceiveTap:(MUKMediaCarouselItemViewController *)viewController
{
    // Show movie controls if bars are hidden and current item is an audio/video
    // Hide movie controls if bars are shows and current item is already playing
    
    if ([viewController isKindOfClass:[MUKMediaCarouselPlayerViewController class]])
    {
        MUKMediaCarouselPlayerViewController *playerViewController = (MUKMediaCarouselPlayerViewController *)viewController;
        if ([self areBarsHidden]) {
            [playerViewController setPlayerControlsHidden:NO animated:YES completion:nil];
        }
        else if (playerViewController.moviePlayerController.playbackState == MPMoviePlaybackStatePlaying)
        {
            [playerViewController setPlayerControlsHidden:YES animated:YES completion:nil];
        }
    }
    
    [self toggleBarsVisibility];
}

- (void)carouselItemViewControllerWantsEditCaption:(MUKMediaCarouselItemViewController *)viewController {
    
}

- (void)carouselItemViewControllerWantsDeleteItem:(MUKMediaCarouselItemViewController *)viewController {
    
}

#pragma mark - <MUKMediaCarouselFullImageViewControllerDelegate>

- (void)carouselFullImageViewController:(MUKMediaCarouselFullImageViewController *)viewController imageScrollViewDidReceiveTapWithGestureRecognizer:(UITapGestureRecognizer *)gestureRecognizer
{
    [self toggleBarsVisibility];
}

#pragma mark - <MUKMediaCarouselPlayerViewControllerDelegate>

- (void)carouselPlayerViewControllerDidChangeNowPlayingMovie:(MUKMediaCarouselPlayerViewController *)viewController
{
    // Dismiss thumbnail (if needed) when new playback starts (or begins scrubbing)
    if ([self shouldDismissThumbnailAsNewPlaybackStartsInPlayerViewController:viewController])
    {
        [self dismissThumbnailInPlayerViewController:viewController];
    }
}

- (void)carouselPlayerViewControllerDidChangePlaybackState:(MUKMediaCarouselPlayerViewController *)viewController
{
    // Hide bars when playback starts
    if (viewController.moviePlayerController.playbackState == MPMoviePlaybackStatePlaying)
    {
        [self setBarsHidden:YES animated:YES];
    }
}

#pragma mark - <MUKMediaCarouselYouTubePlayerViewControllerDelegate>

- (void)carouselYouTubePlayerViewController:(MUKMediaCarouselYouTubePlayerViewController *)viewController webView:(UIWebView *)webView didReceiveTapWithGestureRecognizer:(UITapGestureRecognizer *)gestureRecognizer
{
    [self toggleBarsVisibility];
}

- (void)carouselYouTubePlayerViewController:(MUKMediaCarouselYouTubePlayerViewController *)viewController didFinishLoadingWebView:(UIWebView *)webView error:(NSError *)error
{
    viewController.thumbnailImageView.image = nil;
    [viewController.activityIndicatorView stopAnimating];
}

@end
