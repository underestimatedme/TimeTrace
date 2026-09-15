import Foundation

/// Debug hooks used for automated screenshots (spec §5 调试入口).
///   --sample-data          load createSampleData(), hasOnboarded = true, skip Splash
///   --screen <route>       today | tasks | tasks/new | tasks/<id> | timeline | insights | profile |
///                          focus/<id> | ai/<id> | projects | projects/<id> | goals/<id> | ai-tools |
///                          appearance | account | onboarding | splash
///   --theme <name>         claude | codex | cursor | light
///   --offline              disable networking entirely
///   --api-base-url <url>   override API base URL
struct LaunchOptions {
    var sampleData = false
    var screen: String?
    var theme: ThemeName?
    var offline = false
    var apiBaseURL: URL?
    var uiTesting = false
    var workspaceFixture = false

    static let current = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)

    init() {}

    init(arguments: [String]) {
        var i = 0
        while i < arguments.count {
            let arg = arguments[i]
            func value() -> String? { i + 1 < arguments.count ? arguments[i + 1] : nil }
            switch arg {
            case "--sample-data": sampleData = true
            case "--offline": offline = true
            case "--ui-testing": uiTesting = true; offline = true
            case "--workspace-fixture": workspaceFixture = true; sampleData = true; uiTesting = true; offline = true
            case "--screen": screen = value(); i += 1
            case "--theme": theme = value().flatMap(ThemeName.init(rawValue:)); i += 1
            case "--api-base-url": apiBaseURL = value().flatMap(URL.init(string:)); i += 1
            default: break
            }
            i += 1
        }
        if ProcessInfo.processInfo.environment["KEJI_OFFLINE"] == "1" { offline = true }
    }
}
