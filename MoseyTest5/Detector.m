//
//  Detector.m
//  iCode
//
//  Created by jveres on 2008.03.11.
//  Copyright 2008 Bryton Media Group. All rights reserved.
//

#import "Detector.h"

@implementation Detector

@synthesize flt;
@synthesize w;
@synthesize h;
@synthesize markerCount;
@synthesize barcodeCount;

static int tmap[MAX_IMAGE_SIZE];
static int randtable[8];

static MARKER markers[MAX_MARKER_COUNT];
static BARCODE barcodes[MAX_BARCODE_COUNT];

-(id)init
{
	self = [super init];
	if(self != nil) {
		randtable[0] = _bintoint("001000001011010001100000", 24);
		randtable[1] = _bintoint("110110010101000100111000", 24);
		randtable[2] = _bintoint("100100111100101101111010", 24);
		randtable[3] = _bintoint("001110010111000010111110", 24);
		randtable[4] = _bintoint("001011011100100111110110", 24);
		randtable[5] = _bintoint("000111011111000000111010", 24);
		randtable[6] = _bintoint("111010010111000010110111", 24);
		randtable[7] = _bintoint("111101000010010100000011", 24);
        img = NULL;
		flt = NULL;
		min_max = NULL;
		threshold = NULL;
		golay = [[GolayCode alloc] init];
		tr = [[Transform alloc] init];
		crc = [[CRC alloc] init];
	}
	return self;
}

- (void)dealloc {
	[crc release];
	[golay release];
	[tr release];
    if(flt) free(flt);
	if(min_max) free(min_max);
    if(threshold) free(threshold);
    [super dealloc];
}

- (void)setBitmap:(unsigned char *)bitmap
{
    img = bitmap;
}

- (BOOL)setBitmapSize:(CGSize)bitmapSize
{
	if(bitmapSize.width*bitmapSize.height > MAX_IMAGE_SIZE) {
		img = NULL;
		NSLog(@"Too big image (%dx%d)", (int)bitmapSize.width, (int)bitmapSize.height);
		return NO;
	}
	w = bitmapSize.width;
	h = bitmapSize.height;
	if(flt) free(flt); 
	flt = (unsigned char*)malloc(w*h);
	int first_vector_size = FILTER_TILE2;
    int full_span_count = (w-first_vector_size)/FILTER_TILE;
    int min_max_width = full_span_count+2;
    int first_block_height = FILTER_TILE2;
    int full_block_count = (h-first_block_height)/FILTER_TILE;
    int min_max_height = full_block_count+2;
    int threshold_width = (w/FILTER_TILE)+1;
    int threshold_height = (h/FILTER_TILE)+1;
	if(min_max) free(min_max);
    min_max = (unsigned char*)malloc(min_max_width*min_max_height*2);
	if(threshold) free(threshold);
    threshold = (unsigned char*)malloc(threshold_width*threshold_height);
	return YES;
}

static void init_min_max(unsigned char *min_max_dest, int count) {
    int i;
    for(i=count; i>0; --i) {
        min_max_dest[0] = 255;
        min_max_dest[1] = 0;
        min_max_dest += 2;
    }
}

static void compute_span_min_max(unsigned char *min_max_dest, const unsigned char *source, int count) {
    int i;
    unsigned char min = min_max_dest[0];
    unsigned char max = min_max_dest[1];
    for( i=count; i > 0; --i ) {
        unsigned char x = *source;
        source++;
        if(x<min) min = x;
        else if(x>max) max = x;
    }
    min_max_dest[0] = min;
    min_max_dest[1] = max;
}

static void compute_multiple_spans_min_max(unsigned char *min_max_dest, const unsigned char *source, int vector_size, int span_count) {
    int i;
    for(i=0; i < span_count; ++i ) {
        compute_span_min_max(min_max_dest, source, vector_size);
        min_max_dest += 2;
        source += vector_size;
    }
}

static void compute_line_min_max_spans(unsigned char *min_max_dest, const unsigned char *source, int first_vector_size, int full_span_count, int last_vector_size) {
    compute_span_min_max(min_max_dest, source, first_vector_size);
    source += first_vector_size;
    min_max_dest += 2;
    compute_multiple_spans_min_max(min_max_dest, source, FILTER_TILE, full_span_count);
    source += full_span_count * FILTER_TILE;
    min_max_dest += 2*full_span_count;
    compute_span_min_max(min_max_dest, source, last_vector_size);
}

