import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:family_qr_code/qr/effect_engine.dart';
import 'package:family_qr_code/qr/family_logo.dart';
import 'package:family_qr_code/qr/qr_layout.dart';
import 'package:flutter/rendering.dart';

/// The white anti-aliased circle every dot is drawn from, kept at the
/// resolution the dots are shown at.
///
/// It is rendered at twice the device size of a full dot, so dots are always
/// minified a little and stay smooth, and recreated only when that size
/// changes by a whole pixel.
class DotSprite {
  ui.Image? _image;

  /// Transparent pixels around the circle, so sampling at the edge never
  /// clamps into it.
  static const double padding = 1;

  /// The sprite for dots of [radius] device pixels.
  ui.Image resolve(double radius) {
    final side = (radius * 2 * 2).ceil().clamp(16, 256) + 2;
    final image = _image;
    if (image != null && image.width == side) {
      return image;
    }

    image?.dispose();

    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawCircle(
      Offset(side / 2, side / 2),
      side / 2 - padding,
      Paint()..color = const Color(0xFFFFFFFF),
    );

    return _image = recorder.endRecording().toImageSync(side, side);
  }

  void dispose() {
    _image?.dispose();
    _image = null;
  }
}

/// Paints the QR card from [layout] and the current state of [engine].
///
/// The card is drawn in card units, scaled to the largest square that fits
/// the paint size and centered in it.
///
/// The engine composites the color under the dots into one color per dot,
/// so every dot is drawn in a single atlas call: a white circle sprite
/// tinted per dot and scaled per dot. No layers, no gradients.
class QrPainter extends CustomPainter {
  QrPainter(
    this.layout,
    this.engine,
    this.sprite,
    this.devicePixelRatio,
  ) : _transforms = Float32List(layout.dotCount * 4),
      _rects = Float32List(layout.dotCount * 4),
      _colors = Int32List(layout.dotCount),
      super(repaint: engine.repaint);

  final QrLayout layout;
  final EffectEngine engine;
  final DotSprite sprite;

  /// Only used for the sprite resolution.
  final double devicePixelRatio;

  static final RSuperellipse _cardShape = RSuperellipse.fromRectAndRadius(
    QrLayout.cardRect,
    const Radius.circular(QrLayout.cardRadius),
  );

  // Atlas buffers, packed with the visible dots only.
  final Float32List _transforms;
  final Float32List _rects;
  final Int32List _colors;

  final Paint _cardPaint = Paint()..color = const Color(0xFFFFFFFF);
  final Paint _dotPaint = Paint()..filterQuality = FilterQuality.medium;
  final Paint _finderPaint = Paint();
  final Paint _logoPaint = Paint();

  /// Where the card sits in a paint area of [size]: the largest centered
  /// square, in logical pixels.
  static Rect cardIn(Size size) {
    final side = size.shortestSide;
    return Rect.fromLTWH(
      (size.width - side) / 2,
      (size.height - side) / 2,
      side,
      side,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final card = cardIn(size);
    if (card.isEmpty) {
      return;
    }

    canvas
      ..save()
      ..translate(card.left, card.top)
      ..scale(card.width)
      ..drawRSuperellipse(_cardShape, _cardPaint);

    _drawDots(canvas, card.width);

    for (var i = 0; i < layout.finders.length; i++) {
      final f = layout.finders[i];
      _finderPaint.color = engine.finderColors[i];
      canvas
        ..drawPath(f.ring, _finderPaint)
        ..drawRSuperellipse(f.inner, _finderPaint);
    }

    paintSpinningLogo(
      canvas,
      logo: layout.logoPath,
      rect: layout.logoRect,
      theta: engine.logoTheta,
      scale: engine.logoScale,
      color: engine.logoColor,
      sideColor: engine.logoSideColor,
      paint: _logoPaint,
      pixelsPerUnit: card.width,
    );

    canvas.restore();
  }

  void _drawDots(Canvas canvas, double side) {
    final image = sprite.resolve(layout.dotRadius * side * devicePixelRatio);
    final xs = layout.dotX;
    final ys = layout.dotY;
    final scales = engine.scales;
    final colors = engine.dotColors;
    final spriteSide = image.width.toDouble();
    final half = spriteSide / 2;
    // Sprite pixels to card units for a full-size dot.
    final unit = layout.dotRadius / (half - DotSprite.padding);

    // Hidden dots are left out: a zero-scale transform breaks the atlas on
    // some backends.
    var count = 0;
    for (var i = 0; i < xs.length; i++) {
      final s = scales[i];
      if (s < 0.02) continue;
      final k = unit * s;
      final j = count * 4;
      _transforms[j] = k;
      _transforms[j + 2] = xs[i] - k * half;
      _transforms[j + 3] = ys[i] - k * half;
      _rects[j + 2] = spriteSide;
      _rects[j + 3] = spriteSide;
      _colors[count] = colors[i];
      count++;
    }

    if (count == 0) {
      return;
    }

    canvas.drawRawAtlas(
      image,
      Float32List.sublistView(_transforms, 0, count * 4),
      Float32List.sublistView(_rects, 0, count * 4),
      Int32List.sublistView(_colors, 0, count),
      BlendMode.modulate,
      QrLayout.cardRect,
      _dotPaint,
    );
  }

  @override
  bool shouldRepaint(QrPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.engine != engine ||
        oldDelegate.sprite != sprite ||
        oldDelegate.devicePixelRatio != devicePixelRatio;
  }
}
