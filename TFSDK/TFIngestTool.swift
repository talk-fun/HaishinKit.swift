//
//  TFIngestTool.swift
//  TFSRT
//
//  Created by moRui on 2024/12/26.
//

import UIKit
import HaishinKit
import Photos
import UIKit
import VideoToolbox
import Combine
import CoreVideo
import CoreGraphics
enum ScaleMode {
    case fitWidth    // 适应宽度（宽度铺满）
    case fitHeight   // 适应高度（高度铺满）
    case fitBoth     // 同时适应宽高（可能会有空白）
}
class TFIngestTool: NSObject {
    class func setEnabledPreferredInputBuiltInMic(_ isEnabled: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if isEnabled {
                guard
                    let availableInputs = session.availableInputs,
                    let builtInMicInput = availableInputs.first(where: { $0.portType == .builtInMic }) else {
                    return
                }
                try session.setPreferredInput(builtInMicInput)
            } else {
                try session.setPreferredInput(nil)
            }
        } catch {
        }
    }
    class func extractLastPathComponent(from urlString: String) -> String? {
        if let urlComponents = URLComponents(string: urlString),
           let path = urlComponents.path.split(separator: "/").last {
            return String(path)
        }
        return nil
    }
    // 3. 将 SampleBuffer 创建逻辑分离到独立函数
    class func createSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
            // 4. 使用精确的时间戳计算
            let timestamp = CACurrentMediaTime()
            var timingInfo = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: 30),
                presentationTimeStamp: CMTime(seconds: timestamp, preferredTimescale: 600),
                decodeTimeStamp: .invalid
            )
            
            // 5. 创建 video format description
            var videoInfo: CMFormatDescription?
            let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &videoInfo
            )
            
            guard formatStatus == noErr, let videoInfo = videoInfo else {
                return nil
            }
            
            // 6. 创建 sample buffer
            var sampleBuffer: CMSampleBuffer?
            let createStatus = CMSampleBufferCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: videoInfo,
                sampleTiming: &timingInfo,
                sampleBufferOut: &sampleBuffer
            )
            
            guard createStatus == noErr, let buffer = sampleBuffer else {
                return nil
            }
            
            return buffer
        }
    
    
    class func focusPoint(_ focusPoint: CGPoint,
                             focusMode: AVCaptureDevice.FocusMode,
                             exposureMode: AVCaptureDevice.ExposureMode,
                             device: AVCaptureDevice?) {
          guard let device = device else { return }
          
          do {
              try device.lockForConfiguration()
              
              // 先进行判断是否支持控制对焦模式
              // 对焦模式和对焦点
              if device.isFocusModeSupported(focusMode) {
                  device.focusPointOfInterest = focusPoint
                  device.focusMode = focusMode
              }
              
              // 先进行判断是否支持曝光模式
              // 曝光模式和曝光点
              if device.isExposureModeSupported(exposureMode) {
                  device.exposurePointOfInterest = focusPoint
                  device.exposureMode = exposureMode
              }
              
              device.unlockForConfiguration()
          } catch {
              // 处理错误，例如打印或者显示错误信息
              print("Could not lock device for configuration: \(error)")
          }
      }
    
 
    
    
 

    class func pixelBufferFromCGImage(_ image: CGImage) -> CVPixelBuffer? {
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        var pxbuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         image.width,
                                         image.height,
                                         kCVPixelFormatType_32ARGB,
                                         options as CFDictionary,
                                         &pxbuffer)
        
        guard status == kCVReturnSuccess, let buffer = pxbuffer else {
            // print("Operation failed")
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        }
        
        guard let pxdata = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: pxdata,
                                      width: image.width,
                                      height: image.height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 4 * image.width,
                                      space: rgbColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
            return nil
        }
        
        // Apply transformations
        context.concatenate(CGAffineTransform(rotationAngle: 0))
        
        // Flip vertically
        let flipVertical = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: CGFloat(image.height))
        context.concatenate(flipVertical)
        
        // Flip horizontally
        let flipHorizontal = CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: CGFloat(image.width), y: 0)
        context.concatenate(flipHorizontal)
        
        // Draw the image
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        
        return buffer
    }
    
    class func resizeCIImage(image: CIImage, targetSize: CGSize, mode: ScaleMode = .fitBoth) -> CIImage? {
        let originalSize = image.extent.size
        
        // 根据缩放模式计算缩放比例
        let scale: CGFloat
        switch mode {
        case .fitWidth:
            scale = targetSize.width / originalSize.width
        case .fitHeight:
            scale = targetSize.height / originalSize.height
        case .fitBoth:
            let scaleX = targetSize.width / originalSize.width
            let scaleY = targetSize.height / originalSize.height
            scale = min(scaleX, scaleY)
        }
        
        // 应用缩放
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let resizedImage = image.transformed(by: transform)
        
        // 计算缩放后的尺寸
        let scaledSize = resizedImage.extent.size
        
        // 计算偏移量
        let offsetX = (targetSize.width - scaledSize.width) / 2
        let offsetY = (targetSize.height - scaledSize.height) / 2
        
        // 创建背景
        let newImage = CIImage(color: CIColor.clear)
            .cropped(to: CGRect(origin: .zero, size: targetSize))
        
        // 居中图像
        let centeredImage = resizedImage.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
        
        // 合成最终图像
        let finalImage = centeredImage.composited(over: newImage)
        
        return finalImage
    }
    /// 调整 CIImage 的大小
    /// - Parameters:
    ///   - image: 需要调整大小的 CIImage
    ///   - targetSize: 目标大小（宽度和高度）
    /// - Returns: 调整后的 CIImage
    class func resizeCIImage(image: CIImage, to targetSize: CGSize, mode: UIView.ContentMode) -> CIImage? {
           let originalSize = image.extent.size
           
           // 计算缩放比例
           let scaleX = targetSize.width / originalSize.width
           let scaleY = targetSize.height / originalSize.height
           
           let scale: CGFloat
           switch mode {
           case .scaleAspectFit:
               // 取较小的缩放比例，确保图片完全显示在目标尺寸内
               scale = min(scaleX, scaleY)
           case .scaleAspectFill:
               // 取较大的缩放比例，确保图片填满目标尺寸
               scale = max(scaleX, scaleY)
           case .scaleToFill:
               // 直接使用目标尺寸的缩放比例，可能会拉伸图片
               return image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
           default:
               // 默认使用 Aspect Fit
               scale = min(scaleX, scaleY)
           }
           
           // 应用缩放
           let transform = CGAffineTransform(scaleX: scale, y: scale)
           let resizedImage = image.transformed(by: transform)
           
           // 计算居中偏移量
           let scaledSize = resizedImage.extent.size
           let offsetX = (targetSize.width - scaledSize.width) / 2
           let offsetY = (targetSize.height - scaledSize.height) / 2
           
           // 创建一个新的 CIImage，尺寸为目标尺寸
           let newImage = CIImage(color: CIColor.clear).cropped(to: CGRect(origin: .zero, size: targetSize))
           
           // 将缩放后的图像居中绘制到新图像上
           let centeredImage = resizedImage.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
           
           // 将居中后的图像合成到新图像上
           let finalImage = centeredImage.composited(over: newImage)
           
           return finalImage
       }
   class func calculateNewWatermarkFrame(originalFrame: CGRect, imageExtent: CGSize, screenBounds: CGRect) -> CGRect {
        // 计算缩放因子
        let scaleFactorWidth = imageExtent.width / screenBounds.width
        let scaleFactorHeight = imageExtent.height / screenBounds.height
        let scaleFactor = min(scaleFactorWidth, scaleFactorHeight)
        
        // 调整水印帧的位置和大小
        var newFrame = originalFrame
        newFrame.origin.x *= scaleFactor
        newFrame.origin.y *= scaleFactor
        newFrame.size.width *= scaleFactor
        newFrame.size.height *= scaleFactor
        
        return newFrame
    }
}

