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
    KeyPointDetector * _detector;
    dispatch_queue_t serialQueue;
    int _screenWidth;
    int _screenHeight;
    CameraCalibration * _calibraion;
}

- (instancetype)initWithAcceptor:(id<TransformAcceptorDelegate>) acceptorDelegate
{
    self = [super init];
    if (self)
    {
        self.acceptor = acceptorDelegate;
        
        
        // Update this with the correct screen size
        
       // detector = new KeyPointDetector(cam);
        _detector = nil;
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

-(void)passTransformsBack
{
        // added to a serial queue, so that after the processing is done in the earlier block (detectFeatures
        // and values are obtained.) this block is exectued which will pass the transforms to the accpetor
    
      //  dispatch_async(serialQueue,
      // ^{
           // Obtain the tranforms can pass it back to the source using acceptor delegate
           std::vector<Transformation> transforms = _detector->getTransformations();

           NSLog(@"Size : %lu" , transforms.size());
            // Convert the tranforms into SCNMatrix4 array
           
           NSMutableArray* array = [[NSMutableArray alloc] init];
           
           for( Transformation transform : transforms)
           {
               SCNMatrix4 sceneKitTransform = [self transfromToSceneKit:transform];
               // NSArray cannot hold a struct, so wrap it in an NSValue and do the inverse at the acceptor (swift) side
               [array addObject:[NSValue valueWithSCNMatrix4:sceneKitTransform]];
           }
         
           // Pass it back to the source 
           [self.acceptor acceptTransforms:[NSArray arrayWithArray:array]];
    //   });
}

-(SCNMatrix4) transfromToSceneKit:(Transformation) transform
{
    // SceneKit seems to be row major, not column major .
    // The transformation , open gl and open cv uses column major.
    // So SceneKit is the Transpose of the open* matrix
    
    SCNMatrix4 mat = SCNMatrix4Identity;
    
    // get the rotation matrix
    Matrix33 rot = transform.r();
    Vector3 tran = transform.t();
    
    // SCNMatrix4 does not have subscript operator
    
    // Copy the rotation rows
    mat.m11 = rot.mat[0][0];
    mat.m12 = rot.mat[1][0];
    mat.m13 = rot.mat[2][0];
    
    mat.m21 = rot.mat[0][1];
    mat.m22 = rot.mat[1][1];
    mat.m23 = rot.mat[2][1];
    
    mat.m31 = rot.mat[0][1];
    mat.m32 = rot.mat[1][1];
    mat.m33 = rot.mat[2][1];
   
    //Copy the translation rows
    mat.m41 = tran.data[0];
    mat.m42 = tran.data[1];
    mat.m43 = tran.data[2];
  
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
    Matrix44* projMat = [self buildProjectionMatrix:_calibraion->getIntrinsic() width:_screenWidth height:_screenHeight];
    
    // Now convert the projMat into a tranform an use the utility func to convert into a SCNMatrix4
    Transformation transform(projMat->getRot() , projMat->getTran());
   
    return [self transfromToSceneKit:transform];
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
   
    _calibraion = new CameraCalibration(1350 , 1200 , _screenWidth, _screenHeight);
    
    // Now we can create the detector
    _detector = new KeyPointDetector(*_calibraion);
}

/*
    pre : none
    post : none
    state change : none
    desc :
            Creates the matrix required to do the conversion from the 3D camera coor to the 2D camera coor
            Used as a utiliy function, not exposed to other classes
 */

- (Matrix44 *)buildProjectionMatrix:(Matrix33)cameraMatrix width: (int)screen_width height: (int)screen_height
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
   
    Matrix44 *projectionMatrix = new Matrix44;
    
    projectionMatrix->data[0] = - 2.0 * f_x / screen_width;
    projectionMatrix->data[1] = 0.0;
    projectionMatrix->data[2] = 0.0;
    projectionMatrix->data[3] = 0.0;
    
    projectionMatrix->data[4] = 0.0;
    projectionMatrix->data[5] = 2.0 * f_y / screen_height;
    projectionMatrix->data[6] = 0.0;
    projectionMatrix->data[7] = 0.0;
    
    projectionMatrix->data[8] = 2.0 * c_x / screen_width - 1.0;
    projectionMatrix->data[9] = 2.0 * c_y / screen_height - 1.0;
    projectionMatrix->data[10] = -( far+near ) / ( far - near );
    projectionMatrix->data[11] = -1.0;
    
    projectionMatrix->data[12] = 0.0;
    projectionMatrix->data[13] = 0.0;
    projectionMatrix->data[14] = -2.0 * far * near / ( far - near );
    projectionMatrix->data[15] = 0.0;
    
    return projectionMatrix;
}



@end
