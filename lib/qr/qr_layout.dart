import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:family_qr_code/qr/family_logo.dart';
import 'package:qr/qr.dart';

/// One of the three finder (position) patterns, drawn as a single shape: a
/// ring ([outer] minus [hole]) around a solid [inner] square.
///
/// All three parts are squircles (continuous-corner rounded squares, as in
/// iOS), not circular-corner rounded rects.
class FinderShape {
  FinderShape({
    required this.outer,
    required this.hole,
    required this.inner,
  }) : ring = Path()
         ..fillType = PathFillType.evenOdd
         ..addRSuperellipse(outer)
         ..addRSuperellipse(hole);

  final RSuperellipse outer;
  final RSuperellipse hole;
  final RSuperellipse inner;

  /// The ring, `outer - hole`, built once (there is no squircle version of
  /// [Canvas.drawDRRect]).
  final Path ring;

  Rect get bounds => outer.outerRect;
  Offset get center => bounds.center;
}

/// Static geometry of the QR code: where every dot, finder and the logo sit.
///
/// Everything is in card units: the card is the unit square, from (0, 0) to
/// (1, 1), whatever size it is shown at. The painter scales it to the real
/// size, so resizing never rebuilds the layout.
///
/// Dot data is stored in flat typed lists so the effect engine can iterate it
/// every frame without allocating.
class QrLayout {
  QrLayout._({
    required this.moduleCount,
    required this.cellSize,
    required this.dotX,
    required this.dotY,
    required this.dotDist,
    required this.finders,
    required this.logoRect,
    required this.logoPath,
  });

