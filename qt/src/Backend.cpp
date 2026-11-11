#include "Backend.h"
#include "MemoryParser.h"
#include "PlatformWindow.h"
#include "ReportStore.h"
#include <QClipboard>
#include <QCursor>
#include <QScreen>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QEvent>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QStandardPaths>
#include <QUrl>
#include <QUuid>
#include <QWindow>
#include <QtConcurrent>
#include <algorithm>
#include <stdexcept>

namespace {
void centerNativeFrame(QWindow *window) {
  if (!window->screen()) return;
  const auto available = window->screen()->availableGeometry();
  const auto frame = window->frameGeometry().size();
  window->setFramePosition(available.topLeft() +
      QPoint(qMax(0, (available.width() - frame.width()) / 2),
             qMax(0, (available.height() - frame.height()) / 2)));
}

// Native frame margins can settle only when a window is first exposed (not
// merely created). Correct initial placement once, without moving later windows.
class InitialWindowPlacement final : public QObject {
public:
  explicit InitialWindowPlacement(QWindow *window) : QObject(window) {
    window->installEventFilter(this);
  }
protected:
  bool eventFilter(QObject *object, QEvent *event) override {
    auto *window = static_cast<QWindow *>(object);
    if (event->type() == QEvent::Expose && window->isExposed()) {
      window->removeEventFilter(this);
      QTimer::singleShot(0, window, [window] {
        if (window->isVisible() && window->visibility() == QWindow::Windowed)
          centerNativeFrame(window);
      });
      deleteLater();
    }
    return false;
  }
};

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
      mDeviceMonitor(this),
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
  mDeviceRetryTimer.setSingleShot(true);
  // Discovery must not queue behind slow device/app queries or a capture.
  mDiscoveryPool.setMaxThreadCount(1);
  mAppInfoPool.setMaxThreadCount(2);
  connect(&mDeviceRetryTimer, &QTimer::timeout, this,
          [this] { discoverDevices(false); });
  connect(&mDeviceMonitor, &DeviceMonitor::topologyChanged, this,
          [this](bool arrival) { beginDeviceRefresh(arrival ? 1 : -1); },
          Qt::QueuedConnection);
  connect(&mDeviceMonitor, &DeviceMonitor::resumed, this,
          [this] { beginDeviceRefresh(0); }, Qt::QueuedConnection);
  const auto checkQuit = [this] {
    if (mQuitting && !mActive && !mSnapshotting)
      emit quitReady();
  };
  connect(this, &Backend::statusChanged, this, checkQuit);
  connect(this, &Backend::snapshottingChanged, this, checkQuit);
}

bool Backend::toolPathExists(const QString &path) const {
  const QFileInfo file(path.trimmed());
  return file.isFile() && file.isExecutable();
}

void Backend::requestQuit() {
  mQuitting = true;
  cancelAppStatusQuery();
  mDeviceRetryActive = false;
  mDeviceRetryTimer.stop();
  mDeviceMonitor.stop();
  if (mActive)
    stopSampling();
  if (!mActive && !mSnapshotting)
    emit quitReady();
}
void Backend::prepareWindow(QObject *object) {
  if (auto *window = qobject_cast<QWindow *>(object))
    configurePlatformWindow(window);
}

void Backend::showWindowCentered(QObject *object, QObject *screenReference) {
  auto *window = qobject_cast<QWindow *>(object);
  if (!window)
    return;
  // Secondary windows use the launching window's display. The main window
  // uses the pointer's display. Apply placement only before the first show.
  auto *reference = qobject_cast<QWindow *>(screenReference);
  auto *screen = reference ? reference->screen()
                           : QGuiApplication::screenAt(QCursor::pos());
  if (!screen)
    screen = window->screen();
  const QSize initialSize(window->property("initialWidth").toInt(),
                          window->property("initialHeight").toInt());
  if (screen) {
    window->setScreen(screen);
    window->create();
    const auto available = screen->availableGeometry();
    const auto margins = window->frameMargins();
    const QSize maximum(available.width() - 48 - margins.left() - margins.right(),
                        available.height() - 48 - margins.top() - margins.bottom());
    // Explicit defaults avoid macOS titlebar expansion changing the first size.
    window->resize(initialSize.boundedTo(maximum).expandedTo(window->minimumSize()));
    centerNativeFrame(window);
  } else {
    window->resize(initialSize);
  }
  if (!window->isVisible()) new InitialWindowPlacement(window);
  const auto maximizedKey = window->property("maximizedPreferenceKey").toString();
  if (!maximizedKey.isEmpty() && uiPreference(maximizedKey, false).toBool())
    window->showMaximized();
  else
    window->show();
  window->raise();
  window->requestActivate();
}

