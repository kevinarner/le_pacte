import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Écran de cadrage d'un avatar : l'utilisateur glisse et zoome sa photo
/// pour centrer sa tête dans le cercle-guide, puis valide.
class CropAvatarScreen extends StatefulWidget {
  final Uint8List bytes;
  const CropAvatarScreen({super.key, required this.bytes});

  @override
  State<CropAvatarScreen> createState() => _CropAvatarScreenState();
}

class _CropAvatarScreenState extends State<CropAvatarScreen> {
  static const double _taille = 300;
  static const double _ratioExport = 400 / _taille;
  static const double _multiplicateurZoomMax = 3;

  final _boundaryKey = GlobalKey();

  ui.Image? _image;
  double _echelleCouverture = 1;
  double _echelle = 1;
  Offset _decalage = Offset.zero;

  // Pour le geste en cours (glisser au doigt et/ou pincer pour zoomer).
  double _echelleDebutGeste = 1;
  Offset _pointImageAuFocalDebut = Offset.zero;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final image = await decodeImageFromList(widget.bytes);
    final echelleCouverture = _calculerEchelleCouverture(image);
    setState(() {
      _image = image;
      _echelleCouverture = echelleCouverture;
      _echelle = echelleCouverture;
      _decalage = Offset(
        (_taille - image.width * echelleCouverture) / 2,
        (_taille - image.height * echelleCouverture) / 2,
      );
    });
  }

  double _calculerEchelleCouverture(ui.Image image) {
    final echelleX = _taille / image.width;
    final echelleY = _taille / image.height;
    return echelleX > echelleY ? echelleX : echelleY;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cadrer la photo')),
      body: SafeArea(
        child: _image == null
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      child: Text(
                        "Glisse et zoome pour centrer ta tête dans le cercle.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                    ),
                    GestureDetector(
                      onScaleStart: (d) {
                        _echelleDebutGeste = _echelle;
                        _pointImageAuFocalDebut = (d.localFocalPoint - _decalage) / _echelle;
                      },
                      onScaleUpdate: (d) => setState(() {
                        _echelle = (_echelleDebutGeste * d.scale)
                            .clamp(_echelleCouverture, _echelleCouverture * _multiplicateurZoomMax);
                        _decalage = d.localFocalPoint - _pointImageAuFocalDebut * _echelle;
                        _clamperDecalage();
                      }),
                      child: SizedBox(
                        width: _taille,
                        height: _taille,
                        child: Stack(
                          children: [
                            RepaintBoundary(
                              key: _boundaryKey,
                              child: ClipRect(
                                child: SizedBox(
                                  width: _taille,
                                  height: _taille,
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        left: _decalage.dx,
                                        top: _decalage.dy,
                                        child: SizedBox(
                                          width: _image!.width * _echelle,
                                          height: _image!.height * _echelle,
                                          child: Image.memory(widget.bytes, fit: BoxFit.fill),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            IgnorePointer(
                              child: CustomPaint(
                                size: const Size(_taille, _taille),
                                painter: _MasqueRondPainter(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      child: Row(
                        children: [
                          const Icon(Icons.zoom_out, size: 18, color: Colors.black45),
                          Expanded(
                            child: Slider(
                              value: _echelle,
                              min: _echelleCouverture,
                              max: _echelleCouverture * _multiplicateurZoomMax,
                              onChanged: (v) => setState(() {
                                _appliquerEchelle(v);
                              }),
                            ),
                          ),
                          const Icon(Icons.zoom_in, size: 18, color: Colors.black45),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: FilledButton(
                        onPressed: _valider,
                        child: const Text('Valider'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  void _appliquerEchelle(double nouvelleEchelle) {
    final centreViewport = const Offset(_taille / 2, _taille / 2);
    final pointImage = (centreViewport - _decalage) / _echelle;
    _echelle = nouvelleEchelle;
    _decalage = centreViewport - pointImage * _echelle;
    _clamperDecalage();
  }

  void _clamperDecalage() {
    final image = _image!;
    final largeur = image.width * _echelle;
    final hauteur = image.height * _echelle;
    _decalage = Offset(
      _decalage.dx.clamp(_taille - largeur, 0.0),
      _decalage.dy.clamp(_taille - hauteur, 0.0),
    );
  }

  Future<void> _valider() async {
    final boundary = _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _ratioExport);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    Navigator.pop(context, byteData!.buffer.asUint8List());
  }
}

class _MasqueRondPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final masque = Path.combine(
      PathOperation.difference,
      Path()..addRect(rect),
      Path()..addOval(Rect.fromCircle(center: rect.center, radius: size.width / 2)),
    );
    canvas.drawPath(masque, Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawCircle(
      rect.center,
      size.width / 2,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
