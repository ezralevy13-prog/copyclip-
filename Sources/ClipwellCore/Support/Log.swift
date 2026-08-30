import Foundation
import os

enum Log {
    private static let subsystem = "com.ezralevy.clipwell"

    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let store   = Logger(subsystem: subsystem, category: "store")
    static let ui      = Logger(subsystem: subsystem, category: "ui")
    static let paste   = Logger(subsystem: subsystem, category: "paste")
}
