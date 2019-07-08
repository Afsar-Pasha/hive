import 'dart:typed_data';

import 'package:hive/src/binary/binary_reader_impl.dart';
import 'package:hive/src/crypto_helper.dart';
import 'package:hive/src/hive_instance_impl.dart';
import 'package:hive/src/io/buffered_file_reader.dart';
import 'package:hive/src/io/frame.dart';
import 'package:hive/src/registry/type_registry_impl.dart';
import 'package:test/test.dart';

import 'common.dart';

get registry => TypeRegistryImpl();

const testFrames = [
  Frame.tombstone("Tombstone frame"),
  Frame("Null frame", null),
  Frame("Int", 123123123),
  Frame("Large int", 2 ^ 32),
  Frame("This is true", true),
  Frame("This is not true", false),
  Frame("Float1", 1232312.9912838261),
  Frame("Float2", double.nan),
  Frame("Unicode string",
      "A few characters which are not ASCII: 🇵🇬 😀 🐝 걟 ＄ 乽 👨‍🚀"),
  Frame("Empty list", []),
  Frame("Int list", [123, 456, 129318238]),
  Frame("Bool list", [true, false, false, true]),
  Frame("Double list", [
    10.1723812,
    double.infinity,
    double.maxFinite,
    double.minPositive,
    double.negativeInfinity
  ]),
  Frame("String list", [
    "hello",
    "🧙‍♂️ 👨‍👨‍👧‍👦 ",
    " ﻬ ﻭ ﻮ ﻯ ﻰ ﻱ",
    "അ ആ ഇ ",
    " צּ קּ רּ שּ ",
    "ｩ ｪ ｫ ｬ ｭ ｮ ｯ ｰ "
  ]),
  Frame("List with null", ["This", "is", "a", "test", null]),
  Frame("List with different types", [
    "List",
    [1, 2, 3],
    5.8,
    true,
    12341234,
    {"t": true, "f": false},
  ]),
  Frame("Map", {
    "Bool": true,
    "Int": 1234,
    "Double": 15.7,
    "String": "Hello",
    "List": [1, 2, null],
    "Null": null,
    "Map": {"Key": "Val", "Key2": 2}
  }),
];

void buildGoldens() async {
  var name = 0;
  for (var frame in testFrames) {
    var file = await getAssetFile("frames", (name++).toString());
    await file.create(recursive: true);
    var frameBytes = frame.toBytes(registry);
    await file.writeAsBytes(frameBytes);
  }
}

void expectFramesEqual(Frame f1, Frame f2) {
  expect(f1.key, f2.key);
  expect(f1.deleted, f2.deleted);
  expect(f1.error, f2.error);
  if (f1.value is double && f2.value is double) {
    if (f1.value.isNaN && f1.value.isNaN) return;
  }
  expect(f1.value, f2.value);
}

void main() {
  group("toBytes", () {
    test('key length', () async {
      var tooLongKey = List.filled(256, 'a').join();
      var tooLongFrame = Frame(tooLongKey, 5);
      expect(
        () => tooLongFrame.toBytes(registry),
        throwsA(anything),
      );

      var validKey = List.filled(255, 'a').join();
      var frame = Frame(validKey, 5);
      frame.toBytes(registry);
    });

    test('golden frames', () async {
      var name = 0;
      for (var frame in testFrames) {
        var file = await getTempAssetFile("frames", "${name++}");
        var bytes = await frame.toBytes(registry);
        expect(bytes, await file.readAsBytes());
      }
    });
  });

  group("fromReader", () {
    test('golden frames', () async {
      var name = 0;
      for (var goldenFrame in testFrames) {
        var file = await getTempAssetFile("frames", "${name++}");
        var reader = await BufferedFileReader.fromFile(file);
        var frame = await Frame.fromReader(
          (bytes) => reader.read(bytes),
          registry,
          readValue: true,
        );
        expect(frame.error, null);
        expect(frame.length, await file.length());
        expectFramesEqual(frame, goldenFrame);
      }
    });

    test('eof', () async {
      var emptyFile = await getTempFile();
      var reader = await BufferedFileReader.fromFile(emptyFile);
      var frame = await Frame.fromReader(
        reader.read,
        registry,
        readValue: true,
      );
      expect(frame.error, FrameError.eof);
      expect(frame.key, null);
      expect(frame.value, null);
      expect(frame.deleted, null);
      expect(frame.length, null);
    });
  });

  test("encryption / decryption", () async {
    var key = HiveInstanceImpl().generateSecureKey();
    var crypto = CryptoHelper(Uint8List.fromList(key));
    for (var frame in testFrames) {
      var bytes = frame.toBytes(registry, encryptor: crypto.encryptor);
      var decryptedFrame = await Frame.fromReader(
        ByteListReader(bytes).read,
        registry,
        decryptor: crypto.decryptor,
      );

      expectFramesEqual(frame, decryptedFrame);
    }
  });
}