static void compute_frame_min_max_tiles(unsigned char *min_max_dest, const unsigned char *source, int width, int height) {
    int first_vector_size = FILTER_TILE2;
    int full_span_count = (width - first_vector_size) / FILTER_TILE;
    int last_vector_size = width - first_vector_size - (full_span_count * FILTER_TILE);
    int first_block_height = FILTER_TILE2;
    int full_block_count = (height - first_block_height) / FILTER_TILE;
    int last_block_height = height - first_block_height - (full_block_count * FILTER_TILE);
    int i, j;
	
    init_min_max(min_max_dest, full_span_count + 2);
    for( i=0; i < first_block_height; ++i ) {
        compute_line_min_max_spans( min_max_dest, source, first_vector_size, full_span_count, last_vector_size);
        source += width;
    }
    min_max_dest += 2 * (full_span_count + 2);
    for( i=0; i < full_block_count; ++i ) {
        init_min_max(min_max_dest, full_span_count + 2);
        for(j=0; j < FILTER_TILE; ++j) {
            compute_line_min_max_spans(min_max_dest, source, first_vector_size, full_span_count, last_vector_size);
            source += width;
        }
        min_max_dest += 2 * (full_span_count + 2);
    }
    init_min_max(min_max_dest, full_span_count + 2);
    for( i=0; i < last_block_height; ++i ) {
        compute_line_min_max_spans(min_max_dest, source, first_vector_size, full_span_count, last_vector_size);
        source += width;
    }
}

static void compute_row_thresholds(unsigned char *thresholds_dest, const unsigned char *min_max_a, const unsigned char *min_max_b, int count)
{
    int i;
    unsigned char min_a, max_a, min_b, max_b;
	
    for( i = 0; i < count; ++i ) {
        min_a = min_max_a[0];
        max_a = min_max_a[1];
        if( min_max_a[2] < min_a ) min_a = min_max_a[2];
        if( min_max_a[3] > max_a ) max_a = min_max_a[3];
        min_max_a += 2;
		
        min_b = min_max_b[0];
        max_b = min_max_b[1];
        if( min_max_b[2] < min_b ) min_b = min_max_b[2];
        if( min_max_b[3] > max_b ) max_b = min_max_b[3];
        min_max_b += 2;
		
        if( min_b < min_a ) min_a = min_b;
        if( max_b > max_a ) max_a = max_b;

		if(max_a-min_a<FILTER_THRESHOLD) *thresholds_dest++ = BLACK;
		else *thresholds_dest++ = (unsigned char)((min_a+max_a)>>1);
    }
}

static void apply_frame_thresholds(unsigned char *dest, const unsigned char *source, const unsigned char *threshold, int width, int height)
{
    int j, k, m, n;
    int tile_width, tile_height;
    const unsigned char *t;
    int threshold_width = (width/FILTER_TILE) + 1;
	
    for( j = 0; j < height; j += FILTER_TILE ){
        tile_height = (j + FILTER_TILE > height) ? height - j : FILTER_TILE;
        for( k = 0; k < tile_height; ++k ){
            t = threshold;
            for( m=0; m < width; m += FILTER_TILE ){
                unsigned char tt = *t++;
                tile_width = (m + FILTER_TILE > width) ? width - m : FILTER_TILE;
                for( n=tile_width; n >0; --n ){
                    *dest++ = (*source > tt) ? WHITE : BLACK;
                    source++;
                }
            }
        }
        threshold += threshold_width;
    }
}

static void compute_frame_threshold_tiles(unsigned char *thresholds_dest, const unsigned char *min_max, int width, int height)
{
    int first_vector_size = FILTER_TILE2;
    int full_span_count = (width - first_vector_size) / FILTER_TILE;
    int min_max_width = full_span_count + 2;
    int threshold_width = (width/FILTER_TILE) + 1;
    int threshold_height = (height/FILTER_TILE) + 1;
    int i;
	
    for(i = 0; i < threshold_height; ++i ){
        compute_row_thresholds( thresholds_dest, min_max, min_max + min_max_width * 2, threshold_width);
        thresholds_dest += threshold_width;
        min_max += min_max_width * 2;
    }
}

// nagyon gyors, de nem túl pontos a kontúr pontok meghatározásában
-(void)binarize {
	compute_frame_min_max_tiles(min_max, img, w, h);
    compute_frame_threshold_tiles(threshold, min_max, w, h);	
    apply_frame_thresholds(flt, img, threshold, w, h);
}

#define PIXEL(X, Y) (flt[(Y)*w+(X)])
#define BLACK_PIXEL(X, Y) (PIXEL(X, Y) == BLACK)
#define WHITE_PIXEL(X, Y) (PIXEL(X, Y) == WHITE)
#define PIXEL_IS(X, Y, VALUE) (PIXEL(X, Y) == VALUE)
#define MAP(X, Y) (tmap[Y*w+X])

- (int)marchValue:(unsigned char)pixelColor pixelX:(int)x pixelY:(int)y
{
	int sum = 0;
	if(PIXEL_IS(x, y, pixelColor)) sum |= 1;
	if(PIXEL_IS(x + 1, y, pixelColor)) sum |= 2;
	if(PIXEL_IS(x, y + 1, pixelColor)) sum |= 4;
	if(PIXEL_IS(x + 1, y + 1, pixelColor)) sum |= 8;
	return sum;
}

