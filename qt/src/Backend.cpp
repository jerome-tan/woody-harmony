#include "Backend.h"
#include "MemoryParser.h"
#include "PlatformWindow.h"
#include "ReportStore.h"
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QJsonDocument>
#include <QStandardPaths>
#include <QUrl>
#include <QUuid>
#include <QWindow>
#include <QtConcurrent>
#include <stdexcept>

namespace {
qint64 now() { return QDateTime::currentMSecsSinceEpoch(); }
QString failure(const std::exception &error) {
  return QString::fromUtf8(error.what());
}
QString flags(const QJsonObject &options) {
  QString result;
  if (options["showAshmem"].toBool())
    result += " --show-ashmem";
  if (options["showDmabuf"].toBool())
    result += " --show-dmabuf";
  if (options["showGpumem"].toBool())
    result += " --show-gpumem";
  return result;
}
QString uniqueDirectory(const QString &root, const QString &bundle,
                        bool snapshot) {
  const auto name = bundle + (snapshot ? "-snapshot-" : "-") +
                    QDateTime::currentDateTime().toString("yyyyMMdd-HHmmss");
  QString directory = QDir(root).filePath(name);
  for (int suffix = 2; QFileInfo::exists(directory); ++suffix)
    directory = QDir(root).filePath(name + '-' + QString::number(suffix));
  return directory;
}
struct JobResult {
  QJsonValue value;
  QString error;
};
} // namespace

Backend::Backend(QString profile, QObject *parent)
    : QObject(parent), mProfile(std::move(profile)), mLive(new Report(this)),
      mQuit(std::make_shared<std::atomic_bool>(false)) {
  if (mProfile.isEmpty())
    mProfile =
        QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
  if (!QFileInfo::exists(mProfile)) {
    const QDir parent(QFileInfo(mProfile).absolutePath());
    for (const auto &legacy :
         {QStringLiteral("啄木鸟"), QStringLiteral("鸿蒙内存采样工具"),
          QStringLiteral("HarmonyOS Memory Tools")}) {
      if (QFileInfo::exists(parent.filePath(legacy))) {
        QDir().rename(parent.filePath(legacy), mProfile);
        break;
      }
    }
  }
  QDir().mkpath(mProfile);
  try {
    mSettings = ReportStore::readObject(mProfile + "/settings.json");
  } catch (const std::exception &) {
  }
  try {
    mPreferences = ReportStore::readObject(mProfile + "/qt-ui.json");
  } catch (const std::exception &) {
  }
  mHdc = mSettings["hdcPath"].toString();
  if (sessionsDir().isEmpty() && !QFileInfo::exists(defaultSessionsDir())) {
    const QDir parent(QFileInfo(mProfile).absolutePath());
    for (const auto &legacy :
         {QStringLiteral("Woody"), QStringLiteral("啄木鸟"),
          QStringLiteral("鸿蒙内存采样工具"),
          QStringLiteral("HarmonyOS Memory Tools")}) {
      const auto old = parent.filePath(legacy + "/sessions");
      if (QFileInfo::exists(old)) {
        QDir().mkpath(QFileInfo(defaultSessionsDir()).absolutePath());
        QDir().rename(old, defaultSessionsDir());
        break;
      }
    }
  }
  mStatus = {{"state", "idle"}};
  mTimer.setSingleShot(true);
  connect(&mTimer, &QTimer::timeout, this, &Backend::collect);
  const auto checkQuit = [this] {
    if (mQuitting && !mActive && !mSnapshotting)
      emit quitReady();
  };
  connect(this, &Backend::statusChanged, this, checkQuit);
  connect(this, &Backend::snapshottingChanged, this, checkQuit);
}

void Backend::requestQuit() {
  mQuitting = true;
  if (mActive)
    stopSampling();
  if (!mActive && !mSnapshotting)
    emit quitReady();
}
void Backend::prepareWindow(QObject *object) {
  if (auto *window = qobject_cast<QWindow *>(object))
    configurePlatformWindow(window);
}

