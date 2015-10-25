//
//  CRC.h
//  Kodmania
//
//  Created by jveres on 2008.05.21..
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>


@interface CRC : NSObject {
	unsigned short _checksum;
}

-(unsigned short)checksum;
-(void)addbits_good:(int)value size:(int)length;
-(void)addbits_bad:(int)value size:(int)length;
-(void)reset;

@end
