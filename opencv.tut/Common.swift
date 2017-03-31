//
//  Common.swift
//  opencv.tut
//
//  Created by scm197 on 3/31/17.
//  Copyright © 2017 scm197. All rights reserved.
//

import Foundation


extension CAAnimation
{
    class func animateWithSceneNamed(name : String) -> CAAnimation?
    {
        var anim : CAAnimation?
        if let scene = SCNScene(named:  name)
        {
            scene.rootNode.enumerateChildNodes({ (child, stop) in
                if child.animationKeys.count > 0
                {
                    anim = child.animation(forKey:child.animationKeys.first! )
                    stop.initialize(to: true)
                }
            })
        }
        return anim
    }
}
