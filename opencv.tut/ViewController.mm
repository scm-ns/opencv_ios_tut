//
//  ViewController.m
//  opencv.tut
//
//  Created by scm197 on 2/22/17.
//  Copyright © 2017 scm197. All rights reserved.
//

// Copy of the work done by the author of Mastering open cv with practical projects

#import "ViewController.h"
#import "KeyPointDetector.hpp"
#import "SimpleVisualizationController.h"
#import <opencv2/videoio/cap_ios.h>

@interface ViewController ()<CvVideoCameraDelegate>
{
    CvVideoCamera* videoCamera;
    KeyPointDetector * markerDetector;
    SimpleVisualizationController * visualController;
    CameraCalibration * camCal;
}
@end

@implementation ViewController
@synthesize glView;

-(instancetype)init
{
    if (self = [super initWithNibName:nil bundle:nil])
    {
        _imageView = [[UIImageView alloc] init];
        videoCamera = [self setupVideoCameraWithView:_imageView];
        camCal = new CameraCalibration(1350 , 1200 , 150, 200);
        
        
        markerDetector = new KeyPointDetector(*(camCal));
        glView = [[EAGLView alloc] initWithFrame:CGRectMake(10, 10, 300, 500)];
        
    }
    
    return self;
}

- (CvVideoCamera* ) setupVideoCameraWithView: (UIImageView*) view
{
    CvVideoCamera* cam =  [[CvVideoCamera alloc] initWithParentView:view];
    cam.defaultAVCaptureDevicePosition = AVCaptureDevicePositionBack;
    cam.defaultAVCaptureSessionPreset = AVCaptureSessionPresetMedium;
    cam.defaultAVCaptureVideoOrientation = AVCaptureVideoOrientationPortrait;
    cam.defaultFPS = 30;
    cam.grayscaleMode = NO;
    cam.delegate = self;
    return cam;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self layoutImageView];
    self.view.backgroundColor = [UIColor yellowColor];

    [self.view addSubview:glView];
    
    // Do any additional setup after loading the view, typically from a nib.
}

- (void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
   
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [videoCamera start];
    });
    
}

- (void)viewWillAppear:(BOOL)animated
{
    [self.glView initContext];
    CGSize frameSize = [self getFrameSize];
    
    visualController = [[SimpleVisualizationController alloc] initWithGLView:self.glView calibration:*(camCal) frameSize:self.glView.bounds.size];
   
    
    [super viewWillAppear:animated];
}

-(void) layoutImageView
{
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_imageView];
   
    _imageView.backgroundColor = [UIColor grayColor];
    
    NSString* formatStr_H = @"H:|-[_imageView]-|";
    NSString* formatStr_V = @"V:|-20-[_imageView]-20-|";
   
    NSMutableArray<NSLayoutConstraint *> *contrains = [[NSMutableArray alloc] initWithArray:[NSLayoutConstraint constraintsWithVisualFormat:formatStr_H options:0 metrics:nil views:NSDictionaryOfVariableBindings(_imageView)]];
    
    [contrains addObjectsFromArray:[NSLayoutConstraint constraintsWithVisualFormat:formatStr_V options:0 metrics:nil views:NSDictionaryOfVariableBindings(_imageView)]];
   

    [NSLayoutConstraint activateConstraints:contrains];
}


-(CGSize) getFrameSize
{
   if(![[videoCamera captureSession] isRunning])
   {
       NSLog(@"No camera input");
       return CGSizeZero;
   }
   
    
    NSArray * ports = [[videoCamera captureSession] inputs];
    AVCaptureInputPort* usedPort = nil;
    for (AVCaptureInputPort *port in ports)
    {
        if (usedPort == nil || [port.mediaType isEqualToString:AVMediaTypeVideo] )
        {
            usedPort = port ;
        }
    }
    if(usedPort == nil) return CGSizeZero;
    
    CMFormatDescriptionRef format = usedPort.formatDescription;
    CMVideoDimensions dim =  CMVideoFormatDescriptionGetDimensions(format);
    
    return CGSizeMake(dim.width, dim.height);
}


//MARK : Computer Vision


- (void)processImage:(cv::Mat &)image
{
    cv::Mat image_copy;
    
    cv::cvtColor(image, image_copy, CV_RGB2BGRA);
    
      // Start upload new frame to video memory in main thread
    dispatch_sync( dispatch_get_main_queue(), ^{
        [visualController updateBackground:image_copy];
    });
    
    // And perform processing in current thread
    
    markerDetector->processFrame(image);
    std::vector<cv::Mat> trans = markerDetector->getTransformations();
    
    NSLog(@"Size : %lu" , trans.size());
    
    
    // When it's done we query rendering from main thread
    dispatch_async( dispatch_get_main_queue(), ^{
        [visualController setTransformationList:trans];
        [visualController drawFrame];
    });  
}



@end