Backend::~Backend() {
  mQuit->store(true);
  if (mCancel)
    mCancel->store(true);
}

QString Backend::defaultSessionsDir() const {
  return QDir::homePath() + "/.woody/reports";
}
QString Backend::root() const {
  return sessionsDir().isEmpty() ? defaultSessionsDir() : sessionsDir();
}
HdcClient Backend::client() const {
  return {mHdc.isEmpty() ? QStringLiteral("hdc") : mHdc, mTarget, mQuit};
}
QString Backend::fromFileUrl(const QUrl &url) const {
  return url.toLocalFile();
}
QUrl Backend::toFileUrl(const QString &file) const {
  return QUrl::fromLocalFile(file);
}

void Backend::run(std::function<QJsonValue()> task, Completion done) {
  auto *watcher = new QFutureWatcher<JobResult>(this);
  connect(watcher, &QFutureWatcher<JobResult>::finished, this,
          [watcher, done = std::move(done)] {
            const auto result = watcher->result();
            watcher->deleteLater();
            done(result.value, result.error);
          });
  watcher->setFuture(QtConcurrent::run([task = std::move(task)] {
    try {
      return JobResult{task(), {}};
    } catch (const std::exception &error) {
      return JobResult{{}, failure(error)};
    }
  }));
}

void Backend::initialize() {
  run([configured = mHdc] { return HdcClient::detect(configured); },
      [this](const QJsonValue &value, const QString &problem) {
        if (problem.isEmpty()) {
          mHdc = value.toString();
          emit settingsChanged();
        }
        refreshDevices();
      });
  refreshRecords();
}

void Backend::refreshDevices() {
  if (mDiscovering)
    return;
  mDiscovering = true;
  emit devicesChanged();
  const auto hdc = client();
  run([hdc] { return hdc.devices(); },
      [this](const QJsonValue &value, const QString &problem) {
        mDiscovering = false;
        if (problem.isEmpty())
          mDevices = value.toArray();
        emit devicesChanged();
        // Discovery failures are shown in the empty device state, without
        // repeated modal interruptions.
        if (mTarget.isEmpty() && !mDevices.isEmpty())
          selectDevice(mDevices.first().toObject()["targetId"].toString());
        if (!problem.isEmpty())
          emit notification(problem);
      });
}

void Backend::selectDevice(const QString &target) {
  if (mActive || mSnapshotting) {
    emit error(QStringLiteral("请先结束当前采集再切换设备"));
    return;
  }
  mTarget = target;
  mDevice = {};
  mApps = {};
  const auto generation = ++mDeviceGeneration;
  emit deviceChanged();
  emit appsChanged();
  if (target.isEmpty())
    return;
  const auto hdc = client();
  run([hdc] { return hdc.deviceInfo(); },
      [this, generation](const QJsonValue &value, const QString &problem) {
        if (generation != mDeviceGeneration)
          return;
        if (problem.isEmpty()) {
          mDevice = value.toObject();
          emit deviceChanged();
        } else
          emit error(problem);
      });
  refreshApps();
}

void Backend::refreshApps() {
  if (mLoadingApps || mTarget.isEmpty())
    return;
  mLoadingApps = true;
  emit appsChanged();
  const auto hdc = client();
  const auto generation = mDeviceGeneration;
  run([hdc] { return hdc.apps(); },
      [this, generation](const QJsonValue &value, const QString &) {
        mLoadingApps = false;
        if (generation == mDeviceGeneration && value.isArray())
          mApps = value.toArray();
        emit appsChanged();
        if (generation != mDeviceGeneration)
          refreshApps();
      });
}

void Backend::refreshRecords() {
  run([directory = root()] { return ReportStore::list(directory); },
      [this](const QJsonValue &value, const QString &problem) {
        if (!problem.isEmpty()) {
          emit error(problem);
          return;
        }
        mRecords = value.toArray();
        emit recordsChanged();
      });
}

