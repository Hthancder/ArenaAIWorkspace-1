/**
 * Practice HUD — wait-mode progress, rhythm scoring totals, verdict
 * flashes, calibration flow and the end-of-session summary. Mounted
 * from Layout beside the TransportPill; all logic lives in
 * `usePracticeEngine` / `practiceStore`.
 *
 * Colors map to design tokens (spec/design-tokens.json): success =
 * perfect, warning = early/late, danger = miss/extra.
 */
import { useTranslation } from 'react-i18next'
import clsx from 'clsx'
import { Button } from '../ui/kit'
import { pitchLabel } from '../midi/noteName'
import { CALIBRATION_CLICKS, CALIBRATION_WARN_MS } from './calibration'
import { practiceController } from './usePracticeEngine'
import { usePractice } from './practiceStore'
import type { SessionResult, Verdict, WaitSummary } from './types'

const VERDICT_CLASS: Record<Verdict, string> = {
  perfect: 'text-success',
  good: 'text-ink',
  early: 'text-warning',
  late: 'text-warning',
  miss: 'text-danger',
  extra: 'text-danger',
}

function fmtMs(ms: number): string {
  const r = Math.round(ms)
  return `${r > 0 ? '+' : ''}${r}`
}

function VerdictFlash({ verdict, deltaMs }: { verdict: Verdict; deltaMs: number | null }) {
  const { t } = useTranslation('common')
  return (
    <div
      key={`${verdict}-${deltaMs ?? 0}`}
      className={clsx('nf-verdict-flash pointer-events-none text-center text-display', VERDICT_CLASS[verdict])}
    >
      {t(`practice.verdict.${verdict}`)}
      {deltaMs !== null && verdict !== 'extra' && (
        <span className="ml-2 text-body text-ink-muted">{fmtMs(deltaMs)} ms</span>
      )}
    </div>
  )
}

function RhythmPanel() {
  const { t } = useTranslation('common')
  const totals = usePractice((s) => s.totals)
  const combo = usePractice((s) => s.combo)
  const bestCombo = usePractice((s) => s.bestCombo)
  const done = totals.expected > 0 ? totals.perfect + totals.good + totals.early + totals.late : 0
  const pct = totals.expected > 0 ? Math.round((done / totals.expected) * 100) : 0
  return (
    <>
      <div className="flex items-center gap-3 text-body">
        <span className="text-ink">
          {t('practice.rhythm.accuracy')} <b className="tabular-nums">{pct}%</b>
          <span className="ml-1 text-ink-muted tabular-nums">
            {totals.perfect + totals.good + totals.early + totals.late}/{totals.expected}
          </span>
        </span>
        <span className="text-ink-muted">
          {t('practice.rhythm.combo')} <b className="tabular-nums text-ink">{combo}</b>
          <span className="ml-1 text-ink-faint tabular-nums">
            {t('practice.rhythm.best')} {bestCombo}
          </span>
        </span>
        <span className="flex gap-2 text-caption tabular-nums">
          <span className="text-success">✓{totals.perfect + totals.good}</span>
          <span className="text-warning">~{totals.early + totals.late}</span>
          <span className="text-danger">✗{totals.miss}</span>
          <span className="text-danger">+{totals.extra}</span>
        </span>
      </div>
    </>
  )
}

function WaitPanel() {
  const { t } = useTranslation('common')
  const wait = usePractice((s) => s.wait)
  const auto = usePractice((s) => s.waitAutoAdvanceMs)
  return (
    <div className="flex items-center gap-3 text-body">
      <span className="text-ink">
        {t('practice.wait.step', { current: wait.stepIndex + 1, total: wait.stepCount })}
      </span>
      <span className="text-ink-muted">
        {t('practice.wait.required')}{' '}
        <b className="text-ink">
          {wait.required
            .filter((m) => !wait.satisfied.includes(m))
            .map((m) => pitchLabel(m, 'letterOctave', 'sharp'))
            .join(' ')}
        </b>
      </span>
      {wait.wrong > 0 && <span className="text-danger">{t('practice.wait.wrong', { count: wait.wrong })}</span>}
      {auto > 0 && (
        <span className="text-ink-faint">{t('practice.wait.auto', { seconds: Math.round(auto / 1000) })}</span>
      )}
      <Button size="sm" onPress={() => practiceController.skipStep()}>
        {t('practice.wait.skip')}
      </Button>
    </div>
  )
}

