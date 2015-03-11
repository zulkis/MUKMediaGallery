#import "MUKMediaCarouselItemViewController.h"
#import "MUKMediaGalleryToolbar.h"
#import "MUKMediaGalleryUtils.h"

static CGFloat const kCaptionLabelMaxHeight = 80.0f;
static CGFloat const kCaptionLabelLateralPadding = 8.0f;
static CGFloat const kCaptionLabelBottomPadding = 5.0f;
static CGFloat const kCaptionLabelTopPadding = 3.0f;

@implementation MUKOverlayView

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    for (UIView *view in self.clearTouchViewInOverlay) {
        if (CGRectContainsPoint(view.frame, point)) {
            return NO;
        }
    }
    return [super pointInside:point withEvent:event];
}

@end

@interface MUKMediaCarouselItemViewController () <UIToolbarDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, weak, readwrite) MUKOverlayView *overlayView;
@property (nonatomic, weak, readwrite) UIActivityIndicatorView *activityIndicatorView;
@property (nonatomic, weak, readwrite) UILabel *captionLabel;
@property (nonatomic, weak, readwrite) UIView *captionBackgroundView;
@property (nonatomic, weak, readwrite) UIView *controlsView;
@property (nonatomic, weak, readwrite) UIImageView *thumbnailImageView;

@property (nonatomic, strong) NSLayoutConstraint *captionLabelBottomConstraint, *captionLabelTopConstraint, *captionBackgroundViewBottomConstraint, *captionBackgroundViewTopConstraint, *controlsViewTopConstraint, *controlsViewBottomConstraint, *captionBackgroundHeightConstraint;
@end

@implementation MUKMediaCarouselItemViewController

- (void)dealloc {
    [self unregisterFromContentSizeCategoryNotifications];
}

- (instancetype)initWithMediaIndex:(NSInteger)idx {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _mediaIndex = idx;
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    MUKOverlayView *overlayView = [self newOverlayViewInSuperview:self.view];
    self.overlayView = overlayView;
    
    UIActivityIndicatorView *activityIndicatorView = [self newCenteredActivityIndicatorViewInSuperview:overlayView];
    self.activityIndicatorView = activityIndicatorView;
    
    UIView *controlsView = [self newBottomAttachedControlsViewInSuperview:overlayView];
    self.controlsView = controlsView;
    
    UILabel *captionLabel = [self newBottomAttachedCaptionLabelInSuperview:overlayView];
    self.captionLabel = captionLabel;
    
    UIView *captionBackgroundView = [self newBottomAttachedBackgroundViewForCaptionLabel:captionLabel inSuperview:overlayView];
    self.captionBackgroundView = captionBackgroundView;
    
    
    [self updateCaptionConstraintsWhenHidden:NO];
    [self registerToContentSizeCategoryNotifications];
    [self attachTapGestureRecognizer];
}

- (void)onCaptionButtonTap:(UIButton *)sender {
    [self.delegate carouselItemViewControllerWantsEditCaption:self];
}

- (void)onDeleteButtonTap:(UIButton *)sender {
    [self.delegate carouselItemViewControllerWantsDeleteItem:self];
}

#pragma mark - Caption

- (BOOL)isCaptionHidden {
    return self.captionBackgroundView.alpha < 1.0f;
}

- (void)setCaptionHidden:(BOOL)hidden animated:(BOOL)animated completion:(void (^)(BOOL finished))completionHandler
{
    NSTimeInterval const duration = animated ? UINavigationControllerHideShowBarDuration : 0.0;
    
    [self updateCaptionConstraintsWhenHidden:hidden];
    
    [UIView animateWithDuration:duration animations:^{
        [self.view layoutIfNeeded];
    } completion:completionHandler];
}

#pragma mark - Thumbnail

- (void)createThumbnailImageViewIfNeededInSuperview:(UIView *)superview belowSubview:(UIView *)subview
{
    if (![self.thumbnailImageView.superview isEqual:superview]) {
        [self.thumbnailImageView removeFromSuperview];
        self.thumbnailImageView = nil;
    }
    
    if (self.thumbnailImageView == nil) {
        UIImageView *thumbnailImageView = [[UIImageView alloc] initWithFrame:superview.bounds];
        thumbnailImageView.contentMode = UIViewContentModeScaleAspectFit;
        thumbnailImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        
        if (subview) {
            [superview insertSubview:thumbnailImageView belowSubview:subview];
        }
        else {
            [superview addSubview:thumbnailImageView];
        }
        
        self.thumbnailImageView = thumbnailImageView;
    }
}

#pragma mark - Private

