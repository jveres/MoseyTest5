//
//  Detector.h
//  Kodmania
//
//  Created by jveres on 2008.03.11..
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "Transform.h"
#import "GolayCode.h"
#import "CRC.h"

#define WHITE ((unsigned char)255)
#define BLACK ((unsigned char)0)
#define MAX_IMAGE_WIDTH 640
#define MAX_IMAGE_HEIGHT 480
#define MAX_IMAGE_SIZE (MAX_IMAGE_WIDTH*MAX_IMAGE_HEIGHT)
#define FILTER_TILE 8
#define FILTER_TILE2 4
#define FILTER_THRESHOLD 16
#define STEP_X 1
#define STEP_Y 2
#define MAX_MARKER_COUNT 150
#define MAX_BARCODE_COUNT 1
#define MIN_MARKER_WIDTH 8
#define MAX_MARKER_WIDTH 70
#define MIN_MARKER_HEIGHT 8
#define MAX_MARKER_HEIGHT 70

typedef struct { 
	int cx, cy, x1, y1, x2, y2;
	int w, h, size, color;
	BOOL matched, outer, ring;
} MARKER;

typedef struct { 
	int x, y;
} POINT;

typedef struct {
	int m1, m2, m3, m4;
	POINT p1, p2, p3, p4;
	POINT o1, o2, o3, o4;
	int cx, cy;
	unsigned int chamber;
	unsigned short shortdata;
	unsigned int intdata;
} BARCODE;

@interface Detector : NSObject {
	int w, h;
	unsigned char *img;
	unsigned char *flt;
	unsigned char *min_max;
    unsigned char *threshold;
	
	BOOL fp_fail;
	int fp_minx, fp_miny, fp_maxx, fp_maxy, fp_map, fp_cx, fp_cy, fp_aw, fp_ah, fp_color;
	int markerCount, barcodeCount;
	GolayCode* golay;
	Transform* tr;
	CRC* crc;
}

- (void)setBitmap:(unsigned char *)bitmap;
- (BOOL)setBitmapSize:(CGSize)bitmapSize;
- (void)binarize;
- (void)detectMarkers;
- (void)detectPolygons;
- (MARKER)getMarker:(int)i;
- (BARCODE)getBarcode:(int)i;
- (void)detect;

@property (readonly) unsigned char *flt;
@property (assign) int w;
@property (assign) int h;
@property (readonly) int markerCount;
@property (readonly) int barcodeCount;

@end
