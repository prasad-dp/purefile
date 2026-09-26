import 'dart:io';
import 'dart:typed_data';

/// File-type detection by magic bytes, not by trusting extensions.
/// Catches renamed junk (edge case #6/#7 in docs/edge-cases.md).
enum PfMagic { pdf, png, jpeg, webp, gif, zip, heic, unknown }

PfMagic sniffMagic(Uint8List head) {
  bool startsWith(String s, int offset) {
    if (head.length < offset + s.length) return false;
    for (var i = 0; i < s.length; i++) {
      if (head[offset + i] != s.codeUnitAt(i)) return false;
    }
    return true;
  }

  if (startsWith('%PDF', 0)) return PfMagic.pdf;
  if (head.length >= 4 && head[0] == 0x89 && head[1] == 0x50 && head[2] == 0x4E && head[3] == 0x47) {
    return PfMagic.png;
  }
  if (head.length >= 3 && head[0] == 0xFF && head[1] == 0xD8 && head[2] == 0xFF) {
    return PfMagic.jpeg;
  }
  if (startsWith('RIFF', 0) && startsWith('WEBP', 8)) return PfMagic.webp;
  if (startsWith('GIF8', 0)) return PfMagic.gif;
  if (startsWith('PK\x03\x04', 0) || startsWith('PK\x05\x06', 0) || startsWith('PK\x07\x08', 0)) {
    return PfMagic.zip;
  }
  if (startsWith('ftyp', 4)) {
    final brand = String.fromCharCodes(head.sublist(8, head.length >= 12 ? 12 : head.length));
    if (brand == 'heic' || brand == 'heix' || brand == 'mif1' || brand == 'hevc') {
      return PfMagic.heic;
    }
  }
  return PfMagic.unknown;
}

/// Reads only the first bytes of a large file (cheap even on 50 MB inputs).
Future<PfMagic> sniffFileMagic(String path) async {
  final raf = File(path).openSync();
  try {
    final head = Uint8List.sublistView(raf.readSync(16));
    return sniffMagic(head);
  } finally {
    raf.closeSync();
  }
}

/// Extensions accepted by tools, mapped to their expected magic types.
const Map<String, Set<PfMagic>> kPfExtensionMagic = {
  'pdf': {PfMagic.pdf},
  'png': {PfMagic.png},
  'jpg': {PfMagic.jpeg},
  'jpeg': {PfMagic.jpeg},
  'webp': {PfMagic.webp},
  'gif': {PfMagic.gif},
  'zip': {PfMagic.zip},
  'heic': {PfMagic.heic},
  'heif': {PfMagic.heic},
};

Set<PfMagic>? magicForExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return null;
  return kPfExtensionMagic[fileName.substring(dot + 1).toLowerCase()];
}
