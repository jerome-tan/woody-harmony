#include <QCoreApplication>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLockFile>
#include <QTextStream>
#include <QThread>

int main(int argc, char **argv) {
  QCoreApplication app(argc, argv);
  QFile stateFile(qEnvironmentVariable("WOODY_FAKE_STATE"));
  if (!stateFile.open(QIODevice::ReadOnly))
    return 2;
  const auto state = QJsonDocument::fromJson(stateFile.readAll()).object();
  // A simulated slow command must not hold the fixture open. On Windows that
  // prevents QSaveFile from replacing it to simulate unplug/reconnect events.
  stateFile.close();
  const auto args = app.arguments().mid(1);
  const auto command = args.join(' ');
  {
    const auto logPath = qEnvironmentVariable("WOODY_FAKE_STATE") + ".commands";
    // Device metadata and app queries run in separate processes. Serialize
    // append writes so Windows file offsets cannot overwrite a start marker.
    // Release both handles before simulating a slow command or disconnect.
    QLockFile lock(logPath + ".lock");
    if (!lock.tryLock(5000))
      return 3;
    QFile log(logPath);
    if (!log.open(QIODevice::WriteOnly | QIODevice::Append))
      return 3;
    log.write(QJsonDocument(QJsonArray::fromStringList(args))
                  .toJson(QJsonDocument::Compact) +
              '\n');
    log.flush();
  }
  QTextStream out(stdout);
  if (state.contains("hdcFailure") &&
      (!command.endsWith("list targets") || state["failEnumeration"].toBool())) {
    out << state["hdcFailure"].toString() << '\n';
    return 0;
  }
  const int pid = state.value("pid").toInt(2411);
  const auto runningBundle = state.value("runningBundle").toString("com.example.woodyqa");
  if (command.endsWith("list targets")) {
    QThread::msleep(state["devicesDelayMs"].toInt(0));
    if (state["failDevices"].toBool())
      return 1;
    const auto targets = state.value("targets").toArray({"WOODY-QA-001"});
    for (const auto &target : targets)
      out << target.toString() << '\n';
    return 0;
  }
  if (command.contains("bm dump -a")) {
    QThread::msleep(state["appsDelayMs"].toInt(0));
    if (state["failApps"].toBool())
      return 1;
    if (state.contains("appsOutput")) {
      out << state["appsOutput"].toString();
      return 0;
    }
    const auto bundles = state.value("installedBundles").toArray(
        {"com.example.stopped", "com.example.woodyqa"});
    if (bundles.isEmpty())
      out << "[]\n";
    for (const auto &bundle : bundles)
      out << bundle.toString() << '\n';
    return 0;
  }
  if (command.endsWith("echo woody-device-ready")) {
    out << "woody-device-ready\n";
    return 0;
  }
  if (command.contains("bm dump -n ")) {
    QThread::msleep(state["appInfoDelayMs"].toInt(0));
    if (state["failAppInfo"].toBool())
      return 1;
    if (state.contains("appInfoOutput")) {
      out << state["appInfoOutput"].toString();
      return 0;
    }
    const auto bundle = command.section("bm dump -n ", 1).trimmed();
    const auto debug = state.value("appDebug").isUndefined()
                           ? QJsonValue(bundle == "com.example.woodyqa")
                           : state["appDebug"];
    // Deliberately disagree with debug: signing must not affect the result.
    const QJsonObject info{{"debug", debug},
                           {"appProvisionType", debug.toBool() ? "release" : "debug"}};
    out << bundle << ":\n" << QJsonDocument(QJsonObject{{"applicationInfo", info}}).toJson();
    return 0;
  }
  if (command.contains("pidof ")) {
    QThread::msleep(state["pidDelayMs"].toInt(0));
    if (pid && command.section("pidof ", 1).trimmed() == runningBundle)
      out << pid << '\n';
    return 0;
  }
  if (command.endsWith("ps -ef")) {
    out << "UID PID PPID C STIME TTY TIME CMD\n";
    if (pid)
      out << "2000 " << pid << " 1 0 00:00 ? 00:00:01 " << runningBundle << '\n';
    return 0;
  }
  if (command.contains("param get ")) {
    QThread::msleep(state["deviceInfoDelayMs"].toInt(0));
    const auto name = command.section(' ', -1);
    const QJsonObject params{{"const.product.name", state.value("marketName").toString("HUAWEI QA Device")},
                             {"const.product.model", "QA-001"},
                             {"const.product.os.dist.name", "HarmonyOS"},
                             {"const.ohos.fullname", "OpenHarmony-6.1.1.120"},
                             {"const.product.os.dist.version", "6.1.1.120"},
                             {"const.ohos.apiversion", "18"}};
    out << params[name].toString() << '\n';
    return 0;
  }
  if (command.endsWith("cat /proc/meminfo")) {
    out << "MemTotal: 12582912 kB\nMemFree: 1024 kB\nCached: 2048 kB\n";
    return 0;
  }
  if (command.contains("RenderService")) {
    out << "render resolution=1260x2720\n";
    return 0;
  }
  if (command.contains("--mem-smaps")) {
    out << "1000-2000 rw-p 0 0 0 [heap]\nPss: 64 kB\n";
    return 0;
  }
  if (command.contains("hidumper --mem ")) {
    const auto requested =
        command.section("hidumper --mem ", 1).section(' ', 0, 0).toInt();
    if (requested != pid || state["fail"].toBool())
      return 1;
    QThread::msleep(state["delayMs"].toInt(0));
    out << "Total 196608 10 20 30 65536 0 128 65536 32768 32768\n"
           "native heap 65536 0 0 0 32768 0 0 65536 32768 32768\n"
           "GL 131072 0 0 0 32768 0 128 0 0 0\n"
           "jemalloc heap 65024 0 0 0 32768 0 0 65536 32768 32768\n"
           "PurgSum: 256 kB\nPurgPin: 128 kB\nDma: 4096 kB\nTotal Ashmem: 2048 "
           "kB\n";
    if (command.contains("--show-dmabuf"))
      out << "DMA:\napp  2411  9  4194304  123456  RenderXComponent\n";
    if (command.contains("--show-ashmem"))
      out << "Ashmem:\napp\t2411\t7\t0\t2411\tdev/ashmem/Create "
             "PixelMap\t8388608\t4194304\t0\n";
    if (command.contains("--show-gpumem"))
      out << "GPU:\nChannel:GL (Total memory: 67108864)\nTotal used memory: "
             "67108864\nTotal allocated memory: 83886080\n";
    return 0;
  }
  return 1;
}
