import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import './i18n'
import { App } from './App'
import { bootSettingsPersistence } from './settingsPersist'

// Dev tools (Ctrl+Alt+D / ?dev=1): DEV-guarded dynamic import, so production bundles never contain src/dev/boot.
if (import.meta.env.DEV) void import('./dev/boot').then((m) => m.bootDev())

// Restore saved settings + start persisting changes BEFORE the first
// render — every consumer then reads the restored state as its initial
// state (see settingsPersist.ts).
bootSettingsPersistence()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
