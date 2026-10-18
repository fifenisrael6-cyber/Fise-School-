import 'package:flutter/material.dart';

class AppTexts {
  final Locale locale;

  const AppTexts(this.locale);

  bool get isEnglish => locale.languageCode == 'en';

  String get appName => 'Fise School';

  String get welcome =>
      isEnglish ? 'Welcome to Fise School' : 'Bienvenue sur Fise School';

  String get subtitle => isEnglish
      ? 'Your digital school space, simple and accessible.'
      : 'Votre espace scolaire numérique, simple et accessible.';

  String get language => isEnglish ? 'Language' : 'Langue';
  String get french => 'Français';
  String get english => 'English';
  String get student => isEnglish ? 'Student' : 'Élève';
  String get teacher => isEnglish ? 'Teacher' : 'Enseignant';

  String get studentDescription => isEnglish
      ? 'Access your class, courses, assignments and teachers.'
      : 'Accédez à votre classe, vos cours, devoirs et enseignants.';

  String get teacherDescription => isEnglish
      ? 'Manage your classes, courses, assignments and students.'
      : 'Gérez vos classes, cours, devoirs et élèves.';

  String get continueText => isEnglish ? 'Continue' : 'Continuer';
  String get chooseProfile =>
      isEnglish ? 'Choose your profile' : 'Choisissez votre profil';
  String get publicSpace => isEnglish ? 'Public space' : 'Espace public';

  String get cameroonSystem => isEnglish
      ? 'Designed for the Cameroonian school system'
      : 'Conçu pour le système scolaire camerounais';

