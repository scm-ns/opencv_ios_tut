

#import "SimpleVisualizationController.h"
#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import <iostream>

// This is the step where the conversion between the camera reference to the
// image happens ? How does this happen ?

// I am going to use this code and for morality. I will use attributio so that I do not have to be
// guilty about doing good work.

@implementation SimpleVisualizationController

-(id) initWithGLView:(EAGLView*)view calibration:(CameraCalibration) calibration frameSize:(CGSize) size;
{
    if ((self = [super init]))
    {
        m_glview = view;
        
        glGenTextures(1, &m_backgroundTextureId);
        glBindTexture(GL_TEXTURE_2D, m_backgroundTextureId);
        
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        // This is necessary for non-power-of-two textures
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        glEnable(GL_DEPTH_TEST);
        m_calibration = calibration;
        m_frameSize   = size;
    }
    
    return self;
}

-(void) updateBackground:(const cv::Mat&) frame
{
    [m_glview setFramebuffer];
    
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glBindTexture(GL_TEXTURE_2D, m_backgroundTextureId);
   
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, frame.cols, frame.rows, 0, GL_BGRA, GL_UNSIGNED_BYTE, frame.data);
    
    int glErCode = glGetError();
    if (glErCode != GL_NO_ERROR)
    {
        std::cout << glErCode << std::endl;
    }
}

-(void) setTransformationList:(const std::vector<Transformation>&) transformations
{
    m_transformations = transformations;
}

- (void)buildProjectionMatrix:(Matrix33)cameraMatrix : (int)screen_width : (int)screen_height : (Matrix44&) projectionMatrix
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
    
    projectionMatrix.data[0] = - 2.0 * f_x / screen_width;
    projectionMatrix.data[1] = 0.0;
    projectionMatrix.data[2] = 0.0;
    projectionMatrix.data[3] = 0.0;
    
    projectionMatrix.data[4] = 0.0;
    projectionMatrix.data[5] = 2.0 * f_y / screen_height;
    projectionMatrix.data[6] = 0.0;
    projectionMatrix.data[7] = 0.0;
    
    projectionMatrix.data[8] = 2.0 * c_x / screen_width - 1.0;
    projectionMatrix.data[9] = 2.0 * c_y / screen_height - 1.0;
    projectionMatrix.data[10] = -( far+near ) / ( far - near );
    projectionMatrix.data[11] = -1.0;
    
    projectionMatrix.data[12] = 0.0;
    projectionMatrix.data[13] = 0.0;
    projectionMatrix.data[14] = -2.0 * far * near / ( far - near );
    projectionMatrix.data[15] = 0.0;
}

- (void) drawBackground
{
    GLfloat w = m_glview.bounds.size.width;
    GLfloat h = m_glview.bounds.size.height;
    
    
    const GLfloat squareVertices[] =
    {
        0, 0,
        w, 0,
        0, h,
        w, h
    };
    
     static const GLfloat textureVertices[] =
     {
         1, 0,
         1, 1,
         0, 0,
         0, 1
     };


     static const GLfloat proj[] =
    {
        0, -2.f/w, 0, 0,
        -2.f/h, 0, 0, 0,
        0, 0, 1, 0,
        1, 1, 0, 1
    };

    
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glLoadMatrixf(proj);
    
    
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    glDepthMask(FALSE);
    glDisable(GL_COLOR_MATERIAL);
 
    glEnable(GL_TEXTURE_2D);
    
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
 
    glBindTexture(GL_TEXTURE_2D, m_backgroundTextureId);

    // Update attribute values.
    glVertexPointer(2, GL_FLOAT, 0, squareVertices);
    glEnableClientState(GL_VERTEX_ARRAY);
    glTexCoordPointer(2, GL_FLOAT, 0, textureVertices);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    
    glColor4f(1,1,1,1);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    
    glDisableClientState(GL_VERTEX_ARRAY);
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);

    glDisable(GL_TEXTURE_2D);
}

