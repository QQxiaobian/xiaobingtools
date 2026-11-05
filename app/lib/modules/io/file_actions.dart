import 'dart:io';

import 'package:flutter/material.dart';

import 'data_io.dart';

Future<void> showExportResult(
  BuildContext context,
  File file, {
  String title = '导出成功',
}) async {
  final path = file.path;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SelectableText('文件已保存到：\n$path'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(ctx);
            DataIo.shareFile(file);
          },
          icon: const Icon(Icons.share),
          label: const Text('分享/发送'),
        ),
      ],
    ),
  );
}
