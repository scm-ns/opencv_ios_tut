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
    KeyPointDetector * detector;
    dispatch_queue_t serialQueue;
}

- (instancetype)initWithAcceptor:(id<TransformAcceptorDelegate>) acceptorDelegate
{
    self = [super init];
    if (self)
    {
        self.acceptor = acceptorDelegate;
        
        CameraCalibration cam(6.24860291e+02 * (640./352.), 6.24860291e+02 * (480./288.), 640 * 0.5f, 480 * 0.5f);
        
        detector = new KeyPointDetector(cam);
        
        serialQueue = dispatch_queue_create("com.opencvtut.processFrame", DISPATCH_QUEUE_PRIORITY_DEFAULT);
    }
    return self;
}

- (void)detectFeatures:(CMSampleBufferRef)sampleBuffer
{
        dispatch_async(serialQueue,
       ^{
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

            // Detect the different transforms . THINK : Make the method asyn or something like that ? 
            detector->processFrame(bgraMat);
           
                /*We unlock the  image buffer*/
            CVPixelBufferUnlockBaseAddress(imageBuffer,0);
                
       });
        [self passTransformsBack];
    
       
    
}

-(void)passTransformsBack
{
        // added to a serial queue, so that after the processing is done in the earlier block (detectFeatures
        // and values are obtained.) this block is exectued which will pass the transforms to the accpetor
    
        dispatch_async(serialQueue,
       ^{
           // Obtain the tranforms can pass it back to the source using acceptor delegate
           std::vector<Transformation> transforms = detector->getTransformations();

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
       });
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


@end
