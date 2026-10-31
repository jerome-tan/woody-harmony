#include <QCoreApplication>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>
#include <QThread>

int main(int argc, char **argv) {
  QCoreApplication app(argc, argv);
  QFile stateFile(qEnvironmentVariable("WOODY_FAKE_STATE"));
  if (!stateFile.open(QIODevice::ReadOnly))
    return 2;
  const auto state = QJsonDocument::fromJson(stateFile.readAll()).object();
  const auto args = app.arguments().mid(1);
  const auto command = args.join(' ');
  QFile log(qEnvironmentVariable("WOODY_FAKE_STATE") + ".commands");
  if (log.open(QIODevice::WriteOnly | QIODevice::Append))
    log.write(QJsonDocument(QJsonArray::fromStringList(args))
                  .toJson(QJsonDocument::Compact) +
              '\n');
  QTextStream out(stdout);
  const int pid = state.value("pid").toInt(2411);
  if (command.endsWith("list targets")) {
    out << "WOODY-QA-001\n";
    return 0;
  }
  if (command.contains("bm dump -a")) {
    out << "com.example.stopped\ncom.example.woodyqa\n";
    return 0;
  }
  if (command.contains("pidof ")) {
    if (pid)
      out << pid << '\n';
    return 0;
  }
  if (command.endsWith("ps -ef")) {
    out << "UID PID PPID C STIME TTY TIME CMD\n";
    if (pid)
      out << "2000 " << pid << " 1 0 00:00 ? 00:00:01 com.example.woodyqa\n";
    return 0;
  }
  if (command.contains("param get ")) {
    const auto name = command.section(' ', -1);
    const QJsonObject params{{"const.product.name", "HUAWEI QA Device"},
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
