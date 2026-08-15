import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lar_finance/features/imports/data/ofx_file_picker.dart';
import 'package:lar_finance/features/imports/domain/import_preview.dart';

void main() {
  group('FilePickerOfxPicker', () {
    test('a cancelled dialog selects nothing', () async {
      final picker = FilePickerOfxPicker(pickFile: () async => null);

      expect(await picker.pick(), isNull);
    });

    test('a file without the ofx extension is refused', () async {
      final picker = FilePickerOfxPicker(
        pickFile: () async => _FakePickedFile(
          name: 'extrato.pdf',
          bytes: Uint8List.fromList(const <int>[1, 2, 3]),
        ),
      );

      await expectLater(
        picker.pick(),
        throwsA(
          isA<ImportFailure>().having(
            (failure) => failure.kind,
            'kind',
            ImportFailureKind.unsupportedFile,
          ),
        ),
      );
    });

    test('an oversized file is refused before its bytes are read', () async {
      final file = _FakePickedFile(
        name: 'extrato.ofx',
        bytes: Uint8List.fromList(const <int>[1]),
        reportedLength: maxOfxBytes + 1,
      );
      final picker = FilePickerOfxPicker(pickFile: () async => file);

      await expectLater(
        picker.pick(),
        throwsA(
          isA<ImportFailure>().having(
            (failure) => failure.kind,
            'kind',
            ImportFailureKind.fileTooLarge,
          ),
        ),
      );
      expect(file.readCalls, 0);
    });

    test('an empty file is refused', () async {
      final picker = FilePickerOfxPicker(
        pickFile: () async =>
            _FakePickedFile(name: 'extrato.ofx', bytes: Uint8List(0)),
      );

      await expectLater(
        picker.pick(),
        throwsA(
          isA<ImportFailure>().having(
            (failure) => failure.kind,
            'kind',
            ImportFailureKind.invalidFile,
          ),
        ),
      );
    });

    test('a selection carries bytes and never the real file name', () async {
      final picker = FilePickerOfxPicker(
        pickFile: () async => _FakePickedFile(
          name: 'Nubank_2026-08-15_conta.ofx',
          bytes: Uint8List.fromList(const <int>[79, 70, 88]),
        ),
      );

      final selected = await picker.pick();

      expect(selected, isNotNull);
      expect(selected!.bytes, <int>[79, 70, 88]);
      expect(selected.toString(), isNot(contains('Nubank')));
      expect(selected.toString(), isNot(contains('.ofx')));
    });

    test('the extension check ignores case and surrounding spaces', () async {
      final picker = FilePickerOfxPicker(
        pickFile: () async => _FakePickedFile(
          name: 'Extrato.OFX',
          bytes: Uint8List.fromList(const <int>[1]),
        ),
      );

      expect((await picker.pick())?.bytes, <int>[1]);
    });
  });
}

final class _FakePickedFile implements PickedFile {
  _FakePickedFile({
    required this.name,
    required Uint8List bytes,
    int? reportedLength,
  }) : _bytes = bytes,
       _reportedLength = reportedLength ?? bytes.lengthInBytes;

  @override
  final String name;

  final Uint8List _bytes;
  final int _reportedLength;
  int readCalls = 0;

  @override
  Future<int> length() async => _reportedLength;

  @override
  Future<Uint8List> readAsBytes() async {
    readCalls++;
    return _bytes;
  }
}