#define SEED_PIXEL BLACK
#define MAX_MARKER_SIZE_RATIO 5

// végigmegyünk a kontúron és ha gyűrűnek tűnik, visszaadjuk a paramétereit
- (void)marchingSquares:(unsigned char)pixelColor pixelX:(int)x0 pixelY:(int)y0
{	
	int mv;
	int x = x0, y = y0;
	int sx, sy, fp_maxy_x;
	int px = 0, py = 0;

	// kezdeti értékek
	fp_minx = w; fp_maxx = 0; fp_miny = h; fp_maxy = 0;
	fp_fail = YES;
	
	do {
		if(x<0 || y<0 || x>=w-2 || y>=h-2 || MAP(x, y)) return;

		MAP(x, y) = fp_map;
		
		mv = [self marchValue:pixelColor pixelX:x pixelY:y];
		if(mv<1 || mv>14) return;
		switch(mv) {
			case  1: sx =  0; sy = -1; break;
			case  2: sx =  1; sy =  0; break;
			case  3: sx =  1; sy =  0; break;
			case  4: sx = -1; sy =  0; break;
			case  5: sx =  0; sy = -1; break;
			case  6: if(px == 0 && py == -1) { sx = -1; sy =  0; } else { sx =  1; sy =  0; }; break;
			case  7: sx =  1; sy =  0; break;
			case  8: sx =  0; sy =  1; break;
			case  9: if(px == 1 && py == 0) { sx =  0; sy = -1; } else { sx =  0; sy =  1; }; break;
			case 10: sx =  0; sy =  1; break;
			case 11: sx =  0; sy =  1; break;
			case 12: sx = -1; sy =  0; break;
			case 13: sx =  0; sy = -1; break;
			case 14: sx = -1; sy =  0; break;
		}
        
		if(x < fp_minx) fp_minx = x;
		else if(x > fp_maxx) fp_maxx = x;
		if(y < fp_miny) fp_miny = y;
		else if(y > fp_maxy) {
			fp_maxy = y;
			fp_maxy_x = x;
		}
		
		px = sx; py = sy;
		x += sx; y += sy;
		
	} while (x != x0 || y != y0);
		
	// megnézzük a méretét
	int aw = fp_maxx-fp_minx;
	int ah = fp_maxy-fp_miny;
	if(!(aw > MIN_MARKER_WIDTH && ah > MIN_MARKER_HEIGHT && aw < MAX_MARKER_WIDTH && ah < MAX_MARKER_HEIGHT)) return;
	
	// megnézzük az oldalhosszak arányát
	if(aw*MAX_MARKER_SIZE_RATIO<ah || ah*MAX_MARKER_SIZE_RATIO<aw) return;
	
	// középpont
	fp_cx = fp_minx+((double)aw/2.0)+1;
	fp_cy = fp_miny+((double)ah/2.0)+1;
	
	// méret
	fp_aw = aw;
	fp_ah = ah;
	
	// szín
	fp_color = PIXEL(fp_maxy_x, fp_maxy+1) == BLACK ? WHITE : BLACK;
	
	fp_fail = NO;
}

-(void)deleteMarker:(int)i
{
	markers[i]=markers[--markerCount];
}

#define MAX_CONCENTRIC_DISTANCE 5
#define MAX_CONCENTRIC_SIZE_RATIO 5

// markerek (gyűrűk) megkeresése a képen
- (void)detectMarkers
{
	int x, y;
	fp_map = 1;
	memset(tmap, (int)0, sizeof(int)*w*h);
	markerCount = 0;
	y = 0;
	while(y < h-1) {
		x = 0;
		while(x < w-2) {
			if(MAP(x, y)==0) {
				[self marchingSquares:SEED_PIXEL pixelX:x pixelY:y];
				if(!fp_fail) {
					markers[markerCount].cx = fp_cx;
					markers[markerCount].cy = fp_cy;
					markers[markerCount].x1 = fp_minx;
					markers[markerCount].y1 = fp_miny;
					markers[markerCount].x2 = fp_maxx;
					markers[markerCount].y2 = fp_maxy;
					markers[markerCount].w = fp_aw;
					markers[markerCount].h = fp_ah;
					markers[markerCount].size = fp_aw*fp_ah;
					markers[markerCount].color = fp_color;
					markers[markerCount].ring = NO;
					markers[markerCount].matched = NO;
					markers[markerCount].outer = NO;
					markerCount++;
					if(markerCount==MAX_MARKER_COUNT) {
						NSLog(@"[Detector] Max markerCount reached!");
						return;
					}
				}
				fp_map++;
			}
			x += STEP_X;
		}
		y += STEP_Y;
	}
}

