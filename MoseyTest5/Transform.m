//
//  Transform.m
//  Kodmania
//
//  Created by jveres on 2008.03.22..
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "Transform.h"


@implementation Transform

-(id)init
{
	self = [super init];
	if(self != nil) {
		m00 = 1.0; m11 = 1.0; m22 = 1.0;
		m01 = 0.0; m02 = 0.0; m10 = 0.0;
		m12 = 0.0; m20 = 0.0; m21 = 0.0;
	}
	return self;
}

-(BOOL)getSquareToQuad:(int)x0 y0:(int)y0 x1:(int)x1 y1:(int)y1 x2:(int)x2  y2:(int)y2 x3:(int)x3 y3:(int)y3
{
	int dx1, dy1, dx2, dy2, dx3, dy3;
	double inv, invdet;

	dx3 = x0 - x1 + x2 - x3;
	dy3 = y0 - y1 + y2 - y3;
	
	if(dx3 == 0.0 && dy3 == 0.0) {
		m00 = x1 - x0;
		m01 = x2 - x1;
		m02 = x0;
		m10 = y1 - y0;
		m11 = y2 - y1;
		m12 = y0;
		m20 = 0.0;
		m21 = 0.0;
	} else {
		dx1 = x1 - x2;
		dy1 = y1 - y2;
		dx2 = x3 - x2;
		dy2 = y3 - y2;
	
		inv = dx1*dy2 - dx2*dy1;
		if(inv == 0.0) return NO;
		else invdet = 1.0/inv;
	
		m20 = (dx3*dy2 - dx2*dy3)*invdet;
		m21 = (dx1*dy3 - dx3*dy1)*invdet;
		m00 = x1 - x0 + m20*x1;
		m01 = x3 - x0 + m21*x3;
		m02 = x0;
		m10 = y1 - y0 + m20*y1;
		m11 = y3 - y0 + m21*y3;
		m12 = y0;
	}
	return YES;
}

-(BOOL)transform:(double)x0 y0:(double)y0 x1:(int*)x1 y1:(int*)y1
{
	double w = m20*x0 + m21*y0 + m22;
	if(w == 0.0) return NO;
	else {
		*x1 = rint((m00 * x0 + m01 * y0 + m02) / w);
		*y1 = rint((m10 * x0 + m11 * y0 + m12) / w);
	}
	return YES;
}

-(BOOL)transformWithRounding:(double)x0 y0:(double)y0 x1:(int*)x1 y1:(int*)y1
{
	double w = m20*x0 + m21*y0 + m22;
	if(w == 0.0) return NO;
	else {
		*x1 = rint(((m00 * x0 + m01 * y0 + m02) / w) + 0.5);
		*y1 = rint(((m10 * x0 + m11 * y0 + m12) / w) + 0.5);
	}
	return YES;
}

@end
