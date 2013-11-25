//
//  JFSKnob.m
//  JFSynth
//
//  Created by jforester on 11/22/13.
//  Copyright (c) 2013 John Forester. All rights reserved.
//

#import "JFSKnob.h"

#define MIN_ANGLE 2.2
#define MAX_ANGLE 7.2

@interface JFSKnob ()
{
    CGPoint _curentPoint;
    CGFloat _currentAngle;
}

@property (nonatomic, strong) CAShapeLayer *valueLayer;
@property (nonatomic, strong) CAShapeLayer *innerCircleLayer;

@end

@implementation JFSKnob

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self setUpKnob];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    
    if (self) {
        [self setUpKnob];
    }
    
    return self;
}

- (void)setUpKnob
{
    _minimumValue = 0.0;
    _maximumValue = 1.0;
    
    _valueLayer = [CAShapeLayer layer];
    _valueLayer.fillColor = [UIColor redColor].CGColor;
    _valueLayer.strokeColor = [UIColor blackColor].CGColor;
    _valueLayer.lineWidth = 1.0;
    
    _currentAngle = MAX_ANGLE;
    
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds))
                                                        radius:self.frame.size.width/2
                                                    startAngle:MIN_ANGLE
                                                      endAngle:MAX_ANGLE
                                                     clockwise:YES];
    
    
    [path addLineToPoint:CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds))];
    [path closePath];
    
    _valueLayer.path = path.CGPath;
    
    [self.layer addSublayer:_valueLayer];
    
    path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds))
                                          radius:self.frame.size.width/4
                                      startAngle:0.0
                                        endAngle:2 * M_PI
                                       clockwise:YES];
    
    _innerCircleLayer = [CAShapeLayer layer];
    _innerCircleLayer.fillColor = self.backgroundColor.CGColor;
    _innerCircleLayer.strokeColor = [UIColor blackColor].CGColor;
    _innerCircleLayer.lineWidth = 1.0;
    _innerCircleLayer.path = path.CGPath;
    
    [self.layer addSublayer:_innerCircleLayer];
}

- (void)updateKnobWithAngle:(CGFloat)angle
{
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds))
                                                        radius:self.frame.size.width/2
                                                    startAngle:MIN_ANGLE
                                                      endAngle:angle
                                                     clockwise:YES];
    
    [path addLineToPoint:CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds))];
    [path closePath];
    
    self.valueLayer.path = path.CGPath;
}

#pragma mark - accessors

- (void)setValue:(Float32)value
{
    _value = value;
    
    CGFloat angle = ((value - self.minimumValue) / (self.maximumValue + self.minimumValue)) * MAX_ANGLE;
    
    NSLog(@"angle %f", angle);
    
    [self updateKnobWithAngle:angle];
}

#pragma mark - touches

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event
{
    _curentPoint = [touch locationInView:self];
    
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event
{
    CGPoint nextPoint = [touch locationInView:self];
    
    if (nextPoint.x != _curentPoint.x) {
        CGFloat diff = nextPoint.x - _curentPoint.x;
        CGFloat endAngle = MIN(((diff / self.bounds.size.width) * (MAX_ANGLE - MIN_ANGLE)) + _currentAngle, MAX_ANGLE);
        _currentAngle = MAX(endAngle, MIN_ANGLE);
    } else {
        CGFloat diff = _curentPoint.y - nextPoint.y;
        CGFloat endAngle = MIN(((diff / self.bounds.size.height) * (MAX_ANGLE - MIN_ANGLE)) + _currentAngle, MAX_ANGLE);
        _currentAngle = MAX(endAngle, MIN_ANGLE);
    }
    
    [self updateKnobWithAngle:_currentAngle];
    
    _curentPoint = nextPoint;

    _value = self.minimumValue + ((_currentAngle - MIN_ANGLE) / (MAX_ANGLE - MIN_ANGLE) * (self.maximumValue - self.minimumValue));

    NSLog(@"%f", self.value);

    [self sendActionsForControlEvents:UIControlEventValueChanged];
    
    return YES;
}

- (void)cancelTrackingWithEvent:(UIEvent *)event
{
    
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event
{

}

@end