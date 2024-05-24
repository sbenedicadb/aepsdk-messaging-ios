/*
Copyright 2023 Adobe. All rights reserved.
This file is licensed to you under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License. You may obtain a copy
of the License at http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under
the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
OF ANY KIND, either express or implied. See the License for the specific language
governing permissions and limitations under the License.
*/

import AEPMessaging
import SwiftUI

struct HomeView: View {
    @State private var viewDidLoad = false

    var body: some View {
        TabView {
            InAppView()
                .tabItem {
                    Label("InApp", systemImage: "doc.richtext.fill")
                }
            PushView()
                .tabItem {
                    Label("Push", systemImage: "paperplane.fill")
                }
            CodeBasedOffersView()
                .tabItem {
                    Label("Code Experiences", systemImage: "newspaper.fill")
                }
            ContentCardsView()
                .tabItem {
                    Label("Feeds", systemImage: "tray.and.arrow.down.fill")
                }
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
