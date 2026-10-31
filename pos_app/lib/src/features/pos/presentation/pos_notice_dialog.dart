import 'package:flutter/material.dart';

enum PosNoticeTone { info, success, warning, error }

Future<bool> showPosNotice(
  BuildContext context, {
  required String title,
  required String message,
  PosNoticeTone tone = PosNoticeTone.info,
  String primaryLabel = '确定',
  String? secondaryLabel,
  bool barrierDismissible = false,
}) async {
  // Successful mutations update the page in place. Only confirmations and
  // actionable warnings/errors should interrupt the cashier workflow.
  if (tone == PosNoticeTone.success) return true;
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: const Color(0x66000000),
    builder: (_) => _PosNoticeDialog(
      title: title,
      message: message,
      tone: tone,
      primaryLabel: primaryLabel,
      secondaryLabel: secondaryLabel,
    ),
  );
  final result = await navigator.push<bool>(route);
  // A popped dialog route can complete before its modal barrier leaves the
  // overlay on Flutter Web. Wait through overlay cleanup before callers push
  // another route, otherwise the POS page can open behind a gray barrier.
  await route.completed;
  await Future<void>.delayed(Duration.zero);
  await WidgetsBinding.instance.endOfFrame;
  await WidgetsBinding.instance.endOfFrame;
  return result ?? false;
}

class _PosNoticeDialog extends StatelessWidget {
  const _PosNoticeDialog({
    required this.title,
    required this.message,
    required this.tone,
    required this.primaryLabel,
    required this.secondaryLabel,
  });

  final String title;
  final String message;
  final PosNoticeTone tone;
  final String primaryLabel;
  final String? secondaryLabel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      elevation: 24,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: SizedBox(
        key: const Key('pos-notice-dialog'),
        width: 604,
        height: 364,
        child: Column(
          children: [
            SizedBox(
              height: 79,
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0xff2d2d2d)),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 5,
                    child: ColoredBox(
                      key: const Key('pos-notice-tone'),
                      color: tone.color,
                    ),
                  ),
                  Semantics(
                    label: '${tone.accessibilityLabel}：$title',
                    header: true,
                    child: Center(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 13,
                    right: 14,
                    child: IconButton(
                      key: const Key('pos-notice-close'),
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close, color: Colors.white),
                      iconSize: 34,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned(
                    left: 44,
                    right: 44,
                    top: 40,
                    height: 112,
                    child: Center(
                      child: SingleChildScrollView(
                        key: const Key('pos-notice-message-scroll'),
                        child: Text(
                          message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xff2d2d2d),
                            fontSize: 30,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (secondaryLabel != null)
                    Positioned(
                      left: 77,
                      bottom: 34,
                      child: _NoticeButton(
                        key: const Key('pos-notice-secondary'),
                        label: secondaryLabel!,
                        color: const Color(0xffaeaeae),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                    ),
                  Positioned(
                    left: secondaryLabel == null ? 200 : 324,
                    bottom: 34,
                    child: _NoticeButton(
                      key: const Key('pos-notice-primary'),
                      label: primaryLabel,
                      color: const Color(0xff2d2d2d),
                      onPressed: () => Navigator.of(context).pop(true),
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

extension on PosNoticeTone {
  Color get color => switch (this) {
    PosNoticeTone.info => const Color(0xff3b82d9),
    PosNoticeTone.success => const Color(0xff31b867),
    PosNoticeTone.warning => const Color(0xffed9b2b),
    PosNoticeTone.error => const Color(0xffdf4d4d),
  };

  String get accessibilityLabel => switch (this) {
    PosNoticeTone.info => '信息提示',
    PosNoticeTone.success => '操作成功',
    PosNoticeTone.warning => '操作警告',
    PosNoticeTone.error => '操作失败',
  };
}

class _NoticeButton extends StatelessWidget {
  const _NoticeButton({
    super.key,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 204,
      height: 80,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: 4,
            ),
          ),
        ),
      ),
    );
  }
}
