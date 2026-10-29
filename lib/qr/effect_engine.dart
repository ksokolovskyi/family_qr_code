import 'dart:math' as math;
import 'dart:ui';

import 'package:family_qr_code/qr/palettes.dart';
import 'package:family_qr_code/qr/qr_layout.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/foundation.dart';

/// Timings and sizes of every effect. Times are in seconds. Sizes are in card
/// units (the card is 1×1, so they match the recording regardless of the QR
/// version or the size on screen). Ripple speed is in cells.
abstract final class QrFx {
  // Brush splats.
  static const double splatRadius = 0.2;
  static const double splatSpacing = 0.035;
  static const double splatRestamp = 0.25;
  static const double splatAppear = 0.15;
  static const double splatGrow = 0.3;
  static const double splatHold = 0.6;
  static const double splatFade = 1;
  static const double splatLife = splatHold + splatFade;
  static const int maxSplats = 160;

  // Dots shrinking under the finger.
  static const double holeInner = 0.04;
  static const double holeOuter = 0.2;
  static const double holeEasing = 18;

  // Center ripple, fitted to the recording at 60 fps. A circular front
  // leaves the center at a constant speed (cells/s) and reaches every dot,
  // corners included. Each dot it passes collapses, regrows in the ripple
  // color (scale = progress ^ rippleRegrowExponent), holds the color, then
  // fades back to black.
  static const double rippleSpeed = 42;
  static const double rippleCollapse = 0.03;
  static const double rippleRegrowDelay = 0.105;
  static const double rippleRegrow = 0.19;
  static const double rippleRegrowExponent = 0.6;
  static const double rippleColorHold = 0.165;
  static const double rippleColorFade = 0.125;
  static const double rippleLife = 1.5;

  // Highlight envelopes (rise, hold, fade). Finders start fading in shortly
  // after the front reaches them, the logo is lit from the tap.
  static const double finderDelay = 0.09;
  static const double finderRise = 0.22;
  static const double finderHold = 0.33;
  static const double finderFade = 0.44;
  static const double logoHold = 0.69;
  static const double logoFade = 0.4;

  // Logo: shrinks and lights up as the finger gets close (distances from
  // the center), spins two full turns when a press that began on it is
  // released there (measured at 60 fps).
  static const double logoPressDepth = 0.21;
  static const double logoPressNear = 0.08;
  static const double logoPressFar = 0.17;
  static const double logoPressEasing = 18;
  static const double logoGlowNear = 0.12;
  static const double logoGlowFar = 0.21;
  static const double logoGlowEasing = 25;
  static const double logoGlowHold = 0.9;
  static const double logoGlowFade = 0.5;
  static const double spinDuration = 0.75;
  static const double spinAngle = 4 * math.pi;

  // Card tilt.
  static const double maxTilt = 8 * math.pi / 180;
  static const double brushPress = 0.98;
  static const double springStiffness = 300;
  static const double springDamping = 20;

  /// Logo hit area, relative to the logo width.
  static const double centerHitFactor = 0.6 * 1.2;
}

/// A soft circle of color stamped by the finger onto the layer below the dots.
class Splat {
  Splat(
    this.x,
    this.y,
    this.birth,
    this.palette,
  );

  /// Center.
  final double x;
  final double y;
  final double birth;
  final QrPalette palette;

  double age(double now) => now - birth;

  double radius(double now) {
    final t = (age(now) / QrFx.splatGrow).clamp(0.0, 1.0);
    return QrFx.splatRadius * Curves.easeOutCubic.transform(t);
  }

  double opacity(double now) {
    final a = age(now);
    if (a < 0) {
      return 0;
    }

    final appear = (a / QrFx.splatAppear).clamp(0.0, 1.0);
    if (a < QrFx.splatHold) {
      return appear;
    }

    final t = ((a - QrFx.splatHold) / QrFx.splatFade).clamp(0.0, 1.0);
    return 1 - Curves.easeInQuad.transform(t);
  }
}

/// A ripple started by a tap on the logo.
///
/// Every dot runs the same timeline, offset by when the front reaches it:
/// collapse, stay hidden, regrow in color, hold, fade back to black.
class Ripple {
  Ripple(
    this.birth,
    this.palette, {
    required this.speed,
    required this.maxRadius,
  });

