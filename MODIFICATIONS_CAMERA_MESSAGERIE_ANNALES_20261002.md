# Fise School — caméra messagerie et diffusion des annales (2 octobre 2026)

## À appliquer
Migration Supabase : `supabase/migrations/202610020007_teacher_classes_and_paper_targets.sql`
(à pousser après `202610020006_cours_canaux_groupes.sql`).

## Messagerie (élève et enseignant)
- Bouton caméra dans la barre du haut de **Messages** : photo, puis choix du groupe destinataire.
- La caméra reste aussi dans chaque conversation (groupe et message privé).

## Annales (admin)
- À l'ajout : « Toutes les salles » ou « Salles précises » (une ou plusieurs salles cochées).
- Menu de chaque annale : « Salles de diffusion » pour modifier la diffusion après coup.
- Un élève ne voit que les annales de sa salle ; une annale sans salle ciblée reste visible par tous.

## Non modifié
Cours admin (une salle par cours), QCM, notes, bulletins, IA, paiements.

## Vérification
Le SDK Flutter n'est pas installé ici : le code n'a pas été compilé ni testé.
`flutter analyze` dans GitHub Actions le fera au prochain push.
