#include "UiAutomation.h"
#import <AppKit/AppKit.h>

namespace {
void visitMenu(NSMenu *menu, const QString &prefix, QStringList *entries,
               const QString &target, NSMenuItem **match) {
  for (NSMenuItem *item in menu.itemArray) {
    if (item.separatorItem)
      continue;
    const QString title = QString::fromNSString(item.title);
    const QString path = prefix.isEmpty() ? title : prefix + '/' + title;
    if (entries)
      entries->append(path);
    if (match && path == target)
      *match = item;
    if (item.submenu)
      visitMenu(item.submenu, path, entries, target, match);
  }
}
} // namespace

void UiAutomation::activateApp() {
  // Direct CLI launches on CI may make an NSWindow key while Finder still owns
  // the application menu. This is only used by the explicit QA harness.
  [NSApp activateIgnoringOtherApps:YES];
}

QStringList UiAutomation::nativeMenuEntries() const {
  QStringList entries;
  visitMenu(NSApp.mainMenu, {}, &entries, {}, nullptr);
  return entries;
}

bool UiAutomation::triggerNativeMenu(const QString &path) {
  NSMenuItem *item = nil;
  visitMenu(NSApp.mainMenu, {}, nullptr, path, &item);
  if (!item || !item.enabled || !item.action)
    return false;
  [item.menu performActionForItemAtIndex:[item.menu indexOfItem:item]];
  return true;
}
