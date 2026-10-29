import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/rendering.dart' show Matrix4;

/// The Family mark: a ring of eight merged circles (3×3 grid minus the
/// middle) around a rounded-square hole.
///
/// The outline is traced directly from circle arcs instead of built with
/// [Path.combine], which gives wrong results on the web (the hole is lost).
Path familyLogoPath(Rect rect) {
  final w = rect.width;
  final step = w / 3;
  final r = step / 2;

  // Neighboring circles touch, so going clockwise the outline is one arc per
  // circle: 270° around each corner, 180° along each edge middle.
  Rect circle(int col, int row) => Rect.fromCircle(
    center: rect.topLeft + Offset(r + col * step, r + row * step),
    radius: r,
  );
  const quarter = math.pi / 2;
  final path = Path()
    ..fillType = PathFillType.evenOdd
    ..moveTo(rect.left + r, rect.top + step)
    ..arcTo(circle(0, 0), quarter, 3 * quarter, false)
    ..arcTo(circle(1, 0), 2 * quarter, 2 * quarter, false)
    ..arcTo(circle(2, 0), 2 * quarter, 3 * quarter, false)
    ..arcTo(circle(2, 1), 3 * quarter, 2 * quarter, false)
    ..arcTo(circle(2, 2), 3 * quarter, 3 * quarter, false)
    ..arcTo(circle(1, 2), 0, 2 * quarter, false)
    ..arcTo(circle(0, 2), 0, 3 * quarter, false)
    ..arcTo(circle(0, 1), quarter, 2 * quarter, false)
    ..close();

  // Even-odd fill turns this inner contour into the hole.
  return path..addRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: rect.center, width: w * 0.44, height: w * 0.44),
      Radius.circular(w * 0.06),
    ),
  );
}

/// Paints [logo] (built for [rect]) spun by [theta] radians around the
/// vertical axis in perspective, extruded so it reads as a thick coin.
///
/// Front face uses [color], the sides and back use [sideColor]. [paint] is
/// reused for every slice, and its color is overwritten. [pixelsPerUnit] is how
/// many logical pixels one unit of [rect] covers on screen, so the edge gets
/// enough slices at any size.
void paintSpinningLogo(
  Canvas canvas, {
  required Path logo,
  required Rect rect,
  required double theta,
  required double scale,
  required Color color,
  required Color sideColor,
  required Paint paint,
  double pixelsPerUnit = 1,
}) {
  final cx = rect.center.dx;
  final cy = rect.center.dy;
  final depth = rect.width * 0.22;
  // In the recording the near edge of the spinning logo looks ~13% taller
  // than the face, which puts the eye about 4.3 logo widths away.
  final perspective = 1 / (rect.width * 4.3);

  // Never turn a face fully edge-on, so the edge-on view stays a solid pill.
  var angle = theta;
  final cosT = math.cos(angle);
  if (cosT.abs() < 0.04) {
    final edge = math.acos(0.04);
    final turn = (angle / math.pi).floorToDouble() * math.pi;
    angle = turn + (angle - turn < math.pi / 2 ? edge : math.pi - edge);
  }
  final sinT = math.sin(angle);

  // The coin is a slab from z = -depth/2 (front, towards the viewer) to
  // +depth/2 (back), drawn as stacked slices of the logo shape. A slice at
  // z is front × translateZ(z × scale) × back. Back is affine, so the
  // product only differs between slices in its last column, by z × scale
  // times front's z column.
  final front = Matrix4.translationValues(cx, cy, 0)
    ..multiply(Matrix4.identity()..setEntry(3, 2, perspective))
    // Push the coin back so its face at rest sits at z = 0: same size as
    // when it's not spinning.
    ..translateByDouble(0, 0, depth / 2 * scale, 1)
    // Negative: the right edge swings toward the viewer first, as in the
    // original.
    ..rotateY(-angle);
  final back = Matrix4.diagonal3Values(scale, scale, 1)
    ..translateByDouble(-cx, -cy, 0, 1);
  final base = front.multiplied(back).storage;
  final zColumn = front.storage;
  final m = Float64List(16);

  void slice(double z) {
    m.setAll(0, base);
    final k = z * scale;
    for (var r = 0; r < 4; r++) {
      m[12 + r] += k * zColumn[8 + r];
    }
    canvas
      ..save()
      ..transform(m)
      ..drawPath(logo, paint)
      ..restore();
  }

  if (sinT.abs() > 0.01) {
    // Enough slices that neighbors overlap (under ~0.5 px apart), so the
    // edge reads as one solid band instead of stripes.
    paint.color = sideColor;
    final spread = depth * sinT.abs() * scale * pixelsPerUnit;
    final slices = (spread / 0.5).ceil().clamp(10, 64);
    for (var i = slices; i > 0; i--) {
      slice(-depth / 2 + depth * i / slices);
    }
  }
  paint.color = color;
  slice(-depth / 2);
}
