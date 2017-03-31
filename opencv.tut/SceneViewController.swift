//
//  3DViewController.swift
//  opencv.tut
//
//  Created by scm197 on 3/15/17.
//  Copyright © 2017 scm197. All rights reserved.
//

/*
    Purpose of Existence
 
    Abstract : 
        Show the camera feed
        On top of the camera feed add 3D scene
        Recognize markers from the camera feed and apply the transform to 3D objects
 
    Details :
        Show the camera using the av preview layer
 
    Possible Issues  + Current state:
        I have setup scene kit so that it respects the 3D camera coordinate space. Which is defined by the
        Camera calibration and used by open cv to place the marker in the right location in the space.
            This is done by
                    1) getting the prespective transform and applying it to the camera node
                    2) Applying the transform of the model to be the same as the transform of the marker.
 
        Issues : 
                    1) Inverse relation between the transforms used by OPENCV/GL and Scene Kit.
                        Am I doing this conversion properly ?
                    2) Error in understanding of what is happening ?
 */

import UIKit
import SceneKit
import AVFoundation
import CoreLocation

class SceneViewController: UIViewController 
{
    
    fileprivate var cameraSession : AVCaptureSession?
    fileprivate var cameraInput : AVCaptureDeviceInput?
    fileprivate var cameraLayer : AVCaptureVideoPreviewLayer?
    fileprivate let cameraProcessQeueu : DispatchQueue

    fileprivate var featureDetector : (FeatureDetectorDelegate & PrespectiveProjBuilder)! = nil
    
    fileprivate let scene = SCNScene()
    fileprivate var sceneView : SCNView? = nil
    fileprivate let cameraNode = SCNNode()
    fileprivate var itemNode : SCNNode? = nil
   
    fileprivate var singleNodeTransform : SCNMatrix4! = nil
    fileprivate var singleBoxNode :SCNNode! = nil
    fileprivate var singleModelNode :SCNNode? = nil
    
    fileprivate var nodeTransforms : [SCNMatrix4] = []
    {
        willSet
        {
                singleNodeTransform =  newValue.isEmpty ? singleNodeTransform : newValue[0]
        }
    }
    
    init()
    {
            cameraProcessQeueu =  DispatchQueue(label: "com.camera_process_queue.serial") // by default serial queue
            super.init(nibName: nil, bundle: nil)
        
    }
    
