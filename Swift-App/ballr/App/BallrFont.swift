//
//  BallrFont.swift
//  ballr
//
//  Central app typography.
//

import CoreText
import SwiftUI
import UIKit

enum BallrFont {
    private static var didRegisterFonts = false

    private static let fontResources = [
        "Nunito-Light",
        "Nunito-Regular",
        "Nunito-Medium",
        "Nunito-SemiBold",
        "Nunito-Bold",
        "Nunito-Black"
    ]

    static func registerFontsIfNeeded() {
        guard !didRegisterFonts else { return }
        didRegisterFonts = true

        for resource in fontResources {
            guard let url = fontURL(for: resource) else {
                continue
            }

            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func uiFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        registerFontsIfNeeded()

        if let font = UIFont(name: postScriptName(for: weight), size: size) {
            return font
        }

        return UIFont.systemFont(ofSize: size, weight: weight)
    }

    private static func fontURL(for resource: String) -> URL? {
        Bundle.main.url(forResource: resource, withExtension: "ttf")
            ?? Bundle.main.url(forResource: resource, withExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.main.url(forResource: resource, withExtension: "ttf", subdirectory: "Resources/Fonts")
    }

    private static func postScriptName(for weight: UIFont.Weight) -> String {
        if weight >= .black {
            return "Nunito-Black"
        }

        if weight >= .bold {
            return "Nunito-Bold"
        }

        if weight >= .semibold {
            return "Nunito-SemiBold"
        }

        if weight >= .medium {
            return "Nunito-Medium"
        }

        if weight <= .light {
            return "Nunito-Light"
        }

        return "Nunito-Regular"
    }
}

extension Font {
    static func ballr(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        BallrFont.registerFontsIfNeeded()
        return .custom(postScriptName(for: weight), size: size)
    }

    private static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .black, .heavy:
            return "Nunito-Black"
        case .bold:
            return "Nunito-Bold"
        case .semibold:
            return "Nunito-SemiBold"
        case .medium:
            return "Nunito-Medium"
        case .light, .ultraLight, .thin:
            return "Nunito-Light"
        default:
            return "Nunito-Regular"
        }
    }
}