void Backend::saveSettings() {
  try {
    ReportStore::writeObject(mProfile + "/settings.json", mSettings);
  } catch (const std::exception &problem) {
    emit error(failure(problem));
  }
  emit settingsChanged();
}
void Backend::saveHdcPath(const QString &value) {
  if (mActive || mSnapshotting) {
    emit error(QStringLiteral("采集期间无法更改 hdc 路径"));
    return;
  }
  mSettings["hdcPath"] = value.trimmed();
  mHdc = value.trimmed();
  saveSettings();
  initialize();
}
void Backend::saveSessionsDir(const QString &value) {
  mSettings["sessionsDir"] = value.trimmed();
  saveSettings();
  refreshRecords();
}

void Backend::state(const QString &value, const QString &message,
                    bool automatic) {
  mStatus = {
      {"state", value}, {"message", message}, {"autoStopped", automatic}};
  emit statusChanged();
}

void Backend::startSampling(const QVariantMap &configuration,
                            const QString &bundle, const QString &label,
                            bool persist, const QString &taskName) {
  if (mActive || mSnapshotting) {
    emit error(QStringLiteral("已有采集任务进行中"));
    return;
  }
  if (mTarget.isEmpty()) {
    emit error(QStringLiteral("尚未选择目标设备"));
    return;
  }
  try {
    HdcClient::validateBundle(bundle);
  } catch (const std::exception &problem) {
    emit error(failure(problem));
    return;
  }
  mConfig = QJsonObject::fromVariantMap(configuration);
  mConfig["intervalMs"] = std::max(200, mConfig["intervalMs"].toInt(1000));
  mBundle = bundle;
  mLabel = label;
  mPersist = persist;
  mPid = 0;
  mFailures = 0;
  mActive = mStarting = true;
  mStopping = false;
  mDirectory.clear();
  mStartedAt = now();
  mCancel = std::make_shared<std::atomic_bool>(false);
  mSamplingClient = client();
  mSamplingClient.cancelled = mCancel;
  mLive->reset();
  state("starting", QStringLiteral("正在定位应用进程…"));
  const auto config = mConfig;
  const auto device = mDevice;
  const auto hdc = mSamplingClient;
  const auto output = root();
  run(
      [hdc, config, bundle, label, persist, taskName, device, output] {
        const auto pid = hdc.pid(bundle);
        if (hdc.cancelled->load())
          throw std::runtime_error("采集已取消");
        auto info = device;
        if (info.isEmpty())
          info = hdc.deviceInfo();
        const auto directory =
            persist ? uniqueDirectory(output, bundle, false) : QString();
        const auto started = now();
        QJsonObject meta{{"id", QFileInfo(directory).fileName()},
                         {"bundleName", bundle},
                         {"appLabel", label},
                         {"device", info},
                         {"config", config},
                         {"startedAt", started},
                         {"sampleCount", 0},
                         {"sessionDir", directory},
                         {"taskName", taskName.trimmed()}};
        if (hdc.cancelled->load())
          throw std::runtime_error("采集已取消");
        if (persist)
          ReportStore::writeObject(directory + "/meta.json", meta);
        return QJsonObject{{"pid", pid}, {"meta", meta}};
      },
      [this](const QJsonValue &value, const QString &problem) {
        mStarting = false;
        if (!problem.isEmpty()) {
          mActive = false;
          state(mStopping ? "idle" : "error", mStopping ? QString() : problem);
          if (!mStopping)
            emit error(problem);
          return;
        }
        const auto result = value.toObject();
        mPid = result["pid"].toInteger();
        mLive->metadata = result["meta"].toObject();
        mDirectory = mLive->metadata["sessionDir"].toString();
        emit mLive->changed();
        if (mStopping) {
          finish();
          return;
        }
        state("sampling",
              mPid
                  ? QStringLiteral("采样中，pid=%1").arg(mPid)
                  : QStringLiteral("应用未运行，记录全 0 数据，等待应用启动…"));
        emit samplingStarted(mPersist);
        collect();
      });
}