  final double birth;
  final QrPalette palette;

  /// Front speed in card units per second.
  final double speed;

  /// Distance of the farthest dot. The ripple is over once it has passed.
  final double maxRadius;

  double age(double now) => now - birth;

  /// Seconds after the tap at which the front reaches distance [d].
  double reachTime(double d) => d / speed;

  /// Seconds since the front passed distance [d] (negative before).
  double sincePassed(double now, double d) => age(now) - reachTime(d);

  /// Scale of a dot at distance [d].
  double dotScale(double now, double d) {
    if (d > maxRadius) {
      return 1;
    }
    final u = sincePassed(now, d);
    if (u < 0) {
      return 1;
    }
    if (u < QrFx.rippleCollapse) {
      return 1 - u / QrFx.rippleCollapse;
    }

    final g = (u - QrFx.rippleRegrowDelay) / QrFx.rippleRegrow;
    if (g <= 0) {
      return 0;
    }
    if (g >= 1) {
      return 1;
    }

    return math.pow(g, QrFx.rippleRegrowExponent).toDouble();
  }

  /// Color strength of a dot at distance [d].
  double colorAt(double now, double d) {
    if (d > maxRadius) {
      return 0;
    }

    final u = sincePassed(now, d);
    if (u < QrFx.rippleRegrowDelay) {
      return 0;
    }

    const fadeStart = QrFx.rippleRegrowDelay + QrFx.rippleColorHold;
    if (u < fadeStart) {
      return 1;
    }

    return (1 - (u - fadeStart) / QrFx.rippleColorFade).clamp(0.0, 1.0);
  }

  /// Whether any dot still shows this ripple's color.
  bool hasColor(double now) {
    return sincePassed(now, maxRadius) <
            QrFx.rippleRegrowDelay +
                QrFx.rippleColorHold +
                QrFx.rippleColorFade &&
        age(now) > QrFx.rippleRegrowDelay;
  }
}

/// Underdamped spring (a small overshoot) for the card tilt and press.
class _Spring {
  _Spring(this.value) : target = value;

  double value;

  double target;

  double velocity = 0;

  void step(double dt) {
    final force =
        QrFx.springStiffness * (target - value) - QrFx.springDamping * velocity;
    velocity += force * dt;
    value += velocity * dt;
    if (settled) {
      value = target;
      velocity = 0;
    }
  }

  bool get settled => (target - value).abs() < 1e-4 && velocity.abs() < 1e-3;
}

