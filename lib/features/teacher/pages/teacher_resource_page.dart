import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/services/pedagogy_service.dart';
import '../../../core/services/smart_course_service.dart';
import '../../../models/pedagogy.dart';
import '../../../models/user_profile.dart';

class TeacherResourcePage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final Course course;
  final Lesson? lesson;

  const TeacherResourcePage({
    super.key,
    required this.locale,
    required this.profile,
    required this.course,
    this.lesson,
  });

  @override
  State<TeacherResourcePage> createState() => _TeacherResourcePageState();
}

class _TeacherResourcePageState extends State<TeacherResourcePage> {
  final ResourceService _service = ResourceService();
  final SmartCourseService _smart = SmartCourseService();

  late Future<List<CourseResource>> _resourcesFuture;

  bool get _isFrench => widget.locale.languageCode == 'fr';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    if (widget.lesson != null) {
      _resourcesFuture = _service.listForLesson(widget.lesson!.id);
    } else {
      _resourcesFuture = _service.listForCourse(widget.course.id);
    }
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _resourcesFuture;
  }

  String _pageTitle() {
    if (widget.lesson != null) {
      return _isFrench ? 'Ressources de la leçon' : 'Lesson resources';
    }

    return _isFrench ? 'Ressources du cours' : 'Course resources';
  }

  String _courseTitle() {
    return _isFrench ? widget.course.titleFr : widget.course.titleEn;
  }

  String _resourceTitle(CourseResource resource) {
    final title = _isFrench ? resource.titleFr : resource.titleEn;

    if (title.trim().isNotEmpty) {
      return title.trim();
    }

    return resource.fileName;
  }

  String _resourceTypeLabel(String type) {
    switch (type) {
      case 'pdf':
        return 'PDF';

      case 'document':
        return _isFrench ? 'Document' : 'Document';

      case 'image':
        return _isFrench ? 'Image' : 'Image';

      case 'video':
        return _isFrench ? 'Vidéo' : 'Video';

      case 'audio':
        return _isFrench ? 'Audio' : 'Audio';

      default:
        return type;
    }
  }

  IconData _resourceIcon(String type) {
    switch (type) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;

      case 'document':
        return Icons.description_rounded;

      case 'image':
        return Icons.image_rounded;

      case 'video':
        return Icons.video_library_rounded;

      case 'audio':
        return Icons.audio_file_rounded;

      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  String _detectResourceType(PlatformFile file) {
    final extension = file.extension?.toLowerCase() ?? '';

    switch (extension) {
      case 'pdf':
        return 'pdf';

      case 'doc':
      case 'docx':
      case 'odt':
      case 'txt':
      case 'rtf':
        return 'document';

      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
        return 'image';

      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
      case 'webm':
        return 'video';

      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'aac':
      case 'ogg':
        return 'audio';

      default:
        return 'document';
    }
  }

  Future<void> _pickAndUpload() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp',
          'mp4', 'mov', 'avi', 'mkv', 'webm',
        ],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;

      if (file.bytes == null || file.bytes!.isEmpty) {
        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isFrench
                  ? 'Impossible de lire le fichier sélectionné.'
                  : 'Unable to read the selected file.',
            ),
          ),
        );

        return;
      }

      final type = _detectResourceType(file);
      if (type != 'image' && type != 'video') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_isFrench
                ? 'Seules les photos et les vidéos sont autorisées pour les enseignants.'
                : 'Teachers can only upload photos and videos.')),
          );
        }
        return;
      }
      final position = await _nextPosition();

      if (!mounted) {
        return;
      }

      final resource = await _service.uploadResource(
        courseId: widget.course.id,
        lessonId: widget.lesson?.id,
        file: file,
        resourceType: type,
        position: position,
      );

      if (type == 'pdf') {
        try {
          await _smart.reindexPdf(resource.id);
        } catch (indexError) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_isFrench ? 'PDF ajouté, mais l’indexation a échoué : $indexError' : 'PDF added, but indexing failed: $indexError')),
            );
          }
        }
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFrench
                ? 'Ressource ajoutée avec succès.'
                : 'Resource added successfully.',
          ),
        ),
      );

      await _refresh();
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<int> _nextPosition() async {
    final resources = widget.lesson != null
        ? await _service.listForLesson(widget.lesson!.id)
        : await _service.listForCourse(widget.course.id);

    if (resources.isEmpty) {
      return 0;
    }

    var maxPosition = 0;

    for (final resource in resources) {
      final position = resource.position ?? 0;

      if (position > maxPosition) {
        maxPosition = position;
      }
    }

    return maxPosition + 1;
  }

  Future<void> _openResource(CourseResource resource) async {
    try {
      final url = await _service.createSignedUrl(resource.storagePath);

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(_resourceTitle(resource)),
            content: SelectableText(url),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: Text(_isFrench ? 'Fermer' : 'Close'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _deleteResource(CourseResource resource) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_isFrench ? 'Supprimer la ressource' : 'Delete resource'),
          content: Text(
            _isFrench
                ? 'Voulez-vous vraiment supprimer cette ressource ?'
                : 'Do you really want to delete this resource?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: Text(_isFrench ? 'Annuler' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(_isFrench ? 'Supprimer' : 'Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _service.deleteResource(resource);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFrench ? 'Ressource supprimée.' : 'Resource deleted.',
          ),
        ),
      );

      await _refresh();
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _showResourceDetails(CourseResource resource) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _resourceIcon(resource.resourceType),
                      color: const Color(0xFF166534),
                      size: 30,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _resourceTitle(resource),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _DetailRow(
                  label: _isFrench ? 'Type' : 'Type',
                  value: _resourceTypeLabel(resource.resourceType),
                ),
                const SizedBox(height: 10),
                _DetailRow(
                  label: _isFrench ? 'Fichier' : 'File',
                  value: resource.fileName,
                ),
                const SizedBox(height: 10),
                _DetailRow(
                  label: _isFrench ? 'Position' : 'Position',
                  value: (resource.position ?? 0).toString(),
                ),
                const SizedBox(height: 10),
                _DetailRow(
                  label: _isFrench ? 'Indexation' : 'Indexing',
                  value: resource.resourceType == 'pdf'
                      ? (resource.indexStatus == 'indexed'
                          ? (resource.indexApproved ? (_isFrench ? 'Validée' : 'Approved') : (_isFrench ? 'À valider' : 'Awaiting approval'))
                          : resource.indexStatus)
                      : (_isFrench ? 'Non applicable' : 'Not applicable'),
                ),
                if (resource.indexError.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(resource.indexError, style: const TextStyle(color: Colors.redAccent)),
                ],
                if (resource.resourceType == 'pdf' && resource.indexPreview.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(_isFrench ? 'Aperçu IA' : 'AI preview', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10)),
                    child: Text(resource.indexPreview, maxLines: 10, overflow: TextOverflow.ellipsis),
                  ),
                ],
                const SizedBox(height: 16),
                if (resource.resourceType == 'pdf')
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            await _smart.reindexPdf(resource.id);
                            if (sheetContext.mounted) {
                              Navigator.of(sheetContext).pop();
                              await _refresh();
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                            }
                          }
                        },
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(_isFrench ? 'Réindexer' : 'Re-index'),
                      ),
                      if (resource.indexStatus == 'indexed' && !resource.indexApproved)
                        FilledButton.icon(
                          onPressed: () async {
                            await _smart.approveIndex(resource.id);
                            if (sheetContext.mounted) {
                              Navigator.of(sheetContext).pop();
                              await _refresh();
                            }
                          },
                          icon: const Icon(Icons.verified_rounded),
                          label: Text(_isFrench ? 'Valider pour l’IA' : 'Approve for AI'),
                        ),
                    ],
                  ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _openResource(resource);
                    },
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(
                      _isFrench ? 'Ouvrir la ressource' : 'Open resource',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _pageTitle(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: _isFrench ? 'Actualiser' : 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickAndUpload,
        backgroundColor: const Color(0xFF166534),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(_isFrench ? 'Ajouter' : 'Add'),
      ),
      body: SafeArea(
        child: FutureBuilder<List<CourseResource>>(
          future: _resourcesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _ErrorState(
                message: snapshot.error.toString(),
                isFrench: _isFrench,
                onRetry: _refresh,
              );
            }

            final resources = snapshot.data ?? const [];

            if (resources.isEmpty) {
              return _EmptyState(
                courseTitle: _courseTitle(),
                isFrench: _isFrench,
                onAdd: _pickAndUpload,
              );
            }

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: resources.length + 1,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _CourseHeader(
                      courseTitle: _courseTitle(),
                      count: resources.length,
                      isFrench: _isFrench,
                    );
                  }

                  final resource = resources[index - 1];

                  return _ResourceCard(
                    resource: resource,
                    title: _resourceTitle(resource),
                    typeLabel: _resourceTypeLabel(resource.resourceType),
                    icon: _resourceIcon(resource.resourceType),
                    isFrench: _isFrench,
                    onOpen: () => _openResource(resource),
                    onDetails: () => _showResourceDetails(resource),
                    onDelete: () => _deleteResource(resource),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CourseHeader extends StatelessWidget {
  final String courseTitle;
  final int count;
  final bool isFrench;

  const _CourseHeader({
    required this.courseTitle,
    required this.count,
    required this.isFrench,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: const Color(0xFFF0FDF4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFDCFCE7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF166534),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.folder_copy_rounded, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    courseTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    isFrench
                        ? '$count ressource${count > 1 ? 's' : ''}'
                        : '$count resource${count > 1 ? 's' : ''}',
                    style: const TextStyle(
                      color: Color(0xFF166534),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResourceCard extends StatelessWidget {
  final CourseResource resource;
  final String title;
  final String typeLabel;
  final IconData icon;
  final bool isFrench;
  final VoidCallback onOpen;
  final VoidCallback onDetails;
  final VoidCallback onDelete;

  const _ResourceCard({
    required this.resource,
    required this.title,
    required this.typeLabel,
    required this.icon,
    required this.isFrench,
    required this.onOpen,
    required this.onDetails,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: const Color(0xFF166534), size: 28),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      typeLabel,
                      style: const TextStyle(
                        color: Color(0xFF166534),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      resource.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'open':
                      onOpen();
                      break;

                    case 'details':
                      onDetails();
                      break;

                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'open',
                    child: Row(
                      children: [
                        const Icon(Icons.open_in_new_rounded),
                        const SizedBox(width: 10),
                        Text(isFrench ? 'Ouvrir' : 'Open'),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'details',
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded),
                        const SizedBox(width: 10),
                        Text(isFrench ? 'Détails' : 'Details'),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline_rounded),
                        const SizedBox(width: 10),
                        Text(isFrench ? 'Supprimer' : 'Delete'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String courseTitle;
  final bool isFrench;
  final VoidCallback onAdd;

  const _EmptyState({
    required this.courseTitle,
    required this.isFrench,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(26),
              ),
              child: const Icon(
                Icons.folder_open_rounded,
                size: 48,
                color: Color(0xFF166534),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isFrench ? 'Aucune ressource' : 'No resources',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              courseTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isFrench
                  ? 'Ajoutez une photo ou une vidéo.'
                  : 'Add a photo or video.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                isFrench ? 'Ajouter une ressource' : 'Add a resource',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final bool isFrench;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.message,
    required this.isFrench,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 60,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 16),
            Text(
              isFrench
                  ? 'Impossible de charger les ressources.'
                  : 'Unable to load resources.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(isFrench ? 'Réessayer' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