function SummaryCard() {
  const { t } = useTranslation('common')
  const summary = usePractice((s) => s.summary)
  const setSummary = usePractice((s) => s.setSummary)
  if (!summary) return null
  const isRhythm = summary.mode === 'rhythm'
  const r = summary as SessionResult
  const w = summary as WaitSummary
  const correct = isRhythm ? r.totals.perfect + r.totals.good + r.totals.early + r.totals.late : 0
  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-scrim p-4">
      <div className="nf-glass w-full max-w-md rounded-round p-5 text-body">
        <h2 className="mb-3 text-display text-ink">
          {isRhythm ? t('practice.summary.titleRhythm') : t('practice.summary.titleWait')}
        </h2>
        {isRhythm ? (
          <>
            <dl className="grid grid-cols-2 gap-x-6 gap-y-1.5">
              <dt className="text-ink-muted">{t('practice.summary.expected')}</dt>
              <dd className="text-right tabular-nums">{r.totals.expected}</dd>
              <dt className="text-ink-muted">{t('practice.summary.accuracy')}</dt>
              <dd className="text-right tabular-nums">
                {r.totals.expected > 0 ? Math.round((correct / r.totals.expected) * 100) : 0}%
              </dd>
              <dt className="text-ink-muted">{t('practice.summary.perfect')}</dt>
              <dd className="text-right tabular-nums text-success">{r.totals.perfect}</dd>
              <dt className="text-ink-muted">{t('practice.summary.good')}</dt>
              <dd className="text-right tabular-nums">{r.totals.good}</dd>
              <dt className="text-ink-muted">{t('practice.summary.earlyLate')}</dt>
              <dd className="text-right tabular-nums text-warning">
                {r.totals.early + r.totals.late}
              </dd>
              <dt className="text-ink-muted">{t('practice.summary.miss')}</dt>
              <dd className="text-right tabular-nums text-danger">{r.totals.miss}</dd>
              <dt className="text-ink-muted">{t('practice.summary.extra')}</dt>
              <dd className="text-right tabular-nums text-danger">{r.totals.extra}</dd>
            </dl>
            {r.perBar.length > 0 && (
              <>
                <h3 className="mb-1 mt-4 text-heading text-ink-muted">{t('practice.summary.perBar')}</h3>
                <div className="max-h-40 overflow-y-auto rounded-round bg-fill-well p-2 text-caption">
                  {r.perBar.map((b) => (
                    <div key={b.bar} className="flex justify-between gap-3 py-0.5 tabular-nums">
                      <span className="text-ink-muted">{t('practice.summary.bar', { bar: b.bar })}</span>
                      <span className={b.correct < b.expected ? 'text-warning' : 'text-ink'}>
                        {b.correct}/{b.expected}
                      </span>
                      <span className="text-ink-faint">
                        {b.avgDeltaMs === 0 ? '—' : `${fmtMs(b.avgDeltaMs)} ms`}
                      </span>
                    </div>
                  ))}
                </div>
              </>
            )}
          </>
        ) : (
          <dl className="grid grid-cols-2 gap-x-6 gap-y-1.5">
            <dt className="text-ink-muted">{t('practice.summary.steps')}</dt>
            <dd className="text-right tabular-nums">{w.steps}</dd>
            <dt className="text-ink-muted">{t('practice.summary.firstTry')}</dt>
            <dd className="text-right tabular-nums text-success">{w.firstTry}</dd>
            <dt className="text-ink-muted">{t('practice.summary.retries')}</dt>
            <dd className="text-right tabular-nums">{w.retries}</dd>
            <dt className="text-ink-muted">{t('practice.summary.wrong')}</dt>
            <dd className="text-right tabular-nums text-danger">{w.wrong}</dd>
            <dt className="text-ink-muted">{t('practice.summary.skipped')}</dt>
            <dd className="text-right tabular-nums text-warning">{w.skipped}</dd>
            <dt className="text-ink-muted">{t('practice.summary.duration')}</dt>
            <dd className="text-right tabular-nums">
              {Math.round(summary.durationMs / 1000)}s
            </dd>
          </dl>
        )}
        <div className="mt-4 flex justify-end gap-2">
          <Button
            onPress={() => {
              setSummary(null)
              practiceController.reconcile()
            }}
          >
            {t('practice.retry')}
          </Button>
          <Button variant="primary" onPress={() => setSummary(null)}>
            {t('practice.close')}
          </Button>
        </div>
      </div>
    </div>
  )
}

