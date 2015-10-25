//
//  GolayCode.h
//  Kodmania
//
//  Created by jveres on 2008.05.21..
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>

void _inttobin(int value, char* result, int size);
int _bintoint(char* value, int size);

@interface GolayCode : NSObject {
	int generator[24];
	int check[12];
	int codewords[4096];
	int errors[4096];
}

-(id)init;
-(int)correctAndDecode:(int)word;
-(void)computeCodewords;
-(void)computeErrors;

@end
