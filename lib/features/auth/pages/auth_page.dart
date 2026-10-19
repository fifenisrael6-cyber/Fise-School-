import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/auth_messages.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/exam_catalog_service.dart';
import '../../../models/exam_catalog.dart';
import 'forgot_password_page.dart';

class AuthPage extends StatefulWidget {
  final Locale locale;
  final bool startInRegisterMode;
  final String initialRole;

  /// Permet d'injecter un service de catalogue (tests). Par défaut, le service
  /// Supabase est créé uniquement quand l'inscription en a besoin.
  final ExamCatalogService? catalogService;

  const AuthPage({
    super.key,
    required this.locale,
    this.startInRegisterMode = false,
    this.initialRole = 'student',
    this.catalogService,
  });

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  ExamCatalogService? _catalogService;

  late bool _isRegistering = widget.startInRegisterMode;
  late String _role = widget.initialRole;
  bool _isLoading = false;
  bool _obscurePassword = true;

  // Choix scolaire fait par l'utilisateur pendant l'inscription.
  ExamSubsystem? _subsystem;
  ExamSector? _sector;
  ExamLevel? _level;
  ExamCatalogEntry? _track;
  String? _languageOption;
  String? _languageOption2;
  static const _languageOptions = <String, String>{
    'allemand': 'Allemand',
    'espagnol': 'Espagnol',
    'arabe': 'Arabe',
    'italien': 'Italien',
    'chinois': 'Chinois',
  };
  List<ExamLevel> _levels = const [];
  List<ExamCatalogEntry> _tracks = const [];
  bool _loadingLevels = false;
  bool _catalogError = false;

  bool get _isStudent => _role == 'student';
  String get _lang => widget.locale.languageCode;

  ExamCatalogService get _catalog =>
      _catalogService ??= widget.catalogService ?? ExamCatalogService();

