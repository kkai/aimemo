//
//  GADBannerViewController.swift
//  aiMemo
//
//  Created by kai on 2024/05/25.
//

#if os(iOS)
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif
#endif
import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(iOS) && canImport(GoogleMobileAds) && !PRO_VERSION
struct GADBannerViewController: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let view = BannerView(adSize: AdSizeBanner)
        let viewController = UIViewController()
        view.adUnitID = "ca-app-pub-5970391288492190/1559616680"
        // demo view.adUnitID = "ca-app-pub-3940256099942544/2435281174"
        view.rootViewController = viewController
        viewController.view.addSubview(view)
        viewController.view.frame = CGRect(origin: .zero, size: AdSizeBanner.size)
        view.load(Request())
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
#else
// Fallback for non-iOS platforms
struct GADBannerViewController: View {
    var body: some View {
        EmptyView()
    }
}
#endif
