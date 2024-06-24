import UIKit
import ARKit
import simd

internal class ViewController: UIViewController, ARSessionDelegate {
    
    @IBOutlet weak internal var groundSlider: UISlider!
    @IBOutlet weak internal var aboveSlider: UISlider!
    @IBOutlet weak internal var belowSlider: UISlider!
    @IBOutlet weak internal var groundLabel: UILabel!
    @IBOutlet weak internal var aboveLabel: UILabel!
    @IBOutlet weak internal var belowLabel: UILabel!
    
    internal var sceneView: ARSCNView!
    internal var heatmapView: UIImageView!
    internal var groundLevel: Float = 0.0
    internal var rangeAbove: Float = 0.0
    internal var rangeBelow: Float = 0.0
    
    private let debounceTimeInterval: TimeInterval = 0.2
    private let downsampleFactor = 4
    private let depthScanDuration: TimeInterval = 2.0
    private var depthScanTimer: Timer?
    private var depthValues: [Float] = []
    
    private var debounceTimer: Timer?
    
    override internal func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize ARSCNView and add it to the view
        sceneView = ARSCNView(frame: self.view.bounds)
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(sceneView)
        
        // Initialize heatmapView and add it to the view
        heatmapView = UIImageView(frame: self.view.bounds)
        heatmapView.contentMode = .scaleAspectFit
        heatmapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(heatmapView)
        
        // Bring sliders and labels to the front
        self.view.bringSubviewToFront(groundSlider)
        self.view.bringSubviewToFront(aboveSlider)
        self.view.bringSubviewToFront(belowSlider)
        self.view.bringSubviewToFront(groundLabel)
        self.view.bringSubviewToFront(aboveLabel)
        self.view.bringSubviewToFront(belowLabel)
        
        // Initialize AR session configuration
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = .sceneDepth
        sceneView.session.run(configuration)
        sceneView.session.delegate = self
        
        // Start depth scanning
        startDepthScanning()
        
        // Add target for slider value change
        groundSlider.addTarget(self, action: #selector(groundSliderChanged(_:)), for: .valueChanged)
        aboveSlider.addTarget(self, action: #selector(aboveSliderChanged(_:)), for: .valueChanged)
        belowSlider.addTarget(self, action: #selector(belowSliderChanged(_:)), for: .valueChanged)
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.adjustLayout(for: size)
        })
    }
    
    private func adjustLayout(for size: CGSize) {
        // Update the frames of the ARSCNView and heatmapView
        sceneView.frame = CGRect(origin: .zero, size: size)
        heatmapView.frame = CGRect(origin: .zero, size: size)
    }
    
    private func startDepthScanning() {
        depthScanTimer?.invalidate()
        depthValues.removeAll()
        
        depthScanTimer = Timer.scheduledTimer(withTimeInterval: depthScanDuration, repeats: false) { [weak self] _ in
            self?.updateSliderRanges()
        }
    }
    
    private func updateSliderRanges() {
        guard !depthValues.isEmpty else {
            return
        }
        
        let minDepth = depthValues.min() ?? 0.0
        let maxDepth = depthValues.max() ?? 0.0
        let medianDepth = depthValues.sorted(by: <)[depthValues.count / 2]
        
        let range = maxDepth - minDepth
        let mountainRange = range * 0.2 // Adjust this value to control the size of the mountain range
        let grassRange = range * 0.6 // Adjust this value to control the size of the grass range
        let peakRange = range * 0.05 // Adjust this value to control the size of the peak
        
        groundLevel = maxDepth - grassRange
        rangeBelow = grassRange
        rangeAbove = mountainRange
        
        // Update slider ranges and values
        groundSlider.minimumValue = minDepth
        groundSlider.maximumValue = maxDepth
        groundSlider.value = groundLevel
        
        belowSlider.minimumValue = 0.0
        belowSlider.maximumValue = grassRange
        belowSlider.value = grassRange / 2.0
        
        aboveSlider.minimumValue = 0.0
        aboveSlider.maximumValue = mountainRange + peakRange
        aboveSlider.value = mountainRange / 2.0
        
        // Update labels
        groundLabel.text = String(format: "Ground Distance: %.2fm", groundLevel)
        aboveLabel.text = String(format: "Mountain Height: %.2fm", rangeAbove)
        belowLabel.text = String(format: "Water Depth: %.2fm", rangeBelow)
    }
    @IBAction func groundSliderChanged(_ sender: UISlider) {
        print("Ground slider changed: \(sender.value)")
        groundLevel = sender.value
        groundLabel.text = String(format: "Ground Distance: %.2fm", groundLevel)
        debounceUpdate()
    }
    
