import Foundation
import UIKit

/// Opens action-item deep links in the native GitHub / Linear / Slack apps
/// when installed, falling back to the browser.
@MainActor
enum LinkOpener {

    static func open(_ link: TaskDeepLink, linearWorkspace: String) {
        switch link {
        case .linear:
            // Open via the universal link — the Linear app claims
            // linear.app URLs and navigates straight to the issue. (The
            // bare `linear://issue/<key>` scheme launches the app but does
            // not route, so it's useless here.)
            openWebPreferringApp(link.webURL(linearWorkspace: linearWorkspace))
        case .githubPR(_, _, let raw):
            // The GitHub app claims github.com universal links.
            openWebPreferringApp(raw)
        case .slackThread(let url):
            // The Slack app claims *.slack.com archive universal links.
            openWebPreferringApp(url)
        }
    }

    /// Try the URL as a universal link first (routes into the native app when
    /// installed); fall back to a regular open (Safari).
    static func openWebPreferringApp(_ url: URL) {
        UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { success in
            if !success {
                UIApplication.shared.open(url)
            }
        }
    }
}
