import 'package:flutter/material.dart';

/// PureFile tool registry — the single source of truth for the home grid.
///
/// Every tool the app will ship. Features 1+ implement the actual pipelines;
/// unimplemented tools render with a "coming in this build" state until their
/// feature lands (docs/plan.md — build order).
enum PfCategory { pdf, image, zip, scan, ocr, sign, vault }

extension PfCategoryColor on PfCategory {
  Color get color => switch (this) {
        PfCategory.pdf => const Color(0xFFE11D48),
        PfCategory.image => const Color(0xFF7C3AED),
        PfCategory.zip => const Color(0xFFD97706),
        PfCategory.scan => const Color(0xFF059669),
        PfCategory.ocr => const Color(0xFF2563EB),
        PfCategory.sign => const Color(0xFFDB2777),
        PfCategory.vault => const Color(0xFF475569),
      };
}

enum ToolStatus { available, planned }

class PfTool {
  const PfTool({
    required this.id,
    required this.route,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.icon,
    this.status = ToolStatus.planned,
  });

  final String id;
  final String route;
  final String title;
  final String subtitle;
  final PfCategory category;
  final IconData icon;
  final ToolStatus status;
}

const List<PfTool> kPfTools = [
  // PDF.
  PfTool(
    id: 'pdf_compress',
    route: '/tools/pdf-compress',
    title: 'Compress PDF',
    subtitle: 'Make PDFs smaller',
    category: PfCategory.pdf,
    icon: Icons.compress_rounded,
  ),
  PfTool(
    id: 'pdf_merge',
    route: '/tools/pdf-merge',
    title: 'Merge PDF',
    subtitle: 'Combine PDFs & images',
    category: PfCategory.pdf,
    icon: Icons.merge_rounded,
  ),
  PfTool(
    id: 'pdf_split',
    route: '/tools/pdf-split',
    title: 'Split PDF',
    subtitle: 'Ranges, extract, every N',
    category: PfCategory.pdf,
    icon: Icons.call_split_rounded,
  ),
  PfTool(
    id: 'images_to_pdf',
    route: '/tools/images-to-pdf',
    title: 'Images to PDF',
    subtitle: 'JPG/PNG/HEIC → PDF',
    category: PfCategory.pdf,
    icon: Icons.picture_as_pdf_rounded,
  ),
  PfTool(
    id: 'pdf_to_images',
    route: '/tools/pdf-to-images',
    title: 'PDF to Images',
    subtitle: 'Pages → JPG/PNG',
    category: PfCategory.pdf,
    icon: Icons.image_outlined,
  ),
  // Images.
  PfTool(
    id: 'image_compress',
    route: '/tools/image-compress',
    title: 'Compress Images',
    subtitle: 'Batch, quality slider',
    category: PfCategory.image,
    icon: Icons.photo_size_select_large_rounded,
  ),
  PfTool(
    id: 'image_convert',
    route: '/tools/image-convert',
    title: 'Convert Image',
    subtitle: 'JPG ↔ PNG ↔ WebP',
    category: PfCategory.image,
    icon: Icons.swap_horiz_rounded,
  ),
  // ZIP.
  PfTool(
    id: 'zip_create',
    route: '/tools/zip-create',
    title: 'Create ZIP',
    subtitle: 'Pack any files',
    category: PfCategory.zip,
    icon: Icons.folder_zip_rounded,
  ),
  PfTool(
    id: 'zip_extract',
    route: '/tools/zip-extract',
    title: 'Extract ZIP',
    subtitle: 'Browse & unpack',
    category: PfCategory.zip,
    icon: Icons.drive_file_move_outline,
  ),
  // Unique layer.
  PfTool(
    id: 'scan',
    route: '/tools/scan',
    title: 'Scan Document',
    subtitle: 'Camera → clean PDF',
    category: PfCategory.scan,
    icon: Icons.document_scanner_rounded,
    status: ToolStatus.available,
  ),
  PfTool(
    id: 'sign',
    route: '/tools/sign',
    title: 'Sign & Stamp',
    subtitle: 'Draw, place, flatten',
    category: PfCategory.sign,
    icon: Icons.draw_rounded,
    status: ToolStatus.available,
  ),
  PfTool(
    id: 'ocr',
    route: '/tools/ocr',
    title: 'OCR Text',
    subtitle: 'Searchable PDF + text',
    category: PfCategory.ocr,
    icon: Icons.text_snippet_rounded,
    status: ToolStatus.available,
  ),
  PfTool(
    id: 'vault',
    route: '/tools/vault',
    title: 'Private Vault',
    subtitle: 'Biometric + encrypted',
    category: PfCategory.vault,
    icon: Icons.lock_rounded,
    status: ToolStatus.available,
  ),
];