- (void) drawAR
{
    Matrix44 projectionMatrix;
    [self buildProjectionMatrix:m_calibration.getIntrinsic():m_frameSize.width :m_frameSize.height :projectionMatrix];
    
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    

    glLoadMatrixf(projectionMatrix.data); // how does open gl use ?
    
   // glLoadMatrixf(projectionMatrix.data); // how does open gl use ?

    // Yep it uses this to convert from the 3D model into camera iamge
    
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    
    glDepthMask(TRUE);
    glEnable(GL_DEPTH_TEST);
    //glDepthFunc(GL_LESS);
    //glDepthFunc(GL_GREATER);
    
    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_NORMAL_ARRAY);
    
    glPushMatrix();
    glLineWidth(3.0f);
    
    float lineX[] = {0,0,0,1,0,0};
    float lineY[] = {0,0,0,0,1,0};
    float lineZ[] = {0,0,0,0,0,1};
    
    const GLfloat squareVertices[] = {
        -0.5f, -0.5f,
        0.5f,  -0.5f,
        -0.5f,  0.5f,
        0.5f,   0.5f,
    };
    const GLubyte squareColors[] = {
        255, 255,   0, 255,
        0,   255, 255, 255,
        0,     0,   0,   0,
        255,   0, 255, 255,
    };
   
    // for each marker that has been identified do something ?
   
    // The prespective projection will convert from the camera-model 3D space into the 2D space.
   
    // the transformation matrix knows how to move the 3d model in such a way that it is located on
    // top the correct marker space.
   
    // So we use apply this transform to move to the right location and then draw the square there.
    
    // Nope draw a model :w
    
    // There are two places where all of this could go wrong.
    
    for (size_t transformationIndex=0; transformationIndex<m_transformations.size(); transformationIndex++)
    {
        const Transformation& transformation = m_transformations[transformationIndex];
        
        Matrix44 glMatrix = transformation.getMat44();
        
        glLoadMatrixf(reinterpret_cast<const GLfloat*>(&glMatrix.data[0]));
        
        // draw data
        // Draw the Square
        glVertexPointer(2, GL_FLOAT, 0, squareVertices);
        glEnableClientState(GL_VERTEX_ARRAY);
        glColorPointer(4, GL_UNSIGNED_BYTE, 0, squareColors);
        glEnableClientState(GL_COLOR_ARRAY);
        
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        glDisableClientState(GL_COLOR_ARRAY);
        
        float scale = 0.5; // This ensure that the lines are half the size of the square
        glScalef(scale, scale, scale);
        
        glTranslatef(0, 0, 0.1);
        // Draw the different lines
        glColor4f(1.0f, 0.0f, 0.0f, 1.0f);
        glVertexPointer(3, GL_FLOAT, 0, lineX);
        glDrawArrays(GL_LINES, 0, 2);
        
        glColor4f(0.0f, 1.0f, 0.0f, 1.0f);
        glVertexPointer(3, GL_FLOAT, 0, lineY);
        glDrawArrays(GL_LINES, 0, 2);
        
        glColor4f(0.0f, 0.0f, 1.0f, 1.0f);
        glVertexPointer(3, GL_FLOAT, 0, lineZ);
        glDrawArrays(GL_LINES, 0, 2);
    }
    
    glPopMatrix();
    glDisableClientState(GL_VERTEX_ARRAY);
}

- (void)drawFrame
{
    // Set the active framebuffer
    [m_glview setFramebuffer];
    
    // Draw a video on the background
    [self drawBackground];
    
    {
        int glErCode = glGetError();
        if (glErCode != GL_NO_ERROR)
        {
            std::cerr << "GL error detected. Error code:" << glErCode << std::endl;
        }
    }

    // Draw 3D objects on the position of the detected markers
    [self drawAR];
    
    {
        int glErCode = glGetError();
        if (glErCode != GL_NO_ERROR)
        {
            std::cerr << "GL error detected. Error code:" << glErCode << std::endl;
        }
    }


    // Present framebuffer
    bool ok = [m_glview presentFramebuffer];

    int glErCode = glGetError();
    if (!ok || glErCode != GL_NO_ERROR)
    {
        std::cerr << "GL error detected. Error code:" << glErCode << std::endl;
    }
}

// test bed for running open gl commands
-(void) drawOpenGL
{
    
    glClear( GL_COLOR_BUFFER_BIT);
    
    GLfloat w = m_glview.bounds.size.width;
    GLfloat h = m_glview.bounds.size.height;
   
    
    static const GLfloat proj[] =
    {
        1, -2.f/w, 0, 0,
        -2.f/h, 0, 0, 0,
        0, 0, 1, 0,
        1, 1, 0, 1
    };
    
    glMatrixMode(GL_PROJECTION);
    glLoadMatrixf(proj);
  
    glPushMatrix();
    
    
    const GLfloat squareVertices[] = {
        -0.5f, -0.5f,
        0.5f,  -0.5f,
        -0.5f,  0.5f,
        0.5f,   0.5f,
    };
    const GLubyte squareColors[] = {
        255, 255,   0, 255,
        0,   255, 255, 255,
        0,     0,   0,   0,
        255,   0, 255, 255,
    };
   
    
        // draw data
        glVertexPointer(2, GL_FLOAT, 0, squareVertices);
        glEnableClientState(GL_VERTEX_ARRAY);
        glColorPointer(4, GL_UNSIGNED_BYTE, 0, squareColors);
        glEnableClientState(GL_COLOR_ARRAY);
        
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        glDisableClientState(GL_COLOR_ARRAY);
    
    
}

@end

