//
//  ViewController.swift
//  ToTest2
//
//  Created by Mohit Kumar Gupta on 26/03/24.
//
import UIKit
import SceneKit
import ARKit
import Speech
import AVFoundation
import MediaPlayer
import MapKit
import CoreLocation
import CoreML

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
        guard let _ = camera else { return }

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

class ViewController: UIViewController, ARSCNViewDelegate, SFSpeechRecognizerDelegate {
    
    
    
    
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet var startButton: UIButton!
    @IBOutlet var StartStopButton: UIButton!
    @IBOutlet var stopButton: UIButton!
    @IBOutlet var pathButton: UIButton!
    @IBOutlet var TextView: UITextView!
    @IBOutlet var path2Button: UIButton!
    
    
    @IBOutlet var path3Button: UIButton!
    
    @IBOutlet var mapView: MKMapView!
    
    var focusSquare: FocusNode?
    var lastBallSpawnPosition: SCNVector3?
    var ballSpawnTimer: Timer?
    var ballNodes = [SCNNode]()
    var savedBallPositions = [SCNVector3]()
    var savedPaths: [[SCNVector3]] = []
    var currentPath: [SCNVector3] = []
    var currentPathIndex: Int = 0
    
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
    
    private var audioSession = AVAudioSession.sharedInstance()

    var audioLevel: Float = 0.0
    
    let locationManager = CLLocationManager()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        locationManager.delegate = self
               locationManager.requestWhenInUseAuthorization()
               locationManager.startUpdatingLocation()
        
        StartStopButton.isEnabled = false
        speechRecognizer?.delegate = self

        SFSpeechRecognizer.requestAuthorization { (authStatus) in
            var isButtonEnabled = false
            switch authStatus {
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
        
        
        
        
        listenVolumeButton()
        
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
    
    

    func listenVolumeButton() {
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setActive(true, options: [])
                audioSession.addObserver(self, forKeyPath: "outputVolume", options: .new, context: nil)
                audioLevel = audioSession.outputVolume
            } catch {
                print("Error setting up audio session")
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
    

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == "outputVolume" {
                let audioSession = AVAudioSession.sharedInstance()
                if audioSession.outputVolume > audioLevel {
                    print("Volume Increased")
                    startStopAction(StartStopButton)
                    audioLevel = audioSession.outputVolume
                }
                if audioSession.outputVolume < audioLevel {
                    print("Volume Decreased")
                    startStopAction(StartStopButton)
                    audioLevel = audioSession.outputVolume
                }
                
                
            }
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

        let ballPosition = self.calculateBallSpawnPosition()

        let ballNode = SCNNode(geometry: SCNSphere(radius: 0.05)) // Adjust radius as needed
        ballNode.geometry?.firstMaterial?.diffuse.contents = UIColor.blue
        ballNode.position = self.calculateBallSpawnPosition()

        ballNode.position = ballPosition
        sceneView.scene.rootNode.addChildNode(ballNode)

        ballNodes.append(ballNode)
        currentPath.append(ballNode.position) // Add position to current path
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
        saveCurrentPath() // Save the current path
        removeBalls()
    }

    @IBAction func startStopAction(_ sender: UIButton) {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.init(identifier: lang))
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            StartStopButton.isEnabled = false
            StartStopButton.setTitle("Start Recording", for: .normal)
            
        } else {
            startRecording()
            StartStopButton.setTitle("Stop Recording", for: .normal)
        }
    }

    @IBAction func pathButtonPressed(_ sender: UIButton) {
        
        
        guard let sceneView = self.sceneView else { return }

                // Assuming savedPaths contains the desired path (e.g., path1)
                guard let path = savedPaths.first else {
                    print("No saved path available.")
                    return
                }

                // Remove existing balls and recreate for the selected path
                removeBalls()
                recreateBalls(path: path)

                // Provide guidance for the path
                provideGuidanceForPath()
    }

    @IBAction func path2ButtonPressed(_ sender: UIButton) {
        displayPathAtIndex(index: 1)
    }

