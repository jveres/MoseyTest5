//
//  CRC.m
//  Kodmania
//
//  Created by jveres on 2008.05.21..
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "CRC.h"


@implementation CRC

-(unsigned short)checksum
{
	return _checksum;
}

-(void)addbits_good:(int)value size:(int)length
{
	unsigned int mask = 1 << (length - 1), i;
	for(i=0; i<length; i++) {
		if (((_checksum & 0x8000) == 0) ^ ((value & mask) == 0)) {
			_checksum <<= 1;
			_checksum ^= 0x8005;
		} else {
			_checksum <<= 1;
		}
		mask >>= 1;
	}
}

-(void)addbits_bad:(int)value size:(int)length
{
	unsigned int mask = 1 << (length - 1), i;
	for(i=0; i<length; i++) {
		_checksum <<= 1;
		if (((_checksum & 0x8000) == 0) ^ ((value & mask) == 0)) _checksum ^= 0x8005;
		mask >>= 1;
	}
}

-(void)reset
{
	_checksum = 0xFFFF;
}

@end
