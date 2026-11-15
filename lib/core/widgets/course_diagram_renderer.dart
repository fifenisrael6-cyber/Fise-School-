import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared native diagram cards used by the student course reader and subject feed.
class CourseDiagramRenderer extends StatelessWidget {
  const CourseDiagramRenderer({
    super.key,
    required this.kind,
    required this.locale,
  });

  final String kind;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    const titles = <String, String>{
      'gravity_pair': 'Attraction gravitationnelle entre deux corps',
      'gravity_altitude': 'Champ gravitationnel autour de la Terre',
      'weight': 'Poids d’un corps',
      'geom_triangle': 'Triangle et éléments géométriques',
      'geom_right_triangle': 'Triangle rectangle',
      'geom_circle': 'Cercle et rayon',
      'geom_square': 'Carré et diagonales',
      'geom_parallel': 'Configuration de Thalès',
      'geom_coordinate': 'Repère cartésien',
      'geom_cube': 'Cube en perspective',
      'geom_pyramid': 'Pyramide à base carrée',
      'geom_cylinder': 'Cylindre',
      'geom_prism': 'Prisme droit',
      'graph_line': 'Représentation graphique d’une droite',
      'stats_bar': 'Diagramme en bâtons',
      'svt_cell': 'Échanges à travers la membrane cellulaire',
      'svt_neuron': 'Structure d’un neurone',
      'svt_synapse': 'Transmission au niveau d’une synapse',
    };
    const englishTitles = <String, String>{
      'gravity_pair': 'Gravitational attraction between two bodies',
      'gravity_altitude': 'Gravitational field around Earth',
      'weight': 'Weight of a body',
      'geom_triangle': 'Triangle and its elements',
      'geom_right_triangle': 'Right-angled triangle',
      'geom_circle': 'Circle and radius',
      'geom_square': 'Square and diagonals',
      'geom_parallel': 'Thales configuration',
      'geom_coordinate': 'Cartesian coordinate plane',
      'geom_cube': 'Cube in perspective',
      'geom_pyramid': 'Square-based pyramid',
      'geom_cylinder': 'Cylinder',
      'geom_prism': 'Right prism',
      'graph_line': 'Graph of a straight line',
      'stats_bar': 'Bar chart',
      'svt_cell': 'Cell membrane exchanges',
      'svt_neuron': 'Structure of a neuron',
      'svt_synapse': 'Synaptic transmission',
    };
    const formulas = <String, String>{
      'gravity_pair': 'F = G × m₁ × m₂ / r²',
      'gravity_altitude': 'g(h) = G × Mₜ / (Rₜ + h)²',
      'weight': 'P = m × g',
      'geom_triangle': 'A = (base × hauteur) / 2',
      'geom_right_triangle': 'c² = a² + b²',
      'geom_circle': 'P = 2πr  •  A = πr²',
      'geom_square': 'A = c²  •  diagonale = c√2',
      'geom_parallel': 'MN ∥ BC  ⇒  AM/AB = AN/AC',
      'geom_coordinate': 'Point A(x ; y)',
      'geom_cube': 'V = a³  •  A totale = 6a²',
      'geom_pyramid': 'V = (A base × hauteur) / 3',
      'geom_cylinder': 'V = πr²h',
      'geom_prism': 'V = A base × hauteur',
      'graph_line': 'y = ax + b',
      'stats_bar': 'Hauteur des barres proportionnelle aux effectifs',
      'svt_cell': 'Entrées : eau, ions, nutriments, O₂  •  Sorties : CO₂ et déchets',
      'svt_neuron': 'Dendrites → corps cellulaire → axone → terminaisons',
      'svt_synapse': 'Message électrique → neurotransmetteurs → récepteurs',
    };
    final english = locale.languageCode == 'en';
    final title = english ? (englishTitles[kind] ?? titles[kind]) : titles[kind];
    if (title == null) return const SizedBox.shrink();
    final formula = formulas[kind] ?? '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Text(title, textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800,
            color: Color(0xFF164E63), fontSize: 14)),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, height: 190,
          child: CustomPaint(painter: _CourseDiagramPainter(kind))),
        const SizedBox(height: 6),
        Text(formula, textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800,
            color: Color(0xFF1D4ED8), fontSize: 14)),
      ]),
    );
  }
}

class _CourseDiagramPainter extends CustomPainter {
  final String kind;
  _CourseDiagramPainter(this.kind);

