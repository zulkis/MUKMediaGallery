//
//  UIColor+MUKColor.m
//  
//
//  Created by Alexey Minaev on 18/03/15.
//
//

#import "UIColor+MUKColor.h"

@implementation UIColor (MUKColor)

+ (UIColor *)MUK_textColor {
    return [UIColor colorWithWhite:74.f/255.f alpha:1.f];
}

+ (UIColor *)MUK_maximumTrackTintColor {
    return [UIColor colorWithWhite:189.f/255.f alpha:1.f];
}

+ (UIColor *)MUK_minimumTrackTintColor {
    return [UIColor colorWithRed:1.f green:101.f/255.f blue:0.f alpha:1.f];
}

@end
