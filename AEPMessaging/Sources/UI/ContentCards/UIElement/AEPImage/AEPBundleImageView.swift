/*
 Copyright 2024 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

#if canImport(SwiftUI)
    import SwiftUI
#endif

@available(iOS 15.0, *)
struct AEPBundleImageView: View {
    /// The model containing the data about the image.
    private let model: AEPImage

    /// The color scheme environment variable to detect light/dark mode changes and reload the bundled image if needed.
    @Environment(\.colorScheme) private var colorScheme

    init(_ model: AEPImage) {
        self.model = model
    }

    var body: some View {
        Image(themeBasedBundledImage())
            .resizable()
            .aspectRatio(contentMode: model.contentMode)
    }

    /// Determines the appropriate bundle resource for the image based on the color scheme of the device.
    /// - Returns: The name of the bundle resource to be used for the image.
    private func themeBasedBundledImage() -> String {
        if colorScheme == .dark {
            return model.darkBundle ?? model.bundle!
        } else {
            return model.bundle!
        }
    }
}
