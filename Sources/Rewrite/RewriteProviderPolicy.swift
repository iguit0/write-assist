// WriteAssist — macOS menu bar writing assistant
// Copyright © 2024 Igor Alves. All rights reserved.

import Foundation

struct RewriteProviderPolicy: Sendable, Equatable {
    let primary: AIProvider
    let fallback: AIProvider?
}
