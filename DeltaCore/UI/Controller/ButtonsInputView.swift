//
//  ButtonsInputView.swift
//  DeltaCore
//
//  Created by Riley Testut on 8/4/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

class ButtonsInputView: UIView
{
    var isHapticFeedbackEnabled = true
    
    var items: [ControllerSkin.Item]?
    
    var activateInputsHandler: ((Set<AnyInput>) -> Void)?
    var deactivateInputsHandler: ((Set<AnyInput>) -> Void)?
    
    var image: UIImage? {
        get {
            return self.imageView.image
        }
        set {
            self.imageView.image = newValue
        }
    }
    
    private let imageView = UIImageView(frame: .zero)

    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    private let pressHighlightLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        // Dark overlay to approximate "this button is depressed and its contents are in shadow"
        layer.fillColor = UIColor.black.withAlphaComponent(0.5).cgColor
        layer.strokeColor = UIColor.black.withAlphaComponent(0.85).cgColor
        layer.lineWidth = 2.5
        return layer
    }()

    private let touchDebugLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.white.withAlphaComponent(0.15).cgColor
        layer.strokeColor = UIColor.white.withAlphaComponent(0.8).cgColor
        layer.lineWidth = 1.5
        return layer
    }()

    // Fraction of touch.majorRadius used for button hit-testing.
    // 1.0 = full finger blob (registers every button the finger physically touches).
    // 0.5 = half radius, tuned via on-device testing to avoid false multi-button hits on
    //       tightly-packed layouts (e.g. the SNES four-button diamond) while still
    //       registering intentional two-button thumb presses.
    private static let radiusScale: CGFloat = 0.5
    private static let minimumRadius: CGFloat = 6
    
    private var touchInputsMappingDictionary: [UITouch: Set<AnyInput>] = [:]
    private var previousTouchInputs = Set<AnyInput>()
    private var touchInputs: Set<AnyInput> {
        return self.touchInputsMappingDictionary.values.reduce(Set<AnyInput>(), { $0.union($1) })
    }
    
    override var intrinsicContentSize: CGSize {
        return self.imageView.intrinsicContentSize
    }
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        self.isMultipleTouchEnabled = true
        
        self.feedbackGenerator.prepare()
        
        self.imageView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.imageView)

        NSLayoutConstraint.activate([self.imageView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                                     self.imageView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                                     self.imageView.topAnchor.constraint(equalTo: self.topAnchor),
                                     self.imageView.bottomAnchor.constraint(equalTo: self.bottomAnchor)])

        self.layer.addSublayer(self.pressHighlightLayer)
        self.layer.addSublayer(self.touchDebugLayer)
    }

    override func layoutSubviews()
    {
        super.layoutSubviews()
        self.pressHighlightLayer.frame = self.bounds
        self.touchDebugLayer.frame = self.bounds
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        for touch in touches
        {
            self.touchInputsMappingDictionary[touch] = []
        }
        
        self.updateInputs(for: touches)
    }
    
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        self.updateInputs(for: touches)
    }
    
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        for touch in touches
        {
            self.touchInputsMappingDictionary[touch] = nil
        }
        
        self.updateInputs(for: touches)
    }
    
    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?)
    {
        return self.touchesEnded(touches, with: event)
    }
}

extension ButtonsInputView
{
    func inputs(at point: CGPoint) -> [Input]?
    {
        guard let items = self.items else { return nil }
        
        var point = point
        point.x /= self.bounds.width
        point.y /= self.bounds.height
        
        var inputs: [Input] = []
        
        for item in items
        {
            guard item.extendedFrame.contains(point) else { continue }
            
            switch item.inputs
            {
            // Don't return inputs for thumbsticks or touch screens since they're handled separately.
            case .directional where item.kind == .thumbstick: break
            case .touch: break
                
            case .standard(let itemInputs):
                inputs.append(contentsOf: itemInputs)
            
            case let .directional(up, down, left, right):

                let divisor: CGFloat
                if case .thumbstick = item.kind
                {
                    divisor = 2.0
                }
                else
                {
                    divisor = 3.0
                }
                
                let topRect = CGRect(x: item.extendedFrame.minX, y: item.extendedFrame.minY, width: item.extendedFrame.width, height: (item.frame.height / divisor) + (item.frame.minY - item.extendedFrame.minY))
                let bottomRect = CGRect(x: item.extendedFrame.minX, y: item.frame.maxY - item.frame.height / divisor, width: item.extendedFrame.width, height: (item.frame.height / divisor) + (item.extendedFrame.maxY - item.frame.maxY))
                let leftRect = CGRect(x: item.extendedFrame.minX, y: item.extendedFrame.minY, width: (item.frame.width / divisor) + (item.frame.minX - item.extendedFrame.minX), height: item.extendedFrame.height)
                let rightRect = CGRect(x: item.frame.maxX - item.frame.width / divisor, y: item.extendedFrame.minY, width: (item.frame.width / divisor) + (item.extendedFrame.maxX - item.frame.maxX), height: item.extendedFrame.height)
                
                if topRect.contains(point)
                {
                    inputs.append(up)
                }
                
                if bottomRect.contains(point)
                {
                    inputs.append(down)
                }
                
                if leftRect.contains(point)
                {
                    inputs.append(left)
                }
                
                if rightRect.contains(point)
                {
                    inputs.append(right)
                }
            }
        }
        
        return inputs
    }
}

