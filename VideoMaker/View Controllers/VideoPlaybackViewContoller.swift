//
//  VideoPlaybackViewContoller.swift
//  VideoMaker
//
//  Created by Tom on 9/7/15.
//  Copyright (c) 2015 Tom. All rights reserved.
//

import UIKit
import SCRecorder

class VideoPlaybackViewController: BaseViewController {
    
    @IBOutlet weak var UIElementsContainerView: UIElementsContainer!
    @IBOutlet weak var filterSwipableView: SCSwipeableFilterView!
    
    @IBOutlet weak var audioTypeButton: AudioTypeButton!
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var insertCaptionButton: UIButton!
    @IBOutlet weak var editAudioButton: UIButton!
    @IBOutlet weak var sendButton: UIButton!
    
    //@IBOutlet weak var draggableAudioSlider: DraggableSlider!
    //@IBOutlet weak var editAudioFinishedButton: UIButton!
    
    @IBOutlet weak var trackNameLabel: TrackNameLabel!
    @IBOutlet weak var trackNameLabelBG: UIView!
    
    @IBOutlet weak var activityIndicatorContainer: UIView!
    @IBOutlet weak var activityIndicatorView: UIActivityIndicatorView!
    
    var recordSession: SCRecordSession?
    var player: SCPlayer?
    var playerLayer: AVPlayerLayer?
    var composition: AVMutableComposition?
    
    var captionView: OverlayCaptionView?
    var captionViewPanGestureRecognizer: UIPanGestureRecognizer?
    
    var tapGestureRecognizer: UITapGestureRecognizer? // used for keyboard dismissal
    
    //var audioStartingPosition: Double = 0.0
    var canUseOriginalSound = true // if a song was chosen during the recording, one cannot use the original sound
    var initialAudioTypeButtonState: AudioTypeButton.ButtonState = .OriginalSound
    
// MARK: - View Controller Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        player = SCPlayer()
        player?.loopEnabled = true
        filterSwipableView.refreshAutomaticallyWhenScrolling = false // can't tell what this does, but it is false in the examples, so better stay it
        filterSwipableView.contentMode = .ScaleAspectFit
        let emptyFilter = SCFilter()
        emptyFilter.name = "No Filter"
        filterSwipableView.filters = [emptyFilter,
                                      SCFilter(CIFilterName: "CIPhotoEffectChrome"),
                                      SCFilter(CIFilterName: "CIPhotoEffectFade"),
                                      SCFilter(CIFilterName: "CIPhotoEffectInstant"),
                                      SCFilter(CIFilterName: "CIPhotoEffectMono"),
                                      SCFilter(CIFilterName: "CIPhotoEffectNoir"),
                                      SCFilter(CIFilterName: "CIPhotoEffectProcess"),
                                      SCFilter(CIFilterName: "CIPhotoEffectTonal"),
                                      SCFilter(CIFilterName: "CIPhotoEffectTransfer")]
        player?.CIImageRenderer = filterSwipableView
        
        if navigationController?.respondsToSelector("interactivePopGestureRecognizer") != nil {
            navigationController?.interactivePopGestureRecognizer?.enabled = false
        }
        
        audioTypeButton.buttonState = initialAudioTypeButtonState
        if audioTypeButton.buttonState == .PickSong {
            canUseOriginalSound = false
        }
    }
    
    override func viewWillAppear(animated: Bool) {
        print("musicTrackInfo: \(musicTrackInfo)")
        
        configureTrackNameLabel()
        configureCompositionAndPlay()
    }
    
    override func viewDidLayoutSubviews() {
        playerLayer?.frame = filterSwipableView.bounds
    }
    
    override func viewWillDisappear(animated: Bool) {
        player?.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "Choose Music Playlist" {
            navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .Plain, target: nil, action: nil)
            let targetNavController = segue.destinationViewController as! UINavigationController
            let choosePlaylistViewContorller = targetNavController.topViewController as! ChoosePlaylistCollectionViewController
            choosePlaylistViewContorller.segueBackViewController = self
        }
    }
    
    override func prefersStatusBarHidden() -> Bool {
        return true
    }
    
