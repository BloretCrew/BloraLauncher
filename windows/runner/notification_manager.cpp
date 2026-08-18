#include "notification_manager.h"

#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <propvarutil.h>
#include <propkey.h>

#include <filesystem>

#include <winrt/base.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.UI.Notifications.h>

using namespace winrt;
using namespace Windows::Data::Xml::Dom;
using namespace Windows::UI::Notifications;

namespace {

    constexpr wchar_t kAppId[] = L"Blora Launcher";
    constexpr wchar_t kAppName[] = L"Blora Launcher";

    std::wstring GetExePath() {
        wchar_t path[MAX_PATH];

        DWORD length = GetModuleFileNameW(
                nullptr,
                path,
                MAX_PATH);

        if (length == 0) {
            return {};
        }

        return std::wstring(path, length);
    }

    std::wstring GetShortcutPath() {
        wchar_t appData[MAX_PATH];

        if (SHGetFolderPathW(
                nullptr,
                CSIDL_PROGRAMS,
                nullptr,
                SHGFP_TYPE_CURRENT,
                appData) != S_OK) {
            return {};
        }

        std::filesystem::path path(appData);
        path /= L"Blora Launcher.lnk";

        return path.wstring();
    }

    bool CreateShortcut() {
        std::wstring shortcutPath = GetShortcutPath();
        std::wstring exePath = GetExePath();

        if (shortcutPath.empty() || exePath.empty()) {
            return false;
        }

        if (GetFileAttributesW(shortcutPath.c_str()) != INVALID_FILE_ATTRIBUTES) {
            return true;
        }

        winrt::com_ptr<IShellLinkW> shellLink;

        HRESULT hr = CoCreateInstance(
                CLSID_ShellLink,
                nullptr,
                CLSCTX_INPROC_SERVER,
                IID_PPV_ARGS(shellLink.put()));

        if (FAILED(hr)) {
            return false;
        }

        shellLink->SetPath(exePath.c_str());
        shellLink->SetDescription(kAppName);

        winrt::com_ptr<IPropertyStore> propertyStore;

        hr = shellLink->QueryInterface(
                IID_PPV_ARGS(propertyStore.put()));

        if (FAILED(hr)) {
            return false;
        }

        PROPVARIANT appId;
        PropVariantInit(&appId);

        hr = InitPropVariantFromString(
                kAppId,
                &appId);

        if (FAILED(hr)) {
            return false;
        }

        hr = propertyStore->SetValue(
                PKEY_AppUserModel_ID,
                appId);

        PropVariantClear(&appId);

        if (FAILED(hr)) {
            return false;
        }

        hr = propertyStore->Commit();

        if (FAILED(hr)) {
            return false;
        }

        winrt::com_ptr<IPersistFile> persistFile;

        hr = shellLink->QueryInterface(
                IID_PPV_ARGS(persistFile.put()));

        if (FAILED(hr)) {
            return false;
        }

        hr = persistFile->Save(
                shortcutPath.c_str(),
                TRUE);

        return SUCCEEDED(hr);
    }

}  // namespace

bool NotificationManager::EnsureShortcut() {
    return CreateShortcut();
}

bool NotificationManager::Show(
        const std::wstring& title,
        const std::wstring& body) {

    if (!EnsureShortcut()) {
        return false;
    }

    try {
        XmlDocument xml;

        std::wstring toast =
                L"<toast>"
                L"<visual>"
                L"<binding template=\"ToastGeneric\">"
                L"<text>" + title +
                L"</text>"
                L"<text>" + body +
                L"</text>"
                L"</binding>"
                L"</visual>"
                L"</toast>";

        xml.LoadXml(toast);

        ToastNotification notification(xml);

        auto notifier =
                ToastNotificationManager::CreateToastNotifier(
                        kAppId);

        notifier.Show(notification);

        return true;
    } catch (...) {
        return false;
    }
}