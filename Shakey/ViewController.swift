//
//  ViewController.swift
//  Shakey
//
//  Created by Andrew Konoff on 2016-01-10.
//  Copyright © 2016 Andrew Konoff. All rights reserved.
//

import UIKit
import AVFoundation

enum CamUIState: Int {
    case CamUIStateTakePic = 0
    case CamUIStateCaptionOrPost = 1
    case CamUIStateUploading = 2
    case CamUIStateSuccess = 3
}

class ViewController: UIViewController {
    //    let session = AVCaptureSession()
    //    var sessionQueue : dispatch_queue_t?
    @IBOutlet weak var overlayImage: UIImageView!
    
    

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        // initialize the previewview
        
        // initialize the coremotion manager
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func switchToUI(state: CamUIState) {
        if state == CamUIState.CamUIStateTakePic {
            
        }
    }


}