private extension ButtonsInputView
{
    func updateInputs(for touches: Set<UITouch>)
    {
        // Don't add the touches if it has been removed in touchesEnded:/touchesCancelled:
        for touch in touches where self.touchInputsMappingDictionary[touch] != nil
        {
            guard touch.view == self else { continue }
            
            let point = touch.location(in: self)
            let radius = max(touch.majorRadius * Self.radiusScale, Self.minimumRadius)
            let inputs = Set((self.inputs(coveredBy: point, radius: radius) ?? []).map { AnyInput($0) })
            
            let menuInput = AnyInput(stringValue: StandardGameControllerInput.menu.stringValue, intValue: nil, type: .controller(.controllerSkin))
            if inputs.contains(menuInput)
            {
                // If the menu button is located at this position, ignore all other inputs that might be overlapping.
                self.touchInputsMappingDictionary[touch] = [menuInput]
            }
            else
            {
                self.touchInputsMappingDictionary[touch] = Set(inputs)
            }
        }
        
        let activatedInputs = self.touchInputs.subtracting(self.previousTouchInputs)
        let deactivatedInputs = self.previousTouchInputs.subtracting(self.touchInputs)
        
        // We must update previousTouchInputs *before* calling activate() and deactivate().
        // Otherwise, race conditions that cause duplicate touches from activate() or deactivate() calls can result in various bugs.
        self.previousTouchInputs = self.touchInputs
        
        if !activatedInputs.isEmpty
        {
            self.activateInputsHandler?(activatedInputs)
            
            if self.isHapticFeedbackEnabled
            {
                switch UIDevice.current.feedbackSupportLevel
                {
                case .feedbackGenerator: self.feedbackGenerator.impactOccurred()
                case .basic, .unsupported: UIDevice.current.vibrate()
                }
            }
        }
        
        if !deactivatedInputs.isEmpty
        {
            self.deactivateInputsHandler?(deactivatedInputs)
        }

        self.updatePressHighlights()
    }