// koncentrikus ellipszisek (gyűrűk) kiválasztása
-(void)selectRings
{
	int i=0, j=0;
	while(i<markerCount) {
		MARKER mi = markers[i];
		if(mi.ring || mi.matched || mi.outer) goto left_i;
		markers[i].matched = YES;
		j=0;
		while(j<markerCount) {
			MARKER mj = markers[j];
			if(mj.matched || mj.ring || mj.outer || mi.color==mj.color) goto left_j;
			int dx = abs(mi.cx - mj.cx);
			int dy = abs(mi.cy - mj.cy);
			if(dx < MAX_CONCENTRIC_DISTANCE && dy < MAX_CONCENTRIC_DISTANCE 
			   && mi.size<MAX_CONCENTRIC_SIZE_RATIO*mj.size && mj.size<MAX_CONCENTRIC_SIZE_RATIO*mi.size) {
				if(mi.size < mj.size && mj.color==BLACK) {
					markers[i].ring = YES;
					markers[j].outer = YES;
				} else if(mj.size < mi.size && mi.color==BLACK) {
					markers[j].ring = YES;
					markers[i].outer = YES;
				}
			}
		left_j:
			j++;
		}
	left_i:
		i++;
	}
}

#define H(c) (c*z)
#define BIT(x, y) (flt[y*w+x]==ring_color ? '0' : '1')

// orientáció
const char bo_top[]    = "00011011";
const char bo_right[]  = "01101100";
const char bo_bottom[] = "10110001";
const char bo_left[]   = "11000110";

// adatbit csoport típus
typedef char databit[10][5];

#define D1(i,j) (char)(*((databit*)d1))[i][j]
#define D2(i,j) (char)(*((databit*)d2))[i][j]
#define D3(i,j) (char)(*((databit*)d3))[i][j]
#define D4(i,j) (char)(*((databit*)d4))[i][j]

