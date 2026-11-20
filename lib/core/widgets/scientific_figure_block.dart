import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Read-only textbook-style scientific figures embedded in structured course pages.
///
/// Examples:
/// {"type":"graph","function":"exp","x_min":-4,"x_max":3,"y_min":-1,"y_max":8}
/// {"type":"diagram","diagram_kind":"circle","caption":"Cercle de centre O"}
/// {"type":"diagram","diagram_kind":"plant_cell"}
class ScientificFigureBlock extends StatelessWidget {
  const ScientificFigureBlock({
    super.key,
    required this.block,
    required this.isEnglish,
    this.fontSize = 16,
  });

  final Map<String, dynamic> block;
  final bool isEnglish;
  final double fontSize;

  String _value(String key, String fallback) =>
      (block[key] ?? fallback).toString();

  @override
  Widget build(BuildContext context) {
    final type = _value('type', 'diagram').toLowerCase();
    final isGraph = type == 'graph' || type == 'function_graph' || type == 'chart';
    final kind = isGraph
        ? _value('function', _value('name', 'exp')).toLowerCase()
        : _value('diagram_kind', _value('kind', _value('name', 'circle'))).toLowerCase();
    final language = isEnglish ? 'en' : 'fr';
    final title = _value(
      'title_$language',
      _value('title', isGraph
          ? (isEnglish ? 'Function graph' : 'Courbe représentative')
          : (isEnglish ? 'Scientific diagram' : 'Schéma scientifique')),
    );
    final caption = _value('caption_$language', _value('caption', ''));

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 14),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFB8CBE8)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x0B17365D), blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(
            color: const Color(0xFF17365D),
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
          )),
          const SizedBox(height: 8),
          SizedBox(
            height: isGraph ? 280 : 300,
            width: double.infinity,
            child: CustomPaint(
              painter: _ScientificPainter(
                kind: kind,
                graph: isGraph,
                block: block,
                isEnglish: isEnglish,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          if (caption.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(caption, textAlign: TextAlign.center, style: TextStyle(
              color: const Color(0xFF475569),
              fontSize: fontSize - 2,
              height: 1.35,
            )),
          ],
        ],
      ),
    );
  }
}

class _ScientificPainter extends CustomPainter {
  _ScientificPainter({
    required this.kind,
    required this.graph,
    required this.block,
    required this.isEnglish,
  });

  final String kind;
  final bool graph;
  final Map<String, dynamic> block;
  final bool isEnglish;

  static const navy = Color(0xFF17365D);
  static const blue = Color(0xFF2476D2);
  static const green = Color(0xFF16834A);
  static const red = Color(0xFFD14343);
  static const grey = Color(0xFF64748B);
  static const grid = Color(0xFFE2EAF3);

  double _number(String key, double fallback) {
    final value = block[key];
    return value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;
  }

  void _label(Canvas canvas, String value, Offset at, {
    Color color = navy, double size = 11, bool bold = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: TextStyle(
        color: color, fontSize: size,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      )),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: 130);
    painter.paint(canvas, at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (graph) {
      _paintGraph(canvas, size);
    } else {
      switch (kind) {
        case 'circle':
        case 'geometry_circle':
        case 'unit_circle':
        case 'trigonometric_circle':
          _paintCircle(canvas, size, unit: kind == 'unit_circle' || kind == 'trigonometric_circle');
          break;
        case 'triangle':
        case 'right_triangle':
        case 'geometry_triangle':
          _paintTriangle(canvas, size, right: kind == 'right_triangle');
          break;
        case 'plant_cell':
        case 'animal_cell':
        case 'cell':
          _paintCell(canvas, size, plant: kind == 'plant_cell');
          break;
        case 'circuit':
        case 'electric_circuit':
          _paintCircuit(canvas, size);
          break;
        case 'lens':
        case 'converging_lens':
        case 'optics':
          _paintLens(canvas, size);
          break;
        case 'geom_square':
        case 'square':
          _paintSquare(canvas, size);
          break;
        case 'geom_parallel':
        case 'parallel_lines':
          _paintParallel(canvas, size);
          break;
        case 'geom_coordinate':
        case 'coordinate_plane':
          _paintCoordinate(canvas, size);
          break;
        case 'geom_cube':
        case 'cube':
          _paintCube(canvas, size);
          break;
        case 'geom_pyramid':
        case 'pyramid':
          _paintPyramid(canvas, size);
          break;
        case 'geom_cylinder':
        case 'cylinder':
          _paintCylinder(canvas, size);
          break;
        case 'geom_prism':
        case 'prism':
          _paintPrism(canvas, size);
          break;
        case 'gravity_pair':
          _paintGravityPair(canvas, size);
          break;
        case 'gravity_altitude':
          _paintGravityAltitude(canvas, size);
          break;
        case 'weight':
          _paintWeight(canvas, size);
          break;
        case 'svt_neuron':
        case 'neuron':
          _paintNeuron(canvas, size);
          break;
        case 'svt_synapse':
        case 'synapse':
          _paintSynapse(canvas, size);
          break;
        default:
          _paintPlaceholder(canvas, size);
      }
    }
  }

