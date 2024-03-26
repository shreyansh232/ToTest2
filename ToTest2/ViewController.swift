//
//  ViewController.swift
//  ToTest2
//
//  Created by Mohit Kumar Gupta on 26/03/24.
//

import UIKit
import SceneKit
import ARKit
import CoreML
import Vision

class FocusNode: SCNNode {
    
    private var focusSquare: SCNNode?
    
    override init() {
        super.init()
        setupFocusSquare()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupFocusSquare()
    }
    
    private func setupFocusSquare() {
        let focusSquareGeometry = SCNPlane(width: 0.1, height: 0.1)
        focusSquareGeometry.firstMaterial?.diffuse.contents = UIColor.red.withAlphaComponent(0.8)
        focusSquare = SCNNode(geometry: focusSquareGeometry)
        focusSquare?.eulerAngles.x = -.pi / 2 // Make it horizontal
        addChildNode(focusSquare!)
    }
    
    func update(for position: SCNVector3, planeAnchor: ARPlaneAnchor?, camera: ARCamera?, sceneView: ARSCNView) {
        guard let camera = camera else { return }
        
        // Hide the focus square if no plane anchor is available
        if planeAnchor == nil {
            focusSquare?.isHidden = true
            return
        }
        
        // Calculate the position of the focus square
        let screenCenter = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
        let hitTestResults = sceneView.hitTest(screenCenter, types: .existingPlaneUsingExtent)
        
        if let hitTestResult = hitTestResults.first {
            let hitTransform = hitTestResult.worldTransform
            let hitVector = SCNVector3(hitTransform.columns.3.x, hitTransform.columns.3.y, hitTransform.columns.3.z)
            focusSquare?.position = hitVector
            focusSquare?.isHidden = false
        } else {
            focusSquare?.isHidden = true
        }
    }
}

class ViewController: UIViewController, ARSCNViewDelegate {

    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet var startButton: UIButton!
    
    var focusSquare: FocusNode?
    var lastBallSpawnPosition: SCNVector3?
    var ballSpawnTimer: Timer?
    var yoloModel: YOLOv3TinyInt8LUT?
    var request: VNCoreMLRequest?
    var detectedObjects: [String] = []
    var boundingBoxNode: SCNNode?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Set the view's delegate
        sceneView.delegate = self

        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true

        // Create a new scene
        let scene = SCNScene()

        // Set the scene to the view
        sceneView.scene = scene

        // Enable plane detection
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        sceneView.session.run(configuration)
        
        // Add focus square
        focusSquare = FocusNode()
        if let focusSquare = focusSquare {
            scene.rootNode.addChildNode(focusSquare)
        }

        // Load YOLOv3 Core ML model
        guard let model = try? YOLOv3TinyInt8LUT(configuration: MLModelConfiguration()) else {
            fatalError("Unable to load YOLOv3 model")
        }
        yoloModel = model