    @IBAction func path3ButtonPressed(_ sender: UIButton) {
        displayPathAtIndex(index: 2)
    }

    func provideGuidanceForPath() {
        guard let sceneView = self.sceneView else { return }

        let speechSynthesizer = AVSpeechSynthesizer()
        let cameraPosition = sceneView.pointOfView?.position ?? SCNVector3Zero

        // Store the total number of ball nodes for easier reference
        let totalBallNodes = ballNodes.count

        // Iterate through each ball node
        for (index, ballNode) in ballNodes.enumerated() {
            let ballPosition = ballNode.position
            let relativePosition = SCNVector3(ballPosition.x - cameraPosition.x, ballPosition.y - cameraPosition.y, ballPosition.z - cameraPosition.z)

            // Determine direction based on relative position
            let directionText = getDirectionText(for: relativePosition)

            // Speak the direction immediately
            let speechUtterance = AVSpeechUtterance(string: directionText)
            speechSynthesizer.speak(speechUtterance)

            // If it's the last ball node, speak the completion message after a delay
            if index == totalBallNodes - 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index + 1) * 3.0) {
                    let completionUtterance = AVSpeechUtterance(string: "You've reached the end of the path.")
                    speechSynthesizer.speak(completionUtterance)
                }
            }
        }
    }
    
    func getDirectionText(for position: SCNVector3) -> String {
            let threshold: Float = 0.2 // Adjust as needed

            if abs(position.z) < threshold {
                return "Move forward."
            } else if position.x < -threshold {
                return "Ball is on your left. Move left."
            } else if position.x > threshold {
                return "Ball is on your right. Move right."
            } else {
                return "Unknown direction."
            }
        }
    
    func displayPathAtIndex(index: Int) {
        guard index >= 0 && index < savedPaths.count else {
            print("Invalid path index")
            return
        }

        let path = savedPaths[index]
        recreateBalls(path: path)
    }

    func recreateBalls(path: [SCNVector3]) {
        removeBalls()

        for position in path {
            let ballNode = SCNNode(geometry: SCNSphere(radius: 0.05))
            ballNode.geometry?.firstMaterial?.diffuse.contents = UIColor.green
            ballNode.position = position
            sceneView.scene.rootNode.addChildNode(ballNode)
            ballNodes.append(ballNode)
        }
    }

    func removeBalls() {
        for ballNode in ballNodes {
            ballNode.removeFromParentNode()
        }
        ballNodes.removeAll()
    }

    func stopBallSpawning() {
        ballSpawnTimer?.invalidate()
        ballSpawnTimer = nil
    }

    func saveCurrentPath() {
           if savedPaths.count >= 3 {
               print("Not more paths can be saved")
               let alert = UIAlertController(title: "Limit Exceeded", message: "You can only save up to 3 paths", preferredStyle: .alert)
               alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
               self.present(alert, animated: true, completion: nil)
               return
           }
           
           savedPaths.append(currentPath)
           currentPathIndex += 1
           print("Path \(currentPathIndex) saved")
           let alert = UIAlertController(title: "Path Saved", message: "Path \(currentPathIndex) saved", preferredStyle: .alert)
           alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
           self.present(alert, animated: true, completion: nil)
           currentPath = []
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

            if let transcription = result?.bestTranscription {
                       self.TextView.text = transcription.formattedString
                       // Check if "stop" is recognized
                       if transcription.formattedString.lowercased().contains("stop") {
                           self.audioEngine.stop()
                           // Perform cleanup and stop recording
                           self.recognitionRequest?.endAudio()
                       }
                
                            else if transcription.formattedString.lowercased().contains("navigate to bathroom") {
                                // Programmatically trigger the pathButton action
                                self.pathButtonPressed(self.pathButton)
                            }
                
                
                
                       isFinal = result!.isFinal
                   }

            
            
            if result != nil {
                self.TextView.text = result?.bestTranscription.formattedString
                isFinal = (result?.isFinal)!
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

    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            StartStopButton.isEnabled = true
        } else {
            StartStopButton.isEnabled = false
        }
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