function CalibrationPanel() {
  const { t } = useTranslation('common')
  const cal = usePractice((s) => s.calibration)
  const offset = usePractice((s) => s.scoringOffsetMs)
  if (cal.status === 'idle') return null
  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-scrim p-4">
      <div className="nf-glass w-full max-w-sm rounded-round p-5 text-center text-body">
        <h2 className="mb-2 text-display text-ink">{t('practice.calibration.title')}</h2>
        {cal.status === 'running' && (
          <>
            <p className="text-ink-muted">{t('practice.calibration.instruction')}</p>
            <p className="mt-3 text-display tabular-nums text-ink">
              {t('practice.calibration.beat', { beat: cal.beat, total: CALIBRATION_CLICKS })}
            </p>
            <div className="mt-4 flex justify-center">
              <Button onPress={() => practiceController.cancelCalibration()}>
                {t('practice.cancel')}
              </Button>
            </div>
          </>
        )}
        {cal.status === 'done' && (
          <>
            <p className="text-ink">
              {t('practice.calibration.result', { ms: fmtMs(offset) })}
            </p>
            {Math.abs(offset) > CALIBRATION_WARN_MS && (
              <p className="mt-2 text-caption text-warning">{t('practice.calibration.warn')}</p>
            )}
            <div className="mt-4 flex justify-center">
              <Button variant="primary" onPress={() => practiceController.cancelCalibration()}>
                {t('practice.close')}
              </Button>
            </div>
          </>
        )}
        {cal.status === 'failed' && (
          <>
            <p className="text-ink-muted">{t('practice.calibration.failed')}</p>
            <div className="mt-4 flex justify-center gap-2">
              <Button onPress={() => practiceController.startCalibration()}>
                {t('practice.calibration.again')}
              </Button>
              <Button variant="primary" onPress={() => practiceController.cancelCalibration()}>
                {t('practice.close')}
              </Button>
            </div>
          </>
        )}
      </div>
    </div>
  )
}

export function PracticeHud() {
  const { t } = useTranslation('common')
  const mode = usePractice((s) => s.mode)
  const lastVerdict = usePractice((s) => s.lastVerdict)
  const waitActive = usePractice((s) => s.wait.active)
  const sessionActive = usePractice((s) => s.sessionActive)
  const summary = usePractice((s) => s.summary)
  const cal = usePractice((s) => s.calibration)

  const showWait = mode === 'wait' && waitActive
  const showRhythm = mode === 'rhythm' && sessionActive
  if (!showWait && !showRhythm && !summary && cal.status === 'idle') return null

  return (
    <>
      {(showWait || showRhythm) && (
        <div
          role="status"
          aria-label={t('practice.title')}
          className="nf-glass fixed inset-x-0 top-3 z-30 mx-auto flex w-max max-w-[calc(100vw-32px)] flex-col items-center gap-1 rounded-round px-4 py-2"
        >
          {lastVerdict && mode === 'rhythm' && (
            <VerdictFlash
              key={`${lastVerdict.at}-${lastVerdict.verdict}`}
              verdict={lastVerdict.verdict}
              deltaMs={lastVerdict.deltaMs}
            />
          )}
          {showWait ? <WaitPanel /> : <RhythmPanel />}
          <Button
            size="sm"
            className="self-end text-ink-muted"
            onPress={() => practiceController.finishNow()}
          >
            {t('practice.finish')}
          </Button>
        </div>
      )}
      <SummaryCard />
      <CalibrationPanel />
    </>
  )
}
