import SwiftUI

/// One squeeshy, however it was made. A captured cut-out when there is one, the drawn
/// character when there isn't, so the demo shelf and real captures sit side by side
/// without the layout knowing the difference.
struct SquishyImage: View {
    var squishy: Squishy
    var showsFace: Bool = true

    var body: some View {
        if let image = CutoutCache.shared.image(squishy.photoFilename) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            SquishyArt(species: squishy.species, color: squishy.color, showsFace: showsFace)
        }
    }
}

/// Same choice, but drawing into an existing Canvas so the bubble field can render a
/// whole shelf in one pass.
extension GraphicsContext {
    mutating func drawSquishy(_ squishy: Squishy, in rect: CGRect,
                              showsFace: Bool, opacity: Double) {
        if let image = CutoutCache.shared.image(squishy.photoFilename) {
            var ctx = self
            ctx.opacity = opacity
            let resolved = ctx.resolve(Image(uiImage: image))
            let size = resolved.size
            // Fit rather than fill, so a tall squeeshy is not cropped into a square.
            let scale = min(rect.width / size.width, rect.height / size.height)
            let fitted = CGSize(width: size.width * scale, height: size.height * scale)
            ctx.draw(resolved, in: CGRect(x: rect.midX - fitted.width / 2,
                                          y: rect.midY - fitted.height / 2,
                                          width: fitted.width, height: fitted.height))
        } else {
            SquishyArt.draw(&self, in: rect, species: squishy.species,
                            color: squishy.color, showsFace: showsFace, opacity: opacity)
        }
    }
}
