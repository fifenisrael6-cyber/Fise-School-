# Import PDF hors ligne dans l’éditeur de cours

Le formulaire de création de cours propose maintenant un import PDF local.

## Traitement
- Lecture du fichier sélectionné sur le téléphone.
- Extraction Syncfusion par lots de dix pages, avec extraction des lignes et tailles de police.
- OCR ML Kit Latin sur les pages dont le texte extrait est presque vide.
- Rendu de secours des pages scannées en JPEG compressé (largeur maximale 1 000 px, qualité 70).
- Classification heuristique des titres, paragraphes, listes et tableaux textuels à colonnes espacées.
- Suppression heuristique des lignes courtes répétées dans le document.
- Aperçu avant insertion : sélectionner, supprimer, modifier les textes et éditer les tableaux.
- Insertion au curseur dans Quill ; les tableaux utilisent l’embed de tableau existant.

## Limites à connaître
La détection des tableaux est heuristique et doit être vérifiée dans l’aperçu. Les tableaux dessinés sans texte aligné, les figures au milieu d’une page et les images incorporées dans des pages comportant aussi du texte ne sont pas encore isolés automatiquement : les pages scannées sont conservées comme images complètes. Les images de page sont encodées dans le Delta en données JPEG afin que le contenu accompagne le cours ; ce n’est pas encore un flux de fichiers séparés dans Supabase Storage.

Les fichiers PDF de plus de 50 pages sont traités par lots de dix (limite de protection actuelle : 500 pages). Le moteur OCR embarqué est celui du script Latin ; pour les langues non latines, prévoir un moteur/modèle supplémentaire.