public class TFIngestConfiguration: NSObject {
    /**视频的分辨率，宽高务必设定为 2 的倍数，否则解码播放时可能出现绿边(这个videoSizeRespectingAspectRatio设置为YES则可能会改变)*/
    @objc public var videoSize:CGSize = .zero
    /**视频的帧率，即 fps*/
    @objc public var videoFrameRate:CGFloat = 0
    /**视频的码率，单位是 bps*/
    @objc public var videoBitRate:Int = 0
    /**镜像*/
    @objc public var mirror:Bool = false
    /**近  中   远  摄像头*/
    @objc public var currentDeviceType:AVCaptureDevice.DeviceType = .builtInWideAngleCamera
    /***/
    @objc public var currentPosition:AVCaptureDevice.Position = .front
    /**推流模式*/
    @objc public var streamMode:TFStreamMode = .rtmp
    /**摄像头输出方向*/
    @objc public var outputImageOrientation: AVCaptureVideoOrientation = .portrait
}
extension UIInterfaceOrientation {
    func toAVCaptureVideoOrientation() -> AVCaptureVideoOrientation? {
        switch self {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        case .unknown:
            return .portrait
        @unknown default:
            return .portrait
        }
    }
}
extension Data {
    func chunk(_ size: Int) -> [Data] {
        if count < size {
            return [self]
        }
        var chunks: [Data] = []
        let length = count
        var offset = 0
        repeat {
            let thisChunkSize = ((length - offset) > size) ? size : (length - offset)
            chunks.append(subdata(in: offset..<offset + thisChunkSize))
            offset += thisChunkSize
        } while offset < length
        return chunks
    }
}
//extension CVPixelBuffer {
//    enum Error: Swift.Error {
//        case failedToLock(_ status: CVReturn)
//        case failedToUnlock(_ status: CVReturn)
//        case unsupportedFormat(_ format: OSType)
//    }
//
//    static let lockFlags = CVPixelBufferLockFlags(rawValue: .zero)
//
//    @inlinable @inline(__always)
//    var size: CGSize {
//        return .init(width: CVPixelBufferGetWidth(self), height: CVPixelBufferGetHeight(self))
//    }
//
//    @inlinable @inline(__always)
//    var dataSize: Int {
//        CVPixelBufferGetDataSize(self)
//    }
//
//    @inlinable @inline(__always)
//    var pixelFormatType: OSType {
//        CVPixelBufferGetPixelFormatType(self)
//    }
//
//    @inlinable @inline(__always)
//    var baseAddress: UnsafeMutableRawPointer? {
//        CVPixelBufferGetBaseAddress(self)
//    }
//
//    @inlinable @inline(__always)
//    var planeCount: Int {
//        CVPixelBufferGetPlaneCount(self)
//    }
//
//    @inlinable @inline(__always)
//    var bytesPerRow: Int {
//        CVPixelBufferGetBytesPerRow(self)
//    }
//
//    @inlinable @inline(__always)
//    var width: Int {
//        CVPixelBufferGetWidth(self)
//    }
//
//    @inlinable @inline(__always)
//    var height: Int {
//        CVPixelBufferGetHeight(self)
//    }
//
//    @inlinable @inline(__always)
//    var formatType: OSType {
//        CVPixelBufferGetPixelFormatType(self)
//    }
//
//    @inline(__always)
//    func copy(_ pixelBuffer: CVPixelBuffer?) throws {
//        // https://stackoverflow.com/questions/53132611/copy-a-cvpixelbuffer-on-any-ios-device
//        try pixelBuffer?.mutate(.readOnly) { pixelBuffer in
//            if planeCount == 0 {
//                let dst = self.baseAddress
//                let src = pixelBuffer.baseAddress
//                let bytesPerRowSrc = pixelBuffer.bytesPerRow
//                let bytesPerRowDst = bytesPerRowSrc
//                if bytesPerRowSrc == bytesPerRowDst {
//                    memcpy(dst, src, height * bytesPerRowSrc)
//                } else {
//                    var startOfRowSrc = src
//                    var startOfRowDst = dst
//                    for _ in 0..<height {
//                        memcpy(startOfRowDst, startOfRowSrc, min(bytesPerRowSrc, bytesPerRowDst))
//                        startOfRowSrc = startOfRowSrc?.advanced(by: bytesPerRowSrc)
//                        startOfRowDst = startOfRowDst?.advanced(by: bytesPerRowDst)
//                    }
//                }
//            } else {
//                for plane in 0..<planeCount {
//                    let dst = baseAddressOfPlane(plane)
//                    let src = pixelBuffer.baseAddressOfPlane(plane)
//                    let height = getHeightOfPlane(plane)
//                    let bytesPerRowSrc = pixelBuffer.bytesPerRawOfPlane(plane)
//                    let bytesPerRowDst = bytesPerRawOfPlane(plane)
//                    if bytesPerRowSrc == bytesPerRowDst {
//                        memcpy(dst, src, height * bytesPerRowSrc)
//                    } else {
//                        var startOfRowSrc = src
//                        var startOfRowDst = dst
//                        for _ in 0..<height {
//                            memcpy(startOfRowDst, startOfRowSrc, min(bytesPerRowSrc, bytesPerRowDst))
//                            startOfRowSrc = startOfRowSrc?.advanced(by: bytesPerRowSrc)
//                            startOfRowDst = startOfRowDst?.advanced(by: bytesPerRowDst)
//                        }
//                    }
//                }
//            }
//        }
//    }
//
//    @inline(__always)
//    func lockBaseAddress(_ lockFlags: CVPixelBufferLockFlags = CVPixelBufferLockFlags.readOnly) throws {
//        let status = CVPixelBufferLockBaseAddress(self, lockFlags)
//        guard status == kCVReturnSuccess else {
//            throw Error.failedToLock(status)
//        }
//    }
//
//    @inline(__always)
//    func unlockBaseAddress(_ lockFlags: CVPixelBufferLockFlags = CVPixelBufferLockFlags.readOnly) throws {
//        let status = CVPixelBufferUnlockBaseAddress(self, lockFlags)
//        guard status == kCVReturnSuccess else {
//            throw Error.failedToUnlock(status)
//        }
//    }
//
//    func makeCIImage() throws -> CIImage {
//        try lockBaseAddress(.readOnly)
//        let result = CIImage(cvPixelBuffer: self)
//        try unlockBaseAddress(.readOnly)
//        return result
//    }
//
//    @inline(__always)
//    func mutate(_ lockFlags: CVPixelBufferLockFlags, lambda: (CVPixelBuffer) throws -> Void) throws {
//        let status = CVPixelBufferLockBaseAddress(self, lockFlags)
//        guard status == kCVReturnSuccess else {
//            throw Error.failedToLock(status)
//        }
//        defer {
//            CVPixelBufferUnlockBaseAddress(self, lockFlags)
//        }
//        try lambda(self)
//    }
//
//    @inlinable
//    @inline(__always)
//    func baseAddressOfPlane(_ index: Int) -> UnsafeMutableRawPointer? {
//        CVPixelBufferGetBaseAddressOfPlane(self, index)
//    }
//
//    @inlinable
//    @inline(__always)
//    func getHeightOfPlane(_ index: Int) -> Int {
//        CVPixelBufferGetHeightOfPlane(self, index)
//    }
//
//    @inlinable
//    @inline(__always)
//    func bytesPerRawOfPlane(_ index: Int) -> Int {
//        CVPixelBufferGetBytesPerRowOfPlane(self, index)
//    }
//}
