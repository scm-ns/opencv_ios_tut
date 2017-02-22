//
//  ViewController.m
//  opencv.tut
//
//  Created by scm197 on 2/22/17.
//  Copyright © 2017 scm197. All rights reserved.
//

#import "ViewController.h"
#import <opencv2/videoio/cap_ios.h>

@interface ViewController ()<CvVideoCameraDelegate>
{
    CvVideoCamera* videoCamera;
}
@end

@implementation ViewController


-(instancetype)init
{
    if (self = [super initWithNibName:nil bundle:nil])
    {
        _imageView = [[UIImageView alloc] init];
        videoCamera = [self setupVideoCameraWithView:_imageView];
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


- (void)processImage:(cv::Mat &)image
{
    cv::Mat image_copy;
    cvtColor(image, image_copy, CV_BGRA2BGR);
    
    // invert image
    bitwise_not(image_copy, image_copy);
    cvtColor(image_copy, image, CV_BGR2BGRA);

}


- (void)viewDidLoad {
    [super viewDidLoad];
    [self layoutImageView];
    self.view.backgroundColor = [UIColor yellowColor];
    
    // Do any additional setup after loading the view, typically from a nib.
}

- (void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
   
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [videoCamera start];
    });
    
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


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}




@end
