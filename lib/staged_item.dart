import 'dart:io';
import 'package:path/path.dart' as p;

/// Defines the category of the file to determine how it's handled 
/// and displayed in the Staging Area.
enum NemoFileType { image, video, document, unknown }

/// Defines the current state of the file in the encryption pipeline.
enum StagingStatus { pending, encrypting, sealed, error }

class StagedItem {
  final File file;
  final String id;
  final String fileName;
  final int fileSize;
  final NemoFileType fileType;
  
  // High-Level Controls
  bool shouldStripMetadata;
  StagingStatus status;
  double progress; // 0.0 to 1.0
  String? errorMessage;

  /// 🔱 Primary Constructor: Used when files are first picked in the UI.
  /// Fix: ID is now derived from the file path to prevent duplicate "Ghosts".
  StagedItem({
    required this.file,
    this.shouldStripMetadata = true, 
    this.status = StagingStatus.pending,
    this.progress = 0.0,
    this.errorMessage,
  })  : id = file.path.hashCode.toString(), 
        fileName = p.basename(file.path),
        fileSize = file.existsSync() ? file.lengthSync() : 0,
        fileType = _determineFileType(file.path);

  /// 🔱 Internal Constructor: Required to maintain state across Isolate boundaries.
  StagedItem._internal({
    required this.file,
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.fileType,
    required this.shouldStripMetadata,
    required this.status,
    required this.progress,
    this.errorMessage,
  });

  /// 🔱 Serialization: Converts object to a Map to pass through Isolate SendPort.
  Map<String, dynamic> toMap() {
    return {
      'path': file.path,
      'id': id,
      'fileName': fileName,
      'fileSize': fileSize,
      'fileTypeIndex': fileType.index,
      'shouldStripMetadata': shouldStripMetadata,
      'statusIndex': status.index,
      'progress': progress,
      'errorMessage': errorMessage,
    };
  }

  /// 🔱 Deserialization: Rebuilds the object inside the Background Worker Isolate.
  static StagedItem fromMap(Map<String, dynamic> map) {
    return StagedItem._internal(
      file: File(map['path']),
      id: map['id'],
      fileName: map['fileName'],
      fileSize: map['fileSize'],
      fileType: NemoFileType.values[map['fileTypeIndex']],
      shouldStripMetadata: map['shouldStripMetadata'],
      status: StagingStatus.values[map['statusIndex']],
      progress: map['progress'],
      errorMessage: map['errorMessage'],
    );
  }

  static NemoFileType _determineFileType(String path) {
    final ext = p.extension(path).toLowerCase();
    const imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.heic'};
    const videoExtensions = {'.mp4', '.mov', '.avi', '.mkv', '.wmv'};
    const docExtensions = {'.pdf', '.txt', '.doc', '.docx', '.xlsx', '.pptx'};

    if (imageExtensions.contains(ext)) return NemoFileType.image;
    if (videoExtensions.contains(ext)) return NemoFileType.video;
    if (docExtensions.contains(ext)) return NemoFileType.document;
    return NemoFileType.unknown;
  }

  String get readableSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1048576) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    if (fileSize < 1073741824) return '${(fileSize / 1048576).toStringAsFixed(1)} MB';
    return '${(fileSize / 1073741824).toStringAsFixed(1)} GB';
  }

  /// 🔱 Updated copyWith: Maintained for clean state transitions.
  StagedItem copyWith({
    StagingStatus? status,
    double? progress,
    bool? shouldStripMetadata,
    String? errorMessage,
  }) {
    return StagedItem._internal(
      file: file,
      id: id, 
      fileName: fileName,
      fileSize: fileSize,
      fileType: fileType,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      shouldStripMetadata: shouldStripMetadata ?? this.shouldStripMetadata,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  // 🔱 EQUALITY OVERRIDES
  // These ensure that the app treats two StagedItem objects as the same 
  // if they point to the same physical file.
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StagedItem && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}