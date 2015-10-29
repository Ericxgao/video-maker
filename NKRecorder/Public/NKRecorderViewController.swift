//
//  File.swift
//  VideoMaker
//
//  Created by Tom on 10/24/15.
//  Copyright © 2015 Tom. All rights reserved.
//

import UIKit
import SCRecorder

public struct NKVideoSession {
    let recordSession: SCRecordSession
    let composition: AVComposition
    let overlayImage: UIImage?
    let overlayImagePosition: CGPoint?
    let filter: SCFilter?
    
    public func export(completion: (NSURL) -> ()) {
        let assetExport = SCAssetExportSession(asset: composition)
        assetExport.outputUrl = recordSession.outputUrl
        assetExport.outputFileType = AVFileTypeMPEG4
        assetExport.audioConfiguration.preset = SCPresetHighestQuality
        //assetExport.videoConfiguration.preset = SCPresetHighestQuality
        assetExport.videoConfiguration.filter = filter
        if let overlayImage = overlayImage {
            assetExport.videoConfiguration.watermarkImage = overlayImage
            assetExport.videoConfiguration.watermarkFrame = CGRect(x: 0, y: 0, width: 480, height: 640) // FIXME: HAX - 640x480 hardcoded
        }
        assetExport.videoConfiguration.maxFrameRate = 35
        let timestamp = CACurrentMediaTime()
        assetExport.exportAsynchronouslyWithCompletionHandler({
            print(String(format: "Completed compression in %fs", CACurrentMediaTime() - timestamp))
            if (assetExport.error == nil) {
                completion(assetExport.outputUrl!)
            }
            else {
                print("Video couldn't be exported: \(assetExport.error)")
            }
        })
    }
    
    public func exportWithFirstFrame(completion: (NSURL, UIImage) -> ()) {
        export { exportedVideoURL in
            let asset = AVURLAsset(URL: exportedVideoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            do {
                let CGImage = try imageGenerator.copyCGImageAtTime(CMTimeMake(0, 1), actualTime: nil)
                let image = UIImage(CGImage: CGImage)
                completion(exportedVideoURL, image)
            } catch {
                print("AVAssetImageGenerator couldn't create a CGImage, completion block won't run: \(error)")
            }
        }
    }
}

public protocol NKRecorderDelegate: class {
    func willStartRecording(recorderViewController: NKRecorderViewController)
    func didCancelRecording(recorderViewController: NKRecorderViewController)
    func didProduceVideo(recorderViewController: NKRecorderViewController, videoSession: NKVideoSession)
}

public class NKRecorderViewController : UINavigationController {
    public static var shouldLoadFontsAtLaunch = true
    static let currentBundle = NSBundle(forClass: NKRecorderViewController.self)
    public weak var recorderDelegate: NKRecorderDelegate?
    weak var videoMakerViewContorller: VideoMakerViewController?
    public class func mainNavController() -> NKRecorderViewController {
        if shouldLoadFontsAtLaunch == true {
            var once: dispatch_once_t = 0
            dispatch_once(&once) {
                loadCustomFonts()
            }
        }
        let main = UIStoryboard(name: "Main", bundle: currentBundle)
        return main.instantiateViewControllerWithIdentifier("NKRecorderViewController") as! NKRecorderViewController
    }
    
    public func pauseVideo() {
        videoMakerViewContorller?.videoPlaybackVC.player?.pause()
    }
    
    public func resumeVideo() {
        videoMakerViewContorller?.videoPlaybackVC.player?.play()
    }
    
    // adds a spinning activity indicator
    public func freezeAndShowIndicator() {
        videoMakerViewContorller?.freezeAndShowIndicator()
    }
    
    // removes the spinning activity indicator
    public func unfreezeAndHideIndicator() {
        videoMakerViewContorller?.unfreezeAndHideIndicator()
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    private static func loadCustomFonts() {
        func iterateEnum<T: Hashable>(_: T.Type) -> AnyGenerator<T> {
            var i = 0
            return anyGenerator {
                let next = withUnsafePointer(&i) { UnsafePointer<T>($0).memory }
                return next.hashValue == i++ ? next : nil
            }
        }
        
        for font in iterateEnum(R.Fonts.self) {
            let fontURL = currentBundle.URLForResource(font.rawValue, withExtension: ".ttf")
            // loading custom fonts programatically: http://www.marco.org/2012/12/21/ios-dynamic-font-loading
            if let fontData = NSData(contentsOfURL: fontURL!) {
            let provider = CGDataProviderCreateWithCFData(fontData as CFDataRef)
            let font = CGFontCreateWithDataProvider(provider)
            var error: Unmanaged<CFError>?
            if (!CTFontManagerRegisterGraphicsFont(font!, &error)) {
                print("Failed to register font: \(error)")
                }
            }
        }
    }
}

extension NKRecorderViewController: VideoMakerDelegate {
    func videoMakerWillStartRecording(videoMaker: VideoMakerViewController) {
        recorderDelegate?.willStartRecording(self)
    }
    
    func videoMakerDidCancelRecording(videoMaker: VideoMakerViewController) {
        recorderDelegate?.didCancelRecording(self)
    }
    
    func videoMaker(videoMaker: VideoMakerViewController, didProduceVideoSession session: NKVideoSession) {
        recorderDelegate?.didProduceVideo(self, videoSession: session)
    }
}

extension NKRecorderViewController: UINavigationControllerDelegate {
    public func navigationController(navigationController: UINavigationController, willShowViewController viewController: UIViewController, animated: Bool) {
        if viewController is VideoMakerViewController {
            let vc = viewController as! VideoMakerViewController
            videoMakerViewContorller = vc
            vc.videoMakerDelegate = self
        }
    }
}