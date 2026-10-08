import UIKit
import SwiftUI
import ImageIO
import PlaygroundSupport
import zlib

// Set to true to export PNGs to disk.
let exportPNGs = false

// No packages, external assets, or private APIs. Every visual is synthetic.
// Run as an iOS playground: UIKit's extended-range PNG export is the subject.
func makeImage(range: UIGraphicsImageRendererFormat.Range) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    format.preferredRange = range
    return UIGraphicsImageRenderer(size: CGSize(width: 180, height: 180), format: format).image { context in
        // The top-left pixel supplies the known color/alpha sample inspected below.
        UIColor(white: 0.96, alpha: 0.5).setFill()
        context.fill(CGRect(x: 0, y: 0, width: 180, height: 30))
        // Orange swatches at 25%, 50%, and 75% opacity show the effect of alpha.
        for index in 0..<3 {
            UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 0.25 * CGFloat(index + 1)).setFill()
            context.fill(CGRect(x: 10 + index * 58, y: 40, width: 44, height: 55))
        }
        // A translucent triangle also exposes darkening along antialiased edges.
        UIColor(red: 0.6, green: 0.3, blue: 0.9, alpha: 0.5).setFill()
        let triangle = UIBezierPath()
        triangle.move(to: CGPoint(x: 90, y: 105))
        triangle.addLine(to: CGPoint(x: 150, y: 170))
        triangle.addLine(to: CGPoint(x: 30, y: 170))
        triangle.close()
        triangle.fill()
    }
}

enum ReproError: Error {
    case exportFailed, unexpectedPNG, decompressionFailed
}

func imageIOPNG(_ image: UIImage) throws -> Data {
    let data = NSMutableData()
    guard let cgImage = image.cgImage,
          let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
    else { throw ReproError.exportFailed }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else { throw ReproError.exportFailed }
    return data as Data
}

// Read stored samples, independently of any image decoder's alpha handling.
// This deliberately supports only the non-interlaced RGBA 8/16-bit PNGs here.
func firstPixel(_ data: Data) throws -> (depth: Int, white: Double, alpha: Double) {
    let bytes = Array(data)
    func uint32(_ offset: Int) -> Int {
        bytes[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
    }
    guard bytes.count >= 33,
          Array(bytes.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10],
          String(bytes: bytes[12..<16], encoding: .ascii) == "IHDR",
          [8, 16].contains(bytes[24]), bytes[25] == 6,
          bytes[26] == 0, bytes[27] == 0, bytes[28] == 0
    else { throw ReproError.unexpectedPNG }
    let width = uint32(16), height = uint32(20), depth = Int(bytes[24])
    guard width == 180, height == 180 else { throw ReproError.unexpectedPNG }
    var compressed: [UInt8] = []
    var offset = 8
    while offset + 12 <= bytes.count {
        let count = uint32(offset)
        guard count <= bytes.count - offset - 12 else { throw ReproError.unexpectedPNG }
        if String(bytes: bytes[offset + 4..<offset + 8], encoding: .ascii) == "IDAT" {
            compressed.append(contentsOf: bytes[offset + 8..<offset + 8 + count])
        }
        offset += count + 12
    }
    var raw = [UInt8](repeating: 0, count: (1 + width * 4 * (depth / 8)) * height)
    var length = uLongf(raw.count)
    let status = uncompress(&raw, &length, compressed, uLong(compressed.count))
    guard status == Z_OK, length == raw.count, raw[0] <= 4
    else { throw ReproError.decompressionFailed }
    // Every PNG filter leaves this first pixel unchanged: its neighbors are zero.
    let maximum = depth == 16 ? 65535.0 : 255.0
    let white = depth == 16 ? Int(raw[1]) * 256 + Int(raw[2]) : Int(raw[1])
    let alpha = depth == 16 ? Int(raw[7]) * 256 + Int(raw[8]) : Int(raw[4])
    return (depth, Double(white) / maximum, Double(alpha) / maximum)
}

struct Comparison {
    let title: String
    let source: UIImage
    let sourceBitDepth: Int
    let uikit: UIImage
    let imageIO: UIImage
    let uikitDetails: String
    let imageIODetails: String

    init(range: UIGraphicsImageRendererFormat.Range) throws {
        title = range == .extended ? "Extended range — repro" : "Standard range — control"
        source = makeImage(range: range)
        guard let cgImage = source.cgImage, let uikitData = source.pngData()
        else { throw ReproError.exportFailed }
        sourceBitDepth = cgImage.bitsPerComponent
        let imageIOData = try imageIOPNG(source)
        guard let decodedUIKit = UIImage(data: uikitData),
              let decodedImageIO = UIImage(data: imageIOData)
        else { throw ReproError.exportFailed }
        uikit = decodedUIKit
        imageIO = decodedImageIO
        func describe(_ data: Data) throws -> String {
            let pixel = try firstPixel(data)
            return String(format: "%d-bit PNG\nWhite %.2f\nAlpha %.2f", pixel.depth, pixel.white, pixel.alpha)
        }
        uikitDetails = try describe(uikitData)
        imageIODetails = try describe(imageIOData)
        print("\(title) (\(sourceBitDepth)-bit source)\nUIKit: \(uikitDetails)\nImageIO: \(imageIODetails)")
        if exportPNGs {
            let directory = playgroundSharedDataDirectory.appendingPathComponent("PNGAlphaRepro", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let prefix = range == .extended ? "extended" : "standard"
            try uikitData.write(to: directory.appendingPathComponent("\(prefix)-uikit.png"), options: .atomic)
            try imageIOData.write(to: directory.appendingPathComponent("\(prefix)-imageio.png"), options: .atomic)
            print("Exported PNGs: \(directory.path)")
        }
    }
}

struct ReproView: View {
    let comparisons: [Comparison]
    @State private var darkBackground = false

    func column(_ title: String, image: UIImage, details: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Image(uiImage: image)
                .resizable().scaledToFit()
                .background(darkBackground ? Color(white: 0.12) : .white)
            Text(details).font(.system(.caption, design: .monospaced))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("PNG alpha reproduction").font(.title)
                Text("iOS \(UIDevice.current.systemVersion)\nSame source image, two exporters. Top strip: 96% white at 50% opacity.")
                Toggle("Dark sample background", isOn: $darkBackground)
                ForEach(comparisons.indices, id: \.self) { index in
                    let sample = comparisons[index]
                    VStack(alignment: .leading, spacing: 12) {
                        Text(sample.title).font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .top)], alignment: .leading, spacing: 16) {
                            column("Original", image: sample.source, details: "Before export\n\(sample.sourceBitDepth)-bit source\nWhite 0.96\nAlpha 0.50")
                            column("UIKit PNG", image: sample.uikit, details: sample.uikitDetails)
                            column("ImageIO PNG", image: sample.imageIO, details: sample.imageIODetails)
                        }
                    }
                }
                Text("On an affected runtime, UIKit stores white ≈0.48 with alpha ≈0.50. Displaying the PNG applies opacity again, making it too dark. A fixed runtime should produce matching columns. The numbers come directly from PNG bytes.")
            }
            .padding(20)
        }
        .frame(width: 600, height: 900)
    }
}

// An export/format failure stops execution instead of presenting misleading results.
let comparisons = try [Comparison(range: .extended), Comparison(range: .standard)]
let liveView = UIHostingController(rootView: ReproView(comparisons: comparisons))

PlaygroundPage.current.liveView = liveView
