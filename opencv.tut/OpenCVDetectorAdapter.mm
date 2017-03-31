//
//  OpenCVAdapter.m
//  opencv.tut
//
//  Created by scm197 on 3/16/17.
//  Copyright © 2017 scm197. All rights reserved.
//

#import "OpenCVDetectorAdapter.h"
#import <opencv2/core.hpp>
#import "KeyPointDetector.hpp"

/*
    Purpose of Existence.
        Pass data from the camera buffer from AVFoundation to the OpenCV
        classes which will do the detection for us.
        The pass the results back to the source class
 
    I will need to repeat this, because of ObjCpp not being support within Swift.
        - Is there a better way to do this. Does swift support ObjC++ .
                    It does not seem like it. Swift supports pure C and ObjC. It does not support C++ keywords like classes etc. 
                    I have to create an Adapter which exposes the C++ to Swift
                    Not required. It is the C++ headers which are the problem. I just need to hide the C++ functions within an 
                    ObjC++ class and expose the ObjC++ header to swift. [The ObjC++ header should not have any C++ keywprds ]
    
 */

#import "KeyPointDetector.hpp"
#import <opencv2/opencv.hpp>


@implementation OpenCVDetectorAdapter
{
    KeyPointDetector* _detector;
    dispatch_queue_t serialQueue;
    int _screenWidth;
    int _screenHeight;
    CameraCalibration* _calibraion;
}

- (instancetype)initWithAcceptor: (id<TransformAcceptorDelegate>) acceptorDelegate cameraInput:(AVCaptureDeviceInput* ) camera
{
    self = [super init];
    if (self)
    {
        self.acceptor = acceptorDelegate;
        
        _detector = nil;
        _cameraInput = camera;
        serialQueue = dispatch_queue_create("com.opencvtut.processFrame", DISPATCH_QUEUE_PRIORITY_DEFAULT);
    }
    return self;
}

- (void)detectFeatures:(CMSampleBufferRef)sampleBuffer
{
    
        if(_detector == nil) // is the detector has not been created. Then do not proceed
        {
            return;
        }
    
       // Do Conversion from Core Media to Core Video
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        // Lock the address
        CVPixelBufferLockBaseAddress(imageBuffer,0);
        
        uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
        size_t width = CVPixelBufferGetWidth(imageBuffer);
        size_t height = CVPixelBufferGetHeight(imageBuffer);
        size_t stride = CVPixelBufferGetBytesPerRow(imageBuffer);
        // create a cv::Mat from the frame buffer
        cv::Mat bgraMat(height, width , CV_8UC4 , baseAddress , stride);

        CVPixelBufferUnlockBaseAddress(imageBuffer,0);

        dispatch_async(serialQueue,
        ^{
            _detector->processFrame(bgraMat);
            [self passTransformsBack];
         });

}

/*
    Process the image, find the markers. Identify the transforms of those markers and then, pass it back to the source, using
    the acceptor delegate
 */
-(void)passTransformsBack
{
        // added to a serial queue, so that after the processing is done in the earlier block (detectFeatures
        // and values are obtained.) this block is exectued which will pass the transforms to the accpetor
    
           // Obtain the tranforms can pass it back to the source using acceptor delegate
            std::vector<cv::Mat> transforms = _detector->getTransformations();

           NSLog(@"Size : %lu" , transforms.size());
            // Convert the tranforms into SCNMatrix4 array
           
           NSMutableArray* array = [[NSMutableArray alloc] init];
           
           for( cv::Mat& transform : transforms)
           {
               SCNMatrix4 sceneKitTransform = [self transformToSceneKit:transform];
               // NSArray cannot hold a struct, so wrap it in an NSValue and do the inverse at the acceptor (swift) side
               [array addObject:[NSValue valueWithSCNMatrix4:sceneKitTransform]];
           }
         
           // Pass it back to the source 
           [self.acceptor acceptTransforms:[NSArray arrayWithArray:array]];
}

-(SCNMatrix4) transformToSceneKit:(cv::Mat&) RightHandtransform
{
    SCNMatrix4 mat = SCNMatrix4Identity;
    
    // RightHandtransform is column major
    // Scene Kit is row major.
    RightHandtransform = RightHandtransform.t();
    
    // Copy the rotation rows
    // Copy the first row.
    mat.m11 = RightHandtransform.at<float>(0,0);
    mat.m12 = RightHandtransform.at<float>(0,1);
    mat.m13 = RightHandtransform.at<float>(0,2);
    mat.m14 = RightHandtransform.at<float>(0,3);
   
    mat.m21 = RightHandtransform.at<float>(1,0);
    mat.m22 = RightHandtransform.at<float>(1,1);
    mat.m23 = RightHandtransform.at<float>(1,2);
    mat.m24 = RightHandtransform.at<float>(1,3);
    
    mat.m31 = RightHandtransform.at<float>(2,0);
    mat.m32 = RightHandtransform.at<float>(2,1);
    mat.m33 = RightHandtransform.at<float>(2,2);
    mat.m34 = RightHandtransform.at<float>(2,3);
    
    //Copy the translation row. Which is the bottom row in SceneKIT
    mat.m41 = RightHandtransform.at<float>(3,0);
    mat.m42 = RightHandtransform.at<float>(3,1);
    mat.m43 = RightHandtransform.at<float>(3,2);
    mat.m44 = RightHandtransform.at<float>(3,3);
 
    return mat;
}

