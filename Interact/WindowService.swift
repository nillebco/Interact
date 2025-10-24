import AppKit

enum WindowServiceError: Error {
    case unableToLookupWindows
}

enum WindowFilter {
    case all
    case visibleOnly

    fileprivate var cgOption: CGWindowListOption {
        switch self {
        case .all:
            return [.optionAll]
        case .visibleOnly:
            return [.optionOnScreenOnly, .excludeDesktopElements]
        }
    }
}

enum WindowService {
    static func fetchWindows(filter: WindowFilter = .visibleOnly) -> [WindowInfo] {
        let options: CGWindowListOption = filter.cgOption.union(.excludeDesktopElements)

        guard let windowList = CGWindowListCopyWindowInfo(
            options,
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return windowList.compactMap { entry in
            guard
                let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                let boundsDictionary = entry[kCGWindowBounds as String] as? [String: CGFloat],
                let owner = entry[kCGWindowOwnerName as String] as? String,
                let windowNumber = entry[kCGWindowNumber as String] as? UInt32,
                let pid = entry[kCGWindowOwnerPID as String] as? pid_t
            else {
                return nil
            }

            let title = (entry[kCGWindowName as String] as? String) ?? ""

            let bounds = CGRect(
                x: boundsDictionary["X"] ?? 0,
                y: boundsDictionary["Y"] ?? 0,
                width: boundsDictionary["Width"] ?? 0,
                height: boundsDictionary["Height"] ?? 0
            )

            guard bounds.width > 40, bounds.height > 40 else {
                return nil
            }

            return WindowInfo(
                id: CGWindowID(windowNumber),
                title: title,
                ownerName: owner,
                processID: pid,
                bounds: bounds
            )
        }
        .unique(by: \.id)
        .sorted(by: { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending })
    }
}

private extension Array {
    func unique<T: Hashable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        var seen = Set<T>()
        return compactMap { element in
            let key = element[keyPath: keyPath]
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return element
        }
    }
}
