import 'package:flutter/material.dart';

import '../domain/cashier_dish.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

class DishSpecificationEditorController extends ChangeNotifier {
  DishSpecificationEditorController._({
    required List<CashierDishSpecificationGroup> groups,
    required this.hasUnparsedSpecification,
  }) : _groups = groups.map(_EditableSpecificationGroup.fromGroup).toList();

  factory DishSpecificationEditorController.fromRaw(String raw) {
    final groups = parseCashierDishSpecifications(raw);
    return DishSpecificationEditorController._(
      groups: groups,
      hasUnparsedSpecification: raw.trim().isNotEmpty && groups.isEmpty,
    );
  }

  final List<_EditableSpecificationGroup> _groups;
  final bool hasUnparsedSpecification;

  String get encodedValue => encodeCashierDishSpecifications(
    _groups.map((group) => group.toSpecification()),
  );

  void addGroup() {
    _groups.add(_EditableSpecificationGroup.empty());
    notifyListeners();
  }

  void removeGroup(int groupIndex) {
    _groups.removeAt(groupIndex).dispose();
    notifyListeners();
  }

  void addOption(int groupIndex) {
    _groups[groupIndex].optionControllers.add(TextEditingController());
    notifyListeners();
  }

  void removeOption(int groupIndex, int optionIndex) {
    final options = _groups[groupIndex].optionControllers;
    if (options.length == 1) {
      options.single.clear();
    } else {
      options.removeAt(optionIndex).dispose();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final group in _groups) {
      group.dispose();
    }
    super.dispose();
  }
}

class DishSpecificationEditor extends StatelessWidget {
  const DishSpecificationEditor({super.key, required this.controller});

  final DishSpecificationEditorController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Column(
      key: const Key('cashier-dish-spec-editor'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '菜品规格',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text('可选；按规格名称和选项维护，无需填写 JSON'),
                ],
              ),
            ),
            OutlinedButton.icon(
              key: const Key('cashier-dish-spec-add-group'),
              onPressed: controller.addGroup,
              icon: const Icon(Icons.add_rounded),
              label: const Text('增加规格'),
            ),
          ],
        ),
        if (controller.hasUnparsedSpecification) ...[
          const SizedBox(height: 12),
          const _SpecificationWarning(),
        ],
        if (controller._groups.isEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cashier.canvas,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('当前没有规格。需要时点击“增加规格”。'),
          ),
        ],
        for (
          var groupIndex = 0;
          groupIndex < controller._groups.length;
          groupIndex++
        ) ...[
          const SizedBox(height: 12),
          _SpecificationGroupFields(
            groupIndex: groupIndex,
            group: controller._groups[groupIndex],
            allGroups: controller._groups,
            onRemove: () => controller.removeGroup(groupIndex),
            onAddOption: () => controller.addOption(groupIndex),
            onRemoveOption: (optionIndex) =>
                controller.removeOption(groupIndex, optionIndex),
          ),
        ],
      ],
    ),
  );
}

class _EditableSpecificationGroup {
  _EditableSpecificationGroup({
    required this.labelController,
    required this.optionControllers,
  });

  factory _EditableSpecificationGroup.fromGroup(
    CashierDishSpecificationGroup group,
  ) => _EditableSpecificationGroup(
    labelController: TextEditingController(text: group.label),
    optionControllers: group.options
        .map((option) => TextEditingController(text: option))
        .toList(),
  );

  factory _EditableSpecificationGroup.empty() => _EditableSpecificationGroup(
    labelController: TextEditingController(),
    optionControllers: [TextEditingController()],
  );

  final TextEditingController labelController;
  final List<TextEditingController> optionControllers;

  CashierDishSpecificationGroup toSpecification() =>
      CashierDishSpecificationGroup(
        label: labelController.text,
        options: optionControllers
            .map((controller) => controller.text)
            .toList(),
      );

  void dispose() {
    labelController.dispose();
    for (final controller in optionControllers) {
      controller.dispose();
    }
  }
}

class _SpecificationWarning extends StatelessWidget {
  const _SpecificationWarning();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('cashier-dish-spec-invalid-warning'),
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.cashier.warningBackground,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Icon(Icons.warning_amber_rounded, color: context.cashier.warning),
        const SizedBox(width: 8),
        const Expanded(child: Text('原规格数据无法识别，请删除后按名称和选项重新配置。')),
      ],
    ),
  );
}

class _SpecificationGroupFields extends StatelessWidget {
  const _SpecificationGroupFields({
    required this.groupIndex,
    required this.group,
    required this.allGroups,
    required this.onRemove,
    required this.onAddOption,
    required this.onRemoveOption,
  });

  final int groupIndex;
  final _EditableSpecificationGroup group;
  final List<_EditableSpecificationGroup> allGroups;
  final VoidCallback onRemove;
  final VoidCallback onAddOption;
  final ValueChanged<int> onRemoveOption;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.cashier.canvas,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.cashier.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                key: Key('cashier-dish-spec-group-label-$groupIndex'),
                controller: group.labelController,
                decoration: const InputDecoration(
                  labelText: '规格名称',
                  hintText: '例如：辣度、份量',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final label = value?.trim() ?? '';
                  if (label.isEmpty) return '请输入规格名称';
                  final duplicates = allGroups
                      .where(
                        (item) => item.labelController.text.trim() == label,
                      )
                      .length;
                  return duplicates > 1 ? '规格名称不能重复' : null;
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: Key('cashier-dish-spec-remove-group-$groupIndex'),
              tooltip: '删除规格',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('规格选项', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (
          var optionIndex = 0;
          optionIndex < group.optionControllers.length;
          optionIndex++
        ) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: Key('cashier-dish-spec-option-$groupIndex-$optionIndex'),
                  controller: group.optionControllers[optionIndex],
                  decoration: InputDecoration(
                    labelText: '选项 ${optionIndex + 1}',
                    hintText: '例如：不辣',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final option = value?.trim() ?? '';
                    if (option.isEmpty) return '请输入规格选项';
                    final duplicates = group.optionControllers
                        .where((item) => item.text.trim() == option)
                        .length;
                    return duplicates > 1 ? '规格选项不能重复' : null;
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: Key(
                  'cashier-dish-spec-remove-option-$groupIndex-$optionIndex',
                ),
                tooltip: '删除选项',
                onPressed: () => onRemoveOption(optionIndex),
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
            ],
          ),
          if (optionIndex < group.optionControllers.length - 1)
            const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        TextButton.icon(
          key: Key('cashier-dish-spec-add-option-$groupIndex'),
          onPressed: onAddOption,
          icon: const Icon(Icons.add_rounded),
          label: const Text('增加选项'),
        ),
      ],
    ),
  );
}
