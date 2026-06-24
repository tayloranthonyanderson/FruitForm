import CoreGraphics

/// Non-destructive volume estimate for one fruit, from its 2D silhouette mask plus
/// the LiDAR depth shell.
struct VolumeEstimate {
    var volumeCm3: Double
    var semiAxisACm: Double   // equivalent in-plane semi-axis
    var semiAxisBCm: Double   // equivalent in-plane semi-axis
    var semiAxisCCm: Double   // toward camera
    var geometricMeanDiameterCm: Double
    var medianDepthM: Double
    var fruitPixelCount: Int

    /// weight (g) for a given flesh density (g/cm³); ripe tomato ≈ 0.98.
    func weightGrams(density: Double = 0.98) -> Double { volumeCm3 * density }
}

enum FruitGeometry3D {

    static func estimate(instance: TomatoInstance, frame: CapturedFrame) -> VolumeEstimate? {
        guard let depth = frame.depth else { return nil }
        let dw = depth.width, dh = depth.height
        guard dw > 0, dh > 0 else { return nil }

        var depths: [Float] = []
        var validPixelCount = 0
        var totalPhysicalAreaM2: Double = 0

        for my in 0..<160 {
            for mx in 0..<160 {
                if !instance.mask[my][mx] { continue }
                
                let normX = Double(mx) / 160.0
                let normY = Double(my) / 160.0
                
                let dx = min(dw - 1, max(0, Int(normX * Double(dw))))
                let dy = min(dh - 1, max(0, Int(normY * Double(dh))))
                
                let z = depth.values[dy * dw + dx]
                if z.isFinite && z > 0 {
                    depths.append(z)
                    validPixelCount += 1
                }
            }
        }
        
        guard depths.count >= 8 else { return nil }
        depths.sort()

        let zNear = Double(depths[max(0, depths.count * 3 / 100)])
        let zMed = Double(depths[depths.count / 2])
        
        // The mask is image-space 160×160, so each cell spans width/160 × height/160 px.
        let cellWidthPx = frame.imageWidth / 160.0
        let cellHeightPx = frame.imageHeight / 160.0
        let maskPixelWidthM = cellWidthPx * zMed / frame.fx
        let maskPixelHeightM = cellHeightPx * zMed / frame.fy
        let maskPixelAreaM2 = maskPixelWidthM * maskPixelHeightM
        
        totalPhysicalAreaM2 = Double(validPixelCount) * maskPixelAreaM2

        // Assuming an elliptical silhouette, Area = pi * a * b. 
        // We can approximate equivalent a and b by looking at the bounding box ratio.
        let rectRatio = Double(instance.rect.width / instance.rect.height)
        let aM = sqrt(totalPhysicalAreaM2 * rectRatio / Double.pi)
        let bM = totalPhysicalAreaM2 / (Double.pi * aM)

        guard aM > 0, bM > 0 else { return nil }

        // Toward-camera semi-axis (c): depth spread / 2
        let maxThickness = min(aM, bM) * 2.0
        let fruitDepths = depths.filter { Double($0) <= zNear + maxThickness }
        let zFar = fruitDepths.last.map(Double.init) ?? Double(depths.last!)
        
        // This is the full thickness (diameter)
        var thicknessM = zFar - zNear
        thicknessM = max(min(aM, bM) * 0.5, min(thicknessM, min(aM, bM) * 1.5))
        
        // Semi-axis is half the thickness
        let cM = thicknessM / 2.0

        let aCm = aM * 100, bCm = bM * 100, cCm = cM * 100
        
        // Exact volume based directly on the physical mask area
        // Volume = 4/3 * Area * c
        let volume = (4.0 / 3.0) * (totalPhysicalAreaM2 * 100 * 100) * cCm
        
        let gmd = 2.0 * pow(aCm * bCm * cCm, 1.0 / 3.0)

        return VolumeEstimate(volumeCm3: volume,
                              semiAxisACm: aCm, semiAxisBCm: bCm, semiAxisCCm: cCm,
                              geometricMeanDiameterCm: gmd,
                              medianDepthM: zMed,
                              fruitPixelCount: validPixelCount)
    }
}