void Backend::collect() {
  if (!mActive || mCollecting || mStopping)
    return;
  const auto limit = mConfig["maxDurationMs"].toInteger();
  if (limit > 0 && now() - mStartedAt >= limit) {
    finish(true);
    return;
  }
  mCollecting = true;
  const auto tick = now();
  const auto hdc = mSamplingClient;
  const auto config = mConfig;
  const auto bundle = mBundle;
  const auto directory = mDirectory;
  const auto pid = mPid;
  const auto persist = mPersist;
  run(
      [hdc, config, bundle, directory, pid, persist] {
        auto current = pid ? pid : hdc.pid(bundle);
        QString raw;
        try {
          if (current)
            raw = hdc.shell("hidumper --mem " + QString::number(current) +
                                flags(config),
                            30000);
        } catch (const std::exception &problem) {
          if (hdc.cancelled->load())
            throw;
          const auto next = hdc.pid(bundle);
          return QJsonObject{{"nextPid", next},
                             {"collectError", failure(problem)},
                             {"samePid", next != 0 && next == current}};
        }
        const auto timestamp = now();
        auto sample = MemoryParser::processMemory(raw);
        sample["timestamp"] = timestamp;
        sample["pid"] =
            current ? QJsonValue(current) : QJsonValue(QJsonValue::Null);
        if (hdc.cancelled->load())
          throw std::runtime_error("采集已取消");
        if (persist) {
          if (!raw.isEmpty())
            ReportStore::writeText(
                directory + "/raw/" +
                    ReportStore::rawFileName(bundle, timestamp),
                raw.toUtf8());
          ReportStore::writeText(
              directory + "/samples.jsonl",
              QJsonDocument(sample).toJson(QJsonDocument::Compact) + '\n',
              true);
        }
        return QJsonObject{{"sample", sample}, {"nextPid", current}};
      },
      [this, tick](const QJsonValue &value, const QString &problem) {
        mCollecting = false;
        const auto result = value.toObject();
        if (result.contains("sample")) {
          mPid = result["nextPid"].toInteger();
          mFailures = 0;
          mLive->append(result["sample"].toObject());
          if (!mStopping)
            state("sampling",
                  mPid ? QStringLiteral("采样中，pid=%1").arg(mPid)
                       : QStringLiteral(
                             "应用未运行，记录全 0 数据，等待应用启动…"));
        } else if (result.contains("collectError")) {
          mPid = result["nextPid"].toInteger();
          mFailures = result["samePid"].toBool() ? mFailures + 1 : 0;
        } else if (!problem.isEmpty() && !mStopping)
          ++mFailures;
        if (mStopping) {
          finish();
          return;
        }
        if (mFailures >= 5) {
          emit error(QStringLiteral("采样连续失败：%1")
                         .arg(problem.isEmpty()
                                  ? result["collectError"].toString()
                                  : problem));
          finish();
          return;
        }
        if (mActive)
          mTimer.start(int(std::max<qint64>(
              0, mConfig["intervalMs"].toInt(1000) - (now() - tick))));
      });
}

void Backend::stopSampling() {
  if (!mActive || mStopping)
    return;
  mStopping = true;
  mTimer.stop();
  if (mCancel)
    mCancel->store(true);
  state("stopping", QStringLiteral("正在停止采样…"));
  if (!mCollecting && !mStarting)
    finish();
}

void Backend::finish(bool automatic) {
  mTimer.stop();
  mStopping = true;
  state("stopping", QStringLiteral("正在保存报告…"));
  auto meta = mLive->metadata;
  meta["endedAt"] = now();
  meta["sampleCount"] = mLive->count();
  mLive->metadata = meta;
  emit mLive->changed();
  const auto directory = mDirectory;
  const auto persist = mPersist;
  run(
      [meta, directory, persist] {
        if (persist && !directory.isEmpty())
          ReportStore::updateMetadata(directory,
                                      {{"endedAt", meta["endedAt"]},
                                       {"sampleCount", meta["sampleCount"]}});
        return QJsonValue();
      },
      [this, directory, persist, automatic](const QJsonValue &,
                                            const QString &problem) {
        mActive = mStopping = false;
        state(problem.isEmpty() ? "idle" : "error", problem, automatic);
        if (!problem.isEmpty())
          emit error(problem);
        refreshRecords();
        emit samplingFinished(persist, directory, automatic);
        if (!mQuitting && persist && !directory.isEmpty())
          openReport(directory);
      });
}

