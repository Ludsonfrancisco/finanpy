import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../domain/import_preview.dart';

/// The bytes of a chosen statement. The real file name never crosses here.
final class SelectedOfx {
  const SelectedOfx(this.bytes);

  final Uint8List bytes;

  @override
  String toString() => 'SelectedOfx(${bytes.lengthInBytes} bytes)';
}

abstract interface class OfxFilePicker {
  Future<SelectedOfx?> pick();
}

/// The part of a native selection this feature is allowed to inspect.
abstract interface class PickedFile {
  String get name;
  Future<int> length();
  Future<Uint8List> readAsBytes();
}

typedef PickOfxFile = Future<PickedFile?> Function();

final class FilePickerOfxPicker implements OfxFilePicker {
  FilePickerOfxPicker({PickOfxFile? pickFile})
    : _pickFile = pickFile ?? _pickWithNativeDialog;

  final PickOfxFile _pickFile;

  @override
  Future<SelectedOfx?> pick() async {
    final file = await _pickFile();
    if (file == null) return null;
    if (!_hasOfxExtension(file.name)) {
      throw const ImportFailure(ImportFailureKind.unsupportedFile);
    }
    if (await file.length() > maxOfxBytes) {
      throw const ImportFailure(ImportFailureKind.fileTooLarge);
    }
    final bytes = await file.readAsBytes();
    if (bytes.lengthInBytes > maxOfxBytes) {
      throw const ImportFailure(ImportFailureKind.fileTooLarge);
    }
    if (bytes.isEmpty) {
      throw const ImportFailure(ImportFailureKind.invalidFile);
    }
    return SelectedOfx(bytes);
  }

  bool _hasOfxExtension(String name) =>
      name.trim().toLowerCase().endsWith('.ofx');
}

/// Uses the document picker only. No broad storage permission is requested.
Future<PickedFile?> _pickWithNativeDialog() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const <String>['ofx'],
  );
  return file == null ? null : _NativePickedFile(file);
}

final class _NativePickedFile implements PickedFile {
  const _NativePickedFile(this._file);

  final PlatformFile _file;

  @override
  String get name => _file.name;

  @override
  Future<int> length() => _file.length();

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();
}
