#include "my_application.h"
#include <X11/Xlib.h>

int main(int argc, char** argv) {
  // Native EGL video rendering can touch the X11 connection off the GTK
  // platform thread. Initialize Xlib thread support before GTK starts.
  XInitThreads();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