// MARK: - Creating a Composition
    func configureCompositionAndPlay() {
        if musicTrackInfo != nil { // if music is chosen, music is mixed to the video
            compositionFromMusicTrackAndRecordedMaterial()
        } else {
            compositionFromRecordedMaterial()
        }
        player?.setItemByAsset(composition)
        player?.play()
    }
    
    func compositionFromMusicTrackAndRecordedMaterial() {
        compositionFromRecordedMaterial()
        if let oldMutableCompositionAudioTrack = composition?.tracksWithMediaType(AVMediaTypeAudio).first {
            composition?.removeTrack(oldMutableCompositionAudioTrack)
        }
        let recordedVideoTrack = composition?.tracksWithMediaType(AVMediaTypeVideo).first
        
        let mutableCompositionAudioTrack = composition?.addMutableTrackWithMediaType(AVMediaTypeAudio, preferredTrackID: CMPersistentTrackID())
        if let assetURL = LocalMusicManager.returnMusicDataFromTrackId(trackId: musicTrackInfo!.id) {
            let musicAsset = AVURLAsset(URL: assetURL)
            if let musicAssetTrack = musicAsset.tracksWithMediaType(AVMediaTypeAudio).first, videoTrackDuration = recordedVideoTrack?.timeRange.duration {
                do {
                    try mutableCompositionAudioTrack?.insertTimeRange(CMTimeRangeMake(kCMTimeZero, videoTrackDuration), ofTrack:musicAssetTrack, atTime: kCMTimeZero)
                } catch {
                    print("Music Track  timeRange couldn't be added: \(error)")
                }
            }
        }
    }
    
    func compositionFromRecordedMaterial() {
        composition = AVMutableComposition()
        if var composition = composition {
            addVideoDataToComposition(&composition)
            if (audioTypeButton.buttonState == .OriginalSound) {
                addAudioDataToComposition(&composition)
            }
        }
    }
    
    func addVideoDataToComposition(inout composition: AVMutableComposition) {
        let mutableCompositionVideoTrack = composition.addMutableTrackWithMediaType(AVMediaTypeVideo, preferredTrackID: CMPersistentTrackID())
        
        if let segments = recordSession?.segments as? [SCRecordSessionSegment] {
            var currentVideoTime = kCMTimeZero
            for segment in segments {
                if let videoAssetTracks = segment.asset?.tracksWithMediaType(AVMediaTypeVideo) {
                    for videoAssetTrack in videoAssetTracks {
                        do {
                            try mutableCompositionVideoTrack.insertTimeRange(CMTimeRangeMake(kCMTimeZero, videoAssetTrack.timeRange.duration), ofTrack:videoAssetTrack, atTime:currentVideoTime)
                        } catch {
                            print("Mutable Video Composition Track couldn't adda timeRange")
                        }
                        let timescale = segment.info?["timescale"] as! Float
                        let scaledDuration = CMTimeMultiplyByFloat64(videoAssetTrack.timeRange.duration, Float64(timescale))
                        mutableCompositionVideoTrack.scaleTimeRange(CMTimeRangeMake(currentVideoTime, videoAssetTrack.timeRange.duration), toDuration:scaledDuration)
                        currentVideoTime = CMTimeAdd(currentVideoTime, scaledDuration)
                    }
                }
            }
        }
    }
    
    func addAudioDataToComposition(inout composition: AVMutableComposition) {
        let mutableCompositionAudioTrack = composition.addMutableTrackWithMediaType(AVMediaTypeAudio, preferredTrackID: CMPersistentTrackID())
        
        if let segments = recordSession?.segments as? [SCRecordSessionSegment] {
            var currentAudioTime = kCMTimeZero

            for segment in segments {
                if let audioAssetTracks = segment.asset?.tracksWithMediaType(AVMediaTypeAudio) {
                    for audioAssetTrack in audioAssetTracks {
                        do {
                            try mutableCompositionAudioTrack.insertTimeRange(CMTimeRangeMake(kCMTimeZero, audioAssetTrack.timeRange.duration), ofTrack: audioAssetTrack, atTime: currentAudioTime)
                        } catch {
                            print("Mutable Audio Composition Track couldn't add a timeRange")
                        }
                        let timescale = segment.info?["timescale"] as! Float
                        let scaledDuration = CMTimeMultiplyByFloat64(audioAssetTrack.timeRange.duration, Float64(timescale))
                        mutableCompositionAudioTrack.scaleTimeRange(CMTimeRangeMake(currentAudioTime, audioAssetTrack.timeRange.duration), toDuration: scaledDuration)
                        currentAudioTime = CMTimeAdd(currentAudioTime, scaledDuration)
                    }
                }
            }
        }
    }
