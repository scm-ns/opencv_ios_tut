// Adopted from MasterOpenCV With practical examples book.

////////////////////////////////////////////////////////////////////
// Standard includes:
#include <iostream>
#include <sstream>

////////////////////////////////////////////////////////////////////
// File includes:
#include "KeyPointDetector.hpp"
#include "Marker.hpp"

float perimeter(const std::vector<cv::Point2f> &a)
{
    float sum=0, dx, dy;
    
    for (size_t i=0;i<a.size();i++)
    {
        size_t i2=(i+1) % a.size();
        
        dx = a[i].x - a[i2].x;
        dy = a[i].y - a[i2].y;
        
        sum += sqrt(dx*dx + dy*dy);
    }
    
    return sum;
}


bool isInto(cv::Mat &contour, std::vector<cv::Point2f> &b)
{
    for (size_t i=0;i<b.size();i++)
    {
        if (cv::pointPolygonTest( contour,b[i],false)>0) return true;
    }
    return false;
}

KeyPointDetector::KeyPointDetector(CameraCalibration calibration)
    : m_minContourLengthAllowed(100)
    , markerSize(100,100)
{
    cv::Mat(3,3, CV_32F, const_cast<float*>(&calibration.getIntrinsic().data[0])).copyTo(camMatrix);
    cv::Mat(4,1, CV_32F, const_cast<float*>(&calibration.getDistorsion().data[0])).copyTo(distCoeff);

    // I am operating in two different world coordinates here.
    // The world coordinate for open-cv. It is in this world coordinate that I find the Rvec and TVec using solve pnp.
    // The world coordiantes for metal, used by scene-kit.
    // I need to make sure that they line up.
   
    /*
     // clock wise odering : Open CV
                000         100                  ------ X
                                                |
                                                |
                                                |
                010         110
                                                Y
        counter clockwise odering  : Metal
        
                                                Y
                -110          110               |
                                                |
                                                |
                         000                     ----- X
     
     
                 -1-10         1-10
     
     
        How to force open cv to use the same coordinate system as metal ? 
     */
    
    // Used by solve pnp
    m_markerCorners3d.push_back(cv::Point3f(-1,1,0));
    m_markerCorners3d.push_back(cv::Point3f(1,1,0));
    m_markerCorners3d.push_back(cv::Point3f(1,-1,0));
    m_markerCorners3d.push_back(cv::Point3f(-1,-1,0));
    
    // used to find the points of the marker. Not important for the projection and transform.
    // This is important only with the opencv coordinate system 
    m_markerCorners2d.push_back(cv::Point2f(0,0));
    m_markerCorners2d.push_back(cv::Point2f(markerSize.width-1,0));
    m_markerCorners2d.push_back(cv::Point2f(markerSize.width-1,markerSize.height-1));
    m_markerCorners2d.push_back(cv::Point2f(0,markerSize.height-1));
}

void KeyPointDetector::processFrame(const cv::Mat& frame)
{
    std::vector<Marker> markers;
    findMarkers(frame, markers);

    m_transformations.clear();
    for (size_t i=0; i<markers.size(); i++)
    {
        m_transformations.push_back(markers[i].transformation);
    }
}

const std::vector<cv::Mat>& KeyPointDetector::getTransformations() const
{
    return m_transformations;
}


bool KeyPointDetector::findMarkers(const cv::Mat& frame, std::vector<Marker>& detectedMarkers)
{

    // Convert the image to grayscale
    prepareImage(frame, m_grayscaleImage);

    // Make it binary
    performThreshold(m_grayscaleImage, m_thresholdImg);

    // Detect contours
    findContours(m_thresholdImg, m_contours, m_grayscaleImage.cols / 5);

    // Find closed contours that can be approximated with 4 points
    findCandidates(m_contours, detectedMarkers);

    // Find is them are markers
    recognizeMarkers(m_grayscaleImage, detectedMarkers);

    // Calculate their poses
    estimatePosition(detectedMarkers);

    //sort by id
    std::sort(detectedMarkers.begin(), detectedMarkers.end());
    return false;
}

void KeyPointDetector::prepareImage(const cv::Mat& bgraMat, cv::Mat& grayscale) const
{
    // Convert to grayscale
    cv::cvtColor(bgraMat, grayscale, CV_BGRA2GRAY);
}

void KeyPointDetector::performThreshold(const cv::Mat& grayscale, cv::Mat& thresholdImg) const
{
//    cv::threshold(grayscale, thresholdImg, 127, 255, cv::THRESH_BINARY_INV);

    cv::adaptiveThreshold(grayscale,   // Input image
    thresholdImg,// Result binary image
    255,         // 
    cv::ADAPTIVE_THRESH_GAUSSIAN_C, //
    cv::THRESH_BINARY_INV, //
    7, //
    7  //
    );

}

