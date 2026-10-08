# PNG alpha reproduction

An iOS playground comparing a rendered `UIImage` with PNGs exported through
`UIImage.pngData()` and ImageIO. All images are drawn in code; no dependencies
or external assets are required.

## Run

1. Open `PNGAlphaRepro.playground` in Xcode.
2. Select an iOS simulator, run the playground, and show its Live View.
3. Compare the three columns. Scroll to see the standard-range control; toggle
   the background to inspect transparency.

## Results

Reproduced on the iOS 26.5 simulator (23F77), including Xcode's Live View.
The extended-range UIKit PNG appears darker than the original and ImageIO PNG.
The standard-range control matches across all three columns.

The top strip is 96% white at 50% opacity. Values read directly from the PNG's
first pixel are:

| Export | White | Alpha |
| --- | --- | --- |
| UIKit, 16-bit | 0.48 (incorrect) | 0.50 |
| ImageIO, 16-bit | 0.96 | 0.50 |
| Both, 8-bit control | ≈0.95 | ≈0.50 |

UIKit's affected export retains color values multiplied by alpha. PNG requires
unpremultiplied colors, so displaying the image applies opacity again.
Other OS versions and physical devices have not been verified.

## Export PNGs

Set `exportPNGs = true` in `Contents.swift` and rerun. The four PNGs are saved to
`PNGAlphaRepro` under
[`playgroundSharedDataDirectory`](https://developer.apple.com/documentation/playgroundsupport/playgroundshareddatadirectory);
the console prints the path. Subsequent exports overwrite those files.
No files are written by default.