-(BOOL)testBarcode:(int)m1 m2:(int)m2 m3:(int)m3 m4:(int)m4
{	
	static double z = 1.0/17;
	
	MARKER b1=markers[m1];
	MARKER b2=markers[m2];
	MARKER b3=markers[m3];
	MARKER b4=markers[m4];
	
	// az óra járásával egyezően állítjuk be
	MARKER m;
	if(b1.cx>b2.cx) {
		m = b1;
		b1 = b2;
		b2 = m;
		m = b3;
		b3 = b4;
		b4 = m;
	}
	
	// gyűrű színe
	unsigned char ring_color = b1.color;
	
	// perspektív transzformáció
	if(![tr getSquareToQuad:b1.cx y0:b1.cy x1:b2.cx y1:b2.cy x2:b3.cx y2:b3.cy x3:b4.cx y3:b4.cy]) return NO;
	
	// keret koordináták
	if(![tr transform:H(-2) y0:H(-2) x1:&(b1.cx) y1:&(b1.cy)]) return NO;
	if(b1.cx<0 || b1.cx>w-1 || b1.cy<0 || b1.cy>h-1) return NO;
	if(![tr transform:H(19) y0:H(-2) x1:&(b2.cx) y1:&(b2.cy)]) return NO;
	if(b2.cx<0 || b2.cx>w-1 || b2.cy<0 || b2.cy>h-1) return NO;
	if(![tr transform:H(19) y0:H(19) x1:&(b3.cx) y1:&(b3.cy)]) return NO;
	if(b3.cx<0 || b3.cx>w-1 || b3.cy<0 || b3.cy>h-1) return NO;
	if(![tr transform:H(-2) y0:H(19) x1:&(b4.cx) y1:&(b4.cy)]) return NO;
	if(b4.cx<0 || b4.cx>w-1 || b4.cy<0 || b4.cy>h-1) return NO;
	
	// orientáció meghatározása
	int px, py;
	char o[] = "00000000";
	
	// fent
	[tr transform:H(8) y0:H(2) x1:&px y1:&py];
	o[0] = BIT(px, py);
	[tr transform:H(9) y0:H(2) x1:&px y1:&py];
	o[1] = BIT(px, py);
	
	// jobbra
	[tr transform:H(15) y0:H(8) x1:&px y1:&py];
	o[2] = BIT(px, py);
	[tr transform:H(15) y0:H(9) x1:&px y1:&py];
	o[3] = BIT(px, py);
	
	// lent
	[tr transform:H(9) y0:H(15) x1:&px y1:&py];
	o[4] = BIT(px, py);
	[tr transform:H(8) y0:H(15) x1:&px y1:&py];
	o[5] = BIT(px, py);
	
	// balra
	[tr transform:H(2) y0:H(9) x1:&px y1:&py];
	o[6] = BIT(px, py);
	[tr transform:H(2) y0:H(8) x1:&px y1:&py];
	o[7] = BIT(px, py);
	
	// adatbit csoportok
	static databit db1;
	static databit db2;
	static databit db3;
	static databit db4;
	
	static databit* d1;  // felső
	static databit* d2;  // jobb
	static databit* d3;  // alsó 
	static databit* d4;  // bal
	
	// az orientációnak megfelelően beállítjuk a bitcsoport mutatókat (d1-felső, d2-jobb, d3-alsó, d4-bal)
	if(strcmp(o, bo_top)==0) {
		d1 = &db1;
		d2 = &db2;
		d3 = &db3;
		d4 = &db4;
	} else if(strcmp(o, bo_right)==0) {
		d2 = &db1;
		d3 = &db2;
		d4 = &db3;
		d1 = &db4;
	} else if(strcmp(o, bo_bottom)==0) {
		d3 = &db1;
		d4 = &db2;
		d1 = &db3;
		d2 = &db4;
	} else if(strcmp(o, bo_left)==0) {
		d4 = &db1;
		d1 = &db2;
		d2 = &db3;
		d3 = &db4;
	} else return NO;  // nem találtuk meg az orientációs biteket
	
	int x, y;
	
	// feltöltjük az adatbit mátrixokat
	// első adatcsoport
	for(y=-2; y<=2; y++) {
		for(x=4; x<=13; x++) {
			[tr transform:H(x) y0:H(y) x1:&px y1:&py];
			db1[x-4][y+2] = BIT(px, py);
		}
	}
	
	// második adatcsoport
	for(x=19; x>=15; x--) {
		for(y=4; y<=13; y++) {
			[tr transform:H(x) y0:H(y) x1:&px y1:&py];
			db2[y-4][19-x] = BIT(px, py);
		}
	}
	
	// harmadik adatcsoport
	for(y=19; y>=15; y--) {
		for(x=13; x>=4; x--) {
			[tr transform:H(x) y0:H(y) x1:&px y1:&py];
			db3[13-x][19-y] = BIT(px, py);
		}
	}
	
	// negyedik adatcsoport
	for(x=-2; x<=2; x++) {
		for(y=13; y>=4; y--) {
			[tr transform:H(x) y0:H(y) x1:&px y1:&py];
			db4[13-y][x+2] = BIT(px, py);
		}
	}
	
	// adatbitek dekódolása	
	static char cws_24[] = "000000000000000000000000";
	static int cws_12[8] = {};
	int i;
	//
	cws_24[0]  = D1(0, 0); 
	cws_24[1]  = D1(3, 1); 
	cws_24[2]  = D1(1, 3); 
	cws_24[3]  = D1(6, 0);
	cws_24[4]  = D1(9, 1); 
	cws_24[5]  = D1(7, 3); 
	cws_24[6]  = D2(2, 0);
	cws_24[7]  = D2(0, 2);
	cws_24[8]  = D2(3, 3); 
	cws_24[9]  = D2(8, 0); 
	cws_24[10] = D2(6, 2); 
	cws_24[11] = D2(9, 3);
	cws_24[12] = D3(4, 0); 
	cws_24[13] = D3(2, 2); 
	cws_24[14] = D3(0, 4); 
	cws_24[15] = D3(5, 1);
	cws_24[16] = D3(8, 2); 
	cws_24[17] = D3(7, 4); 
	cws_24[18] = D4(1, 1); 
	cws_24[19] = D4(4, 2);
	cws_24[20] = D4(2, 4); 
	cws_24[21] = D4(7, 1); 
	cws_24[22] = D4(5, 3); 
	cws_24[23] = D4(9, 4);
	i = 0;
	cws_12[i] = _bintoint(cws_24, 24) ^ randtable[i];
	cws_12[i] = [golay correctAndDecode:cws_12[i]];
	//
	cws_24[0]  = D1(1, 0); 
	cws_24[1]  = D1(4, 1); 
	cws_24[2]  = D1(2, 3); 
	cws_24[3]  = D1(7, 0);
	cws_24[4]  = D1(5, 2); 
	cws_24[5]  = D1(8, 3); 
	cws_24[6]  = D2(3, 0); 
	cws_24[7]  = D2(1, 2);
	cws_24[8]  = D2(4, 3); 
	cws_24[9]  = D2(9, 0); 
	cws_24[10] = D2(7, 2); 
	cws_24[11] = D2(6, 4);
	cws_24[12] = D3(0, 1); 
	cws_24[13] = D3(3, 2); 
	cws_24[14] = D3(1, 4); 
	cws_24[15] = D3(6, 1);
	cws_24[16] = D3(9, 2); 
	cws_24[17] = D3(8, 4); 
	cws_24[18] = D4(2, 1); 
	cws_24[19] = D4(0, 3);
	cws_24[20] = D4(3, 4); 
	cws_24[21] = D4(8, 1); 
	cws_24[22] = D4(6, 3); 
	cws_24[23] = D4(5, 0);
	i = 1;
	cws_12[i] = _bintoint(cws_24, 24) ^ randtable[i];
	cws_12[i] = [golay correctAndDecode:cws_12[i]];
	//
	cws_24[0]  = D1(2, 0); 
	cws_24[1]  = D1(0, 2); 
	cws_24[2]  = D1(3, 3); 
	cws_24[3]  = D1(8, 0);
	cws_24[4]  = D1(6, 2); 
	cws_24[5]  = D1(9, 3); 
	cws_24[6]  = D2(4, 0); 
	cws_24[7]  = D2(2, 2);
	cws_24[8]  = D2(0, 4); 
	cws_24[9]  = D2(5, 1); 
	cws_24[10] = D2(8, 2); 
	cws_24[11] = D2(7, 4);
	cws_24[12] = D3(1, 1); 
	cws_24[13] = D3(4, 2); 
	cws_24[14] = D3(2, 4); 
	cws_24[15] = D3(7, 1);
	cws_24[16] = D3(5, 3); 
	cws_24[17] = D3(9, 4); 
	cws_24[18] = D4(3, 1); 
	cws_24[19] = D4(1, 3);
	cws_24[20] = D4(0, 0); 
	cws_24[21] = D4(9, 1); 
	cws_24[22] = D4(7, 3); 
	cws_24[23] = D4(6, 0);
	i = 2;
	cws_12[i] = _bintoint(cws_24, 24) ^ randtable[i];
	cws_12[i] = [golay correctAndDecode:cws_12[i]];
	//
	cws_24[0]  = D1(3, 0); 
	cws_24[1]  = D1(1, 2); 
	cws_24[2]  = D1(4, 3); 
	cws_24[3]  = D1(9, 0);
	cws_24[4]  = D1(7, 2); 
	cws_24[5]  = D1(6, 4); 
	cws_24[6]  = D2(0, 1); 
	cws_24[7]  = D2(3, 2);
	cws_24[8]  = D2(1, 4); 
	cws_24[9]  = D2(6, 1); 
	cws_24[10] = D2(9, 2); 
	cws_24[11] = D2(8, 4);
	cws_24[12] = D3(2, 1); 
	cws_24[13] = D3(0, 3); 
	cws_24[14] = D3(3, 4); 
	cws_24[15] = D3(8, 1);
	cws_24[16] = D3(6, 3); 
	cws_24[17] = D3(5, 0); 
	cws_24[18] = D4(4, 1); 
	cws_24[19] = D4(2, 3);
	cws_24[20] = D4(1, 0); 
	cws_24[21] = D4(5, 2); 
	cws_24[22] = D4(8, 3); 
	cws_24[23] = D4(7, 0);
	i = 3;
	cws_12[i] = _bintoint(cws_24, 24) ^ randtable[i];
	cws_12[i] = [golay correctAndDecode:cws_12[i]];
	//
	cws_24[0]  = D1(4, 0); 
	cws_24[1]  = D1(2, 2); 
	cws_24[2]  = D1(0, 4); 
	cws_24[3]  = D1(5, 1);
	cws_24[4]  = D1(8, 2); 
	cws_24[5]  = D1(7, 4); 
	cws_24[6]  = D2(1, 1); 
	cws_24[7]  = D2(4, 2);
	cws_24[8]  = D2(2, 4); 
	cws_24[9]  = D2(7, 1); 
	cws_24[10] = D2(5, 3); 
	cws_24[11] = D2(9, 4);
	cws_24[12] = D3(3, 1); 
	cws_24[13] = D3(1, 3); 
	cws_24[14] = D3(0, 0); 
	cws_24[15] = D3(9, 1);
	cws_24[16] = D3(7, 3); 
	cws_24[17] = D3(6, 0); 
	cws_24[18] = D4(0, 2); 
	cws_24[19] = D4(3, 3);
	cws_24[20] = D4(2, 0); 
	cws_24[21] = D4(6, 2); 
	cws_24[22] = D4(9, 3); 
	cws_24[23] = D4(8, 0);
	i = 4;
	cws_12[i] = _bintoint(cws_24, 24) ^ randtable[i];
	cws_12[i] = [golay correctAndDecode:cws_12[i]];
	//
	cws_24[0]  = D1(0, 1); 
	cws_24[1]  = D1(3, 2); 
	cws_24[2]  = D1(1, 4); 
	cws_24[3]  = D1(6, 1);
	cws_24[4]  = D1(9, 2); 
	cws_24[5]  = D1(8, 4); 
	cws_24[6]  = D2(2, 1); 
	cws_24[7]  = D2(0, 3);
	cws_24[8]  = D2(3, 4); 
	cws_24[9]  = D2(8, 1); 
	cws_24[10] = D2(6, 3); 
	cws_24[11] = D2(5, 0);
	cws_24[12] = D3(4, 1); 
	cws_24[13] = D3(2, 3); 
	cws_24[14] = D3(1, 0); 
	cws_24[15] = D3(5, 2);
	cws_24[16] = D3(8, 3); 
	cws_24[17] = D3(7, 0); 
	cws_24[18] = D4(1, 2); 
	cws_24[19] = D4(4, 3);
	cws_24[20] = D4(3, 0); 
	cws_24[21] = D4(7, 2); 
	cws_24[22] = D4(6, 4); 
	cws_24[23] = D4(9, 0);
	i = 5;
	cws_12[i] = _bintoint(cws_24, 24) ^ randtable[i];
	cws_12[i] = [golay correctAndDecode:cws_12[i]];
	//
	cws_24[0]  = D1(1, 1); 
	cws_24[1]  = D1(4, 2); 
	cws_24[2]  = D1(2, 4); 
	cws_24[3]  = D1(7, 1);
	cws_24[4]  = D1(5, 3); 
	cws_24[5]  = D1(9, 4); 
	cws_24[6]  = D1(3, 1); 
	cws_24[7]  = D2(1, 3);
	cws_24[8]  = D2(0, 0); 
	cws_24[9]  = D2(9, 1); 
	cws_24[10] = D2(7, 3); 
	cws_24[11] = D2(6, 0);
	cws_24[12] = D3(0, 2); 
	cws_24[13] = D3(3, 3); 
	cws_24[14] = D3(2, 0); 
	cws_24[15] = D3(6, 2);
	cws_24[16] = D3(9, 3); 
	cws_24[17] = D3(8, 0); 
	cws_24[18] = D4(2, 2); 
	cws_24[19] = D4(0, 4);
	cws_24[20] = D4(4, 0); 
	cws_24[21] = D4(8, 2); 
	cws_24[22] = D4(7, 4); 
	cws_24[23] = D4(5, 1);
	i = 6;
	cws_12[i] = _bintoint(cws_24, 24) ^ randtable[i];
	cws_12[i] = [golay correctAndDecode:cws_12[i]];
	//
	cws_24[0]  = D1(2, 1); 
	cws_24[1]  = D1(0, 3); 
	cws_24[2]  = D1(3, 4); 
	cws_24[3]  = D1(8, 1);
	cws_24[4]  = D1(6, 3); 
	cws_24[5]  = D1(5, 0); 
	cws_24[6]  = D2(4, 1); 
	cws_24[7]  = D2(2, 3);
	cws_24[8]  = D2(1, 0); 
	cws_24[9]  = D2(5, 2); 
	cws_24[10] = D2(8, 3); 
	cws_24[11] = D2(7, 0);
	cws_24[12] = D3(1, 2); 
	cws_24[13] = D3(4, 3); 
	cws_24[14] = D3(3, 0); 
	cws_24[15] = D3(7, 2);
	cws_24[16] = D3(6, 4); 
	cws_24[17] = D3(9, 0); 
	cws_24[18] = D4(3, 2); 
	cws_24[19] = D4(1, 4);
	cws_24[20] = D4(0, 1); 
	cws_24[21] = D4(9, 2); 
	cws_24[22] = D4(8, 4); 
	cws_24[23] = D4(6, 1);
	i = 7;
	cws_12[i] = _bintoint(cws_24, 24) ^ randtable[i];
	cws_12[i] = [golay correctAndDecode:cws_12[i]];

	// crc ellenőrzés
	static char cws[96] = "";
	static char bits[12] = "";
	for(i=0; i<8; i++) {
		_inttobin(cws_12[i], bits, 12);
		memcpy(cws+(i*12), bits, 12);
	}
	static unsigned int chamber, intdata;
	static unsigned short shortdata, checksum;
	static char _chamber[32] = "";
	static char _shortdata[16] = "";
	static char _intdata[32] = "";
	static char _crc[16] = "";
	memcpy(_chamber, cws, 32);
	memcpy(_shortdata, cws+32, 16);
	memcpy(_intdata, cws+48, 32);
	memcpy(_crc, cws+80, 16);
	chamber = (unsigned int)_bintoint(_chamber, 32);
	shortdata = (unsigned short)_bintoint(_shortdata, 16);
	intdata = (unsigned int)_bintoint(_intdata, 32);
	checksum = _bintoint(_crc, 16);
	[crc reset];
	if(chamber<16) {
		[crc addbits_bad:chamber size:32];
		[crc addbits_bad:shortdata size:16];
		[crc addbits_bad:intdata size:32];
	} else {
		[crc addbits_good:chamber size:32];
		[crc addbits_good:shortdata size:16];
		[crc addbits_good:intdata size:32];		
	}
	
	if(checksum!=[crc checksum]) return NO;
	
	//NSLog(@"%x:%x:%x\n", chamber, shortdata, intdata);
	
	// találtunk egy kódot
	BARCODE b;
	b.m1 = m1;
	b.m2 = m2;
	b.m3 = m3;
	b.m4 = m4;
	b.cx = rint((b1.cx+b2.cx+b3.cx+b4.cx)/4.0);
	b.cy = rint((b1.cy+b2.cy+b3.cy+b4.cy)/4.0);
	
	// külső koordináták p1, p2, p3, p4 
	// - ezek a néző számára adnak jó nézetet
	[tr transformWithRounding:H(-3.5) y0:H(-3.5) x1:&(b.p1.x) y1:&(b.p1.y)];
	[tr transformWithRounding:H(20.5) y0:H(-3.5) x1:&(b.p2.x) y1:&(b.p2.y)];
	[tr transformWithRounding:H(20.5) y0:H(20.5) x1:&(b.p3.x) y1:&(b.p3.y)];
	[tr transformWithRounding:H(-3.5) y0:H(20.5) x1:&(b.p4.x) y1:&(b.p4.y)];
	
	// az orientációnak megfelelően beállítjuk koordinátákat o1, o2, o3, o4
	// - ezek a kép elfordulásának megfelelően jók
	if(strcmp(o, bo_top)==0) {
		b.o1 = b.p1;
		b.o2 = b.p2;
		b.o3 = b.p3;
		b.o4 = b.p4;
	} else if(strcmp(o, bo_right)==0) {
		b.o2 = b.p1;
		b.o3 = b.p2;
		b.o4 = b.p3;
		b.o1 = b.p4;
	} else if(strcmp(o, bo_bottom)==0) {
		b.o3 = b.p1;
		b.o4 = b.p2;
		b.o1 = b.p3;
		b.o2 = b.p4;
	} else if(strcmp(o, bo_left)==0) {
		b.o4 = b.p1;
		b.o1 = b.p2;
		b.o2 = b.p3;
		b.o3 = b.p4;
	} else return NO;  // ez itt már nem fordulhat elő
	
	b.chamber = chamber;
	b.shortdata = shortdata;
	b.intdata = intdata;
	barcodes[barcodeCount] = b;
	barcodeCount++;
	
	return YES;
}

