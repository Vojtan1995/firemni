import 'package:flutter/material.dart';
import '../../../core/design_tokens.dart';
import 'floor_plan_filters.dart';

class FloorPlanFilterSheet extends StatefulWidget {
  const FloorPlanFilterSheet({
    super.key,
    required this.initial,
    required this.floorSeals,
    required this.hideByWorker,
    required this.currentUserId,
  });

  final FloorPlanFilterState initial;
  final List<Map<String, dynamic>> floorSeals;
  final bool hideByWorker;
  final String? currentUserId;

  static Future<FloorPlanFilterState?> show(
    BuildContext context, {
    required FloorPlanFilterState initial,
    required List<Map<String, dynamic>> floorSeals,
    required bool hideByWorker,
    required String? currentUserId,
  }) {
    return showModalBottomSheet<FloorPlanFilterState>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: FloorPlanFilterSheet(
          initial: initial,
          floorSeals: floorSeals,
          hideByWorker: hideByWorker,
          currentUserId: currentUserId,
        ),
      ),
    );
  }

  @override
  State<FloorPlanFilterSheet> createState() => _FloorPlanFilterSheetState();
}

class _FloorPlanFilterSheetState extends State<FloorPlanFilterSheet> {
  late FloorPlanMarkerFilter _mode;
  String? _workerId;
  String? _workerName;
  String? _status;
  late Set<String> _selectedIds;
  late TextEditingController _numbersCtrl;

  List<FloorPlanMarkerFilter> get _modes {
    if (widget.hideByWorker) {
      return FloorPlanMarkerFilter.values
          .where((m) => m != FloorPlanMarkerFilter.byWorker)
          .toList();
    }
    return FloorPlanMarkerFilter.values.toList();
  }

  @override
  void initState() {
    super.initState();
    _mode = widget.initial.mode;
    _workerId = widget.initial.workerId;
    _workerName = widget.initial.workerName;
    _status = widget.initial.status;
    _selectedIds = Set<String>.from(widget.initial.selectedSealIds);
    _numbersCtrl = TextEditingController(
      text: widget.initial.selectedSealNumbers.join(', '),
    );
  }

  @override
  void dispose() {
    _numbersCtrl.dispose();
    super.dispose();
  }

  FloorPlanFilterState get _draft => FloorPlanFilterState(
        mode: _mode,
        workerId: _mode == FloorPlanMarkerFilter.byWorker ? _workerId : null,
        workerName:
            _mode == FloorPlanMarkerFilter.byWorker ? _workerName : null,
        status: _mode == FloorPlanMarkerFilter.byStatus ? _status : null,
        selectedSealIds: _mode == FloorPlanMarkerFilter.selected
            ? _selectedIds
            : const {},
        selectedSealNumbers: _mode == FloorPlanMarkerFilter.selected
            ? FloorPlanFilterState.sealNumbersFromIds(
                _selectedIds,
                widget.floorSeals,
              )
            : const {},
      );

  void _syncNumbersFromSelection() {
    _numbersCtrl.text = FloorPlanFilterState.sealNumbersFromIds(
      _selectedIds,
      widget.floorSeals,
    ).join(', ');
  }

  void _applyNumbersFromField() {
    final ids = FloorPlanFilterState.sealIdsFromNumbers(
      _numbersCtrl.text,
      widget.floorSeals,
    );
    setState(() => _selectedIds = ids);
  }

  bool get _canApply => _draft.isValidForApply;

  Widget _buildModeParams() {
    switch (_mode) {
      case FloorPlanMarkerFilter.byWorker:
        return _buildWorkerSection();
      case FloorPlanMarkerFilter.byStatus:
        return _buildStatusSection();
      case FloorPlanMarkerFilter.selected:
        return _buildSelectedSection();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildWorkerSection() {
    final workers = FloorPlanFilterState.workersFromSeals(widget.floorSeals);
    if (workers.isEmpty) {
      return const Text(
        'Na tomto patře nejsou dostupná data o montérech.',
        style: TextStyle(color: AppColors.textSecondary),
      );
    }
    return DropdownButtonFormField<String>(
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Vyberte montéra',
        border: OutlineInputBorder(),
      ),
      value: _workerId,
      items: workers
          .map(
            (w) => DropdownMenuItem(
              value: w.id,
              child: Text(w.name, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (id) {
        final w = workers.where((x) => x.id == id).firstOrNull;
        setState(() {
          _workerId = id;
          _workerName = w?.name;
        });
      },
    );
  }

  Widget _buildStatusSection() {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Vyberte stav',
        border: OutlineInputBorder(),
      ),
      value: _status,
      items: const [
        DropdownMenuItem(value: 'draft', child: Text('Rozpracované')),
        DropdownMenuItem(value: 'checked', child: Text('Zkontrolované')),
        DropdownMenuItem(value: 'invoiced', child: Text('Fakturované')),
      ],
      onChanged: (v) => setState(() => _status = v),
    );
  }

  Widget _buildSelectedSection() {
    final sortedSeals = [...widget.floorSeals]
      ..sort((a, b) =>
          (a['sealNumber'] as String).compareTo(b['sealNumber'] as String));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _numbersCtrl,
          decoration: const InputDecoration(
            labelText: 'Čísla ucpávek (oddělená čárkou)',
            border: OutlineInputBorder(),
            hintText: 'např. 88601, 88602, 88603',
            helperText: 'Zadejte čísla a klepněte Použít, nebo zaškrtněte níže',
          ),
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _applyNumbersFromField(),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_selectedIds.isNotEmpty)
          Text(
            'Vybráno: ${_selectedIds.length} ucpávek',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (sortedSeals.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text(
              'Na patře zatím nejsou načtené ucpávky. Zadejte čísla ručně.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          )
        else ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Nebo vyberte ze seznamu',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          ...sortedSeals.map((s) {
            final id = s['id'] as String;
            final checked = _selectedIds.contains(id);
            return CheckboxListTile(
              dense: true,
              value: checked,
              title: Text('#${s['sealNumber']}'),
              subtitle: Text(s['status'] as String? ?? 'draft'),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedIds.add(id);
                  } else {
                    _selectedIds.remove(id);
                  }
                  _syncNumbersFromSelection();
                });
              },
            );
          }),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Filtry výkresu',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, FloorPlanFilterState.allFilters),
                    child: const Text('Vymazat'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                children: [
                  DropdownButtonFormField<FloorPlanMarkerFilter>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Režim filtru',
                      border: OutlineInputBorder(),
                    ),
                    value: _mode,
                    items: _modes
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(
                              FloorPlanFilterState(mode: m).label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _mode = v);
                    },
                  ),
                  if (_mode == FloorPlanMarkerFilter.selected ||
                      _mode == FloorPlanMarkerFilter.byWorker ||
                      _mode == FloorPlanMarkerFilter.byStatus) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _buildModeParams(),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Zrušit'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: _canApply
                          ? () {
                              if (_mode == FloorPlanMarkerFilter.selected) {
                                _applyNumbersFromField();
                              }
                              Navigator.pop(context, _draft);
                            }
                          : null,
                      child: const Text('Použít'),
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