void Backend::takeSnapshot(const QString &bundle, const QString &label,
                           const QString &taskName,
                           const QVariantMap &options) {
  if (mSnapshotting || mActive) {
    emit error(QStringLiteral("已有采集任务进行中"));
    return;
  }
  if (mTarget.isEmpty()) {
    emit error(QStringLiteral("尚未选择目标设备"));
    return;
  }
  try {
    HdcClient::validateBundle(bundle);
  } catch (const std::exception &problem) {
    emit error(failure(problem));
    return;
  }
  mSnapshotting = true;
  emit snapshottingChanged();
  const auto hdc = client();
  const auto device = mDevice;
  const auto output = root();
  const auto opts = QJsonObject::fromVariantMap(options);
  run(
      [hdc, device, output, opts, bundle, label, taskName] {
        const auto pid = hdc.pid(bundle);
        if (!pid)
          throw std::runtime_error(
              QStringLiteral("应用 %1 未在运行，无法拍摄快照")
                  .arg(bundle)
                  .toStdString());
        const auto raw = hdc.shell(
            "hidumper --mem " + QString::number(pid) + flags(opts), 30000);
        const auto captured = now();
        auto snapshot = MemoryParser::processMemory(raw);
        snapshot["capturedAt"] = captured;
        snapshot["pid"] = pid;
        const auto details = MemoryParser::details(raw);
        if (opts["showAshmem"].toBool())
          snapshot["ashmemDetail"] = details["ashmem"];
        if (opts["showDmabuf"].toBool())
          snapshot["dmabufDetail"] = details["dmabuf"];
        if (opts["showGpumem"].toBool() && details["gpu"].isObject())
          snapshot["gpuDetail"] = details["gpu"];
        const auto directory = uniqueDirectory(output, bundle, true);
        const auto info = device.isEmpty() ? hdc.deviceInfo() : device;
        const QJsonObject meta{{"id", QFileInfo(directory).fileName()},
                               {"type", "snapshot"},
                               {"bundleName", bundle},
                               {"appLabel", label},
                               {"device", info},
                               {"config", QJsonObject{{"intervalMs", 0},
                                                      {"showAshmem", false},
                                                      {"showDmabuf", false},
                                                      {"showGpumem", false}}},
                               {"startedAt", captured},
                               {"endedAt", captured},
                               {"sampleCount", 1},
                               {"sessionDir", directory},
                               {"taskName", taskName.trimmed()}};
        ReportStore::writeObject(directory + "/meta.json", meta);
        ReportStore::writeObject(directory + "/snapshot.json", snapshot);
        const auto file =
            directory + '/' + ReportStore::rawFileName(bundle, captured);
        ReportStore::writeText(file, raw.toUtf8());
        QString warning;
        if (opts["includeSmaps"].toBool()) {
          try {
            const auto smaps = hdc.shell(
                "hidumper --mem-smaps " + QString::number(pid), 60000);
            ReportStore::writeText(file.left(file.size() - 4) + ".smaps.txt",
                                   smaps.toUtf8());
          } catch (const std::exception &problem) {
            warning = failure(problem);
          }
        }
        return QJsonObject{{"directory", directory}, {"warning", warning}};
      },
      [this](const QJsonValue &value, const QString &problem) {
        mSnapshotting = false;
        emit snapshottingChanged();
        if (!problem.isEmpty()) {
          emit error(problem);
          return;
        }
        const auto result = value.toObject();
        if (!result["warning"].toString().isEmpty())
          emit notification(QStringLiteral("快照已保存，smaps 未成功采集：") +
                            result["warning"].toString());
        refreshRecords();
        if (!mQuitting)
          openReport(result["directory"].toString());
      });
}

