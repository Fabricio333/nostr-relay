import { useState, useEffect } from 'preact/hooks'
import { adminApi } from '../../services/AdminApiClient'

interface WhitelistEntry {
  hex: string
  npub: string
}

export const WhitelistManager = () => {
  const [entries, setEntries] = useState<WhitelistEntry[]>([])
  const [newPubkey, setNewPubkey] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [toast, setToast] = useState<string | null>(null)
  const [confirmRemove, setConfirmRemove] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  const showToast = (msg: string) => {
    setToast(msg)
    setTimeout(() => setToast(null), 3000)
  }

  const fetchWhitelist = () => {
    setLoading(true)
    adminApi.getWhitelist()
      .then(data => { setEntries(data); setError(null) })
      .catch(e => setError(e.message))
      .finally(() => setLoading(false))
  }

  useEffect(fetchWhitelist, [])

  const handleAdd = async () => {
    if (!newPubkey.trim()) return
    setError(null)
    try {
      const entry = await adminApi.addToWhitelist(newPubkey.trim())
      setEntries(prev => [...prev.filter(e => e.hex !== entry.hex), entry])
      setNewPubkey('')
      showToast('Pubkey added to whitelist')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to add')
    }
  }

  const handleRemove = async (hex: string) => {
    setError(null)
    try {
      await adminApi.removeFromWhitelist(hex)
      setEntries(prev => prev.filter(e => e.hex !== hex))
      setConfirmRemove(null)
      showToast('Pubkey removed from whitelist')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to remove')
    }
  }

  const truncate = (s: string) => s.length > 16 ? `${s.slice(0, 8)}...${s.slice(-8)}` : s

  return (
    <div>
      <h2 class="text-xl font-bold mb-4">Whitelist Management</h2>

      {toast && (
        <div class="mb-4 p-3 rounded text-sm bg-green-500/10 text-green-400 border border-green-500/20">
          {toast}
        </div>
      )}

      {error && (
        <div class="mb-4 p-3 rounded text-sm bg-red-500/10 text-red-400 border border-red-500/20">
          {error}
        </div>
      )}

      {/* Add form */}
      <div class="flex gap-2 mb-6">
        <input
          type="text"
          value={newPubkey}
          onInput={(e) => setNewPubkey((e.target as HTMLInputElement).value)}
          placeholder="npub1... or hex pubkey"
          class="flex-1 px-4 py-2 rounded-lg text-sm"
          style={{ background: 'var(--color-bg-tertiary)', color: 'var(--color-text-primary)', border: '1px solid var(--color-border)' }}
          onKeyDown={(e) => e.key === 'Enter' && handleAdd()}
        />
        <button
          onClick={handleAdd}
          disabled={!newPubkey.trim()}
          class="px-4 py-2 rounded-lg text-sm font-medium disabled:opacity-50"
          style={{ background: 'var(--color-accent)', color: '#fff' }}
        >
          Add
        </button>
      </div>

      {/* Table */}
      {loading ? (
        <div style={{ color: 'var(--color-text-secondary)' }}>Loading...</div>
      ) : entries.length === 0 ? (
        <div style={{ color: 'var(--color-text-secondary)' }}>No whitelisted pubkeys. The relay is open to all.</div>
      ) : (
        <div class="rounded-lg overflow-hidden" style={{ border: '1px solid var(--color-border)' }}>
          <table class="w-full">
            <thead>
              <tr style={{ background: 'var(--color-bg-tertiary)' }}>
                <th class="text-left px-4 py-2 text-sm font-medium" style={{ color: 'var(--color-text-secondary)' }}>Hex</th>
                <th class="text-left px-4 py-2 text-sm font-medium" style={{ color: 'var(--color-text-secondary)' }}>npub</th>
                <th class="text-right px-4 py-2 text-sm font-medium" style={{ color: 'var(--color-text-secondary)' }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {entries.map(entry => (
                <tr key={entry.hex} style={{ borderTop: '1px solid var(--color-border)' }}>
                  <td class="px-4 py-3 text-sm font-mono">{truncate(entry.hex)}</td>
                  <td class="px-4 py-3 text-sm font-mono" style={{ color: 'var(--color-text-secondary)' }}>{truncate(entry.npub)}</td>
                  <td class="px-4 py-3 text-right">
                    {confirmRemove === entry.hex ? (
                      <span class="space-x-2">
                        <button
                          onClick={() => handleRemove(entry.hex)}
                          class="text-sm text-red-400 hover:text-red-300"
                        >
                          Confirm
                        </button>
                        <button
                          onClick={() => setConfirmRemove(null)}
                          class="text-sm" style={{ color: 'var(--color-text-secondary)' }}
                        >
                          Cancel
                        </button>
                      </span>
                    ) : (
                      <button
                        onClick={() => setConfirmRemove(entry.hex)}
                        class="text-sm text-red-400 hover:text-red-300"
                      >
                        Remove
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <div class="mt-4 text-sm" style={{ color: 'var(--color-text-secondary)' }}>
        {entries.length} whitelisted pubkey{entries.length !== 1 ? 's' : ''}
      </div>
    </div>
  )
}