void Backend::copyText(const QString &text) {
  QGuiApplication::clipboard()->setText(text);
}

Backend::~Backend() {
  cancelAppStatusQuery();
  mDeviceMonitor.stop();
  mQuit->store(true);
  if (mDeviceCancel)
    mDeviceCancel->store(true);
  if (mSnapshotCancel) mSnapshotCancel->store(true);
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

void Backend::run(std::function<QJsonValue()> task, Completion done,
                  QThreadPool *pool) {
  auto *watcher = new QFutureWatcher<JobResult>(this);
  connect(watcher, &QFutureWatcher<JobResult>::finished, this,
          [watcher, done = std::move(done)] {
            const auto result = watcher->result();
            watcher->deleteLater();
            done(result.value, result.error);
          });
  watcher->setFuture(QtConcurrent::run(pool ? pool : QThreadPool::globalInstance(),
                                     [task = std::move(task)] {
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
        if (mQuitting) return;
        // GUI-less tests drive the same signals explicitly, without host USB events.
        if (qobject_cast<QGuiApplication *>(QCoreApplication::instance())) {
          QString monitorError;
          if (!mDeviceMonitor.start(&monitorError))
            emit notification(QStringLiteral("设备事件监听不可用，请手动刷新设备。%1")
                                  .arg(monitorError));
        }
        beginDeviceRefresh(0);
      });
  refreshRecords();
}

void Backend::refreshDevices() {
  // Explicit refresh performs one query; never starts a periodic fallback.
  mDeviceRetryActive = false;
  mDeviceRetryTimer.stop();
  ++mDiscoveryRevision;
  discoverDevices(true);
}

void Backend::beginDeviceRefresh(int goal) {
  if (mQuitting) return;
  ++mDiscoveryRevision;
  mDeviceRetryGoal = goal;
  mDeviceRetryBaseline.clear();
  for (const auto &entry : mDevices)
    mDeviceRetryBaseline.insert(entry.toObject()["targetId"].toString());
  mDeviceRetryIndex = 0;
  mDeviceRetryClock.start();
  mDeviceRetryActive = true;
  // Coalesce the multiple interface notifications emitted by a composite USB device.
  mDeviceRetryTimer.start(100);
}

void Backend::continueDeviceRefresh(const QJsonArray &devices, bool success) {
  if (!mDeviceRetryActive || mQuitting) return;
  QSet<QString> current;
  for (const auto &entry : devices)
    current.insert(entry.toObject()["targetId"].toString());
  const bool settled = success && (mDeviceRetryGoal > 0
      ? !(current - mDeviceRetryBaseline).isEmpty()
      : mDeviceRetryGoal < 0 ? !(mDeviceRetryBaseline - current).isEmpty()
                            : !current.isEmpty());
  // Bounded settling retries only, at most ten seconds after an event.
  static constexpr int delays[] = {250, 500, 1000, 2000, 3000, 3000};
  if (settled || mDeviceRetryIndex >= int(std::size(delays)) ||
      mDeviceRetryClock.elapsed() + delays[mDeviceRetryIndex] > 10000) {
    mDeviceRetryActive = false;
    mDeviceRetryTimer.stop();
    return;
  }
  mDeviceRetryTimer.start(delays[mDeviceRetryIndex++]);
}

void Backend::discoverDevices(bool manual) {
  if (mQuitting)
    return;
  // Only explicit refreshes affect the button. Requests received in flight
  // are serialized into a fresh query instead of starting concurrent processes.
  if (manual && !mDiscovering) {
    mDiscovering = true;
    emit discoveringChanged();
  }
  if (mDiscoveryInFlight) {
    mDiscoveryRequested = true;
    return;
  }
  mDiscoveryRequested = false;
  mDiscoveryInFlight = true;
  const auto revision = mDiscoveryRevision;
  const auto hdc = client();
  run([hdc] {
        const auto devices = hdc.devices();
        QJsonArray ready;
        QString readinessError;
        for (const auto &entry : devices) {
          auto probe = hdc;
          probe.target = entry.toObject()["targetId"].toString();
          try {
            // Enumeration alone does not mean the HDC communication channel is ready.
            if (probe.shell("echo woody-device-ready", 3000).trimmed() == "woody-device-ready")
              ready.append(probe.target);
            else
              readinessError = QStringLiteral("设备通信通道尚未就绪，请稍后刷新设备。");
          } catch (const std::exception &e) {
            readinessError = QString::fromUtf8(e.what());
          }
        }
        return QJsonObject{{"devices", devices}, {"ready", ready},
                           {"readinessError", readinessError}};
      },
      [this, binary = hdc.binary, revision](const QJsonValue &value, const QString &problem) {
        mDiscoveryInFlight = false;
        if (mQuitting)
          return;
        if (binary != client().binary || revision != mDiscoveryRevision ||
            mDiscoveryRequested) {
          // An event received during a query must not be lost or apply stale results.
          mDeviceRetryTimer.stop();
          discoverDevices(mDiscovering);
          return;
        }
        const bool manual = mDiscovering;
        if (mDiscovering) {
          mDiscovering = false;
          emit discoveringChanged();
        }
        const auto result = value.toObject();
        const auto devices = problem.isEmpty() ? result["devices"].toArray() : QJsonArray{};
        const auto ready = result["ready"].toArray();
        const auto readinessError = result["readinessError"].toString();
        const bool changed = mDevices != devices;
        mDevices = devices;
        const bool recordingDevicePresent = std::any_of(
            mDevices.cbegin(), mDevices.cend(), [this](const auto &entry) {
              return entry.toObject()["targetId"].toString() == mSamplingClient.target;
            });
        if (mActive && mPersist && !mStopping && !recordingDevicePresent) {
          mDisconnectedAt = now();
          stopSampling();
        }
        const bool targetPresent = std::any_of(
            mDevices.cbegin(), mDevices.cend(), [this](const auto &entry) {
              return entry.toObject()["targetId"].toString() == mTarget;
            });
        if (!mTarget.isEmpty() && !targetPresent)
          clearDevice();
        if (changed)
          emit devicesChanged();
        // Discovery failures are shown in the empty device state, without
        // repeated modal interruptions.
        if (!mActive && !mSnapshotting) {
          if (!mTarget.isEmpty() && !ready.contains(mTarget))
            clearDevice();
          if (mTarget.isEmpty() && !ready.isEmpty())
            selectDevice(ready.first().toString());
          else if (!mTarget.isEmpty() && (manual || mDevice.isEmpty()))
            selectDevice(mTarget);
        }
        if (manual && (!problem.isEmpty() || !readinessError.isEmpty()))
          emit notification(problem.isEmpty() ? readinessError : problem);
        continueDeviceRefresh(devices, problem.isEmpty() && readinessError.isEmpty());
      }, &mDiscoveryPool);
}

void Backend::clearDevice() {
  cancelAppStatusQuery();
  // Invalidate pending queries even if the same device reconnects shortly.
  ++mDeviceGeneration;
  mAppDebugCache.clear();
  mAppDebugPending.clear();
  if (mDeviceCancel)
    mDeviceCancel->store(true);
  mTarget.clear();
  mDevice = {};
  mApps = {};
  mSelectedBundle.clear();
  mLoadingApps = false;
  emit loadingAppsChanged();
  // Keep selectedApps in settings: disconnection is not uninstallation.
  emit deviceChanged();
  emit selectedBundleChanged();
  emit appsChanged();
}

void Backend::selectDevice(const QString &target) {
  if (mActive || mSnapshotting) {
    emit error(QStringLiteral("请先结束当前采集再切换设备"));
    return;
  }
  // Explicitly selecting/refreshing the same device must also reload metadata.
  // Otherwise a transient handshake failure leaves the old device name cached.
  cancelAppStatusQuery();
  mTarget = target;
  mDevice = {};
  mApps = {};
  mSelectedBundle = mSettings["selectedApps"].toObject()[target].toString();
  const auto generation = ++mDeviceGeneration;
  mAppDebugCache.clear();
  mAppDebugPending.clear();
  if (mDeviceCancel)
    mDeviceCancel->store(true);
  mDeviceCancel = std::make_shared<std::atomic_bool>(false);
  mLoadingApps = false;
  emit loadingAppsChanged();
  emit deviceChanged();
  emit selectedBundleChanged();
  emit appsChanged();
  if (target.isEmpty())
    return;
  auto hdc = client();
  hdc.cancelled = mDeviceCancel;
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

void Backend::rememberAppSelection(const QString &bundle) {
  auto selections = mSettings["selectedApps"].toObject();
  const bool changed = mSelectedBundle != bundle;
  if (changed)
    cancelAppStatusQuery();
  mSelectedBundle = bundle;
  if (!selections.contains(mTarget) || selections[mTarget].toString() != bundle) {
    // An explicit empty choice prevents silently switching to another app
    // after the remembered application has been uninstalled.
    selections[mTarget] = bundle;
    mSettings["selectedApps"] = selections;
    saveSettings();
  }
  if (changed)
    emit selectedBundleChanged();
}

void Backend::selectApp(const QString &bundle) {
  if (mActive || mSnapshotting || mTarget.isEmpty())
    return;
  if (!bundle.isEmpty() &&
      !std::any_of(mApps.cbegin(), mApps.cend(), [&](const auto &entry) {
        return entry.toObject()["bundleName"].toString() == bundle;
      })) {
    emit error(QStringLiteral("目标应用已不在列表中，请刷新后重新选择"));
    return;
  }
  rememberAppSelection(bundle);
}

void Backend::cancelAppStatusQuery() {
  if (mAppStatusCancel)
    mAppStatusCancel->store(true);
  ++mAppStatusRevision;
  mAppStatusPending = false;
}

void Backend::refreshSelectedAppStatus() {
  if (mQuitting || mActive || mSnapshotting || mLoadingApps ||
      mAppStatusPending || mTarget.isEmpty() || mSelectedBundle.isEmpty())
    return;
  const auto bundle = mSelectedBundle;
  const auto generation = mDeviceGeneration;
  const auto revision = ++mAppStatusRevision;
  mAppStatusPending = true;
  mAppStatusCancel = std::make_shared<std::atomic_bool>(false);
  auto hdc = client();
  hdc.cancelled = mAppStatusCancel;
  run([hdc, bundle] { return QJsonValue(hdc.queryPid(bundle)); },
      [this, bundle, generation, revision](const QJsonValue &value, const QString &problem) {
        if (revision != mAppStatusRevision)
          return;
        mAppStatusPending = false;
        if (generation != mDeviceGeneration || bundle != mSelectedBundle)
          return;
        for (qsizetype i = 0; i < mApps.size(); ++i) {
          auto app = mApps[i].toObject();
          if (app["bundleName"].toString() != bundle)
            continue;
          const auto previous = app;
          app["pid"] = problem.isEmpty() ? value : QJsonValue(QJsonValue::Null);
          app["statusKnown"] = problem.isEmpty();
          if (app != previous) {
            mApps[i] = app;
            emit appsChanged();
          }
          break;
        }
      }, &mAppInfoPool);
}

void Backend::refreshApps() {
  if (mLoadingApps || mTarget.isEmpty())
    return;
  // The full refresh supersedes any older selected-app response.
  cancelAppStatusQuery();
  mLoadingApps = true;
  emit loadingAppsChanged();
  auto hdc = client();
  hdc.cancelled = mDeviceCancel;
  const auto generation = mDeviceGeneration;
  run([hdc] { return hdc.apps(); },
      [this, generation](const QJsonValue &value, const QString &problem) {
        if (generation != mDeviceGeneration)
          return;
        mLoadingApps = false;
        emit loadingAppsChanged();
        const auto previousApps = mApps;
        if (problem.isEmpty() && value.isArray()) {
          mApps = value.toArray();
          QSet<QString> installed;
          for (qsizetype i = 0; i < mApps.size(); ++i) {
            auto app = mApps[i].toObject();
            const auto bundle = app["bundleName"].toString();
            installed.insert(bundle);
            app["debug"] = mAppDebugCache.value(bundle).value("debug");
            mApps[i] = app;
          }
          for (auto it = mAppDebugCache.begin(); it != mAppDebugCache.end();) {
            if (!installed.contains(it.key()))
              it = mAppDebugCache.erase(it);
            else
              ++it;
          }
          const bool selectedIsInstalled =
              std::any_of(mApps.cbegin(), mApps.cend(), [&](const auto &entry) {
                return entry.toObject()["bundleName"].toString() == mSelectedBundle;
              });
          if (!mSelectedBundle.isEmpty() && !selectedIsInstalled) {
            rememberAppSelection({});
          } else if (!mSettings["selectedApps"].toObject().contains(mTarget)) {
            // Preserve the initial running-app default only for a device
            // without a saved choice. Process exits never change that choice.
            for (const auto &entry : mApps) {
              const auto app = entry.toObject();
              if (app["pid"].toInteger() > 0) {
                rememberAppSelection(app["bundleName"].toString());
                break;
              }
            }
          }
        }
        if (mApps != previousApps)
          emit appsChanged();
      });
}

void Backend::requestAppDebugMode(const QString &bundle) {
  if (mTarget.isEmpty() || mAppDebugPending.contains(bundle) ||
      !std::any_of(mApps.cbegin(), mApps.cend(), [&](const auto &entry) {
        return entry.toObject()["bundleName"].toString() == bundle;
      }))
    return;
  const auto cached = mAppDebugCache.value(bundle);
  if (!cached.isEmpty() && now() - cached["checkedAt"].toInteger() < 30000)
    return;
  mAppDebugPending.insert(bundle);
  auto hdc = client();
  hdc.cancelled = mDeviceCancel;
  const auto generation = mDeviceGeneration;
  run([hdc, bundle] { return hdc.appDebugMode(bundle); },
      [this, bundle, generation](const QJsonValue &value, const QString &) {
        if (generation != mDeviceGeneration)
          return;
        mAppDebugPending.remove(bundle);
        const auto debug = value.isBool() ? value : QJsonValue(QJsonValue::Null);
        for (qsizetype i = 0; i < mApps.size(); ++i) {
          auto app = mApps[i].toObject();
          if (app["bundleName"].toString() != bundle)
            continue;
          mAppDebugCache.insert(bundle, {{"debug", debug}, {"checkedAt", now()}});
          if (app.value("debug") != debug) {
            app["debug"] = debug;
            mApps[i] = app;
            emit appsChanged();
          }
          break;
        }
      }, &mAppInfoPool);
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
  mDisconnectedAt = 0;
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
                         {"appDebug", hdc.appDebugMode(bundle)},
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
          const bool stopped = mStopping;
          mActive = false;
          mStopping = false;
          state(stopped ? "idle" : "error", stopped ? QString() : problem);
          if (mDisconnectedAt)
            emit notification(QStringLiteral("设备连接已中断，录制已结束，尚未产生可保存的数据。重连后需手动开始录制。"));
          else if (!stopped)
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
                  ? (mPersist ? QStringLiteral("录制中，pid=%1") : QStringLiteral("监测中，pid=%1")).arg(mPid)
                  : QStringLiteral("等待应用启动"));
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
                  mPid ? (mPersist ? QStringLiteral("录制中，pid=%1") : QStringLiteral("监测中，pid=%1")).arg(mPid)
                       : QStringLiteral(
                             "等待应用启动"));
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
  state("stopping", mPersist ? QStringLiteral("正在结束录制…") : QStringLiteral("正在结束监测…"));
  if (!mCollecting && !mStarting)
    finish();
}

void Backend::finish(bool automatic) {
  mTimer.stop();
  mStopping = true;
  state("stopping", QStringLiteral("正在保存报告…"));
  auto meta = mLive->metadata;
  meta["endedAt"] = mDisconnectedAt ? mDisconnectedAt : now();
  meta["sampleCount"] = mLive->count();
  if (mDisconnectedAt)
    meta["stopReason"] = "device-disconnected";
  mLive->metadata = meta;
  emit mLive->changed();
  const auto directory = mDirectory;
  const auto persist = mPersist;
  run(
      [meta, directory, persist] {
        if (persist && !directory.isEmpty()) {
          QJsonObject update{{"endedAt", meta["endedAt"]},
                             {"sampleCount", meta["sampleCount"]}};
          if (meta.contains("stopReason"))
            update["stopReason"] = meta["stopReason"];
          ReportStore::updateMetadata(directory, update);
        }
        return QJsonValue();
      },
      [this, directory, persist, automatic](const QJsonValue &,
                                            const QString &problem) {
        mActive = mStopping = false;
        state(problem.isEmpty() ? "idle" : "error", problem, automatic);
        if (!problem.isEmpty())
          emit error(mDisconnectedAt
                         ? QStringLiteral("设备连接已中断，录制已结束，但报告保存失败：%1").arg(problem)
                         : problem);
        else if (mDisconnectedAt)
          emit notification(QStringLiteral("设备连接已中断，录制已结束，已有数据已保存。重连后需手动开始录制。"));
        refreshRecords();
        emit samplingFinished(persist, directory, automatic);
        if (!mQuitting && persist && !directory.isEmpty())
          openReport(directory);
      });
}

void Backend::cancelSnapshot() {
  if (mSnapshotting && mSnapshotCancel) mSnapshotCancel->store(true);
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
  auto hdc = client();
  mSnapshotCancel = std::make_shared<std::atomic_bool>(false);
  hdc.cancelled = mSnapshotCancel;
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
        QString warning, smaps;
        if (opts["includeSmaps"].toBool()) {
          try {
            smaps = hdc.shell(
                "hidumper --mem-smaps " + QString::number(pid), 60000);

          } catch (const std::exception &problem) {
            if (hdc.cancelled->load()) throw;
            warning = failure(problem);
          }
        }
        if (hdc.cancelled->load()) throw std::runtime_error("采集已取消");
        const auto directory = uniqueDirectory(output, bundle, true);
        const auto info = device.isEmpty() ? hdc.deviceInfo() : device;
        const QJsonObject meta{{"id", QFileInfo(directory).fileName()},
                               {"type", "snapshot"},
                               {"bundleName", bundle},
                               {"appLabel", label},
                               {"appDebug", hdc.appDebugMode(bundle)},
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
        if (!smaps.isEmpty())
          ReportStore::writeText(file.left(file.size() - 4) + ".smaps.txt", smaps.toUtf8());
        return QJsonObject{{"directory", directory}, {"warning", warning}};
      },
      [this](const QJsonValue &value, const QString &problem) {
        const bool cancelled = mSnapshotCancel && mSnapshotCancel->load();
        mSnapshotCancel.reset();
        if (cancelled) {
          const auto directory = value.toObject()["directory"].toString();
          if (!directory.isEmpty()) QDir(directory).removeRecursively();
        }
        mSnapshotting = false;
        emit snapshottingChanged();
        if (cancelled) {
          emit notification(QStringLiteral("已取消采集"));
          return;
        }
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
            throw std::runtime_error("内存录制与内存快照不可互相对比");
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
        for (const auto &data : value.toArray()) {
          auto *report = new Report(this);
          report->load(data.toObject());
          report->compareOrdinal = reports.size();
          report->compareColor = Report::comparisonColor(reports.size()).name();
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
void Backend::revealFileDirectory(const QString &filePath) {
  const QFileInfo file(filePath.trimmed());
  if (!file.isFile()) {
    emit error(QStringLiteral("文件不存在，无法打开所在目录"));
    return;
  }
  if (!QDesktopServices::openUrl(QUrl::fromLocalFile(file.absolutePath())))
    emit error(QStringLiteral("无法打开文件所在目录"));
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
