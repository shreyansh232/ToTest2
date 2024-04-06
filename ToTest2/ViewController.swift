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
        } else {
            focusSquare?.isHidden = true
        }
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
    @IBOutlet var textLabel: UILabel!
    

    var focusSquare: FocusNode?
    var lastBallSpawnPosition: SCNVector3?
    var ballSpawnTimer: Timer?
    var ballNodes = [SCNNode]()
    var savedBallPositions = [SCNVector3]()
    var savedPaths: [[SCNVector3]] = []
    var currentPath: [SCNVector3] = []
    var currentPathIndex: Int = 0

    private var speechRecognizer = SFSpeechRecognizer(locale: Locale.init(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    var lang: String = "en-US"

    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(volumeChanged(notification:)), name: NSNotification.Name(rawValue: "AVSystemController_SystemVolumeDidChangeNotification"), object: nil)
        
        
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
        
        
        
    }
    
    @objc func volumeChanged(notification: NSNotification) {
        guard let userInfo = notification.userInfo else { return }
        guard let volumeChangeType = userInfo["AVSystemController_AudioVolumeChangeReasonNotificationParameter"] as? String else { return }
        if volumeChangeType == "ExplicitVolumeChange" {
            // Call the startStopAction method
            startStopAction(StartStopButton)
        }
    }
    

    // ARSCNViewDelegate method
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let _ = sceneView.session.currentFrame else {
            return
        }

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
        displayPathAtIndex(index: 0)
    }

    @IBAction func path2ButtonPressed(_ sender: UIButton) {
        displayPathAtIndex(index: 1)
    }

    @IBAction func path3ButtonPressed(_ sender: UIButton) {
        displayPathAtIndex(index: 2)
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