  static const blue = Color(0xFF2563EB);
  static const orange = Color(0xFFF97316);
  static const red = Color(0xFFDC2626);
  static const green = Color(0xFF16A34A);
  static const ink = Color(0xFF0F172A);
  static const grey = Color(0xFF64748B);

  void _text(Canvas c, String value, Offset at, {double size = 12, Color color = ink, bool bold = false}) {
    final p = TextPainter(
      text: TextSpan(text: value, style: TextStyle(fontSize: size, color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 180);
    p.paint(c, at);
  }

  void _line(Canvas c, Offset a, Offset b, Color color, {double width = 2, bool dashed = false}) {
    final paint = Paint()..color = color..strokeWidth = width..style = PaintingStyle.stroke;
    if (!dashed) { c.drawLine(a, b, paint); return; }
    final delta = b - a;
    final length = delta.distance;
    if (length == 0) return;
    final unit = delta / length;
    for (double d = 0; d < length; d += 10) {
      c.drawLine(a + unit * d, a + unit * math.min(d + 5, length).toDouble(), paint);
    }
  }

  void _arrow(Canvas c, Offset a, Offset b, Color color) {
    _line(c, a, b, color, width: 2.5);
    final angle = (b - a).direction;
    const head = 9.0;
    _line(c, b, b - Offset(head * math.cos(angle - .5), head * math.sin(angle - .5)), color);
    _line(c, b, b - Offset(head * math.cos(angle + .5), head * math.sin(angle + .5)), color);
  }

  void _point(Canvas c, Offset p, String label, {Color color = red}) {
    c.drawCircle(p, 3.5, Paint()..color = color);
    _text(c, label, p + const Offset(5, -17), size: 11, color: ink, bold: true);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final center = Offset(w * .5, h * .52);

    if (kind == 'gravity_pair') {
      final y = h * .43;
      canvas.drawCircle(Offset(w * .22, y), 27, Paint()..color = blue);
      canvas.drawCircle(Offset(w * .78, y), 35, Paint()..color = orange);
      _text(canvas, 'm₁', Offset(w * .22 - 9, y - 7), color: Colors.white, bold: true);
      _text(canvas, 'm₂', Offset(w * .78 - 10, y - 7), color: Colors.white, bold: true);
      _arrow(canvas, Offset(w * .43, y - 13), Offset(w * .30, y - 13), red);
      _arrow(canvas, Offset(w * .57, y + 13), Offset(w * .69, y + 13), red);
      _text(canvas, 'F₂₁', Offset(w * .33, y - 36), color: red, bold: true);
      _text(canvas, 'F₁₂', Offset(w * .61, y + 20), color: red, bold: true);
      _line(canvas, Offset(w * .22, y + 49), Offset(w * .78, y + 49), grey);
      _text(canvas, 'distance r', Offset(w * .43, y + 54), size: 11);
    } else if (kind == 'gravity_altitude') {
      final earth = Offset(w * .34, h * .53);
      canvas.drawCircle(earth, 53, Paint()..color = blue);
      _text(canvas, 'Terre', earth - const Offset(18, 7), size: 11, color: Colors.white, bold: true);
      canvas.drawCircle(earth, 82, Paint()..color = grey..style = PaintingStyle.stroke..strokeWidth = 1.5);
      final sat = Offset(earth.dx + 82, earth.dy - 8);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: sat, width: 22, height: 14), const Radius.circular(3)), Paint()..color = orange);
      _arrow(canvas, earth, Offset(earth.dx + 82, earth.dy), green);
      _text(canvas, 'Rₜ', earth + const Offset(-43, 25), color: Colors.white, bold: true);
      _text(canvas, 'h', earth + const Offset(43, -37), color: green, bold: true);
      _text(canvas, 'Satellite', sat + const Offset(-26, -29), size: 11, bold: true);
      _text(canvas, 'r = Rₜ + h', Offset(w * .58, h * .46), size: 14, color: blue, bold: true);
    } else if (kind == 'weight') {
      final groundY = h * .72;
      _line(canvas, Offset(8, groundY), Offset(w - 8, groundY), green, width: 4);
      canvas.drawCircle(Offset(w * .5, groundY - 48), 18, Paint()..color = orange);
      _arrow(canvas, Offset(w * .5, groundY - 25), Offset(w * .5, groundY - 2), red);
      _text(canvas, 'm', Offset(w * .5 + 24, groundY - 56), bold: true);
      _text(canvas, 'P', Offset(w * .5 + 13, groundY - 25), color: red, bold: true);
      _text(canvas, 'Sol', Offset(w * .5 - 12, groundY + 7), size: 11, color: green, bold: true);
    } else if (kind == 'geom_triangle' || kind == 'geom_right_triangle') {
      final a = Offset(w * .22, h * .78), b = Offset(w * .78, h * .78);
      final c = kind == 'geom_right_triangle' ? Offset(w * .22, h * .18) : Offset(w * .53, h * .18);
      final p = Path()..moveTo(a.dx,a.dy)..lineTo(b.dx,b.dy)..lineTo(c.dx,c.dy)..close();
      canvas.drawPath(p, Paint()..color = const Color(0x332563EB)..style = PaintingStyle.fill);
      canvas.drawPath(p, Paint()..color = blue..style = PaintingStyle.stroke..strokeWidth = 3);
      _point(canvas,a,'A'); _point(canvas,b,'B'); _point(canvas,c,'C');
      if (kind == 'geom_right_triangle') {
        _line(canvas, a + const Offset(0,-16), a + const Offset(16,-16), green);
        _line(canvas, a + const Offset(16,-16), a + const Offset(16,0), green);
        _text(canvas,'angle droit',Offset(w*.28,h*.58),size:10,color:green);
      } else {
        _line(canvas, Offset((a.dx+b.dx)/2,h*.70), Offset((a.dx+b.dx)/2,h*.78), red);
        _text(canvas,'base',Offset(w*.44,h*.82),size:11,color:red);
        _line(canvas,c,Offset(c.dx,h*.78),green,dashed:true);
        _text(canvas,'hauteur',Offset(c.dx+5,h*.48),size:10,color:green);
      }
    } else if (kind == 'geom_circle') {
      final r = math.min(w,h).toDouble()*.31;
      canvas.drawCircle(center,r,Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=3);
      canvas.drawCircle(center,4,Paint()..color=red);
      final edge=center+Offset(r*.78,-r*.63);
      _line(canvas,center,edge,red,width:3);
      _text(canvas,'O',center+const Offset(-17,7),bold:true);
      _text(canvas,'r',center+Offset(r*.35,-r*.42),color:red,bold:true);
    } else if (kind == 'geom_square') {
      final side=math.min(w,h).toDouble()*.62;
      final rect=Rect.fromCenter(center:center,width:side,height:side);
      canvas.drawRect(rect,Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=3);
      _line(canvas,rect.topLeft,rect.bottomRight,red,width:2.5);
      _line(canvas,rect.topRight,rect.bottomLeft,green,width:2.5);
      _text(canvas,'c',Offset(rect.left-18,center.dy),color:blue,bold:true);
    } else if (kind == 'geom_parallel') {
      final a=Offset(w*.20,h*.78), b=Offset(w*.82,h*.78);
      final c=Offset(w*.31,h*.24), d=Offset(w*.70,h*.24);
      _line(canvas,a,b,blue,width:3); _line(canvas,c,d,blue,width:3);
      _line(canvas,Offset(w*.40,h*.08),Offset(w*.54,h*.94),red,width:2.5);
      _line(canvas,Offset(w*.68,h*.08),Offset(w*.78,h*.94),red,width:2.5);
      _point(canvas,Offset(w*.40,h*.64),'M'); _point(canvas,Offset(w*.54,h*.64),'N');
      _point(canvas,Offset(w*.20,h*.78),'B'); _point(canvas,Offset(w*.82,h*.78),'C');
      _text(canvas,'(MN) ∥ (BC)',Offset(w*.35,h*.06),color:green,bold:true);
    } else if (kind == 'geom_coordinate' || kind == 'graph_line') {
      final origin=Offset(w*.18,h*.82);
      _arrow(canvas,Offset(w*.08,origin.dy),Offset(w*.92,origin.dy),ink);
      _arrow(canvas,Offset(origin.dx,h*.92),Offset(origin.dx,h*.08),ink);
      for (int i=1;i<=6;i++) {
        final x=origin.dx+i*w*.105;
        _line(canvas,Offset(x,origin.dy-4),Offset(x,origin.dy+4),grey);
        final y=origin.dy-i*h*.105;
        _line(canvas,Offset(origin.dx-4,y),Offset(origin.dx+4,y),grey);
      }
      if (kind=='geom_coordinate') {
        final a=Offset(w*.60,h*.30);
        _line(canvas,a,Offset(a.dx,origin.dy),green,dashed:true);
        _line(canvas,a,Offset(origin.dx,a.dy),orange,dashed:true);
        _point(canvas,a,'A(x ; y)');
      } else {
        final a=Offset(w*.24,h*.72),b=Offset(w*.82,h*.18);
        _line(canvas,a,b,red,width:3);
        _point(canvas,a,''); _point(canvas,b,'');
      }
      _text(canvas,'x',Offset(w*.92,origin.dy+5),bold:true);
      _text(canvas,'y',Offset(origin.dx+7,h*.05),bold:true);
    } else if (kind == 'geom_cube' || kind == 'geom_prism') {
      final dx=w*.18,dy=h*.17;
      final x=w*.24,y=h*.30,bw=w*.43,bh=h*.43;
      final f=Offset(dx,-dy);
      final p1=Offset(x,y),p2=Offset(x+bw,y),p3=Offset(x+bw,y+bh),p4=Offset(x,y+bh);
      final q1=p1+f,q2=p2+f,q3=p3+f,q4=p4+f;
      for(final pair in <List<Offset>>[[p1,p2],[p2,p3],[p3,p4],[p4,p1],[q1,q2],[q2,q3],[q3,q4],[q4,q1],[p1,q1],[p2,q2],[p3,q3],[p4,q4]]) {
        _line(canvas,pair[0],pair[1],blue,width:2.5);
      }
      _text(canvas,kind=='geom_cube'?'a':'h',Offset(x+bw+dx+3,y+bh*.5),color:red,bold:true);
    } else if (kind == 'geom_pyramid') {
      final apex=Offset(w*.52,h*.12),a=Offset(w*.20,h*.72),b=Offset(w*.78,h*.72),c=Offset(w*.88,h*.48),d=Offset(w*.32,h*.48);
      _line(canvas,a,b,blue,width:2.5); _line(canvas,b,c,blue,width:2.5); _line(canvas,c,d,blue,width:2.5); _line(canvas,d,a,blue,width:2.5);
      for(final p in [a,b,c,d]) _line(canvas,apex,p,red,width:2.5);
      _line(canvas,apex,Offset(w*.54,h*.59),green,dashed:true);
      _text(canvas,'S',apex+const Offset(4,-12),bold:true); _text(canvas,'H',Offset(w*.54,h*.60),color:green,bold:true);
    } else if (kind == 'geom_cylinder') {
      final left=w*.25,right=w*.75,top=h*.20,bottom=h*.78,ry=h*.10;
      canvas.drawOval(Rect.fromLTRB(left,top-ry,right,top+ry),Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=2.5);
      _line(canvas,Offset(left,top),Offset(left,bottom),blue,width:2.5);
      _line(canvas,Offset(right,top),Offset(right,bottom),blue,width:2.5);
      canvas.drawArc(Rect.fromLTRB(left,bottom-ry,right,bottom+ry),0,math.pi, false,Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=2.5);
      canvas.drawArc(Rect.fromLTRB(left,bottom-ry,right,bottom+ry),math.pi,math.pi,false,Paint()..color=grey..style=PaintingStyle.stroke..strokeWidth=1.5);
      _line(canvas,center,Offset(w*.72,h*.42),red,width:2.5);
      _text(canvas,'r',Offset(w*.61,h*.40),color:red,bold:true); _text(canvas,'h',Offset(right+7,h*.47),color:green,bold:true);
    } else if (kind == 'svt_cell') {
      final cell=Rect.fromCenter(center:center,width:w*.48,height:h*.68);
      canvas.drawOval(cell,Paint()..color=const Color(0x3322C55E)..style=PaintingStyle.fill);
      canvas.drawOval(cell,Paint()..color=green..style=PaintingStyle.stroke..strokeWidth=3);
      canvas.drawCircle(center,24,Paint()..color=const Color(0xFF93C5FD));
      canvas.drawCircle(center,24,Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=2);
      _text(canvas,'Noyau',center+const Offset(28,-8),size:10,color:blue,bold:true);
      _text(canvas,'Membrane',Offset(w*.34,h*.12),size:10,color:green,bold:true);
      _arrow(canvas,Offset(5,h*.40),Offset(w*.25,h*.40),blue);
      _arrow(canvas,Offset(5,h*.58),Offset(w*.25,h*.58),orange);
      _arrow(canvas,Offset(w*.75,h*.47),Offset(w-5,h*.47),red);
      _text(canvas,'Entrées',Offset(3,h*.24),size:10,color:blue,bold:true);
      _text(canvas,'Sorties',Offset(w*.78,h*.27),size:10,color:red,bold:true);
    } else if (kind == 'svt_neuron') {
      final soma=Offset(w*.28,h*.50);
      canvas.drawCircle(soma,27,Paint()..color=const Color(0xFFFDE68A));
      canvas.drawCircle(soma,27,Paint()..color=orange..style=PaintingStyle.stroke..strokeWidth=2);
      canvas.drawCircle(soma,9,Paint()..color=blue);
      for(final end in [Offset(w*.08,h*.20),Offset(w*.07,h*.48),Offset(w*.10,h*.82),Offset(w*.25,h*.12),Offset(w*.34,h*.10)]) {
        _line(canvas,soma,end,green,width:2.5);
      }
      final axonStart=Offset(w*.43,h*.50), axonEnd=Offset(w*.88,h*.50);
      _line(canvas,axonStart,axonEnd,blue,width:4);
      for(int i=0;i<4;i++) {
        final x=w*(.48+i*.095);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x,h*.43,w*.065,h*.14),const Radius.circular(8)),Paint()..color=const Color(0xFFBFDBFE));
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x,h*.43,w*.065,h*.14),const Radius.circular(8)),Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=1.5);
      }
      _line(canvas,axonEnd,Offset(w*.94,h*.34),red,width:2);
      _line(canvas,axonEnd,Offset(w*.95,h*.50),red,width:2);
      _line(canvas,axonEnd,Offset(w*.94,h*.66),red,width:2);
      _text(canvas,'Dendrites',Offset(2,h*.04),size:10,color:green,bold:true);
      _text(canvas,'Corps cellulaire',Offset(w*.18,h*.78),size:10,bold:true);
      _text(canvas,'Axone + myéline',Offset(w*.48,h*.23),size:10,color:blue,bold:true);
      _text(canvas,'Terminaisons',Offset(w*.72,h*.78),size:10,color:red,bold:true);
    } else if (kind == 'svt_synapse') {
      final pre=Rect.fromLTWH(w*.12,h*.20,w*.30,h*.30);
      final post=Rect.fromLTWH(w*.58,h*.58,w*.30,h*.22);
      canvas.drawRRect(RRect.fromRectAndRadius(pre,const Radius.circular(25)),Paint()..color=const Color(0xFFBFDBFE));
      canvas.drawRRect(RRect.fromRectAndRadius(pre,const Radius.circular(25)),Paint()..color=blue..style=PaintingStyle.stroke..strokeWidth=2);
      canvas.drawRRect(RRect.fromRectAndRadius(post,const Radius.circular(18)),Paint()..color=const Color(0xFFDCFCE7));
      canvas.drawRRect(RRect.fromRectAndRadius(post,const Radius.circular(18)),Paint()..color=green..style=PaintingStyle.stroke..strokeWidth=2);
      for(int i=0;i<5;i++) {
        canvas.drawCircle(Offset(w*(.20+i*.045),h*.38),4,Paint()..color=orange);
        canvas.drawCircle(Offset(w*(.48+i*.035),h*(.48+(i%2)*.05)),3,Paint()..color=orange);
      }
      _arrow(canvas,Offset(w*.43,h*.42),Offset(w*.58,h*.62),red);
      _text(canvas,'Bouton présynaptique',Offset(w*.08,h*.06),size:10,color:blue,bold:true);
      _text(canvas,'Fente synaptique',Offset(w*.39,h*.80),size:10,color:orange,bold:true);
      _text(canvas,'Récepteurs',Offset(w*.62,h*.84),size:10,color:green,bold:true);
    } else if (kind == 'stats_bar') {
      final base=h*.82;
      _line(canvas,Offset(w*.12,base),Offset(w*.92,base),ink);
      final vals=[.28,.52,.40,.72,.60];
      for(int i=0;i<vals.length;i++) {
        final x=w*(.20+i*.14);
        canvas.drawRect(Rect.fromLTWH(x,base-h*vals[i]*.72,w*.075,h*vals[i]*.72),Paint()..color=[blue,green,orange,red,Color(0xFF7C3AED)][i]);
      }
      _text(canvas,'Catégories',Offset(w*.42,base+8),size:10);
      _text(canvas,'Effectif',Offset(3,h*.12),size:10);
    }
  }

  @override
  bool shouldRepaint(covariant _CourseDiagramPainter oldDelegate) => oldDelegate.kind != kind;
}
