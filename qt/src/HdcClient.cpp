#include "HdcClient.h"
#include "MemoryParser.h"
#include <QDir>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QProcess>
#include <QRegularExpression>
#include <QSet>
#include <QStandardPaths>
#include <algorithm>
#include <stdexcept>
#ifdef Q_OS_WIN
#include <windows.h>
#endif

namespace {
[[noreturn]] void fail(const QString &message) {
  throw std::runtime_error(message.toStdString());
}
QStringList subdirectories(const QString &path) {
  QStringList result;
  for (const auto &entry : QDir(path).entryInfoList(
           QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name | QDir::Reversed))
    result.append(entry.absoluteFilePath());
  return result;
}
} // namespace

QString HdcClient::detect(const QString &configured) {
#ifdef Q_OS_WIN
  const QString executable = "hdc.exe";
#else
  const QString executable = "hdc";
#endif
  if (!configured.isEmpty() && QFileInfo::exists(configured))
    return configured;
  const QString environment = qEnvironmentVariable("HDC_PATH");
  if (!environment.isEmpty() && QFileInfo::exists(environment))
    return environment;
  QStringList candidates;
  const auto home = QDir::homePath();
#ifdef Q_OS_WIN
  const QStringList roots{home + "/AppData/Local/OpenHarmony/Sdk",
                          home + "/AppData/Local/Huawei/Sdk"};
#else
  const QStringList roots{home + "/Library/OpenHarmony/Sdk",
                          home + "/Library/Huawei/Sdk"};
#endif
  for (const auto &root : roots) {
    for (const auto &version : subdirectories(root))
      candidates.append(version + "/toolchains/" + executable);
    candidates << root + "/toolchains/" + executable << root + '/' + executable;
  }
#ifdef Q_OS_MACOS
  for (const auto &application : subdirectories("/Applications")) {
    if (!application.contains("deveco-studio", Qt::CaseInsensitive))
      continue;
    for (const auto &sdk : subdirectories(application + "/Contents/sdk"))
      candidates.append(sdk + "/openharmony/toolchains/hdc");
  }
  for (const auto &base : {home, home + "/Tools"}) {
    for (const auto &directory : subdirectories(base)) {
      if (!QFileInfo(directory).fileName().contains("command-line-tools",
                                                    Qt::CaseInsensitive))
        continue;
      for (const auto &sdk : subdirectories(directory + "/sdk"))
        candidates.append(sdk + "/openharmony/toolchains/hdc");
    }
  }
  candidates << home + "/.local/bin/hdc"
             << "/usr/local/bin/hdc"
             << home + "/Library/OpenHarmony/Sdk/toolchains/hdc_std";
#elif defined(Q_OS_WIN)
  candidates << "C:/Program Files/Huawei/Sdk/toolchains/hdc.exe";
#endif
  for (const auto &candidate : candidates)
    if (QFileInfo::exists(candidate))
      return candidate;
  const auto onPath = QStandardPaths::findExecutable(executable);
  if (!onPath.isEmpty())
    return onPath;
#ifdef Q_OS_MACOS
  QProcess loginShell;
  loginShell.start(qEnvironmentVariable("SHELL", "/bin/zsh"),
                   {"-lc", "which hdc"});
  if (loginShell.waitForFinished(3000)) {
    auto lines = QString::fromUtf8(loginShell.readAllStandardOutput())
                     .trimmed()
                     .split('\n');
    std::reverse(lines.begin(), lines.end());
    for (auto line : lines) {
      line = line.trimmed();
      if (line.startsWith('/') && line.endsWith("/hdc") &&
          QFileInfo::exists(line))
        return line;
    }
  } else {
    loginShell.kill();
    loginShell.waitForFinished(1000);
  }
#endif
  return executable;
}

QString HdcClient::run(const QStringList &arguments, int timeoutMs,
                       bool useTarget) const {
  if (cancelled && cancelled->load())
    fail(QStringLiteral("采集已取消"));
  QProcess process;
#ifdef Q_OS_WIN
  process.setCreateProcessArgumentsModifier(
      [](QProcess::CreateProcessArguments *args) {
        args->flags |= CREATE_NO_WINDOW;
      });
#endif
  QStringList args;
  if (useTarget && !target.isEmpty())
    args << "-t" << target;
  args << arguments;
  QElapsedTimer timer;
  timer.start();
  process.start(binary, args);
  if (!process.waitForStarted(5000))
    fail(QStringLiteral(
             "未找到或无法启动 hdc（%1）。请在「设置」中指定完整路径。\n%2")
             .arg(binary, process.errorString()));
  QByteArray output, errors;
  while (process.state() != QProcess::NotRunning) {
    process.waitForFinished(100);
    output += process.readAllStandardOutput();
    errors += process.readAllStandardError();
    const bool stopped = cancelled && cancelled->load();
    if (stopped || timer.elapsed() >= timeoutMs ||
        output.size() > 32 * 1024 * 1024) {
      process.kill();
      process.waitForFinished(2000);
      fail(stopped ? QStringLiteral("采集已取消")
                   : QStringLiteral("hdc 执行超时或输出超过 32 MB：%1")
                         .arg(arguments.join(' ')));
    }
  }
  output += process.readAllStandardOutput();
  errors += process.readAllStandardError();
  if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0)
    fail(QStringLiteral("hdc %1 执行失败：%2")
             .arg(arguments.join(' '), QString::fromUtf8(errors).left(4096)));
  return QString::fromUtf8(output);
}

QString HdcClient::shell(const QString &command, int timeoutMs) const {
  return run({"shell", command}, timeoutMs);
}

