//
//  ViewController.swift
//  Shakey
//
//  Created by Andrew Konoff on 2016-01-10.
//  Copyright © 2016 Andrew Konoff. All rights reserved.
//

import UIKit
import AVFoundation
import CoreMotion
import AssetsLibrary

enum CamUIState: Int {
    case TakePic = 0
    case CaptionOrPost = 1
    case Uploading = 2
    case Success = 3
}

let CapturingStillImageContext = UnsafeMutablePointer<()>()
let SessionRunningAndDeviceAuthorizedContext = UnsafeMutablePointer<()>()

let accelerationThreshold = 2.0 // lower is easier - 4.0 is good for prod
let decelerationThreshold = 0.2 // higher is easier - 0.07 is good for prod

extension AVCaptureVideoOrientation {
    var uiInterfaceOrientation: UIInterfaceOrientation {
        get {
            switch self {
            case .LandscapeLeft:        return .LandscapeLeft
            case .LandscapeRight:       return .LandscapeRight
            case .Portrait:             return .Portrait
            case .PortraitUpsideDown:   return .PortraitUpsideDown
            }
        }
    }
    
    init(ui:UIInterfaceOrientation) {
        switch ui {
        case .LandscapeRight:       self = .LandscapeRight
        case .LandscapeLeft:        self = .LandscapeLeft
        case .Portrait:             self = .Portrait
        case .PortraitUpsideDown:   self = .PortraitUpsideDown
        default:                    self = .Portrait
        }
    }
}

class ViewController: UIViewController {
    // cam capture stuff
    var capturedImage : UIImage?
    let motionManager = CMMotionManager()
    var shookHard = false
    
    let captureSession = AVCaptureSession()
    var captureDevice : AVCaptureDevice?
    var videoDeviceInput : AVCaptureDeviceInput?
    var stillImageOutput : AVCaptureStillImageOutput?
    var previewLayer : AVCaptureVideoPreviewLayer?
    