  String get sector => isEnglish ? 'School sector' : 'Secteur scolaire';
  String get chooseSubsystem =>
      isEnglish ? 'Choose your subsystem' : 'Choisissez votre sous-système';
  String get francophone => 'Francophone';
  String get anglophone => 'Anglophone';
  String get examLevel => isEnglish ? 'Examination level' : 'Niveau d’examen';
  String get exam => isEnglish ? 'Examination' : 'Examen';
  String get general => isEnglish ? 'General' : 'Général';
  String get technical => isEnglish ? 'Technical' : 'Technique';
  String get chooseSector =>
      isEnglish ? 'Choose your sector' : 'Choisissez votre secteur';
  String get chooseExamLevel => isEnglish
      ? 'Choose your examination level'
      : 'Choisissez votre niveau d’examen';
  String get chooseTrack => isEnglish
      ? 'Choose your series, stream or specialty'
      : 'Choisissez votre série, filière ou spécialité';
  String get configurableTrack => isEnglish
      ? 'Configurable catalogue entry'
      : 'Entrée de catalogue configurable';
  String get trackNotListed => isEnglish
      ? 'Series or specialty to configure'
      : 'Série ou spécialité à configurer';
  String get trackToConfigure => isEnglish
      ? 'The official correspondence is not confirmed yet.'
      : 'La correspondance officielle n’est pas encore confirmée.';
  String get catalogUnavailable => isEnglish
      ? 'The examination catalogue could not be loaded.'
      : 'Le catalogue des examens n’a pas pu être chargé.';
  String get noConfiguredTracks => isEnglish
      ? 'No series or specialty is configured for this level yet.'
      : 'Aucune série ou spécialité n’est encore configurée pour ce niveau.';
  String get continueWithoutTrack =>
      isEnglish ? 'Continue without selecting one' : 'Continuer sans sélection';
  String get verificationPending => isEnglish
      ? 'Official confirmation pending'
      : 'Confirmation officielle en attente';
  String get promotion => isEnglish ? 'My promotion' : 'Ma promotion';
  String get currentSchoolYear =>
      isEnglish ? 'Current school year' : 'Année scolaire actuelle';
  String get nextSchoolYear =>
      isEnglish ? 'Next school year' : 'Année scolaire suivante';
  String get currentClass => isEnglish ? 'Current class' : 'Classe actuelle';
  String get chooseNextClass => isEnglish
      ? 'Choose your class for the next school year'
      : 'Choisissez votre classe pour la prochaine année scolaire';
  String get requestPromotion =>
      isEnglish ? 'Request my promotion' : 'Demander mon passage';
  String get promotionPending =>
      isEnglish ? 'Promotion request pending' : 'Demande en attente';
  String get promotionApproved =>
      isEnglish ? 'Promotion approved' : 'Promotion acceptée';
  String get promotionRejected =>
      isEnglish ? 'Promotion rejected' : 'Promotion refusée';
  String get promotionCancelled =>
      isEnglish ? 'Promotion cancelled' : 'Promotion annulée';
  String get cancelPromotion =>
      isEnglish ? 'Cancel request' : 'Annuler la demande';
  String get noPromotionPath => isEnglish
      ? 'No valid promotion path is available yet.'
      : 'Aucun parcours de promotion valide n’est encore disponible.';
  String get noDestinationClasses => isEnglish
      ? 'No destination class is configured for the next school year yet.'
      : 'Aucune classe destination n’est encore configurée pour la prochaine année scolaire.';
  String get noCurrentClass => isEnglish
      ? 'You are not assigned to a current class.'
      : 'Vous n’êtes affecté à aucune classe actuelle.';
  String get noPendingPromotions => isEnglish
      ? 'There are no pending promotion requests.'
      : 'Aucune demande de promotion en attente.';
  String get approvePromotion => isEnglish ? 'Approve' : 'Approuver';
  String get rejectPromotion => isEnglish ? 'Reject' : 'Rejeter';
  String get promotionReviewError => isEnglish
      ? 'The promotion request could not be processed.'
      : 'La demande de promotion n’a pas pu être traitée.';
  String get settings => isEnglish ? 'Settings' : 'Paramètres';
  String get myProfile => isEnglish ? 'My profile' : 'Mon profil';
  String get schooling => isEnglish ? 'My schooling' : 'Ma scolarité';
  String get privacy => isEnglish ? 'Privacy' : 'Confidentialité';
  String get security => isEnglish ? 'Security' : 'Sécurité';
  String get about => isEnglish ? 'About' : 'À propos';
  String get save => isEnglish ? 'Save' : 'Enregistrer';
  String get takePhoto => isEnglish ? 'Take a photo' : 'Prendre une photo';
  String get choosePhoto => isEnglish ? 'Choose a photo' : 'Choisir une photo';
  String get deletePhoto => isEnglish ? 'Delete photo' : 'Supprimer la photo';
  String get profileSaveError => isEnglish
      ? 'The profile could not be saved.'
      : 'Le profil n’a pas pu être enregistré.';
  String get photoError => isEnglish
      ? 'The photo could not be updated.'
      : 'La photo n’a pas pu être mise à jour.';
  String get markAllRead => isEnglish ? 'Mark all read' : 'Tout lire';
  String get notificationsError => isEnglish
      ? 'Notifications could not be loaded.'
      : 'Les notifications n’ont pas pu être chargées.';
  String get noNotifications =>
      isEnglish ? 'No notifications.' : 'Aucune notification.';
  String get search => isEnglish ? 'Search' : 'Recherche';
  String get searchHint => isEnglish
      ? 'Search the available catalogue and classes.'
      : 'Rechercher dans le catalogue et les classes disponibles.';
  String get searchError =>
      isEnglish ? 'Search failed.' : 'La recherche a échoué.';
  String get noSearchResults => isEnglish ? 'No results.' : 'Aucun résultat.';
  String get adminDashboard =>
      isEnglish ? 'Admin dashboard' : 'Tableau de bord admin';
  String get adminWelcome => 'Administration';
  String get academicYears => isEnglish ? 'Academic years' : 'Années scolaires';
  String get classes => 'Classes';
  String get students => isEnglish ? 'Students' : 'Élèves';
  String get teachers => isEnglish ? 'Teachers' : 'Enseignants';
  String get adminComingSoon => isEnglish
      ? 'Management module is being prepared.'
      : 'Le module de gestion est en préparation.';
  String get reviewPromotions =>
      isEnglish ? 'Review requests' : 'Revoir les demandes';
  String get adminLoadError => isEnglish
      ? 'Management data could not be loaded.'
      : 'Les données de gestion n’ont pas pu être chargées.';
  String get noAcademicYears => isEnglish
      ? 'No academic years configured.'
      : 'Aucune année scolaire configurée.';
  String get noClasses =>
      isEnglish ? 'No classes configured.' : 'Aucune classe configurée.';
  String get yearLabel => isEnglish ? 'Year label' : 'Libellé de l’année';
  String get noPeople =>
      isEnglish ? 'No users found.' : 'Aucun utilisateur trouvé.';
  String get edit => isEnglish ? 'Edit' : 'Modifier';
  String get setCurrent =>
      isEnglish ? 'Set as current' : 'Définir comme actuelle';
  String get disable => isEnglish ? 'Disable' : 'Désactiver';
  String get confirmation => isEnglish ? 'Confirmation' : 'Confirmation';
  String get confirm => isEnglish ? 'Confirm' : 'Confirmer';
  String get confirmDisable => isEnglish
      ? 'Disable this academic year?'
      : 'Désactiver cette année scolaire ?';
  String get studentSpace => isEnglish ? 'Student space' : 'Espace élève';
  String get teacherSpace => isEnglish ? 'Teacher space' : 'Espace enseignant';
  String get dashboard => isEnglish ? 'Dashboard' : 'Tableau de bord';
  String get hello => isEnglish ? 'Hello' : 'Bonjour';
  String get schoolClass => isEnglish ? 'Class' : 'Classe';
  String get subsystem => isEnglish ? 'Subsystem' : 'Sous-système';
  String get progress => isEnglish ? 'Progress' : 'Progression';
  String get timetable => isEnglish ? 'Timetable' : 'Emploi du temps';
  String get taughtClasses =>
      isEnglish ? 'Classes taught' : 'Classes enseignées';
  String get subjects => isEnglish ? 'Subjects' : 'Matières';
  String get signOut => isEnglish ? 'Log out' : 'Déconnexion';
  String get profileUnavailable => isEnglish
      ? 'Your profile could not be found.'
      : 'Votre profil est introuvable.';
  String get sessionError => isEnglish
      ? 'The session could not be loaded.'
      : 'La session n’a pas pu être chargée.';
  String get accessDenied => isEnglish
      ? 'This account has no available space yet.'
      : 'Cet espace n’est pas encore disponible pour ce compte.';
  String get welcomeBack =>
      isEnglish ? 'Your school overview' : 'Votre aperçu scolaire';
  String get comingSoon => isEnglish
      ? 'This section will be developed in the next step.'
      : 'Cette section sera développée à l’étape suivante.';
  String get back => isEnglish ? 'Back' : 'Retour';
  String get home => isEnglish ? 'Home' : 'Accueil';
  String get courses => isEnglish ? 'Courses' : 'Cours';
  String get lessons => isEnglish ? 'Lessons' : 'Leçons';
  String get objectives => isEnglish ? 'Objectives' : 'Objectifs';
  String get explanation => isEnglish ? 'Explanation' : 'Explication';
  String get examples => isEnglish ? 'Examples' : 'Exemples';
  String get summary => isEnglish ? 'Summary' : 'Résumé';
  String get previousLesson =>
      isEnglish ? 'Previous lesson' : 'Leçon précédente';
  String get nextLesson => isEnglish ? 'Next lesson' : 'Leçon suivante';
  String get markCompleted =>
      isEnglish ? 'Mark as completed' : 'Marquer comme terminée';
  String get pedagogyLoadError => isEnglish
      ? 'Learning content could not be loaded.'
      : 'Les contenus pédagogiques n’ont pas pu être chargés.';
  String get noCoursesYet => isEnglish
      ? 'Courses will appear here when your school or teachers publish them.'
      : 'Les cours apparaîtront ici lorsque votre établissement ou vos enseignants les auront publiés.';
  String get noCurriculumYet => isEnglish
      ? 'No curriculum is available for this subject yet.'
      : 'Aucun programme n’est encore disponible pour cette matière.';
  String get noPublishedCourses => isEnglish
      ? 'No published course is available yet.'
      : 'Aucun cours publié n’est encore disponible.';
  String get noPublishedLessons => isEnglish
      ? 'No published lesson is available yet.'
      : 'Aucune leçon publiée n’est encore disponible.';
  String get myCourses => isEnglish ? 'My courses' : 'Mes cours';
  String get createCourse => isEnglish ? 'Create course' : 'Créer un cours';
  String get draft => isEnglish ? 'Draft' : 'Brouillon';
  String get published => isEnglish ? 'Published' : 'Publié';
  String get archived => isEnglish ? 'Archived' : 'Archivé';
  String get archive => isEnglish ? 'Archive' : 'Archiver';
  String get noTeacherCourses => isEnglish
      ? 'You have not created any course yet.'
      : 'Vous n’avez encore créé aucun cours.';
  String get curriculum => isEnglish ? 'Curriculum' : 'Programme';
  String get chapter => isEnglish ? 'Chapter' : 'Chapitre';
  String get titleFrench => isEnglish ? 'French title' : 'Titre français';
  String get titleEnglish => isEnglish ? 'English title' : 'Titre anglais';
  String get descriptionFrench =>
      isEnglish ? 'French description' : 'Description française';
  String get descriptionEnglish =>
      isEnglish ? 'English description' : 'Description anglaise';
  String get contentFrench => isEnglish ? 'French content' : 'Contenu français';
  String get contentEnglish =>
      isEnglish ? 'English content' : 'Contenu anglais';
  String get saveDraft => isEnglish ? 'Save draft' : 'Enregistrer le brouillon';
  String get publish => isEnglish ? 'Publish' : 'Publier';
  String get completeCourseFields => isEnglish
      ? 'Complete the class, subject, curriculum and chapter fields.'
      : 'Complétez les champs classe, matière, programme et chapitre.';
  String get courseSaveError => isEnglish
      ? 'The course could not be saved.'
      : 'Le cours n’a pas pu être enregistré.';
  String get assignments => isEnglish ? 'Assignments' : 'Devoirs';
  String get notifications => isEnglish ? 'Notifications' : 'Notifications';
  String get messages => isEnglish ? 'Messages' : 'Messages';
  String get profile => isEnglish ? 'Profile' : 'Profil';
  String get login => isEnglish ? 'Log in' : 'Connexion';
  String get register => isEnglish ? 'Sign up' : 'Inscription';
  String get profileRole => isEnglish ? 'Profile type' : 'Type de profil';
  String get identifier =>
      isEnglish ? 'Email address' : 'Adresse e-mail';

