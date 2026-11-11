// Standalone updater: no Qt DLL/framework dependency, so it can keep running
// while the original application directory is replaced.
#include <chrono>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <set>
#include <thread>
#include <vector>
#ifdef _WIN32
#include <windows.h>
#else
#include <cerrno>
#include <csignal>
#include <sys/wait.h>
#include <unistd.h>
#endif
namespace fs = std::filesystem;
using namespace std::chrono_literals;
#ifdef _WIN32
using Process = HANDLE;
std::wstring quote(const std::wstring &value) {
  std::wstring out = L"\""; size_t slashes = 0;
  for (wchar_t c : value) {
    if (c == L'\\') { ++slashes; continue; }
    out.append(slashes * (c == L'"' ? 2 : 1), L'\\'); slashes = 0;
    if (c == L'"') out += L'\\';
    out += c;
  }
  out.append(slashes * 2, L'\\'); return out + L'"';
}
Process start(const fs::path &exe, const std::vector<fs::path> &args) {
  std::wstring command = quote(exe.wstring());
  for (const auto &arg : args) {
    const auto value = arg.wstring();
    // NSIS consumes the raw remainder after /D=, including spaces.
    command += L" " + (value.starts_with(L"/D=") ? value : quote(value));
  }
  STARTUPINFOW info{}; info.cb = sizeof(info); PROCESS_INFORMATION process{};
  if (!CreateProcessW(exe.c_str(), command.data(), nullptr, nullptr, FALSE,
                      CREATE_NO_WINDOW, nullptr, exe.parent_path().c_str(), &info, &process))
    throw std::runtime_error("无法启动程序");
  CloseHandle(process.hThread); return process.hProcess;
}
bool exited(Process p) { return WaitForSingleObject(p, 0) == WAIT_OBJECT_0; }
void closeProcess(Process p) { CloseHandle(p); }
void terminate(Process p) { TerminateProcess(p, 1); WaitForSingleObject(p, 5000); }
#else
using Process = pid_t;
Process start(const fs::path &exe, const std::vector<fs::path> &args) {
  std::vector<std::string> strings{exe.string()};
  for (const auto &arg : args) strings.push_back(arg.string());
  std::vector<char *> argv;
  for (auto &s : strings) argv.push_back(s.data());
  argv.push_back(nullptr);
  const pid_t pid = fork();
  if (pid < 0) throw std::runtime_error("无法启动程序");
  if (pid == 0) { chdir(exe.parent_path().c_str()); execv(exe.c_str(), argv.data()); _exit(127); }
  return pid;
}
bool exited(Process p) { int status; return waitpid(p, &status, WNOHANG) == p; }
void closeProcess(Process) {}
void terminate(Process p) { kill(p, SIGKILL); waitpid(p, nullptr, 0); }
#endif
void waitParent(unsigned long parent) {
#ifdef _WIN32
  HANDLE process = OpenProcess(SYNCHRONIZE, FALSE, parent);
  if (!process) {
    if (GetLastError() == ERROR_INVALID_PARAMETER) return;
    throw std::runtime_error("无法等待原程序退出");
  }
  const auto result = WaitForSingleObject(process, 120000); CloseHandle(process);
  if (result != WAIT_OBJECT_0) throw std::runtime_error("原程序尚未退出，未安装更新");
#else
  for (int i = 0; i < 1200; ++i) {
    if (kill(static_cast<pid_t>(parent), 0) != 0 && errno == ESRCH) return;
    std::this_thread::sleep_for(100ms);
  }
  throw std::runtime_error("原程序尚未退出，未安装更新");
#endif
}
fs::path executable(const fs::path &target) {
#ifdef _WIN32
  return target / "Woody.exe";
#else
  return target / "Contents/MacOS/Woody";
#endif
}
void writeResult(const fs::path &path, const std::string &text) {
  std::ofstream file(path, std::ios::trunc); file << text; file.flush();
}
unsigned long launchReady(const fs::path &target, const fs::path &ready) {
  fs::remove(ready);
  Process p = start(executable(target), {"--ready-file", ready});
  for (int i = 0; i < 450; ++i) {
    if (fs::exists(ready)) {
#ifdef _WIN32
      const auto pid = GetProcessId(p);
#else
      const auto pid = p;
#endif
      closeProcess(p); return static_cast<unsigned long>(pid);
    }
    if (exited(p)) { closeProcess(p); return 0; }
    std::this_thread::sleep_for(100ms);
  }
  terminate(p); closeProcess(p); return 0;
}
void preservePortableFiles(const fs::path &old, const fs::path &staged) {
#ifdef _WIN32
  std::ifstream manifest(old / ".woody-files");
  if (!manifest) throw std::runtime_error("当前目录版缺少文件清单，请手动更新");
  std::set<fs::path> managed;
  std::string line;
  while (std::getline(manifest, line)) {
    if (!line.empty() && line.back() == '\r') line.pop_back();
    managed.insert(fs::u8path(line));
  }
  for (const auto &entry : fs::recursive_directory_iterator(old)) {
    const auto relative = entry.path().lexically_relative(old);
    if (managed.contains(relative)) continue;
    const auto destination = staged / relative;
    if (entry.is_directory()) { fs::create_directories(destination); continue; }
    if (fs::exists(destination)) throw std::runtime_error("用户文件与新版程序重名，请手动更新");
    fs::create_directories(destination.parent_path());
    fs::copy(entry.path(), destination, fs::copy_options::copy_symlinks);
  }
#else
  (void)old; (void)staged;
#endif
}
int apply(unsigned long parent, const fs::path &target, const fs::path &source,
          bool installer, const fs::path &result, const fs::path &temporary) {
  fs::path staged, backup;
  bool movedOld = false, movedNew = false, parentExited = false, ownsStaged = false;
  try {
    waitParent(parent); parentExited = true;
    if (!target.is_absolute() || target == target.root_path() || !fs::is_regular_file(executable(target))
        || !source.is_absolute() || !fs::exists(source) || !temporary.is_absolute())
      throw std::runtime_error("更新路径无效，未更改原程序");
    // Stage on the same volume. The final directory
    // renames are atomic and never merge old DLLs with a new runtime.
    if (!installer) {
      if (!fs::is_regular_file(executable(source))) throw std::runtime_error("更新包缺少程序文件");
      staged = target.parent_path() / (".woody-new-" + temporary.filename().string());
      backup = target.parent_path() / (".woody-old-" + temporary.filename().string());
      if (fs::exists(staged) || fs::exists(backup)) throw std::runtime_error("更新临时目录已存在");
      ownsStaged = true;
      fs::copy(source, staged, fs::copy_options::recursive | fs::copy_options::copy_symlinks);
      preservePortableFiles(target, staged);
    }
    if (installer) {
#ifdef _WIN32
      Process p = start(source, {"/S", fs::path(L"/D=" + target.wstring())});
      const auto waited = WaitForSingleObject(p, 300000);
      DWORD code = 1; GetExitCodeProcess(p, &code); CloseHandle(p);
      if (waited != WAIT_OBJECT_0 || code != 0) throw std::runtime_error("安装程序未成功完成，请从 Release 重新安装");
#else
      throw std::runtime_error("此平台不支持该安装方式");
#endif
    } else {
      fs::rename(target, backup); movedOld = true;
      fs::rename(staged, target); movedNew = true;
    }
    const auto newPid = launchReady(target, temporary / "ready");
    if (!newPid) throw std::runtime_error(installer ? "新版安装后未能启动，请从 Release 重新安装" : "新版未能启动，已尝试恢复原版本");
    writeResult(result, "OK:" + std::to_string(newPid));
    // Keep a successful backup until launch acknowledgement, then remove only
    // the specific directory created by this update transaction.
    std::error_code ignored;
    if (movedOld) fs::remove_all(backup, ignored);
    // Windows cannot remove the running helper; leave only it in the OS temp
    // folder, with no application bundles for Spotlight to index.
    for (const auto &entry : fs::directory_iterator(temporary)) {
      fs::remove_all(entry.path(), ignored);
    }
    return 0;
  } catch (const std::exception &e) {
    std::string message = e.what();
    try {
      if (movedOld) {
        if (movedNew) fs::rename(target, staged);
        fs::rename(backup, target);
      }
    } catch (const std::exception &) { message += "；原版本保留在同目录 .woody-old-*，请手动恢复。"; }
    writeResult(result, "ERROR:" + message);
    if (parentExited && fs::exists(executable(target))) {
      try { closeProcess(start(executable(target), {})); } catch (...) {}
    }
    std::error_code ignored;
    if (ownsStaged) fs::remove_all(staged, ignored);
    return 1;
  }
}
#ifdef _WIN32
int wmain(int argc, wchar_t **argv) {
  if (argc != 7) return 2;
  try { return apply(std::stoul(argv[1]), argv[2], argv[3], std::wstring(argv[4]) == L"installer", argv[5], argv[6]); }
  catch (...) { return 2; }
}
#else
int main(int argc, char **argv) {
  if (argc != 7) return 2;
  try { return apply(std::stoul(argv[1]), argv[2], argv[3], std::string(argv[4]) == "installer", argv[5], argv[6]); }
  catch (...) { return 2; }
}
#endif
