import Foundation

public enum BrowserCleanerScanner {
    public static let defaultRules: [CleanerItem] = [
        // Safari
        CleanerItem(
            id: "safari-cache",
            title: "Safari Cache",
            path: "~/Library/Caches/com.apple.Safari",
            risk: .safe,
            description: "Safari browser cache. Safe to remove; Safari will rebuild cached content as you browse."
        ),
        CleanerItem(
            id: "safari-container-cache",
            title: "Safari Container Cache",
            path: "~/Library/Containers/com.apple.Safari/Data/Library/Caches",
            risk: .safe,
            description: "Safari sandbox cache files. Safe to remove without deleting bookmarks, history, or saved passwords."
        ),
        CleanerItem(
            id: "safari-favicon-cache",
            title: "Safari Favicon Cache",
            path: "~/Library/Safari/Favicon Cache",
            risk: .safe,
            description: "Safari website icon cache. Safe to remove; icons will be downloaded again."
        ),

        // Chrome
        CleanerItem(
            id: "chrome-browser-cache",
            title: "Chrome Browser Cache",
            path: "~/Library/Caches/Google/Chrome",
            risk: .safe,
            description: "Chrome HTTP, storage, and code caches across profiles. Safe to remove; Chrome will recreate cache data as you browse."
        ),
        CleanerItem(
            id: "chrome-screen-ai",
            title: "Chrome Screen AI Models",
            path: "~/Library/Application Support/Google/Chrome/screen_ai",
            risk: .safe,
            description: "Downloaded Chrome Screen AI OCR/accessibility models. Safe to remove; Chrome may download them again if the feature is used."
        ),
        CleanerItem(
            id: "chrome-component-cache",
            title: "Chrome Component Cache",
            path: "~/Library/Application Support/Google/Chrome/component_crx_cache",
            risk: .safe,
            description: "Cached Chrome component update packages. Safe to remove; Chrome will re-fetch components if needed."
        ),
        CleanerItem(
            id: "chrome-on-device-model",
            title: "Chrome On-Device AI Model",
            path: "~/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel",
            risk: .safe,
            description: "Chrome on-device optimization guide model files. Safe to remove; Chrome may download them again."
        ),
        CleanerItem(
            id: "chrome-on-device-classifier",
            title: "Chrome On-Device Classifier",
            path: "~/Library/Application Support/Google/Chrome/OptGuideOnDeviceClassifierModel",
            risk: .safe,
            description: "Chrome on-device classifier model files. Safe to remove; Chrome may download them again."
        ),
        CleanerItem(
            id: "chrome-head-suggest-model",
            title: "Chrome Head Suggest Model",
            path: "~/Library/Application Support/Google/Chrome/OnDeviceHeadSuggestModel",
            risk: .safe,
            description: "Chrome on-device address-bar suggestion model. Safe to remove; Chrome may download it again."
        ),
        CleanerItem(
            id: "chrome-optimization-hints",
            title: "Chrome Optimization Hints",
            path: "~/Library/Application Support/Google/Chrome/OptimizationHints",
            risk: .safe,
            description: "Downloaded Chrome optimization hint data. Safe to remove; Chrome will regenerate or re-download it as needed."
        ),
        CleanerItem(
            id: "chrome-optimization-model-store",
            title: "Chrome Optimization Model Store",
            path: "~/Library/Application Support/Google/Chrome/optimization_guide_model_store",
            risk: .safe,
            description: "Chrome optimization guide model store. Safe to remove; Chrome may download model data again."
        ),

        // Other Chromium browsers
        chromiumCache("chromium", "Chromium", "~/Library/Caches/Chromium"),
        chromiumComponentCache("chromium-component-cache", "Chromium Component Cache", "~/Library/Application Support/Chromium/component_crx_cache"),
        chromiumCache("edge", "Microsoft Edge", "~/Library/Caches/Microsoft Edge"),
        chromiumComponentCache("edge-component-cache", "Microsoft Edge Component Cache", "~/Library/Application Support/Microsoft Edge/component_crx_cache"),
        chromiumCache("brave", "Brave", "~/Library/Caches/BraveSoftware/Brave-Browser"),
        chromiumComponentCache("brave-component-cache", "Brave Component Cache", "~/Library/Application Support/BraveSoftware/Brave-Browser/component_crx_cache"),
        chromiumCache("arc", "Arc", "~/Library/Caches/company.thebrowser.Browser"),
        chromiumComponentCache("arc-component-cache", "Arc Component Cache", "~/Library/Application Support/Arc/component_crx_cache"),
        chromiumCache("vivaldi", "Vivaldi", "~/Library/Caches/Vivaldi"),
        chromiumComponentCache("vivaldi-component-cache", "Vivaldi Component Cache", "~/Library/Application Support/Vivaldi/component_crx_cache"),
        chromiumCache("opera", "Opera", "~/Library/Caches/com.operasoftware.Opera"),
        chromiumComponentCache("opera-component-cache", "Opera Component Cache", "~/Library/Application Support/com.operasoftware.Opera/component_crx_cache"),

        // Firefox
        CleanerItem(
            id: "firefox-cache",
            title: "Firefox Cache",
            path: "~/Library/Caches/Firefox",
            risk: .safe,
            description: "Firefox profile caches. Safe to remove; Firefox keeps bookmarks, history, and saved passwords under Application Support."
        )
    ]

    public static func runSelfCheck() {
        let ids = defaultRules.map(\.id)
        assert(Set(ids).count == ids.count)
        assert(defaultRules.contains { $0.id == "chrome-browser-cache" })
        assert(defaultRules.allSatisfy { !$0.path.contains("/Google/Chrome/Default") })
    }

    private static func chromiumCache(_ idPrefix: String, _ browserName: String, _ path: String) -> CleanerItem {
        CleanerItem(
            id: "\(idPrefix)-browser-cache",
            title: "\(browserName) Browser Cache",
            path: path,
            risk: .safe,
            description: "\(browserName) browser cache. Safe to remove; cached content will be rebuilt as you browse."
        )
    }

    private static func chromiumComponentCache(_ id: String, _ title: String, _ path: String) -> CleanerItem {
        CleanerItem(
            id: id,
            title: title,
            path: path,
            risk: .safe,
            description: "Cached Chromium component update packages. Safe to remove; the browser will re-fetch components if needed."
        )
    }
}
