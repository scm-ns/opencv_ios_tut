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
            // Detect the different transforms . THINK : Make the method asyn or something like that ?
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
    
      //  dispatch_async(serialQueue,
      // ^{
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
    //   });
}

-(SCNMatrix4) transformToSceneKit:(cv::Mat&) openGL_transform  // This matrix is in the opengl format
{
    SCNMatrix4 mat = SCNMatrix4Identity;
    // Place of possible error : The formats might not be handled properly yet. Read more about Apple docs

    // Scene Kit is row major. How to handle that ?
  
    /*
        But why does the memory odering ever matter. Yes the data will be stored differntly in either
        strucutres but we are not accessing memory directly, but using index access and that should
        make the memory order irrelavent
     
        So the odering does not seem to be something that I need to worry about
     */
   
    /*
        In open cv the data is stored like this : 
            
        ROT | TRAN
        0   |   1
    
     
        In open gl + Scene kit
     
        ROT | 0
         _    _
        TRAN 1
     
        Here the transform has to be in the format for OpenGL
     
     */
    
    
    // Copy the rotation rows
    mat.m11 = openGL_transform.at<float>(0,0);
    mat.m12 = openGL_transform.at<float>(0,1);
    mat.m13 = openGL_transform.at<float>(0,2);
    mat.m14 = openGL_transform.at<float>(0,3);
   
    mat.m21 = openGL_transform.at<float>(1,0);
    mat.m22 = openGL_transform.at<float>(1,1);
    mat.m23 = openGL_transform.at<float>(1,2);
    mat.m24 = openGL_transform.at<float>(1,3);
    
    mat.m31 = openGL_transform.at<float>(2,0);
    mat.m32 = openGL_transform.at<float>(2,1);
    mat.m33 = openGL_transform.at<float>(2,2);
    mat.m34 = openGL_transform.at<float>(2,3);
    
    //Copy the translation row. Which is the bottom row in OpenGL /SceneKIT
    mat.m41 = openGL_transform.at<float>(3,0);
    mat.m42 = openGL_transform.at<float>(3,1);
    mat.m43 = openGL_transform.at<float>(3,2);
    mat.m44 = openGL_transform.at<float>(3,3);
 
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
   
    // the camera calibraion required the width and height
    _screenWidth = width;
    _screenHeight = height;
    
    _calibraion = [self createCameraCalibration];
    // Now we can create the detector
    _detector = new KeyPointDetector(*_calibraion);
}

-(CameraCalibration*) createCameraCalibration
{
    // #ERROR Is there errors here that I need to worry ABOUT ?
    
    AVCaptureDeviceFormat* format = self.cameraInput.device.activeFormat;
    CMFormatDescriptionRef fDesc = format.formatDescription;
    CGSize dm = CMVideoFormatDescriptionGetPresentationDimensions(fDesc, true, true);
   
    float cx = float(dm.width) / 2.0;
    float cy = float(dm.height) / 2.0 ;
   
    float HFOV = format.videoFieldOfView;
    float VFOV = ((HFOV)/cx)*cy;
    
    float fx = std::abs(float(dm.width) / (2 * tan(HFOV / 180 * float(M_PI) / 2)));
    float fy = std::abs(float(dm.height) / (2 * tan(VFOV / 180 * float(M_PI) / 2)));
    
    std::cout << "Obtained Calibration " << fx << " " << fx << " " << cx << " " << cy;
    
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
    float near = 0.01;  // Near clipping distance
    float far  = 100;  // Far clipping distance
    
    // Camera parameters
    float f_x = cameraMatrix.data[0]; // Focal length in x axis
    float f_y = cameraMatrix.data[4]; // Focal length in y axis (usually the same?)
    float c_x = cameraMatrix.data[2]; // Camera primary point x
    float c_y = cameraMatrix.data[5]; // Camera primary point y
  
    // Look at the equation to create the projection matrix.
   
    // This is not the simple projection, this also does the scaling required to convert the objects from the
    // camera reference frame to the image model ?
    
    // Storage as column major. That is along the columns. 1st column , then 2nd column etc
    // Same as sceneKit
    
    cv::Mat projectionMatrix(4,4,CV_32F);
   
    // ANother place of possible error. The row vs col majoring issues
    // #ERROR
    // What is the format here for the projectoin matrices ?
  
    // ERROR POSSIBILITY HIGH
    // This formula has not beed found anywhere other than the opencv book
        // There is a high probability of being wrong here. 
    
    projectionMatrix.at<float>(0,0) = - 2.0 * f_x / screen_width;
    projectionMatrix.at<float>(1,0) = 0.0;
    projectionMatrix.at<float>(2,0) = 0.0;
    projectionMatrix.at<float>(3,0) = 0.0;
   
    projectionMatrix.at<float>(0,1) = 0.0;
    projectionMatrix.at<float>(1,1) = 2.0 * f_y / screen_height;
    projectionMatrix.at<float>(2,1) = 0.0;
    projectionMatrix.at<float>(3,1) = 0.0;
    
    projectionMatrix.at<float>(0,2) = 2.0 * c_x / screen_width - 1.0;
    projectionMatrix.at<float>(1,2) = 2.0 * c_y / screen_height - 1.0;
    projectionMatrix.at<float>(2,2) = -( far+near ) / ( far - near );
    projectionMatrix.at<float>(3,2) = -1.0;
    
    projectionMatrix.at<float>(0,3) = 0.0;
    projectionMatrix.at<float>(1,3) = 0.0;
    projectionMatrix.at<float>(2,3) = -2.0 * far * near / ( far - near );
    projectionMatrix.at<float>(3,3) = 0.0;
    
    return projectionMatrix.t(); // Scene kit only behaves properly, when this matrix is transposed.
    // Else the x and y axis are screwed up. I spend hours due to this bug.
}



@end
