
#ifndef Example_MarkerBasedAR_CameraCalibration_hpp
#define Example_MarkerBasedAR_CameraCalibration_hpp

////////////////////////////////////////////////////////////////////
// File includes:
#include "GeometryTypes.hpp"

/**
 * A camera calibraiton class that stores intrinsic matrix
 * and distorsion vector.
 */
class CameraCalibration
{
public:
  CameraCalibration();
  CameraCalibration(float fx, float fy, float cx, float cy);
  CameraCalibration(float fx, float fy, float cx, float cy, float distorsionCoeff[4]);
  
  void getMatrix34(float cparam[3][4]) const;

  const Matrix33& getIntrinsic() const;
  const Vector4&  getDistorsion() const;
  
private:
  Matrix33 m_intrinsic;
  Vector4  m_distorsion;
};

#endif