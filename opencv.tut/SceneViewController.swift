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
 
 */

import UIKit
import SceneKit
import AVFoundation
import CoreLocation

class SceneViewController: UIViewController , AVCaptureVideoDataOutputSampleBufferDelegate , SCNSceneRendererDelegate , TransformAcceptorDelegate
{
    
    private var cameraSession : AVCaptureSession?
    private var cameraLayer : AVCaptureVideoPreviewLayer?
    private let cameraProcessQeueu : DispatchQueue

    private var featureDetector : FeatureDetectorDelegate! = nil
    
    private let scene = SCNScene()
    private var sceneView : SCNView? = nil
    private let cameraNode = SCNNode()
    private var itemNode : SCNNode? = nil
    
    private var nodeTransforms : [SCNMatrix4] = []
    
    init()
    {
            cameraProcessQeueu =  DispatchQueue(label: "com.camera_process_queue.serial") // by default serial queue
            super.init(nibName: nil, bundle: nil)
            featureDetector = OpenCVDetectorAdapter(acceptor: self)
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
        self.setupCameraFeed()
        self.setupSceneKitView()
        self.positionSceneKitCamera()
        self.loadSceneNodes()
        self.positionSceneNodes()
        
        
        self.cameraProcessQeueu.async
        {
                self.cameraSession?.startRunning()
        }
    }

    /*
        desc : 
            Called by the SCNView before appying the animations and physics for each
            frame. Called once a frame. Update the position of the itemNodes here
            using the transformations that are avaliable.
 
    */
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval)
    {
            print("Rendering")
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
            self.itemNode = node
        }
        else
        {
            print("ERROR : failed to load node")
        }
    }
    
    
    func positionSceneKitCamera()
    {
        self.cameraNode.camera = SCNCamera()
        
        // THINK : How to transform the cameraNode properly to handle the calibrations and camera coordinate transforms
        self.cameraNode.position = SCNVector3(x: 0 , y: 0 , z:10)
        self.scene.rootNode.addChildNode(self.cameraNode)
    }
    
    func setupSceneKitView()
    {
            // For now take up the whole screen
            self.sceneView = SCNView(frame: self.view.bounds)
            self.sceneView?.scene = self.scene
            self.sceneView?.delegate = self
            self.sceneView?.backgroundColor = UIColor.clear
            self.view.addSubview(self.sceneView!)
    }
    
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
            self.cameraProcessQeueu.async
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