- (MUKOverlayView *)newOverlayViewInSuperview:(UIView *)superview {
    MUKOverlayView *overlayView = [[MUKOverlayView alloc] initWithFrame:superview.bounds];
    overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    overlayView.userInteractionEnabled = YES;
    overlayView.backgroundColor = [UIColor clearColor];
    [superview addSubview:overlayView];
    return overlayView;
}

- (UIActivityIndicatorView *)newCenteredActivityIndicatorViewInSuperview:(UIView *)superview
{
    UIActivityIndicatorView *activityIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    activityIndicatorView.translatesAutoresizingMaskIntoConstraints = NO;
    [superview addSubview:activityIndicatorView];
    
    NSLayoutConstraint *centerX = [NSLayoutConstraint constraintWithItem:superview attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:activityIndicatorView attribute:NSLayoutAttributeCenterX multiplier:1.0f constant:0.0f];
    NSLayoutConstraint *centerY = [NSLayoutConstraint constraintWithItem:superview attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:activityIndicatorView attribute:NSLayoutAttributeCenterY multiplier:1.0f constant:0.0f];
    [superview addConstraints:@[centerX, centerY]];
    
    return activityIndicatorView;
}

- (UIView *)newBottomAttachedControlsViewInSuperview:(UIView *)superview {
    const CGFloat controlsHeight = 60.f;
    
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0,
                                                            0,
                                                            CGRectGetWidth(superview.frame),
                                                            controlsHeight)];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.backgroundColor = [UIColor colorWithWhite:1.f alpha:0.96f]; //#F5F5F5
    [superview addSubview:view];
    
    
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
    
    NSDictionary *viewsDict = NSDictionaryOfVariableBindings(view, captionButton, deleteButton);
    // Our controls view width must be == to superview width
    NSArray *constraints = [NSLayoutConstraint constraintsWithVisualFormat:@"|-(0)-[view]-(0)-|" options:0 metrics:nil views:viewsDict];
    [superview addConstraints:constraints];
    
    constraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:[view(==controlsHeight)]" options:0 metrics:@{ @"controlsHeight" : @(controlsHeight) } views:viewsDict];
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

- (UILabel *)newBottomAttachedCaptionLabelInSuperview:(UIView *)superview {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 20.0f, 20.0f)];
    label.userInteractionEnabled = NO;
    label.textColor = [UIColor whiteColor];
    label.font = [[self class] defaultCaptionLabelFont];
    label.numberOfLines = 0;
    label.backgroundColor = [UIColor clearColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [superview addSubview:label];
    
    UIView *controlsView = self.controlsView;
    NSDictionary *viewsDict = NSDictionaryOfVariableBindings(label, controlsView);
    NSArray *constraints = [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(padding)-[label]-(padding)-|" options:0 metrics:@{@"padding" : @(kCaptionLabelLateralPadding)} views:viewsDict];
    [superview addConstraints:constraints];
    
    constraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:[label(<=maxHeight)]" options:0 metrics:@{ @"maxHeight" : @(kCaptionLabelMaxHeight) } views:viewsDict];
    [superview addConstraints:constraints];
    
    return label;
}

- (UIView *)newBottomAttachedBackgroundViewForCaptionLabel:(UILabel *)label inSuperview:(UIView *)superview
{
    UIView *view;
    if ([MUKMediaGalleryUtils defaultUIParadigm] == MUKMediaGalleryUIParadigmLayered)
    {
        // A toolbar gives live blurry effect on iOS 7
        MUKMediaGalleryToolbar *toolbar = [[MUKMediaGalleryToolbar alloc] initWithFrame:label.frame];
        toolbar.barStyle = UIBarStyleBlack;
        toolbar.delegate = self;
        
        view = toolbar;
    }
    else {
        view = [[UIView alloc] initWithFrame:label.frame];
        view.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.5f];
    }
    
    view.userInteractionEnabled = NO;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [superview insertSubview:view belowSubview:label];
    
    NSDictionary *viewsDict = NSDictionaryOfVariableBindings(view);
    NSArray *constraints = [NSLayoutConstraint constraintsWithVisualFormat:@"|-(0)-[view]-(0)-|" options:0 metrics:nil views:viewsDict];
    [superview addConstraints:constraints];
    
    return view;
}

#pragma mark - Private — Caption

