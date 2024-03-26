//
//  FocusNode.swift
//  ToTest2
//
//  Created by Mohit Kumar Gupta on 26/03/24.
//

//import Foundation
//import SceneKit
//import ARKit
//
//class FocusNode: SCNNode {
//    
//    private var focusSquare: SCNNode?
//    
//    override init() {
//        super.init()
//        setupFocusSquare()
//    }
//    
//    required init?(coder aDecoder: NSCoder) {
//        super.init(coder: aDecoder)
//        setupFocusSquare()
//    }
//    
//    private func setupFocusSquare() {
//        let focusSquareGeometry = SCNPlane(width: 0.1, height: 0.1)
//        focusSquareGeometry.firstMaterial?.diffuse.contents = UIColor.red.withAlphaComponent(0.8)
//        focusSquare = SCNNode(geometry: focusSquareGeometry)
//        focusSquare?.eulerAngles.x = -.pi / 2 // Make it horizontal
//        addChildNode(focusSquare!)
//    }
//    
//    func update(for position: SCNVector3, planeAnchor: ARPlaneAnchor?, camera: ARCamera?, sceneView: ARSCNView) {
//        guard let camera = camera else { return }
//        
//        // Hide the focus square if no plane anchor is available
//        if planeAnchor == nil {
//            focusSquare?.isHidden = true
//            return
//        }
//        
//        // Calculate the position of the focus square
//        let translation = camera.transform.columns.3
//        let hitTestResults = sceneView.hitTest(sceneView.center, types: .existingPlaneUsingExtent)
//        if let hitTestResult = hitTestResults.first {
//            let hitTransform = hitTestResult.worldTransform
//            let hitVector = SCNVector3(hitTransform.columns.3.x, hitTransform.columns.3.y, hitTransform.columns.3.z)
//            focusSquare?.position = hitVector
//            focusSquare?.isHidden = false
//        } else {
//            focusSquare?.isHidden = true
//        }
//    }
//}