  void _paintGraph(Canvas canvas, Size size) {
    const left = 38.0, top = 14.0;
    final right = size.width - 14, bottom = size.height - 30;
    final xMin = _number('x_min', -5), xMax = _number('x_max', 5);
    final defaultYMax = kind == 'exp' || kind == 'exponential' ? 8.0 : 5.0;
    final yMin = _number('y_min', -5), yMax = _number('y_max', defaultYMax);
    if (xMax <= xMin || yMax <= yMin) {
      _label(canvas, isEnglish ? 'Invalid graph range' : 'Intervalle de tracé invalide', const Offset(12, 20), color: red);
      return;
    }
    final plot = Rect.fromLTRB(left, top, right, bottom);
    final paintGrid = Paint()..color = grid..strokeWidth = 1;
    final axis = Paint()..color = navy..strokeWidth = 1.6;
    Offset map(double x, double y) => Offset(
      left + (x - xMin) / (xMax - xMin) * plot.width,
      bottom - (y - yMin) / (yMax - yMin) * plot.height,
    );
    for (var i = 0; i <= 10; i++) {
      final x = left + plot.width * i / 10;
      final y = top + plot.height * i / 10;
      canvas.drawLine(Offset(x, top), Offset(x, bottom), paintGrid);
      canvas.drawLine(Offset(left, y), Offset(right, y), paintGrid);
    }
    if (xMin <= 0 && xMax >= 0) canvas.drawLine(map(0, yMin), map(0, yMax), axis);
    if (yMin <= 0 && yMax >= 0) canvas.drawLine(map(xMin, 0), map(xMax, 0), axis);
    _label(canvas, 'x', Offset(right - 3, bottom + 7), bold: true);
    _label(canvas, 'y', Offset(left - 22, top - 4), bold: true);
    if (xMin <= 0 && xMax >= 0 && yMin <= 0 && yMax >= 0) {
      _label(canvas, 'O', map(0, 0) + const Offset(4, 4), size: 9);
    }

    final a = _number('a', 1), b = _number('b', 0), c = _number('c', 0);
    double f(double x) {
      switch (kind) {
        case 'exp':
        case 'exponential': return math.exp(x);
        case 'ln':
        case 'log':
        case 'logarithm': return x > 0 ? math.log(x) : double.nan;
        case 'sin':
        case 'sine': return math.sin(x);
        case 'cos':
        case 'cosine': return math.cos(x);
        case 'tan':
        case 'tangent': return math.tan(x);
        case 'sqrt':
        case 'square_root': return x >= 0 ? math.sqrt(x) : double.nan;
        case 'quadratic':
        case 'parabola': return a*x*x + b*x + c;
        case 'linear':
        case 'line': return a*x + b;
        case 'inverse': return x.abs() < 0.0001 ? double.nan : a/x;
        case 'absolute':
        case 'abs': return (a*x + b).abs();
        default: return double.nan;
      }
    }
    final curve = Path();
    var started = false;
    const samples = 500;
    for (var i = 0; i <= samples; i++) {
      final x = xMin + (xMax - xMin) * i / samples;
      final y = f(x);
      if (!y.isFinite || y < yMin - (yMax-yMin) || y > yMax + (yMax-yMin)) {
        started = false;
        continue;
      }
      final boundedY = y.clamp(yMin - (yMax-yMin), yMax + (yMax-yMin)).toDouble();
      final point = map(x, boundedY);
      if (!started) {
        curve.moveTo(point.dx, point.dy);
        started = true;
      } else {
        curve.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(curve, Paint()
      ..color = blue..style = PaintingStyle.stroke..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    if (kind == 'exp' || kind == 'exponential') {
      final p = map(0, 1);
      canvas.drawCircle(p, 4, Paint()..color = red);
      _label(canvas, '(0 ; 1)', p + const Offset(6, -17), color: red, size: 10);
    }
    _label(canvas, 'f(x)', Offset(left + 8, top + 5), color: blue, bold: true);
  }

  void _paintCircle(Canvas canvas, Size size, {required bool unit}) {
    final center = Offset(size.width * .48, size.height * .53);
    final radius = math.min(size.width * .29, size.height * .36);
    final stroke = Paint()..color = blue..style = PaintingStyle.stroke..strokeWidth = 2.4;
    canvas.drawCircle(center, radius, stroke);
    canvas.drawLine(Offset(center.dx-radius-18, center.dy), Offset(center.dx+radius+18, center.dy),
      Paint()..color = grey..strokeWidth = 1.2);
    canvas.drawLine(Offset(center.dx, center.dy-radius-18), Offset(center.dx, center.dy+radius+18),
      Paint()..color = grey..strokeWidth = 1.2);
    canvas.drawLine(center, Offset(center.dx+radius*.72, center.dy-radius*.69),
      Paint()..color = red..strokeWidth = 2.2);
    canvas.drawCircle(center, 3.5, Paint()..color = navy);
    _label(canvas, 'O', center + const Offset(-15, 5), bold: true);
    _label(canvas, unit ? '1' : 'r', Offset(center.dx+radius*.38, center.dy-radius*.52), color: red, bold: true);
    _label(canvas, unit ? 'cos θ' : 'A', Offset(center.dx+radius+7, center.dy-7), color: navy);
    _label(canvas, unit ? 'sin θ' : 'B', Offset(center.dx+radius*.72+5, center.dy-radius*.69-14), color: red);
    if (unit) {
      _label(canvas, '−1', Offset(center.dx-radius-20, center.dy+8), size: 9);
      _label(canvas, '1', Offset(center.dx+radius-2, center.dy+8), size: 9);
    }
  }

  void _paintTriangle(Canvas canvas, Size size, {required bool right}) {
    final a = Offset(size.width*.18, size.height*.78);
    final b = Offset(size.width*.82, size.height*.78);
    final c = Offset(size.width*(right ? .18 : .55), size.height*.18);
    final path = Path()..moveTo(a.dx,a.dy)..lineTo(b.dx,b.dy)..lineTo(c.dx,c.dy)..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFEEF5FF)..style = PaintingStyle.fill);
    canvas.drawPath(path, Paint()..color = blue..style = PaintingStyle.stroke..strokeWidth = 2.5);
    _label(canvas, 'A', a + const Offset(-14, 2), bold: true);
    _label(canvas, 'B', b + const Offset(5, 2), bold: true);
    _label(canvas, 'C', c + const Offset(-2, -20), bold: true);
    if (right) {
      final s = size.width*.055;
      final corner = Path()..moveTo(a.dx+s,a.dy)..lineTo(a.dx+s,a.dy-s)..lineTo(a.dx,a.dy-s);
      canvas.drawPath(corner, Paint()..color = red..style = PaintingStyle.stroke..strokeWidth = 1.8);
      _label(canvas, '90°', a + const Offset(13,-28), color: red, size: 10);
    }
    _label(canvas, 'c', Offset((a.dx+b.dx)/2, a.dy+8), color: green, bold: true);
    _label(canvas, 'a', Offset((a.dx+c.dx)/2-14, (a.dy+c.dy)/2), color: green, bold: true);
    _label(canvas, 'b', Offset((b.dx+c.dx)/2+6, (b.dy+c.dy)/2), color: green, bold: true);
  }

  void _paintCell(Canvas canvas, Size size, {required bool plant}) {
    final rect = Rect.fromCenter(
      center: Offset(size.width*.46,size.height*.52),
      width: size.width*.53,
      height: size.height*.65,
    );
    final outer = RRect.fromRectAndRadius(rect, Radius.circular(plant ? 22 : 95));
    canvas.drawRRect(outer, Paint()..color = plant ? const Color(0xFFEAF7E8) : const Color(0xFFFFF1E8));
    canvas.drawRRect(outer, Paint()..color = green..style = PaintingStyle.stroke..strokeWidth = plant ? 5 : 2.5);
    final nucleus = rect.center;
    canvas.drawCircle(nucleus, rect.width*.12, Paint()..color = const Color(0xFFD8C9F3));
    canvas.drawCircle(nucleus, rect.width*.12, Paint()..color = const Color(0xFF7955B5)..style = PaintingStyle.stroke..strokeWidth = 1.5);
    final organelle = Paint()..color = const Color(0xFF75B7D9);
    for (final p in [
      Offset(rect.left+rect.width*.22,rect.top+rect.height*.28),
      Offset(rect.left+rect.width*.72,rect.top+rect.height*.30),
      Offset(rect.left+rect.width*.25,rect.top+rect.height*.72),
      Offset(rect.left+rect.width*.75,rect.top+rect.height*.72),
    ]) {
      canvas.drawOval(Rect.fromCenter(center:p,width:rect.width*.12,height:rect.height*.07),organelle);
    }
    if (plant) {
      _label(canvas,isEnglish?'Cell wall':'Paroi',Offset(rect.right+7,rect.top+12),color:green,size:10);
      _label(canvas,isEnglish?'Chloroplast':'Chloroplaste',Offset(rect.right+7,rect.top+43),color:green,size:9);
    }
    _label(canvas,isEnglish?'Nucleus':'Noyau',Offset(rect.right+7,rect.center.dy-5),color:navy,size:10);
    _label(canvas,isEnglish?'Membrane':'Membrane',Offset(rect.right+7,rect.bottom-22),color:navy,size:9);
    _label(canvas,isEnglish?'Cytoplasm':'Cytoplasme',Offset(rect.left-4,rect.bottom+7),color:grey,size:9);
  }

  void _paintCircuit(Canvas canvas, Size size) {
    final y = size.height*.48, l = size.width*.14, r = size.width*.86;
    final p = Paint()..color = navy..strokeWidth = 2.2..style = PaintingStyle.stroke;
    final top = y-size.height*.25, bottom = y+size.height*.25;
    canvas.drawLine(Offset(l,y),Offset(l,top),p);
    canvas.drawLine(Offset(l,top),Offset(r,top),p);
    canvas.drawLine(Offset(r,top),Offset(r,bottom),p);
    canvas.drawLine(Offset(r,bottom),Offset(l,bottom),p);
    canvas.drawLine(Offset(l,bottom),Offset(l,y),p);
    canvas.drawCircle(Offset(size.width*.5,top),13,p);
    _label(canvas,'R',Offset(size.width*.5-4,top-6),bold:true);
    canvas.drawLine(Offset(l-7,y-12),Offset(l+7,y-12),Paint()..color=red..strokeWidth=2.5);
    canvas.drawLine(Offset(l,y-23),Offset(l,y-1),Paint()..color=red..strokeWidth=1.5);
    _label(canvas,isEnglish?'Battery':'Pile',Offset(l+14,y-26),size:10);
    _label(canvas,'I',Offset(r+5,y-4),color:red,bold:true);
    _label(canvas,isEnglish?'Resistor':'Résistance',Offset(size.width*.5-38,top-34),size:10);
  }

  void _paintLens(Canvas canvas, Size size) {
    final cy=size.height*.55, cx=size.width*.55;
    final axis=Paint()..color=grey..strokeWidth=1.3;
    canvas.drawLine(Offset(12,cy),Offset(size.width-12,cy),axis);
    final lens=Path()
      ..moveTo(cx,cy-size.height*.36)
      ..cubicTo(cx-size.width*.14,cy-size.height*.18,cx-size.width*.14,cy+size.height*.18,cx,cy+size.height*.36)
      ..cubicTo(cx+size.width*.14,cy+size.height*.18,cx+size.width*.14,cy-size.height*.18,cx,cy-size.height*.36);
    canvas.drawPath(lens,Paint()..color=const Color(0xFFDBEFFB)..style=PaintingStyle.fill);
    canvas.drawPath(lens,Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=2);
    final f=size.width*.2;
    for(final x in [cx-f,cx+f]) {
      canvas.drawLine(Offset(x,cy-6),Offset(x,cy+6),Paint()..color=navy..strokeWidth=1.5);
      _label(canvas,'F',Offset(x-4,cy+9),bold:true);
    }
    final objectX=cx-size.width*.32;
    canvas.drawLine(Offset(objectX,cy),Offset(objectX,cy-size.height*.2),Paint()..color=green..strokeWidth=2.5);
    canvas.drawLine(Offset(objectX,cy-size.height*.2),Offset(objectX-5,cy-size.height*.17),Paint()..color=green..strokeWidth=2);
    canvas.drawLine(Offset(objectX,cy-size.height*.2),Offset(objectX+5,cy-size.height*.17),Paint()..color=green..strokeWidth=2);
    canvas.drawLine(Offset(objectX,cy-size.height*.2),Offset(cx,cy-size.height*.2),Paint()..color=red..strokeWidth=1.5);
    canvas.drawLine(Offset(cx,cy-size.height*.2),Offset(size.width*.9,cy+size.height*.08),Paint()..color=red..strokeWidth=1.5);
    _label(canvas,isEnglish?'Object':'Objet',Offset(objectX-18,cy-size.height*.27),color:green,size:10);
    _label(canvas,isEnglish?'Converging lens':'Lentille convergente',Offset(cx-45,12),color:blue,size:10);
  }


  void _paintSquare(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(center: Offset(size.width * .5, size.height * .52),
      width: size.width * .48, height: size.width * .48);
    canvas.drawRect(rect, Paint()..color = const Color(0xFFEEF5FF));
    canvas.drawRect(rect, Paint()..color = blue..style = PaintingStyle.stroke..strokeWidth = 2.5);
    canvas.drawLine(rect.topLeft, rect.bottomRight, Paint()..color = red..strokeWidth = 2);
    _label(canvas, 'A', rect.topLeft + const Offset(-15, -16), bold: true);
    _label(canvas, 'B', rect.topRight + const Offset(5, -5), bold: true);
    _label(canvas, 'C', rect.bottomRight + const Offset(5, 0), bold: true);
    _label(canvas, 'D', rect.bottomLeft + const Offset(-15, 0), bold: true);
    _label(canvas, isEnglish ? 'Square' : 'Carré', Offset(rect.left, rect.bottom + 18), color: navy, bold: true);
  }

  void _paintParallel(Canvas canvas, Size size) {
    final p = Paint()..color = blue..strokeWidth = 2.5;
    final y1 = size.height * .34, y2 = size.height * .68;
    canvas.drawLine(Offset(size.width*.12, y1), Offset(size.width*.88, y1), p);
    canvas.drawLine(Offset(size.width*.12, y2), Offset(size.width*.88, y2), p);
    canvas.drawLine(Offset(size.width*.35, size.height*.16), Offset(size.width*.68, size.height*.86),
      Paint()..color = red..strokeWidth = 2);
    _label(canvas, 'd₁', Offset(size.width*.83, y1-22), color: blue, bold: true);
    _label(canvas, 'd₂', Offset(size.width*.83, y2-22), color: blue, bold: true);
    _label(canvas, isEnglish ? 'Parallel lines' : 'Droites parallèles', Offset(18, 12), bold: true);
  }

  void _paintCoordinate(Canvas canvas, Size size) {
    final center = Offset(size.width*.5, size.height*.52);
    final p = Paint()..color = grid..strokeWidth = 1;
    for (var i=1;i<=6;i++) {
      final dx = size.width*.4*i/7, dy = size.height*.4*i/7;
      canvas.drawLine(Offset(center.dx-dx, 18), Offset(center.dx-dx, size.height-18), p);
      canvas.drawLine(Offset(center.dx+dx, 18), Offset(center.dx+dx, size.height-18), p);
      canvas.drawLine(Offset(18, center.dy-dy), Offset(size.width-18, center.dy-dy), p);
      canvas.drawLine(Offset(18, center.dy+dy), Offset(size.width-18, center.dy+dy), p);
    }
    final axis = Paint()..color = navy..strokeWidth = 2;
    canvas.drawLine(Offset(18, center.dy), Offset(size.width-18, center.dy), axis);
    canvas.drawLine(Offset(center.dx, size.height-18), Offset(center.dx, 18), axis);
    _label(canvas, 'x', Offset(size.width-17, center.dy+7), bold: true);
    _label(canvas, 'y', Offset(center.dx+7, 8), bold: true);
    _label(canvas, 'O', center+const Offset(5,5), size: 9);
    _label(canvas, isEnglish ? 'Coordinate plane' : 'Repère du plan', Offset(18, size.height-14), color: grey, size: 9);
  }

  void _paintCube(Canvas canvas, Size size) {
    final a=Offset(size.width*.25,size.height*.38), b=Offset(size.width*.62,size.height*.38);
    final c=Offset(size.width*.62,size.height*.76), d=Offset(size.width*.25,size.height*.76);
    final shift=Offset(size.width*.17,-size.height*.18);
    final p=Paint()..color=blue..strokeWidth=2.3..style=PaintingStyle.stroke;
    final path=Path()..moveTo(a.dx,a.dy)..lineTo(b.dx,b.dy)..lineTo(c.dx,c.dy)..lineTo(d.dx,d.dy)..close()
      ..moveTo(a.dx,a.dy)..lineTo((a+shift).dx,(a+shift).dy)
      ..moveTo(b.dx,b.dy)..lineTo((b+shift).dx,(b+shift).dy)
      ..moveTo(c.dx,c.dy)..lineTo((c+shift).dx,(c+shift).dy)
      ..moveTo((a+shift).dx,(a+shift).dy)..lineTo((b+shift).dx,(b+shift).dy)
      ..lineTo((c+shift).dx,(c+shift).dy)..lineTo((d+shift).dx,(d+shift).dy)
      ..lineTo((a+shift).dx,(a+shift).dy);
    canvas.drawPath(path,p);
    _label(canvas,isEnglish?'Cube':'Cube',Offset(size.width*.38,size.height*.88),bold:true);
  }

  void _paintPyramid(Canvas canvas, Size size) {
    final a=Offset(size.width*.2,size.height*.72), b=Offset(size.width*.78,size.height*.72);
    final c=Offset(size.width*.64,size.height*.88), d=Offset(size.width*.08,size.height*.88);
    final top=Offset(size.width*.48,size.height*.16);
    final p=Paint()..color=blue..strokeWidth=2.3..style=PaintingStyle.stroke;
    final base=Path()..moveTo(a.dx,a.dy)..lineTo(b.dx,b.dy)..lineTo(c.dx,c.dy)..lineTo(d.dx,d.dy)..close();
    canvas.drawPath(base,p);
    canvas.drawLine(top,a,p); canvas.drawLine(top,b,p); canvas.drawLine(top,c,p); canvas.drawLine(top,d,p);
    _label(canvas,isEnglish?'Pyramid':'Pyramide',Offset(size.width*.34,12),bold:true);
  }

  void _paintCylinder(Canvas canvas, Size size) {
    final rect=Rect.fromCenter(center:Offset(size.width*.5,size.height*.52),width:size.width*.48,height:size.height*.58);
    final p=Paint()..color=blue..strokeWidth=2.3..style=PaintingStyle.stroke;
    canvas.drawOval(Rect.fromLTWH(rect.left,rect.top,rect.width,rect.height*.22),p);
    canvas.drawLine(Offset(rect.left,rect.top+rect.height*.11),Offset(rect.left,rect.bottom-rect.height*.11),p);
    canvas.drawLine(Offset(rect.right,rect.top+rect.height*.11),Offset(rect.right,rect.bottom-rect.height*.11),p);
    canvas.drawArc(Rect.fromLTWH(rect.left,rect.bottom-rect.height*.22,rect.width,rect.height*.22),0,math.pi,false,p);
    canvas.drawArc(Rect.fromLTWH(rect.left,rect.bottom-rect.height*.22,rect.width,rect.height*.22),math.pi,math.pi,false,
      Paint()..color=grey..strokeWidth=1.4..style=PaintingStyle.stroke..strokeCap=StrokeCap.round);
    _label(canvas,isEnglish?'Cylinder':'Cylindre',Offset(rect.left,rect.bottom+20),bold:true);
  }

  void _paintPrism(Canvas canvas, Size size) {
    final a=Offset(size.width*.18,size.height*.65), b=Offset(size.width*.4,size.height*.28), c=Offset(size.width*.62,size.height*.65);
    final shift=Offset(size.width*.2,-size.height*.12);
    final p=Paint()..color=blue..strokeWidth=2.3..style=PaintingStyle.stroke;
    final tri=Path()..moveTo(a.dx,a.dy)..lineTo(b.dx,b.dy)..lineTo(c.dx,c.dy)..close();
    canvas.drawPath(tri,p);
    canvas.drawLine(a,a+shift,p); canvas.drawLine(b,b+shift,p); canvas.drawLine(c,c+shift,p);
    final back=Path()..moveTo((a+shift).dx,(a+shift).dy)..lineTo((b+shift).dx,(b+shift).dy)
      ..lineTo((c+shift).dx,(c+shift).dy)..close();
    canvas.drawPath(back,p);
    _label(canvas,isEnglish?'Triangular prism':'Prisme droit',Offset(size.width*.28,size.height*.88),bold:true);
  }

  void _paintGravityPair(Canvas canvas, Size size) {
    final left=Offset(size.width*.29,size.height*.5), right=Offset(size.width*.71,size.height*.5);
    final p=Paint()..color=blue..style=PaintingStyle.fill;
    canvas.drawCircle(left,24,p); canvas.drawCircle(right,34,Paint()..color=green);
    final force=Paint()..color=red..strokeWidth=2.8;
    canvas.drawLine(Offset(left.dx+28,left.dy),Offset(right.dx-38,right.dy),force);
    canvas.drawLine(Offset(right.dx-38,right.dy),Offset(right.dx-48,right.dy-7),force);
    canvas.drawLine(Offset(right.dx-38,right.dy),Offset(right.dx-48,right.dy+7),force);
    canvas.drawLine(Offset(right.dx-38,right.dy+18),Offset(left.dx+28,left.dy+18),force);
    _label(canvas,isEnglish?'Mass 1':'Masse 1',Offset(left.dx-24,left.dy+42),size:10);
    _label(canvas,isEnglish?'Mass 2':'Masse 2',Offset(right.dx-28,right.dy+48),size:10);
    _label(canvas,'F',Offset(size.width*.49,size.height*.38),color:red,bold:true);
  }

  void _paintGravityAltitude(Canvas canvas, Size size) {
    final earth=Offset(size.width*.5,size.height*.86);
    canvas.drawCircle(earth,size.width*.28,Paint()..color=const Color(0xFFDDEFE4));
    canvas.drawCircle(earth,size.width*.28,Paint()..color=green..style=PaintingStyle.stroke..strokeWidth=2);
    final object=Offset(size.width*.5,size.height*.2);
    canvas.drawCircle(object,10,Paint()..color=red);
    final dash=Paint()..color=navy..strokeWidth=1.6;
    for(var y=object.dy+14;y<earth.dy-size.width*.28;y+=10) {
      canvas.drawLine(Offset(object.dx,y),Offset(object.dx,y+5),dash);
    }
    _label(canvas,'h',Offset(object.dx+10,size.height*.49),color:red,bold:true);
    _label(canvas,isEnglish?'Altitude':'Altitude',Offset(18,12),bold:true);
    _label(canvas,isEnglish?'Earth':'Terre',Offset(earth.dx-17,earth.dy-4),color:green,bold:true);
  }

  void _paintWeight(Canvas canvas, Size size) {
    final center=Offset(size.width*.5,size.height*.34);
    final rect=Rect.fromCenter(center:center,width:70,height:55);
    canvas.drawRect(rect,Paint()..color=const Color(0xFFFFF1E8));
    canvas.drawRect(rect,Paint()..color=navy..style=PaintingStyle.stroke..strokeWidth=2);
    final x=center.dx, start=rect.bottom+5, end=size.height*.82;
    canvas.drawLine(Offset(x,start),Offset(x,end),Paint()..color=red..strokeWidth=3);
    canvas.drawLine(Offset(x,end),Offset(x-7,end-12),Paint()..color=red..strokeWidth=2);
    canvas.drawLine(Offset(x,end),Offset(x+7,end-12),Paint()..color=red..strokeWidth=2);
    _label(canvas,'P',Offset(x+10,(start+end)/2),color:red,bold:true,size:15);
    _label(canvas,isEnglish?'Weight':'Poids',Offset(18,12),bold:true);
  }

  void _paintNeuron(Canvas canvas, Size size) {
    final soma=Offset(size.width*.35,size.height*.5);
    final p=Paint()..color=blue..strokeWidth=2.2..style=PaintingStyle.stroke;
    canvas.drawCircle(soma,31,Paint()..color=const Color(0xFFEAF3FF));
    canvas.drawCircle(soma,31,p);
    canvas.drawCircle(soma,9,Paint()..color=red);
    final branches=[
      [soma+const Offset(-24,-20),soma+const Offset(-65,-55)],
      [soma+const Offset(-29,0),soma+const Offset(-78,2)],
      [soma+const Offset(-22,23),soma+const Offset(-62,57)],
      [soma+const Offset(-5,-29),soma+const Offset(0,-72)],
    ];
    for(final branch in branches) {
      canvas.drawLine(branch[0],branch[1],p);
    }
    canvas.drawLine(Offset(soma.dx+31,soma.dy),Offset(size.width*.91,soma.dy),p);
    for(var x=soma.dx+70;x<size.width*.86;x+=35) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x,soma.dy-8,22,16),const Radius.circular(8)),
        Paint()..color=const Color(0xFFD9EEDC));
    }
    _label(canvas,isEnglish?'Dendrites':'Dendrites',Offset(8,12),size:10);
    _label(canvas,isEnglish?'Cell body':'Corps cellulaire',Offset(soma.dx-38,soma.dy+40),size:9);
    _label(canvas,isEnglish?'Axon':'Axone',Offset(size.width*.73,soma.dy-22),size:10);
  }

  void _paintSynapse(Canvas canvas, Size size) {
    final x=size.width*.5;
    final pre=Rect.fromLTWH(18, size.height*.22, size.width*.38, size.height*.18);
    final post=Rect.fromLTWH(size.width*.56, size.height*.62, size.width*.38, size.height*.18);
    canvas.drawRRect(RRect.fromRectAndRadius(pre,const Radius.circular(22)),Paint()..color=const Color(0xFFEAF3FF));
    canvas.drawRRect(RRect.fromRectAndRadius(post,const Radius.circular(22)),Paint()..color=const Color(0xFFEAF7E8));
    canvas.drawRRect(RRect.fromRectAndRadius(pre,const Radius.circular(22)),Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=2);
    canvas.drawRRect(RRect.fromRectAndRadius(post,const Radius.circular(22)),Paint()..color=green..style=PaintingStyle.stroke..strokeWidth=2);
    for(var i=0;i<5;i++) {
      canvas.drawCircle(Offset(x-42+i*20,size.height*.49),4,Paint()..color=red);
    }
    canvas.drawLine(Offset(x,size.height*.42),Offset(x,size.height*.57),Paint()..color=red..strokeWidth=1.5);
    _label(canvas,isEnglish?'Presynaptic':'Pré-synaptique',Offset(20,12),size:10);
    _label(canvas,isEnglish?'Postsynaptic':'Post-synaptique',Offset(size.width*.55,size.height*.84),size:10);
    _label(canvas,isEnglish?'Synaptic cleft':'Fente synaptique',Offset(x-55,size.height*.53),color:red,size:9);
  }

  void _paintPlaceholder(Canvas canvas, Size size) {
    final rect=Rect.fromLTWH(12,12,size.width-24,size.height-24);
    canvas.drawRRect(RRect.fromRectAndRadius(rect,const Radius.circular(12)),
      Paint()..color=const Color(0xFFF3F7FC));
    canvas.drawRRect(RRect.fromRectAndRadius(rect,const Radius.circular(12)),
      Paint()..color=grey..style=PaintingStyle.stroke);
    _label(canvas,isEnglish?'Scientific diagram':'Schéma scientifique',Offset(24,size.height*.45),color:navy,bold:true,size:14);
    _label(canvas,isEnglish?'Diagram type not yet supported':'Type de schéma non encore pris en charge',Offset(24,size.height*.55),color:grey,size:10);
  }

  @override
  bool shouldRepaint(covariant _ScientificPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.graph != graph ||
      oldDelegate.block != block || oldDelegate.isEnglish != isEnglish;
}
