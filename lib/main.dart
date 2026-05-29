import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fast_gbk/fast_gbk.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '代码提取工具',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const CodeExtractorHome(),
    );
  }
}

class CodeExtractorHome extends StatefulWidget {
  const CodeExtractorHome({super.key});

  @override
  State<CodeExtractorHome> createState() => _CodeExtractorHomeState();
}

class _CodeExtractorHomeState extends State<CodeExtractorHome> {
  String _selectedPath = "";
  final TextEditingController _exExtController = TextEditingController(
      text: "jpg, png, gif, zip, exe, jar, class, pyc, ico, woff, ttf, pdf, mp4, mov");
  final TextEditingController _incExtController = TextEditingController();
  final TextEditingController _exDirController = TextEditingController(
      text: "node_modules, .git, .idea, dist, build, __pycache__, target, .vscode");
  final TextEditingController _exFileController = TextEditingController(
      text: "package-lock.json, yarn.lock, .DS_Store");

  bool _isMd = true;
  bool _isProcessing = false;
  String _statusText = "状态: 准备就绪";
  String _finalResult = "";
  String _previewResult = "";

  // 申请管理外部存储权限
  Future<bool> _requestPermission() async {
    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
    }
    return status.isGranted;
  }

  // 选择文件夹
  Future<void> _selectFolder() async {
    bool hasPermission = await _requestPermission();
    if (!hasPermission) {
      _showSnackBar("无法提取：未授予管理外部存储权限。请在系统设置中开启。");
      openAppSettings();
      return;
    }

    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      setState(() {
        _selectedPath = selectedDirectory;
        _statusText = "已选择路径: $_selectedPath";
      });
    }
  }

  // 开始提取任务
  void _startExtraction() async {
    if (_selectedPath.isEmpty) {
      _showSnackBar("请先选择项目目录");
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusText = "正在扫描文件，请稍候...";
      _finalResult = "";
      _previewResult = "";
    });

    // 收集配置信息传递给后台线程
    final config = {
      'path': _selectedPath,
      'exExts': _parseConfigString(_exExtController.text),
      'incExts': _parseConfigString(_incExtController.text),
      'exDirs': _parseConfigString(_exDirController.text),
      'exFiles': _parseConfigString(_exFileController.text),
      'isMd': _isMd,
    };

    try {
      // 在后台线程（Isolate）中执行繁重的文件 I/O 操作，防止 UI 卡死
      final result = await compute(_performExtraction, config);
      
      setState(() {
        _finalResult = result;
        _isProcessing = false;
        _statusText = "提取完成！";
        
        // 限制预览区域大小，防止渲染大文本卡顿
        const int limit = 80000;
        if (_finalResult.length > limit) {
          _previewResult = "${_finalResult.substring(0, limit)}\n\n......(内容过长，预览已截断。请复制或直接保存查看完整版)......";
        } else {
          _previewResult = _finalResult;
        }
      });
      _showSnackBar("提取成功！");
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusText = "出现错误: $e";
      });
      _showSnackBar("提取失败: $e");
    }
  }

  List<String> _parseConfigString(String input) {
    return input
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  // 一键复制到剪贴板
  void _copyToClipboard() {
    if (_finalResult.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _finalResult));
    _showSnackBar("已成功复制到剪贴板");
  }

  // 自动保存至系统下载目录 (Downloads)
  Future<void> _saveToFile() async {
    if (_finalResult.isEmpty) return;
    try {
      // 在安卓系统下载目录下创建文件
      final ext = _isMd ? "md" : "txt";
      final fileName = "code_extract_${DateTime.now().millisecondsSinceEpoch}.$ext";
      final file = File("/storage/emulated/0/Download/$fileName");
      
      await file.writeAsString(_finalResult);
      _showSnackBar("已保存至系统下载夹:\nDownload/$fileName");
    } catch (e) {
      _showSnackBar("保存失败: $e");
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('全能代码提取工具'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 目录选择
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedPath.isEmpty ? "请选择项目根目录" : _selectedPath,
                        style: TextStyle(
                          color: _selectedPath.isEmpty ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _selectFolder,
                      icon: const Icon(Icons.folder_open),
                      label: const Text("选择目录"),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 配置区
            Expanded(
              flex: 3,
              child: ListView(
                children: [
                  _buildInputField("排除后缀", _exExtController),
                  _buildInputField("仅包含后缀", _incExtController),
                  _buildInputField("排除文件夹", _exDirController),
                  _buildInputField("排除特定文件", _exFileController),
                  Row(
                    children: [
                      Checkbox(
                        value: _isMd,
                        onChanged: (val) {
                          setState(() {
                            _isMd = val ?? true;
                          });
                        },
                      ),
                      const Text("启用 Markdown 代码块包裹"),
                    ],
                  ),
                ],
              ),
            ),
            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _startExtraction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(_isProcessing ? "扫描中..." : "开始提取"),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _finalResult.isNotEmpty ? _copyToClipboard : null,
                  icon: const Icon(Icons.copy),
                  tooltip: "复制",
                ),
                IconButton(
                  onPressed: _finalResult.isNotEmpty ? _saveToFile : null,
                  icon: const Icon(Icons.save),
                  tooltip: "保存到下载目录",
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(_statusText, style: const TextStyle(grey: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            // 预览区域
            const Text("内容预览:", style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              flex: 4,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.all(6.0),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _previewResult.isEmpty ? "暂无预览数据" : _previewResult,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

// 独立的顶层函数：专用于后台线程的文件遍历和解码
String _performExtraction(Map<String, dynamic> config) {
  final String path = config['path'];
  final List<String> exExts = config['exExts'];
  final List<String> incExts = config['incExts'];
  final List<String> exDirs = config['exDirs'];
  final List<String> exFiles = config['exFiles'];
  final bool isMd = config['isMd'];

  final buffer = StringBuffer();
  final dir = Directory(path);

  if (!dir.existsSync()) return "指定的目录不存在";

  // 获取上一级目录用于计算相对路径
  final parentPath = dir.parent.path;

  // 递归遍历
  _traverseDirectory(dir, parentPath, buffer, exExts, incExts, exDirs, exFiles, isMd);

  return buffer.toString();
}

void _traverseDirectory(
  Directory dir,
  String parentPath,
  StringBuffer buffer,
  List<String> exExts,
  List<String> incExts,
  List<String> exDirs,
  List<String> exFiles,
  bool isMd,
) {
  try {
    final List<FileSystemEntity> entities = dir.listSync(recursive: false);

    for (var entity in entities) {
      final name = entity.path.split(Platform.pathSeparator).last;

      if (entity is Directory) {
        // 文件夹过滤
        if (exDirs.contains(name.toLowerCase())) continue;
        _traverseDirectory(entity, parentPath, buffer, exExts, incExts, exDirs, exFiles, isMd);
      } else if (entity is File) {
        // 文件名过滤
        if (exFiles.contains(name.toLowerCase())) continue;

        // 后缀名提取与过滤
        final parts = name.split('.');
        final ext = parts.length > 1 ? parts.last.toLowerCase() : "";

        if (exExts.contains(ext)) continue;
        if (incExts.isNotEmpty && !incExts.contains(ext)) continue;

        // 安全读取内容
        final content = _readBytesSafely(entity);
        final relativePath = entity.path.replaceFirst(parentPath, "").replaceFirst(RegExp(r'^[/\\]'), "");

        buffer.write("文件位置: $relativePath\n");
        if (isMd) {
          buffer.write("```$ext\n$content\n```\n\n");
        } else {
          buffer.write("========================================\n$content\n\n");
        }
      }
    }
  } catch (_) {
    // 忽略无法读取的个别系统文件夹或受保护文件
  }
}

// 安全读取并解析文本编码
String _readBytesSafely(File file) {
  try {
    final bytes = file.readAsBytesSync();
    
    // 1. 尝试使用 UTF-8
    try {
      return utf8.decode(bytes);
    } catch (_) {}

    // 2. 尝试使用 GBK (兼容中文系统常见文本)
    try {
      return gbk.decode(bytes);
    } catch (_) {}

    // 3. 降级为 Latin1 (避免崩溃)
    return latin1.decode(bytes);
  } catch (e) {
    return "[无法读取文件内容: $e]";
  }
}
