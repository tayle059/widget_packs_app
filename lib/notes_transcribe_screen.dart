import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class NotesTranscribeScreen extends StatefulWidget {
  const NotesTranscribeScreen({super.key});

  @override
  State<NotesTranscribeScreen> createState() => _NotesTranscribeScreenState();
}

class _NotesTranscribeScreenState extends State<NotesTranscribeScreen> {
  // Storage keys
  static const _kNotes = 'notes_transcribe:list';

  final _speech = stt.SpeechToText();
  bool _available = false;
  bool _listening = false;

  String _partial = '';
  String _selectedLocaleId = '';
  List<stt.LocaleName> _locales = [];

  List<_Note> _notes = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _loadNotes();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    // Try to initialize mic/speech
    final available = await _speech.initialize(
      onError: (e) => _snack('Speech error: ${e.errorMsg}'),
      onStatus: (s) => setState(() => _listening = s == 'listening'),
    );
    List<stt.LocaleName> locales = [];
    String current = '';
    if (available) {
      locales = await _speech.locales();
      current = await _speech.systemLocale().then((l) => l?.localeId ?? '') ;
    }
    setState(() {
      _available = available;
      _locales = locales;
      _selectedLocaleId = current.isNotEmpty ? current : (locales.isNotEmpty ? locales.first.localeId : 'en_US');
    });
  }

  Future<void> _loadNotes() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kNotes);
    if (raw != null) {
      final list = (jsonDecode(raw) as List)
          .map((e) => _Note.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() => _notes = list);
    }
    setState(() => _loading = false);
  }

  Future<void> _saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNotes, jsonEncode(_notes.map((e) => e.toJson()).toList()));
  }

  Future<void> _start() async {
    if (!_available) {
      _snack('Speech not available. Check mic permission.');
      return;
    }
    setState(() => _partial = '');
    await _speech.stop();
    await _speech.listen(
      localeId: _selectedLocaleId.isEmpty ? null : _selectedLocaleId,
      listenMode: stt.ListenMode.confirmation, // good for short notes
      partialResults: true,
      onResult: (r) {
        setState(() => _partial = r.recognizedWords);
        if (r.finalResult && _partial.trim().isNotEmpty) {
          _addNote(_partial.trim());
          _partial = '';
        }
      },
    );
  }

  Future<void> _stop() async {
    await _speech.stop();
    setState(() => _listening = false);
  }

  void _addNote(String text) async {
    final note = _Note(text: text, ts: DateTime.now());
    setState(() => _notes.insert(0, note));
    await _saveNotes();
    _snack('Saved note');
  }

  void _deleteNote(_Note n) async {
    setState(() => _notes.removeWhere((e) => e.id == n.id));
    await _saveNotes();
  }

  void _copyNote(_Note n) async {
    await Clipboard.setData(ClipboardData(text: n.text));
    _snack('Copied to clipboard');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  List<_Note> get _filteredNotes {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _notes;
    return _notes.where((n) => n.text.toLowerCase().contains(q)).toList();
    }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes / Transcribe'),
        actions: [
          if (_available)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedLocaleId.isEmpty ? null : _selectedLocaleId,
                  items: _locales
                      .map((l) => DropdownMenuItem(
                            value: l.localeId,
                            child: Text(l.name),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedLocaleId = v ?? _selectedLocaleId),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Transcription panel
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Material(
                    color: theme.colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(_listening ? Icons.mic : Icons.mic_none),
                              const SizedBox(width: 8),
                              Text(_listening ? 'Listening…' : 'Tap Record to dictate a note'),
                              const Spacer(),
                              FilledButton.icon(
                                onPressed: _listening ? _stop : _start,
                                icon: Icon(_listening ? Icons.stop : Icons.fiber_manual_record),
                                label: Text(_listening ? 'Stop' : 'Record'),
                              ),
                            ],
                          ),
                          if (_partial.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              _partial,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

                // Search + Add manually
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Search notes…',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final text = await showDialog<String>(
                            context: context,
                            builder: (_) => const _AddNoteDialog(),
                          );
                          if (text != null && text.trim().isNotEmpty) {
                            _addNote(text.trim());
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 4),

                // Notes list
                Expanded(
                  child: _filteredNotes.isEmpty
                      ? const Center(child: Text('No notes yet. Dictate or add one!'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          itemCount: _filteredNotes.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final n = _filteredNotes[i];
                            return Dismissible(
                              key: ValueKey(n.id),
                              background: Container(
                                decoration: BoxDecoration(
                                  color: Colors.red.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.only(left: 20),
                                child: const Icon(Icons.delete),
                              ),
                              secondaryBackground: Container(
                                decoration: BoxDecoration(
                                  color: Colors.red.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                child: const Icon(Icons.delete),
                              ),
                              onDismissed: (_) => _deleteNote(n),
                              child: ListTile(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                tileColor: theme.colorScheme.surfaceVariant,
                                title: Text(n.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                                subtitle: Text(n.fmtTime),
                                leading: const Icon(Icons.note_alt_outlined),
                                trailing: IconButton(
                                  tooltip: 'Copy',
                                  icon: const Icon(Icons.copy),
                                  onPressed: () => _copyNote(n),
                                ),
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      title: const Text('Note'),
                                      content: SingleChildScrollView(child: Text(n.text)),
                                      actions: [
                                        TextButton(
                                          onPressed: () {
                                            _copyNote(n);
                                            Navigator.of(context).pop();
                                          },
                                          child: const Text('Copy'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.of(context).pop(),
                                          child: const Text('Close'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _AddNoteDialog extends StatefulWidget {
  const _AddNoteDialog();

  @override
  State<_AddNoteDialog> createState() => _AddNoteDialogState();
}

class _AddNoteDialogState extends State<_AddNoteDialog> {
  final _ctrl = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New note'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLines: 4,
        decoration: const InputDecoration(hintText: 'Type your note…'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('Save')),
      ],
    );
  }
}

class _Note {
  final String id;
  final String text;
  final DateTime ts;
  _Note({required this.text, required this.ts}) : id = '${ts.microsecondsSinceEpoch}-${text.hashCode}';

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'ts': ts.toIso8601String()};

  factory _Note.fromJson(Map<String, dynamic> m) => _Note(
        text: m['text'] as String,
        ts: DateTime.tryParse(m['ts'] as String)!,
      );

  String get fmtTime {
    final d = ts;
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$mm/$dd ${hh}:${mi}';
  }
}
