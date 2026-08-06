#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include <string>
#include <vector>
#include <cstring>

static GtkWindow* g_window = nullptr;
static FlBinaryMessenger* g_messenger = nullptr;
static bool g_is_dark = true; // Default to dark

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
static GtkStatusIcon* g_status_icon = nullptr;
#pragma GCC diagnostic pop

extern "C" __attribute__((visibility("default")))
void SetTaskbarProgress(uint64_t completed, uint64_t total) {}

extern "C" __attribute__((visibility("default")))
void SetTaskbarState(int state) {}

extern "C" __attribute__((visibility("default")))
void SetTrayTheme(bool is_dark) { g_is_dark = is_dark; }

extern "C" __attribute__((visibility("default")))
void c_terminate_process() { exit(0); }

extern "C" __attribute__((visibility("default")))
void DestroyApp() { c_terminate_process(); }

extern "C" __attribute__((visibility("default")))
void HideApp() {
  if (g_window) gtk_widget_hide(GTK_WIDGET(g_window));
}

extern "C" __attribute__((visibility("default")))
void SetDarkMode(bool dark) {
  g_is_dark = dark;
  GtkSettings *settings = gtk_settings_get_default();
  g_object_set(settings, "gtk-application-prefer-dark-theme", dark, NULL);
}

extern "C" __attribute__((visibility("default")))
void SetIconTheme(bool dark) {
  if (!g_window) return;
  SetDarkMode(dark);

  g_autofree gchar* executable_path = g_file_read_link("/proc/self/exe", nullptr);
  if (executable_path == nullptr) return;
  g_autofree gchar* dir = g_path_get_dirname(executable_path);
  const char* icon_name = dark ? "bloret_dark.png" : "bloret_light.png";
  g_autofree gchar* icon_path = g_build_filename(dir, "data", "flutter_assets", "assets", icon_name, nullptr);

  GError* error = nullptr;
  gtk_window_set_icon_from_file(g_window, icon_path, &error);

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
  if (g_status_icon) {
    gtk_status_icon_set_from_file(g_status_icon, icon_path);
  }
#pragma GCC diagnostic pop

  if (error) {
    g_clear_error(&error);
    const char* ico_name = dark ? "bloret_dark.ico" : "bloret_light.ico";
    g_autofree gchar* ico_path = g_build_filename(dir, "data", "flutter_assets", "assets", ico_name, nullptr);
    gtk_window_set_icon_from_file(g_window, ico_path, &error);
    if (error) {
      g_warning("Failed to set icon: %s", error->message);
      g_error_free(error);
    }
  }
}

static void send_tray_event(const char* action) {
  if (!g_messenger) return;
  g_autoptr(FlValue) val = fl_value_new_string(action);
  g_autoptr(FlStandardMessageCodec) codec = fl_standard_message_codec_new();
  g_autoptr(GBytes) data = fl_message_codec_encode_message(FL_MESSAGE_CODEC(codec), val, nullptr);
  fl_binary_messenger_send_on_channel(g_messenger, "bloret/tray", data, nullptr, nullptr, nullptr);
}

static void on_menu_item_clicked(GtkMenuItem* menu_item, gpointer user_data) {
  const char* action = (const char*)user_data;
  if (strcmp(action, "hide_show") == 0) {
    if (g_window) {
      if (gtk_widget_get_visible(GTK_WIDGET(g_window))) {
        gtk_widget_hide(GTK_WIDGET(g_window));
      } else {
        gtk_window_present(g_window);
      }
    }
  } else if (strcmp(action, "exit") == 0) {
    exit(0);
  } else {
    send_tray_event(action);
  }
}

