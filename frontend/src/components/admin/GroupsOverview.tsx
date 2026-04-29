import { useState, useEffect } from 'preact/hooks'
import { adminApi } from '../../services/AdminApiClient'

interface GroupInfo {
  id: string
  name: string
  about: string | null
  member_count: number
  private: boolean
  closed: boolean
  broadcast: boolean
}

export const GroupsOverview = () => {
  const [groups, setGroups] = useState<GroupInfo[]>([])
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    adminApi.getGroups()
      .then(data => { setGroups(data); setError(null) })
      .catch(e => setError(e.message))
      .finally(() => setLoading(false))
  }, [])

  if (error) {
    return <div class="p-4 rounded bg-red-500/10 text-red-400">{error}</div>
  }

  const badge = (text: string, active: boolean) => (
    <span class={`px-2 py-0.5 rounded text-xs ${active ? 'bg-blue-500/20 text-blue-400' : 'bg-gray-500/20 text-gray-500'}`}>
      {text}
    </span>
  )

  return (
    <div>
      <h2 class="text-xl font-bold mb-4">Groups Overview</h2>

      {loading ? (
        <div style={{ color: 'var(--color-text-secondary)' }}>Loading groups...</div>
      ) : groups.length === 0 ? (
        <div style={{ color: 'var(--color-text-secondary)' }}>No groups yet.</div>
      ) : (
        <div class="rounded-lg overflow-hidden" style={{ border: '1px solid var(--color-border)' }}>
          <table class="w-full">
            <thead>
              <tr style={{ background: 'var(--color-bg-tertiary)' }}>
                <th class="text-left px-4 py-2 text-sm font-medium" style={{ color: 'var(--color-text-secondary)' }}>Name</th>
                <th class="text-left px-4 py-2 text-sm font-medium" style={{ color: 'var(--color-text-secondary)' }}>ID</th>
                <th class="text-center px-4 py-2 text-sm font-medium" style={{ color: 'var(--color-text-secondary)' }}>Members</th>
                <th class="text-left px-4 py-2 text-sm font-medium" style={{ color: 'var(--color-text-secondary)' }}>Type</th>
              </tr>
            </thead>
            <tbody>
              {groups.map(group => (
                <tr key={group.id} style={{ borderTop: '1px solid var(--color-border)' }}>
                  <td class="px-4 py-3">
                    <div class="font-medium">{group.name || '(unnamed)'}</div>
                    {group.about && (
                      <div class="text-xs mt-0.5" style={{ color: 'var(--color-text-secondary)' }}>
                        {group.about.length > 60 ? group.about.slice(0, 60) + '...' : group.about}
                      </div>
                    )}
                  </td>
                  <td class="px-4 py-3 text-sm font-mono" style={{ color: 'var(--color-text-secondary)' }}>
                    {group.id.length > 12 ? group.id.slice(0, 12) + '...' : group.id}
                  </td>
                  <td class="px-4 py-3 text-center text-sm">{group.member_count}</td>
                  <td class="px-4 py-3">
                    <div class="flex gap-1 flex-wrap">
                      {badge(group.private ? 'Private' : 'Public', group.private)}
                      {badge(group.closed ? 'Closed' : 'Open', group.closed)}
                      {group.broadcast && badge('Broadcast', true)}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <div class="mt-4 text-sm" style={{ color: 'var(--color-text-secondary)' }}>
        {groups.length} group{groups.length !== 1 ? 's' : ''}
      </div>
    </div>
  )
}
