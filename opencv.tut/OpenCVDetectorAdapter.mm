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
        In open cv and open gl the data is stored like this :
            
        ROT | TRAN
        0   |   1
    
        In Scene kit
     
        ROT | 0
         _    _
        TRAN 1
     
        Here the transform has to be in the format for OpenGL
     
     */
    
    openGL_transform = openGL_transform.t(); // This is necessary to convert from the column major ordering of the
    // rotation and translation to the row major odering of the rot and tran
    std::cout << openGL_transform << std::endl;
    
    // Copy the rotation rows
    // Copy the first row.
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
  
    /*
        Check if the cx , cy , fx, fy obtained here is the same as the one
        that is need by the camera clibration ?
        How is this being calculated. This could be asource of error too.
     */
    
    double fx = 1.1072782183366783e+03;
    double fy = 1.0849198430596782e+03;
    double cx = 5.5150736004400665e+02;
    double cy = 3.4412221680732574e+02;
    
    std::cout << "Obtained Calibration " << fx << " " << fy << " " << cx << " " << cy;
    
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
    float f_y = cameraMatrix.data[4]; // Focal length in y axis (usually the same?)
    float c_x = cameraMatrix.data[2]; // Camera primary point x
    float c_y = cameraMatrix.data[5]; // Camera primary point y
    
    cv::Mat projectionMatrix(4,4,CV_32F);
    /*
        Use the fov directyl instead of figuring out the fx fy etc .
        cx and cy might be causing errors for me though.
     
        The frustum is projected on the focal plane.
        Which has size cx , cy
        Then is have to converted to an image place which is what is shown on the screen.
   
        // ERROR
            Can the calibration effect the rotation ?
            cx and cy could. When I visualize it, this seems like a probablity.
     
     */
    
   // I am inverting the x and y axis.
    // Not in terms of signs, but x,y = y,x
    
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
    projectionMatrix.at<float>(2,2) = -( far) / ( far - near );
    projectionMatrix.at<float>(3,2) = -1.0;
    
    projectionMatrix.at<float>(0,3) = 0.0;
    projectionMatrix.at<float>(1,3) = 0.0;
    projectionMatrix.at<float>(2,3) = -far * near / ( far - near );
    projectionMatrix.at<float>(3,3) = 0.0;
  
    cv::Mat ndcShiftMatrix(4,4,CV_32F);
    std::cout << ndcShiftMatrix << std::endl;
    
  // http://blog.athenstean.com/post/135771439196/from-opengl-to-metal-the-projection-matrix
    
    ndcShiftMatrix.at<float>(0,0) = 1;
    ndcShiftMatrix.at<float>(1,1) = 1;
    ndcShiftMatrix.at<float>(2,2) = 0.5;
    ndcShiftMatrix.at<float>(2,3) = 0.5;
    ndcShiftMatrix.at<float>(3,3) = 1;
    
    
    return ndcShiftMatrix*projectionMatrix; // Scene kit only behaves properly, when this matrix is transposed.
    // Else the x and y axis are screwed up. I spend hours due to this bug.
}



@end