  String get email =>
      isEnglish ? 'Email address' : 'Adresse e-mail';
  String get invalidEmail =>
      isEnglish ? 'Enter a valid email address.' : 'Entrez une adresse e-mail valide.';
  String get emailOptional =>
      isEnglish ? 'Email address' : 'Adresse e-mail';
  String get firstName => isEnglish ? 'First name' : 'Prénom';
  String get lastName => isEnglish ? 'Last name' : 'Nom';
  String get password => isEnglish ? 'Password' : 'Mot de passe';
  String get submitLogin => isEnglish ? 'Log in' : 'Se connecter';
  String get submitRegister => isEnglish ? 'Create account' : 'Créer le compte';
  String get switchToRegister => isEnglish
      ? 'No account? Create one'
      : 'Pas encore de compte ? Créer un compte';
  String get switchToLogin => isEnglish
      ? 'Already have an account? Log in'
      : 'Vous avez déjà un compte ? Se connecter';
  String get requiredField =>
      isEnglish ? 'Required field' : 'Champ obligatoire';
  String get accountCreated => isEnglish
      ? 'Account created. Check your email to verify your account.'
      : 'Compte créé. Vérifiez votre e-mail pour confirmer votre compte.';

  // --- Inscription : choix du sous-système, du secteur et de la classe ---
  String get chooseYourClass =>
      isEnglish ? 'Choose your class' : 'Choisissez votre classe';
  String get classLabel => isEnglish ? 'Class' : 'Classe';
  String get sectorLabel => isEnglish ? 'Sector' : 'Secteur';
  String get subsystemLabel => isEnglish ? 'Subsystem' : 'Sous-système';
  String get examClassBadge => isEnglish ? 'Exam class' : 'Classe d’examen';
  String examPrepared(String exam) =>
      isEnglish ? 'Exam: $exam' : 'Examen : $exam';
  String get curriculumLabel => isEnglish ? 'Curriculum' : 'Programme';
  String get trackOptional => isEnglish
      ? 'Series / specialty (optional)'
      : 'Série / spécialité (facultatif)';
  String get retry => isEnglish ? 'Retry' : 'Réessayer';
  String get selectionRequired =>
      isEnglish ? 'Please make a selection' : 'Veuillez faire un choix';
  String get noClassesForChoice => isEnglish
      ? 'No class is available for this choice yet.'
      : 'Aucune classe n’est encore disponible pour ce choix.';
  String get networkError => isEnglish
      ? 'A network error occurred. Please try again.'
      : 'Une erreur réseau est survenue. Veuillez réessayer.';
  String get accountCreatedWelcome =>
      isEnglish ? 'Account created. Welcome!' : 'Compte créé. Bienvenue !';
  String get passwordTooShort => isEnglish
      ? 'At least 6 characters required'
      : '6 caractères minimum';
}
