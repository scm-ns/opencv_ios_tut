
#import <Foundation/Foundation.h>

////////////////////////////////////////////////////////////////////
// File includes:
#import "EAGLView.h"
#import "CameraCalibration.hpp"


@interface SimpleVisualizationController : NSObject
{
  EAGLView * m_glview;
  GLuint m_backgroundTextureId;
  std::vector<Transformation> m_transformations;
  CameraCalibration m_calibration;
  CGSize m_frameSize;
    GLfloat angle;
}

-(id) initWithGLView:(EAGLView*)view calibration:(CameraCalibration) calibration frameSize:(CGSize) size;

-(void) drawFrame;
-(void) updateBackground:(const cv::Mat&) frame;
-(void) setTransformationList:(const std::vector<Transformation>&) transformations;

@end
