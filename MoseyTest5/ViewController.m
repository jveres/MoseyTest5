//
//  ViewController.m
//  MoseyTest5
//
//  Created by Veres János on 2011.10.18..
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "ViewController.h"
#import "Detector.h"

@implementation ViewController {
    AVCaptureSession *session;
    AVCaptureVideoDataOutput *videoDataOutput;
	dispatch_queue_t videoDataOutputQueue;
    AVCaptureVideoPreviewLayer *previewLayer;
    Detector *detector;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}

- (void)setupAVCapture
{
	NSError *error = nil;
	
	session = [[AVCaptureSession alloc] init];
    
    [session setSessionPreset:AVCaptureSessionPresetMedium];
	
    // Select a video device, make an input
	AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
	
	if ([session canAddInput:deviceInput]) [session addInput:deviceInput];
	
    // Make a video data output
	videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
	
	NSDictionary *rgbOutputSettings = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
	[videoDataOutput setVideoSettings:rgbOutputSettings];
	[videoDataOutput setAlwaysDiscardsLateVideoFrames:YES]; // discard if the data output queue is blocked (as we process the still image)
    
    // create a serial dispatch queue used for the sample buffer delegate as well as when a still image is captured
    // a serial dispatch queue must be used to guarantee that video frames will be delivered in order
    // see the header doc for setSampleBufferDelegate:queue: for more information
	videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
	[videoDataOutput setSampleBufferDelegate:self queue:videoDataOutputQueue];
	
    if([session canAddOutput:videoDataOutput]) [session addOutput:videoDataOutput];
	[[videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:YES];
	
    CALayer *rootLayer = [self.view layer];
    
    // Preview layer
	previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
	[previewLayer setBackgroundColor:[[UIColor blackColor] CGColor]];
	[previewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
	[rootLayer setMasksToBounds:YES];
	[previewLayer setFrame:[rootLayer bounds]];
	[rootLayer addSublayer:previewLayer];
        
	[session startRunning];
}

#define PREVIEW_WIDTH 480
#define PREVIEW_HEIGHT 360

- (void)setupDetector {
	// Barcode detector
	detector = [[Detector alloc] init];
	[detector setBitmapSize:CGSizeMake(PREVIEW_WIDTH, PREVIEW_HEIGHT)];
}

// clean up capture setup
- (void)teardownAVCapture
{
	if (videoDataOutputQueue) dispatch_release(videoDataOutputQueue);
    videoDataOutput = nil;
    previewLayer = nil;
    session = nil;
    detector = nil;
}

static BOOL detect = YES;

- (void)decoration {
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:@"MoseyCode detected!"
                                                                 delegate:self
                                                        cancelButtonTitle:@"Cancel"
                                                   destructiveButtonTitle:nil
                                                        otherButtonTitles:@"Do something", nil];
    actionSheet.cancelButtonIndex = 1;
    [actionSheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet*) actionSheet didDismissWithButtonIndex:(NSInteger) buttonIndex
{
    detect = YES;
}


- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    if (detect) {
        CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
        unsigned char *data = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
        [detector setBitmap:data];
    
        CFAbsoluteTime t1 = CFAbsoluteTimeGetCurrent();
        [detector detect];
        CFAbsoluteTime t2 = CFAbsoluteTimeGetCurrent();
        NSLog(@"%.0fms", (t2-t1)*1000);
    
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
        if (detector.barcodeCount > 0) {
            detect = NO;
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                [self decoration];
            });
        }
    }
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    [self setupDetector];
    [self setupAVCapture];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
    [self teardownAVCapture];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

@end
