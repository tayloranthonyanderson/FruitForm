import CoreGraphics

/// The crop rectangle (pixel space) for one fruit, shared by every site that feeds
/// a crop to the classifiers. Centralised on purpose: `pad` is a fraction of the
/// **box**, matching `ml/extract_crops.py`. An earlier bug padded by a fraction of
/// the **image** (~115 px on a 1920px frame), burying each fruit in background so
/// the classifier mis-read everything as flat/fasciated. Keep this the single
/// source of truth so train/serve crop framing can't drift again. See
/// `CropGeometryTests` for the regression guard.
enum CropGeometry {
    static func paddedRect(normRect: CGRect,
                           imageWidth: CGFloat,
                           imageHeight: CGFloat,
                           pad: CGFloat = 0.06) -> CGRect {
        let padX = normRect.width * pad
        let padY = normRect.height * pad
        return CGRect(
            x: (normRect.minX - padX) * imageWidth,
            y: (normRect.minY - padY) * imageHeight,
            width: (normRect.width + 2 * padX) * imageWidth,
            height: (normRect.height + 2 * padY) * imageHeight
        ).intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
    }
}
