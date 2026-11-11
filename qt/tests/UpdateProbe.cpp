// Minimal replacement app for updater lifecycle tests; no Qt/runtime dependencies.
#include <chrono>
#include <filesystem>
#include <fstream>
#include <thread>
#ifdef _WIN32
int wmain(int argc, wchar_t **argv) {
#else
int main(int argc, char **argv) {
#endif
  namespace fs = std::filesystem;
  const fs::path self = fs::absolute(argv[0]);
  std::ifstream config(self.parent_path() / "probe-mode.txt");
  std::string mode; config >> mode;
  if (mode == "fail") return 7;
  if (argc == 3) {
    std::ofstream ready{fs::path(argv[2])}; ready << "ready"; ready.close();
  }
  std::ofstream marker(self.parent_path() / "started.txt"); marker << mode; marker.close();
  std::this_thread::sleep_for(std::chrono::milliseconds(800));
  return 0;
}
