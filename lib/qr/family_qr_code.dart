import 'dart:math' as math;

import 'package:family_qr_code/qr/effect_engine.dart';
import 'package:family_qr_code/qr/qr_layout.dart';
import 'package:family_qr_code/qr/qr_painter.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:qr/qr.dart';

/// An interactive QR code in the style of the Family wallet.
///
/// * Touch or drag anywhere: paints fading color through the dots and tilts
///   the card toward the finger.
/// * Tap the logo: spins it, sends a color ripple to the edges, highlights
///   the finders, then switches to the next color.
///
/// The card is always square and sizes itself like [AspectRatio]: it takes
/// the largest square its parent allows, at most [size] when that is set.
/// With no bound at all (say, in a scroll view's cross axis inside another
/// scroll view) it falls back to [size], or [fallbackSize].
class FamilyQrCode extends StatefulWidget {
  const FamilyQrCode({
    required this.data,
    this.size,
    this.errorCorrectLevel = QrErrorCorrectLevel.medium,
    this.minVersion = 1,
    super.key,
  });

  final String data;

  /// Preferred side of the card, in logical pixels. The card shrinks below
  /// it when its parent has less room. When null, the card fills the space.
  final double? size;

  /// Lowest level that still scans with the logo cut out (see [QrLayout.from]).
  final QrErrorCorrectLevel errorCorrectLevel;

  /// Smallest QR version to use (1–40). Version 4 is 33×33 modules.
  final int minVersion;

  /// Side used when neither [size] nor the parent bounds the card.
  static const double fallbackSize = 300;

  @override
  State<FamilyQrCode> createState() => _FamilyQrCodeState();
}

class _FamilyQrCodeState extends State<FamilyQrCode>
    with SingleTickerProviderStateMixin {
  late QrLayout _layout;
  late EffectEngine _engine;
  final DotSprite _sprite = DotSprite();
  QrPainter? _painter;
  late final Ticker _ticker = createTicker(_onTick);
  int? _pointer;

  /// Side of the card on screen when the last pointer event came in, for
  /// the tilt perspective. The tilt only moves after a pointer event.
  double _cardSide = FamilyQrCode.fallbackSize;

  /// How strong the tilt perspective is, relative to the card size.
  static const double _perspective = 0.3;

  // Effect time follows the frame clock: the ticker's elapsed time on top of
  // everything accumulated before it last stopped. Idle gaps don't count.
  double _timeBase = 0;
  Duration _elapsed = Duration.zero;

  double get _time =>
      _timeBase + _elapsed.inMicroseconds / Duration.microsecondsPerSecond;

  @override
  void initState() {
    super.initState();
    _createEngine();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updatePainter();
  }

  @override
  void didUpdateWidget(FamilyQrCode oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The size only changes how the card is scaled, so it keeps its state.
    if (oldWidget.data != widget.data ||
        oldWidget.errorCorrectLevel != widget.errorCorrectLevel ||
        oldWidget.minVersion != widget.minVersion) {
      _engine.dispose();
      _pointer = null;
      _createEngine();
      _updatePainter();
    }
  }

  void _createEngine() {
    _layout = QrLayout.from(
      widget.data,
      errorCorrectLevel: widget.errorCorrectLevel,
      minVersion: widget.minVersion,
    );
    _engine = EffectEngine(_layout);
    _painter = null;
  }

  /// Keeps the painter matched to the engine and the screen density.
  void _updatePainter() {
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    if (_painter?.devicePixelRatio != ratio) _painter = null;
    _painter ??= QrPainter(_layout, _engine, _sprite, ratio);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sprite.dispose();
    _engine.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    _elapsed = elapsed;
    _engine.tick(_time);
    if (!_engine.isAnimating) {
      _ticker.stop();
      _timeBase = _time;
      _elapsed = Duration.zero;
    }
  }

  void _wake() {
    if (!_ticker.isActive) _ticker.start();
  }

  /// [local] (logical pixels in this widget) in card units.
  Offset _toCard(Offset local) {
    final box = context.findRenderObject()! as RenderBox;
    final card = QrPainter.cardIn(box.size);
    _cardSide = card.width;
    return (local - card.topLeft) / card.width;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_pointer != null) {
      return;
    }
    final p = _toCard(event.localPosition);
    // Presses beside the card (when the parent forces a non-square box)
    // don't count.
    if (!QrLayout.cardRect.contains(p)) {
      return;
    }
    _pointer = event.pointer;
    _engine.pointerDown(p, _time);
    _wake();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _engine.pointerMove(_toCard(event.localPosition), _time);
    _wake();
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    if (_engine.pointerUp(_time)) HapticFeedback.lightImpact();
    _wake();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointer = null;
    _engine.pointerCancel(_time);
    _wake();
  }

  Matrix4 _tiltMatrix() => Matrix4.identity()
    ..setEntry(3, 2, _perspective / _cardSide)
    ..rotateX(_engine.tiltX)
    ..rotateY(_engine.tiltY)
    ..scaleByDouble(_engine.pressScale, _engine.pressScale, 1, 1);

  @override
  Widget build(BuildContext context) {
    // The Listener sits outside the Transform so pointer positions are in
    // untilted card coordinates.
    return _SquareBox(
      size: widget.size,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: ListenableBuilder(
          listenable: _engine,
          builder: (context, child) => Transform(
            alignment: Alignment.center,
            transform: _tiltMatrix(),
            child: child,
          ),
          child: RepaintBoundary(child: CustomPaint(painter: _painter)),
        ),
      ),
    );
  }
}

/// Sizes its child to the largest square the constraints allow, at most
/// [size]. When they allow any size, it uses [size] or
/// [FamilyQrCode.fallbackSize].
///
/// Like [AspectRatio] with a cap, except that only a fully unbounded parent
/// gets the fallback: in a [Column], the card still fills the width.
class _SquareBox extends SingleChildRenderObjectWidget {
  const _SquareBox({
    required this.size,
    super.child,
  });

  final double? size;

  @override
  _RenderSquareBox createRenderObject(BuildContext context) =>
      _RenderSquareBox(size);

  @override
  void updateRenderObject(BuildContext context, _RenderSquareBox renderObject) {
    renderObject.preferred = size;
  }
}

class _RenderSquareBox extends RenderProxyBox {
  _RenderSquareBox(this._preferred);

  double? _preferred;
  double? get preferred => _preferred;
  set preferred(double? value) {
    if (value == _preferred) {
      return;
    }
    _preferred = value;
    markNeedsLayout();
  }

  /// The side when the parent sets no limit.
  double get _unbounded => _preferred ?? FamilyQrCode.fallbackSize;

  Size _sizeFor(BoxConstraints constraints) {
    var side = math.min(constraints.maxWidth, constraints.maxHeight);
    if (side.isInfinite) side = _unbounded;
    if (_preferred != null) side = math.min(side, _preferred!);
    // Tight constraints win, even when they are not square. The painter
    // centers the card in whatever box it gets.
    return constraints.constrain(Size.square(side));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _sizeFor(constraints);

  @override
  void performLayout() {
    size = _sizeFor(constraints);
    child?.layout(BoxConstraints.tight(size));
  }

  /// A square's side for a given length of the other axis.
  double _sideFor(double other) =>
      other.isFinite ? math.min(other, _preferred ?? other) : _unbounded;

  @override
  double computeMinIntrinsicWidth(double height) => _sideFor(height);

  @override
  double computeMaxIntrinsicWidth(double height) => _sideFor(height);

  @override
  double computeMinIntrinsicHeight(double width) => _sideFor(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _sideFor(width);
}
