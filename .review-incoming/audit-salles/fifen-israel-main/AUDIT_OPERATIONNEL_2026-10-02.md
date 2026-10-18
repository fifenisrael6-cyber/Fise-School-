# Fise School — audit opérationnel complet — 2 octobre 2026

## Scénarios simulés

### Élève
1. Connexion → salle attribuée.
2. Accueil → cours, QCM, progression, emploi du temps, notifications, messages.
3. Cours → leçons → progression.
4. Nouveau devoir publié → notification serveur.
5. Nouveau créneau → notification serveur.
6. Message d'un enseignant → notification + réception temps réel.
7. Hors ligne → cours/leçons déjà synchronisés restent accessibles.

### Enseignant
1. Connexion → uniquement ses salles et contenus autorisés.
2. Cours → salle → matière → programme → chapitre.
3. QCM → salle/cours/leçon sans UUID saisi manuellement.
4. Forum → seulement les salles auxquelles il est affecté.
5. Emploi du temps → consultation de ses créneaux.
6. Devoir remis par un élève → notification serveur.
7. Message privé → réception temps réel + accusé de lecture.
8. Paramètres → déconnexion; pas de bouton de déconnexion sur l'accueil enseignant.

### Administrateur
1. Gestion des salles, élèves et enseignants.
2. Matières par salle.
3. Cours et contenus.
4. QCM/devoirs.
5. Emploi du temps : choix salle → matière → enseignant → jour → heures → salle physique.
6. Le serveur refuse les conflits de classe, enseignant ou salle physique.

## Comparaison fonctionnelle documentée

- OnBuch met en avant cours MINESEC, quiz/exercices, annales, IA, résultats, agenda et fonctionnement avec connexion limitée.
- Scolive met en avant notes/bulletins, emploi du temps par classe/enseignant/salle, devoirs, vie scolaire, messagerie et ressources.
- Les plateformes de gestion scolaire camerounaises consultées mettent aussi en avant présences, notes/bulletins, paiements, messagerie et notifications.
- WhatsApp fournit un modèle utile pour la messagerie : conversation, pièces jointes, notifications configurables et états de lecture. Fise School reprend les principes utiles à une messagerie scolaire sans devenir une messagerie générale.

## État Fise School après ce passage

### Opérationnel dans le code
- Authentification et séparation des rôles.
- Cours, leçons, ressources.
- QCM/exercices et soumissions.
- Forums sécurisés par salle.
- Messagerie privée enseignant ↔ élève avec pièces jointes.
- IA multi-tour avec caméra, galerie, PDF et fichiers texte autorisés.
- Emploi du temps par salle.
- Notifications serveur déclenchées par événements scolaires.
- Notifications et messages en temps réel via Supabase Realtime.
- Paiement Premium/Notch Pay déjà présent.
- Cache hors ligne des cours/leçons déjà synchronisés.

### À prévoir pour une version encore plus complète
- Notifications push Android en arrière-plan avec jetons appareils.
- Synchronisation bidirectionnelle de la progression offline.
- Téléchargement offline des médias avec gestion de l'espace.
- Notes/bulletins et présence si l'application doit devenir un ERP scolaire complet.
- Portail parent si Fise School doit couvrir aussi la famille.

## Validation technique

Le SDK Flutter n'est pas installé dans l'environnement de modification. Aucun build local n'est donc déclaré. La validation finale doit passer par GitHub Actions avec `flutter analyze` puis `flutter build apk --release`.