    func updatePressHighlights()
    {
        let path = CGMutablePath()

        if let items = self.items
        {
            for item in items
            {
                switch item.inputs
                {
                case .directional where item.kind == .thumbstick: continue
                case .touch: continue

                case .standard(let itemInputs):
                    let anyInputs = Set(itemInputs.map { AnyInput($0) })
                    guard !anyInputs.isDisjoint(with: self.touchInputs) else { continue }
                    // Circle highlight matching the visible button frame.
                    let frame = item.frame.scaled(to: self.bounds)
                    path.addEllipse(in: frame.insetBy(dx: 2, dy: 2))

                case let .directional(up, down, left, right):
                    // Highlight the center-ninth square of each arm of the d-pad cross,
                    // matching the arrow art rather than the full extended hit zone.
                    let fi = item.frame.scaled(to: self.bounds)
                    let divisor: CGFloat = 3.0
                    let dirs: [(Input, CGRect)] = [
                        (up,    CGRect(x: fi.minX + fi.width / divisor, y: fi.minY,                       width: fi.width / divisor, height: fi.height / divisor)),
                        (down,  CGRect(x: fi.minX + fi.width / divisor, y: fi.maxY - fi.height / divisor, width: fi.width / divisor, height: fi.height / divisor)),
                        (left,  CGRect(x: fi.minX,                       y: fi.minY + fi.height / divisor, width: fi.width / divisor, height: fi.height / divisor)),
                        (right, CGRect(x: fi.maxX - fi.width / divisor, y: fi.minY + fi.height / divisor, width: fi.width / divisor, height: fi.height / divisor)),
                    ]
                    for (input, rect) in dirs where self.touchInputs.contains(AnyInput(input))
                    {
                        path.addRoundedRect(in: rect, cornerWidth: 8, cornerHeight: 8)
                    }
                }
            }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.pressHighlightLayer.path = path

        // Debug: draw the actual hit-test circle for each active touch.
        let debugPath = CGMutablePath()
        for touch in self.touchInputsMappingDictionary.keys
        {
            guard touch.view == self else { continue }
            let center = touch.location(in: self)
            let radius = max(touch.majorRadius * Self.radiusScale, Self.minimumRadius)
            debugPath.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        self.touchDebugLayer.path = debugPath

        CATransaction.commit()
    }

    func inputs(coveredBy point: CGPoint, radius: CGFloat) -> [Input]?
    {
        guard let items = self.items else { return nil }
        var inputs: [Input] = []

        for item in items
        {
            let extendedInBounds = item.extendedFrame.scaled(to: self.bounds)

            switch item.inputs
            {
            case .directional where item.kind == .thumbstick: break
            case .touch: break
            case .standard(let itemInputs):
                // Use the visible frame's shape (circle for face buttons, capsule for
                // Start/Select) as the corner radius for hit-testing against the extended frame.
                let frameInBounds = item.frame.scaled(to: self.bounds)
                let cornerRadius = min(frameInBounds.width, frameInBounds.height) / 2
                guard Self.circle(center: point, radius: radius, intersects: extendedInBounds, cornerRadius: cornerRadius) else { continue }
                inputs.append(contentsOf: itemInputs)
            case let .directional(up, down, left, right):
                guard Self.circle(center: point, radius: radius, intersects: extendedInBounds) else { continue }
                let fi = item.frame.scaled(to: self.bounds)
                let f  = extendedInBounds
                let divisor: CGFloat = 3.0
                let topRect    = CGRect(x: f.minX, y: f.minY, width: f.width, height: (fi.height / divisor) + (fi.minY - f.minY))
                let bottomRect = CGRect(x: f.minX, y: fi.maxY - fi.height / divisor, width: f.width, height: (fi.height / divisor) + (f.maxY - fi.maxY))
                let leftRect   = CGRect(x: f.minX, y: f.minY, width: (fi.width / divisor) + (fi.minX - f.minX), height: f.height)
                let rightRect  = CGRect(x: fi.maxX - fi.width / divisor, y: f.minY, width: (fi.width / divisor) + (f.maxX - fi.maxX), height: f.height)
                if Self.circle(center: point, radius: radius, intersects: topRect)    { inputs.append(up) }
                if Self.circle(center: point, radius: radius, intersects: bottomRect) { inputs.append(down) }
                if Self.circle(center: point, radius: radius, intersects: leftRect)   { inputs.append(left) }
                if Self.circle(center: point, radius: radius, intersects: rightRect)  { inputs.append(right) }
            }
        }

        return inputs
    }

    // Circle vs axis-aligned rectangle.
    static func circle(center: CGPoint, radius: CGFloat, intersects rect: CGRect) -> Bool
    {
        let closestX = max(rect.minX, min(rect.maxX, center.x))
        let closestY = max(rect.minY, min(rect.maxY, center.y))
        let dx = closestX - center.x
        let dy = closestY - center.y
        return dx * dx + dy * dy <= radius * radius
    }

    // Circle vs rounded rectangle. Equivalent to shrinking the rect by cornerRadius on all
    // sides (giving the "inner rect") and expanding the touch radius by cornerRadius — so
    // corners are excluded and the shape matches the button's visual outline.
    static func circle(center: CGPoint, radius: CGFloat, intersects rect: CGRect, cornerRadius: CGFloat) -> Bool
    {
        let cr = min(cornerRadius, min(rect.width, rect.height) / 2)
        let innerRect = rect.insetBy(dx: cr, dy: cr)
        let closestX = max(innerRect.minX, min(innerRect.maxX, center.x))
        let closestY = max(innerRect.minY, min(innerRect.maxY, center.y))
        let dx = closestX - center.x
        let dy = closestY - center.y
        return dx * dx + dy * dy <= (radius + cr) * (radius + cr)
    }
}
