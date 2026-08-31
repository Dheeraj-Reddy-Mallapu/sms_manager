import 'package:material_ui/material_ui.dart';

class ComposePage extends StatelessWidget {
  const ComposePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New message'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        actions: [
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
        ],
      ),
      body: const Center(child: Text('Compose Page Placeholder')),
    );
  }
}
