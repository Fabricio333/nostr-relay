export class AdminApiClient {
  private baseUrl: string

  constructor(baseUrl: string = '') {
    this.baseUrl = baseUrl
  }

  private getToken(): string | null {
    return sessionStorage.getItem('admin_token')
  }

  private setToken(token: string) {
    sessionStorage.setItem('admin_token', token)
  }

  clearToken() {
    sessionStorage.removeItem('admin_token')
  }

  hasToken(): boolean {
    return this.getToken() !== null
  }

  private async request<T>(path: string, options: RequestInit = {}): Promise<T> {
    const token = this.getToken()
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      ...(options.headers as Record<string, string> || {}),
    }
    if (token) {
      headers['Authorization'] = `Bearer ${token}`
    }

    const res = await fetch(`${this.baseUrl}${path}`, { ...options, headers })

    if (res.status === 401) {
      this.clearToken()
      throw new Error('Session expired')
    }

    if (!res.ok) {
      const body = await res.json().catch(() => ({ error: res.statusText }))
      throw new Error(body.error || `HTTP ${res.status}`)
    }

    if (res.status === 204) return undefined as T
    return res.json()
  }

  async getChallenge(): Promise<{ challenge: string }> {
    return this.request('/api/admin/challenge')
  }

  async authenticate(signedEvent: any): Promise<{ token: string }> {
    const result = await this.request<{ token: string }>('/api/admin/auth', {
      method: 'POST',
      body: JSON.stringify({ signed_event: signedEvent }),
    })
    this.setToken(result.token)
    return result
  }

  async checkSession(): Promise<{ valid: boolean; pubkey?: string }> {
    return this.request('/api/admin/session')
  }

  async getWhitelist(): Promise<Array<{ hex: string; npub: string }>> {
    return this.request('/api/admin/whitelist')
  }

  async addToWhitelist(pubkey: string): Promise<{ hex: string; npub: string }> {
    return this.request('/api/admin/whitelist', {
      method: 'POST',
      body: JSON.stringify({ pubkey }),
    })
  }

  async removeFromWhitelist(hex: string): Promise<void> {
    return this.request(`/api/admin/whitelist/${hex}`, { method: 'DELETE' })
  }

  async getGroups(): Promise<Array<{
    id: string
    name: string
    about: string | null
    member_count: number
    private: boolean
    closed: boolean
    broadcast: boolean
  }>> {
    return this.request('/api/admin/groups')
  }

  async getStats(): Promise<{
    active_connections: number
    total_groups: number
    total_members: number
    whitelisted_count: number
    uptime_seconds: number
  }> {
    return this.request('/api/admin/stats')
  }

  async getReferenceAccounts(): Promise<Array<{ hex: string; npub: string }>> {
    return this.request('/api/admin/reference-accounts')
  }

  async addReferenceAccount(pubkey: string): Promise<{ hex: string; npub: string }> {
    return this.request('/api/admin/reference-accounts', {
      method: 'POST',
      body: JSON.stringify({ pubkey }),
    })
  }

  async removeReferenceAccount(hex: string): Promise<void> {
    return this.request(`/api/admin/reference-accounts/${hex}`, { method: 'DELETE' })
  }

  async syncFollows(): Promise<{ derived_count: number; message: string }> {
    return this.request('/api/admin/reference-accounts/sync', { method: 'POST' })
  }

  async getBlacklist(): Promise<Array<{ hex: string; npub: string }>> {
    return this.request('/api/admin/blacklist')
  }

  async addToBlacklist(pubkey: string): Promise<{ hex: string; npub: string }> {
    return this.request('/api/admin/blacklist', {
      method: 'POST',
      body: JSON.stringify({ pubkey }),
    })
  }

  async removeFromBlacklist(hex: string): Promise<void> {
    return this.request(`/api/admin/blacklist/${hex}`, { method: 'DELETE' })
  }

  async deleteGroup(id: string): Promise<void> {
    return this.request(`/api/admin/groups/${encodeURIComponent(id)}`, { method: 'DELETE' })
  }

  async getGroupEvents(groupId: string, limit?: number, author?: string): Promise<EventInfo[]> {
    const params = new URLSearchParams()
    if (limit) params.set('limit', String(limit))
    if (author) params.set('author', author)
    const q = params.toString() ? `?${params}` : ''
    return this.request(`/api/admin/groups/${encodeURIComponent(groupId)}/events${q}`)
  }

  async getGroupMembers(groupId: string): Promise<MemberInfo[]> {
    return this.request(`/api/admin/groups/${encodeURIComponent(groupId)}/members`)
  }

  async deleteEvent(eventId: string): Promise<void> {
    return this.request(`/api/admin/events/${eventId}`, { method: 'DELETE' })
  }

  async removeGroupMember(groupId: string, pubkey: string): Promise<void> {
    return this.request(
      `/api/admin/groups/${encodeURIComponent(groupId)}/members/${pubkey}`,
      { method: 'DELETE' },
    )
  }

  async deleteUserEvents(pubkey: string): Promise<void> {
    return this.request(`/api/admin/users/${pubkey}/events`, { method: 'DELETE' })
  }
}

export interface EventInfo {
  id: string
  pubkey: string
  kind: number
  content: string
  created_at: number
}

export interface MemberInfo {
  pubkey: string
  roles: string[]
}

export const adminApi = new AdminApiClient()
