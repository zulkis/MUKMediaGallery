#import "MUKMediaCarouselItemViewController.h"
#import "MUKMediaGalleryToolbar.h"
#import "MUKMediaGalleryUtils.h"
#import "UIColor+MUKColor.h"
#import "UIFont+MUKFont.h"

static CGFloat const kCaptionLabelMaxHeight = 80.0f;
static CGFloat const kCaptionLabelLateralPadding = 20.0f;
static CGFloat const kCaptionLabelBottomPadding = 10.0f;
static CGFloat const kCaptionLabelTopPadding = 6.0f;


@interface MUKMediaCarouselItemViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, weak, readwrite) UIView *overlayView;
@property (nonatomic, weak, readwrite) UIActivityIndicatorView *activityIndicatorView;
@property (nonatomic, weak, readwrite) UILabel *captionLabel;
@property (nonatomic, weak, readwrite) UIView *captionBackgroundView;
@property (nonatomic, weak, readwrite) UIImageView *thumbnailImageView;

@property (nonatomic, strong) NSLayoutConstraint *captionLabelBottomConstraint, *captionLabelTopConstraint, *captionBackgroundViewBottomConstraint, *captionBackgroundViewTopConstraint, *captionBackgroundViewHeightConstraint;
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
    
    UIView *overlayView = [self newOverlayViewInSuperview:self.view];
    self.overlayView = overlayView;
    
    UIActivityIndicatorView *activityIndicatorView = [self newCenteredActivityIndicatorViewInSuperview:overlayView];
    self.activityIndicatorView = activityIndicatorView;
    
    UILabel *captionLabel = [self newBottomAttachedCaptionLabelInSuperview:overlayView];
    self.captionLabel = captionLabel;
    
    UIView *captionBackgroundView = [self newBottomAttachedBackgroundViewForCaptionLabel:captionLabel inSuperview:overlayView];
    self.captionBackgroundView = captionBackgroundView;
    
    
    [self updateCaptionConstraintsWhenHidden:NO];
    [self registerToContentSizeCategoryNotifications];
    [self attachTapGestureRecognizer];
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

- (UIView *)newOverlayViewInSuperview:(UIView *)superview {
    UIView *overlayView = [[UIView alloc] initWithFrame:superview.bounds];
    overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    overlayView.userInteractionEnabled = NO;
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

- (UILabel *)newBottomAttachedCaptionLabelInSuperview:(UIView *)superview {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 20.0f, 20.0f)];
    label.userInteractionEnabled = NO;
    label.textColor = [UIColor MUK_textColor];
    label.font = [[self class] defaultCaptionLabelFont];
    label.numberOfLines = 0;
    label.backgroundColor = [UIColor clearColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [superview addSubview:label];
    
    NSDictionary *viewsDict = NSDictionaryOfVariableBindings(label);
    NSArray *constraints = [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(padding)-[label]-(padding)-|" options:0 metrics:@{@"padding" : @(kCaptionLabelLateralPadding)} views:viewsDict];
    [superview addConstraints:constraints];
    
    constraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:[label(<=maxHeight)]" options:0 metrics:@{ @"maxHeight" : @(kCaptionLabelMaxHeight) } views:viewsDict];
    [superview addConstraints:constraints];
    
    return label;
}

- (UIView *)newBottomAttachedBackgroundViewForCaptionLabel:(UILabel *)label inSuperview:(UIView *)superview
{
    UIView *view = [[UIView alloc] initWithFrame:label.frame];
    view.backgroundColor = [UIColor whiteColor];
    
    view.userInteractionEnabled = NO;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [superview insertSubview:view belowSubview:label];
    
    NSDictionary *viewsDict = NSDictionaryOfVariableBindings(view);
    NSArray *constraints = [NSLayoutConstraint constraintsWithVisualFormat:@"|-(0)-[view]-(0)-|" options:0 metrics:nil views:viewsDict];
    [superview addConstraints:constraints];
    
    self.captionBackgroundViewHeightConstraint = [NSLayoutConstraint constraintWithItem:view attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:label attribute:NSLayoutAttributeHeight multiplier:1.0f constant:kCaptionLabelBottomPadding + kCaptionLabelTopPadding];
    [superview addConstraint:self.captionBackgroundViewHeightConstraint];
    
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
        self.captionBackgroundViewTopConstraint = [NSLayoutConstraint constraintWithItem:self.captionBackgroundView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:superview attribute:NSLayoutAttributeBottom multiplier:1.0f constant:0];
    }
    
    if (!self.captionLabelBottomConstraint) {
        self.captionLabelBottomConstraint = [NSLayoutConstraint constraintWithItem:self.captionLabel attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:superview attribute:NSLayoutAttributeBottom multiplier:1.0f constant:-(kCaptionLabelBottomPadding + self.captionBottomOffset)];
    }
    
    if (!self.captionBackgroundViewBottomConstraint) {
        self.captionBackgroundViewBottomConstraint = [NSLayoutConstraint constraintWithItem:self.captionBackgroundView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:superview attribute:NSLayoutAttributeBottom multiplier:1.0f constant:-self.captionBottomOffset];
    }
    
    if (self.captionLabel.text.length > 0) {
        self.captionBackgroundViewHeightConstraint.constant = kCaptionLabelBottomPadding + kCaptionLabelTopPadding;
    } else {
        self.captionBackgroundViewHeightConstraint.constant = 0;
    }
    
    // Change constraints
    NSArray *unusedConstraints, *usedConstraints;
    
    if (hidden) {
        usedConstraints = @[ self.captionLabelTopConstraint, self.captionBackgroundViewTopConstraint ];
        unusedConstraints = @[ self.captionLabelBottomConstraint, self.captionBackgroundViewBottomConstraint ];
    }
    else {
        usedConstraints = @[ self.captionLabelBottomConstraint, self.captionBackgroundViewBottomConstraint ];
        unusedConstraints = @[ self.captionLabelTopConstraint, self.captionBackgroundViewTopConstraint ];
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
    return [UIFont MUK_defaultFontWithSize:14.f];;
}

#pragma mark - Private — Tap Gesture Recognizer

- (void)attachTapGestureRecognizer {
    UITapGestureRecognizer *gestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [self.view addGestureRecognizer:gestureRecognizer];
}

- (void)handleTap:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        [self.delegate carouselItemViewControllerDidReceiveTap:self];
    }
}

@end
