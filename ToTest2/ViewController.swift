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
import AVFoundation
import Speech
import MapKit
import CoreLocation

class FocusNode: SCNNode {
    
    
    private var focusSquare: SCNNode?
    private var previousPosition: SCNVector3?
    
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
            
            // Draw line if previous position exists
            if let previousPosition = previousPosition {
                drawLine(from: previousPosition, to: hitVector, in: sceneView.scene)
            }
            
            // Update previous position
            previousPosition = hitVector
        } else {
            focusSquare?.isHidden = true
            previousPosition = nil
        }
    }
    
    private func drawLine(from start: SCNVector3, to end: SCNVector3, in scene: SCNScene) {
        let lineGeometry = SCNGeometry.line(from: start, to: end)
        let lineMaterial = SCNMaterial()
        lineMaterial.diffuse.contents = UIColor.orange // Change color here
            lineGeometry.materials = [lineMaterial]
        let lineNode = SCNNode(geometry: lineGeometry)
        scene.rootNode.addChildNode(lineNode)
    }
}
class ViewController: UIViewController, ARSCNViewDelegate, AVSpeechSynthesizerDelegate {

    
    
    @IBOutlet var mapView: MKMapView!
    
    
    @IBOutlet var StartStopButton: UIButton!
    
    
    @IBOutlet var TextView: UITextView!
    
    
    @IBOutlet var sceneView: ARSCNView!
    
    @IBOutlet var startButton: UIButton!
    
    
    @IBOutlet var stopButton: UIButton!
    