// MARK: - Button Touch Handlers
    @IBAction func saveToCameraRollPressed(sender: AnyObject)
    {
        activityIndicatorContainer.hidden = false
        activityIndicatorView.startAnimating()
        player?.pause()
        UIApplication.sharedApplication().beginIgnoringInteractionEvents()
        let segmentsAsset = composition
        var assetExport = SCAssetExportSession()
        if let asset = segmentsAsset {
            assetExport = SCAssetExportSession(asset: asset)
        }
        assetExport.outputUrl = recordSession?.outputUrl
        assetExport.outputFileType = AVFileTypeMPEG4
        assetExport.audioConfiguration.preset = SCPresetHighestQuality
        assetExport.videoConfiguration.preset = SCPresetHighestQuality
        assetExport.videoConfiguration.filter = filterSwipableView.selectedFilter
        if let captionView = captionView {
            assetExport.videoConfiguration.overlay = captionView
        }
        assetExport.videoConfiguration.maxFrameRate = 35
        let timestamp = CACurrentMediaTime()
        assetExport.exportAsynchronouslyWithCompletionHandler({
            print(String(format: "Completed compression in %fs", CACurrentMediaTime() - timestamp))
            if (assetExport.error == nil) {
                if let path = assetExport.outputUrl?.path {
                    UISaveVideoAtPathToSavedPhotosAlbum(path, self, "video:didFinishSavingWithError:contextInfo:", nil)
                }
            }
            else {
                UIApplication.sharedApplication().endIgnoringInteractionEvents()
                UIAlertView(title: "Failed to save", message:assetExport.error?.localizedDescription, delegate: nil, cancelButtonTitle: "Okay").show()
            }
        })
    }

    @IBAction func insertCaptionPressed(sender: AnyObject) {
        if captionView == nil {
            tapGestureRecognizer = UITapGestureRecognizer(target: self, action: "dismissKeyboard:")
            if let recognizer = tapGestureRecognizer {
                self.view.addGestureRecognizer(recognizer)
            }
            captionView = OverlayCaptionView(frame: view.frame)
            captionViewPanGestureRecognizer = UIPanGestureRecognizer(target: self, action: "captionPanGestureRecognized:")
            if let captionView = captionView {
                if let gestureRecognizer = captionViewPanGestureRecognizer {
                    captionView.addGestureRecognizer(gestureRecognizer)
                    view.addSubview(captionView)
                    NSNotificationCenter.defaultCenter().addObserver(self, selector: "keyboardWillShow:", name: UIKeyboardWillShowNotification, object:nil)
                }
            }
        } else {
            captionView?.removeFromSuperview()
            captionView = nil
        }
    }
    
    func captionPanGestureRecognized(recognizer: UIPanGestureRecognizer) {
        let translationPoint = recognizer.translationInView(self.view)
        if let view = recognizer.view {
            if view.center.y + translationPoint.y > CGRectGetMaxY(insertCaptionButton.frame) + 15 && view.center.y + translationPoint.y < CGRectGetMinY(sendButton.frame) - 15 { // 15 is temporary, change when new ui elements will be there
                view.center = CGPointMake(view.center.x, view.center.y + translationPoint.y)
                captionView?.viewPercentageYPos = view.frame.origin.y / self.view.frame.height
                recognizer.setTranslation(CGPointMake(0, 0), inView:self.view)
            }
        }
    }
    
    func dismissKeyboard(recognizer: UITapGestureRecognizer) {
        if let isEditing = captionView?.textField.editing {
            if isEditing == true {
                captionView?.textField.endEditing(true)
            }
        }
    }
    
    @IBAction func backButtonPressed(sender: AnyObject) {
        let alertController = UIAlertController(title: "Discard Recording", message: "Do you really want to discard your current recording?", preferredStyle: .Alert)
        
        let yesAction = UIAlertAction(title: "Yes", style: .Destructive) { (action) in
            let recordingViewController = self.navigationController?.viewControllers[0] as! RecordViewController
            recordingViewController.retakeButtonPressed(self)
            self.navigationController?.popViewControllerAnimated(true)
        }
        alertController.addAction(yesAction)
        let cancelAction = UIAlertAction(title: "Cancel", style: .Cancel) { (action) in
            alertController.dismissViewControllerAnimated(true, completion: nil)
        }
        alertController.addAction(cancelAction)
        presentViewController(alertController, animated: true, completion: nil)
    }
    
    @IBAction func audioTypeButtonPressed(sender: AnyObject) {
        let actionSheetController = UIAlertController(title: nil, message: nil, preferredStyle: .ActionSheet)
        actionSheetController.view.tintColor = StyleKit.lightPurple
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .Cancel) { (action) in
            actionSheetController.dismissViewControllerAnimated(true, completion: nil)
        }
        actionSheetController.addAction(cancelAction)
        
        let originalSoundAction = UIAlertAction(title: "Original Sound", style: .Default) { (action) in
            self.audioTypeButton.buttonState = .OriginalSound
            self.musicTrackInfo = nil
            self.configureTrackNameLabel()
            self.player?.pause()
            self.configureCompositionAndPlay()
        }
        originalSoundAction.enabled = canUseOriginalSound
        actionSheetController.addAction(originalSoundAction)
        
        let addMusicAction = UIAlertAction(title: "Pick a Song", style: .Default) { (action) in
            self.performSegueWithIdentifier("Choose Music Playlist", sender: self)
        }
        actionSheetController.addAction(addMusicAction)
        
        let noSoundAction = UIAlertAction(title: "No Sound", style: .Default) { (action) in
            self.audioTypeButton.buttonState = .NoSound
            self.musicTrackInfo = nil
            self.configureTrackNameLabel()
            self.player?.pause()
            self.configureCompositionAndPlay()
        }
        actionSheetController.addAction(noSoundAction)
        
        presentViewController(actionSheetController, animated: true, completion: nil)
    }