extern "C" __attribute__((visibility("default")))
void ShowTrayMenu(bool is_dark) {
  GtkWidget* menu = gtk_menu_new();

  static const struct { const char* label; const char* action; } items[] = {
    {"访问 BBBS", "bbbs"},
    {"访问 Bloret Passport", "passport"},
    {"访问 百络图床", "img_host"}
  };

  for (const auto& item : items) {
    GtkWidget* mi = gtk_menu_item_new_with_label(item.label);
    g_signal_connect(mi, "activate", G_CALLBACK(on_menu_item_clicked), (gpointer)item.action);
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), mi);
  }

  gtk_menu_shell_append(GTK_MENU_SHELL(menu), gtk_separator_menu_item_new());

  const char* toggle_label = (g_window && gtk_widget_get_visible(GTK_WIDGET(g_window))) ? "隐藏窗口" : "显示窗口";
  GtkWidget* mi_toggle = gtk_menu_item_new_with_label(toggle_label);
  g_signal_connect(mi_toggle, "activate", G_CALLBACK(on_menu_item_clicked), (gpointer)"hide_show");
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), mi_toggle);

  GtkWidget* mi_exit = gtk_menu_item_new_with_label("退出程序");
  g_signal_connect(mi_exit, "activate", G_CALLBACK(on_menu_item_clicked), (gpointer)"exit");
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), mi_exit);

  gtk_widget_show_all(menu);
  gtk_menu_popup_at_pointer(GTK_MENU(menu), NULL);
}

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
static void on_status_icon_activate(GtkStatusIcon* icon, gpointer user_data) {
  if (g_window) {
    if (gtk_widget_get_visible(GTK_WIDGET(g_window))) {
      gtk_widget_hide(GTK_WIDGET(g_window));
    } else {
      gtk_window_present(g_window);
    }
  }
}

static void on_status_icon_popup_menu(GtkStatusIcon* icon, guint button, guint activate_time, gpointer user_data) {
  ShowTrayMenu(g_is_dark);
}
#pragma GCC diagnostic pop

static gboolean on_window_delete_event(GtkWidget* widget, GdkEventAny* event, gpointer user_data) {
  g_print("delete-event triggered\n");
  if (!g_messenger) {
    g_print("NO MESSENGER\n");
    return TRUE;
  }
  const char* msg = "on_close";
  g_autoptr(GBytes) data = g_bytes_new(msg, strlen(msg));
  fl_binary_messenger_send_on_channel(g_messenger, "bloret/window_event", data, nullptr, nullptr, nullptr);
  return TRUE;
}

static void setup_tray_icon() {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
  g_status_icon = gtk_status_icon_new();
  g_autofree gchar* executable_path = g_file_read_link("/proc/self/exe", nullptr);
  if (executable_path) {
    g_autofree gchar* dir = g_path_get_dirname(executable_path);
    g_autofree gchar* icon_path = g_build_filename(dir, "data", "flutter_assets", "assets", "bloret_dark.png", nullptr);
    gtk_status_icon_set_from_file(g_status_icon, icon_path);
  }
  gtk_status_icon_set_tooltip_text(g_status_icon, "Blora Launcher");
  g_signal_connect(g_status_icon, "activate", G_CALLBACK(on_status_icon_activate), NULL);
  g_signal_connect(g_status_icon, "popup-menu", G_CALLBACK(on_status_icon_popup_menu), NULL);
  gtk_status_icon_set_visible(g_status_icon, TRUE);
#pragma GCC diagnostic pop
}

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void on_window_destroy(GtkWidget* widget, gpointer user_data) {
  g_print("DESTROY triggered\n");
}

static void on_shutdown(GApplication* app, gpointer data) {
  g_print("GAPPLICATION SHUTDOWN\n");
}

static void on_quit(GApplication* app, gpointer data) {
  g_print("GAPPLICATION QUIT\n");
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Blora Launcher");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Blora Launcher");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  gtk_widget_show(GTK_WIDGET(view));

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));

  g_window = window;
  g_messenger = fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_signal_connect(window, "delete-event", G_CALLBACK(on_window_delete_event), NULL);
  g_signal_connect(
          window,
          "destroy",
          G_CALLBACK(on_window_destroy),
          nullptr
  );
  g_signal_connect(application, "shutdown",
                   G_CALLBACK(on_shutdown), nullptr);

  g_signal_connect(application, "quit",
                   G_CALLBACK(on_quit), nullptr);

  // Set initial icon
  g_autofree gchar* executable_path = g_file_read_link("/proc/self/exe", nullptr);
  if (executable_path) {
    g_autofree gchar* dir = g_path_get_dirname(executable_path);
    g_autofree gchar* icon_path = g_build_filename(dir, "data", "flutter_assets", "assets", "bloret_dark.png", nullptr);
    if (g_file_test(icon_path, G_FILE_TEST_EXISTS)) {
      gtk_window_set_icon_from_file(window, icon_path, nullptr);
      gtk_window_set_default_icon_from_file(icon_path, nullptr);
    }
  }

  setup_tray_icon();
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  g_set_prgname("Blora Launcher");
  g_set_application_name("Blora Launcher");
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
