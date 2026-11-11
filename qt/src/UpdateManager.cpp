#include "UpdateManager.h"
#include "Backend.h"
#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QProcess>
#include <QSysInfo>
#include <QTimer>

namespace {
QNetworkRequest request(const QUrl &url) {
  QNetworkRequest r(url);
  r.setRawHeader("User-Agent", "Woody/" + QCoreApplication::applicationVersion().toUtf8());
  r.setRawHeader("Accept", "application/vnd.github+json");
  r.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
  r.setMaximumRedirectsAllowed(5);
  r.setTransferTimeout(30000);
  return r;
}
QString arch() { return QSysInfo::buildCpuArchitecture() == "arm64" ? "arm64" : "x64"; }
QString platform() {
#ifdef Q_OS_MACOS
  return "mac";
#else
  return "win";
#endif
}
}
UpdateManager::UpdateManager(Backend *backend, QObject *parent, QNetworkAccessManager *network)
    : QObject(parent), mBackend(backend), mNetwork(network ? network : new QNetworkAccessManager(this)) {}
UpdateManager::~UpdateManager() { cancel(); }
bool UpdateManager::automatic() const { return mBackend->uiPreference("automaticUpdates", true).toBool(); }
void UpdateManager::setAutomatic(bool enabled) { mBackend->setUiPreference("automaticUpdates", enabled); emit changed(); }
QString UpdateManager::target() const {
#ifdef Q_OS_MACOS
  return QDir::cleanPath(QCoreApplication::applicationDirPath() + "/../..");
#else
  return QCoreApplication::applicationDirPath();
#endif
}
QString UpdateManager::helper() const {
#ifdef Q_OS_MACOS
  return QCoreApplication::applicationDirPath() + "/woody_updater";
#else
  return QCoreApplication::applicationDirPath() + "/woody_updater.exe";
#endif
}
bool UpdateManager::installed() const {
#ifdef Q_OS_WIN
  return QFileInfo::exists(target() + "/Uninstall.exe");
#else
  return false;
#endif
}
void UpdateManager::setState(const QString &state, const QString &message) { mState = state; mMessage = message; emit changed(); }
void UpdateManager::fail(const QString &message) { setState("error", message); }
void UpdateManager::startup() {
  QFile result(mBackend->profile() + "/update-result.txt");
  if (result.open(QIODevice::ReadOnly)) {
    const auto text = QString::fromUtf8(result.readAll());
    result.close(); result.remove();
    if (text.startsWith("ERROR:")) { fail(text.mid(6)); emit showRequested(); return; }
  }
  if (automatic()) check(false);
}
void UpdateManager::fetch(const QUrl &url, const std::function<void(QByteArray)> &done) {
  auto *reply = mNetwork->get(request(url)); mReply = reply;
  auto data = std::make_shared<QByteArray>();
  connect(reply, &QIODevice::readyRead, this, [this, reply, data] {
    data->append(reply->readAll());
    if (data->size() > 2*1024*1024) { fail("更新服务返回内容过大"); reply->abort(); }
  });
  connect(reply, &QNetworkReply::finished, this, [this, reply, data, done] {
    reply->deleteLater();
    if (mReply != reply) return;
    mReply = nullptr;
    if (reply->error() != QNetworkReply::NoError) {
      fail(reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() == 403
        ? "GitHub 暂时限制了请求，请稍后重试。" : "无法连接更新服务：" + reply->errorString());
      return;
    }
    data->append(reply->readAll());
    if (data->size() > 2*1024*1024) { fail("更新服务返回内容过大"); return; }
    try { done(*data); } catch (const std::exception &e) { fail(QString::fromUtf8(e.what())); }
  });
}
void UpdateManager::check(bool interactive) {
  if (interactive) emit showRequested();
  if (mReply || mExtract || mState == "installing" || mState == "ready") return;
  mRelease = {}; mProgress = 0;
  setState("checking", "正在检查 GitHub Release…");
  fetch(QUrl("https://api.github.com/repos/jerome-tan/woody-harmony/releases/latest"), [this, interactive](const QByteArray &body) {
    QJsonParseError error;
    const auto doc = QJsonDocument::fromJson(body, &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject()) { fail("更新服务返回的版本信息无效"); return; }
    mRelease = ReleaseUpdate::parse(doc.object(), QCoreApplication::applicationVersion(), platform(), arch(), installed());
    if (mRelease.version.isEmpty()) setState("current", "当前已是最新正式版本");
    else {
      setState("available", "发现新版本 " + mRelease.version);
      if (!interactive) emit showRequested();
    }
  });
}
void UpdateManager::download() {
  if (mState != "available") return;
  // A .app opened from a DMG, translocated app, or a read-only portable folder
  // must be moved/installed before it can be safely replaced in place.
  if (!QFileInfo::exists(helper()) || target().contains("/AppTranslocation/") || target().startsWith("/Volumes/")) {
    fail("请先将 Woody 安装或解压到可写目录，再使用自动更新。"); return;
  }
  QTemporaryDir writable(QFileInfo(target()).absolutePath() + "/.woody-write-check-XXXXXX");
  if (!writable.isValid()) { fail("当前应用目录不可写，请从 Release 手动安装新版。"); return; }
  mTemporary = std::make_unique<QTemporaryDir>(QDir::tempPath() + "/woody-update-XXXXXX.noindex");
  if (!mTemporary->isValid()) { fail("无法创建更新临时目录"); return; }
  mProgress = 0;
  setState("downloading", "正在获取校验信息…");
  fetch(mRelease.checksums, [this](const QByteArray &text) {
    mExpected = ReleaseUpdate::checksum(text, mRelease.assetName);
    downloadAsset();
  });
}
void UpdateManager::downloadAsset() {
  mFile.setFileName(mTemporary->filePath(mRelease.assetName));
  if (!mFile.open(QIODevice::WriteOnly)) { fail("无法写入下载文件"); return; }
  mHash.reset(); mReceived = 0;
  setState("downloading", "正在下载更新…");
  auto *reply = mNetwork->get(request(mRelease.asset)); mReply = reply;
  auto consume = [this, reply] {
    const auto bytes = reply->readAll();
    mReceived += bytes.size();
    if (mReceived > mRelease.size || mFile.write(bytes) != bytes.size()) {
      fail("更新包大小不符或磁盘空间不足"); reply->abort(); return;
    }
    mHash.addData(bytes);
    mProgress = double(mReceived) / mRelease.size;
    emit changed();
  };
  connect(reply, &QIODevice::readyRead, this, consume);
  connect(reply, &QNetworkReply::finished, this, [this, reply, consume] {
    reply->deleteLater();
    if (mReply != reply) return;
    if (reply->error() == QNetworkReply::NoError) consume();
    mReply = nullptr; mFile.close();
    if (mState == "error") return;
    if (reply->error() != QNetworkReply::NoError) { fail("下载失败：" + reply->errorString()); return; }
    if (mReceived != mRelease.size || mHash.result().toHex() != mExpected) {
      mFile.remove(); fail("更新包 SHA-256 校验失败，请重新检查并下载。"); return;
    }
    prepare();
  });
}
void UpdateManager::prepare() {
  if (installed()) {
    mPayload = mFile.fileName();
    setState("ready", "下载及校验完成，安装后将重新打开 Woody。"); return;
  }
  setState("preparing", "校验完成，正在解压更新…");
  const QString directory = mTemporary->filePath("extracted");
  QDir().mkpath(directory);
  auto *process = new QProcess(this); mExtract = process;
#ifdef Q_OS_MACOS
  process->setProgram("/usr/bin/ditto");
  process->setArguments({"-x", "-k", mFile.fileName(), directory});
  mPayload = directory + "/Woody.app";
#else
  // Pass paths through environment variables, never interpolate them into code.
  auto env = QProcessEnvironment::systemEnvironment();
  env.insert("WOODY_UPDATE_ZIP", mFile.fileName()); env.insert("WOODY_UPDATE_DEST", directory);
  process->setProcessEnvironment(env);
  process->setProgram(qEnvironmentVariable("SystemRoot", "C:/Windows") + "/System32/WindowsPowerShell/v1.0/powershell.exe");
  process->setArguments({"-NoProfile", "-NonInteractive", "-Command",
    "$ErrorActionPreference='Stop'; Expand-Archive -LiteralPath $env:WOODY_UPDATE_ZIP -DestinationPath $env:WOODY_UPDATE_DEST"});
  mPayload = directory + "/Woody";
#endif
  connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
    if (error == QProcess::FailedToStart) { mExtract = nullptr; process->deleteLater(); fail("无法启动更新包解压程序"); }
  });
  connect(process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
      [this, process](int code, QProcess::ExitStatus status) {
    process->deleteLater();
    if (mExtract != process) return;
    mExtract = nullptr;
    const QString executable = mPayload + (platform() == "mac" ? "/Contents/MacOS/Woody" : "/Woody.exe");
    if (code != 0 || status != QProcess::NormalExit || !QFileInfo::exists(executable)) {
      fail("更新包解压失败或缺少 Woody 程序"); return;
    }
    setState("ready", "下载及校验完成，重启后使用新版本。");
  });
  process->start();
}
void UpdateManager::cancel() {
  if (mState == "installing") return;
  if (mReply) { auto *r = mReply.data(); mReply = nullptr; r->abort(); }
  if (mExtract) { auto *p = mExtract.data(); mExtract = nullptr; p->kill(); p->waitForFinished(3000); }
  mFile.close(); mTemporary.reset(); mPayload.clear();
  if (mState == "downloading" || mState == "preparing" || mState == "ready")
    setState("available", "已取消下载，可重新下载更新。");
}
void UpdateManager::install() {
  if (mState != "ready" || !mTemporary) return;
  if (mBackend->sampling() || mBackend->snapshotting()) {
    mMessage = "请先结束内存监测、录制或快照采集，再安装更新。"; emit changed(); return;
  }
  const QString copy = mTemporary->filePath(QFileInfo(helper()).fileName());
  if (!QFile::copy(helper(), copy)) { fail("无法准备更新助手"); return; }
  QFile::setPermissions(copy, QFile::permissions(helper()));
  const QString result = mBackend->profile() + "/update-result.txt";
  QFile::remove(result);
  QProcess helperProcess;
  helperProcess.setProgram(copy);
  helperProcess.setArguments({QString::number(QCoreApplication::applicationPid()), target(), mPayload,
    installed() ? "installer" : "directory", result, mTemporary->path()});
  helperProcess.setWorkingDirectory(mTemporary->path());
  if (!helperProcess.startDetached()) { fail("无法启动更新助手"); return; }
  mTemporary->setAutoRemove(false); // Helper owns the payload until replacement finishes.
  setState("installing", "正在退出并安装更新…");
  mBackend->requestQuit();
}
void UpdateManager::openRelease() {
  QDesktopServices::openUrl(mRelease.page.isEmpty()
    ? QUrl("https://github.com/jerome-tan/woody-harmony/releases/latest") : mRelease.page);
}
