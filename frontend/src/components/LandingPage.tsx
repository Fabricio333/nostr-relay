import { useState, useEffect } from 'preact/hooks'

interface RelayInfo {
  name: string
  description: string
  group_count: number
  supported_nips: number[]
}

export const LandingPage = (_props: { path?: string }) => {
  const [info, setInfo] = useState<RelayInfo | null>(null)
  const [copied, setCopied] = useState(false)
  const [online, setOnline] = useState<boolean | null>(null)

  const wsUrl = `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}`

  useEffect(() => {
    fetch('/api/relay-info')
      .then(r => r.json())
      .then(setInfo)
      .catch(() => {})

    // Check relay online status via WebSocket
    try {
      const ws = new WebSocket(wsUrl)
      ws.onopen = () => { setOnline(true); ws.close() }
      ws.onerror = () => setOnline(false)
      setTimeout(() => ws.close(), 5000)
    } catch {
      setOnline(false)
    }
  }, [])

  const copyUrl = () => {
    navigator.clipboard.writeText(wsUrl).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    })
  }

  return (
    <div class="min-h-screen flex flex-col" style={{ background: 'var(--color-bg-primary)', color: 'var(--color-text-primary)' }}>
      {/* Hero */}
      <div class="flex-1 flex flex-col items-center justify-center px-4 py-16">
        <div class="max-w-2xl w-full text-center">
          <div class="mb-6">
            <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full text-sm" style={{ background: 'var(--color-bg-tertiary)', border: '1px solid var(--color-border)' }}>
              <span class={`w-2 h-2 rounded-full ${online === true ? 'bg-green-400' : online === false ? 'bg-red-400' : 'bg-yellow-400'}`}></span>
              {online === true ? 'Online' : online === false ? 'Offline' : 'Checking...'}
            </div>
          </div>

          <h1 class="text-4xl md:text-5xl font-bold mb-4">
            {info?.name || 'Obelisk Groups Relay'}
          </h1>
          <p class="text-lg mb-8" style={{ color: 'var(--color-text-secondary)' }}>
            {info?.description || 'NIP-29 groups relay for Obelisk. Auth-required, whitelisted access.'}
          </p>

          {/* Stats */}
          <div class="grid grid-cols-2 gap-4 mb-8 max-w-md mx-auto">
            <div class="rounded-lg p-4" style={{ background: 'var(--color-bg-secondary)', border: '1px solid var(--color-border)' }}>
              <div class="text-2xl font-bold">{info?.group_count ?? '—'}</div>
              <div class="text-sm" style={{ color: 'var(--color-text-secondary)' }}>Groups</div>
            </div>
            <div class="rounded-lg p-4" style={{ background: 'var(--color-bg-secondary)', border: '1px solid var(--color-border)' }}>
              <div class="text-2xl font-bold">{info?.supported_nips?.length ?? '—'}</div>
              <div class="text-sm" style={{ color: 'var(--color-text-secondary)' }}>Supported NIPs</div>
            </div>
          </div>

          {/* Connection info */}
          <div class="rounded-lg p-4 mb-8" style={{ background: 'var(--color-bg-secondary)', border: '1px solid var(--color-border)' }}>
            <div class="text-sm mb-2" style={{ color: 'var(--color-text-secondary)' }}>Connect your Nostr client:</div>
            <div class="flex items-center gap-2 justify-center">
              <code class="text-sm px-3 py-2 rounded" style={{ background: 'var(--color-bg-tertiary)' }}>
                {wsUrl}
              </code>
              <button
                onClick={copyUrl}
                class="px-3 py-2 rounded text-sm font-medium transition-colors"
                style={{ background: 'var(--color-accent)', color: '#fff' }}
              >
                {copied ? 'Copied!' : 'Copy'}
              </button>
            </div>
          </div>

          {/* NIPs */}
          {info?.supported_nips && (
            <div class="mb-8">
              <div class="text-sm mb-2" style={{ color: 'var(--color-text-secondary)' }}>Supported NIPs:</div>
              <div class="flex flex-wrap gap-2 justify-center">
                {info.supported_nips.map(nip => (
                  <span key={nip} class="px-2 py-1 rounded text-xs font-mono" style={{ background: 'var(--color-bg-tertiary)', border: '1px solid var(--color-border)' }}>
                    NIP-{nip}
                  </span>
                ))}
              </div>
            </div>
          )}

          {/* CTA */}
          <div class="flex gap-4 justify-center">
            <a
              href="/app"
              class="px-6 py-3 rounded-lg font-medium transition-colors"
              style={{ background: 'var(--color-accent)', color: '#fff' }}
            >
              Open Chat
            </a>
            <a
              href="/admin"
              class="px-6 py-3 rounded-lg font-medium transition-colors"
              style={{ background: 'var(--color-bg-tertiary)', color: 'var(--color-text-primary)', border: '1px solid var(--color-border)' }}
            >
              Admin Panel
            </a>
          </div>
        </div>
      </div>

      {/* Footer */}
      <footer class="py-4 text-center text-sm" style={{ color: 'var(--color-text-secondary)', borderTop: '1px solid var(--color-border)' }}>
        Powered by NIP-29 Group Relay
      </footer>
    </div>
  )
}
