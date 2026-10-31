#pragma once
#include "HdcClient.h"
#include "Report.h"
#include <QElapsedTimer>
#include <QTimer>
#include <QUrl>
#include <functional>

class Backend : public QObject {
  Q_OBJECT
  Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)
  Q_PROPERTY(QVariantList apps READ apps NOTIFY appsChanged)
  Q_PROPERTY(QVariantMap deviceInfo READ deviceInfo NOTIFY deviceChanged)
  Q_PROPERTY(QString target READ target NOTIFY deviceChanged)
  Q_PROPERTY(QString hdcPath READ hdcPath NOTIFY settingsChanged)
  Q_PROPERTY(QString sessionsDir READ sessionsDir NOTIFY settingsChanged)
  Q_PROPERTY(QString defaultSessionsDir READ defaultSessionsDir CONSTANT)
  Q_PROPERTY(QVariantMap status READ status NOTIFY statusChanged)
  Q_PROPERTY(bool sampling READ sampling NOTIFY statusChanged)
  Q_PROPERTY(bool snapshotting READ snapshotting NOTIFY snapshottingChanged)
  Q_PROPERTY(bool discovering READ discovering NOTIFY devicesChanged)
  Q_PROPERTY(bool loadingApps READ loadingApps NOTIFY appsChanged)
  Q_PROPERTY(Report *live READ live CONSTANT)
  Q_PROPERTY(QVariantList records READ records NOTIFY recordsChanged)
  Q_PROPERTY(QString profile READ profile CONSTANT)
public:
  explicit Backend(QString profile = {}, QObject *parent = nullptr);
  ~Backend() override;
  QVariantList devices() const { return mDevices.toVariantList(); }
  QVariantList apps() const { return mApps.toVariantList(); }
  QVariantMap deviceInfo() const { return mDevice.toVariantMap(); }
  QString target() const { return mTarget; }
  QString hdcPath() const { return mHdc; }
  QString sessionsDir() const { return mSettings["sessionsDir"].toString(); }
  QString defaultSessionsDir() const;
  QString profile() const { return mProfile; }
  QVariantMap status() const { return mStatus.toVariantMap(); }
  bool sampling() const { return mActive; }
  bool snapshotting() const { return mSnapshotting; }
  bool discovering() const { return mDiscovering; }
  bool loadingApps() const { return mLoadingApps; }
  Report *live() const { return mLive; }
  QVariantList records() const { return mRecords.toVariantList(); }

  Q_INVOKABLE void initialize();
  Q_INVOKABLE void requestQuit();
  Q_INVOKABLE void prepareWindow(QObject *window);
  Q_INVOKABLE void refreshDevices();
  Q_INVOKABLE void selectDevice(const QString &target);
  Q_INVOKABLE void refreshApps();
  Q_INVOKABLE void refreshRecords();
  Q_INVOKABLE void saveHdcPath(const QString &value);
  Q_INVOKABLE void saveSessionsDir(const QString &value);
  Q_INVOKABLE void startSampling(const QVariantMap &config,
                                 const QString &bundle, const QString &label,
                                 bool persist, const QString &taskName);
  Q_INVOKABLE void stopSampling();
  Q_INVOKABLE void takeSnapshot(const QString &bundle, const QString &label,
                                const QString &taskName,
                                const QVariantMap &options);
  Q_INVOKABLE void openReport(const QString &directory);
  Q_INVOKABLE void openCompare(const QStringList &directories);
  Q_INVOKABLE void releaseReport(Report *report);
  Q_INVOKABLE void renameReport(const QString &directory, const QString &name);
  Q_INVOKABLE void deleteReports(const QStringList &directories);
  Q_INVOKABLE void revealPath(const QString &directory);
  Q_INVOKABLE QVariant uiPreference(const QString &key,
                                    const QVariant &fallback = {}) const;
  Q_INVOKABLE void setUiPreference(const QString &key, const QVariant &value);
  Q_INVOKABLE QString colorOf(const QString &name, int index = 0) const {
    return Report::color(name, index).name();
  }
  Q_INVOKABLE QString fromFileUrl(const QUrl &url) const;
  Q_INVOKABLE QUrl toFileUrl(const QString &file) const;
signals:
  void devicesChanged();
  void appsChanged();
  void deviceChanged();
  void settingsChanged();
  void recordsChanged();
  void statusChanged();
  void snapshottingChanged();
  void error(const QString &message);
  void notification(const QString &message);
  void reportOpened(Report *report);
  void compareOpened(const QVariantList &reports);
  void samplingStarted(bool persist);
  void samplingFinished(bool persist, const QString &directory,
                        bool autoStopped);
  void quitReady();

private:
  using Completion = std::function<void(const QJsonValue &, const QString &)>;
  void run(std::function<QJsonValue()> task, Completion done);
  void state(const QString &value, const QString &message = {},
             bool autoStopped = false);
  void collect();
  void finish(bool automatic = false);
  void saveSettings();
  QString root() const;
  HdcClient client() const;
  QString mProfile, mHdc, mTarget;
  QJsonObject mSettings, mPreferences, mDevice, mStatus;
  QJsonArray mDevices, mApps, mRecords;
  Report *mLive;
  QTimer mTimer;
  std::shared_ptr<std::atomic_bool> mQuit;
  std::shared_ptr<std::atomic_bool> mCancel;
  QJsonObject mConfig;
  QString mBundle, mLabel, mDirectory;
  HdcClient mSamplingClient;
  qint64 mPid = 0, mStartedAt = 0;
  int mFailures = 0;
  quint64 mDeviceGeneration = 0;
  bool mActive = false, mCollecting = false, mStarting = false,
       mStopping = false;
  bool mPersist = false, mSnapshotting = false, mDiscovering = false,
       mLoadingApps = false;
  bool mQuitting = false;
};
