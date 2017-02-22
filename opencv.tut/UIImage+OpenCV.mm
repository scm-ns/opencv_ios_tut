//
//  UIImage+OpenCV.m
//  opencv.tut
//
//  Created by scm197 on 2/22/17.
//  Copyright © 2017 scm197. All rights reserved.
//

#import "UIImage+OpenCV.h"

@implementation UIImage (OpenCV)

-(cv::Mat) getCvMat
{
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(self.CGImage);
    CGFloat cols = self.size.width;
    CGFloat rows = self.size.height;
   
    cv::Mat cvMat(rows , cols , CV_8UC4);
    
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data ,
                                                    cols ,
                                                    rows ,
                                                    8 ,
                                                    cvMat.step[0],
                                                    colorSpace,
                                                    kCGImageAlphaNoneSkipLast |
                                                    kCGBitmapByteOrderMask);
    
    CGContextDrawImage(contextRef , CGRectMake(0, 0, cols, rows), self.CGImage);
    CGContextRelease(contextRef);
    
    return cvMat;
}

-(cv::Mat) getGrayCvMat
{
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(self.CGImage);
    CGFloat cols = self.size.width;
    CGFloat rows = self.size.height;
   
    cv::Mat cvMat(rows , cols , CV_8UC1);
    
    CGContextRef contextRef = CGBitmapContextCreate(cvMat.data ,
                                                    cols ,
                                                    rows ,
                                                    8 ,
                                                    cvMat.step[0],
                                                    colorSpace,
                                                    kCGImageAlphaNoneSkipLast |
                                                    kCGBitmapByteOrderMask);
    
    CGContextDrawImage(contextRef , CGRectMake(0, 0, cols, rows), self.CGImage);
    CGContextRelease(contextRef);
    
    return cvMat;
}



+(UIImage*) imageWithCVMat:(cv::Mat) mat
{
    NSData * data = [NSData dataWithBytes:mat.data length:mat.elemSize() * mat.total()];
    CGColorSpaceRef colorSpace ;
    
    if(mat.elemSize() == 1) // based on the number of bytes in each element
    {
        colorSpace = CGColorSpaceCreateDeviceGray();
    }
    else
    {
        colorSpace = CGColorSpaceCreateDeviceRGB();
    }
   
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    
    
    CGImageRef cgimage = CGImageCreate(mat.cols, mat.rows
                                       , 8, 8 * mat.elemSize(), mat.step[0], colorSpace, kCGImageAlphaNone | kCGBitmapByteOrderDefault, provider, NULL, false, kCGRenderingIntentDefault);
    
    UIImage* image = [UIImage imageWithCGImage:cgimage];
    CGImageRelease(cgimage);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
    return image;
}



@end