        // Create a Vision request
        guard let visionModel = try? VNCoreMLModel(for: model.model) else {
            fatalError("Failed to create VNCoreMLModel")
        }
        request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
            self?.processDetection(for: request, error: error)
        }
        request?.imageCropAndScaleOption = .scaleFit
    }

    func processDetection(for request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNRecognizedObjectObservation] else {
            return
        }

        // Clear previous detections
        detectedObjects.removeAll()

        for result in results {
            // Access the detected objects directly from the observation
            let objectLabel = result.labels.first?.identifier ?? "Unknown"
            let confidence = result.confidence
            detectedObjects.append("\(objectLabel) - \(String(format: "%.2f", confidence * 100))%")
            
            // Draw bounding box around the detected object
            drawBoundingBox(for: result)
        }
    }
    
    func drawBoundingBox(for observation: VNRecognizedObjectObservation) {
        // Perform this task asynchronously on the main queue to avoid delays
        DispatchQueue.main.async {
            guard let currentFrame = self.sceneView.session.currentFrame else {
                return
            }
            
            let boundingBox = observation.boundingBox
            let width = boundingBox.maxX - boundingBox.minX
            let height = boundingBox.maxY - boundingBox.minY
            let depth: CGFloat = 0.01 // Set the depth of the bounding box
            
            // Convert the normalized bounding box coordinates to scene coordinates
            let minX = boundingBox.minX * CGFloat(self.sceneView.frame.width)
            let minY = boundingBox.minY * CGFloat(self.sceneView.frame.height)
            let maxX = boundingBox.maxX * CGFloat(self.sceneView.frame.width)
            let maxY = boundingBox.maxY * CGFloat(self.sceneView.frame.height)
            
            // Calculate the center of the bounding box in 2D screen space
            let centerX = (minX + maxX) / 2
            let centerY = (minY + maxY) / 2
            
            // Convert the 2D center point to 3D world coordinates
            let worldPoint = self.sceneView.unprojectPoint(SCNVector3(Float(centerX), Float(centerY), 0.999))
            
            // Check if the worldPoint is valid
            guard worldPoint.x != 0 || worldPoint.y != 0 || worldPoint.z != 0 else {
                // Hide the previous bounding box if the world point is invalid
                self.boundingBoxNode?.isHidden = true
                return
            }
            
            // Create or update bounding box node
            if let boundingBoxNode = self.boundingBoxNode {
                boundingBoxNode.position = worldPoint
            } else {
                let boundingBoxNode = SCNNode(geometry: SCNGeometry.createWireframe(width: Float(width), height: Float(height), depth: depth))
                boundingBoxNode.position = worldPoint
                let material = SCNMaterial()
                material.diffuse.contents = UIColor.red // Change color here
                boundingBoxNode.geometry?.firstMaterial = material

                // Add bounding box node to the scene
                self.sceneView.scene.rootNode.addChildNode(boundingBoxNode)
                self.boundingBoxNode = boundingBoxNode
            }
            
            // Remove previous text node
            self.boundingBoxNode?.childNodes.filter { $0.geometry is SCNText }.forEach { $0.removeFromParentNode() }
            
            // Display label
            let objectLabel = observation.labels.first?.identifier ?? "Unknown"
            let textNode = self.createTextNode(text: objectLabel, fontSize: 0.01, color: UIColor.yellow)
            
            // Adjust Y position to make the label appear above the wireframe bounding box
            textNode.position = SCNVector3(worldPoint.x, worldPoint.y + Float(height) / 2 + 0.05, worldPoint.z)
            
            self.boundingBoxNode?.addChildNode(textNode)
        }
    }

    func createTextNode(text: String, fontSize: CGFloat, color: UIColor) -> SCNNode {
        let textGeometry = SCNText(string: text, extrusionDepth: 0.01)
        textGeometry.firstMaterial?.diffuse.contents = color
        let textNode = SCNNode(geometry: textGeometry)
        textNode.scale = SCNVector3(fontSize, fontSize, fontSize)
        return textNode
    }
    
    // ARSCNViewDelegate method
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let currentFrame = sceneView.session.currentFrame else {
            return
        }
        
        // Convert ARFrame to CIImage
        let pixelBuffer = currentFrame.capturedImage
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Perform object detection
        let handler = VNImageRequestHandler(ciImage: image)
        try? handler.perform([request!])
        
        // Handle ball spawning
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        focusSquare?.update(for: node.position, planeAnchor: planeAnchor, camera: sceneView.session.currentFrame?.camera, sceneView: sceneView)
    }
    
    func startBallSpawning() {
        let spawnInterval: TimeInterval = 1.0 // Adjust as needed
        ballSpawnTimer = Timer.scheduledTimer(withTimeInterval: spawnInterval, repeats: true) { [weak self] timer in
            self?.spawnBall()
        }
    }
    
    func spawnBall() {
        guard let sceneView = self.sceneView else { return }
        
        let ballNode = SCNNode(geometry: SCNSphere(radius: 0.05)) // Adjust radius as needed
        ballNode.geometry?.firstMaterial?.diffuse.contents = UIColor.blue
        ballNode.position = self.calculateBallSpawnPosition()
        sceneView.scene.rootNode.addChildNode(ballNode)
    }
    
    func calculateBallSpawnPosition() -> SCNVector3 {
        // Use last known ball spawn position or default to origin if not available
        let position = lastBallSpawnPosition ?? SCNVector3(0, 0, -1)
        
        // Adjust position based on user movement (e.g., forward)
        let forwardOffset: Float = 0.2 // Adjust as needed
        let currentPosition = sceneView.pointOfView?.position ?? SCNVector3Zero
        let forwardVector = sceneView.pointOfView?.worldFront ?? SCNVector3(0, 0, -1)
        let newPosition = SCNVector3(currentPosition.x + forwardVector.x * forwardOffset,
                                      currentPosition.y + forwardVector.y * forwardOffset,
                                      currentPosition.z + forwardVector.z * forwardOffset)
        
        // Update last ball spawn position
        lastBallSpawnPosition = newPosition
        
        return newPosition
    }
    @IBAction func StartButton(_ sender: UIButton) {
        startBallSpawning()
    }
    
    
    @IBAction func StopButton(_ sender: UIButton) {
        stopBallSpawning()
    }
    
    // MARK: - Ball Spawning Control
    
    func stopBallSpawning() {
        ballSpawnTimer?.invalidate()
        ballSpawnTimer = nil
    }
}

extension SCNGeometry {
    static func line(from start: SCNVector3, to end: SCNVector3) -> SCNGeometry {
        let indices: [Int32] = [0, 1]
        let source = SCNGeometrySource(vertices: [start, end])
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        return SCNGeometry(sources: [source], elements: [element])
    }
    
    static func createWireframe(width: Float, height: Float, depth: CGFloat) -> SCNGeometry {
        let vertices: [SCNVector3] = [
            SCNVector3(-width / 2, -height / 2, 0),
            SCNVector3(width / 2, -height / 2, 0),
            SCNVector3(width / 2, height / 2, 0),
            SCNVector3(-width / 2, height / 2, 0),
            SCNVector3(-width / 2, -height / 2, Float(depth)),
            SCNVector3(width / 2, -height / 2, Float(depth)),
            SCNVector3(width / 2, height / 2, Float(depth)),
            SCNVector3(-width / 2, height / 2, Float(depth)),
        ]
        
        let verticesSource = SCNGeometrySource(vertices: vertices)
        
        let indices: [UInt8] = [
            0, 1, 1, 2, 2, 3, 3, 0,
            4, 5, 5, 6, 6, 7, 7, 4,
            0, 4, 1, 5, 2, 6, 3, 7,
        ]
        
        let indicesData = Data(bytes: indices, count: indices.count)
        let element = SCNGeometryElement(data: indicesData, primitiveType: .line, primitiveCount: 8,bytesPerIndex: 1)
        
        return SCNGeometry(sources: [verticesSource], elements: [element])
    }
}
