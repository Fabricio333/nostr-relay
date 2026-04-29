import { useState, useEffect } from 'preact/hooks'
import { adminApi } from '../../services/AdminApiClient'

interface Stats {
  active_connections: number
  total_groups: number
  total_members: number
  whitelisted_count: number
  uptime_seconds: number
}

const formatUptime = (seconds: number): string => {
  const days = Math.floor(seconds / 86400)
  const hours = Math.floor((seconds % 86400) / 3600)
  const mins = Math.floor((seconds % 3600) / 60)
  if (days > 0) return `${days}d ${hours}h ${mins}m`
  if (hours > 0) return `${hours}h ${mins}m`
  return `${mins}m`
}

export const Dashboard = () => {
  const [stats, setStats] = useState<Stats | null>(null)
  const [error, setError] = useState<string | null>(null)

  const fetchStats = () => {
    adminApi.getStats()
      .then(setStats)
      .catch(e => setError(e.message))
  }

  useEffect(() => {
    fetchStats()
    const interval = setInterval(fetchStats, 30000)
    return () => clearInterval(interval)
  }, [])

  if (error) {
    return <div class="p-4 rounded bg-red-500/10 text-red-400">{error}</div>
  }

  if (!stats) {
    return <div style={{ color: 'var(--color-text-secondary)' }}>Loading stats...</div>
  }

  const cards = [
    { label: 'Active Connections', value: stats.active_connections },
    { label: 'Total Groups', value: stats.total_groups },
    { label: 'Total Members', value: stats.total_members },
    { label: 'Whitelisted Pubkeys', value: stats.whitelisted_count },
    { label: 'Uptime', value: formatUptime(stats.uptime_seconds) },
  ]

  return (
    <div>
      <h2 class="text-xl font-bold mb-4">Dashboard</h2>
      <div class="grid grid-cols-2 md:grid-cols-3 gap-4">
        {cards.map(card => (
          <div key={card.label} class="rounded-lg p-4" style={{ background: 'var(--color-bg-tertiary)', border: '1px solid var(--color-border)' }}>
            <div class="text-2xl font-bold">{card.value}</div>
            <div class="text-sm" style={{ color: 'var(--color-text-secondary)' }}>{card.label}</div>
          </div>
        ))}
      </div>
    </div>
  )
}