    var focusSquare: FocusNode?
    var lastBallSpawnPosition: SCNVector3?
    var ballSpawnTimer: Timer?
    var yoloModel: YOLOv3TinyInt8LUT?
    var request: VNCoreMLRequest?
    var detectedObjects: [String] = []
    var boundingBoxNode: SCNNode?
    var spokenObjects: Set<String> = Set()
    let speechSynthesizer = AVSpeechSynthesizer()
    
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale.init(identifier: "en-US"))
    
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private var audioEngine = AVAudioEngine()
    
    var lang: String = "en-US"
    
    let locationManager = CLLocationManager()
    
    
    
    var savedPaths: [String: Data] = [:]
    
    override func viewDidLoad() {
        
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        mapView.showsUserLocation = true
                mapView.delegate = self
        
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
        
        // Set speech synthesizer delegate
        speechSynthesizer.delegate = self
        
        
        
        StartStopButton.isEnabled = false
        
        speechRecognizer?.delegate = self as? SFSpeechRecognizerDelegate
        
        SFSpeechRecognizer.requestAuthorization{
            (authStatus) in
            
            var isButtonEnabled = false
            
            switch authStatus{
                
            case .authorized:
                isButtonEnabled = true
                
                
            case .notDetermined:
                isButtonEnabled = false
                print("not yet recognized")
                
            case .denied:
                isButtonEnabled = false
                print("User denied")
                
            case .restricted:
                isButtonEnabled = false
                print("restricted")
                
                
            }
            
            OperationQueue.main.addOperation(){
                self.StartStopButton.isEnabled = isButtonEnabled
            }
        }
    }
    
    func savePath(name: String) {
            // Save the current world map data
            sceneView.session.getCurrentWorldMap { worldMap, error in
                guard let worldMap = worldMap else {
                    print("Error saving world map: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                do {
                    let archivedData = try NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true)
                    self.savedPaths[name] = archivedData
                    // Optionally, save the archivedData wherever appropriate (e.g., UserDefaults, file system)
                } catch {
                    print("Error archiving world map data: \(error.localizedDescription)")
                }
            }
        }

    
    func restorePath(name: String) {
            guard let data = savedPaths[name] else {
                print("Path with name \(name) not found.")
                return
            }
            restoreWorldMap(data)
            // Optionally, update UI or perform additional tasks after restoring the path
            spawnBallsAlongPath()
        }
    
    
    func restoreWorldMap(_ data: Data) {
           do {
               guard let unarchivedData = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
                   print("Error unarchiving world map data")
                   return
               }
               let configuration = ARWorldTrackingConfiguration()
               configuration.initialWorldMap = unarchivedData
               sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
           } catch {
               print("Error unarchiving world map data: \(error.localizedDescription)")
           }
       }
    
    
    func spawnBallsAlongPath() {
            // Code to spawn balls along the path goes here
            // You can use the same logic as the existing ball spawning method
        
        guard let sceneView = self.sceneView else { return }
        
        let ballNode = SCNNode(geometry: SCNSphere(radius: 0.05)) // Adjust radius as needed
        ballNode.geometry?.firstMaterial?.diffuse.contents = UIColor.blue
        ballNode.position = self.calculateBallSpawnPosition()
        sceneView.scene.rootNode.addChildNode(ballNode)
        }

    func processDetection(for request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNRecognizedObjectObservation] else {
            return
        }

        for result in results {
            let objectLabel = result.labels.first?.identifier ?? "Unknown"
            let confidence = result.confidence
            detectedObjects.append("\(objectLabel) - \(String(format: "%.2f", confidence * 100))%")
            
            // Check if the object has already been spoken
            if !spokenObjects.contains(objectLabel) {
                // Speak out the object
                speak(text: objectLabel)
                // Add the object to the spoken set
                spokenObjects.insert(objectLabel)
            }
            
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
                material.diffuse.contents = UIColor.green // Change color here
                boundingBoxNode.geometry?.firstMaterial = material

                // Add bounding box node to the scene
                self.sceneView.scene.rootNode.addChildNode(boundingBoxNode)
                self.boundingBoxNode = boundingBoxNode
            }
            
            // Remove previous text node
            self.boundingBoxNode?.childNodes.filter { $0.geometry is SCNText }.forEach {
                $0.removeFromParentNode() }
                           
                           // Display label
                           let objectLabel = observation.labels.first?.identifier ?? "Unknown"
                           let textNode = self.createTextNode(text: objectLabel, fontSize: 0.01, color:UIColor.yellow)
                           
                           // Adjust Y position to make the label appear above the wireframe bounding box
                           textNode.position = SCNVector3(worldPoint.x, worldPoint.y + Float(height) / 2 + 0.05, worldPoint.z)
                           
                           // Add the label text to the bounding box node
                           self.boundingBoxNode?.addChildNode(textNode)
                       }
                   }
                   
                   func speak(text: String) {
                       let speechUtterance = AVSpeechUtterance(string: text)
                       speechUtterance.rate = AVSpeechUtteranceDefaultSpeechRate
                       speechSynthesizer.speak(speechUtterance)
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

                  
    @IBAction func StartButton(_ sender: UIButton) {
        
        startBallSpawning()
    }
    
    
    @IBAction func StopButton(_ sender: UIButton) {
        stopBallSpawning()
        
        let pathName = "MyPath" // Set a default path name or provide an interface for the user to input a name
                savePath(name: pathName)
                // Remove existing ball nodes from the scene
                removeBallNodes()
        
    }
    
    
    
    @IBAction func startStopAction(_ sender: UIButton) {
        
        speechRecognizer = SFSpeechRecognizer(locale: Locale.init(identifier: lang))
        
        if audioEngine.isRunning{
            
            audioEngine.stop()
            recognitionRequest?.endAudio()
            StartStopButton.isEnabled = false
            StartStopButton.setTitle("Start Recording", for: .normal)
        }
        else{
            
            startRecording()
            StartStopButton.setTitle("Stop Recording", for: .normal)
        }
    }
    
    func removeBallNodes() {
            sceneView.scene.rootNode.enumerateChildNodes { (node, _) in
                if node.name == "ballNode" {
                    node.removeFromParentNode()
                }
            }
        }
    func startRecording() {
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(AVAudioSession.Category.record)
            try audioSession.setMode(AVAudioSession.Mode.measurement)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("audioSession properties weren't set because of an error.")
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        let inputNode = audioEngine.inputNode
        
        guard let recognitionRequest = recognitionRequest else {
            fatalError("Unable to create an SFSpeechAudioBufferRecognitionRequest object")
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest, resultHandler: { (result, error) in
            
            var isFinal = false
            
            if ((result?.bestTranscription.formattedString.lowercased().starts(with: "navigate to")) != nil) {
                // Extract the path name from the command
                let command = result!.bestTranscription.formattedString
                let pathName = command.replacingOccurrences(of: "navigate to", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                // Restore and display the path
                self.restorePath(name: pathName)
            }
        
            
            if let result = result {
                self.TextView.text = result.bestTranscription.formattedString
                isFinal = result.isFinal
                
                // Check if the recognized text contains "start"
                if result.bestTranscription.formattedString.lowercased().contains("start") {
                    // Programmatically trigger StartButton action
                    self.StartButton(self.startButton)
                    
                    
                }
                else if result.bestTranscription.formattedString.lowercased().contains("stop") {
                    // Programmatically trigger StopButton action
                    self.StopButton(self.stopButton)
                }
                else if result.bestTranscription.formattedString.lowercased().starts(with: "navigate to") {
                               // Extract destination from the command
                               let command = result.bestTranscription.formattedString
                               let destination = command.replacingOccurrences(of: "navigate to", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                               
                               // Calculate and display route to the destination
                               self.calculateAndDisplayRoute(to: destination)
                           }
            }
            
            if error != nil || isFinal {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                
                self.recognitionRequest = nil
                self.recognitionTask = nil
                
                self.StartStopButton.isEnabled = true
            }
        })
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, when) in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch {
            print("audioEngine couldn't start because of an error.")
        }
        
        TextView.text = "Say something, I'm listening!"
    }
    
    func calculateAndDisplayRoute(to destination: String) {
           // Create a request to geocode the destination address
           let geocoder = CLGeocoder()
           geocoder.geocodeAddressString(destination) { (placemarks, error) in
               guard let destinationPlacemark = placemarks?.first?.location else {
                   print("Error finding destination location: \(error?.localizedDescription ?? "Unknown error")")
                   return
               }
               
               // Create a request to calculate the route
               let request = MKDirections.Request()
               request.source = MKMapItem.forCurrentLocation()
               request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destinationPlacemark.coordinate))
               request.requestsAlternateRoutes = false
               request.transportType = .walking // You can change this to .walking if needed
               
               // Create the directions object
               let directions = MKDirections(request: request)
               
               // Calculate the route
               directions.calculate { (response, error) in
                   guard let route = response?.routes.first else {
                       print("Error finding route: \(error?.localizedDescription ?? "Unknown error")")
                       return
                   }
                   
                   // Remove any existing overlays on the map
                   self.mapView.removeOverlays(self.mapView.overlays)
                   
                   // Add the route to the map as an overlay
                   self.mapView.addOverlay(route.polyline)
                   
                   // Adjust the map to show the route
                   self.mapView.setVisibleMapRect(route.polyline.boundingMapRect, animated: true)
               }
           }
       }
       
       func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
           if available {
               StartStopButton.isEnabled = true
           } else {
               StartStopButton.isEnabled = false
           }
       }
    
    func startBallSpawning() {
                       let spawnInterval: TimeInterval = 1.0 // Adjust as needed
                       ballSpawnTimer = Timer.scheduledTimer(withTimeInterval: spawnInterval, repeats: true) { [weak self]  timer in
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
                   
                   func stopBallSpawning() {
                       ballSpawnTimer?.invalidate()
                       ballSpawnTimer = nil
                   }
               }

extension SCNGeometry {
    static func createWireframe(width: Float, height: Float, depth: CGFloat) -> SCNGeometry {
        // Increase wireframe width
        let wireframeWidth: Float = 0.1
        
        let vertices: [SCNVector3] = [
            SCNVector3(-width / 2 - wireframeWidth, -height / 2 - wireframeWidth, 0),
            SCNVector3(width / 2 + wireframeWidth, -height / 2 - wireframeWidth, 0),
            SCNVector3(width / 2 + wireframeWidth, height / 2 + wireframeWidth, 0),
            SCNVector3(-width / 2 - wireframeWidth, height / 2 + wireframeWidth, 0),
            SCNVector3(-width / 2 - wireframeWidth, -height / 2 - wireframeWidth, Float(depth)),
            SCNVector3(width / 2 + wireframeWidth, -height / 2 - wireframeWidth, Float(depth)),
            SCNVector3(width / 2 + wireframeWidth, height / 2 + wireframeWidth, Float(depth)),
            SCNVector3(-width / 2 - wireframeWidth, height / 2 + wireframeWidth, Float(depth)),
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
    
    static func line(from start: SCNVector3, to end: SCNVector3) -> SCNGeometry {
           let indices: [Int32] = [0, 1]
           let source = SCNGeometrySource(vertices: [start, end])
           let element = SCNGeometryElement(indices: indices, primitiveType: .line)
           return SCNGeometry(sources: [source], elements: [element])
       }
}
 
extension ViewController : CLLocationManagerDelegate{
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        let coodinates: CLLocationCoordinate2D = manager.location!.coordinate
        let spanDegree = MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)
        let region = MKCoordinateRegion(center: coodinates, span: spanDegree)
        
        mapView.setRegion(region, animated: true)
        mapView.showsUserLocation = true
        
  
    }
}
extension ViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor.systemBlue
            renderer.lineWidth = 3
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}
