import Foundation

struct Vec2 {
    var x: Double
    var y: Double
}

enum Geometry {

    /// Principal-axis analysis of a 2D point cloud (a fruit silhouette).
    /// Returns the centroid, unit major/minor axes, and the extent along each
    /// axis (max projection minus min projection). Orientation-invariant, so it
    /// works regardless of how the phone was held.
    static func principalAxes(points: [Vec2]) -> (centroid: Vec2, majorLen: Double, minorLen: Double)? {
        guard points.count >= 3 else { return nil }
        var mx = 0.0, my = 0.0
        for p in points { mx += p.x; my += p.y }
        let n = Double(points.count)
        let cx = mx / n, cy = my / n

        var a = 0.0, b = 0.0, c = 0.0
        for p in points {
            let dx = p.x - cx, dy = p.y - cy
            a += dx * dx; b += dx * dy; c += dy * dy
        }
        a /= n; b /= n; c /= n

        // Eigenvector of the larger eigenvalue of [[a,b],[b,c]].
        let tr = a + c
        let det = a * c - b * b
        let disc = max(0, tr * tr / 4 - det)
        let s = disc.squareRoot()
        let l1 = tr / 2 + s

        var ex: Double, ey: Double
        if abs(b) > 1e-12 {
            ex = l1 - c; ey = b
        } else {
            if a >= c { ex = 1; ey = 0 } else { ex = 0; ey = 1 }
        }
        let elen = (ex * ex + ey * ey).squareRoot()
        let majx = ex / elen, majy = ey / elen
        let minx = -majy, miny = majx

        var minA = Double.greatestFiniteMagnitude, maxA = -Double.greatestFiniteMagnitude
        var minB = Double.greatestFiniteMagnitude, maxB = -Double.greatestFiniteMagnitude
        for p in points {
            let dx = p.x - cx, dy = p.y - cy
            let pa = dx * majx + dy * majy
            let pb = dx * minx + dy * miny
            minA = min(minA, pa); maxA = max(maxA, pa)
            minB = min(minB, pb); maxB = max(maxB, pb)
        }
        return (Vec2(x: cx, y: cy), maxA - minA, maxB - minB)
    }

    /// Like `principalAxes`, but also returns the unit major/minor axis vectors —
    /// needed to re-express the silhouette in its own (polar) coordinate frame.
    static func principalFrame(points: [Vec2]) -> (centroid: Vec2, major: Vec2, minor: Vec2,
                                                   majorLen: Double, minorLen: Double)? {
        guard points.count >= 3 else { return nil }
        var mx = 0.0, my = 0.0
        for p in points { mx += p.x; my += p.y }
        let n = Double(points.count)
        let cx = mx / n, cy = my / n

        var a = 0.0, b = 0.0, c = 0.0
        for p in points {
            let dx = p.x - cx, dy = p.y - cy
            a += dx * dx; b += dx * dy; c += dy * dy
        }
        a /= n; b /= n; c /= n

        let tr = a + c
        let det = a * c - b * b
        let disc = max(0, tr * tr / 4 - det)
        let s = disc.squareRoot()
        let l1 = tr / 2 + s

        var ex: Double, ey: Double
        if abs(b) > 1e-12 { ex = l1 - c; ey = b }
        else { if a >= c { ex = 1; ey = 0 } else { ex = 0; ey = 1 } }
        let elen = (ex * ex + ey * ey).squareRoot()
        let major = Vec2(x: ex / elen, y: ey / elen)
        let minor = Vec2(x: -major.y, y: major.x)

        var minA = Double.greatestFiniteMagnitude, maxA = -Double.greatestFiniteMagnitude
        var minB = Double.greatestFiniteMagnitude, maxB = -Double.greatestFiniteMagnitude
        for p in points {
            let dx = p.x - cx, dy = p.y - cy
            let pa = dx * major.x + dy * major.y
            let pb = dx * minor.x + dy * minor.y
            minA = min(minA, pa); maxA = max(maxA, pa)
            minB = min(minB, pb); maxB = max(maxB, pb)
        }
        return (Vec2(x: cx, y: cy), major, minor, maxA - minA, maxB - minB)
    }

    /// Area of the convex hull of the points (same units as the points).
    static func convexHullArea(points: [Vec2]) -> Double {
        let hull = convexHull(points)
        guard hull.count >= 3 else { return 0 }
        var area = 0.0
        for i in 0..<hull.count {
            let p = hull[i]
            let q = hull[(i + 1) % hull.count]
            area += p.x * q.y - q.x * p.y
        }
        return abs(area) / 2
    }

    /// Andrew's monotone-chain convex hull.
    static func convexHull(_ pts: [Vec2]) -> [Vec2] {
        guard pts.count >= 3 else { return pts }
        let points = pts.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        func cross(_ o: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [Vec2] = []
        for p in points {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }
        var upper: [Vec2] = []
        for p in points.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }
        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }
}
