// The pairing QR code on Android (patch 0031 calls it from PairingView's PairingQRCode): the
// modules of QRCodeMatrix as black squares, where iOS scales up Core Image's bitmap. Each row's
// dark runs are one rectangle, and all of them one path, so adjacent modules meet without seams.

import SwiftUI

struct AndroidQRCodeView: View {
    let matrix: QRCodeMatrix

    var body: some View {
        Canvas { context, size in
            let module = min(size.width, size.height) / CGFloat(matrix.size)
            var path = Path()
            for y in 0 ..< matrix.size {
                var x = 0
                while x < matrix.size {
                    guard matrix[x, y] else {
                        x += 1
                        continue
                    }
                    let start = x
                    while x < matrix.size, matrix[x, y] {
                        x += 1
                    }
                    path.addRect(CGRect(
                        x: CGFloat(start) * module, y: CGFloat(y) * module,
                        width: CGFloat(x - start) * module, height: module,
                    ))
                }
            }
            context.fill(path, with: .color(.black))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
