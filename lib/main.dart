// Copyright by Stefan Schmidt
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MyApp());

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {PointerDeviceKind.touch, PointerDeviceKind.mouse};
}

class ArrowData {
  Offset start;
  Offset end;
  String length;
  String unit;
  String comment;
  ArrowData({required this.start, required this.end, this.length = "", this.unit = "mm", this.comment = ""});

  factory ArrowData.fromJson(Map<String, dynamic> json) => ArrowData(
    start: Offset(json['start']['dx'], json['start']['dy']),
    end: Offset(json['end']['dx'], json['end']['dy']),
    length: json['length'] ?? "",
    unit: json['unit'] ?? "mm",
    comment: json['comment'] ?? "",
  );

  Map<String, dynamic> toJson() => {
    'start': {'dx': start.dx, 'dy': start.dy},
    'end': {'dx': end.dx, 'dy': end.dy},
    'length': length,
    'unit': unit,
    'comment': comment,
  };

  String get displayInfo => "$length$unit ${comment.isNotEmpty ? '($comment)' : ''}";
}

enum AppMode { idle, addingStart, addingEnd, editingStart, editingEnd }

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scrollBehavior: MyCustomScrollBehavior(),
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const ArrowApp(),
    );
  }
}

class ArrowApp extends StatefulWidget {
  const ArrowApp({super.key});

  @override
  State<ArrowApp> createState() => _ArrowAppState();
}

class _ArrowAppState extends State<ArrowApp> {
  bool _imageLoaded = false;
  File? _currentImageFile;
  String? _lastSavedName;
  String _lastUsedUnit = "mm";
  final List<ArrowData> _arrows = [];
  final TransformationController _controller = TransformationController();

  AppMode _mode = AppMode.idle;
  int? _editingIndex;
  int? _selectedIndex;
  late StreamSubscription _intentSub;
  Offset? _originalPoint;

