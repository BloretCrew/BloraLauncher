#include "flutter_window.h"
#include "resource.h"

#include <optional>
#include <shellapi.h>
#include <uxtheme.h>
#include <vssym32.h>

#include "flutter/generated_plugin_registrant.h"
#include <flutter/encodable_value.h>
#include <flutter/standard_message_codec.h>

#define WM_TRAYICON (WM_USER + 1)
#define ID_TRAYICON 1001

static FlutterWindow* g_flutter_window = nullptr;

extern "C" __declspec(dllexport) void SetTaskbarProgress(uint64_t completed, uint64_t total) {
  if (g_flutter_window) g_flutter_window->SetTaskbarProgress(completed, total);
}

extern "C" __declspec(dllexport) void SetTaskbarState(int state) {
  if (g_flutter_window) g_flutter_window->SetTaskbarState(static_cast<TBPFLAG>(state));
}

extern "C" __declspec(dllexport) void SetTrayTheme(bool is_dark) {
  if (g_flutter_window) SetWindowTheme(g_flutter_window->GetHandle(), is_dark ? L"DarkMode_Explorer" : L"Explorer", NULL);
}

extern "C" __declspec(dllexport) void ShowTrayMenu(bool is_dark) {
  HMENU hMenu = CreatePopupMenu();
  AppendMenu(hMenu, MF_STRING, 1, L"访问 BBBS");
  AppendMenu(hMenu, MF_STRING, 2, L"访问 Bloret Passport");
  AppendMenu(hMenu, MF_STRING, 3, L"访问 百络图床");
  AppendMenu(hMenu, MF_SEPARATOR, 0, NULL);
  if (g_flutter_window && ::IsWindowVisible(g_flutter_window->GetHandle())) {
    AppendMenu(hMenu, MF_STRING, 4, L"隐藏窗口");
  } else {
    AppendMenu(hMenu, MF_STRING, 4, L"显示窗口");
  }
  AppendMenu(hMenu, MF_STRING, 5, L"退出程序");

  POINT pt;
  GetCursorPos(&pt);
  SetForegroundWindow(g_flutter_window->GetHandle());
  TrackPopupMenu(hMenu, TPM_RIGHTALIGN | TPM_BOTTOMALIGN, pt.x, pt.y, 0, g_flutter_window->GetHandle(), NULL);
  DestroyMenu(hMenu);
}

extern "C" __declspec(dllexport) void DestroyApp() { PostQuitMessage(0); }
extern "C" __declspec(dllexport) void HideApp() { if (g_flutter_window) g_flutter_window->Hide(); }

FlutterWindow::FlutterWindow(const flutter::DartProject& project) : project_(project) {
  g_flutter_window = this;
}

FlutterWindow::~FlutterWindow() {
  g_flutter_window = nullptr;
  if (taskbar_list_) {
    taskbar_list_->Release();
    taskbar_list_ = nullptr;
  }
}

void FlutterWindow::SetupTrayIcon() {
  NOTIFYICONDATA nid = { sizeof(NOTIFYICONDATA) };
  nid.hWnd = GetHandle();
  nid.uID = ID_TRAYICON;
  nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  nid.uCallbackMessage = WM_TRAYICON;
  nid.hIcon = LoadIcon(GetModuleHandle(NULL), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(nid.szTip, L"Bloret Launcher");
  Shell_NotifyIcon(NIM_ADD, &nid);
}

void FlutterWindow::Show() {
  ::ShowWindow(GetHandle(), SW_SHOW);
  SetForegroundWindow(GetHandle());
}

void FlutterWindow::Hide() {
  ::ShowWindow(GetHandle(), SW_HIDE);
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) return false;
  CoCreateInstance(CLSID_TaskbarList, NULL, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&taskbar_list_));

  RECT frame = GetClientArea();
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) return false;

  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  SetupTrayIcon();

  flutter_controller_->engine()->SetNextFrameCallback([&]() { this->Show(); });
  flutter_controller_->ForceRedraw();
  return true;
}

void FlutterWindow::SetTaskbarProgress(uint64_t completed, uint64_t total) {
  if (taskbar_list_) taskbar_list_->SetProgressValue(GetHandle(), completed, total);
}

void FlutterWindow::SetTaskbarState(TBPFLAG state) {
  if (taskbar_list_) taskbar_list_->SetProgressState(GetHandle(), state);
}

void FlutterWindow::OnDestroy() {
  NOTIFYICONDATA nid = { sizeof(NOTIFYICONDATA) };
  nid.hWnd = GetHandle();
  nid.uID = ID_TRAYICON;
  Shell_NotifyIcon(NIM_DELETE, &nid);

  if (flutter_controller_) flutter_controller_ = nullptr;
  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message, WPARAM const wparam, LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result = flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    if (result) return *result;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_COMMAND:
      switch(wparam) {
        case 1: {
          flutter::EncodableValue val("bbbs");
          auto data = flutter::StandardMessageCodec::GetInstance().EncodeMessage(val);
          flutter_controller_->engine()->messenger()->Send("bloret/tray", data->data(), data->size(), nullptr);
          break;
        }
        case 2: {
          flutter::EncodableValue val("passport");
          auto data = flutter::StandardMessageCodec::GetInstance().EncodeMessage(val);
          flutter_controller_->engine()->messenger()->Send("bloret/tray", data->data(), data->size(), nullptr);
          break;
        }
        case 3: {
          flutter::EncodableValue val("img_host");
          auto data = flutter::StandardMessageCodec::GetInstance().EncodeMessage(val);
          flutter_controller_->engine()->messenger()->Send("bloret/tray", data->data(), data->size(), nullptr);
          break;
        }
        case 4:
          if (::IsWindowVisible(hwnd)) Hide(); else Show();
          break;
        case 5: PostQuitMessage(0); break;
      }
      break;
    case WM_TRAYICON:
      if (lparam == WM_LBUTTONUP) {
        if (::IsWindowVisible(hwnd)) Hide(); else Show();
      } else if (lparam == WM_RBUTTONUP) {
        ShowTrayMenu(false);
      }
      break;
    case WM_CLOSE: {
      std::string msg = "on_close";
      flutter_controller_->engine()->messenger()->Send(
          "bloret/window_event",
          reinterpret_cast<const uint8_t*>(msg.c_str()),
          msg.size(),
          nullptr);
      return 0;
    }
  }
  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
