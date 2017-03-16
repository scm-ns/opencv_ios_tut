//
//  OpenCVAdapter.h
//  opencv.tut
//
//  Created by scm197 on 3/16/17.
//  Copyright © 2017 scm197. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <SceneKit/SceneKit.h>

/*
    Purpose :
        Pass the sample buffer to the feature detector
        The results of the processing will be routed asyn through
        the TransformAcceptorDelegate
 */
@protocol FeatureDetectorDelegate
    -(void)detectFeatures:(CMSampleBufferRef) sampleBuffer;
@end

/*
    Purpose : 
        After FeatureDelectorDelegate is passed the sample buffer.
        Processing is done on it and transform are obtained. // Trasform which identify the location of the marker in the camera coordinate????
        These transform are passed back to soruce of the samplebuffer using this proctol

        The transform is used to move the data from the model coordinate system to camera coordinate system  ????
 
    Matrix Data Format :
        The first 3x3 matrix represets the rotation 
        The last column represent the translation
 
 */
@protocol TransformAcceptorDelegate
-(void) acceptTransforms:(NSArray<id> *) transforms; // Create Swift Data Structure to present the tranform
@end


// Convert to protcol for better design
@interface OpenCVDetectorAdapter : NSObject <FeatureDetectorDelegate>
    
@property (nonatomic,weak) id<TransformAcceptorDelegate> acceptor;

- (instancetype)initWithAcceptor: (id<TransformAcceptorDelegate>) acceptorDelegate;

@end