  @override
  void dispose() {
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadLevels() async {
    final subsystem = _subsystem;
    final sector = _sector;
    setState(() {
      _level = null;
      _track = null;
      _languageOption = null;
      _languageOption2 = null;
      _levels = const [];
      _tracks = const [];
      _catalogError = false;
    });
    if (subsystem == null || sector == null) {
      return;
    }

    setState(() => _loadingLevels = true);
    try {
      final levels = await _catalog.getExamLevels(
        subsystem: subsystem,
        sector: sector,
      );
      if (!mounted || subsystem != _subsystem || sector != _sector) {
        return;
      }
      setState(() => _levels = levels);
    } catch (_) {
      if (mounted && subsystem == _subsystem && sector == _sector) {
        setState(() => _catalogError = true);
      }
    } finally {
      // Ne réinitialise le chargement que si la sélection n'a pas changé entre-temps.
      if (mounted && subsystem == _subsystem && sector == _sector) {
        setState(() => _loadingLevels = false);
      }
    }
  }

  Future<void> _loadTracks(ExamLevel level) async {
    setState(() {
      _track = null;
      _languageOption = null;
      _languageOption2 = null;
      _tracks = const [];
    });
    try {
      final tracks = level.sector == ExamSector.general
          ? await _catalog.getSeriesForLevel(level.id)
          : await _catalog.getSpecialtiesForLevel(level.id);
      if (!mounted || _level?.id != level.id) {
        return;
      }
      setState(() => _tracks = tracks);
    } catch (_) {
      // Série/spécialité facultative : une erreur ne bloque pas l'inscription.
    }
  }

  Future<void> _submit(AppTexts texts) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isLoading = true);
    try {
      var signedIn = true;
      if (_isRegistering) {
        final level = _isStudent ? _level : null;
        final isGeneral = _sector == ExamSector.general;
        signedIn = await _authService.signUp(
          email: _emailController.text,
          password: _passwordController.text,
          firstName: _firstNameController.text,
          lastName: _lastNameController.text,
          role: _role,
          subsystem: _subsystem?.name,
          sector: _sector?.name,
          examLevelId: level?.id,
          examId: level?.exam?.id,
          seriesId: isGeneral ? _track?.id : null,
          specialtyId: isGeneral ? null : _track?.id,
          examLevel: level?.labelFor(_lang),
          exam: level?.exam?.labelFor(_lang),
          track: _track?.labelFor(_lang),
          className: level?.labelFor(_lang),
          languageOption: _languageOption == null
              ? null
              : _track?.code.toLowerCase() == 'a5' && _languageOption2 != null
                  ? '${_languageOption}_${_languageOption2}'
                  : _languageOption,
        );
      } else {
        await _authService.signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }
      if (!mounted) {
        return;
      }

      // Pas de message après une simple connexion : le tableau de bord suffit.
      if (_isRegistering) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              signedIn ? texts.accountCreatedWelcome : texts.accountCreated,
            ),
          ),
        );
      }
      // AuthGate affiche le tableau de bord dès que la session existe : on
      // revient donc à la racine (auparavant la page d'inscription restait ouverte).
      if (!_isRegistering || signedIn) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        // Inscription réussie mais confirmation e-mail requise : on passe au
        // formulaire de connexion au lieu de laisser le formulaire d'inscription.
        setState(() => _isRegistering = false);
      }
    } on AuthException catch (error) {
      if (mounted) {
        _showError(
          AuthMessages.from(
            error,
            english: _lang == 'en',
            registering: _isRegistering,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        _showError(texts.networkError);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

  String? _validEmail(String? value, AppTexts texts) {
    final email = (value ?? '').trim();
    if (email.isEmpty) {
      return texts.requiredField;
    }
    if (!_emailPattern.hasMatch(email)) {
      return texts.invalidEmail;
    }
    return null;
  }

  String? _required(String? value, String message) =>
      value == null || value.trim().isEmpty ? message : null;

  @override
  Widget build(BuildContext context) {
    final texts = AppTexts(widget.locale);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isRegistering ? texts.register : texts.login),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isRegistering)
                      ..._registerFields(texts)
                    else
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: texts.email,
                        ),
                        validator: (value) => _validEmail(value, texts),
                      ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: texts.password,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      validator: (value) {
                        final required = _required(value, texts.requiredField);
                        if (required != null) {
                          return required;
                        }
                        if (_isRegistering && value!.length < 6) {
                          return texts.passwordTooShort;
                        }
                        return null;
                      },
                    ),
                    if (!_isRegistering)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _isLoading
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => ForgotPasswordPage(locale: widget.locale),
                                    ),
                                  ),
                          child: Text(
                            widget.locale.languageCode == 'fr'
                                ? 'Mot de passe oublié ?'
                                : 'Forgot password?',
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _isLoading ? null : () => _submit(texts),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _isRegistering
                                  ? texts.submitRegister
                                  : texts.submitLogin,
                            ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => setState(
                              () => _isRegistering = !_isRegistering,
                            ),
                      child: Text(
                        _isRegistering
                            ? texts.switchToLogin
                            : texts.switchToRegister,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _registerFields(AppTexts texts) {
    return [
      DropdownButtonFormField<String>(
        initialValue: _role,
        decoration: InputDecoration(labelText: texts.profileRole),
        items: [
          DropdownMenuItem(value: 'student', child: Text(texts.student)),
          DropdownMenuItem(value: 'teacher', child: Text(texts.teacher)),
        ],
        onChanged: (value) {
          if (value != null) {
            setState(() => _role = value);
          }
        },
      ),
      const SizedBox(height: 14),
      _field(_firstNameController, texts.firstName, texts),
      const SizedBox(height: 14),
      _field(_lastNameController, texts.lastName, texts),
      const SizedBox(height: 14),
      TextFormField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(labelText: texts.email),
        validator: (value) => _validEmail(value, texts),
      ),
      const SizedBox(height: 22),
      ..._schoolChoiceFields(texts),
    ];
  }

  /// Sous-système -> secteur -> classe (-> série/spécialité) : choisis par
  /// l'élève lui-même. Les classes proviennent du catalogue (toutes les classes,
  /// pas uniquement celles d'examen), selon le programme de chaque sous-système.
  List<Widget> _schoolChoiceFields(AppTexts texts) {
    return [
      Text(
        texts.chooseYourClass,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: Color(0xFF14532D),
        ),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<ExamSubsystem>(
        key: const ValueKey('subsystem'),
        initialValue: _subsystem,
        isExpanded: true,
        decoration: InputDecoration(labelText: texts.subsystemLabel),
        items: [
          DropdownMenuItem(
            value: ExamSubsystem.francophone,
            child: Text('🇫🇷  ${texts.francophone}'),
          ),
          DropdownMenuItem(
            value: ExamSubsystem.anglophone,
            child: Text('🇬🇧  ${texts.anglophone}'),
          ),
        ],
        validator: (value) => value == null ? texts.selectionRequired : null,
        onChanged: (value) {
          setState(() => _subsystem = value);
          _loadLevels();
        },
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<ExamSector>(
        key: const ValueKey('sector'),
        initialValue: _sector,
        isExpanded: true,
        decoration: InputDecoration(labelText: texts.sectorLabel),
        items: [
          DropdownMenuItem(
            value: ExamSector.general,
            child: Text(texts.general),
          ),
          DropdownMenuItem(
            value: ExamSector.technical,
            child: Text(texts.technical),
          ),
        ],
        validator: (value) => value == null ? texts.selectionRequired : null,
        onChanged: (value) {
          setState(() => _sector = value);
          _loadLevels();
        },
      ),
      if (_isStudent) ...[
        const SizedBox(height: 14),
        ..._classFields(texts),
      ],
    ];
  }

  List<Widget> _classFields(AppTexts texts) {
    if (_subsystem == null || _sector == null) {
      return const [];
    }
    if (_loadingLevels) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_catalogError) {
      return [
        Text(texts.catalogUnavailable, textAlign: TextAlign.center),
        TextButton.icon(
          onPressed: _loadLevels,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(texts.retry),
        ),
      ];
    }
    if (_levels.isEmpty) {
      return [Text(texts.noClassesForChoice, textAlign: TextAlign.center)];
    }

    final level = _level;
    final curriculum = level?.curriculumFor(_lang);
    return [
      DropdownButtonFormField<ExamLevel>(
        key: ValueKey('level-${_subsystem?.name}-${_sector?.name}'),
        initialValue: level,
        isExpanded: true,
        decoration: InputDecoration(labelText: texts.classLabel),
        items: [
          for (final item in _levels)
            DropdownMenuItem(
              value: item,
              child: Text(
                item.exam == null
                    ? item.labelFor(_lang)
                    : '${item.labelFor(_lang)} — ${item.exam!.labelFor(_lang)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        validator: (value) => value == null ? texts.selectionRequired : null,
        onChanged: (value) {
          setState(() => _level = value);
          if (value != null) {
            _loadTracks(value);
          }
        },
      ),
      if (level != null) ...[
        const SizedBox(height: 10),
        _levelInfo(texts, level, curriculum),
      ],
      if (_tracks.isNotEmpty) ...[
        const SizedBox(height: 14),
        DropdownButtonFormField<ExamCatalogEntry>(
          key: ValueKey('track-${level?.id}'),
          initialValue: _track,
          isExpanded: true,
          decoration: InputDecoration(labelText: texts.trackOptional),
          items: [
            for (final item in _tracks)
              DropdownMenuItem(
                value: item,
                child: Text(
                  item.labelFor(_lang),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          validator: (value) =>
              _isStudent && value == null ? texts.selectionRequired : null,
          onChanged: (value) => setState(() {
            _track = value;
            _languageOption = null;
          _languageOption2 = null;
          }),
        ),
      ],
      if (_needsLanguageOption(level)) ...[
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          key: ValueKey('language-option-${level?.id}-${_track?.code}'),
          initialValue: _languageOption,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: _lang == 'en' ? 'Language option' : 'Langue vivante',
          ),
          items: [
            for (final entry in _languageOptions.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text(
                  _lang == 'en'
                      ? const {
                          'allemand': 'German',
                          'espagnol': 'Spanish',
                          'arabe': 'Arabic',
                          'italien': 'Italian',
                          'chinois': 'Chinese',
                        }[entry.key]!
                      : entry.value,
                ),
              ),
          ],
          validator: (value) =>
              _isStudent && value == null ? texts.selectionRequired : null,
          onChanged: (value) => setState(() {
            _languageOption = value;
            if (_languageOption2 == value) _languageOption2 = null;
          }),
        ),
        if (_track?.code.toLowerCase() == 'a5') ...[
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: ValueKey('language-option-2-${level?.id}-${_track?.code}'),
            initialValue: _languageOption2,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: _lang == 'en' ? 'Second language option' : 'Deuxième langue vivante',
            ),
            items: [
              for (final entry in _languageOptions.entries.where((e) => e.key != _languageOption))
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(
                    _lang == 'en'
                        ? const {
                            'allemand': 'German',
                            'espagnol': 'Spanish',
                            'arabe': 'Arabic',
                            'italien': 'Italian',
                            'chinois': 'Chinese',
                          }[entry.key]!
                        : entry.value,
                  ),
                ),
            ],
            validator: (value) =>
                _isStudent && value == null ? texts.selectionRequired : null,
            onChanged: (value) => setState(() => _languageOption2 = value),
          ),
        ],
      ],
    ];
  }

  bool _needsLanguageOption(ExamLevel? level) {
    if (level == null ||
        _subsystem != ExamSubsystem.francophone ||
        _sector != ExamSector.general) {
      return false;
    }
    if (level.code == 'fr_general_troisieme') return true;
    return const {'a2', 'a4', 'a5'}.contains(_track?.code.toLowerCase());
  }

  Widget _levelInfo(AppTexts texts, ExamLevel level, String? curriculum) {
    final lines = <String>[
      if (level.exam != null) texts.examPrepared(level.exam!.labelFor(_lang)),
      if (curriculum != null && curriculum.isNotEmpty)
        '${texts.curriculumLabel} : $curriculum',
      if (level.verification == VerificationStatus.pendingOfficialConfirmation)
        texts.verificationPending,
    ];
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5ED),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (level.isExamClass)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                texts.examClassBadge,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF166534),
                ),
              ),
            ),
          for (final line in lines)
            Text(line, style: const TextStyle(color: Color(0xFF244331))),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    AppTexts texts,
  ) => TextFormField(
    controller: controller,
    decoration: InputDecoration(labelText: label),
    validator: (value) => _required(value, texts.requiredField),
  );
}
