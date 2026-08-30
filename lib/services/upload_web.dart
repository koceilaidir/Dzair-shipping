import 'dart:async';
import 'dart:convert';
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

Future<(Uint8List, String)> compresserImage(Uint8List bytes, String mime,
    {int maxCote = 1600, double qualite = 0.82}) async {
  try {
    final blob = html.Blob([bytes], mime);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final img = html.ImageElement(src: url);
    await img.onLoad.first.timeout(const Duration(seconds: 12));
    final w = img.naturalWidth, h = img.naturalHeight;
    html.Url.revokeObjectUrl(url);
    if (w <= 0 || h <= 0) return (bytes, mime);
    final plusGrand = w > h ? w : h;
    final echelle = plusGrand > maxCote ? maxCote / plusGrand : 1.0;
    final nw = (w * echelle).round(), nh = (h * echelle).round();
    final canvas = html.CanvasElement(width: nw, height: nh);
    canvas.context2D.drawImageScaled(img, 0, 0, nw, nh);
    final dataUrl = canvas.toDataUrl('image/jpeg', qualite);
    final b64 = dataUrl.substring(dataUrl.indexOf(',') + 1);
    final sortie = base64Decode(b64);
    return sortie.length < bytes.length || echelle < 1.0
        ? (sortie, 'image/jpeg')
        : (bytes, mime);
  } catch (_) {
    return (bytes, mime);
  }
}
