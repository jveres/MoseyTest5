//
//  GolayCode.m
//  Kodmania
//
//  Created by jveres on 2008.05.21..
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "GolayCode.h"

static int MASK = 0xfff;

static unsigned int _pws[32] = {
	1u, 2u, 4u, 8u, 16u, 32u, 64u, 128u, 
	256u, 512u, 1024u, 2048u, 4096u, 8192u, 16384u, 32768u, 
	65536u, 131072u, 262144u, 524288u, 1048576u, 2097152u, 4194304u, 8388608u, 
 	16777216u, 33554432u, 67108864u, 134217728u, 268435456u, 536870912u, 1073741824u, 2147483648u
};

void _inttobin(int value, char* result, int size) {
	int i, j;
	for(i=0; i<size; i++) {
		j = size-i-1;
		if(value&_pws[i]) result[j] = '1';
		else result[j] = '0';
	}
}

int _bintoint(char* value, int size) {
	int i;
	int result = 0;
	for(i=0; i<size; i++) {
		if(value[i]=='1') result += _pws[size-i-1];
	}
	return result;
}

static int _bitcount(int value) {
	int i;
	int result = 0;
	for(i=0; i<32; i++) if(value&_pws[i]) result++;
	return result;
}

@implementation GolayCode

-(id)init 
{
	self = [super init];
	if(self != nil) {
		generator[ 0] = _bintoint("100000000000", 12);
		generator[ 1] = _bintoint("010000000000", 12);
		generator[ 2] = _bintoint("001000000000", 12);
		generator[ 3] = _bintoint("000100000000", 12);
		generator[ 4] = _bintoint("000010000000", 12);
		generator[ 5] = _bintoint("000001000000", 12);
		generator[ 6] = _bintoint("000000100000", 12);
		generator[ 7] = _bintoint("000000010000", 12);
		generator[ 8] = _bintoint("000000001000", 12);
		generator[ 9] = _bintoint("000000000100", 12);
		generator[10] = _bintoint("000000000010", 12);
		generator[11] = _bintoint("000000000001", 12);
		generator[12] = _bintoint("011111111111", 12);
		generator[13] = _bintoint("111011100010", 12);
		generator[14] = _bintoint("110111000101", 12);
		generator[15] = _bintoint("101110001011", 12);
		generator[16] = _bintoint("111100010110", 12);
		generator[17] = _bintoint("111000101101", 12);
		generator[18] = _bintoint("110001011011", 12);
		generator[19] = _bintoint("100010110111", 12);
		generator[20] = _bintoint("100101101110", 12);
		generator[21] = _bintoint("101011011100", 12);
		generator[22] = _bintoint("110110111000", 12);
		generator[23] = _bintoint("101101110001", 12);
		
		check[ 0] = _bintoint("011111111111100000000000", 24);
		check[ 1] = _bintoint("111011100010010000000000", 24);
		check[ 2] = _bintoint("110111000101001000000000", 24);
		check[ 3] = _bintoint("101110001011000100000000", 24);
		check[ 4] = _bintoint("111100010110000010000000", 24);
		check[ 5] = _bintoint("111000101101000001000000", 24);
		check[ 6] = _bintoint("110001011011000000100000", 24);
		check[ 7] = _bintoint("100010110111000000010000", 24);
		check[ 8] = _bintoint("100101101110000000001000", 24);
		check[ 9] = _bintoint("101011011100000000000100", 24);
		check[10] = _bintoint("110110111000000000000010", 24);
		check[11] = _bintoint("101101110001000000000001", 24);
		
		[self computeCodewords];
		[self computeErrors];
	}
	return self;
}

-(int)syndrome:(int)word
{
	int syndrome = 0, j;
	for(j=0; j<12; j++) {
		int d = word & check[j];
		int p = _bitcount(d);
		syndrome = (syndrome << 1) | (p & 1);
	}
	return syndrome;
}

-(void)computeCodewords 
{
	int i, j;
	for(i=0; i<4096; i++) {
		int cw = 0;
        for(j= 0; j<24; j++) {
			int d = i & generator[j];
			int p = _bitcount(d);
			cw = (cw << 1) | (p & 1);
		}
		codewords[i] = cw;
	}
}

-(void)computeErrors
{
	int i, j, k;
	for(i=0; i<4096; i++) errors[i] = -1;
	
	int error = 0;
	int syn = [self syndrome:error];
	errors[syn] = error;
	
	for(i=0; i<24; i++) {
		error = 1 << i;
		syn = [self syndrome:error];
		errors[syn] = error;
	}
	
	for(i=1;i<24; i++) {
		int j;
		for(j=0; j<i; j++) {
			error = (1 << i) | (1 << j);
			syn = [self syndrome:error];
			errors[syn] = error;
		}
	}
	
	for(i=2; i<24; i++) {
		for(j=1; j<i; j++) {
			for(k=0; k<j; k++) {
				error = (1 << i) | (1 << j) | (1 << k);
				syn = [self syndrome:error];
				errors[syn] = error;
			}
		}
	}
}

-(int)encode:(int)data
{
	return codewords[data];
}

-(int)isCodeword:(int)word 
{
	int w = _bitcount(word);
    if (w != 0 && w != 8 && w != 12 && w != 16 && w != 24) return 0;
	return [self syndrome:word] == 0;
}

-(int)decode:(int)codeword 
{
	return (codeword >> 12) & MASK;
}

-(int)correctAndDecode:(int)word 
{
	int err = errors[[self syndrome:word]];
	return err <= 0 ? [self decode:word] : [self decode:word^err];
}

@end