double _smoothstep(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Linear rise, hold, then ease-in fade. 0 before [t] = 0.
double _envelope(double t, double rise, double hold, double fade) {
  if (t < 0) {
    return 0;
  }
  if (t < rise) {
    return t / rise;
  }
  final f = ((t - rise - hold) / fade).clamp(0.0, 1.0);
  return 1 - f * f;
}

/// Distance from ([x], [y]) to the closest point of [r] (0 inside).
double _distanceToRect(double x, double y, Rect r) {
  final dx = math.max(math.max(r.left - x, 0), x - r.right);
  final dy = math.max(math.max(r.top - y, 0), y - r.bottom);
  return math.sqrt(dx * dx + dy * dy);
}

/// Alpha of a splat's soft edge at [u] = distance / radius (0..1): solid to
/// 0.4, 40% at 0.75, clear at the rim.
double _splatProfile(double u) {
  if (u < 0.4) {
    return 1;
  }
  if (u < 0.75) {
    return 1 - 0.6 * (u - 0.4) / 0.35;
  }
  return 0.4 * (1 - u) / 0.25;
}

/// Index of the first value in ascending [list] that is >= [value].
int _lowerBound(Float32List list, double value) {
  var lo = 0;
  var hi = list.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (list[mid] < value) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

class _Notifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// All time-based state of the QR effects.
///
/// Time is passed in explicitly (seconds on any monotonic clock), so the
/// engine has no dependency on a ticker.
class EffectEngine extends ChangeNotifier {
  EffectEngine(this.layout)
    : scales = Float32List(layout.dotCount)..fillRange(0, layout.dotCount, 1),
      dotColors = Int32List(layout.dotCount)
        ..fillRange(0, layout.dotCount, _blackArgb),
      _brushScale = Float32List(layout.dotCount)
        ..fillRange(0, layout.dotCount, 1),
      _keep = Float32List(layout.dotCount),
      _red = Float32List(layout.dotCount),
      _green = Float32List(layout.dotCount),
      _blue = Float32List(layout.dotCount),
      _cx = layout.center.dx,
      _cy = layout.center.dy,
      finderColors = List.filled(layout.finders.length, _black),
      _finderReach = [
        for (final f in layout.finders) (f.center - layout.center).distance,
      ],
      _finderGradientT = [for (final f in layout.finders) f.center.dy],
      _paletteRgb = [
        for (final palette in qrPalettes) _rgbAtDots(palette, layout.dotY),
      ];

  /// [palette] at each of the heights [ys], as r, g, b triples (0..1).
  static Float32List _rgbAtDots(QrPalette palette, Float32List ys) {
    final rgb = Float32List(ys.length * 3);
    for (var i = 0; i < ys.length; i++) {
      final c = palette.at(ys[i]);
      rgb[i * 3] = c.r;
      rgb[i * 3 + 1] = c.g;
      rgb[i * 3 + 2] = c.b;
    }
    return rgb;
  }

  static const Color _black = Color(0xFF000000);
  static const int _blackArgb = 0xFF000000;

  final QrLayout layout;

  int _paletteIndex = 0;

  /// The current color: used by drags and by the next center ripple.
  QrPalette get palette => qrPalettes[_paletteIndex];

  double _now = 0;

  /// Time of the previous tick. Pointer events move [now] forward too, so
  /// frame deltas are measured from here instead.
  double? _lastTick;
  double get now => _now;

  final List<Splat> splats = [];
  final List<Ripple> ripples = [];

  /// Final per-dot scale to paint (brush hole × ripples).
  final Float32List scales;

  /// Final per-dot color to paint (ARGB): black with the splats and ripples
  /// composited on top, sampled at each dot's center.
  final Int32List dotColors;

  final Float32List _brushScale;
  bool _brushSettled = true;

  // Scratch buffers for compositing dot colors: the part of each dot one
  // palette leaves uncovered, and the running color.
  final Float32List _keep;
  final Float32List _red;
  final Float32List _green;
  final Float32List _blue;
  bool _colored = false;

  /// Each palette's color at every dot, in [qrPalettes] order. Dots never
  /// move, so this is worked out once.
  final List<Float32List> _paletteRgb;

  final double _cx;
  final double _cy;

  bool _down = false;
  double _px = 0;
  double _py = 0;
  double _stampX = 0;
  double _stampY = 0;
  double _lastStampTime = 0;

  /// Whether the current press began on the logo (a tap candidate).
  bool _pressedCenter = false;

  /// False for a press on the logo until the finger moves: a still finger on
  /// the logo only presses it, it doesn't paint.
  bool _brushing = false;

  /// How far the logo is pressed in, 0..1, eased toward the finger distance.
  double _logoPress = 0;

  /// How strongly the finger lights the logo, 0..1. It rises with
  /// proximity, holds after the finger moves away, then fades.
  double _logoGlow = 0;
  double _logoGlowHeldAt = 0;
  QrPalette? _logoGlowPalette;

  final List<Color> finderColors;

  /// Distance of each finder's center from the card center.
  final List<double> _finderReach;

  /// Where each finder's center sits on the vertical palette gradient.
  final List<double> _finderGradientT;

  Color logoColor = _black;
  Color logoSideColor = _black;
  double logoTheta = 0;
  double logoScale = 1;

  final _Spring _tiltX = _Spring(0);
  final _Spring _tiltY = _Spring(0);
  final _Spring _press = _Spring(1);

  /// Card rotation around the X axis (pitch), radians.
  double get tiltX => _tiltX.value;

  /// Card rotation around the Y axis (yaw), radians.
  double get tiltY => _tiltY.value;

  double get pressScale => _press.value;

  /// Notifies when anything painted inside the card changed. The engine
  /// itself notifies on every tick (the card tilt moves even when the
  /// content is still), this only when the content needs repainting.
  Listenable get repaint => _repaint;
  final _Notifier _repaint = _Notifier();
  bool _dirty = false;

  bool get isPointerDown => _down;

  bool get isAnimating =>
      _down ||
      splats.isNotEmpty ||
      ripples.isNotEmpty ||
      !_brushSettled ||
      _logoPress > 1e-3 ||
      _logoGlow > 0 ||
      !_tiltX.settled ||
      !_tiltY.settled ||
      !_press.settled;

  bool hitsCenter(Offset p) => _hitsCenter(p.dx, p.dy);

  bool _hitsCenter(double x, double y) {
    final dx = x - _cx;
    final dy = y - _cy;
    final r = layout.logoRect.width * QrFx.centerHitFactor;
    return dx * dx + dy * dy <= r * r;
  }

  /// Starts a press. On the logo it only presses the logo in, anywhere else
  /// it starts painting.
  void pointerDown(Offset p, double t) {
    _now = math.max(_now, t);
    _down = true;
    _px = p.dx;
    _py = p.dy;
    _pressedCenter = _hitsCenter(_px, _py);
    _brushing = !_pressedCenter;
    _stampX = _px;
    _stampY = _py;
    if (_brushing) _stampAt(_px, _py);
    _aimTilt();
    _press.target = QrFx.brushPress;
  }

  /// Moves the press. Any movement paints, including across the logo.
  void pointerMove(Offset p, double t) {
    if (!_down) {
      return;
    }
    _now = math.max(_now, t);
    final moved = p.dx != _px || p.dy != _py;
    _px = p.dx;
    _py = p.dy;
    if (!_brushing) {
      if (!moved) {
        return;
      }
      _brushing = true;
    }
    final fromX = _stampX;
    final fromY = _stampY;
    final dx = _px - fromX;
    final dy = _py - fromY;
    const spacing = QrFx.splatSpacing;
    final dist = math.sqrt(dx * dx + dy * dy);
    final count = (dist / spacing).floor();
    for (var i = 1; i <= count; i++) {
      final f = i * spacing / dist;
      _stampAt(fromX + dx * f, fromY + dy * f);
    }
    _aimTilt();
  }

  /// Ends the press. Returns true if it was a tap on the logo: it began on
  /// the logo and is released over it, which starts the ripple.
  bool pointerUp(double t) {
    _now = math.max(_now, t);
    final tapped = _down && _pressedCenter && _hitsCenter(_px, _py);
    _down = false;
    _pressedCenter = false;
    _brushing = false;
    _tiltX.target = 0;
    _tiltY.target = 0;
    _press.target = 1;
    if (tapped) _centerTap();
    return tapped;
  }

  /// Ends the press without a tap (the gesture was taken elsewhere).
  void pointerCancel(double t) {
    _pressedCenter = false;
    pointerUp(t);
  }

  void _centerTap() {
    ripples.add(
      Ripple(
        _now,
        palette,
        speed: QrFx.rippleSpeed * layout.cellSize,
        maxRadius: layout.maxRadius,
      ),
    );
    _paletteIndex = (_paletteIndex + 1) % qrPalettes.length;
    // From here the ripple decides how long the logo stays lit.
    _logoGlow = 0;
  }

  void _stampAt(double x, double y) {
    splats.add(Splat(x, y, _now, palette));
    if (splats.length > QrFx.maxSplats) splats.removeAt(0);
    _stampX = x;
    _stampY = y;
    _lastStampTime = _now;
  }

  void _aimTilt() {
    final nx = ((_px - _cx) * 2).clamp(-1.0, 1.0);
    final ny = ((_py - _cy) * 2).clamp(-1.0, 1.0);
    // Push the touched side away from the viewer.
    _tiltX.target = ny * QrFx.maxTilt;
    _tiltY.target = -nx * QrFx.maxTilt;
  }

  /// Advances every effect to time [t] and notifies listeners.
  void tick(double t) {
    final dt = (t - (_lastTick ?? t)).clamp(0.0, 1 / 20);
    _lastTick = t;
    _now = math.max(_now, t);

    if (_down && _brushing && _now - _lastStampTime >= QrFx.splatRestamp) {
      _stampAt(_px, _py);
    }
    splats.removeWhere((s) => s.age(_now) >= QrFx.splatLife);
    ripples.removeWhere((r) => r.age(_now) >= QrFx.rippleLife);

    _updateDots(dt);
    _updateColors();
    _updateFinders();
    _updateLogo(dt);

    _tiltX.step(dt);
    _tiltY.step(dt);
    _press.step(dt);

    notifyListeners();
    if (_dirty) {
      _dirty = false;
      _repaint.notify();
    }
  }

  @override
  void dispose() {
    _repaint.dispose();
    super.dispose();
  }

  void _updateDots(double dt) {
    final xs = layout.dotX;
    final ys = layout.dotY;
    final ds = layout.dotDist;
    final k = 1 - math.exp(-QrFx.holeEasing * dt);

    var settled = true;
    for (var i = 0; i < xs.length; i++) {
      var target = 1.0;
      if (_down) {
        final dx = xs[i] - _px;
        final dy = ys[i] - _py;
        target = _smoothstep(
          QrFx.holeInner,
          QrFx.holeOuter,
          math.sqrt(dx * dx + dy * dy),
        );
      }
      var b = _brushScale[i];
      b += (target - b) * k;
      if ((target - b).abs() < 1e-3) {
        b = target;
      } else {
        settled = false;
      }
      _brushScale[i] = b;

      var s = b;
      final d = ds[i];
      for (final r in ripples) {
        s *= r.dotScale(_now, d);
      }
      // Compare as stored: the list rounds to float32.
      final old = scales[i];
      scales[i] = s;
      if (scales[i] != old) _dirty = true;
    }
    _brushSettled = settled;
  }

  /// Composites the splats and ripples onto each dot, palette by palette in
  /// cycle order, the way layers of the color under the dots would blend.
  void _updateColors() {
    final n = layout.dotCount;
    if (splats.isEmpty && ripples.isEmpty) {
      if (_colored) {
        dotColors.fillRange(0, n, _blackArgb);
        _colored = false;
        _dirty = true;
      }
      return;
    }
    _colored = true;
    _dirty = true;

    final xs = layout.dotX;
    final ys = layout.dotY;
    final ds = layout.dotDist;
    _red.fillRange(0, n, 0);
    _green.fillRange(0, n, 0);
    _blue.fillRange(0, n, 0);

    for (var p = 0; p < qrPalettes.length; p++) {
      final palette = qrPalettes[p];
      var covered = false;
      for (final s in splats) {
        if (!identical(s.palette, palette)) continue;
        final r = s.radius(_now);
        final a = s.opacity(_now);
        if (r <= 0 || a <= 0) continue;
        if (!covered) {
          _keep.fillRange(0, n, 1);
          covered = true;
        }
        final r2 = r * r;
        // Dots are sorted by y, so only the rows the splat spans are read.
        final end = _lowerBound(ys, s.y + r);
        for (var i = _lowerBound(ys, s.y - r); i < end; i++) {
          final dx = xs[i] - s.x;
          if (dx * dx >= r2) continue;
          final dy = ys[i] - s.y;
          final d2 = dx * dx + dy * dy;
          if (d2 >= r2) continue;
          _keep[i] *= 1 - a * _splatProfile(math.sqrt(d2) / r);
        }
      }
      for (final r in ripples) {
        if (!identical(r.palette, palette) || !r.hasColor(_now)) continue;
        if (!covered) {
          _keep.fillRange(0, n, 1);
          covered = true;
        }
        for (var i = 0; i < n; i++) {
          _keep[i] *= 1 - r.colorAt(_now, ds[i]);
        }
      }
      if (!covered) continue;

      final rgb = _paletteRgb[p];
      for (var i = 0; i < n; i++) {
        final a = 1 - _keep[i];
        if (a <= 0) continue;
        final keep = 1 - a;
        _red[i] = _red[i] * keep + rgb[i * 3] * a;
        _green[i] = _green[i] * keep + rgb[i * 3 + 1] * a;
        _blue[i] = _blue[i] * keep + rgb[i * 3 + 2] * a;
      }
    }

    for (var i = 0; i < n; i++) {
      dotColors[i] =
          _blackArgb |
          (_red[i] * 255 + 0.5).toInt() << 16 |
          (_green[i] * 255 + 0.5).toInt() << 8 |
          (_blue[i] * 255 + 0.5).toInt();
    }
  }

  /// Strongest highlight of a shape with [bounds] at [reachDistance] from
  /// the center, as (intensity, palette).
  (double, QrPalette?) _highlight(
    Rect bounds,
    double reachDistance, {
    required double rise,
    required double hold,
    required double fade,
    required bool fromCenter,
    bool fromSplats = true,
  }) {
    var best = 0.0;
    QrPalette? bestPalette;
    for (final s in fromSplats ? splats : const <Splat>[]) {
      final r = s.radius(_now);
      if (_distanceToRect(s.x, s.y, bounds) <= r * 0.6) {
        final v = s.opacity(_now);
        if (v > best) {
          best = v;
          bestPalette = s.palette;
        }
      }
    }
    for (final r in ripples) {
      final start = fromCenter
          ? 0.0
          : r.reachTime(reachDistance) + QrFx.finderDelay;
      final v = _envelope(r.age(_now) - start, rise, hold, fade);
      if (v > best) {
        best = v;
        bestPalette = r.palette;
      }
    }
    return (best, bestPalette);
  }

  void _updateFinders() {
    for (var i = 0; i < layout.finders.length; i++) {
      final f = layout.finders[i];
      final (v, p) = _highlight(
        f.bounds,
        _finderReach[i],
        rise: QrFx.finderRise,
        hold: QrFx.finderHold,
        fade: QrFx.finderFade,
        fromCenter: false,
      );
      final color = p == null
          ? _black
          : Color.lerp(_black, p.at(_finderGradientT[i]), v)!;
      if (color != finderColors[i]) {
        finderColors[i] = color;
        _dirty = true;
      }
    }
  }

  void _updateLogo(double dt) {
    final dx = _px - _cx;
    final dy = _py - _cy;
    final distance = _down ? math.sqrt(dx * dx + dy * dy) : double.infinity;

    final pressTarget =
        1 - _smoothstep(QrFx.logoPressNear, QrFx.logoPressFar, distance);
    final k = 1 - math.exp(-QrFx.logoPressEasing * dt);
    _logoPress += (pressTarget - _logoPress) * k;
    if ((pressTarget - _logoPress).abs() < 1e-3) _logoPress = pressTarget;

    final glowTarget =
        1 - _smoothstep(QrFx.logoGlowNear, QrFx.logoGlowFar, distance);
    if (glowTarget > 0 && glowTarget >= _logoGlow - 1e-3) {
      final rise = 1 - math.exp(-QrFx.logoGlowEasing * dt);
      _logoGlow += (glowTarget - _logoGlow) * rise;
      if ((glowTarget - _logoGlow).abs() < 1e-3) _logoGlow = glowTarget;
      _logoGlowHeldAt = _now;
      _logoGlowPalette = palette;
    } else if (_now - _logoGlowHeldAt > QrFx.logoGlowHold) {
      _logoGlow = math.max(glowTarget, _logoGlow - dt / QrFx.logoGlowFade);
    }
    if (_logoGlow < 1e-3) _logoGlow = 0;

    // The ripple lights the logo too, and the stronger light wins.
    var (v, p) = _highlight(
      layout.logoRect,
      0,
      rise: 0,
      hold: QrFx.logoHold,
      fade: QrFx.logoFade,
      fromCenter: true,
      fromSplats: false,
    );
    if (_logoGlow > v) {
      v = _logoGlow;
      p = _logoGlowPalette;
    }
    final color = p == null ? _black : Color.lerp(_black, p.at(0.5), v)!;
    final scale = 1 - QrFx.logoPressDepth * _logoPress;
    var theta = 0.0;
    if (ripples.isNotEmpty) {
      final spin = ripples.last.age(_now) / QrFx.spinDuration;
      if (spin < 1) {
        theta = Curves.easeOutQuad.transform(spin) * QrFx.spinAngle;
      }
    }
    if (color != logoColor || scale != logoScale || theta != logoTheta) {
      _dirty = true;
    }
    logoColor = color;
    // The original draws the coin edge in the face color: one solid blob.
    logoSideColor = color;
    logoScale = scale;
    logoTheta = theta;
  }
}
