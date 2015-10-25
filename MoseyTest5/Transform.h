//
//  Transform.h
//  Kodmania
//
//  Created by jveres on 2008.03.22..
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>


@interface Transform : NSObject {
	double m00, m11, m22, m01, m02, m10, m12, m20, m21;
}

-(BOOL)getSquareToQuad:(int)x0 y0:(int)y0 x1:(int)x1 y1:(int)y1 x2:(int)x2  y2:(int)y2 x3:(int)x3 y3:(int)y3;
-(BOOL)transform:(double)x0 y0:(double)y0 x1:(int*)x1 y1:(int*)y1;
-(BOOL)transformWithRounding:(double)x0 y0:(double)y0 x1:(int*)x1 y1:(int*)y1;

@end
