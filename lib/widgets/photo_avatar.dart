import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../screens/crop_avatar/crop_avatar_screen.dart';
import '../theme/app_theme.dart';

/// Avatar circulaire cliquable pour choisir une photo depuis la galerie.
/// Affiche l'initiale du nom (ou [libellePlaceholder]) tant qu'aucune photo
/// n'a été choisie.
class PhotoAvatar extends StatelessWidget {
  final Uint8List? photo;
  final String nom;
  final double taille;
  final ValueChanged<Uint8List> onPhotoChoisie;
  final String? libellePlaceholder;

  const PhotoAvatar({
    super.key,
    required this.photo,
    required this.nom,
    required this.onPhotoChoisie,
    this.taille = 32,
    this.libellePlaceholder,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _choisirPhoto(context),
      child: Container(
        width: taille,
        height: taille,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.pecheClair,
          image: photo != null
              ? DecorationImage(image: MemoryImage(photo!), fit: BoxFit.cover)
              : null,
          border: photo == null
              ? Border.all(color: AppColors.accent.withValues(alpha: 0.4))
              : null,
        ),
        alignment: Alignment.center,
        child: photo != null
            ? null
            : Text(
                libellePlaceholder ?? (nom.isNotEmpty ? nom[0].toUpperCase() : '?'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: libellePlaceholder != null ? taille * 0.15 : taille * 0.4,
                  fontWeight: FontWeight.bold,
                  color: AppColors.peche,
                ),
              ),
      ),
    );
  }

  Future<void> _choisirPhoto(BuildContext context) async {
    final picker = ImagePicker();
    final fichier = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (fichier == null) return;
    final octets = await fichier.readAsBytes();
    if (!context.mounted) return;
    final recadree = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => CropAvatarScreen(bytes: octets)),
    );
    if (recadree != null) {
      onPhotoChoisie(recadree);
    }
  }
}
