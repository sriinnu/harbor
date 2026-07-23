import { invoke } from '@tauri-apps/api/core'
import { useEffect, useState } from 'react'
import './styles.css'

type RuntimeInfo = { platform: string; version: string }

export default function App() {
  const [runtime, setRuntime] = useState<RuntimeInfo | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    Promise.all([
      invoke<string>('get_platform'),
      invoke<string>('get_version'),
    ])
      .then(([platform, version]) => setRuntime({ platform, version }))
      .catch(() => setError('The Harbor Linux runtime did not respond.'))
  }, [])

  return (
    <main>
      <p className="eyebrow">DEVELOPER PREVIEW</p>
      <h1>Harbor for Linux</h1>
      <p className="lead">
        The Linux surface is now a runnable Tauri shell. Repository data,
        secure authentication, tray behavior, and release packaging are the
        next implementation milestones.
      </p>

      <section>
        <h2>Runtime</h2>
        {runtime ? (
          <dl>
            <div><dt>Platform</dt><dd>{runtime.platform}</dd></div>
            <div><dt>Version</dt><dd>{runtime.version}</dd></div>
          </dl>
        ) : (
          <p>{error ?? 'Connecting to the native runtime…'}</p>
        )}
      </section>

      <section>
        <h2>Not yet a release</h2>
        <ul>
          <li>No GitHub account or repository data is connected.</li>
          <li>No Linux credential-store validation has been completed.</li>
          <li>No signed package or upgrade channel is configured.</li>
        </ul>
      </section>
    </main>
  )
}
