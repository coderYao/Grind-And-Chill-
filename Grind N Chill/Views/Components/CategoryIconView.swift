import SwiftUI
import UIKit

struct CategoryIconView: View {
    let iconName: String
    let color: Color
    var font: Font = .body

    var body: some View {
        if Self.isSFSymbol(iconName) {
            Image(systemName: iconName)
                .font(font)
                .foregroundStyle(color)
        } else {
            Text(iconName)
                .font(font)
        }
    }

    private static func isSFSymbol(_ iconName: String) -> Bool {
        UIImage(systemName: iconName) != nil
    }
}