- (void)updateCaptionConstraintsWhenHidden:(BOOL)hidden {
    UIView *const superview = self.captionLabel.superview;
    
    // Create all constraints
    
    
    if (!self.captionLabelTopConstraint) {
        self.captionLabelTopConstraint = [NSLayoutConstraint constraintWithItem:self.captionLabel attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:superview attribute:NSLayoutAttributeBottom multiplier:1.0f constant:kCaptionLabelTopPadding];
    }
    
    if (!self.captionBackgroundViewTopConstraint) {
        self.captionBackgroundViewTopConstraint = [NSLayoutConstraint constraintWithItem:self.captionBackgroundView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:superview attribute:NSLayoutAttributeBottom multiplier:1.0f constant:kCaptionLabelTopPadding];
    }
    
    if (!self.controlsViewTopConstraint) {
        self.controlsViewTopConstraint = [NSLayoutConstraint constraintWithItem:self.controlsView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:superview attribute:NSLayoutAttributeBottom multiplier:1.0f constant:0];
    }
    
    if (!self.captionLabelBottomConstraint) {
        self.captionLabelBottomConstraint = [NSLayoutConstraint constraintWithItem:self.captionLabel attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.controlsView attribute:NSLayoutAttributeTop multiplier:1.0f constant:-kCaptionLabelBottomPadding];
    }
    
    if (!self.captionBackgroundViewBottomConstraint) {
        self.captionBackgroundViewBottomConstraint = [NSLayoutConstraint constraintWithItem:self.captionBackgroundView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.controlsView attribute:NSLayoutAttributeTop multiplier:1.0f constant:0.0f];
    }
    
    if (!self.controlsViewBottomConstraint) {
        self.controlsViewBottomConstraint = [NSLayoutConstraint constraintWithItem:self.controlsView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:superview attribute:NSLayoutAttributeBottom multiplier:1.0f constant:0];
    }
    if (!self.captionBackgroundHeightConstraint) {
        self.captionBackgroundHeightConstraint = [NSLayoutConstraint constraintWithItem:self.captionBackgroundView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:self.captionLabel attribute:NSLayoutAttributeHeight multiplier:1.0f constant:0];
        [superview addConstraint:self.captionBackgroundHeightConstraint];
    }
    
    if (self.captionLabel.text.length > 0) {
        self.captionBackgroundHeightConstraint.constant = kCaptionLabelBottomPadding + kCaptionLabelTopPadding;
    } else {
        self.captionBackgroundHeightConstraint.constant = 0;
    }
    
    // Change constraints
    NSArray *unusedConstraints, *usedConstraints;
    
    if (hidden) {
        usedConstraints = @[ self.captionLabelTopConstraint, self.captionBackgroundViewTopConstraint, self.controlsViewTopConstraint];
        unusedConstraints = @[ self.captionLabelBottomConstraint, self.captionBackgroundViewBottomConstraint, self.controlsViewBottomConstraint ];
    }
    else {
        usedConstraints = @[ self.captionLabelBottomConstraint, self.captionBackgroundViewBottomConstraint , self.controlsViewBottomConstraint];
        unusedConstraints = @[ self.captionLabelTopConstraint, self.captionBackgroundViewTopConstraint, self.controlsViewTopConstraint ];
    }
    
    [superview removeConstraints:unusedConstraints];
    [superview addConstraints:usedConstraints];
    
    // Notify
    [self.view setNeedsUpdateConstraints];
}

#pragma mark - Private — Notifications

- (void)registerToContentSizeCategoryNotifications {
    if (&UIContentSizeCategoryDidChangeNotification != NULL) {
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(contentSizeCategoryDidChangeNotification:) name:UIContentSizeCategoryDidChangeNotification object:nil];
    }
}

- (void)unregisterFromContentSizeCategoryNotifications {
    if (&UIContentSizeCategoryDidChangeNotification != NULL) {
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc removeObserver:self name:UIContentSizeCategoryDidChangeNotification object:nil];
    }
}

- (void)contentSizeCategoryDidChangeNotification:(NSNotification *)notification
{
    self.captionLabel.font = [[self class] defaultCaptionLabelFont];
}

#pragma mark - Private — Fonts

+ (UIFont *)defaultCaptionLabelFont {
    UIFont *font;
    
    if ([[UIFont class] respondsToSelector:@selector(preferredFontForTextStyle:)])
    {
        font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    }
    else {
        font = [UIFont systemFontOfSize:12.0f];
    }
    
    return font;
}

#pragma mark - Private — Tap Gesture Recognizer

- (void)attachTapGestureRecognizer {
    UITapGestureRecognizer *gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [self.overlayView addGestureRecognizer:gestureRecognizer];
}

- (void)handleTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        [self.delegate carouselItemViewControllerDidReceiveTap:self];
    }
}

#pragma mark - <UIToolbarDelegate>

- (UIBarPosition)positionForBar:(id<UIBarPositioning>)bar {
    return UIBarPositionBottom;
}

@end
