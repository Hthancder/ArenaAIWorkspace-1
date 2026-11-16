#!/bin/sh

cd $(dirname $0)/..

plutil -convert xml1 AIGate/AIGate/Info.plist
plutil -convert xml1 AIGate/AIGate/AIGate.entitlements
plutil -convert xml1 AIGate/AIGate/AIGatePrivileged.entitlements

plutil -convert xml1 WriteNowPrefs/Resources/Info.plist
plutil -convert xml1 WriteNowPrefs/layout/Library/PreferenceLoader/Preferences/WriteNowPrefs/Root.plist