void KeyPointDetector::findContours(cv::Mat& thresholdImg, ContoursVector& contours, int minContourPointsAllowed) const
{
    ContoursVector allContours;
    cv::findContours(thresholdImg, allContours, CV_RETR_LIST, CV_CHAIN_APPROX_NONE);

    contours.clear();
    for (size_t i=0; i<allContours.size(); i++)
    {
        int contourSize = allContours[i].size();
        if (contourSize > minContourPointsAllowed)
        {
            contours.push_back(allContours[i]);
        }
    }
}


void KeyPointDetector::findCandidates
(
    const ContoursVector& contours, 
    std::vector<Marker>& detectedMarkers
) 
{
    std::vector<cv::Point>  approxCurve;
    std::vector<Marker>     possibleMarkers;

    // For each contour, analyze if it is a parallelepiped likely to be the marker
    for (size_t i=0; i<contours.size(); i++)
    {
        // Approximate to a polygon
        double eps = contours[i].size() * 0.05;
        cv::approxPolyDP(contours[i], approxCurve, eps, true);

        // We interested only in polygons that contains only four points
        if (approxCurve.size() != 4)
            continue;

        // And they have to be convex
        if (!cv::isContourConvex(approxCurve))
            continue;

        // Ensure that the distance between consecutive points is large enough
        float minDist = std::numeric_limits<float>::max();

        for (int i = 0; i < 4; i++)
        {
            cv::Point side = approxCurve[i] - approxCurve[(i+1)%4];            
            float squaredSideLength = side.dot(side);
            minDist = std::min(minDist, squaredSideLength);
        }

        // Check that distance is not very small
        if (minDist < m_minContourLengthAllowed)
            continue;

        // All tests are passed. Save marker candidate:
        Marker m;

        for (int i = 0; i<4; i++)
            m.points.push_back( cv::Point2f(approxCurve[i].x,approxCurve[i].y) );

        // Sort the points in anti-clockwise order
        // Trace a line between the first and second point.
        // If the third point is at the right side, then the points are anti-clockwise
        cv::Point v1 = m.points[1] - m.points[0];
        cv::Point v2 = m.points[2] - m.points[0];

        double o = (v1.x * v2.y) - (v1.y * v2.x);

        if (o < 0.0)		 //if the third point is in the left side, then sort in anti-clockwise order
            std::swap(m.points[1], m.points[3]);

        possibleMarkers.push_back(m);
    }


    // Remove these elements which corners are too close to each other.  
    // First detect candidates for removal:
    std::vector< std::pair<int,int> > tooNearCandidates;
    for (size_t i=0;i<possibleMarkers.size();i++)
    { 
        const Marker& m1 = possibleMarkers[i];

        //calculate the average distance of each corner to the nearest corner of the other marker candidate
        for (size_t j=i+1;j<possibleMarkers.size();j++)
        {
            const Marker& m2 = possibleMarkers[j];

            float distSquared = 0;

            for (int c = 0; c < 4; c++)
            {
                cv::Point v = m1.points[c] - m2.points[c];
                distSquared += v.dot(v);
            }

            distSquared /= 4;

            if (distSquared < 100)
            {
                tooNearCandidates.push_back(std::pair<int,int>(i,j));
            }
        }				
    }

    // Mark for removal the element of the pair with smaller perimeter
    std::vector<bool> removalMask (possibleMarkers.size(), false);

    for (size_t i=0; i<tooNearCandidates.size(); i++)
    {
        float p1 = perimeter(possibleMarkers[tooNearCandidates[i].first ].points);
        float p2 = perimeter(possibleMarkers[tooNearCandidates[i].second].points);

        size_t removalIndex;
        if (p1 > p2)
            removalIndex = tooNearCandidates[i].second;
        else
            removalIndex = tooNearCandidates[i].first;

        removalMask[removalIndex] = true;
    }

    // Return candidates
    detectedMarkers.clear();
    for (size_t i=0;i<possibleMarkers.size();i++)
    {
        if (!removalMask[i])
            detectedMarkers.push_back(possibleMarkers[i]);
    }
}

// This is the conversion from the markers to the coordinate state is done.
// This is done by :
// Finding the markers and then ?? 

