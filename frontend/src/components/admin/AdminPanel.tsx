import { useState, useEffect } from 'preact/hooks'
import { adminApi } from '../../services/AdminApiClient'
import { AdminAuth } from './AdminAuth'
import { Dashboard } from './Dashboard'
import { WhitelistManager } from './WhitelistManager'
import { GroupsOverview } from './GroupsOverview'

type Tab = 'dashboard' | 'whitelist' | 'groups'

export const AdminPanel = (_props: { path?: string }) => {
  const [authenticated, setAuthenticated] = useState(false)
  const [checking, setChecking] = useState(true)
  const [activeTab, setActiveTab] = useState<Tab>('dashboard')

  useEffect(() => {
    if (!adminApi.hasToken()) {
      setChecking(false)
      return
    }

    adminApi.checkSession()
      .then(res => {
        setAuthenticated(res.valid)
        if (!res.valid) adminApi.clearToken()
      })
      .catch(() => {
        adminApi.clearToken()
        setAuthenticated(false)
      })
      .finally(() => setChecking(false))
  }, [])

  if (checking) {
    return (
      <div class="min-h-screen flex items-center justify-center" style={{ background: 'var(--color-bg-primary)' }}>
        <div style={{ color: 'var(--color-text-secondary)' }}>Checking session...</div>
      </div>
    )
  }

  if (!authenticated) {
    return <AdminAuth onAuthenticated={() => setAuthenticated(true)} />
  }

  const handleLogout = () => {
    adminApi.clearToken()
    setAuthenticated(false)
  }

  const tabs: Array<{ id: Tab; label: string }> = [
    { id: 'dashboard', label: 'Dashboard' },
    { id: 'whitelist', label: 'Whitelist' },
    { id: 'groups', label: 'Groups' },
  ]

  return (
    <div class="min-h-screen flex" style={{ background: 'var(--color-bg-primary)' }}>
      {/* Sidebar */}
      <div class="w-56 flex-shrink-0 flex flex-col" style={{ background: 'var(--color-bg-secondary)', borderRight: '1px solid var(--color-border)' }}>
        <div class="p-4">
          <a href="/" class="text-lg font-bold block">Relay Admin</a>
          <div class="text-xs mt-1" style={{ color: 'var(--color-text-secondary)' }}>Management Panel</div>
        </div>

        <nav class="flex-1 px-2">
          {tabs.map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              class={`w-full text-left px-3 py-2 rounded-lg mb-1 text-sm transition-colors ${activeTab === tab.id ? 'font-medium' : ''}`}
              style={{
                background: activeTab === tab.id ? 'var(--color-bg-tertiary)' : 'transparent',
                color: activeTab === tab.id ? 'var(--color-text-primary)' : 'var(--color-text-secondary)',
              }}
            >
              {tab.label}
            </button>
          ))}
        </nav>

        <div class="p-4" style={{ borderTop: '1px solid var(--color-border)' }}>
          <a href="/app" class="block text-sm mb-2" style={{ color: 'var(--color-text-secondary)' }}>
            Open Chat
          </a>
          <button
            onClick={handleLogout}
            class="text-sm text-red-400 hover:text-red-300"
          >
            Logout
          </button>
        </div>
      </div>

      {/* Content */}
      <div class="flex-1 p-6 overflow-auto">
        {activeTab === 'dashboard' && <Dashboard />}
        {activeTab === 'whitelist' && <WhitelistManager />}
        {activeTab === 'groups' && <GroupsOverview />}
      </div>
    </div>
  )
}