    required init?(coder aDecoder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
  
    /*
        pre : default
        post : default
        input : none
        return : none
        state change : none
        desc : 
            default behavior + Shows the camera feed
    */
    override func viewDidLoad()
    {
        super.viewDidLoad()
        self.setupCameraCapture()
        
        featureDetector = OpenCVDetectorAdapter(acceptor: self, cameraInput: self.cameraInput!)
        
        self.setupSceneKitView()
        self.setupSceneKitCamera()
        self.setupLights()
        //self.positionCube()
        self.positionModel()
        
        self.cameraSession?.startRunning()
    }

    /*
        pre : The camera node should exist. The Scene and view should be set up.
              And the scnview size should be setup
        post : SceneKit is not able to convert from the 3D camera coor to the 2D camera coor in the right manner. 
                    Meaning that the porjection of the real camera and this artifical camera is lined up ?
     
        state change : 
        desc : 
                But what does it actually do ?
                    It positions the camera in camera coor space properly such that the tranforms applied to the model by
                    open cv to convert the model into camera coor is respected. That is, the models now become obserable
                    by the camera
                    THINK : Make this better
    */
    func setupPrespectiveTranformInSceneKit()
    {
            // Set properties for forming the projection matrix
            self.featureDetector.setScreenProperties(Int32(self.view.bounds.width), height: Int32(self.view.bounds.height))
        
            let prespectiveTransform = self.featureDetector.getPrespectiveSCNMatrix4()
       
            // Make sure that the prespective transform is set properly. Else, the 2D image might not even show up.
            self.cameraNode.camera?.projectionTransform = prespectiveTransform
     
    }
    
   
    /*
        pre :
        post :
        input :
        return :
        state change :
        
        desc :
            Puts the loaded items at the correct position
    */
    func positionSceneNodes()
    {
        if let itemNode = self.itemNode
        {
            itemNode.position = SCNVector3(x: 0, y: 0, z: 0)
            self.scene.rootNode.addChildNode(itemNode)
        }
    }
    
    /*
        pre : make sure scn file to load the node is present
        post : node will be loaded from the scn file
        input : none
        return : none
        state change :
                if success self.itemNode will have 3D item
                else self.itemNode will be nil
        desc : none
    */
    func loadSceneNodes()
    {
        let sceneForLoading = SCNScene(named: "art.scnassets/ship.scn")
        let node = sceneForLoading?.rootNode.childNode(withName: "ship", recursively: true)
        if let node = node
        {
            node.scale = SCNVector3Make(0.1, 0.1, 0.1)
            self.itemNode = node
        }
        else
        {
            print("ERROR : failed to load node")
        }
    }
   

    
    func setupSceneKitCamera()
    {
            self.cameraNode.camera = SCNCamera()
            self.setupPrespectiveTranformInSceneKit()
        
            // Rotating and positioning the camera so that the model is properly oriented.
            self.cameraNode.eulerAngles = SCNVector3Make(0 , 0 , Float(90.degreesToRadians))
            self.cameraNode.position = SCNVector3Make(1, -1, 2)
        
            self.sceneView?.scene?.rootNode.addChildNode(self.cameraNode)
            self.sceneView?.pointOfView = self.cameraNode  // Without setting this property, the camera and its prespective is not used.
      
            self.sceneView?.autoenablesDefaultLighting = true
       
            //self.sceneView?.allowsCameraControl = true
        
            // USED FOR DEBUGGING AND ORITENTING THE AXIS
            self.addDebugingHelpers()
    }
    
    func addDebugingHelpers()
    {
        
        let boxGeometryX = SCNBox(width: 0.3, height: 0.3, length: 0.3, chamferRadius: 0.0)
        boxGeometryX.firstMaterial!.diffuse.contents = UIColor.red
        boxGeometryX.firstMaterial!.specular.contents = UIColor.white
    
        let boxNodeX = SCNNode(geometry: boxGeometryX)
        boxNodeX.position = SCNVector3Make(0, 0, -5)
        scene.rootNode.addChildNode(boxNodeX)
  
        // add animation to box node
        boxNodeX.runAction(SCNAction.repeatForever(SCNAction.rotateBy(x: CGFloat(90.degreesToRadians), y: CGFloat(0.degreesToRadians), z: CGFloat(0.degreesToRadians), duration: 3)))

        let boxGeometryY = SCNBox(width: 0.3, height: 0.3, length: 0.3, chamferRadius: 0.0)
        boxGeometryY.firstMaterial!.diffuse.contents = UIColor.green
        boxGeometryY.firstMaterial!.specular.contents = UIColor.white
    
        let boxNodeY = SCNNode(geometry: boxGeometryY)
        boxNodeY.position = SCNVector3Make(0 , 0 , -4)
        scene.rootNode.addChildNode(boxNodeY)
    
        boxNodeY.runAction(SCNAction.repeatForever(SCNAction.rotateBy(x: CGFloat(0.degreesToRadians), y: CGFloat(90.degreesToRadians), z: CGFloat(0.degreesToRadians), duration: 3)))
     
    
    }
    
   
    func setupLights()
    {
        
            // Add lights without them the object will not show up
            let myLight = SCNLight()
            let myLightNode = SCNNode()
            myLight.type = SCNLight.LightType.omni
            myLight.color = UIColor.yellow
            myLightNode.light = myLight
            myLightNode.position = SCNVector3(-1.94764662, -0.0102603436, 5.74969292)
            scene.rootNode.addChildNode(myLightNode)
        
       
            let ambientLightNode = SCNNode()
            ambientLightNode.light = SCNLight()
            ambientLightNode.light!.type = .ambient
            ambientLightNode.light!.color = UIColor.white
            scene.rootNode.addChildNode(ambientLightNode)
        
    }
    
    
    func setupSceneKitView()
    {
            // For now take up the whole screen
            self.sceneView = SCNView(frame: self.view.bounds)
            self.sceneView?.scene = self.scene
            self.sceneView?.delegate = self
            self.sceneView?.play(nil)
            self.sceneView?.backgroundColor = UIColor.clear
            self.sceneView?.contentMode = .scaleAspectFit
            self.view.addSubview(self.sceneView!)
    }

    func positionCube()
    {
        let boxGeometry = SCNPyramid()
        boxGeometry.firstMaterial!.diffuse.contents = UIColor.blue
        boxGeometry.firstMaterial!.specular.contents = UIColor.white
        
        self.singleBoxNode = SCNNode(geometry: boxGeometry)
        
        self.singleBoxNode.eulerAngles = SCNVector3Make(-(Float)(90.degreesToRadians),0, 0)
        
        scene.rootNode.addChildNode(self.singleBoxNode)
        
    }
    
    
    func positionModel()
    {
        self.singleModelNode = loadArtModel(scene: "base_human" , node:"base_human_armtr")
        
        guard let singleModelNode = singleModelNode else {return}
      
        self.scene.rootNode.addChildNode(singleModelNode)
        
    }

    
    
    func loadArtModel(scene:String , node :String) -> SCNNode?
    {
        let scene = SCNScene(named: "art.scnassets/\(scene).dae")
        
        return scene?.rootNode.childNode(withName: node,recursively: true)
    }
    
    
}

extension SceneViewController : SCNSceneRendererDelegate
{
  