    let sessionQueue : dispatch_queue_t = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL) // for setting up the device preview using the main thread
    var backgroundRecordingID : UIBackgroundTaskIdentifier?
    var isDeviceAuthorized : Bool?
    var runtimeErrorHandlingObserver : AnyObject?
    
    var uiState : CamUIState = CamUIState.TakePic
    @IBOutlet weak var overlayImage: UIImageView!
    
    

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        // check if camera is allowed
        self.checkAuthStatus()

        // setup camera
        dispatch_async(self.sessionQueue) { () -> Void in
            let videoDevice = ViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: AVCaptureDevicePosition.Back)
            let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice)
            
            if self.captureSession.canAddInput(videoDeviceInput) {
                self.captureSession.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    let previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
                    previewLayer.connection.videoOrientation = AVCaptureVideoOrientation(ui:self.interfaceOrientation)
                    previewLayer.frame = self.view.bounds
                    self.view.layer.insertSublayer(previewLayer, below: self.overlayImage.layer)
                    self.previewLayer = previewLayer
                })
            }
            let stillImageOutput = AVCaptureStillImageOutput()
            if self.captureSession.canAddOutput(stillImageOutput) {
                stillImageOutput.outputSettings = [AVVideoCodecKey : AVVideoCodecJPEG]
                self.captureSession.addOutput(stillImageOutput)
                self.stillImageOutput = stillImageOutput
            }
        }
        
        // setup the coremotion manager
        self.motionManager.deviceMotionUpdateInterval = 0.1
    }
    
    override func viewWillAppear(animated: Bool) {
        dispatch_async(self.sessionQueue) { () -> Void in
            self.addObserver(self, forKeyPath: "sessionRunningAndDeviceAuthorized", options: [NSKeyValueObservingOptions.Old, NSKeyValueObservingOptions.New], context: SessionRunningAndDeviceAuthorizedContext)
            self.addObserver(self, forKeyPath: "stillImageOutput.capturingStillImage", options: [NSKeyValueObservingOptions.Old, NSKeyValueObservingOptions.New], context: CapturingStillImageContext)

            self.runtimeErrorHandlingObserver = NSNotificationCenter.defaultCenter().addObserverForName(AVCaptureSessionRuntimeErrorNotification, object: self.captureSession, queue: nil, usingBlock: { (notif) -> Void in
                self.captureSession.startRunning()
            })
            self.captureSession.startRunning()
        }
        
        // start motion manager
        self.motionManager.startDeviceMotionUpdatesToQueue(NSOperationQueue.currentQueue()!) { (motion, error) -> Void in
            if (error != nil) {
                print("%@", error)
            } else {
                self.motionMethod(motion!)
            }
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func switchToUI(state: CamUIState) {
        if state == CamUIState.TakePic {
            self.overlayImage.image = nil
            self.captureSession.startRunning()
        } else if state == CamUIState.CaptionOrPost {
            dispatch_async(self.sessionQueue, { () -> Void in
                self.captureSession.stopRunning()
                NSNotificationCenter.defaultCenter().removeObserver(self.runtimeErrorHandlingObserver!)
                self.removeObserver(self, forKeyPath: "sessionRunningAndDeviceAuthorized", context: SessionRunningAndDeviceAuthorizedContext)
                self.removeObserver(self, forKeyPath: "stillImageOutput.capturingStillImage", context: CapturingStillImageContext)
            })
            // show pic
            self.overlayImage.image = self.capturedImage
            
        }
    }
    
    func checkAuthStatus() {
        let mediaType = AVMediaTypeVideo
        AVCaptureDevice.requestAccessForMediaType(mediaType) { (granted) -> Void in
            if granted {
                self.isDeviceAuthorized = true
            } else {
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    let alertController = UIAlertController(title: "Shakegram??", message: "Shakeagram sad. Don't have access to camera. Shakeagram want you to change privacy settings. Please?", preferredStyle: .Alert)
                    let cancelAction = UIAlertAction(title: "OK", style: .Cancel, handler: { (action) -> Void in
                        // nothing
                    })
                    alertController.addAction(cancelAction)
                    self.presentViewController(alertController, animated: true, completion: { () -> Void in
                        // ok
                    })
                    
                })
            }
        }
    }
    
    class func deviceWithMediaType(mediaType: String, preferringPosition: AVCaptureDevicePosition) -> AVCaptureDevice {
        let devices = AVCaptureDevice.devicesWithMediaType(mediaType)
        
        var captureDevice : AVCaptureDevice?
        
        for device in devices {
            if device.position == preferringPosition {
                captureDevice = device as? AVCaptureDevice
                break
            }
        }
        return captureDevice!
    }
    // MARK: Motion manager stuff
    func motionMethod(deviceMotion: CMDeviceMotion) {
        let userAcceleration = deviceMotion.userAcceleration
        if self.uiState == CamUIState.TakePic {
            if self.shookHard == true {
                if fabs(userAcceleration.x) < decelerationThreshold && fabs(userAcceleration.y) < decelerationThreshold && fabs(userAcceleration.z) < decelerationThreshold {
                    // reset and display taken pic
                    print("Took pic: X%f Y%f Z%f", fabs(userAcceleration.x), fabs(userAcceleration.y), fabs(userAcceleration.z))
                    self.shookHard = false
                    self.switchToUI(CamUIState.CaptionOrPost)
                }
            } else {
                if fabs(userAcceleration.x) > accelerationThreshold && fabs(userAcceleration.y) > accelerationThreshold && fabs(userAcceleration.z) > accelerationThreshold {
                    print("Shook hard.")
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                    self.snapStillImage()
                    self.shookHard = true
                    let img = UIImage(named: "stop")
                    self.overlayImage.image = img
                }
            }
        }
    }
    
    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        if context == CapturingStillImageContext {
            let isCapturingStillImage = change![NSKeyValueChangeNewKey]?.boolValue
            
            if isCapturingStillImage == true {
                // here you'd fade in the preview layer if we had one
//                self.runStillImageCaptureAnimation()
            }
        } else if context == SessionRunningAndDeviceAuthorizedContext {
            let isRunning = change![NSKeyValueChangeNewKey]?.boolValue
            print("Session is running!")
        } else {
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        }
    }
    
    func snapStillImage() {
        dispatch_async(self.sessionQueue) { () -> Void in
            self.stillImageOutput?.connectionWithMediaType(AVMediaTypeVideo).videoOrientation = (self.previewLayer?.connection.videoOrientation)!
            self.stillImageOutput?.captureStillImageAsynchronouslyFromConnection(self.stillImageOutput?.connectionWithMediaType(AVMediaTypeVideo), completionHandler: { (imageDataSampleBuffer, err) -> Void in
                if (imageDataSampleBuffer != nil) {
                    let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                    let image = UIImage(data: imageData)
                    self.capturedImage = image
                    ALAssetsLibrary().writeImageToSavedPhotosAlbum(image?.CGImage, orientation: ALAssetOrientation(rawValue: image!.imageOrientation.rawValue)!, completionBlock: nil)
                }
            })
        }
    }
    
    func runStillImageCaptureAnimation() {
//        dispatch_async(dispatch_get_main_queue()) { () -> Void in
//            self.view.layer.
//        }
    }
    
    @IBAction func changeCamera(sender: AnyObject) {
        dispatch_async(self.sessionQueue) { 
            let currentVideoDevice : AVCaptureDevice = self.videoDeviceInput!.device
            var preferredPosition : AVCaptureDevicePosition = AVCaptureDevicePosition.Unspecified
            let currentPosition : AVCaptureDevicePosition = currentVideoDevice.position
            
            switch currentPosition {
            case AVCaptureDevicePosition.Unspecified:
                preferredPosition = AVCaptureDevicePosition.Back
                break
            case AVCaptureDevicePosition.Back:
                preferredPosition = AVCaptureDevicePosition.Front
                break
            case AVCaptureDevicePosition.Front:
                preferredPosition = AVCaptureDevicePosition.Back
                break
            }
            
            let videoDevice = ViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: preferredPosition)
            let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice)
            
            // configure and remove capture session
            self.captureSession.beginConfiguration()
            self.captureSession.removeInput(self.videoDeviceInput)
            
            if self.captureSession.canAddInput(videoDeviceInput) {
                NSNotificationCenter.defaultCenter().removeObserver(self, name: AVCaptureDeviceSubjectAreaDidChangeNotification, object: currentVideoDevice)
                self.captureSession.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
            } else {
                self.captureSession.addInput(self.videoDeviceInput)
            }
            self.captureSession.commitConfiguration()
        }
    }
    
    @IBAction func xButtonPressed(sender: AnyObject) {
        self.switchToUI(CamUIState.TakePic)
        self.addObserver(self, forKeyPath: "sessionRunningAndDeviceAuthorized", options: [NSKeyValueObservingOptions.Old, NSKeyValueObservingOptions.New], context: SessionRunningAndDeviceAuthorizedContext)
        self.addObserver(self, forKeyPath: "stillImageOutput.capturingStillImage", options: [NSKeyValueObservingOptions.Old, NSKeyValueObservingOptions.New], context: CapturingStillImageContext)
    }


}