// MARK: - UI Related
    func configureTrackNameLabel() {
        if let musicTrackInfo = musicTrackInfo {
            audioTypeButton.buttonState = .PickSong
            trackNameLabel.changeScrollableTextTo(String.presentableArtistAndSongName(musicTrackInfo.artistName, songName: musicTrackInfo.trackName))
            trackNameLabel.layer.opacity = 1.0
            trackNameLabelBG.layer.opacity = 1.0
            editAudioButton.layer.opacity = 1.0
        } else {
            trackNameLabel.changeScrollableTextTo("")
            trackNameLabel.layer.opacity = 0.0
            trackNameLabelBG.layer.opacity = 0.0
            editAudioButton.layer.opacity = 0.0
        }
    }
//    
//    func reconfigureCaptionView() {
//        let currentCaptionViewFrame = captionView!.frame
//        let currentCaptionViewText = captionView!.textField.text
//        captionView!.removeFromSuperview()
//        captionView = nil
//        insertCaptionPressed(self)
//        captionView?.frame = currentCaptionViewFrame
//        captionView?.textField.text = currentCaptionViewText
//    }
    
//    @IBAction func editAudioPressed(sender: AnyObject) {
//        configureDraggableSlider()
//    }
//    
//    @IBAction func editAudioFinishedPressed(sender: AnyObject) {
//        draggableAudioSlider.hidden = true
//        editAudioFinishedButton.hidden = true
//        editAudioButton.enabled = true
//        audioStartingPosition = draggableAudioSlider.lowerValue
//    }
    
