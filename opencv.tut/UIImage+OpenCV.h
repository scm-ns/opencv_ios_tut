//
//  UIImage+OpenCV.h
//  opencv.tut
//
//  Created by scm197 on 2/22/17.
//  Copyright © 2017 scm197. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <opencv2/opencv.hpp>


@interface UIImage (OpenCV)

-(cv::Mat) getCvMat;
-(cv::Mat) getGrayCvMat;

+(UIImage*) imageWithCVMat:(cv::Mat) mat;

@end
