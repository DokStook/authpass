import 'dart:io';
import 'package:authpass/bloc/kdbx/file_source.dart';
import 'package:authpass/bloc/kdbx/file_source_local.dart';
import 'package:authpass/bloc/kdbx_bloc.dart';
import 'package:authpass/cloud_storage/cloud_storage_provider.dart';
import 'package:authpass/bloc/kdbx/file_source_ui.dart';
import 'package:authpass/utils/platform.dart';
import 'package:logging/logging.dart';
import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'package:file_chooser/file_chooser.dart';
import 'package:file_picker_writable/file_picker_writable.dart';

import 'package:authpass/bloc/app_data.dart';
import 'package:authpass/cloud_storage/cloud_storage_ui.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_async_utils/flutter_async_utils.dart';

final _logger = Logger('manage_file');

typedef FileSourceChanged = void Function(FileSource newFileSource);
typedef OnSave = void Function(Future<KdbxOpenedFile> saveFuture);

class SaveFileAs extends StatefulWidget {
  const SaveFileAs({
    @required this.title,
    @required this.file,
    this.icon,
    this.cs,
    @required this.onSave,
    this.subtitle,
  })  : assert(title != null),
        assert(file != null),
        assert(onSave != null),
        assert((icon != null && subtitle != null) || cs != null);

  final OnSave onSave;
  final KdbxOpenedFile file;
  final String title;
  final String subtitle;
  final Icon icon;
  final CloudStorageProvider cs;
  bool get local => cs == null;

  @override
  _SaveFileAsState createState() => _SaveFileAsState();
}

class _SaveFileAsState extends State<SaveFileAs> with FutureTaskStateMixin {
  KdbxBloc kdbxBloc;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    _init();
    super.didChangeDependencies();
  }

  void _init() {
    kdbxBloc ??= context.read<KdbxBloc>();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: widget.icon ?? Icon(widget.cs.displayIcon.iconData),
      title: Text(widget.title),
      subtitle: Text(widget.subtitle ?? widget.cs.displayName),
      onTap: () async {
        _logger.fine('saving. ${widget.local}');
        if (widget.local) {
          final fs = await _selectLocalFileSource();
          if (fs != null) {
            widget.onSave(kdbxBloc.saveAs(widget.file, fs));
          }
        } else {
          final result = await _saveAsCloudStorage(widget.cs);
          if (result != null) {
            widget
                .onSave(kdbxBloc.saveAsNewFile(widget.file, result, widget.cs));
          }
        }
      },
    );
  }

  Future<FileSource> _selectLocalFileSource() async {
    if (AuthPassPlatform.isIOS || AuthPassPlatform.isAndroid) {
      final fileInfo = await FileSourceLocal.createFileInNewTempDirectory(
          '${path.basenameWithoutExtension(widget.file.fileSource.displayPath)}.kdbx',
          (tempFile) async {
        return await FilePickerWritable().openFileForCreate(
          fileName:
              '${path.basenameWithoutExtension(widget.file.fileSource.displayPath)}.kdbx',
          writer: (file) async {
            _logger.fine('Writing placeholder into $file');
            await file.writeAsString('<placeholder>');
          },
        );
      });

      if (fileInfo == null) {
        _logger.info('User cancelled file picker.');
        return null;
      }
      _logger.fine('writing to ${fileInfo.uri} / ${fileInfo.fileName}');
      return FileSourceLocal(
        File(fileInfo.fileName),
        databaseName: widget.file.fileSource.displayName,
        uuid: AppDataBloc.createUuid(),
        filePickerIdentifier: fileInfo.toJsonString(),
      );
    }
    final result = await showSavePanel(
      suggestedFileName: path.basename(widget.file.fileSource.displayPath),
      confirmButtonText: 'Save',
    );
    if (result.canceled) {
      return null;
    }

    final pathFile = result.paths.first;
    final outputFile = File(pathFile);
    String macOsBookmark;
    if (AuthPassPlatform.isMacOS) {
      // create a dummy file, so we can create a secure bookmark.
      await outputFile.writeAsString('.');
      macOsBookmark = await SecureBookmarks().bookmark(outputFile);
    }
    return FileSourceLocal(
      outputFile,
      uuid: AppDataBloc.createUuid(),
      macOsSecureBookmark: macOsBookmark,
    );
  }

  Future<CloudStorageSelectorSaveResult> _saveAsCloudStorage(
      CloudStorageProvider cs) async {
    _logger.fine('pushing cloud storage selector.');
    final createFileInfo =
        await Navigator.of(context).push(CloudStorageSelector.route(
      cs,
      CloudStorageBrowserConfig(
          defaultFileName: path.basename(widget.file.fileSource.displayPath),
          isSave: true),
    ));
    _logger.fine('done. $createFileInfo');
    return createFileInfo;
  }
}