void Backend::openReport(const QString &directory) {
  run([directory] { return ReportStore::load(directory); },
      [this](const QJsonValue &value, const QString &problem) {
        if (!problem.isEmpty()) {
          emit error(problem);
          return;
        }
        const auto data = value.toObject();
        if (data["meta"].toObject()["type"] == "snapshot" &&
            !data["snapshot"].isObject()) {
          emit error(QStringLiteral("快照文件缺失或损坏"));
          return;
        }
        auto *report = new Report(this);
        report->load(data);
        emit reportOpened(report);
      });
}

void Backend::openCompare(const QStringList &directories) {
  if (directories.size() < 2 || directories.size() > 4) {
    emit error(QStringLiteral("请选择 2～4 份同类型报告"));
    return;
  }
  run(
      [directories] {
        QJsonArray result;
        QString kind;
        for (const auto &directory : directories) {
          const auto data = ReportStore::load(directory);
          const auto type = data["meta"].toObject()["type"].toString("trend");
          if (!kind.isEmpty() && kind != type)
            throw std::runtime_error("持续采样与内存快照不可互相对比");
          kind = type;
          if (type == "snapshot" && !data["snapshot"].isObject())
            throw std::runtime_error("快照文件缺失或损坏");
          result.append(data);
        }
        return result;
      },
      [this](const QJsonValue &value, const QString &problem) {
        if (!problem.isEmpty()) {
          emit error(problem);
          return;
        }
        QVariantList reports;
        const QStringList colors{"#1677ff", "#fa8c16", "#52c41a", "#722ed1"};
        for (const auto &data : value.toArray()) {
          auto *report = new Report(this);
          report->load(data.toObject());
          report->compareOrdinal = reports.size();
          report->compareColor = colors[reports.size()];
          reports.append(QVariant::fromValue(report));
        }
        emit compareOpened(reports);
      });
}

void Backend::releaseReport(Report *report) {
  if (report && report != mLive)
    report->deleteLater();
}
void Backend::renameReport(const QString &inputDirectory, const QString &name) {
  const auto directory = QDir(inputDirectory).absolutePath();
  if (name.trimmed().isEmpty()) {
    emit error(QStringLiteral("任务名称不能为空"));
    return;
  }
  // Update the in-memory active metadata before its eventual stop/save.
  if (directory == mDirectory && mActive)
    mLive->metadata["taskName"] = name.trimmed();
  run(
      [directory, name] {
        ReportStore::rename(directory, name);
        return QJsonValue();
      },
      [this, directory, name](const QJsonValue &, const QString &problem) {
        if (!problem.isEmpty()) {
          emit error(problem);
          return;
        }
        for (auto *report :
             findChildren<Report *>(QString(), Qt::FindDirectChildrenOnly)) {
          if (report->metadata["sessionDir"].toString() == directory) {
            report->metadata["taskName"] = name.trimmed();
            emit report->changed();
          }
        }
        refreshRecords();
      });
}

void Backend::deleteReports(const QStringList &directories) {
  const auto locked = mActive ? mDirectory : QString();
  run(
      [directories, locked] {
        for (const auto &directory : directories)
          ReportStore::remove(directory, locked);
        return QJsonValue();
      },
      [this](const QJsonValue &, const QString &problem) {
        if (!problem.isEmpty())
          emit error(problem);
        refreshRecords();
      });
}
void Backend::revealPath(const QString &directory) {
  QDesktopServices::openUrl(QUrl::fromLocalFile(directory));
}
QVariant Backend::uiPreference(const QString &key,
                               const QVariant &fallback) const {
  return mPreferences.contains(key) ? mPreferences[key].toVariant() : fallback;
}
void Backend::setUiPreference(const QString &key, const QVariant &value) {
  mPreferences[key] = QJsonValue::fromVariant(value);
  try {
    ReportStore::writeObject(mProfile + "/qt-ui.json", mPreferences);
  } catch (const std::exception &problem) {
    emit error(failure(problem));
  }
}
