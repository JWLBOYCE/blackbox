import SceneKit
import SwiftUI
import OpenPilotLogbookCore

struct WorldSceneView: NSViewRepresentable {
    var routes: [MapRoute]
    var routeLimit: Int = 700
    var allowsCameraControl: Bool = true
    var cameraDistance: Float = 7

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = allowsCameraControl
        view.autoenablesDefaultLighting = true
        view.backgroundColor = NSColor(red: 0.025, green: 0.040, blue: 0.055, alpha: 1)
        view.scene = buildScene()
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        nsView.allowsCameraControl = allowsCameraControl
        nsView.scene = buildScene()
    }

    private func buildScene() -> SCNScene {
        let scene = SCNScene()
        let globe = SCNSphere(radius: 2.0)
        globe.segmentCount = 192
        let material = SCNMaterial()
        material.diffuse.contents = Self.earthTexture
        material.emission.contents = NSColor(red: 0.004, green: 0.012, blue: 0.020, alpha: 1)
        material.specular.contents = NSColor.white.withAlphaComponent(0.10)
        material.shininess = 0.10
        globe.materials = [material]
        scene.rootNode.addChildNode(SCNNode(geometry: globe))

        let atmosphere = SCNSphere(radius: 2.04)
        atmosphere.segmentCount = 96
        let atmosphereMaterial = SCNMaterial()
        atmosphereMaterial.diffuse.contents = NSColor.systemCyan.withAlphaComponent(0.10)
        atmosphereMaterial.emission.contents = NSColor.systemBlue.withAlphaComponent(0.12)
        atmosphereMaterial.isDoubleSided = true
        atmosphereMaterial.blendMode = .add
        atmosphere.materials = [atmosphereMaterial]
        scene.rootNode.addChildNode(SCNNode(geometry: atmosphere))

        addGrid(to: scene)
        for route in routes.prefix(routeLimit) {
            addArc(route, to: scene)
        }

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 240
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 820
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.55, 0.45, 0)
        scene.rootNode.addChildNode(sunNode)

        let camera = SCNCamera()
        camera.zFar = 100
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, cameraDistance)
        scene.rootNode.addChildNode(cameraNode)
        return scene
    }

    private func addGrid(to scene: SCNScene) {
        for latitude in stride(from: -60.0, through: 60.0, by: 30.0) {
            addPolyline((0...120).map { lon in point(lat: latitude, lon: Double(lon) * 3 - 180, radius: 2.025) }, color: NSColor.white.withAlphaComponent(0.10), to: scene)
        }
        for longitude in stride(from: -180.0, through: 150.0, by: 30.0) {
            addPolyline((0...60).map { lat in point(lat: Double(lat) * 3 - 90, lon: longitude, radius: 2.025) }, color: NSColor.white.withAlphaComponent(0.10), to: scene)
        }
    }

    private func addArc(_ route: MapRoute, to scene: SCNScene) {
        let start = point(lat: route.departureLatitude, lon: route.departureLongitude, radius: 2.06)
        let end = point(lat: route.arrivalLatitude, lon: route.arrivalLongitude, radius: 2.06)
        let points = (0...32).map { index -> SCNVector3 in
            let t = CGFloat(index) / 32.0
            var vector = slerp(start, end, t)
            let lift = sin(Double(t) * .pi) * 0.35
            vector = scaled(normalized(vector), by: CGFloat(2.06 + lift))
            return vector
        }
        addPolyline(points, color: NSColor.systemCyan.withAlphaComponent(0.82), to: scene)
        addMarker(at: start, color: NSColor.white.withAlphaComponent(0.86), to: scene)
        addMarker(at: end, color: NSColor.systemCyan.withAlphaComponent(0.78), to: scene)
    }

    private func addMarker(at point: SCNVector3, color: NSColor, to scene: SCNScene) {
        let marker = SCNSphere(radius: 0.018)
        marker.segmentCount = 12
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(0.72)
        marker.materials = [material]
        let node = SCNNode(geometry: marker)
        node.position = point
        scene.rootNode.addChildNode(node)
    }

    private func addPolyline(_ points: [SCNVector3], color: NSColor, to scene: SCNScene) {
        guard points.count >= 2 else { return }
        let source = SCNGeometrySource(vertices: points)
        var indices: [Int32] = []
        for index in 0..<(points.count - 1) {
            indices.append(Int32(index))
            indices.append(Int32(index + 1))
        }
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color
        geometry.materials = [material]
        scene.rootNode.addChildNode(SCNNode(geometry: geometry))
    }

    private func point(lat: Double, lon: Double, radius: Double) -> SCNVector3 {
        let latRad = lat * .pi / 180
        let lonRad = lon * .pi / 180
        let x = radius * cos(latRad) * sin(lonRad)
        let y = radius * sin(latRad)
        let z = radius * cos(latRad) * cos(lonRad)
        return SCNVector3(Float(x), Float(y), Float(z))
    }

    private func normalized(_ vector: SCNVector3) -> SCNVector3 {
        let length = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
        guard length > 0 else { return vector }
        return SCNVector3(vector.x / length, vector.y / length, vector.z / length)
    }

    private func scaled(_ vector: SCNVector3, by scale: CGFloat) -> SCNVector3 {
        SCNVector3(vector.x * scale, vector.y * scale, vector.z * scale)
    }

    private func slerp(_ a: SCNVector3, _ b: SCNVector3, _ t: CGFloat) -> SCNVector3 {
        let an = normalized(a)
        let bn = normalized(b)
        let dot = max(-1, min(1, an.x * bn.x + an.y * bn.y + an.z * bn.z))
        let omega = acos(dot)
        if abs(omega) < 0.0001 { return an }
        let sinOmega = sin(omega)
        let scaleA = sin((1 - t) * omega) / sinOmega
        let scaleB = sin(t * omega) / sinOmega
        return SCNVector3(an.x * scaleA + bn.x * scaleB, an.y * scaleA + bn.y * scaleB, an.z * scaleA + bn.z * scaleB)
    }

    private static let earthTexture: Any = {
        if let url = LogbookResources.earthBlueMarbleURL,
           let image = NSImage(contentsOf: url) {
            return image
        }
        let size = NSSize(width: 2048, height: 1024)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: size)
        NSGradient(colors: [
            NSColor(red: 0.020, green: 0.085, blue: 0.125, alpha: 1),
            NSColor(red: 0.035, green: 0.160, blue: 0.230, alpha: 1),
            NSColor(red: 0.015, green: 0.050, blue: 0.095, alpha: 1)
        ])?.draw(in: rect, angle: 0)

        NSColor(red: 0.180, green: 0.355, blue: 0.215, alpha: 1).setFill()
        drawLand([(-168, 70), (-140, 68), (-105, 58), (-86, 48), (-78, 30), (-96, 18), (-116, 25), (-132, 45), (-155, 54)], size: size)
        drawLand([(-83, 12), (-65, 5), (-50, -12), (-54, -34), (-70, -55), (-78, -28)], size: size)
        drawLand([(-10, 36), (18, 58), (52, 56), (93, 62), (142, 48), (154, 26), (120, 8), (76, 20), (42, 28), (10, 36)], size: size)
        drawLand([(-18, 34), (30, 32), (50, 8), (42, -26), (20, -35), (2, -20), (-10, 6)], size: size)
        drawLand([(65, 22), (86, 18), (96, 7), (80, 8)], size: size)
        drawLand([(110, -12), (154, -10), (154, -36), (122, -42), (112, -26)], size: size)
        drawLand([(-44, 72), (-20, 74), (-22, 62), (-48, 60)], size: size)

        NSColor(red: 0.285, green: 0.480, blue: 0.265, alpha: 0.72).setFill()
        drawLand([(-6, 50), (8, 55), (30, 46), (16, 39), (-5, 42)], size: size)
        drawLand([(96, 36), (122, 42), (137, 30), (118, 20), (100, 24)], size: size)

        NSColor.white.withAlphaComponent(0.16).setStroke()
        for latitude in stride(from: -60.0, through: 60.0, by: 30.0) {
            let y = y(forLatitude: latitude, height: size.height)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: y))
            path.line(to: NSPoint(x: size.width, y: y))
            path.lineWidth = 1
            path.stroke()
        }

        return image
    }()

    private static func drawLand(_ coordinates: [(Double, Double)], size: NSSize) {
        guard let first = coordinates.first else { return }
        let path = NSBezierPath()
        path.move(to: point(forLongitude: first.0, latitude: first.1, size: size))
        for coordinate in coordinates.dropFirst() {
            path.line(to: point(forLongitude: coordinate.0, latitude: coordinate.1, size: size))
        }
        path.close()
        path.fill()
    }

    private static func point(forLongitude longitude: Double, latitude: Double, size: NSSize) -> NSPoint {
        NSPoint(
            x: ((longitude + 180) / 360) * size.width,
            y: y(forLatitude: latitude, height: size.height)
        )
    }

    private static func y(forLatitude latitude: Double, height: CGFloat) -> CGFloat {
        ((latitude + 90) / 180) * height
    }
}