QJsonArray HdcClient::devices() const {
  QJsonArray result;
  const auto output = run({"list targets"}, 20000, false);
  for (const auto &line : output.split('\n')) {
    const auto parts =
        line.trimmed().split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
    if (parts.isEmpty() || parts.first() == "[Empty]")
      continue;
    result.append(
        QJsonObject{{"targetId", parts.first()},
                    {"status", parts.size() > 1 ? parts[1] : "connected"}});
  }
  return result;
}

QString HdcClient::parameter(const QString &name) const {
  try {
    const auto value = shell("param get " + name, 10000).trimmed();
    return value.contains("fail!") ? QString() : value;
  } catch (const std::exception &) {
    return {};
  }
}

QJsonObject HdcClient::deviceInfo() const {
  auto market = parameter("const.product.name");
  auto model = parameter("const.product.model");
  if (model.isEmpty())
    model = parameter("const.ohos.model");
  auto distribution = parameter("const.product.os.dist.name");
  if (distribution.isEmpty())
    distribution = "HarmonyOS";
  const auto fullname = parameter("const.ohos.fullname");
  const auto distributionVersion = parameter("const.product.os.dist.version");
  const auto version = fullname.contains('-')
                           ? fullname.section('-', -1).trimmed()
                           : distributionVersion;
  auto api = parameter("const.ohos.apiversion");
  if (api.isEmpty())
    api = parameter("const.product.os.dist.apiversion");
  double ram = 0;
  try {
    ram = MemoryParser::procMeminfo(
              shell("cat /proc/meminfo", 10000))["ramTotalKb"]
              .toDouble();
  } catch (const std::exception &) {
  }
  if (ram == 0) {
    try {
      ram = MemoryParser::systemMemory(
                shell("hidumper --mem", 90000))["ramTotalKb"]
                .toDouble();
    } catch (const std::exception &) {
    }
  }
  QString resolution;
  try {
    const auto match =
        QRegularExpression("render resolution=(\\d+)\\s*x\\s*(\\d+)")
            .match(shell("hidumper -s RenderService -a screen", 15000));
    if (match.hasMatch())
      resolution =
          match.captured(1) + QStringLiteral(" × ") + match.captured(2);
  } catch (const std::exception &) {
  }
  return {{"targetId", target},
          {"marketName", market.isEmpty() ? QStringLiteral("未知") : market},
          {"model", model.isEmpty() ? QStringLiteral("未知") : model},
          {"softwareVersion",
           version.isEmpty() ? distribution : distribution + ' ' + version},
          {"apiVersion", api},
          {"serialNumber", target},
          {"ramTotalKb", ram},
          {"screenResolution", resolution}};
}

QJsonArray HdcClient::apps() const {
  const auto output = shell("bm dump -a", 40000);
  QList<QJsonObject> apps;
  QSet<QString> seen;
  const auto add = [&](const QString &bundle) {
    if (seen.contains(bundle))
      return;
    seen.insert(bundle);
    apps.append({{"bundleName", bundle},
                 {"label", bundle.section('.', -1)},
                 {"pid", QJsonValue::Null}});
  };
  static const QRegularExpression kv(
      "bundleName[\"']?\\s*[:=]\\s*[\"']?([A-Za-z0-9_.]+)[\"']?");
  auto matches = kv.globalMatch(output);
  while (matches.hasNext())
    add(matches.next().captured(1));
  const QRegularExpression name(
      "^\\s*([A-Za-z][A-Za-z0-9_]*(?:\\.[A-Za-z0-9_]+)+)\\s*$");
  for (const auto &line : output.split('\n')) {
    const auto match = name.match(line);
    if (match.hasMatch())
      add(match.captured(1));
  }
  try {
    const auto processes = shell("ps -ef", 15000);
    for (const auto &line : processes.split('\n')) {
      const auto tokens = line.trimmed().split(QRegularExpression("\\s+"));
      if (tokens.size() < 8)
        continue;
      bool ok;
      const auto id = tokens[1].toLongLong(&ok);
      if (!ok)
        continue;
      const auto bundle = tokens[7].section(':', 0, 0);
      for (auto &app : apps)
        if (app["bundleName"] == bundle && app["pid"].isNull())
          app["pid"] = id;
    }
  } catch (const std::exception &) {
  }
  std::stable_sort(apps.begin(), apps.end(), [](const auto &a, const auto &b) {
    return !a["pid"].isNull() && b["pid"].isNull();
  });
  QJsonArray result;
  for (const auto &app : apps)
    result.append(app);
  return result;
}

void HdcClient::validateBundle(const QString &bundle) {
  if (!QRegularExpression("^[A-Za-z][A-Za-z0-9_.]*$").match(bundle).hasMatch())
    fail(QStringLiteral("应用包名格式无效"));
}

qint64 HdcClient::pid(const QString &bundle) const {
  validateBundle(bundle);
  try {
    const auto match = QRegularExpression("^(\\d+)(?:\\s+\\d+)*$")
                           .match(shell("pidof " + bundle).trimmed());
    if (match.hasMatch())
      return match.captured(1).toLongLong();
  } catch (const std::exception &) {
  }
  try {
    for (const auto &line : shell("ps -ef").split('\n')) {
      const auto tokens = line.trimmed().split(QRegularExpression("\\s+"));
      if (tokens.size() >= 8 && tokens[7].section(':', 0, 0) == bundle) {
        bool ok;
        const auto value = tokens[1].toLongLong(&ok);
        if (ok)
          return value;
      }
    }
  } catch (const std::exception &) {
  }
  return 0;
}
