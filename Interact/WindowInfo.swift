import AppKit

struct WindowInfo: Identifiable, Hashable {
    let id: CGWindowID
    let title: String
    let ownerName: String
    let processID: pid_t
    let bounds: CGRect

    var displayTitle: String {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ownerName
        }
        return title
    }

    var subtitle: String {
        "\(ownerName) · PID \(processID)"
    }
}
