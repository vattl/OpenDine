#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>

#include "crash_handler.h"
#include "flutter/generated_plugin_registrant.h"

namespace {

WNDPROC g_original_flutter_view_wndproc = nullptr;

// The Flutter view child window's window procedure is registered inside the
// engine (flutter_windows.dll), so the WM_GETOBJECT interception on the top
// level window cannot reach it. When UIA/MSAA clients probe the window tree
// (screen readers, accessibility scanners, remote assistance, etc.), the
// engine's internal WM_GETOBJECT handling can null-dereference
// (0xC0000005, read at +0x50 offset). Intercept the message on the child
// window as well; the only trade-off is losing screen-reader support for this
// window, acceptable for internal cashier use.
LRESULT CALLBACK FlutterViewWindowProc(HWND window, UINT message,
                                       WPARAM wparam, LPARAM lparam) noexcept {
  if (message == WM_GETOBJECT) {
    return 0;
  }
  return ::CallWindowProc(g_original_flutter_view_wndproc, window, message,
                          wparam, lparam);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetNativeAccessibilityGuardState(true, "global_default_enabled");
  crash_guard_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "laofei_cashier/native_crash_guard",
          &flutter::StandardMethodCodec::GetInstance());
  crash_guard_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "setReceiptTemplateTextGuard") {
          result->NotImplemented();
          return;
        }
        const auto* arguments = call.arguments();
        const auto* enabled =
            arguments == nullptr ? nullptr : std::get_if<bool>(arguments);
        if (enabled == nullptr) {
          result->Error("invalid_argument", "Expected a boolean guard state");
          return;
        }
        // Keep global crash guard permanently enabled to protect against
        // flutter_windows.dll accessibility null-dereference crashes across all pages.
        suppress_accessibility_requests_ = true;
        SetNativeAccessibilityGuardState(
            true, *enabled ? "receipt_template_text_enabled"
                           : "receipt_template_text_disabled");
        result->Success();
      });

  // Subclass the Flutter view child window to intercept WM_GETOBJECT,
  // covering the engine-internal window procedure path that the top-level
  // window interception cannot reach.
  flutter_view_window_ = flutter_controller_->view()->GetNativeWindow();
  g_original_flutter_view_wndproc = reinterpret_cast<WNDPROC>(
      ::SetWindowLongPtrW(flutter_view_window_, GWLP_WNDPROC,
                          reinterpret_cast<LONG_PTR>(&FlutterViewWindowProc)));
  SetChildContent(flutter_view_window_);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  suppress_accessibility_requests_ = false;
  SetNativeAccessibilityGuardState(false, "window_destroyed");
  // Restore the original window procedure of the Flutter view child window so
  // the engine does not unload a subclassed window procedure during teardown.
  if (g_original_flutter_view_wndproc != nullptr &&
      flutter_view_window_ != nullptr && ::IsWindow(flutter_view_window_)) {
    ::SetWindowLongPtrW(flutter_view_window_, GWLP_WNDPROC,
                        reinterpret_cast<LONG_PTR>(
                            g_original_flutter_view_wndproc));
    g_original_flutter_view_wndproc = nullptr;
  }
  crash_guard_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  RecordNativeWindowMessage(hwnd, message, wparam, lparam, "before_dispatch");
  if (suppress_accessibility_requests_ && message == WM_GETOBJECT) {
    RecordNativeWindowMessage(hwnd, message, wparam, lparam,
                              "suppressed_global_accessibility_guard");
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    RecordNativeWindowMessage(hwnd, message, wparam, lparam, "before_engine");
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      RecordNativeWindowMessage(hwnd, message, wparam, lparam,
                                "engine_handled");
      return *result;
    }
    RecordNativeWindowMessage(hwnd, message, wparam, lparam, "after_engine");
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  const LRESULT result =
      Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  RecordNativeWindowMessage(hwnd, message, wparam, lparam, "after_runner");
  return result;
}

