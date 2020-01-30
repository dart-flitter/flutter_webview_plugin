import 'package:flutter/material.dart';

class MyAlertDialog extends StatelessWidget {
  final String message;

  MyAlertDialog({this.message = ''});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Text(message),
      actions: <Widget>[
        FlatButton(
            child: const Text('OK'),
            onPressed: () {
              Navigator.of(context).pop();
            }),
      ],
    );
  }
}

class ConfirmDialog extends StatelessWidget {
  final String message;

  ConfirmDialog({this.message = ''});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Text(message),
      actions: <Widget>[
        FlatButton(
            child: const Text('Cancel'),
            onPressed: () {
              Navigator.of(context).pop(false);
            }),
        FlatButton(
            child: const Text('OK'),
            onPressed: () {
              Navigator.of(context).pop(true);
            }),
      ],
    );
  }
}

class PromptDialog extends StatefulWidget {
  final String message;
  final String defaultText;

  PromptDialog({Key key, this.message, this.defaultText = ''})
      : super(key: key);

  @override
  _PromptDialogState createState() => _PromptDialogState();
}

class _PromptDialogState extends State<PromptDialog> {
  TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.text = widget.defaultText;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(widget.message),
            TextField(controller: _controller),
          ]),
      actions: <Widget>[
        FlatButton(
            child: const Text('Cancel'),
            onPressed: () {
              Navigator.of(context).pop('');
            }),
        FlatButton(
            child: const Text('OK'),
            onPressed: () {
              Navigator.of(context).pop(_controller.text);
            }),
      ],
    );
  }
}
