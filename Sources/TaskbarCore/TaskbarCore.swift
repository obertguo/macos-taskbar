// Sources/TaskbarCore/TaskbarCore.swift

public struct TaskbarCoreInfo: Sendable {
    public static var version: String {
        BuildConfiguration.appVersion
    }
    
    public static var name: String {
        BuildConfiguration.appName
    }
    
    public static var bundleID: String {
        BuildConfiguration.bundleID
    }
    
    public init() {}
}