    /*
        desc : 
            Called by the SCNView before appying the animations and physics for each
            frame. Called once a frame. Update the position of the itemNodes here
            using the transformations that are avaliable.
            
            During each step of the render loop the markers transforms obtained by using opencv
            is used to draw the models.
 
    */
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval)
    {
        // Position the model in the right location in the 3D camera coor
        //singleModelNode?.transform = singleNodeTransform ?? SCNMatrix4Identity
    }
    
    func printNodeProperty(node : SCNNode)
    {
        print("poition : \(node.position)")
        print("rotation : \(node.rotation)")
        return
        print("Orientation :\(node.orientation)")
        print("transform : \(node.transform)")
        print("W transform : \(node.worldTransform)")
        print("Pivot : \(node.pivot))")
    }
}


// Extensions for setting up the camera and conforming to the delegate
extension SceneViewController : AVCaptureVideoDataOutputSampleBufferDelegate
{
    
    /*
        pre : done during init
        post : setups up avcapture session pointing at the back camera
        input : none
        return : none
        state change : 
            if success cameraSession gets a value
            if failure cameraSession value is nil
        desc :
            Sets up avcaptureSession on a background thread during init
    */
    func setupCameraCapture() 
    {
                let backCamera = AVCaptureDevice.defaultDevice(withDeviceType: .builtInWideAngleCamera, mediaType: AVMediaTypeVideo, position: .back)
                
                guard backCamera != nil else
                {
                    self.cameraSession = nil
                    let error = NSError(domain: "", code: -1, userInfo: ["description ":"Error adding back camera"])
                    print(error.localizedDescription)
                    return
                }
                
                var cameraInput : AVCaptureDeviceInput?
               
                do
                {
                        cameraInput = try AVCaptureDeviceInput(device: backCamera)
                }
                catch let error as NSError
                {
                   cameraInput = nil
                   print(error.localizedDescription)
                }
                
               
                guard cameraInput != nil else
                {
                    self.cameraSession = nil
                    let error = NSError(domain: "", code: -1, userInfo: ["description ":"Error create device input"])
                    print(error.localizedDescription)
                    return
                }
                
                self.cameraInput = cameraInput
                
                self.cameraSession = AVCaptureSession()
                
                if (self.cameraSession?.canAddInput(cameraInput))!
                {
                    self.cameraSession?.addInput(cameraInput)
                }
                else
                {
                    self.cameraSession = nil
                    let error = NSError(domain: "", code: -1, userInfo: ["description ":"Error adding video input"])
                    print(error.localizedDescription)
                    return
                }
                
                // set up the out for the session
                let videoOutput = AVCaptureVideoDataOutput()
                videoOutput.alwaysDiscardsLateVideoFrames = true
                videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as AnyHashable : kCMPixelFormat_32BGRA]
                videoOutput.setSampleBufferDelegate(self, queue: self.cameraProcessQeueu)
                
               
                if ( self.cameraSession?.canAddOutput(videoOutput) )!
                {
                    self.cameraSession?.addOutput(videoOutput)
                }
               
                videoOutput.connection(withMediaType: AVMediaTypeVideo)
               
                self.setupCameraFeed()
                
    }
   
    /*
     
     pre : have called setupCameraCapture for setting up the session
     post : the root views first layer now shows the camera preview
     input :  none
     return :  none
     state change : cameraLayer private variable gets a value
     description : Manipulation of the view hierarchy is done on the main thread
    */
    func setupCameraFeed()
    {
        guard self.cameraSession != nil else
        {
                let error = NSError(domain: "", code: -1, userInfo: ["description ":"Cannot create feed as capture session not working"])
                print(error.localizedDescription)
                return
        }
       
           self.cameraLayer = AVCaptureVideoPreviewLayer(session: self.cameraSession) ?? nil
            
           guard self.cameraLayer != nil else
           {
                let error = NSError(domain: "", code: -1, userInfo: ["description ":"Error creating preview layer"])
                print(error.localizedDescription)
                return
           }
            
           self.cameraLayer?.videoGravity = AVLayerVideoGravityResizeAspectFill
           self.cameraLayer?.frame = self.view.bounds
           self.view.layer.insertSublayer(self.cameraLayer!, at: 0)
    }
    
    /*
        pre :
        post :
        input :
        return
        state change :
        desc :
            The input buffer is passed in by avfoundation.  
            We pass this to opencv. Do the required processing and obtain the transformation
            matrices that are required.
     
            We store them and update the SceneKit.
            We need a FIFO buffer that will store the values that are passed in
            and pass it to SceneKit to update its position.
     
            Simple Architecture will not work here. 
            I need to pass this to another delegate which will feed the sample buffer into
            an ObjC class which will pass the data into the feature detector.
            From the feature . I need to obtain the transformations.
            Then I need to pass those tranformations back into this pass for SceneKit to use,
            using another delegate.
     
    */
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!)
    {
        // Process each frame. Reduce this to lower numbers
        featureDetector.detectFeatures(sampleBuffer)
    }
  
}


