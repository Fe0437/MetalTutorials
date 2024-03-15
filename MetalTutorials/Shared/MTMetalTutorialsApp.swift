//
//  MetalTutorialsApp.swift
//  Shared
//
//  Created by federico forti on 04/03/2021.
//

import SwiftUI

/**
 Welcome ! 🤗
 
 Choose the tutorial that you want and place it in the window group.
 It's enough to substitute the number of the tutorial in MT[N]ContentView.
 
 Every tutorial is indipendent except to the extensions that you can find in the folder Extensions
 (the name of the folder specifes where the extensions are used)
 
 - Attention: 🚨 at the moment this project is available only for IOS, porting everything to MacOS is easy
but it adds a lot of code and the objective of these tutorials is to keep the code as small as possible.
 
 - Attention: 🚨 Tutorial 5 and Tutorial 6 run only on device not on simulators
(you can run on mac if you run an app designed for ipad)
 
 */
@main
struct MetalTutorialsApp: App {
    var body: some Scene {
        WindowGroup {
            // substitute here to choose the tutorial
            MT6ContentView()
        }
    }
}
