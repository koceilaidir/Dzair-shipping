import 'dart:async';

import 'dart:html' as html;
import 'dart:typed_data';

Future<(Uint8List, String, String)?> pickImage() async {
  final input = html.FileUploadInputElement()..accept = 'image/*';
  input.click();
  await input.onChange.first;
  final files = input.files;
  if (files == null || files.isEmpty) return null;
  final f = files.first;
  final reader = html.FileReader();
  reader.readAsArrayBuffer(f);
  await reader.onLoad.first;
  final res = reader.result;
  final bytes = res is Uint8List
      ? res
      : res is ByteBuffer
          ? Uint8List.view(res)
          : Uint8List.fromList((res as List).cast<int>());
  return (bytes, f.type.isNotEmpty ? f.type : 'image/jpeg', f.name);
}