extension SceneViewController : TransformAcceptorDelegate
{
    
    /*
        pre : feature has to be detected before the transforms can be obtained.
        post :
        input : an array of SCNMatrix4 stored as NSValue
        return : none
        state change : get the transforms to be applied to the nodes in the scene
        desc :
            called by the featureDetector when the features are obtained and the transforms are passed back
            into the acceptor
            We just store the transforms, nothing is done with it.
    */
    func acceptTransforms(_ transforms: [Any]!)
    {
        // get rid of old transforms
        nodeTransforms = []
        
        // Extract the rotation and translation components and apply it to the models
        for transform in transforms
        {
            let value = transform as? NSValue
            if let value = value
            {
                let mat = value as? SCNMatrix4
                if let mat = mat
                {
                        nodeTransforms.append(mat)
                }
            }
        }
        
        if nodeTransforms.isEmpty
        {
           print("Failure to obtain transforms")
        }
    }
   
}




/*
    Discussion about the SceneKit camera and model setup.
    
    OpenCV allows us to find the pose of the camera. 
            > Which is the transformations that have to be made to a camera such that the 2D model 
              appears in a specific way in the 3D space. 
                    So in the case of markers. We have a 2D model of what they look like. Meaning their height width and the 
                    positions of the edges of the marker in a Model Coordinate system.
                    Open CV finds and compares this 2D model's position with the position of the markers ( edges ) in the 3D space
                    and finds the transformations that have to be made to the camera (rot , translation), such that the 2D item 
                    appears as such in the 3D space
    
                    Now if we invert the transformations that have to be applied to the camera, we get the transformations that
                    have to be applied to an object in 3D Model space such that they appear in right position in the Camera Coordinate system

 
 
    Then in OpenGL we set a projection Matrix, which determines how to do the transform from a 3D camera coordinate to a 2D camera Coordinate. The prespective projection using the frustrum. 
            This is done by setting the PROJECTION Matrix in OpenGL
 
    But using the transforms obtained using opencv which can be used to do a conversion between 2D model space to 3D model space.
    (
        We know that the marker is a 3D item, but for finding that correspondence, we have to use a 2D model space.
        The transform obtained by openCV can do a conversion between 3D model space to 3D camera coordinate space. 
                This is the high level description, I don't know how this is being done.
    )
 
    We tranfrom from the 3D model coor to 3D camera coor.
        This is done by setting the MODELVIEW Matrix in OpenGL. Which applies the transform form 3d model space to 3d camera coor.
 
    Then Finally the prespective projection does the conversion from the 3D camera coor to the 2D camera coor.
            So all the 3D model items transformed and placed in the 3D camera coor will be converted to cooresponding
            2D camera coor. 


    HOW TO CONVERT THIS TO SCENE KIT
        The parameters that I can control are
 
            1) the prespective tranform of the camera node
                [ Converts from 3D camera coor to 2D camera coor ]
 
            2) the transform of the nodes that are positioned in the camera coor
 
 
        How to set : 
 
            1)  
                There is an internal prepective transform of the camera node. This is USELESS as it only converts from the
                articial 3D camera coor to the 2D camera coor. It does not correspond to prespective tranform that has to
                done on every model in the real 3D camera coor to the real 2D camera coor.
 
                    May be a better term for the artificial camera coor is scene coor.

                So how to set this. Not sure. If I understand it correctly, then this should correspond to the 
                PROJECTION Matrix that is set in OpenGL.
 
                Issues here are : 
                            a) How to move the data from the cpp classes to the Swift classes
                            b) The SceneKit represent Matrix in a different form that the one used in OPENGL/CV
                                    Essentially this is just a transform
 
           2)
                Again if I am understanding the pipeline correctly. I will just have to set the transform obtained by
                open cv ( more presicely its inverse ( The transformed are stored in the inverted form already ))
                to the transform of the each of the nodes.
            
                Isssues here are :
                            a) The movement of the data
                            b) The inverse relationship between the data formats
 */

extension Int {
    var degreesToRadians: Double { return Double(self) * .pi / 180 }
}
extension FloatingPoint {
    var degreesToRadians: Self { return self * .pi / 180 }
    var radiansToDegrees: Self { return self * 180 / .pi }
}