/*
    pre : have called the setScreenPorperties. Which will items that we need in this funciton
    post :
    input :  none
    return : SCNMatrix4
    state change : none
    decs :
         Obtain the prespective transfrom reqired for the converion from 3D camera coor to the 2D camera coor
         Use this to set the prespective matrix of the SCNCamera
 
        If called before setSreenProperties then error
 */
-(SCNMatrix4) getPrespectiveSCNMatrix4
{
    
    std::cout << "Set up calibration with = Width : " << _screenWidth << " Height :" << _screenHeight << std::endl;
    cv::Mat projMat = [self buildProjectionMatrix:_calibraion->getIntrinsic() width:_screenWidth height:_screenHeight];
   
    return [self transformToSceneKit:projMat];
}

/*
    pre : none.
    post : Now that the detector has been created with the correct calibration, processing of the frames occurs
    input : width and height
    return : none
    state change : 
            CameraCalibration is created as _calibration
            KeyPointDetector is created using _calibration
            Now the process can happen
    decs : 
 
 */
-(void) setScreenProperties:(int)width height:(int)height
{
   
    _screenWidth = width;
    _screenHeight = height;
    
    _calibraion = [self createCameraCalibration];
    // Now we can create the detector
    _detector = new KeyPointDetector(*_calibraion);
}

-(CameraCalibration*) createCameraCalibration
{
    // Parameters obtained from the yaml file from running the calibration on iPHONE 5S ONLY. For other camera's run the calibration again
    // I have some uncertainity in whether the parameters are accurate enough.
    double fx = 1.1072782183366783e+03;
    double fy = 1.0849198430596782e+03;
    double cx = 5.5150736004400665e+02;
    double cy = 3.4412221680732574e+02;
    
    return new CameraCalibration(fx , fy , cx , cy);
}


/*
    pre : none
    post : none
    state change : none
    desc :
            Creates the matrix required to do the conversion from the 3D camera coor to the 2D camera coor
            Used as a utiliy function, not exposed to other classes
 */
- (cv::Mat)buildProjectionMatrix:(Matrix33)cameraMatrix width: (int)screen_width height: (int)screen_height
{
    float near = 1;  // Near clipping distance
    float far  = 100;  // Far clipping distance

    
    // Camera parameters
    float f_x = cameraMatrix.data[0]; // Focal length in x axis
    float f_y = cameraMatrix.data[4]; // Focal length in y axis
    float c_x = cameraMatrix.data[2]; // Camera primary point x
    float c_y = cameraMatrix.data[5]; // Camera primary point y
    
    cv::Mat projectionMatrix(4,4,CV_32F);
    
    // I am inverting the x and y axis.
    // Not in terms of signs, but x,y = y,x // I don't know why this works.
    
    double left_modified = -(near / f_x)*c_x;
    double right_modified = (near / f_x)*c_x;
    
    double bottom_modified = -(near / f_y) * c_y;
    double top_modified = (near/ f_y) * c_y;

    projectionMatrix.at<float>(1,0) = 2.0 * near / (right_modified - left_modified);
    projectionMatrix.at<float>(0,0) = 0.0;
    projectionMatrix.at<float>(2,0) = 0.0;
    projectionMatrix.at<float>(3,0) = 0.0;
   
    projectionMatrix.at<float>(1,1) = 0.0;
    projectionMatrix.at<float>(0,1) = 2.0 * near / (top_modified - bottom_modified);
    projectionMatrix.at<float>(2,1) = 0.0;
    projectionMatrix.at<float>(3,1) = 0.0;
    
    projectionMatrix.at<float>(1,2) = (right_modified + left_modified ) / (right_modified - left_modified);
    projectionMatrix.at<float>(0,2) = (top_modified + bottom_modified) / (top_modified - bottom_modified);
    projectionMatrix.at<float>(2,2) = -( far + near ) / ( far - near );
    projectionMatrix.at<float>(3,2) = -1.0;
    
    projectionMatrix.at<float>(0,3) = 0.0;
    projectionMatrix.at<float>(1,3) = 0.0;
    projectionMatrix.at<float>(2,3) = -2*far * near / ( far - near );
    projectionMatrix.at<float>(3,3) = 0.0;
  
    cv::Mat ndcShiftMatrix = cv::Mat::zeros(4,4,CV_32F);
    
  // http://blog.athenstean.com/post/135771439196/from-opengl-to-metal-the-projection-matrix
    
    ndcShiftMatrix.at<float>(0,0) = 1;
    ndcShiftMatrix.at<float>(1,1) = 1;
    ndcShiftMatrix.at<float>(2,2) = 0.5;
    ndcShiftMatrix.at<float>(2,3) = 0.5;
    ndcShiftMatrix.at<float>(3,3) = 1;
   
    std::cout << "NDC" << ndcShiftMatrix << std::endl;
    std::cout << "shift mat " << ndcShiftMatrix*projectionMatrix << std::endl;
    
    // Convet from 2x2x2 NDC of open gl to 2x2x1 NDC of metal
    return ndcShiftMatrix*projectionMatrix;
}



@end
