#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

extern "C" __declspec(dllexport) void SetTaskbarProgress(uint64_t completed, uint64_t total);
extern "C" __declspec(dllexport) void SetTaskbarState(int state);

static FlutterWindow* g_flutter_window = nullptr;

extern "C" __declspec(dllexport) void SetTaskbarProgress(uint64_t completed, uint64_t total) {
  if (g_flutter_window) {
    g_flutter_window->SetTaskbarProgress(completed, total);
  }
}

extern "C" __declspec(dllexport) void SetTaskbarState(int state) {
  if (g_flutter_window) {
    g_flutter_window->SetTaskbarState(static_cast<TBPFLAG>(state));
  }
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {
  g_flutter_window = this;
}

FlutterWindow::~FlutterWindow() {
  g_flutter_window = nullptr;
  if (taskbar_list_) {
    taskbar_list_->Release();
    taskbar_list_ = nullptr;
  }
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  CoCreateInstance(CLSID_TaskbarList, NULL, CLSCTX_INPROC_SERVER,
                   IID_PPV_ARGS(&taskbar_list_));

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SetTaskbarProgress(uint64_t completed, uint64_t total) {
  if (taskbar_list_) {
    taskbar_list_->SetProgressValue(GetHandle(), completed, total);
  }
}

void FlutterWindow::SetTaskbarState(TBPFLAG state) {
  if (taskbar_list_) {
    taskbar_list_->SetProgressState(GetHandle(), state);
  }
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
