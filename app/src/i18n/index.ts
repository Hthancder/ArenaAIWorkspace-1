/**
 * i18n setup (react-i18next).
 *
 * Source/default locale is English — every key's English value IS the
 * canonical UI string (consistent with "code/UI source in English";
 * other locales are translation layers, never a fork of the source).
 *
 * Resources are bundled (the app ships two small locales; no lazy
 * namespace loading needed) and split **one JSON file per namespace
 * per language** so independent areas can be translated in parallel
 * without touching a shared file. ALL namespaces are pre-registered
 * here, so adding strings to an area only edits that area's two JSON
 * files + its components — never this file.
 *
 * Language is detected from localStorage (`nf:lang`) then the browser,
 * and the chosen language is cached back to localStorage.
 */
import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'
import LanguageDetector from 'i18next-browser-languagedetector'

import enCommon from './locales/en/common.json'
import enToolbar from './locales/en/toolbar.json'
import enScreens from './locales/en/screens.json'
import enDialogs from './locales/en/dialogs.json'
import enInspector from './locales/en/inspector.json'
import enTimeline from './locales/en/timeline.json'
import enEditor from './locales/en/editor.json'

import jaCommon from './locales/ja/common.json'
import jaToolbar from './locales/ja/toolbar.json'
import jaScreens from './locales/ja/screens.json'
import jaDialogs from './locales/ja/dialogs.json'
import jaInspector from './locales/ja/inspector.json'
import jaTimeline from './locales/ja/timeline.json'
import jaEditor from './locales/ja/editor.json'

import viCommon from './locales/vi/common.json'
import viToolbar from './locales/vi/toolbar.json'
import viScreens from './locales/vi/screens.json'
import viDialogs from './locales/vi/dialogs.json'
import viInspector from './locales/vi/inspector.json'
import viTimeline from './locales/vi/timeline.json'
import viEditor from './locales/vi/editor.json'

// Vietnamese first: it is the product's default language (research
// rule 41.1.12) — the detector still picks up the browser language.
export const SUPPORTED_LANGUAGES = [
  { code: 'vi', label: 'Tiếng Việt' },
  { code: 'en', label: 'English' },
  { code: 'ja', label: '日本語' },
] as const

export type LanguageCode = (typeof SUPPORTED_LANGUAGES)[number]['code']

export const I18N_NAMESPACES = [
  'common',
  'toolbar',
  'screens',
  'dialogs',
  'inspector',
  'timeline',
  'editor',
] as const

const resources = {
  en: {
    common: enCommon,
    toolbar: enToolbar,
    screens: enScreens,
    dialogs: enDialogs,
    inspector: enInspector,
    timeline: enTimeline,
    editor: enEditor,
  },
  ja: {
    common: jaCommon,
    toolbar: jaToolbar,
    screens: jaScreens,
    dialogs: jaDialogs,
    inspector: jaInspector,
    timeline: jaTimeline,
    editor: jaEditor,
  },
  vi: {
    common: viCommon,
    toolbar: viToolbar,
    screens: viScreens,
    dialogs: viDialogs,
    inspector: viInspector,
    timeline: viTimeline,
    editor: viEditor,
  },
} as const

void i18n
  .use(LanguageDetector)
  .use(initReactI18next)
  .init({
    resources,
    fallbackLng: 'vi',
    supportedLngs: ['vi', 'en', 'ja'],
    // 'ja-JP' / 'en-US' collapse to the base language.
    load: 'languageOnly',
    nonExplicitSupportedLngs: true,
    ns: I18N_NAMESPACES,
    defaultNS: 'common',
    detection: {
      order: ['localStorage', 'navigator'],
      lookupLocalStorage: 'nf:lang',
      caches: ['localStorage'],
    },
    interpolation: {
      // React already escapes; double-escaping would mangle output.
      escapeValue: false,
    },
    react: {
      // Resources are bundled and synchronous, so there's nothing to
      // suspend on — keep it off to avoid needing a Suspense boundary.
      useSuspense: false,
    },
  })

export default i18n