  /// Builds the layout for [data].
  ///
  /// The Family app shows a version 4 (33×33) code. Pass `minVersion: 4` to
  /// get the same grid for a 42-character address. The default level is M:
  /// the original uses L, but with a plain logo cut-out L does not reliably
  /// scan, while M does at the same grid size.
  factory QrLayout.from(
    String data, {
    QrErrorCorrectLevel errorCorrectLevel = QrErrorCorrectLevel.medium,
    int minVersion = 1,
  }) {
    final code = QrCode(
      payload: QrPayload.fromString(data),
      errorCorrectLevel: errorCorrectLevel,
      minTypeNumber: minVersion,
    );
    final n = code.moduleCount;

    const padding = cardPaddingFraction;
    final cell = (1 - padding * 2) / n;
    const origin = Offset(padding, padding);
    const center = Offset(0.5, 0.5);

    // Centered square of cells cleared for the logo. Always odd so it is
    // symmetric around the middle module.
    var clear = (n * logoClearFraction).round();
    if (clear.isEven) clear += 1;
    final clearStart = (n - clear) ~/ 2;
    final clearEnd = clearStart + clear;

    final clearRect = Rect.fromLTWH(
      origin.dx + clearStart * cell,
      origin.dy + clearStart * cell,
      clear * cell,
      clear * cell,
    );
    final logoRect = clearRect.deflate(cell * logoMargin);
    final logoPath = familyLogoPath(logoRect);

    // A scanner reads the cut-out as it is drawn: cells under the black logo
    // as dark, the margin and the logo's hole as light. Every mismatch with
    // the real module is a read error, so pick the mask with the fewest.
    //
    // The logo is measured on the grid (one unit per cell). Some cell centers
    // sit exactly on the logo's outline. Sampling just around each center
    // counts those as half covered instead of leaving them to rounding.
    final gridLogo = familyLogoPath(
      Rect.fromLTWH(
        clearStart.toDouble(),
        clearStart.toDouble(),
        clear.toDouble(),
        clear.toDouble(),
      ).deflate(logoMargin),
    );
    const sample = 0.01;
    final coverage = Float64List(clear * clear);
    for (var r = 0; r < clear; r++) {
      for (var c = 0; c < clear; c++) {
        final x = clearStart + c + 0.5;
        final y = clearStart + r + 0.5;
        var inside = 0;
        for (final (dx, dy) in const [(-1, -1), (1, -1), (-1, 1), (1, 1)]) {
          if (gridLogo.contains(Offset(x + dx * sample, y + dy * sample))) {
            inside++;
          }
        }
        coverage[r * clear + c] = inside / 4;
      }
    }

    double logoErrors(QrImage image) {
      var errors = 0.0;
      for (var r = 0; r < clear; r++) {
        for (var c = 0; c < clear; c++) {
          final covered = coverage[r * clear + c];
          final dark = image.isDark(clearStart + r, clearStart + c);
          errors += dark ? 1 - covered : covered;
        }
      }
      return errors;
    }

    var image = QrImage.withMaskPattern(code, 0);
    var fewest = logoErrors(image);
    for (var mask = 1; mask < 8; mask++) {
      final candidate = QrImage.withMaskPattern(code, mask);
      final errors = logoErrors(candidate);
      if (errors < fewest) {
        image = candidate;
        fewest = errors;
      }
    }

    bool isFinderCell(int r, int c) =>
        (r < 7 && c < 7) || (r < 7 && c >= n - 7) || (r >= n - 7 && c < 7);
    bool isLogoCell(int r, int c) =>
        r >= clearStart && r < clearEnd && c >= clearStart && c < clearEnd;

    final xs = <double>[];
    final ys = <double>[];
    final ds = <double>[];
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (!image.isDark(r, c) || isFinderCell(r, c) || isLogoCell(r, c)) {
          continue;
        }
        final p = origin + Offset((c + 0.5) * cell, (r + 0.5) * cell);
        xs.add(p.dx);
        ys.add(p.dy);
        ds.add((p - center).distance);
      }
    }

    FinderShape finderAt(int row, int col) {
      final o = origin + Offset(col * cell, row * cell);
      final outer = Rect.fromLTWH(o.dx, o.dy, cell * 7, cell * 7);
      return FinderShape(
        outer: RSuperellipse.fromRectAndRadius(
          outer,
          Radius.circular(cell * finderOuterRadius),
        ),
        hole: RSuperellipse.fromRectAndRadius(
          outer.deflate(cell * finderRing),
          Radius.circular(cell * finderHoleRadius),
        ),
        inner: RSuperellipse.fromRectAndRadius(
          outer.deflate(cell * (7 - finderInner) / 2),
          Radius.circular(cell * finderInnerRadius),
        ),
      );
    }

    return QrLayout._(
      moduleCount: n,
      cellSize: cell,
      dotX: Float32List.fromList(xs),
      dotY: Float32List.fromList(ys),
      dotDist: Float32List.fromList(ds),
      finders: [finderAt(0, 0), finderAt(0, n - 7), finderAt(n - 7, 0)],
      logoRect: logoRect,
      logoPath: logoPath,
    );
  }

  static const Rect cardRect = Rect.fromLTWH(0, 0, 1, 1);

  static const double cardRadius = 0.11;

  /// Fraction of the card size used as white margin around the QR grid.
  static const double cardPaddingFraction = 0.075;

  /// Fraction of the grid (per side) cleared for the logo: 9 of 33 cells,
  /// as in the recording.
  static const double logoClearFraction = 0.27;

  /// Empty cells between the cleared zone's edge and the logo.
  static const double logoMargin = 1.5;

  /// Dot diameter relative to the cell size.
  static const double dotFraction = 0.72;

  // Finder proportions in cells, measured from the recording.
  static const double finderRing = 0.75;
  static const double finderInner = 3.1;
  static const double finderOuterRadius = 2;
  static const double finderHoleRadius = 1.3;
  static const double finderInnerRadius = 0.6;

  final int moduleCount;

  final double cellSize;

  /// Dot centers, row by row (so sorted by y).
  final Float32List dotX;
  final Float32List dotY;

  /// Distance of each dot from the card center.
  final Float32List dotDist;

  /// Top-left, top-right, bottom-left.
  final List<FinderShape> finders;

  final Rect logoRect;

  final Path logoPath;

  int get dotCount => dotX.length;
  Offset get center => cardRect.center;
  double get dotRadius => cellSize * dotFraction / 2;

  /// Distance from the center to the card corner, as far as ripples travel.
  double get maxRadius => math.sqrt2 / 2;
}
