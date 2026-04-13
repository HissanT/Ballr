import CoreML
import Foundation
import Vision

struct BallTrackerResources {
    let config: BallTrackerConfig
    let metadataURL: URL
    let modelURL: URL

    func makeVisionModel() throws -> VNCoreMLModel {
        let resolvedModelURL: URL
        switch modelURL.pathExtension.lowercased() {
        case "mlmodelc":
            resolvedModelURL = modelURL
        case "mlmodel", "mlpackage":
            do {
                resolvedModelURL = try MLModel.compileModel(at: modelURL)
            } catch {
                throw BallTrackerConfigError.modelCompileFailed(error)
            }
        default:
            resolvedModelURL = modelURL
        }

        do {
            let configuration = MLModelConfiguration()
            let model = try MLModel(contentsOf: resolvedModelURL, configuration: configuration)
            return try VNCoreMLModel(for: model)
        } catch {
            throw BallTrackerConfigError.modelLoadFailed(error)
        }
    }
}

struct BallTrackerConfig: Decodable {
    static let resourceBaseName = "ballr_v4_tune_cleaned"

    struct Input: Decodable {
        let shape: [Int]
    }

    struct RuntimeDefaults: Decodable {
        let confidenceThreshold: Double
        let iouThreshold: Double
        let ballClassID: Int

        enum CodingKeys: String, CodingKey {
            case confidenceThreshold = "confidence_threshold"
            case iouThreshold = "iou_threshold"
            case ballClassID = "ball_class_id"
        }
    }

    struct FrontendNotes: Decodable {
        let visionCropAndScale: String
        let passCaptureOrientation: Bool
        let mirrorPreviewOnly: Bool
        let mapBoxesBackToPreview: Bool

        enum CodingKeys: String, CodingKey {
            case visionCropAndScale = "vision_crop_and_scale"
            case passCaptureOrientation = "pass_capture_orientation"
            case mirrorPreviewOnly = "mirror_preview_only"
            case mapBoxesBackToPreview = "map_boxes_back_to_preview"
        }
    }

    struct Export: Decodable {
        let imgsz: Int?
    }

    let input: Input
    let ballrRuntimeDefaults: RuntimeDefaults
    let frontendNotes: FrontendNotes
    let export: Export

    enum CodingKeys: String, CodingKey {
        case input
        case ballrRuntimeDefaults = "ballr_runtime_defaults"
        case frontendNotes = "frontend_notes"
        case export
    }

    var inputImageSize: Int {
        export.imgsz ?? input.shape.last ?? 768
    }

    var visionCropAndScaleOption: VNImageCropAndScaleOption {
        switch frontendNotes.visionCropAndScale.lowercased() {
        case "centercrop":
            return .centerCrop
        case "scalefill":
            return .scaleFill
        default:
            return .scaleFit
        }
    }

    static func load(from bundle: Bundle = .main) throws -> BallTrackerResources {
        guard let metadataURL = bundle.url(forResource: resourceBaseName, withExtension: "json") else {
            throw BallTrackerConfigError.missingMetadata
        }

        let config: BallTrackerConfig
        do {
            let decoder = JSONDecoder()
            let data = try Data(contentsOf: metadataURL)
            config = try decoder.decode(Self.self, from: data)
        } catch {
            throw BallTrackerConfigError.invalidMetadata(error)
        }

        guard
            let modelURL = bundle.url(forResource: resourceBaseName, withExtension: "mlmodelc")
            ?? bundle.url(forResource: resourceBaseName, withExtension: "mlpackage")
            ?? bundle.url(forResource: resourceBaseName, withExtension: "mlmodel")
        else {
            throw BallTrackerConfigError.missingModelArtifact
        }

        return BallTrackerResources(
            config: config,
            metadataURL: metadataURL,
            modelURL: modelURL
        )
    }
}

enum BallTrackerConfigError: LocalizedError {
    case missingMetadata
    case invalidMetadata(Error)
    case missingModelArtifact
    case modelCompileFailed(Error)
    case modelLoadFailed(Error)

    var errorDescription: String? {
        switch self {
        case .missingMetadata:
            return "Missing `ballr_v4_tune_cleaned.json` in the app bundle."
        case .invalidMetadata(let error):
            return "Unable to decode the ball tracker metadata: \(error.localizedDescription)"
        case .missingModelArtifact:
            return "Missing `ballr_v4_tune_cleaned` CoreML model in the app bundle."
        case .modelCompileFailed(let error):
            return "Unable to prepare the bundled CoreML package: \(error.localizedDescription)"
        case .modelLoadFailed(let error):
            return "Unable to load the bundled CoreML model: \(error.localizedDescription)"
        }
    }
}