//    func draggableAudioSliderEditingDidStart() {
//        player?.pause()
//    }
//    
//    func draggableAudioSliderEditingDidEnd() {
//        if let oldMutableCompositionAudioTrack = composition?.tracksWithMediaType(AVMediaTypeAudio).first {
//            composition?.removeTrack(oldMutableCompositionAudioTrack)
//        }
//        
//        let recordedVideoTrack = composition?.tracksWithMediaType(AVMediaTypeVideo).first
//        
//        let mutableCompositionAudioTrack = composition?.addMutableTrackWithMediaType(AVMediaTypeAudio, preferredTrackID: CMPersistentTrackID())
//        if let musicAsset = AVURLAsset(URL: LocalMusicManager.returnMusicDataFromTrackId(trackId: musicTrackInfo!.id)) {
//            if let musicAssetTrack = musicAsset.tracksWithMediaType(AVMediaTypeAudio).first, videoTrackDuration = recordedVideoTrack?.timeRange.duration {
//                do {
//                    let startingTime = CMTime(seconds: draggableAudioSlider.lowerValue, preferredTimescale: musicAssetTrack.timeRange.duration.timescale)
//                    try mutableCompositionAudioTrack?.insertTimeRange(CMTimeRangeMake(startingTime, videoTrackDuration), ofTrack:musicAssetTrack, atTime: kCMTimeZero)
//                } catch {
//                    print("Music Track timeRange couldn't be added: \(error)")
//                }
//            }
//        }
//        player?.setItemByAsset(composition)
//        player?.play()
//    }
    
// MARK: - Misc
    
//    func configureDraggableSlider() {
//        if let musicTrackInfo = musicTrackInfo {
//            let musicAsset = AVURLAsset(URL: musicTrackInfo.url)
//            if let musicAssetTrack = musicAsset.tracksWithMediaType(AVMediaTypeAudio).first {
//                draggableAudioSlider.minimumValue = 0.0
//                draggableAudioSlider.maximumValue = Double(CMTimeGetSeconds(musicAssetTrack.timeRange.duration))
//                
//                if let videoTrack = composition?.tracksWithMediaType(AVMediaTypeVideo).first {
//                    draggableAudioSlider.upperValue = audioStartingPosition + Double(CMTimeGetSeconds(videoTrack.timeRange.duration))
//                    draggableAudioSlider.lowerValue = audioStartingPosition
//                    draggableAudioSlider.updateRange()
//                }
//                draggableAudioSlider.hidden = false
//                editAudioFinishedButton.hidden = false
//                editAudioButton.enabled = false
//                draggableAudioSlider.addTarget(self, action: "draggableAudioSliderEditingDidEnd", forControlEvents: .TouchDragExit)
//                draggableAudioSlider.addTarget(self, action: "draggableAudioSliderEditingDidStart", forControlEvents: .TouchDragEnter)
//            }
//        }
//    }
    
    func keyboardWillShow(notification: NSNotification) {
        if let captionView = captionView {
            if captionView.textField.isFirstResponder() == true {
                let keyboardFrame = (notification.userInfo?[UIKeyboardFrameEndUserInfoKey] as! NSValue).CGRectValue()
                let animationDuration = (notification.userInfo?[UIKeyboardAnimationDurationUserInfoKey] as! NSNumber).doubleValue
                UIView.animateWithDuration(animationDuration, animations: {
                    captionView.frame = CGRect(x: captionView.frame.origin.x, y: keyboardFrame.origin.y - captionView.frame.size.height, width: captionView.frame.size.width, height: captionView.frame.size.height)
                }, completion: { (Bool) -> Void in
                    captionView.viewPercentageYPos = captionView.frame.origin.y / self.view.frame.height
                })
            }
        }
    }
    
    func video(videoPath: NSString?, didFinishSavingWithError error: NSError?, contextInfo: UnsafePointer<()>) {
        UIApplication.sharedApplication().endIgnoringInteractionEvents()
        player?.play()
        activityIndicatorContainer.hidden = true
        activityIndicatorView.stopAnimating()
        insertCaptionPressed(self)
        if (error == nil) {
            UIAlertView(title: "Saved to camera roll", message:"", delegate: nil, cancelButtonTitle: "Done").show()
        } else {
            UIAlertView(title: "Failed to save", message: "'", delegate: nil, cancelButtonTitle: "Okay").show()
        }
    }
    
}