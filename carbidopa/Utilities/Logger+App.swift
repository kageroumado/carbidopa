import Foundation
import os

extension Logger {
    static func app(category: String) -> Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "carbidopa", category: category)
    }
}