  Color _lineColor = Colors.blueAccent;
  double _lineWidth = 2.5;
  double _selectedWidth = 2.5;
  Color _selectedColor = Colors.orangeAccent;
  Color _editColor = Colors.red;
  Color _textColor = Colors.black;
  double _textSize = 14.0;
  Color _textBgColor = Colors.white70;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initSharing();
    _controller.addListener(() => setState(() {}));
    _checkStartupIntent();
  }

  void _checkStartupIntent() async {
    final initialMedia = await ReceiveSharingIntent.instance.getInitialMedia();
    if (initialMedia.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showFilePicker();
      });
    } else {
      _handleSharedFile(initialMedia[0]);
      ReceiveSharingIntent.instance.reset();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lineColor = Color(prefs.getInt('lineColor') ?? Colors.blueAccent.value);
      _lineWidth = prefs.getDouble('lineWidth') ?? 2.5;
      _selectedWidth = prefs.getDouble('selectedWidth') ?? 2.5;
      _selectedColor = Color(prefs.getInt('selectedColor') ?? Colors.orangeAccent.value);
      _editColor = Color(prefs.getInt('editColor') ?? Colors.red.value);
      _textColor = Color(prefs.getInt('textColor') ?? Colors.black.value);
      _textSize = prefs.getDouble('textSize') ?? 14.0;
      _textBgColor = Color(prefs.getInt('textBgColor') ?? Colors.white70.value);
      _lastUsedUnit = prefs.getString('lastUsedUnit') ?? "mm";
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lineColor', _lineColor.value);
    await prefs.setDouble('lineWidth', _lineWidth);
    await prefs.setDouble('selectedWidth', _selectedWidth);
    await prefs.setInt('selectedColor', _selectedColor.value);
    await prefs.setInt('editColor', _editColor.value);
    await prefs.setInt('textColor', _textColor.value);
    await prefs.setDouble('textSize', _textSize);
    await prefs.setInt('textBgColor', _textBgColor.value);
    await prefs.setString('lastUsedUnit', _lastUsedUnit);
  }

  void _initSharing() {
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen((value) {
      if (value.isNotEmpty) _handleSharedFile(value[0]);
    });
  }

  Future<void> _handleSharedFile(SharedMediaFile sharedFile) async {
    final destDir = await getExternalStorageDirectory();
    if (destDir == null) return;
    final file = File(sharedFile.path);
    String destPath = path.join(destDir.path, path.basename(sharedFile.path));
    final newFile = await file.copy(destPath);
    _resetView();
    setState(() {
      _currentImageFile = newFile;
      _imageLoaded = true;
      _arrows.clear();
      _lastSavedName = null;
    });
  }

  void _resetView() => _controller.value = Matrix4.identity();

  void _showSettings() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setST) => AlertDialog(
          title: const Text("Settings"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildColorTile("Line Color", _lineColor, (c) => setST(() => _lineColor = c)),
                _buildColorTile("Selected Color", _selectedColor, (c) => setST(() => _selectedColor = c)),
                _buildColorTile("Edit Color", _editColor, (c) => setST(() => _editColor = c)),
                _buildSliderTile("Line Width", _lineWidth, 1, 10, (v) => setST(() => _lineWidth = v)),
                _buildSliderTile("Selected Width", _selectedWidth, 1, 10, (v) => setST(() => _selectedWidth = v)),
                _buildColorTile("Text Color", _textColor, (c) => setST(() => _textColor = c)),
                _buildColorTile("Text Background", _textBgColor, (c) => setST(() => _textBgColor = c)),
                _buildSliderTile("Text Size", _textSize, 8, 30, (v) => setST(() => _textSize = v)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _saveSettings();
                Navigator.pop(context);
                setState(() {});
              },
              child: const Text("Done"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorTile(String title, Color current, Function(Color) onSelect) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontSize: 14)),
      trailing: CircleAvatar(backgroundColor: current, radius: 15),
      onTap: () => _pickColor(title, current, onSelect),
    );
  }

  Widget _buildSliderTile(String title, double val, double min, double max, Function(double) onCh) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("$title: ${val.toStringAsFixed(1)}", style: const TextStyle(fontSize: 12)),
        Slider(value: val, min: min, max: max, onChanged: onCh),
      ],
    );
  }

  void _pickColor(String title, Color initial, Function(Color) onSelect) {
  // Local state for the dialog
  Color baseColor = initial.withAlpha(255);
  int alphaValue = initial.alpha;

  final List<Color> colors = [
    Colors.red, Colors.pink, Colors.purple, Colors.blue,
    Colors.cyan, Colors.green, Colors.yellow, Colors.orange,
    Colors.brown, Colors.grey, Colors.black, Colors.white,
  ];

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) {
        // The actual color being previewed/selected
        final Color currentColor = baseColor.withAlpha(alphaValue);

        return AlertDialog(
          title: Text("Select $title"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Color Grid
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: colors.map((c) => GestureDetector(
                  onTap: () => setDialogState(() => baseColor = c),
                  child: CircleAvatar(
                    backgroundColor: c,
                    radius: 20,
                    child: baseColor.value == c.value 
                        ? const Icon(Icons.check, color: Colors.white, size: 20) 
                        : null,
                  ),
                )).toList(),
              ),
              const SizedBox(height: 25),
              // Alpha Slider
              Row(
                children: [
                  const Icon(Icons.opacity, size: 20),
                  Expanded(
                    child: Slider(
                      value: alphaValue.toDouble(),
                      min: 0,
                      max: 255,
                      divisions: 255,
                      label: "${(alphaValue / 255 * 100).round()}%",
                      onChanged: (v) => setDialogState(() => alphaValue = v.toInt()),
                    ),
                  ),
                ],
              ),
              // Preview Box
              Container(
                height: 40,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: currentColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Center(
                  child: Text(
                    "Preview",
                    style: TextStyle(
                      color: currentColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                onSelect(currentColor);
                Navigator.pop(ctx);
              },
              child: const Text("Select"),
            ),
          ],
        );
      },
    ),
  );
}

  Future<void> _showFilePicker() async {
    final dir = await getExternalStorageDirectory();
    if (dir == null) return;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final entities = dir.listSync();
          final jsons = entities.where((f) => path.extension(f.path).toLowerCase() == '.json').toList();
          final imgs = entities
              .where((f) => ['.jpg', '.jpeg', '.png'].contains(path.extension(f.path).toLowerCase()))
              .toList();
          final files = [...jsons, ...imgs];
          return AlertDialog(
            title: const Text("Open File"),
            content: SizedBox(
              width: double.maxFinite,
              child: files.isEmpty
                  ? const Text("No files.")
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: files.length,
                      itemBuilder: (context, i) {
                        final f = File(files[i].path);
                        final isJson = path.extension(f.path).toLowerCase() == '.json';
                        return ListTile(
                          leading: Icon(
                            isJson ? Icons.description : Icons.image,
                            color: isJson ? Colors.orange : Colors.blue,
                          ),
                          title: Text(path.basename(f.path), style: const TextStyle(fontSize: 12)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () async {
                              if (await _confirm("Delete File?", "Delete ${path.basename(f.path)}?")) {
                                await f.delete();
                                setDialogState(() {});
                              }
                            },
                          ),
                          onTap: () => isJson ? _loadJsonData(f) : _loadImageOnly(f),
                        );
                      },
                    ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))],
          );
        },
      ),
    );
  }

  Future<void> _loadImageOnly(File f) async {
    _resetView();
    setState(() {
      _currentImageFile = f;
      _imageLoaded = true;
      _arrows.clear();
      _lastSavedName = null;
    });
    Navigator.pop(context);
  }

  Future<void> _loadJsonData(File jsonFile) async {
    try {
      final data = jsonDecode(await jsonFile.readAsString());
      final dir = await getExternalStorageDirectory();
      final imageFile = File(path.join(dir!.path, data['image_filename']));
      if (await imageFile.exists()) {
        _resetView();
        setState(() {
          _currentImageFile = imageFile;
          _imageLoaded = true;
          _lastSavedName = data['save_name'];
          _arrows.clear();
          for (var item in data['arrows']) {
            _arrows.add(ArrowData.fromJson(item));
          }
        });
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _showSaveDialog() async {
    if (_currentImageFile == null) return;
    final defaultBase = _lastSavedName ?? path.basenameWithoutExtension(_currentImageFile!.path);
    final nameCtrl = TextEditingController(text: defaultBase);
    final dir = await getExternalStorageDirectory();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Save"),
          content: TextField(
            controller: nameCtrl,
            decoration: InputDecoration(
              labelText: "File Name",
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => setDialogState(() => nameCtrl.clear()),
              ),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                String saveAs = nameCtrl.text.isEmpty ? defaultBase : nameCtrl.text;
                _processSave(saveAs, dir!, defaultBase != saveAs);
                Navigator.pop(context);
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processSave(String fileName, Directory dir, bool confirmOverwrite) async {
    String base = fileName.endsWith('.json') ? path.basenameWithoutExtension(fileName) : fileName;
    File file = File(path.join(dir.path, '$base.json'));
    if (confirmOverwrite && await file.exists() && !await _confirm("Overwrite?", "File exists. Overwrite?")) return;
    final data = {
      'image_filename': path.basename(_currentImageFile!.path),
      'save_name': base,
      'arrows': _arrows.map((a) => a.toJson()).toList(),
    };
    await file.writeAsString(jsonEncode(data));
    setState(() => _lastSavedName = base);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Saved $base.json"), duration: const Duration(seconds: 1)));
    }
  }

  void _handleQuickSave() async {
    if (_lastSavedName == null) {
      _showSaveDialog();
    } else {
      final dir = await getExternalStorageDirectory();
      if (dir != null) await _processSave(_lastSavedName!, dir, false);
    }
  }

  Future<void> _showDetailsDialog(ArrowData arrow) async {
    final lCtrl = TextEditingController(text: arrow.length);
    final cCtrl = TextEditingController(text: arrow.comment);
    String tUnit = arrow.unit;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          title: const Text("Dimenso"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: lCtrl,
                decoration: const InputDecoration(labelText: "Length"),
                keyboardType: TextInputType.number,
                autofocus: true,
              ),
              const SizedBox(height: 10),
              ToggleButtons(
                isSelected: [tUnit == "mm", tUnit == "cm", tUnit == "m"],
                onPressed: (i) => setS(() => tUnit = ["mm", "cm", "m"][i]),
                children: const [
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("mm")),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("cm")),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text("m")),
                ],
              ),
              TextField(
                controller: cCtrl,
                decoration: const InputDecoration(labelText: "Comment"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (await _confirm("Delete Arrow?", "Are you sure?")) {
                  setState(() => _arrows.remove(arrow));
                  if (mounted) Navigator.pop(context);
                }
              },
              child: const Text("Delete", style: TextStyle(color: Colors.red)),
            ),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  arrow.length = lCtrl.text;
                  arrow.unit = tUnit;
                  arrow.comment = cCtrl.text;
                  _lastUsedUnit = tUnit;
                });
                _saveSettings();
                Navigator.pop(context);
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("No")),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("Yes")),
          ],
        ),
      ) ??
      false;

  void _centerViewOn(Offset scenePoint) {
    final Size size = MediaQuery.of(context).size;
    final double scale = _controller.value.getMaxScaleOnAxis();
    final double tx = (size.width / 2) - (scenePoint.dx * scale);
    final double ty = (size.height / 2) - (scenePoint.dy * scale);
    setState(() {
      _controller.value = Matrix4.identity()
        ..translate(tx, ty)
        ..scale(scale);
    });
  }

  void _handleActionButton() async {
    if (_mode == AppMode.idle) {
      setState(() {
        _mode = AppMode.addingStart;
        _editingIndex = null;
      });
    } else if (_mode == AppMode.addingStart) {
      final newArrow = ArrowData(start: _getSceneCenter(), end: _getSceneCenter(), unit: _lastUsedUnit);
      setState(() {
        _arrows.insert(0, newArrow);
        _editingIndex = 0;
        _mode = AppMode.addingEnd;
      });
    } else if (_mode == AppMode.addingEnd) {
      final arrow = _arrows[_editingIndex!];
      setState(() {
        _mode = AppMode.idle;
        _editingIndex = null;
      });
      await _showDetailsDialog(arrow);
    } else {
      setState(() {
        _mode = AppMode.idle;
        _editingIndex = null;
      });
    }
  }

  void _handleCancelButton() {
    setState(() {
      if ((_mode == AppMode.addingStart || _mode == AppMode.addingEnd) && _editingIndex != null) {
        _arrows.removeAt(_editingIndex!);
      } else if (_editingIndex != null && _originalPoint != null) {
        if (_mode == AppMode.editingStart) {
          _arrows[_editingIndex!].start = _originalPoint!;
        } else if (_mode == AppMode.editingEnd) {
          _arrows[_editingIndex!].end = _originalPoint!;
        }
      }
      _mode = AppMode.idle;
      _editingIndex = null;
      _originalPoint = null;
    });
  }

  Offset _getSceneCenter() =>
      _controller.toScene(Offset(MediaQuery.of(context).size.width / 2, MediaQuery.of(context).size.height / 2));

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final fabBottomPadding = screenHeight * 0.35;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (!_imageLoaded)
            Center(
              child: ElevatedButton(onPressed: _showFilePicker, child: const Text("Open File Library")),
            )
          else ...[
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _controller,
                boundaryMargin: const EdgeInsets.all(1000),
                minScale: 0.1,
                maxScale: 15.0,
                onInteractionUpdate: (_) {
                  if (_mode == AppMode.idle || _editingIndex == null) return;
                  setState(() {
                    if (_mode == AppMode.addingEnd || _mode == AppMode.editingEnd)
                      _arrows[_editingIndex!].end = _getSceneCenter();
                    else if (_mode == AppMode.addingStart || _mode == AppMode.editingStart)
                      _arrows[_editingIndex!].start = _getSceneCenter();
                  });
                },
                child: _currentImageFile != null ? Image.file(_currentImageFile!) : const SizedBox(),
              ),
            ),
            if (_mode == AppMode.idle && _imageLoaded)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Row(
                    children: [
                      FloatingActionButton(
                        heroTag: "settings",
                        onPressed: _showSettings,
                        backgroundColor: Colors.black54,
                        mini: true,
                        child: const Icon(Icons.settings, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      FloatingActionButton(
                        heroTag: "f",
                        onPressed: _showFilePicker,
                        backgroundColor: Colors.black54,
                        mini: true,
                        child: const Icon(Icons.folder_open, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            IgnorePointer(
              child: CustomPaint(
                size: Size.infinite,
                painter: ArrowPainter(
                  arrows: _arrows,
                  selectedIndex: _selectedIndex,
                  editingIndex: _editingIndex,
                  mode: _mode,
                  transform: _controller.value,
                  lineColor: _lineColor,
                  lineWidth: _lineWidth,
                  selectedWidth: _selectedWidth,
                  selectedColor: _selectedColor,
                  editColor: _editColor,
                  textColor: _textColor,
                  textSize: _textSize,
                  textBgColor: _textBgColor,
                ),
              ),
            ),
          ],
          if (_mode == AppMode.addingStart)
            IgnorePointer(
              child: Center(child: Icon(Icons.add, size: 50, color: _editColor)),
            ),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: _imageLoaded ? fabBottomPadding : 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_mode == AppMode.idle && _imageLoaded) ...[
              GestureDetector(
                onLongPress: _showSaveDialog,
                child: FloatingActionButton(
                  heroTag: "s",
                  onPressed: _handleQuickSave,
                  backgroundColor: Colors.green,
                  mini: true,
                  child: const Icon(Icons.save, color: Colors.white),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_mode != AppMode.idle) ...[
              FloatingActionButton(
                heroTag: "c",
                onPressed: _handleCancelButton,
                backgroundColor: Colors.redAccent,
                mini: true,
                child: const Icon(Icons.close, color: Colors.white),
              ),
              const SizedBox(height: 12),
            ],
            FloatingActionButton(
              heroTag: "m",
              mini: true,
              onPressed: _handleActionButton,
              child: Icon(_mode == AppMode.idle ? Icons.add : Icons.check),
            ),
          ],
        ),
      ),
      bottomSheet: _imageLoaded ? _buildBottomSheet() : null,
    );
  }

  Widget _buildBottomSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.1,
      minChildSize: 0.05,
      maxChildSize: 0.33,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView.builder(
          controller: scrollController,
          itemCount: _arrows.length + 1,
          itemBuilder: (context, index) {
            if (index == 0)
              return Center(
                child: Container(
                  height: 4,
                  width: 30,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  color: Colors.grey[300],
                ),
              );
            final i = index - 1;
            final a = _arrows[i];
            return ListTile(
              visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
              dense: true,
              selected: _selectedIndex == i,
              onTap: () => setState(() => _selectedIndex = i),
              title: Text(
                a.displayInfo.trim().isEmpty ? "Arrow ${_arrows.length - i}" : a.displayInfo,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_note, size: 22),
                    onPressed: () => _showDetailsDialog(a),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_back_outlined, size: 22),
                    color: (_mode == AppMode.editingStart && _editingIndex == i) ? Colors.green : Colors.blue,
                    onPressed: () {
                      _centerViewOn(a.start);
                      setState(() {
                        _mode = AppMode.editingStart;
                        _editingIndex = i;
                        _originalPoint = a.start;
                      });
                    },
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.arrow_forward_outlined, size: 22),
                    color: (_mode == AppMode.editingEnd && _editingIndex == i) ? Colors.green : Colors.blue,
                    onPressed: () {
                      _centerViewOn(a.end);
                      setState(() {
                        _mode = AppMode.editingEnd;
                        _editingIndex = i;
                        _originalPoint = a.end;
                      });
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class ArrowPainter extends CustomPainter {
  final List<ArrowData> arrows;
  final int? selectedIndex;
  final int? editingIndex;
  final AppMode mode;
  final Matrix4 transform;
  final Color lineColor;
  final double lineWidth;
  final double selectedWidth;
  final Color selectedColor;
  final Color editColor;
  final Color textColor;
  final double textSize;
  final Color textBgColor;

  ArrowPainter({
    required this.arrows,
    this.selectedIndex,
    this.editingIndex,
    required this.mode,
    required this.transform,
    required this.lineColor,
    required this.lineWidth,
    required this.selectedWidth,
    required this.selectedColor,
    required this.editColor,
    required this.textColor,
    required this.textSize,
    required this.textBgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < arrows.length; i++) {
      final a = arrows[i];
      final start = MatrixUtils.transformPoint(transform, a.start);
      final end = MatrixUtils.transformPoint(transform, a.end);
      final isS = i == selectedIndex;
      final isE = i == editingIndex;
      final p = Paint()
        ..color = isS ? selectedColor : lineColor
        ..strokeWidth = isS ? selectedWidth : lineWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(start, end, p);
      final hps = (isE && (mode == AppMode.addingStart || mode == AppMode.editingStart))
          ? (Paint()
              ..color = editColor
              ..strokeWidth = selectedWidth
              ..style = PaintingStyle.stroke)
          : p;
      final hpe = (isE && (mode == AppMode.addingEnd || mode == AppMode.editingEnd))
          ? (Paint()
              ..color = editColor
              ..strokeWidth = selectedWidth
              ..style = PaintingStyle.stroke)
          : p;
      _drawHead(canvas, end, start, hps, 16.0);
      _drawHead(canvas, start, end, hpe, 16.0);
      if (a.displayInfo.trim().isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: a.displayInfo,
            style: TextStyle(
              color: textColor,
              fontSize: textSize,
              fontWeight: FontWeight.bold,
              backgroundColor: textBgColor,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2).translate(10, -25));
      }
    }
  }

  void _drawHead(Canvas canvas, Offset from, Offset to, Paint p, double h) {
    if (from == to) {
      canvas.drawCircle(to, h * 0.4, p..style = PaintingStyle.fill);
      return;
    }
    double ang = math.atan2(to.dy - from.dy, to.dx - from.dx);
    canvas.drawLine(to, Offset(to.dx - h * math.cos(ang - 0.5), to.dy - h * math.sin(ang - 0.5)), p);
    canvas.drawLine(to, Offset(to.dx - h * math.cos(ang + 0.5), to.dy - h * math.sin(ang + 0.5)), p);
  }

  @override
  bool shouldRepaint(covariant ArrowPainter oldDelegate) => true;
}