#define O_COLLINEAR 0
#define O_LEFT 1
#define O_RIGHT -1

static int orientation(MARKER m1, MARKER m2, MARKER m3)
{
	long orin = (m2.cx - m1.cx) * (m3.cy - m1.cy) - (m3.cx - m1.cx) * (m2.cy - m1.cy);
	if(orin>0) return O_LEFT; // balra van
	else if(orin<0) return O_RIGHT; // jobbra van
	else return O_COLLINEAR;  // egy vonalra esnek	
}

static BOOL intersect(MARKER m1, MARKER m2, MARKER m3, MARKER m4)
{
	return (orientation(m1, m2, m3) * orientation(m1, m2, m4) <= 0 && orientation(m3, m4, m1) * orientation(m3, m4, m2) <= 0);
}

#define MAX_DIAGONAL_DIFF 2

-(void)detectPolygons
{
	static int m1, m2, m3, m4, b, b1, b2, b3, b4, o1, o2, o3, o4;
	barcodeCount = 0;
	for(m1=0; m1<markerCount; m1++) {
		if(!markers[m1].ring) continue;
		for(m2=m1+1; m2<markerCount; m2++) {
			if(!markers[m2].ring || (markers[m2].color!=markers[m1].color)) continue;
			for(m3=m2+1; m3<markerCount; m3++) {
				if(!markers[m3].ring || (markers[m3].color!=markers[m1].color)) continue;
				for(m4=m3+1; m4<markerCount; m4++) {
					if(!markers[m4].ring || (markers[m4].color!=markers[m1].color)) continue;
					// konvex poligon
					b1=m1; b2=m2; b3=m3; b4=m4;
					o1 = orientation(markers[m1], markers[m3], markers[m2]);
					if(o1==O_COLLINEAR) continue;
					o2 = orientation(markers[m1], markers[m3], markers[m4]);
					if(o2==O_COLLINEAR) continue;
					o3 = orientation(markers[m2], markers[m3], markers[m1]);
					if(o3==O_COLLINEAR) continue;
					o4 = orientation(markers[m2], markers[m3], markers[m4]);
					if(o4==O_COLLINEAR) continue;
					if(o1==o2) { // m1-m3: oldal
						if(o3==o4) continue; // konkáv
						b = b3;
						b3 = b4;
						b4 = b;
					} else { // m1-m3: átló
						if(o3!=o4) continue; // konkáv
					}
					// átlók ellenőrzése
					if(!intersect(markers[b1], markers[b3], markers[b2], markers[b4])) continue;
					// minden ok, mehet a barcode teszt
					if([self testBarcode:b1 m2:b2 m3:b3 m4:b4] && barcodeCount == MAX_BARCODE_COUNT) return;
				} 
			}
		}
	}
}

-(MARKER)getMarker:(int)i
{
	return markers[i];
}

-(BARCODE)getBarcode:(int)i
{
	return barcodes[i];
}

-(void)detect
{
	[self binarize];
	[self detectMarkers];
	[self selectRings];
	[self detectPolygons];
}

@end