void KeyPointDetector::recognizeMarkers(const cv::Mat& grayscale, std::vector<Marker>& detectedMarkers)
{
    std::vector<Marker> goodMarkers;

    // Identify the markers
    for (size_t i=0;i<detectedMarkers.size();i++)
    {
        Marker& marker = detectedMarkers[i];

        // Find the perspective transformation that brings current marker to rectangular form
        // Converting from rotated state into a state where it fills out a rectangle
        
        
        // Form a relationship between the image coordinates and the marker coordinates.
        // The relationship is formed between points of the real image that might be sweked rotated etc and
        // the image where we want to draw this new image. Which has its own hieight/width etc.
        
        // how to do the transformatin between the points in 3d space and the known points.
        // An important thing to realize is that the marker positions are not absolute.
        // But that a sequence of affine transformations have converted from the the maker points in the
        // real world to this "original marker" coordinates that we know about.
       // And this matrix will tell us how to do this conversion.
        
        cv::Mat markerTransform = cv::getPerspectiveTransform(marker.points, m_markerCorners2d);
        

        // Transform image to get a canonical marker image
        cv::warpPerspective(grayscale, canonicalMarkerImage,  markerTransform, markerSize);

        int nRotations;
        int id = Marker::getMarkerId(canonicalMarkerImage, nRotations);
        if (id !=- 1)
        {
            marker.id = id;
            //sort the points so that they are always in the same order no matter the camera orientation
            std::rotate(marker.points.begin(), marker.points.begin() + 4 - nRotations, marker.points.end());

            goodMarkers.push_back(marker);
        }
    }  

    // Refine marker corners using sub pixel accuracy
    if (goodMarkers.size() > 0)
    {
        std::vector<cv::Point2f> preciseCorners(4 * goodMarkers.size());

        for (size_t i=0; i<goodMarkers.size(); i++)
        {  
            const Marker& marker = goodMarkers[i];      

            for (int c = 0; c <4; c++)
            {
                preciseCorners[i*4 + c] = marker.points[c];
            }
        }

        cv::TermCriteria termCriteria = cv::TermCriteria(cv::TermCriteria::MAX_ITER | cv::TermCriteria::EPS, 30, 0.01);
        cv::cornerSubPix(grayscale, preciseCorners, cvSize(5,5), cvSize(-1,-1), termCriteria);

        // Copy refined corners position back to markers
        for (size_t i=0; i<goodMarkers.size(); i++)
        {
            Marker& marker = goodMarkers[i];      

            for (int c=0;c<4;c++) 
            {
                marker.points[c] = preciseCorners[i*4 + c];
            }      
        }
    }

    detectedMarkers = goodMarkers;
}


void KeyPointDetector::estimatePosition(std::vector<Marker>& detectedMarkers)
{
    for (size_t i=0; i<detectedMarkers.size(); i++)
    {					
        Marker& m = detectedMarkers[i];

        cv::Mat Rvec;
        cv::Mat_<float> Tvec;
        cv::Mat raux,taux;
       
        
        cv::solvePnP(m_markerCorners3d, m.points, camMatrix, distCoeff,raux,taux);
        // the raux taux contained, helps us move from the world model coordinate into the camera coordiantes
        
        raux.convertTo(Rvec,CV_32F);
        taux.convertTo(Tvec ,CV_32F);
        
        cv::Mat_<float> rotMat(3,3);
       
        cv::Mat viewMatrix(4, 4, CV_32F); // This will hold the combined rot and trans
        cv::Rodrigues(Rvec, rotMat);
       
       
        // Copy to tranformation matrix. This matrix will be able to move from model coor to camera coor
        // Docs : rotMat and TVec is actually used to transfrom from the object coordinate to the camera coor.
        // Not the location of the camera in the model coor. So the transformations can be applied to a 
        // model to bring it into camera coor. Keep in mind that the axises are a bit different.
        
        // There is conflicting information here : Some say the axis is : up : Y , right : X , out of camra : Z(along view)
        //                                         others say   axis is : up : X , right : Y , out of camera : Z
        
        viewMatrix( cv::Range(0,3) , cv::Range(0,3)) = rotMat * 1;
        viewMatrix( cv::Range(0,3) , cv::Range(3,4)) = Tvec *1;
       
        
        float *p = viewMatrix.ptr<float>(3); 
        p[0] = p[1] = p[2] = 0; p[3] = 1;
        
        // Convert to OpenGL Format

        // convert from left hand coor in opencv to right handed coor in opengl and scenekit
        cv::Mat cvToGl = cv::Mat::zeros(4, 4, CV_32F);
        cvToGl.at<float>(0, 1) = 1.0f;
        cvToGl.at<float>(1, 0) = -1.0f; // Invert the y axis.
        cvToGl.at<float>(2, 2) = -1.0f; // invert the z axis
        cvToGl.at<float>(3, 3) = 1.0f;

        viewMatrix = cvToGl * viewMatrix;
        
        m.transformation = viewMatrix;
      
        
    }
}
