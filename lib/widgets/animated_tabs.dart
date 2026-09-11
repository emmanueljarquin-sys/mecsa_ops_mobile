// =============================================================================
// animated_tabs.dart — Cambio de pestaña con animación, conservando estado
// -----------------------------------------------------------------------------
// Reemplaza al IndexedStack del shell. Mantiene TODAS las pestañas montadas
// (scroll, formularios y mapas no se reinician) y al cambiar de índice hace
// un deslizamiento corto + desvanecido en la dirección del movimiento
// (derecha si la nueva pestaña está a la derecha, izquierda en caso
// contrario). Las pestañas no visibles quedan en Offstage con TickerMode
// apagado, igual que hacía IndexedStack.
// =============================================================================
import 'package:flutter/material.dart';

class AnimatedTabs extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const AnimatedTabs({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 280),
  });

  @override
  State<AnimatedTabs> createState() => _AnimatedTabsState();
}

class _AnimatedTabsState extends State<AnimatedTabs>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: widget.duration);
  int? _prev;
  int _dir = 1;

  @override
  void initState() {
    super.initState();
    _ctrl.value = 1;
    _ctrl.addStatusListener((st) {
      if (st == AnimationStatus.completed && _prev != null) {
        setState(() => _prev = null);
      }
    });
  }

  @override
  void didUpdateWidget(covariant AnimatedTabs old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _prev = old.index;
      _dir = widget.index > old.index ? 1 : -1;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curva = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (int i = 0; i < widget.children.length; i++)
          _capa(i, curva),
      ],
    );
  }

  Widget _capa(int i, Animation<double> curva) {
    final bool esActual = i == widget.index;
    final bool esPrevia = i == _prev;
    final bool visible = esActual || esPrevia;

    Widget child = widget.children[i];
    if (esActual) {
      child = FadeTransition(
        opacity: curva,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset(0.06 * _dir, 0),
            end: Offset.zero,
          ).animate(curva),
          child: child,
        ),
      );
    } else if (esPrevia) {
      child = IgnorePointer(
        child: FadeTransition(
          opacity: ReverseAnimation(curva),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset.zero,
              end: Offset(-0.06 * _dir, 0),
            ).animate(curva),
            child: child,
          ),
        ),
      );
    }

    return Offstage(
      offstage: !visible,
      child: TickerMode(enabled: visible, child: child),
    );
  }
}
