/*
 Copyright 2021 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

import UIKit
import AEPCore
import AEPEdgeConsent
import AEPEdgeIdentity
import AEPMessaging
import AEPEdge

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        MobileCore.setLogLevel(.trace)
        // ** staging environment **
        // sb_stage on "CJM Stage" (AJO Web sandbox)
        // App Surface - sb_app_configuration
        // com.adobe.MessagingDemoApp
        // staging/1b50a869c4a2/bcd1a623883f/launch-e44d085fc760-development
        
        // MobileCore.configureWith(appId: "staging/1b50a869c4a2/bcd1a623883f/launch-e44d085fc760-development")
        // let configDict = ConfigurationLoader.getConfig("functionalTestConfigStage")
        // MobileCore.updateConfigurationWith(configDict: configDict)
        
        // DC Tag > AJO - IAM end-to-end Functional Tests on "AEM Assets Departmental - Campaign" (Prod - VA7)
        // App Surface > AJO - IAM end-to-end Functional Tests
        // com.adobe.ajo.e2eTestApp
        // 3149c49c3910/04253786b724/launch-0cb6f35aacd0-development
        MobileCore.configureWith(appId: "3149c49c3910/04253786b724/launch-0cb6f35aacd0-development")

        let extensions = [
            Consent.self,
            Identity.self,
            Messaging.self,
            Edge.self
        ]

        MobileCore.registerExtensions(extensions)
        
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options _: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_: UIApplication, didDiscardSceneSessions _: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}
