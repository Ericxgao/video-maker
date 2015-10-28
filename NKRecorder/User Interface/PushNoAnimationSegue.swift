//
//  PushNoAnimationSegue.swift
//  VideoMaker
//
//  Created by Tom on 10/28/15.
//  Copyright © 2015 Tom. All rights reserved.
//

import UIKit

@objc(PushNoAnimationSegue)
class PushNoAnimationSegue: UIStoryboardSegue {
        override func perform() {
            let source = sourceViewController as UIViewController
            let dest = destinationViewController as UIViewController
            
            source.navigationController?.pushViewController(dest, animated: false)
        }
}