    @IBAction func aboveSliderChanged(_ sender: UISlider) {
        print("Above slider changed: \(sender.value)")
        rangeAbove = sender.value
        aboveLabel.text = String(format: "Snow Height: %.2fm", rangeAbove)
        debounceUpdate()
    }
    
    @IBAction func belowSliderChanged(_ sender: UISlider) {
        print("Below slider changed: \(sender.value)")
        rangeBelow = sender.value
        belowLabel.text = String(format: "Water Depth: %.2fm", rangeBelow)
        debounceUpdate()
    }
    
    private func debounceUpdate() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(timeInterval: debounceTimeInterval, target: self, selector: #selector(updateColorMap), userInfo: nil, repeats: false)
    }
    
    internal func session(_ session: ARSession, didUpdate frame: ARFrame) {
        updateColorMap()
        
        guard let sceneDepth = frame.sceneDepth else {
            return
        }
        
        let depthData = sceneDepth.depthMap
        let width = CVPixelBufferGetWidth(depthData)
        let height = CVPixelBufferGetHeight(depthData)
        
        CVPixelBufferLockBaseAddress(depthData, .readOnly)
        let baseAddress = CVPixelBufferGetBaseAddress(depthData)
        let buffer = baseAddress!.assumingMemoryBound(to: Float32.self)
        
        for y in stride(from: 0, to: height, by: downsampleFactor) {
            for x in stride(from: 0, to: width, by: downsampleFactor) {
                let index = y * width + x
                depthValues.append(buffer[index])
            }
        }
        
        CVPixelBufferUnlockBaseAddress(depthData, .readOnly)
    }
    
    @objc private func updateColorMap() {
        print("Updating color map")
        guard let frame = sceneView.session.currentFrame, let sceneDepth = frame.sceneDepth else { return }
        
        let depthData = sceneDepth.depthMap
        let width = CVPixelBufferGetWidth(depthData)
        let height = CVPixelBufferGetHeight(depthData)
        
        CVPixelBufferLockBaseAddress(depthData, .readOnly)
        let baseAddress = CVPixelBufferGetBaseAddress(depthData)
        let buffer = baseAddress!.assumingMemoryBound(to: Float32.self)
        
        // Downsample the depth data for efficiency
        let downsampledWidth = width / downsampleFactor
        let downsampledHeight = height / downsampleFactor
        var downsampledDepthArray = [Float32](repeating: 0, count: downsampledWidth * downsampledHeight)
        
        for y in 0..<downsampledHeight {
            for x in 0..<downsampledWidth {
                let index = y * downsampledWidth + x
                let originalIndex = (y * downsampleFactor) * width + (x * downsampleFactor)
                if originalIndex < width * height { // Ensure we don't go out of bounds
                    downsampledDepthArray[index] = buffer[originalIndex]
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(depthData, .readOnly)
        
        let colorMapImage = createColorMap(from: downsampledDepthArray, width: downsampledWidth, height: downsampledHeight)
        DispatchQueue.main.async {
            self.heatmapView.image = colorMapImage
        }
    }
    
    internal func createColorMap(from depthData: [Float32], width: Int, height: Int) -> UIImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo)!
        
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let depth = depthData[index]
                
                // Map the depth to a terrain-like color
                let color: UIColor
                if depth > groundLevel {
                    color = UIColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0) // Water (Blue)
                } else if depth > groundLevel - rangeBelow {
                    let greenComponent = (depth - (groundLevel - rangeBelow)) / rangeBelow
                    color = UIColor(red: 0.0, green: CGFloat(greenComponent), blue: 0.0, alpha: 1.0) // Gradient from brown to green
                } else if depth > groundLevel - rangeBelow - rangeAbove {
                    let brownComponent = (depth - (groundLevel - rangeBelow - rangeAbove)) / rangeAbove
                    color = UIColor(red: 0.6 * CGFloat(brownComponent), green: 0.4 * CGFloat(brownComponent), blue: 0.2 * CGFloat(brownComponent), alpha: 1.0) // Gradient from green to brown
                } else {
                    color = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0) // Snow (White)
                }
                
                context.setFillColor(color.cgColor)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        
        let cgImage = context.makeImage()
        return UIImage(cgImage: cgImage!)
    }
    
}
