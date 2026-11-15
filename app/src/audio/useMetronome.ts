import { useEffect } from 'react'
import * as Tone from 'tone'
import { metronome } from './metronome'
import { useStore } from '../store'

/**
 * Binds the standalone metronome to Settings: `metronomeEnabled` starts /
 * stops it, tempo and meter changes apply live. Mounted once from Layout.
 *
 * Toggling always comes from a user gesture (the Inspector switch or the
 * Ctrl/Cmd+M shortcut), which is also what unlocks the AudioContext —
 * if the context is still suspended the metronome's clicks simply stay
 * silent until the first gesture (same model as the rest of the app).
 */
export function useMetronome() {
  useEffect(() => {
    const apply = () => {
      const s = useStore.getState().settings
      if (s.metronomeEnabled) {
        if (Tone.getContext().state !== 'running') {
          void Tone.start().catch(() => {})
        }
        if (metronome.running) {
          metronome.update(s.metronomeBpm, s.metronomeBeatsPerBar)
        } else {
          metronome.start(s.metronomeBpm, s.metronomeBeatsPerBar)
        }
      } else {
        metronome.stop()
      }
    }
    apply()
    return useStore.subscribe((st, prev) => {
      if (
        st.settings.metronomeEnabled !== prev.settings.metronomeEnabled ||
        st.settings.metronomeBpm !== prev.settings.metronomeBpm ||
        st.settings.metronomeBeatsPerBar !== prev.settings.metronomeBeatsPerBar
      ) {
        apply()
      }
    })
  }, [])
}
